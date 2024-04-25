local M = {}
local u = require("tinygit.shared.utils")
--------------------------------------------------------------------------------

function M.undoLastCommit()
	if u.notInGitRepo() then return end

	local response = vim.trim(vim.fn.system({ "git", "reset", "--mixed", "HEAD~1" }))
	if u.nonZeroExit(response) then return end

	u.notify(response, "info", "Undo Last Commit")
	vim.cmd.checktime() -- updates the current buffer
	u.updateStatuslineComponents()
end

--------------------------------------------------------------------------------
return M
