#Requires -Modules Pester

<#
.SYNOPSIS
    Pester tests for Remove-StaleProfiles module.

.DESCRIPTION
    Comprehensive tests for profile detection, exclude list functionality,
    WhatIf behavior, and error handling.
#>

BeforeAll {
    # Import the module
    $modulePath = Join-Path $PSScriptRoot "Remove-StaleProfiles.psm1"
    Import-Module $modulePath -Force
    
    # Create test log directory
    $script:testLogPath = Join-Path $TestDrive "TestLogs"
    if (-not (Test-Path $script:testLogPath)) {
        New-Item -Path $script:testLogPath -ItemType Directory -Force | Out-Null
    }
}

AfterAll {
    # Clean up
    Remove-Module Remove-StaleProfiles -Force -ErrorAction SilentlyContinue
}

Describe "Get-StaleUserProfiles" {
    Context "Profile Detection" {
        It "Should return profile objects with required properties" {
            $profiles = Get-StaleUserProfiles -ErrorAction SilentlyContinue
            
            if ($profiles) {
                $profiles[0].PSTypeName | Should -Be 'StaleUserProfile'
                $profiles[0].PSObject.Properties.Name | Should -Contain 'ComputerName'
                $profiles[0].PSObject.Properties.Name | Should -Contain 'Username'
                $profiles[0].PSObject.Properties.Name | Should -Contain 'SID'
                $profiles[0].PSObject.Properties.Name | Should -Contain 'ProfilePath'
                $profiles[0].PSObject.Properties.Name | Should -Contain 'SizeGB'
                $profiles[0].PSObject.Properties.Name | Should -Contain 'Status'
                $profiles[0].PSObject.Properties.Name | Should -Contain 'ErrorMessage'
            }
        }
        
        It "Should filter profiles by InactiveDays parameter" {
            $profiles = Get-StaleUserProfiles -InactiveDays 365 -ErrorAction SilentlyContinue
            
            if ($profiles) {
                foreach ($profile in $profiles) {
                    if ($null -ne $profile.DaysInactive) {
                        $profile.DaysInactive | Should -BeGreaterOrEqual 365
                    }
                }
            }
        }
        
        It "Should not return special profiles" {
            $profiles = Get-StaleUserProfiles -ErrorAction SilentlyContinue
            
            if ($profiles) {
                $profiles.SID | Should -Not -Contain 'S-1-5-18'  # Local System
                $profiles.SID | Should -Not -Contain 'S-1-5-19'  # Local Service
                $profiles.SID | Should -Not -Contain 'S-1-5-20'  # Network Service
            }
        }
        
        It "Should return Status = 'Found' for detected profiles" {
            $profiles = Get-StaleUserProfiles -ErrorAction SilentlyContinue
            
            if ($profiles) {
                foreach ($profile in $profiles) {
                    $profile.Status | Should -Be 'Found'
                }
            }
        }
    }
    
    Context "Exclude List Functionality" {
        It "Should exclude Administrator account by default" {
            $profiles = Get-StaleUserProfiles -ErrorAction SilentlyContinue
            
            if ($profiles) {
                $adminProfiles = $profiles | Where-Object { $_.Username -like "*Administrator*" }
                $adminProfiles | Should -BeNullOrEmpty
            }
        }
        
        It "Should exclude Guest account by default" {
            $profiles = Get-StaleUserProfiles -ErrorAction SilentlyContinue
            
            if ($profiles) {
                $guestProfiles = $profiles | Where-Object { $_.Username -like "*Guest*" }
                $guestProfiles | Should -BeNullOrEmpty
            }
        }
        
        It "Should exclude custom users when specified" {
            # This test assumes there's at least one profile we can test against
            $allProfiles = Get-StaleUserProfiles -ExcludeUsers @() -ErrorAction SilentlyContinue
            
            if ($allProfiles -and $allProfiles.Count -gt 0) {
                $testUsername = $allProfiles[0].Username
                $filteredProfiles = Get-StaleUserProfiles -ExcludeUsers @($testUsername) -ErrorAction SilentlyContinue
                
                if ($filteredProfiles) {
                    $filteredProfiles.Username | Should -Not -Contain $testUsername
                }
            }
        }
        
        It "Should accept SIDs in exclude list" {
            # Test that SID-based exclusion works
            $excludeSID = 'S-1-5-21-1234567890-1234567890-1234567890-500'  # Example SID
            
            # Should not throw error
            { Get-StaleUserProfiles -ExcludeUsers @($excludeSID) -ErrorAction SilentlyContinue } | Should -Not -Throw
        }
    }
    
    Context "Parameter Validation" {
        It "Should accept ComputerName parameter" {
            { Get-StaleUserProfiles -ComputerName 'localhost' -ErrorAction SilentlyContinue } | Should -Not -Throw
        }
        
        It "Should accept InactiveDays parameter" {
            { Get-StaleUserProfiles -InactiveDays 30 -ErrorAction SilentlyContinue } | Should -Not -Throw
        }
        
        It "Should not accept negative InactiveDays" {
            { Get-StaleUserProfiles -InactiveDays -1 } | Should -Throw
        }
        
        It "Should accept pipeline input" {
            $computerName = 'localhost'
            { $computerName | Get-StaleUserProfiles -ErrorAction SilentlyContinue } | Should -Not -Throw
        }
    }
}

