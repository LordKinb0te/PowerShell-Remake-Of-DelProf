<#
.SYNOPSIS
    Installation script for the Remove-StaleProfiles module.

.DESCRIPTION
    This script helps install the Remove-StaleProfiles module to your PowerShell modules directory
    and optionally runs tests to verify functionality.

.PARAMETER Scope
    Install scope: 'CurrentUser' or 'AllUsers'
    CurrentUser: Installs to user profile (no admin required)
    AllUsers: Installs system-wide (requires admin)

.PARAMETER RunTests
    Run Pester tests after installation to verify functionality.

.EXAMPLE
    .\Install-Module.ps1 -Scope CurrentUser
    
    Installs the module for the current user.

.EXAMPLE
    .\Install-Module.ps1 -Scope AllUsers -RunTests
    
    Installs the module system-wide and runs tests (requires admin).
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [ValidateSet('CurrentUser', 'AllUsers')]
    [string]$Scope = 'CurrentUser',
    
    [Parameter(Mandatory = $false)]
    [switch]$RunTests
)

# Check if running as administrator for AllUsers scope
if ($Scope -eq 'AllUsers') {
    $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmin) {
        Write-Error "Installing for AllUsers requires administrator privileges. Please run as administrator or use -Scope CurrentUser"
        exit 1
    }
}

Write-Host "=== Remove-StaleProfiles Module Installation ===" -ForegroundColor Cyan
Write-Host ""

# Determine installation path
if ($Scope -eq 'CurrentUser') {
    $modulePath = Join-Path $env:USERPROFILE "Documents\PowerShell\Modules\Remove-StaleProfiles"
    Write-Host "Installing to user profile: $modulePath" -ForegroundColor Green
}
else {
    $modulePath = Join-Path $env:ProgramFiles "PowerShell\Modules\Remove-StaleProfiles"
    Write-Host "Installing system-wide: $modulePath" -ForegroundColor Green
}

# Create module directory
try {
    if (-not (Test-Path $modulePath)) {
        Write-Host "Creating module directory..."
        New-Item -Path $modulePath -ItemType Directory -Force | Out-Null
    }
    else {
        Write-Host "Module directory already exists. Updating..."
    }
    
    # Copy module files
    Write-Host "Copying module files..."
    $filesToCopy = @(
        "Remove-StaleProfiles.psm1",
        "Remove-StaleProfiles.psd1",
        "Remove-StaleProfiles.Tests.ps1",
        "README.md",
        "Examples.ps1"
    )
    
    foreach ($file in $filesToCopy) {
        if (Test-Path $file) {
            Copy-Item -Path $file -Destination $modulePath -Force
            Write-Host "  ✓ Copied: $file" -ForegroundColor Green
        }
        else {
            Write-Warning "  ⚠ File not found: $file"
        }
    }
    
    Write-Host ""
    Write-Host "Installation complete!" -ForegroundColor Green
    
    # Verify installation
    Write-Host ""
    Write-Host "Verifying installation..." -ForegroundColor Cyan
    
    # Remove old module if loaded
    if (Get-Module -Name Remove-StaleProfiles) {
        Remove-Module -Name Remove-StaleProfiles -Force
    }
    
    # Try to import the module
    Import-Module Remove-StaleProfiles -Force -ErrorAction Stop
    
    $commands = Get-Command -Module Remove-StaleProfiles
    Write-Host "  ✓ Module imported successfully" -ForegroundColor Green
    Write-Host "  ✓ Available commands:" -ForegroundColor Green
    foreach ($cmd in $commands) {
        Write-Host "    - $($cmd.Name)" -ForegroundColor Gray
    }
    
    # Run tests if requested
    if ($RunTests) {
        Write-Host ""
        Write-Host "Running Pester tests..." -ForegroundColor Cyan
        
        # Check if Pester is installed
        if (-not (Get-Module -ListAvailable -Name Pester)) {
            Write-Host "Pester not found. Installing..."
            Install-Module -Name Pester -Force -SkipPublisherCheck -Scope $Scope
        }
        
        $testFile = Join-Path $modulePath "Remove-StaleProfiles.Tests.ps1"
        if (Test-Path $testFile) {
            $testResults = Invoke-Pester -Path $testFile -PassThru
            
            Write-Host ""
            if ($testResults.FailedCount -eq 0) {
                Write-Host "✓ All tests passed!" -ForegroundColor Green
            }
            else {
                Write-Warning "⚠ Some tests failed. Review the output above for details."
            }
        }
        else {
            Write-Warning "Test file not found: $testFile"
        }
    }
    
    # Display usage information
    Write-Host ""
    Write-Host "=== Quick Start ===" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "1. View all stale profiles:" -ForegroundColor Yellow
    Write-Host "   Get-StaleUserProfiles" -ForegroundColor Gray
    Write-Host ""
    Write-Host "2. View profiles inactive for 90+ days:" -ForegroundColor Yellow
    Write-Host "   Get-StaleUserProfiles -InactiveDays 90" -ForegroundColor Gray
    Write-Host ""
    Write-Host "3. Preview removal (WhatIf mode):" -ForegroundColor Yellow
    Write-Host "   Remove-StaleUserProfile -Username 'DOMAIN\user' -WhatIf" -ForegroundColor Gray
    Write-Host ""
    Write-Host "4. Remove a profile:" -ForegroundColor Yellow
    Write-Host "   Remove-StaleUserProfile -Username 'DOMAIN\user' -Force" -ForegroundColor Gray
    Write-Host ""
    Write-Host "5. Get help:" -ForegroundColor Yellow
    Write-Host "   Get-Help Remove-StaleUserProfile -Full" -ForegroundColor Gray
    Write-Host ""
    Write-Host "For more examples, see: $modulePath\Examples.ps1" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "⚠ IMPORTANT: Always use -WhatIf to preview changes before removal!" -ForegroundColor Yellow
}
catch {
    Write-Error "Installation failed: $_"
    exit 1
}

