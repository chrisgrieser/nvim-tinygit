local M = {}

local config = require("tinygit.config").config.blameStatusLine

-- INFO This file is required nowhere but in the snippet the user uses. That
-- means non of this code will be executed, if the user does not decide to use
-- this feature.

--------------------------------------------------------------------------------

---@param bufnr number
---@return string blame
---@nodiscard
local function getBlame(bufnr)
	local bufPath = vim.api.nvim_buf_get_name(bufnr)
	local blame = vim.trim(
		vim.fn.system { "git", "log", "--format=%an\t%cr\t%s", "--max-count=1", "--", bufPath }
	)

	-- GUARD
	if vim.v.shell_error ~= 0 or blame == "" then return "" end

	local author, date, msg = unpack(vim.split(blame, "\t"))

	-- shorten
	date = date:match("%d+ %wi?") or "" -- 1st letter (or min, "m" could be min or month)
	msg = #msg > config.maxMsgLen and msg:sub(1, config.maxMsgLen) .. "…" or msg

	if vim.tbl_contains(config.ignoreAuthors, author) then return "" end
	return ("%s%s (%s)"):format(config.icon, msg, date)
end

--------------------------------------------------------------------------------

vim.api.nvim_create_autocmd({ "BufEnter", "DirChanged" }, {
	callback = function(ctx)
		local bufnr = ctx.buf
		if vim.api.nvim_buf_get_option(ctx.buf, "buftype") ~= "" then return end
		vim.b["tinygit_blame"] = getBlame(bufnr)
	end,
})

-- initialize in case of lazy-loading
vim.b["tinygit_blame"] = getBlame(0)

function M.statusLine() return vim.b["tinygit_blame"] or "" end

--------------------------------------------------------------------------------
return M
