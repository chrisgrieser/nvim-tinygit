local M = {}
--------------------------------------------------------------------------------

---@alias Tinygit.NotifyLevel "info"|"trace"|"debug"|"warn"|"error"

---@param msg string
---@param level? Tinygit.NotifyLevel
---@param opts? table
---@return unknown -- depends on the notification plugin of the user (if any)
function M.notify(msg, level, opts)
	if not level then level = "info" end
	if not opts then opts = {} end

	opts.title = opts.title and "tinygit: " .. opts.title or "tinygit"
	if not opts.icon then opts.icon = require("tinygit.config").config.appearance.mainIcon end

	return vim.notify(vim.trim(msg), vim.log.levels[level:upper()], opts)
end

---checks if command was successful, if not, notifies
---@nodiscard
---@return boolean
---@param result vim.SystemCompleted
function M.nonZeroExit(result)
	local msg = (result.stdout or "") .. (result.stderr or "")
	if result.code ~= 0 then M.notify(msg, "error") end
	return result.code ~= 0
end

---also notifies if not in git repo
---@nodiscard
---@return boolean
function M.notInGitRepo()
	local notInRepo = vim.system({ "git", "rev-parse", "--is-inside-work-tree" }):wait().code ~= 0
	if notInRepo then M.notify("Not in a git repo", "error") end
	return notInRepo
end

---@nodiscard
---@return boolean
function M.inShallowRepo()
	return M.syncShellCmd { "git", "rev-parse", "--is-shallow-repository" } == "true"
end

---@nodiscard
---@param cmd string[]
---@param notrim? any
---@return string stdout
function M.syncShellCmd(cmd, notrim)
	local stdout = vim.system(cmd):wait().stdout or ""
	if notrim then return stdout end
	return vim.trim(stdout)
end

function M.intentToAddUntrackedFiles()
	local gitLsResponse = M.syncShellCmd { "git", "ls-files", "--others", "--exclude-standard" }
	local newFiles = gitLsResponse ~= "" and vim.split(gitLsResponse, "\n") or {}
	for _, file in ipairs(newFiles) do
		vim.system({ "git", "add", "--intent-to-add", "--", file }):wait()
	end
end

---@param longStr string
---@return string shortened
function M.shortenRelativeDate(longStr)
	local shortStr = (longStr:match("%d+ %ai?n?") or "") -- 1 unit char (expect min)
		:gsub("m$", "mo") -- "month" -> "mo" to keep it distinguishable from "min"
		:gsub(" ", "")
		:gsub("%d+s$", "just now") -- secs -> just now
	if shortStr ~= "just now" then shortStr = shortStr .. " ago" end
	return shortStr
end

--------------------------------------------------------------------------------
return M
