local backdrop = require("tinygit.shared.backdrop")
local highlight = require("tinygit.shared.highlights")
local u = require("tinygit.shared.utils")

local M = {}

local state = {
	abortedCommitMsg = {}, ---@type table<string, string[]> -- saves message per cwd
	winid = -1,
	bufnr = -1,
}

local MAX_TITLE_LEN = 72
--------------------------------------------------------------------------------

---@param msg string
local function warn(msg) u.notify(msg, "warn", { title = "Commit message" }) end

---@param confirmationCallback fun(commitTitle: string, commitBody?: string)
local function setupKeymaps(confirmationCallback)
	local bufnr = state.bufnr
	local conf = require("tinygit.config").config.commit
	local function map(mode, lhs, rhs)
		vim.keymap.set(mode, lhs, rhs, { buffer = bufnr, nowait = true })
	end

	-----------------------------------------------------------------------------

	map("n", conf.keymaps.normal.abort, function()
		-- save msg
		if state.mode ~= "amend" then
			local cwd = vim.uv.cwd() or ""
			state.abortedCommitMsg[cwd] = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
			vim.defer_fn(
				function() state.abortedCommitMsg[cwd] = nil end,
				1000 * conf.keepAbortedMsgSecs
			)
		end

		vim.cmd.bwipeout(bufnr)
	end)

	-----------------------------------------------------------------------------

	local function confirm()
		-- validate commit title
		local commitTitle = vim.trim(vim.api.nvim_buf_get_lines(bufnr, 0, 1, false)[1])
		if #commitTitle > MAX_TITLE_LEN then
			warn("Title is too long.")
			return
		end
		if #commitTitle == 0 then
			warn("Title is empty.")
			return
		end
		if conf.conventionalCommits.enforce then
			local firstWord = commitTitle:match("^%w+")
			if not vim.tbl_contains(conf.conventionalCommits.keywords, firstWord) then
				warn("Not using a Conventional Commits keyword.")
				return
			end
		end

		-- confirm
		local bodytext = vim
			.iter(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false))
			:skip(1) -- skip title
			:join("\n") -- join for shell command
		local commitBody = vim.trim(bodytext) ~= "" and vim.trim(bodytext) or nil
		confirmationCallback(commitTitle, commitBody)

		-- close win
		vim.cmd.bwipeout(bufnr)
	end

	map("n", conf.keymaps.normal.confirm, confirm)
	map("i", conf.keymaps.insert.confirm, confirm)
end

---@param borderChar string
local function setupTitleCharCount(borderChar)
	local bufnr, winid = state.bufnr, state.winid

	local function updateTitleCharCount()
		local titleChars = vim.api.nvim_buf_get_lines(bufnr, 0, 1, false)[1]:len()
		local countHighlight = titleChars <= MAX_TITLE_LEN and "FloatBorder" or "ErrorMsg"

		local winConf = vim.api.nvim_win_get_config(winid)
		winConf.footer[#winConf.footer - 2] = { titleChars < 10 and borderChar or "", "FloatBorder" }
		winConf.footer[#winConf.footer - 1] = { " " .. tostring(titleChars), countHighlight }

		vim.api.nvim_win_set_config(winid, winConf)
	end

	updateTitleCharCount() -- initialize
	vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
		desc = "Tinygit: update char count in input window",
		buffer = bufnr,
		callback = updateTitleCharCount,
	})
end

local function setupUnmount()
	vim.api.nvim_create_autocmd("WinLeave", {
		desc = "Tinygit: unmount of commit message input window",
		callback = function()
			local curWin = vim.api.nvim_get_current_win()
			if curWin == state.winid then
				vim.cmd.bwipeout(state.bufnr)
				return true -- deletes this autocmd
			end
		end,
	})
end

local function setupSeparator(width)
	local function updateSeparator()
		local ns = vim.api.nvim_create_namespace("tinygit.commitMsgInput")
		vim.api.nvim_buf_clear_namespace(state.bufnr, ns, 0, -1)
		local separator = { char = "┄", hlgroup = "Comment" }

		vim.api.nvim_buf_set_extmark(state.bufnr, ns, 0, 0, {
			virt_lines = {
				{ { separator.char:rep(width), separator.hlgroup } },
			},
			virt_lines_leftcol = true,
		})
	end
	updateSeparator() -- initialize

	-- ensure the separator is always there, even if user has deleted first line
	vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
		desc = "Tinygit: update separator in input window",
		buffer = state.bufnr,
		callback = updateSeparator,
	})
end

