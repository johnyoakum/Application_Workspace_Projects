<#
    .SYNOPSIS
        Reads all shortcuts (.lnk and .url) from the Start Menu, resolves their targets,
        and extracts arguments and icon locations, with URL normalization.

    .DESCRIPTION
        This script enumerates shortcuts found in both the All Users Start Menu and
        the Current User Start Menu. It handles two types of shortcuts:
        - .lnk (Windows Shortcuts): Retrieves TargetPath, Arguments, and IconLocation
          using WScript.Shell.
        - .url (Internet Shortcuts): Parses the .url file content to extract the URL,
          and IconFile/IconIndex for IconLocation.
        - It can also resolve .lnk files that point to .url files, replacing the .lnk's
          target with the actual web URL.
        - Automatically cleans up URLs by removing excessive forward slashes
          (e.g., // in paths) to normalize them.
        - The Get-ResolvedIconFilePath function determines the effective path for icon extraction.
        - The Get-IconAsBase64 function properly returns only the Base64 string.
        - The output now includes both the original RawIconLocation and the ResolvedIconPath.

    .PARAMETER CreateEntitlements
        A switch parameter. If present, the script will create a context for all users and devices and then add an
        entitlement to that context to the package.

    .PARAMETER CreateDesktopIcons
        A switch parameter. If present, the script will create desktop icons during the entitlement of a package

    .PARAMETER CreateStartMenuIcons
        A switch parameter. If present, the script will create start menu icons during the entitlement of a package

    .NOTES
        Author: John Yoakum
        Date: July 7, 2025
        Version: 1.4 - Enhanced icon extraction debugging and error handling.

        Requires PowerShell 3.0 or later.
        Runs best with Administrator privileges to access all Start Menu paths.
#>
param (
    [switch]$CreateEntitlements = $false,
    [switch]$CreateDesktopIcons = $false,
    [switch]$CreateStartMenuIcons = $false
)

Add-Type -AssemblyName System.Drawing

Function Get-Shortcuts {
    $ExcludeApps = @(
        "Microsoft Edge",
        "Application", # If 'Microsoft Edge' or other apps are still grouped as 'Application'
        "OneDrive",
        "OneDrive for Business",
        "Skype for Business",
        "Skype for Business Recording Manager",
        "Application Workspace",
        "Visual Studio Installer",
        "Wordpad",
        "Windows Media Player Legacy"
    )

    # Helper function to normalize URLs (remove extra slashes in path)
    function Normalize-UrlPath {
        param (
            [string]$Url
        )
        if ([string]::IsNullOrWhiteSpace($Url)) {
            return $Url
        }
        # Replaces // with / unless it's part of http:// or https://
        return $Url -replace '(?<!:)/{2,}', '/'
    }

    # Function to get .LNK (Windows Shortcut) details
    function Get-LnkShortcutInfo {
        param (
            [string]$Path
        )

        try {
            $shell = New-Object -ComObject WScript.Shell
            $shortcut = $shell.CreateShortcut($Path)

            $targetPath = $shortcut.TargetPath
            $arguments = $shortcut.Arguments
            $iconLocation = $shortcut.IconLocation # This is the raw IconLocation from the LNK

            [System.Runtime.InteropServices.Marshal]::ReleaseComObject($shortcut) | Out-Null
            [System.Runtime.InteropServices.Marshal]::ReleaseComObject($shell) | Out-Null

            # --- NEW LOGIC: Check if LNK target is a .URL file and resolve it ---
            if (-not ([string]::IsNullOrWhiteSpace($targetPath)) -and `
                $targetPath.ToLower().EndsWith(".url") -and `
                (Test-Path -Path $targetPath -PathType Leaf) # Ensure it's an existing file
               ) {
                Write-Verbose "LNK shortcut '$Path' points to a URL file: '$targetPath'. Resolving..."
                $urlInfo = Get-UrlShortcutInfo -Path $targetPath # Recursively call the URL parser
                if ($urlInfo) {
                    # Normalize the URL path here
                    $resolvedTargetPath = Normalize-UrlPath -Url $urlInfo.TargetPath
                    $resolvedArguments = "" # LNK pointing to URL doesn't have separate arguments for the URL

                    # Prefer the LNK's iconLocation, but fall back to the URL's iconLocation if LNK's is empty or generic
                    $resolvedIconLocation = $iconLocation
                    if ([string]::IsNullOrWhiteSpace($resolvedIconLocation) -or ($resolvedIconLocation -match "^%SystemRoot%\\System32\\SHELL32\.dll,") -or ($resolvedIconLocation -match "^\s*,\s*\d+\s*$")) {
                        $resolvedIconLocation = $urlInfo.IconLocation
                    }

                    return [PSCustomObject]@{
                        Type         = "LNK_RESOLVED_URL" # Indicates an LNK whose target was resolved to a URL
                        TargetPath   = $resolvedTargetPath
                        Arguments    = $resolvedArguments
                        IconLocation = $resolvedIconLocation
                    }
                }
            }
            # Original LNK path
            return [PSCustomObject]@{
                Type         = "LNK"
                TargetPath   = $targetPath
                Arguments    = $arguments
                IconLocation = $iconLocation
            }
        }
        catch {
            Write-Warning "Failed to get LNK shortcut info for '$Path'. Error: $($_.Exception.Message)"
            return $null
        }
    }

    # Function to get .URL (Internet Shortcut) details
    function Get-UrlShortcutInfo {
        param (
            [string]$Path
        )

        try {
            # Read as single string for regex, handling potential encoding issues
            $content = Get-Content -Path $Path -ErrorAction Stop -Raw -Encoding Default

            # Initialize variables to empty string to prevent null issues
            $url = ""
            $iconFile = ""
            $iconIndex = ""

            # Safely extract URL using regex (case-insensitive, multiline)
            $urlMatch = [regex]::Match($content, "(?mi)^URL=(.*)")
            if ($urlMatch.Success) {
                $url = $urlMatch.Groups[1].Value.Trim()
            }
        
            # Safely extract IconFile using regex
            $iconFileMatch = [regex]::Match($content, "(?mi)^IconFile=(.*)")
            if ($iconFileMatch.Success) {
                $iconFile = $iconFileMatch.Groups[1].Value.Trim()
            }

            # Safely extract IconIndex using regex
            $iconIndexMatch = [regex]::Match($content, "(?mi)^IconIndex=(.*)")
            if ($iconIndexMatch.Success) {
                $iconIndex = $iconIndexMatch.Groups[1].Value.Trim()
            }

            $iconLocation = $null
            if (-not ([string]::IsNullOrWhiteSpace($iconFile))) {
                $iconLocation = $iconFile
                if (-not ([string]::IsNullOrWhiteSpace($iconIndex))) {
                    $iconLocation += ",$iconIndex" # Combine path and index like LNKs
                }
            }

            # Normalize the URL path here before returning
            $normalizedUrl = Normalize-UrlPath -Url $url

            return [PSCustomObject]@{
                Type         = "URL"
                TargetPath   = $normalizedUrl # Return the normalized URL
                Arguments    = ""            # .url files don't have separate arguments
                IconLocation = $iconLocation
            }
        }
        catch {
            Write-Warning "Failed to get URL shortcut info for '$Path'. Error: $($_.Exception.Message)"
            return $null
        }
    }

    # --- Function to get Target-Based Application Name ---
    function Get-TargetBasedAppName {
        param (
            [string]$TargetPath,
            [string]$ShortcutType # LNK, URL, LNK_RESOLVED_URL
        )

        $appName = "Other / Uncategorized (Target)" # Default if no specific app name is found

        if ($ShortcutType -eq "LNK") {
            $targetDirectory = $null
            if (Test-Path -Path $TargetPath -PathType Leaf) { $targetDirectory = [System.IO.Path]::GetDirectoryName($TargetPath) }
            elseif (Test-Path -Path $TargetPath -PathType Container) { $targetDirectory = $TargetPath }
        
            if ($targetDirectory) {
                $currentPathSegment = $targetDirectory
            
                # Common program installation roots (normalized for consistent comparison)
                $programRoots = @(
                    "$env:ProgramFiles(x86)",
                    "$env:ProgramFiles",
                    "$env:LocalAppData\Programs"
                ) | ForEach-Object { $_.TrimEnd('\').ToLower() }
            
                # List of common vendor folders (can be expanded based on your environment)
                $vendorList = @("microsoft", "google", "mozilla", "adobe", "apple", "videolan", "vmware", "citrix", "hp", "dell", "autodesk", "ibm", "oracle", "epic games", "steam", "riot games", "nvidia corporation", "intel")

                # This loop tries to find the most relevant application folder name by walking up the path
                while ($currentPathSegment) {
                    $parentDir = [System.IO.Path]::GetDirectoryName($currentPathSegment)
                
                    if (-not $parentDir) { break } # Reached drive root

                    $segmentName = [System.IO.Path]::GetFileName($currentPathSegment) # e.g., "Application" for Edge, "Office16" for Word
                    $parentSegmentName = [System.IO.Path]::GetFileName($parentDir) # e.g., "Edge" for Edge, "root" for Word
                    $parentDirLower = $parentDir.ToLower()
                
                    if ($programRoots -contains $parentDirLower) {
                        return $segmentName
                    }

                    $grandParentDir = [System.IO.Path]::GetDirectoryName($parentDir)
                    if ($grandParentDir) {
                        $grandParentSegmentName = [System.IO.Path]::GetFileName($grandParentDir) # e.g., "Microsoft" for Edge, "Microsoft Office" for Word (from Root\Office16)
                        $greatGrandParentDir = [System.IO.Path]::GetDirectoryName($grandParentDir)
                    
                        if ($greatGrandParentDir) {
                            $greatGrandParentDirLower = $greatGrandParentDir.ToLower()
                            if ($programRoots -contains $greatGrandParentDirLower) {
                                if ($grandParentSegmentName.ToLower() -in $vendorList) {
                                    # This means we are in a structure like: ProgramFiles\Vendor\AppName\SubFolder
                                    # The AppName is $parentSegmentName (e.g., "Edge" or "Acrobat DC")
                                    return $parentSegmentName
                                }
                            }
                        }
                    }
                
                    $currentPathSegment = $parentDir # Move up one level
                }
            
                $lastFolder = [System.IO.Path]::GetFileName($targetDirectory)
                if (-not ([string]::IsNullOrWhiteSpace($lastFolder))) {
                    return $lastFolder # Use the last folder name in the target path
                } else {
                    return $targetDirectory # If it's a drive root or something unidentifiable, use the full path
                }
            }
        } elseif ($ShortcutType -in ("URL", "LNK_RESOLVED_URL")) {
            # For URLs, group by domain name
            try {
                $uri = New-Object System.Uri($TargetPath)
                $hostName = $uri.Host
                if ($hostName.StartsWith("www.", [System.StringComparison]::OrdinalIgnoreCase)) {
                    $hostName = $hostName.Substring(4) # Remove "www." for cleaner grouping
                }
                return $hostName
            } catch {
                return "Web (Other)" # Fallback for malformed URLs
            }
        }
        return $appName # Return default if none of the above applied
    }

    # NEW FUNCTION: To determine the actual file path used for icon extraction
    function Get-ResolvedIconFilePath {
        param (
            [string]$IconLocation,
            [string]$FallbackTargetPath # The shortcut's TargetPath
        )

        $resolvedPath = $null
        $iconIndex = 0 # Default icon index, not strictly used for path resolution but might be informative

        # If IconLocation is empty or only an index (e.g., ",0"), use FallbackTargetPath
        if ([string]::IsNullOrWhiteSpace($IconLocation) -or ($IconLocation -match "^\s*,\s*\d+\s*$")) {
            $resolvedPath = $FallbackTargetPath
            # If IconLocation *was* just an index, try to parse it for verbose output
            if ($IconLocation -match "^\s*,\s*(\d+)\s*$") {
                [int]::TryParse($matches[1].Trim(), [ref]$iconIndex) | Out-Null
            }
        }
        elseif ($IconLocation -like "*,*") {
            # IconLocation contains a path and an index (e.g., "C:\path\to\file.exe,0")
            $parts = $IconLocation.Split(',')
            $resolvedPath = $parts[0].Trim()
            if ($parts.Length -gt 1) {
                [int]::TryParse($parts[1].Trim(), [ref]$iconIndex) | Out-Null
            }
        } else {
            # IconLocation is just a path (e.g., "C:\path\to\icon.ico")
            $resolvedPath = $IconLocation.Trim()
        }

        # Resolve any environment variables in the path (e.g., %SystemRoot%)
        $resolvedPath = [System.Environment]::ExpandEnvironmentVariables($resolvedPath)
        
        # If the resolved path is a URL, it cannot be used for direct icon extraction by System.Drawing
        if ($resolvedPath -match "^https?://|^ftp://|^file://") {
            # Returning a distinct string here to avoid confusion with actual file paths
            return "IS_URL_TARGET:$resolvedPath"
        }

        return $resolvedPath # Return the determined file path
    }


    # Function to extract an icon and convert it to a Base64 string (PNG format)
    function Get-IconAsBase64 {
        param (
            [string]$ResolvedFilePath # Now directly takes the resolved file path
        )

        # Write-Host "DEBUG: Get-IconAsBase64 called for path: '$ResolvedFilePath'" -ForegroundColor Yellow

        # Check if the path indicates it's a URL target from Get-ResolvedIconFilePath
        if ($ResolvedFilePath -match "^IS_URL_TARGET:") {
            # Write-Host "DEBUG: '$ResolvedFilePath' is a URL target. Cannot extract icon. Returning null." -ForegroundColor Red
            return $null
        }

        if ([string]::IsNullOrWhiteSpace($ResolvedFilePath)) {
            # Write-Host "DEBUG: ResolvedFilePath is empty or null. Returning null." -ForegroundColor Red
            return $null
        }

        # Explicitly check Test-Path and log its result
        $fileExists = Test-Path -LiteralPath $ResolvedFilePath -PathType Leaf
        if (-not $fileExists) {
            # Write-Host "DEBUG: Icon file NOT FOUND at path: '$ResolvedFilePath'. Returning null." -ForegroundColor Red
            return $null
        } else {
            # Write-Host "DEBUG: Icon file FOUND at path: '$ResolvedFilePath'." -ForegroundColor Green
        }

        try {
            $icon = $null
            
            if ($ResolvedFilePath.ToLower().EndsWith(".ico")) {
                # Write-Host "DEBUG: Attempting to load icon from ICO file: '$ResolvedFilePath'." -ForegroundColor Cyan
                try {
                    $icon = New-Object System.Drawing.Icon($ResolvedFilePath)
                } catch {
                    # Write-Host "DEBUG: ERROR - Failed to create System.Drawing.Icon from ICO file '$ResolvedFilePath'. Exception: $($_.Exception.Message)" -ForegroundColor Red
                    $icon = $null # Ensure $icon is null if creation failed
                }
            } else {
                # Write-Host "DEBUG: Attempting to extract associated icon from executable/DLL: '$ResolvedFilePath'." -ForegroundColor Cyan
                try {
                    $icon = [System.Drawing.Icon]::ExtractAssociatedIcon($ResolvedFilePath)
                } catch {
                    # Write-Host "DEBUG: ERROR - Failed to call ExtractAssociatedIcon for '$ResolvedFilePath'. Exception: $($_.Exception.Message)" -ForegroundColor Red
                    $icon = $null # Ensure $icon is null if an exception occurred during call
                }
            }
        
            # --- CRUCIAL DEBUGGING STEP: Check if $icon object was successfully created/extracted ---
            if ($icon -eq $null) {
                # Write-Host "DEBUG: Icon object is NULL after extraction attempt for '$ResolvedFilePath'. This means no icon was found or could be loaded." -ForegroundColor Magenta
                return $null
            } else {
                # Write-Host "DEBUG: Icon object SUCCESSFULLY extracted/loaded for '$ResolvedFilePath'. Proceeding to Base64 conversion." -ForegroundColor Green
            }
            # --- END CRUCIAL DEBUGGING STEP ---

            $bitmap = $icon.ToBitmap()
            $ms = New-Object System.IO.MemoryStream
            
            $bitmap.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
            
            $byteArray = $ms.ToArray()
            
            $ms.Dispose()
            $bitmap.Dispose()
            $icon.Dispose()

            $base64String = [System.Convert]::ToBase64String($byteArray)
            # Write-Host "DEBUG: Successfully converted icon from '$ResolvedFilePath' to Base64. Length: $($base64String.Length)." -ForegroundColor Green
            return $base64String
        }
        catch {
            # Catch all other unexpected errors during bitmap/stream operations
            # Write-Host "DEBUG: UNEXPECTED ERROR during icon conversion for '$ResolvedFilePath'. Exception: $($_.Exception.Message)" -ForegroundColor Red
        }
        
        # Write-Host "DEBUG: Reaching end of Get-IconAsBase64 without successful Base64 return for '$ResolvedFilePath'. Returning null." -ForegroundColor Red
        return $null
    }
    
    # Common Start Menu paths
    $startMenuPaths = @(
        "$env:ProgramData\Microsoft\Windows\Start Menu", # All Users Start Menu
        "$env:AppData\Microsoft\Windows\Start Menu"      # Current User Start Menu
    )

    $allShortcuts = @()

    foreach ($smPath in $startMenuPaths) {
        if (Test-Path $smPath) {
            # Include both .lnk and .url files in the search
            $allShortcuts += Get-ChildItem -Path $smPath -Recurse -Include *.lnk, *.url -ErrorAction SilentlyContinue
        }
    }

    if ($allShortcuts.Count -eq 0) {
        Write-Warning "No shortcuts found in the specified Start Menu paths."
        return @()
    }

    $results = @()

    # Pre-process ExcludeApps for case-insensitive comparison
    $excludeAppsLower = $ExcludeApps | ForEach-Object { $_.ToLower() }

    foreach ($shortcut in $allShortcuts) {
        $shortcutInfo = $null
    
        # Determine shortcut type based on extension and call the appropriate function
        if ($shortcut.Extension -eq ".lnk") {
            $shortcutInfo = Get-LnkShortcutInfo -Path $shortcut.FullName
        } elseif ($shortcut.Extension -eq ".url") {
            $shortcutInfo = Get-UrlShortcutInfo -Path $shortcut.FullName
        } else {
            continue # Skip to the next shortcut
        }

        if ($shortcutInfo) {
            # Check for empty target path (applies to both LNK and URL)
            if ([string]::IsNullOrWhiteSpace($shortcutInfo.TargetPath)) {
                Write-Verbose "Skipping shortcut $($shortcut.FullName) due to empty TargetPath."
                continue # Skip to the next shortcut
            }

            # Skip Windows system-related shortcuts (e.g., C:\Windows\System32\cmd.exe)
            if ($shortcutInfo.Type -eq "LNK" -and ($shortcutInfo.TargetPath.ToLower()).StartsWith("c:\windows")) {
                Write-Verbose "Skipping Windows system shortcut: $($shortcut.FullName)"
                continue # Skip to the next shortcut
            }

            # --- COMBINED GROUPING LOGIC (Prioritizes Start Menu folder, then Target Path) ---
            $groupName = "Other / Uncategorized" # Default fallback
            $shortcutDirectory = $shortcut.DirectoryName
            $targetPathToAnalyze = $shortcutInfo.TargetPath

            # --- 1. Calculate StartMenuGroupName ---
            $startMenuGroupName = $null
            foreach ($smPath in $startMenuPaths) {
                $normalizedSmPath = $smPath.TrimEnd('\') # Ensure no trailing slash for consistent comparison
                $normalizedShortcutDirectory = $shortcutDirectory.TrimEnd('\')

                if ($normalizedShortcutDirectory.StartsWith($normalizedSmPath, [System.StringComparison]::OrdinalIgnoreCase)) {
                    $relativePath = $normalizedShortcutDirectory.Substring($normalizedSmPath.Length).TrimStart('\')
                    $segments = $relativePath.Split('\', [System.StringSplitOptions]::RemoveEmptyEntries)

                    if ($segments.Length -gt 0) {
                        # Iterate from deepest to shallowest to find the most specific non-generic folder name
                        for ($i = $segments.Length - 1; $i -ge 0; $i--) {
                            $segment = $segments[$i]
                            $segmentLower = $segment.ToLower()
                            # Exclude common generic folders that are unlikely to be meaningful app names.
                            if (-not ($segmentLower -in @("programs", "common", "tools", "utility", "system tools", "accessories", "maintenance", "microsoft office tools", "bin", "doc", "html", "lib", "fonts", "x86", "x64", "programdata", "data", "appdata", "local", "roaming", "profile", "users", "drivers", "resources", "shared", "installer", "setup", "update", "temp", "tmp", "logs", "cache", "config", "settings", "applications", "apps", "main", "default", "desktop", "start menu", "software"))) {
                                $startMenuGroupName = $segment
                                break # Found a good, specific name, stop searching deeper
                            }
                        }
                    }
                    break # Found the base Start Menu path for this shortcut
                }
            }

            # --- 2. Calculate TargetBasedGroupName using the new function ---
            $targetBasedGroupName = Get-TargetBasedAppName -TargetPath $targetPathToAnalyze -ShortcutType $shortcutInfo.Type
        
            # --- Final GroupName Decision ---
            # Prioritize Start Menu grouping if it provides a specific application name
            if (-not ([string]::IsNullOrWhiteSpace($startMenuGroupName))) {
                $groupName = $startMenuGroupName
            } else {
                # Otherwise, fall back to the TargetPath-based grouping
                $groupName = $targetBasedGroupName
            }
            # --- END COMBINED GROUPING LOGIC ---

            # --- Exclusion Logic ---
            $shortcutNameLower = $shortcut.BaseName.ToLower()
            $groupNameLower = $groupName.ToLower()

            if ($excludeAppsLower.Count -gt 0) {
                if ($excludeAppsLower -contains $shortcutNameLower -or $excludeAppsLower -contains $groupNameLower) {
                    Write-Verbose "Skipping excluded application: $($shortcut.BaseName) (Group: $groupName)"
                    continue # Skip adding this shortcut to results
                }
            }
            # --- End Exclusion Logic ---

            # Get the resolved icon file path first
            $resolvedIconPath = Get-ResolvedIconFilePath -IconLocation $shortcutInfo.IconLocation -FallbackTargetPath $shortcutInfo.TargetPath

            # Then, extract the icon as base64 using the resolved path
            $iconBase64 = Get-IconAsBase64 -ResolvedFilePath $resolvedIconPath

            # Add the processed shortcut information to the results
            $results += [PSCustomObject]@{
                ShortcutName    = $shortcut.BaseName
                Type            = $shortcutInfo.Type
                TargetPath      = $shortcutInfo.TargetPath
                Arguments       = $shortcutInfo.Arguments
                RawIconLocation = $shortcutInfo.IconLocation   # The original IconLocation string from the shortcut
                ResolvedIconPath = $resolvedIconPath           # The actual file path that Get-IconAsBase64 attempted to use
                Icon            = $iconBase64                  # <--- THIS LINE IS CRITICAL
                GroupName       = $groupName                   # The derived group name
                SourcePath      = $shortcut.FullName           # The full path to the .lnk or .url file
            }
        }
    }

    if ($results.Count -gt 0) {
        # Group the results by the GroupName property and sort alphabetically
        $groupedResults = $results | Group-Object -Property GroupName | Sort-Object Name
        return $groupedResults # Changed to return grouped results for convenience if desired by calling script
    }
    return $results # Fallback: return raw results if no grouping (e.g., if results.Count is 0 after filtering)
}

function Add-Base64Padding {
    param (
        [string]$Base64String
    )

    $padding = ""
    $mod = $Base64String.Length % 4
    if ($mod -eq 1) {
        # This case should technically not happen with valid Base64, but included for robustness
        $padding = "==="
    } elseif ($mod -eq 2) {
        $padding = "=="
    } elseif ($mod -eq 3) {
        $padding = "="
    }
    return $Base64String + $padding
}

# Variables
$LiquitURI = 'https://john.liquit.com' # Replace this with your zone
$username = 'local\apiaccess'          # Replace this with a service account you have created for creating and accessing this information
$password = 'IsaiahMaddux@2014'        # Enter the password for that service Account
$PackagePrefix = 'Shortcut - '
$base64CitiLogo = 'iVBORw0KGgoAAAANSUhEUgAAAFkAAABZCAMAAABi1XidAAACN1BMVEUAAAAAAP//AAAAgP//AAAAVf//VQBAQP//QEAzZsz/MzMrVdX/KyskSdv/ORwaZuYuXegnYuskW9siVd0gYN//QDArVeMoXuT/Nij/QCYkVecpXOD/PSknWOL/OycmXuP/QCQjWOUhWub/OikoWN8kV+IjXOMiWuP/PCj/OyckW+EoW+P/PCYlWuT/Oiv/PSkjWuEnXeL/OiYmWuMlXeMkW+QmWeEmXOL/OyolWuL/PikkWeP/PCgjWuQnXeQmWuX/PCklXOEkWuImWuMlXOQlW+QkWuIlWuMlXOP/PSgkW+QkWuT/PCcmW+L/Oyn/PCj/OyckW+P/PCkmXOQmW+QlWuIlXOL/PCckWuMmXOMmWuT/PCj/OyckW+ImXOMlWuP/PCcmXOIlWuIlXOMkWuP/PCn/PCj/OyglWuIkWuP/PCj/PCglW+QlW+QmXOL/OyglW+IlW+P/PCgkWuP/PCf/PSklW+IlXOMkWuMmXOMlW+P/PSj/Oyn/PCklW+MlW+P/OyklW+QlW+P/PCj/PCn/PCj/PCgkWuMlW+MlW+MkW+L/PCglW+MkWuP/PCglW+MlW+MlXOMkW+MlW+MlW+IlW+P/PCj/PCglW+MkW+MlW+P/PCglW+MlW+MlW+MmW+MlW+T/PCj/PCglW+P/PCglW+P/PCglW+MlW+P/PCj/PCglW+P/PCglW+MlW+P/PCglWuMlW+MlW+P/PCglW+MlW+P/PCglW+MlW+P/PCglW+P/PCj////cfsi+AAAAunRSTlMAAQECAgMDBAQFBQYGBwkKCw0ODxAQEhMTFBUZGRoaGxwdHx8gIyQlJicqLS8wMDIzNDU2Nzg8PT0+Pj9AQUJEREVHSktMT1JTU1RVVVdXWltcXV5fYGFhY2RmZmhqbG5vcnR1d3d4eXx/f4CDhI6Oj5GRk5WXmJmbnJ2go6qrrrCxs7O2t7i9v8HEx8nLzc/Q0dLT1tjZ2t7g4eHi4+bn6Ojq6+vs8fLz8/T19fb39/j5+vr7/Pz9/v6DZrtqAAAAAWJLR0S8StLi7wAAAkpJREFUWMNjYBgFo2AUjIJRMApGwSgYBSMUiFqEJ6SnRntqsFHTVBab/Om7YWBNa4wMlczli5m2GxVsrtGnhsE+s+EmrtoGY+2sodjdki0Qk7qzHBRA7tcLql4CFlkWQJnBRmAHry/SQBLj8ekDm13CRYHBVitBRtTKwfhKEIrJbyFIvIGHfINXgdKCP4yrUrgOxpRoAxndzEGmwcqLgLqXwJNB5ZZdu+BybKUgo/PJNDmtFgh04NwVu5BMZmDKBslqUiVdo5pMTUCJyZxu5RMXbJjVlWfCCBEQc3V1dQHShvZAsBZosj0YiDMwKAJlrIk1lzF0xi4YmGwJFjIHMrcD6c5dKMCJgSECSE0h0mDBOmTNO4qZqWUyL0T3pkkdUzeBWVXMVDK5EqRlfqwQKHRj5wHZlUgmg8I5ZBdyOBNvsskOoNJ+aShPpBFsMNxkEFDfhZw2iDe5CahyqSycyx3LzEAdk4U2AFUmYwhTwWRHUHKQp4XJYUCFixloYXIcUOFMmpjsBVS4jpUWJuuCtJnTwmTGWUCV9UgC/NQymSEHlDgC4VzVWYHoJquBTBYn3WShBaBCI54ZwvNYsGtrCJrJ4iCTg0k3mcF5C7j0TDLTskvsBTFXS6GaDA6w5Zm2ph5luqSVopFbUcqzje5obmbIhMuZk2Yyg+18JIMnGKOHMwN/D7kmMwikzIFq7Y1jB4sYz507F5GBhCsgJfcmAwYGX6BMOyk1oXZUZkFumCouadng3LwMb5HR3sQoGAWjYBSMglEwCkbBsAcAs+XJiC5ARngAAAAASUVORK5CYII='

# Create Connection to Application Workspace
$credentials = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $username, (ConvertTo-SecureString -String $password -AsPlainText -Force)
Connect-LiquitWorkspace -URI $LiquitURI -Credential $credentials -ErrorAction Stop

# Get all the shortcuts on the machine
# Write-Host "Gathering shortcuts from Start Menu..."
$AvailableGroups = Get-Shortcuts
# Write-Host "Found $($AvailableGroups.Count) grouped applications."

# Process each group and potentially create Liquit packages
ForEach ($Group in $AvailableGroups) {
    # Combine Package Prefix with Group Name
    $FullPackageName = $PackagePrefix + $Group.Name
    $Description = "Automatically generated package for '" + $Group.Name + "' based on Start Menu shortcuts."

    $PackageExist = Get-LiquitPackage -Name $FullPackageName -ErrorAction SilentlyContinue

    If (!$PackageExist) {
        
        $path = "C:\Temp"
        if (-not (Test-Path -Path $path)) {
            New-Item -ItemType Directory -Path $path -Force | Out-Null
        }
        $appIcon = Add-Base64Padding -Base64String $base64CitiLogo
        $bytes = [System.Convert]::FromBase64String($appIcon)
        [System.IO.File]::WriteAllBytes("$path\icon.png", $bytes) | Out-Null
        $iconPath = "$path\icon.png"
        $iconContent = New-LiquitContent -Path $iconPath
        $AWPackage = New-LiquitPackage -Name $FullPackageName -Type "Launch" -DisplayName "$($Group.Name)" -Description $Description -Priority 100 -Enabled $true -Offline $true -Web $false -Icon $iconContent
        $AWSnapshot = New-LiquitPackageSnapshot -Package $AWPackage -Name "Initial Rollout"
        $AWFilterSet = New-LiquitFilterSet -Snapshot $AWSnapshot

        ForEach ($IndShortcut in $Group.Group) {
            # Create Icon for Shortcut
            $appIcon = Add-Base64Padding -Base64String $IndShortcut.Icon
            $bytes = [System.Convert]::FromBase64String($appIcon)
            Try {
                [System.IO.File]::WriteAllBytes("$path\icon.png", $bytes) | Out-Null
                $iconPath = "$path\icon.png"
                $iconContent = New-LiquitContent -Path $iconPath
            } catch {
                $appIcon = Add-Base64Padding -Base64String $base64CitiLogo
                $bytes = [System.Convert]::FromBase64String($appIcon)
                [System.IO.File]::WriteAllBytes("$path\icon.png", $bytes) | Out-Null
                $iconPath = "$path\icon.png"
                $iconContent = New-LiquitContent -Path $iconPath
            }
            $trimmedString = $IndShortcut.ShortcutName -replace '\s', ''
            # Create the shortcut on the package
            $Shorcut = New-LiquitPackageShortcut -Snapshot $AWSnapshot -ID $trimmedString -Name $($IndShortcut.ShortcutName) -Description $($IndShortcut.ShortcutName) -Enabled $true # -Icon $iconContent
            $Shorcut | Set-LiquitPackageShortcut -Icon $iconContent
            # Create the action set for the shortcuts
            $AWActionSet = New-LiquitActionSet -Snapshot $AWSnapshot -Type Launch -Name $($IndShortcut.ShortcutName) -Enabled $true -Frequency Always -Process Sequential -Collection $trimmedString
            $FilterSet = New-LiquitFilterSet -ActionSet $AWActionSet
            New-Liquitfilter -FilterSet $FilterSet -Type fileexists -Settings @{path = "$($IndShortcut.TargetPath)";} -Value "true"
            New-Liquitfilter -FilterSet $AWFilterSet -Type fileexists -Settings @{path = "$($IndShortcut.TargetPath)";} -Value "true"
            If ($($IndShortcut.Type) -eq 'LNK_RESOLVED_URL'){
                New-LiquitAction -ActionSet $AWActionSet -Name "Launch $($IndShortcut.ShortcutName)" -Type 'openurl' -Enabled $true -IgnoreErrors $false -Context User -Settings @{name = "Launch $($IndShortcut.ShortcutName)"; url = "$($IndShortcut.TargetPath)"}
            } else {
                New-LiquitAction -ActionSet $AWActionSet -Name "Launch $($IndShortcut.ShortcutName)" -Type 'processstart' -Enabled $true -IgnoreErrors $false -Context User -Settings @{name = $($IndShortcut.TargetPath); parameters = "$($IndShortcut.Arguments)"}
            }
        }
        If ($CreateEntitlements) {
            $Context = Get-LiquitContext -Name 'Shortcuts - All Users and Devices'
            If (!$Context) {
                $Context = New-LiquitContext -Filter -Name 'Shortcuts - All Users and Devices' -Priority 100 -Enabled $true -Filters @{operator = "AND"; sets =@()}
                Start-Sleep -Seconds 10
            }
            If ($CreateDesktopIcons -or $CreateStartMenuIcons) {
                $Icons = New-Object Liquit.API.Server.V3.PackageEntitlementIcons
                If ($CreateDesktopIcons) {
                    $Icons.Desktop = $true
                }
                If ($CreateStartMenuIcons) {
                    $Icons.StartMenu = $true
                }
            }
            $Identity = Get-LiquitIdentity -Type Context | Where-Object {$_.Name -eq 'Shortcuts - All Users and Devices'}
            If ($Icons) {
                $Entitlement = New-LiquitPackageEntitlement -Package $AWPackage -Publish Workspace -Stage Production -Identity $Identity -Icons $Icons
            } else {
                $Entitlement = New-LiquitPackageEntitlement -Package $AWPackage -Publish Workspace -Stage Production -Identity $Identity
            }
        }
    } else {
        $AWPackage = Get-LiquitPackage -Name $FullPackageName
        $AWSnapshot = Get-LiquitPackageSnapshot -Package $AWPackage -Type Development
        $AWActionSets = Get-LiquitActionSet -Snapshot $AWSnapshot -Type Launch
        $AWFilterSet = Get-LiquitFilterSet -Snapshot $AWSnapshot

        ForEach ($IndShortcut in $Group.Group) {
            If ($IndShortcut.ShortcutName -notin $AWActionSets.Name) {
                # Create Icon for Shortcut
                $appIcon = Add-Base64Padding -Base64String $IndShortcut.Icon
                $bytes = [System.Convert]::FromBase64String($appIcon)
            Try {
                [System.IO.File]::WriteAllBytes("$path\icon.png", $bytes) | Out-Null
                    $iconPath = "$path\icon.png"
                    $iconContent = New-LiquitContent -Path $iconPath
                } catch {
                    $iconContent = $null
                }
                $trimmedString = $IndShortcut.ShortcutName -replace '\s', ''
                # Create the shortcut on the package
                $Shortcut = New-LiquitPackageShortcut -Snapshot $AWSnapshot -ID $trimmedString -Name $($IndShortcut.ShortcutName) -Description $($IndShortcut.ShortcutName) -Enabled $true # -Icon $iconContent
                $Shortcut | Set-LiquitPackageShortcut -Icon $iconContent
                # Create the action set for the shortcuts
                $AWActionSet = New-LiquitActionSet -Snapshot $AWSnapshot -Type Launch -Name $($IndShortcut.ShortcutName) -Enabled $true -Frequency Always -Process Sequential -Collection $trimmedString
                $FilterSet = New-LiquitFilterSet -ActionSet $AWActionSet
                New-Liquitfilter -FilterSet $FilterSet -Type fileexists -Settings @{path = "$($IndShortcut.TargetPath)";} -Value "true"
                New-Liquitfilter -FilterSet $AWFilterSet -Type fileexists -Settings @{path = "$($IndShortcut.TargetPath)";} -Value "true"
                If ($($IndShortcut.Type) -eq 'LNK_RESOLVED_URL'){
                    New-LiquitAction -ActionSet $AWActionSet -Name "Launch $($IndShortcut.ShortcutName)" -Type 'openurl' -Enabled $true -IgnoreErrors $false -Context User -Settings @{name = "Launch $($IndShortcut.ShortcutName)"; url = "$($IndShortcut.TargetPath)"}
                } else {
                    New-LiquitAction -ActionSet $AWActionSet -Name "Launch $($IndShortcut.ShortcutName)" -Type 'processstart' -Enabled $true -IgnoreErrors $false -Context User -Settings @{name = $($IndShortcut.TargetPath); parameters = "$($IndShortcut.Arguments)"}
                }
            }
        }
    }
    
}