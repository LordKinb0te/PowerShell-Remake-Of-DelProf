@{
    # Script module or binary module file associated with this manifest.
    RootModule = 'Remove-StaleProfiles.psm1'
    
    # Version number of this module.
    ModuleVersion = '1.0.0'
    
    # ID used to uniquely identify this module
    GUID = 'a1b2c3d4-e5f6-7890-abcd-ef1234567890'
    
    # Author of this module
    Author = 'PowerShell Profile Management'
    
    # Company or vendor of this module
    CompanyName = 'Unknown'
    
    # Copyright statement for this module
    Copyright = '(c) 2025. All rights reserved.'
    
    # Description of the functionality provided by this module
    Description = 'PowerShell module for safely identifying and removing stale user profiles with comprehensive safety checks, logging, and registry cleanup.'
    
    # Minimum version of the Windows PowerShell engine required by this module
    PowerShellVersion = '5.1'
    
    # Modules that must be imported into the global environment prior to importing this module
    RequiredModules = @()
    
    # Assemblies that must be loaded prior to importing this module
    RequiredAssemblies = @()
    
    # Script files (.ps1) that are run in the caller's environment prior to importing this module.
    ScriptsToProcess = @()
    
    # Type files (.ps1xml) to be loaded when importing this module
    TypesToProcess = @()
    
    # Format files (.ps1xml) to be loaded when importing this module
    FormatsToProcess = @()
    
    # Functions to export from this module
    FunctionsToExport = @(
        'Get-StaleUserProfiles',
        'Remove-StaleUserProfile'
    )
    
    # Cmdlets to export from this module
    CmdletsToExport = @()
    
    # Variables to export from this module
    VariablesToExport = @()
    
    # Aliases to export from this module
    AliasesToExport = @()
    
    # List of all modules packaged with this module
    ModuleList = @()
    
    # List of all files packaged with this module
    FileList = @(
        'Remove-StaleProfiles.psm1',
        'Remove-StaleProfiles.psd1',
        'Remove-StaleProfiles.Tests.ps1',
        'README.md',
        'DEPLOYMENT_GUIDE.md',
        'GETTING_STARTED.md',
        'QUICK_REFERENCE.md',
        'PROJECT_SUMMARY.md',
        'Examples.ps1',
        'ProfileCleanup-GPO.ps1',
        'QuickCleanup.ps1',
        'Install-Module.ps1',
        'Uninstall-Module.ps1'
    )
    
    # Private data to pass to the module specified in RootModule/ModuleToProcess
    PrivateData = @{
        PSData = @{
            # Tags applied to this module. These help with module discovery in online galleries.
            Tags = @('Profile', 'UserProfile', 'Cleanup', 'Administration', 'Windows', 'WMI', 'Registry')
            
            # A URL to the license for this module.
            LicenseUri = ''
            
            # A URL to the main website for this project.
            ProjectUri = ''
            
            # A URL to an icon representing this module.
            IconUri = ''
            
            # ReleaseNotes of this module
            ReleaseNotes = @'
Version 1.0.0 (November 2025)
- Initial release
- Get-StaleUserProfiles function for querying stale profiles
- Remove-StaleUserProfile function for safe profile removal
- Comprehensive safety checks (loaded status, file locks, scheduled tasks, services)
- CMTrace-compatible logging with accurate event log and folder date detection
- Registry cleanup in multiple locations
- WhatIf support
- Pipeline compatibility
- Exclude list functionality
- Inactivity threshold filtering
- Enterprise deployment scripts for GPO and Quick Assist workflows
- Comprehensive documentation and examples
'@
        }
    }
    
    # HelpInfo URI of this module
    HelpInfoURI = ''
    
    # Default prefix for commands exported from this module. Override the default prefix using Import-Module -Prefix.
    DefaultCommandPrefix = ''
}

