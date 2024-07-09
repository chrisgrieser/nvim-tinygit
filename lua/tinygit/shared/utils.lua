local M = {}
--------------------------------------------------------------------------------

---send notification
---@param body string
---@param level? "info"|"trace"|"debug"|"warn"|"error"
---@param title? string
---@param extraOpts? { icon?: string, on_open?: function, timeout?: boolean|number, animate?: boolean }
function M.notify(body, level, title, extraOpts)
	local pluginName = "tinygit"
	local notifyTitle = title and pluginName .. ": " .. title or pluginName
	local notifyLevel = level and vim.log.levels[level:upper()] or vim.log.levels.INFO

	local baseOpts = { title = notifyTitle }
	local opts = vim.tbl_extend("force", baseOpts, extraOpts or {})
	return vim.notify(vim.trim(body), notifyLevel, opts)
end

---checks if last command was successful, if not, notify
---@nodiscard
---@return boolean
---@param result vim.SystemCompleted
function M.nonZeroExit(result)
	local msg = (result.stdout or "") .. (result.stderr or "")
	if result.code ~= 0 then M.notify(msg, "error") end
	return result.code ~= 0
end

---also notifies if not in git repo
---@nodiscard
---@return boolean
function M.notInGitRepo()
	local notInRepo = vim.system({ "git", "rev-parse", "--is-inside-work-tree" }):wait().code ~= 0
	if notInRepo then M.notify("Not in Git Repo", "error") end
	return notInRepo
end

---@return boolean
function M.inShallowRepo()
	return M.syncShellCmd { "git", "rev-parse", "--is-shallow-repository" } == "true"
end

---@nodiscard
---@param cmd string[]
---@return string stdout
function M.syncShellCmd(cmd)
	local stdout = vim.system(cmd):wait().stdout or ""
	return vim.trim(stdout)
end

---@return string? ahead
---@return string? behind
function M.getAheadBehind()
	local cwd = vim.uv.cwd()
	if not cwd then return nil, nil end

	local allBranchInfo = vim.system({ "git", "-C", cwd, "branch", "--verbose" }):wait()
	if allBranchInfo.code ~= 0 then return end -- not in git repo

	-- get only line on current branch (starting with `*`)
	local branches = vim.split(allBranchInfo.stdout, "\n")
	local currentBranchInfo
	for _, line in pairs(branches) do
		currentBranchInfo = line:match("^%* .*")
		if currentBranchInfo then break end
	end
	if not currentBranchInfo then return end -- detached HEAD

	local ahead = currentBranchInfo:match("ahead (%d+)")
	local behind = currentBranchInfo:match("behind (%d+)")
	return ahead, behind
end

--------------------------------------------------------------------------------

-- INFO using namespace in here does not work, therefore simply
-- using `matchadd`, since it is restricted to the current window anyway
-- INFO the order the highlights are added matters, later has priority

local function markupHighlights()
	vim.fn.matchadd("Number", [[#\d\+]]) -- issue number
	vim.fn.matchadd("@markup.raw.markdown_inline", [[`.\{-}`]]) -- .\{-} = non-greedy quantifier
end

---@param mode? "only-markup"
function M.commitMsgHighlighting(mode)
	markupHighlights()
	if mode == "only-markup" then return end

	---Event though there is a `gitcommit` treesitter parser, we still need to
	---manually mark conventional commits keywords, the parser assume the keyword to
	---be the first word in the buffer, while we want to highlight it in lists of
	---commits or in buffers where the commit message is placee somewhere else.
	local cc = require("tinygit.config").config.commitMsg.conventionalCommits.keywords
	local ccRegex = [[\v(]] .. table.concat(cc, "|") .. [[)(\(.{-}\))?!?\ze: ]]
	vim.fn.matchadd("Title", ccRegex)

	vim.fn.matchadd("WarningMsg", [[\v(fixup|squash)!]])
end

function M.issueTextHighlighting()
	markupHighlights()
	vim.fn.matchadd("DiagnosticError", [[\v[Bb]ug]])
	vim.fn.matchadd("DiagnosticInfo", [[\v[Ff]eature [Rr]equest|FR]])
	vim.fn.matchadd("Comment", [[\vby \w+\s*$]]) -- `\s*` as nvim-notify sometimes adds padding
end

--------------------------------------------------------------------------------
return M
