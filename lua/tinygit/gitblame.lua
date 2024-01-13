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
	local gitLogLine = vim.trim(
		vim.fn.system { "git", "log", "--format=%an\t%cr\t%s", "--max-count=1", "--", bufPath }
	)
	local author, relDate, msg = unpack(vim.split(gitLogLine, "\t"))

	-- GUARD
	if vim.v.shell_error ~= 0 or gitLogLine == "" then return "" end
	if vim.tbl_contains(config.ignoreAuthors, author) then return "" end

	-- shorten the output
	local shortRelDate = (relDate:match("%d+ %wi?n?") or "") -- 1 unit char (expect min)
		:gsub("m$", "mo") -- month -> mo to be distinguishable from "min"
		:gsub(" ", "")
		:gsub("%d+s", "just now") -- secs -> just now
	local trimmedMsg = #msg < config.maxMsgLen and msg
		or vim.trim(msg:sub(1, config.maxMsgLen)) .. "…"
	local authorInitials = not (author:find("%s")) and author:sub(1, 2) -- "janedoe" -> "ja"
		or author:sub(1, 1) .. author:match("%s(%S)") -- "Jane Doe" -> "JD"
	local authorStr = vim.tbl_contains(config.hideAuthorNames, author) and ""
		or " by " .. authorInitials

	return config.icon .. ("%s [%s ago%s]"):format(trimmedMsg, shortRelDate, authorStr)
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
