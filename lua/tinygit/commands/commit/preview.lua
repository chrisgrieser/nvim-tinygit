local M = {}

local u = require("tinygit.shared.utils")
--------------------------------------------------------------------------------

local function diffStatsHighlights()
	vim.fn.matchadd("diffAdded", [[ \zs+\+]]) -- color the plus/minus like in the terminal
	vim.fn.matchadd("diffRemoved", [[-\+\ze\s*$]])
	vim.fn.matchadd("Keyword", [[(new.*)]])
	vim.fn.matchadd("Keyword", [[(gone.*)]])
	vim.fn.matchadd("Comment", "│") -- vertical separator
	vim.fn.matchadd("Function", ".*/") -- directory of a file
	vim.fn.matchadd("WarningMsg", "/")
end

---@param gitStatsArgs string[]
local function cleanupStatsOutput(gitStatsArgs)
	return u
		.syncShellCmd(gitStatsArgs)
		:gsub("\n[^\n]*$", "") -- remove summary line (footer)
		:gsub(" | ", " │ ") -- pipes to full vertical bars
		:gsub(" Bin ", "    ") -- binary icon
		:gsub("\n +", "\n") -- remove leading spaces
end

---@param willStageAllChanges boolean
---@param statsWidth number
---@return string
---@nodiscard
local function getCommitPreview(willStageAllChanges, statsWidth)
	-- get changes
	local gitStatsCmd = { "git", "diff", "--compact-summary", "--stat=" .. statsWidth }
	local title = "Commit preview"
	local changes
	if willStageAllChanges then
		u.intentToAddUntrackedFiles() -- include new files in diff stats
		title = "Stage & " .. title:lower()
		changes = cleanupStatsOutput(gitStatsCmd)
	else
		local notStaged = cleanupStatsOutput(gitStatsCmd)
		table.insert(gitStatsCmd, "--staged")
		local staged = cleanupStatsOutput(gitStatsCmd)
		changes = notStaged == "" and staged
			or table.concat({ staged, "not staged:", notStaged }, "\n")
	end

	return changes
end

--------------------------------------------------------------------------------
return M
