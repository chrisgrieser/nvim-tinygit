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

setmetatable(M, {
	__index = function(_, key)
		return function(...)
			if key == "setup" then
				require("tinygit.config").setupPlugin(...)
				return
			end

			local cmdToModuleMap = {
				smartCommit = "commit-and-amend",
				fixupCommit = "commit-and-amend",
				amendOnlyMsg = "commit-and-amend",
				amendNoEdit = "commit-and-amend",
				undoLastCommitOrAmend = "undo",
				diffview = "diffview",
				stashPop = "stash",
				stashPush = "stash",
				push = "push-pull",
				githubUrl = "github",
				issuesAndPrs = "github",
				openIssueUnderCursor = "github",
				createGitHubPr = "github",
				searchFileHistory = "diffview",
				functionHistory = "diffview",
				lineHistory = "diffview",
			}

			local module = cmdToModuleMap[key]
			require("tinygit.commands." .. module)[key](...)
		end
	end,
})

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
