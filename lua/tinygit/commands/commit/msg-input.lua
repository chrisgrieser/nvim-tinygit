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
---@param level? Tinygit.notifyLevel
---@param opts? table
local function notify(msg, level, opts)
	if not opts then opts = {} end
	opts.title = "Commit message"
	u.notify(msg, level, opts)
end

local function diffStatsHighlights()
	vim.fn.matchadd("diffAdded", [[ \zs+\+]]) -- color the plus/minus like in the terminal
	vim.fn.matchadd("diffRemoved", [[-\+\ze\s*$]])
	vim.fn.matchadd("Keyword", [[(new.*)]])
	vim.fn.matchadd("Keyword", [[(gone.*)]])
	vim.fn.matchadd("Comment", "│") -- vertical separator
	vim.fn.matchadd("Function", ".*/") -- directory of a file
	vim.fn.matchadd("WarningMsg", "/")
end

---@param willStageAllChanges boolean
---@param statsWidth number
---@return string
---@nodiscard
local function getCommitPreview(willStageAllChanges, statsWidth)
	---@param gitStatsArgs string[]
	local function cleanupStatsOutput(gitStatsArgs)
		return u
			.syncShellCmd(gitStatsArgs)
			:gsub("\n[^\n]*$", "") -- remove summary line (footer)
			:gsub(" | ", " │ ") -- pipes to full vertical bars
			:gsub(" Bin ", "    ") -- binary icon
			:gsub("\n +", "\n") -- remove leading spaces
	end

	-----------------------------------------------------------------------------

	-- get changes
	local gitStatsCmd = { "git", "diff", "--compact-summary", "--stat=" .. statsWidth }
	local title = "Commit preview"
	local changes
	if willStageAllChanges then
		u.intentToAddUntrackedFiles() -- include new files in diff stats
		title = "Stage & " .. title:lower()
		changes = cleanupStatsOutput(gitStatsCmd)
	else
		local notStaged = cleanupStatsOutput(gitStatsCmd)
		table.insert(gitStatsCmd, "--staged")
		local staged = cleanupStatsOutput(gitStatsCmd)
		changes = notStaged == "" and staged
			or table.concat({ staged, "not staged:", notStaged }, "\n")
	end

	return changes
end

---@param confirmationCallback fun(commitTitle: string, commitBody?: string)
local function setupKeymaps(confirmationCallback)
	local bufnr = state.bufnr
	local conf = require("tinygit.config").config.commit
	local function map(lhs, rhs) vim.keymap.set("n", lhs, rhs, { buffer = bufnr, nowait = true }) end

	-----------------------------------------------------------------------------

	map(conf.normalModeKeymaps.abort, function()
		-- save msg
		if state.mode ~= "amend" then
			local cwd = vim.uv.cwd() or ""
			state.abortedCommitMsg[cwd] = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
			vim.defer_fn(
				function() state.abortedCommitMsg[cwd] = nil end,
				1000 * conf.keepAbortedMsgSecs
			)
		end

		-- abort
		vim.cmd.bwipeout(bufnr)
	end)

	map(conf.normalModeKeymaps.confirm, function()
		-- validate commit title
		local commitTitle = vim.trim(vim.api.nvim_buf_get_lines(bufnr, 0, 1, false)[1])
		if #commitTitle > MAX_TITLE_LEN then
			notify("Commit title too long.", "warn")
			return
		end
		if #commitTitle == 0 then
			notify("No commit title.", "warn")
			return
		end
		if conf.conventionalCommits.enforce then
			local firstWord = commitTitle:match("^%w+")
			if not vim.tbl_contains(conf.conventionalCommits.keywords, firstWord) then
				notify("Not using a Conventional Commits keyword.", "warn")
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
	end)
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
	local config = require("tinygit.config").config
	local width = MAX_TITLE_LEN + 1
	local border = config.commit.border
	local borderChar = border == "double" and "═" or "─"
	local height = 4
	prompt = vim.trim(config.appearance.mainIcon .. "  " .. prompt)

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
	local maps = config.commit.normalModeKeymaps
	local hlgroup = { key = "Comment", desc = "NonText" }
	local keymapHints = {
		{ borderChar, "FloatBorder" }, -- extend border to align with padding
		{ " normal: ", hlgroup.desc },
		{ maps.confirm, hlgroup.key },
		{ " confirm  ", hlgroup.desc },
		{ maps.abort, hlgroup.key },
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
		border = border,
		style = "minimal",
	})
	vim.wo[winid].winfixbuf = true
	vim.wo[winid].scrolloff = 0
	vim.wo[winid].sidescrolloff = 1
	vim.wo[winid].statuscolumn = " " -- just for left-padding
	vim.wo[winid].list = true
	vim.wo[winid].listchars = "precedes:…,extends:…"

	vim.bo[bufnr].textwidth = MAX_TITLE_LEN
	vim.wo[winid].colorcolumn = "+1"
	vim.wo[winid].wrap = true

	-- no highlight, since we do that more intuitively with our separator is enough
	vim.wo[winid].winhighlight = "@markup.heading.gitcommit:,@markup.link.gitcommit:"

	-- needs to be set after window creation to trigger local opts from ftplugin
	vim.bo[bufnr].filetype = "gitcommit"

	vim.cmd.startinsert { bang = true }
	state.winid, state.bufnr = winid, bufnr

	-- AUTOCMDS
	backdrop.new(bufnr)
	vim.api.nvim_win_call(winid, function() highlight.commitMsg("only-inline-code-and-issues") end)
	setupKeymaps(confirmationCallback)
	setupTitleCharCount(borderChar)
	setupUnmount()
	setupSeparator(width)
end

--------------------------------------------------------------------------------
return M
