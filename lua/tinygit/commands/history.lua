local M = {}
local fn = vim.fn
local a = vim.api
local basename = vim.fs.basename

local u = require("tinygit.shared.utils")
local config = require("tinygit.config").config.historySearch
local backdrop = require("tinygit.shared.backdrop")
local selectCommit = require("tinygit.shared.select-commit")
--------------------------------------------------------------------------------

---@class (exact) historyState
---@field hashList string[] ordered list of all hashes where the string/function was found
---@field absPath string
---@field query string search query pickaxed for
---@field ft string
---@field unshallowingRunning boolean
---@field lnum? number only for line history
---@field offset? number only for line history
---@field type? "file"|"function"|"line"
local state = {
	hashList = {},
	absPath = "",
	query = "",
	ft = "",
	unshallowingRunning = false,
}

--------------------------------------------------------------------------------

---@param msg string
---@param level? "info"|"trace"|"debug"|"warn"|"error"
---@param extraOpts? { icon?: string, on_open?: function, timeout?: boolean|number, animate?: boolean }
local function notify(msg, level, extraOpts)
	---@diagnostic disable-next-line: param-type-mismatch -- wrong diagnostic
	u.notify(msg, level, "Git History", extraOpts)
end

---If `autoUnshallowIfNeeded = true`, will also run `git fetch --unshallow` and
---and also returns `false` then. This is so the caller can check whether the
---function should be aborted. However, if called with callback, will return
---`true`, since the original call can be aborted, as the callback will be
---called once the auto-unshallowing is done.
---@param callback? function called when auto-unshallowing is done
---@return boolean whether the repo is shallow
local function repoIsShallow(callback)
	if state.unshallowingRunning then return false end
	if not u.inShallowRepo() then return false end

	if config.autoUnshallowIfNeeded then
		notify("Auto-unshallowing: fetching repo history…")
		state.unshallowingRunning = true

		-- run async, to allow user input while waiting for the command
		vim.system(
			{ "git", "fetch", "--unshallow" },
			{},
			vim.schedule_wrap(function(out)
				if u.nonZeroExit(out) then return end
				state.unshallowingRunning = false
				notify("Auto-unshallowing done.")
				if callback then callback() end
			end)
		)
		if callback then return true end -- original call can be aborting, since callback is called
		return false
	else
		local msg = "Aborting: Repository is shallow.\nRun `git fetch --unshallow`."
		notify(msg, "warn")
		return true
	end
end

---@param hash string
local function restoreFileToCommit(hash)
	-- restore
	local out = vim.system({ "git", "restore", "--source=" .. hash, "--", state.absPath }):wait()
	if u.nonZeroExit(out) then return end

	-- notification
	local commitMsg = u.syncShellCmd { "git", "log", "--max-count=1", "--format=%s", hash }
	local restoreText = "Restored file to " .. hash .. ":"
	notify(restoreText .. "\n" .. commitMsg, "info", {
		on_open = function(win)
			local buf = vim.api.nvim_win_get_buf(win)
			vim.api.nvim_buf_call(buf, function()
				u.commitMsgHighlighting()
				vim.fn.matchadd("Comment", restoreText)
			end)
		end,
	})

	-- reload buffer
	vim.cmd.checktime()
end

--------------------------------------------------------------------------------

