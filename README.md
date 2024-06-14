<!-- LTeX: enabled=false -->
# nvim-tinygit
<!-- LTeX: enabled=true -->
<a href="https://dotfyle.com/plugins/chrisgrieser/nvim-tinygit">
<img alt="badge" src="https://dotfyle.com/plugins/chrisgrieser/nvim-tinygit/shield"/></a>

A lightweight bundle of commands focussed on swift and streamlined git
operations.

<!-- toc -->

- [Features Overview](#features-overview)
- [Installation](#installation)
- [Commands](#commands)
	* [Smart-Commit](#smart-commit)
	* [Amend](#amend)
	* [Fixup & Squash Commits](#fixup--squash-commits)
	* [Undo Last Commit/Amend](#undo-last-commitamend)
	* [GitHub Interaction](#github-interaction)
	* [Push & PR](#push--pr)
	* [Search File/Function/Line History ("git pickaxe")](#search-filefunctionline-history-git-pickaxe)
	* [Stash](#stash)
- [Status Line Components](#status-line-components)
	* [Git Blame](#git-blame)
	* [Branch State](#branch-state)
- [Other Features](#other-features)
	* [Improved Highlighting of Interactive Rebase](#improved-highlighting-of-interactive-rebase)
- [Configuration](#configuration)
- [Comparison to existing git plugins](#comparison-to-existing-git-plugins)
- [Credits](#credits)

<!-- tocstop -->

## Features Overview
- **Smart-Commit**: Open a popup to enter a commit message with syntax highlighting,
  commit preview, and overlength indicators. If there are no staged
  changes, stages all changes before doing so (`git add -A`). Optionally trigger
  a `git push` afterward.
- Quick commands for amend, stash, fixup, or undoing commits.
- Search **issues & PRs**. Open the selected issue or PR in the browser.
- Open the **GitHub URL** of the current line or selection.
- **Search the file history** for a string ("git pickaxe"), show results in a diff view
  with syntax highlighting, correctly following file renamings.
- **Statusline components:** `git blame` and branch state.
- **Streamlined workflow:** operations are smartly combined to minimize
  friction. For instance, the smart-commit command combines staging, committing,
  and pushing, and searching the file history combines unshallowing, searching,
  and navigating diffs.

<img alt="Showcase smart commit" width=70% src="https://github.com/chrisgrieser/nvim-tinygit/assets/73286100/f09dba0b-a81e-4973-897a-20605f4c29db">
<img alt="Showcase diffview" width=70% src="https://github.com/chrisgrieser/nvim-tinygit/assets/73286100/34161d44-02eb-4340-a7ea-d18d436b4ab4">
<img alt="Showcase statusline components" width=70% src="https://github.com/chrisgrieser/nvim-tinygit/assets/73286100/20b8bc97-e1dc-4b7d-8d0e-54f2ed3f10ce">

## Installation
**Hard Requirements**  
- nvim 0.10 or higher
- `dressing.nvim`

**Optional/Recommended Requirements**
- Treesitter parsers for git filetypes: `TSInstall gitcommit git_rebase`
- `nvim-notify` for the commit preview & various notifications
- [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim) or
  [fzf-lua](https://github.com/ibhagwan/fzf-lua) for better selectors when
  selecting commits or issues/PRs.

```lua
-- lazy.nvim
{
	"chrisgrieser/nvim-tinygit",
	ft = "git_rebase", -- so ftplugin is loaded
	dependencies = "stevearc/dressing.nvim",
},

-- packer
use {
	"chrisgrieser/nvim-tinygit",
	requires = "stevearc/dressing.nvim",
}
```

## Commands

### Smart-Commit
- Open a commit popup, alongside a preview of what is going to be committed. If
  there are no staged changes, stage all changes (`git add --all`) before the
  commit.
- Input field contents of aborted commits are briefly kept, if you just want to
  fix a detail.
- Optionally run `git push` if the repo is clean after committing.
- The title of the input field displays what actions are going to be performed.
  You can see at glance whether all changes are going to be committed, or whether
  there a `git push` is triggered afterward, so there are no surprises.
- Only supports the commit subject line (no commit body).

```lua
-- values shown are the defaults
require("tinygit").smartCommit { pushIfClean = false, pullBeforePush = true }
```

**Example Workflow**
Assuming these keybindings:

```lua
vim.keymap.set("n", "ga", "<cmd>Gitsigns add_hunk<CR>") -- gitsigns.nvim
vim.keymap.set("n", "gc", function() require("tinygit").smartCommit() end)
vim.keymap.set("n", "gp", function() require("tinygit").push() end)
```

1. Stage some hunks (changes) via `ga`.
2. Use `gc` to enter a commit message.
3. Repeat 1 and 2.
4. When done, `gp` to push the commits.

Using `pushIfClean = true` allows you to combine staging, committing, and
pushing into a single step, when it is the last commit you intend to make.

### Amend
- `amendOnlyMsg` just opens the commit popup to change the last commit message,
  and does not stage any changes.
- `amendNoEdit` keeps the last commit message; if there are no staged changes,
  stages all changes (`git add --all`), like `smartCommit`.
- Optionally runs `git push --force-with-lease` afterward, if the branch has
  diverged (that is, the amended commit was already pushed).

```lua
-- options default to `false`
require("tinygit").amendOnlyMsg { forcePushIfDiverged = false }
require("tinygit").amendNoEdit { forcePushIfDiverged = false }
```

### Fixup & Squash Commits
- `fixupCommit` lets you select a commit from the last X commits and runs `git
  commit --fixup` on the selected commit.
- If there are no staged changes, stages all changes (`git add --all`), like
  `smartCommit`.
- Use `squashInstead = true` to squash instead of fixup (`git commit --squash`).
- `autoRebase = true` automatically runs rebase with `--autosquash` and
`--autostash` afterward, confirming all fixups and squashes **without opening a
rebase view**. (Note that this can potentially result in conflicts.)

```lua
-- options show default values
require("tinygit").fixupCommit {
	selectFromLastXCommits = 15,
	squashInstead = false,
	autoRebase = false,
}
```

### Undo Last Commit/Amend

```lua
require("tinygit").undoLastCommitOrAmend()
```

- Changes in the working directory are kept, but unstaged. (In the background,
  this uses `git reset --mixed`.)
- Any `push` operation done as a followup (such as `.smartCommit {
  pushIfClean = false }`) is not undone.

### GitHub Interaction
- Search issues & PRs. (Requires `curl`.)

```lua
-- state: all|closed|open (default: all)
-- type: all|issue|pr (default: all)
require("tinygit").issuesAndPrs { type = "all", state = "all" }

-- alternative: if the word under the cursor is of the form `#123`,
-- just open that issue/PR
require("tinygit").openIssueUnderCursor()
```

- Open the current file at GitHub in the browser and copy the URL to the system clipboard.
- Normal mode: open the current file or repo.
- Visual mode: open the current selection.

```lua
-- file|repo (default: file)
require("tinygit").githubUrl("file")
```

### Push & PR
- `push` can be combined with other actions, depending on the options.
- `createGitHubPr` opens a PR from the current branch browser.
	* This requires the repo to be a fork with sufficient information on the remote.
	* This does not require the `gh` cli, as it uses a GitHub web feature.

```lua
-- options default to `false`
require("tinygit").push {
	pullBefore = false,
	forceWithLease = false,
	createGitHubPr = false,
}
require("tinygit").createGitHubPr()
```

### Explore the History of a File, Function, or Line ("git pickaxe")
Search the git history. Select from the matching commits to open a popup with a
diff of the changes.

- Search the git **history of the current file** (`git log -G`).
	* The search is case-insensitive and supports regex.
	* Correctly follows file renamings, and displays past file names in the commit
	  selection.
- Explore the **history of a function in the current file** (`git log -L`).
	* The search is literal.
	* If the current buffer has an LSP with support for document symbols
	  attached, you can select a function. (Otherwise, you are prompted to
	  enter a function name.)
	* Note that [`git` uses heuristics to determine the enclosing function of a
	  change](https://news.ycombinator.com/item?id=38153309), so this is not
	  100% perfect and has varying reliability across languages.
- Go through the **history of the current line (range)** (`git log -L`).
	* In normal mode, searches the history of the line under the cursor.
	* When called in visual mode, searches the history of the selected line
	  range.

**Keymaps in the diff popup**
- `<Tab>`: show older commit
- `<S-Tab>`: show newer commit
- `yh`: yank the commit hash to the system clipboard
- `n`/`N`: go to the next/previous occurrence of the query (only file history)

```lua
require("tinygit").searchFileHistory()
require("tinygit").functionHistory()
require("tinygit").lineHistory()
```

### Stash
Simple wrappers around `git stash push` and `git stash pop`.

```lua
require("tinygit").stashPush()
require("tinygit").stashPop()
```

## Status Line Components

### Git Blame
Shows the message and date (`git blame`) of the last commit that changed the
current *file* (not line).

```lua
require("tinygit.statusline").blame()
```

> [!TIP]
> Some status line plugins also allow you to put components into the tabline or
> winbar. If your status line is too crowded, you can add the blame-component to
> the one of those bars instead.

The component can be configured with the `statusline.blame` options in the [plugin
configuration](#configuration).

### Branch State
Shows whether the local branch is ahead or behind of its remote counterpart.
(Note that this component does not run `git fetch` for performance reasons, so
the information may not be up-to-date with remote changes.)

```lua
require("tinygit.statusline").branchState()
```

## Other Features

### Improved Highlighting of Interactive Rebase
`tinygit` also comes with some highlighting improvements for interactive
rebasing (`git rebase -i`).

> [!NOTE]
> This requires `nvim` as your git editor (or sequence editor).
> You can do so by running `git config --global core.editor "nvim"`.

If you want to disable the modifications by `tinygit`, add this to your config:

```lua
vim.g.tinygit_no_rebase_ftplugin = true
```

## Configuration
The `setup` call is optional. These are the default settings:

```lua
local defaultConfig = {
	commitMsg = {
		-- Shows diffstats of the changes that are going to be committed.
		-- (requires nvim-notify)
		commitPreview = true,

		conventionalCommits = {
			enforce = false, -- disallow commit messages without a keyword
			-- stylua: ignore
			keywords = {
				"fix", "feat", "chore", "docs", "refactor", "build", "test",
				"perf", "style", "revert", "ci", "break", "improv",
			},
		},

		-- enable vim's builtin spellcheck for the commit message input field.
		-- (configured to ignore capitalization and correctly consider camelCase)
		spellcheck = false,

		-- if commit message references issue/PR, open it in the browser
		openReferencedIssue = false,

		-- how long to remember the state of the message input field when aborting
		keepAbortedMsgSecs = 300,
	},
	push = {
		preventPushingFixupOrSquashCommits = true,
		confirmationSound = true, -- currently macOS only, PRs welcome
	},
	issueIcons = {
		openIssue = "🟢",
		closedIssue = "🟣",
		openPR = "🟩",
		mergedPR = "🟪",
		closedPR = "🟥",
	},
	historySearch = {
		diffPopup = {
			width = 0.8, -- float, 0 to 1
			height = 0.8,
			border = "single",
		},
		-- if trying to call `git log` on a shallow repository, automatically
		-- unshallow the repo by running `git fetch --unshallow`
		autoUnshallowIfNeeded = false,
	},
	statusline = {
		blame = {
			-- Any of these authors and the component is not shown (useful for bots)
			ignoreAuthors = {},

			-- show component, but leave out names (useful for your own name)
			hideAuthorNames = {},

			maxMsgLen = 35,
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
}
```

The appearance of the commit message input field and of the selectors is
configured via [dressing.nvim](https://github.com/stevearc/dressing.nvim). To
enable normal mode in the input field, use:

```lua
require("dressing").setup {
	input = { insert_only = false },
}
```

The appearance of the commit preview is determined by
[nvim-notify](https://github.com/rcarriga/nvim-notify). To change for example
the width of the preview, use:

```lua
require("notify").setup {
	max_width = 60,
}
```

## Comparison to existing git plugins
- `gitsigns.nvim`: No feature overlap. `tinygit` rather complements `gitsigns`
  as the latter is used to stage changes (`:GitSigns stage_hunk`) quickly, and
  the former allows you to commit (and push) those changes quickly.
- `Neogit` / `Fugitive`: These two probably cover much more features than
  `tinygit` has, but with much more configuration options. The benefit of
  `tinygit` is that it is more lightweight and aims to streamline common actions
  by smartly combining operations. For instance, the smart-commit command
  combines staging, committing, and pushing. As such, `tinygit` is mostly for
  those people that do want a more nimble and lightweight git integration.
- `diffview.nvim`: No overlap, except for the command to search the file history.
  `tinygit`'s version of file history search should be easier to use and has a few
  more quality-of-life features, such as automatically jumping to occurrences of
  the search term. As opposed to `diffview`, the diff is not presented in a
  side-by-side-diff, but in a unified view.

<!-- vale Google.FirstPerson = NO -->
## Credits
In my day job, I am a sociologist studying the social mechanisms underlying the
digital economy. For my PhD project, I investigate the governance of the app
economy and how software ecosystems manage the tension between innovation and
compatibility. If you are interested in this subject, feel free to get in touch.

I also occasionally blog about vim: [Nano Tips for Vim](https://nanotipsforvim.prose.sh)

- [Academic Website](https://chris-grieser.de/)
- [Mastodon](https://pkm.social/@pseudometa)
- [ResearchGate](https://www.researchgate.net/profile/Christopher-Grieser)
- [LinkedIn](https://www.linkedin.com/in/christopher-grieser-ba693b17a/)

<a href='https://ko-fi.com/Y8Y86SQ91' target='_blank'>
<img
	height='36'
	style='border:0px;height:36px;'
	src='https://cdn.ko-fi.com/cdn/kofi1.png?v=3'
	border='0'
	alt='Buy Me a Coffee at ko-fi.com'
/></a>
