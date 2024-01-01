local M = {}
local fn = vim.fn
--------------------------------------------------------------------------------

-- open with the OS-specific shell command
---@param url string
function M.openUrl(url)
	local opener
	if fn.has("macunix") == 1 then
		opener = "open"
	elseif fn.has("linux") == 1 then
		opener = "xdg-open"
	elseif fn.has("win64") == 1 or fn.has("win32") == 1 then
		opener = "start"
	end
	local openCommand = ("%s '%s' >/dev/null 2>&1"):format(opener, url)
	fn.system(openCommand)
end

---send notification
---@param body string
---@param level? "info"|"trace"|"debug"|"warn"|"error"
---@param title? string
function M.notify(body, level, title)
	local titlePrefix = "tinygit"
	if not level then level = "info" end
	local notifyTitle = title and titlePrefix .. ": " .. title or titlePrefix
	vim.notify(vim.trim(body), vim.log.levels[level:upper()], { title = notifyTitle })
end

---checks if last command was successful, if not, notify
---@nodiscard
---@return boolean
---@param errorMsg string
function M.nonZeroExit(errorMsg)
	local exitCode = vim.v.shell_error
	if exitCode ~= 0 then M.notify(vim.trim(errorMsg), "error") end
	return exitCode ~= 0
end

---also notifies if not in git repo
---@nodiscard
---@return boolean
function M.notInGitRepo()
	fn.system { "git", "rev-parse", "--is-inside-work-tree" }
	local notInRepo = M.nonZeroExit("Not in Git Repo.")
	return notInRepo
end

---@return string "user/name" of repo
---@nodiscard
function M.getRepo()
	local allRemotes = fn.system { "git", "remote", "-v" }
	local firstRemote = vim.split(allRemotes, "\n")[1]:match(":.*%."):sub(2, -2)
	return firstRemote
end

--------------------------------------------------------------------------------
return M
