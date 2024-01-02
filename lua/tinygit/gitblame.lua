local M = {}

local config = require("tinygit.config").config.blameStatusLine

-- INFO This file is required nowhere but in the snippet the user uses. That
-- means non of this code will be executed, if the user does not decide to use
-- this feature.

--------------------------------------------------------------------------------

---@param bufnr? number
---@return string blame
---@nodiscard
local function getBlame(bufnr)
	local bufPath = vim.api.nvim_buf_get_name(bufnr or 0)
	local blame = vim.trim(
		vim.fn.system { "git", "log", "--format=%an\t%cr\t%s", "--max-count=1", "--", bufPath }
	)

	-- GUARD
	if vim.v.shell_error ~= 0 or blame == "" then return "" end

	local author, date, msg = unpack(vim.split(blame, "\t"))

	-- shorten
	date = (date:match("%d+ %wi?n?") or "") -- 1st letter (+in for min, to distinguish from "month")
		:gsub(" ", "")
		:gsub("%d+s", "just now")
	msg = #msg > config.maxMsgLen and vim.trim(msg:sub(1, config.maxMsgLen)) .. "…" or msg

	if vim.tbl_contains(config.ignoreAuthors, author) then return "" end
	return ("%s%s (%s)"):format(config.icon, msg, date)
end

--------------------------------------------------------------------------------

---@param bufnr? number
function M.refreshBlame(bufnr) vim.b["tinygit_blame"] = getBlame(bufnr) end

vim.api.nvim_create_autocmd({ "BufEnter", "DirChanged", "FocusGained" }, {
	callback = function(ctx)
		if vim.api.nvim_buf_get_option(ctx.buf, "buftype") ~= "" then return end
		M.refreshBlame(ctx.buf)
	end,
})

M.refreshBlame() -- initialize in case of lazy-loading

function M.statusLine() return vim.b["tinygit_blame"] or "" end

--------------------------------------------------------------------------------
return M
