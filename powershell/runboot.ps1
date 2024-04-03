<#
.SYNOPSIS
    runboot bootstrap script to set up a new Windows development environment optimized for Unreal Engine development.

.DESCRIPTION
    This script automates the setup of a new Windows development environment by installing various dependencies and tools using winget.
    It supports installing winget itself if not already present, as well as Visual Studio, VS Code, Buildkite agent, 7-Zip, and a configurable list of dependencies from a JSON file.

.PARAMETER Winget
    Install winget package manager.

.PARAMETER Deps
    Install dependencies listed in the winget-packages.json file.

.PARAMETER Vs
    Install Visual Studio 2022 (using a .vsconfig file in the same directory) and Visual Studio Code.

.PARAMETER Buildkite
    Install Buildkite agent.

.PARAMETER SevenZip
    Install 7-Zip.

.PARAMETER All
    Install all components (default if no options specified).

.PARAMETER Help
    Displays help information about the script.

.EXAMPLE
    .\bootstrap.ps1 -All

.EXAMPLE
    .\bootstrap.ps1 -Help

.NOTES
    Version: 1.0.0
    - Requires running with administrator privileges.
    - Looks for a .env file in the same directory to load environment variables.
    - Looks for a winget-packages.json file in the same directory to load the list of dependencies to install.
    - Logs activity to bootstrap.log in the same directory.
.LINK
    Repository: https://github.com/runreal/runboot
#>
[CmdletBinding()]
param (
    [switch]$Winget,
    [switch]$Deps,
    [switch]$Vs,
    [switch]$Buildkite,
    [switch]$SevenZip,
    [switch]$All,
    [switch]$Version,
    [switch]$Help
)

# ============================================================================ #
# Metadata
# ============================================================================ #
$CurrentVersion = "1.0.0"


# ============================================================================ #
# Functions
# ============================================================================ #

# Logs a message to the console and a log file with timestamp and type (Info, Warning, Error).
function Log($message, $type = "Info") {
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$type] $message"
    switch ($type) {
        "Error" { Write-Host $logMessage -ForegroundColor Red }
        "Warning" { Write-Host $logMessage -ForegroundColor Yellow }
        default { Write-Host $logMessage -ForegroundColor Green }
    }
    $logPath = Join-Path -Path $PSScriptRoot -ChildPath "bootstrap.log"
    try {
        Add-Content -Path $logPath -Value $logMessage
    }
    catch {
        Write-Host "Failed to write to log file: $_" -ForegroundColor Red
    }
}

# Loads environment variables from a .env file, if present.
function LoadEnvVariables {
    $envFile = Join-Path -Path $PSScriptRoot -ChildPath ".env"
    if (Test-Path $envFile) {
        $envVars = Get-Content $envFile
        foreach ($line in $envVars) {
            if ($line -match '^([^#].+?)=(.+)$') {
                $key = $matches[1].Trim()
                $value = $matches[2].Trim()
                [Environment]::SetEnvironmentVariable($key, $value, "Process")
            }
        }
        Log "Loaded environment variables from .env file"
    }
    else {
        Log "No .env file found. Skipping loading environment variables."
    }
}

# Loads the list of packages to install with winget from a JSON configuration file.
function LoadPackageList {
    $packageFile = Join-Path -Path $PSScriptRoot -ChildPath "winget-packages.json"
    if (Test-Path $packageFile) {
        $packages = (Get-Content $packageFile | ConvertFrom-Json).packages
        Log "Loaded package list from configuration file"
		return $packages
    }
    else {
        Log "Package configuration file not found. Exiting..." -type "Error"
        exit
    }
}

