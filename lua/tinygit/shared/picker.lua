local M = {}
--------------------------------------------------------------------------------

---@param prompt string
---@param items any[]
---@param itemFormatter fun(item: any): string
---@param stylingFunc fun()
---@param onChoice fun(item: any, index?: number)
function M.pick(prompt, items, itemFormatter, stylingFunc, onChoice)
	-- Add some basic styling & backdrop, if using `telescope` or `snacks.picker`
	local autocmd = vim.api.nvim_create_autocmd("FileType", {
		desc = "Tinygit: Styling for TelescopeResults",
		once = true,
		pattern = { "TelescopeResults", "snacks_picker_list" },
		callback = function(ctx)
			vim.schedule(function() vim.api.nvim_buf_call(ctx.buf, stylingFunc) end)
			require("tinygit.shared.backdrop").new(ctx.buf)
		end,
	})

	vim.ui.select(items, {
		prompt = prompt,
		format_item = itemFormatter,
	}, function(selection, index)
		if selection then onChoice(selection, index) end
		vim.api.nvim_del_autocmd(autocmd)
	end)
end

--------------------------------------------------------------------------------
return M
