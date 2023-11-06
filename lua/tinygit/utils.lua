local M = {}
local fn = vim.fn
--------------------------------------------------------------------------------

-- open with the OS-specific shell command
---@param url string
function M.openUrl(url)
	local opener
	if fn.has("macunix") == 1 then
		opener = "open"
	elseif fn.has("linux") == 1 then
		opener = "xdg-open"
	elseif fn.has("win64") == 1 or fn.has("win32") == 1 then
		opener = "start"
	end
	local openCommand = ("%s '%s' >/dev/null 2>&1"):format(opener, url)
	fn.system(openCommand)
end

---send notification
---@param body string
---@param level? "info"|"trace"|"debug"|"warn"|"error"
---@param title? string
function M.notify(body, level, title)
	local titlePrefix = "tinygit"
	if not level then level = "info" end
	local notifyTitle = title and titlePrefix .. ": " .. title or titlePrefix
	vim.notify(vim.trim(body), vim.log.levels[level:upper()], { title = notifyTitle })
end

---checks if last command was successful, if not, notify
---@nodiscard
---@return boolean
---@param errorMsg string
function M.nonZeroExit(errorMsg)
	local exitCode = vim.v.shell_error
	if exitCode ~= 0 then M.notify(vim.trim(errorMsg), "warn") end
	return exitCode ~= 0
end

---also notifies if not in git repo
---@nodiscard
---@return boolean
function M.notInGitRepo()
	fn.system("git rev-parse --is-inside-work-tree")
	local notInRepo = M.nonZeroExit("Not in Git Repo.")
	return notInRepo
end

---@return string "user/name" of repo
---@nodiscard
function M.getRepo() return fn.system("git remote -v | head -n1"):match(":.*%."):sub(2, -2) end

-- get effective backend for the selector
-- @see https://github.com/stevearc/dressing.nvim/blob/master/lua/dressing/config.lua#L164-L179
---@return string filetype of selector, nil if not supported
function M.dressingBackendFt()
		local dressingTinygitConfig = require("dressing.config").select.get_config { kind = "tinygit" }
		local dressingBackend = dressingTinygitConfig.backend
			or require("dressing.config").select.backend[1]

		local backendMap = {
			telescope = "TelescopeResults",
			builtin = "DressingSelect",
			nui = "DressingSelect",
		}
		local selectorFiletype = backendMap[dressingBackend]
		return selectorFiletype
end

---Since the various elements of this object must be changed together, since
---they depend on the configuration of the other
---@type { selectorFormatter: fun(commitLine: string): string; gitlogFormat: string; setupAppearance: fun() }
M.commitList = {
	-- what is passed to `git log --format`. hash/`%h` follows by a tab is required
	-- at the beginning, the rest is decorative, though \t as delimiter as
	-- assumed by the others parts here.
	gitlogFormat = "%h\t%s\t%cr", -- hash, subject, date

	-- how the commits are displayed in the selector
	---@param commitLine string, formatted as gitlogFormat
	---@return string formatted text
	selectorFormatter = function(commitLine)
		local _, subject, date = unpack(vim.split(commitLine, "\t"))
		return ("%s\t%s"):format(subject, date)
	end,

	-- highlights for the items in the selector
	setupAppearance = function()
		local backendFiletype = M.dressingBackendFt()
		if not backendFiletype then return end 

		vim.api.nvim_create_autocmd("FileType", {
			once = true, -- to not affect other selectors
			pattern = backendFiletype,
			callback = function()
				local ns = vim.api.nvim_create_namespace("tinygit.selector")
				vim.api.nvim_win_set_hl_ns(0, ns)

				vim.fn.matchadd("tinygit_selector_issueNumber", [[#\d\+]])
				vim.api.nvim_set_hl(ns, "tinygit_selector_issueNumber", { link = "Number" })

				vim.fn.matchadd("tinygit_selector_date", [[\t.*$]])
				vim.api.nvim_set_hl(ns, "tinygit_selector_date", { link = "Comment" })

				vim.fn.matchadd("tinygit_selector_mdInlineCode", [[`.\{-}`]]) -- .\{-} = non-greedy quantifier
				vim.api.nvim_set_hl(ns, "tinygit_selector_mdInlineCode", { link = "@text.literal" })

				vim.fn.matchadd(
					"tinygit_selector_conventionalCommit",
					[[\v^ *(feat|fix|test|perf|build|ci|revert|refactor|chore|docs|break|improv|style)(!|(.{-}))?\ze:]]
				)
				vim.api.nvim_set_hl(ns, "tinygit_selector_conventionalCommit", { link = "Title" })
			end,
		})
	end,
}

--------------------------------------------------------------------------------
return M
