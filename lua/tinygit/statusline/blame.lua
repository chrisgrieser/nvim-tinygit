local M = {}

local u = require("tinygit.shared.utils")
--------------------------------------------------------------------------------

---@param bufnr? number
---@return string blame lualine stringifys result, so need to return empty string instead of nil
---@nodiscard
local function getBlame(bufnr)
	bufnr = bufnr or 0
	local config = require("tinygit.config").config.statusline.blame

	-- GUARD valid buffer
	if not vim.api.nvim_buf_is_valid(bufnr) then return "" end
	if vim.api.nvim_get_option_value("buftype", { buf = bufnr }) ~= "" then return "" end

	local bufPath = vim.api.nvim_buf_get_name(bufnr)
	local gitLogCmd = { "git", "log", "--max-count=1", "--format=%H\t%an\t%cr\t%s", "--", bufPath }
	local gitLogResult = vim.system(gitLogCmd):wait()

	-- GUARD git log output
	local stdout = vim.trim(gitLogResult.stdout)
	if stdout == "" or gitLogResult.code ~= 0 then return "" end

	local hash, author, relDate, msg = unpack(vim.split(stdout, "\t"))
	if vim.tbl_contains(config.ignoreAuthors, author) then return "" end
	local shortRelDate = u.shortenRelativeDate(relDate)

	-- GUARD shallow and on first commit
	-- get first commit: https://stackoverflow.com/a/5189296/22114136
	local isOnFirstCommit = hash == u.syncShellCmd { "git", "rev-list", "--max-parents=0", "HEAD" }
	local shallowRepo = require("tinygit.shared.utils").inShallowRepo()
	if shallowRepo and isOnFirstCommit then return "" end

	if vim.list_contains(config.showOnlyTimeIfAuthor, author) then
		return vim.trim(("%s %s"):format(config.icon, shortRelDate))
	end

	local trimmedMsg = #msg <= config.maxMsgLen and msg
		or vim.trim(msg:sub(1, config.maxMsgLen)) .. "…"
	local authorInitials = not (author:find("%s")) and author:sub(1, 2) -- "janedoe" -> "ja"
		or author:sub(1, 1) .. author:match("%s(%S)") -- "Jane Doe" -> "JD"
	local authorStr = vim.list_contains(config.hideAuthorNames, author) and ""
		or " by " .. authorInitials
	return vim.trim(("%s %s [%s%s]"):format(config.icon, trimmedMsg, shortRelDate, authorStr))
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

function M.getBlame() return vim.b.tinygit_blame or "" end

--------------------------------------------------------------------------------
return M
