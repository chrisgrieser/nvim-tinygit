local M = {}

local commitAndAmend = require("tinygit.commands.commit-and-amend")
local config = require("tinygit.config")
local github = require("tinygit.commands.github")
local pickaxe = require("tinygit.commands.pickaxe")
local push = require("tinygit.commands.push")
local stash = require("tinygit.commands.stash")

--------------------------------------------------------------------------------

---@param userConfig? pluginConfig
function M.setup(userConfig) config.setupPlugin(userConfig or {}) end

--------------------------------------------------------------------------------

---@param userOpts? { forcePush?: boolean }
function M.amendNoEdit(userOpts) commitAndAmend.amendNoEdit(userOpts or {}) end

---@param userOpts? { forcePush?: boolean }
function M.amendOnlyMsg(userOpts) commitAndAmend.amendOnlyMsg(userOpts or {}) end

---@param userOpts? table
function M.smartCommit(userOpts) commitAndAmend.smartCommit(userOpts or {}) end

---@param userOpts? { selectFromLastXCommits?: number, squashInstead: boolean, autoRebase?: boolean }
function M.fixupCommit(userOpts) commitAndAmend.fixupCommit(userOpts or {}) end

--------------------------------------------------------------------------------

---@param justRepo any -- don't link to file with a specific commit, just link to repo
function M.githubUrl(justRepo) github.githubUrl(justRepo) end

---@param userOpts? table
function M.issuesAndPrs(userOpts) github.issuesAndPrs(userOpts or {}) end
function M.openIssueUnderCursor() github.openIssueUnderCursor() end
function M.createGitHubPr() github.createGitHubPr() end

--------------------------------------------------------------------------------

---@param userOpts { pullBefore?: boolean, force?: boolean, createGitHubPr?: boolean }
function M.push(userOpts) push.push(userOpts or {}, true) end

function M.searchFileHistory() pickaxe.searchFileHistory() end
function M.functionHistory() pickaxe.functionHistory() end

function M.stashPop() stash.stashPop() end
function M.stashPush() stash.stashPush() end

--------------------------------------------------------------------------------
return M
