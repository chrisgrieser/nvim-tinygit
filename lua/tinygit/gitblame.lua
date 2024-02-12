local M = {}
--------------------------------------------------------------------------------

-- This module is only there for backwards compatibility. Will notify the user
-- to use the new module.

local notified = false

---@deprecated
function M.statusLine()
	if not notified then
		vim.defer_fn(function()
			local msg = '`require("tinygit.gitblame").statusLine()` is deprecated.\n'
				.. 'Please use `require("tinygit.statusline").blame()` instead.\n\n'
			.. "Note that the config also changed from `blameStatusLine` to `statusline.blame`."
			vim.notify(msg, vim.log.levels.WARN, { title = "tinygit" })
		end, 3000)
		notified = true
	end
	return require("tinygit.statusline").blame()
end

--------------------------------------------------------------------------------
return M
