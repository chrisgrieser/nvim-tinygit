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
---@return string[] cleanedOutput
---@return string summary
---@nodiscard
function M.getDiffStats(mode, statsWidth)
	---@type fun(args: string[]): string[], string
	local function runGitStatsAndCleanUp(args)
		local output = vim.split(u.syncShellCmd(args), "\n")

		local summary = table
			.remove(output)
			:gsub("^%s*", "") -- remove indentation
			:gsub(" changed", "")
			:gsub(" insertions?", "")
			:gsub(" deletions?", "")
			:gsub("[()]", "")
			:gsub(",", " ")

		local cleanedOutput = vim.tbl_map(function(line)
			local cleanLine = line
				:gsub(" | ", " │ ") -- full vertical bars instead of pipes
				:gsub(" Bin ", "    ") -- icon for binaries
				:gsub("^%s*", "") -- remove indentation
			return cleanLine
		end, output)

		return cleanedOutput, summary
	end

	local gitStatsArgs = { "git", "diff", "--compact-summary", "--stat=" .. statsWidth }

	if mode == "stage-all-and-commit" then
		u.intentToAddUntrackedFiles() -- include new files in diff stats
		return runGitStatsAndCleanUp(gitStatsArgs)
	end

	local notStaged, _ = runGitStatsAndCleanUp(gitStatsArgs)
	local staged, summary = runGitStatsAndCleanUp(vim.list_extend(gitStatsArgs, { "--staged" }))
	if #notStaged > 0 then notStaged = vim.list_extend({ "", "not staged:" }, notStaged) end
	return vim.list_extend(staged, notStaged), summary
end

function M.diffStatsHighlights()
	local hlGroups = require("tinygit.config").config.appearance.hlGroups
	vim.fn.matchadd(hlGroups.addedText, [[ \zs+\+]]) -- color the plus/minus like in the terminal
	vim.fn.matchadd(hlGroups.removedText, [[-\+\ze\s*$]])

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
	local inputWin = vim.api.nvim_win_get_config(inputWinid)
	local diffStats, summary = M.getDiffStats(mode, inputWin.width - 2)

	-- CREATE WINDOW
	local bufnr = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, diffStats)
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
		footer = #diffStats > 1 and " " .. summary .. " " or "",
		footer_pos = "right",
	})
	state.bufnr = bufnr
	state.winid = winid
	state.diffHeight = #diffStats
	M.adaptWinPosition(inputWin)

	vim.bo[bufnr].filetype = "tinygit.diffstats"
	vim.wo[winid].statuscolumn = " " -- = left-padding

	vim.wo[winid].winhighlight = "FloatFooter:NonText,FloatBorder:Comment,Normal:Normal"
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
