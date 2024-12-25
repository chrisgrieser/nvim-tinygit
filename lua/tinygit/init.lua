local version = vim.version()
if version.major == 0 and version.minor < 10 then
	vim.notify("tinygit requires at least nvim 0.10.", vim.log.levels.WARN)
	return
end
--------------------------------------------------------------------------------
local M = {}

---@param userConfig? Tinygit.Config
function M.setup(userConfig) require("tinygit.config").setup(userConfig) end

M.cmdToModuleMap = {
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

setmetatable(M, {
	__index = function(_, key)
		return function(...)
			local u = require("tinygit.shared.utils")

			-- DEPRECATION (2024-11-28)
			local deprecated = { "searchFileHistory", "functionHistory", "lineHistory" }
			if vim.tbl_contains(deprecated, key) then
				local msg = "`.searchFileHistory`, `.functionHistory`, and `.lineHistory` have been unified to a `.fileHistory` command that adapts behavior depending on the mode called in.\n\n"
					.. "See the readme for further information. "
				u.notify(msg, "warn")
				return function() end -- prevent function call throwing error
			end

			local module = M.cmdToModuleMap[key]
			if not module then
				u.notify(("Unknown command `%s`."):format(key), "warn")
				return function() end -- prevent function call throwing error
			end
			require("tinygit.commands." .. module)[key](...)
		end
	end,
})

--------------------------------------------------------------------------------
return M
