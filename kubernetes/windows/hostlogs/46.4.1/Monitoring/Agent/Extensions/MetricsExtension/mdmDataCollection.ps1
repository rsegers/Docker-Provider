<#
Powershell script to collect data about Geneva Metrics (AKA MDM, AKA Geneva Hot Path) data publication
Configuration options can be controlled via the following environment variables:

DebugMdmDataCollection -> Define this variable to echo all commands
Table2CsvParameters -> Set this to the parameters that should be used when calling table2csv
MetricCollectionDurationSec -> Set this parameter to the desired duration, default is 190 secounds
MetricCollectionSizeMaxMB -> Set this parameter to limit traffic collection size, default is 500 MB
SkipAdminCheck -> Define this variable to override administrative privileges check
CppRestUtilPath -> Set this optional parameter for specifying CppRestUtil.exe path you desire to use
Table2CsvPath -> Set this optional parameter for specifying table2csv.exe path you desire to use
TimeOutSecondsSearchFiles -> Set this optional parameter for specifying the TimeOut seconds when searching files. For not having TimeOut set -1. Default value is 1h or 3600 seconds
LogicalDisks -> Set this optional parameter with the logical disks splitted by a new line where you want to search your ME related files. Example for only searching in C: and D:, "C:`nD:". Use `n as separator.

For example, you can set the path of Table2CsvPath like this: $env:Table2CsvPath = "C:/table2csv.exe"
#>

$ScriptVersion = "Windows-1.7"

$MeFrontendUrls = @(
    "global.prod.microsoftmetrics.com"
    "global.metrics.nsatc.net"
    "azglobal.metrics.nsatc.net"
)

$Ports = @(
    "80"
    "443"
)

$MeStamps = @(
    "https://global.prod.microsoftmetrics.com"
    "https://azglobal-red.prod.microsoftmetrics.com"
    "https://azglobal-black.prod.microsoftmetrics.com"
    "https://global.metrics.nsatc.net"
    "https://azglobal-red.azglobal.metrics.nsatc.net"
    "https://azglobal-black.azglobal.metrics.nsatc.net"
    "https://global.metrics.azure.microsoft.scloud"
    "https://global.metrics.azure.eaglex.ic.gov"
    "https://13.90.249.229"
    "https://40.77.24.27"
    "https://[2a01:111:f100:2000::a83e:33d6]"
    "https://[2603:1030:7::155]"
)

$StampPaths = @(
    "/public/lb-probe"
    "/public/monitoringAccount/MetricTeamInternalMetrics/acls"
)

$ExcludedEnvironmentVariables = @(
    "_NT_SYMBOL_PATH"
)

function Main {
    Set-UTF8-Encoding
    Initialize-Environment-Variables-If-Not-Defined
    Confirm-Admin-Permissions

    $mdmDataCollectionOutput = Get-MdmDataCollectionOutput
    $compressedDataOutput = Get-CompressedDataOutput $mdmDataCollectionOutput

    Show-Starting-Message

    Get-Logical-Disks
    $logicalDisks = Get-Content -Path .\LogicalDisks.txt

    $metricsExtensionPath = Get-File-Version "MetricsExtension.Native.exe" ".\MetricsExtensionProcesses.txt" "MetricsExtensionVersions.txt"

    $cppRestUtil = Search-CppRestUtil $metricsExtensionPath $logicalDisks

    Test-ME-Stamps $mdmDataCollectionOutput $cppRestUtil

    Get-Etw-Session-And-IfxMetrics-At-Start

    Get-OS-And-Processes-Information

    Get-Local-Time-Information

    Get-Difference-Time-Server-And-Agent $cppRestUtil

    Get-Certificates

    Get-HTTP-Proxy-Configuration

    Get-Environment-Variables

    Get-Open-Sockets-And-Owning-Processes

    Test-Frontend-Urls

    Get-Application-Event-Logs

    Get-Raw-And-Aggregated-Metrics

    Search-Files-Job "MetricsExtensionV1_configuration.json" $logicalDisks "MetricsExtension_Configuration_CachedConfig.txt" "$PSScriptRoot\$mdmDataCollectionOutput"

    Get-Cached-Config

    $fileNames = @(
        "MaMetricsExtensionEtw.tsf"
        "MAEventTable.tsf"
        "LocallyAggregatedMdmMetricsV1.tsf"
    )
    Search-Files-Job $fileNames $logicalDisks "TsfLogs.txt" "$PSScriptRoot\$mdmDataCollectionOutput"

    Copy-Autopilot-Logs
    Get-Autopilot-Ini

    $monAgentHostPath = Get-File-Version "MonAgentHost.exe" ".\MonAgentHostProcesses.txt" "MonAgentHostVersions.txt"

    $table2csv = Search-Table2csv $monAgentHostPath
    Convert-Tsf-Logs-To-Csv $table2csv

    Get-Etw-Session-And-IfxMetrics-At-End

    Compress-Output $compressedDataOutput $mdmDataCollectionOutput

    Show-Ending-Message
}

function Set-UTF8-Encoding
{
    [void](chcp 65001)
}

function Initialize-Environment-Variables-If-Not-Defined
{
    if (-NOT (Test-Path env:MetricCollectionDurationSec))
    {
        $env:MetricCollectionDurationSec = 190
    }

    if (-NOT (Test-Path env:MetricCollectionSizeMaxMB))
    {
        $env:MetricCollectionSizeMaxMB = 500
    }

    if (-NOT (Test-Path env:Table2CsvParameters))
    {
        $env:Table2CsvParameters = "-tail 150000"
    }

    if (-NOT (Test-Path env:TimeOutSecondsSearchFiles))
    {
        $env:TimeOutSecondsSearchFiles = 3600
    }
}

function Confirm-Admin-Permissions
{
    if (Test-Path env:SkipAdminCheck) {
        Write-Warning "Administrative permissions check skipped due to SkipAdminCheck being set."
    }
    elseif(-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole] "Administrator"))
    {
        $errorMessage = "ERROR: This script has to be run with administrative permissions.`n"
        $errorMessage += "If you believe you have received this message due to an error, you can`n"
        $errorMessage += "override this check by defining SkipAdminCheck variable."
        Write-Error $errorMessage
        break
    }
}

function Get-MdmDataCollectionOutput
{
    $folderSuffix = [DateTime]::UtcNow.ToString('yyyy_MM_dd_hh_mm_ss')
    $randomNumber = Get-Random
    $mdmDataCollectionOutput = "MdmDataCollectionOutput" + $folderSuffix + "_random_" + $randomNumber

    [void](Remove-Directory-If-It-Exists $mdmDataCollectionOutput)
    [void](mkdir $mdmDataCollectionOutput)
    [void](Set-Location $mdmDataCollectionOutput)

    return $mdmDataCollectionOutput
}

function Get-CompressedDataOutput([String]$mdmDataCollectionOutput)
{
    $compressedDataOutput = $mdmDataCollectionOutput + ".zip"
    [void](Remove-Directory-If-It-Exists $compressedDataOutput)

    return $compressedDataOutput
}

