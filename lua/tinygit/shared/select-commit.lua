-- Shared Components for selecting a commit
--------------------------------------------------------------------------------
local M = {}

-- what is passed to `git log --format`. hash/`%h` follows by a tab is required
-- at the beginning, the rest is decorative, though \t as delimiter as
-- assumed by the others parts here.
M.gitlogFormat = "%h\t%s\t%cr" -- hash, subject, date

---Formats line for `vim.ui.select`
---@param commitLine string, formatted as M.gitlogFormat
---@return string formatted text
function M.selectorFormatter(commitLine)
	local _, subject, date, nameAtCommit = unpack(vim.split(commitLine, "\t"))
	local displayLine = ("%s\t%s"):format(subject, date)
	-- append name at commit, if it exists
	if nameAtCommit then displayLine = displayLine .. ("\t(%s)"):format(nameAtCommit) end
	return displayLine
end

-- highlights for the items in the selector
function M.setupAppearance()
	local autocmdId = vim.api.nvim_create_autocmd("FileType", {
		once = true, -- to not affect other selectors
		pattern = { "DressingSelect", "TelescopeResults" }, -- nui also uses `DressingSelect`
		callback = function()
			require("tinygit.shared.utils").commitMsgHighlighting()

			-- detects date due to `M.gitlogFormat`
			vim.fn.matchadd("Comment", [[\t.*$]])
		end,
	})
	return autocmdId
end

--------------------------------------------------------------------------------
return M