---@param commitIdx number index of the selected commit in the list of commits
local function showDiff(commitIdx)
	local setDiffBuffer = require("tinygit.shared.diff").setDiffBuffer

	local hashList = state.hashList
	local hash = hashList[commitIdx]
	local query = state.query
	local type = state.type
	local date = u.syncShellCmd { "git", "log", "--max-count=1", "--format=(%cr)", hash }
	local commitMsg = u.syncShellCmd { "git", "log", "--max-count=1", "--format=%s", hash }

	-- DETERMINE FILENAME (in case of renaming)
	local filenameInPresent = state.absPath
	local gitroot = u.syncShellCmd { "git", "rev-parse", "--show-toplevel" }
	local nameHistory = u.syncShellCmd {
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
	local nameAtCommit = table.remove(vim.split(nameHistory, "\n"))

	-- DIFF COMMAND
	local diffCmd = { "git", "-C", gitroot }
	local args = {}
	if type == "file" then
		args = { "show", "--format=", hash, "--", nameAtCommit }
	elseif type == "function" or type == "line" then
		args = { "log", "--format=", "--max-count=1", hash }
		local extra = type == "function" and ("-L:%s:%s"):format(query, nameAtCommit)
			or ("-L%d,+%d:%s"):format(state.lnum, state.offset, nameAtCommit)
		table.insert(args, extra)
	end
	local diffResult = vim.system(vim.list_extend(diffCmd, args)):wait()
	if u.nonZeroExit(diffResult) then return end

	local diff = assert(diffResult.stdout, "No diff output.")
	local diffLines = vim.split(diff, "\n", { trimempty = true })

	-- WINDOW STATS
	local relWidth = math.min(config.diffPopup.width, 1)
	local relHeight = math.min(config.diffPopup.height, 1)
	local vimWidth = vim.o.columns - 2
	local vimHeight = vim.o.lines - 2
	local absWidth = math.floor(relWidth * vimWidth)

	-- BUFFER
	local bufnr = a.nvim_create_buf(false, true)
	a.nvim_buf_set_name(bufnr, hash .. " " .. nameAtCommit)
	vim.bo[bufnr].buftype = "nofile"
	setDiffBuffer(bufnr, diffLines, state.ft, absWidth)

	-- FOOTER & TITLE
	local footer = {
		"q: close",
		"(⇧)↹ : next/prev commit",
		"yh: yank hash",
		"R: restore to commit",
	}
	if query ~= "" and type == "file" then table.insert(footer, "n/N: next/prev occ.") end
	local footerText = table.concat(footer, "  ")

	local maxMsgLen = absWidth - #date - 3
	commitMsg = commitMsg:sub(1, maxMsgLen)
	local title = (" %s %s "):format(commitMsg, date)

	-- CREATE WINDOW
	local historyZindex = 40 -- below nvim-notify, which has 50
	local winnr = a.nvim_open_win(bufnr, true, {
		-- center of the editor
		relative = "editor",
		width = absWidth,
		height = math.floor(relHeight * vimHeight),
		row = math.ceil((1 - relHeight) * vimHeight / 2),
		col = math.floor((1 - relWidth) * vimWidth / 2),

		title = title,
		title_pos = "center",
		border = config.diffPopup.border,
		style = "minimal",
		footer = { { " " .. footerText .. " ", "FloatBorder" } },
		zindex = historyZindex,
	})
	vim.wo[winnr].winfixheight = true
	backdrop.new(bufnr, historyZindex)

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

	-- KEYMAPS
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
			notify("Already on last commit.", "warn")
			return
		end
		closePopup()
		showDiff(commitIdx + 1)
	end, opts)
	keymap("n", "<S-Tab>", function()
		if commitIdx == 1 then
			notify("Already on first commit.", "warn")
			return
		end
		closePopup()
		showDiff(commitIdx - 1)
	end, opts)

	keymap("n", "R", function()
		closePopup()
		restoreFileToCommit(hash)
	end, opts)

	-- keymaps: yank hash
	keymap("n", "yh", function()
		vim.fn.setreg("+", hash)
		notify("Copied hash: " .. hash)
	end, opts)
end

---Given a list of commits, prompt user to select one
---@param commitList string raw response from `git log`
local function selectFromCommits(commitList)
	-- GUARD
	commitList = vim.trim(commitList or "")
	if commitList == "" then
		notify(("No commits found where %q was changed."):format(state.query), "warn")
		return
	end

	-- INFO due to `git log --name-only`, information on one commit is split across
	-- three lines (1: info, 2: blank, 3: filename). This loop merges them into one.
	-- This only compares basenames, file movements are not accounted
	-- for, however this is for display purposes only, so this is not a problem.
	local commits = {}
	if state.type == "file" then
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
	elseif state.type == "function" or state.type == "line" then
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
		kind = "tinygit.history",
	}, function(_, commitIdx)
		a.nvim_del_autocmd(autocmdId)
		if commitIdx then showDiff(commitIdx) end
	end)