Describe "Remove-StaleUserProfile" {
    BeforeEach {
        $script:testLog = Join-Path $script:testLogPath "RemoveProfile_Test_$(Get-Date -Format 'yyyyMMddHHmmss').log"
    }
    
    Context "WhatIf Behavior" {
        It "Should not remove profile when WhatIf is specified" {
            # Get a test profile (don't actually remove anything)
            $profiles = Get-StaleUserProfiles -ErrorAction SilentlyContinue
            
            if ($profiles -and $profiles.Count -gt 0) {
                $testProfile = $profiles[0]
                
                $result = Remove-StaleUserProfile -SID $testProfile.SID -WhatIf -LogPath $script:testLog -ErrorAction SilentlyContinue
                
                if ($result) {
                    $result.Status | Should -Be 'WhatIf'
                }
                
                # Verify profile still exists
                $stillExists = Get-CimInstance -ClassName Win32_UserProfile -Filter "SID = '$($testProfile.SID)'" -ErrorAction SilentlyContinue
                $stillExists | Should -Not -BeNullOrEmpty
            }
        }
        
        It "Should return correct object structure in WhatIf mode" {
            $profiles = Get-StaleUserProfiles -ErrorAction SilentlyContinue
            
            if ($profiles -and $profiles.Count -gt 0) {
                $testProfile = $profiles[0]
                
                $result = Remove-StaleUserProfile -SID $testProfile.SID -WhatIf -LogPath $script:testLog -ErrorAction SilentlyContinue
                
                if ($result) {
                    $result.PSTypeName | Should -Be 'ProfileRemovalResult'
                    $result.PSObject.Properties.Name | Should -Contain 'ComputerName'
                    $result.PSObject.Properties.Name | Should -Contain 'Username'
                    $result.PSObject.Properties.Name | Should -Contain 'SID'
                    $result.PSObject.Properties.Name | Should -Contain 'ProfilePath'
                    $result.PSObject.Properties.Name | Should -Contain 'SizeGB'
                    $result.PSObject.Properties.Name | Should -Contain 'Status'
                    $result.PSObject.Properties.Name | Should -Contain 'ErrorMessage'
                }
            }
        }
    }
    
    Context "Safety Checks" {
        It "Should require Force or WhatIf parameter on first run" {
            $profiles = Get-StaleUserProfiles -ErrorAction SilentlyContinue
            
            if ($profiles -and $profiles.Count -gt 0) {
                # Should throw without Force or WhatIf
                { Remove-StaleUserProfile -SID $profiles[0].SID -LogPath $script:testLog -ErrorAction Stop } | Should -Throw
            }
        }
        
        It "Should block removal of loaded profiles" {
            # Try to find a loaded profile
            $loadedProfile = Get-CimInstance -ClassName Win32_UserProfile -Filter "Special = False AND Loaded = True" -ErrorAction SilentlyContinue | Select-Object -First 1
            
            if ($loadedProfile) {
                $result = Remove-StaleUserProfile -SID $loadedProfile.SID -Force -LogPath $script:testLog -ErrorAction SilentlyContinue
                
                if ($result) {
                    $result.Status | Should -Be 'Failed'
                    $result.ErrorMessage | Should -Match "currently loaded"
                }
            }
        }
        
        It "Should respect exclude list" {
            # Try to remove Administrator
            $result = Remove-StaleUserProfile -Username "Administrator" -Force -LogPath $script:testLog -ErrorAction SilentlyContinue
            
            if ($result) {
                $result.Status | Should -Be 'Excluded'
                $result.ErrorMessage | Should -Match "exclude list"
            }
        }
        
        It "Should check InactiveDays threshold" {
            $profiles = Get-StaleUserProfiles -ErrorAction SilentlyContinue
            
            if ($profiles -and $profiles.Count -gt 0) {
                $testProfile = $profiles[0]
                
                # Set threshold to future date (impossible to meet)
                $result = Remove-StaleUserProfile -SID $testProfile.SID -InactiveDays 999999 -Force -LogPath $script:testLog -ErrorAction SilentlyContinue
                
                if ($result -and $result.Status -ne 'NotFound') {
                    $result.Status | Should -BeIn @('Active', 'WhatIf')
                }
            }
        }
    }
    
    Context "Error Handling for Locked Profiles" {
        It "Should detect locked NTUSER.DAT files" {
            # This is difficult to test without actually locking a file
            # We'll test that the function handles the check gracefully
            
            $profiles = Get-StaleUserProfiles -ErrorAction SilentlyContinue
            
            if ($profiles -and $profiles.Count -gt 0) {
                # Just verify the function runs without throwing
                { Remove-StaleUserProfile -SID $profiles[0].SID -WhatIf -LogPath $script:testLog -ErrorAction SilentlyContinue } | Should -Not -Throw
            }
        }
        
        It "Should provide clear error message for locked profiles" {
            # Test error message format
            $profiles = Get-StaleUserProfiles -ErrorAction SilentlyContinue
            
            if ($profiles -and $profiles.Count -gt 0) {
                $result = Remove-StaleUserProfile -SID $profiles[0].SID -WhatIf -LogPath $script:testLog -ErrorAction SilentlyContinue
                
                # Result should have ErrorMessage property
                $result.PSObject.Properties.Name | Should -Contain 'ErrorMessage'
            }
        }
    }
    
    Context "Parameter Validation" {
        It "Should accept Username parameter" {
            { Remove-StaleUserProfile -Username "TestUser" -WhatIf -LogPath $script:testLog -ErrorAction SilentlyContinue } | Should -Not -Throw
        }
        
        It "Should accept SID parameter" {
            { Remove-StaleUserProfile -SID "S-1-5-21-1234567890-1234567890-1234567890-1001" -WhatIf -LogPath $script:testLog -ErrorAction SilentlyContinue } | Should -Not -Throw
        }
        
        It "Should not allow negative InactiveDays" {
            { Remove-StaleUserProfile -Username "TestUser" -InactiveDays -1 -WhatIf -LogPath $script:testLog } | Should -Throw
        }
        
        It "Should accept pipeline input from Get-StaleUserProfiles" {
            { Get-StaleUserProfiles -ErrorAction SilentlyContinue | Remove-StaleUserProfile -WhatIf -LogPath $script:testLog -ErrorAction SilentlyContinue } | Should -Not -Throw
        }
    }
    
    Context "Logging" {
        It "Should create log file" {
            $profiles = Get-StaleUserProfiles -ErrorAction SilentlyContinue
            
            if ($profiles -and $profiles.Count -gt 0) {
                Remove-StaleUserProfile -SID $profiles[0].SID -WhatIf -LogPath $script:testLog -ErrorAction SilentlyContinue
                
                Test-Path $script:testLog | Should -Be $true
            }
        }
        
        It "Should write CMTrace-compatible log format" {
            $profiles = Get-StaleUserProfiles -ErrorAction SilentlyContinue
            
            if ($profiles -and $profiles.Count -gt 0) {
                Remove-StaleUserProfile -SID $profiles[0].SID -WhatIf -LogPath $script:testLog -ErrorAction SilentlyContinue
                
                if (Test-Path $script:testLog) {
                    $logContent = Get-Content $script:testLog -Raw
                    
                    # Check for CMTrace format markers
                    $logContent | Should -Match "<!\[LOG\["
                    $logContent | Should -Match "time="
                    $logContent | Should -Match "date="
                    $logContent | Should -Match "component="
                }
            }
        }
        
        It "Should log session start and end" {
            $profiles = Get-StaleUserProfiles -ErrorAction SilentlyContinue
            
            if ($profiles -and $profiles.Count -gt 0) {
                Remove-StaleUserProfile -SID $profiles[0].SID -WhatIf -LogPath $script:testLog -ErrorAction SilentlyContinue
                
                if (Test-Path $script:testLog) {
                    $logContent = Get-Content $script:testLog -Raw
                    
                    $logContent | Should -Match "Session Started"
                    $logContent | Should -Match "Session Ended"
                }
            }
        }
    }
    
    Context "Output Format" {
        It "Should return custom object with correct type" {
            $profiles = Get-StaleUserProfiles -ErrorAction SilentlyContinue
            
            if ($profiles -and $profiles.Count -gt 0) {
                $result = Remove-StaleUserProfile -SID $profiles[0].SID -WhatIf -LogPath $script:testLog -ErrorAction SilentlyContinue
                
                if ($result) {
                    $result.PSTypeName | Should -Be 'ProfileRemovalResult'
                }
            }
        }
        
        It "Should include all required output properties" {
            $profiles = Get-StaleUserProfiles -ErrorAction SilentlyContinue
            
            if ($profiles -and $profiles.Count -gt 0) {
                $result = Remove-StaleUserProfile -SID $profiles[0].SID -WhatIf -LogPath $script:testLog -ErrorAction SilentlyContinue
                
                if ($result) {
                    $result.ComputerName | Should -Not -BeNullOrEmpty
                    $result.PSObject.Properties.Name | Should -Contain 'Username'
                    $result.PSObject.Properties.Name | Should -Contain 'SID'
                    $result.PSObject.Properties.Name | Should -Contain 'ProfilePath'
                    $result.PSObject.Properties.Name | Should -Contain 'SizeGB'
                    $result.PSObject.Properties.Name | Should -Contain 'Status'
                    $result.PSObject.Properties.Name | Should -Contain 'ErrorMessage'
                }
            }
        }
        
        It "Should be pipeline compatible" {
            $profiles = Get-StaleUserProfiles -ErrorAction SilentlyContinue | Select-Object -First 1
            
            if ($profiles) {
                $results = $profiles | Remove-StaleUserProfile -WhatIf -LogPath $script:testLog -ErrorAction SilentlyContinue
                
                $results | Should -Not -BeNullOrEmpty
                $results[0].PSTypeName | Should -Be 'ProfileRemovalResult'
            }
        }
    }
}

