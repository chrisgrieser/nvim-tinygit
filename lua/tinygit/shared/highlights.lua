
local M = {}
--------------------------------------------------------------------------------

-- INFO using namespace in here does not work, therefore simply
-- using `matchadd`, since it is restricted to the current window anyway
-- INFO the order the highlights are added matters, later has priority

local function markupHighlights()
	vim.fn.matchadd("Number", [[#\d\+]]) -- issue number
	vim.fn.matchadd("@markup.raw.markdown_inline", [[`.\{-}`]]) -- .\{-} = non-greedy quantifier
end

---@param mode? "only-markup"
function M.commitMsg(mode)
	markupHighlights()
	if mode == "only-markup" then return end

	---Event though there is a `gitcommit` treesitter parser, we still need to
	---manually mark conventional commits keywords, the parser assume the keyword to
	---be the first word in the buffer, while we want to highlight it in lists of
	---commits or in buffers where the commit message is placee somewhere else.
	local cc = require("tinygit.config").config.commitMsg.conventionalCommits.keywords
	local ccRegex = [[\v(]] .. table.concat(cc, "|") .. [[)(\(.{-}\))?!?\ze: ]]
	vim.fn.matchadd("Title", ccRegex)

	vim.fn.matchadd("WarningMsg", [[\v(fixup|squash)!]])
end

function M.issueText()
	markupHighlights()
	vim.fn.matchadd("DiagnosticError", [[\v[Bb]ug]])
	vim.fn.matchadd("DiagnosticInfo", [[\v[Ff]eature [Rr]equest|FR]])
	vim.fn.matchadd("Comment", [[\vby \w+\s*$]]) -- `\s*` as nvim-notify sometimes adds padding
end

--------------------------------------------------------------------------------
return M
