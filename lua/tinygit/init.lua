local version = vim.version()
if version.major == 0 and version.minor < 10 then
	vim.notify("tinygit requires at least nvim 0.10.", vim.log.levels.WARN)
	return
end
--------------------------------------------------------------------------------
local M = {}

-- PERF do not require the plugin's modules here, since it loads the complete
-- code base on the plugin's initialization.

--------------------------------------------------------------------------------
-- CONFIG
---@param userConfig? pluginConfig
function M.setup(userConfig) require("tinygit.config").setupPlugin(userConfig) end

--------------------------------------------------------------------------------
-- COMMIT
---@param userOpts? { forcePushIfDiverged?: boolean }
function M.amendNoEdit(userOpts) require("tinygit.commands.commit-and-amend").amendNoEdit(userOpts) end

---@param userOpts? { forcePushIfDiverged?: boolean }
function M.amendOnlyMsg(userOpts)
	require("tinygit.commands.commit-and-amend").amendOnlyMsg(userOpts)
end

---@param userOpts? { pushIfClean?: boolean }
function M.smartCommit(userOpts) require("tinygit.commands.commit-and-amend").smartCommit(userOpts) end

---@param userOpts? { selectFromLastXCommits?: number, squashInstead?: boolean, autoRebase?: boolean }
function M.fixupCommit(userOpts) require("tinygit.commands.commit-and-amend").fixupCommit(userOpts) end

--------------------------------------------------------------------------------
-- GITHUB
---@param justRepo any -- don't link to file with a specific commit, just link to repo
function M.githubUrl(justRepo) require("tinygit.commands.github").githubUrl(justRepo) end

---@param userOpts? { state?: string, type?: string }
function M.issuesAndPrs(userOpts) require("tinygit.commands.github").issuesAndPrs(userOpts) end

function M.openIssueUnderCursor() require("tinygit.commands.github").openIssueUnderCursor() end

function M.createGitHubPr() require("tinygit.commands.github").createGitHubPr() end

--------------------------------------------------------------------------------
-- OTHER
---@param userOpts? { pullBefore?: boolean, forceWithLease?: boolean, createGitHubPr?: boolean }
function M.push(userOpts) require("tinygit.commands.push-pull").push(userOpts, true) end

function M.searchFileHistory() require("tinygit.commands.pickaxe").searchFileHistory() end
function M.functionHistory() require("tinygit.commands.pickaxe").functionHistory() end

function M.stashPop() require("tinygit.commands.stash").stashPop() end
function M.stashPush() require("tinygit.commands.stash").stashPush() end

function M.undoLastCommitOrAmend()
	require("tinygit.commands.undo-commit-amend").undoLastCommitOrAmend()
end

--------------------------------------------------------------------------------

local wasNotifiedOnce = false
---@deprecated
function M.undoLastCommit()
	require("tinygit.commands.undo-commit-amend").undoLastCommitOrAmend()
	if not wasNotifiedOnce then
		wasNotifiedOnce = true
		vim.notify(
			"`require('tinygit').undoLastCommit()` is deprecated, use `.undoLastCommitOrAmend()` instead.",
			vim.log.levels.WARN,
			{ title = "tinygit" }
		)
	end
end

--------------------------------------------------------------------------------
return M
