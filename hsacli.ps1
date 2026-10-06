# ==============================================================================
#
#              Copyright (C) 2016-2026 Hammerspace, Inc.
#  -----------------------------------------------------------------
#      DO NOT ATTEMPT TO LOGIN UNLESS YOU ARE AN AUTHORIZED USER.
#  -----------------------------------------------------------------
#                            _____________
#                           /             \
#                           \     _____    \
#                            \    \    \    \
#                             \    \    \    \
#                       ___    \____\    \    \
#                      /   \              \    \
#                      \    \     _____    \___/
#                       \    \    \    \
#                        \    \    \    \
#                         \    \____\    \
#                          \              \
#                           \_____________/
#
#                  Hammerspace CLI - Connection Setup
#
# ==============================================================================
#  hsacli.ps1 - Hammerspace CLI Remote Wrapper for Windows PowerShell
#  Author : Jason Ventresco
#
#  VERSION HISTORY:
#    v1.0.0  Initial release. Core hsa() wrapper, credential caching via
#            script-scope variables, hsa-session, hsa-status, hsa-login,
#            hsa-logout, hsa-help. Uses plink.exe (PuTTY) for SSH.
#
#    v1.1.0  Added tab-completion via Register-ArgumentCompleter covering
#            all Hammerspace CLI subcommands.
#
#    v1.2.0  Added hsa> mode (Invoke-HsaMode), -print / -recursive command
#            chaining, -export-txt / -export-csv, and enhanced tab-completion
#            for wrapper options and -print field names.
#
#    v1.3.0  Full parity with hsacli.sh v1.5.0. Verified command list (207
#            commands), -print field names, and all wrapper flags are
#            identical across both scripts. Improved inline documentation
#            throughout to match the bash script's structure and comments.
#
# ==============================================================================
#
#  USAGE - two ways to load this tool:
#
#    1) Dot-source into your current session (recommended):
#         . C:\path\to\hsacli.ps1
#       Adds hsa, hsa-login, hsa-logout, hsa-status, hsa-session, hsa-help
#       as functions in your session. Credentials are cached in script-scope
#       variables for the duration of the session.
#
#    2) Run directly to enter hsa> mode:
#         powershell -File C:\path\to\hsacli.ps1
#       Drops you into the hsa> prompt where HS commands run without a prefix.
#       Type 'exit' or 'quit' to leave.
#
#  DEPENDENCIES:
#    plink.exe  - Part of PuTTY. Download from:
#                 https://www.chiark.greenend.org.uk/~sgtatham/putty/latest.html
#                 The installer adds plink.exe to PATH automatically.
#
#  SECURITY NOTE:
#    Credentials are stored in script-scope variables ($script:HSA_IP,
#    $script:HSA_USER, $script:HSA_PASS) for the duration of the session only.
#    They are never written to disk. The password is passed to plink via the
#    -pw flag; to avoid it appearing in Get-Process output the variable is
#    cleared from memory on hsa-logout.
#
# ==============================================================================

Set-StrictMode -Version Latest

# ==============================================================================
#  COLOUR HELPERS
# ==============================================================================

function _HSA-Info  { param([string]$msg) Write-Host "[hsa] $msg" -ForegroundColor Cyan }
function _HSA-Ok    { param([string]$msg) Write-Host "[hsa] $msg" -ForegroundColor Green }
function _HSA-Warn  { param([string]$msg) Write-Host "[hsa] $msg" -ForegroundColor Yellow }
function _HSA-Err   { param([string]$msg) Write-Host "[hsa] $msg" -ForegroundColor Red }


# ==============================================================================
#  CREDENTIAL SETUP
# ==============================================================================