end

--------------------------------------------------------------------------------

function M.searchFileHistory()
	if u.notInGitRepo() or repoIsShallow() then return end
	state.absPath = a.nvim_buf_get_name(0)
	state.ft = vim.bo.filetype
	state.type = "file"

	vim.api.nvim_create_autocmd("FileType", {
		once = true,
		pattern = "DressingInput",
		callback = function(ctx)
			backdrop.new(ctx.buf)
			local winid = vim.api.nvim_get_current_win()
			local footerText = "empty = all commits"
			vim.api.nvim_win_set_config(winid, {
				footer = { { " " .. footerText .. " ", "FloatBorder" } },
				footer_pos = "right",
			})
		end,
	})

	vim.ui.input({ prompt = "󰊢 Search File History" }, function(query)
		if not query then return end -- aborted

		-- GUARD loop back when unshallowing is still running
		if state.unshallowingRunning then
			notify("Unshallowing still running. Please wait a moment.", "warn")
			M.searchFileHistory()
			return
		end

		state.query = query
		-- without argument, search all commits that touched the current file
		local args = {
			"git",
			"log",
			"--format=" .. selectCommit.gitlogFormat,
			"--follow", -- follow file renamings
			"--name-only", -- add filenames to display renamed files
			"--",
			state.absPath,
		}
		if query ~= "" then
			local posBeforeDashDash = #args - 2
			table.insert(args, posBeforeDashDash, "--regexp-ignore-case")
			table.insert(args, posBeforeDashDash, "-G" .. query)
		end
		local result = vim.system(args):wait()
		if u.nonZeroExit(result) then return end
		selectFromCommits(result.stdout)
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
		selectFromCommits(result.stdout)
	end

	-- GUARD
	if u.notInGitRepo() or repoIsShallow() then return end
	if vim.tbl_contains({ "json", "yaml", "toml", "css" }, vim.bo.ft) then
		notify(vim.bo.ft .. " does not have any functions.", "warn")
		return
	end

	state.absPath = a.nvim_buf_get_name(0)
	state.ft = vim.bo.filetype
	state.type = "function"

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
				notify("Unshallowing still running. Please wait a moment.", "warn")
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
				notify(("LSP (%s) could not find any functions."):format(client), "warn")
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
						notify("Unshallowing still running. Please wait a moment.", "warn")
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

function M.lineHistory()
	if u.notInGitRepo() then return end

	-- GUARD in case of auto-unshallowing, will recursively call itself once done
	-- As opposed to function and file history, no further input is needed by the
	-- user, so that we have to abort here, and do a callback to this function
	-- once the auto-unshallowing is done.
	if repoIsShallow(M.lineHistory) then return end

	local lnum, offset
	local mode = vim.fn.mode()
	if mode == "n" then
		lnum = vim.api.nvim_win_get_cursor(0)[1]
		offset = 1
		state.query = "Line " .. lnum
	elseif mode:find("[Vv]") then
		vim.cmd.normal { mode, bang = true } -- leave visual mode so marks are set
		local startOfVisual = vim.api.nvim_buf_get_mark(0, "<")[1]
		local endOfVisual = vim.api.nvim_buf_get_mark(0, ">")[1]
		lnum = startOfVisual
		offset = endOfVisual - startOfVisual + 1
		local onlyOneLine = endOfVisual == startOfVisual
		state.query = "L" .. startOfVisual .. (onlyOneLine and "" or "-L" .. endOfVisual)
	end

	state.absPath = a.nvim_buf_get_name(0)
	state.ft = vim.bo.filetype
	state.lnum = lnum
	state.offset = offset
	state.type = "line"

	local result = vim.system({
		-- CAVEAT `git log -L` does not support `--follow` and `--name-only`
		"git",
		"log",
		"--format=" .. selectCommit.gitlogFormat,
		("-L%d,+%d:%s"):format(lnum, offset, state.absPath),
		"--no-patch",
	}):wait()
	if u.nonZeroExit(result) then return end

	selectFromCommits(result.stdout)
end

--------------------------------------------------------------------------------
return M
