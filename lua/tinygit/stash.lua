local M = {}
local fn = vim.fn
local u = require("tinygit.utils")

--------------------------------------------------------------------------------

function M.stashPush()
	if u.notInGitRepo() then return end

	local response = fn.system({ "git", "stash", "push" })
		:gsub("\n$", "")
		:gsub("^Saved working directory and index state ", "")
	if u.nonZeroExit(response) then return end
	local stashStat = fn.system({ "git", "stash", "show", "0" }):gsub("\n$", "")

	u.notify(response .. "\n" .. stashStat, "info", "Stash Push")
	vim.cmd.checktime() -- reload this file from disk
end

function M.stashPop()
	if u.notInGitRepo() then return end

	local response = fn.system({ "git", "stash", "pop" }):gsub("\n$", "")
	if u.nonZeroExit(response) then return end

	u.notify(response, "info", "Stash Pop")
	vim.cmd.checktime() -- reload this file from disk
end

--------------------------------------------------------------------------------
return M
