local M = {}
local u = require("tinygit.shared.utils")
--------------------------------------------------------------------------------

---@alias FileMode "new"|"deleted"|"modified"|"renamed"

---@class (exact) Hunk
---@field absPath string
---@field relPath string
---@field lnum number
---@field added number
---@field removed number
---@field patch string
---@field alreadyStaged boolean
---@field fileMode FileMode

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
	local splitOffDiffHeader = require("tinygit.shared.diff").splitOffDiffHeader

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
		-- split off diff header
		local diffLines = vim.split(file, "\n")
		local changesInFile, diffHeaderLines, fileMode, _ = splitOffDiffHeader(diffLines)
		local diffHeader = table.concat(diffHeaderLines, "\n")
		local relPath = diffHeaderLines[1]:match("b/(.+)") or "ERROR: path not found"
		local absPath = gitroot .. "/" .. relPath

		-- split remaining output into hunks
		local hunksInFile = {}
		for _, line in ipairs(changesInFile) do
			if vim.startswith(line, "@@") then
				table.insert(hunksInFile, line)
			else
				hunksInFile[#hunksInFile] = hunksInFile[#hunksInFile] .. "\n" .. line
			end
		end

		-- special case: file renamed without any other changes
		-- (needs to be handled separately because it has no hunks, that is no `@@` lines)
		if #changesInFile == 0 and fileMode == "renamed" then
			---@type Hunk
			local hunkObj = {
				absPath = absPath,
				relPath = relPath,
				lnum = -1,
				added = 0,
				removed = 0,
				patch = diffHeader .. "\n",
				alreadyStaged = diffIsOfStaged,
				fileMode = fileMode,
			}
			table.insert(hunks, hunkObj)
		end

		-- loop hunks
		for _, hunk in ipairs(hunksInFile) do
			-- meaning of @@-line: https://www.gnu.org/software/diffutils/manual/html_node/Detailed-Unified.html
			local lnum = tonumber(hunk:match("^@@ .- %+(%d+)"))
			assert(lnum, "lnum not found.")

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
				alreadyStaged = diffIsOfStaged,
				fileMode = fileMode,
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
		hunk.alreadyStaged and "--reverse" or nil, -- unstage, if already staged
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
	local setDiffBuffer = require("tinygit.shared.diff").setDiffBuffer

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
					---@type Hunk
					local h = _entry.value
					local renamedWithoutChanges = h.lnum == -1 and h.fileMode == "renamed"

					local name = vim.fs.basename(h.relPath)
					local added = h.added > 0 and (" +" .. h.added) or ""
					local del = h.removed > 0 and (" -" .. h.removed) or ""
					local location = ""
					if h.fileMode == "new" then
						added = added .. " (new file)"
					elseif h.fileMode == "deleted" then
						del = del .. " (deleted file)"
					elseif renamedWithoutChanges then
						location = " (renamed)"
					else
						location = ":" .. h.lnum
						if h.fileMode == "renamed" then location = location .. " (renamed)" end
					end
					local status = h.alreadyStaged and opts.stagedIndicator
						or (" "):rep(vim.api.nvim_strwidth(opts.stagedIndicator))

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
					setDiffBuffer(bufnr, diffLines, ft, false)
				end,
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
					hunks[entry.index].alreadyStaged = not hunks[entry.index].alreadyStaged

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
	u.intentToAddUntrackedFiles() -- include untracked files, enables using `--diff-filter=A`

	local diffArgs =
		{ "git", "-c", "diff.context=" .. getContextSize(), "diff", "--diff-filter=ADMR" }
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
