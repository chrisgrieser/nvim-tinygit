local M = {}
local u = require("tinygit.shared.utils")
local updateStatusline = require("tinygit.statusline").updateAllComponents
--------------------------------------------------------------------------------

function M.undoLastCommitOrAmend()
	if u.notInGitRepo() then return end

	-- GUARD last operation was not a commit or amend
	local lastReflogLine = u.syncShellCmd { "git", "reflog", "show", "-1", "HEAD@{0}" }
	local lastChangeType = vim.trim(vim.split(lastReflogLine, ":")[2])
	if not lastChangeType:find("commit") then
		local msg = ("Aborting: Last operation was %q, not a commit or amend."):format(lastChangeType)
		u.notify(msg, "warn", { title = "Undo last commit/amend" })
		return
	end

	local result = vim.system({ "git", "reset", "--mixed", "HEAD@{1}" }):wait()
	if u.nonZeroExit(result) then return end
	local infoText = vim.trim(result.stdout)

	u.notify(infoText, "info", { title = "Undo last commit/amend" })
	vim.cmd.checktime() -- updates the current buffer
	updateStatusline()
end

--------------------------------------------------------------------------------
return M
