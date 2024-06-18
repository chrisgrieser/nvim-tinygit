local M = {}

local selectCommit = require("tinygit.shared.select-commit")
local u = require("tinygit.shared.utils")
local push = require("tinygit.commands.push-pull").push
local updateStatusline = require("tinygit.statusline").updateAllComponents
local fn = vim.fn

--------------------------------------------------------------------------------

M.state = {
	abortedCommitMsg = nil,
	openIssues = {},
	curIssue = nil,
	issueNotif = nil,
}

---@nodiscard
---@return boolean
local function hasNoStagedChanges()
	return vim.system({ "git", "diff", "--staged", "--quiet" }):wait().code == 0
end

---@nodiscard
---@return boolean
local function hasNoUnstagedChanges()
	return vim.system({ "git", "diff", "--quiet" }):wait().code == 0
end

---@nodiscard
---@return boolean
local function hasNoChanges()
	local noChanges = vim.system({ "git", "status", "--porcelain" }):wait().stdout == ""
	if noChanges then
		u.notify("There are no staged or unstaged changes to be committed.", "warn")
	end
	return noChanges
end

---process a commit message: length, not empty, adheres to conventional commits
---@param commitMsg string
---@nodiscard
---@return boolean -- is the commit message valid?
---@return string -- the (modified) commit message
local function processCommitMsg(commitMsg)
	local config = require("tinygit.config").config.commitMsg
	commitMsg = vim.trim(commitMsg)
	local commitMaxLen = 72

	if #commitMsg > commitMaxLen then
		u.notify("Commit Message too long.", "warn")
		local shortenedMsg = commitMsg:sub(1, commitMaxLen)
		return false, shortenedMsg
	elseif commitMsg == "" then
		u.notify("Commit Message empty.", "warn")
		return false, ""
	end

	if config.conventionalCommits.enforce then
		local firstWord = commitMsg:match("^%w+")
		if not vim.tbl_contains(config.conventionalCommits.keywords, firstWord) then
			u.notify("Not using a Conventional Commits keyword.", "warn")
			return false, commitMsg
		end
	end

	-- message ok
	return true, commitMsg
end

---@param mode "first"|"next"|"prev"
local function insertIssueNumber(mode)
	-- GUARD – all hotkeys should still insert a # if there are no issues
	if #M.state.openIssues == 0 then 
		if mode == "first" then return "#" end
		local line = vim.api.nvim_get_current_line()
		vim.api.nvim_set_current_line(vim.trim(line) + " #")
		return
	end

	if mode == "next" or mode == "prev" then
		M.state.curIssue = M.state.curIssue + (mode == "next" and 1 or -1)
	end
	if M.state.curIssue == 0 then M.state.curIssue = #M.state.openIssues end
	if M.state.curIssue > #M.state.openIssues then M.state.curIssue = 1 end
	local issue = M.state.openIssues[M.state.curIssue]
	local msg = string.format("#%d %s by %s", issue.number, issue.title, issue.user.login)

	M.state.issueNotif = u.notify(msg, "info", "Referenced Issue", {
		timeout = false,
		replace = M.state.issueNotif and M.state.issueNotif.id, ---@diagnostic disable-line: undefined-field
		on_open = function(win)
			local buf = vim.api.nvim_win_get_buf(win)
			vim.api.nvim_buf_call(buf, u.issueTextHighlighting)
		end,
	})

	if mode == "first" then
		return "#" .. issue.number -- keymap needs `expr = true`
	else
		local line = vim.api.nvim_get_current_line()
		-- `(.*)` to only updated the last occurrence of `#` in the line
		local updatedLine, found = line:gsub("(.*)#%d+", "%1#" .. issue.number, 1)
		if found == 0 then updatedLine = line .. " #" .. issue.number end
		vim.api.nvim_set_current_line(updatedLine)
	end
end

---@param bufnr number
local function setupIssueInsertion(bufnr)
	local opts = require("tinygit.config").config.commitMsg.insertIssuesOnHash
	M.state.curIssue = 0
	M.state.openIssues = {}
	require("tinygit.commands.github").getOpenIssuesAsync()

	vim.keymap.set(
		"i",
		"#",
		function() return insertIssueNumber("first") end,
		{ buffer = bufnr, expr = true }
	)
	vim.keymap.set(
		{ "n", "i" },
		opts.next,
		function() insertIssueNumber("next") end,
		{ buffer = bufnr }
	)
	vim.keymap.set(
		{ "n", "i" },
		opts.prev,
		function() insertIssueNumber("prev") end,
		{ buffer = bufnr }
	)
