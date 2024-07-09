local M = {}
local u = require("tinygit.shared.utils")
--------------------------------------------------------------------------------

---@class (exact) Hunk
---@field absPath string
---@field relPath string
---@field lnum number
---@field added number
---@field removed number
---@field patch string

--------------------------------------------------------------------------------

---@nodiscard
---@return Hunk[]?
local function getHunks()
	-- CAVEAT for some reason, context=0 results in patches that are not valid.
	-- Using context=1 seems to work, but has the downside of merging hunks that
	-- are only two line apart. Test it: here 0 fails, but 1 works:
	-- `git -c diff.context=0 diff . | git apply --cached --verbose -`
	local contextSize = require("tinygit.config").config.staging.contextSize
	if contextSize < 1 then contextSize = 0 end

	local out =
		vim.system({ "git", "-c", "diff.context=" .. contextSize, "diff", "--diff-filter=M" }):wait()
	if u.nonZeroExit(out) then return end

	local gitroot = u.syncShellCmd { "git", "rev-parse", "--show-toplevel" }

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
		local absPath = gitroot .. "/" .. relPath
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
			-- meaning of @@-line: https://www.gnu.org/software/diffutils/manual/html_node/Detailed-Unified.html
			local lnum = tonumber(hunk:match("^@@ .- %+(%d+)")) + contextSize

			-- not from `@@` line, since number includes lines between two changes and context lines
			local _, added = hunk:gsub("\n%+", "")
			local _, removed = hunk:gsub("\n%-", "")

			-- needs trailing newline for valid patch
			local patch = diffHeader .. "\n" .. hunk .. "\n"

			---@type Hunk
			local hunkObj = {
				absPath = absPath,
				relPath = relPath,
				lnum = lnum,
				added = added,
				removed = removed,
				patch = patch,
			}
			table.insert(hunks, hunkObj)
		end
	end
	return hunks
end

---@param hunk Hunk
local function stageHunk(hunk)
	-- use `git apply` to stage only part of a file https://stackoverflow.com/a/66618356/22114136
	vim.system(
		{ "git", "apply", "--apply", "--cached", "--verbose", "-" },
		{ stdin = hunk.patch },
		function(out)
			if out.code ~= 0 then u.notify(out.stderr, "error", "Stage Hunk") end
		end
	)
end

---@param hunks Hunk[]
local function telescopePickHunk(hunks)
	local pickers = require("telescope.pickers")
	local telescopeConf = require("telescope.config").values
	local actionState = require("telescope.actions.state")
	local actions = require("telescope.actions")
	local finders = require("telescope.finders")
	local previewers = require("telescope.previewers")

	local opts = require("tinygit.config").config.staging
	local diffBuf = require("tinygit.shared.diff-buffer")

	---@param _hunks Hunk[]
	local function newFinder(_hunks)
		return finders.new_table {
			results = _hunks,
			entry_maker = function(hunk)
				local entry = { value = hunk }

				-- search for filenames, but also changed line contents
				local changeLines = vim.iter(vim.split(hunk.patch, "\n"))
					:filter(function(line) return line:match("^[+-]") end)
					:join("\n")
				entry.ordinal = hunk.relPath .. "\n" .. changeLines

				-- format: filename, lnum, added, removed
				-- (and colored components)
				entry.display = function(_entry)
					local h = _entry.value
					local name = vim.fs.basename(h.relPath)
					local addedStr = h.added > 0 and (" +" .. h.added) or ""
					local removedStr = h.removed > 0 and (" -" .. h.removed) or ""
					local out = name .. ":" .. h.lnum .. addedStr .. removedStr
					local diffStatPos = #name + #tostring(h.lnum) + 2
					local highlights = {
						{ { #name, diffStatPos - 1 }, "Comment" },
						{ { diffStatPos, diffStatPos + #addedStr }, "diffAdded" },
						{ { #out - #removedStr, #out }, "diffRemoved" },
					}
					return out, highlights
				end

				return entry
			end,
		}
	end

	-- DOCS https://github.com/nvim-telescope/telescope.nvim/blob/master/developers.md
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
				define_preview = function(self, entry)
					local bufnr = self.state.bufnr
					local hunk = entry.value
					local diffLines = vim.split(hunk.patch, "\n")
					local ft = vim.filetype.match { filename = vim.fs.basename(hunk.relPath) }
					diffBuf.set(bufnr, diffLines, ft, false)
				end,
				dyn_title = function(_, entry)
					local hunk = entry.value
					return hunk.relPath .. (" (+%d -%d)"):format(hunk.added, hunk.removed)
				end,
			},

			attach_mappings = function(prompt_bufnr, map)
				map({ "n", "i" }, opts.keymaps.gotoHunk, function()
					local hunk = actionState.get_selected_entry().value
					actions.close(prompt_bufnr)
					vim.cmd(("edit +%d %s"):format(hunk.lnum, hunk.absPath))
				end, { desc = "Goto Hunk" })

				map({ "n", "i" }, opts.keymaps.stageHunk, function()
					local entry = actionState.get_selected_entry()
					local hunk = entry.value
					stageHunk(hunk)
					table.remove(hunks, entry.index)

					if #hunks > 0 then
						local picker = actionState.get_current_picker(prompt_bufnr)
						picker:refresh(newFinder(hunks), { reset_prompt = false })
					else
						actions.close(prompt_bufnr)
					end
				end, { desc = "Stage Hunk" })

				return true -- keep default mappings
			end,
		})
		:find()
end

--------------------------------------------------------------------------------

function M.interactiveStaging()
	vim.cmd("silent update")

	-- GUARD
	local installed = pcall(require, "telescope")
	if not installed then
		u.notify("This feature requires `nvim-telescope`.", "warn", "Staging")
		return
	end
	if u.notInGitRepo() then return end
	local hasNoUnstagedChanges = vim.system({ "git", "diff", "--quiet" }):wait().code == 0
	if hasNoUnstagedChanges then
		u.notify("There are no unstaged changes.", "warn", "Staging")
		return
	end

	local hunks = getHunks()
	if not hunks then return end

	-- backdrop
	vim.api.nvim_create_autocmd("FileType", {
		once = true,
		pattern = "TelescopeResults",
		callback = function(ctx) require("tinygit.shared.backdrop").new(ctx.buf) end,
	})

	telescopePickHunk(hunks)
end
--------------------------------------------------------------------------------
return M