function Remove-Directory-If-It-Exists([String]$directory)
{
    if (Test-Path -Path $directory)
    {
        Write-Output "File $directory already exists deleting it before proceeding..."
        try
        {
            Invoke-Command "Remove-Item -LiteralPath $directory -Force -Recurse"
        }
        catch
        {
            Write-Error "Failed to delete the file ${CompressedDataOutput}: $_. Aborting..."
        }
    }
}

function Show-Starting-Message
{
    $date = Get-Date
    Write-Output "Begin - MDM Data Collection Script - $date"
    Write-Output "Script version $ScriptVersion"
    Write-Output "Collecting general information..."
    Write-Output "MdmDataCollection script version $ScriptVersion" > AboutCollectionScript.txt
}

function Get-Logical-Disks
{
    Write-Output "Collecting information about logical disks"

    if (Test-Path env:LogicalDisks)
    {
        $env:LogicalDisks >> LogicalDisks.txt
    }

    else
    {
        $logicalDisks = Get-WmiObject -Class Win32_LogicalDisk

        foreach ($logicalDisk in $logicalDisks)
        {
            $logicalDisk.DeviceID >> LogicalDisks.txt
        }
    }
}

function Get-File-Version([String]$processName, [String]$inputFile, [String]$outputFile)
{
    Write-Host "Searching the process: $processName"
    wmic PROCESS WHERE "(Name='${processName}')" GET ExecutablePath /FORMAT:list | findstr "=" > $inputFile

    if ([String]::IsNullOrWhiteSpace((Get-content $inputFile)))
    {
        Write-Warning "The process $processName is not running"
        "The process $processName is not running" > $inputFile
        return
    }

    foreach ($process in Get-Content -Path $inputFile)
    {
        $executablePath = $process
        $executablePath = $executablePath.TrimStart("ExecutablePath=")
        Write-Output "$executablePath" >> $outputFile
        (Get-Item $executablePath).VersionInfo | format-list >> $outputFile
    }

    return $executablePath
}


function Search-CppRestUtil ([String]$metricsExtensionPath, [Object[]]$logicalDisks)
{
    $envCppRestUtilPath = Test-Environment-Variable-Contains-Valid-Directory "CppRestUtilPath"
    if (-Not [string]::IsNullOrEmpty($envCppRestUtilPath))
    {
        return $envCppRestUtilPath
    }

    if (Test-Path -Path "..\CppRestUtil\CppRestUtil.exe")
    {
        return "..\CppRestUtil\CppRestUtil.exe"
    }

    if ($metricsExtensionPath.Contains("MetricsExtension\MetricsExtension.Native.exe"))
    {
        $possibleLocationCppRestUtil = $metricsExtensionPath.Replace("MetricsExtension\MetricsExtension.Native","CppRestUtil\CppRestUtil")
        if (Test-Path -Path $possibleLocationCppRestUtil)
        {
            return $possibleLocationCppRestUtil
        }
    }

    [void](Search-Files-Job "CppRestUtil.exe" $logicalDisks "CppRestUtilLocation.txt" "$PSScriptRoot\$mdmDataCollectionOutput")

    if (Test-Path -Path ".\CppRestUtilLocation.txt")
    {
        $cppRestUtilLocation = Get-Content .\CppRestUtilLocation.txt | Select-Object -First 1
    }

    if ([string]::IsNullOrEmpty($cppRestUtilLocation))
    {
        $warningMessage = "CppRestUtil was not found in the environment. Instead of CppRestUtil, internal Powershell tools will be used."
        $warningMessage += "Check for more information in the following link: https://eng.ms/docs/cloud-ai-platform/azure-edge-platform-aep/aep-health-standards/observability/mdm/geneva-metrics-mdm/docs/tsg/customer-side/actions/winhttp-escalation#powershell-way"
        Write-Warning $warningMessage
    }

    return $cppRestUtilLocation
}

function Get-Etw-Session-And-IfxMetrics-At-Start
{
    tasklist /M IfxMetrics.dll /FO CSV > ProcessLoadingIfxMetrics_At_Start.csv
    logman NativeMetricsExtension_Provider -ets > MetricsExtensionEtwSessionAtStart.txt
    logman -ets > EtwSessions.txt
}

function Get-OS-And-Processes-Information
{
    wmic OS GET Caption,SystemDrive,Version /FORMAT:CSV > OS.csv
    wmic PROCESS LIST FULL /FORMAT:CSV > AllProcesses.csv
}

function Get-Local-Time-Information
{
    Write-Output "Collecting time from ME client and server"

    Get-Date > DateTimeLocal.txt
    Get-TimeZone > TimeZoneInfo.txt
}

function Get-Difference-Time-Server-And-Agent([String]$cppRestUtil)
{
    if ([string]::IsNullOrEmpty($cppRestUtil))
    {
        Write-Warning "CppRestUtil.exe is not found. MdmDataCollection will not able to check if there is a difference of time between the server and the agent"
        return
    }

    $serverDate = Invoke-Expression "& '$cppRestUtil' https://global.prod.microsoftmetrics.com/public/lb-probe" | findstr /C:"Date"
    $serverDate > DateTimeServer.txt
    $serverDate = $serverDate.TrimStart("Date: ")
    $serverDate = Get-Date -Date "${serverDate}"
    $serverDateUtc = $serverDate.ToUniversalTime()

    $localDateUtc = [DateTime]::UtcNow

    $deltaMinutes = ($localDateUtc - $serverDateUtc).TotalMinutes

    if (($deltaMinutes -ge 1) -OR ($deltaMinutes -le -5))
    {
        "ERROR: There is a difference of ${deltaMinutes} minutes between ME client time and server time." > TimeDifferenceError.txt
        Write-Error "ERROR: There is a difference of ${deltaMinutes} minutes between ME client time and server time."
    }
}

function Get-Certificates
{
    certutil -silent -v -gmt -store "My" > Certificates_On_LocalMachine_My.txt
    certutil -user -v -gmt -silent -store "My" > Certificates_On_User_My.txt
}

function Get-HTTP-Proxy-Configuration
{
    netsh winhttp dump > WinHttp_Config.txt
}

function Get-Environment-Variables
{
    Get-ChildItem env: | Where-Object -Value $ExcludedEnvironmentVariables -NotIn -Property Name > EnvironmentVariables.txt
}

function Test-ME-Stamps([String]$mdmDataCollectionOutput, [String]$cppRestUtil)
{
    Write-Output "Testing several MetricsExtension global endpoints"
    foreach ($meStamp in $MeStamps)
    {
        foreach ($stampPath in $StampPaths)
        {
            Test-Connection-To-URL $cppRestUtil $meStamp$stampPath >> .\CppRestUtilResults.txt
        }
    }
}

function Get-Open-Sockets-And-Owning-Processes
{
    Write-Output "Listing open sockets and owning processes"
    netstat -abno > ListeningSockets.txt
}

