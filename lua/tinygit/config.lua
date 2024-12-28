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

		-- accepts the common telescope picker config
		telescopeOpts = {
			layout_strategy = "horizontal",
			layout_config = {
				horizontal = {
					preview_width = 0.65,
					height = { 0.7, min = 20 },
				},
			},
		},
	},
	commit = {
		keepAbortedMsgSecs = 300,
		border = "single",
		normalModeKeymaps = {
			abort = "q",
			confirm = "<CR>",
		},
		conventionalCommits = {
			enforce = false,
			-- stylua: ignore
			keywords = {
				"fix", "feat", "chore", "docs", "refactor", "build", "test",
				"perf", "style", "revert", "ci", "break", "improv",
			},
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
function M.setup(userConfig)
	M.config = vim.tbl_deep_extend("force", defaultConfig, userConfig or {})
	local function warn(msg) require("tinygit.shared.utils").notify(msg, "warn", { ft = "markdown" }) end

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
		warn([[The config structure has been overhauled:
- `staging` → `stage`
- `commitMsg` → `commit`
  - `commitMsg.commitPreview` → `commit.preview`
  - `commitMsg.insertIssuesOnHash` → `commit.insertIssuesOnHashSign`
- `historySearch` → `history`
- `issueIcons` → `github.icons`
- `backdrop` → `appearance.backdrop`
- `mainIcon` → `appearance.mainIcon`]])
	end

	-- DEPRECATION (2024-12-28)
	if M.config.commit.insertIssuesOnHashSign then
		warn("The `commit.insertIssuesOnHashSign` feature has been removed. Since "
			.. "the commit creation window is now larger, much better issue insertion "
			.. "via plugins like `cmp-git` now work there.")
	end

	-- DEPRECATION (2024-12-28)
	if M.config.commit.commitPreview then
		warn("The config `commit.commitPreview` has been removed. It is now enabled by default.")
	end
	if M.config.commit.inputFieldWidth then
		warn("The config `commit.inputFieldWidth` has been removed, since there is no longer a need for it.")
	end
	if M.config.commit.spellcheck then
		warn("The config `commit.spellcheck` has been removed. Configure via ftplugin for `gitcommit`.")
	end
	---@diagnostic enable: undefined-field

	-- VALIDATE border `none` does not work with and title/footer used by this plugin
	if M.config.history.diffPopup.border == "none" then
		local fallback = defaultConfig.history.diffPopup.border
		M.config.history.diffPopup.border = fallback
		warn(('Border type "none" is not supported, falling back to %q.'):format(fallback))
	end
end

--------------------------------------------------------------------------------
return M
