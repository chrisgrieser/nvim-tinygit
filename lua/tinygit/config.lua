local M = {}
--------------------------------------------------------------------------------

---@class pluginConfig
---@field commitMsg commitConfig
---@field issueIcons issueIconConfig
---@field historySearch historySearchConfig
---@field push pushConfig
---@field statusline { branchState: branchStateConfig, blame: blameConfig }

---@class issueIconConfig
---@field closedIssue string
---@field openIssue string
---@field openPR string
---@field mergedPR string
---@field closedPR string

---@class commitConfig
---@field maxLen number
---@field mediumLen number
---@field conventionalCommits {enforce: boolean, keywords: string[]}
---@field spellcheck boolean
---@field openReferencedIssue boolean
---@field commitPreview boolean
---@field keepAbortedMsgSecs number

---@class historySearchConfig
---@field diffPopup { width: number, height: number, border: "single"|"double"|"rounded"|"solid"|"none"|"shadow"|string[]}
---@field autoUnshallowIfNeeded boolean

---@class pushConfig
---@field preventPushingFixupOrSquashCommits boolean
---@field confirmationSound boolean

---@class blameConfig
---@field ignoreAuthors string[]
---@field hideAuthorNames string[]
---@field maxMsgLen number
---@field icon string

---@class branchStateConfig

--------------------------------------------------------------------------------

---@type pluginConfig
local defaultConfig = {
	commitMsg = {
		-- Why 50/72 is recommended: https://stackoverflow.com/q/2290016/22114136
		mediumLen = 50,
		maxLen = 72,

		-- Shows diffstats of the changes that are going to be committed.
		-- (requires nvim-notify)
		commitPreview = true,

		conventionalCommits = {
			enforce = false, -- disallow commit messages without a keyword
			-- stylua: ignore
			keywords = {
				"fix", "feat", "chore", "docs", "refactor", "build", "test",
				"perf", "style", "revert", "ci", "break", "improv",
			},
		},

		-- enable vim's builtin spellcheck for the commit message input field.
		-- (configured to ignore capitalization and correctly consider camelCase)
		spellcheck = false,

		-- if commit message references issue/PR, open it in the browser
		openReferencedIssue = false,

		-- how long to remember the state of the message input field when aborting
		keepAbortedMsgSecs = 300,
	},
	push = {
		preventPushingFixupOrSquashCommits = true,
		confirmationSound = true, -- currently macOS only, PRs welcome
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
	statusline = {
		blame = {
			-- Any of these authors and the component is not shown (useful for bots)
			ignoreAuthors = {},

			-- show component, but leave out names (useful for your own name)
			hideAuthorNames = {},

			maxMsgLen = 35,
			icon = "ﰖ ",
		},
		branchState = {}, -- TODO
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
