local M = {}
--------------------------------------------------------------------------------

---@class pluginConfig
local defaultConfig = {
	staging = { -- requires telescope
		contextSize = 1, -- larger values "merge" hunks
		stagedIndicator = "✜ ",
		keymaps = { -- insert & normal mode
			stagingToggle = "<Space>", -- stage/unstage hunk
			gotoHunk = "<CR>",
			resetHunk = "<C-r>",
		},
		moveToNextHunkOnStagingToggle = false,
	},
	commitMsg = {
		commitPreview = true, -- requires nvim-notify
		spellcheck = false,
		keepAbortedMsgSecs = 300,
		inputFieldWidth = 72, -- `false` to use dressing.nvim config
		conventionalCommits = {
			enforce = false,
			-- stylua: ignore
			keywords = {
				"fix", "feat", "chore", "docs", "refactor", "build", "test",
				"perf", "style", "revert", "ci", "break", "improv",
			},
		},
		openReferencedIssue = false, -- if message has issue/PR, open in browser afterwards
		insertIssuesOnHash = {
			-- Experimental. Typing `#` will insert the most recent open issue.
			-- Requires nvim-notify.
			enabled = false,
			next = "<Tab>", -- insert & normal mode
			prev = "<S-Tab>",
			issuesToFetch = 20,
		},
	},
	push = {
		preventPushingFixupOrSquashCommits = true,
		confirmationSound = true, -- currently macOS only, PRs welcome
	},
	historySearch = {
		diffPopup = {
			width = 0.8, -- float, 0 to 1
			height = 0.8,
			border = "single",
		},
		autoUnshallowIfNeeded = false,
	},
	issueIcons = {
		openIssue = "🟢",
		closedIssue = "🟣",
		notPlannedIssue = "⚪",
		openPR = "🟩",
		mergedPR = "🟪",
		draftPR = "⬜",
		closedPR = "🟥",
	},
	statusline = {
		blame = {
			ignoreAuthors = {}, -- hide component if these authors (useful for bots)
			hideAuthorNames = {}, -- show component, but hide names (useful for your own name)
			maxMsgLen = 40,
			icon = "ﰖ ",
		},
		branchState = {
			icons = {
				ahead = "󰶣",
				behind = "󰶡",
				diverge = "󰃻",
			},
		},
	},
	backdrop = {
		enabled = true,
		blend = 50, -- 0-100
	},
}

--------------------------------------------------------------------------------

M.config = defaultConfig -- in case user does not call `setup`

---@param userConfig? pluginConfig
function M.setupPlugin(userConfig)
	M.config = vim.tbl_deep_extend("force", defaultConfig, userConfig or {})

	-- VALIDATE border `none` does not work with and title/footer used by this plugin
	if M.config.historySearch.diffPopup.border == "none" then
		local fallback = defaultConfig.historySearch.diffPopup.border
		M.config.historySearch.diffPopup.border = fallback
		local msg = ('Border type "none" is not supported, falling back to %q.'):format(fallback)
		require("tinygit.shared.utils").notify(msg, "warn")
	end
end

--------------------------------------------------------------------------------
return M