end

---@param commitType? "smartCommit"
local function setupInputField(commitType)
	local opts = require("tinygit.config").config.commitMsg
	local commitMaxLen = 72 -- hard git limit
	local commitOverflowLen = 50 -- limit used by treesitter gitcommit parser

	local function overwriteDressingWidth(winid)
		if not opts.inputFieldWidth then return end -- keep dressings default
		local width = math.max(opts.inputFieldWidth, 20) + 1
		vim.api.nvim_win_set_config(winid, {
			relative = "editor",
			width = width,
			row = math.floor(vim.o.lines / 2),
			col = math.floor((vim.o.columns - width) / 2),
		})
	end

	-- the order the highlights are added matters, later has priority
	local function setupHighlighting(winid)
		-- only-markup, since stuff like conventional commits keywords are done by
		-- the treesitter parser
		u.commitMsgHighlighting("only-markup")

		-- INFO no need to highlight between 50-72, since the treesitter parser
		-- for gitcommit already does this now
		fn.matchadd("ErrorMsg", ([[.\{%s}\zs.*\ze]]):format(commitMaxLen))

		-- colorcolumn as extra indicators of overLength
		vim.opt_local.colorcolumn = { commitOverflowLen + 1, commitMaxLen + 1 }

		-- treesitter highlighting & ftplugin
		vim.bo.filetype = "gitcommit"

		-- prevent auto-wrapping due to filetype "gitcommit" being set
		vim.opt_local.formatoptions:remove("t")

		-- treesitter parser makes first line bold, but since we have only one
		-- line, we do not need to bold everything in it
		local ns = vim.api.nvim_create_namespace("tinygit.inputField")
		vim.api.nvim_win_set_hl_ns(winid, ns)
		vim.api.nvim_set_hl(ns, "@markup.heading.gitcommit", {}) -- = clear
	end

	local function charCountInFooter(bufnr, winid)
		vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
			buffer = bufnr,
			callback = function()
				local neutralColor = "FloatBorder"
				local charCount = #vim.api.nvim_get_current_line()
				local countHighlight = charCount <= commitMaxLen and neutralColor or "ErrorMsg"
				vim.api.nvim_win_set_config(winid, {
					footer = {
						{ " ", neutralColor },
						{ tostring(charCount), countHighlight },
						{ ("/%s "):format(commitMaxLen), neutralColor },
					},
					footer_pos = "right",
				})
			end,
		})
	end

	vim.api.nvim_create_autocmd("FileType", {
		pattern = "DressingInput",
		once = true, -- do not affect other DressingInputs
		callback = function(ctx)
			local winid = vim.api.nvim_get_current_win()
			local bufnr = ctx.buf

			require("tinygit.shared.backdrop").new(bufnr)
			overwriteDressingWidth(winid)
			setupHighlighting(winid)
			charCountInFooter(bufnr, winid)

			-- fetch the issues now, so they are later available when typing `#`
			if opts.insertIssuesOnHash.enabled and package.loaded["notify"] then
				setupIssueInsertion(bufnr)
			end

			-- activates styling for statusline plugins (e.g., filename icons)
			vim.api.nvim_buf_set_name(bufnr, "COMMIT_EDITMSG")

			-- spellcheck
			vim.opt_local.spell = true
			vim.opt_local.spelloptions = "camel"
			vim.opt_local.spellcapcheck = ""
		end,
	})

	-- SETUP BRIEFLY SAVING MESSAGE WHEN ABORTING COMMIT
	-- Only relevant for smartCommit, since amendNoEdit has no commitMsg and
	-- amendOnlyMsg uses different prefilled message.
	if commitType == "smartCommit" then
		vim.api.nvim_create_autocmd("WinClosed", {
			callback = function(ctx)
				local ft = vim.api.nvim_get_option_value("filetype", { buf = ctx.buf })
				if not (ft == "gitcommit" or ft == "DressingInput") then return end

				M.state.abortedCommitMsg = vim.api.nvim_buf_get_lines(ctx.buf, 0, 1, false)[1]
				vim.defer_fn(
					function() M.state.abortedCommitMsg = nil end,
					1000 * opts.keepAbortedMsgSecs
				)

				-- Disables this autocmd. Cannot use `once = true`, as things like
				-- closed notification windows would still trigger it which would false
				-- trigger and disable this autocmd then.
				return true
			end,
		})
	end
