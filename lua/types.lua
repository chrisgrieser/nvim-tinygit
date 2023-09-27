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
---@field openReferencesIssues boolean
---@field enforceConvCommits enforceConvCommitsConfig

---@class enforceConvCommitsConfig
---@field enabled boolean
---@field keywords string[]
