local M = {}
--------------------------------------------------------------------------------

---Returns info ahead, behind, and divergence of the local branch with the
---remote one
---@param bufnr? number
---@return string blame lualine stringifys result, so need to return empty string instead of nil
---@nodiscard
local function getBranchState(bufnr)
	bufnr = bufnr or 0

	-- GUARD valid buffer
	if not vim.api.nvim_buf_is_valid(bufnr) then return "" end
	if vim.api.nvim_buf_get_option(bufnr, "buftype") ~= "" then return "" end

	local allBranchInfo = vim.fn.system {
		"git",
		"-C",
		vim.loop.cwd(),
		"branch",
		"--verbose",
	}
	-- GUARD not in git repo
	if vim.v.shell_error ~= 0 then return "" end

	-- get only line on current branch (starting with `*`)
	local branches = vim.split(allBranchInfo, "\n")
	local currentBranchInfo
	for _, line in pairs(branches) do
		currentBranchInfo = line:match("^%* .*")
		if currentBranchInfo then break end
	end
	if not currentBranchInfo then return "" end

	local ahead = currentBranchInfo:match("ahead (%d+)")
	local behind = currentBranchInfo:match("behind (%d+)")
	if ahead then ahead = "󰶣 " .. ahead end
	if behind then behind = "󰶡 " .. behind end
	local text = table.concat({ ahead, behind }, "  ") or ""
	if ahead and behind then text = "󰃻 " .. text end

	return text
end

--------------------------------------------------------------------------------

---@param bufnr? number
function M.refreshBranchState(bufnr) vim.b["tinygit_branchState"] = getBranchState(bufnr) end

vim.api.nvim_create_autocmd({ "BufEnter", "DirChanged", "FocusGained" }, {
	group = vim.api.nvim_create_augroup("tinygit_branchState", { clear = true }),
	callback = function(ctx)
		-- so buftype is set before checking the buffer
		vim.defer_fn(function() M.refreshBranchState(ctx.buf) end, 1)
	end,
})

vim.defer_fn(getBranchState, 1) -- initialize in case of lazy-loading

function M.getBranchState() return vim.b.tinygit_branchState or "" end

--------------------------------------------------------------------------------
return M
