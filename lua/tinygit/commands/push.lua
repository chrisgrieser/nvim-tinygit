local M = {}
local fn = vim.fn

local u = require("tinygit.shared.utils")
local config = require("tinygit.config").config.push
local createGitHubPr = require("tinygit.commands.github").createGitHubPr
--------------------------------------------------------------------------------

---@return string
local function getFixupOrSquashCommits()
	return vim.trim(fn.system { "git", "log", "--oneline", "--grep=^fixup!", "--grep=^squash!" })
end

---@param userOpts { pullBefore?: boolean, forceWithLease?: boolean, createGitHubPr?: boolean }
---@param soundFilepath string
local function postPushActions(userOpts, soundFilepath)
	-- CAVEAT currently only on macOS
	local onMacOs = fn.has("macunix") == 1
	if not (onMacOs and config.confirmationSound) then return end
	fn.system(("afplay %q &"):format(soundFilepath))

	if userOpts.pullBefore then vim.cmd.checktime() end
	if userOpts.createGitHubPr then createGitHubPr() end

	-- conditation to avoid unnecessarily loading the module
	if package.loaded["tinygit.statusline.branch-state"] then
		require("tinygit.statusline.branch-state").refreshBranchState()
	end
end

--------------------------------------------------------------------------------

-- pull before to avoid conflicts
---@param userOpts { pullBefore: boolean, forceWithLease: boolean, createGitHubPr?: boolean }
---@param calledByUser? boolean
function M.push(userOpts, calledByUser)
	-- GUARD
	if u.notInGitRepo() then return end

	local title = userOpts.forceWithLease and "Force Push" or "Push"
	local shellCmd = userOpts.forceWithLease and "git push --force-with-lease" or "git push"
	if userOpts.pullBefore then
		shellCmd = "git pull && " .. shellCmd -- && prevents force-push on failed pull
		title = "Pull & " .. title
	end

	-- GUARD
	if config.preventPushingFixupOrSquashCommits then
		local fixupOrSquashCommits = getFixupOrSquashCommits()
		if fixupOrSquashCommits ~= "" then
			u.notify(
				"Aborting: There are fixup or squash commits.\n\n" .. fixupOrSquashCommits,
				"warn",
				"Push"
			)
			return
		end
	end

	if calledByUser then u.notify(title .. "…", "info") end

	fn.jobstart(shellCmd, {
		stdout_buffered = true,
		stderr_buffered = true,
		detach = true, -- finish even when quitting nvim
		on_stdout = function(_, data)
			if data[1] == "" and #data == 1 then return end
			local output = vim.trim(table.concat(data, "\n"))
			output = output:gsub("^%[K", "") -- remove weird ANSI escape code being added sometimes

			-- no need to notify that the pull in `git pull ; git push` yielded no update
			if
				output:find("Current branch .* is up to date") or output:find("Already up to date.")
			then
				return
			end

			u.notify(u.rmAnsiEscFromStr(output), "info", title)
			local sound =
				"/System/Library/Components/CoreAudio.component/Contents/SharedSupport/SystemSounds/siri/jbl_confirm.caf" -- codespell-ignore
			postPushActions(userOpts, sound)
		end,
		on_stderr = function(_, data)
			if data[1] == "" and #data == 1 then return end
			local output = vim.trim(table.concat(data, "\n"))
			output = output:gsub("^%[K", "") -- remove weird ANSI escape code being added sometimes

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

			u.notify(u.rmAnsiEscFromStr(output), logLevel, title)
			postPushActions(userOpts, sound)
		end,
	})
end

--------------------------------------------------------------------------------
return M
