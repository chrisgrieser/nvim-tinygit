local M = {}
local fn = vim.fn
--------------------------------------------------------------------------------

function M.pickaxeCurrentFile()
	local query = "foobar"
	local filename = fn.expand("%")
	fn.system {
		"git",
		"log",
		"--pickaxe-regex",
		"--regexp-ignore-case",
		("-S'%s'"):format(query),
		"--format='%h\t%s\t%cr'",
		"--",
		filename,
	}
end

--------------------------------------------------------------------------------
return M
