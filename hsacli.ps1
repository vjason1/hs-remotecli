# ==============================================================================
#
#              Copyright (C) 2016-2026 Hammerspace, Inc.
#  -----------------------------------------------------------------
#      DO NOT ATTEMPT TO LOGIN UNLESS YOU ARE AN AUTHORIZED USER.
#  -----------------------------------------------------------------
#
#  hsacli.ps1 - Hammerspace CLI Remote Wrapper for Windows PowerShell
#
#  Load:
#    . .\hsacli.ps1
#
#  Run:
#    hsa share-list
#    hsa
#    hsa> share-list -print name
#    hsa> share-list -print name -recursive share-snapshot-create --share-name '$#' --now
#    hsa> share-list -export-txt shares.txt
#    hsa> share-list -export-csv shares.csv
#
#  Dependency:
#    plink.exe from PuTTY must be installed and available on PATH.
#
# ==============================================================================

Set-StrictMode -Version 2.0

$script:HsaIp = $null
$script:HsaUser = $null
$script:HsaPass = $null
$script:HsaModeHistory = New-Object System.Collections.Generic.List[string]

$script:HsaCommands = @'
ad-config ad-discover
antivirus-add antivirus-list antivirus-remove antivirus-update
builtin-group-user-add builtin-group-user-list builtin-group-user-remove
cluster-config
dns-config
domain-idmap-add domain-idmap-delete domain-idmap-list domain-idmap-reload
dp-update
drive-list
email-config
event-list event-update
file-snapshot-create file-snapshot-delete file-snapshot-list
file-snapshot-restore file-snapshot-schedule-list file-snapshot-update
floating-ip-add floating-ip-remove
gateway-list gateway-update
gfs-participant-add gfs-participant-disable gfs-participant-enable
gfs-participant-list gfs-participant-remove
heartbeat-list heartbeat-send heartbeat-update
identity-group-mapping-create identity-group-mapping-delete
identity-group-mapping-list identity-group-mapping-update
idp-add idp-list idp-remove idp-update
interface-create interface-delete interface-list interface-update
kms-add kms-list kms-remove kms-update
label-create label-delete label-list label-update
license-add license-list license-offline-add license-offline-cancel
license-offline-remove license-offline-update license-remove license-update
local-site-config
logical-volume-create logical-volume-delete logical-volume-discover
logical-volume-list
login-policy-config
metric-list
nis-config
node-add node-list node-mode-change node-refresh node-remove
node-storage-repair node-update
notification-rule-create notification-rule-list notification-rule-remove
notification-rule-update
ntp-config
nvmeof-config
object-logical-volume-discover
object-storage-add object-storage-update
object-volume-add object-volume-decommission object-volume-decommission-cancel
object-volume-fail object-volume-gc-start object-volume-gc-stop
object-volume-list object-volume-remove object-volume-remove-cancel
object-volume-reservation-delete object-volume-set-available
object-volume-set-unavailable object-volume-update
objective-create objective-delete objective-export objective-import
objective-list objective-update
preview-no-upload-object-volume-add
privileged-delete
processor-add processor-list processor-remove processor-update
remote-site-add remote-site-discover remote-site-list remote-site-remove
remote-site-update
role-create role-delete role-list role-update
s3-server-bucket-create s3-server-bucket-remove
s3-server-create s3-server-delete s3-server-list s3-server-update
s3-server-user-add s3-server-user-remove
schedule-create schedule-delete schedule-list schedule-update
share-clone-create share-create share-delete share-list share-mount
share-move share-objective-add share-objective-list share-objective-remove
share-objective-reset share-offline share-online share-snapshot-create
share-snapshot-delete share-snapshot-list share-snapshot-restore
share-snapshot-schedule-list share-snapshot-update share-undelete
share-unmount share-update
smb-config
snapshot-retention-create snapshot-retention-delete snapshot-retention-list
snapshot-retention-update
snmp-config
software-apply software-list software-package-delete software-update-cancel
software-update-status software-upload
static-route-add static-route-delete static-route-list
subnet-gateway-add subnet-gateway-delete subnet-gateway-list
support-bundle
syslog-config
system-backup-config system-backup-list system-backup-restore
system-shutdown system-view
task-cancel task-list task-resume
user-create user-delete user-import user-list user-password-update
user-update
volume-add volume-assimilation volume-assimilation-cancel
volume-decommission volume-decommission-cancel volume-fail
volume-group-create volume-group-delete volume-group-list
volume-group-update volume-list volume-remove volume-remove-cancel
volume-set-available volume-set-unavailable volume-update
'@ -split '\s+' | Where-Object { $_ }

