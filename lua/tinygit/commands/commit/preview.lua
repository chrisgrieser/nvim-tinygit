local M = {}

local u = require("tinygit.shared.utils")

local state = {
	bufnr = -1,
	winid = -1,
	diffHeight = -1,
}
--------------------------------------------------------------------------------

---@param mode "stage-all-and-commit"|"commit"
---@param width number
---@return string[] cleanedOutput
---@return string summary
---@return number stagedLinesCount
---@nodiscard
function M.getDiffStats(mode, width)
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

	local gitStatsArgs = { "git", "diff", "--compact-summary", "--stat=" .. width }

	if mode == "stage-all-and-commit" then
		u.intentToAddUntrackedFiles() -- include new files in diff stats
		local staged, summary = runGitStatsAndCleanUp(gitStatsArgs)
		return staged, summary, #staged
	end

	local notStaged, _ = runGitStatsAndCleanUp(gitStatsArgs)
	local staged, summary = runGitStatsAndCleanUp(vim.list_extend(gitStatsArgs, { "--staged" }))
	local stagedLinesCount = #staged -- save, since `list_extend` mutates
	return vim.list_extend(staged, notStaged), summary, stagedLinesCount
end

---@return string[] logLines
function M.getGitLog()
	local loglines = require("tinygit.config").config.commit.preview.loglines
	local args = { "git", "log", "--max-count=" .. loglines, "--format=%s  %cr" } -- subject, date
	local lines = vim.split(u.syncShellCmd(args), "\n")

	return vim.tbl_map(
		function(line) return line:gsub("%d+ %a+ ago$", u.shortenRelativeDate) end,
		lines
	)
end

---@param bufnr number
---@param stagedLines number
---@param diffstatLines number
local function highlightPreviewWin(bufnr, stagedLines, diffstatLines)
	-- highlight diffstat for STAGED lines
	local hlGroups = require("tinygit.config").config.appearance.hlGroups
	local highlightPatterns = {
		{ hlGroups.addedText, [[ \zs+\+]] }, -- added lines
		{ hlGroups.removedText, "[ +]\\zs-\\+" }, -- removed lines
		{ "Keyword", [[(new.*)]] },
		{ "Keyword", [[(gone.*)]] },
		{ "Function", [[.*\ze/]] }, -- directory of a file
		{ "WarningMsg", "/" }, -- path separator
		{ "Comment", "│" }, -- path separator
	}
	local endToken = "\\%<" .. stagedLines + 1 .. "l" -- limit pattern to range, see :help \%<l
	for _, hl in ipairs(highlightPatterns) do
		local pattern = hl[2] .. endToken
		vim.fn.matchadd(hl[1], pattern)
	end

	-- highlight diffstat for UNSTAGED lines (if any)
	local ns = vim.api.nvim_create_namespace("tinygit.commitPreview")
	vim.hl.range(bufnr, ns, "Comment", { stagedLines, 0 }, { diffstatLines - 1, -1 })

	-- highlight separator line
	vim.hl.range(bufnr, ns, "NonText", { diffstatLines, 0 }, { diffstatLines, -1 })

	-- highlight log lines
	local highlights = require("tinygit.shared.highlights")
	highlights.commitType(stagedLines)
	highlights.inlineCodeAndIssueNumbers()
	vim.fn.matchadd("Comment", [[\d\+\w\{1,3} ago$\|just now]]) -- date at the end via `git log --format="%s (%cr)"`
end

--------------------------------------------------------------------------------

---@param mode "stage-all-and-commit"|"commit"
---@param inputWinid number
function M.createWin(mode, inputWinid)
	local inputWin = vim.api.nvim_win_get_config(inputWinid)
	local textWidth = inputWin.width - 2
	local diffStatLines, summary, stagedLinesCount = M.getDiffStats(mode, textWidth)
	local diffstatLineCount = #diffStatLines -- save, since `list_extend` mutates
	table.insert(diffStatLines, ("─"):rep(textWidth)) -- separator
	local logLines = M.getGitLog()
	local previewLines = vim.list_extend(diffStatLines, logLines)

	-- CREATE WINDOW
	local bufnr = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, previewLines)
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
		footer = #diffStatLines > 1 and " " .. summary .. " " or "",
		footer_pos = "right",
	})
	state.bufnr = bufnr
	state.winid = winid
	state.diffHeight = #previewLines
	M.adaptWinPosition(inputWin)

	vim.bo[bufnr].filetype = "tinygit.diffstats"
	vim.wo[winid].statuscolumn = " " -- = left-padding

	vim.wo[winid].winhighlight = "FloatFooter:Comment,FloatBorder:Comment,Normal:Normal"
	vim.api.nvim_win_call(
		winid,
		function() highlightPreviewWin(bufnr, stagedLinesCount, diffstatLineCount) end
	)
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