function _HSA-SetupCredentials {
    Write-Host ""
    Write-Host "             Copyright (C) 2016-2026 Hammerspace, Inc." -ForegroundColor Cyan
    Write-Host "  ---------------------------------------------------------------" -ForegroundColor DarkGray
    Write-Host "      DO NOT ATTEMPT TO LOGIN UNLESS YOU ARE AN AUTHORIZED USER." -ForegroundColor Yellow
    Write-Host "  ---------------------------------------------------------------" -ForegroundColor DarkGray
    Write-Host "                        _____________" -ForegroundColor Cyan
    Write-Host "                       /             \" -ForegroundColor Cyan
    Write-Host "                       \     _____    \" -ForegroundColor Cyan
    Write-Host "                        \    \    \    \" -ForegroundColor Cyan
    Write-Host "                         \    \    \    \" -ForegroundColor Cyan
    Write-Host "                   ___    \____\    \    \" -ForegroundColor Cyan
    Write-Host "                  /   \              \    \" -ForegroundColor Cyan
    Write-Host "                  \    \     _____    \___/" -ForegroundColor Cyan
    Write-Host "                   \    \    \    \" -ForegroundColor Cyan
    Write-Host "                    \    \    \    \" -ForegroundColor Cyan
    Write-Host "                     \    \____\    \" -ForegroundColor Cyan
    Write-Host "                      \              \" -ForegroundColor Cyan
    Write-Host "                       \_____________/" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "            Hammerspace CLI - Connection Setup" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Credentials are cached in this session only." -ForegroundColor DarkGray
    Write-Host "  Run 'hsa-logout' to clear them. Run 'hsa-status' to review." -ForegroundColor DarkGray
    Write-Host ""

    # Cluster IP
    $defaultIP = if ($script:HSA_IP) { $script:HSA_IP } else { "" }
    $promptIP  = if ($defaultIP) { "  Cluster IP or hostname [$defaultIP]: " } else { "  Cluster IP or hostname: " }
    $inputIP   = Read-Host $promptIP
    if (-not $inputIP -and $defaultIP) { $inputIP = $defaultIP }
    if (-not $inputIP) {
        _HSA-Err "Cluster IP is required."
        return $false
    }

    # Username
    $defaultUser = if ($script:HSA_USER) { $script:HSA_USER } else { "admin" }
    $inputUser   = Read-Host "  Username [$defaultUser]"
    if (-not $inputUser) { $inputUser = $defaultUser }

    # Password (masked)
    $securePass = Read-Host "  Password" -AsSecureString
    $inputPass  = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
                    [Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePass))
    if (-not $inputPass) {
        _HSA-Err "Password is required."
        return $false
    }

    Write-Host ""
    _HSA-Info "Testing connection to ${inputUser}@${inputIP} ..."

    # Dependency check
    if (-not (Get-Command plink -ErrorAction SilentlyContinue)) {
        _HSA-Err "'plink.exe' is not found. Install PuTTY from https://www.putty.org"
        return $false
    }

    # Test connection — run system-view as a lightweight probe
    $plinkArgs = @("-ssh", "-batch", "-pw", $inputPass, "${inputUser}@${inputIP}", "system-view")
    try {
        $testOutput = & plink @plinkArgs 2>&1
        $rc = $LASTEXITCODE
    } catch {
        _HSA-Err "Failed to run plink: $_"
        return $false
    }

    if ($rc -ne 0) {
        _HSA-Err "Connection failed (exit code $rc)."
        _HSA-Err "Check IP, username, password, and that the cluster is reachable."
        if ($testOutput) { _HSA-Err "plink output: $testOutput" }
        return $false
    }

    # Cache credentials in script scope
    $script:HSA_IP   = $inputIP
    $script:HSA_USER = $inputUser
    $script:HSA_PASS = $inputPass

    _HSA-Ok "Connected to ${inputUser}@${inputIP}"
    Write-Host ""
    return $true
}

function _HSA-RequireCredentials {
    if (-not $script:HSA_IP -or -not $script:HSA_PASS) {
        return (_HSA-SetupCredentials)
    }
    return $true
}


# ==============================================================================
#  SSH COMMAND EXECUTION
# ==============================================================================

function _HSA-SshCommand {
    param([string[]]$CmdArgs)
    # Join args into a single command string for the remote shell
    $remoteCmd = $CmdArgs -join " "
    $plinkArgs = @("-ssh", "-batch", "-pw", $script:HSA_PASS,
                   "${script:HSA_USER}@${script:HSA_IP}", $remoteCmd)
    & plink @plinkArgs
    return $LASTEXITCODE
}

function _HSA-SshCommandCapture {
    param([string[]]$CmdArgs)
    $remoteCmd = $CmdArgs -join " "
    $plinkArgs = @("-ssh", "-batch", "-pw", $script:HSA_PASS,
                   "${script:HSA_USER}@${script:HSA_IP}", $remoteCmd)
    $output = & plink @plinkArgs 2>&1
    return $output, $LASTEXITCODE
}


# ==============================================================================
#  -print HELPERS
# ==============================================================================

function _HSA-PrintColumn {
    param([string[]]$Lines, [int]$Col)
    foreach ($line in $Lines) {
        $parts = $line -split '\s+' | Where-Object { $_ -ne '' }
        if ($parts.Count -ge $Col) {
            Write-Output $parts[$Col - 1]
        }
    }
}

