local M = {}
--------------------------------------------------------------------------------

---send notification
---@param body string
---@param level? "info"|"trace"|"debug"|"warn"|"error"
---@param title? string
---@param extraOpts? { icon?: string, on_open?: function, timeout?: boolean|number, animate?: boolean }
function M.notify(body, level, title, extraOpts)
	local pluginName = "tinygit"
	local notifyTitle = title and pluginName .. ": " .. title or pluginName
	local notifyLevel = level and vim.log.levels[level:upper()] or vim.log.levels.INFO

	local baseOpts = { title = notifyTitle }
	local opts = vim.tbl_extend("force", baseOpts, extraOpts or {})
	vim.notify(vim.trim(body), notifyLevel, opts)
end

---checks if last command was successful, if not, notify
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
	if notInRepo then M.notify("Not in Git Repo", "error") end
	return notInRepo
end

---@return boolean
function M.inShallowRepo()
	return M.syncShellCmd { "git", "rev-parse", "--is-shallow-repository" } == "true"
end

---@nodiscard
---@param cmd string[]
---@return string
function M.syncShellCmd(cmd)
	local stdout = vim.system(cmd):wait().stdout or ""
	return vim.trim(stdout)
end

--------------------------------------------------------------------------------
return M
