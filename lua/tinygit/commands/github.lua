local M = {}
local highlight = require("tinygit.shared.highlights")
local u = require("tinygit.shared.utils")
--------------------------------------------------------------------------------

---@param silent? "silent"
---@return string? "user/name" of repo, without the trailing ".git"
---@nodiscard
function M.getGithubRemote(silent)
	local remotes = vim.system({ "git", "remote", "--verbose" }):wait().stdout or ""
	local githubRemote = remotes:match("github%.com[/:](%S+)")
	if not githubRemote then
		if not silent then
			u.notify("Remote does not appear to be at GitHub: " .. githubRemote, "warn")
		end
		return
	end
	return githubRemote:gsub("%.git$", "")
end

--------------------------------------------------------------------------------

---opens current buffer in the browser & copies the link to the clipboard
---normal mode: link to file
---visual mode: link to selected lines
---@param what? "file"|"repo"|"blame"
function M.githubUrl(what)
	-- GUARD
	if u.notInGitRepo() then return end
	local repo = M.getGithubRemote()
	if not repo then return end -- not on github

	-- just open repo url
	if what == "repo" then
		local url = "https://github.com/" .. repo
		vim.ui.open(url)
		vim.fn.setreg("+", url)
		return
	end

	-- GUARD unpushed commits
	local alreadyPushed = u.syncShellCmd { "git", "branch", "--remote", "--contains", "HEAD" } ~= ""
	if not alreadyPushed then
		u.notify("Cannot open at GitHub, current commit has not been pushed yet.", "warn")
		return
	end

	-- PARAMETERS
	local filepath = vim.api.nvim_buf_get_name(0)
	local gitroot = u.syncShellCmd { "git", "rev-parse", "--show-toplevel" }
	local pathInRepo = filepath:sub(#gitroot + 2)
	local pathInRepoEncoded = pathInRepo:gsub("%s+", "%%20")
	local hash = u.syncShellCmd { "git", "rev-parse", "HEAD" }
	local url = "https://github.com/" .. repo
	local location = ""
	local mode = vim.fn.mode()

	if mode:find("[Vv]") then
		vim.cmd.normal { mode, bang = true } -- leave visual mode, so marks are set
		local startLn = vim.api.nvim_buf_get_mark(0, "<")[1]
		local endLn = vim.api.nvim_buf_get_mark(0, ">")[1]
		if startLn == endLn then -- one-line-selection
			location = "#L" .. startLn
		elseif startLn < endLn then
			location = "#L" .. startLn .. "-L" .. endLn
		else
			location = "#L" .. endLn .. "-L" .. startLn
		end
	end
	local type = what == "blame" and "blame" or "blob"
	url = url .. ("/%s/%s/%s%s"):format(type, hash, pathInRepoEncoded, location)

	vim.ui.open(url)
	vim.fn.setreg("+", url) -- copy to clipboard
end

--------------------------------------------------------------------------------

---CAVEAT Due to GitHub API limitations, only the last 100 issues are shown.
---@param opts? { state?: string, type?: string }
function M.issuesAndPrs(opts)
	-- GUARD
	if u.notInGitRepo() then return end
	local repo = M.getGithubRemote()
	if not repo then return end
	if vim.fn.executable("curl") == 0 then
		u.notify("`curl` cannot be found.", "warn")
		return
	end

	local defaultOpts = { state = "all", type = "all" }
	opts = vim.tbl_deep_extend("force", defaultOpts, opts or {})

	-- DOCS https://docs.github.com/en/free-pro-team@latest/rest/issues/issues?apiVersion=2022-11-28#list-repository-issues
	local baseUrl = ("https://api.github.com/repos/%s/issues"):format(repo)
	local rawJsonUrl = baseUrl .. ("?per_page=100&state=%s&sort=updated"):format(opts.state)
	local rawJSON = vim.system({ "curl", "-sL", rawJsonUrl }):wait().stdout or ""
	local issues = vim.json.decode(rawJSON)
	if not issues then
		u.notify("Failed to fetch issues.", "warn")
		return
	end
	if issues and opts.type ~= "all" then
		issues = vim.tbl_filter(function(issue)
			local isPR = issue.pull_request ~= nil
			local isRightKind = (isPR and opts.type == "pr") or (not isPR and opts.type == "issue")
			return isRightKind
		end, issues)
	end

	if #issues == 0 then
		local state = opts.state == "all" and "" or opts.state .. " "
		local type = opts.type == "all" and "issues or PRs " or opts.type .. "s "
		local msg = ("There are no %s%sfor this repo."):format(state, type)
		u.notify(msg, "warn")
		return
	end

	local type = opts.type == "all" and "Issue/PR" or opts.type
	local mainIcon = require("tinygit.config").config.appearance.mainIcon
	local prompt = vim.trim(("%s Select %s (%s)"):format(mainIcon, type, opts.state))
	local onChoice = function(choice) vim.ui.open(choice.html_url) end
	local stylingFunc = function()
		highlight.commitType()
		highlight.inlineCodeAndIssueNumbers()
		vim.fn.matchadd("DiagnosticError", [[\v[Bb]ug]])
		vim.fn.matchadd("DiagnosticInfo", [[\v[Ff]eature [Rr]equest|FR]])
		vim.fn.matchadd("Comment", [[\vby [A-Za-z0-9-]+\s*$]])
	end
	local function issueListFormatter(issue)
		local icons = require("tinygit.config").config.github.icons
		local icon
		if issue.pull_request then
			if issue.draft then
				icon = icons.draftPR
			elseif issue.state == "open" then
				icon = icons.openPR
			elseif issue.pull_request.merged_at then
				icon = icons.mergedPR
			else
				icon = icons.closedPR
			end
		else
			if issue.state == "open" then
				icon = icons.openIssue
			elseif issue.state_reason == "completed" then
				icon = icons.closedIssue
			elseif issue.state_reason == "not_planned" then
				icon = icons.notPlannedIssue
			end
		end
		return ("%s #%s %s by %s"):format(icon, issue.number, issue.title, issue.user.login)
	end

	require("tinygit.shared.picker").pick(prompt, issues, issueListFormatter, stylingFunc, onChoice)
end

function M.openIssueUnderCursor()
	-- ensure `#` is part of cword
	local prevKeywordSetting = vim.opt_local.iskeyword:get()
	vim.opt_local.iskeyword:append("#")

	local cword = vim.fn.expand("<cword>")
	if not cword:match("^#%d+$") then
		local msg = "Word under cursor is not an issue id of the form `#123`"
		u.notify(msg, "warn", { ft = "markdown" })
		return
	end

	local issue = cword:sub(2) -- remove the `#`
	local repo = M.getGithubRemote()
	if not repo then return end
	local url = ("https://github.com/%s/issues/%s"):format(repo, issue)
	vim.ui.open(url)

	vim.opt_local.iskeyword = prevKeywordSetting
end

function M.createGitHubPr()
	local branchName = u.syncShellCmd { "git", "branch", "--show-current" }
	local repo = M.getGithubRemote()
	if not repo then return end
	local prUrl = ("https://github.com/%s/pull/new/%s"):format(repo, branchName)
	vim.ui.open(prUrl)
end

--------------------------------------------------------------------------------
return M
