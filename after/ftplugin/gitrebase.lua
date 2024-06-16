if vim.g.tinygit_no_rebase_ftplugin then return end
--------------------------------------------------------------------------------

require("tinygit.shared.utils").commitMsgHighlighting()

local ns = vim.api.nvim_create_namespace("tinygit.drop-rebase")
vim.fn.matchadd("tinygit_rebase_drop", [[^drop .*]])
vim.api.nvim_set_hl(ns, "tinygit_rebase_drop", { strikethrough = true, fg = "#808080" })