function _HSA-NormalizeKey {
    param([string]$s)
    return ($s.ToLower() -replace '[^a-z0-9]', '')
}

function _HSA-PrintField {
    param([string[]]$Lines, [string]$Selector)
    $wanted = _HSA-NormalizeKey $Selector
    foreach ($line in $Lines) {
        if ($line -match '^([^:]+):(.*)$') {
            $key   = _HSA-NormalizeKey $Matches[1]
            $value = $Matches[2].Trim()
            if ($key -eq $wanted) {
                Write-Output $value
            }
        }
    }
}

function _HSA-PrintValues {
    param([string[]]$Lines, [string]$Selector)
    if ($Selector -match '^\d+$') {
        _HSA-PrintColumn -Lines $Lines -Col ([int]$Selector)
    } else {
        _HSA-PrintField -Lines $Lines -Selector $Selector
    }
}


# ==============================================================================
#  CSV EXPORT
# ==============================================================================

function _HSA-OutputToCsv {
    param([string[]]$Lines)

    $headers     = [System.Collections.Generic.List[string]]::new()
    $headerSeen  = @{}
    $labels      = @{}
    $rows        = [System.Collections.Generic.List[hashtable]]::new()
    $current     = @{}
    $lastKey     = ""
    $hasFields   = $false
    $plainLines  = [System.Collections.Generic.List[string]]::new()

    function Flush-Record {
        if ($hasFields) {
            $rows.Add($current.Clone())
        }
    }

    function Remember-Header([string]$key, [string]$label) {
        if (-not $headerSeen.ContainsKey($key)) {
            $headerSeen[$key] = $true
            $headers.Add($key)
            $labels[$key] = $label
        }
    }

    function Csv-Escape([string]$s) {
        if ($s -match '[",\r\n]') {
            return '"' + $s.Replace('"', '""') + '"'
        }
        return $s
    }

    foreach ($line in $Lines) {
        if ($line -match '^\s*$') {
            Flush-Record
            $current  = @{}
            $lastKey  = ""
            $hasFields = $false
            continue
        }
        if ($line -match '^([^:\s][^:]*):(.*)$') {
            $label   = $Matches[1].Trim()
            $value   = $Matches[2].Trim()
            $key     = _HSA-NormalizeKey $label
            Remember-Header $key $label
            $current[$key] = $value
            $hasFields = $true
            $lastKey   = $key
            continue
        }
        if ($line -match '^\s+' -and $lastKey) {
            $cont = $line.Trim()
            if ($cont) {
                if ($current[$lastKey]) {
                    $current[$lastKey] += " $cont"
                } else {
                    $current[$lastKey] = $cont
                }
            }
            continue
        }
        $trimmed = $line.Trim()
        if ($trimmed -and -not $hasFields) {
            $plainLines.Add($trimmed)
        }
    }
    Flush-Record

    $sb = [System.Text.StringBuilder]::new()
    if ($rows.Count -gt 0) {
        $sb.AppendLine(($headers | ForEach-Object { Csv-Escape $labels[$_] }) -join ",") | Out-Null
        foreach ($row in $rows) {
            $sb.AppendLine(($headers | ForEach-Object { Csv-Escape ($row[$_] ?? "") }) -join ",") | Out-Null
        }
    } else {
        $sb.AppendLine("Value") | Out-Null
        foreach ($p in $plainLines) { $sb.AppendLine((Csv-Escape $p)) | Out-Null }
    }
    return $sb.ToString()
}


# ==============================================================================
#  EXPORT OUTPUT
# ==============================================================================

function _HSA-ExportOutput {
    param([string]$ExportType, [string]$ExportFile, [string[]]$OutputLines)

    if (-not $ExportFile) {
        _HSA-Err "-export-$ExportType requires a local filename."
        return $false
    }

    try {
        switch ($ExportType) {
            "txt" {
                $OutputLines | Set-Content -Path $ExportFile -Encoding UTF8
            }
            "csv" {
                $csv = _HSA-OutputToCsv -Lines $OutputLines
                $csv | Set-Content -Path $ExportFile -Encoding UTF8
            }
            default {
                _HSA-Err "Unknown export type: $ExportType"
                return $false
            }
        }
        _HSA-Ok "Exported output to $ExportFile"
        return $true
    } catch {
        _HSA-Err "Failed to write $ExportFile`: $_"
        return $false
    }
}


# ==============================================================================
#  -recursive HELPER
# ==============================================================================

