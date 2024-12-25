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

---@param userConfig? Tinygit.Config
function M.setup(userConfig) require("tinygit.config").setupPlugin(userConfig) end

setmetatable(M, {
	__index = function(_, key)
		return function(...)
			local cmdToModuleMap = {
				interactiveStaging = "staging",
				smartCommit = "commit-and-amend",
				fixupCommit = "commit-and-amend",
				amendOnlyMsg = "commit-and-amend",
				amendNoEdit = "commit-and-amend",
				undoLastCommitOrAmend = "undo",
				stashPop = "stash",
				stashPush = "stash",
				push = "push-pull",
				githubUrl = "github",
				issuesAndPrs = "github",
				openIssueUnderCursor = "github",
				createGitHubPr = "github",
				fileHistory = "history",
			}

			-- DEPRECATION (2024-11-28)
			local deprecated = { "searchFileHistory", "functionHistory", "lineHistory" }
			if vim.tbl_contains(deprecated, key) then
				local msg = "`.searchFileHistory`, `.functionHistory`, and `.lineHistory` have been unified to a `.fileHistory` command that adapts behavior depending on the mode called in.\n\n"
					.. "See the readme for further information. "
				vim.notify(msg, vim.log.levels.WARN, { title = "tinygit" })
				return function() end -- prevent function call throwing error
			end

			local module = cmdToModuleMap[key]
			require("tinygit.commands." .. module)[key](...)
		end
	end,
})

--------------------------------------------------------------------------------
return M
