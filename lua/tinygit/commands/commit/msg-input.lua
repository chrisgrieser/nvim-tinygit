local backdrop = require("tinygit.shared.backdrop")
local commitPreview = require("tinygit.commands.commit.preview")
local highlight = require("tinygit.shared.highlights")
local u = require("tinygit.shared.utils")

local M = {}

local state = {
	abortedCommitMsg = {}, ---@type table<string, string[]> -- saves message per cwd
	winid = -1,
	bufnr = -1,
}

local MAX_TITLE_LEN = 72
local INPUT_WIN_HEIGHT = { small = 3, big = 6 }

---@alias Tinygit.Input.ConfirmationCallback fun(commitTitle: string, commitBody?: string)

--------------------------------------------------------------------------------

---@param msg string
local function warn(msg) u.notify(msg, "warn", { title = "Commit message" }) end

---@param confirmationCallback Tinygit.Input.ConfirmationCallback
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
		-- TITLE
		local commitTitle = vim.trim(vim.api.nvim_buf_get_lines(bufnr, 0, 1, false)[1])
			:gsub("%.$", "") -- no trailing dot https://commitlint.js.org/reference/rules.html#body-full-stop
		if conf.subject.noSentenceCase and conf.subject.enforceType then
			commitTitle = commitTitle
				:gsub("^(%w+: )(.)", function(c1, c2) return c1 .. c2:lower() end) -- no scope
				:gsub("^(%w+%b(): )(.)", function(c1, c2) return c1 .. c2:lower() end) -- with scope
		elseif conf.subject.noSentenceCase and not conf.subject.enforceType then
			commitTitle = commitTitle:gsub("^%w", string.lower)
		end
		if #commitTitle > MAX_TITLE_LEN then
			warn("Title is too long.")
			return
		end
		if #commitTitle == 0 then
			warn("Title is empty.")
			return
		end
		if conf.subject.enforceType then
			local firstWord = commitTitle:match("^%w+")
			if not vim.tbl_contains(conf.subject.types, firstWord) then
				local msg = "Not using a type allowed by the config `commit.subject.types`. "
					.. "(Alternatively, you can also disable `commit.subject.enforceType`.)"
				warn(msg)
				return
			end
		end

		-- BODY
		local bodytext = vim
			.iter(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false))
			:skip(1) -- skip title
			:join("\n") -- join for shell command
		---@type string|nil
		local commitBody = vim.trim(bodytext)
		if commitBody == "" then
			if conf.body.enforce then
				warn("Body is empty.")
				return
			end
			commitBody = nil
		end

		-- reset remembered message
		local cwd = vim.uv.cwd() or ""
		state.abortedCommitMsg[cwd] = nil

		-- confirm and close
		confirmationCallback(commitTitle, commitBody)
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
				commitPreview.unmount()
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

local function setupWinHeightUpdate()
	local function updateWinHeight()
		local winConf = vim.api.nvim_win_get_config(state.winid)
		local bodyLines = vim.api.nvim_buf_line_count(state.bufnr) - 1
		winConf.height = bodyLines > 1 and INPUT_WIN_HEIGHT.big or INPUT_WIN_HEIGHT.small

		vim.api.nvim_win_set_config(state.winid, winConf)
		commitPreview.adaptWinPosition(winConf)
	end

	updateWinHeight() -- initialize
	vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
		desc = "Tinygit: update input window height",
		buffer = state.bufnr,
		callback = updateWinHeight,
	})
end

--------------------------------------------------------------------------------

---@param mode "stage-all-and-commit"|"commit"|"amend-msg"
---@param prompt string
---@param confirmationCallback Tinygit.Input.ConfirmationCallback
function M.new(mode, prompt, confirmationCallback)
	-- PARAMS
	local conf = require("tinygit.config").config.commit
	local icon = require("tinygit.config").config.appearance.mainIcon
	prompt = vim.trim(icon .. " " .. prompt)
	local borderChar = conf.border == "double" and "═" or "─"

	local height = INPUT_WIN_HEIGHT.small
	local width = MAX_TITLE_LEN + 2

	-- PREFILL
	local msgLines = {}
	if mode == "amend-msg" then
		local lastCommitTitle = u.syncShellCmd { "git", "log", "--max-count=1", "--pretty=%s" }
		local lastCommitBody = u.syncShellCmd { "git", "log", "--max-count=1", "--pretty=%b" }
		msgLines = { lastCommitTitle, lastCommitBody }
	else
		local cwd = vim.uv.cwd() or ""
		msgLines = state.abortedCommitMsg[cwd] or {}
		while #msgLines < 2 do -- so there is always a body
			table.insert(msgLines, "")
		end
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
		height = height,
		width = width,
		row = math.ceil((vim.o.lines - height) / 2) - 5,
		col = math.ceil((vim.o.columns - width) / 2),
		border = conf.border,
		title = " " .. prompt .. " ",
		footer = footer,
		footer_pos = "right",
		style = "minimal",
	})
	state.winid, state.bufnr = winid, bufnr

	vim.cmd.startinsert { bang = true }

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

	-- COMMIT PREVIEW
	if mode ~= "amend-msg" then
		---@cast mode "stage-all-and-commit"|"commit" -- ensured above
		commitPreview.createWin(mode, winid)
	end

	-- STYLING
	-- no highlight, since we do that more intuitively with our separator is enough
	-- linking to original `Normal` hl looks better in some themes
	vim.wo[winid].winhighlight = "Normal:Normal,@markup.heading.gitcommit:,@markup.link.gitcommit:"

	vim.api.nvim_win_call(winid, function()
		highlight.inlineCodeAndIssueNumbers()
		-- overlength
		-- * `\%<2l` to only highlight 1st line https://neovim.io/doc/user/pattern.html#search-range
		-- * match only starts after `\zs` https://neovim.io/doc/user/pattern.html#%2Fordinary-atom
		vim.fn.matchadd("ErrorMsg", [[\%<2l.\{]] .. MAX_TITLE_LEN .. [[}\zs.*]])
	end)

	-- AUTOCMDS
	backdrop.new(bufnr)
	setupKeymaps(confirmationCallback)
	setupTitleCharCount(borderChar)
	setupUnmount()
	setupSeparator(width)
	setupWinHeightUpdate()
end

--------------------------------------------------------------------------------
return M
