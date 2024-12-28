local u = require("tinygit.shared.utils")
local backdrop = require("tinygit.shared.backdrop")

local M = {}
local state = {
	---@type table<string, string[]> -- saves message per cwd
	abortedCommitMsg = {},
	---@type "commit"|"amend"|nil
	commitMode = nil,
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
	opts.title = state.commitMode
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

---@param confirmationCallback fun(commitTitle: string, commitBody: string)
local function setupKeymaps(confirmationCallback)
	local bufnr = state.bufnr
	local conf = require("tinygit.config").config.commit
	local function map(lhs, rhs) vim.keymap.set("n", lhs, rhs, { buffer = bufnr, nowait = true }) end

	-----------------------------------------------------------------------------

	map(conf.normalModeKeymaps.abort, function()
		-- save msg
		if state.mode ~= "amend" then
			local cwd = vim.uv.cwd() or ""
			state.abortedCommitMsg[cwd] = vim.api.nvim_buf_get_lines(bufnr, 0, 1, false)
			vim.defer_fn(
				function() M.state.abortedCommitMsg[cwd] = nil end,
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
		local commitBody = vim
			.iter(vim.api.nvim_buf_get_lines(bufnr, 1, -1, false))
			:skip(1) -- skip title
			:join("\n") -- join for shell command
		confirmationCallback(commitTitle, vim.trim(commitBody))

		-- close win
		vim.cmd.bwipeout(bufnr)
	end)
end

local function setupFooter()
	local bufnr, winid = state.bufnr, state.winid

	local function updateFooter()
		local titleChars = vim.api.nvim_buf_get_lines(bufnr, 0, 1, false)[1]:len()
		local countHighlight = titleChars <= MAX_TITLE_LEN and "FloatBorder" or "ErrorMsg"
		vim.api.nvim_win_set_config(winid, {
			footer = {
				{ " ", "FloatBorder" },
				{ tostring(titleChars), countHighlight },
				{ "/" .. MAX_TITLE_LEN .. " ", "FloatBorder" },
			},
			footer_pos = "right",
		})
	end

	updateFooter() -- initialize
	vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
		desc = "Tinygit: update char count in input window",
		buffer = bufnr,
		callback = updateFooter,
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

--------------------------------------------------------------------------------

---@param mode "commit"|"amend"
---@param prompt string
---@param confirmationCallback fun(commitTitle: string, commitBody: string)
function M.new(mode, prompt, confirmationCallback)
	state.commitMode = mode

	-- PARAMS
	local config = require("tinygit.config").config
	local width = MAX_TITLE_LEN
	local height = 3
	prompt = vim.trim(config.appearance.mainIcon .. " " .. prompt)

	-- PREFILL
	local msgLines = {}
	if mode == "amend" then
		local lastCommitTitle = u.syncShellCmd { "git", "log", "--max-count=1", "--pretty=%s" }
		local lastCommitBody = u.syncShellCmd { "git", "log", "--max-count=1", "--pretty=%b" }
		msgLines = { lastCommitTitle, "", lastCommitBody }
	elseif mode == "commit" then
		local cwd = vim.uv.cwd() or ""
		local lastCommitMsg = state.abortedCommitMsg[cwd]
		msgLines = lastCommitMsg or {}
	end

	-- CREATE WINDOW & BUFFER
	local bufnr = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, msgLines)
	vim.bo[bufnr].filetype = "gitcommit"
	local winid = vim.api.nvim_open_win(bufnr, true, {
		relative = "editor",
		row = math.floor((vim.o.lines - height) / 2) - 3,
		col = math.floor((vim.o.columns - width) / 2),
		width = width,
		height = height,
		title = " " .. prompt .. " ",
		border = config.commit.border,
		style = "minimal",
	})
	vim.wo[winid].winfixbuf = true
	vim.wo[winid].statuscolumn = " " -- = left-padding
	state.winid, state.bufnr = winid, bufnr

	-- BASE SETUP
	vim.cmd.startinsert { bang = true }
	setupKeymaps(confirmationCallback)

	-- AUTOCMDS
	setupFooter()
	setupUnmount()

	-- APPEARANCE
	backdrop.new(bufnr)
end

--------------------------------------------------------------------------------
return M