$script:HsaPrintFields = @(
    'name',
    'internal-id',
    'id',
    'path',
    'lifecycle',
    'state',
    'size-limit-state',
    'export-options',
    'smb-browsable',
    'is-referral',
    'client-specification',
    'access-permissions',
    'root-squash',
    'insecure',
    'security-options'
)

function Write-HsaInfo {
    param([string]$Message)
    Write-Host "[hsa] $Message" -ForegroundColor Cyan
}

function Write-HsaOk {
    param([string]$Message)
    Write-Host "[hsa] $Message" -ForegroundColor Green
}

function Write-HsaWarn {
    param([string]$Message)
    Write-Warning "[hsa] $Message"
}

function Write-HsaErr {
    param([string]$Message)
    Write-Host "[hsa] $Message" -ForegroundColor Red
}

function ConvertFrom-HsaSecureString {
    param([Security.SecureString]$SecureString)
    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecureString)
    try {
        [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
    } finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    }
}

function Test-HsaPlink {
    if (-not (Get-Command plink.exe -ErrorAction SilentlyContinue)) {
        Write-HsaErr "plink.exe is not installed or not on PATH."
        Write-HsaErr "Install PuTTY from https://www.putty.org/ and reopen PowerShell."
        return $false
    }
    return $true
}

function Invoke-HsaSshCommand {
    param([Parameter(Mandatory)][string[]]$CommandArgs)

    if (-not (Test-HsaPlink)) {
        return $null
    }

    $remoteCommand = $CommandArgs -join ' '
    $target = "$($script:HsaUser)@$($script:HsaIp)"
    $output = & plink.exe -ssh -batch -pw $script:HsaPass $target $remoteCommand 2>&1
    if ($LASTEXITCODE -ne 0) {
        $output | ForEach-Object { Write-Error $_ }
        throw "Remote command failed with exit code $LASTEXITCODE."
    }
    return @($output)
}

function Open-HsaSession {
    if (-not (Test-HsaPlink)) {
        return
    }

    Write-HsaInfo "Opening raw Hammerspace CLI session to $($script:HsaUser)@$($script:HsaIp) ..."
    & plink.exe -ssh -pw $script:HsaPass "$($script:HsaUser)@$($script:HsaIp)"
    Write-HsaInfo "Returned to PowerShell. HSA credentials are still cached."
}

function Ensure-HsaCredentials {
    if ([string]::IsNullOrWhiteSpace($script:HsaIp) -or [string]::IsNullOrWhiteSpace($script:HsaPass)) {
        hsa-login
    }
    return -not ([string]::IsNullOrWhiteSpace($script:HsaIp) -or [string]::IsNullOrWhiteSpace($script:HsaPass))
}

