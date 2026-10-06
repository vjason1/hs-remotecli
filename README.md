# Hammerspace Cluster Remote Admin CLI Console

A CLI wrapper that lets you run Hammerspace admin commands from your local machine over SSH — with full shell integration, tab completion, field extraction, and CSV export. No need to use `serviceadmin` or log into the cluster interactively for every command.

```
[hsa] Hammerspace CLI wrapper loaded.
     Commands: hsa-login  hsa-logout  hsa <cmd>  hsa-session  hsa-status  hsa-help
     Tab-completion enabled: hsa <Tab> to see all commands.
     Credentials will be prompted on first use.
```

---

## Downloads

| Platform | File | Version |
|---|---|---|
| **Mac / Linux** | [`hsacli.sh`](hsacli.sh) | v1.5.0 |
| **Windows (PowerShell)** | [`hsacli.ps1`](hsacli.ps1) | v1.3.0 |

---

## Table of Contents

- [Requirements](#requirements)
- [Installation](#installation)
  - [Mac / Linux](#mac--linux)
  - [Windows](#windows)
- [Loading the wrapper](#loading-the-wrapper)
- [Connecting to a cluster](#connecting-to-a-cluster)
- [Running commands](#running-commands)
- [hsa> mode](#hsa-mode)
- [Tab completion](#tab-completion)
- [-print — extract field values](#-print--extract-field-values)
- [-recursive — run commands per value](#-recursive--run-commands-per-value)
- [Exporting output](#exporting-output)
- [For loops and scripting](#for-loops-and-scripting)
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

# macOS (Homebrew) — the tap is required; brew install sshpass alone will not work
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

Download `hsacli.sh` and source it into your shell. The leading `source` (or `.`) is required — running it directly with `bash` launches `hsa>` mode instead.

```bash
source /path/to/hsacli.sh
```

**Make it permanent** — add the source line to your shell's startup file:

```bash
# macOS (Zsh — default since Catalina): add to ~/.zshrc
echo 'source /path/to/hsacli.sh' >> ~/.zshrc

# Linux Bash: add to ~/.bashrc
echo 'source /path/to/hsacli.sh' >> ~/.bashrc

# Apply immediately without opening a new terminal
source ~/.zshrc   # or ~/.bashrc
```

### Windows

**One-time setup** — allow locally-created scripts to run:

```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

**Dot-source the script** — the leading `.` is required:

```powershell
. C:\path\to\hsacli.ps1
```

**Make it permanent** — add the dot-source line to your PowerShell profile:

```powershell
# Find your profile path
$PROFILE

# Open or create the profile
notepad $PROFILE

# Add this line (adjust path as needed):
. C:\Users\YourName\tools\hsacli.ps1

# Apply immediately
. $PROFILE
```

---

## Loading the wrapper

After sourcing (Mac/Linux) or dot-sourcing (Windows), you'll see:

```
[hsa] Hammerspace CLI wrapper loaded.
     Commands: hsa-login  hsa-logout  hsa <cmd>  hsa-session  hsa-status  hsa-help
     Tab-completion enabled: hsa <Tab> to see all commands.
     Credentials will be prompted on first use.
```

Tab-completion is registered automatically — no extra setup needed.

---

## Connecting to a cluster

Run any `hsa` command and you'll be prompted automatically, or call `hsa-login` explicitly:

```
$ hsa-login

             Copyright (C) 2016-2026 Hammerspace, Inc.
  ---------------------------------------------------------------
      DO NOT ATTEMPT TO LOGIN UNLESS YOU ARE AN AUTHORIZED USER.
  ---------------------------------------------------------------
                        _____________
                       /             \
                       ...

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

After a successful connection, credentials are cached in the session and a test command is run automatically to confirm reachability. Credentials are never written to disk.

---

## Running commands

```bash
hsa <command> [arguments ...]
```

The `hsa` prefix sends the command to the cluster over SSH. Everything without the prefix runs locally.

```bash
hsa share-list
hsa share-list --full
hsa node-list
hsa system-view
hsa share-create --name myshare --path /shares/myshare
hsa share-snapshot-create --share-name myshare --now
```

Output goes to stdout, so all standard shell features work:

```bash
# Pipe to local commands
hsa share-list | grep active

# Capture output in a variable
name=$(hsa share-list --name myshare | grep Name)

# Redirect to a file
hsa share-list --full > /home/serviceadmin/share_report.txt
```

---

## hsa> mode

Run `hsa` with no arguments to enter an interactive prompt where the `hsa` prefix is no longer needed:

```bash
$ hsa

Hammerspace CLI - hsa> mode
Type HS commands directly. Built-ins: help, status, login, logout, session, exit.

hsa> share-list
hsa> node-list
hsa> share-list -print name
hsa> exit
```

All commands typed at `hsa>` are sent to the cluster. The following keywords are handled locally and never forwarded:

| Built-in | Action |
|---|---|
| `help`, `?` | Show quick-reference help |
| `status` | Show connection info and test reachability |
| `login` | Re-prompt for cluster credentials |
| `logout` | Clear cached credentials |
| `session` | Open the raw SSH Hammerspace CLI session |
| `exit`, `quit` | Leave `hsa>` and return to your shell |

Tab-completion, history (↑/↓), and inline editing all work inside `hsa>` mode.

You can also launch `hsa>` mode directly without sourcing:

```bash
# Mac / Linux
bash /path/to/hsacli.sh

# Windows
powershell -File C:\path\to\hsacli.ps1
```

---

## Tab completion

After loading, Tab-completion is active for all Hammerspace subcommands.

### Mac / Linux (Bash and Zsh)

| Input | Result |
|---|---|
| `hsa sh<Tab>` | Completes to `share-*` commands |
| `hsa volume-<Tab>` | Lists only `volume-*` commands |
| `hsa <Tab><Tab>` | Lists all available commands |

### Windows (PowerShell)

| Input | Result |
|---|---|
| `hsa sh<Tab>` | Cycles through `share-*` commands |
| `hsa volume-<Tab>` | Cycles through `volume-*` commands |
| `hsa <Tab><Tab>` | Lists all available commands |
| `Ctrl+Space` | Shows inline completion menu (Windows Terminal / PS7) |

### Inside hsa> mode

Tab-completion in `hsa>` mode is extended to cover wrapper options, `-print` field names, `-recursive` child commands, and local export filenames:

| Input | Result |
|---|---|
| `sh<Tab>` | Completes toward `share-*` commands |
| `share-list -p<Tab>` | Completes `-print`, `-recursive`, etc. |
| `share-list -print n<Tab>` | Completes common field names like `name` |
| `share-list -recursive sh<Tab>` | Completes child command names |
| `share-list -export-txt re<Tab>` | Completes local filenames |

**Verifying completion is active:**

```bash
# Zsh
functions _hsa_completions_zsh   # should print the function body

# Bash
complete -p hsa                  # should print: complete -F _hsa_completions hsa
```

```powershell
# PowerShell
(Get-Command hsa).ScriptBlock    # should print the hsa function body
```

---

## -print — extract field values

Extract a single field's value from record-style command output:

```bash
hsa <command> -print <field>
```

Field matching ignores case, spaces, hyphens, and underscores — so `-print internal-id` matches a line like `Internal ID:  abc123`.

Numeric selectors work for simple whitespace-delimited output (e.g. `-print 2` returns the second column).

**Examples:**

```bash
hsa share-list -print name
hsa node-list  -print internal-id
hsa share-list -print name -export-txt share_names.txt
```

Works inside `hsa>` mode too:

```
hsa> share-list -print name
```

---

## -recursive — run commands per value

Run a second command once for each value extracted by `-print`, replacing `$#` with each value in turn:

```bash
hsa <parent-command> -print <field> -recursive <child-command with '$#'>
```

> **Important:** Quote `'$#'` in your shell so it is not expanded locally before being passed to the wrapper.

**Examples:**

```bash
# Create a snapshot of every share
hsa share-list -print name \
    -recursive share-snapshot-create --share-name '$#' --now

# Take each node offline one by one
hsa node-list -print name \
    -recursive node-mode-change --name '$#' --mode maintenance

# Delete every share matching a pattern (use carefully)
hsa share-list -print name \
    -recursive share-delete --name '$#'
```

`-recursive` requires `-print` so the parent output provides one value per child invocation.

---

## Exporting output

### `-export-txt <file>`

Saves the exact displayed output to a local text file:

```bash
hsa share-list -export-txt shares.txt
hsa share-list -print name -export-txt share_names.txt
```

### `-export-csv <file>`

Converts record-style `Field: value` output to a local CSV file:

```bash
hsa share-list -export-csv shares.csv
hsa node-list  -export-csv nodes.csv
```

Both flags work inside `hsa>` mode and can be combined with `-print`:

```
hsa> share-list -export-csv shares.csv
hsa> share-list -print name -export-txt names.txt
```

---

## For loops and scripting

### Mac / Linux (Bash)

```bash
# Snapshot every share whose name starts with "prod-"
for share in $(hsa share-list | awk '/^prod-/{print $1}'); do
    echo "Snapshotting: $share"                    # runs locally
    hsa share-snapshot-create \                    # runs on cluster
        --share-name "$share" \
        --now \
        --snapshot-name "manual-$(date +%Y%m%d)"
done

# Iterate over a local file, query each node
while IFS= read -r node; do
    echo "--- $node ---"
    hsa node-list --name "$node"
done < /home/serviceadmin/node_list.txt

# Save a full share report
hsa share-list --full > /home/serviceadmin/share_report.txt
echo "Report saved."
```

### Windows (PowerShell)

```powershell
# Snapshot every share whose name starts with "prod-"
foreach ($share in (hsa share-list -print name | Where-Object { $_ -like 'prod-*' })) {
    Write-Host "Snapshotting: $share"
    hsa share-snapshot-create --share-name $share --now `
        --snapshot-name "manual-$(Get-Date -Format yyyyMMdd)"
}

# Iterate over a local file, query each node
foreach ($node in (Get-Content C:\admin\node_list.txt)) {
    Write-Host "--- $node ---"
    hsa node-list --name $node
}

# Save a full share report
hsa share-list --full | Out-File C:\reports\share_report.txt
```

---

## Session management

| Command | Description |
|---|---|
| `hsa-login` | Prompt for cluster IP, username, and password |
| `hsa-logout` | Clear cached credentials from this session |
| `hsa-status` | Show current cluster IP/username and test reachability |
| `hsa-session` | Open the raw SSH Hammerspace CLI session |
| `hsa-help` | Print the built-in quick reference |

**Switching clusters:** run `hsa-logout`, then any `hsa` command to re-prompt, or run `hsa-login` directly.

**`hsa-session` vs `hsa>` mode:**

- `hsa-session` opens a full raw SSH session to the Hammerspace restricted shell — useful for multi-step interactive work and the cluster's own native tab-completion. Type `exit` or Ctrl-D to return.
- `hsa>` mode is the local wrapper prompt — it adds `-print`, `-recursive`, export, and local tab-completion on top of the same SSH connection.

---

## Troubleshooting

### Mac / Linux

**`sshpass: command not found`**
Install sshpass for your OS. On macOS, use the Homebrew tap — `brew install sshpass` alone will not work:
```bash
brew install hudochenkov/sshpass/sshpass
```

**`Connection failed` on first login**
Confirm the cluster is reachable: `ping <cluster-ip>`. Check that port 22 is not blocked. Verify the username and password.

**Host key changed error**
If the cluster was rebuilt, its SSH host key will have changed. Remove the old entry and re-login:
```bash
ssh-keygen -R <cluster-ip>
hsa-login
```

**Tab does nothing after `hsa` (Zsh / macOS)**
Confirm the completion function loaded:
```bash
functions _hsa_completions_zsh
```
If missing, re-source the script: `source /path/to/hsacli.sh`. If you use a heavily customised Oh My Zsh setup that defers `compinit`, try opening a fresh terminal tab after adding the source line to `~/.zshrc`.

**Tab does nothing after `hsa` (Bash)**
The script wasn't sourced in this session. Run `source /path/to/hsacli.sh`. Confirm with: `complete -p hsa`

**Colors not showing / escape codes printing as text**
The script requires Bash 3.2+ or Zsh. Colors are suppressed automatically when stdout is not a TTY (e.g. when redirecting to a file) — this is expected.

### Windows

**`plink is not recognized`**
plink.exe is not on your PATH. Reinstall PuTTY using the installer (which sets the PATH automatically), or add `C:\Program Files\PuTTY\` to your PATH manually via System Properties → Environment Variables → Path.

**`running scripts is disabled on this system`**
Run the execution policy command shown in [Installation → Windows](#windows).

**`Connection failed` on first login**
Confirm the cluster is reachable: `ping <cluster-ip>`. Check that port 22 is not blocked. Verify the username and password.

**Tab does nothing after `hsa`**
The script wasn't dot-sourced in this session. Run `. C:\path\to\hsacli.ps1`. Confirm with:
```powershell
$PSVersionTable.PSVersion   # must be 5.1 or later
(Get-Command hsa).ScriptBlock
```

**Completion cycles but doesn't show a list**
In the classic `conhost.exe` PowerShell window, Tab cycles one result at a time. Use **Windows Terminal** or **PowerShell 7** for the `Ctrl+Space` inline completion menu.

**Host key changed error after a cluster rebuild**
Clear the old key from the PuTTY registry, then re-login:
```powershell
hsa-logout
# In Registry Editor, delete the entry for your cluster IP under:
# HKCU\Software\SimonTatham\PuTTY\SshHostKeys
hsa-login
```

**Commands I expect aren't appearing in completion**
The command list is embedded in the script. If Hammerspace adds new commands in a future release, the `$script:_HSA_COMMANDS` array in `hsacli.ps1` (or `$_HSA_COMMANDS` in `hsacli.sh`) will need to be updated.

---

## Security notes

- Credentials are stored in shell/session variables only — `HSA_IP`, `HSA_USER`, `HSA_PASS` (Mac/Linux) or `$script:HSA_*` (Windows). Never written to disk.
- On Mac/Linux, the password is passed to `sshpass` via the `SSHPASS` environment variable rather than on the command line, so it does not appear in `ps` output.
- On Windows, the password is passed to `plink` via the `-pw` flag. Host keys are stored automatically in the Windows registry on first connect.
- SSH options used (Mac/Linux): `StrictHostKeyChecking=accept-new`, `ConnectTimeout=10`, `LogLevel=ERROR`, `BatchMode=no`.
- Run `hsa-logout` or close the terminal to clear cached credentials.

---

## Version history

### hsacli.sh (Mac / Linux)

| Version | Changes |
|---|---|
| v1.5.0 | Added `hsa>` mode with inline readline editing and tab-completion, `-print` field extraction, `-recursive` command chaining, `-export-txt`, `-export-csv` |
| v1.4.0 | Updated login banner with official Hammerspace logo and branding. Added version history |
| v1.3.0 | Added Zsh tab-completion via `compdef` / `_describe`. Script auto-detects shell and calls `compinit` automatically if needed |
| v1.2.0 | Added Bash tab-completion via `complete -F` / `COMPREPLY` for all HS subcommands |
| v1.1.0 | Renamed `hs` → `hsa` prefix throughout |
| v1.0.0 | Initial release: `hsa()` wrapper, credential caching, `hsa-session`, `hsa-status`, `hsa-login`, `hsa-logout`, `hsa-help` |

### hsacli.ps1 (Windows)

| Version | Changes |
|---|---|
| v1.3.0 | Full feature parity with `hsacli.sh` v1.5.0. Verified 207-command list, `-print` field names, and all wrapper flags are identical across both scripts. Improved inline documentation throughout |
| v1.2.0 | Added `hsa>` mode (`Invoke-HsaMode`), `-print` / `-recursive` command chaining, `-export-txt` / `-export-csv`, enhanced tab-completion for wrapper options and field names |
| v1.1.0 | Added tab-completion via `Register-ArgumentCompleter` for all HS subcommands |
| v1.0.0 | Initial release: `hsa`, `hsa-login`, `hsa-logout`, `hsa-status`, `hsa-session`, `hsa-help`. Uses `plink.exe` for SSH |

---

## Author

Jason Ventresco

Copyright (C) 2016–2026 Hammerspace, Inc.
