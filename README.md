<!-- LTeX: enabled=false -->
# nvim-tinygit
<!-- LTeX: enabled=true -->
<a href="https://dotfyle.com/plugins/chrisgrieser/nvim-tinygit">
<img alt="badge" src="https://dotfyle.com/plugins/chrisgrieser/nvim-tinygit/shield?style=flat"/></a>

A lightweight bundle of commands focused on swift and streamlined git
operations.

> [!NOTE]
> [Version 1.0](#breaking-changes-in-v10) included several breaking changes. If
> you want to keep using the previous version, pin the tag `v0.9`:
>
> ```lua
> -- lazy.nvim
> {
> 	"chrisgrieser/nvim-tinygit",
> 	tag = "v0.9"
> 	dependencies = "stevearc/dressing.nvim",
> },
> ```

## TODO version 1.0
- [x] Commit msg module
- [ ] Commit preview
- [ ] Use `telescope` instead of `vim.ui.select`.
- [ ] Commit preview for fixup commits?
- [ ] Issue insertion module for `blink.cmp`?
- [ ] Update docs.
- [ ] New showcase screenshots.
- [ ] Update issue templates.

## Screenshots

| Interactive staging                                                                                                                               | File History                                                                                                                              |
|---------------------------------------------------------------------------------------------------------------------------------------------------|-------------------------------------------------------------------------------------------------------------------------------------------|
| <img alt="interactive staging" width=70% src="https://github.com/chrisgrieser/nvim-tinygit/assets/73286100/3c055861-6b93-4065-8601-f79568d8ac28"> | <img alt="git history" width=70% src="https://github.com/chrisgrieser/nvim-tinygit/assets/73286100/b4cb918e-ff95-40ac-a09f-feb767ba2b94"> |

## Feature overview
- **Interactive staging** of hunks (parts of a file). Displays hunk diffs with
  proper syntax highlighting, and allows resetting or navigating to the hunk.
- **Smart-commit**: Open a popup to enter a commit message with syntax highlighting,
  commit preview, automatic issue number insertion, and overlength indicators.
  If there are no staged changes, stages all changes before doing so (`git add
  -A`). Optionally trigger a `git push` afterward.
- Quick commands for amend, stash, fixup, or undoing commits.
- Search **issues & PRs**. Open the selected issue or PR in the browser.
- Open the **GitHub URL** of the current file, repo, or selection. Also supports
  opening the blame view.
- **Explore the git history**: Search the file for a string ("git pickaxe"), or
  examine the history of a function or line range. Displays the results in a
  diff view with syntax highlighting, correctly following file renamings.
- **Status line components:** `git blame` of a file and branch state.
- **Streamlined workflow:** operations are smartly combined to minimize
  friction. For instance, the smart-commit command combines staging, committing,
  and pushing, and searching the file history combines un-shallowing, searching,
  and navigating diffs.

<!-- toc -->

- [Breaking changes in v1.0](#breaking-changes-in-v10)
- [Installation](#installation)
- [Commands](#commands)
	* [Interactive staging](#interactive-staging)
	* [Smart-commit](#smart-commit)
	* [Amend and fixup commits](#amend-and-fixup-commits)
	* [Undo last commit/amend](#undo-last-commitamend)
	* [GitHub interaction](#github-interaction)
	* [Push & PRs](#push--prs)
	* [Search file history](#search-file-history)
	* [Stash](#stash)
- [Status line components](#status-line-components)
	* [git blame](#git-blame)
	* [Branch state](#branch-state)
- [Configuration](#configuration)
- [Credits](#credits)

<!-- tocstop -->

## Breaking changes in v1.0
- `dressing.nvim` and `nvim-notify` are **no longer dependencies****.
- `telescope.nvim` is now an **always required dependency**.
- The `commit.insertIssuesOnHashSign` feature has been removed. Since the commit
  creation window is now larger, much better issue insertion via plugins like
  [cmp-git](https://github.com/petertriho/cmp-git) now work there.

## Installation
**Requirements**
- nvim 0.10+
- [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim)
- `curl` for GitHub-related features
- *optional*: Treesitter parser for syntax highlighting: `TSInstall gitcommit`

```lua
-- lazy.nvim
{
	"chrisgrieser/nvim-tinygit",
	dependencies = "nvim-telescope/telescope.nvim",
},

-- packer
use {
	"chrisgrieser/nvim-tinygit",
	requires = "nvim-telescope/telescope.nvim",
}
```

## Commands
All commands are available via lua function or sub-command of `:Tinygit`, for
example `require("tinygit").interactiveStaging()` and `:Tinygit
interactiveStaging`. However, do note that the lua function is preferable,
since the `:Tinygit` does not accept command-specific options and also does not
trigger visual-mode specific changes to the commands.

### Interactive staging
- This feature requires
  [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim).
- This command stages hunks, that is, *parts* of a file instead of the
  full file. It is roughly comparable to `git add -p`.
- Use `<Space>` to (un)stage the hunk, `<CR>` to go to the hunk, or `<C-r` to
  reset the hunk (mappings customizable). Your regular `telescope` mappings also
  apply.
- The size of the hunks is determined by the setting `staging.contextSize`.
  Larger context size is going to "merge" changes that are close to one another
  into one hunk. (As such, the hunks displayed are not 1:1 the same as the hunks
  from `gitsigns.nvim`.) A context size between 1 and 4 is recommended.
- Limitations: `contextSize=0` (= no merging at all) is not supported.

```lua
require("tinygit").interactiveStaging()
```

### Smart-commit
- Open a commit popup, alongside a preview of what is going to be committed. If
  there are no staged changes, stage all changes (`git add --all`) before the
  commit.
- Input field contents of aborted commits are briefly kept, if you just want to
  fix a detail.
- Optionally run `git push` if the repo is clean after committing.
- The title of the input field displays what actions are going to be performed.
  You can see at glance whether all changes are going to be committed, or whether
  there a `git push` is triggered afterward, so there are no surprises.
- Typing `#` inserts the most recent issue number, `<Tab>` cycles through the
  issues (opt-in, see plugin configuration).
- Only supports the commit subject line (no commit body).

```lua
-- values shown are the defaults
require("tinygit").smartCommit { pushIfClean = false, pullBeforePush = true }
```

**Example workflow**
Assuming these keybindings:

```lua
vim.keymap.set("n", "<leader>ga", function() require("tinygit").interactiveStaging() end, { desc = "git add" })
vim.keymap.set("n", "<leader>gc", function() require("tinygit").smartCommit() end, { desc = "git commit" })
vim.keymap.set("n", "<leader>gp", function() require("tinygit").push() end, { desc = "git push" })
```

1. Stage some changes via `ga`.
2. Use `gc` to enter a commit message.
3. Repeat 1 and 2.
4. When done, `gp` to push the commits.

Using `pushIfClean = true` allows you to combine staging, committing, and
pushing into a single step, when it is the last commit you intend to make.

### Amend and fixup commits
**Amending**
- `amendOnlyMsg` just opens the commit popup to change the last commit message,
  and does not stage any changes.
- `amendNoEdit` keeps the last commit message; if there are no staged changes,
  stages all changes (`git add --all`), like `smartCommit`.
- Optionally runs `git push --force-with-lease` afterward, if the branch has
  diverged (that is, the amended commit was already pushed).

```lua
-- options default to `false`
require("tinygit").amendOnlyMsg { forcePushIfDiverged = false }
require("tinygit").amendNoEdit { forcePushIfDiverged = false, stageAllIfNothingStaged = true }
```

**Fixup commits**
- `fixupCommit` lets you select a commit from the last X commits and runs `git
  commit --fixup` on the selected commit.
- If there are no staged changes, stages all changes (`git add --all`), like
  `smartCommit`.
- `autoRebase = true` automatically runs rebase with `--autosquash` and
`--autostash` afterward, confirming all fixups and squashes **without opening a
rebase to do editor**. Note that this can potentially result in conflicts.

```lua
-- options show default values
require("tinygit").fixupCommit {
	selectFromLastXCommits = 15,
	autoRebase = false,
}
```

### Undo last commit/amend

```lua
require("tinygit").undoLastCommitOrAmend()
```

- Changes in the working directory are kept, but unstaged. (In the background,
  this uses `git reset --mixed`.)
- If there was a `push` operation done as a followup (such as `.smartCommit {
  pushIfClean = false }`), the last commit is not undone.

### GitHub interaction
**Search issues & PRs**
- Requires `curl`.

```lua
-- state: all|closed|open (default: all)
-- type: all|issue|pr (default: all)
require("tinygit").issuesAndPrs { type = "all", state = "all" }

-- alternative: if the word under the cursor is of the form `#123`,
-- open that issue/PR
require("tinygit").openIssueUnderCursor()
```

**GitHub URL**
Creates a permalink to the current file/lines at GitHub. The link is opened in
the browser and copied to the system clipboard. In normal mode, uses the current
file, in visual mode, uses the selected lines. (Note that visual mode detection
requires you to use the lua function below instead of the `:Tinygit` ex-command.)
- `"file"`: code view
- `"blame"`: blame view
- `"repo"`: repo root

```lua
-- file|repo|blame (default: file)
require("tinygit").githubUrl()
```

### Push & PRs
- `push` can be combined with other actions, depending on the options.
- `createGitHubPr` opens a PR from the current branch browser. (This requires the
  repo to be a fork with sufficient information on the remote.)

```lua
-- options default to `false`
require("tinygit").push {
	pullBefore = false,
	forceWithLease = false,
	createGitHubPr = false,
}
require("tinygit").createGitHubPr()
```

### Search file history
Search the git history of the current file. Select from the matching commits to
open a popup with a diffview of the changes.

If the config `history.autoUnshallowIfNeeded` is set to `true`, will also
automatically un-shallow the repo if needed.

```lua
require("tinygit").fileHistory()
```

The type of history search depends on the mode `.searchHistory` is called from:
- **Normal mode**: search history for a string (`git log -G`)
	* Correctly follows file renamings, and displays past file names in the
	  commit selection.
	* The search input is case-insensitive and supports regex.
	* Leave the input field empty to display *all* commits that changed the
	  current file.
- **Visual mode**: function history (`git log -L`).
	* The selected text is assumed to be the name of the function whose history
	  you want to explore.
	* Note that [`git` uses heuristics to determine the enclosing function of
	  a change](https://news.ycombinator.com/item?id=38153309), so this is not
	  100% perfect and has varying reliability across languages.
	* Caveat: for function history, git does not support to follow renamings of
	  the file or function name.
- **Visual line mode**: line range history (`git log -L`).
	* Uses the selected lines as the line range.
	* Caveat: for line history, git does not support to follow file renamings.

Note that visual mode detection requires you to use the lua function above
instead of the `:Tinygit` ex-command.

**Keymaps in the diff popup**
- `<Tab>`: show older commit
- `<S-Tab>`: show newer commit
- `yh`: yank the commit hash to the system clipboard
- `R`: restore file to state at commit
- `n`/`N`: go to the next/previous occurrence of the query (only file history)

### Stash
Simple wrappers around `git stash push` and `git stash pop`.

```lua
require("tinygit").stashPush()
require("tinygit").stashPop()
```

## Status line components

<!-- LTeX: enabled=false -->
### git blame
<!-- LTeX: enabled=true -->
Shows the message and date (`git blame`) of the last commit that changed the
current *file* (not line).

```lua
require("tinygit.statusline").blame()
```

> [!TIP]
> Some status line plugins also allow you to put components into the tab line or
> win bar. If your status line is too crowded, you can add the blame-component to
> one of those bars instead.

The component can be configured with the `statusline.blame` options in the [plugin
configuration](#configuration).

### Branch state
Shows whether the local branch is ahead or behind of its remote counterpart.
(Note that this component does not run `git fetch` for performance reasons, so
the information may not be up-to-date with remote changes.)

```lua
require("tinygit.statusline").branchState()
```

## Configuration
The `setup` call is optional.

```lua
-- default config
require("tinygit").setup {
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
```

The appearance of the commit preview and notifications is determined by
[nvim-notify](https://github.com/rcarriga/nvim-notify) or
[snacks.nvim](https://https://github.com/folke/snacks.nvim/blob/main/docs/notifier.md)
respectively.

## Credits
In my day job, I am a sociologist studying the social mechanisms underlying the
digital economy. For my PhD project, I investigate the governance of the app
economy and how software ecosystems manage the tension between innovation and
compatibility. If you are interested in this subject, feel free to get in touch.

I also occasionally blog about vim: [Nano Tips for Vim](https://nanotipsforvim.prose.sh)

- [Website](https://chris-grieser.de/)
- [Mastodon](https://pkm.social/@pseudometa)
- [ResearchGate](https://www.researchgate.net/profile/Christopher-Grieser)
- [LinkedIn](https://www.linkedin.com/in/christopher-grieser-ba693b17a/)

<a href='https://ko-fi.com/Y8Y86SQ91' target='_blank'> <img height='36'
style='border:0px;height:36px;' src='https://cdn.ko-fi.com/cdn/kofi1.png?v=3'
border='0' alt='Buy Me a Coffee at ko-fi.com' /></a>
