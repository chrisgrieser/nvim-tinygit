local M = {}

local config = require("tinygit.config").config.blameStatusLine
local trim = vim.trim
local fn = vim.fn

-- INFO This file is required nowhere but in the snippet the user uses. That
-- means non of this code will be executed, if the user does not decide to use
-- this feature.

--------------------------------------------------------------------------------

---@param bufnr? number
---@return string blame
---@nodiscard
local function getBlame(bufnr)
	local bufPath = vim.api.nvim_buf_get_name(bufnr or 0)
	local gitLogLine = trim(
		vim.fn.system { "git", "log", "--format=%H\t%an\t%cr\t%s", "--max-count=1", "--", bufPath }
	)
	local hash, author, relDate, msg = unpack(vim.split(gitLogLine, "\t"))

	-- GUARD
	local shallowRepo = require("tinygit.shared.utils").inShallowRepo()
	local isOnFirstCommit = hash == trim(fn.system { "git", "rev-list", "--max-parents=0", "HEAD" })
	if
		vim.v.shell_error ~= 0 -- errors
		or gitLogLine == ""
		or vim.tbl_contains(config.ignoreAuthors, author) -- user config
		or (shallowRepo and isOnFirstCommit) -- false commit infos on shallow repos
	then
		return "" -- lualine stringifys, so returning nil would display "nil" as string
	end

	-- shorten the output
	local shortRelDate = (relDate:match("%d+ %wi?n?") or "") -- 1 unit char (expect min)
		:gsub("m$", "mo") -- month -> mo to be distinguishable from "min"
		:gsub(" ", "")
		:gsub("%d+s", "just now") -- secs -> just now
	if not shortRelDate:find("just now") then shortRelDate = shortRelDate .. " ago" end
	local trimmedMsg = #msg < config.maxMsgLen and msg or trim(msg:sub(1, config.maxMsgLen)) .. "…"
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
	callback = function(ctx)
		if vim.api.nvim_buf_get_option(ctx.buf, "buftype") ~= "" then return end
		M.refreshBlame(ctx.buf)
	end,
})

M.refreshBlame() -- initialize in case of lazy-loading

function M.statusLine() return vim.b["tinygit_blame"] or "" end

--------------------------------------------------------------------------------
return M
