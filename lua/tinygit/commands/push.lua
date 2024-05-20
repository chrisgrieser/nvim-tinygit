local M = {}
local fn = vim.fn

local u = require("tinygit.shared.utils")
local config = require("tinygit.config").config.push
local createGitHubPr = require("tinygit.commands.github").createGitHubPr
--------------------------------------------------------------------------------

---@param userOpts { pullBefore: boolean, forceWithLease: boolean, createGitHubPr?: boolean }
local function pushCmd(userOpts)
	local cmd = { "git", "push" }
	if userOpts.forceWithLease then table.insert(cmd, "--force-with-lease") end

	vim.system(cmd, { detach = true, text = true }, function(result)
		local out = (result.stdout or "") .. (result.stderr or "")
		local severity = result.code == 0 and "info" or "error"
		u.notify(out, severity, "Push")

		-- sound
		if config.confirmationSound and fn.has("macunix") == 1 then
			local sound = result.code == 0
					and "/System/Library/Components/CoreAudio.component/Contents/SharedSupport/SystemSounds/siri/jbl_confirm.caf" -- codespell-ignore
				or "/System/Library/Sounds/Basso.aiff"
			vim.system { "afplay", sound }
		end

		-- post-push actions
		vim.schedule_wrap(function()
			if userOpts.createGitHubPr then createGitHubPr() end
			u.updateStatuslineComponents()
		end)
	end)
end
--------------------------------------------------------------------------------

-- pull before to avoid conflicts
---@param userOpts { pullBefore: boolean, forceWithLease: boolean, createGitHubPr?: boolean }
---@param calledByUser? boolean
function M.push(userOpts, calledByUser)
	-- GUARD
	if u.notInGitRepo() then return end
	if config.preventPushingFixupOrSquashCommits then
		local fixupOrSquashCommits = vim.trim(
			vim.system({ "git", "log", "--oneline", "--grep=^fixup!", "--grep=^squash!" }):wait().stdout
		)
		if fixupOrSquashCommits ~= "" then
			u.notify(
				"Aborting: There are fixup or squash commits.\n\n" .. fixupOrSquashCommits,
				"warn",
				"Push"
			)
			return
		end
	end

	-- extra notification when called by user
	if calledByUser then
		local title = userOpts.forceWithLease and "Force Push" or "Push"
		if userOpts.pullBefore then title = "Pull & " .. title end
		u.notify(title .. "…", "info")
	end

	-- Only Push
	if not userOpts.pullBefore then
		pushCmd(userOpts)
		return
	end

	-- Pull & Push
	vim.system({ "git", "pull" }, { detach = true, text = true }, function(result)
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
		vim.schedule_wrap(vim.cmd.checktime)

		-- only push if pull was successful
		if result.code == 0 then pushCmd(userOpts) end
	end)
end

--------------------------------------------------------------------------------
return M
