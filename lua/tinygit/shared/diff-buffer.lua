local M = {}
--------------------------------------------------------------------------------

---@param bufnr number
---@param diffLines string[]
---@param filetype string|nil
---@param sepLength number|false -- false to not draw separators
function M.set(bufnr, diffLines, filetype, sepLength)
	local ns = vim.api.nvim_create_namespace("tinygit.diffBuffer")
	local sepChar = "═"

	-- remove diff header, if the input has it. checking for `@@`, as number of
	-- header lines can vary (e.g., diff to new file are 5 lines, not 4)
	while not vim.startswith(diffLines[1], "@@") do
		table.remove(diffLines, 1)
	end

	-- INFO not using `diff` filetype, since that removes filetype-specific highlighting
	-- prefer only starting treesitter as opposed to setting the buffer filetype,
	-- as this avoid triggering the filetype plugin, which can sometimes entail
	-- undesired effects like LSPs attaching
	if filetype then
		local hasTsParser = pcall(vim.treesitter.start, bufnr, filetype)
		if not hasTsParser then vim.bo[bufnr].filetype = filetype end
	end

	-- remove diff signs and remember line numbers
	local diffAddLines, diffDelLines, diffHunkHeaderLines = {}, {}, {}
	for i = 1, #diffLines do
		local line = diffLines[i]
		local lnum = i - 1
		if line:find("^%+") then
			table.insert(diffAddLines, lnum)
			diffLines[i] = line:sub(2)
		elseif line:find("^%-") then
			table.insert(diffDelLines, lnum)
			diffLines[i] = line:sub(2)
		elseif line:find("^@@") then
			-- remove preproc info and inject the lnum later as inline text
			-- as keeping in the text breaks filetype-highlighting
			local originalLnum, cleanLine = line:match("^@@ %-.- %+(%d+).* @@ ?(.*)")
			diffLines[i] = cleanLine or "" -- nil on new file
			diffHunkHeaderLines[lnum] = originalLnum
		end
	end

	-- set lines
	vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, diffLines)
	vim.bo[bufnr].modifiable = false

	-- add highlights
	for _, ln in pairs(diffAddLines) do
		vim.api.nvim_buf_set_extmark(bufnr, ns, ln, 0, { line_hl_group = "DiffAdd" })
	end
	for _, ln in pairs(diffDelLines) do
		vim.api.nvim_buf_set_extmark(bufnr, ns, ln, 0, { line_hl_group = "DiffDelete" })
	end
	for ln, originalLnum in pairs(diffHunkHeaderLines) do
		vim.api.nvim_buf_set_extmark(bufnr, ns, ln, 0, { line_hl_group = "DiffText" })
		vim.api.nvim_buf_set_extmark(bufnr, ns, ln, 0, {
			virt_text = {
				{ originalLnum .. ":", "diffLine" },
				{ " ", "None" },
			},
			virt_text_pos = "inline",
		})

		-- separator between hunks
		if ln > 1 and sepLength then
			vim.api.nvim_buf_set_extmark(bufnr, ns, ln, 0, {
				virt_lines = { { { sepChar:rep(sepLength), "FloatBorder" } } },
				virt_lines_above = true,
			})
		end
	end

	-- separator below last hunk for clarity
	if sepLength then
		vim.api.nvim_buf_set_extmark(bufnr, ns, #diffLines, 0, {
			virt_lines = { { { sepChar:rep(sepLength), "FloatBorder" } } },
			virt_lines_above = true,
		})
	end
end

--------------------------------------------------------------------------------
return M
