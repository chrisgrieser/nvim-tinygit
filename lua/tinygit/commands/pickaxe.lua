local M = {}
local fn = vim.fn
local a = vim.api
local basename = vim.fs.basename

local u = require("tinygit.shared.utils")
local config = require("tinygit.config").config.historySearch
local selectCommit = require("tinygit.shared.select-commit")
--------------------------------------------------------------------------------

---@class (exact) pickaxeState
---@field hashList string[] ordered list of all hashes where the string/function was found
---@field absPath string
---@field query string search query pickaxed for
---@field ft string
---@field unshallowingRunning boolean
local state = {
	hashList = {},
	absPath = "",
	query = "",
	ft = "",
	unshallowingRunning = false,
}

---if `autoUnshallowIfNeeded = true`, will also run `git fetch --unshallow`
---@return boolean -- whether the repo is shallow
local function repoIsShallow()
	if state.unshallowingRunning then return false end
	if not u.inShallowRepo() then return false end

	if config.autoUnshallowIfNeeded then
		u.notify("Auto-Unshallowing repo…", "info", "History Search")
		state.unshallowingRunning = true

		-- run async, to allow user input while waiting for the command
		vim.system({ "git", "fetch", "--unshallow" }, {}, function()
			state.unshallowingRunning = false
			u.notify("Auto-Unshallowing done.", "info", "History Search")
		end)
		return false
	else
		local msg = "Aborting: Repository is shallow.\nRun `git fetch --unshallow`."
		u.notify(msg, "warn", "History Search")
		return true
	end
end

--------------------------------------------------------------------------------

