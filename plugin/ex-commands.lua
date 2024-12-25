-- CAVEAT this is a simple version of an ex-command which does not accept
-- command-specific arguments and does not detect visual mode yet

vim.api.nvim_create_user_command("Tinygit", function(ctx) require("tinygit")[ctx.args]() end, {
	nargs = 1,
	complete = function(query)
		local subcommands = vim.tbl_keys(require("tinygit").cmdToModuleMap)
		return vim.tbl_filter(function(op) return op:lower():find(query, nil, true) end, subcommands)
	end,
})