end

---@param title string title for nvim-notify
---@param stagedAllChanges boolean
---@param commitMsg string
---@param extraInfo? string extra lines to display
local function postCommitNotif(title, stagedAllChanges, commitMsg, extraInfo)
	local stageAllText = "Staged all changes."
	local lines = { commitMsg }
	if stagedAllChanges then table.insert(lines, 1, stageAllText) end
	if extraInfo then table.insert(lines, extraInfo) end
	local text = table.concat(lines, "\n")

	u.notify(text, "info", title, {
		on_open = function(win)
			local bufnr = vim.api.nvim_win_get_buf(win)

			-- commit msg custom highlights
			vim.api.nvim_buf_call(bufnr, function()
				u.commitMsgHighlighting()
				if stagedAllChanges then fn.matchadd("Comment", stageAllText) end
				if extraInfo then fn.matchadd("Comment", extraInfo) end
			end)
		end,
	})
end

---The notification makes it more transparent to the user what is going to be
---committed. (This is similar to the commented out lines at the bottom of a git
---message in the terminal.)
---@return number|nil -- nil if no notification is shown
local function showCommitPreview()
	local config = require("tinygit.config").config.commitMsg
	local notifyInstalled, notifyNvim = pcall(require, "notify")
	if not (notifyInstalled and config.commitPreview) then return end

	---@param gitStatsArgs string[]
	local function cleanupStatsOutput(gitStatsArgs)
		return u
			.syncShellCmd(gitStatsArgs)
			:gsub("\n[^\n]*$", "") -- remove summary line (footer)
			:gsub(" | ", " │ ") -- pipes to full vertical bars
			:gsub(" Bin ", "    ") -- binary icon
	end
	-----------------------------------------------------------------------------

	-- get width defined by user for nvim-notify to avoid overflow/wrapped lines
	-- INFO max_width can be number, nil, or function, see https://github.com/chrisgrieser/nvim-tinygit/issues/6#issuecomment-1999537606
	local _, notifyConfig = notifyNvim.instance() ---@diagnostic disable-line: missing-parameter
	local width = 50
	if notifyConfig and notifyConfig.max_width then
		local max_width = type(notifyConfig.max_width) == "number" and notifyConfig.max_width
			or notifyConfig.max_width()
		width = max_width - 3
	end

	-- get changes
	local gitStatsCmd = { "git", "diff", "--compact-summary", "--stat=" .. tostring(width) }
	local title = "Commit Preview"
	local willStageAllChanges = hasNoStagedChanges()
	local changes
	local specialWhitespace = " " -- HACK to force nvim-notify to keep the blank line
	if willStageAllChanges then
		-- include new files in diff stats
		local newFiles = u.syncShellCmd { "git", "ls-files", "--others", "--exclude-standard" }
		if newFiles ~= "" then
			for _, file in ipairs(vim.split(newFiles, "\n")) do
				vim.system({ "git", "add", "--intent-to-add", "--", file }):wait()
			end
		end

		title = "Stage & " .. title
		changes = cleanupStatsOutput(gitStatsCmd)
	else
		local notStaged = cleanupStatsOutput(gitStatsCmd)
		table.insert(gitStatsCmd, "--staged")
		local staged = cleanupStatsOutput(gitStatsCmd)
		changes = notStaged == "" and staged
			or table.concat({ staged, specialWhitespace, "not staged:", notStaged }, "\n")
	end

	-- send notification
	u.notify(changes, "info", title, {
		timeout = false, -- keep shown, only remove when input window closed
		animate = false,
		on_open = function(win)
			local bufnr = vim.api.nvim_win_get_buf(win)
			vim.api.nvim_buf_call(bufnr, function()
				fn.matchadd("diffAdded", [[ \zs+\+]]) -- color the plus/minus like in the terminal
				fn.matchadd("diffRemoved", [[-\+\ze\s*$]])
				fn.matchadd("Keyword", [[(new.*)]])
				fn.matchadd("Keyword", [[(gone.*)]])
				fn.matchadd("Comment", "│")

				if not willStageAllChanges then
					-- `\_.` matches any char, including newline
					fn.matchadd("Comment", specialWhitespace .. [[\_.*]])
				end
			end)
		end,
	})
end

