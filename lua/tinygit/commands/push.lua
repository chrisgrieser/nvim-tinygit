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
		local out = u.rmAnsiEscFromStr(vim.trim((result.stdout or "") .. (result.stderr or "")))
		local severity = result.code == 0 and "info" or "error"
		u.notify(out, severity, "Push")

		-- sound
		if fn.has("macunix") == 1 and config.confirmationSound then
			local sound = result.code == 0
					and "/System/Library/Components/CoreAudio.component/Contents/SharedSupport/SystemSounds/siri/jbl_confirm.caf" -- codespell-ignore
				or "/System/Library/Sounds/Basso.aiff"
			vim.system { "afplay", sound }
		end

		vim.schedule_wrap(function()
			if userOpts.pullBefore then vim.cmd.checktime() end
			if userOpts.createGitHubPr then createGitHubPr() end

			-- condition to avoid unnecessarily loading the module
			if package.loaded["tinygit.statusline.branch-state"] then
				require("tinygit.statusline.branch-state").refreshBranchState()
			end
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

	-- system command
	if userOpts.pullBefore then
		vim.system({ "git", "pull" }, { detach = true, text = true }, function(result)
			local out = (result.stdout or "") .. (result.stderr or "")
			if not (out:find("Current branch .* is up to date") or out:find("Already up to date")) then
				out = u.rmAnsiEscFromStr(vim.trim(out))
				local severity = result.code == 0 and "info" or "error"
				u.notify(out, severity, "Pull")
			end
			-- only push if pull was successful
			if result.code == 0 then pushCmd(userOpts) end
		end)
	else
		pushCmd(userOpts)
	end
end

--------------------------------------------------------------------------------
return M
