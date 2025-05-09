local M = {}
--------------------------------------------------------------------------------

function M.inlineCodeAndIssueNumbers()
	vim.fn.matchadd("Number", [[#\d\+]])
	vim.fn.matchadd("@markup.raw.markdown_inline", [[`.\{-}`]]) -- .\{-} = non-greedy quantifier
end

function M.commitType()
	-- not restricted to start of string, so prefixes like the numbering from the
	-- snacks-ui-select do not prevent the highlight
	local commitTypePattern = [[\v\w+(\(.{-}\))?!?]]

	local type = commitTypePattern .. [[\ze: ]] -- `\ze`: end of match
	local colonAfterType = commitTypePattern .. [[\zs: ]] -- `\zs`: start of match
	vim.fn.matchadd("Title", type)
	vim.fn.matchadd("Comment", colonAfterType)
	vim.fn.matchadd("WarningMsg", [[\v(fixup|squash)!]])
end

--------------------------------------------------------------------------------
return M