local function closeNotifications()
	local opts = require("tinygit.config").config.commitMsg
	if package.loaded["notify"] and (opts.commitPreview or M.state.issueNotif) then
		-- can only dismiss all and not by ID: https://github.com/rcarriga/nvim-notify/issues/240
		require("notify").dismiss() ---@diagnostic disable-line: missing-parameter
		M.state.issueNotif = nil
	end
end

---@param processedMsg string
local function openReferencedIssue(processedMsg)
	local config = require("tinygit.config").config.commitMsg
	local issueReferenced = processedMsg:match("#(%d+)")
	if config.openReferencedIssue and issueReferenced then
		local repo = u.getGithubRemote("silent")
		if not repo then return end
		local url = ("https://github.com/%s/issues/%s"):format(repo, issueReferenced)
		vim.ui.open(url)
	end
end

--------------------------------------------------------------------------------

---If there are staged changes, commit them.
---If there aren't, add all changes (`git add -A`) and then commit.
---@param msgNeedsFixing? string used internally when calling this function recursively due to corrected commit message
---@param opts? { pushIfClean?: boolean, pullBeforePush?: boolean }
function M.smartCommit(opts, msgNeedsFixing)
	vim.cmd("silent update")
	if u.notInGitRepo() or hasNoChanges() then return end

	local defaultOpts = { pushIfClean = false, pullBeforePush = true }
	opts = vim.tbl_deep_extend("force", defaultOpts, opts or {})
	local prefillMsg = msgNeedsFixing or M.state.abortedCommitMsg or ""

	local doStageAllChanges = hasNoStagedChanges()
	-- When committing with no staged changes, all changes are staged, resulting
	-- in a clean repo afterwards. Alternatively, if there are no unstaged
	-- changes, the repo will also be clean after committing. If one of the two
	-- conditions is fulfilled, we can safely push after committing.
	local cleanAfterCommit = hasNoUnstagedChanges() or doStageAllChanges

	local title = "Commit"
	if doStageAllChanges then title = "Stage All · " .. title end
	if cleanAfterCommit and opts.pushIfClean then title = title .. " · Push" end

	showCommitPreview()
	setupInputField("smartCommit")

	vim.ui.input({ prompt = "󰊢 " .. title, default = prefillMsg }, function(commitMsg)
		closeNotifications()

		-- abort
		local aborted = not commitMsg
		if aborted then return end
		if not aborted then M.state.abortedCommitMsg = nil end

		-- validate
		local validMsg, processedMsg = processCommitMsg(commitMsg)
		if not validMsg then
			M.smartCommit(opts, processedMsg) -- if msg invalid, run again to fix the msg
			return
		end

		-- stage
		if doStageAllChanges then
			local result = vim.system({ "git", "add", "--all" }):wait()
			if u.nonZeroExit(result) then return end
		end

		-- commit
		local result = vim.system({ "git", "commit", "-m", processedMsg }):wait()
		if u.nonZeroExit(result) then return end

		-- notification
		local extra = nil
		if opts.pushIfClean and cleanAfterCommit then
			extra = "Pushing…"
		elseif opts.pushIfClean and not cleanAfterCommit then
			extra = "Not pushing since repo still dirty."
		end
		postCommitNotif("Smart Commit", doStageAllChanges, processedMsg, extra)

		-- push
		if opts.pushIfClean and cleanAfterCommit then push { pullBefore = opts.pullBeforePush } end

		openReferencedIssue(processedMsg)
		updateStatusline()
	end)
end

---@param opts? { forcePushIfDiverged?: boolean }
function M.amendNoEdit(opts)
	vim.cmd("silent update")
	if u.notInGitRepo() or hasNoChanges() then return end
	if not opts then opts = {} end

	-- stage
	local doStageAllChanges = hasNoStagedChanges()
	if doStageAllChanges then
		local result = vim.system({ "git", "add", "--all" }):wait()
		if u.nonZeroExit(result) then return end
	end

	-- commit
	local result = vim.system({ "git", "commit", "--amend", "--no-edit" }):wait()
	if u.nonZeroExit(result) then return end

	-- push & notification
	local lastCommitMsg = u.syncShellCmd { "git", "log", "-1", "--format=%s" }
	local branchInfo = vim.system({ "git", "branch", "--verbose" }):wait().stdout or ""
	local prevCommitWasPushed = branchInfo:find("%[ahead 1, behind 1%]") ~= nil
	local extraInfo
	if opts.forcePushIfDiverged and prevCommitWasPushed then
		extraInfo = "Force Pushing…"
		push { forceWithLease = true }
	end
	postCommitNotif("Amend-No-Edit", doStageAllChanges, lastCommitMsg, extraInfo)
	updateStatusline()
