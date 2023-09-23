local M = {}
local fn = vim.fn

--------------------------------------------------------------------------------

local defaultConfig = {
	commitMsg = {
		-- Why 50/72 is recommended: https://stackoverflow.com/q/2290016/22114136
		maxLen = 72,
		mediumLen = 50,

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
		closedIssue = "🟣",
		openIssue = "🟢",
		openPR = "🟦",
		mergedPR = "🟨",
		closedPR = "🟥",
	},
}

-- set values if setup call is not run
local config = defaultConfig

function M.setup(userConf) config = vim.tbl_extend("force", defaultConfig, userConf) end

--------------------------------------------------------------------------------
-- HELPERS

-- open with the OS-specific shell command
---@param url string
local function openUrl(url)
	local opener
	if fn.has("macunix") == 1 then
		opener = "open"
	elseif fn.has("linux") == 1 then
		opener = "xdg-open"
	elseif fn.has("win64") == 1 or fn.has("win32") == 1 then
		opener = "start"
	end
	local openCommand = ("%s '%s' >/dev/null 2>&1"):format(opener, url)
	fn.system(openCommand)
end

---send notification
---@param body string
---@param level? "info"|"trace"|"debug"|"warn"|"error"
---@param title? string
local function notify(body, level, title)
	local titlePrefix = "tinygit"
	if not level then level = "info" end
	local notifyTitle = title and titlePrefix .. ": " .. title or title
	vim.notify(vim.trim(body), vim.log.levels[level:upper()], { title = notifyTitle })
end

---checks if last command was successful, if not, notify
---@nodiscard
---@return boolean
---@param errorMsg string
local function nonZeroExit(errorMsg)
	local exitCode = vim.v.shell_error
	if exitCode ~= 0 then notify(vim.trim(errorMsg), "warn") end
	return exitCode ~= 0
end

---@nodiscard
---@return boolean
local function hasStagedChanges()
	fn.system("git diff --staged --quiet")
	local hasStaged = vim.v.shell_error ~= 0
	return hasStaged
end

---also notifies if not in git repo
---@nodiscard
---@return boolean
local function notInGitRepo()
	fn.system("git rev-parse --is-inside-work-tree")
	local notInRepo = nonZeroExit("Not in Git Repo.")
	return notInRepo
end

---CAVEAT currently only on macOS
---@param soundFilepath string
local function confirmationSound(soundFilepath)
	local onMacOs = fn.has("macunix") == 1
	if not onMacOs or not config.asyncOpConfirmationSound then return end
	fn.system(("afplay %q &"):format(soundFilepath))
end

---process a commit message: length, not empty, adheres to conventional commits
---@param commitMsg string
---@nodiscard
---@return boolean is the commit message valid?
---@return string the (modified) commit message
local function processCommitMsg(commitMsg)
	commitMsg = vim.trim(commitMsg)
	local conf = config.commitMsg

	if #commitMsg > conf.maxLen then
		notify("Commit Message too long.", "warn")
		local shortenedMsg = commitMsg:sub(1, conf.maxLen)
		return false, shortenedMsg
	elseif commitMsg == "" then
		if not conf.emptyFillIn then
			notify("Commit Message empty.", "warn")
			return false, ""
		else
			---@diagnostic disable-next-line: return-type-mismatch -- checked above
			return true, conf.emptyFillIn
		end
	end

	if conf.enforceConvCommits.enabled then
		-- stylua: ignore
		local firstWord = commitMsg:match("^%w+")
		if not vim.tbl_contains(conf.enforceConvCommits.keywords, firstWord) then
			notify("Not using a Conventional Commits keyword.", "warn")
			return false, commitMsg
		end
	end

	-- message ok
	return true, commitMsg
end

