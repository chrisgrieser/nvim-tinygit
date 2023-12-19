local M = {}
--------------------------------------------------------------------------------

---@param userConfig? pluginConfig
function M.setup(userConfig) require("tinygit.config").setupPlugin(userConfig or {}) end

--------------------------------------------------------------------------------

---@param userOpts? { forcePush?: boolean }
function M.amendNoEdit(userOpts) require("tinygit.commit-and-amend").amendNoEdit(userOpts or {}) end

---@param userOpts? { forcePush?: boolean }
function M.amendOnlyMsg(userOpts) require("tinygit.commit-and-amend").amendOnlyMsg(userOpts or {}) end

---If there are staged changes, commit them.
---If there aren't, add all changes (`git add -A`) and then commit.
---@param userOpts? table
function M.smartCommit(userOpts) require("tinygit.commit-and-amend").smartCommit(userOpts or {}) end

---@param userOpts? { selectFromLastXCommits?: number, squashInstead: boolean, autoRebase?: boolean }
function M.fixupCommit(userOpts) require("tinygit.commit-and-amend").fixupCommit(userOpts or {}) end

--------------------------------------------------------------------------------

---opens current buffer in the browser & copies the link to the clipboard
---normal mode: link to file
---visual mode: link to selected lines
---@param justRepo any -- don't link to file with a specific commit, just link to repo
function M.githubUrl(justRepo) require("tinygit.github").githubUrl(justRepo) end

---Choose a GitHub issue/PR from the current repo to open in the browser.
---CAVEAT Due to GitHub API limitations, only the last 100 issues are shown.
---@param userOpts? table
function M.issuesAndPrs(userOpts) require("tinygit.github").issuesAndPrs(userOpts or {}) end

function M.openIssueUnderCursor() require("tinygit.github").openIssueUnderCursor() end

--------------------------------------------------------------------------------

---@param userOpts { pullBefore?: boolean, force?: boolean, createGitHubPr?: boolean }
function M.push(userOpts) require("tinygit.push").push(userOpts or {}, true) end

function M.createGitHubPr() require("tinygit.github").createGitHubPr() end

function M.searchFileHistory() require("tinygit.pickaxe").searchFileHistory() end
function M.functionHistory() require("tinygit.pickaxe").functionHistory() end

function M.stashPop() require("tinygit.stash").stashPop() end
function M.stashPush() require("tinygit.stash").stashPush() end

--------------------------------------------------------------------------------
return M
