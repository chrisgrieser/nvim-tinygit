local M = {}
--------------------------------------------------------------------------------

local fallbackBorder = "rounded"

---@return string
local function getBorder()
	local hasWinborder, winborder = pcall(function() return vim.o.winborder end)
	if not hasWinborder or winborder == "" or winborder == "none" then return fallbackBorder end
	return winborder
end

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
		border = getBorder(), -- `vim.o.winborder` on nvim 0.11, otherwise "rounded"
		spellcheck = false, -- vim's builtin spellcheck
		wrap = "hard", ---@type "hard"|"soft"|"none"
		keymaps = {
			normal = { abort = "q", confirm = "<CR>" },
			insert = { confirm = "<C-CR>" },
		},
		preview = {
			loglines = 3,
		},
		subject = {
			-- automatically apply formatting to the subject line
			autoFormat = function(subject) ---@type nil|fun(subject: string): string
				subject = subject:gsub("%.$", "") -- remove trailing dot https://commitlint.js.org/reference/rules.html#body-full-stop
				return subject
			end,

			-- disallow commits that do not use an allowed type
			enforceType = false,
			-- stylua: ignore
			types = {
				"fix", "feat", "chore", "docs", "refactor", "build", "test",
				"perf", "style", "revert", "ci", "break",
			},
		},
		body = {
			enforce = false,
		},
		keymapHints = true,
	},
	push = {
		preventPushingFixupCommits = true,
		confirmationSound = true, -- currently macOS only, PRs welcome

		-- If pushed commits contain references to issues, open them in the browser
		-- (not used when force-pushing).
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
			border = getBorder(), -- `vim.o.winborder` on nvim 0.11, otherwise "rounded"
		},
		autoUnshallowIfNeeded = false,
	},
	appearance = {
		mainIcon = "󰊢",
		backdrop = {
			enabled = true,
			blend = 40, -- 0-100
		},
		hlGroups = {
			addedText = "Added", -- i.e. use hlgroup `Added`
			removedText = "Removed",
		},
	},
	statusline = {
		blame = {
			ignoreAuthors = {}, -- hide component if from these authors (useful for bots)
			hideAuthorNames = {}, -- show component, but hide names (useful for your own name)
			showOnlyTimeIfAuthor = {}, -- show only time if these authors (useful for automated commits)
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
		fileState = {
			icon = "",
		},
	},
}

--------------------------------------------------------------------------------

M.config = defaultConfig -- in case user does not call `setup`

---@param userConfig? Tinygit.Config
function M.setup(userConfig)
	M.config = vim.tbl_deep_extend("force", defaultConfig, userConfig or {})
	local function warn(msg) require("tinygit.shared.utils").notify(msg, "warn", { ft = "markdown" }) end

	-- VALIDATE border `none` does not work with and title/footer used by this plugin
	if M.config.history.diffPopup.border == "none" or M.config.history.diffPopup.border == "" then
		M.config.history.diffPopup.border = fallbackBorder
		warn(('Border type "none" is not supported, falling back to %q.'):format(fallbackBorder))
	end
	if M.config.commit.border == "none" or M.config.commit.border == "" then
		M.config.commit.border = fallbackBorder
		warn(('Border type "none" is not supported, falling back to %q.'):format(fallbackBorder))
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

	-- `preview_width` is only supported by `horizontal` & `cursor` strategies,
	-- see https://github.com/chrisgrieser/nvim-scissors/issues/28
	local strategy = M.config.stage.telescopeOpts.layout_strategy
	if strategy ~= "horizontal" and strategy ~= "cursor" then
		M.config.stage.telescopeOpts.layout_config.preview_width = nil
	end
end

--------------------------------------------------------------------------------
return M
