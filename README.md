<!-- LTeX: enabled=false -->
# nvim-tinygit
<!-- LTeX: enabled=true -->
<a href="https://dotfyle.com/plugins/chrisgrieser/nvim-tinygit">
<img alt="badge" src="https://dotfyle.com/plugins/chrisgrieser/nvim-tinygit/shield?style=flat"/></a>

Bundle of commands focused on swift and streamlined git operations.

## Feature overview

<table>
	<tr>
		<th>Interactive staging</th>
		<th>Smart commit</th>
	</tr>
	<tr>
		<td><img alt="interactive staging" src="https://github.com/user-attachments/assets/93812b73-7a0d-4496-b101-8551c41ee393"></td>
		<td><img alt="smart commit" src="https://github.com/user-attachments/assets/8dfdaa83-2f5b-49ee-a4a7-a72ae07f5941"></td>
	</tr>
	<tr>
		<th>File history</th>
		<th></th>
	</tr>
	<tr>
		<td><img alt="file history" src="https://github.com/chrisgrieser/nvim-tinygit/assets/73286100/b4cb918e-ff95-40ac-a09f-feb767ba2b94"></td>
		<td></td>
	</tr>
 </table>

- **Interactive staging** of hunks (parts of a file). Displays hunk diffs with
  syntax highlighting, and allows resetting or navigating to the hunk.
- **Smart-commit**: Open a popup to enter a commit message with syntax highlighting,
  commit preview, and commit title length indicators. If there are no staged
  changes, stages all changes before doing so (`git add -A`). Optionally trigger
  a `git push` afterward.
- Convenient commands for **amending, stashing, fixup, or undoing commits**.
- Search **issues & PRs**. Open the selected issue or PR in the browser.
- Open the **GitHub URL** of the current file, repo, or selected lines. Also
  supports opening GitHub's blame view.
