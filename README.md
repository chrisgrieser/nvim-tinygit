<!-- LTeX: enabled=false -->
# nvim-tinygit
<!-- LTeX: enabled=true -->
<a href="https://dotfyle.com/plugins/chrisgrieser/nvim-tinygit">
<img alt="badge" src="https://dotfyle.com/plugins/chrisgrieser/nvim-tinygit/shield"/></a>

A lightweight bundle of commands focussed on swift and streamlined git
operations.

<!-- toc -->

- [Features](#features)
- [Installation](#installation)
- [Commands](#commands)
	* [Smart-Commit](#smart-commit)
	* [Amend](#amend)
	* [Fixup & Squash Commits](#fixup--squash-commits)
	* [GitHub Interaction](#github-interaction)
	* [Push & PR](#push--pr)
	* [Search File/Function History ("git pickaxe")](#search-filefunction-history-git-pickaxe)
	* [Stash](#stash)
- [Other Features](#other-features)
	* [Improved Highlighting of Interactive Rebase](#improved-highlighting-of-interactive-rebase)
	* [Git Blame Status Line Component](#git-blame-status-line-component)
- [Configuration](#configuration)
- [Comparison to existing git plugins](#comparison-to-existing-git-plugins)
- [Credits](#credits)

<!-- tocstop -->

## Features
- **Smart-Commit:** Open a popup to enter a commit message with syntax highlighting
  and indicators for commit message overlength. If there are no staged changed,
  stages all changes before doing so (`git add -A`). Optionally trigger a `git
  push` afterward.
- Quick commands for amend, stash, fixup, and squash commits.
- Search **issues & PRs**. Open the selected issue or PR in the browser.
- Open the **GitHub URL** of the current file or selection.
- **Search the file history** for a string ("git pickaxe"), show results in a diff
  with filetype syntax highlighting, correctly following file renamings.
- Highlighting improvements for interactive **rebasing** when using nvim as sequence
  editor.

| Commit Message Input   | Commit Notification   |
|--------------- | -------------- |
| <img src="https://github.com/chrisgrieser/nvim-tinygit/assets/73286100/009d9139-f429-49e2-a244-15396fb13d7a" alt="showcase 1">   | <img src="https://github.com/chrisgrieser/nvim-tinygit/assets/73286100/de3049b4-68fc-4362-99ff-e8a6e09e1af7" alt="showcase 2">   |

| Select From Commit History ("git pickaxe")   | File History Diff Popup   |
|--------------- | -------------- |
| <img src="https://github.com/chrisgrieser/nvim-tinygit/assets/73286100/a8a775bf-f7ce-4730-83e3-a91563481d35" alt="showcase 3">   | <img src="https://github.com/chrisgrieser/nvim-tinygit/assets/73286100/99cc8def-760a-4cdd-9aea-fbd1fb3d1ecb" alt="showcase 4">   |

## Installation

Install the Treesitter parser for git filetypes: `TSInstall gitcommit gitrebase`

```lua
-- lazy.nvim
{
	"chrisgrieser/nvim-tinygit",
	ft = { "gitrebase", "gitcommit" }, -- so ftplugins are loaded
	dependencies = {
		"stevearc/dressing.nvim",
		"nvim-telescope/telescope.nvim", -- either telescope or fzf-lua
		-- "ibhagwan/fzf-lua",
		"rcarriga/nvim-notify", -- optional, but will lack some features without it
	},
},

-- packer
use {
	"chrisgrieser/nvim-tinygit",
	requires = {
		"stevearc/dressing.nvim",
		"nvim-telescope/telescope.nvim", -- either telescope or fzf-lua
		-- "ibhagwan/fzf-lua",
		"rcarriga/nvim-notify", -- optional, but will lack some features without it
	},
}
```

## Commands

### Smart-Commit
- Open a commit popup, alongside a preview of what is going to be committed. If
  there are no staged changes, stage all changes (`git add --all`) before the
  commit. Currently, only supports the commit subject line (no commit body).
- Optionally run `git push` if the repo is clean after committing.
- The title of the input field displays what actions are going to be performed.
  You can see at glance, whether all changes are going to be committed or whether
  there a `git push` is triggered afterward, so there are no surprises.

```lua
require("tinygit").smartCommit { pushIfClean = false } -- options default to `false`
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
  it stages all changes (`git add --all`), like `smartCommit`.
- Optionally runs `git push --force` afterward, if the branch has diverged (the
  amended commit was already pushed).

```lua
-- options default to `false`
require("tinygit").amendOnlyMsg { forcePushIfDiverged = false }
require("tinygit").amendNoEdit { forcePushIfDiverged = false }
```

### Fixup & Squash Commits
- `fixupCommit` lets you select a commit from the last X commits and runs `git
  commit --fixup` on the selected commit
- Use `squashInstead = true` to squash instead of fixup (`git commit --squash`).
- `autoRebase = true` automatically runs rebase with `--autosquash` and
`--autostash` afterward, confirming all fixups and squashes **without opening a
rebase view**. (Note that this can potentially result in conflicts.)

```lua
-- options show default values
require("tinygit").fixupCommit { 
	selectFromLastXCommits = 15
	squashInstead = false, 
	autoRebase = false,
}
```

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
	force = false,
	createGitHubPr = false,
}
require("tinygit").createGitHubPr()
```

### Search File/Function History ("git pickaxe")
Search the git history. Select from the matching commits to open a popup with a
diff of the changes.

- Search the git **history of the current file for a term** (`git log -G`).
	* The search is case-insensitive and supports regex.
	* Correctly follows file renamings, display past file names in the commit
	  selection.
- Explore the **history of a function in the current file** (`git log -L`).
	* The search is literal.
	* If the current buffer has an LSP with support for document symbols
	  attached, you can select a function. (Otherwise, you are prompted to
	  enter a function name.)
	* Note that [`git` uses heuristics to determine the enclosing function of a
	  change](https://news.ycombinator.com/item?id=38153309), so this is not
	  100% perfect and has varying reliability across languages.

**Keymaps in the diff popup**
- `<Tab>`/`<S-Tab>`: cycle through the commits.
- `yh`: yank the commit hash to the system clipboard.
- `n`/`N` (file history): go to the next/previous occurrence of the query.

```lua
require("tinygit").searchFileHistory()
require("tinygit").functionHistory()
```

### Stash

```lua
require("tinygit").stashPush()
require("tinygit").stashPop()
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

### Git Blame Status Line Component
Shows the message and date (`git blame`) of the last commit that changed the
current *file* (not line).

```lua
require("tinygit.gitblame").statusLine()
```

The component can be configured with the `blameStatusLine` options in the [plugin
configuration](#configuration).

## Configuration
The `setup` call is optional. These are the default settings:

```lua
local defaultConfig = {
	commitMsg = {
		-- Why 50/72 is recommended: https://stackoverflow.com/q/2290016/22114136
		mediumLen = 50,
		maxLen = 72,

		-- When conforming the commit message popup with an empty message, fill in
		-- this message. Set to `false` to disallow empty commit messages.
		emptyFillIn = "chore", ---@type string|false

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
	},
	push = {
		preventPushingFixupOrSquashCommits = true,
		confirmationSound = true, -- currently macOS only
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
	blameStatusLine = {
		ignoreAuthors = {}, -- any of these authors and the blame will be hidden
		maxMsgLen = 30,
		icon = " ",
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

## Comparison to existing git plugins
- `gitsigns.nvim`: No feature overlap. `tinygit` rather complements `gitsigns`
  as the latter is used to stage changes (`:GitSigns stage_hunk`) quickly, and
  the former allows you to commit (and push) those changes quickly.
- `Neogit` / `Fugitive`: These two probably cover every feature `tinygit` has,
  but with much more configuration options. The benefit of `tinygit` is that it
  is aims to streamline common actions as much as possible by smartly combining
  git operations. For instance, smart-commit combines staging, committing, and
  pushing.
- `diffview.nvim`: No overlap, except for the command to search the file history.
  `tinygit`'s version of file history search should be easier to use and has a few
  more quality-of-life features, such as automatically jumping to occurrences of
  the search term. As opposed to `diffview`, the diff is not presented in a
  side-by-side-diff, but in a unified view.

<!-- vale Google.FirstPerson = NO -->
## Credits
**About Me**  
In my day job, I am a sociologist studying the social mechanisms underlying the
digital economy. For my PhD project, I investigate the governance of the app
economy and how software ecosystems manage the tension between innovation and
compatibility. If you are interested in this subject, feel free to get in touch.

**Blog**  
I also occasionally blog about vim: [Nano Tips for Vim](https://nanotipsforvim.prose.sh)

**Profiles**  
- [reddit](https://www.reddit.com/user/pseudometapseudo)
- [Discord](https://discordapp.com/users/462774483044794368/)
- [Academic Website](https://chris-grieser.de/)
- [Twitter](https://twitter.com/pseudo_meta)
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