-- Uses ColorColumn to indicate max length of commit messages, and
-- additionally colors commit messages that are too long in red.
local function setGitCommitAppearance()
	vim.api.nvim_create_autocmd("FileType", {
		pattern = "DressingInput",
		once = true, -- do not affect other DressingInputs
		callback = function()
			local conf = config.commitMsg
			local winNs = 1

			vim.api.nvim_win_set_hl_ns(0, winNs)

			-- custom highlighting
			fn.matchadd("overLength", ([[.\{%s}\zs.*\ze]]):format(conf.maxLen - 1))
			fn.matchadd(
				"closeToOverlengh",
				-- \ze = end of match, \zs = start of match
				([[.\{%s}\zs.\{1,%s}\ze]]):format(conf.mediumLen - 1, conf.maxLen - conf.mediumLen)
			)
			fn.matchadd("issueNumber", [[#\d\+]])
			vim.api.nvim_set_hl(winNs, "overLength", { link = "ErrorMsg" })
			vim.api.nvim_set_hl(winNs, "closeToOverlengh", { link = "WarningMsg" })
			vim.api.nvim_set_hl(winNs, "issueNumber", { link = "Number" })

			-- colorcolumn as extra indicators of overLength
			vim.opt_local.colorcolumn = { conf.mediumLen, conf.maxLen }

			-- treesitter highlighting
			vim.bo.filetype = "gitcommit"
			vim.api.nvim_set_hl(winNs, "Title", { link = "Normal" })

			-- fix confirming input field (not working in insert mode due to filetype change)
			vim.keymap.set("i", "<CR>", "<Esc><CR>", { buffer = true, remap = true })

			-- activate styling of statusline plugins
			vim.api.nvim_buf_set_name(0, "COMMIT_EDITMSG") 
		end,
	})
end

--------------------------------------------------------------------------------

---@param opts? { forcePush?: boolean }
function M.amendNoEdit(opts)
	if not opts then opts = {} end
	vim.cmd("silent update")
	if notInGitRepo() then return end

	-- show the message of the last commit
	local lastCommitMsg = vim.trim(fn.system("git log -1 --pretty=%B"))

	if not hasStagedChanges() then
		local stderr = fn.system { "git", "add", "-A" }
		if nonZeroExit(stderr) then return end
	end

	local stderr = fn.system { "git", "commit", "--amend", "--no-edit" }
	if nonZeroExit(stderr) then return end

	local body = ('"%s"'):format(lastCommitMsg)
	if opts.forcePush then body = body .. "\n➤ Force Pushing…" end
	notify(body, "info", "Amend-No-edit")

	if opts.forcePush then M.push { force = true } end
end

---@param opts? { forcePush?: boolean }
---@param prefillMsg? string
function M.amendOnlyMsg(opts, prefillMsg)
	if not opts then opts = {} end
	vim.cmd("silent update")
	if notInGitRepo() then return end

	if not prefillMsg then
		local lastCommitMsg = vim.trim(fn.system("git log -1 --pretty=%B"))
		prefillMsg = lastCommitMsg
	end
	setGitCommitAppearance()

	vim.ui.input({ prompt = "󰊢 Amend Message", default = prefillMsg }, function(commitMsg)
		if not commitMsg then return end -- aborted input modal
		local validMsg, newMsg = processCommitMsg(commitMsg)
		if not validMsg then -- if msg invalid, run again to fix the msg
			M.amendOnlyMsg(opts, newMsg)
			return
		end

		local stderr = fn.system { "git", "commit", "--amend", "-m", newMsg }
		if nonZeroExit(stderr) then return end

		local body = ('"%s"'):format(newMsg)
		if opts.forcePush then body = body .. "\n➤ Force Pushing…" end
		notify(body, "info", "Amend-Only-Msg")

		if opts.forcePush then M.push { force = true } end
	end)
end

--------------------------------------------------------------------------------

---If there are staged changes, commit them.
---If there aren't, add all changes (`git add -A`) and then commit.
---@param prefillMsg? string
---@param opts? { push?: boolean }
function M.smartCommit(opts, prefillMsg)
	if notInGitRepo() then return end

	vim.cmd("silent update")
	if not opts then opts = {} end
	if not prefillMsg then prefillMsg = "" end

	setGitCommitAppearance()
	vim.ui.input({ prompt = "󰊢 Commit Message", default = prefillMsg }, function(commitMsg)
		if not commitMsg then return end -- aborted input modal
		local validMsg, newMsg = processCommitMsg(commitMsg)
		if not validMsg then -- if msg invalid, run again to fix the msg
			M.smartCommit(opts, newMsg)
			return
		end

		if not hasStagedChanges() then
			local stderr = fn.system { "git", "add", "-A" }
			if nonZeroExit(stderr) then return end
		end

		local stderr = fn.system { "git", "commit", "-m", newMsg }
		if nonZeroExit(stderr) then return end

		local body = ('"%s"'):format(newMsg)
		if opts.push then body = body .. "\n➤ Pushing…" end
		notify(body, "info", "Smart-Commit")

		if opts.push then M.push { pullBefore = true } end
	end)
end

-- pull before to avoid conflicts
---@param opts? { pullBefore?: boolean, force?: boolean }
function M.push(opts)
	if not opts then opts = {} end
	local shellCmd = opts.pullBefore and "git pull ; git push" or "git push"
	if opts.force then shellCmd = shellCmd .. " --force" end
	fn.jobstart(shellCmd, {
		stdout_buffered = true,
		stderr_buffered = true,
		detach = true, -- finish even when quitting nvim
		on_stdout = function(_, data)
			if data[1] == "" and #data == 1 then return end
			local output = vim.trim(table.concat(data, "\n"))

			-- no need to notify that the pull in `git pull ; git push` yielded no update
			if output:find("Current branch .* is up to date") then return end

			notify(output, "info", "Push")
			confirmationSound(
				"/System/Library/Components/CoreAudio.component/Contents/SharedSupport/SystemSounds/siri/jbl_confirm.caf" -- codespell-ignore
			)
			vim.cmd.checktime() -- in case a `git pull` has updated a file
		end,
		on_stderr = function(_, data)
			if data[1] == "" and #data == 1 then return end
			local output = vim.trim(table.concat(data, "\n"))

			-- git often puts non-errors into STDERR, therefore checking here again
			-- whether it is actually an error or not
			local logLevel = "info"
			local sound =
				"/System/Library/Components/CoreAudio.component/Contents/SharedSupport/SystemSounds/siri/jbl_confirm.caf" -- codespell-ignore
			if output:lower():find("error") then
				logLevel = "error"
				sound = "/System/Library/Sounds/Basso.aiff"
			elseif output:lower():find("warning") then
				logLevel = "warn"
				sound = "/System/Library/Sounds/Basso.aiff"
			end

			notify(output, logLevel, "Push")
			confirmationSound(sound)
			vim.cmd.checktime() -- in case a `git pull` has updated a file
		end,
	})
end

--------------------------------------------------------------------------------

---opens current buffer in the browser & copies the link to the clipboard
---normal mode: link to file
---visual mode: link to selected lines
---@param justRepo any -- don't link to file with a specific commit, just link to repo
function M.githubUrl(justRepo)
	if notInGitRepo() then return end

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

	openUrl(url)
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
---@param userOpts? { state?: string, type?: string }
function M.issuesAndPrs(userOpts)
	if notInGitRepo() then return end
	if not userOpts then userOpts = {} end
	local defaultOpts = { state = "all", type = "all" }
	local opts = vim.tbl_deep_extend("force", defaultOpts, userOpts)

	local repo = fn.system("git remote -v | head -n1"):match(":.*%."):sub(2, -2)

	-- DOCS https://docs.github.com/en/free-pro-team@latest/rest/issues/issues?apiVersion=2022-11-28#list-repository-issues
	local rawJsonUrl = ("https://api.github.com/repos/%s/issues?per_page=100&state=%s&sort=updated"):format(
		repo,
		opts.state
	)
	local rawJSON = fn.system { "curl", "-sL", rawJsonUrl }
	local issues = vim.json.decode(rawJSON)
	if not issues then
		notify("Failed to fetch issues.", "warn")
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
		notify(("There are no %s%sfor this repo."):format(state, type), "warn")
		return
	end

	local title = opts.type == "all" and "Issue/PR" or opts.type
	vim.ui.select(
		issues,
		{ prompt = " Select " .. title, kind = "github_issue", format_item = issueListFormatter },
		function(choice)
			if not choice then return end
			openUrl(choice.html_url)
		end
	)
end

--------------------------------------------------------------------------------
return M
