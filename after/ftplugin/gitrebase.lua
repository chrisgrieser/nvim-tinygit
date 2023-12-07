-- GUARD
if vim.g.tinygit_no_rebase_ftplugin then return end

--------------------------------------------------------------------------------

-- BETTER HIGHLIGHTING
local ns = vim.api.nvim_create_namespace("tinygit.selector")
vim.api.nvim_win_set_hl_ns(0, ns)

vim.fn.matchadd("tinygit_rebase_issueNumber", [[#\d\+]])
vim.api.nvim_set_hl(ns, "tinygit_rebase_issueNumber", { link = "Number" })

vim.fn.matchadd("tinygit_rebase_mdInlineCode", [[`.\{-}`]]) -- .\{-} = non-greedy quantifier
vim.api.nvim_set_hl(ns, "tinygit_rebase_mdInlineCode", { link = "@text.literal" })

vim.fn.matchadd(
	"tinygit_rebase_conventionalCommit",
	[[\v (feat|fix|test|perf|build|ci|revert|refactor|chore|docs|break|improv|style)(!|(.{-}))?\ze:]]
)
vim.api.nvim_set_hl(ns, "tinygit_rebase_conventionalCommit", { link = "Title" })

vim.fn.matchadd("tinygit_rebase_fixupSquash", [[\v (fixup|squash)!]])
vim.api.nvim_set_hl(ns, "tinygit_rebase_fixupSquash", { link = "WarningMsg" })

vim.fn.matchadd("tinygit_rebase_drop", [[^drop .*]])
vim.api.nvim_set_hl(ns, "tinygit_rebase_drop", { strikethrough = true, fg = "#808080" })

--------------------------------------------------------------------------------
-- KEYMAPS

-- rebase action toggle
vim.keymap.set("n", "<Tab>", function()
	local modes = {
		"pick",
		"squash",
		"\tfixup", -- indented to indicate it's a fixup
		"reword",
		"drop",
	}
	local curLine = vim.api.nvim_get_current_line()
	local firstWord = curLine:match("^\t?%a+")

	for i = 1, #modes do
		if firstWord == modes[i] then
			local nextMode = modes[(i % #modes) + 1]
			local changedLine = curLine:gsub(firstWord, nextMode, 1)
			vim.api.nvim_set_current_line(changedLine)
			return
		elseif firstWord == modes[i]:sub(1, 1) then
			-- abbreviations of short actions
			local nextMode = modes[(i % #modes) + 1]:sub(1, 1)
			local changedLine = curLine:gsub(firstWord, nextMode, 1)
			vim.api.nvim_set_current_line(changedLine)
			return
		end
	end
end, { buffer = true, desc = "Toggle Rebase Action" })