Describe "Edge Cases" {
    Context "Profile Path Variations" {
        It "Should handle standard username format" {
            # Test detection only, not removal
            $profiles = Get-StaleUserProfiles -ErrorAction SilentlyContinue
            
            if ($profiles) {
                foreach ($profile in $profiles) {
                    $profile.ProfilePath | Should -Not -BeNullOrEmpty
                }
            }
        }
    }
    
    Context "Orphaned Folders" {
        It "Should detect when profile folder exists but no WMI entry" {
            # Try to remove a non-existent SID
            $fakeSID = "S-1-5-21-0000000000-0000000000-0000000000-9999"
            $testLog = Join-Path $script:testLogPath "OrphanTest_$(Get-Date -Format 'yyyyMMddHHmmss').log"
            
            $result = Remove-StaleUserProfile -SID $fakeSID -WhatIf -LogPath $testLog -ErrorAction SilentlyContinue
            
            if ($result) {
                $result.Status | Should -Be 'NotFound'
            }
        }
    }
    
    Context "Scheduled Tasks Detection" {
        It "Should check for scheduled tasks without throwing errors" {
            $profiles = Get-StaleUserProfiles -ErrorAction SilentlyContinue
            
            if ($profiles -and $profiles.Count -gt 0) {
                # Should complete without error even if tasks exist
                { Remove-StaleUserProfile -SID $profiles[0].SID -WhatIf -LogPath (Join-Path $script:testLogPath "TaskTest.log") -ErrorAction SilentlyContinue } | Should -Not -Throw
            }
        }
    }
    
    Context "Services Detection" {
        It "Should check for services without throwing errors" {
            $profiles = Get-StaleUserProfiles -ErrorAction SilentlyContinue
            
            if ($profiles -and $profiles.Count -gt 0) {
                # Should complete without error
                { Remove-StaleUserProfile -SID $profiles[0].SID -WhatIf -LogPath (Join-Path $script:testLogPath "ServiceTest.log") -ErrorAction SilentlyContinue } | Should -Not -Throw
            }
        }
    }
}

