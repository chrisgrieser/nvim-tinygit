local version = vim.version()
if version.major == 0 and version.minor < 12 then
	local msg = "nvim-scissors requires at least nvim 0.12.\n"
		.. "The latest commit supporting nvim 0.11 is d108d5c."
	vim.notify(msg, vim.log.levels.WARN)
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
