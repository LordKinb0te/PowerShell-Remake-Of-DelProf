<#
.SYNOPSIS
    Example usage scenarios for the Remove-StaleProfiles module.

.DESCRIPTION
    This script demonstrates various ways to use the Remove-StaleProfiles module
    for identifying and removing stale user profiles.
#>

# Import the module
Import-Module .\Remove-StaleProfiles.psm1 -Force

#region Basic Examples

# Example 1: View all stale profiles (no changes made)
Write-Host "`n=== Example 1: View All Stale Profiles ===" -ForegroundColor Cyan
Get-StaleUserProfiles | Format-Table ComputerName, Username, SizeGB, DaysInactive, Loaded

# Example 2: View profiles inactive for 90+ days
Write-Host "`n=== Example 2: Profiles Inactive 90+ Days ===" -ForegroundColor Cyan
Get-StaleUserProfiles -InactiveDays 90 | Format-Table Username, DaysInactive, SizeGB

# Example 3: Preview removal (WhatIf mode)
Write-Host "`n=== Example 3: Preview Removal (WhatIf) ===" -ForegroundColor Cyan
$profiles = Get-StaleUserProfiles -InactiveDays 180 | Select-Object -First 1
if ($profiles) {
    Remove-StaleUserProfile -SID $profiles.SID -WhatIf
}

#endregion

#region Advanced Filtering

# Example 4: Find large profiles (over 5GB)
Write-Host "`n=== Example 4: Large Profiles (5GB+) ===" -ForegroundColor Cyan
Get-StaleUserProfiles | Where-Object { $_.SizeGB -gt 5 } | Format-Table Username, SizeGB, DaysInactive

# Example 5: Find profiles inactive for over 1 year
Write-Host "`n=== Example 5: Profiles Inactive Over 1 Year ===" -ForegroundColor Cyan
Get-StaleUserProfiles -InactiveDays 365 | Format-Table Username, LastUseTime, DaysInactive

# Example 6: Exclude specific users
Write-Host "`n=== Example 6: Exclude Specific Users ===" -ForegroundColor Cyan
Get-StaleUserProfiles -InactiveDays 90 -ExcludeUsers "admin", "svcaccount" | Format-Table Username, DaysInactive

#endregion

#region Removal Examples

# Example 7: Remove a specific profile (requires -Force)
Write-Host "`n=== Example 7: Remove Specific Profile ===" -ForegroundColor Cyan
# Uncomment to run - this will actually remove a profile!
# Remove-StaleUserProfile -Username "DOMAIN\testuser" -Force -LogPath ".\ProfileRemoval.log"

# Example 8: Remove profile with inactivity check
Write-Host "`n=== Example 8: Remove if Inactive 180+ Days ===" -ForegroundColor Cyan
# Uncomment to run
# Remove-StaleUserProfile -Username "DOMAIN\testuser" -InactiveDays 180 -Force

# Example 9: Pipeline removal of multiple profiles
Write-Host "`n=== Example 9: Pipeline Removal (Commented) ===" -ForegroundColor Cyan
# Uncomment to run - this will remove ALL profiles meeting criteria!
# Get-StaleUserProfiles -InactiveDays 365 | 
#     Where-Object { $_.SizeGB -gt 0 } |
#     Remove-StaleUserProfile -Force -LogPath ".\BulkRemoval.log"

#endregion

#region Reporting

# Example 10: Generate space recovery report
Write-Host "`n=== Example 10: Space Recovery Report ===" -ForegroundColor Cyan
$staleProfiles = Get-StaleUserProfiles -InactiveDays 180
$totalSpaceGB = ($staleProfiles | Measure-Object -Property SizeGB -Sum).Sum
$report = [PSCustomObject]@{
    TotalProfiles      = $staleProfiles.Count
    TotalSpaceGB       = [math]::Round($totalSpaceGB, 2)
    AverageProfileSize = [math]::Round($totalSpaceGB / $staleProfiles.Count, 2)
}
$report | Format-List

# Example 11: Export to CSV for review
Write-Host "`n=== Example 11: Export to CSV ===" -ForegroundColor Cyan
Get-StaleUserProfiles -InactiveDays 90 | 
    Export-Csv -Path ".\StaleProfiles_Report_$(Get-Date -Format 'yyyyMMdd').csv" -NoTypeInformation
Write-Host "Report exported to: .\StaleProfiles_Report_$(Get-Date -Format 'yyyyMMdd').csv"

# Example 12: Group by inactivity ranges
Write-Host "`n=== Example 12: Group by Inactivity Ranges ===" -ForegroundColor Cyan
Get-StaleUserProfiles | 
    Group-Object {
        if ($_.DaysInactive -lt 90) { "0-89 days" }
        elseif ($_.DaysInactive -lt 180) { "90-179 days" }
        elseif ($_.DaysInactive -lt 365) { "180-364 days" }
        else { "365+ days" }
    } |
    Select-Object Name, Count |
    Format-Table -AutoSize

#endregion

#region Error Handling

# Example 13: Handle errors gracefully
Write-Host "`n=== Example 13: Error Handling ===" -ForegroundColor Cyan
$result = Remove-StaleUserProfile -Username "NonExistentUser" -WhatIf -ErrorAction SilentlyContinue
if ($result) {
    if ($result.Status -eq 'Failed' -or $result.Status -eq 'NotFound') {
        Write-Warning "Removal failed: $($result.ErrorMessage)"
    }
    else {
        Write-Host "Status: $($result.Status)" -ForegroundColor Green
    }
}

