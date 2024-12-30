local M = {}

local u = require("tinygit.shared.utils")

local state = {
	bufnr = -1,
}
--------------------------------------------------------------------------------

---@param args string[]
---@return string cleanedOutput
local function runGitStatsAndCleanUp(args)
	local cleanedOutput = u
		.syncShellCmd(args)
		:gsub("\n[^\n]*$", "") -- remove summary line (footer)
		:gsub(" | ", " │ ") -- full vertical bars instead of pipes
		:gsub(" Bin ", "    ") -- icon for binaries
		:gsub("\n +", "\n") -- remove leading spaces
	return cleanedOutput
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

---@param mode "stage-all-and-commit"|"commit"
---@param statsWidth number
---@return string diffStats
---@nodiscard
function M.get(mode, statsWidth)
	local gitStatsArgs = { "git", "diff", "--compact-summary", "--stat=" .. statsWidth }

	local diffStats
	if mode == "stage-all-and-commit" then
		u.intentToAddUntrackedFiles() -- include new files in diff stats
		diffStats = runGitStatsAndCleanUp(gitStatsArgs)
	elseif mode == "commit" then
		local notStaged = runGitStatsAndCleanUp(gitStatsArgs)
		table.insert(gitStatsArgs, "--staged")
		local staged = runGitStatsAndCleanUp(gitStatsArgs)

		if notStaged == "" then
			diffStats = staged
		else
			local parts = { staged, "", "not staged:", notStaged }
			diffStats = table.concat(parts, "\n")
		end
	end

	return diffStats
end

--------------------------------------------------------------------------------

---@param mode "stage-all-and-commit"|"commit"
---@param inputWin Tinygit.Input.WinConf
function M.createWin(mode, inputWin)
	-- PARAMS
	---@type Tinygit.Input.WinConf
	local preview = {
		height = -1,
		width = inputWin.width,
		row = inputWin.row + inputWin.height + 2,
		col = inputWin.col,
		border = inputWin.border,
	}
	local diffStats = M.get(mode, preview.width - 2)
	local diffStatsLines = vim.split(diffStats, "\n")
	preview.height = #diffStatsLines

	-- CREATE WINDOW
	local bufnr = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, diffStatsLines)
	local winid = vim.api.nvim_open_win(bufnr, true, {
		relative = "editor",
		row = preview.row,
		col = preview.col,
		width = preview.width,
		height = preview.height,
		border = preview.border,
		style = "minimal",
		focusable = false,
	})
	state.bufnr = bufnr

	-- SETTINGS
	vim.bo[bufnr].filetype = "tinygit.diffstats"
	vim.bo[bufnr].modifiable = false
	vim.wo[winid].winfixbuf = true
	vim.wo[winid].statuscolumn = " " -- = left-padding

	-- HIGHLIGHT
	vim.wo.winhighlight = "FloatBorder:Comment"
	vim.api.nvim_win_call(winid, M.diffStatsHighlights)
end

function M.unmount()
	if vim.api.nvim_buf_is_valid(state.bufnr) then vim.cmd.bwipeout(state.bufnr) end
end

--------------------------------------------------------------------------------
return M