function hsa-login {
    if (-not (Test-HsaPlink)) {
        return
    }

    if ($script:HsaIp) {
        Write-HsaWarn "Currently connected to $($script:HsaUser)@$($script:HsaIp). New credentials will replace this connection."
    }

    Write-Host ""
    Write-Host "             Copyright (C) 2016-2026 Hammerspace, Inc." -ForegroundColor Cyan
    Write-Host "  ---------------------------------------------------------------" -ForegroundColor DarkGray
    Write-Host "      DO NOT ATTEMPT TO LOGIN UNLESS YOU ARE AN AUTHORIZED USER." -ForegroundColor Yellow
    Write-Host "  ---------------------------------------------------------------" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "            Hammerspace CLI - Connection Setup" -ForegroundColor Cyan
    Write-Host ""

    $defaultIp = $script:HsaIp
    if ($defaultIp) {
        $inputIp = Read-Host "  Cluster IP or hostname [$defaultIp]"
        if ([string]::IsNullOrWhiteSpace($inputIp)) { $inputIp = $defaultIp }
    } else {
        $inputIp = Read-Host "  Cluster IP or hostname"
    }

    if ([string]::IsNullOrWhiteSpace($inputIp)) {
        Write-HsaErr "Cluster IP is required."
        return
    }

    $defaultUser = if ($script:HsaUser) { $script:HsaUser } else { 'admin' }
    $inputUser = Read-Host "  Username [$defaultUser]"
    if ([string]::IsNullOrWhiteSpace($inputUser)) { $inputUser = $defaultUser }

    $securePass = Read-Host "  Password" -AsSecureString
    $inputPass = ConvertFrom-HsaSecureString $securePass
    if ([string]::IsNullOrWhiteSpace($inputPass)) {
        Write-HsaErr "Password is required."
        return
    }

    $oldIp = $script:HsaIp
    $oldUser = $script:HsaUser
    $oldPass = $script:HsaPass

    $script:HsaIp = $inputIp
    $script:HsaUser = $inputUser
    $script:HsaPass = $inputPass

    Write-HsaInfo "Testing connection to $inputUser@$inputIp ..."
    try {
        [void](Invoke-HsaSshCommand @('system-view'))
        Write-HsaOk "Connected to $($script:HsaUser)@$($script:HsaIp)"
    } catch {
        $script:HsaIp = $oldIp
        $script:HsaUser = $oldUser
        $script:HsaPass = $oldPass
        Write-HsaErr "Connection failed. Check IP, username, password, host key, and network reachability."
        Write-HsaErr $_.Exception.Message
    }
}

function hsa-logout {
    if (-not $script:HsaIp) {
        Write-HsaInfo "No credentials cached - nothing to clear."
        return
    }

    $oldIp = $script:HsaIp
    $script:HsaIp = $null
    $script:HsaUser = $null
    $script:HsaPass = $null
    Write-HsaOk "Credentials cleared (was connected to $oldIp)."
}

function hsa-status {
    Write-Host ""
    Write-Host "Hammerspace CLI - Connection Status" -ForegroundColor Cyan
    Write-Host "-----------------------------------" -ForegroundColor DarkGray

    if (-not $script:HsaIp) {
        Write-Host "  Not connected. Run hsa-login, or run any hsa command to be prompted." -ForegroundColor Yellow
        Write-Host ""
        return
    }

    Write-Host "  Cluster  : $($script:HsaIp)"
    Write-Host "  Username : $($script:HsaUser)"
    Write-Host "  Password : (cached in session - not shown)" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  Testing connectivity..." -ForegroundColor DarkGray

    try {
        $probe = Invoke-HsaSshCommand @('system-view')
        Write-Host "  Reachable" -ForegroundColor Green
        if ($probe) {
            Write-Host ""
            Write-Host "  system-view (first 5 lines):" -ForegroundColor DarkGray
            $probe | Select-Object -First 5 | ForEach-Object { Write-Host "    $_" }
        }
    } catch {
        Write-Host "  Unreachable - check network or run hsa-logout and reconnect." -ForegroundColor Red
    }
    Write-Host ""
}

function hsa-session {
    if (Ensure-HsaCredentials) {
        Open-HsaSession
    }
}

function Normalize-HsaFieldName {
    param([string]$Value)
    if ($null -eq $Value) { return '' }
    return (($Value.Trim().ToLowerInvariant()) -replace '[^a-z0-9]', '')
}

function Select-HsaPrintValues {
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string[]]$Lines,
        [Parameter(Mandatory)][string]$Selector
    )

    if ($Selector -match '^\d+$') {
        $index = [int]$Selector - 1
        foreach ($line in $Lines) {
            $parts = ($line -split '\s+') | Where-Object { $_ -ne '' }
            if ($parts.Count -gt $index) {
                $parts[$index]
            }
        }
        return
    }

    $wanted = Normalize-HsaFieldName $Selector
    foreach ($line in $Lines) {
        if ($line -match '^[^\s][^:]*:') {
            $colon = $line.IndexOf(':')
            $key = $line.Substring(0, $colon)
            $value = $line.Substring($colon + 1).Trim()
            if ((Normalize-HsaFieldName $key) -eq $wanted) {
                $value
            }
        }
    }
}