function Test-Frontend-Urls
{
    foreach ($meFrontendUrl in $MeFrontendUrls)
    {
        foreach ($port in $Ports)
        {
            $solvedDNS = Resolve-DnsName -Name $meFrontendUrl
            Write-Output "Running IPv4 against ${meFrontendUrl}:${port}" 1>> GlobalStamp_TCPPing.txt
            Test-NetConnection $solvedDNS.IP4Address -port ${port} -InformationLevel "Detailed" 1>> GlobalStamp_TCPPing.txt 2>&1
            Write-Output "Finished running IPv4 against ${meFrontendUrl}:${port}" 1>> GlobalStamp_TCPPing.txt
            Write-Output "Running IPv6 against ${meFrontendUrl}:${port}" 1>> GlobalStamp_TCPPing.txt
            Test-NetConnection $solvedDNS.IP6Address -port ${port} -InformationLevel "Detailed" 1>> GlobalStamp_TCPPing.txt 2>&1
            Write-Output "Finished running IPv6 against ${meFrontendUrl}:${port}" 1>> GlobalStamp_TCPPing.txt
        }
    }
}

function Get-Application-Event-Logs
{
    Write-Output "Collecting application event logs for Level Error and EventID 1000 happened within last one hour..."
    Write-Output "Collecting application event logs for Level Error and EventID 1000 happened within last one hour..." > ApplicationErrorLog.txt
    wevtutil qe Application /q:"*[System[Level=2 and EventID=1000 and TimeCreated[timediff(@SystemTime) <= 3600000]]]" /f:text /rd:true >> ApplicationErrorLog.txt
}

function Get-Raw-And-Aggregated-Metrics
{
    Set-MdmInputOutputProviders-File
    Write-Output "Collecting raw and aggregated metrics, please wait..."
    Invoke-Command "logman start MdmDataCollection -max ${env:MetricCollectionSizeMaxMB} -pf mdmInputOutputProviders.txt -o mdmRaw.etl -ets"
    timeout ${env:MetricCollectionDurationSec} /nobreak
    Invoke-Command "logman stop MdmDataCollection -ets"
    Invoke-Command "Remove-Item mdmInputOutputProviders.txt"

    logman -ets | findstr /i IfxViewerSession > IfxConsumerSessions.txt

    foreach ($ifxConsumerSession in Get-Content -Path .\IfxConsumerSessions.txt)
    {
        Invoke-Command "logman stop $ifxConsumerSession -ets"
    }
}

