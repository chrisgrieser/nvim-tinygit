local M = {}
--------------------------------------------------------------------------------

---@param bufnr number
---@param diffLines string[]
---@param filetype string
---@param sepLength number|false -- false to not draw separators
function M.setDiffBuffer(bufnr, diffLines, filetype, sepLength)
	local ns = vim.api.nvim_create_namespace("tinygit.diffBuffer")
	if not sepLength then sepLength = 20 end
	local sepChar = "═"

	-- INFO not using `diff` filetype, since that removes filetype-specific highlighting
	-- prefer only starting treesitter as opposed to setting the buffer filetype,
	-- as this avoid triggering the filetype plugin, which can sometimes entail
	-- undesired effects like LSPs attaching
	local hasTsParser = pcall(vim.treesitter.start, bufnr, filetype)
	if not hasTsParser then vim.api.nvim_set_option_value("filetype", filetype, { buf = bufnr }) end

	for _ = 1, 4 do -- remove first four lines (irrelevant diff header)
		table.remove(diffLines, 1)
	end

	-- remove diff signs and remember line numbers
	local diffAddLines = {}
	local diffDelLines = {}
	local diffHunkHeaderLines = {}
	for i = 1, #diffLines do
		local line = diffLines[i]
		local lnum = i - 1
		if line:find("^%+") then
			table.insert(diffAddLines, lnum)
		elseif line:find("^%-") then
			table.insert(diffDelLines, lnum)
		elseif line:find("^@@") then
			-- remove preproc info and inject it alter as inline text,
			-- as keeping in the text breaks filetype-highlighting
			local preprocInfo, cleanLine = line:match("^(@@.-@@)(.*)")
			diffLines[i] = cleanLine
			diffHunkHeaderLines[lnum] = preprocInfo
		end
		diffLines[i] = diffLines[i]:sub(2)
	end

	-- set lines
	vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, diffLines)
	vim.bo[bufnr].modifiable = false

	-- add highlights
	for _, ln in pairs(diffAddLines) do
		vim.api.nvim_buf_add_highlight(bufnr, ns, "DiffAdd", ln, 0, -1)
	end
	for _, ln in pairs(diffDelLines) do
		vim.api.nvim_buf_add_highlight(bufnr, ns, "DiffDelete", ln, 0, -1)
	end
	for ln, preprocInfo in pairs(diffHunkHeaderLines) do
		vim.api.nvim_buf_add_highlight(bufnr, ns, "DiffText", ln, 0, -1)

		-- add preproc info
		vim.api.nvim_buf_set_extmark(bufnr, ns, ln, 0, {
			virt_text = { { preprocInfo .. " ", "DiffText" } },
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