function Convert-HsaOutputToObjects {
    param([AllowEmptyString()][string[]]$Lines)

    $records = New-Object System.Collections.Generic.List[object]
    $current = [ordered]@{}
    $lastKey = $null
    $plain = New-Object System.Collections.Generic.List[string]

    function Flush-Record {
        if ($current.Count -gt 0) {
            $records.Add([pscustomobject]$current)
            $script:current = [ordered]@{}
        }
    }

    foreach ($line in $Lines) {
        if ([string]::IsNullOrWhiteSpace($line)) {
            if ($current.Count -gt 0) {
                $records.Add([pscustomobject]$current)
                $current = [ordered]@{}
                $lastKey = $null
            }
            continue
        }

        if ($line -match '^[^\s][^:]*:') {
            $colon = $line.IndexOf(':')
            $label = $line.Substring(0, $colon).Trim()
            $value = $line.Substring($colon + 1).Trim()
            $current[$label] = $value
            $lastKey = $label
            continue
        }

        if ($line -match '^\s+' -and $lastKey -and $current.Contains($lastKey)) {
            $continuation = $line.Trim()
            if ($continuation) {
                if ($current[$lastKey]) {
                    $current[$lastKey] = "$($current[$lastKey]) $continuation"
                } else {
                    $current[$lastKey] = $continuation
                }
            }
            continue
        }

        if ($current.Count -eq 0 -and $line.Trim()) {
            $plain.Add($line.Trim())
        }
    }

    if ($current.Count -gt 0) {
        $records.Add([pscustomobject]$current)
    }

    if ($records.Count -gt 0) {
        return @($records.ToArray())
    }

    return @($plain.ToArray() | ForEach-Object { [pscustomobject]@{ Value = $_ } })
}

function Export-HsaOutput {
    param(
        [Parameter(Mandatory)][ValidateSet('txt', 'csv')][string]$Type,
        [Parameter(Mandatory)][string]$Path,
        [AllowEmptyString()][string[]]$Lines
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        Write-HsaErr "-export-$Type requires a local filename."
        return
    }

    if ($Type -eq 'txt') {
        $Lines | Set-Content -Path $Path -Encoding UTF8
    } else {
        Convert-HsaOutputToObjects $Lines | Export-Csv -Path $Path -NoTypeInformation -Encoding UTF8
    }

    Write-HsaOk "Exported output to $Path"
}

function Invoke-HsaRunRecursive {
    param(
        [string]$PrintSelector,
        [string[]]$BaseArgs,
        [string[]]$RecursiveArgs
    )

    if ([string]::IsNullOrWhiteSpace($PrintSelector)) {
        Write-HsaErr "-recursive requires -print <field> so the parent output has one value per child command."
        return @()
    }
    if (-not $BaseArgs -or $BaseArgs.Count -eq 0) {
        Write-HsaErr "-recursive requires a parent command before -recursive."
        return @()
    }
    if (-not $RecursiveArgs -or $RecursiveArgs.Count -eq 0) {
        Write-HsaErr "-recursive requires a child command."
        return @()
    }

    $parentOutput = Invoke-HsaSshCommand $BaseArgs
    $values = Select-HsaPrintValues -Lines $parentOutput -Selector $PrintSelector
    $combined = New-Object System.Collections.Generic.List[string]

    foreach ($value in $values) {
        if ([string]::IsNullOrWhiteSpace($value)) { continue }
        $childArgs = foreach ($arg in $RecursiveArgs) {
            $arg.Replace('$#', $value)
        }
        $childOutput = Invoke-HsaRunCommand $childArgs
        foreach ($line in $childOutput) {
            $combined.Add($line)
        }
    }

    return @($combined)
}

