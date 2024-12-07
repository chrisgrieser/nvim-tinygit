local M = {}
--------------------------------------------------------------------------------

---@class Tinygit.Config
local defaultConfig = {
	stage = { -- requires `telescope.nvim`
		contextSize = 1, -- larger values "merge" hunks. 0 is not supported.
		stagedIndicator = "󰐖",
		keymaps = { -- insert & normal mode
			stagingToggle = "<Space>", -- stage/unstage hunk
			gotoHunk = "<CR>",
			resetHunk = "<C-r>",
		},
		moveToNextHunkOnStagingToggle = false,
	},
	commit = {
		preview = true, -- requires `nvim-notify` or `snacks.nvim`
		spellcheck = false,
		keepAbortedMsgSecs = 300,
		inputFieldWidth = 72,
		conventionalCommits = {
			enforce = false,
			-- stylua: ignore
			keywords = {
				"fix", "feat", "chore", "docs", "refactor", "build", "test",
				"perf", "style", "revert", "ci", "break", "improv",
			},
		},
		insertIssuesOnHashSign = {
			-- Typing `#` will insert the most recent open issue.
			-- Requires `nvim-notify` or `snacks.nvim`.
			enabled = false,
			next = "<Tab>", -- insert & normal mode
			prev = "<S-Tab>",
			issuesToFetch = 20,
		},
	},
	push = {
		preventPushingFixupOrSquashCommits = true,
		confirmationSound = true, -- currently macOS only, PRs welcome

		-- Pushed commits contain references to issues, open those issues.
		-- Not used when using force-push.
		openReferencedIssues = false,
	},
	github = {
		icons = {
			openIssue = "🟢",
			closedIssue = "🟣",
			notPlannedIssue = "⚪",
			openPR = "🟩",
			mergedPR = "🟪",
			draftPR = "⬜",
			closedPR = "🟥",
		},
	},
	history = {
		diffPopup = {
			width = 0.8, -- between 0-1
			height = 0.8,
			border = "single",
		},
		autoUnshallowIfNeeded = false,
	},
	appearance = {
		mainIcon = "󰊢",
		backdrop = {
			enabled = true,
			blend = 50, -- 0-100
		},
	},
	statusline = {
		blame = {
			ignoreAuthors = {}, -- hide component if these authors (useful for bots)
			hideAuthorNames = {}, -- show component, but hide names (useful for your own name)
			maxMsgLen = 40,
			icon = "ﰖ",
		},
		branchState = {
			icons = {
				ahead = "󰶣",
				behind = "󰶡",
				diverge = "󰃻",
			},
		},
	},
}

--------------------------------------------------------------------------------

M.config = defaultConfig -- in case user does not call `setup`

---@param userConfig? Tinygit.Config
function M.setupPlugin(userConfig)
	M.config = vim.tbl_deep_extend("force", defaultConfig, userConfig or {})

	-- DEPRECATION (2024-11-23)
	---@diagnostic disable: undefined-field
	if
		M.config.staging
		or M.config.commitMsg
		or M.config.historySearch
		or M.config.issueIcons
		or M.config.backdrop
		or M.config.mainIcon
		or (M.config.commit and (M.config.commit.commitPreview or M.config.commit.insertIssuesOnHash))
	then
		---@diagnostic enable: undefined-field
		local msg = [[The config structure has been overhauled:
- `staging` → `stage`
- `commitMsg` → `commit`
  - `commitMsg.commitPreview` → `commit.preview`
  - `commitMsg.insertIssuesOnHash` → `commit.insertIssuesOnHashSign`
- `historySearch` → `history`
- `issueIcons` → `github.icons`
- `backdrop` → `appearance.backdrop`
- `mainIcon` → `appearance.mainIcon`]]
		require("tinygit.shared.utils").notify(msg, "warn", { ft = "markdown" })
	end

	-- VALIDATE border `none` does not work with and title/footer used by this plugin
	if M.config.history.diffPopup.border == "none" then
		local fallback = defaultConfig.history.diffPopup.border
		M.config.history.diffPopup.border = fallback
		local msg = ('Border type "none" is not supported, falling back to %q.'):format(fallback)
		require("tinygit.shared.utils").notify(msg, "warn")
	end
end

--------------------------------------------------------------------------------
return M
