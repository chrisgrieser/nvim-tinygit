local M = {}

local highlight = require("tinygit.shared.highlights")
local u = require("tinygit.shared.utils")
local push = require("tinygit.commands.push-pull").push
local updateStatusline = require("tinygit.statusline").updateAllComponents
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

---@param notifTitle string
---@param doStageAllChanges boolean
---@param commitTitle string
---@param extraLines string
local function postCommitNotif(notifTitle, doStageAllChanges, commitTitle, extraLines)
	local stageAllText = "Staged all changes."

	-- if using `snacks.nvim` or `nvim-notify`, add extra highlighting to the notification
	if package.loaded["snacks"] or package.loaded["notify"] then
		vim.api.nvim_create_autocmd("FileType", {
			pattern = { "noice", "notify", "snacks_notif" },
			once = true,
			callback = function(ctx)
				vim.defer_fn(function()
					vim.api.nvim_buf_call(ctx.buf, function()
						highlight.commitType()
						highlight.inlineCodeAndIssueNumbers()
						vim.fn.matchadd("Comment", stageAllText)
						vim.fn.matchadd("Comment", extraLines)
					end)
				end, 1)
			end,
		})
	end

	local lines = { commitTitle, extraLines }
	if doStageAllChanges then table.insert(lines, 1, stageAllText) end
	u.notify(table.concat(lines, "\n"), "info", { title = notifTitle })
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

	local inputMode = doStageAllChanges and "stage-all-and-commit" or "commit"

	-- check if pre-commit would pass before opening message input
	local preCommitResult = vim.system({ "git", "hook", "run", "--ignore-missing", "pre-commit" })
		:wait()
	if u.nonZeroExit(preCommitResult) then return end

	require("tinygit.commands.commit.msg-input").new(inputMode, prompt, function(title, body)
		-- stage
		if doStageAllChanges then
			local result = vim.system({ "git", "add", "--all" }):wait()
			if u.nonZeroExit(result) then return end
		end

		-- commit
		-- (using `--no-verify`, since we checked the pre-commit earlier already)
		local commitArgs = { "git", "commit", "--no-verify", "--message=" .. title }
		if body then table.insert(commitArgs, "--message=" .. body) end
		local result = vim.system(commitArgs):wait()
		if u.nonZeroExit(result) then return end

		-- notification
		local extra = ""
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
	if not opts then opts = {} end

	local prompt = "Amend message"

	require("tinygit.commands.commit.msg-input").new("amend-msg", prompt, function(title, body)
		-- commit
		-- (skip precommit via `--no-verify`, since only editing message)
		local commitArgs = { "git", "commit", "--no-verify", "--amend", "--message=" .. title }
		if body then table.insert(commitArgs, "--message=" .. body) end
		local result = vim.system(commitArgs):wait()
		if u.nonZeroExit(result) then return end

		-- push & notification
		local prevCommitWasPushed = u.syncShellCmd({ "git", "branch", "--verbose" })
			:find("%[ahead 1, behind 1%]")
		local extra = ""
		if opts.forcePushIfDiverged and prevCommitWasPushed then
			push({ forceWithLease = true }, true)
			extra = "Force pushing…"
		end
		postCommitNotif(prompt, false, title, extra)

		updateStatusline()
	end)
end

---@param opts? { selectFromLastXCommits?: number, squashInstead: boolean, autoRebase?: boolean }
function M.fixupCommit(opts)
	-- GUARD
	if u.notInGitRepo() or hasNoChanges() then return end
	local installed, _ = pcall(require, "telescope")
	if not installed then
		u.notify("telescope.nvim is not installed.", "warn")
		return
	end

	local defaultOpts = { selectFromLastXCommits = 15, autoRebase = false }
	opts = vim.tbl_deep_extend("force", defaultOpts, opts or {})

	-- get commits
	local gitlogFormat = "%h\t%s\t%cr" -- hash, subject, date, `\t` as delimiter required
	local result = vim.system({
		"git",
		"log",
		"-n" .. tostring(opts.selectFromLastXCommits),
		"--format=" .. gitlogFormat,
	}):wait()
	if u.nonZeroExit(result) then return end
	local commits = vim.split(vim.trim(result.stdout), "\n")

	-- user selection of commit
	local icon = require("tinygit.config").config.appearance.mainIcon
	local prompt = vim.trim(icon .. " Select commit to fixup")
	local commitFormatter = function(commitLine)
		local _, subject, date, nameAtCommit = unpack(vim.split(commitLine, "\t"))
		local displayLine = ("%s\t%s"):format(subject, date)
		-- append name at commit, if it exists
		if nameAtCommit then displayLine = displayLine .. ("\t(%s)"):format(nameAtCommit) end
		return displayLine
	end
	local stylingFunc = function()
		local hl = require("tinygit.shared.highlights")
		hl.commitType()
		hl.inlineCodeAndIssueNumbers()
		vim.fn.matchadd("Comment", [[\t.*$]])
	end
	local onChoice = function(commit)
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
	end

	require("tinygit.shared.picker").withTelescope(
		prompt,
		commits,
		commitFormatter,
		stylingFunc,
		onChoice
	)
end

--------------------------------------------------------------------------------
return M
