local M = {}
--------------------------------------------------------------------------------

---@class pluginConfig
---@field commitMsg commitConfig
---@field asyncOpConfirmationSound boolean
---@field issueIcons issueIconConfig

---@class issueIconConfig
---@field closedIssue string
---@field openIssue string
---@field openPR string
---@field mergedPR string
---@field closedPR string

---@class commitConfig
---@field maxLen number
---@field mediumLen number
---@field emptyFillIn string
---@field enforceConvCommits enforceConvCommitsConfig

---@class enforceConvCommitsConfig
---@field enabled boolean
---@field keywords string[]

---@class searchFileHistoryConfig 
---@field diffPopupWidth number
---@field diffPopupHeight number

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

		-- disallow commit messages without a conventinal commit keyword
		enforceConvCommits = {
			enabled = true,
			-- stylua: ignore
			keywords = {
				"chore", "build", "test", "fix", "feat", "refactor", "perf",
				"style", "revert", "ci", "docs", "break", "improv",
			},
		},
	},
	asyncOpConfirmationSound = true, -- currently macOS only
	issueIcons = {
		openIssue = "🟢",
		closedIssue = "🟣",
		openPR = "🟩",
		mergedPR = "🟪",
		closedPR = "🟥",
	},
	searchFileHistory = {
		diffPopupWidth = 0.8,
		diffPopupHeight = 0.8,
	} 
}

--------------------------------------------------------------------------------

-- in case user does not call `setup`
M.config = defaultConfig

---@param userConfig pluginConfig
function M.setupPlugin(userConfig) M.config = vim.tbl_deep_extend("force", defaultConfig, userConfig) end

--------------------------------------------------------------------------------
return M