function Invoke-HsaRunCommand {
    param([Parameter(Mandatory, ValueFromRemainingArguments = $true)][string[]]$Args)

    if (-not $Args -or $Args.Count -eq 0) {
        Write-HsaErr "No HSA command supplied."
        return @()
    }

    $printSelector = $null
    $exportType = $null
    $exportFile = $null
    $recursiveMode = $false
    $baseArgs = New-Object System.Collections.Generic.List[string]
    $recursiveArgs = New-Object System.Collections.Generic.List[string]

    for ($i = 0; $i -lt $Args.Count; $i++) {
        $arg = $Args[$i]
        switch -Regex ($arg) {
            '^-print$' {
                $i++
                if ($i -ge $Args.Count) { Write-HsaErr "-print requires a field name."; return @() }
                $printSelector = $Args[$i]
                continue
            }
            '^-print=(.+)$' {
                $printSelector = $Matches[1]
                continue
            }
            '^(-?export-txt)$' {
                $i++
                if ($i -ge $Args.Count) { Write-HsaErr "$arg requires a local filename."; return @() }
                $exportType = 'txt'
                $exportFile = $Args[$i]
                continue
            }
            '^-export-txt=(.+)$' {
                $exportType = 'txt'
                $exportFile = $Matches[1]
                continue
            }
            '^export-txt=(.+)$' {
                $exportType = 'txt'
                $exportFile = $Matches[1]
                continue
            }
            '^(-?export-csv)$' {
                $i++
                if ($i -ge $Args.Count) { Write-HsaErr "$arg requires a local filename."; return @() }
                $exportType = 'csv'
                $exportFile = $Args[$i]
                continue
            }
            '^-export-csv=(.+)$' {
                $exportType = 'csv'
                $exportFile = $Matches[1]
                continue
            }
            '^export-csv=(.+)$' {
                $exportType = 'csv'
                $exportFile = $Matches[1]
                continue
            }
            '^-recursive$' {
                $recursiveMode = $true
                for ($j = $i + 1; $j -lt $Args.Count; $j++) {
                    $recursiveArgs.Add($Args[$j])
                }
                break
            }
            '^-recursive=(.+)$' {
                $recursiveMode = $true
                $recursiveArgs.Add($Matches[1])
                for ($j = $i + 1; $j -lt $Args.Count; $j++) {
                    $recursiveArgs.Add($Args[$j])
                }
                break
            }
            default {
                $baseArgs.Add($arg)
                continue
            }
        }

        if ($recursiveMode) { break }
    }

    if ($recursiveMode) {
        $output = Invoke-HsaRunRecursive -PrintSelector $printSelector -BaseArgs @($baseArgs) -RecursiveArgs @($recursiveArgs)
        if ($exportType) { Export-HsaOutput -Type $exportType -Path $exportFile -Lines $output }
        return @($output)
    }

    if ($baseArgs.Count -eq 0) {
        Write-HsaErr "No HSA command supplied."
        return @()
    }

    $output = Invoke-HsaSshCommand @($baseArgs)
    if ($printSelector) {
        $output = @(Select-HsaPrintValues -Lines $output -Selector $printSelector)
    }

    if ($exportType) {
        Export-HsaOutput -Type $exportType -Path $exportFile -Lines $output
    }

    return @($output)
}

function Split-HsaCommandLine {
    param([string]$Line)
    $parseErrors = $null
    $tokens = [System.Management.Automation.PSParser]::Tokenize($Line, [ref]$parseErrors)
    if ($parseErrors -and $parseErrors.Count -gt 0) {
        Write-HsaWarn "Could not parse command line: $($parseErrors[0].Message)"
        return @()
    }
    return @($tokens | Where-Object {
        $_.Type -in @('Command', 'CommandArgument', 'CommandParameter', 'String', 'Number')
    } | ForEach-Object { $_.Content })
}

