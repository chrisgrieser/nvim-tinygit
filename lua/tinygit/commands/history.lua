local M = {}
local selectCommit = require("tinygit.shared.select-commit")
local u = require("tinygit.shared.utils")
--------------------------------------------------------------------------------

---@class (exact) Tinygit.historyState
---@field absPath string
---@field ft string
---@field type? "stringSearch"|"function"|"line"
---@field unshallowingRunning boolean
---@field query string search query or function name
---@field hashList string[] ordered list of all hashes where the string/function was found
---@field lnum? number only for line history
---@field offset? number only for line history

---@type Tinygit.historyState
local state = {
	hashList = {},
	absPath = "",
	query = "",
	ft = "",
	unshallowingRunning = false,
}

--------------------------------------------------------------------------------

---@param msg string
---@param level? Tinygit.notifyLevel
---@param opts? table
local function notify(msg, level, opts)
	if not opts then opts = {} end
	opts.title = "History"
	u.notify(msg, level, opts)
end

---If `autoUnshallowIfNeeded = true`, will also run `git fetch --unshallow` and
---and also returns `false` then. This is so the caller can check whether the
---function should be aborted. However, if called with callback, will return
---`true`, since the original call can be aborted, as the callback will be
---called once the auto-unshallowing is done.
---@param callback? function called when auto-unshallowing is done
---@return boolean whether the repo is shallow
---@async
local function repoIsShallow(callback)
	if state.unshallowingRunning or not u.inShallowRepo() then return false end

	local autoUnshallow = require("tinygit.config").config.history.autoUnshallowIfNeeded
	if not autoUnshallow then
		local msg = "Aborting: Repository is shallow.\nRun `git fetch --unshallow`."
		notify(msg, "warn")
		return true
	end

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
	if callback then return true end -- original call aborted, callback will be called
	return false
end

---@param hash string
local function restoreFileToCommit(hash)
	local out = vim.system({ "git", "restore", "--source=" .. hash, "--", state.absPath }):wait()
	if u.nonZeroExit(out) then return end
	notify(("Restored file to [%s]"):format(hash))
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
	local config = require("tinygit.config").config.history

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
	if type == "stringSearch" then
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

	-- WINDOW PARAMS
	local relWidth = math.min(config.diffPopup.width, 1)
	local relHeight = math.min(config.diffPopup.height, 1)
	local absWidth = math.floor(relWidth * vim.o.columns)

	-- BUFFER
	local bufnr = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_name(bufnr, hash .. " " .. nameAtCommit)
	setDiffBuffer(bufnr, diffLines, state.ft, absWidth)

	-- TITLE
	local maxMsgLen = absWidth - #date - 3
	commitMsg = commitMsg:sub(1, maxMsgLen)
	local title = (" %s %s "):format(commitMsg, date)

	-- FOOTER
	local hlgroup = { key = "Keyword", desc = "Comment" }
	local footer = {
		{ " ", "FloatBorder" },
		{ "q", hlgroup.key },
		{ " close", hlgroup.desc },
		{ "  ", "FloatBorder" },
		{ "<Tab>/<S-Tab>", hlgroup.key },
		{ " next/prev commit", hlgroup.desc },
		{ "  ", "FloatBorder" },
		{ "yh", hlgroup.key },
		{ " yank hash", hlgroup.desc },
		{ "  ", "FloatBorder" },
		{ "R", hlgroup.key },
		{ " restore to commit", hlgroup.desc },
		{ " ", "FloatBorder" },
	}
	if type == "stringSearch" and query ~= "" then
		vim.list_extend(footer, {
			{ " ", "FloatBorder" },
			{ "n/N", hlgroup.key },
			{ " next/prev occ.", hlgroup.desc },
			{ " ", "FloatBorder" },
		})
	end

	-- CREATE WINDOW
	local historyZindex = 40 -- below nvim-notify, which has 50
	local winnr = vim.api.nvim_open_win(bufnr, true, {
		-- center of the editor
		relative = "editor",
		width = absWidth,
		height = math.floor(relHeight * vim.o.lines),
		row = math.floor((1 - relHeight) * vim.o.lines / 2),
		col = math.floor((1 - relWidth) * vim.o.columns / 2),

		title = title,
		title_pos = "center",
		border = config.diffPopup.border,
		style = "minimal",
		footer = footer,
		zindex = historyZindex,
	})
	vim.wo[winnr].winfixheight = true
	vim.wo[winnr].conceallevel = 0 -- do not hide chars in markdown/json
	require("tinygit.shared.backdrop").new(bufnr, historyZindex)

	-- search for the query
	local ignoreCaseBefore = vim.o.ignorecase
	local smartCaseBefore = vim.o.smartcase
	if query ~= "" and type == "stringSearch" then
		-- consistent with git's `--regexp-ignore-case`
		vim.o.ignorecase = true
		vim.o.smartcase = false

		vim.fn.matchadd("Search", query) -- highlight, CAVEAT: is case-sensitive
		vim.fn.setreg("/", query) -- so `n` searches directly

		-- (pcall to prevent error when query cannot found, due to non-equivalent
		-- case-sensitivity with git, because of git-regex or due to file renamings)
		pcall(vim.cmd.normal, { "n", bang = true }) -- move to first match
	end

	-- KEYMAPS
	local function keymap(lhs, rhs)
		vim.keymap.set({ "n", "x" }, lhs, rhs, { buffer = bufnr, nowait = true })
	end

	-- keymaps: closing
	local function closePopup()
		if vim.api.nvim_win_is_valid(winnr) then vim.api.nvim_win_close(winnr, true) end
		if vim.api.nvim_buf_is_valid(bufnr) then vim.api.nvim_buf_delete(bufnr, { force = true }) end
		vim.o.ignorecase = ignoreCaseBefore
		vim.o.smartcase = smartCaseBefore
	end
	keymap("q", closePopup)

	-- also close the popup on leaving buffer, ensures there is not leftover
	-- buffer when user closes popup in a different way, such as `:close`.
	vim.api.nvim_create_autocmd("BufLeave", {
		buffer = bufnr,
		callback = closePopup,
	})

	-- keymaps: next/prev commit
	keymap("<Tab>", function()
		if commitIdx == #hashList then
			notify("Already on last commit.", "warn")
			return
		end
		closePopup()
		showDiff(commitIdx + 1)
	end)
	keymap("<S-Tab>", function()
		if commitIdx == 1 then
			notify("Already on first commit.", "warn")
			return
		end
		closePopup()
		showDiff(commitIdx - 1)
	end)

	keymap("R", function()
		closePopup()
		restoreFileToCommit(hash)
	end)

	-- keymaps: yank hash
	keymap("yh", function()
		vim.fn.setreg("+", hash)
		notify("Copied hash: " .. hash)
	end)
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
	if state.type == "stringSearch" then
		local oneCommitPer3Lines = vim.split(commitList, "\n")
		for i = 1, #oneCommitPer3Lines, 3 do
			local commitLine = oneCommitPer3Lines[i]
			local nameAtCommit = vim.fs.basename(oneCommitPer3Lines[i + 2])
			-- append name at commit only when it is not the same name as in the present
			if vim.fs.basename(state.absPath) ~= nameAtCommit then
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
	local searchMode = state.query == "" and vim.fs.basename(state.absPath) or state.query
	local icon = require("tinygit.config").config.appearance.mainIcon
	vim.ui.select(commits, {
		prompt = vim.trim(("%s Commits that changed %q"):format(icon, searchMode)),
		format_item = selectCommit.selectorFormatter,
		kind = "tinygit.history",
	}, function(_, commitIdx)
		vim.api.nvim_del_autocmd(autocmdId)
		if commitIdx then showDiff(commitIdx) end
	end)