# Example 14: Try-catch wrapper for production
Write-Host "`n=== Example 14: Production Error Handling ===" -ForegroundColor Cyan
try {
    $profiles = Get-StaleUserProfiles -InactiveDays 365 -ErrorAction Stop
    Write-Host "Found $($profiles.Count) profiles to potentially remove"
    
    # Uncomment to proceed with removal
    # foreach ($profile in $profiles) {
    #     try {
    #         $result = Remove-StaleUserProfile -SID $profile.SID -Force -ErrorAction Stop
    #         Write-Host "✓ Removed: $($profile.Username)" -ForegroundColor Green
    #     }
    #     catch {
    #         Write-Warning "✗ Failed to remove $($profile.Username): $_"
    #     }
    # }
}
catch {
    Write-Error "Failed to query profiles: $_"
}

#endregion

#region Remote Computer Examples

# Example 15: Query remote computer
Write-Host "`n=== Example 15: Remote Computer Query ===" -ForegroundColor Cyan
# Uncomment and replace SERVER01 with actual server name
# Get-StaleUserProfiles -ComputerName SERVER01 -InactiveDays 180 | Format-Table

# Example 16: Multiple remote computers
Write-Host "`n=== Example 16: Multiple Remote Computers ===" -ForegroundColor Cyan
# Uncomment to run
# $servers = "SERVER01", "SERVER02", "SERVER03"
# $allResults = foreach ($server in $servers) {
#     Write-Host "Querying $server..."
#     Get-StaleUserProfiles -ComputerName $server -InactiveDays 365
# }
# $allResults | Export-Csv -Path ".\AllServers_StaleProfiles.csv" -NoTypeInformation

#endregion

#region Scheduled Task Integration

# Example 17: Create a scheduled cleanup script
Write-Host "`n=== Example 17: Scheduled Cleanup Script Template ===" -ForegroundColor Cyan
$scheduledScriptTemplate = @'
# Scheduled-ProfileCleanup.ps1
# Run this script on a schedule to automatically clean up stale profiles

Import-Module Remove-StaleProfiles

$logPath = "C:\Logs\ScheduledProfileCleanup_$(Get-Date -Format 'yyyyMMdd').log"
$inactiveDays = 365  # 1 year threshold
$excludeUsers = @("admin", "svcbackup", "svcmonitoring")

try {
    # Get stale profiles
    $profiles = Get-StaleUserProfiles -InactiveDays $inactiveDays -ExcludeUsers $excludeUsers
    
    if ($profiles.Count -eq 0) {
        Write-Host "No stale profiles found."
        exit 0
    }
    
    Write-Host "Found $($profiles.Count) stale profiles"
    
    # Remove each profile
    $results = $profiles | Remove-StaleUserProfile -Force -LogPath $logPath
    
    # Count successes and failures
    $removed = ($results | Where-Object { $_.Status -eq 'Removed' }).Count
    $failed = ($results | Where-Object { $_.Status -eq 'Failed' }).Count
    
    Write-Host "Removed: $removed, Failed: $failed"
    
    # Export results
    $results | Export-Csv -Path "C:\Logs\ProfileRemovalResults_$(Get-Date -Format 'yyyyMMdd').csv" -NoTypeInformation
}
catch {
    Write-Error "Scheduled cleanup failed: $_"
    exit 1
}
'@

Write-Host $scheduledScriptTemplate -ForegroundColor Gray

#endregion

#region Validation and Pre-Check

# Example 18: Pre-removal validation
Write-Host "`n=== Example 18: Pre-Removal Validation ===" -ForegroundColor Cyan
$profiles = Get-StaleUserProfiles -InactiveDays 180
foreach ($profile in $profiles | Select-Object -First 3) {
    Write-Host "`nProfile: $($profile.Username)" -ForegroundColor Yellow
    Write-Host "  SID: $($profile.SID)"
    Write-Host "  Path: $($profile.ProfilePath)"
    Write-Host "  Size: $($profile.SizeGB) GB"
    Write-Host "  Inactive: $($profile.DaysInactive) days"
    Write-Host "  Loaded: $($profile.Loaded)"
    
    if ($profile.Loaded) {
        Write-Host " WARNING: Profile is currently loaded!" -ForegroundColor Red
    }
}

# Example 19: Check for profiles with scheduled tasks or services
Write-Host "`n=== Example 19: Check for Dependencies ===" -ForegroundColor Cyan
# This example shows how to check for potential issues before removal
$profile = Get-StaleUserProfiles | Select-Object -First 1
if ($profile) {
    Write-Host "Testing removal of: $($profile.Username)"
    $result = Remove-StaleUserProfile -SID $profile.SID -WhatIf
    if ($result.Status -eq 'Failed' -and $result.ErrorMessage -match "service") {
        Write-Warning "Profile has services running - cannot remove safely"
    }
}

#endregion

#region Logging Examples

# Example 20: Review logs
Write-Host "`n=== Example 20: Review Recent Logs ===" -ForegroundColor Cyan
$logFile = ".\Remove-StaleProfiles_$(Get-Date -Format 'yyyyMMdd').log"
if (Test-Path $logFile) {
    Write-Host "Recent log entries:" -ForegroundColor Cyan
    Get-Content $logFile -Tail 5 | ForEach-Object {
        if ($_ -match "type=`"3`"") {
            Write-Host $_ -ForegroundColor Red
        }
        elseif ($_ -match "type=`"2`"") {
            Write-Host $_ -ForegroundColor Yellow
        }
        else {
            Write-Host $_ -ForegroundColor Gray
        }
    }
}
else {
    Write-Host "No log file found for today. Run a removal command to create one."
}

#endregion

Write-Host "`n=== Examples Complete ===" -ForegroundColor Green
Write-Host "Remember to use -WhatIf before making any changes!" -ForegroundColor Yellow
Write-Host "For help: Get-Help Remove-StaleUserProfile -Full" -ForegroundColor Cyan