---@param commitIdx number index of the selected commit in the list of commits
---@param type "file"|"function"
local function showDiff(commitIdx, type)
	local ns = a.nvim_create_namespace("tinygit.pickaxe_diff")
	local hashList = state.hashList
	local hash = hashList[commitIdx]
	local query = state.query
	local date = u.syncShellCmd { "git", "log", "--max-count=1", "--format=%cr", hash }
	local shortMsg =
		u.syncShellCmd({ "git", "log", "--max-count=1", "--format=%s", hash }):sub(1, 50)

	-- determine filename in case of renaming
	local filenameInPresent = state.absPath
	local gitroot = u.syncShellCmd { "git", "rev-parse", "--show-toplevel" }
	local logCmd = {
		"git",
		"-C",
		gitroot, -- in case cwd is not the git root
		"log",
		hash .. "^..",
		"--follow",
		"--name-only",
		"--format=", -- suppress commit info
		"--",
		filenameInPresent,
	}
	local nameHistory = u.syncShellCmd(logCmd)
	local nameAtCommit = table.remove(vim.split(nameHistory, "\n"))

	-- get diff
	local diffCmd = { "git", "-C", gitroot }
	if type == "file" then
		diffCmd = vim.list_extend(diffCmd, { "show", "--format=", hash, "--", nameAtCommit })
	elseif type == "function" then
		diffCmd = vim.list_extend(
			diffCmd,
			{ "log", "--format=", "--max-count=1", ("-L:%s:%s"):format(query, nameAtCommit) }
		)
	end
	local diffResult = vim.system(diffCmd):wait()
	if u.nonZeroExit(diffResult) then return end -- GUARD
	local diff = diffResult.stdout or ""

	local diffLines = vim.split(vim.trim(diff), "\n")
	for _ = 1, 4 do -- remove first four lines (irrelevant diff header)
		table.remove(diffLines, 1)
	end

	-- remove diff signs and remember line numbers
	local diffAddLines = {}
	local diffDelLines = {}
	local diffHunkHeaderLines = {}
	for i = 1, #diffLines do
		local line = diffLines[i]
		local lnum = i - 1
		if line:find("^%+") then
			table.insert(diffAddLines, lnum)
		elseif line:find("^%-") then
			table.insert(diffDelLines, lnum)
		elseif line:find("^@@") then
			-- remove preproc info and inject it alter as inline text,
			-- as keeping in the text breaks filetype-highlighting
			local preprocInfo, cleanLine = line:match("^(@@.-@@)(.*)")
			diffLines[i] = cleanLine
			diffHunkHeaderLines[lnum] = preprocInfo
		end
		diffLines[i] = diffLines[i]:sub(2)
	end

	-- create new buf with diff
	local bufnr = a.nvim_create_buf(false, true)
	a.nvim_buf_set_lines(bufnr, 0, -1, false, diffLines)
	a.nvim_buf_set_name(bufnr, hash .. " " .. nameAtCommit)
	a.nvim_set_option_value("modifiable", false, { buf = bufnr })

	-- open new win for the buf
	local footerText = "<[S-]Tab>: prev/next commit  q: close  yh: yank hash"
	if type == "file" then footerText = footerText .. "  n/N: next/prev occurrence" end
	local width = math.min(config.diffPopup.width, 0.99)
	local height = math.min(config.diffPopup.height, 0.99)
	local winnr = a.nvim_open_win(bufnr, true, {
		relative = "win",
		-- center of current win
		width = math.floor(width * a.nvim_win_get_width(0)),
		height = math.floor(height * a.nvim_win_get_height(0)),
		row = math.floor((1 - height) * a.nvim_win_get_height(0) / 2),
		col = math.floor((1 - width) * a.nvim_win_get_width(0) / 2),
		title = (" %s (%s) "):format(shortMsg, date),
		title_pos = "center",
		border = config.diffPopup.border,
		style = "minimal",
		footer = { { " " .. footerText .. " ", "Comment" } },
		zindex = 1, -- below nvim-notify floats
	})

	-- Highlighting
	-- INFO not using `diff` filetype, since that removes filetype-specific highlighting
	a.nvim_set_option_value("filetype", state.ft, { buf = bufnr })

	-- some LSPs attach to the buffer
	vim.diagnostic.enable(false, { buf = bufnr })
	vim.diagnostic.reset(ns, bufnr)

	for _, ln in pairs(diffAddLines) do
		a.nvim_buf_add_highlight(bufnr, ns, "DiffAdd", ln, 0, -1)
	end
	for _, ln in pairs(diffDelLines) do
		a.nvim_buf_add_highlight(bufnr, ns, "DiffDelete", ln, 0, -1)
	end
	for ln, preprocInfo in pairs(diffHunkHeaderLines) do
		a.nvim_buf_add_highlight(bufnr, ns, "DiffText", ln, 0, -1)
		a.nvim_buf_set_extmark(bufnr, ns, ln, 0, {
			virt_text = { { preprocInfo .. " ", "DiffText" } },
			virt_text_pos = "inline",
		})
	end

	-- search for the query
	local ignoreCaseBefore = vim.o.ignorecase
	local smartCaseBefore = vim.o.smartcase
	if query ~= "" and type == "file" then
		-- consistent with git's `--regexp-ignore-case`
		vim.o.ignorecase = true
		vim.o.smartcase = false

		fn.matchadd("Search", query) -- highlight, CAVEAT: is case-sensitive
		vim.fn.setreg("/", query) -- so `n` searches directly
		pcall(vim.cmd.normal, { "n", bang = true }) -- move to first match
		-- (pcall to prevent error when query cannot found, due to non-equivalent
		-- case-sensitivity with git, because of git-regex, or due to file renamings)
	end

	-- keymaps: closing
	local keymap = vim.keymap.set
	local opts = { buffer = bufnr, nowait = true }
	local function closePopup()
		if a.nvim_win_is_valid(winnr) then a.nvim_win_close(winnr, true) end
		if a.nvim_buf_is_valid(bufnr) then a.nvim_buf_delete(bufnr, { force = true }) end
		vim.o.ignorecase = ignoreCaseBefore
		vim.o.smartcase = smartCaseBefore
	end
	keymap("n", "q", closePopup, opts)

	-- also close the popup on leaving buffer, ensures there is not leftover
	-- buffer when user closes popup in a different way, such as `:close`.
	vim.api.nvim_create_autocmd("BufLeave", {
		buffer = bufnr,
		callback = closePopup,
	})

	-- keymaps: next/prev commit
	keymap("n", "<Tab>", function()
		if commitIdx == #hashList then
			u.notify("Already on last commit", "warn")
			return
		end
		closePopup()
		showDiff(commitIdx + 1, type)
	end, opts)
	keymap("n", "<S-Tab>", function()
		if commitIdx == 1 then
			u.notify("Already on first commit", "warn")
			return
		end
		closePopup()
		showDiff(commitIdx - 1, type)
	end, opts)

	-- keymaps: yank hash
	keymap("n", "yh", function()
		vim.fn.setreg("+", hash)
		u.notify("Copied hash: " .. hash)
	end, opts)
end

--------------------------------------------------------------------------------

---Given a list of commits, prompt user to select one
---@param commitList string raw response from `git log`
---@param type "file"|"function"
local function selectFromCommits(commitList, type)
	-- GUARD
	commitList = vim.trim(commitList or "")
	if commitList == "" then
		u.notify(("No commits found where %q was changed."):format(state.query))
		return
	end

	-- INFO due to `git log --name-only`, information on one commit is split across
	-- three lines (1: info, 2: blank, 3: filename). This loop merges them into one.
	-- This only compares basenames, file movements are not accounted
	-- for, however this is for display purposes only, so this is not a problem.
	local commits = {}
	if type == "file" then
		local oneCommitPer3Lines = vim.split(commitList, "\n")
		for i = 1, #oneCommitPer3Lines, 3 do
			local commitLine = oneCommitPer3Lines[i]
			local nameAtCommit = basename(oneCommitPer3Lines[i + 2])
			-- append name at commit only when it is not the same name as in the present
			if basename(state.absPath) ~= nameAtCommit then
				-- tab-separated for consistently with `--format` output
				commitLine = commitLine .. "\t" .. nameAtCommit
			end
			table.insert(commits, commitLine)
		end

	-- CAVEAT `git log -L` does not support `--follow` and `--name-only`, so we
	-- cannot add the name here
	elseif type == "function" then
		commits = vim.split(commitList, "\n")
	end

	-- save state
	state.hashList = vim.tbl_map(function(commitLine)
		local hash = vim.split(commitLine, "\t")[1]
		return hash
	end, commits)

	-- select commit
	local autocmdId = selectCommit.setupAppearance()
	local searchMode = state.query == "" and basename(state.absPath) or state.query
	vim.ui.select(commits, {
		prompt = ('󰊢 Commits that changed "%s"'):format(searchMode),
		format_item = selectCommit.selectorFormatter,
		kind = "tinygit.pickaxeDiff",
	}, function(_, commitIdx)
		a.nvim_del_autocmd(autocmdId)
		if commitIdx then showDiff(commitIdx, type) end
	end)
