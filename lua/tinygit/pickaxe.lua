local M = {}
local fn = vim.fn
local u = require("tinygit.utils")
local a = vim.api
local config = require("tinygit.config").config.searchFileHistory
--------------------------------------------------------------------------------

---@class currentPickaxe saves metadata for the current pickaxe operation
---@field hashList string[] list of all hashes where the string was found
---@field filename string
---@field query string search query pickaxed for

---@type currentPickaxe
local currentPickaxe = { hashList = {}, filename = "", query = "" }

--------------------------------------------------------------------------------

---@param commitLine string
---@return string formatted text
local function commitFormatter(commitLine)
	local _, commitMsg, date, author = unpack(vim.split(commitLine, "\t"))
	return table.concat({ commitMsg, date, author }, " · ")
end

---@param commitIdx number index of the selected commit in the list of commits
local function showDiff(commitIdx)
	local hashList = currentPickaxe.hashList
	local hash = hashList[commitIdx]
	local filename = currentPickaxe.filename
	local query = currentPickaxe.query
	local ns = a.nvim_create_namespace("tinygit.pickaxe_diff")

	-- get diff
	local diff = fn.system { "git", "show", hash, "--format=", "--", filename }
	if u.nonZeroExit(diff) then return end
	local diffLines = vim.split(diff, "\n")
	for _ = 1, 4 do -- remove first four lines (irrelevant diff header)
		table.remove(diffLines, 1)
	end
	table.insert(diffLines, 1, "") -- empty line for extmark

	-- remove diff signs and remember line numbers
	local diffAddLines = {}
	local diffDelLines = {}
	local diffPreProcLines = {}
	for i = 1, #diffLines, 1 do
		local line = diffLines[i]
		if line:find("^%+") then
			table.insert(diffAddLines, i - 1)
		elseif line:find("^%-") then
			table.insert(diffDelLines, i - 1)
		elseif line:find("^@@") then
			table.insert(diffPreProcLines, i - 1)
			diffLines[i] = "" -- removing preproc info, since it breaks ft highlighting
		end
		diffLines[i] = diffLines[i]:sub(2)
	end

	-- create new buf with diff
	local bufnr = a.nvim_create_buf(false, true)
	a.nvim_buf_set_lines(bufnr, 0, -1, false, diffLines)
	a.nvim_buf_set_name(bufnr, hash .. " " .. filename)
	a.nvim_buf_set_option(bufnr, "modifiable", false)

	-- open new win for the buff
	local width = math.min(config.diffPopupWidth, 0.99)
	local height = math.min(config.diffPopupHeight, 0.99)

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

	-- Highlighting
	-- INFO not using `diff` filetype, since that would remove filetype-specific highlighting
	local ft = vim.filetype.match { filename = vim.fs.basename(filename) }
	a.nvim_buf_set_option(bufnr, "filetype", ft)

	for _, ln in pairs(diffAddLines) do
		a.nvim_buf_add_highlight(bufnr, ns, "DiffAdd", ln, 0, -1)
	end
	for _, ln in pairs(diffDelLines) do
		a.nvim_buf_add_highlight(bufnr, ns, "DiffDelete", ln, 0, -1)
	end
	for _, ln in pairs(diffPreProcLines) do
		local divider = ("─"):rep(110)
		a.nvim_buf_set_extmark(bufnr, ns, ln, 0, {
			virt_text = { { divider, "PreProc" } },
			virt_text_pos = "overlay",
		})
	end

	-- search for the query
	if query ~= "" then
		fn.matchadd("Search", query) -- highlight, CAVEAT: is case-sensitive
		vim.fn.search(query) -- move cursor
		vim.fn.execute("/" .. query, "silent!") -- insert query so only `n` needs to be pressed
	end

	-- keymaps: info message as extmark
	local infotext =
		"n/N: next/prev occurrence   <Tab>/<S-Tab>: next/prev commit   q: close   yh: yank hash   "
	a.nvim_buf_set_extmark(bufnr, ns, 0, 0, {
		virt_text = { { infotext, "DiagnosticVirtualTextInfo" } },
		virt_text_pos = "overlay",
	})

	-- keymaps: closing
	local keymap = vim.keymap.set
	local opts = { buffer = bufnr, nowait = true }
	local function close()
		a.nvim_win_close(winnr, true)
		a.nvim_buf_delete(bufnr, { force = true })
	end
	keymap("n", "q", close, opts)
	keymap("n", "<Esc>", close, opts)

	-- keymaps: next/prev commit
	keymap("n", "<Tab>", function()
		if commitIdx == #hashList then
			u.notify("Already on last commit", "warn")
			return
		end
		close()
		showDiff(commitIdx + 1)
	end, opts)
	keymap("n", "<S-Tab>", function()
		if commitIdx == 1 then
			u.notify("Already on first commit", "warn")
			return
		end
		close()
		showDiff(commitIdx - 1)
	end, opts)

	-- keymaps: yank hash
	keymap("n", "yh", function()
		vim.fn.setreg("+", hash)
		u.notify("Copied hash: " .. hash)
	end, opts)
end

--------------------------------------------------------------------------------

function M.searchFileHistory()
	if u.notInGitRepo() then return end

	local filename = fn.expand("%")
	vim.ui.input({ prompt = "󰊢 Search File History" }, function(query)
		if not query then return end -- aborted
		local response
		if query == "" then
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
		response = vim.trim(response)
		if response == "" then
			u.notify(('No commits found where "%s" was changed.'):format(query))
			return
		end

		-- save data
		local commits = vim.split(response, "\n")
		local hashList = vim.tbl_map(function(commitLine)
			local hash = vim.split(commitLine, "\t")[1]
			return hash
		end, commits)
		currentPickaxe = {
			hashList = hashList,
			query = query,
			filename = filename,
		}

		-- select
		local searchMode = query == "" and vim.fs.basename(filename) or query
		vim.ui.select(commits, {
			prompt = ("󰊢 Commits that changed '%s'"):format(searchMode),
			format_item = commitFormatter,
			kind = "tinygit.pickaxe_diff",
		}, function(_, commitIdx)
			if not commitIdx then return end -- aborted selection
			showDiff(commitIdx)
		end)
	end)
end

--------------------------------------------------------------------------------
return M