--------------------------------------------------------------------------------

---@param mode "commit"|"amend"
---@param prompt string
---@param confirmationCallback fun(commitTitle: string, commitBody?: string)
function M.new(mode, prompt, confirmationCallback)
	-- PARAMS
	local conf = require("tinygit.config").config.commit
	local icon = require("tinygit.config").config.appearance.mainIcon
	local width = MAX_TITLE_LEN + 2
	local borderChar = conf.border == "double" and "═" or "─"
	local height = 4
	prompt = vim.trim(icon .. "  " .. prompt)

	-- PREFILL
	local msgLines = {}
	if mode == "amend" then
		local lastCommitTitle = u.syncShellCmd { "git", "log", "--max-count=1", "--pretty=%s" }
		local lastCommitBody = u.syncShellCmd { "git", "log", "--max-count=1", "--pretty=%b" }
		msgLines = { lastCommitTitle, lastCommitBody }
	elseif mode == "commit" then
		local cwd = vim.uv.cwd() or ""
		msgLines = state.abortedCommitMsg[cwd] or {}
	end
	while #msgLines < 2 do -- so there is always a body
		table.insert(msgLines, "")
	end

	-- FOOTER
	local nmaps = conf.keymaps.normal
	local hlgroup = { key = "Comment", desc = "NonText" }
	local keymapHints = {
		{ borderChar, "FloatBorder" }, -- extend border to align with padding
		{ " normal: ", hlgroup.desc },
		{ nmaps.confirm, hlgroup.key },
		{ " confirm  ", hlgroup.desc },
		{ nmaps.abort, hlgroup.key },
		{ " abort ", hlgroup.desc },
	}

	local titleCharCount = {
		{ borderChar:rep(3), "FloatBorder" },
		{ borderChar, "FloatBorder" }, -- extend border if title count < 10
		{ " 0", "FloatBorder" }, -- initial count
		{ "/" .. MAX_TITLE_LEN .. " ", "FloatBorder" },
	}
	local footer = vim.list_extend(keymapHints, titleCharCount)

	-- CREATE WINDOW & BUFFER
	local bufnr = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, msgLines)
	local winid = vim.api.nvim_open_win(bufnr, true, {
		relative = "editor",
		row = math.floor((vim.o.lines - height) / 2) - 3,
		col = math.floor((vim.o.columns - width) / 2),
		width = width,
		height = height,
		title = " " .. prompt .. " ",
		footer = footer,
		footer_pos = "right",
		border = conf.border,
		style = "minimal",
	})

	-- needs to be set after window creation to trigger local opts from ftplugin,
	-- but before the plugin sets its options, so they aren't overridden by the
	-- user's config
	vim.bo[bufnr].filetype = "gitcommit"

	vim.wo[winid].winfixbuf = true
	vim.wo[winid].statuscolumn = " " -- just for left-padding (also makes line numbers not show up)

	vim.wo[winid].scrolloff = 0
	vim.wo[winid].sidescrolloff = 0
	vim.wo[winid].list = true
	vim.wo[winid].listchars = "precedes:…,extends:…"
	vim.wo[winid].spell = conf.spellcheck

	-- wrapping
	vim.bo[bufnr].textwidth = MAX_TITLE_LEN
	vim.wo[winid].wrap = conf.wrap == "soft"
	if conf.wrap == "hard" then
		vim.bo[bufnr].formatoptions = vim.bo[bufnr].formatoptions .. "t" -- auto-wrap at textwidth
	end

	vim.cmd.startinsert { bang = true }

	-- STYLING
	-- no highlight, since we do that more intuitively with our separator is enough
	vim.wo[winid].winhighlight = "@markup.heading.gitcommit:,@markup.link.gitcommit:"

	vim.api.nvim_win_call(winid, function()
		highlight.inlineCodeAndIssueNumbers()
		-- overlength
		-- * `\%<2l` to only highlight 1st line https://neovim.io/doc/user/pattern.html#search-range
		-- * match only starts after `\zs` https://neovim.io/doc/user/pattern.html#%2Fordinary-atom
		vim.fn.matchadd("ErrorMsg", [[\%<2l.\{]] .. MAX_TITLE_LEN .. [[}\zs.*]])
	end)

	-- AUTOCMDS
	state.winid, state.bufnr = winid, bufnr
	backdrop.new(bufnr)
	setupKeymaps(confirmationCallback)
	setupTitleCharCount(borderChar)
	setupUnmount()
	setupSeparator(width)
end

--------------------------------------------------------------------------------
return M