function Get-HsaCompletionWords {
    param(
        [string]$Buffer,
        [int]$Cursor,
        [string]$CurrentWord
    )

    $before = $Buffer.Substring(0, [Math]::Min($Cursor, $Buffer.Length))
    $tokens = Split-HsaCommandLine $before
    $endsWithSpace = $before -match '\s$'
    $prev = $null
    if ($tokens.Count -gt 0) {
        if ($endsWithSpace) {
            $prev = $tokens[-1]
        } elseif ($tokens.Count -gt 1) {
            $prev = $tokens[-2]
        }
    }

    if ($tokens.Count -eq 0 -or ($tokens.Count -eq 1 -and -not $endsWithSpace) -or ($tokens.Count -eq 1 -and $tokens[0] -eq 'hsa')) {
        return @($script:HsaCommands + @('exit', 'quit', 'help', 'status', 'login', 'logout', 'session', 'hsa-help', 'hsa-status', 'hsa-login', 'hsa-logout', 'hsa-session'))
    }

    if ($prev -in @('-print')) {
        return @($script:HsaPrintFields)
    }

    if ($prev -in @('-recursive')) {
        return @($script:HsaCommands)
    }

    if ($prev -in @('-export-txt', 'export-txt', '-export-csv', 'export-csv')) {
        return @(Get-ChildItem -Path "$CurrentWord*" -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName })
    }

    if ($CurrentWord.StartsWith('-')) {
        return @('-print', '-recursive', '-export-txt', '-export-csv')
    }

    return @('-print', '-recursive', '-export-txt', '-export-csv')
}

function Get-HsaWordBounds {
    param([string]$Buffer, [int]$Cursor)
    $start = $Cursor
    $end = $Cursor
    while ($start -gt 0 -and -not [char]::IsWhiteSpace($Buffer[$start - 1])) { $start-- }
    while ($end -lt $Buffer.Length -and -not [char]::IsWhiteSpace($Buffer[$end])) { $end++ }
    [pscustomobject]@{
        Start = $start
        End = $end
        Word = $Buffer.Substring($start, $end - $start)
    }
}

function Get-CommonPrefix {
    param([string[]]$Values)
    if (-not $Values -or $Values.Count -eq 0) { return '' }
    $prefix = $Values[0]
    foreach ($value in $Values) {
        while ($prefix.Length -gt 0 -and -not $value.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
            $prefix = $prefix.Substring(0, $prefix.Length - 1)
        }
    }
    return $prefix
}

function Redraw-HsaLine {
    param([string]$Prompt, [string]$Buffer, [int]$Cursor)
    Write-Host "`r$(' ' * ([Console]::BufferWidth - 1))`r$Prompt$Buffer" -NoNewline
    $right = $Buffer.Length - $Cursor
    if ($right -gt 0) {
        [Console]::SetCursorPosition([Console]::CursorLeft - $right, [Console]::CursorTop)
    }
}

function Complete-HsaLine {
    param(
        [string]$Prompt,
        [ref]$Buffer,
        [ref]$Cursor
    )

    $bounds = Get-HsaWordBounds -Buffer $Buffer.Value -Cursor $Cursor.Value
    $matches = @(Get-HsaCompletionWords -Buffer $Buffer.Value -Cursor $Cursor.Value -CurrentWord $bounds.Word |
        Where-Object { $_ -like "$($bounds.Word)*" } |
        Sort-Object -Unique)

    if ($matches.Count -eq 0) {
        [Console]::Beep()
        return
    }

    if ($matches.Count -eq 1) {
        $replacement = "$($matches[0]) "
    } else {
        $prefix = Get-CommonPrefix $matches
        if ([string]::IsNullOrEmpty($prefix) -or $prefix -eq $bounds.Word) {
            Write-Host ""
            $matches -join "  " | Write-Host
            Redraw-HsaLine -Prompt $Prompt -Buffer $Buffer.Value -Cursor $Cursor.Value
            return
        }
        $replacement = $prefix
    }

    $Buffer.Value = $Buffer.Value.Substring(0, $bounds.Start) + $replacement + $Buffer.Value.Substring($bounds.End)
    $Cursor.Value = $bounds.Start + $replacement.Length
}

