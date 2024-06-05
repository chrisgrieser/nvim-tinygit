local M = {}

local u = require("tinygit.shared.utils")
local config = require("tinygit.config").config.push
local createGitHubPr = require("tinygit.commands.github").createGitHubPr
--------------------------------------------------------------------------------

---@param opts { pullBefore?: boolean|nil, forceWithLease?: boolean, createGitHubPr?: boolean }
local function pushCmd(opts)
	local cmd = { "git", "push" }
	if opts.forceWithLease then table.insert(cmd, "--force-with-lease") end

	vim.system(
		cmd,
		{ detach = true, text = true },
		vim.schedule_wrap(function(result)
			local out = (result.stdout or "") .. (result.stderr or "")
			local severity = result.code == 0 and "info" or "error"
			u.notify(out, severity, "Push")

			-- sound
			if config.confirmationSound and vim.uv.os_uname().sysname == "Darwin" then
				local sound = result.code == 0
						and "/System/Library/Components/CoreAudio.component/Contents/SharedSupport/SystemSounds/siri/jbl_confirm.caf" -- codespell-ignore
					or "/System/Library/Sounds/Basso.aiff"
				vim.system { "afplay", sound }
			end

			-- post-push actions
			if opts.createGitHubPr then createGitHubPr() end
			u.updateStatuslineComponents()
		end)
	)
end
--------------------------------------------------------------------------------

---@param opts? { pullBefore?: boolean, forceWithLease?: boolean, createGitHubPr?: boolean }
---@param calledByUser? boolean
function M.push(opts, calledByUser)
	-- GUARD
	if u.notInGitRepo() then return end
	if config.preventPushingFixupOrSquashCommits then
		local fixupOrSquashCommits =
			u.syncShellCmd { "git", "log", "--oneline", "--grep=^fixup!", "--grep=^squash!" }
		if fixupOrSquashCommits ~= "" then
			local msg = "Aborting: There are fixup or squash commits.\n\n" .. fixupOrSquashCommits
			u.notify(msg, "warn", "Push")
			return
		end
	end
	if not opts then opts = {} end

	-- extra notification when called by user
	if calledByUser then
		local title = opts.forceWithLease and "Force Push" or "Push"
		if opts.pullBefore then title = "Pull & " .. title end
		u.notify(title .. "…", "info")
	end

	-- Only Push
	if not opts.pullBefore then
		pushCmd(opts)
		return
	end

	-- Pull & Push
	vim.system(
		{ "git", "pull" },
		{ detach = true, text = true },
		vim.schedule_wrap(function(result)
			-- Git messaging is weird and sometimes puts normal messages into
			-- stderr. Thus we print all messages and silence some of them.
			local out = (result.stdout or "") .. (result.stderr or "")
			local silenceMsg = out:find("Current branch .* is up to date")
				or out:find("Already up to date")
				or out:find("Successfully rebased and updated refs/heads/")
			if not silenceMsg then
				local severity = result.code == 0 and "info" or "error"
				u.notify(out, severity, "Pull")
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
