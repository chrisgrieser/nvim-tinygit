local M = {}
local fn = vim.fn
local u = require("tinygit.shared.utils")
local config = require("tinygit.config").config
--------------------------------------------------------------------------------

---opens current buffer in the browser & copies the link to the clipboard
---normal mode: link to file
---visual mode: link to selected lines
---@param justRepo any -- don't link to file with a specific commit, just link to repo
function M.githubUrl(justRepo)
	if u.notInGitRepo() then return end

	local filepath = vim.fn.expand("%:p")
	local gitroot = vim.fn.system("git --no-optional-locks rev-parse --show-toplevel")
	local pathInRepo = filepath:sub(#gitroot + 1)
	local pathInRepoEncoded = pathInRepo:gsub("%s+", "%%20")

	local remoteInfo = fn.system("git --no-optional-locks remote --verbose")
	local remote = remoteInfo:match("github%.com[:/]([^%s/]-/[^%s/]+)")
	if not remote then
		u.notify("Remote does not appear to be at GitHub: " .. remoteInfo, "warn")
		return
	end
	remote = remote:gsub("%.git$", "")

	local hash = vim.trim(fn.system("git --no-optional-locks rev-parse HEAD"))
	local branch = vim.trim(fn.system("git --no-optional-locks branch --show-current"))

	local selStart = fn.line("v")
	local selEnd = fn.line(".")
	local isVisualMode = fn.mode():find("[Vv]")
	local isNormalMode = fn.mode() == "n"
	local url = "https://github.com/" .. remote

	if not justRepo and isNormalMode then
		url = url .. ("/blob/%s/%s"):format(branch, pathInRepoEncoded)
	elseif not justRepo and isVisualMode then
		local location
		if selStart == selEnd then -- one-line-selection
			location = "#L" .. tostring(selStart)
		elseif selStart < selEnd then
			location = "#L" .. tostring(selStart) .. "-L" .. tostring(selEnd)
		else
			location = "#L" .. tostring(selEnd) .. "-L" .. tostring(selStart)
		end
		url = url .. ("/blob/%s/%s%s"):format(hash, pathInRepoEncoded, location)
	end

	u.openUrl(url)
	fn.setreg("+", url) -- copy to clipboard
end

--------------------------------------------------------------------------------

---formatter for vim.ui.select
---@param issue table
---@return string
local function issueListFormatter(issue)
	local isPR = issue.pull_request ~= nil
	local merged = isPR and issue.pull_request.merged_at ~= nil

	local icon
	if issue.state == "open" and isPR then
		icon = config.issueIcons.openPR
	elseif issue.state == "closed" and isPR and merged then
		icon = config.issueIcons.mergedPR
	elseif issue.state == "closed" and isPR and not merged then
		icon = config.issueIcons.closedPR
	elseif issue.state == "closed" and not isPR then
		icon = config.issueIcons.closedIssue
	elseif issue.state == "open" and not isPR then
		icon = config.issueIcons.openIssue
	end

	return icon .. " #" .. issue.number .. " " .. issue.title
end

---sets the appearance for TelescopeResults or DressingSelect
---@return number autocmdId
local function issueListAppearance()
	local autocmdId = vim.api.nvim_create_autocmd("FileType", {
		once = true, -- to not affect other selectors
		pattern = { "DressingSelect", "TelescopeResults" }, -- nui also uses `DressingSelect`
		callback = function()
			local ns = vim.api.nvim_create_namespace("tinygit.issueList")
			vim.api.nvim_win_set_hl_ns(0, ns)

			vim.fn.matchadd("tinygit_issueList_bugs", [[\v[Bb]ug]])
			vim.api.nvim_set_hl(ns, "tinygit_issueList_bugs", { link = "DiagnosticError" })

			vim.fn.matchadd("tinygit_issueList_featureRequests", [[\v[Ff]eature [Rr]equest|FR]]) -- codespell-ignore
			vim.api.nvim_set_hl(ns, "tinygit_issueList_featureRequests", { link = "DiagnosticInfo" })

			vim.fn.matchadd("tinygit_issueList_issueNumber", [[#\d\+]])
			vim.api.nvim_set_hl(ns, "tinygit_issueList_issueNumber", { link = "Number" })

			vim.fn.matchadd("tinygit_issueList_mdInlineCode", [[`.\{-}`]]) -- .\{-} = non-greedy quantifier
			vim.api.nvim_set_hl(ns, "tinygit_issueList_mdInlineCode", { link = "@text.literal" })

			-- conventional commit keywords for PRs
			vim.fn.matchadd(
				"tinygit_issueList_conventionalCommit",
				[[\v (feat|fix|test|perf|build|ci|revert|refactor|chore|docs|break|improv|style)(!|(.{-}))?\ze:]]
			)
			vim.api.nvim_set_hl(ns, "tinygit_issueList_conventionalCommit", { link = "Title" })
		end,
	})
	return autocmdId
end

---Choose a GitHub issue/PR from the current repo to open in the browser.
---CAVEAT Due to GitHub API limitations, only the last 100 issues are shown.
---@param userOpts { state?: string, type?: string }
function M.issuesAndPrs(userOpts)
	if u.notInGitRepo() then return end

	local defaultOpts = {
		state = "all",
		type = "all",
	}
	local opts = vim.tbl_deep_extend("force", defaultOpts, userOpts)

	local repo = u.getGithubRemote()
	if not repo then return end

	-- DOCS https://docs.github.com/en/free-pro-team@latest/rest/issues/issues?apiVersion=2022-11-28#list-repository-issues
	local rawJsonUrl = ("https://api.github.com/repos/%s/issues?per_page=100&state=%s&sort=updated"):format(
		repo,
		opts.state
	)
	local rawJSON = fn.system { "curl", "-sL", rawJsonUrl }
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
		u.notify(("There are no %s%sfor this repo."):format(state, type), "warn")
		return
	end

	local type = opts.type == "all" and "Issue/PR" or opts.type
	local autocmdId = issueListAppearance()
	vim.ui.select(issues, {
		prompt = (" Select %s (%s)"):format(type, opts.state),
		kind = "tinygit.githubIssue",
		format_item = function(issue) return issueListFormatter(issue) end,
	}, function(choice)
		vim.api.nvim_del_autocmd(autocmdId)
		if not choice then return end
		u.openUrl(choice.html_url)
	end)
end

function M.openIssueUnderCursor()
	-- ensure `#` is part of cword
	local prevKeywordSetting = vim.opt_local.iskeyword:get()
	vim.opt_local.iskeyword:append("#")

	local cword = vim.fn.expand("<cword>")
	if not cword:match("^#%d+$") then
		u.notify("Word under cursor is not an issue id of the form `#123`", "warn")
		return
	end

	local issue = cword:sub(2) -- remove the `#`
	local repo = u.getGithubRemote()
	if not repo then return end
	local url = ("https://github.com/%s/issues/%s"):format(repo, issue)
	u.openUrl(url)

	vim.opt_local.iskeyword = prevKeywordSetting
end

function M.createGitHubPr()
	local branchName = vim.trim(fn.system("git --no-optional-locks branch --show-current"))
	local repo = u.getGithubRemote()
	if not repo then return end
	local prUrl = ("https://github.com/%s/pull/new/%s"):format(repo, branchName)
	u.openUrl(prUrl)
end

--------------------------------------------------------------------------------
return M
