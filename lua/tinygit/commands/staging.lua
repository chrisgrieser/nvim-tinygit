local M = {}
local u = require("tinygit.shared.utils")
--------------------------------------------------------------------------------

function M.interactiveStaging()
	vim.cmd("silent! update")

	-- CAVEAT for some reason, context=0 results in patches that are not valid.
	-- Using context=1 seems to work, but has the downside of merging hunks that
	-- are only two line apart. Test it: here 0 fails, but 1 works:
	-- `git -c diff.context=0 diff . | git apply --cached --verbose -`
	local out = vim.system({ "git", "-c", "diff.context=1", "diff", "--diff-filter=M" }):wait()
	if out.code ~= 0 then
		u.notify("error", out.stderr, "Staging")
		return
	end
	local changesPerFile = vim.split(out.stdout, "diff --git a/", { plain = true })
	table.remove(changesPerFile, 1) -- first item is always an empty string

	-- Loop through each file, and then through each hunk of that file. Construct
	-- flattened list of hunks, each with their own diff header, so they work as
	-- independent patches. Those patches in turn are needed for `git apply`
	-- stage only part of a file.
	local hunks = {}
	for _, file in ipairs(changesPerFile) do
		-- severe diff header
		file = "diff --git a/" .. file
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
			table.insert(hunks, {
				file = relPath,
				lnum = lnum,
				display = vim.fs.basename(relPath) .. ":" .. lnum,
				patch = patch,
			})
		end
	end

	-----------------------------------------------------------------------------
	-- select from hunks & preview the hunk
	vim.ui.select(hunks, {
		prompt = "Git Hunks",
		format_item = function(hunk) return hunk.display end,
		telescope = {
			previewer = require("telescope.previewers").new_buffer_previewer {
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
			finder = require("telescope.finders").new_table {
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
		},
	}, function(hunk)
		if not hunk then return end

		-- use `git apply` to stage only part of a file, see https://stackoverflow.com/a/66618356/22114136
		local out2 = vim.system(
			{ "git", "apply", "--apply", "--cached", "--verbose", "-" },
			{ stdin = hunk.patch }
		):wait()
		if u.nonZeroExit(out2) then return end

		u.notify("git", hunk.display)
		if #hunks > 1 then M.gitChanges() end -- call itself to continue staging
	end)
end
--------------------------------------------------------------------------------
return M