function _HSA-RunRecursive {
    param(
        [string]   $PrintSelector,
        [string[]] $BaseArgs,
        [string[]] $RecursiveArgs
    )

    if (-not $PrintSelector) {
        _HSA-Err "-recursive requires -print <field> so the parent output has one value per child command."
        return 1
    }
    if (-not $BaseArgs) {
        _HSA-Err "-recursive requires a parent command before -recursive."
        return 1
    }
    if (-not $RecursiveArgs) {
        _HSA-Err "-recursive requires a child command."
        return 1
    }

    $parentLines, $parentRc = _HSA-SshCommandCapture -CmdArgs $BaseArgs
    if ($parentRc -ne 0) { return $parentRc }

    $values = _HSA-PrintValues -Lines $parentLines -Selector $PrintSelector
    $rc = 0

    foreach ($value in $values) {
        if (-not $value) { continue }
        $childArgs = $RecursiveArgs | ForEach-Object { $_ -replace '\$#', $value }
        _HSA-RunCommand -Args $childArgs
        if ($LASTEXITCODE -ne 0) { $rc = $LASTEXITCODE }
    }
    return $rc
}


# ==============================================================================
#  CORE COMMAND DISPATCHER
# ==============================================================================

function _HSA-RunCommand {
    param([string[]]$Args)

    if (-not $Args) {
        _HSA-Err "No HSA command supplied."
        return 1
    }

    $printSelector = ""
    $exportType    = ""
    $exportFile    = ""
    $recursiveMode = $false
    $baseArgs      = [System.Collections.Generic.List[string]]::new()
    $recursiveArgs = [System.Collections.Generic.List[string]]::new()

    $i = 0
    while ($i -lt $Args.Count) {
        $arg = $Args[$i]
        switch -Regex ($arg) {
            '^-print$' {
                $i++
                if ($i -ge $Args.Count) { _HSA-Err "-print requires a field name."; return 1 }
                $printSelector = $Args[$i]
            }
            '^-print=(.+)$' {
                $printSelector = $Matches[1]
            }
            '^(-export-txt|export-txt)$' {
                $i++
                if ($i -ge $Args.Count) { _HSA-Err "$arg requires a local filename."; return 1 }
                $exportType = "txt"; $exportFile = $Args[$i]
            }
            '^-export-txt=(.+)$' {
                $exportType = "txt"; $exportFile = $Matches[1]
            }
            '^(-export-csv|export-csv)$' {
                $i++
                if ($i -ge $Args.Count) { _HSA-Err "$arg requires a local filename."; return 1 }
                $exportType = "csv"; $exportFile = $Args[$i]
            }
            '^-export-csv=(.+)$' {
                $exportType = "csv"; $exportFile = $Matches[1]
            }
            '^-recursive$' {
                $recursiveMode = $true
                $i++
                while ($i -lt $Args.Count) { $recursiveArgs.Add($Args[$i]); $i++ }
                continue
            }
            '^-recursive=(.+)$' {
                $recursiveMode = $true
                $recursiveArgs.Add($Matches[1])
                $i++
                while ($i -lt $Args.Count) { $recursiveArgs.Add($Args[$i]); $i++ }
                continue
            }
            default {
                $baseArgs.Add($arg)
            }
        }
        $i++
    }

    if ($recursiveMode) {
        $result = _HSA-RunRecursive -PrintSelector $printSelector `
                                     -BaseArgs $baseArgs.ToArray() `
                                     -RecursiveArgs $recursiveArgs.ToArray()
        return $result
    }

    if ($baseArgs.Count -eq 0) {
        _HSA-Err "No HSA command supplied."
        return 1
    }

    if ($printSelector) {
        $outputLines, $rc = _HSA-SshCommandCapture -CmdArgs $baseArgs.ToArray()
        if ($rc -ne 0) { return $rc }
        $printed = _HSA-PrintValues -Lines $outputLines -Selector $printSelector
        $printed | Write-Output
        if ($exportType) {
            _HSA-ExportOutput -ExportType $exportType -ExportFile $exportFile -OutputLines $printed | Out-Null
        }
        return 0
    }

    if ($exportType) {
        $outputLines, $rc = _HSA-SshCommandCapture -CmdArgs $baseArgs.ToArray()
        $outputLines | Write-Output
        if ($rc -ne 0) { return $rc }
        _HSA-ExportOutput -ExportType $exportType -ExportFile $exportFile -OutputLines $outputLines | Out-Null
        return 0
    }

    _HSA-SshCommand -CmdArgs $baseArgs.ToArray()
    return $LASTEXITCODE
}


