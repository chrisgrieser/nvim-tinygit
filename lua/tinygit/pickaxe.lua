local M = {}
local fn = vim.fn
local u = require("tinygit.utils")
--------------------------------------------------------------------------------

---@param commitLine string
---@return string formatted as: "commitMsg (date)"
local function commitFormatter(commitLine)
	local _, commitMsg, date, author = unpack(vim.split(commitLine, "\t"))
	return ("%s\t%s\t"):format(commitMsg, date, author)
end

---https://www.reddit.com/r/neovim/comments/oxddk9/comment/h7maerh/
---@param name string name of highlight group
---@param key "fg"|"bg"
---@nodiscard
---@return string|nil the value, or nil if hlgroup or key is not available
local function getHighlightValue(name, key)
	local ok, hl = pcall(vim.api.nvim_get_hl, 0, { name = name })
	if not ok then return end
	local value = hl[key]
	if not value then return end
	return string.format("#%06x", value)
end

--------------------------------------------------------------------------------

---@param hash string
---@param filename string
---@param query string
local function showDiff(hash, filename, query)
	-- get diff
	local diff = fn.system { "git", "show", hash, "--format=", "--", filename }
	if u.nonZeroExit(diff) then return end
	local diffLines = vim.split(diff, "\n")
	for _ = 1, 4, 1 do -- remove first four lines (irrelevant diff header)
		table.remove(diffLines, 1)
		table.insert(diffLines, 1, "") -- empty line for extmark
	end

	-- open new win with diff
	local height = 0.8
	local width = 0.8
	local bufnr = a.nvim_create_buf(true, true)
	a.nvim_buf_set_lines(bufnr, 0, -1, false, diffLines)
	a.nvim_buf_set_name(bufnr, hash .. " " .. filename)
	a.nvim_buf_set_option(bufnr, "modifiable", false)
	local winnr = a.nvim_open_win(bufnr, true, {
		relative = "win",
		-- center of current win
		width = math.floor(width * a.nvim_win_get_width(0)),
		height = math.floor(height * a.nvim_win_get_height(0)),
		row = math.floor((1 - height) * a.nvim_win_get_height(0) / 2),
		col = math.floor((1 - width) * a.nvim_win_get_width(0) / 2),
		title = filename .. " @ " .. hash,
		title_pos = "center",
		border = "single",
		style = "minimal",
		zindex = 1, -- below nvim-notify floats
	})
	a.nvim_win_set_option(winnr, "list", false)
	a.nvim_win_set_option(winnr, "signcolumn", "no")

	-- keymaps
	vim.keymap.set("n", "q", vim.cmd.close, { buffer = bufnr, nowait = true })
	vim.keymap.set("n", "<Esc>", vim.cmd.close, { buffer = bufnr, nowait = true })

	-- filetype-specific highlighting
	local ft = vim.filetype.match { filename = filename }
	vim.api.nvim_buf_set_option(bufnr, "filetype", ft)

	-- diff-highlighting
	-- INFO not using `diff` filetype, since that would remove filetype-specific highlighting
	-- INFO highlights from `matchadd` are restricted to the current window
	fn.matchadd("DiffAdd", "^+.*")
	fn.matchadd("DiffDelete", "^-.*")
	fn.matchadd("PreProc", "^@@.*")

	local addBg = getHighlightValue("DiffAdd", "bg")
	local delBg = getHighlightValue("DiffDelete", "bg")
	local fg = getHighlightValue("Comment", "fg")
	fn.matchadd("DiffAdd_", "^+++.*")
	fn.matchadd("DiffDelete_", "^---.*")
	vim.api.nvim_set_hl(0, "DiffAdd_", { fg = fg, bg = addBg })
	vim.api.nvim_set_hl(0, "DiffDelete_", { fg = fg, bg = delBg })

	-- search for the query
	fn.matchadd("Search", query) -- highlight, CAVEAT: is case-sensitive
	vim.fn.search(query) -- move cursor
	vim.fn.execute("/" .. query, "silent!") -- insert query so only `n` needs to be pressed
end

function M.searchFileHistory()
	if u.notInGitRepo() then return end

	local filename = fn.expand("%")
	vim.ui.input({ prompt = "󰊢 Search File History" }, function(query)
		if not query then return end -- aborted
		local response
		if query == "" then
			-- empty query
			response = fn.system { "git", "log", "--format=%h\t%s\t%cr\t%cn", "--", filename }
		else
			response = fn.system {
				"git",
				"log",
				"--format=%h\t%s\t%cr\t%cn", -- format: hash, subject, date, author
				"--pickaxe-regex",
				"--regexp-ignore-case",
				("-S%s"):format(query),
				"--",
				filename,
			}
		end

		-- guards
		if u.nonZeroExit(response) then return end
		if response == "" then
			u.notify(("No commits found for '%s'"):format(query))
			return
		end

		local commits = vim.split(response, "\n")
		vim.ui.select(commits, {
			prompt = "󰊢 Select Commit",
			format_item = commitFormatter,
			kind = "commit_selection",
		}, function(selectedCommit)
			if not selectedCommit then return end -- aborted selection
			local hash = vim.split(selectedCommit, "\t")[1]
			showDiff(hash, filename, query)
		end)
	end)
end

--------------------------------------------------------------------------------
return M
