# mise activation for Git Bash

## TL;DR

This is a small helper script to make [mise](https://mise.jdx.dev) activation work properly in Git Bash. 

Mise supports Windows via PowerShell/pwsh and WSL, but not Git Bash. This script fixes PATH handling there.

---

## Problem
- In Git Bash, mise produces **Windows-style PATH**. 
- This breaks tool resolution because Git Bash expects **Unix-style paths**.
- Running `eval "$(mise activate bash)"` directly is incorrect in Git Bash.

You can read more about how mise PATH activation works in the official docs: [mise shims and PATH activation](https://mise.jdx.dev/dev-tools/shims.html#path-activation)

---

## Requirements

- mise >= 2025.12.1  
- Git Bash >= 2.52.0  
- cygpath and stat (included with Git Bash) 

This script is only tested with the versions above. Older versions might work, but are not tested.

## How it works 
- Gets PATH from `mise env` and converts it using `cygpath`
- Stays in sync with project changes using upward search
- Uses caching to avoid slow repeated calls to `mise env`

---

## Installation

**1. Download the script**

Save `activate.sh` into `~/.config/mise`:

```bash
curl --create-dirs -o ~/.config/mise/activate.sh https://raw.githubusercontent.com/phrechu/mise-activate-gitbash/main/activate.sh
```

**2. Source it from your bash config**

Edit `~/.bashrc` and add:

```bash
source ~/.config/mise/activate.sh
```

If you already had `eval "$(mise activate bash)"` in your `.bashrc`, remove that line.

**3. Reload your shell**

```bash
source ~/.bashrc
```

**4. Check PATH**

Run:

`mise-path`

You should see a Unix style PATH (paths separated by `:` and using `/c/...` instead of `C:\...`).

---

## Usage

You do not need to run anything manually most of the time.

- The script hooks into `PROMPT_COMMAND` and keeps PATH in sync as you `cd` and run commands.    
- When you want to force a rebuild or inspect PATH, run: `mise-path`

If mise starts supporting Git Bash natively in the future, `mise-path` will tell you and suggest trying the official activation instead.
