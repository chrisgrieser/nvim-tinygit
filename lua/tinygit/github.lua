local M = {}
local fn = vim.fn
local u = require("tinygit.utils")
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
	local remote = fn.system("git --no-optional-locks remote -v"):gsub(".*:(.-)%.git.*", "%1")
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
---formats the list of issues/PRs for vim.ui.select
---@param issue table
---@return table
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

---Choose a GitHub issue/PR from the current repo to open in the browser.
---CAVEAT Due to GitHub API liminations, only the last 100 issues are shown.
---@param userOpts { state?: string, type?: string }
function M.issuesAndPrs(userOpts)
	if u.notInGitRepo() then return end
	local defaultOpts = { state = "all", type = "all" }
	local opts = vim.tbl_deep_extend("force", defaultOpts, userOpts)

	local repo = u.getRepo()

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

	local title = opts.type == "all" and "Issue/PR" or opts.type
	vim.ui.select(issues, {
		prompt = " Select " .. title,
		kind = "github_issue",
		format_item = function(issue) return issueListFormatter(issue) end,
	}, function(choice)
		if not choice then return end
		u.openUrl(choice.html_url)
	end)
end

--------------------------------------------------------------------------------
return M
