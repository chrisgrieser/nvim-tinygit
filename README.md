<!-- LTeX: enabled=false -->
# nvim-tinygit
<!-- LTeX: enabled=true -->
<a href="https://dotfyle.com/plugins/chrisgrieser/nvim-tinygit"><img src="https://dotfyle.com/plugins/chrisgrieser/nvim-tinygit/shield" /></a>

Lightweight and nimble git client for nvim.

<img src="https://github.com/chrisgrieser/nvim-tinygit/assets/73286100/009d9139-f429-49e2-a244-15396fb13d7a" alt="showcase commit message writing" width=65%>

<!--toc:start-->
- [Features](#features)
- [Installation](#installation)
- [Usage](#usage)
- [Example Workflows](#example-workflows)
- [Configuration](#configuration)
- [Non-Goals](#non-goals)
- [Credits](#credits)
<!--toc:end-->

## Features
- Smart-Commit: Open a popup to enter a commit message. If there are no staged changed, stages all changes before doing so (`git add -A`).
- Commit Messages have syntax highlighting, indicators for [commit message overlength](https://stackoverflow.com/questions/2290016/git-commit-messages-50-72-formatting), and optionally enforce conventional commits keywords.
- Option to run `git push` in a non-blocking manner after committing.
- Quick amends.
- Search issues & PRs. Open the selected issue or PR in the browser.
- Open the GitHub URL of the current file or selection.

## Installation

```lua
-- lazy.nvim
{
	"chrisgrieser/nvim-tinygit",
	dependencies = "stevearc/dressing.nvim",
},

-- packer
use {
	"chrisgrieser/nvim-tinygit",
	requires = "stevearc/dressing.nvim",
}
```

Optionally, install the Treesitter parser for git commits for some syntax highlighting of your commit messages like emphasized conventional commit keywords: `TSInstall gitcommit`

## Usage

```lua
-- Open a commit popup. If there are no staged changes, stage all changes (`git add -A`) before the commit. 
-- Right now, only supports the commit subject line. Optionally runs `git push` afterwards.
-- 💡 Use gitsigns.nvim's `add_hunk` command to conveniently stage changes.
-- 💡 To use vim commands in the input field, set dressing.nvim's `insert_only` to `false`.
require("tinygit").smartCommit({ push = false }) -- options default to `false`

-- Quick amends. 
-- `amendOnlyMsg` just opens the commit popup to change the last commit message, and does not stage any changes.
-- `amendNoEdit` keeps the last commit message; if there are no staged changes, it will stage all changes (`git add -A`).
-- Optionally runs `git push --force` afterwards (only recommended for single-person repos).
require("tinygit").amendOnlyMsg({ forcePush = false }) -- options default to `false`
require("tinygit").amendNoEdit({ forcePush = false }) -- options default to `false`

-- Search issues & PRs. Requires `curl`.
-- (Uses telescope, if you configure dressing.nvim to use telescope as selector.)
-- state: all|closed|open (default: all)
-- type: all|issue|pr (default: all)
require("tinygit").issuesAndPrs({ type = "all", state = "all" }) 

-- Open at GitHub and copy the URL to the system clipboard.
-- Normal mode: the current file, visual mode: the current selection.
require("tinygit").githubUrl("file") -- file|repo (default: file)

-- `git push`
require("tinygit").push({ pullBefore = false, force = false }) -- options default to `false`
```

## Example Workflows
Assuming these keybindings:

```lua
vim.keymap.set("n", "ga", "<cmd>Gitsigns add_hunk<CR>") -- gitsigns.nvim
vim.keymap.set("n", "gc", function() require("tinygit").smartCommit() end)
vim.keymap.set("n", "gm", function() require("tinygit").amendNoEdit() end)
```

1. Stage some hunks (changes) via `ga`.
2. Press `gc` to enter a commit message.
3. You have forgotten to add a comment. You add the comment.
4. Stage & amend the added comment in one go via `gm`.

---

You can also stage all changes, commit, and push them in one go via:

```lua
vim.keymap.set("n", "gC", function() require("tinygit").smartCommit({ push = true }) end)
```


## Configuration

The `setup` call is optional. These are the default settings:

```lua
local defaultConfig = {
	commitMsg = {
		-- Why 50/72 is recommended: https://stackoverflow.com/q/2290016/22114136
		maxLen = 72,
		mediumLen = 50,

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
		closedIssue = "🟣",
		openIssue = "🟢",
		openPR = "🟦",
		mergedPR = "🟨",
		closedPR = "🟥",
	},
}
```

> [!NOTE]
> To change the appearance and behavior of the commit message input field, you need to configure [dressing.nvim](https://github.com/stevearc/dressing.nvim).

## Non-Goals
- Become a full-fledged git client. Use [neogit](https://github.com/NeogitOrg/neogit) for that.
- Add features available in [gitsigns.nvim](https://github.com/lewis6991/gitsigns.nvim). `tinygit` is intended to complement `gitsigns.nvim` with some simple commands, not replace it.
- UI Customization. Configure [dressing.nvim](https://github.com/stevearc/dressing.nvim) for that.

## Credits
__About Me__  
In my day job, I am a sociologist studying the social mechanisms underlying the digital economy. For my PhD project, I investigate the governance of the app economy and how software ecosystems manage the tension between innovation and compatibility. If you are interested in this subject, feel free to get in touch.

__Blog__  
I also occasionally blog about vim: [Nano Tips for Vim](https://nanotipsforvim.prose.sh)

__Profiles__  
- [reddit](https://www.reddit.com/user/pseudometapseudo)
- [Discord](https://discordapp.com/users/462774483044794368/)
- [Academic Website](https://chris-grieser.de/)
- [Twitter](https://twitter.com/pseudo_meta)
- [Mastodon](https://pkm.social/@pseudometa)
- [ResearchGate](https://www.researchgate.net/profile/Christopher-Grieser)
- [LinkedIn](https://www.linkedin.com/in/christopher-grieser-ba693b17a/)

__Buy Me a Coffee__  
<br>
<a href='https://ko-fi.com/Y8Y86SQ91' target='_blank'><img height='36' style='border:0px;height:36px;' src='https://cdn.ko-fi.com/cdn/kofi1.png?v=3' border='0' alt='Buy Me a Coffee at ko-fi.com' /></a>
