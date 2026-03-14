#Requires -Version 5.1
#Requires -RunAsAdministrator

<#
.SYNOPSIS
    PowerShell module for managing and removing stale user profiles.

.DESCRIPTION
    This module provides functions to identify and remove stale user profiles from Windows systems.
    It includes comprehensive safety checks, logging, and registry cleanup.

.NOTES
    Author: PowerShell Profile Management
    Version: 1.0.0
    Requires: PowerShell 5.1 or higher, Administrator privileges
#>

#region Helper Functions

<#
.SYNOPSIS
    Writes log entries in CMTrace-compatible format.
#>
function Write-CMTraceLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,
        
        [Parameter(Mandatory = $true)]
        [string]$LogPath,
        
        [Parameter(Mandatory = $false)]
        [ValidateSet('Info', 'Warning', 'Error')]
        [string]$Severity = 'Info',
        
        [Parameter(Mandatory = $false)]
        [string]$Component = 'Remove-StaleProfiles'
    )
    
    # Map severity to CMTrace severity levels (1=Info, 2=Warning, 3=Error)
    $severityMap = @{
        'Info'    = 1
        'Warning' = 2
        'Error'   = 3
    }
    
    $time = Get-Date -Format "HH:mm:ss.fff"
    $date = Get-Date -Format "MM-dd-yyyy"
    $severityNumber = $severityMap[$Severity]
    
    # CMTrace log format: <![LOG[Message]LOG]!><time="HH:mm:ss.fff+000" date="MM-DD-YYYY" component="Component" context="" type="1" thread="1234" file="">
    $logLine = "<![LOG[$Message]LOG]!><time=`"$time+000`" date=`"$date`" component=`"$Component`" context=`"`" type=`"$severityNumber`" thread=`"$([System.Threading.Thread]::CurrentThread.ManagedThreadId)`" file=`"`">"
    
    try {
        # Ensure log directory exists
        $logDir = Split-Path -Path $LogPath -Parent
        if ($logDir -and -not (Test-Path -Path $logDir)) {
            New-Item -Path $logDir -ItemType Directory -Force | Out-Null
        }
        
        Add-Content -Path $LogPath -Value $logLine -Encoding UTF8
    }
    catch {
        Write-Warning "Failed to write to log: $_"
    }
}

<#
.SYNOPSIS
    Tests if a file is locked by another process.
#>
function Test-FileLock {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )
    
    if (-not (Test-Path -Path $Path)) {
        return $false
    }
    
    try {
        $fileStream = [System.IO.File]::Open(
            $Path,
            [System.IO.FileMode]::Open,
            [System.IO.FileAccess]::ReadWrite,
            [System.IO.FileShare]::None
        )
        
        if ($fileStream) {
            $fileStream.Close()
            $fileStream.Dispose()
        }
        
        return $false
    }
    catch {
        return $true
    }
}

<#
.SYNOPSIS
    Gets scheduled tasks registered under a specific SID.
#>
function Get-ScheduledTaskBySID {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$SID,
        
        [Parameter(Mandatory = $false)]
        [string]$ComputerName = 'localhost'
    )
    
    try {
        $tasks = @()
        
        if ($ComputerName -eq 'localhost' -or $ComputerName -eq $env:COMPUTERNAME) {
            # Local computer
            $allTasks = Get-ScheduledTask -ErrorAction SilentlyContinue
            foreach ($task in $allTasks) {
                $taskInfo = Get-ScheduledTaskInfo -TaskName $task.TaskName -TaskPath $task.TaskPath -ErrorAction SilentlyContinue
                if ($taskInfo -and $taskInfo.Principal -and $taskInfo.Principal.UserId -match $SID) {
                    $tasks += $task
                }
            }
        }
        else {
            # Remote computer - use CIM
            $allTasks = Get-CimInstance -ClassName MSFT_ScheduledTask -Namespace root\Microsoft\Windows\TaskScheduler -ComputerName $ComputerName -ErrorAction SilentlyContinue
            foreach ($task in $allTasks) {
                if ($task.Principal -match $SID) {
                    $tasks += $task
                }
            }
        }
        
        return $tasks
    }
    catch {
        Write-Verbose "Error checking scheduled tasks: $_"
        return @()
    }
}

<#
.SYNOPSIS
    Gets services running as a specific user SID.
#>
function Get-ServiceBySID {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$SID,
        
        [Parameter(Mandatory = $false)]
        [string]$ComputerName = 'localhost'
    )
    
    try {
        $services = @()
        
        if ($ComputerName -eq 'localhost' -or $ComputerName -eq $env:COMPUTERNAME) {
            # Local computer
            $allServices = Get-CimInstance -ClassName Win32_Service
        }
        else {
            # Remote computer
            $allServices = Get-CimInstance -ClassName Win32_Service -ComputerName $ComputerName
        }
        
        foreach ($service in $allServices) {
            if ($service.StartName) {
                try {
                    $account = New-Object System.Security.Principal.NTAccount($service.StartName)
                    $serviceSID = $account.Translate([System.Security.Principal.SecurityIdentifier]).Value
                    if ($serviceSID -eq $SID) {
                        $services += $service
                    }
                }
                catch {
                    # Unable to translate account, skip
                    continue
                }
            }
        }
        
        return $services
    }
    catch {
        Write-Verbose "Error checking services: $_"
        return @()
    }
}

<#
.SYNOPSIS
    Gets the username from a SID.
#>
function Get-UsernameFromSID {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$SID
    )
    
    try {
        $objSID = New-Object System.Security.Principal.SecurityIdentifier($SID)
        $objUser = $objSID.Translate([System.Security.Principal.NTAccount])
        return $objUser.Value
    }
    catch {
        return $null
    }
}

<#
.SYNOPSIS
    Gets the SID from a username.
#>
function Get-SIDFromUsername {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Username
    )
    
    try {
        $objUser = New-Object System.Security.Principal.NTAccount($Username)
        $objSID = $objUser.Translate([System.Security.Principal.SecurityIdentifier])
        return $objSID.Value
    }
    catch {
        return $null
    }
}

<#
.SYNOPSIS
    Calculates the size of a directory in GB.
#>
function Get-DirectorySize {
    [CmdletBinding()]
    [OutputType([double])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )
    
    if (-not (Test-Path -Path $Path)) {
        return 0
    }
    
    try {
        $size = (Get-ChildItem -Path $Path -Recurse -Force -ErrorAction SilentlyContinue | 
            Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum
        
        if ($size) {
            return [math]::Round($size / 1GB, 2)
        }
        else {
            return 0
        }
    }
    catch {
        return 0
    }
}

<#
.SYNOPSIS
    Backs up registry keys to JSON.
#>
function Backup-RegistryKeys {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$SID,
        
        [Parameter(Mandatory = $true)]
        [string]$BackupPath
    )
    
    $registryPaths = @(
        "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\$SID",
        "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileGuid\$SID",
        "HKLM:\SOFTWARE\Microsoft\IdentityStore\Cache\$SID",
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Installer\UserData\$SID"
    )
    
    $backup = @{
        SID       = $SID
        Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        Keys      = @{}
    }
    
    foreach ($path in $registryPaths) {
        if (Test-Path -Path $path) {
            try {
                $key = Get-Item -Path $path -ErrorAction SilentlyContinue
                if ($key) {
                    $backup.Keys[$path] = @{
                        Properties = @{}
                    }
                    
                    foreach ($prop in $key.Property) {
                        $backup.Keys[$path].Properties[$prop] = $key.GetValue($prop)
                    }
                }
            }
            catch {
                Write-Verbose "Failed to backup registry key: $path - $_"
            }
        }
    }
    
    try {
        $backup | ConvertTo-Json -Depth 10 | Out-File -FilePath $BackupPath -Encoding UTF8
        return $true
    }
    catch {
        Write-Warning "Failed to save registry backup: $_"
        return $false
    }
}

<#
.SYNOPSIS
    Removes registry keys associated with a user profile.
#>
function Remove-ProfileRegistryKeys {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory = $true)]
        [string]$SID,
        
        [Parameter(Mandatory = $false)]
        [string]$LogPath
    )
    
    $registryPaths = @(
        "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\$SID",
        "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileGuid\$SID",
        "HKLM:\SOFTWARE\Microsoft\IdentityStore\Cache\$SID",
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Installer\UserData\$SID"
    )
    
    $results = @()
    $existedCount = 0
    
    foreach ($path in $registryPaths) {
        if (Test-Path -Path $path) {
            $existedCount++
            if ($PSCmdlet.ShouldProcess($path, "Remove registry key")) {
                try {
                    Remove-Item -Path $path -Recurse -Force -ErrorAction Stop
                    $results += [PSCustomObject]@{
                        Path    = $path
                        Removed = $true
                        Error   = $null
                    }
                    
                    if ($LogPath) {
                        Write-CMTraceLog -Message "Removed registry key: $path" -LogPath $LogPath -Severity Info -Component "RegistryCleanup"
                    }
                }
                catch {
                    $results += [PSCustomObject]@{
                        Path    = $path
                        Removed = $false
                        Error   = $_.Exception.Message
                    }
                    
                    if ($LogPath) {
                        Write-CMTraceLog -Message "Failed to remove registry key: $path - $_" -LogPath $LogPath -Severity Error -Component "RegistryCleanup"
                    }
                }
            }
            else {
                $results += [PSCustomObject]@{
                    Path    = $path
                    Removed = $false
                    Error   = "WhatIf mode"
                }
            }
        }
    }
    
    # Log summary
    if ($LogPath -and $existedCount -eq 0) {
        Write-CMTraceLog -Message "No registry keys found to clean up (already removed by WMI or never existed)" -LogPath $LogPath -Severity Info -Component "RegistryCleanup"
    }
    
    return $results
}

#endregion

#region Main Functions

<#
.SYNOPSIS
    Retrieves stale user profiles from a computer.

.DESCRIPTION
    Queries user profiles on a local or remote computer and filters them based on
    inactivity threshold. Returns profile information without making any changes.

.PARAMETER ComputerName
    The name of the computer to query. Defaults to localhost.

.PARAMETER InactiveDays
    The number of days of inactivity to consider a profile stale.

.PARAMETER ExcludeUsers
    Array of usernames or SIDs to exclude from results.

.EXAMPLE
    Get-StaleUserProfiles -InactiveDays 90
    
    Gets all user profiles that haven't been used in 90 days on the local computer.

.EXAMPLE
    Get-StaleUserProfiles -ComputerName SERVER01 -InactiveDays 180 -ExcludeUsers "admin", "service_account"
    
    Gets stale profiles from SERVER01, excluding specified accounts.

.OUTPUTS
    PSCustomObject with profile information including ComputerName, Username, SID, ProfilePath, SizeGB, LastUseTime, DaysInactive, Loaded, Status.
#>
function Get-StaleUserProfiles {
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param(
        [Parameter(Mandatory = $false, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [Alias('CN', 'Computer')]
        [string]$ComputerName = 'localhost',
        
        [Parameter(Mandatory = $false)]
        [ValidateRange(0, [int]::MaxValue)]
        [int]$InactiveDays,
        
        [Parameter(Mandatory = $false)]
        [string[]]$ExcludeUsers = @('Administrator', 'DefaultAccount', 'Guest', 'WDAGUtilityAccount', 'defaultuser0')
    )
    
    begin {
        Write-Verbose "Starting Get-StaleUserProfiles"
    }
    
    process {
        try {
            Write-Verbose "Querying profiles on $ComputerName"
            
            # Get all user profiles using WMI
            if ($ComputerName -eq 'localhost' -or $ComputerName -eq $env:COMPUTERNAME) {
                $profiles = Get-CimInstance -ClassName Win32_UserProfile -Filter "Special = False" -ErrorAction Stop
            }
            else {
                $profiles = Get-CimInstance -ClassName Win32_UserProfile -ComputerName $ComputerName -Filter "Special = False" -ErrorAction Stop
            }
            
            Write-Verbose "Found $($profiles.Count) non-special profiles"
            
            # Build exclude list with SIDs
            $excludeSIDs = @()
            foreach ($exclude in $ExcludeUsers) {
                if ($exclude -match '^S-1-5-') {
                    $excludeSIDs += $exclude
                }
                else {
                    $sid = Get-SIDFromUsername -Username $exclude
                    if ($sid) {
                        $excludeSIDs += $sid
                    }
                }
            }
            
            # Add well-known SIDs to exclude
            $excludeSIDs += 'S-1-5-18'  # Local System
            $excludeSIDs += 'S-1-5-19'  # Local Service
            $excludeSIDs += 'S-1-5-20'  # Network Service
            
            $results = @()
            
            foreach ($userProfile in $profiles) {
                $sid = $userProfile.SID
                $username = Get-UsernameFromSID -SID $sid
                
                # Check exclude list
                if ($excludeSIDs -contains $sid) {
                    Write-Verbose "Skipping excluded profile: $username ($sid)"
                    continue
                }
                
                # Check username against exclude list
                $skipProfile = $false
                foreach ($exclude in $ExcludeUsers) {
                    if ($username -like "*$exclude*") {
                        Write-Verbose "Skipping excluded profile by username: $username"
                        $skipProfile = $true
                        break
                    }
                }
                
                if ($skipProfile) {
                    continue
                }
                
                # Calculate inactivity - use Windows Event Log for most accurate local logon data
                $lastUseTime = $null
                $daysInactive = $null
                $source = "Unknown"
                
                # BEST: Check Windows Security Event Log for actual interactive logons (Event ID 4624, LogonType 2/10/11)
                # LogonType 2 = Interactive (console), 10 = RemoteInteractive (RDP), 11 = CachedInteractive
                try {
                    $userSID = $sid  # Use the SID we already have from the profile
                    
                    # Query for recent logon events for this SID
                    $logonEvent = Get-WinEvent -FilterHashtable @{
                        LogName = 'Security'
                        Id = 4624
                    } -MaxEvents 1000 -ErrorAction Stop | Where-Object {
                        $_.Properties[4].Value -eq $userSID -and  # TargetUserSid
                        $_.Properties[8].Value -in @(2, 10, 11)   # LogonType (Interactive, RDP, Cached)
                    } | Select-Object -First 1
                    
                    if ($logonEvent) {
                        $lastUseTime = $logonEvent.TimeCreated
                        $daysInactive = [math]::Round((New-TimeSpan -Start $lastUseTime -End (Get-Date)).TotalDays, 0)
                        $source = "Event Log"
                        Write-Verbose "Profile $username last interactive logon (Event Log): $lastUseTime ($daysInactive days ago)"
                    }
                    else {
                        Write-Verbose "No interactive logon events found for $username in recent event log"
                    }
                }
                catch {
                    Write-Verbose "Could not query event log for $username (insufficient permissions or log not available): $_"
                }
                
                # FALLBACK: Profile folder last write time
                if ($null -eq $lastUseTime -and $userProfile.LocalPath -and (Test-Path $userProfile.LocalPath)) {
                    try {
                        $profileFolder = Get-Item -Path $userProfile.LocalPath -ErrorAction SilentlyContinue
                        if ($profileFolder) {
                            $lastUseTime = $profileFolder.LastWriteTime
                            $daysInactive = [math]::Round((New-TimeSpan -Start $lastUseTime -End (Get-Date)).TotalDays, 0)
                            $source = "Profile Folder"
                            Write-Verbose "Profile $username last activity (folder): $lastUseTime ($daysInactive days ago)"
                        }
                    }
                    catch {
                        Write-Verbose "Could not get folder date for $username : $_"
                    }
                }
                
                # Filter by inactivity threshold
                if ($PSBoundParameters.ContainsKey('InactiveDays')) {
                    if ($null -eq $daysInactive -or $daysInactive -lt $InactiveDays) {
                        Write-Verbose "Skipping profile $username - not inactive enough ($daysInactive days)"
                        continue
                    }
                }
                
                # Get profile size
                $sizeGB = Get-DirectorySize -Path $userProfile.LocalPath
                
                $results += [PSCustomObject]@{
                    PSTypeName    = 'StaleUserProfile'
                    ComputerName  = $ComputerName
                    Username      = $username
                    SID           = $sid
                    ProfilePath   = $userProfile.LocalPath
                    SizeGB        = $sizeGB
                    LastUseTime   = $lastUseTime
                    DaysInactive  = $daysInactive
                    Loaded        = $userProfile.Loaded
                    Status        = 'Found'
                    ErrorMessage  = $null
                }
            }
            
            Write-Verbose "Returning $($results.Count) stale profiles"
            return $results
        }
        catch {
            Write-Error "Failed to query profiles on ${ComputerName}: $_"
            return $null
        }
    }
    
    end {
        Write-Verbose "Completed Get-StaleUserProfiles"
    }
}

<#
.SYNOPSIS
    Removes a stale user profile from a computer.

.DESCRIPTION
    Safely removes a user profile from a local or remote computer with comprehensive
    safety checks including file locks, loaded status, scheduled tasks, and services.
    Includes registry cleanup and detailed logging.

.PARAMETER ComputerName
    The name of the computer to remove the profile from. Defaults to localhost.

.PARAMETER Username
    The username of the profile to remove. Cannot be used with -SID parameter.

.PARAMETER SID
    The SID of the profile to remove. Cannot be used with -Username parameter.

.PARAMETER InactiveDays
    Only remove profiles that have been inactive for at least this many days.

.PARAMETER ExcludeUsers
    Array of usernames or SIDs to exclude from removal.

.PARAMETER LogPath
    Path to the log file. Defaults to .\Remove-StaleProfiles.log

.PARAMETER Force
    Bypasses the mandatory WhatIf on first run.

.PARAMETER WhatIf
    Shows what would happen if the command runs without actually removing anything.

.PARAMETER Confirm
    Prompts for confirmation before removing each profile.

.EXAMPLE
    Remove-StaleUserProfile -Username "DOMAIN\jdoe" -WhatIf
    
    Shows what would happen when removing John Doe's profile.

.EXAMPLE
    Remove-StaleUserProfile -Username "DOMAIN\jdoe" -InactiveDays 90 -Force -LogPath "C:\Logs\ProfileRemoval.log"
    
    Removes John Doe's profile if inactive for 90+ days, with detailed logging.

.EXAMPLE
    Get-StaleUserProfiles -InactiveDays 180 | Remove-StaleUserProfile -Force
    
    Removes all profiles inactive for 180+ days.

.OUTPUTS
    PSCustomObject with removal results including ComputerName, Username, SID, ProfilePath, SizeGB, Status, ErrorMessage.
#>
function Remove-StaleUserProfile {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High', DefaultParameterSetName = 'Username')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $true)]
        [Alias('CN', 'Computer')]
        [string]$ComputerName = 'localhost',
        
        [Parameter(Mandatory = $false, ParameterSetName = 'Username', ValueFromPipelineByPropertyName = $true)]
        [string]$Username,
        
        [Parameter(Mandatory = $false, ParameterSetName = 'SID', ValueFromPipelineByPropertyName = $true)]
        [string]$SID,
        
        [Parameter(Mandatory = $false)]
        [ValidateRange(0, [int]::MaxValue)]
        [int]$InactiveDays,
        
        [Parameter(Mandatory = $false)]
        [string[]]$ExcludeUsers = @('Administrator', 'DefaultAccount', 'Guest', 'WDAGUtilityAccount', 'defaultuser0'),
        
        [Parameter(Mandatory = $false)]
        [string]$LogPath = ".\Remove-StaleProfiles_$(Get-Date -Format 'yyyyMMdd').log",
        
        [Parameter(Mandatory = $false)]
        [switch]$Force
    )
    
    begin {
        Write-Verbose "Starting Remove-StaleUserProfile"
        
        # Initialize logging
        Write-CMTraceLog -Message "======== Profile Removal Session Started ========" -LogPath $LogPath -Severity Info -Component "Session"
        
        # Safety check - require WhatIf or Force on first run
        if (-not $WhatIfPreference -and -not $Force) {
            $message = @"
SAFETY WARNING: You are about to remove user profiles.
This operation cannot be undone. On first run, you must either:
  1. Use -WhatIf to preview changes, or
  2. Use -Force to acknowledge the risk

Example: Remove-StaleUserProfile -Username "DOMAIN\user" -WhatIf
"@
            Write-Warning $message
            Write-CMTraceLog -Message "Removal blocked: -Force or -WhatIf required on first run" -LogPath $LogPath -Severity Warning -Component "Safety"
            throw "Use -WhatIf or -Force parameter. See warning message above."
        }
    }
    
    process {
        try {
            # Resolve SID and Username
            $targetSID = $null
            $targetUsername = $null
            
                if ($PSCmdlet.ParameterSetName -eq 'Username') {
                if ($Username) {
                    $targetUsername = $Username
                    $targetSID = Get-SIDFromUsername -Username $Username
                    if (-not $targetSID) {
                        $errorMsg = "Could not resolve username '$Username' to a SID"
                        Write-Error $errorMsg
                        Write-CMTraceLog -Message $errorMsg -LogPath $LogPath -Severity Error -Component "Resolution"
                        return [PSCustomObject]@{
                            PSTypeName   = 'ProfileRemovalResult'
                            ComputerName = $ComputerName
                            Username     = $Username
                            SID          = $null
                            ProfilePath  = $null
                            SizeGB       = 0
                            Status       = 'Failed'
                            ErrorMessage = $errorMsg
                        }
                    }
                }
            }
            else {
                if ($SID) {
                    $targetSID = $SID
                    $targetUsername = Get-UsernameFromSID -SID $SID
                    if (-not $targetUsername) {
                        Write-Warning "Could not resolve SID '$SID' to a username"
                        $targetUsername = "Unknown ($SID)"
                    }
                }
            }
            
            # If no username or SID provided, this might be from pipeline
            if (-not $targetSID) {
                Write-Error "No valid Username or SID provided"
                return
            }
            
            Write-Verbose "Target Profile - Username: $targetUsername, SID: $targetSID"
            Write-CMTraceLog -Message "Processing profile removal for $targetUsername ($targetSID)" -LogPath $LogPath -Severity Info -Component "Process"
            
            # Build exclude list with SIDs
            $excludeSIDs = @()
            foreach ($exclude in $ExcludeUsers) {
                if ($exclude -match '^S-1-5-') {
                    $excludeSIDs += $exclude
                }
                else {
                    $sid = Get-SIDFromUsername -Username $exclude
                    if ($sid) {
                        $excludeSIDs += $sid
                    }
                }
            }
            
            # Add well-known SIDs to exclude
            $excludeSIDs += 'S-1-5-18'  # Local System
            $excludeSIDs += 'S-1-5-19'  # Local Service
            $excludeSIDs += 'S-1-5-20'  # Network Service
            
            # Check if profile is in exclude list
            if ($excludeSIDs -contains $targetSID) {
                $errorMsg = "Profile $targetUsername is in the exclude list and cannot be removed"
                Write-Error $errorMsg
                Write-CMTraceLog -Message $errorMsg -LogPath $LogPath -Severity Error -Component "ExcludeCheck"
                return [PSCustomObject]@{
                    PSTypeName   = 'ProfileRemovalResult'
                    ComputerName = $ComputerName
                    Username     = $targetUsername
                    SID          = $targetSID
                    ProfilePath  = $null
                    SizeGB       = 0
                    Status       = 'Excluded'
                    ErrorMessage = $errorMsg
                }
            }
            
            # Get the profile from WMI
            Write-Verbose "Querying WMI for profile"
            if ($ComputerName -eq 'localhost' -or $ComputerName -eq $env:COMPUTERNAME) {
                $userProfile = Get-CimInstance -ClassName Win32_UserProfile -Filter "SID = '$targetSID'" -ErrorAction Stop
            }
            else {
                $userProfile = Get-CimInstance -ClassName Win32_UserProfile -ComputerName $ComputerName -Filter "SID = '$targetSID'" -ErrorAction Stop
            }
            
            if (-not $userProfile) {
                $errorMsg = "Profile not found for $targetUsername ($targetSID)"
                Write-Error $errorMsg
                Write-CMTraceLog -Message $errorMsg -LogPath $LogPath -Severity Error -Component "ProfileLookup"
                
                # Check for orphaned folder
                $possiblePaths = @(
                    "C:\Users\$($targetUsername.Split('\')[-1])",
                    "C:\Users\$($targetUsername.Split('\')[-1]).*"
                )
                
                foreach ($path in $possiblePaths) {
                    $orphanedFolders = Get-Item -Path $path -ErrorAction SilentlyContinue
                    if ($orphanedFolders) {
                        foreach ($folder in $orphanedFolders) {
                            Write-Warning "Orphaned profile folder detected: $($folder.FullName)"
                            Write-CMTraceLog -Message "Orphaned folder found but no WMI entry: $($folder.FullName)" -LogPath $LogPath -Severity Warning -Component "OrphanDetection"
                        }
                    }
                }
                
                return [PSCustomObject]@{
                    PSTypeName   = 'ProfileRemovalResult'
                    ComputerName = $ComputerName
                    Username     = $targetUsername
                    SID          = $targetSID
                    ProfilePath  = $null
                    SizeGB       = 0
                    Status       = 'NotFound'
                    ErrorMessage = $errorMsg
                }
            }
            
            $profilePath = $userProfile.LocalPath
            Write-Verbose "Profile found at: $profilePath"
            Write-CMTraceLog -Message "Profile found: $profilePath" -LogPath $LogPath -Severity Info -Component "ProfileLookup"
            
            # SAFETY CHECK 1: Profile is not currently loaded
            if ($userProfile.Loaded) {
                $errorMsg = "Profile is currently loaded and cannot be removed. User may be logged in."
                Write-Error $errorMsg
                Write-CMTraceLog -Message $errorMsg -LogPath $LogPath -Severity Error -Component "LoadedCheck"
                return [PSCustomObject]@{
                    PSTypeName   = 'ProfileRemovalResult'
                    ComputerName = $ComputerName
                    Username     = $targetUsername
                    SID          = $targetSID
                    ProfilePath  = $profilePath
                    SizeGB       = 0
                    Status       = 'Failed'
                    ErrorMessage = $errorMsg
                }
            }
            Write-CMTraceLog -Message " Profile is not loaded" -LogPath $LogPath -Severity Info -Component "LoadedCheck"
            
            # SAFETY CHECK 2: No file locks on NTUSER.DAT
            $ntuserPath = Join-Path -Path $profilePath -ChildPath "NTUSER.DAT"
            if (Test-Path -Path $ntuserPath) {
                if (Test-FileLock -Path $ntuserPath) {
                    $errorMsg = "NTUSER.DAT is locked by another process. Profile may be in use or failed to unload properly."
                    Write-Error $errorMsg
                    Write-CMTraceLog -Message $errorMsg -LogPath $LogPath -Severity Error -Component "FileLockCheck"
                    return [PSCustomObject]@{
                        PSTypeName   = 'ProfileRemovalResult'
                        ComputerName = $ComputerName
                        Username     = $targetUsername
                        SID          = $targetSID
                        ProfilePath  = $profilePath
                        SizeGB       = 0
                        Status       = 'Failed'
                        ErrorMessage = $errorMsg
                    }
                }
                Write-CMTraceLog -Message " NTUSER.DAT is not locked" -LogPath $LogPath -Severity Info -Component "FileLockCheck"
            }
            
            # SAFETY CHECK 3: Verify inactivity threshold
            if ($PSBoundParameters.ContainsKey('InactiveDays')) {
                $lastUseTime = $null
                $daysInactive = $null
                $source = "Unknown"
                
                # BEST: Check Windows Security Event Log for actual interactive logons (Event ID 4624, LogonType 2/10/11)
                try {
                    # Query for recent logon events for this SID
                    $logonEvent = Get-WinEvent -FilterHashtable @{
                        LogName = 'Security'
                        Id = 4624
                    } -MaxEvents 1000 -ErrorAction Stop | Where-Object {
                        $_.Properties[4].Value -eq $targetSID -and  # TargetUserSid
                        $_.Properties[8].Value -in @(2, 10, 11)     # LogonType (Interactive, RDP, Cached)
                    } | Select-Object -First 1
                    
                    if ($logonEvent) {
                        $lastUseTime = $logonEvent.TimeCreated
                        $daysInactive = [math]::Round((New-TimeSpan -Start $lastUseTime -End (Get-Date)).TotalDays, 0)
                        $source = "Event Log"
                        Write-Verbose "Profile last interactive logon (Event Log): $lastUseTime ($daysInactive days ago)"
                        Write-CMTraceLog -Message "Profile last interactive logon (Event Log): $lastUseTime ($daysInactive days ago)" -LogPath $LogPath -Severity Info -Component "InactivityCheck"
                    }
                    else {
                        Write-Verbose "No interactive logon events found in recent event log"
                        Write-CMTraceLog -Message "No interactive logon events found in event log" -LogPath $LogPath -Severity Warning -Component "InactivityCheck"
                    }
                }
                catch {
                    Write-Verbose "Could not query event log (insufficient permissions or log not available): $_"
                    Write-CMTraceLog -Message "Could not query event log: $_" -LogPath $LogPath -Severity Warning -Component "InactivityCheck"
                }
                
                # FALLBACK: Profile folder last write time
                if ($null -eq $lastUseTime -and $profilePath -and (Test-Path $profilePath)) {
                    try {
                        $profileFolder = Get-Item -Path $profilePath -ErrorAction SilentlyContinue
                        if ($profileFolder) {
                            $lastUseTime = $profileFolder.LastWriteTime
                            $daysInactive = [math]::Round((New-TimeSpan -Start $lastUseTime -End (Get-Date)).TotalDays, 0)
                            $source = "Profile Folder"
                            Write-Verbose "Profile last activity (folder): $lastUseTime ($daysInactive days ago)"
                            Write-CMTraceLog -Message "Profile last activity (folder): $lastUseTime ($daysInactive days ago)" -LogPath $LogPath -Severity Info -Component "InactivityCheck"
                        }
                    }
                    catch {
                        Write-Verbose "Could not get folder date: $_"
                    }
                }
                
                # Now check if we meet the threshold
                if ($null -ne $daysInactive) {
                    if ($daysInactive -lt $InactiveDays) {
                        $errorMsg = "Profile has only been inactive for $daysInactive days (threshold: $InactiveDays days) [Source: $source]"
                        Write-Error $errorMsg
                        Write-CMTraceLog -Message $errorMsg -LogPath $LogPath -Severity Warning -Component "InactivityCheck"
                        return [PSCustomObject]@{
                            PSTypeName   = 'ProfileRemovalResult'
                            ComputerName = $ComputerName
                            Username     = $targetUsername
                            SID          = $targetSID
                            ProfilePath  = $profilePath
                            SizeGB       = 0
                            Status       = 'Active'
                            ErrorMessage = $errorMsg
                        }
                    }
                    Write-CMTraceLog -Message "Profile inactive for $daysInactive days (threshold: $InactiveDays) [Source: $source]" -LogPath $LogPath -Severity Info -Component "InactivityCheck"
                }
                else {
                    Write-Verbose "Profile has no valid LastUseTime, treating as never used (allowing removal)"
                    Write-CMTraceLog -Message "Profile has no valid LastUseTime, treating as never used" -LogPath $LogPath -Severity Warning -Component "InactivityCheck"
                }
            }
            
            # SAFETY CHECK 4: Check for scheduled tasks
            Write-Verbose "Checking for scheduled tasks registered under this SID"
            $tasks = Get-ScheduledTaskBySID -SID $targetSID -ComputerName $ComputerName
            if ($tasks.Count -gt 0) {
                $taskNames = ($tasks | ForEach-Object { $_.TaskName }) -join ", "
                $warning = "WARNING: $($tasks.Count) scheduled task(s) registered under this user: $taskNames"
                Write-Warning $warning
                Write-CMTraceLog -Message $warning -LogPath $LogPath -Severity Warning -Component "ScheduledTaskCheck"
            }
            else {
                Write-CMTraceLog -Message " No scheduled tasks found" -LogPath $LogPath -Severity Info -Component "ScheduledTaskCheck"
            }
            
            # SAFETY CHECK 5: Check for services running as this user
            Write-Verbose "Checking for services running as this user"
            $services = Get-ServiceBySID -SID $targetSID -ComputerName $ComputerName
            if ($services.Count -gt 0) {
                $serviceNames = ($services | ForEach-Object { $_.Name }) -join ", "
                $errorMsg = "BLOCKED: $($services.Count) service(s) running as this user: $serviceNames. Cannot remove profile."
                Write-Error $errorMsg
                Write-CMTraceLog -Message $errorMsg -LogPath $LogPath -Severity Error -Component "ServiceCheck"
                return [PSCustomObject]@{
                    PSTypeName   = 'ProfileRemovalResult'
                    ComputerName = $ComputerName
                    Username     = $targetUsername
                    SID          = $targetSID
                    ProfilePath  = $profilePath
                    SizeGB       = 0
                    Status       = 'Failed'
                    ErrorMessage = $errorMsg
                }
            }
            Write-CMTraceLog -Message " No services running as this user" -LogPath $LogPath -Severity Info -Component "ServiceCheck"
            
            # Calculate profile size
            $sizeGB = Get-DirectorySize -Path $profilePath
            Write-CMTraceLog -Message "Profile size: $sizeGB GB" -LogPath $LogPath -Severity Info -Component "SizeCalculation"
            
            # Create registry backup
            if ($PSCmdlet.ShouldProcess($targetUsername, "Backup registry keys")) {
                $backupPath = Join-Path -Path (Split-Path $LogPath) -ChildPath "RegistryBackup_${targetSID}_$(Get-Date -Format 'yyyyMMddHHmmss').json"
                Write-Verbose "Creating registry backup: $backupPath"
                $backupSuccess = Backup-RegistryKeys -SID $targetSID -BackupPath $backupPath
                if ($backupSuccess) {
                    Write-CMTraceLog -Message "Registry backup created: $backupPath" -LogPath $LogPath -Severity Info -Component "RegistryBackup"
                }
                else {
                    Write-CMTraceLog -Message "Failed to create registry backup (non-fatal)" -LogPath $LogPath -Severity Warning -Component "RegistryBackup"
                }
            }
            
            # REMOVAL: Remove the profile via WMI
            if ($PSCmdlet.ShouldProcess("$targetUsername ($profilePath)", "Remove user profile")) {
                try {
                    Write-CMTraceLog -Message "Attempting to remove profile via WMI" -LogPath $LogPath -Severity Info -Component "ProfileRemoval"
                    
                    Remove-CimInstance -InputObject $userProfile -ErrorAction Stop
                    
                    Write-CMTraceLog -Message "Successfully removed profile via WMI" -LogPath $LogPath -Severity Info -Component "ProfileRemoval"
                    
                    # Clean up registry keys
                    Write-Verbose "Cleaning up remaining registry keys"
                    $regResults = Remove-ProfileRegistryKeys -SID $targetSID -LogPath $LogPath -WhatIf:$WhatIfPreference
                    
                    $cleanedKeys = ($regResults | Where-Object { $_.Removed -eq $true }).Count
                    if ($cleanedKeys -gt 0) {
                        Write-CMTraceLog -Message "Cleaned up $cleanedKeys additional registry keys" -LogPath $LogPath -Severity Info -Component "RegistryCleanup"
                    }
                    
                    # Verify profile folder removal
                    Start-Sleep -Seconds 2
                    if (Test-Path -Path $profilePath) {
                        Write-Warning "Profile folder still exists: $profilePath"
                        Write-CMTraceLog -Message "Profile folder still exists after WMI removal: $profilePath" -LogPath $LogPath -Severity Warning -Component "Verification"
                    }
                    
                    Write-CMTraceLog -Message "Profile removal completed successfully for $targetUsername" -LogPath $LogPath -Severity Info -Component "ProfileRemoval"
                    
                    return [PSCustomObject]@{
                        PSTypeName   = 'ProfileRemovalResult'
                        ComputerName = $ComputerName
                        Username     = $targetUsername
                        SID          = $targetSID
                        ProfilePath  = $profilePath
                        SizeGB       = $sizeGB
                        Status       = 'Removed'
                        ErrorMessage = $null
                    }
                }
                catch {
                    $errorMsg = "Failed to remove profile: $_"
                    Write-Error $errorMsg
                    Write-CMTraceLog -Message $errorMsg -LogPath $LogPath -Severity Error -Component "ProfileRemoval"
                    
                    return [PSCustomObject]@{
                        PSTypeName   = 'ProfileRemovalResult'
                        ComputerName = $ComputerName
                        Username     = $targetUsername
                        SID          = $targetSID
                        ProfilePath  = $profilePath
                        SizeGB       = $sizeGB
                        Status       = 'Failed'
                        ErrorMessage = $_.Exception.Message
                    }
                }
            }
            else {
                # WhatIf mode
                Write-CMTraceLog -Message "WhatIf: Would remove profile $targetUsername ($profilePath)" -LogPath $LogPath -Severity Info -Component "WhatIf"
                
                return [PSCustomObject]@{
                    PSTypeName   = 'ProfileRemovalResult'
                    ComputerName = $ComputerName
                    Username     = $targetUsername
                    SID          = $targetSID
                    ProfilePath  = $profilePath
                    SizeGB       = $sizeGB
                    Status       = 'WhatIf'
                    ErrorMessage = $null
                }
            }
        }
        catch {
            $errorMsg = "Unexpected error: $_"
            Write-Error $errorMsg
            Write-CMTraceLog -Message $errorMsg -LogPath $LogPath -Severity Error -Component "Process"
            
            return [PSCustomObject]@{
                PSTypeName   = 'ProfileRemovalResult'
                ComputerName = $ComputerName
                Username     = $targetUsername
                SID          = $targetSID
                ProfilePath  = $null
                SizeGB       = 0
                Status       = 'Failed'
                ErrorMessage = $_.Exception.Message
            }
        }
    }
    
    end {
        Write-CMTraceLog -Message "======== Profile Removal Session Ended ========" -LogPath $LogPath -Severity Info -Component "Session"
        Write-Verbose "Completed Remove-StaleUserProfile"
    }
}

#endregion

# Export module members
Export-ModuleMember -Function @(
    'Get-StaleUserProfiles',
    'Remove-StaleUserProfile'
)

