-- GUARD
if vim.g.tinygit_no_rebase_ftplugin then return end

--------------------------------------------------------------------------------

-- BETTER HIGHLIGHTING
local ns = vim.api.nvim_create_namespace("tinygit.gitrebase-hls")
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