function Read-HsaLine {
    param([string]$Prompt)

    if ([Console]::IsInputRedirected) {
        Write-Host $Prompt -NoNewline
        return [Console]::In.ReadLine()
    }

    $buffer = ''
    $cursor = 0
    $historyIndex = $script:HsaModeHistory.Count
    $saved = ''
    Write-Host $Prompt -NoNewline

    while ($true) {
        $key = [Console]::ReadKey($true)
        switch ($key.Key) {
            'Enter' {
                Write-Host ""
                return $buffer
            }
            'Tab' {
                Complete-HsaLine -Prompt $Prompt -Buffer ([ref]$buffer) -Cursor ([ref]$cursor)
            }
            'Backspace' {
                if ($cursor -gt 0) {
                    $buffer = $buffer.Remove($cursor - 1, 1)
                    $cursor--
                } else {
                    [Console]::Beep()
                }
            }
            'Delete' {
                if ($cursor -lt $buffer.Length) {
                    $buffer = $buffer.Remove($cursor, 1)
                } else {
                    [Console]::Beep()
                }
            }
            'LeftArrow' {
                if ($cursor -gt 0) { $cursor-- }
            }
            'RightArrow' {
                if ($cursor -lt $buffer.Length) { $cursor++ }
            }
            'Home' {
                $cursor = 0
            }
            'End' {
                $cursor = $buffer.Length
            }
            'UpArrow' {
                if ($script:HsaModeHistory.Count -gt 0 -and $historyIndex -gt 0) {
                    if ($historyIndex -eq $script:HsaModeHistory.Count) { $saved = $buffer }
                    $historyIndex--
                    $buffer = $script:HsaModeHistory[$historyIndex]
                    $cursor = $buffer.Length
                } else {
                    [Console]::Beep()
                }
            }
            'DownArrow' {
                if ($historyIndex -lt $script:HsaModeHistory.Count) {
                    $historyIndex++
                    if ($historyIndex -eq $script:HsaModeHistory.Count) {
                        $buffer = $saved
                    } else {
                        $buffer = $script:HsaModeHistory[$historyIndex]
                    }
                    $cursor = $buffer.Length
                } else {
                    [Console]::Beep()
                }
            }
            default {
                if (($key.Modifiers -band [ConsoleModifiers]::Control) -and $key.Key -eq 'C') {
                    Write-Host "^C"
                    return ''
                }
                if (($key.Modifiers -band [ConsoleModifiers]::Control) -and $key.Key -eq 'D') {
                    if ($buffer.Length -eq 0) { return $null }
                }
                if (-not [char]::IsControl($key.KeyChar)) {
                    $buffer = $buffer.Insert($cursor, [string]$key.KeyChar)
                    $cursor++
                }
            }
        }
        Redraw-HsaLine -Prompt $Prompt -Buffer $buffer -Cursor $cursor
    }
}

function Start-HsaMode {
    Write-Host ""
    Write-Host "Hammerspace CLI - hsa mode" -ForegroundColor Cyan
    Write-Host "Type HS commands directly. Built-ins: help, status, login, logout, session, exit." -ForegroundColor DarkGray
    Write-Host ""

    if (-not (Ensure-HsaCredentials)) {
        return
    }

    while ($true) {
        $line = Read-HsaLine "hsa> "
        if ($null -eq $line) {
            Write-HsaInfo "Leaving hsa mode."
            return
        }
        if ([string]::IsNullOrWhiteSpace($line)) {
            continue
        }

        if ($script:HsaModeHistory.Count -eq 0 -or $script:HsaModeHistory[$script:HsaModeHistory.Count - 1] -ne $line) {
            $script:HsaModeHistory.Add($line)
        }

        switch -Regex ($line) {
            '^(exit|quit)$' { Write-HsaInfo "Leaving hsa mode."; return }
            '^(help|\?|hsa-help)$' { hsa-help; continue }
            '^(status|hsa-status)$' { hsa-status; continue }
            '^(login|hsa-login)$' { hsa-login; continue }
            '^(logout|hsa-logout)$' { hsa-logout; continue }
            '^(session|hsa-session)$' { hsa-session; continue }
            '^hsa\s+' { $line = $line -replace '^hsa\s+', '' }
            '^hsa$' { hsa-session; continue }
        }

        $args = Split-HsaCommandLine $line
        try {
            Invoke-HsaRunCommand $args | ForEach-Object { Write-Output $_ }
        } catch {
            Write-HsaWarn $_.Exception.Message
        }
    }
}