# Checks if the script is running with administrator privileges.
function CheckAdmin {
    if (([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        return $true
    }
    return $false
}

# Checks if winget is installed and returns the version if available.
function CheckWinget {
    Log "Checking winget version..."
    try {
        $wingetVersion = winget --version
        if ($wingetVersion) {
            return $wingetVersion
        }
        else {
            return $false
        }
    }
    catch {
        return $false
    }
}

# Adapted from https://github.com/asheroto/winget-install/
# Retrieves the download URL of the latest release asset that matches a specified pattern from the GitHub repository.
function Get-WingetDownloadUrl {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Match
    )

    $uri = "https://api.github.com/repos/microsoft/winget-cli/releases"
    $releases = Invoke-RestMethod -uri $uri -Method Get -ErrorAction stop

    Write-Debug "Getting latest release..."
    foreach ($release in $releases) {
        if ($release.name -match "preview") {
            continue
        }
        $data = $release.assets | Where-Object name -Match $Match
        if ($data) {
            return $data.browser_download_url
        }
    }

    Write-Debug "Falling back to the latest release..."
    $latestRelease = $releases | Select-Object -First 1
    $data = $latestRelease.assets | Where-Object name -Match $Match
    return $data.browser_download_url
}

 # Downloads and installs winget and its dependencies.
function InstallWinget {
    try {
        Log "Downloading winget dependencies..."

        $tempDir = [System.IO.Path]::GetTempPath()
        $tempDir = Join-Path $tempDir ([System.IO.Path]::GetRandomFileName())
        New-Item -ItemType Directory -Path $tempDir | Out-Null

        # Download VCLibs
        $VCLibs_Path = Join-Path $tempDir "Microsoft.VCLibs.x64.14.00.Desktop.appx"
        $VCLibs_Url = "https://aka.ms/Microsoft.VCLibs.x64.14.00.Desktop.appx"
        Log "Downloading VCLibs from $VCLibs_Url to $VCLibs_Path"
        try {
            Invoke-WebRequest -Uri $VCLibs_Url -OutFile $VCLibs_Path
        }
        catch {
            Log "Failed to download VCLibs. Error: $_" -type "Error"
            throw
        }

        # Download UI.Xaml
        $UIXaml_Path = Join-Path $tempDir "Microsoft.UI.Xaml.2.8.x64.appx"
        $UIXaml_Url = "https://github.com/microsoft/microsoft-ui-xaml/releases/download/v2.8.6/Microsoft.UI.Xaml.2.8.x64.appx"
        Log "Downloading UI.Xaml from $UIXaml_Url to $UIXaml_Path"
        try {
            Invoke-WebRequest -Uri $UIXaml_Url -OutFile $UIXaml_Path
        }
        catch {
            Log "Failed to download UI.Xaml. Error: $_" -type "Error"
            throw
        }

        # Download winget license
        $winget_license_path = Join-Path $tempDir "License1.xml"
        $winget_license_url = Get-WingetDownloadUrl -Match "License1.xml"
        Log "Downloading winget license from $winget_license_url to $winget_license_path"
        try {
            Invoke-WebRequest -Uri $winget_license_url -OutFile $winget_license_path
        }
        catch {
            Log "Failed to download winget license. Error: $_" -type "Error"
            throw
        }

        # Download winget
        $winget_path = Join-Path $tempDir "Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle"
        $winget_url = "https://aka.ms/getwinget"
        Log "Downloading winget from $winget_url to $winget_path"
        try {
            Invoke-WebRequest -Uri $winget_url -OutFile $winget_path
        }
        catch {
            Log "Failed to download winget. Error: $_" -type "Error"
            throw
        }

        # Install everything
        Log "Installing winget and its dependencies..."
        Add-AppxProvisionedPackage -Online -PackagePath $winget_path -DependencyPackagePath $UIXaml_Path, $VCLibs_Path -LicensePath $winget_license_path | Out-Null

        # Remove temp directory
        Remove-Item $tempDir -Recurse -Force
    }
    catch {
        Log "Failed to install winget. Error: $_" -type "Error"
    }
}

# Installs the dependencies listed in the winget-packages.json file.
function InstallDeps {
    Log "Installing dependencies..."
 	$packages = LoadPackageList
    foreach ($package in $packages) {
        try {
            winget install -e --id $package -h
            Log "$package installation attempted."
        }
        catch {
            Log "Failed to install $package. Error: $_" -type "Error"
        }
    }
    Log "Dependencies installation attempt complete"
}

 # Installs Visual Studio using a .vsconfig file for the installation configuration.
function InstallVisualStudio {
    try {
        Log "Installing Visual Studio..."
        $vsconfigFile = Join-Path -Path $PSScriptRoot -ChildPath ".vsconfig"
        winget install --source winget --exact --id Microsoft.VisualStudio.2022.Community --override "--passive --config $vsconfigFile"
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to install Visual Studio."
        }
        Log "Visual Studio installation complete"
    }
    catch {
        Log "Failed to install Visual Studio. Error: $_" -type "Error"
    }
}

