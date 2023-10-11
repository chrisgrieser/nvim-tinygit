local M = {}
local u = require("tinygit.utils")
--------------------------------------------------------------------------------

---@deprecated 
function M.stageHunkWithInfo()
	-- stage
	local ok, gitsigns = pcall(require, "gitsigns")
	if not ok then
		u.notify("Gitsigns not installed.", "warn")
		return
	end
	gitsigns.stage_hunk()

	-- HACK defer since stage_hunk is async
	-- PENDING https://github.com/lewis6991/gitsigns.nvim/issues/906
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