- **Explore file history**: Search the git history of a file for a string ("git
  pickaxe"), or examine the history of a function or line range. Displays the
  results in a diff view with syntax highlighting, correctly following file
  renamings.
- **Status line components:** `git blame` of a file and branch state.
- **Streamlined workflow:** operations are smartly combined to minimize
  friction. For instance, the smart-commit command combines staging, committing,
  and pushing, and searching the file history combines unshallowing, searching,
  and diff navigation.

## Table of contents

<!-- toc -->

- [Installation](#installation)
- [Configuration](#configuration)
- [Commands](#commands)
	* [Interactive staging](#interactive-staging)
	* [Smart commit](#smart-commit)
	* [Amend and fixup commits](#amend-and-fixup-commits)
	* [Undo last commit/amend](#undo-last-commitamend)
	* [GitHub interaction](#github-interaction)
	* [Push & PRs](#push--prs)
	* [File history](#file-history)
	* [Stash](#stash)
- [Status line components](#status-line-components)
	* [git blame](#git-blame)
	* [Branch state](#branch-state)
- [Credits](#credits)

<!-- tocstop -->

## Installation
**Requirements**
- nvim 0.10+
- A plugin implementing `vim.ui.select`, such as:
  * [snacks.picker](http://github.com/folke/snacks.nvim)
  * [mini.pick](http://github.com/echasnovski/mini.pick)
  * [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim) with
	[telescope-ui-select](https://github.com/nvim-telescope/telescope-ui-select.nvim)
  * [fzf-lua](https://github.com/ibhagwan/fzf-lua)
- For interactive staging:
  [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim) (PRs
  adding support for other pickers are welcome.)
- For GitHub-related commands: `curl`
- *Recommended*: Treesitter parser for syntax highlighting `TSInstall
  gitcommit`.

```lua
-- lazy.nvim
{ 
	"chrisgrieser/nvim-tinygit",
	-- dependencies = "nvim-telescope/telescope.nvim", -- only for interactive staging
},

-- packer
use {
	"chrisgrieser/nvim-tinygit",
	-- requires = "nvim-telescope/telescope.nvim", -- only for interactive staging
}
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
		border = getBorder(), -- `vim.o.winborder` on nvim 0.11, otherwise "rounded"
		spellcheck = false, -- vim's builtin spellcheck
		wrap = "hard", ---@type "hard"|"soft"|"none"
		keymaps = {
			normal = { abort = "q", confirm = "<CR>" },
			insert = { confirm = "<C-CR>" },
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
```

## Commands
All commands are available as lua function or as sub-command of `:Tinygit`,
for example `require("tinygit").interactiveStaging()` and `:Tinygit
interactiveStaging`. Note that the lua function is preferable,
since `:Tinygit` does not accept command-specific options and does not
trigger visual-mode specific changes.

### Interactive staging
- Interactive straging requires `telescope`. (PRs adding support for other
  pickers welcome.)
- This command stages hunks, that is, *parts* of a file instead of the full
  file. It is roughly comparable to `git add -p`.
- Use `<Space>` to (un)stage the hunk, `<CR>` to go to the hunk, or `<C-r>` to
  reset the hunk (mappings customizable). Your regular `telescope` mappings also
  apply.
- The size of the hunks is determined by the setting `staging.contextSize`.
  Larger context size is going to "merge" changes that are close to one another
  into one hunk. (As such, the hunks displayed are not 1:1 the same as the hunks
  from `gitsigns.nvim`.) A context size between 1 and 4 is recommended.
- Limitation: `contextSize=0` (= no merging at all) is not supported.

```lua
require("tinygit").interactiveStaging()
```

### Smart commit
- Open a commit popup, alongside a preview of what is going to be committed. If
  there are no staged changes, stage all changes (`git add --all`) before the
  commit. Optionally run `git push` if the repo is clean after committing.
- The window title of the input field displays what actions are going to be
  performed. You can see at glance whether all changes are going to be
  committed, or whether there a `git push` is triggered afterward, so there are
  no surprises.
- Input field contents of aborted commits are briefly kept, if you just want to
  fix a detail.
- The first line is used as commit subject, the rest as commit body.

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

1. Stage some changes via `<leader>ga`.
2. Use `<leader>gc` to enter a commit message.
3. Repeat 1 and 2.
4. When done, use `<leader>gp` to push the commits.

Using `require("tinygit").smartCommit({pushIfClean = true})` allows you to
combine staging, committing, and pushing into a single step, when it is the last
commit you intend to make.

### Amend and fixup commits
**Amending**
- `amendOnlyMsg` just opens the commit popup to change the last commit message,
  and does not stage any changes.
- `amendNoEdit` keeps the last commit message; if there are no staged changes,
  stages all changes (`git add --all`), like `smartCommit`.
- Optionally runs `git push --force-with-lease` afterward, if the branch has
  diverged (that is, the amended commit was already pushed).

```lua
-- values shown are the defaults
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
-- values shown are the defaults
require("tinygit").fixupCommit {
	selectFromLastXCommits = 15,
	autoRebase = false,
}
```

### Undo last commit/amend

```lua
require("tinygit").undoLastCommitOrAmend()
```

- Changes in the working directory are kept but unstaged. (In the background,
  this uses `git reset --mixed`.)
- If there was a `push` operation done as a followup, the last commit is not
  undone.

### GitHub interaction
**Search issues & PRs**
- All GitHub interaction commands require `curl`.

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
- `"file"`: link to the file
- `"blame"`: link to the blame view of the file
- `"repo"`: link to the repo root

```lua
-- "file"|"repo"|"blame" (default: "file")
require("tinygit").githubUrl("file")
```

### Push & PRs
- `push` can be combined with other actions, depending on the options.
- `createGitHubPr` opens a PR from the current branch browser. (This requires the
  repo to be a fork with sufficient information on the remote.)

```lua
-- values shown are the defaults
require("tinygit").push {
	pullBefore = false,
	forceWithLease = false,
	createGitHubPr = false,
}
require("tinygit").createGitHubPr() -- to push before, use `.push { createGitHubPr = true }`
```

### File history
Search the git history of the current file. Select from the matching commits to
open a popup with a diff view of the changes.

If the config `history.autoUnshallowIfNeeded` is set to `true`, will also
automatically un-shallow the repo if needed.

```lua
require("tinygit").fileHistory()
```

The type of history search depends on the mode `.fileHistory` is called from:
- **Normal mode**: search file history for a string (`git log -G`)
	* Correctly follows file renamings, and displays past filenames in the
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
> win bar. If your status line is too crowded, you can add the blame-component
> to one of those bars instead.

The component can be configured with the `statusline.blame` options in the [plugin
configuration](#configuration).

### Branch state
Shows whether the local branch is ahead or behind of its remote counterpart.
(Note that this component does not run `git fetch` for performance reasons, so
the component may not be up-to-date with remote changes.)

```lua
require("tinygit.statusline").branchState()
```

## Credits
In my day job, I am a sociologist studying the social mechanisms underlying the
digital economy. For my PhD project, I investigate the governance of the app
economy and how software ecosystems manage the tension between innovation and
compatibility. If you are interested in this subject, feel free to get in touch.

- [Website](https://chris-grieser.de/)
- [Mastodon](https://pkm.social/@pseudometa)
- [ResearchGate](https://www.researchgate.net/profile/Christopher-Grieser)
- [LinkedIn](https://www.linkedin.com/in/christopher-grieser-ba693b17a/)

<a href='https://ko-fi.com/Y8Y86SQ91' target='_blank'> <img height='36'
style='border:0px;height:36px;' src='https://cdn.ko-fi.com/cdn/kofi1.png?v=3'
border='0' alt='Buy Me a Coffee at ko-fi.com' /></a>
