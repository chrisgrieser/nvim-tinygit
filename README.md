<!-- LTeX: enabled=false -->
# nvim-tinygit
<!-- LTeX: enabled=true -->
<a href="https://dotfyle.com/plugins/chrisgrieser/nvim-tinygit"><img src="https://dotfyle.com/plugins/chrisgrieser/nvim-tinygit/shield"/></a>

Lightweight and nimble git client for nvim.

<img src="https://github.com/chrisgrieser/nvim-tinygit/assets/73286100/009d9139-f429-49e2-a244-15396fb13d7a"
	alt="showcase commit message input field"
	width=65%>

*Commit Message Input with highlighting*

<img src="https://github.com/chrisgrieser/nvim-tinygit/assets/73286100/123fcfd9-f989-4c10-bd98-32f62ea683c3"
	alt="showcase commit message notification"
	width=50%>

*Informative notifications with highlighting (using `nvim-notify`)*

<img src="https://github.com/chrisgrieser/nvim-tinygit/assets/73286100/99cc8def-760a-4cdd-9aea-fbd1fb3d1ecb"
	alt="Pasted image 2023-10-11 at 18 49 40"
	width=60%>

*Search File history ("git pickaxe") and inspect the commit diffs.*

## Table of Contents

<!-- toc -->

- [Features](#features)
- [Installation](#installation)
- [Usage](#usage)
	* [Smart-Commit](#smart-commit)
	* [Quick Amends](#quick-amends)
	* [GitHub Interaction](#github-interaction)
	* [Push](#push)
	* [Search File History ("git pickaxe")](#search-file-history-git-pickaxe)
- [Configuration](#configuration)
- [Non-Goals](#non-goals)
- [Credits](#credits)

<!-- tocstop -->

## Features
- Smart-Commit: Open a popup to enter a commit message. If there are no staged
  changed, stages all changes before doing so (`git add -A`).
- Option to automatically open references GitHub issues in the browser after committing.
- Commit Messages have syntax highlighting, indicators for [commit message
  overlength](https://stackoverflow.com/questions/2290016/git-commit-messages-50-72-formatting),
  and optionally enforce conventional commits keywords.
- Option to run `git push` in a non-blocking manner after committing.
- Quick amends.
- Search issues & PRs. Open the selected issue or PR in the browser.
- Open the GitHub URL of the current file or selection.
- Search the file history for a string ("git pickaxe"), show results in a diff
  with filetype syntax highlighting.

## Installation

```lua
-- lazy.nvim
{
	"chrisgrieser/nvim-tinygit",
	dependencies = {
		"stevearc/dressing.nvim",
		"rcarriga/nvim-notify", -- optional, but recommended
	},
},

-- packer
use {
	"chrisgrieser/nvim-tinygit",
	requires = {
		"stevearc/dressing.nvim",
		"rcarriga/nvim-notify", -- optional, but recommended
	},
}
```

Optionally, install the Treesitter parser for git commits for some syntax
highlighting of your commit messages like emphasized conventional commit
keywords: `TSInstall gitcommit`

## Usage

### Smart-Commit
- Open a commit popup. If there are no staged changes, stage all changes (`git
  add -A`) before the commit. Only supports the commit subject line.
- Optionally run `git push` if the repo is clean after committing, or opens
  references issues in the browser.
- The title of the input field displays what actions are going to be performed.
  You can see at glance, whether all changes are going to be committed or whether
  there a `git push` is triggered afterward, so there are no surprises.
- 💡 To use vim commands in the input field, set dressing.nvim's `insert_only`
  to `false`.

```lua
-- options default to `false`
require("tinygit").smartCommit { pushIfClean = false, openReferencedIssue = false }
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

### Quick Amends
- `amendOnlyMsg` just opens the commit popup to change the last commit message,
  and does not stage any changes.
- `amendNoEdit` keeps the last commit message; if there are no staged changes,
  it stages all changes (`git add -A`).
- Optionally runs `git push --force` afterward (only recommended for
  single-person repos).

```lua
-- options default to `false`
require("tinygit").amendOnlyMsg { forcePush = false }
require("tinygit").amendNoEdit { forcePush = false }
```

### GitHub Interaction
- Search issues & PRs. (Requires `curl`.)
- The appearance of the selector is controlled by `dressing.nvim`. (You can
  configure `dressing` to use `telescope`.)

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

### Push

```lua
-- options default to `false`
require("tinygit").push { pullBefore = false, force = false }
```

### Search File History ("git pickaxe")
- Search the git history of the current file for a term ("git pickaxe").
- The search is case-insensitive and supports regex.
- Select from the matching commits to open a diff popup.
- Keymaps in the diff popup:
	* `n`/`N`: go to the next/previous occurrence of the query.
	* `<Tab>`/`<S-Tab>`: cycle through the commits.
	* `yh`: yank the commit hash to the system clipboard.

```lua
require("tinygit").searchFileHistory()
```

## Configuration
The `setup` call is optional. These are the default settings:

```lua
local defaultConfig = {
	commitMsg = {
		-- Why 50/72 is recommended: https://stackoverflow.com/q/2290016/22114136
		mediumLen = 50,
		maxLen = 72,

		-- When conforming the commit message popup with an empty message, fill
		-- in this message. `false` to disallow empty commit messages.
		emptyFillIn = "chore", ---@type string|false

		-- disallow commit messages without a conventinal commit keyword
		enforceConvCommits = {
			enabled = true,
			-- stylua: ignore
			keywords = {
				"chore", "build", "test", "fix", "feat", "refactor", "perf",
				"style", "revert", "ci", "docs", "break", "improv",
			},
		},
	},
	asyncOpConfirmationSound = true, -- currently macOS only
	issueIcons = {
		openIssue = "🟢",
		closedIssue = "🟣",
		openPR = "🟩",
		mergedPR = "🟪",
		closedPR = "🟥",
	},
	searchFileHistory = {
		diffPopupWidth = 0.8, -- float, 0 to 1
		diffPopupHeight = 0.8, -- float, 0 to 1
		diffPopupBorder = "single",
	},
}
```

> [!NOTE]
> To change the appearance and behavior of the commit message input field, you
> need to configure [dressing.nvim](https://github.com/stevearc/dressing.nvim).

## Non-Goals
- Become a full-fledged git client. Use
  [neogit](https://github.com/NeogitOrg/neogit) for that.
- Add features available in
  [gitsigns.nvim](https://github.com/lewis6991/gitsigns.nvim). `tinygit` is
  intended to complement `gitsigns.nvim` with some simple commands, not replace
  it.
- UI Customization. Configure
  [dressing.nvim](https://github.com/stevearc/dressing.nvim) for that.

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
