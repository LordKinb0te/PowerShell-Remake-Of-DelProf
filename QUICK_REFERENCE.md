# Remove-StaleProfiles - Quick Reference Guide

## Installation

```powershell
# Install for current user (no admin required)
.\Install-Module.ps1 -Scope CurrentUser

# Install system-wide (requires admin)
.\Install-Module.ps1 -Scope AllUsers

# Install and run tests
.\Install-Module.ps1 -Scope CurrentUser -RunTests
```

## Basic Commands

### View Stale Profiles

```powershell
# View all profiles
Get-StaleUserProfiles

# View profiles inactive 90+ days
Get-StaleUserProfiles -InactiveDays 90

# View profiles with specific exclusions
Get-StaleUserProfiles -InactiveDays 180 -ExcludeUsers "admin", "service"
```

### Remove Profiles

```powershell
# ALWAYS preview first with -WhatIf
Remove-StaleUserProfile -Username "DOMAIN\user" -WhatIf

# Remove by username
Remove-StaleUserProfile -Username "DOMAIN\user" -Force

# Remove by SID
Remove-StaleUserProfile -SID "S-1-5-21-..." -Force

# Remove with inactivity check
Remove-StaleUserProfile -Username "DOMAIN\user" -InactiveDays 180 -Force

# Custom log path
Remove-StaleUserProfile -Username "DOMAIN\user" -Force -LogPath "C:\Logs\cleanup.log"
```

### Pipeline Operations

```powershell
# Find and preview removal
Get-StaleUserProfiles -InactiveDays 365 | Remove-StaleUserProfile -WhatIf

# Bulk removal (be careful!)
Get-StaleUserProfiles -InactiveDays 365 | Remove-StaleUserProfile -Force
```

## Safety Checks

The module automatically checks:
-  Profile not currently loaded
-  NTUSER.DAT not locked
-  Not in exclude list
-  Meets inactivity threshold
-  No services running as user (blocks removal)
-  Scheduled tasks (warns but allows)

## Common Parameters

| Parameter | Type | Description | Default |
|-----------|------|-------------|---------|
| `-ComputerName` | String | Target computer | localhost |
| `-Username` | String | Username to remove | - |
| `-SID` | String | SID to remove | - |
| `-InactiveDays` | Int | Inactivity threshold | - |
| `-ExcludeUsers` | String[] | Users to exclude | Admin accounts |
| `-LogPath` | String | Log file path | Current dir |
| `-Force` | Switch | Skip safety prompt | - |
| `-WhatIf` | Switch | Preview only | - |

## Output Properties

**Get-StaleUserProfiles:**
- ComputerName
- Username
- SID
- ProfilePath
- SizeGB
- LastUseTime
- DaysInactive
- Loaded
- Status (Found)

**Remove-StaleUserProfile:**
- ComputerName
- Username
- SID
- ProfilePath
- SizeGB
- Status (Removed/Failed/WhatIf/Excluded/NotFound/Active)
- ErrorMessage

## Status Values

| Status | Meaning |
|--------|---------|
| `Removed` | Successfully removed |
| `Failed` | Removal failed |
| `WhatIf` | Preview mode (no changes) |
| `Excluded` | In exclude list |
| `NotFound` | Profile doesn't exist |
| `Active` | Below inactivity threshold |
| `Found` | Profile detected (Get command) |

## Registry Locations Cleaned

- `HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\<SID>`
- `HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileGuid\<SID>`
- `HKLM:\SOFTWARE\Microsoft\IdentityStore\Cache\<SID>`
- `HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Installer\UserData\<SID>`

*Registry keys are automatically backed up to JSON before removal.*

## Common Scenarios

### Monthly Cleanup
```powershell
Get-StaleUserProfiles -InactiveDays 365 |
    Remove-StaleUserProfile -Force -LogPath "C:\Logs\MonthlyCleanup.log"
```

### Space Recovery Report
```powershell
$profiles = Get-StaleUserProfiles -InactiveDays 180
$totalGB = ($profiles | Measure-Object -Property SizeGB -Sum).Sum
Write-Host "Can recover: $totalGB GB from $($profiles.Count) profiles"
```

### Export for Review
```powershell
Get-StaleUserProfiles -InactiveDays 90 |
    Export-Csv -Path ".\StaleProfiles.csv" -NoTypeInformation
```

### Remote Servers
```powershell
$servers = "SERVER01", "SERVER02"
$results = foreach ($server in $servers) {
    Get-StaleUserProfiles -ComputerName $server -InactiveDays 365
}
$results | Export-Csv -Path ".\AllServers.csv"
```

## Error Handling

### Common Errors

**"Use -WhatIf or -Force parameter"**
- Add `-Force` or `-WhatIf` to command

**"Profile is currently loaded"**
- User is logged in - have them log out

**"NTUSER.DAT is locked"**
- Profile didn't unload properly - it's borked! just restart computer

**"Services running as this user"**
- Change service account before removal

## Logging

Logs are in CMTrace format:
```
<![LOG[Message]LOG]!><time="14:30:15.123+000" date="11-09-2025" 
component="Component" context="" type="1" thread="1234" file="">
```

View with:
- CMTrace.exe
- OneTrace (Windows 10/11)
- Any text editor

**Severity Levels:**
- Type 1 = Info (normal)
- Type 2 = Warning (non-fatal)
- Type 3 = Error (failure)

## Best Practices

1.  Always use `-WhatIf` first
2.  Check logs after operations
3.  Use inactivity thresholds (180+ days recommended)
4.  Maintain exclude lists
5.  Test on non-production first
6.  Review space savings before bulk removal
7.  Schedule cleanup during maintenance windows

## Getting Help

```powershell
# Command help
Get-Help Get-StaleUserProfiles -Full
Get-Help Remove-StaleUserProfile -Full

# Examples
Get-Help Remove-StaleUserProfile -Examples

# View examples file
Get-Content .\Examples.ps1
```

## Testing

```powershell
# Run all tests
Invoke-Pester -Path .\Remove-StaleProfiles.Tests.ps1

# Run specific test
Invoke-Pester -Path .\Remove-StaleProfiles.Tests.ps1 -TagFilter "WhatIf"
```

## Uninstallation

```powershell
# Remove from current user
.\Uninstall-Module.ps1 -Scope CurrentUser

# Remove from system (requires admin)
.\Uninstall-Module.ps1 -Scope AllUsers

# Remove but keep logs
.\Uninstall-Module.ps1 -Scope CurrentUser -KeepLogs
```

## Files Included

- `Remove-StaleProfiles.psm1` - Main module
- `Remove-StaleProfiles.psd1` - Module manifest
- `Remove-StaleProfiles.Tests.ps1` - Pester tests
- `README.md` - Full documentation
- `QUICK_REFERENCE.md` - This file
- `Examples.ps1` - Usage examples
- `Install-Module.ps1` - Installation script
- `Uninstall-Module.ps1` - Uninstallation script

## Requirements

- PowerShell 5.1+
- Administrator privileges
- Windows OS
- Pester 5.0+ (for testing)

---

**WARNING: Profile removal cannot be undone. Always preview with -WhatIf first!**

