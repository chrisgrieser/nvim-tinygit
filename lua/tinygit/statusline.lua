local M = {}
--------------------------------------------------------------------------------

function M.blame() return require("tinygit.statusline.blame").getBlame() end

function M.branchState() return require("tinygit.statusline.branch-state").getBranchState() end

--------------------------------------------------------------------------------
return M
