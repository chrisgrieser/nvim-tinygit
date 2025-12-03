local M = {}
--------------------------------------------------------------------------------

function M.inlineCodeAndIssueNumbers()
	vim.fn.matchadd("Number", [[#\d\+]])
	vim.fn.matchadd("@markup.raw.markdown_inline", [[`.\{-}`]]) -- .\{-} = non-greedy quantifier
end

---@param startingFromLine? number
function M.commitType(startingFromLine)
	local prefix = startingFromLine and "\\%>" .. startingFromLine .. "l" or ""

	-- not restricted to start of string, so prefixes like the numbering from the
	-- snacks-ui-select do not prevent the highlight
	local commitTypePattern = [[\v\w+(\(.{-}\))?!?]]

	local type = prefix .. commitTypePattern .. [[\ze: ]] -- `\ze`: end of match
	local colonAfterType = prefix .. commitTypePattern .. [[\zs: ]] -- `\zs`: start of match
	vim.fn.matchadd("Keyword", type)
	vim.fn.matchadd("Comment", colonAfterType)
end

--------------------------------------------------------------------------------
return M
