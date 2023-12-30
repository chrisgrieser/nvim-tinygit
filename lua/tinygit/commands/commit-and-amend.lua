local selectCommit = require("tinygit.shared.select-commit")
local u = require("tinygit.shared.utils")
local config = require("tinygit.config").config.commitMsg
local push = require("tinygit.commands.push").push

local M = {}
local fn = vim.fn
--------------------------------------------------------------------------------

---@nodiscard
---@return boolean
local function hasNoStagedChanges()
	fn.system { "git", "diff", "--staged", "--quiet" }
	local hasNoStaged = vim.v.shell_error == 0
	return hasNoStaged
end

---@nodiscard
---@return boolean
local function hasNoUnstagedChanges()
	fn.system { "git", "diff", "--quiet" }
	local hasNoUnstaged = vim.v.shell_error == 0
	return hasNoUnstaged
end

---process a commit message: length, not empty, adheres to conventional commits
---@param commitMsg string
---@nodiscard
---@return boolean -- is the commit message valid?
---@return string -- the (modified) commit message
local function processCommitMsg(commitMsg)
	commitMsg = vim.trim(commitMsg)

	if #commitMsg > config.maxLen then
		u.notify("Commit Message too long.", "warn")
		local shortenedMsg = commitMsg:sub(1, config.maxLen)
		return false, shortenedMsg
	elseif commitMsg == "" then
		if type(config.emptyFillIn) == "string" then
			return true, config.emptyFillIn ---@diagnostic disable-line: return-type-mismatch
		else
			u.notify("Commit Message empty.", "warn")
			return false, ""
		end
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