function Set-MdmInputOutputProviders-File
{
    $content = @(
        "{edc24920-e004-40f6-a8e1-0e6e48f39d84}"
        "{2f23a2a9-0de7-4cb4-a778-fbdf5c1e7372}"
    )
    $pathMdmInputOutputProviders = (Get-Item -Path ".\" -Verbose).FullName | Join-Path -ChildPath 'mdmInputOutputProviders.txt'
    [IO.File]::WriteAllLines($pathMdmInputOutputProviders, $content)
}

function Search-Files-Job([Object[]]$fileNames, [Object[]]$logicalDisks, [String]$outputFile, [String]$currentPath)
{
    $searchFilesFunc = $(Get-Command Search-Files).Definition
    $invokeCommandFunc = $(Get-Command Invoke-Command).Definition
    $scriptBlock =
    {
        param($fileNames, $logicalDisks, $outputFile, $currentPath)

        Set-Location $currentPath
        Invoke-Expression "function Search-Files {$using:searchFilesFunc}"
        Invoke-Expression "function Invoke-Command {$using:invokeCommandFunc}"
        Search-Files -fileNames $fileNames -logicalDisks $logicalDisks -outputFile $outputFile
    }

    $job = Start-Job -ArgumentList $fileNames, $logicalDisks, $outputFile, $currentPath -ScriptBlock $scriptBlock
    $job | Wait-Job -Timeout $env:TimeOutSecondsSearchFiles

    if ($job.State -ne "Completed")
    {
        Write-Warning "$fileNames were searched but they took more than $env:TimeOutSecondsSearchFiles seconds, aborting this search..."
    }
}

function Search-Files([Object[]]$fileNames, [Object[]]$logicalDisks, [String]$outputFile)
{
    foreach($logicalDisk in $logicalDisks)
    {
        foreach($fileName in $fileNames)
        {
            try
            {
                Write-Output "cmd /c dir /s/b ${logicalDisk}\${fileName}"
                cmd /c "dir /s/b ${logicalDisk}\${fileName} > lastDir.txt 2>>dirFailures.txt"
            }
            catch
            {
                "ERROR: cmd /c dir /s/b ${logicalDisk}\${fileName} failed: $_"  >> dirFailures.txt
                Write-Error "ERROR: cmd /c dir /s/b ${logicalDisk}\${fileName} failed: $_"
            }
            Invoke-Command "Get-Content .\lastDir.txt"
            Get-Content .\lastDir.txt >> $outputFile
        }
    }
}

function Get-Cached-Config
{
    Write-Output "Collecting cached configuration from MetricsExtension"
    if (-Not (Test-Path -Path .\MetricsExtension_Configuration_CachedConfig.txt))
    {
        Write-Warning "MetricsExtensionV1_configuration.json was not found in the environment. Cached configuration will not be able to be collected."
    }
    elseif ([String]::IsNullOrWhiteSpace((Get-content .\MetricsExtension_Configuration_CachedConfig.txt)))
    {
        Write-Warning "MetricsExtension_Configuration_CachedConfig.txt is empty. Cached configuration will not be able to be collected."
    }
    else
    {
        try
        {
            $cachedConfigsSet = 0
            foreach ($configuration in Get-Content -Path .\MetricsExtension_Configuration_CachedConfig.txt)
            {
                $cachedConfigsSet++
                Invoke-Command "mkdir .\MetricsExtensionCachedConfig_${cachedConfigsSet}"
                $parentPath = Split-Path -Path $configuration
                Write-Output "xcopy /C ${parentPath}\* .\MetricsExtensionCachedConfig_$cachedConfigsSet"
                Invoke-Command "xcopy /C '${parentPath}\*' '.\MetricsExtensionCachedConfig_$cachedConfigsSet'"
            }
        }
        catch {
            Write-Error "ERROR: MetricsExtension_Configuration_Cached_Config was not retrieved correctly: $_"
        }
    }
}

function Copy-Autopilot-Logs
{
    if (Test-Path -Path D:\Data\logs\local)
    {
        Write-Output "Copying autopilot logs..."
        Invoke-Command "mkdir .\GenevaMetricsExtensionLogs"
        Invoke-Command "Copy-Item -Path (Get-ChildItem D:\Data\logs\local\GenevaMetricsExtension_*.log) -Destination GenevaMetricsExtensionLogs"
        Invoke-Command "mkdir .\GenevaMetricsExtensionHostLogs"
        Invoke-Command "Copy-Item -Path (Get-ChildItem D:\Data\logs\local\GenevaMetricsExtensionHost_*.log) -Destination GenevaMetricsExtensionHostLogs"
    }
    else
    {
        Write-Warning "No autopilot logs were found. If this machine is not an Autopilot machine, this is not an issue."
    }
}

function Get-Autopilot-Ini
{
    if (Test-Path -Path D:\app\autopilot.ini)
    {
        Write-Output "Attempting to collect autopilot.ini..."
        Write-Output "Attempting to collect autopilot.ini..." > CollectAutopilotLogs.txt
        Invoke-Command "xcopy /C D:\app\autopilot.ini >> CollectAutopilotLogs.txt"
    }
    else
    {
        Write-Warning "D:\app\autopilot.ini was not found. If this machine is not an Autopilot machine, this is not an issue."
    }
}


function Convert-Tsf-Logs-To-Csv([String]$table2csv)
{
    if ([string]::IsNullOrEmpty($table2csv))
    {
        Write-Warning "table2csv.exe was not found. The conversion from tsf logs to csv will not be done."
        return
    }
    $tsfCounter = 0
    foreach ($tsfLog in Get-Content -Path .\TsfLogs.txt)
    {
        try
        {
            Write-Output "$table2csv $env:Table2CsvParameters $tsfLog"
            Write-Output "Waiting for Table2Csv to complete..."
            Write-Output "${table2csv} ${env:Table2CsvParameters} ${tsfLog}" >> Table2CsvLogs.txt
            Invoke-Expression "${Table2Csv} ${env:Table2CsvParameters} '${tsfLog}'" >> Table2CsvLogs.txt
        }
        catch
        {
            "ERROR: Command {$table2csv $env:Table2CsvParameters '$tsfLog'} Failed: $_" >> Table2CsvLogs.txt
            Write-Error "ERROR: Command {$table2csv $env:Table2CsvParameters '$tsfLog'} Failed: $_"
        }

        $tsfCounter++
        $csvFullPath = $tsfLog.Replace("tsf","csv")
        $tsfLogFileName = Split-Path $tsfLog -Leaf
        $csvLogFileName = $tsfLogFileName.Replace(".tsf", "_${tsfCounter}.csv")
        try
        {
            Write-Output "Copy-Item '${csvFullPath}' ${csvLogFileName}"
            Invoke-Command "Copy-Item '${csvFullPath}' .\${csvLogFileName} 2>> CsvCopyErrors.txt"
        }
        catch
        {
            "ERROR: Command {failed to copy ${csvFullPath} to .\${csvLogFileName}}: $_" >> CsvCopyErrors.txt
            Write-Error "ERROR: Command {failed to copy ${csvFullPath} to .\${csvLogFileName}}: $_"
        }
    }
}

function Get-Etw-Session-And-IfxMetrics-At-End
{
    tasklist /M IfxMetrics.dll /FO CSV > ProcessLoadingIfxMetrics_At_End.csv
    logman NativeMetricsExtension_Provider -ets > MetricsExtensionEtwSessionAtEnd.txt
}

function Compress-Output([String]$compressedDataOutput, [String]$mdmDataCollectionOutput)
{
    Write-Output "Compressing MDM Data Collection Output ..."
    try
    {
        Invoke-Command "Compress-Archive -Path .\* -DestinationPath ..\$compressedDataOutput"
        Invoke-Command "Set-Location .."
        Invoke-Command "Remove-Item -r -Force $mdmDataCollectionOutput"
        Write-Output "Done -^> MDM Data ready at $pwd\$compressedDataOutput"
    }
    catch
    {
        Write-Error "ERROR: MDM Data Collection Output has not been compressed: $_"
    }
}

function Show-Ending-Message
{
    $date = Get-Date
    Write-Output "End - MDM Data Collection Script - $date"
}

function Invoke-Command([String]$command)
{
    $output = Invoke-Expression $command
    if (Test-Path env:DebugMdmDataCollection)
    {
        Write-Output $output
    }
}

function Test-Connection-To-URL([String]$cppRestUtil, [String]$url)
{
    try
    {
        if ([String]::IsNullOrEmpty($cppRestUtil))
        {
            [System.Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }
            Write-Output "(New-Object System.IO.StreamReader ((([System.Net.WebRequest]::Create($url)).GetResponse()).GetResponseStream())).ReadToEnd()"
            (New-Object System.IO.StreamReader ((([System.Net.WebRequest]::Create($url)).GetResponse()).GetResponseStream())).ReadToEnd()
        }
        else
        {
            Write-Output "'$cppRestUtil' --json $url"
            Invoke-Expression "& '$cppRestUtil' --json $url"
        }
    }
    catch
    {
        "Request to $url failed."
    }
}

function Search-Table2csv([String]$monAgentHostPath)
{
    $envTable2CsvPath = Test-Environment-Variable-Contains-Valid-Directory "Table2CsvPath"
    if (-Not [string]::IsNullOrEmpty($envTable2CsvPath))
    {
        return $envTable2CsvPath
    }

    if (-Not [string]::IsNullOrEmpty($monAgentHostPath) -And $monAgentHostPath.Contains("MonAgentHost.exe"))
    {
        $table2CsvPath = $monAgentHostPath.Replace("MonAgentHost.exe","table2csv.exe")
        if (Test-Path -Path $table2CsvPath)
        {
            return $table2CsvPath
        }
    }

    [void](Search-Files-Job "table2csv.exe" $logicalDisks "Table2csvLocation.txt" "$PSScriptRoot\$mdmDataCollectionOutput")

    if (Test-Path -Path ".\Table2csvLocation.txt")
    {
        $table2CsvPath = Get-Content .\Table2csvLocation.txt | Select-Object -First 1
    }

    return $table2CsvPath
}

function Test-Environment-Variable-Contains-Valid-Directory([String]$environmentVariable)
{
    $environmentVariableValue = [Environment]::GetEnvironmentVariable($environmentVariable)
    if (-Not [String]::IsNullOrEmpty($environmentVariableValue))
    {
        if (Test-Path -Path $environmentVariableValue)
        {
            return $environmentVariableValue
        }
        else
        {
            $fileName = Split-Path -Path $environmentVariableValue -leaf
            Write-Warning "You have specified $environmentVariable : $environmentVariableValue ,but the path does not exist. $fileName will be searched in your current environment given this situation."
        }
    }
}

if ($args[0] -ne "ImportFunctions")
{
    Main
}

# SIG # Begin signature block
# MIInngYJKoZIhvcNAQcCoIInjzCCJ4sCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCAJk50nLbz6JHAg
# 0X8szmCCkhXCe7ZA0HnOHlbVIBvMjKCCDYEwggX/MIID56ADAgECAhMzAAACzI61
# lqa90clOAAAAAALMMA0GCSqGSIb3DQEBCwUAMH4xCzAJBgNVBAYTAlVTMRMwEQYD
# VQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNy
# b3NvZnQgQ29ycG9yYXRpb24xKDAmBgNVBAMTH01pY3Jvc29mdCBDb2RlIFNpZ25p
# bmcgUENBIDIwMTEwHhcNMjIwNTEyMjA0NjAxWhcNMjMwNTExMjA0NjAxWjB0MQsw
# CQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9u
# ZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMR4wHAYDVQQDExVNaWNy
# b3NvZnQgQ29ycG9yYXRpb24wggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIB
# AQCiTbHs68bADvNud97NzcdP0zh0mRr4VpDv68KobjQFybVAuVgiINf9aG2zQtWK
# No6+2X2Ix65KGcBXuZyEi0oBUAAGnIe5O5q/Y0Ij0WwDyMWaVad2Te4r1Eic3HWH
# UfiiNjF0ETHKg3qa7DCyUqwsR9q5SaXuHlYCwM+m59Nl3jKnYnKLLfzhl13wImV9
# DF8N76ANkRyK6BYoc9I6hHF2MCTQYWbQ4fXgzKhgzj4zeabWgfu+ZJCiFLkogvc0
# RVb0x3DtyxMbl/3e45Eu+sn/x6EVwbJZVvtQYcmdGF1yAYht+JnNmWwAxL8MgHMz
# xEcoY1Q1JtstiY3+u3ulGMvhAgMBAAGjggF+MIIBejAfBgNVHSUEGDAWBgorBgEE
# AYI3TAgBBggrBgEFBQcDAzAdBgNVHQ4EFgQUiLhHjTKWzIqVIp+sM2rOHH11rfQw
# UAYDVR0RBEkwR6RFMEMxKTAnBgNVBAsTIE1pY3Jvc29mdCBPcGVyYXRpb25zIFB1
# ZXJ0byBSaWNvMRYwFAYDVQQFEw0yMzAwMTIrNDcwNTI5MB8GA1UdIwQYMBaAFEhu
# ZOVQBdOCqhc3NyK1bajKdQKVMFQGA1UdHwRNMEswSaBHoEWGQ2h0dHA6Ly93d3cu
# bWljcm9zb2Z0LmNvbS9wa2lvcHMvY3JsL01pY0NvZFNpZ1BDQTIwMTFfMjAxMS0w
# Ny0wOC5jcmwwYQYIKwYBBQUHAQEEVTBTMFEGCCsGAQUFBzAChkVodHRwOi8vd3d3
# Lm1pY3Jvc29mdC5jb20vcGtpb3BzL2NlcnRzL01pY0NvZFNpZ1BDQTIwMTFfMjAx
# MS0wNy0wOC5jcnQwDAYDVR0TAQH/BAIwADANBgkqhkiG9w0BAQsFAAOCAgEAeA8D
# sOAHS53MTIHYu8bbXrO6yQtRD6JfyMWeXaLu3Nc8PDnFc1efYq/F3MGx/aiwNbcs
# J2MU7BKNWTP5JQVBA2GNIeR3mScXqnOsv1XqXPvZeISDVWLaBQzceItdIwgo6B13
# vxlkkSYMvB0Dr3Yw7/W9U4Wk5K/RDOnIGvmKqKi3AwyxlV1mpefy729FKaWT7edB
# d3I4+hldMY8sdfDPjWRtJzjMjXZs41OUOwtHccPazjjC7KndzvZHx/0VWL8n0NT/
# 404vftnXKifMZkS4p2sB3oK+6kCcsyWsgS/3eYGw1Fe4MOnin1RhgrW1rHPODJTG
# AUOmW4wc3Q6KKr2zve7sMDZe9tfylonPwhk971rX8qGw6LkrGFv31IJeJSe/aUbG
# dUDPkbrABbVvPElgoj5eP3REqx5jdfkQw7tOdWkhn0jDUh2uQen9Atj3RkJyHuR0
# GUsJVMWFJdkIO/gFwzoOGlHNsmxvpANV86/1qgb1oZXdrURpzJp53MsDaBY/pxOc
# J0Cvg6uWs3kQWgKk5aBzvsX95BzdItHTpVMtVPW4q41XEvbFmUP1n6oL5rdNdrTM
# j/HXMRk1KCksax1Vxo3qv+13cCsZAaQNaIAvt5LvkshZkDZIP//0Hnq7NnWeYR3z
# 4oFiw9N2n3bb9baQWuWPswG0Dq9YT9kb+Cs4qIIwggd6MIIFYqADAgECAgphDpDS
# AAAAAAADMA0GCSqGSIb3DQEBCwUAMIGIMQswCQYDVQQGEwJVUzETMBEGA1UECBMK
# V2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0
# IENvcnBvcmF0aW9uMTIwMAYDVQQDEylNaWNyb3NvZnQgUm9vdCBDZXJ0aWZpY2F0
# ZSBBdXRob3JpdHkgMjAxMTAeFw0xMTA3MDgyMDU5MDlaFw0yNjA3MDgyMTA5MDla
# MH4xCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdS
# ZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xKDAmBgNVBAMT
# H01pY3Jvc29mdCBDb2RlIFNpZ25pbmcgUENBIDIwMTEwggIiMA0GCSqGSIb3DQEB
# AQUAA4ICDwAwggIKAoICAQCr8PpyEBwurdhuqoIQTTS68rZYIZ9CGypr6VpQqrgG
# OBoESbp/wwwe3TdrxhLYC/A4wpkGsMg51QEUMULTiQ15ZId+lGAkbK+eSZzpaF7S
# 35tTsgosw6/ZqSuuegmv15ZZymAaBelmdugyUiYSL+erCFDPs0S3XdjELgN1q2jz
# y23zOlyhFvRGuuA4ZKxuZDV4pqBjDy3TQJP4494HDdVceaVJKecNvqATd76UPe/7
# 4ytaEB9NViiienLgEjq3SV7Y7e1DkYPZe7J7hhvZPrGMXeiJT4Qa8qEvWeSQOy2u
# M1jFtz7+MtOzAz2xsq+SOH7SnYAs9U5WkSE1JcM5bmR/U7qcD60ZI4TL9LoDho33
# X/DQUr+MlIe8wCF0JV8YKLbMJyg4JZg5SjbPfLGSrhwjp6lm7GEfauEoSZ1fiOIl
# XdMhSz5SxLVXPyQD8NF6Wy/VI+NwXQ9RRnez+ADhvKwCgl/bwBWzvRvUVUvnOaEP
# 6SNJvBi4RHxF5MHDcnrgcuck379GmcXvwhxX24ON7E1JMKerjt/sW5+v/N2wZuLB
# l4F77dbtS+dJKacTKKanfWeA5opieF+yL4TXV5xcv3coKPHtbcMojyyPQDdPweGF
# RInECUzF1KVDL3SV9274eCBYLBNdYJWaPk8zhNqwiBfenk70lrC8RqBsmNLg1oiM
# CwIDAQABo4IB7TCCAekwEAYJKwYBBAGCNxUBBAMCAQAwHQYDVR0OBBYEFEhuZOVQ
# BdOCqhc3NyK1bajKdQKVMBkGCSsGAQQBgjcUAgQMHgoAUwB1AGIAQwBBMAsGA1Ud
# DwQEAwIBhjAPBgNVHRMBAf8EBTADAQH/MB8GA1UdIwQYMBaAFHItOgIxkEO5FAVO
# 4eqnxzHRI4k0MFoGA1UdHwRTMFEwT6BNoEuGSWh0dHA6Ly9jcmwubWljcm9zb2Z0
# LmNvbS9wa2kvY3JsL3Byb2R1Y3RzL01pY1Jvb0NlckF1dDIwMTFfMjAxMV8wM18y
# Mi5jcmwwXgYIKwYBBQUHAQEEUjBQME4GCCsGAQUFBzAChkJodHRwOi8vd3d3Lm1p
# Y3Jvc29mdC5jb20vcGtpL2NlcnRzL01pY1Jvb0NlckF1dDIwMTFfMjAxMV8wM18y
# Mi5jcnQwgZ8GA1UdIASBlzCBlDCBkQYJKwYBBAGCNy4DMIGDMD8GCCsGAQUFBwIB
# FjNodHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20vcGtpb3BzL2RvY3MvcHJpbWFyeWNw
# cy5odG0wQAYIKwYBBQUHAgIwNB4yIB0ATABlAGcAYQBsAF8AcABvAGwAaQBjAHkA
# XwBzAHQAYQB0AGUAbQBlAG4AdAAuIB0wDQYJKoZIhvcNAQELBQADggIBAGfyhqWY
# 4FR5Gi7T2HRnIpsLlhHhY5KZQpZ90nkMkMFlXy4sPvjDctFtg/6+P+gKyju/R6mj
# 82nbY78iNaWXXWWEkH2LRlBV2AySfNIaSxzzPEKLUtCw/WvjPgcuKZvmPRul1LUd
# d5Q54ulkyUQ9eHoj8xN9ppB0g430yyYCRirCihC7pKkFDJvtaPpoLpWgKj8qa1hJ
# Yx8JaW5amJbkg/TAj/NGK978O9C9Ne9uJa7lryft0N3zDq+ZKJeYTQ49C/IIidYf
# wzIY4vDFLc5bnrRJOQrGCsLGra7lstnbFYhRRVg4MnEnGn+x9Cf43iw6IGmYslmJ
# aG5vp7d0w0AFBqYBKig+gj8TTWYLwLNN9eGPfxxvFX1Fp3blQCplo8NdUmKGwx1j
# NpeG39rz+PIWoZon4c2ll9DuXWNB41sHnIc+BncG0QaxdR8UvmFhtfDcxhsEvt9B
# xw4o7t5lL+yX9qFcltgA1qFGvVnzl6UJS0gQmYAf0AApxbGbpT9Fdx41xtKiop96
# eiL6SJUfq/tHI4D1nvi/a7dLl+LrdXga7Oo3mXkYS//WsyNodeav+vyL6wuA6mk7
# r/ww7QRMjt/fdW1jkT3RnVZOT7+AVyKheBEyIXrvQQqxP/uozKRdwaGIm1dxVk5I
# RcBCyZt2WwqASGv9eZ/BvW1taslScxMNelDNMYIZczCCGW8CAQEwgZUwfjELMAkG
# A1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQx
# HjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEoMCYGA1UEAxMfTWljcm9z
# b2Z0IENvZGUgU2lnbmluZyBQQ0EgMjAxMQITMwAAAsyOtZamvdHJTgAAAAACzDAN
# BglghkgBZQMEAgEFAKCBrjAZBgkqhkiG9w0BCQMxDAYKKwYBBAGCNwIBBDAcBgor
# BgEEAYI3AgELMQ4wDAYKKwYBBAGCNwIBFTAvBgkqhkiG9w0BCQQxIgQgj9lAKLeN
# 9v1CRSI97H7rg1SEDbBDU7b/dbKFWkYBLbQwQgYKKwYBBAGCNwIBDDE0MDKgFIAS
# AE0AaQBjAHIAbwBzAG8AZgB0oRqAGGh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbTAN
# BgkqhkiG9w0BAQEFAASCAQB5sJP7UkVC1G2XKkQe58ejW9AQlh26XIx5nxNtIsnY
# VfKB5/IydZTQ2/c35fKD3VyzTm9EQxLZ9eojAVn8+hXYwxi9uLj1daaWEHXVJHA2
# VpOVXI/1h43m+VCUIu96aFN221Bc3gTheTjgj0277i236mkNjSbQPd/LCm/c3cOr
# 5MIhQV0D6aZ4eVIABS0tJdm7wz7vHbeNe8xcQ1NzIxZ/bnR3xqCINAIfGiubLHD6
# O7MJEq45VHru5Pkuf8Xu1K+AA+X4dvNFlkBuKC7+RP+e9bGH4LocF0KA+yxOMKJD
# UblbLd0Lb78HjOmFQGyswRsxR9rJdg8bOEe+hrgGsuH3oYIW/TCCFvkGCisGAQQB
# gjcDAwExghbpMIIW5QYJKoZIhvcNAQcCoIIW1jCCFtICAQMxDzANBglghkgBZQME
# AgEFADCCAVEGCyqGSIb3DQEJEAEEoIIBQASCATwwggE4AgEBBgorBgEEAYRZCgMB
# MDEwDQYJYIZIAWUDBAIBBQAEIPj55fyh4aSpLW60uBqWY3qSUGUWf14012wzgRRt
# yftUAgZjmwapkhwYEzIwMjMwMTA1MjExNzMzLjM5OVowBIACAfSggdCkgc0wgcox
# CzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRt
# b25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xJTAjBgNVBAsTHE1p
# Y3Jvc29mdCBBbWVyaWNhIE9wZXJhdGlvbnMxJjAkBgNVBAsTHVRoYWxlcyBUU1Mg
# RVNOOjIyNjQtRTMzRS03ODBDMSUwIwYDVQQDExxNaWNyb3NvZnQgVGltZS1TdGFt
# cCBTZXJ2aWNloIIRVDCCBwwwggT0oAMCAQICEzMAAAHBPqCDnOAJr8UAAQAAAcEw
# DQYJKoZIhvcNAQELBQAwfDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0
# b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3Jh
# dGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRpbWUtU3RhbXAgUENBIDIwMTAwHhcN
# MjIxMTA0MTkwMTI3WhcNMjQwMjAyMTkwMTI3WjCByjELMAkGA1UEBhMCVVMxEzAR
# BgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1p
# Y3Jvc29mdCBDb3Jwb3JhdGlvbjElMCMGA1UECxMcTWljcm9zb2Z0IEFtZXJpY2Eg
# T3BlcmF0aW9uczEmMCQGA1UECxMdVGhhbGVzIFRTUyBFU046MjI2NC1FMzNFLTc4
# MEMxJTAjBgNVBAMTHE1pY3Jvc29mdCBUaW1lLVN0YW1wIFNlcnZpY2UwggIiMA0G
# CSqGSIb3DQEBAQUAA4ICDwAwggIKAoICAQDksdczJ3DaFQLiklTQjm48mcx5Gbws
# oLjFogO7cXHHciln9Z7apcuPg06ajD9Y8V5ji9pPj9LhP3GgOwUaDnAQkzo4tlV9
# rsFQ27S0O3iuSXtAFg0fPPqlyv1vBqraqbvHo/3KLlbRjyyOiP5BOC2aZejEKg1e
# EnWgboZuoANBcNmRNwOMgCK14TpPGuEGkhvt7q6mJ9MZk19wKE9+7MerrUVIjAnR
# cLFxpHUHACVIqFv81Q65AY+v1nN3o6chwD5Fy3HAqB84oH1pYQQeW3SOEoqCkQG9
# wmcww/5ZpPCYyGhvV76GgIQXH+cjRge6mLrTzaQV00WtoTvaaw5hCvCtTJYJ5KY3
# bTYtkOlPPFlW3LpCsE6T5/4ESuxH4zl6+Qq5RNZUkcje+02Bvorn6CToS5DDShyw
# N2ymI+n6qXEFpbnTJRuvrCd/NiMmHtCQ9x8EhlskCFZAdpXS5LdPs6Q5t0KywJEx
# YftVZQB5Jt6a5So5cJHut2kVN9j9Jco72UIhAEBBKH7DPCHlm/Vv6NPbNbBWXzYH
# LdgeZJPxvwIqdFdIKMu2CjLLsREvCRvM8iQJ8FdzJWd4LXDb/BSeo+ICMrTBB/O1
# 9cV+gxCvxhRwsecC16Tw5U0+5EhXptwRFsXqu0VeaeOMPhnBXEhn8czhyN5UawTC
# QUD1dPOpf1bU/wIDAQABo4IBNjCCATIwHQYDVR0OBBYEFF+vYwnrHvIT6A/m5f3F
# YZPClEL6MB8GA1UdIwQYMBaAFJ+nFV0AXmJdg/Tl0mWnG1M1GelyMF8GA1UdHwRY
# MFYwVKBSoFCGTmh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2lvcHMvY3JsL01p
# Y3Jvc29mdCUyMFRpbWUtU3RhbXAlMjBQQ0ElMjAyMDEwKDEpLmNybDBsBggrBgEF
# BQcBAQRgMF4wXAYIKwYBBQUHMAKGUGh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9w
# a2lvcHMvY2VydHMvTWljcm9zb2Z0JTIwVGltZS1TdGFtcCUyMFBDQSUyMDIwMTAo
# MSkuY3J0MAwGA1UdEwEB/wQCMAAwEwYDVR0lBAwwCgYIKwYBBQUHAwgwDQYJKoZI
# hvcNAQELBQADggIBAF+6JoGCx5we8z3RFmJMOV8duUvT2v1f7mr1yS4xHQGzVKvk
# HYwAuFPljRHeCAu59FfpFBBtJztbFFcgyvm0USAHnPL/tiDzUKfZ2FN/UbOMJvv+
# ffC0lIa2vZDAexrV6FhZ0x+L4RMugRfUbv1U8WuzS3oaLCmvvi2/4IsTezqbXRU7
# B7zTA/jK5Pd6IV+pFXymhQVJ0vbByWBAqhLBsKlsmU0L8RJoNBttAWWL247mPZ/8
# btLhMwb+DLLG8xDlAm6L0XDazuqSWajNChfYCHhoq5sp739Vm96IRM1iXUBk+PSS
# PWDnVU3JaO8fD4fPXFl6RYil8xdASLTCsZ1Z6JbiLyX3atjdlt0ewSsVirOHoVEU
# 55eBrM2x+QubDL5MrXuYDsJMRTNoBYyrn5/0rhj/eaEHivpSuKy2Ral2Q9YSjxv2
# 1uR0pJjTQT4VLkNS2OAB0JpEE1oG7xwVgJsSuH2uhYPFz4iy/zIxABQO4TBdLLQT
# GcgCVxUiuHMvjQ6wbZxrlHkGAB68Y/UeP16PiX/L5KHQdVw303ouY8OYj8xpTasR
# ntj6NF8JnV36XkMRJ0tcjENPKxheRP7dUz/XOHrLazRmxv/e89oaenbN6PB/ZiUZ
# aXVekKE1lN6UXl44IJ9LNRSfeod7sjLIMqFqGBucqmbBwSQxUGz5EdtWQ1aoMIIH
# cTCCBVmgAwIBAgITMwAAABXF52ueAptJmQAAAAAAFTANBgkqhkiG9w0BAQsFADCB
# iDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1Jl
# ZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEyMDAGA1UEAxMp
# TWljcm9zb2Z0IFJvb3QgQ2VydGlmaWNhdGUgQXV0aG9yaXR5IDIwMTAwHhcNMjEw
# OTMwMTgyMjI1WhcNMzAwOTMwMTgzMjI1WjB8MQswCQYDVQQGEwJVUzETMBEGA1UE
# CBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9z
# b2Z0IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQ
# Q0EgMjAxMDCCAiIwDQYJKoZIhvcNAQEBBQADggIPADCCAgoCggIBAOThpkzntHIh
# C3miy9ckeb0O1YLT/e6cBwfSqWxOdcjKNVf2AX9sSuDivbk+F2Az/1xPx2b3lVNx
# WuJ+Slr+uDZnhUYjDLWNE893MsAQGOhgfWpSg0S3po5GawcU88V29YZQ3MFEyHFc
# UTE3oAo4bo3t1w/YJlN8OWECesSq/XJprx2rrPY2vjUmZNqYO7oaezOtgFt+jBAc
# nVL+tuhiJdxqD89d9P6OU8/W7IVWTe/dvI2k45GPsjksUZzpcGkNyjYtcI4xyDUo
# veO0hyTD4MmPfrVUj9z6BVWYbWg7mka97aSueik3rMvrg0XnRm7KMtXAhjBcTyzi
# YrLNueKNiOSWrAFKu75xqRdbZ2De+JKRHh09/SDPc31BmkZ1zcRfNN0Sidb9pSB9
# fvzZnkXftnIv231fgLrbqn427DZM9ituqBJR6L8FA6PRc6ZNN3SUHDSCD/AQ8rdH
# GO2n6Jl8P0zbr17C89XYcz1DTsEzOUyOArxCaC4Q6oRRRuLRvWoYWmEBc8pnol7X
# KHYC4jMYctenIPDC+hIK12NvDMk2ZItboKaDIV1fMHSRlJTYuVD5C4lh8zYGNRiE
# R9vcG9H9stQcxWv2XFJRXRLbJbqvUAV6bMURHXLvjflSxIUXk8A8FdsaN8cIFRg/
# eKtFtvUeh17aj54WcmnGrnu3tz5q4i6tAgMBAAGjggHdMIIB2TASBgkrBgEEAYI3
# FQEEBQIDAQABMCMGCSsGAQQBgjcVAgQWBBQqp1L+ZMSavoKRPEY1Kc8Q/y8E7jAd
# BgNVHQ4EFgQUn6cVXQBeYl2D9OXSZacbUzUZ6XIwXAYDVR0gBFUwUzBRBgwrBgEE
# AYI3TIN9AQEwQTA/BggrBgEFBQcCARYzaHR0cDovL3d3dy5taWNyb3NvZnQuY29t
# L3BraW9wcy9Eb2NzL1JlcG9zaXRvcnkuaHRtMBMGA1UdJQQMMAoGCCsGAQUFBwMI
# MBkGCSsGAQQBgjcUAgQMHgoAUwB1AGIAQwBBMAsGA1UdDwQEAwIBhjAPBgNVHRMB
# Af8EBTADAQH/MB8GA1UdIwQYMBaAFNX2VsuP6KJcYmjRPZSQW9fOmhjEMFYGA1Ud
# HwRPME0wS6BJoEeGRWh0dHA6Ly9jcmwubWljcm9zb2Z0LmNvbS9wa2kvY3JsL3By
# b2R1Y3RzL01pY1Jvb0NlckF1dF8yMDEwLTA2LTIzLmNybDBaBggrBgEFBQcBAQRO
# MEwwSgYIKwYBBQUHMAKGPmh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2kvY2Vy
# dHMvTWljUm9vQ2VyQXV0XzIwMTAtMDYtMjMuY3J0MA0GCSqGSIb3DQEBCwUAA4IC
# AQCdVX38Kq3hLB9nATEkW+Geckv8qW/qXBS2Pk5HZHixBpOXPTEztTnXwnE2P9pk
# bHzQdTltuw8x5MKP+2zRoZQYIu7pZmc6U03dmLq2HnjYNi6cqYJWAAOwBb6J6Gng
# ugnue99qb74py27YP0h1AdkY3m2CDPVtI1TkeFN1JFe53Z/zjj3G82jfZfakVqr3
# lbYoVSfQJL1AoL8ZthISEV09J+BAljis9/kpicO8F7BUhUKz/AyeixmJ5/ALaoHC
# gRlCGVJ1ijbCHcNhcy4sa3tuPywJeBTpkbKpW99Jo3QMvOyRgNI95ko+ZjtPu4b6
# MhrZlvSP9pEB9s7GdP32THJvEKt1MMU0sHrYUP4KWN1APMdUbZ1jdEgssU5HLcEU
# BHG/ZPkkvnNtyo4JvbMBV0lUZNlz138eW0QBjloZkWsNn6Qo3GcZKCS6OEuabvsh
# VGtqRRFHqfG3rsjoiV5PndLQTHa1V1QJsWkBRH58oWFsc/4Ku+xBZj1p/cvBQUl+
# fpO+y/g75LcVv7TOPqUxUYS8vwLBgqJ7Fx0ViY1w/ue10CgaiQuPNtq6TPmb/wrp
# NPgkNWcr4A245oyZ1uEi6vAnQj0llOZ0dFtq0Z4+7X6gMTN9vMvpe784cETRkPHI
# qzqKOghif9lwY1NNje6CbaUFEMFxBmoQtB1VM1izoXBm8qGCAsswggI0AgEBMIH4
# oYHQpIHNMIHKMQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4G
# A1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSUw
# IwYDVQQLExxNaWNyb3NvZnQgQW1lcmljYSBPcGVyYXRpb25zMSYwJAYDVQQLEx1U
# aGFsZXMgVFNTIEVTTjoyMjY0LUUzM0UtNzgwQzElMCMGA1UEAxMcTWljcm9zb2Z0
# IFRpbWUtU3RhbXAgU2VydmljZaIjCgEBMAcGBSsOAwIaAxUARIo61IrtFVUr5KL5
# qoV3RhJj5U+ggYMwgYCkfjB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGlu
# Z3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBv
# cmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0EgMjAxMDAN
# BgkqhkiG9w0BAQUFAAIFAOdhNFIwIhgPMjAyMzAxMDUxOTM0NDJaGA8yMDIzMDEw
# NjE5MzQ0MlowdDA6BgorBgEEAYRZCgQBMSwwKjAKAgUA52E0UgIBADAHAgEAAgIN
# ezAHAgEAAgIRtDAKAgUA52KF0gIBADA2BgorBgEEAYRZCgQCMSgwJjAMBgorBgEE
# AYRZCgMCoAowCAIBAAIDB6EgoQowCAIBAAIDAYagMA0GCSqGSIb3DQEBBQUAA4GB
# ABXXcWH+/d67ZQhhAUqQ9wt+R4FDZ1akDD2bSYI0z0iTfKuzce588BSTOohMeVaT
# dRNYic2KAAqiUH9l//I+STL14w7vM2I3KJtzuGQpW0dLxNCY7rJc9ULR/cEguZGI
# dJl4i3aJ7n8IFkfFqxl0Hj/vq0B9gedFmwJismsM+3gQMYIEDTCCBAkCAQEwgZMw
# fDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1Jl
# ZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UEAxMd
# TWljcm9zb2Z0IFRpbWUtU3RhbXAgUENBIDIwMTACEzMAAAHBPqCDnOAJr8UAAQAA
# AcEwDQYJYIZIAWUDBAIBBQCgggFKMBoGCSqGSIb3DQEJAzENBgsqhkiG9w0BCRAB
# BDAvBgkqhkiG9w0BCQQxIgQgtfpXoTjCm0Hhgjtt+Pjoqzk/y1bY/bTIR3cR3e0z
# bx0wgfoGCyqGSIb3DQEJEAIvMYHqMIHnMIHkMIG9BCAKuSDq2Bgd5KAiw3eilHbP
# sQTFYDRiSKuS9VhJMGB21DCBmDCBgKR+MHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQI
# EwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3Nv
# ZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBD
# QSAyMDEwAhMzAAABwT6gg5zgCa/FAAEAAAHBMCIEICvZYg9dvXt65ey5zifNeeJj
# v7NoFvlDcT9liXcNOmjnMA0GCSqGSIb3DQEBCwUABIICAMPfv+DDTqG8MCjEKeMG
# uMhgVUHjMb9xQTm3/gW50GG4HkRvU7aVQNCKp+5TFGC0TxCOy77w1WpmvbZXxGST
# X3qSXENA/j7fIeVRJdbcWb34VQMExbWD1AoWSF+jtuo/FjtLWDetOHgBh/XkIAhm
# VonTxWnSojWfhPBhqG0FCWhTGy3+AvVyoKI5VRBpsc3tnAYn0Op85zi+tpfehJP2
# GdAqEo0yTz3Y9sghnH802lZ1zDR5lUBmT9XcJsirJRHjK+Dx6kEYDv+cHqa6THlm
# 6/UwFRh05R9B2xEfqM7o3Kwbq34M/TCkPp06IeM/sX5vWLU5Hm3UhGdPwXXx5Ak6
# bFvwRKBQjlGs7M2hAzwGLaVz21HcnM9l/EiMNWMDzwEuj2BQK5M7bpXFViGugfSx
# NREnj0qirn2Zi1B7RkBASJWfY62lpqhX4GMHnOJS/+xMtvDgazlqfZk672iLFq/1
# UXtuv/RiiILpVgmVBZQyyrGl98/CoTCj6euCcTj3E2cSoA1mdl/8maW69s1VTsii
# c6RaxB/AGeWUk6TIB935nNlJFGLW/6wvHx+EQHJoqSO8CJp1d4sy55WxVtPsmm2e
# GOJmqQR50lqwshnvQ5TOofoShD/rJYbJXQ5S+7YW70nKcD9/lDooK5Fg4iSJ1Kja
# hellbwt1M42+hK+PXg5Z6Gsh
# SIG # End signature block
