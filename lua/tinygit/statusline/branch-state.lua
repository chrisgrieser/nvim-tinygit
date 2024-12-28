local M = {}
--------------------------------------------------------------------------------

---@return string blame lualine stringifys result, so need to return empty string instead of nil
---@nodiscard
local function getBranchState()
	local cwd = vim.uv.cwd()
	if not cwd then return "" end -- file without cwd

	local allBranchInfo = vim.system({ "git", "-C", cwd, "branch", "--verbose" }):wait()
	if allBranchInfo.code ~= 0 then return "" end -- not in git repo

	-- get only line on current branch (which starts with `*`)
	local branches = vim.split(allBranchInfo.stdout, "\n")
	local currentBranchInfo
	for _, line in pairs(branches) do
		currentBranchInfo = line:match("^%* .*")
		if currentBranchInfo then break end
	end
	if not currentBranchInfo then return "" end -- not on a branch, e.g., detached HEAD
	local ahead = currentBranchInfo:match("ahead (%d+)")
	local behind = currentBranchInfo:match("behind (%d+)")

	local icons = require("tinygit.config").config.statusline.branchState.icons
	if ahead and behind then
		return (icons.diverge .. " %s/%s"):format(ahead, behind)
	elseif ahead then
		return icons.ahead .. ahead
	elseif behind then
		return icons.behind .. behind
	end
	return ""
end

--------------------------------------------------------------------------------

function M.refreshBranchState() vim.b.tinygit_branchState = getBranchState() end

function M.getBranchState() return vim.b.tinygit_branchState or "" end

vim.api.nvim_create_autocmd({ "BufEnter", "DirChanged", "FocusGained" }, {
	group = vim.api.nvim_create_augroup("tinygit_branchState", { clear = true }),
	callback = M.refreshBranchState,
})
M.refreshBranchState() -- initialize in case of lazy-loading

--------------------------------------------------------------------------------
return M
