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
		spellcheck = false, -- vim's builtin spellcheck
		wrap = "hard", ---@type "hard"|"soft"|"none"
		keymaps = {
			normal = { abort = "q", confirm = "<CR>" },
			insert = { confirm = "<C-CR>" },
		},
		conventionalCommits = {
			enforce = false,
			-- stylua: ignore
			keywords = {
				"fix", "feat", "chore", "docs", "refactor", "build", "test",
				"perf", "style", "revert", "ci", "break",
			},
		},
	},
	push = {
		preventPushingFixupCommits = true,
		confirmationSound = true, -- currently macOS only, PRs welcome

		-- If pushed commits contain references to issues, open them in the browser
		-- (not used when using force-push).
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
			ignoreAuthors = {}, -- hide component if from these authors (useful for bots)
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
		warn(
			"The `commit.insertIssuesOnHashSign` feature has been removed. Since "
				.. "the commit creation window is now larger, much better issue insertion "
				.. "via plugins like `cmp-git` now works there."
		)
	end

	-- DEPRECATION (2024-12-28)
	if M.config.commit.commitPreview then
		warn("The config `commit.commitPreview` has been removed. It is now enabled by default.")
	end
	if M.config.commit.inputFieldWidth then
		warn(
			"The config `commit.inputFieldWidth` has been removed, since there is no longer a need for it."
		)
	end
	if M.config.push.preventPushingFixupOrSquashCommits then
		warn(
			"The config `push.preventPushingFixupOrSquashCommits` has moved to `push.preventPushingFixupCommits`."
		)
	end

	---@diagnostic enable: undefined-field

	-- VALIDATE border `none` does not work with and title/footer used by this plugin
	if M.config.history.diffPopup.border == "none" then
		local fallback = defaultConfig.history.diffPopup.border
		M.config.history.diffPopup.border = fallback
		warn(('Border type "none" is not supported, falling back to %q.'):format(fallback))
	end

	-- VALIDATE `context` > 0 (0 is not supported without `--unidiff-zero`)
	-- DOCS https://git-scm.com/docs/git-apply#Documentation/git-apply.txt---unidiff-zero
	-- However, it is discouraged in the git manual, and `git apply` tends to
	-- fail quite often, probably as line count changes are not accounted for
	-- when splitting up changes into hunks in `getHunksFromDiffOutput`.
	-- Using context=1 works, but has the downside of not being 1:1 the same
	-- hunks as with `gitsigns.nvim`. Since many small hunks are actually abit
	-- cumbersome, and since it's discouraged by git anyway, we simply disallow
	-- context=0 for now.
	if M.config.stage.contextSize < 1 then M.config.stage.contextSize = 1 end
end

--------------------------------------------------------------------------------
return M
