local M = {}
--------------------------------------------------------------------------------

function M.inlineCodeAndIssueNumbers()
	vim.fn.matchadd("Number", [[#\d\+]])
	vim.fn.matchadd("@markup.raw.markdown_inline", [[`.\{-}`]]) -- .\{-} = non-greedy quantifier
end

---@param startingFromLine? number
function M.commitType(startingFromLine)
	local prefix = startingFromLine and "\\%>" .. startingFromLine .. "l" or ""

	-- TYPE
	-- not restricted to start of string, so prefixes like the numbering from the
	-- `snacks-ui-select` do not prevent the highlight
	local commitTypePattern = [[\v\w+(\(.{-}\))?!?]]
	local commitType = prefix .. commitTypePattern .. [[\ze: ]] -- `\ze`: end of match
	vim.fn.matchadd("@keyword.gitcommit", commitType)
	local colonAfterType = prefix .. commitTypePattern .. [[\zs: ]] -- `\zs`: start of match
	vim.fn.matchadd("Comment", colonAfterType)

	-- SCOPE
	local commitScopeBrackets = prefix .. [[\v\w+\zs(\(.{-}\)\ze): ]] -- matches scope with brackets
	vim.fn.matchadd("Comment", commitScopeBrackets, 10) -- lower prio than scope-matching for simple pattern
	local commitScope = prefix .. [[\v\w+(\(\zs.{-}\ze\)): ]] -- matches scope without brackets
	vim.fn.matchadd("@variable.parameter.gitcommit", commitScope, 11)

	-- BANG
	vim.fn.matchadd("@punctuation.special.gitcommit", [[\v\w+(\(.{-}\))?\zs!\ze: ]])
end

--------------------------------------------------------------------------------
return M