# ==============================================================================
#  PUBLIC FUNCTIONS
# ==============================================================================

function hsa {
    <#
    .SYNOPSIS
        Run a Hammerspace CLI command on the cluster, or enter hsa> mode.
    .DESCRIPTION
        Dot-source hsacli.ps1 to load this function. Credentials are prompted
        on first use and cached for the session.
    .EXAMPLE
        hsa share-list
        hsa share-list -print name
        hsa share-list -export-csv shares.csv
        hsa share-list -print name -recursive share-snapshot-create --share-name '$#' --now
        hsa         # enters hsa> interactive mode
    #>
    param([Parameter(ValueFromRemainingArguments)][string[]]$Command)

    if (-not (_HSA-RequireCredentials)) { return }

    if (-not $Command) {
        Invoke-HsaMode
        return
    }

    _HSA-RunCommand -Args $Command
}


function hsa-login {
    <#
    .SYNOPSIS
        Prompt for cluster credentials and cache them for this session.
    #>
    if ($script:HSA_IP) {
        _HSA-Warn "Currently connected to $($script:HSA_USER)@$($script:HSA_IP)."
        _HSA-Warn "Entering new credentials will replace the existing connection."
        Write-Host ""
    }
    _HSA-SetupCredentials | Out-Null
}


function hsa-logout {
    <#
    .SYNOPSIS
        Clear cached credentials from this session.
    #>
    if (-not $script:HSA_IP) {
        _HSA-Info "No credentials cached - nothing to clear."
        return
    }
    $oldIP = $script:HSA_IP
    $script:HSA_IP   = ""
    $script:HSA_USER = ""
    $script:HSA_PASS = ""
    _HSA-Ok "Credentials cleared (was connected to $oldIP)."
}


function hsa-status {
    <#
    .SYNOPSIS
        Show current connection info and test reachability.
    #>
    Write-Host ""
    Write-Host "Hammerspace CLI - Connection Status" -ForegroundColor White
    Write-Host ("─" * 36) -ForegroundColor DarkGray

    if (-not $script:HSA_IP) {
        Write-Host "  Not connected. Run 'hsa-login' to connect." -ForegroundColor Yellow
        Write-Host ("─" * 36) -ForegroundColor DarkGray
        Write-Host ""
        return
    }

    Write-Host "  Cluster  : $($script:HSA_IP)" -ForegroundColor White
    Write-Host "  Username : $($script:HSA_USER)"
    Write-Host "  Password : (cached in session - not shown)" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  Testing connectivity..." -ForegroundColor DarkGray

    $probe, $rc = _HSA-SshCommandCapture -CmdArgs @("system-view")
    if ($rc -eq 0) {
        Write-Host "  Reachable" -ForegroundColor Green
        if ($probe) {
            Write-Host ""
            Write-Host "  system-view (first 5 lines):" -ForegroundColor DarkGray
            $probe | Select-Object -First 5 | ForEach-Object { Write-Host "    $_" }
        }
    } else {
        Write-Host "  Unreachable - check network or run 'hsa-logout' and reconnect." -ForegroundColor Red
    }

    Write-Host ("─" * 36) -ForegroundColor DarkGray
    Write-Host ""
}


function hsa-session {
    <#
    .SYNOPSIS
        Open a raw interactive SSH session to the Hammerspace cluster.
    #>
    if (-not (_HSA-RequireCredentials)) { return }
    _HSA-Info "Opening interactive session to $($script:HSA_USER)@$($script:HSA_IP) ..."
    _HSA-Info "Type 'exit' or Ctrl-D to return to PowerShell."
    Write-Host ""
    & plink -ssh -pw $script:HSA_PASS "$($script:HSA_USER)@$($script:HSA_IP)"
    Write-Host ""
    _HSA-Info "Returned to PowerShell. HS credentials still cached (run 'hsa-logout' to clear)."
}


