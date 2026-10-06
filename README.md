# Hammerspace Cluster Remote Admin CLI Console

A CLI wrapper for Hammerspace admin commands. Load the script and you are immediately dropped into the `hsa>` prompt — type Hammerspace commands directly, no prefix required. Includes tab completion, field extraction, CSV export, and command chaining.

```
[hsa] Hammerspace CLI wrapper loaded.
     Type commands directly at hsa> — no prefix needed.
     Built-ins: login  logout  status  session  help  exit
     Credentials will be prompted on first use.

Hammerspace CLI - hsa mode
Type HS commands directly. Built-ins: help, status, login, logout, session, exit.

hsa> share-list
hsa> share-list -print name
hsa> exit
```

---

## Downloads

| Platform | File | Version |
|---|---|---|
| **Mac / Linux** | [`hsacli.sh`](hsacli.sh) | v1.6.0 |
| **Windows (PowerShell)** | [`hsacli.ps1`](hsacli.ps1) | v1.1.0 |

> Both scripts expose the same commands, flags, and behaviour. Feature parity is maintained across platforms.

---

## Table of Contents

- [Requirements](#requirements)
- [Installation](#installation)
  - [Mac / Linux](#mac--linux)
  - [Windows](#windows)
- [Connecting to a cluster](#connecting-to-a-cluster)
- [Using hsa> mode](#using-hsa-mode)
- [Tab completion](#tab-completion)
- [-print — extract field values](#-print--extract-field-values)
- [-recursive — run commands per value](#-recursive--run-commands-per-value)
- [Exporting output](#exporting-output)
- [Session management](#session-management)
- [Troubleshooting](#troubleshooting)
- [Security notes](#security-notes)
- [Version history](#version-history)

---

## Requirements

### Mac / Linux (`hsacli.sh`)

| Requirement | Notes |
|---|---|
| `ssh` | Included with macOS and all Linux distros |
| `sshpass` | Must be installed separately (see below) |
| Bash 3.2+ or Zsh | macOS ships both; Zsh is the default since Catalina |

**Installing sshpass:**

```bash
# Debian / Ubuntu
apt install sshpass

# RHEL / CentOS / Fedora
yum install sshpass

# macOS — the tap is required; brew install sshpass alone will not work
brew install hudochenkov/sshpass/sshpass
```

### Windows (`hsacli.ps1`)

| Requirement | Notes |
|---|---|
| PowerShell 5.1 | Built into Windows 10 and 11 |
| PowerShell 7+ | Recommended — better tab-completion UI. [Download](https://aka.ms/powershell) |
| plink.exe (PuTTY) | Required for SSH. [Download PuTTY](https://www.chiark.greenend.org.uk/~sgtatham/putty/latest.html) |

The PuTTY installer adds `plink.exe` to your PATH automatically. If you place it manually, ensure its folder is on your PATH.

---

## Installation

### Mac / Linux

Source the script. You are immediately placed at the `hsa>` prompt.

```bash
source /path/to/hsacli.sh
```

**Make it permanent** — add the source line to your shell's startup file so it opens automatically on every new terminal:

```bash
# macOS (Zsh — default since Catalina)
echo 'source /path/to/hsacli.sh' >> ~/.zshrc

# Linux Bash
echo 'source /path/to/hsacli.sh' >> ~/.bashrc

# Apply immediately without opening a new terminal
source ~/.zshrc   # or ~/.bashrc
```

You can also run it directly as a standalone session:

```bash
bash /path/to/hsacli.sh
```

### Windows

**One-time setup** — allow locally-created scripts to run:

```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

**Dot-source the script.** You are immediately placed at the `hsa>` prompt:

```powershell
. C:\path\to\hsacli.ps1
```

**Make it permanent** — add the dot-source line to your PowerShell profile:

```powershell
# Find your profile path
$PROFILE

# Open or create the profile
notepad $PROFILE

# Add this line (adjust path as needed)
. C:\Users\YourName\tools\hsacli.ps1

# Apply immediately
. $PROFILE
```

> If the profile file doesn't exist yet:
> ```powershell
> New-Item -Path $PROFILE -ItemType File -Force
> notepad $PROFILE
> ```

You can also run directly as a standalone session:

```powershell
powershell -File C:\path\to\hsacli.ps1
```

---

## Connecting to a cluster

Credentials are prompted automatically the first time you enter a command at `hsa>`, or you can connect explicitly with `login`:

```
hsa> login

             Copyright (C) 2016-2026 Hammerspace, Inc.
  ---------------------------------------------------------------
      DO NOT ATTEMPT TO LOGIN UNLESS YOU ARE AN AUTHORIZED USER.
  ---------------------------------------------------------------

            Hammerspace CLI - Connection Setup

  Cluster IP or hostname: 10.200.10.160
  Username [admin]:
  Password:

[hsa] Testing connection to admin@10.200.10.160 ...
[hsa] Connected to admin@10.200.10.160
```

Prompts:
- **Cluster IP or hostname** — remembers the last value in brackets
- **Username** — defaults to `admin`
- **Password** — silent input, nothing echoed

A test connection is made automatically after credentials are entered. If it fails, credentials are rolled back to the previous values. On success, credentials are cached for the session and never written to disk.

---

## Using hsa> mode

After loading, you are at the `hsa>` prompt. Type any Hammerspace CLI command directly — no prefix needed:

```
hsa> share-list
hsa> share-list --full
hsa> node-list
hsa> system-view
hsa> share-create --name myshare --path /shares/myshare
hsa> share-snapshot-create --share-name myshare --now
```

### Built-in keywords

These are handled locally and never sent to the cluster:

| Built-in | Action |
|---|---|
| `exit`, `quit` | Leave `hsa>` mode |
| `help`, `?` | Show quick-reference help |
| `status` | Show connection info and test reachability |
| `login` | Re-prompt for cluster credentials |
| `logout` | Clear cached credentials |
| `session` | Open the raw SSH Hammerspace CLI session |

### Line editing

| Key | Action |
|---|---|
| ← / → | Move cursor left / right |
| ↑ / ↓ | Navigate command history |
| Home / End | Jump to start / end of line |
| Backspace | Delete character before cursor |
| Delete | Delete character under cursor |
| Tab | Complete command, option, field name, or filename |
| Ctrl-C | Cancel current line |
| Ctrl-D | Exit `hsa>` mode (on empty line) |

---

## Tab completion

Tab-completion is context-aware at the `hsa>` prompt:

| Input | Result |
|---|---|
| `sh<Tab>` | Completes toward `share-*` commands |
| `share-<Tab>` | Lists all `share-*` commands |
| `<Tab><Tab>` | Lists all available commands |
| `share-list -p<Tab>` | Completes `-print`, `-recursive`, etc. |
| `share-list -print n<Tab>` | Completes known field names like `name` |
| `share-list -recursive sh<Tab>` | Completes child command names |
| `share-list -export-txt <Tab>` | Completes local filenames |

**Mac / Linux:** Tab-completion is registered automatically for both Bash and Zsh when the script is sourced. On Zsh, `compinit` is called automatically if it hasn't run yet.

**Windows:** Registered automatically via `Register-ArgumentCompleter`. Use `Ctrl+Space` in Windows Terminal or PowerShell 7 to show an inline completion menu instead of cycling.

---

## -print — extract field values

Extract a single field's value from record-style command output:

```
hsa> share-list -print name
hsa> node-list -print internal-id
hsa> share-list -print name -export-txt share_names.txt
```

Field matching ignores case, spaces, hyphens, and underscores — so `-print internal-id` matches a line like `Internal ID:  abc123`. Numeric selectors work for simple whitespace-delimited output (e.g. `-print 2` returns the second column).

**Known field names** (tab-completed automatically):

`name`, `internal-id`, `id`, `path`, `lifecycle`, `state`, `size-limit-state`, `export-options`, `smb-browsable`, `is-referral`, `client-specification`, `access-permissions`, `root-squash`, `insecure`, `security-options`

---

## -recursive — run commands per value

Run a second command once for each value extracted by `-print`, replacing `$#` with each value in turn:

```
hsa> share-list -print name -recursive share-snapshot-create --share-name '$#' --now
```

> **Important:** Quote `'$#'` so your shell doesn't expand it before the wrapper sees it.

**More examples:**

```
hsa> node-list -print name -recursive node-mode-change --name '$#' --mode maintenance
hsa> share-list -print name -recursive share-delete --name '$#'
```

`-recursive` requires `-print` so the parent output provides one value per child invocation.

---

## Exporting output

### `-export-txt <file>`

Saves the exact displayed output to a local text file:

```
hsa> share-list -export-txt shares.txt
hsa> share-list -print name -export-txt share_names.txt
```

### `-export-csv <file>`

Converts record-style `Field: value` output to a CSV file. Multi-line field values are joined with a space. Plain (non-record) output is written to a single `Value` column.

```
hsa> share-list -export-csv shares.csv
hsa> node-list -export-csv nodes.csv
```

Both flags can be combined with `-print`:

```
hsa> share-list -print name -export-txt names.txt
```

---

## Session management

| Command | Description |
|---|---|
| `login` | Prompt for cluster IP, username, and password |
| `logout` | Clear cached credentials from this session |
| `status` | Show current cluster IP/username and test reachability |
| `session` | Open the raw SSH Hammerspace CLI session |
| `help` | Print the built-in quick reference |
| `exit` / `quit` | Leave `hsa>` mode |

**Switching clusters:** run `logout`, then `login` at the `hsa>` prompt.

**`session` vs `hsa>` mode:**

- `session` opens a full raw SSH session to the Hammerspace restricted shell — useful for multi-step interactive work and the cluster's own native tab-completion. Type `exit` or Ctrl-D to return to `hsa>`.
- `hsa>` is the local wrapper prompt — it adds `-print`, `-recursive`, export, local tab-completion, and command history on top of the same SSH connection.

---

## Troubleshooting

### Mac / Linux

**`sshpass: command not found`**
Install sshpass for your OS. On macOS, the tap is required:
```bash
brew install hudochenkov/sshpass/sshpass
```

**Connection failed on first login**
Confirm the cluster is reachable: `ping <cluster-ip>`. Check that port 22 is not blocked. If the connection test fails, credentials are automatically rolled back to the previous values.

**Host key changed error**
If the cluster was rebuilt, its SSH host key will have changed:
```bash
ssh-keygen -R <cluster-ip>
```
Then run `login` at the `hsa>` prompt.

**Tab does nothing (Zsh / macOS)**
Confirm the completion function loaded:
```bash
functions _hsa_completions_zsh
```
If missing, re-source the script. If you use a heavily customised Oh My Zsh setup that defers `compinit`, try opening a fresh terminal tab.

**Tab does nothing (Bash)**
The script wasn't sourced in this session. Run `source /path/to/hsacli.sh`. Confirm with: `complete -p hsa`

**Colors not showing / escape codes printing as text**
The script requires Bash 3.2+ or Zsh. Colors are suppressed automatically when stdout is not a TTY — this is expected when redirecting output.

### Windows

**`plink is not recognized`**
plink.exe is not on your PATH. Reinstall PuTTY using the installer, or add `C:\Program Files\PuTTY\` to your PATH via System Properties → Environment Variables → Path.

**`running scripts is disabled on this system`**
Run the execution policy command shown in [Installation → Windows](#windows).

**Connection failed on first login**
Confirm the cluster is reachable: `ping <cluster-ip>`. Check that port 22 is not blocked. Credentials are rolled back automatically if the connection test fails.

**Tab does nothing**
The script wasn't dot-sourced in this session. Run `. C:\path\to\hsacli.ps1`. Confirm with:
```powershell
$PSVersionTable.PSVersion   # must be 5.1 or later
(Get-Command hsa).ScriptBlock
```

**Completion cycles but doesn't show a list**
In the classic `conhost.exe` PowerShell window, Tab cycles one result at a time. Use **Windows Terminal** or **PowerShell 7** for the `Ctrl+Space` completion menu.

**Host key changed error after a cluster rebuild**
Clear the old key from the PuTTY registry, then reconnect:
```
# In Registry Editor, delete the entry for your cluster IP under:
# HKCU\Software\SimonTatham\PuTTY\SshHostKeys
```
Then run `login` at the `hsa>` prompt.

**Commands I expect aren't appearing in completion**
The command list is embedded in the script. If Hammerspace adds new commands in a future release, the `$script:HsaCommands` here-string in `hsacli.ps1` (or `$_HSA_COMMANDS` in `hsacli.sh`) will need to be updated.

---

## Security notes

**Mac / Linux:**
- Credentials are stored in shell variables (`HSA_IP`, `HSA_USER`, `HSA_PASS`) for the session only — never written to disk.
- The password is passed to `sshpass` via the `SSHPASS` environment variable, not on the command line, so it does not appear in `ps` output.
- SSH options: `StrictHostKeyChecking=accept-new`, `ConnectTimeout=10`, `LogLevel=ERROR`, `BatchMode=no`.

**Windows:**
- Credentials are stored in `$script:` scoped variables (`HsaIp`, `HsaUser`, `HsaPass`) for the session only — never written to disk.
- The SecureString password is converted using `SecureStringToBSTR` with `ZeroFreeBSTR` cleanup to minimise the time the plaintext exists in memory.
- Host keys are stored automatically in the Windows registry by plink on first connect.
- If a login attempt fails, credentials are rolled back to the previous working values automatically.

Run `logout` or close the terminal to clear cached credentials.

---

## Version history

### hsacli.sh (Mac / Linux)

| Version | Changes |
|---|---|
| v1.6.0 | Removed `hsa <command>` prefix usage. Sourcing the script now launches `hsa>` mode directly. All Hammerspace commands are entered at the `hsa>` prompt without a prefix. Added Shawn Dutton as co-author |
| v1.5.0 | Added `hsa>` mode with inline readline editing and tab-completion, `-print` field extraction, `-recursive` command chaining, `-export-txt`, `-export-csv` |
| v1.4.0 | Updated login banner with official Hammerspace logo and branding. Added author and version history |
| v1.3.0 | Added Zsh tab-completion via `compdef` / `_describe`. Script auto-detects shell and calls `compinit` automatically if needed |
| v1.2.0 | Added Bash tab-completion via `complete -F` / `COMPREPLY` for all HS subcommands |
| v1.1.0 | Renamed `hs` → `hsa` prefix throughout |
| v1.0.0 | Initial release: `hsa()` wrapper, credential caching, `hsa-session`, `hsa-status`, `hsa-login`, `hsa-logout`, `hsa-help` |

### hsacli.ps1 (Windows)

| Version | Changes |
|---|---|
| v1.1.0 | Removed `hsa <command>` prefix usage. Dot-sourcing the script now launches `hsa>` mode directly. All Hammerspace commands are entered at the `hsa>` prompt without a prefix. Added Shawn Dutton as co-author |
| v1.0.0 | Full-featured initial release. `hsa>` mode with full line editor; `-print`, `-recursive`, `-export-txt`, `-export-csv`; credential rollback on failed login; `SecureString` + `ZeroFreeBSTR` password handling; `PSParser` tokenizer; tab-completion via `Register-ArgumentCompleter`. Uses `plink.exe` (PuTTY) for SSH |

---

## Authors

Jason Ventresco, Shawn Dutton

Copyright (C) 2016–2026 Hammerspace, Inc.
