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
end

--------------------------------------------------------------------------------
return M