end

--------------------------------------------------------------------------------

function M.searchFileHistory()
	if u.notInGitRepo() or repoIsShallow() then return end
	state.absPath = a.nvim_buf_get_name(0)
	state.ft = vim.bo.filetype

	vim.ui.input({ prompt = "󰊢 Search File History" }, function(query)
		if not query then return end -- aborted

		-- GUARD loop back when unshallowing is still running
		if state.unshallowingRunning then
			u.notify("Unshallowing still running. Please wait a moment.", "warn", "History Search")
			M.searchFileHistory()
			return
		end

		state.query = query
		-- without argument, search all commits that touched the current file
		local args = query == ""
				and {
					"git",
					"log",
					"--format=" .. selectCommit.gitlogFormat,
					"--follow", -- follow file renamings
					"--name-only", -- add filenames to display renamed files
					"--",
					state.absPath,
				}
			or {
				"git",
				"log",
				"--format=" .. selectCommit.gitlogFormat,
				"--regexp-ignore-case",
				"-G" .. query,
				"--follow", -- follow file renamings
				"--name-only", -- add filenames to display renamed files
				"--",
				state.absPath,
			}
		local result = vim.system(args):wait()
		if u.nonZeroExit(result) then return end
		selectFromCommits(result.stdout, "file")
	end)
end

function M.functionHistory()
	---@param funcname? string -- nil: aborted
	local function selectFromFunctionHistory(funcname)
		if not funcname or funcname == "" then return end

		local result = vim.system({
			-- CAVEAT `git log -L` does not support `--follow` and `--name-only`
			"git",
			"log",
			"--format=" .. selectCommit.gitlogFormat,
			("-L:%s:%s"):format(funcname, state.absPath),
			"--no-patch",
		}):wait()
		if u.nonZeroExit(result) then return end
		selectFromCommits(result.stdout, "function")
	end

	-- GUARD
	if u.notInGitRepo() or repoIsShallow() then return end
	if vim.tbl_contains({ "json", "yaml", "toml", "css" }, vim.bo.ft) then
		u.notify(vim.bo.ft .. " does not have any functions.", "warn")
		return
	end

	state.absPath = a.nvim_buf_get_name(0)
	state.ft = vim.bo.filetype

	-- TODO figure out how to query treesitter for function names, and use
	-- treesitter instead?
	local lspWithSymbolSupport = false
	local clients = vim.lsp.get_clients { bufnr = 0 }
	for _, client in pairs(clients) do
		if client.server_capabilities.documentSymbolProvider then
			lspWithSymbolSupport = true
			break
		end
	end

	if not lspWithSymbolSupport then
		vim.ui.input({ prompt = "󰊢 Search History of Function named:" }, function(funcname)
			if not funcname then return end -- aborted

			-- GUARD loop back when unshallowing is still running
			if state.unshallowingRunning then
				u.notify("Unshallowing still running. Please wait a moment.", "warn", "History Search")
				M.functionHistory()
				return
			end

			state.query = funcname
			selectFromFunctionHistory(funcname)
		end)
		return
	end

	vim.lsp.buf.document_symbol {
		on_list = function(response)
			-- filter by kind "function"/"method", prompt to select a name,
			local funcsObjs = vim.tbl_filter(
				function(item) return item.kind == "Function" or item.kind == "Method" end,
				response.items
			)
			if #funcsObjs == 0 then
				local client = vim.lsp.get_client_by_id(response.context.client_id)
				u.notify(("LSP (%s) could not find any functions."):format(client), "warn")
			end

			local funcNames = vim.tbl_map(function(item)
				if item.kind == "Function" then
					return item.text:gsub("^%[Function%] ", "")
				elseif item.kind == "Method" then
					return item.text:match("%[Method%]%s+([^%(]+)")
				end
			end, funcsObjs)

			-- prompt to select a commit that changed that function/method
			vim.ui.select(
				funcNames,
				{ prompt = "󰊢 Select Function:", kind = "tinygit.functionSelect" },
				function(funcname)
					if not funcname then return end -- aborted

					-- GUARD loop back when unshallowing is still running
					if state.unshallowingRunning then
						u.notify("Unshallowing still running. Please wait.", "warn", "History Search")
						M.searchFileHistory()
						return
					end

					state.query = funcname
					selectFromFunctionHistory(funcname)
				end
			)
		end,
	}
end

--------------------------------------------------------------------------------
return M
