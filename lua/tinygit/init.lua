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
	interactiveStaging = "stage",
	smartCommit = "commit",
	fixupCommit = "commit",
	amendOnlyMsg = "commit",
	amendNoEdit = "commit",
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
