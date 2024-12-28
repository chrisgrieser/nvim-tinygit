local M = {}

local selectCommit = require("tinygit.shared.select-commit")
local u = require("tinygit.shared.utils")
local push = require("tinygit.commands.push-pull").push
local updateStatusline = require("tinygit.statusline").updateAllComponents
local highlight = require("tinygit.shared.highlights")

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
	vim.cmd("silent update")
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

--------------------------------------------------------------------------------

---@param opts? { pushIfClean?: boolean, pullBeforePush?: boolean }
function M.smartCommit(opts)
	if u.notInGitRepo() or hasNoChanges() then return end

	local defaultOpts = { pushIfClean = false, pullBeforePush = true }
	opts = vim.tbl_deep_extend("force", defaultOpts, opts or {})

	local doStageAllChanges = hasNoStagedChanges()
	local cleanAfterCommit = hasNoUnstagedChanges() or doStageAllChanges

	local prompt = "Commit"
	if doStageAllChanges then prompt = "Stage all · " .. prompt:lower() end
	if cleanAfterCommit and opts.pushIfClean then prompt = prompt .. " · push" end

	require("tinygit.commands.commit.msg-input").new("commit", prompt, function(title, body)
		-- stage
		if doStageAllChanges then
			local result = vim.system({ "git", "add", "--all" }):wait()
			if u.nonZeroExit(result) then return end
		end

		-- commit
		local commitArgs = { "git", "commit", "--message=" .. title }
		if body then table.insert(commitArgs, "--message=" .. body) end
		local result = vim.system(commitArgs):wait()
		if u.nonZeroExit(result) then return end

		-- notification
		local extra = nil
		if opts.pushIfClean then
			extra = cleanAfterCommit and "Pushing…" or "Not pushing since repo still dirty."
		end
		postCommitNotif("Smart commit", doStageAllChanges, title, extra)

		-- push
		if opts.pushIfClean and cleanAfterCommit then
			push({ pullBefore = opts.pullBeforePush }, true)
		end

		updateStatusline()
	end)
end

---@param opts? { forcePushIfDiverged?: boolean, stageAllIfNothingStaged?: boolean }
function M.amendNoEdit(opts)
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
function M.amendOnlyMsg(opts)
	if u.notInGitRepo() then return end
	if not hasNoStagedChanges() then
		u.notify("Aborting: There are staged changes.", "warn", { title = "Amend only message" })
		return
	end
	if not opts then opts = {} end

	require("tinygit.commands.commit.msg-input").new("amend", "Amend message", function(title, body)
		-- commit
		local commitArgs = { "git", "commit", "--amend", "--message=" .. title }
		if body then table.insert(commitArgs, "--message=" .. body) end
		local result = vim.system(commitArgs):wait()
		if u.nonZeroExit(result) then return end

		-- push & notification
		local branchInfo = u.syncShellCmd { "git", "branch", "--verbose" }
		local prevCommitWasPushed = branchInfo:find("%[ahead 1, behind 1%]") ~= nil
		local extra = (opts.forcePushIfDiverged and prevCommitWasPushed) and "Force pushing…" or nil
		postCommitNotif("Amend message", false, title, extra)
		if opts.forcePushIfDiverged and prevCommitWasPushed then
			push({ forceWithLease = true }, true)
		end

		updateStatusline()
	end)
end

---@param opts? { selectFromLastXCommits?: number, squashInstead: boolean, autoRebase?: boolean }
function M.fixupCommit(opts)
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
	local autocmdId = selectCommit.setupAppearance()
	local icon = require("tinygit.config").config.appearance.mainIcon
	local prompt = vim.trim(icon .. " Select commit to fixup")
	vim.ui.select(commits, {
		prompt = prompt,
		format_item = selectCommit.selectorFormatter,
		kind = "tinygit.fixupCommit",
	}, function(commit)
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
