local M = {}

local u = require("tinygit.shared.utils")
--------------------------------------------------------------------------------

---@param prompt string
---@param items any[]
---@param itemFormatter fun(item: any): string
---@param stylingFunc fun()
---@param onChoice fun(item: any, index?: number)
function M.withTelescope(prompt, items, itemFormatter, stylingFunc, onChoice)
	local installed, _ = pcall(require, "telescope")
	if not installed then
		u.notify("telescope.nvim is not installed.", "warn")
		return
	end

	local finders = require("telescope.finders")
	local pickers = require("telescope.pickers")
	local telescopeConf = require("telescope.config").values
	local actionState = require("telescope.actions.state")
	local actions = require("telescope.actions")

	-- INFO implement styling via `autocmd` instead of telescope's `entry_maker`,
	-- since the former is more generic, and can be used for potential other
	-- pickers in the future
	vim.api.nvim_create_autocmd("FileType", {
		desc = "Tinygit: Styling for TelescopeResults",
		once = true,
		pattern = "TelescopeResults",
		callback = stylingFunc,
	})

	local telescopeOpts = {
		layout_strategy = "horizontal",
		layout_config = {
			horizontal = {
				width = { 0.9, max = 100 },
				height = { 0.6, max = 40 },
			},
		},
	}

	-- DOCS https://github.com/nvim-telescope/telescope.nvim/blob/master/developers.md#first-picker
	pickers
		.new(telescopeOpts, {
			prompt_title = prompt,
			sorter = telescopeConf.generic_sorter {},
			finder = finders.new_table {
				results = items,
				entry_maker = function(item)
					local display = itemFormatter(item)
					return { value = item, display = display, ordinal = display }
				end,
			},
			attach_mappings = function(promptBufnr, _)
				actions.select_default:replace(function()
					actions.close(promptBufnr)
					local selection = actionState.get_selected_entry()
					onChoice(selection.value, selection.index)
				end)
				return true -- `true` = keep other mappings from the user
			end,
		})
		:find()
end

--------------------------------------------------------------------------------
return M
