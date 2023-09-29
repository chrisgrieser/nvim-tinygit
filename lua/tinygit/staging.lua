local M = {}
local u = require("tinygit.utils")
--------------------------------------------------------------------------------

---@deprecated
---TODO make PR to gitsigns.nvim instead?
function M.stageHunkWithInfo()
	-- stage
	local ok, gitsigns = pcall(require, "gitsigns")
	if not ok then
		u.notify("Gitsigns not installed.", "warn")
		return
	end
	gitsigns.stage_hunk()

	-- HACK defer since stage_hunk is async
	vim.defer_fn(function()
		-- display total stage info
		local info = vim.fn.system { "git", "diff", "--staged", "--stat" }
		if vim.v.shell_error ~= 0 then return "" end
		local infoNoLastLine = info:gsub("\n.-$", "")
		u.notify(infoNoLastLine, "info", "Staged Changes")
	end, 100)
end

--------------------------------------------------------------------------------
return M
