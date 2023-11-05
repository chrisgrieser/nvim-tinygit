local M = {}
local fn = vim.fn
local u = require("tinygit.utils")
local config = require("tinygit.config").config.commitMsg
local push = require("tinygit.push").push
--------------------------------------------------------------------------------

---@nodiscard
---@return boolean
local function hasStagedChanges()
	fn.system { "git", "diff", "--staged", "--quiet" }
	local hasStaged = vim.v.shell_error == 0
	return hasStaged
end

---@nodiscard
---@return boolean
local function hasNoUnstagedChanges()
	fn.system { "git", "diff", "--quiet" }
	-- SIC yes, in this case the meaning of the exit codes 1 and 0 is indeed
	-- switched as compared to `--staged`, for whatever reason. Thus, the exit
	-- code 0 means *no* changes here.
	local hasNoUnstaged = vim.v.shell_error == 0
	return hasNoUnstaged
end

---process a commit message: length, not empty, adheres to conventional commits
---@param commitMsg string
---@nodiscard
---@return boolean is the commit message valid?
---@return string the (modified) commit message
local function processCommitMsg(commitMsg)
	commitMsg = vim.trim(commitMsg)

	if #commitMsg > config.maxLen then
		u.notify("Commit Message too long.", "warn")
		local shortenedMsg = commitMsg:sub(1, config.maxLen)
		return false, shortenedMsg
	elseif commitMsg == "" then
		if not config.emptyFillIn then
			u.notify("Commit Message empty.", "warn")
			return false, ""
		else
			return true, config.emptyFillIn
		end
	end

	if config.enforceConvCommits.enabled then
		local firstWord = commitMsg:match("^%w+")
		if not vim.tbl_contains(config.enforceConvCommits.keywords, firstWord) then
			u.notify("Not using a Conventional Commits keyword.", "warn")
			return false, commitMsg
		end
	end

	-- message ok
	return true, commitMsg
end

-- Uses ColorColumn to indicate max length of commit messages, and
-- additionally colors commit messages that are too long in red.
local function setGitCommitAppearance()
	vim.api.nvim_create_autocmd("FileType", {
		pattern = "DressingInput",
		once = true, -- do not affect other DressingInputs
		callback = function()
			local ns = vim.api.nvim_create_namespace("tinygit.commit_input")
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
			vim.api.nvim_buf_set_name(0, "COMMIT_EDITMSG")

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
	local titlePrefix = "tinygit"
	local lines = { commitMsg }
	if stagedAllChanges then table.insert(lines, 1, "Staged all changes.") end
	if extra then table.insert(lines, extra) end
	local text = table.concat(lines, "\n")

	vim.notify(text, vim.log.levels.INFO, {
		title = titlePrefix .. ": " .. title,
		on_open = function(win)
			-- HACK manually creating gitcommit highlighting, since fn.matchadd does
			-- not work in a non-focussed window and since setting the filetype to
			-- "gitcommit" does not work well with nvim-notify
			local buf = vim.api.nvim_win_get_buf(win)
			local ns = vim.api.nvim_create_namespace("tinygit.commit_notify")
			vim.api.nvim_win_set_hl_ns(win, ns)
			local lastLine = vim.api.nvim_buf_line_count(buf) - 1
			local hl = vim.api.nvim_buf_add_highlight

			local commitMsgLine = extra and lastLine - 1 or lastLine
			local ccKeywordStart, _, ccKeywordEnd, ccScopeEnd = commitMsg:find("^%a+()%b()():")
			if not ccKeywordStart then
				-- has cc keyword, but not scope
				ccKeywordStart, _, ccKeywordEnd = commitMsg:find("^%a+():")
			end
			if ccKeywordStart then hl(buf, ns, "@keyword", commitMsgLine, ccKeywordStart, ccKeywordEnd) end
			if ccScopeEnd then
				local ccScopeStart = ccKeywordEnd
				hl(buf, ns, "@parameter", commitMsgLine, ccScopeStart + 1, ccScopeEnd - 1)
			end

			local mdInlineCodeStart, mdInlineCodeEnd = commitMsg:find("`(.-)`")
			if mdInlineCodeStart and mdInlineCodeEnd then
				hl(buf, ns, "@text.literal", commitMsgLine, mdInlineCodeStart + 1, mdInlineCodeEnd)
			end

			local issueNumberStart, issueNumberEnd = commitMsg:find("#%d+")
			if issueNumberStart then
				-- stylua: ignore
				hl(buf, ns, "@number", commitMsgLine, issueNumberStart, issueNumberEnd + 1)
			end

			if stagedAllChanges then hl(buf, ns, "Comment", 1, 0, -1) end
			if extra then hl(buf, ns, "Comment", lastLine, 0, -1) end
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

	local doStageAllChanges = hasStagedChanges()
	-- When committing with no staged changes, all changes are staged, resulting
	-- in a clean repo afterwards. Alternatively, if there are no unstaged
	-- changes, the repo will also be clean after committing. If one of the two
	-- conditions is fulfilled, we can safely push after committing.
	local cleanAfterCommit = hasNoUnstagedChanges() or doStageAllChanges

	local title = "Commit"
	if doStageAllChanges then title = "Stage All · " .. title end
	if cleanAfterCommit and opts.pushIfClean then title = title .. " · Push" end

	setGitCommitAppearance()

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
			extra = "(not pushing since repo still dirty)"
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
	if not opts then opts = {} end
	vim.cmd("silent update")
	if u.notInGitRepo() then return end

	local stageAllChanges = hasStagedChanges()
	if stageAllChanges then
		local stderr = fn.system { "git", "add", "-A" }
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
	if not opts then opts = {} end
	vim.cmd("silent update")

	-- GUARD
	if u.notInGitRepo() then return end
	if hasStagedChanges() then
		u.notify("Aborting: There are staged changes.", "warn", "Amend Only Msg")
		return
	end

	if not prefillMsg then
		local lastCommitMsg = vim.trim(fn.system { "git", "log", "-n1", "--pretty=%s" })
		prefillMsg = lastCommitMsg
	end
	setGitCommitAppearance()

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

---@param userOpts { selectFromLastXCommits?: number, squashInstead: boolean }
function M.fixupCommit(userOpts)
	local defaultOpts = {
		selectFromLastXCommits = 15,
		squashInstead = false,
	}
	local opts = vim.tbl_deep_extend("force", defaultOpts, userOpts)

	local response = fn.system {
		"git",
		"log",
		"-n" .. tostring(opts.selectFromLastXCommits),
		"--format=%h\t%s\t%cr\t%cn", -- format: hash, subject, date, author
	}

	-- GUARD
	if u.nonZeroExit(response) then return end
	local commits = vim.split(vim.trim(response), "\n")

	local title = opts.squashInstead and "Squash" or "Fixup"

	vim.ui.select(commits, {
		prompt = ("󰊢 Select Commit to %s"):format(title),
		format_item = u.commitListFormatter,
		kind = "):format()tinygit.fixupCommit",
	}, function(commit)
		if not commit then return end
		local hash = commit:match("^%w+")
		local fixupOrSquash = opts.squashInstead and "--squash" or "--fixup"

		local stdout = fn.system { "git", "commit", fixupOrSquash, hash }
		if u.nonZeroExit(stdout) then return end

		u.notify(stdout, "info", title .. " Commit")
	end)
end

--------------------------------------------------------------------------------
return M
