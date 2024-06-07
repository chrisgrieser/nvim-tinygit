local M = {}
--------------------------------------------------------------------------------

function M.blame() return require("tinygit.statusline.blame").getBlame() end

function M.branchState() return require("tinygit.statusline.branch-state").getBranchState() end

function M.updateAllComponents()
	-- conditions to avoid unnecessarily loading the modules
	if package.loaded["tinygit.statusline.blame"] then
		require("tinygit.statusline.blame").refreshBlame()
	end
	if package.loaded["tinygit.statusline.branch-state"] then
		require("tinygit.statusline.branch-state").refreshBranchState()
	end

	-- Needs to be triggered manually, since lualine updates the git diff
	-- component only on BufEnter.
	if package.loaded["lualine"] then
		require("lualine.components.diff.git_diff").update_diff_args()
	end
end

--------------------------------------------------------------------------------
return M
