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

---@param userOpts { pullBefore?: boolean, force?: boolean, createGitHubPr?: boolean }
---@param soundFilepath string
local function postPushActions(userOpts, soundFilepath)
	-- CAVEAT currently only on macOS
	local onMacOs = fn.has("macunix") == 1
	if not (onMacOs and config.confirmationSound) then return end
	fn.system(("afplay %q &"):format(soundFilepath))

	if userOpts.pullBefore then vim.cmd.checktime() end
	if userOpts.createGitHubPr then createGitHubPr() end
end

--------------------------------------------------------------------------------

-- pull before to avoid conflicts
---@param userOpts { pullBefore: boolean, force: boolean, createGitHubPr?: boolean }
---@param calledByUser? boolean
function M.push(userOpts, calledByUser)
	-- GUARD
	if u.notInGitRepo() then return end

	local title = userOpts.force and "Force Push" or "Push"
	local shellCmd = userOpts.force and "git push --force" or "git push"
	if userOpts.pullBefore then
		shellCmd = "git pull && " .. shellCmd
		title = "Pull & " .. title
	end

	-- GUARD
	if config.preventPushingFixupOrSquashCommits then
		local fixupOrSquashCommits = getFixupOrSquashCommits()
		if fixupOrSquashCommits ~= "" then
			-- stylua: ignore
			u.notify("Aborting: There are fixup or squash commits.\n\n" .. fixupOrSquashCommits, "warn", "Push")
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

			-- no need to notify that the pull in `git pull ; git push` yielded no update
			if output:find("Current branch .* is up to date") or output:find("Already up to date.") then
				return
			end

			u.notify(output, "info", title)
			local sound =
				"/System/Library/Components/CoreAudio.component/Contents/SharedSupport/SystemSounds/siri/jbl_confirm.caf" -- codespell-ignore
			postPushActions(userOpts, sound)
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

			u.notify(output, logLevel, title)
			postPushActions(userOpts, sound)
		end,
	})
end

--------------------------------------------------------------------------------
return M
