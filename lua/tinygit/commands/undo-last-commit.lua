local M = {}
local fn = vim.fn
local u = require("tinygit.shared.utils")

--------------------------------------------------------------------------------

function M.undoLastCommit()
	if u.notInGitRepo() then return end

	local response = fn.system({ "git", "reset", "--mixed", "HEAD~1" }):gsub("\n$", "")
	if u.nonZeroExit(response) then return end

	u.notify(response, "info", "Git Undo Last Commit")
	vim.cmd.checktime()
end

--------------------------------------------------------------------------------
return M
