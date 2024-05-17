local M = {}
local u = require("tinygit.shared.utils")
--------------------------------------------------------------------------------

function M.stashPush()
	if u.notInGitRepo() then return end

	local result = vim.system({ "git", "stash", "push" }):wait()
	if u.nonZeroExit(result) then return end
	local infoText = vim.trim(result.stdout):gsub("^Saved working directory and index state ", "")
	local stashStat = vim.system({ "git", "stash", "show", "0" }):wait().stdout or ""

	u.notify(infoText .. "\n" .. stashStat, "info", "Stash Push")
	vim.cmd.checktime() -- reload this file from disk
end

function M.stashPop()
	if u.notInGitRepo() then return end

	local result = vim.system({ "git", "stash", "push" }):wait()
	if u.nonZeroExit(result) then return end
	local infoText = vim.trim(result.stdout)

	u.notify(infoText, "info", "Stash Pop")
	vim.cmd.checktime() -- reload this file from disk
end

--------------------------------------------------------------------------------
return M
