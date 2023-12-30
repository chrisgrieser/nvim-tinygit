local M = {}
--------------------------------------------------------------------------------

---@class pluginConfig
---@field commitMsg commitConfig
---@field issueIcons issueIconConfig
---@field historySearch historySearchConfig
---@field push pushConfig

---@class issueIconConfig
---@field closedIssue string
---@field openIssue string
---@field openPR string
---@field mergedPR string
---@field closedPR string

---@class commitConfig
---@field maxLen number
---@field mediumLen number
---@field emptyFillIn string|false
---@field conventionalCommits {enforce: boolean, keywords: string[]}
---@field spellcheck boolean
---@field openReferencedIssue boolean

---@class historySearchConfig
---@field diffPopup { width: number, height: number, border: "single"|"double"|"rounded"|"solid"|"none"|"shadow"|string[]}
---@field autoUnshallowIfNeeded boolean

---@class pushConfig
---@field preventPushingFixupOrSquashCommits boolean
---@field confirmationSound boolean

--------------------------------------------------------------------------------

---@type pluginConfig
local defaultConfig = {
	commitMsg = {
		-- Why 50/72 is recommended: https://stackoverflow.com/q/2290016/22114136
		mediumLen = 50,
		maxLen = 72,

		-- When conforming the commit message popup with an empty message, fill in
		-- this message. Set to `false` to disallow empty commit messages.
		emptyFillIn = "chore", ---@type string|false

		conventionalCommits = {
			enforce = false, -- disallow commit messages without a keyword
			-- stylua: ignore
			keywords = { -- also used for the cycle-keywords via <Tab>
				"fix", "feat", "chore", "docs", "refactor", "build", "test",
				"perf", "style", "revert", "ci", "break", "improv",
			},
		},

		-- enable vim's builtin spellcheck for the commit message input field.
		-- (configured to ignore capitalization and correctly consider camelCase)
		spellcheck = false,

		-- if commit message references issue/PR, open it in the browser
		openReferencedIssue = false,
	},
	push = {
		preventPushingFixupOrSquashCommits = true,
		confirmationSound = true, -- currently macOS only
	},
	issueIcons = {
		openIssue = "🟢",
		closedIssue = "🟣",
		openPR = "🟩",
		mergedPR = "🟪",
		closedPR = "🟥",
	},
	historySearch = {
		diffPopup = {
			width = 0.8, -- float, 0 to 1
			height = 0.8,
			border = "single",
		},
		-- if trying to call `git log` on a shallow repository, automatically
		-- unshallow the repo by running `git fetch --unshallow`
		autoUnshallowIfNeeded = false,
	},
}

--------------------------------------------------------------------------------

M.config = defaultConfig -- in case user does not call `setup`

---@param userConfig pluginConfig
function M.setupPlugin(userConfig)
	M.config = vim.tbl_deep_extend("force", defaultConfig, userConfig)
end

--------------------------------------------------------------------------------
return M
