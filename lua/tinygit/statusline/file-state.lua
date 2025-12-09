local M = {}
--------------------------------------------------------------------------------

---@return string? state lualine stringifys result, so need to return empty string instead of nil
---@nodiscard
local function getFileState()
	if not vim.uv.cwd() then return end -- file without cwd

	local u = require("tinygit.shared.utils")
	local gitroot = u.syncShellCmd { "git", "rev-parse", "--show-toplevel" }
	if not gitroot then return "" end
	local gitStatus = vim.system({ "git", "-C", gitroot, "status", "--porcelain" }):wait()
	if gitStatus.code ~= 0 then return "" end

	local icons = {
		added = "+",
		modified = "~",
		deleted = "-",
		untracked = "?",
		renamed = "R",
	}

	local changes = vim.iter(vim.split(gitStatus.stdout, "\n")):fold({}, function(acc, line)
		local label = vim.trim(line:sub(1, 2))
		if #label > 1 then label = label:sub(1, 1) end -- prefer staged over unstaged
		local map = {
			["?"] = icons.untracked,
			A = icons.added,
			M = icons.modified,
			R = icons.renamed,
			D = icons.deleted,
		}
		local key = map[label]
		if key then acc[key] = (acc[key] or 0) + 1 end
		return acc
	end)

	local stateStr = ""
	for icon, count in pairs(changes) do
		stateStr = stateStr .. icon .. count .. " "
	end

	local icon = require("tinygit.config").config.statusline.fileState.icon
	return vim.trim(icon .. " " .. stateStr)
end

--------------------------------------------------------------------------------

function M.refreshFileState()
	local state = getFileState()
	if state then vim.b.tinygit_fileState = state end
end

function M.getFileState() return vim.b.tinygit_fileState or "" end

vim.api.nvim_create_autocmd({ "BufEnter", "DirChanged", "FocusGained" }, {
	group = vim.api.nvim_create_augroup("tinygit_fileState", { clear = true }),
	callback = function()
		-- defer so cwd changes take place before checking
		vim.defer_fn(M.refreshFileState, 1)
	end,
})
vim.defer_fn(M.refreshFileState, 1) -- initialize in case of lazy-loading

--------------------------------------------------------------------------------
return M
