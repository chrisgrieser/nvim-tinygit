local M = {}
--------------------------------------------------------------------------------

function M.inlineCodeAndIssueNumbers()
	vim.fn.matchadd("Number", [[#\d\+]])
	vim.fn.matchadd("@markup.raw.markdown_inline", [[`.\{-}`]]) -- .\{-} = non-greedy quantifier
end

function M.commitType()
	local commitTypePattern = [[\v^\s*\w+(\(.{-}\))?!?]]
	local type = commitTypePattern .. [[\ze: ]] -- `\ze`: end of match
	local colonAfterType = commitTypePattern .. [[\zs: ]] -- `\zs`: start of match
	vim.fn.matchadd("Title", type)
	vim.fn.matchadd("Comment", colonAfterType)
	vim.fn.matchadd("WarningMsg", [[\v(fixup|squash)!]])
end

--------------------------------------------------------------------------------
return M