local function setupInputField()
	vim.api.nvim_create_autocmd("FileType", {
		pattern = "DressingInput",
		once = true, -- do not affect other DressingInputs
		callback = function(ctx)
			local ns = vim.api.nvim_create_namespace("tinygit.inputField")
			vim.api.nvim_win_set_hl_ns(0, ns)

			-- custom highlighting
			-- (INFO the order the highlights are added matters, later has priority)
			fn.matchadd("issueNumber", [[#\d\+]])
			vim.api.nvim_set_hl(ns, "issueNumber", { link = "Number" })

			fn.matchadd("mdInlineCode", [[`.\{-}`]]) -- .\{-} = non-greedy quantifier
			vim.api.nvim_set_hl(ns, "mdInlineCode", { link = "@text.literal" })

			fn.matchadd("overLength", ([[.\{%s}\zs.*\ze]]):format(config.maxLen - 1))
			vim.api.nvim_set_hl(ns, "overLength", { link = "ErrorMsg" })

			fn.matchadd(
				"closeToOverlength",
				-- \ze = end of match, \zs = start of match
				([[.\{%s}\zs.\{1,%s}\ze]]):format(config.mediumLen, config.maxLen - config.mediumLen)
			)
			vim.api.nvim_set_hl(ns, "closeToOverlength", { link = "WarningMsg" })

			-- colorcolumn as extra indicators of overLength
			vim.opt_local.colorcolumn = { config.mediumLen, config.maxLen }

			-- treesitter highlighting
			vim.bo.filetype = "gitcommit"
			vim.api.nvim_set_hl(ns, "@text.title.gitcommit", { link = "Normal" })
			-- prevent auto-wrapping due to filetype "gitcommit" being set
			vim.opt_local.formatoptions:remove("t")

			-- activates styling for statusline plugins (e.g., filename icons)
			vim.api.nvim_buf_set_name(ctx.buf, "COMMIT_EDITMSG")

			-- spellcheck
			if config.spellcheck then
				vim.opt_local.spell = true
				vim.opt_local.spelloptions = "camel"
				vim.opt_local.spellcapcheck = ""
			end
		end,
	})
end

---@param title string title for nvim-notify
---@param stagedAllChanges boolean
---@param commitMsg string
---@param extra? string extra lines to display
local function commitNotification(title, stagedAllChanges, commitMsg, extra)
	local lines = { commitMsg }
	if stagedAllChanges then table.insert(lines, 1, "Staged all changes.") end
	if extra then table.insert(lines, extra) end
	local text = table.concat(lines, "\n")

	vim.notify(text, vim.log.levels.INFO, {
		title = "tinygit: " .. title,
		on_open = function(win)
			local ns = vim.api.nvim_create_namespace("tinygit.commitNotification")
			local bufnr = vim.api.nvim_win_get_buf(win)

			-- commented info lines
			local lastLine = vim.api.nvim_buf_line_count(bufnr) - 1
			if stagedAllChanges then vim.api.nvim_buf_add_highlight(bufnr, ns, "Comment", 1, 0, -1) end
			if extra then vim.api.nvim_buf_add_highlight(bufnr, ns, "Comment", lastLine, 0, -1) end

			-- commit msg custom highlights
			vim.api.nvim_buf_call(bufnr, function()
				-- INFO using namespace in here does not work, therefore simply
				-- using `matchadd`, since it is restricted to the current window anyway
				-- INFO the order the highlights are added matters, later has priority
				fn.matchadd("Number", [[#\d\+]]) -- issues number
				fn.matchadd("@text.literal", [[`.\{-}`]]) -- inline code (.\{-} = non-greedy quantifier)
				-- setting the filetype to "gitcommit" does not work well with
				-- nvim-notify, therefore manually highlighting conventional commits
				fn.matchadd(
					"Title",
					[[\v(feat|fix|test|perf|build|ci|revert|refactor|chore|docs|break|improv|style)(!|(.{-}))?\ze:]]
				)
			end)
		end,
	})
end

---The notification makes it more transparent to the user what is going to be
---committed. (This is similar to the commented out lines at the bottom of a git
---message in the terminal.)
function M.notifyWhatChanged()
	local width = 50
	local diffStatsCmd = { "git", "diff", "--compact-summary", "--stat=" .. tostring(width) }
	local willStageAllChanges = hasNoStagedChanges()
	local title
	if willStageAllChanges then
		title = "To be staged & committed"
		-- so new files show up in the diff stats
		fn.system("git ls-files --others --exclude-standard | xargs git add --intent-to-add")
	else
		title = "Staged Changes"
		table.insert(diffStatsCmd, "--staged")
	end

	local changes = vim.trim(vim.fn.system(diffStatsCmd))
	local changesWithoutSummary = changes:gsub("\n[^\n]*$", "")

	vim.notify(changesWithoutSummary, vim.log.levels.INFO, {
		title = "tinygit: " .. title,
		on_open = function(win)
			local bufnr = vim.api.nvim_win_get_buf(win)
			vim.api.nvim_buf_call(bufnr, function()
				-- INFO using namespace in here does not work, therefore simply
				-- using `matchadd`, since it is restricted to the current window anyway
				fn.matchadd("diffAdded", [[ +\+]]) -- color the plus/minus like in the terminal
				fn.matchadd("diffRemoved", [[-\+\s*$]])
				fn.matchadd("Keyword", [[(new.*)]])
			end)
		end,
	})
end

--------------------------------------------------------------------------------

---If there are staged changes, commit them.
---If there aren't, add all changes (`git add -A`) and then commit.
---@param prefillMsg? string used internally when calling this function recursively due to corrected commit message
---@param opts? { pushIfClean?: boolean }
function M.smartCommit(opts, prefillMsg)
	if u.notInGitRepo() then return end

	vim.cmd("silent update")
	if not opts then opts = {} end
	if not prefillMsg then prefillMsg = "" end

	local doStageAllChanges = hasNoStagedChanges()
	-- When committing with no staged changes, all changes are staged, resulting
	-- in a clean repo afterwards. Alternatively, if there are no unstaged
	-- changes, the repo will also be clean after committing. If one of the two
	-- conditions is fulfilled, we can safely push after committing.
	local cleanAfterCommit = hasNoUnstagedChanges() or doStageAllChanges

	local title = "Commit"
	if doStageAllChanges then title = "Stage All · " .. title end
	if cleanAfterCommit and opts.pushIfClean then title = title .. " · Push" end

	M.notifyWhatChanged()

	setupInputField()
	vim.ui.input({ prompt = "󰊢 " .. title, default = prefillMsg }, function(commitMsg)
		if not commitMsg then return end -- aborted input modal
		local validMsg, processedMsg = processCommitMsg(commitMsg)
		if not validMsg then -- if msg invalid, run again to fix the msg
			M.smartCommit(opts, processedMsg)
			return
		end

		if doStageAllChanges then
			local stderr = fn.system { "git", "add", "-A" }
			if u.nonZeroExit(stderr) then return end
		end

		local stderr = fn.system { "git", "commit", "-m", processedMsg }
		if u.nonZeroExit(stderr) then return end

		local extra = nil
		if opts.pushIfClean and cleanAfterCommit then
			extra = "Pushing…"
		elseif opts.pushIfClean and not cleanAfterCommit then
			extra = "Not pushing since repo still dirty."
		end
		commitNotification("Smart Commit", doStageAllChanges, processedMsg, extra)

		local issueReferenced = processedMsg:match("#(%d+)")
		if config.openReferencedIssue and issueReferenced then
			local url = ("https://github.com/%s/issues/%s"):format(u.getRepo(), issueReferenced)
			u.openUrl(url)
		end

		if opts.pushIfClean and cleanAfterCommit then push { pullBefore = true } end
	end)
end

---@param opts? { forcePush?: boolean }
function M.amendNoEdit(opts)
	if u.notInGitRepo() then return end

	if not opts then opts = {} end
	vim.cmd("silent update")

	local stageAllChanges = hasNoStagedChanges()
	if stageAllChanges then
		local stderr = fn.system { "git", "add", "--all" }
		if u.nonZeroExit(stderr) then return end
	end

	local stderr = fn.system { "git", "commit", "--amend", "--no-edit" }
	if u.nonZeroExit(stderr) then return end

	local lastCommitMsg = vim.trim(fn.system("git log -1 --format=%s"))
	local extra = opts.forcePush and "Force Pushing…" or nil
	commitNotification("Amend-No-Edit", stageAllChanges, lastCommitMsg, extra)

	if opts.forcePush then push { force = true } end
end

---@param opts? { forcePush?: boolean }
---@param prefillMsg? string used internally when calling this function recursively due to corrected commit message
function M.amendOnlyMsg(opts, prefillMsg)
	-- GUARD
	if u.notInGitRepo() then return end
	if not hasNoStagedChanges() then
		u.notify("Aborting: There are staged changes.", "warn", "Amend Only Msg")
		return
	end

	if not opts then opts = {} end
	vim.cmd("silent update")

	if not prefillMsg then
		local lastCommitMsg = vim.trim(fn.system { "git", "log", "-n1", "--pretty=%s" })
		prefillMsg = lastCommitMsg
	end

	setupInputField()
	vim.ui.input({ prompt = "󰊢 Amend Message", default = prefillMsg }, function(commitMsg)
		if not commitMsg then return end -- aborted input modal
		local validMsg, processedMsg = processCommitMsg(commitMsg)
		if not validMsg then -- if msg invalid, run again to fix the msg
			M.amendOnlyMsg(opts, processedMsg)
			return
		end

		local stderr = fn.system { "git", "commit", "--amend", "-m", processedMsg }
		if u.nonZeroExit(stderr) then return end

		commitNotification("Amend Message", false, processedMsg)

		local issueReferenced = processedMsg:match("#(%d+)")
		if config.openReferencedIssue and issueReferenced then
			local url = ("https://github.com/%s/issues/%s"):format(u.getRepo(), issueReferenced)
			u.openUrl(url)
		end

		if opts.forcePush then push { force = true } end
	end)
end

---@param userOpts { selectFromLastXCommits?: number, squashInstead: boolean, autoRebase?: boolean }
function M.fixupCommit(userOpts)
	local defaultOpts = {
		selectFromLastXCommits = 15,
		squashInstead = false,
		autoRebase = false,
	}
	local opts = vim.tbl_deep_extend("force", defaultOpts, userOpts)

	local response = fn.system {
		"git",
		"log",
		"-n" .. tostring(opts.selectFromLastXCommits),
		"--format=" .. selectCommit.gitlogFormat,
	}

	-- GUARD
	if u.nonZeroExit(response) then return end
	local commits = vim.split(vim.trim(response), "\n")

	local autocmdId = selectCommit.setupAppearance()
	local title = opts.squashInstead and "Squash" or "Fixup"
	vim.ui.select(commits, {
		prompt = ("󰊢 Select Commit to %s"):format(title),
		format_item = selectCommit.selectorFormatter,
		kind = "tinygit.fixupCommit",
	}, function(commit)
		vim.api.nvim_del_autocmd(autocmdId)
		if not commit then return end
		local hash = commit:match("^%w+")
		local fixupOrSquash = opts.squashInstead and "--squash" or "--fixup"

		local stdout = fn.system { "git", "commit", fixupOrSquash, hash }
		if u.nonZeroExit(stdout) then return end
		u.notify(stdout, "info", title .. " Commit")

		if opts.autoRebase then
			stdout = fn.system {
				"git",
				"-c",
				"sequence.editor=:", -- HACK ":" is a "no-op-"editor https://www.reddit.com/r/git/comments/uzh2no/what_is_the_utility_of_noninteractive_rebase/
				"rebase",
				"--interactive",
				"--autostash",
				"--autosquash",
				hash .. "^", -- rebase up until the selected commit
			}
			if u.nonZeroExit(stdout) then return end
			u.notify(stdout, "info", "Auto Rebase applied")
		end
	end)
end

--------------------------------------------------------------------------------
return M
