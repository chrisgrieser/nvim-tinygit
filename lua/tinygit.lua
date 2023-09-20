local M = {}
local fn = vim.fn

--------------------------------------------------------------------------------
local defaultConfig = {
	commitMaxLen = 72,
	smallCommitMaxLen = 50, -- https://stackoverflow.com/q/2290016/22114136
	emptyCommitMsgFillIn = "chore",
	enforceConvCommits = {
		enabled = true,
		-- stylua: ignore
		keywords = {
			"chore", "build", "test", "fix", "feat", "refactor", "perf",
			"style", "revert", "ci", "docs", "break", "improv",
		},
	},
	issueIcons = {
		closedIssue = "🟣",
		openIssue = "🟢",
		openPR = "🟦",
		mergedPR = "🟨",
		closedPR = "🟥",
	},
	confirmationSoundsOnMacOs = true,
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
---@param msg string
---@param level? "info"|"trace"|"debug"|"warn"|"error"
local function notify(msg, level)
	local pluginName = "tinygit"
	if not level then level = "info" end
	vim.notify(vim.trim(msg), vim.log.levels[level:upper()], { title = pluginName })
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

---also notifies if not in git repo
---@nodiscard
---@return boolean
local function notInGitRepo()
	fn.system("git rev-parse --is-inside-work-tree")
	local notInRepo = nonZeroExit("Not in Git Repo.")
	return notInRepo
end

---if on mac, play a sound
---@param soundFilepath string
local function playSoundMacOS(soundFilepath)
	local onMacOs = fn.has("macunix") == 1
	if not onMacOs or not config.confirmationSoundsOnMacOs then return end
	fn.system(("afplay %q &"):format(soundFilepath))
end

---process a commit message: length, not empty, adheres to conventional commits
---@param commitMsg string
---@nodiscard
---@return boolean is the commit message valid?
---@return string the (modified) commit message
local function processCommitMsg(commitMsg)
	commitMsg = vim.trim(commitMsg)
	if #commitMsg > config.commitMaxLen then
		notify("Commit Message too long.", "warn")
		local shortenedMsg = commitMsg:sub(1, config.commitMaxLen)
		return false, shortenedMsg
	elseif commitMsg == "" then
		if not config.emptyCommitMsgFillIn then
			notify("Commit Message empty.", "warn")
			return false, ""
		else
			return true, config.emptyCommitMsgFillIn
		end
	end

	if config.enforceConvCommits then
		-- stylua: ignore
		local firstWord = commitMsg:match("^%w+")
		if not vim.tbl_contains(config.enforceConvCommits.keywords, firstWord) then
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
			local winNs = 1
			vim.api.nvim_win_set_hl_ns(0, winNs)

			-- \zs = start of match
			-- \ze = end of match
			fn.matchadd(
				"almostLong",
				([[.\{%s}\zs.\{1,%s}\ze]]):format(
					config.smallCommitMaxLen - 1,
					config.commitMaxLen - config.smallCommitMaxLen
				)
			)
			vim.api.nvim_set_hl(winNs, "almostLong", { link = "WarningMsg" })

			fn.matchadd("tooLong", ([[.\{%s}\zs.*\ze]]):format(config.commitMaxLen - 1))
			vim.api.nvim_set_hl(winNs, "tooLong", { link = "ErrorMsg" })

			-- for treesitter highlighting
			vim.bo.filetype = "gitcommit"
			vim.api.nvim_set_hl(winNs, "Title", { link = "Normal" })

			-- fix confirming input field (not working in insert mode due to filetype change)
			vim.keymap.set("i", "<CR>", "<Esc><CR>", { buffer = true, remap = true })

			vim.api.nvim_buf_set_name(0, "COMMIT_EDITMSG") -- for statusline plugins

			vim.opt_local.colorcolumn = { config.smallCommitMaxLen, config.commitMaxLen }
		end,
	})
