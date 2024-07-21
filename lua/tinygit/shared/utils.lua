local M = {}
--------------------------------------------------------------------------------

---@param body string
---@param level? "info"|"trace"|"debug"|"warn"|"error"
---@param title? string
---@param extraOpts? { on_open?: function, timeout?: boolean|number, animate?: boolean }
function M.notify(body, level, title, extraOpts)
	local pluginName = "tinygit"
	local notifyTitle = title and pluginName .. ": " .. title or pluginName
	local notifyLevel = level and vim.log.levels[level:upper()] or vim.log.levels.INFO

	local baseOpts = { title = notifyTitle }
	local opts = vim.tbl_extend("force", baseOpts, extraOpts or {})
	return vim.notify(vim.trim(body), notifyLevel, opts)
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
	if notInRepo then M.notify("Not in Git Repo", "error") end
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

---@nodiscard
---@return string? ahead
---@return string? behind
function M.getAheadBehind()
	local cwd = vim.uv.cwd()
	if not cwd then return nil, nil end

	local allBranchInfo = vim.system({ "git", "-C", cwd, "branch", "--verbose" }):wait()
	if allBranchInfo.code ~= 0 then return end -- not in git repo

	-- get only line on current branch (starting with `*`)
	local branches = vim.split(allBranchInfo.stdout, "\n")
	local currentBranchInfo
	for _, line in pairs(branches) do
		currentBranchInfo = line:match("^%* .*")
		if currentBranchInfo then break end
	end
	if not currentBranchInfo then return end -- detached HEAD

	local ahead = currentBranchInfo:match("ahead (%d+)")
	local behind = currentBranchInfo:match("behind (%d+)")
	return ahead, behind
end

function M.intentToAddUntrackedFiles()
	local gitLsResponse = M.syncShellCmd { "git", "ls-files", "--others", "--exclude-standard" }
	local newFiles = gitLsResponse ~= "" and vim.split(gitLsResponse, "\n") or {}
	for _, file in ipairs(newFiles) do
		vim.system({ "git", "add", "--intent-to-add", "--", file }):wait()
	end
end

--------------------------------------------------------------------------------
return M
