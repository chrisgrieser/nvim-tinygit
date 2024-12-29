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

---@param willStageAllChanges boolean
---@param statsWidth number
---@return string
---@nodiscard
function M.getCommitPreview(willStageAllChanges, statsWidth)
	local gitStatsArgs = { "git", "diff", "--compact-summary", "--stat=" .. statsWidth }
	local footer = "Commit preview"
	local changes
	if willStageAllChanges then
		u.intentToAddUntrackedFiles() -- include new files in diff stats
		footer = "Stage & " .. footer:lower()
		changes = runGitStatsAndCleanUp(gitStatsArgs)
	else
		local notStaged = runGitStatsAndCleanUp(gitStatsArgs)
		table.insert(gitStatsArgs, "--staged")
		local staged = runGitStatsAndCleanUp(gitStatsArgs)
		changes = notStaged == "" and staged
			or table.concat({ staged, "not staged:", notStaged }, "\n")
	end

	return changes
end

--------------------------------------------------------------------------------
return M
