local M = {}

local u = require("tinygit.shared.utils")

local state = {
	bufnr = -1,
	winid = -1,
	diffHeight = -1,
}
--------------------------------------------------------------------------------

---@param mode "stage-all-and-commit"|"commit"
---@param statsWidth number
---@return string diffStats
---@nodiscard
function M.get(mode, statsWidth)
	---@type fun(args: string[]): string
	local function runGitStatsAndCleanUp(args)
		local cleanedOutput = u
			.syncShellCmd(args)
			:gsub("\n[^\n]*$", "") -- remove summary line (footer)
			:gsub(" | ", " │ ") -- full vertical bars instead of pipes
			:gsub(" Bin ", "    ") -- icon for binaries
			:gsub("\n +", "\n") -- remove leading spaces
		return cleanedOutput
	end

	local gitStatsArgs = { "git", "diff", "--compact-summary", "--stat=" .. statsWidth }

	local diffStats
	if mode == "stage-all-and-commit" then
		u.intentToAddUntrackedFiles() -- include new files in diff stats
		diffStats = runGitStatsAndCleanUp(gitStatsArgs)
	elseif mode == "commit" then
		local notStaged = runGitStatsAndCleanUp(gitStatsArgs)
		table.insert(gitStatsArgs, "--staged")
		local staged = runGitStatsAndCleanUp(gitStatsArgs)
		diffStats = notStaged == "" and staged
			or table.concat({ staged, "", "not staged:", notStaged }, "\n")
	end

	return diffStats
end

function M.diffStatsHighlights()
	vim.fn.matchadd("diffAdded", [[ \zs+\+]]) -- color the plus/minus like in the terminal
	vim.fn.matchadd("diffRemoved", [[-\+\ze\s*$]])

	vim.fn.matchadd("Keyword", [[(new.*)]])
	vim.fn.matchadd("Keyword", [[(gone.*)]])

	vim.fn.matchadd("Function", ".*/") -- directory of a file
	vim.fn.matchadd("WarningMsg", "/") -- path separator

	vim.fn.matchadd("Comment", "│") -- vertical separator

	-- starting with "not staged", color rest of buffer (`\_.` matches any char, inc. \n)
	vim.fn.matchadd("Comment", [[^not staged:\_.*]])
end

--------------------------------------------------------------------------------

---@param mode "stage-all-and-commit"|"commit"
---@param inputWinid number
function M.createWin(mode, inputWinid)
	-- PARAMS
	local inputWin = vim.api.nvim_win_get_config(inputWinid)
	local diffStats = M.get(mode, inputWin.width - 2)
	local diffStatsLines = vim.split(diffStats, "\n")

	-- CREATE WINDOW
	local bufnr = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, diffStatsLines)
	local winid = vim.api.nvim_open_win(bufnr, false, {
		relative = "win",
		win = inputWinid,
		row = inputWin.height + 1,
		col = -1,
		width = inputWin.width,
		height = 1, -- just to initialize, will be updated later
		border = inputWin.border,
		style = "minimal",
		focusable = false,
	})
	state.bufnr = bufnr
	state.winid = winid
	state.diffHeight = #diffStatsLines
	M.adaptWinPosition(inputWin)

	-- SETTINGS
	vim.bo[bufnr].filetype = "tinygit.diffstats"
	vim.wo[winid].winfixbuf = true
	vim.wo[winid].statuscolumn = " " -- = left-padding

	-- HIGHLIGHTS
	vim.wo[winid].winhighlight = "FloatBorder:Comment,Normal:Normal"
	vim.api.nvim_win_call(winid, M.diffStatsHighlights)
end

---@param inputWin vim.api.keyset.win_config
function M.adaptWinPosition(inputWin)
	if not vim.api.nvim_win_is_valid(state.winid) then return end

	local winConf = vim.api.nvim_win_get_config(state.winid)

	local borders = 4 -- 2x this win & 2x input win
	local linesToBottomOfEditor = vim.o.lines - (inputWin.row + inputWin.height + borders)
	winConf.height = math.min(state.diffHeight, linesToBottomOfEditor)
	winConf.row = inputWin.height + 1

	vim.api.nvim_win_set_config(state.winid, winConf)
end

function M.unmount()
	if vim.api.nvim_buf_is_valid(state.bufnr) then vim.cmd.bwipeout(state.bufnr) end
end

--------------------------------------------------------------------------------
return M
