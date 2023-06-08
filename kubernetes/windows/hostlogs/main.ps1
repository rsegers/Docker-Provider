Set-Location $env:CONTAINER_SANDBOX_MOUNT_POINT

function Start-FileSystemWatcher {
    Start-Process powershell -NoNewWindow .\opt\hostlogswindows\scripts\powershell\filesystemwatcher.ps1
}

function Invoke-ConfigmapParser($rubypath) {
    & $rubypath ./opt/hostlogswindows/scripts/ruby/tomlparser-hostlogs-geneva-config.rb
}

# Workaround for https://github.com/microsoft/Windows-Containers/issues/366
function Invoke-ConfigmapParserFromHost($rubypath) {
    $tmpdir = "C:\WindowsHostLogs"

    # Cleanup any old files from previous run
    if (Test-Path $tmpdir) {
        Remove-Item $tmpdir -R -Force
    }

    Write-host "Copying ruby binaries to host directory: $tmpdir"
    New-Item $tmpdir -Type Directory > $null
    Copy-Item "./ruby31" $tmpdir -R

    Invoke-ConfigmapParser (Join-Path $tmpdir $rubypath)

    Write-host "Cleaning up ruby binaries from the host"
    Remove-Item $tmpdir -R -Force
}

function Get-ProcessEnvironmentVariable($name) {
    return [System.Environment]::GetEnvironmentVariable($name, "process")
}

function Set-EnvironmentVariables {

    $schemaVersionFile = './etc/config/settings/schema-version'

    # Set env vars for geneva monitor
    $envVars = @{
        AZMON_AGENT_CFG_SCHEMA_VERSION = if (Test-Path $schemaVersionFile) {Get-Content $schemaVersionFile | ForEach-Object { $_.TrimEnd() } } else {""}
        # Agent identity
        AKS_CLUSTER_NAME               = Get-ProcessEnvironmentVariable AKS_CLUSTER_NAME
        AKS_REGION                     = Get-ProcessEnvironmentVariable AKS_REGION
        HOSTNAME                       = Get-ProcessEnvironmentVariable HOSTNAME
        # Agent Configuration
        MONITORING_DATA_DIRECTORY      = (Join-Path $env:CONTAINER_SANDBOX_MOUNT_POINT "opt\genevamonitoringagent\datadirectory")
        MONITORING_GCS_AUTH_ID_TYPE    = "AuthMSIToken"
        MONITORING_GCS_REGION          = Get-ProcessEnvironmentVariable AKS_REGION   
    }

    foreach ($key in $envVars.PSBase.Keys) {
        $value = $envVars[$key]
        if (![string]::IsNullOrEmpty($value)) {
            [System.Environment]::SetEnvironmentVariable($key, $value, "Process")
            [System.Environment]::SetEnvironmentVariable($key, $value, "User")
            Write-Host "Successfully set environment variable $key - $value"
        }
        else {
            Write-Host "Failed to set environment variable $key since it is either null or empty"
        }
    }

    # Load env vars from config map
    $rubypath = "./ruby31/bin/ruby.exe"

    # Use Join-Path to normalize paths with consistent delimeters
    $mountPath = Join-Path $env:CONTAINER_SANDBOX_MOUNT_POINT ""
    $bindMountPath = Join-Path "C:\hpc" ""
    # Check if using bind mounted directory added in containerd 1.7
    if ($mountPath -eq $bindMountPath) {
        Invoke-ConfigmapParserFromHost $rubypath 
    }
    else {
        Invoke-ConfigmapParser $rubypath 
    }

    # Set env vars parsed from the config map
    .\setagentenv.ps1
}

# Checks if all geneva env vars are set to start the geneva agent
function Get-GenevaEnabled {
    $enabled = $true

    foreach ($envvar in 
        "MONITORING_DATA_DIRECTORY",
        "MONITORING_CONFIG_VERSION",
        "MONITORING_GCS_ENVIRONMENT", 
        "MONITORING_GCS_ACCOUNT", 
        "MONITORING_GCS_NAMESPACE", 
        "MONITORING_GCS_REGION",
        "MONITORING_GCS_AUTH_ID_TYPE",
        "MONITORING_MANAGED_ID_IDENTIFIER", 
        "MONITORING_MANAGED_ID_VALUE"
    ) {
        $enabled = $enabled -and ![string]::IsNullOrEmpty((Get-ProcessEnvironmentVariable $envvar))
    }

    return $enabled
}

Start-Transcript -Path main.txt

Set-EnvironmentVariables
Start-FileSystemWatcher

if (Get-GenevaEnabled) {
    Invoke-Expression ".\opt\genevamonitoringagent\genevamonitoringagent\Monitoring\Agent\MonAgentLauncher.exe -useenv"
}
else {
    Write-Host "Geneva not configured. Watching for config map"
    # Infinite loop keeps container alive while waiting for config map
    # Otherwise when the process ends, kubernetes sees this as a crash and the container will enter a crash loop
    while ($true) {
        Start-Sleep 3600
    }
}

