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
---@field staged boolean already staged

--------------------------------------------------------------------------------

---@return number
local function getContextSize()
	-- CAVEAT for some reason, context=0 results in patches that are not valid.
	-- Using context=1 seems to work, but has the downside of merging hunks that
	-- are only two line apart. Test it: here 0 fails, but 1 works:
	-- `git -c diff.context=0 diff . | git apply --cached --verbose -`
	local contextSize = require("tinygit.config").config.staging.contextSize
	if contextSize < 1 then contextSize = 0 end
	return contextSize
end

---@param diffCmdStdout string
---@param diffIsOfStaged boolean
---@return Hunk[] hunks
local function getHunksFromDiffOutput(diffCmdStdout, diffIsOfStaged)
	if diffCmdStdout == "" then return {} end -- no hunks
	local gitroot = u.syncShellCmd { "git", "rev-parse", "--show-toplevel" }
	local changesPerFile = vim.split(diffCmdStdout, "\ndiff --git a/", { plain = true })

	-- Loop through each file, and then through each hunk of that file. Construct
	-- flattened list of hunks, each with their own diff header, so they work as
	-- independent patches. Those patches in turn are needed for `git apply`
	-- stage only part of a file.
	---@type Hunk[]
	local hunks = {}
	for _, file in ipairs(changesPerFile) do
		if not vim.startswith(file, "diff --git a/") then -- first file still has this
			file = "diff --git a/" .. file -- needed to make patches valid
		end
		-- severe diff header
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
			local lnum = tonumber(hunk:match("^@@ .- %+(%d+)")) or -1

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
				staged = diffIsOfStaged,
			}
			table.insert(hunks, hunkObj)
		end
	end
	return hunks
end

---@param hunk Hunk
---@return boolean success
local function stagingToggleHunk(hunk)
	-- use `git apply` to stage only part of a file https://stackoverflow.com/a/66618356/22114136
	local applyResult = vim.system({
		"git",
		"apply",
		hunk.staged and "--reverse" or nil, -- unstage, if already staged
		"--cached", -- only change staging area, not working tree
		"--verbose", -- better stderr for errors
		"-",
	}, { stdin = hunk.patch }):wait()
	local success = applyResult.code == 0
	if not success then u.notify(applyResult.stderr, "error", "Stage Hunk") end
	return success
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

				-- format: status, filename, lnum, added, removed
				entry.display = function(_entry)
					local h = _entry.value
					local name = vim.fs.basename(h.relPath)
					local added = h.added > 0 and (" +" .. h.added) or ""
					local del = h.removed > 0 and (" -" .. h.removed) or ""
					local status = h.staged and opts.stagedIndicator
						or (" "):rep(vim.api.nvim_strwidth(opts.stagedIndicator))
					local out = status .. name .. ":" .. h.lnum .. added .. del
					local statPos = #status + #name + 1 + #tostring(h.lnum)
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
					-- hunk lnum starts at beginning of context, not change
					local hunkStart = hunk.lnum + getContextSize()
					vim.cmd(("edit +%d %s"):format(hunkStart, hunk.absPath))
				end, { desc = "Goto Hunk" })

				map({ "n", "i" }, opts.keymaps.stagingToggle, function()
					local entry = actionState.get_selected_entry()
					local hunk = entry.value
					local success = stagingToggleHunk(hunk)
					if not success then return end

					-- Change value for selected hunk in cached hunk-list
					hunks[entry.index].staged = not hunks[entry.index].staged

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
				end, { desc = "Staging Toggle" })

				return true -- keep default mappings
			end,
		})
		:find()
end

--------------------------------------------------------------------------------

function M.interactiveStaging()
	vim.cmd("silent! update")

	-- GUARD prerequisites not met
	local installed = pcall(require, "telescope")
	if not installed then
		u.notify("This feature requires `nvim-telescope`.", "warn", "Staging")
		return
	end
	if u.notInGitRepo() then return end
	local noChanges = u.syncShellCmd { "git", "status", "--porcelain" } == ""
	if noChanges then
		u.notify("There are no staged or unstaged changes.", "warn", "Staging")
		return
	end

	-- GET ALL HUNKS
	local diffArgs = { "git", "-c", "diff.context=" .. getContextSize(), "diff", "--diff-filter=M" }
	local changesDiff = u.syncShellCmd(diffArgs)
	local changedHunks = getHunksFromDiffOutput(changesDiff, false)

	table.insert(diffArgs, "--staged")
	local stagedDiff = u.syncShellCmd(diffArgs)
	local stagedHunks = getHunksFromDiffOutput(stagedDiff, true)

	local allHunks = vim.list_extend(changedHunks, stagedHunks)

	-- START TELESCOPE PICKER
	vim.api.nvim_create_autocmd("FileType", {
		once = true,
		pattern = "TelescopeResults",
		callback = function(ctx) require("tinygit.shared.backdrop").new(ctx.buf) end,
	})
	telescopePickHunk(allHunks)
end
--------------------------------------------------------------------------------
return M