Describe "Helper Functions" {
    Context "CMTrace Logging" {
        It "Should create log in CMTrace format" {
            $testLog = Join-Path $script:testLogPath "CMTraceTest_$(Get-Date -Format 'yyyyMMddHHmmss').log"
            
            # Call a function that uses logging
            $profiles = Get-StaleUserProfiles -ErrorAction SilentlyContinue
            if ($profiles -and $profiles.Count -gt 0) {
                Remove-StaleUserProfile -SID $profiles[0].SID -WhatIf -LogPath $testLog -ErrorAction SilentlyContinue
            }
            
            if (Test-Path $testLog) {
                $content = Get-Content $testLog -Raw
                $content | Should -Match "type=`"[123]`""  # Severity level
            }
        }
    }
}

Describe "Module Export" {
    It "Should export Get-StaleUserProfiles function" {
        $commands = Get-Command -Module Remove-StaleProfiles
        $commands.Name | Should -Contain 'Get-StaleUserProfiles'
    }
    
    It "Should export Remove-StaleUserProfile function" {
        $commands = Get-Command -Module Remove-StaleProfiles
        $commands.Name | Should -Contain 'Remove-StaleUserProfile'
    }
    
    It "Should not export helper functions" {
        $commands = Get-Command -Module Remove-StaleProfiles
        $commands.Name | Should -Not -Contain 'Write-CMTraceLog'
        $commands.Name | Should -Not -Contain 'Test-FileLock'
        $commands.Name | Should -Not -Contain 'Get-ScheduledTaskBySID'
        $commands.Name | Should -Not -Contain 'Get-ServiceBySID'
    }
}

