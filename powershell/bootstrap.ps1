# < >
$BootstrapFile = ".bootstrap-version"
$BootstrapFilePath = Join-Path -Path $PSScriptRoot -ChildPath $BootstrapFile

function LoadPackageList {
    $packageFile = Join-Path -Path $PSScriptRoot -ChildPath "winget-packages.json"
    if (Test-Path $packageFile) {
        $packages = (Get-Content $packageFile | ConvertFrom-Json).packages
        Log "Loaded package list from configuration file"
    }
    else {
        Log "Package configuration file not found. Exiting..." -type "Error"
        exit
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
    } catch {
        Write-Host "Failed to write to log file: $_" -ForegroundColor Red
    }
}

# Prompt the user for admin privileges
$isAdmin = [bool](([System.Security.Principal.WindowsIdentity]::GetCurrent()).groups -match "S-1-5-32-544")

if (-not $isAdmin) {
    # Relaunch the script with admin privileges
    Start-Process powershell.exe "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    Exit
}

# Continue running the script with admin privileges
Log "Running with admin privileges"

function GetScriptHash {
    $scriptHash = Get-FileHash $PSCommandPath -Algorithm SHA256
    # Write-Host "Script hash: $($scriptHash.Hash)"
    return $scriptHash.Hash
}

function CheckWinGet {
    try {
        $wingetVersion = winget --version
        if ($wingetVersion) {
            return $wingetVersion
        } else {
            return $false
        }
    } catch {
        return $false
    }
}

function InstallWinGet {
    
    Invoke-WebRequest -Uri https://aka.ms/winget-cli -OutFile winget-cli.msixbundle
    Add-AppPackage .\winget-cli.msixbundle -Verbose
}

function InstallDeps {
    Log "Installing dependencies"
    foreach ($package in $packages) {
        try {
            winget install -e --id $package -h
            Log "$package installation attempted."
        } catch {
            Log "Failed to install $package. Error: $_" -type "Error"
        }
    }
    Log "Dependencies installation attempt complete"
}

function InstallVisualStudio {
    Log "Installing VS"
    $vsconfigFile = Join-Path -Path $PSScriptRoot -ChildPath ".vsconfig"
    winget install --source winget --exact --id Microsoft.VisualStudio.2022.Professional --override "--passive --config $vsconfigFile"
}

function InstallBuildkiteAgent {
    Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://raw.githubusercontent.com/buildkite/agent/main/install.ps1'))
}

function Add7ZipToPath {
    if (!(Get-Command 7z -ErrorAction SilentlyContinue)) {
        $installDir = Join-Path -Path $env:ProgramFiles -ChildPath '7-Zip'
        $envMachinePath = [System.Environment]::GetEnvironmentVariable('PATH', 'machine')
        if ($envMachinePath -split ';' -notcontains $installDir) {
            [Environment]::SetEnvironmentVariable('PATH', "$envMachinePath;$installDir", 'Machine')
        }
    }
}

function ParseArguments {
    param (
        [string[]]$args
    )

    $global:installOptions = @{
        "winget" = $args -contains "-winget"
        "deps" = $args -contains "-deps"
        "vs" = $args -contains "-vs"
        "buildkite" = $args -contains "-buildkite"
        "7zip" = $args -contains "-7zip"
        "all" = $args -contains "-all"
    }

    if (-not $global:installOptions.Values -contains $true) {
        $global:installOptions["all"] = $true
    }
}

function Bootstrap {
    Log "Running bootstrap"
    LoadEnvVariables
    CheckWinGet
    if ($global:installOptions["winget"] -or $global:installOptions["all"]) {
        InstallDeps
    }
    if ($global:installOptions["deps"] -or $global:installOptions["all"]) {
        InstallDeps
    }
    if ($global:installOptions["buildkite"] -or $global:installOptions["all"]) {
        InstallBuildkiteAgent
    }
    if ($global:installOptions["7zip"] -or $global:installOptions["all"]) {
        winget install -e --id 7zip.7zip -h
        Add7ZipToPath
    }
    if ($global:installOptions["vs"] -or $global:installOptions["all"]) {
        InstallVisualStudio
    }
    Log "Bootstrap complete"
}

$ScriptHash = GetScriptHash
if ( -Not (Test-Path $BootstrapFilePath.Trim() )) {
    Log "Detected first run - running bootstrap"
    LoadPackageList
    ParseArguments $args
    Bootstrap
    New-Item -path $PSScriptRoot -name ".bootstrap-version" -type "file" -value $ScriptHash
}
else {
    $text = Get-Content -Path $BootstrapFilePath -First 1
    if ( $text -eq $ScriptHash) {
        Log "Bootstrap is up to date - Skipping"
    }
    else {
        Log "Bootstrap is out of date - running bootstrap"
        Bootstrap
        Set-Content -Path $BootstrapFilePath -value $ScriptHash
    }
}

Log "Script completed. Press any key to exit..."
$host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")