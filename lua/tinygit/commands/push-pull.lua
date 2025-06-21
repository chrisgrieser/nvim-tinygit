local M = {}

local u = require("tinygit.shared.utils")
local createGitHubPr = require("tinygit.commands.github").createGitHubPr
local updateStatusline = require("tinygit.statusline").updateAllComponents
--------------------------------------------------------------------------------

---@param commitRange string|nil
local function openReferencedIssues(commitRange)
	if not commitRange then return end -- e.g. for "Everything is up-to-date"
	local repo = require("tinygit.commands.github").getGithubRemote("silent")
	if not repo then return end

	local pushedCommits = u.syncShellCmd { "git", "log", commitRange, "--format=%s" }
	for issue in pushedCommits:gmatch("#(%d+)") do
		local url = ("https://github.com/%s/issues/%s"):format(repo, issue)

		-- deferred, so github registers the change before tab is opened, and so
		-- the user can register notifications before switching to browser
		vim.defer_fn(function() vim.ui.open(url) end, 400)
	end
end

---@param opts { pullBefore?: boolean|nil, forceWithLease?: boolean, createGitHubPr?: boolean }
local function pushCmd(opts)
	local config = require("tinygit.config").config.push
	local gitCommand = { "git", "push" }
	local title = opts.forceWithLease and "Force push" or "Push"
	if opts.forceWithLease then table.insert(gitCommand, "--force-with-lease") end

	vim.system(
		gitCommand,
		{ detach = true },
		vim.schedule_wrap(function(result)
			local out = vim.trim((result.stdout or "") .. (result.stderr or ""))
			out = out:gsub("\n%s+", "\n") -- remove padding
			local commitRange = out:match("%x+%.%.%x+") ---@type string|nil
			-- force-push `+` would get md-lhighlight
			local ft = opts.forceWithLease and "text" or "markdown"

			-- notify
			if result.code == 0 then
				local numOfPushedCommits = u.syncShellCmd { "git", "rev-list", "--count", commitRange }
				if numOfPushedCommits ~= "" then
					local plural = numOfPushedCommits ~= "1" and "s" or ""
					-- `[]` -> simple highlighting for `snacks.nvim`
					out = out .. ("\n[%d commit%s]"):format(numOfPushedCommits, plural)
				end
			end
			u.notify(out, result.code == 0 and "info" or "error", { title = title, ft = ft })

			-- sound
			if config.confirmationSound and jit.os == "OSX" then
				local sound = result.code == 0
						and "/System/Library/Components/CoreAudio.component/Contents/SharedSupport/SystemSounds/siri/jbl_confirm.caf" -- codespell-ignore
					or "/System/Library/Sounds/Basso.aiff"
				vim.system { "afplay", sound } -- run async
			end

			-- post-push actions
			if config.openReferencedIssues and not opts.forceWithLease then
				openReferencedIssues(commitRange)
			end
			updateStatusline()
			if opts.createGitHubPr then
				-- deferred to ensrue GitHub has registered the PR
				vim.defer_fn(createGitHubPr, 1000)
			end
		end)
	)
end
--------------------------------------------------------------------------------

---@param opts? { pullBefore?: boolean, forceWithLease?: boolean, createGitHubPr?: boolean }
---@param calledByCommitFunc? boolean
function M.push(opts, calledByCommitFunc)
	local config = require("tinygit.config").config.push
	if not opts then opts = {} end
	local title = opts.forceWithLease and "Force push" or "Push"

	-- GUARD
	if u.notInGitRepo() then return end
	if config.preventPushingFixupOrSquashCommits then
		local fixupOrSquashCommits =
			u.syncShellCmd { "git", "log", "--oneline", "--grep=^fixup!", "--grep=^squash!" }
		if fixupOrSquashCommits ~= "" then
			local msg = "Aborting: There are fixup or squash commits.\n\n" .. fixupOrSquashCommits
			u.notify(msg, "warn", { title = title })
			return
		end
	end

	-- extra notification when called by user
	if not calledByCommitFunc then
		if opts.pullBefore then title = "Pull & " .. title:lower() end
		u.notify(title .. "…", "info")
	end

	-- Only Push
	if not opts.pullBefore then
		pushCmd(opts)
		return
	end

	-- Handle missing tracking branch, see #21
	local hasNoTrackingBranch = u.syncShellCmd({ "git", "status", "--short", "--branch" })
		:find("## (.-)%.%.%.") == nil
	if hasNoTrackingBranch then
		local noAutoSetupRemote = u.syncShellCmd { "git", "config", "--get", "push.autoSetupRemote" }
			== "false"
		if noAutoSetupRemote then
			u.notify("There is no tracking branch. Aborting push.", "warn", { title = title })
			return
		end
		if opts.pullBefore then
			local msg = "Not pulling since not tracking any branch. Skipping to push."
			u.notify(msg, "info", { title = title })
			pushCmd(opts)
			return
		end
	end

	-- Pull & Push
	vim.system(
		{ "git", "pull" },
		{ detach = true },
		vim.schedule_wrap(function(result)
			-- Git messaging is weird and sometimes puts normal messages into
			-- stderr, thus we need to merge stdout and stderr.
			local out = (result.stdout or "") .. (result.stderr or "")

			local silenceMsg = out:find("Current branch .* is up to date")
				or out:find("Already up to date")
				or out:find("Successfully rebased and updated")
			if not silenceMsg then
				local severity = result.code == 0 and "info" or "error"
				u.notify(out, severity, { title = "Pull" })
			end

			-- update buffer in case the pull changed it
			vim.cmd.checktime()

			-- only push if pull was successful
			if result.code == 0 then pushCmd(opts) end
		end)
	)
end

--------------------------------------------------------------------------------
return M