function hsa-help {
    <#
    .SYNOPSIS
        Print usage summary.
    #>
    Write-Host @"

  Hammerspace CLI Wrapper - Quick Reference
  -----------------------------------------

  COMMANDS:
    hsa <command> [args]    Run any HS CLI command on the cluster
    hsa                     Enter hsa> mode; HS commands no longer need prefix
    hsa-session             Open the raw SSH Hammerspace CLI session
    hsa-status              Show connection info and test reachability
    hsa-logout              Clear cached credentials
    hsa-help                Show this help

  HSA> MODE:
    Run 'hsa' by itself to enter hsa> mode.
    In that mode, type Hammerspace commands directly:
      hsa> share-list
      hsa> share-list -print name

  TAB COMPLETION:
    After dot-sourcing, tab-completion is active for all HS commands:
      hsa sh<Tab>           -> cycles through share-* commands
      hsa <Tab><Tab>        -> lists all available commands
    In hsa> mode, use Tab to complete commands and wrapper options.

  PRINT AND RECURSIVE:
    -print <field>  extracts values from record-style output like "Name: root".
    Field matching ignores case, spaces, hyphens, and underscores, so
    "-print internal-id" matches "Internal ID:".
    Numeric selectors work for whitespace-delimited output (e.g. -print 2).

    -recursive runs another command once per printed value. Use '$#' in the
    child command where the parent value should be substituted.

      hsa share-list -print name
      hsa share-list -print name -recursive share-snapshot-create --share-name '$#' --now

  EXPORT:
    -export-txt <file>   saves raw output to a local text file.
    -export-csv <file>   converts "Field: value" output to a local CSV file.

      hsa share-list -export-txt shares.txt
      hsa share-list -export-csv shares.csv
      hsa share-list -print name -export-txt share_names.txt

  EXAMPLES:
    hsa share-list
    hsa share-list --full
    hsa node-list
    hsa share-list -print name
    hsa share-list -export-csv shares.csv
    hsa system-view
    hsa share-create --name myshare --path /shares/myshare

  FOR LOOPS (PowerShell):
    foreach (`$share in (hsa share-list -print name)) {
        Write-Host "Snapshotting: `$share"
        hsa share-snapshot-create --share-name `$share --now ``
            --snapshot-name "manual-`$(Get-Date -Format yyyyMMdd)"
    }

  NOTES:
    - Credentials cached in `$script:HSA_IP / HSA_USER / HSA_PASS for session only.
    - plink.exe must be installed (PuTTY): https://www.putty.org
    - To switch clusters: hsa-logout, then run any 'hsa' command to re-prompt.
    - Host keys are stored automatically by plink in the Windows registry.

"@
}


# ==============================================================================
#  hsa> INTERACTIVE MODE
# ==============================================================================

function Invoke-HsaMode {
    Write-Host ""
    Write-Host "Hammerspace CLI - hsa> mode" -ForegroundColor Cyan
    Write-Host "Type HS commands directly. Built-ins: help, status, login, logout, session, exit." -ForegroundColor DarkGray
    Write-Host ""

    if (-not (_HSA-RequireCredentials)) { return }

    $history = [System.Collections.Generic.List[string]]::new()

    while ($true) {
        $userInput = Read-Host "hsa>"
        $userInput = $userInput.Trim()

        if (-not $userInput) { continue }

        # History: add if different from last entry
        if ($history.Count -eq 0 -or $history[$history.Count - 1] -ne $userInput) {
            $history.Add($userInput)
        }

        switch -Regex ($userInput) {
            '^(exit|quit)$' {
                _HSA-Info "Leaving hsa> mode."
                return
            }
            '^(help|\?|hsa-help)$' {
                hsa-help
                continue
            }
            '^(status|hsa-status)$' {
                hsa-status
                continue
            }
            '^(login|hsa-login)$' {
                hsa-login
                continue
            }
            '^(logout|hsa-logout)$' {
                hsa-logout
                continue
            }
            '^(session|hsa-session)$' {
                hsa-session
                continue
            }
            '^hsa\s+(.+)$' {
                # Strip leading 'hsa ' prefix if user typed it inside hsa> mode
                $userInput = $Matches[1]
            }
            '^hsa$' {
                hsa-session
                continue
            }
        }

        # Parse the line into tokens (respecting quoted strings)
        $tokens = _HSA-TokenizeLine $userInput
        if ($tokens.Count -gt 0) {
            _HSA-RunCommand -Args $tokens
            $rc = $LASTEXITCODE
            if ($rc -ne 0) { _HSA-Warn "Command exited with status $rc" }
        }
    }
}


# ==============================================================================
#  LINE TOKENIZER (handles quoted strings for hsa> mode)
# ==============================================================================

function _HSA-TokenizeLine {
    param([string]$Line)
    $tokens  = [System.Collections.Generic.List[string]]::new()
    $current = [System.Text.StringBuilder]::new()
    $inSingle = $false
    $inDouble = $false

    for ($i = 0; $i -lt $Line.Length; $i++) {
        $c = $Line[$i]
        if ($inSingle) {
            if ($c -eq "'") { $inSingle = $false }
            else { $current.Append($c) | Out-Null }
        } elseif ($inDouble) {
            if ($c -eq '"') { $inDouble = $false }
            else { $current.Append($c) | Out-Null }
        } elseif ($c -eq "'") {
            $inSingle = $true
        } elseif ($c -eq '"') {
            $inDouble = $true
        } elseif ($c -eq ' ' -or $c -eq "`t") {
            if ($current.Length -gt 0) {
                $tokens.Add($current.ToString())
                $current.Clear() | Out-Null
            }
        } else {
            $current.Append($c) | Out-Null
        }
    }
    if ($current.Length -gt 0) { $tokens.Add($current.ToString()) }
    return $tokens.ToArray()
}


