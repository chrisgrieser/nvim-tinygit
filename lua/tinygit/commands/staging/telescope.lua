local M = {}

local pickers = require("telescope.pickers")
local telescopeConf = require("telescope.config").values
local actionState = require("telescope.actions.state")
local actions = require("telescope.actions")
local finders = require("telescope.finders")
local previewers = require("telescope.previewers")

local staging = require("tinygit.commands.staging")
local conf = require("tinygit.config").config.stage
local setDiffBuffer = require("tinygit.shared.diff").setDiffBuffer
--------------------------------------------------------------------------------

---@param hunks Tinygit.Hunk[]
local function newFinder(hunks)
	return finders.new_table {
		results = hunks,
		entry_maker = function(hunk)
			local entry = { value = hunk }

			-- search for filenames, but also changed line contents
			local changeLines = vim.iter(vim.split(hunk.patch, "\n"))
				:filter(function(line) return line:match("^[+-]") end)
				:join("\n")
			entry.ordinal = hunk.relPath .. "\n" .. changeLines

			-- format: status, filename, lnum, added, removed
			entry.display = function(_entry)
				---@type Tinygit.Hunk
				local h = _entry.value
				local changeWithoutHunk = h.lnum == -1

				local name = vim.fs.basename(h.relPath)
				local added = h.added > 0 and (" +" .. h.added) or ""
				local del = h.removed > 0 and (" -" .. h.removed) or ""
				local location = ""
				if h.fileMode == "new" then
					added = added .. " (new file)"
				elseif h.fileMode == "deleted" then
					del = del .. " (deleted file)"
				elseif changeWithoutHunk then
					location = h.fileMode == "binary" and " (binary)" or " (renamed)"
				else
					location = ":" .. h.lnum
					if h.fileMode == "renamed" then location = location .. " (renamed)" end
				end
				local status = h.alreadyStaged and conf.stagedIndicator
					or (" "):rep(vim.api.nvim_strwidth(conf.stagedIndicator))
				status = status .. " " -- padding

				local out = status .. name .. location .. added .. del
				local statPos = #status + #name + #location
				local highlights = {
					{ { 0, 1 }, "diffChanged" }, -- status
					{ { #status + #name, statPos }, "Comment" }, -- lnum
					{ { statPos, statPos + #added }, "diffAdded" }, -- added
					{ { statPos + #added + 1, statPos + #added + #del }, "diffRemoved" }, -- removed
				}

				return out, highlights
			end

			return entry
		end,
	}
end

---@param hunks Tinygit.Hunk[]
---@param prompt_bufnr number
local function refreshPicker(hunks, prompt_bufnr)
	-- temporarily register a callback which keeps selection on refresh
	-- SOURCE https://github.com/nvim-telescope/telescope.nvim/blob/bfcc7d5c6f12209139f175e6123a7b7de6d9c18a/lua/telescope/builtin/__git.lua#L412-L421
	local picker = actionState.get_current_picker(prompt_bufnr)
	local selection = picker:get_selection_row()
	local callbacks = { unpack(picker._completion_callbacks) } -- shallow copy
	picker:register_completion_callback(function(self)
		self:set_selection(selection)
		self._completion_callbacks = callbacks
	end)

	picker:refresh(newFinder(hunks), { reset_prompt = false })
end

---@param absPath string
---@return string|nil ft
local function getFiletype(absPath)
	local ft = vim.filetype.match { filename = vim.fs.basename(absPath) }
	if ft then return ft end

	-- In some cases, the filename alone is not unambiguous (like `.ts` files for
	-- typescript), so we need the actual buffer to determine the filetype.
	local bufnr = vim.iter(vim.api.nvim_list_bufs())
		:find(function(buf) return vim.api.nvim_buf_get_name(buf) == absPath end)
	if bufnr then return vim.filetype.match { buf = bufnr } end

	-- If there are changes in files that are not loaded as buffer, we have to
	-- add file to a buffer to be able to determine the filetype from it.
	bufnr = vim.fn.bufadd(absPath)
	return vim.filetype.match { buf = bufnr }
end

--------------------------------------------------------------------

-- DOCS https://github.com/nvim-telescope/telescope.nvim/blob/master/developers.md
---@param hunks Tinygit.Hunk[]
function M.pickHunk(hunks)
	pickers
		.new({}, {
			prompt_title = "Git Hunks",
			sorter = telescopeConf.generic_sorter {},

			layout_strategy = "horizontal",
			layout_config = {
				horizontal = {
					preview_width = 0.65,
					height = { 0.7, min = 20 },
				},
			},

			finder = newFinder(hunks),

			-- DOCS `:help telescope.previewers`
			previewer = previewers.new_buffer_previewer {
				---@param self table
				---@param entry { value: Tinygit.Hunk }
				define_preview = function(self, entry)
					local bufnr = self.state.bufnr
					local hunk = entry.value
					local diffLines = vim.split(hunk.patch, "\n")
					local ft = getFiletype(hunk.absPath)
					setDiffBuffer(bufnr, diffLines, ft, false)
				end,
				---@param entry { value: Tinygit.Hunk }
				dyn_title = function(_, entry)
					local hunk = entry.value
					if hunk.added + hunk.removed == 0 then return hunk.relPath end -- renamed w/o changes
					local stats = ("(+%d -%d)"):format(hunk.added, hunk.removed)
					if hunk.added == 0 then stats = ("(-%d)"):format(hunk.removed) end
					if hunk.removed == 0 then stats = ("(+%d)"):format(hunk.added) end
					return hunk.relPath .. " " .. stats
				end,
			},

			attach_mappings = function(prompt_bufnr, map)
				map({ "n", "i" }, conf.keymaps.gotoHunk, function()
					local hunk = actionState.get_selected_entry().value
					actions.close(prompt_bufnr)
					-- hunk lnum starts at beginning of context, not change
					local hunkStart = hunk.lnum + staging.getContextSize()
					vim.cmd(("edit +%d %s"):format(hunkStart, hunk.absPath))
				end, { desc = "Goto Hunk" })

				map({ "n", "i" }, conf.keymaps.stagingToggle, function()
					local entry = actionState.get_selected_entry()
					local hunk = entry.value
					local success = staging.applyPatch(hunk, "toggle")
					if success then
						-- Change value for selected hunk in cached hunk-list
						hunks[entry.index].alreadyStaged = not hunks[entry.index].alreadyStaged
						if conf.moveToNextHunkOnStagingToggle then
							actions.move_selection_next(prompt_bufnr)
						end
						refreshPicker(hunks, prompt_bufnr)
					end
				end, { desc = "Staging Toggle" })

				map({ "n", "i" }, conf.keymaps.resetHunk, function()
					local entry = actionState.get_selected_entry()
					local hunk = entry.value

					-- a staged hunk cannot be reset, so we unstage it first
					if hunk.alreadyStaged then
						local success1 = staging.applyPatch(hunk, "toggle")
						if not success1 then return end
						hunk.alreadyStaged = false
					end

					local success2 = staging.applyPatch(hunk, "reset")
					if not success2 then return end
					table.remove(hunks, entry.index) -- remove from list as not a hunk anymore
					refreshPicker(hunks, prompt_bufnr)
				end, { desc = "Reset Hunk" })

				return true -- keep default mappings
			end,
		})
		:find()
end

--------------------------------------------------------------------------------
return M