# Installs Visual Studio Code with override options.
function InstallVisualStudioCode {
    try {    
        Log "Installing VS Code..."
        winget install Microsoft.VisualStudioCode --override '/SILENT /mergetasks="!runcode,addcontextmenufiles,addcontextmenufolders"'
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to install Visual Studio Code."
        }
        Log "Visual Studio Code installation complete"
    }
    catch {
        Log "Failed to install Visual Studio Code. Error: $_" -type "Error" 
    }
}

# Installs the Buildkite agent using the official install script with BUILDKITE_AGENT_TOKEN read from environment variable.
function InstallBuildkiteAgent {
    Log "Installing buildkite-agent..."
    $env:buildkiteAgentToken = $env:BUILDKITE_AGENT_TOKEN
    Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://raw.githubusercontent.com/buildkite/agent/main/install.ps1'))
}

# Installs 7-Zip and adds its directory to the PATH.
function Install7Zip {
    Log "Installing 7-Zip..."
    winget install -e --id 7zip.7zip -h
    if (!(Get-Command 7z -ErrorAction SilentlyContinue)) {
        $installDir = Join-Path -Path $env:ProgramFiles -ChildPath '7-Zip'
        $envMachinePath = [System.Environment]::GetEnvironmentVariable('PATH', 'machine')
        if ($envMachinePath -split ';' -notcontains $installDir) {
            [Environment]::SetEnvironmentVariable('PATH', "$envMachinePath;$installDir", 'Machine')
        }
    }
}

# Exits the script with a delay and optional exit code.
function ExitWithDelay {
    param (
        [int]$DelayInSeconds = 5,
        [int]$ExitCode = 0
    )

    Start-Sleep -Seconds $DelayInSeconds
    exit $ExitCode
}

# Main bootstrap function that calls the other functions based on the installOptions.
function Bootstrap {
    Log "Running bootstrap"
    if ($Winget -or $All) {
        $wingetVersion = CheckWinget
        if (-not $wingetVersion) {
            InstallWinget
        }
    }
    if (-not (CheckWinget)) {
        Log "Winget not found. Please install winget and try again." -type "Error"
        ExitWithDelay 1
    }
    if ($Deps -or $All) {
        InstallDeps
    }
    if ($Buildkite -or $All) {
        InstallBuildkiteAgent
    }
    if ($SevenZip -or $All) {
        Install7Zip
    }
    if ($Vs -or $All) {
        InstallVisualStudioCode
        InstallVisualStudio
    }
    Log "Bootstrap complete"
}

# ============================================================================ #
# Main Script
# ============================================================================ #
try {
    if ($Help) {
        Get-Help $MyInvocation.MyCommand.Path -Detailed
        exit
    }

    if ($Version.IsPresent) {
        Write-Output $CurrentVersion
        exit
    }

    if (-not (CheckAdmin)) {
        Log "Please run this script as an administrator." -type "Error"
        ExitWithDelay 1
    }

    LoadEnvVariables

    # Determine which components to install based on parameters or default to all if none specified.
    if (-not ($Winget -or $Deps -or $Vs -or $Buildkite -or $SevenZip) -or $All) {
        $Winget = $Deps = $Vs = $Buildkite = $SevenZip = $true
    }

    Bootstrap
}
catch {
    Log "An error occurred: $_" -type "Error"
}
