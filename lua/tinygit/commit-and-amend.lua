local M = {}
local fn = vim.fn
local u = require("tinygit.utils")
local config = require("tinygit.config").config
local push = require("tinygit.push").push
--------------------------------------------------------------------------------

-- if there are no staged changes, will add all changes (`git add -A`)
-- if not, indicates the already staged changes
---@return boolean|nil stagedAllChanges nil if staging unsuccessful
local function stageAllIfNoChanges()
	fn.system { "git", "diff", "--staged", "--quiet" }
	local hasStagedChanges = vim.v.shell_error ~= 0
	if hasStagedChanges then return false end

	local stderr = fn.system { "git", "add", "-A" }
	if u.nonZeroExit(stderr) then return nil end
	return true
end

---process a commit message: length, not empty, adheres to conventional commits
---@param commitMsg string
---@nodiscard
---@return boolean is the commit message valid?
---@return string the (modified) commit message
local function processCommitMsg(commitMsg)
	commitMsg = vim.trim(commitMsg)
	local conf = config.commitMsg

	if #commitMsg > conf.maxLen then
		u.notify("Commit Message too long.", "warn")
		local shortenedMsg = commitMsg:sub(1, conf.maxLen)
		return false, shortenedMsg
	elseif commitMsg == "" then
		if not conf.emptyFillIn then
			u.notify("Commit Message empty.", "warn")
			return false, ""
		else
			return true, conf.emptyFillIn
		end
	end

	if conf.enforceConvCommits.enabled then
		-- stylua: ignore
		local firstWord = commitMsg:match("^%w+")
		if not vim.tbl_contains(conf.enforceConvCommits.keywords, firstWord) then
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
			local conf = config.commitMsg
			local winNs = 1
			vim.api.nvim_win_set_hl_ns(0, winNs)

			-- custom highlighting
			fn.matchadd("overLength", ([[.\{%s}\zs.*\ze]]):format(conf.maxLen - 1))
			vim.api.nvim_set_hl(winNs, "overLength", { link = "ErrorMsg" })

			fn.matchadd(
				"closeToOverlength",
				-- \ze = end of match, \zs = start of match
				([[.\{%s}\zs.\{1,%s}\ze]]):format(conf.mediumLen - 1, conf.maxLen - conf.mediumLen)
			)
			vim.api.nvim_set_hl(winNs, "closeToOverlength", { link = "WarningMsg" })

			fn.matchadd("issueNumber", [[#\d\+]])
			vim.api.nvim_set_hl(winNs, "issueNumber", { link = "Number" })

			fn.matchadd("mdInlineCode", [[`\zs.\+\ze`]])
			vim.api.nvim_set_hl(winNs, "mdInlineCode", { link = "@text.literal" })

			-- colorcolumn as extra indicators of overLength
			vim.opt_local.colorcolumn = { conf.mediumLen, conf.maxLen }

			-- treesitter highlighting
			vim.bo.filetype = "gitcommit"
			vim.api.nvim_set_hl(winNs, "Title", { link = "Normal" })

			-- activate styling of statusline plugins
			vim.api.nvim_buf_set_name(0, "COMMIT_EDITMSG")
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
			local buf, ns = vim.api.nvim_win_get_buf(win), 2
			vim.api.nvim_win_set_hl_ns(win, ns)
			local lastLine = vim.api.nvim_buf_line_count(buf) - 1
			local hl = vim.api.nvim_buf_add_highlight

			local commitMsgLine = extra and lastLine - 1 or lastLine
			local ccKeywordStart, _, ccKeywordEnd, ccScopeEnd = commitMsg:find("^%a+()%b()():")
			if not ccKeywordStart then
				-- has cc keyword, but not scope
				ccKeywordStart, _, ccKeywordEnd = commitMsg:find("^%a+():")
			end
			if ccKeywordStart then hl(buf, ns, "Keyword", commitMsgLine, ccKeywordStart, ccKeywordEnd) end
			if ccScopeEnd then
				local ccScopeStart = ccKeywordEnd
				hl(buf, ns, "@parameter", commitMsgLine, ccScopeStart + 1, ccScopeEnd - 1)
			end

			local mdInlineCodeStart, mdInlineCodeEnd = commitMsg:find("`(.+)`")
			if mdInlineCodeStart and mdInlineCodeEnd then
				hl(buf, ns, "@text.literal", commitMsgLine, mdInlineCodeStart + 1, mdInlineCodeEnd)
			end

			local issueNumberStart, issueNumberEnd = commitMsg:find("#%d+")
			if issueNumberStart then
				-- stylua: ignore
				hl(buf, ns, "Number", commitMsgLine, issueNumberStart, issueNumberEnd + 1)
			end

			if stagedAllChanges then hl(buf, ns, "Comment", 1, 0, -1) end
			if extra then hl(buf, ns, "Comment", lastLine, 0, -1) end
		end,
	})
end

--------------------------------------------------------------------------------

---If there are staged changes, commit them.
---If there aren't, add all changes (`git add -A`) and then commit.
---@param prefillMsg? string
---@param opts? { push?: boolean, openReferencedIssue?: boolean }
function M.smartCommit(opts, prefillMsg)
	if u.notInGitRepo() then return end

	vim.cmd("silent update")
	if not opts then opts = {} end
	if not prefillMsg then prefillMsg = "" end

	setGitCommitAppearance()
	vim.ui.input({ prompt = "󰊢 Commit Message", default = prefillMsg }, function(commitMsg)
		if not commitMsg then return end -- aborted input modal
		local validMsg, processedMsg = processCommitMsg(commitMsg)
		if not validMsg then -- if msg invalid, run again to fix the msg
			M.smartCommit(opts, processedMsg)
			return
		end

		local stagedAllChanges = stageAllIfNoChanges()
		if stagedAllChanges == nil then return end

		local stderr = fn.system { "git", "commit", "-m", processedMsg }
		if u.nonZeroExit(stderr) then return end

		local extra = opts.push and "Pushing…" or nil
		commitNotification("Smart-Commit", stagedAllChanges, processedMsg, extra)

		local issueReferenced = processedMsg:match("#(%d+)")
		if opts.openReferencedIssue and issueReferenced then
			local url = ("https://github.com/%s/issues/%s"):format(u.getRepo(), issueReferenced)
			u.openUrl(url)
		end

		if opts.push then push { pullBefore = true } end
	end)
end

---@param opts? { forcePush?: boolean }
function M.amendNoEdit(opts)
	if not opts then opts = {} end
	vim.cmd("silent update")
	if u.notInGitRepo() then return end

	local stagedAllChanges = stageAllIfNoChanges()
	if stagedAllChanges == nil then return end

	local stderr = fn.system { "git", "commit", "--amend", "--no-edit" }
	if u.nonZeroExit(stderr) then return end

	local lastCommitMsg = vim.trim(fn.system("git log -1 --pretty=%B"))
	local extra = opts.forcePush and "Force Pushing…" or nil
	commitNotification("Amend-No-Edit", stagedAllChanges, lastCommitMsg, extra)

	if opts.forcePush then push { force = true } end
end

---@param opts? { forcePush?: boolean }
---@param prefillMsg? string
function M.amendOnlyMsg(opts, prefillMsg)
	if not opts then opts = {} end
	vim.cmd("silent update")
	if u.notInGitRepo() then return end

	if not prefillMsg then
		local lastCommitMsg = vim.trim(fn.system("git log -1 --pretty=%B"))
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

		commitNotification("Amend-Only-Msg", false, processedMsg)

		if opts.forcePush then push { force = true } end
	end)
end

--------------------------------------------------------------------------------
return M