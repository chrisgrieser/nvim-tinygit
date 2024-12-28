local M = {}
local u = require("tinygit.shared.utils")
--------------------------------------------------------------------------------

---@class (exact) Tinygit.Hunk
---@field absPath string
---@field relPath string
---@field lnum number
---@field added number
---@field removed number
---@field patch string
---@field alreadyStaged boolean
---@field fileMode Tinygit.FileMode

---@param msg string
---@param level? Tinygit.notifyLevel
---@param opts? table
local function notify(msg, level, opts)
	if not opts then opts = {} end
	opts.title = "Staging"
	u.notify(msg, level, opts)
end

--------------------------------------------------------------------------------

---@return number
function M.getContextSize()
	-- CAVEAT context=0 is not supported without `--unidiff-zero`
	-- DOCS https://git-scm.com/docs/git-apply#Documentation/git-apply.txt---unidiff-zero
	-- However, it is discouraged in the git manual, and the `git apply` tends to
	-- fail quite often, probably as line count changes are not accounted for
	-- when splitting up changes into hunks in `getHunksFromDiffOutput`.
	-- Using context=1 works, but has the downside of not being 1:1 the same
	-- hunks as with `gitsigns.nvim`. Since many small hunks are actually abit
	-- cumbersome, and since it's discouraged by git anyway, we simply disallow
	-- context=0 for now.
	local contextSize = require("tinygit.config").config.stage.contextSize
	if contextSize < 1 then contextSize = 0 end
	return contextSize
end

---@param diffCmdStdout string
---@param diffIsOfStaged boolean
---@return Tinygit.Hunk[] hunks
local function getHunksFromDiffOutput(diffCmdStdout, diffIsOfStaged)
	local splitOffDiffHeader = require("tinygit.shared.diff").splitOffDiffHeader

	if diffCmdStdout == "" then return {} end -- no hunks
	local gitroot = u.syncShellCmd { "git", "rev-parse", "--show-toplevel" }
	local changesPerFile = vim.split(diffCmdStdout, "\ndiff --git a/", { plain = true })

	-- Loop through each file, and then through each hunk of that file. Construct
	-- flattened list of hunks, each with their own diff header, so they work as
	-- independent patches. Those patches in turn are needed for `git apply`
	-- stage only part of a file.
	---@type Tinygit.Hunk[]
	local hunks = {}
	for _, file in ipairs(changesPerFile) do
		if not vim.startswith(file, "diff --git a/") then -- first file still has this
			file = "diff --git a/" .. file -- needed to make patches valid
		end
		-- split off diff header
		local diffLines = vim.split(file, "\n")
		local changesInFile, diffHeaderLines, fileMode, _ = splitOffDiffHeader(diffLines)
		local diffHeader = table.concat(diffHeaderLines, "\n")
		local relPath = diffHeaderLines[1]:match("b/(.+)") or "ERROR: path not found"
		local absPath = gitroot .. "/" .. relPath

		-- split remaining output into hunks
		local hunksInFile = {}
		for _, line in ipairs(changesInFile) do
			if vim.startswith(line, "@@") then
				table.insert(hunksInFile, line)
			else
				hunksInFile[#hunksInFile] = hunksInFile[#hunksInFile] .. "\n" .. line
			end
		end

		-- special case: file renamed without any other changes
		-- (needs to be handled separately because it has no hunks, that is no `@@` lines)
		if #changesInFile == 0 and (fileMode == "renamed" or fileMode == "binary") then
			---@type Tinygit.Hunk
			local hunkObj = {
				absPath = absPath,
				relPath = relPath,
				lnum = -1,
				added = 0,
				removed = 0,
				patch = diffHeader .. "\n",
				alreadyStaged = diffIsOfStaged,
				fileMode = fileMode,
			}
			table.insert(hunks, hunkObj)
		end

		-- loop hunks
		for _, hunk in ipairs(hunksInFile) do
			-- meaning of @@-line: https://www.gnu.org/software/diffutils/manual/html_node/Detailed-Unified.html
			local lnum = tonumber(hunk:match("^@@ .- %+(%d+)"))
			assert(lnum, "lnum not found.")

			-- not from `@@` line, since number includes lines between two changes and context lines
			local _, added = hunk:gsub("\n%+", "")
			local _, removed = hunk:gsub("\n%-", "")

			-- needs trailing newline for valid patch
			local patch = diffHeader .. "\n" .. hunk .. "\n"

			---@type Tinygit.Hunk
			local hunkObj = {
				absPath = absPath,
				relPath = relPath,
				lnum = lnum,
				added = added,
				removed = removed,
				patch = patch,
				alreadyStaged = diffIsOfStaged,
				fileMode = fileMode,
			}
			table.insert(hunks, hunkObj)
		end
	end
	return hunks
end

-- `git apply` to stage only part of a file https://stackoverflow.com/a/66618356/22114136
---@param hunk Tinygit.Hunk
---@param mode "toggle" | "reset"
---@return boolean success
function M.applyPatch(hunk, mode)
	local args = {
		"git",
		"apply",
		"--verbose", -- so the error messages are more informative
		"-", -- read patch from stdin
	}
	if mode == "toggle" then
		table.insert(args, "--cached") -- = only affect staging area, not working tree
		if hunk.alreadyStaged then table.insert(args, "--reverse") end
	elseif mode == "reset" then
		assert(hunk.alreadyStaged == false, "A staged hunk cannot be reset, unstage it first.")
		table.insert(args, "--reverse") -- undoing patch
	end
	local applyResult = vim.system(args, { stdin = hunk.patch }):wait()

	local success = applyResult.code == 0
	if success and mode == "reset" then
		vim.cmd.checktime() -- refresh buffer
		local filename = vim.fs.basename(hunk.absPath)
		notify(('Hunk "%s:%s" reset.'):format(filename, hunk.lnum))
	end
	if not success then notify(applyResult.stderr, "error") end
	return success
end

--------------------------------------------------------------------------------

function M.interactiveStaging()
	vim.cmd("silent! update")

	-- GUARD prerequisites not met
	local installed = pcall(require, "telescope")
	if not installed then
		notify("This feature requires `nvim-telescope`.", "warn")
		return
	end
	if u.notInGitRepo() then return end
	local noChanges = u.syncShellCmd { "git", "status", "--porcelain" } == ""
	if noChanges then
		notify("There are no staged or unstaged changes.", "warn")
		return
	end

	-- GET ALL HUNKS
	u.intentToAddUntrackedFiles() -- include untracked files, enables using `--diff-filter=A`

	local diffArgs = { "git", "diff", "--unified=" .. M.getContextSize(), "--diff-filter=ADMR" }
	-- no trimming, since trailing empty lines can be blank context lines in diff output
	local changesDiff = u.syncShellCmd(diffArgs, "notrim")
	local changedHunks = getHunksFromDiffOutput(changesDiff, false)

	table.insert(diffArgs, "--staged")
	local stagedDiff = u.syncShellCmd(diffArgs, "notrim")
	local stagedHunks = getHunksFromDiffOutput(stagedDiff, true)

	local allHunks = vim.list_extend(changedHunks, stagedHunks)

	-- START TELESCOPE PICKER
	vim.api.nvim_create_autocmd("FileType", {
		once = true,
		pattern = "TelescopeResults",
		callback = function(ctx) require("tinygit.shared.backdrop").new(ctx.buf) end,
	})
	require("tinygit.commands.stage.telescope").pickHunk(allHunks)
end
--------------------------------------------------------------------------------
return M