# ==============================================================================
#  TAB COMPLETION
# ==============================================================================

$script:_HSA_COMMANDS = @(
    "ad-config", "ad-discover",
    "antivirus-add", "antivirus-list", "antivirus-remove", "antivirus-update",
    "builtin-group-user-add", "builtin-group-user-list", "builtin-group-user-remove",
    "cluster-config",
    "dns-config",
    "domain-idmap-add", "domain-idmap-delete", "domain-idmap-list", "domain-idmap-reload",
    "dp-update",
    "drive-list",
    "email-config",
    "event-list", "event-update",
    "file-snapshot-create", "file-snapshot-delete", "file-snapshot-list",
    "file-snapshot-restore", "file-snapshot-schedule-list", "file-snapshot-update",
    "floating-ip-add", "floating-ip-remove",
    "gateway-list", "gateway-update",
    "gfs-participant-add", "gfs-participant-disable", "gfs-participant-enable",
    "gfs-participant-list", "gfs-participant-remove",
    "heartbeat-list", "heartbeat-send", "heartbeat-update",
    "identity-group-mapping-create", "identity-group-mapping-delete",
    "identity-group-mapping-list", "identity-group-mapping-update",
    "idp-add", "idp-list", "idp-remove", "idp-update",
    "interface-create", "interface-delete", "interface-list", "interface-update",
    "kms-add", "kms-list", "kms-remove", "kms-update",
    "label-create", "label-delete", "label-list", "label-update",
    "license-add", "license-list", "license-offline-add", "license-offline-cancel",
    "license-offline-remove", "license-offline-update", "license-remove", "license-update",
    "local-site-config",
    "logical-volume-create", "logical-volume-delete", "logical-volume-discover",
    "logical-volume-list",
    "login-policy-config",
    "metric-list",
    "nis-config",
    "node-add", "node-list", "node-mode-change", "node-refresh", "node-remove",
    "node-storage-repair", "node-update",
    "notification-rule-create", "notification-rule-list", "notification-rule-remove",
    "notification-rule-update",
    "ntp-config",
    "nvmeof-config",
    "object-logical-volume-discover",
    "object-storage-add", "object-storage-update",
    "object-volume-add", "object-volume-decommission", "object-volume-decommission-cancel",
    "object-volume-fail", "object-volume-gc-start", "object-volume-gc-stop",
    "object-volume-list", "object-volume-remove", "object-volume-remove-cancel",
    "object-volume-reservation-delete", "object-volume-set-available",
    "object-volume-set-unavailable", "object-volume-update",
    "objective-create", "objective-delete", "objective-export", "objective-import",
    "objective-list", "objective-update",
    "preview-no-upload-object-volume-add",
    "privileged-delete",
    "processor-add", "processor-list", "processor-remove", "processor-update",
    "remote-site-add", "remote-site-discover", "remote-site-list", "remote-site-remove",
    "remote-site-update",
    "role-create", "role-delete", "role-list", "role-update",
    "s3-server-bucket-create", "s3-server-bucket-remove",
    "s3-server-create", "s3-server-delete", "s3-server-list", "s3-server-update",
    "s3-server-user-add", "s3-server-user-remove",
    "schedule-create", "schedule-delete", "schedule-list", "schedule-update",
    "share-clone-create", "share-create", "share-delete", "share-list", "share-mount",
    "share-move", "share-objective-add", "share-objective-list", "share-objective-remove",
    "share-objective-reset", "share-offline", "share-online", "share-snapshot-create",
    "share-snapshot-delete", "share-snapshot-list", "share-snapshot-restore",
    "share-snapshot-schedule-list", "share-snapshot-update", "share-undelete",
    "share-unmount", "share-update",
    "smb-config",
    "snapshot-retention-create", "snapshot-retention-delete", "snapshot-retention-list",
    "snapshot-retention-update",
    "snmp-config",
    "software-apply", "software-list", "software-package-delete", "software-update-cancel",
    "software-update-status", "software-upload",
    "static-route-add", "static-route-delete", "static-route-list",
    "subnet-gateway-add", "subnet-gateway-delete", "subnet-gateway-list",
    "support-bundle",
    "syslog-config",
    "system-backup-config", "system-backup-list", "system-backup-restore",
    "system-shutdown", "system-view",
    "task-cancel", "task-list", "task-resume",
    "user-create", "user-delete", "user-import", "user-list", "user-password-update",
    "user-update",
    "volume-add", "volume-assimilation", "volume-assimilation-cancel",
    "volume-decommission", "volume-decommission-cancel", "volume-fail",
    "volume-group-create", "volume-group-delete", "volume-group-list",
    "volume-group-update", "volume-list", "volume-remove", "volume-remove-cancel",
    "volume-set-available", "volume-set-unavailable", "volume-update"
)

