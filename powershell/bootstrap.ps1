<# 

#>

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

function CheckAdmin {
    if (([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        return $true
    }
    return $false
}

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

function InstallBuildkiteAgent {
    Log "Installing buildkite-agent..."
    $env:buildkiteAgentToken = $env:BUILDKITE_AGENT_TOKEN
    Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://raw.githubusercontent.com/buildkite/agent/main/install.ps1'))
}

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

function ExitWithDelay {
    param (
        [int]$DelayInSeconds = 5,
        [int]$ExitCode = 0
    )

    Start-Sleep -Seconds $DelayInSeconds
    exit $ExitCode
}

function ParseArguments {
    param (
        [Parameter(Mandatory = $false, Position = 0)]
        [string[]]$args
    )

    $global:installOptions = @{
        "winget"    = $false
        "deps"      = $false
        "vs"        = $false
        "buildkite" = $false
        "7zip"      = $false
        "all"       = $false
    }

    foreach ($arg in $args) {
        switch ($arg) {
            "-winget" { $global:installOptions["winget"] = $true }
            "-deps" { $global:installOptions["deps"] = $true }
            "-vs" { $global:installOptions["vs"] = $true }
            "-buildkite" { $global:installOptions["buildkite"] = $true }
            "-7zip" { $global:installOptions["7zip"] = $true }
            "-all" { $global:installOptions["all"] = $true }
            default { Write-Host "Unknown option: $arg" -ForegroundColor Red }
        }
    }

    if (-not ($global:installOptions.Values -contains $true)) {
        $global:installOptions["all"] = $true
    }
}

function Bootstrap {
    Log "Running bootstrap"
    if ($global:installOptions["winget"] -or $global:installOptions["all"]) {
        $wingetVersion = CheckWinget
        if (-not $wingetVersion) {
            InstallWinget
        }
    }
    if (-not (CheckWinget)) {
        Log "Winget not found. Please install winget and try again." -type "Error"
        ExitWithDelay 1
    }
    if ($global:installOptions["deps"] -or $global:installOptions["all"]) {
        InstallDeps
    }
    if ($global:installOptions["buildkite"] -or $global:installOptions["all"]) {
        InstallBuildkiteAgent
    }
    if ($global:installOptions["7zip"] -or $global:installOptions["all"]) {
        Install7Zip
    }
    if ($global:installOptions["vs"] -or $global:installOptions["all"]) {
        InstallVisualStudioCode
        InstallVisualStudio
    }
    Log "Bootstrap complete"
}

# ============================================================================ #
# Setup
# ============================================================================ #
if (-not (CheckAdmin)) {
    Log "Please run this script as an administrator." -type "Error"
    ExitWithDelay 1
}

# ============================================================================ #
# Main Script
# ============================================================================ #
try {
    LoadEnvVariables
    ParseArguments $args
    Bootstrap
}
catch {
    Log "An error occurred: $_" -type "Error"
}