function hsa {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Args)

    if (-not (Ensure-HsaCredentials)) {
        return
    }

    if (-not $Args -or $Args.Count -eq 0) {
        Start-HsaMode
        return
    }

    try {
        Invoke-HsaRunCommand $Args | ForEach-Object { Write-Output $_ }
    } catch {
        Write-HsaWarn $_.Exception.Message
    }
}

function hsa-help {
    @'

  Hammerspace CLI Wrapper for Windows PowerShell
  ------------------------------------------------

  COMMANDS:
    hsa <command> [args]    Run any HS CLI command on the cluster
    hsa                     Enter hsa> mode; HS commands no longer need prefix
    hsa-session             Open the raw remote Hammerspace CLI session
    hsa-status              Show connection info and test reachability
    hsa-logout              Clear cached credentials
    hsa-help                Show this help

  HSA MODE:
    hsa> share-list
    hsa> share-list -print name
    hsa> share-list -export-csv shares.csv
    hsa> quit

  PRINT AND RECURSIVE:
    hsa share-list -print name
    hsa share-list -print name -recursive share-snapshot-create --share-name '$#' --now

  EXPORT:
    hsa share-list -export-txt shares.txt
    hsa share-list -export-csv shares.csv
    hsa share-list -print name -export-txt share_names.txt

  NOTES:
    - plink.exe from PuTTY must be installed and on PATH.
    - Credentials are cached in this PowerShell session only.
    - hsa> mode sends non-built-in commands remotely to the cluster.

'@
}

function Register-HsaCompletion {
    Register-ArgumentCompleter -CommandName hsa -ScriptBlock {
        param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)

        $elements = @($commandAst.CommandElements | ForEach-Object { $_.Extent.Text })
        $prev = if ($elements.Count -ge 2) { $elements[-2] } else { $null }

        if ($elements.Count -le 2) {
            $script:HsaCommands + @('hsa-login', 'hsa-logout', 'hsa-status', 'hsa-session', 'hsa-help') |
                Where-Object { $_ -like "$wordToComplete*" } |
                ForEach-Object { [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_) }
            return
        }

        if ($prev -eq '-print') {
            $script:HsaPrintFields |
                Where-Object { $_ -like "$wordToComplete*" } |
                ForEach-Object { [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_) }
            return
        }

        if ($prev -eq '-recursive') {
            $script:HsaCommands |
                Where-Object { $_ -like "$wordToComplete*" } |
                ForEach-Object { [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_) }
            return
        }

        if ($prev -in @('-export-txt', 'export-txt', '-export-csv', 'export-csv')) {
            Get-ChildItem -Path "$wordToComplete*" -ErrorAction SilentlyContinue |
                ForEach-Object {
                    [System.Management.Automation.CompletionResult]::new($_.FullName, $_.Name, 'ProviderItem', $_.FullName)
                }
            return
        }

        @('-print', '-recursive', '-export-txt', '-export-csv') |
            Where-Object { $_ -like "$wordToComplete*" } |
            ForEach-Object { [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterName', $_) }
    }
}

Register-HsaCompletion

if ($MyInvocation.InvocationName -ne '.') {
    Start-HsaMode
} else {
    Write-Host "[hsa] Hammerspace CLI wrapper loaded." -ForegroundColor Cyan
    Write-Host "     Commands: hsa-login  hsa-logout  hsa <cmd>  hsa-session  hsa-status  hsa-help" -ForegroundColor DarkGray
    Write-Host "     Tab-completion enabled: hsa <Tab> to see commands and options." -ForegroundColor DarkGray
    Write-Host "     Credentials will be prompted on first use." -ForegroundColor DarkGray
}
