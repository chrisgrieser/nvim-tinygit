local M = {}
--------------------------------------------------------------------------------

---@enum (key) Tinygit.FileMode
local FILEMODES = {
	new = 0,
	deleted = 1,
	modified = 2,
	renamed = 3,
	binary = 4,
	line_or_function_history = 5,
}

--------------------------------------------------------------------------------

-- remove diff header, if the input has it. checking for `@@`, as number of
-- header lines can vary (e.g., diff to new file are 5 lines, not 4)
---@param diffLines string[]
---@return string[] headerLines
---@return string[] outputWithoutHeader
---@return Tinygit.FileMode fileMode
---@return { from?: string, to?: string } rename
---@nodiscard
function M.splitOffDiffHeader(diffLines)
	local headerLines = {}
	while not vim.startswith(diffLines[1], "@@") do
		local headerLine = table.remove(diffLines, 1)
		table.insert(headerLines, headerLine)
		if #diffLines == 0 then break end -- renamed file without changes have no `@@`
	end

	local fileMode = headerLines[2]:match("^(%w+) file") or headerLines[3]:match("^(%w+) file")
	local rename = {}
	if not fileMode and headerLines[4] then
		rename.from = headerLines[3]:match("^rename from (.+)$")
		rename.to = headerLines[4]:match("^rename to (.+)$")
		fileMode = rename.from and "renamed" or "modified"
	elseif not fileMode and not headerLines[4] then
		fileMode = "line_or_function_history"
	end
	if fileMode then fileMode = fileMode:lower() end

	assert(
		vim.tbl_contains(vim.tbl_keys(FILEMODES), fileMode),
		"Unknown file mode, please create an issue: " .. fileMode
	)

	return diffLines, headerLines, fileMode, rename
end

--------------------------------------------------------------------------------

---@param bufnr number
---@param diffLinesWithHeader string[]
---@param filetype string|nil
---@param sepLength number|false -- false to not draw separators
function M.setDiffBuffer(bufnr, diffLinesWithHeader, filetype, sepLength)
	local ns = vim.api.nvim_create_namespace("tinygit.diffBuffer")
	local sepChar = "┄"
	local sepHlGroup = "Comment"
	local diffLines, _, fileMode, rename = M.splitOffDiffHeader(diffLinesWithHeader)

	-- context line is useless in this case
	if fileMode == "deleted" or fileMode == "new" then
		table.remove(diffLines, 1)
	elseif fileMode == "renamed" then
		-- dummy blanks for virtual text, as nvim does not support placing a
		-- virtual line above the first line
		table.insert(diffLines, 1, "")
		table.insert(diffLines, 1, "")
	end

	-- remove diff signs and remember line numbers
	local diffAddLines, diffDelLines, diffHunkHeaderLines = {}, {}, {}
	for i = 1, #diffLines do
		local line = diffLines[i]
		local lnum = i - 1
		if line:find("^%+") then
			table.insert(diffAddLines, lnum)
		elseif line:find("^%-") then
			table.insert(diffDelLines, lnum)
		elseif line:find("^@@") then
			-- remove preproc info and inject the lnum later as inline text
			-- as keeping in the text breaks filetype-highlighting
			local originalLnum, cleanLine = line:match("^@@ %-.- %+(%d+).* @@ ?(.*)")
			diffLines[i] = cleanLine or "" -- nil on new file
			diffHunkHeaderLines[lnum] = originalLnum
		end
		if not line:find("^@@") then diffLines[i] = line:sub(2) end
	end

	-- set lines & buffer properties
	vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, diffLines)
	vim.bo[bufnr].modifiable = false
	if filetype then
		local hasTsParser = pcall(vim.treesitter.start, bufnr, filetype)
		if not hasTsParser then vim.bo[bufnr].filetype = filetype end
	end

	-- add highlights
	for _, ln in pairs(diffAddLines) do
		vim.api.nvim_buf_set_extmark(bufnr, ns, ln, 0, { line_hl_group = "DiffAdd" })
	end
	for _, ln in pairs(diffDelLines) do
		vim.api.nvim_buf_set_extmark(bufnr, ns, ln, 0, { line_hl_group = "DiffDelete" })
	end
	if fileMode == "renamed" then
		vim.api.nvim_buf_set_extmark(bufnr, ns, 0, 0, {
			virt_text = { { ("renamed from %q"):format(rename.from), "Comment" } },
			virt_text_pos = "inline",
		})
		vim.api.nvim_buf_set_extmark(bufnr, ns, 1, 0, {
			virt_text = { { ("to %q"):format(rename.to), "Comment" } },
			virt_text_pos = "inline",
		})
	end
	for ln, originalLnum in pairs(diffHunkHeaderLines) do
		vim.api.nvim_buf_set_extmark(bufnr, ns, ln, 0, {
			virt_text = {
				{ originalLnum .. ":", "diffLine" },
				{ " " },
			},
			virt_text_pos = "inline",
			line_hl_group = "DiffText",
		})

		-- separator between hunks
		if ln > 1 and sepLength then
			vim.api.nvim_buf_set_extmark(bufnr, ns, ln, 0, {
				virt_lines = {
					{ { sepChar:rep(sepLength), sepHlGroup } },
				},
				virt_lines_above = true,
			})
		end
	end

	-- separator below last hunk for clarity
	if sepLength then
		vim.api.nvim_buf_set_extmark(bufnr, ns, #diffLines, 0, {
			virt_lines = {
				{ { sepChar:rep(sepLength), sepHlGroup } },
			},
			virt_lines_above = true,
		})
	end
end

--------------------------------------------------------------------------------
return M
