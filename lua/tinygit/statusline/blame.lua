-- INFO This file is required nowhere but in the snippet the user uses. That
-- means non of this code will be executed, if the user does not decide to use
-- this feature.
--------------------------------------------------------------------------------
local M = {}

local config = require("tinygit.config").config.statusline.blame
local trim = vim.trim
local fn = vim.fn
--------------------------------------------------------------------------------

---@param bufnr? number
---@return string blame lualine stringifys result, so need to return empty string instead of nil
---@nodiscard
local function getBlame(bufnr)
	bufnr = bufnr or 0

	-- GUARD valid buffer
	if not vim.api.nvim_buf_is_valid(bufnr) then return "" end
	if vim.api.nvim_buf_get_option(bufnr, "buftype") ~= "" then return "" end

	local bufPath = vim.api.nvim_buf_get_name(bufnr)
	local gitLogLine = trim(
		vim.fn.system { "git", "log", "--format=%H\t%an\t%cr\t%s", "--max-count=1", "--", bufPath }
	)
	-- GUARD git log
	if gitLogLine == "" or vim.v.shell_error ~= 0 then return "" end

	local hash, author, relDate, msg = unpack(vim.split(gitLogLine, "\t"))
	if vim.tbl_contains(config.ignoreAuthors, author) then return "" end

	-- GUARD shallow and on first commit
	-- get first commit: https://stackoverflow.com/a/5189296/22114136
	local isOnFirstCommit = hash == trim(fn.system { "git", "rev-list", "--max-parents=0", "HEAD" })
	local shallowRepo = require("tinygit.shared.utils").inShallowRepo()
	if shallowRepo and isOnFirstCommit then return "" end

	-- shorten the output
	local shortRelDate = (relDate:match("%d+ %wi?n?") or "") -- 1 unit char (expect min)
		:gsub("m$", "mo") -- month -> mo to be distinguishable from "min"
		:gsub(" ", "")
		:gsub("%d+s", "just now") -- secs -> just now
	if not shortRelDate:find("just now") then shortRelDate = shortRelDate .. " ago" end
	local trimmedMsg = #msg <= config.maxMsgLen and msg or trim(msg:sub(1, config.maxMsgLen)) .. "…"
	local authorInitials = not (author:find("%s")) and author:sub(1, 2) -- "janedoe" -> "ja"
		or author:sub(1, 1) .. author:match("%s(%S)") -- "Jane Doe" -> "JD"
	local authorStr = vim.tbl_contains(config.hideAuthorNames, author) and ""
		or " by " .. authorInitials

	return config.icon .. ("%s [%s%s]"):format(trimmedMsg, shortRelDate, authorStr)
end

--------------------------------------------------------------------------------

---@param bufnr? number
function M.refreshBlame(bufnr) vim.b["tinygit_blame"] = getBlame(bufnr) end

vim.api.nvim_create_autocmd({ "BufEnter", "DirChanged", "FocusGained" }, {
	group = vim.api.nvim_create_augroup("tinygit_blame", { clear = true }),
	callback = function(ctx)
		-- so buftype is set before checking the buffer
		vim.defer_fn(function() M.refreshBlame(ctx.buf) end, 1)
	end,
})

vim.defer_fn(M.refreshBlame, 1) -- initialize in case of lazy-loading

function M.getBlame() return vim.b["tinygit_blame"] or "" end

--------------------------------------------------------------------------------
return M