$script:_HSA_PRINT_FIELDS = @(
    "name", "internal-id", "id", "path", "lifecycle", "state", "size-limit-state",
    "export-options", "smb-browsable", "is-referral", "client-specification",
    "access-permissions", "root-squash", "insecure", "security-options"
)

$script:_HSA_WRAPPER_OPTIONS = @("-print", "-recursive", "-export-txt", "-export-csv")

Register-ArgumentCompleter -CommandName hsa -ParameterName Command -ScriptBlock {
    param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)

    # Parse the tokens already on the command line
    $tokens = $commandAst.CommandElements | Select-Object -Skip 1  # skip 'hsa'
    $tokenStrings = $tokens | ForEach-Object { $_.ToString() }
    $prev = if ($tokenStrings.Count -ge 2) { $tokenStrings[-2] } else { "" }

    # First argument: complete HS commands
    if ($tokenStrings.Count -le 1) {
        return $script:_HSA_COMMANDS |
            Where-Object { $_ -like "$wordToComplete*" } |
            ForEach-Object { [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_) }
    }

    # After -print: complete field names
    if ($prev -eq "-print") {
        return $script:_HSA_PRINT_FIELDS |
            Where-Object { $_ -like "$wordToComplete*" } |
            ForEach-Object { [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_) }
    }

    # After -recursive: complete HS commands (child command)
    if ($prev -eq "-recursive") {
        return $script:_HSA_COMMANDS |
            Where-Object { $_ -like "$wordToComplete*" } |
            ForEach-Object { [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_) }
    }

    # After -export-txt / -export-csv: complete local filenames
    if ($prev -in @("-export-txt", "-export-csv")) {
        return Get-ChildItem -Path "$wordToComplete*" -ErrorAction SilentlyContinue |
            ForEach-Object { [System.Management.Automation.CompletionResult]::new($_.Name, $_.Name, 'ParameterValue', $_.FullName) }
    }

    # Otherwise: complete wrapper options
    return $script:_HSA_WRAPPER_OPTIONS |
        Where-Object { $_ -like "$wordToComplete*" } |
        ForEach-Object { [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_) }
}


# ==============================================================================
#  ENTRY POINT
# ==============================================================================
#
#  Detect whether the script is being dot-sourced or run directly.
#  When dot-sourced, $MyInvocation.InvocationName is '.' or the calling context.
#  When run directly, $MyInvocation.InvocationName is the script path.
# ==============================================================================

# Initialise credential cache
if (-not (Get-Variable -Name HSA_IP   -Scope Script -ErrorAction SilentlyContinue)) { $script:HSA_IP   = "" }
if (-not (Get-Variable -Name HSA_USER -Scope Script -ErrorAction SilentlyContinue)) { $script:HSA_USER = "" }
if (-not (Get-Variable -Name HSA_PASS -Scope Script -ErrorAction SilentlyContinue)) { $script:HSA_PASS = "" }

if ($MyInvocation.InvocationName -eq '.' -or
    $MyInvocation.Line -match '^\.\s') {
    # Dot-sourced: register functions and print load message
    Write-Host "[hsa] " -ForegroundColor Cyan -NoNewline
    Write-Host "Hammerspace CLI wrapper loaded."
    Write-Host "     Commands: hsa-login  hsa-logout  hsa <cmd>  hsa-session  hsa-status  hsa-help" -ForegroundColor DarkGray
    Write-Host "     Tab-completion enabled: hsa <Tab> to see all commands." -ForegroundColor DarkGray
    Write-Host "     Credentials will be prompted on first use." -ForegroundColor DarkGray
} else {
    # Run directly: enter hsa> mode
    Invoke-HsaMode
}