end

--------------------------------------------------------------------------------

---@param opts? object
local function amendNoEdit(opts)
	-- show the message of the last commit
	local lastCommitMsg = vim.trim(fn.system("git log -1 --pretty=%B"))
	notify('󰊢 Amend-No-Edit\n"' .. lastCommitMsg .. '"')

	local stderr = fn.system("git add -A && git commit --amend --no-edit")
	if nonZeroExit(stderr) then return end

	if opts.forcePush then M.push { force = true } end
end

---@param opts? object
---@param prefillMsg? string
function M.amend(opts, prefillMsg)
	if not opts then opts = {} end
	vim.cmd("silent update")
	if notInGitRepo() then return end

	if opts.noedit then
		amendNoEdit(opts)
		return
	end

	if not prefillMsg then
		local lastCommitMsg = vim.trim(fn.system("git log -1 --pretty=%B"))
		prefillMsg = lastCommitMsg
	end
	setGitCommitAppearance()

	vim.ui.input({ prompt = "󰊢 Amend", default = prefillMsg }, function(commitMsg)
		if not commitMsg then return end -- aborted input modal
		local validMsg, newMsg = processCommitMsg(commitMsg)
		if not validMsg then -- if msg invalid, run again to fix the msg
			M.amend(newMsg)
			return
		end

		notify('󰊢 Amend\n"' .. newMsg .. '"')
		local stderr = fn.system("git add -A && git commit --amend -m '" .. newMsg .. "'")
		if nonZeroExit(stderr) then return end

		if opts.forcePush then M.push { force = true } end
	end)
end

--------------------------------------------------------------------------------

---If there are staged changes, commit them.
---If there aren't, add all changes (`git add -A`) and then commit.
---@param prefillMsg? string
---@param opts? object
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
			M.smartCommitPush(newMsg)
			return
		end

		local hasStagedChanges = fn.system("git diff --staged --quiet || echo -n 'yes'") == "yes"
		if not hasStagedChanges then
			local stderr = fn.system { "git", "add", "-A" }
			if nonZeroExit(stderr) then return end
		end
		notify('󰊢 Smart Commit\n"' .. newMsg .. '"')

		local stderr = fn.system { "git", "commit", "-m", newMsg }
		if nonZeroExit(stderr) then return end

		if opts.push then M.push { pullBefore = true } end
	end)
end

-- pull before to avoid conflicts
---@param opts? object
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

			notify(output)
			playSoundMacOS(
				"/System/Library/Components/CoreAudio.component/Contents/SharedSupport/SystemSounds/siri/jbl_confirm.caf" -- codespell-ignore
			)
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

			notify(output, logLevel)
			playSoundMacOS(sound)
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

---Choose a GitHub issue/PR from the current repo to open in the browser.
---(Due to -GitHub API liminations, only the last 100 issues are shown.)
---@param state? "open"|"closed"|"all" default "all"
function M.issuesAndPrs(state)
	if notInGitRepo() then return end
	if not state then state = "all" end

	local repo = fn.system("git remote -v | head -n1"):match(":.*%."):sub(2, -2)

	-- TODO figure out how to make a proper http request in nvim
	local rawJsonUrl = ("https://api.github.com/repos/%s/issues?per_page=100&state=%s"):format(
		repo,
		state
	)
	local rawJSON = fn.system { "curl", "-sL", rawJsonUrl }
	local issues = vim.json.decode(rawJSON)

	if not issues or #issues == 0 then
		local type = state == "all" and "" or state .. " "
		notify(("There are no %sissues or PRs for this repo."):format(type), "warn")
		return
	end

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

	vim.ui.select(
		issues,
		{ prompt = " Select Issue:", kind = "github_issue", format_item = issueListFormatter },
		function(choice)
			if not choice then return end
			openUrl(choice.html_url)
		end
	)
end

--------------------------------------------------------------------------------
return M
