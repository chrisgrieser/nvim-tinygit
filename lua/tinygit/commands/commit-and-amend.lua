local M = {}

local selectCommit = require("tinygit.shared.select-commit")
local u = require("tinygit.shared.utils")
local push = require("tinygit.commands.push-pull").push
local updateStatusline = require("tinygit.statusline").updateAllComponents
local highlight = require("tinygit.shared.highlights")
--------------------------------------------------------------------------------

M.state = {
	abortedCommitMsg = {},
}

--------------------------------------------------------------------------------

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
	local noChanges = u.syncShellCmd { "git", "status", "--porcelain" } == ""
	if noChanges then u.notify("There are no staged or unstaged changes.", "warn") end
	return noChanges
end

---@param highlightingFunc function
local function setupNotificationHighlights(highlightingFunc)
	if not (package.loaded["snacks"] or package.loaded["notify"]) then return end

	-- determine snacks.nvim notification filetype
	local snacksInstalled, snacks = pcall(require, "snacks")
	local snacksFt = snacksInstalled
			and snacks.config.get("styles", { notification = { bo = { filetype = "snacks_notif" } } }).notification.bo.filetype
		or nil

	-- call highlighting function in notification buffer
	vim.api.nvim_create_autocmd("FileType", {
		pattern = { "noice", "notify", snacksFt },
		once = true,
		callback = function(ctx)
			vim.defer_fn(function() vim.api.nvim_buf_call(ctx.buf, highlightingFunc) end, 1)
		end,
	})
end

---process a commit message: length, not empty, adheres to conventional commits
---@param commitMsg string
---@nodiscard
---@return boolean -- is the commit message valid?
---@return string -- the (modified) commit message
local function processCommitMsg(commitMsg)
	local config = require("tinygit.config").config.commit
	commitMsg = vim.trim(commitMsg)
	local commitMaxLen = 72

	if #commitMsg > commitMaxLen then
		u.notify("Commit message too long.", "warn")
		return false, commitMsg
	elseif commitMsg == "" then
		u.notify("Commit message empty.", "warn")
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

