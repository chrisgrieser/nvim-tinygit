local M = {}
local u = require("tinygit.shared.utils")
--------------------------------------------------------------------------------

function M.undoLastCommit()
	if u.notInGitRepo() then return end

	local result = vim.system({ "git", "reset", "--mixed", "HEAD~1" }):wait()
	if u.nonZeroExit(result) then return end
	local infoText = vim.trim(result.stdout)

	u.notify(infoText, "info", "Undo Last Commit")
	vim.cmd.checktime() -- updates the current buffer
	u.updateStatuslineComponents()
end

--------------------------------------------------------------------------------
return M
