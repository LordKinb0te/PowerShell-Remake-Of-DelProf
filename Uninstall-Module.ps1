<#
.SYNOPSIS
    Uninstallation script for the Remove-StaleProfiles module.

.DESCRIPTION
    This script removes the Remove-StaleProfiles module from your PowerShell modules directory.

.PARAMETER Scope
    Installation scope to remove from: 'CurrentUser', 'AllUsers', or 'Both'

.PARAMETER KeepLogs
    If specified, log files will not be deleted.

.EXAMPLE
    .\Uninstall-Module.ps1 -Scope CurrentUser
    
    Removes the module from the current user's profile.

.EXAMPLE
    .\Uninstall-Module.ps1 -Scope Both -KeepLogs
    
    Removes the module from both user and system locations but keeps log files.
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory = $false)]
    [ValidateSet('CurrentUser', 'AllUsers', 'Both')]
    [string]$Scope = 'CurrentUser',
    
    [Parameter(Mandatory = $false)]
    [switch]$KeepLogs
)

Write-Host "=== Remove-StaleProfiles Module Uninstallation ===" -ForegroundColor Cyan
Write-Host ""

# Check if running as administrator for AllUsers scope
if ($Scope -eq 'AllUsers' -or $Scope -eq 'Both') {
    $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmin) {
        Write-Error "Removing from AllUsers requires administrator privileges. Please run as administrator or use -Scope CurrentUser"
        exit 1
    }
}

# Remove module from memory first
if (Get-Module -Name Remove-StaleProfiles) {
    Write-Host "Unloading module from memory..."
    Remove-Module -Name Remove-StaleProfiles -Force
    Write-Host "  ✓ Module unloaded" -ForegroundColor Green
}

# Determine paths to remove
$pathsToRemove = @()

if ($Scope -eq 'CurrentUser' -or $Scope -eq 'Both') {
    $userPath = Join-Path $env:USERPROFILE "Documents\PowerShell\Modules\Remove-StaleProfiles"
    if (Test-Path $userPath) {
        $pathsToRemove += $userPath
    }
}

if ($Scope -eq 'AllUsers' -or $Scope -eq 'Both') {
    $systemPath = Join-Path $env:ProgramFiles "PowerShell\Modules\Remove-StaleProfiles"
    if (Test-Path $systemPath) {
        $pathsToRemove += $systemPath
    }
}

if ($pathsToRemove.Count -eq 0) {
    Write-Host "Module not found in specified scope(s)." -ForegroundColor Yellow
    exit 0
}

# Remove module directories
foreach ($path in $pathsToRemove) {
    if ($PSCmdlet.ShouldProcess($path, "Remove module directory")) {
        try {
            Write-Host "Removing: $path"
            Remove-Item -Path $path -Recurse -Force -ErrorAction Stop
            Write-Host "  ✓ Removed successfully" -ForegroundColor Green
        }
        catch {
            Write-Error "Failed to remove $path : $_"
        }
    }
}

# Optionally remove log files
if (-not $KeepLogs) {
    Write-Host ""
    $currentDir = Get-Location
    $logFiles = Get-ChildItem -Path $currentDir -Filter "Remove-StaleProfiles*.log" -ErrorAction SilentlyContinue
    $registryBackups = Get-ChildItem -Path $currentDir -Filter "RegistryBackup_*.json" -ErrorAction SilentlyContinue
    
    $allCleanupFiles = $logFiles + $registryBackups
    
    if ($allCleanupFiles.Count -gt 0) {
        Write-Host "Found $($allCleanupFiles.Count) log/backup file(s) in current directory:"
        foreach ($file in $allCleanupFiles) {
            Write-Host "  - $($file.Name)" -ForegroundColor Gray
        }
        
        if ($PSCmdlet.ShouldProcess("log and backup files", "Remove")) {
            $response = Read-Host "Remove these files? (Y/N)"
            if ($response -eq 'Y' -or $response -eq 'y') {
                foreach ($file in $allCleanupFiles) {
                    try {
                        Remove-Item -Path $file.FullName -Force
                        Write-Host "  ✓ Removed: $($file.Name)" -ForegroundColor Green
                    }
                    catch {
                        Write-Warning "Failed to remove $($file.Name): $_"
                    }
                }
            }
        }
    }
    else {
        Write-Host "No log or backup files found in current directory."
    }
}

Write-Host ""
Write-Host "Uninstallation complete!" -ForegroundColor Green
Write-Host ""