---@param commitType? "smartCommit"
local function setupInputField(commitType)
	local opts = require("tinygit.config").config.commit
	local commitMaxLen = 72 -- hard git limit

	local function overwriteDressingWidth(winid)
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
		highlight.commitMsg("only-markup")
		vim.bo.filetype = "gitcommit" -- treesitter highlighting & ftplugin
		vim.opt_local.formatoptions:remove("t") -- prevent auto-wrapping due "gitcommit" filetype

		-- overlength
		vim.fn.matchadd("ErrorMsg", ([[.\{%s}\zs.*]]):format(commitMaxLen))

		-- treesitter parser makes first line bold, but since we have only one
		-- line, we do not need to bold everything in it
		local ns = vim.api.nvim_create_namespace("tinygit.inputField")
		vim.api.nvim_win_set_hl_ns(winid, ns)
		vim.api.nvim_set_hl(ns, "@markup.heading.gitcommit", {})
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

			-- activates styling for statusline plugins (e.g., filename icons)
			vim.api.nvim_buf_set_name(bufnr, "COMMIT_EDITMSG")

			-- spellcheck
			vim.opt_local.spell = true
			vim.opt_local.spelloptions = "camel"
			vim.opt_local.spellcapcheck = ""
		end,
	})

	-- SETUP BRIEFLY SAVING MESSAGE WHEN ABORTING COMMIT
	-- Only relevant for `smartCommit`, since `amendNoEdit` has no commitMsg and
	-- `amendOnlyMsg` uses a prefilled message.
	if commitType == "smartCommit" then
		vim.api.nvim_create_autocmd("WinClosed", {
			callback = function(ctx)
				local ft = vim.bo[ctx.buf].filetype
				if ft ~= "gitcommit" and ft ~= "DressingInput" then return end

				local cwd = vim.uv.cwd() or ""
				M.state.abortedCommitMsg[cwd] = vim.api.nvim_buf_get_lines(ctx.buf, 0, 1, false)[1]
				vim.defer_fn(
					function() M.state.abortedCommitMsg[cwd] = nil end,
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

---@param title string
---@param stagedAllChanges? boolean
---@param commitMsg string
---@param extraInfo? string extra lines to display
local function postCommitNotif(title, stagedAllChanges, commitMsg, extraInfo)
	local stageAllText = "Staged all changes."
	local lines = { commitMsg }
	if stagedAllChanges then table.insert(lines, 1, stageAllText) end
	if extraInfo then table.insert(lines, extraInfo) end
	local text = table.concat(lines, "\n")

	setupNotificationHighlights(function()
		highlight.commitMsg()
		if stagedAllChanges then vim.fn.matchadd("Comment", stageAllText) end
		if extraInfo then vim.fn.matchadd("Comment", extraInfo) end
	end)

	u.notify(text, "info", { title = title })
end

local function showCommitPreview()
	local config = require("tinygit.config").config.commit
	if not (config.preview and (package.loaded["notify"] or package.loaded["snacks"])) then
		return
	end

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

	-- INFO get width defined by user to avoid overflow/wrapped lines
	local width
	if package.loaded["notify"] then
		local _, notifyConfig = require("notify").instance() ---@diagnostic disable-line: missing-parameter
		if notifyConfig and notifyConfig.max_width then
			-- max_width can be number, nil, or function, see #6
			local max_width = type(notifyConfig.max_width) == "number" and notifyConfig.max_width
				or notifyConfig.max_width()
			width = max_width - 3 -- account of notification borders/padding
		else
			-- default max width is unset, minimum width is 50
			width = 50
		end
	elseif package.loaded["snacks"] then
		-- default is 0.4 https://github.com/folke/snacks.nvim/blob/f5602e60c325f0c60eb6f2869a7222beb88a773c/lua/snacks/notifier.lua#L77C29-L77C32
		width = require("snacks").config.get("notifier", { width = { max = 0.4 } }).width.max
		if width < 1 then width = math.floor(vim.o.columns * width) end
	end

	-- get changes
	local gitStatsCmd = { "git", "diff", "--compact-summary", "--stat=" .. tostring(width) }
	local title = "Commit preview"
	local willStageAllChanges = hasNoStagedChanges()
	local changes
	local specialWhitespace = " " -- HACK to force nvim-notify to keep the blank line
	if willStageAllChanges then
		u.intentToAddUntrackedFiles() -- include new files in diff stats

		title = "Stage & " .. title:lower()
		changes = cleanupStatsOutput(gitStatsCmd)
	else
		local notStaged = cleanupStatsOutput(gitStatsCmd)
		table.insert(gitStatsCmd, "--staged")
		local staged = cleanupStatsOutput(gitStatsCmd)
		changes = notStaged == "" and staged
			or table.concat({ staged, specialWhitespace, "not staged:", notStaged }, "\n")
	end

	setupNotificationHighlights(function()
		vim.fn.matchadd("diffAdded", [[ \zs+\+]]) -- color the plus/minus like in the terminal
		vim.fn.matchadd("diffRemoved", [[-\+\ze\s*$]])
		vim.fn.matchadd("Keyword", [[(new.*)]])
		vim.fn.matchadd("Keyword", [[(gone.*)]])
		vim.fn.matchadd("Comment", "│") -- vertical separator
		vim.fn.matchadd("Function", ".*/") -- directory of a file
		vim.fn.matchadd("WarningMsg", "/")

		if not willStageAllChanges then
			-- `\_.` matches any char, including newline
			vim.fn.matchadd("Comment", specialWhitespace .. [[\_.*]])
		end
	end)

	u.notify(changes, "info", {
		title = title,
		timeout = false, -- keep shown, only remove when input window closed
		id = "tinygit.commit-preview", -- only `snacks.nvim`
		animate = false, -- only `nvim-notify`
		ft = "text", -- only `snacks.nvim`, `+` and `-` would be markdown highlighted otherwise
	})
end

local function closeNotifications()
	local opts = require("tinygit.config").config.commit
	if not (opts.preview) then return end

	if package.loaded["notify"] then
		-- can only dismiss all and not by ID: https://github.com/rcarriga/nvim-notify/issues/240
		require("notify").dismiss() ---@diagnostic disable-line: missing-parameter
	elseif package.loaded["snacks"] then
		require("snacks").notifier.hide("tinygit.commit-preview")
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
	local cwd = vim.uv.cwd() or ""
	local prefillMsg = msgNeedsFixing or M.state.abortedCommitMsg[cwd] or ""

	local doStageAllChanges = hasNoStagedChanges()
	-- When committing with no staged changes, all changes are staged, resulting
	-- in a clean repo afterwards. Alternatively, if there are no unstaged
	-- changes, the repo will also be clean after committing. If one of the two
	-- conditions is fulfilled, we can safely push after committing.
	local cleanAfterCommit = hasNoUnstagedChanges() or doStageAllChanges

	local prompt = "Commit"
	if doStageAllChanges then prompt = "Stage all · " .. prompt:lower() end
	if cleanAfterCommit and opts.pushIfClean then prompt = prompt .. " · push" end
	local icon = require("tinygit.config").config.appearance.mainIcon
	prompt = vim.trim(icon .. " " .. prompt)

	showCommitPreview()
	setupInputField("smartCommit")

	-- INFO explicitly using dressing's `input` instead of `vim.ui.input` allows
	-- the user to use a different input plugin like `snacks` for the rest
	require("dressing.input")({ prompt = prompt, default = prefillMsg }, function(commitMsg)
		closeNotifications()

		-- abort
		local aborted = not commitMsg
		if aborted then return end
		if not aborted then M.state.abortedCommitMsg[cwd] = nil end

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
		postCommitNotif("Smart commit", doStageAllChanges, processedMsg, extra)

		-- push
		if opts.pushIfClean and cleanAfterCommit then
			push({ pullBefore = opts.pullBeforePush }, true)
		end

		updateStatusline()
	end)
end

---@param opts? { forcePushIfDiverged?: boolean, stageAllIfNothingStaged?: boolean }
function M.amendNoEdit(opts)
	vim.cmd("silent update")
	if u.notInGitRepo() or hasNoChanges() then return end
	local defaultOpts = { forcePushIfDiverged = false, stageAllIfNothingStaged = true }
	opts = vim.tbl_deep_extend("force", defaultOpts, opts or {})

	-- stage
	local doStageAllChanges = false
	if hasNoStagedChanges() then
		if opts.stageAllIfNothingStaged then
			doStageAllChanges = true
			local result = vim.system({ "git", "add", "--all" }):wait()
			if u.nonZeroExit(result) then return end
		else
			u.notify("Nothing staged. Aborting.", "warn")
			return
		end
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
		extraInfo = "Force pushing…"
		push({ forceWithLease = true }, true)
	end
	postCommitNotif("Amend-no-edit", doStageAllChanges, lastCommitMsg, extraInfo)
	updateStatusline()
end

---@param opts? { forcePushIfDiverged?: boolean }
---@param msgNeedsFixing? string used internally when calling this function recursively due to corrected commit message
function M.amendOnlyMsg(opts, msgNeedsFixing)
	vim.cmd("silent update")
	-- GUARD
	if u.notInGitRepo() then return end
	if not hasNoStagedChanges() then
		u.notify("Aborting: There are staged changes.", "warn", { title = "Amend only message" })
		return
	end
	if not opts then opts = {} end

	if not msgNeedsFixing then
		local lastCommitMsg = u.syncShellCmd { "git", "log", "--max-count=1", "--pretty=%s" }
		msgNeedsFixing = lastCommitMsg
	end

	setupInputField()
	local icon = require("tinygit.config").config.appearance.mainIcon
	local prompt = vim.trim(icon .. " Amend only message")
	require("dressing.input")({ prompt = prompt, default = msgNeedsFixing }, function(commitMsg)
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
		local extra = (opts.forcePushIfDiverged and prevCommitWasPushed) and "Force pushing…" or nil
		postCommitNotif("Amend only message", false, processedMsg, extra)
		if opts.forcePushIfDiverged and prevCommitWasPushed then
			push({ forceWithLease = true }, true)
		end

		updateStatusline()
	end)
end

---@param opts? { selectFromLastXCommits?: number, squashInstead: boolean, autoRebase?: boolean }
function M.fixupCommit(opts)
	vim.cmd("silent update")
	if u.notInGitRepo() or hasNoChanges() then return end

	local defaultOpts = { selectFromLastXCommits = 15, autoRebase = false }
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
	local icon = require("tinygit.config").config.appearance.mainIcon
	local prompt = vim.trim(icon .. " Select commit to fixup")
	vim.ui.select(commits, {
		prompt = prompt,
		format_item = selectCommit.selectorFormatter,
		kind = "tinygit.fixupCommit",
	}, function(commit)
		closeNotifications()
		vim.api.nvim_del_autocmd(autocmdId)
		if not commit then return end

		-- stage
		local doStageAllChanges = hasNoStagedChanges()
		if doStageAllChanges then
			local _result = vim.system({ "git", "add", "--all" }):wait()
			if u.nonZeroExit(_result) then return end
		end

		-- commit
		local hash = commit:match("^%w+")
		local commitResult = vim.system({ "git", "commit", "--fixup", hash }):wait()
		if u.nonZeroExit(commitResult) then return end
		u.notify(commitResult.stdout, "info", { title = "Fixup commit" })

		-- rebase
		if opts.autoRebase then
			local _result = vim.system({
				"git",
				"-c",
				"sequence.editor=:", -- HACK ":" is a "no-op-"editor https://www.reddit.com/r/git/comments/uzh2no/what_is_the_utility_of_noninteractive_rebase/
				"rebase",
				"--interactive",
				"--committer-date-is-author-date", -- preserves dates
				"--autostash",
				"--autosquash",
				hash .. "^", -- rebase up until the selected commit
			}):wait()
			if u.nonZeroExit(_result) then return end

			vim.cmd.checktime() -- reload in case of conflicts
			u.notify("Auto-rebase applied.", "info", { title = "Fixup commit" })
		end

		updateStatusline()
	end)
end

--------------------------------------------------------------------------------
return M
