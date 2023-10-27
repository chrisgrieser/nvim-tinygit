local M = {}
local fn = vim.fn
local u = require("tinygit.utils")
--------------------------------------------------------------------------------

---CAVEAT currently only on macOS
---@param soundFilepath string
local function confirmationSound(soundFilepath)
	local onMacOs = fn.has("macunix") == 1
	local useSound = require("tinygit.config").config.asyncOpConfirmationSound
	if not (onMacOs and useSound) then return end
	fn.system(("afplay %q &"):format(soundFilepath))
end

--------------------------------------------------------------------------------

-- pull before to avoid conflicts
---@param userOpts { pullBefore?: boolean|nil, force?: boolean|nil }
function M.push(userOpts)
	local title = userOpts.force and "Force Push" or "Push"
	local shellCmd = userOpts.force and "git push --force" or "git push"
	if userOpts.pullBefore then
		shellCmd = "git pull && " .. shellCmd
		title = "Pull & " .. title
	end

	fn.jobstart(shellCmd, {
		stdout_buffered = true,
		stderr_buffered = true,
		detach = true, -- finish even when quitting nvim
		on_stdout = function(_, data)
			if data[1] == "" and #data == 1 then return end
			local output = vim.trim(table.concat(data, "\n"))

			-- no need to notify that the pull in `git pull ; git push` yielded no update
			if output:find("Current branch .* is up to date") then return end

			u.notify(output, "info", title)
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

			u.notify(output, logLevel, title)
			confirmationSound(sound)
			vim.cmd.checktime() -- in case a `git pull` has updated a file
		end,
	})
end

--------------------------------------------------------------------------------
return M
