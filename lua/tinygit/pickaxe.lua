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
	local diff = fn.system { "git", "show", hash, "--", filename }
	local diffLines = vim.split(diff, "\n")
	table.remove(diffLines, 1) -- remove header, since shown in window title already
	if u.nonZeroExit(diff) then return end

	-- open new win with diff
	local bufnr = vim.api.nvim_create_buf(true, true)
	vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, diffLines)
	vim.api.nvim_buf_set_name(bufnr, hash .. " " .. filename)
	vim.api.nvim_buf_set_option(bufnr, "modifiable", false)
	vim.api.nvim_buf_set_option(bufnr, "list", false)
	vim.api.nvim_open_win(bufnr, true, {
		width = vim.api.nvim_win_get_width(0),
		height = vim.api.nvim_win_get_height(0) - 2, -- -2 to not obfuscate statusline
		relative = "win",
		row = 0,
		col = 0,
		title = filename .. " @ " .. hash,
		title_pos = "center",
		border = "single",
	})

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
		if not query then return end
		local response = fn.system {
			"git",
			"log", -- DOCS https://git-scm.com/docs/git-log
			"--format=%h\t%s\t%cr\t%cn", -- hash, subject, date, author
			"--pickaxe-regex",
			"--regexp-ignore-case",
			("-S%s"):format(query),
			"--",
			filename,
		}
		response = vim.trim(response)

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
