local M = {}
local u = require("tinygit.shared.utils")
--------------------------------------------------------------------------------

---@class (exact) Hunk
---@field file string
---@field lnum number
---@field display string
---@field patch string

--------------------------------------------------------------------------------

---@nodiscard
---@return Hunk[]?
local function getHunks()
	-- CAVEAT for some reason, context=0 results in patches that are not valid.
	-- Using context=1 seems to work, but has the downside of merging hunks that
	-- are only two line apart. Test it: here 0 fails, but 1 works:
	-- `git -c diff.context=0 diff . | git apply --cached --verbose -`
	local out = vim.system({ "git", "-c", "diff.context=1", "diff", "--diff-filter=M" }):wait()
	if u.nonZeroExit(out) then return end

	local changesPerFile = vim.split(out.stdout, "diff --git a/", { plain = true })
	table.remove(changesPerFile, 1) -- first item is always an empty string

	-- Loop through each file, and then through each hunk of that file. Construct
	-- flattened list of hunks, each with their own diff header, so they work as
	-- independent patches. Those patches in turn are needed for `git apply`
	-- stage only part of a file.
	---@type Hunk[]
	local hunks = {}
	for _, file in ipairs(changesPerFile) do
		-- severe diff header
		file = "diff --git a/" .. file -- re-add, since needed to make patches valid
		local diffLines = vim.split(file, "\n")
		local relPath = diffLines[3]:sub(7)
		local diffHeader = table.concat(vim.list_slice(diffLines, 1, 4), "\n")

		-- split output into hunks
		local changesInFile = vim.list_slice(diffLines, 5)
		local hunksInFile = {}
		for _, line in ipairs(changesInFile) do
			if vim.startswith(line, "@@") then
				table.insert(hunksInFile, line)
			else
				hunksInFile[#hunksInFile] = hunksInFile[#hunksInFile] .. "\n" .. line
			end
		end

		-- loop hunks
		for _, hunk in ipairs(hunksInFile) do
			local lnum = hunk:match("@@ %-(%d+)")
			local patch = diffHeader .. "\n" .. hunk .. "\n"

			---@type Hunk
			local hunkObj = {
				file = relPath,
				lnum = lnum,
				display = vim.fs.basename(relPath) .. ":" .. lnum,
				patch = patch,
			}
			table.insert(hunks, hunkObj)
		end
	end
	return hunks
end

---@param hunk Hunk
local function applyChange(hunk)
	-- use `git apply` to stage only part of a file
	-- https://stackoverflow.com/a/66618356/22114136
	vim.system(
		{ "git", "apply", "--apply", "--cached", "--verbose", "-" },
		{ stdin = hunk.patch },
		function(out)
			if u.nonZeroExit(out) then return end
			u.notify(hunk.display)
		end
	)
end

---@param hunks Hunk[]
local function pickHunk(hunks)
	local pickers = require("telescope.pickers")
	local telescopeConf = require("telescope.config").values
	local actionState = require("telescope.actions.state")
	local actions = require("telescope.actions")
	local finders = require("telescope.finders")
	local previewers = require("telescope.previewers")

	-- DOCS https://github.com/nvim-telescope/telescope.nvim/blob/master/developers.md
	pickers
		.new({}, {
			prompt_title = "Git Hunks",
			sorter = telescopeConf.generic_sorter {},

			-- DOCS `:help telescope.previewers`
			previewer = previewers.new_buffer_previewer {
				define_preview = function(self, entry)
					local bufnr = self.state.bufnr
					local hunk = entry.value
					local display = vim.list_slice(vim.split(hunk.patch, "\n"), 5)
					vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, display)
					vim.bo[bufnr].filetype = "diff"
				end,
				dyn_title = function(_, entry)
					local hunk = entry.value
					return hunk.file .. ":" .. hunk.lnum
				end,
			},

			finder = finders.new_table {
				results = hunks,
				-- search for filenames, but also changed line contents
				entry_maker = function(hunk)
					local changeLines = vim.iter(vim.split(hunk.patch, "\n"))
						:filter(function(line) return line:match("^[+-]") end)
						:join("\n")
					local matcher = hunk.file .. "\n" .. changeLines
					return { value = hunk, display = hunk.display, ordinal = matcher }
				end,
			},

			attach_mappings = function(prompt_bufnr, _)
				actions.select_default:replace(function()
					local entry = actionState.get_selected_entry()
					local hunk = entry.value
					applyChange(hunk)

					table.remove(hunks, entry.index)
					actions.close(prompt_bufnr)
					if #hunks > 0 then pickHunk(hunks) end -- select next hunk
				end)
				return true -- keep default mappings
			end,
		})
		:find()
end

--------------------------------------------------------------------------------

function M.interactiveStaging()
	vim.cmd("silent update")
	if u.notInGitRepo() or u.hasNoChanges() then return end

	local hunks = getHunks()
	if not hunks then return end

	pickHunk(hunks)
end
--------------------------------------------------------------------------------
return M
