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

			local module
			-- stylua: ignore
			local isGithubCmd = vim.tbl_contains( { "githubUrl", "issuesAndPrs", "openIssueUnderCursor", "createGitHubPr" }, key)
			if isGithubCmd then
				module = "github"
			elseif key == "push" then
				module = "push-pull"
			elseif key == "searchFileHistory" or key == "functionHistory" then
				module = "diffview"
			elseif key == "stashPop" or key == "stashPush" then
				module = "stash"
			elseif key == "diffview" then
				module = "diffview"
			else
				module = "commit-and-amend"
			end
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
