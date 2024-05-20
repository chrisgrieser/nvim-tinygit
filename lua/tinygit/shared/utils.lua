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

	---for some edge cases like pre-commit-hooks that add colored output, it is
	---still necessary to remove the ansi escapes from the output
	body = vim.trim(
		body
			:gsub("%[[%w;]-m", "") -- colors codes like \033[1;34m or \033[0m
			:gsub("%[K", "") -- special keycodes
	)

	local baseOpts = { title = notifyTitle }
	local opts = vim.tbl_extend("force", baseOpts, extraOpts or {})
	vim.notify(body, notifyLevel, opts)
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
	return vim.trim(vim.system({ "git", "rev-parse", "--is-shallow-repository" }):wait().stdout)
		== "true"
end

---@return string? "user/name" of repo, without the trailing ".git"
---@nodiscard
function M.getGithubRemote()
	local remotes = vim.system({ "git", "remote", "--verbose" }):wait().stdout or ""
	local githubRemote = remotes:match("github%.com[/:](%S+)")
	if not githubRemote then
		M.notify("Not a GitHub repo", "error")
		return
	end
	return githubRemote:gsub("%.git$", "")
end

function M.updateStatuslineComponents()
	-- conditions to avoid unnecessarily loading the module(s)
	if package.loaded["tinygit.statusline.blame"] then
		require("tinygit.statusline.blame").refreshBlame()
	end
	if package.loaded["tinygit.statusline.branch-state"] then
		require("tinygit.statusline.branch-state").refreshBranchState()
	end
end

--------------------------------------------------------------------------------
return M