end

---@param opts? { forcePushIfDiverged?: boolean }
---@param msgNeedsFixing? string used internally when calling this function recursively due to corrected commit message
function M.amendOnlyMsg(opts, msgNeedsFixing)
	vim.cmd("silent update")
	-- GUARD
	if u.notInGitRepo() then return end
	if not hasNoStagedChanges() then
		u.notify("Aborting: There are staged changes.", "warn", "Amend Only Msg")
		return
	end
	if not opts then opts = {} end

	if not msgNeedsFixing then
		local lastCommitMsg = u.syncShellCmd { "git", "log", "--max-count=1", "--pretty=%s" }
		msgNeedsFixing = lastCommitMsg
	end

	setupInputField()
	vim.ui.input(
		{ prompt = "󰊢 Amend only message", default = msgNeedsFixing },
		function(commitMsg)
			if not commitMsg then return end -- aborted input modal
			local validMsg, processedMsg = processCommitMsg(commitMsg)
			if not validMsg then -- if msg invalid, run again to fix the msg
				M.amendOnlyMsg(opts, processedMsg)
				return
			end

			-- commit
			local result = vim.system({ "git", "commit", "--amend", "-m", processedMsg }):wait()
			if u.nonZeroExit(result) then return end

			-- push & notification
			local branchInfo = vim.system({ "git", "branch", "--verbose" }):wait().stdout or ""
			local prevCommitWasPushed = branchInfo:find("%[ahead 1, behind 1%]") ~= nil
			local extra = (opts.forcePushIfDiverged and prevCommitWasPushed) and "Force Pushing…"
				or nil
			postCommitNotif("Amend only message", false, processedMsg, extra)
			if opts.forcePushIfDiverged and prevCommitWasPushed then push { forceWithLease = true } end

			openReferencedIssue(processedMsg)
			updateStatusline()
		end
	)
end

---@param opts? { selectFromLastXCommits?: number, squashInstead: boolean, autoRebase?: boolean }
function M.fixupCommit(opts)
	vim.cmd("silent update")
	if u.notInGitRepo() or hasNoChanges() then return end
	local defaultOpts = {
		selectFromLastXCommits = 15,
		squashInstead = false,
		autoRebase = false,
	}
	opts = vim.tbl_deep_extend("force", defaultOpts, opts or {})

	-- get commits
	local result = vim.system({
		"git",
		"log",
		"-n" .. tostring(opts.selectFromLastXCommits),
		"--format=" .. selectCommit.gitlogFormat,
	}):wait()
	if u.nonZeroExit(result) then return end
	local commits = vim.split(vim.trim(result.stdout), "\n")

	-- user selection of commit
	showCommitPreview()
	local autocmdId = selectCommit.setupAppearance()
	local title = opts.squashInstead and "Squash" or "Fixup"
	vim.ui.select(commits, {
		prompt = ("󰊢 Select Commit to %s"):format(title),
		format_item = selectCommit.selectorFormatter,
		kind = "tinygit.fixupCommit",
	}, function(commit)
		closeNotifications()

		vim.api.nvim_del_autocmd(autocmdId)
		if not commit then return end

		local hash = commit:match("^%w+")
		local fixupOrSquash = opts.squashInstead and "--squash" or "--fixup"

		-- stage
		local doStageAllChanges = hasNoStagedChanges()
		if doStageAllChanges then
			local _result = vim.system({ "git", "add", "--all" }):wait()
			if u.nonZeroExit(_result) then return end
		end

		-- commit
		local commitResult = vim.system({ "git", "commit", fixupOrSquash, hash }):wait()
		if u.nonZeroExit(commitResult) then return end
		u.notify(commitResult.stdout, "info", title .. " Commit")

		-- rebase
		if opts.autoRebase then
			local _result = vim.system({
				"git",
				"-c",
				"sequence.editor=:", -- HACK ":" is a "no-op-"editor https://www.reddit.com/r/git/comments/uzh2no/what_is_the_utility_of_noninteractive_rebase/
				"rebase",
				"--interactive",
				"--autostash",
				"--autosquash",
				hash .. "^", -- rebase up until the selected commit
			}):wait()
			if u.nonZeroExit(_result) then return end
			u.notify("Auto-rebase applied.", "info", title .. " Commit")
		end
		updateStatusline()
	end)
end

--------------------------------------------------------------------------------
return M