end

--------------------------------------------------------------------------------

---@param prefill? string only needed when recursively calling this function
local function searchHistoryForString(prefill)
	if repoIsShallow() then return end

	-- prompt for a search query
	local icon = require("tinygit.config").config.appearance.mainIcon
	local prompt = vim.trim(icon .. " Search file history")
	vim.ui.input({ prompt = prompt, default = prefill }, function(query)
		if not query then return end -- aborted

		-- GUARD loop back when unshallowing is still running
		if state.unshallowingRunning then
			notify("Unshallowing still running. Please wait a moment.", "warn")
			searchHistoryForString(query) -- call this function again, preserving current query
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

local function functionHistory()
	-- INFO in case of auto-unshallowing, will abort this call and be called
	-- again once auto-unshallowing is done.
	if repoIsShallow(functionHistory) then return end

	-- get selection
	local startLn, startCol = unpack(vim.api.nvim_buf_get_mark(0, "<"))
	local endLn, endCol = unpack(vim.api.nvim_buf_get_mark(0, ">"))
	local selection = vim.api.nvim_buf_get_text(0, startLn - 1, startCol, endLn - 1, endCol + 1, {})
	local funcname = table.concat(selection, "\n")
	state.query = funcname

	-- select from commits
	-- CAVEAT `git log -L` does not support `--follow` and `--name-only`
	local result = vim.system({
		"git",
		"log",
		"--format=" .. selectCommit.gitlogFormat,
		("-L:%s:%s"):format(funcname, state.absPath),
		"--no-patch",
	}):wait()
	if u.nonZeroExit(result) then return end

	selectFromCommits(result.stdout)
end

local function lineHistory()
	-- INFO in case of auto-unshallowing, will abort this call and be called
	-- again once auto-unshallowing is done.
	if repoIsShallow(lineHistory) then return end

	local lnum, offset
	local startOfVisual = vim.api.nvim_buf_get_mark(0, "<")[1]
	local endOfVisual = vim.api.nvim_buf_get_mark(0, ">")[1]
	lnum = startOfVisual
	offset = endOfVisual - startOfVisual + 1
	local onlyOneLine = endOfVisual == startOfVisual
	state.query = "L" .. startOfVisual .. (onlyOneLine and "" or "-L" .. endOfVisual)

	state.lnum = lnum
	state.offset = offset

	-- CAVEAT `git log -L` does not support `--follow` and `--name-only`
	local result = vim.system({
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

function M.fileHistory()
	if u.notInGitRepo() then return end

	state.absPath = vim.api.nvim_buf_get_name(0)
	state.ft = vim.bo.filetype
	local mode = vim.fn.mode()

	if mode == "n" then
		state.type = "stringSearch"
		searchHistoryForString()
	elseif mode == "v" then
		vim.cmd.normal { "v", bang = true } -- leave visual mode
		state.type = "function"
		functionHistory()
	elseif mode == "V" then
		vim.cmd.normal { "V", bang = true }
		state.type = "line"
		lineHistory()
	else
		notify("Unsupported mode: " .. mode, "warn")
	end
end

--------------------------------------------------------------------------------
return M
