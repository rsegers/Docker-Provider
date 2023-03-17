<#----------------------------------------------------------------------------------------------------------------------------------- 
:: <copyright file="collectDiagnostics.ps1" company="Microsoft">
::     Copyright (c) Microsoft Corporation.  All rights reserved. 
:: </copyright> 
:: 
:: <summary> 
:: Tool to collect Diagonostic Data specific to AzSecPack.
:: </summary>
:: ----------------------------------------------------------------------------------------------------------------------------------

::------------------------------------------------------------------------------------------------------------------------------------
::	 												collectDiagnostics.ps1
::------------------------------------------------------------------------------------------------------------------------------------
::-- Tool to collect Diagonostic Data specific to ASM.
::-- This tool can be either run via command line manually
::-- or using some other process to launch it, it gets 
::-- all the logs/relevant information needed to determine
::-- what might be wrong on a particular node.
::-- Usage : 
::--	(i).\collectDiagnostics.ps1 <path to Monitoring Data Directory> 
::--    (ii).\collectDiagnostics.ps1 -monitoringPath <path to Monitoring Data Directory> -readLogPath <path to log file Directory> 
::--                                 -outputLogPath <path to output Directory>
::--        readLogPath and outputLogPath are not mandatory
::-- 1. Cleans up the diagnosticsData directory if exists else creates one
::-- 2. Collects all the logs and copies them to the diagnosticsData dir:
::--	a. List of all processes running on the system in : tasklist.txt
::--	b. Gets the list of all publishers on the machine in : AllPublishers.txt
::--	c. Executes command "wevtutil gp Microsoft-Azure-Security-Scanner" 
::--		and the output is copied to : ASMPublisher.txt
::--	d. Checks whether the Antimalware engine is running; executes command
::--		"sc query msmpsvc" and copies output to msmpsvc.txt 
::--	e. Executes command "wevtutil gp Microsoft-Windows-AppLocker" 
::--		and the output is copied to : AppLockerPublisher.txt
::--    f. Copies local AppLocker events from all four Applocker channels into diagnostics data directory 
::--    g. Gets local and effective AppLocker policy in xml format and copies policy to AppLockerLocalPolicy.xml and AppLockerEffectivePolicy.xml
::--    h. Copies local CodeIntegrity events from all four CodeIntegrity channels into diagnostics data directory 
::--    i. Gets local CodeIntegrity policy(Sipolicy.p7b)
::--    j. Copies the contents of <MonitoringDataDirectory>/Packages,Configurations,Packets to diagnosticsData dir
::--    k. Converts Scanner specific MA tables AsmScannerData/AsmScannerDefaultEvents/AsmScannerStatusEvents/TraceEvents from tsf to CSV
::-- 		and copies the corresponding CSV files as is to the dataDiagnostics dir.
::--    l. Converts AppLocker and CodeIntegrity specific MA tables LocalALEXE, LocalALDel, LocalALAPPEXE, LocalALAPPDEP,
            LocalALSCR",LocalALSvcMgr,LocalCIdel,LocalCIExe,LocalCIScr from tsf to CSV
::-- 		and copies the corresponding CSV files as is to the dataDiagnostics dir.
::--    m. Copy all the *.log, *xml, *.json, *er files from current dir, readLogPath, $env:APPDATA\AzureSecurityPack, $env:TEMP\AzureSecurityPack 
::--        to $outputLogPath\currentDir, $outputLogPath\specifiedDirLog, $outputLogPath\appdataLog, $outputLogPath\tempLog.
::--    n. Get SecurityScanMgr and MonAgentHost process details and log to SecurityScanMgrProcessInfo.log and MonAgentHostProcessInfo.log;
::--    o. Status of copying table and logs are in copyTableStatus.log, copyLogStatus.log and collectDiagnosticsStatusLog.log
::-- ******************************************************************************************************************************************
::-- 3.	Once all the relevant information is copied over to the dataDiagnostics dir,  
::--	we zip it : %computername%_diagnosticsData_%currentDate%_%currentTime%.zip
::-- 4. This zip file can be pulled to get all the relevant diagnostic data from a particular node.#>

Param([Parameter(Mandatory=$true)]
      [string] $monitoringPath = "", 
      [string] $readLogPath = "",
      [string] $outputLogPath = "")

$logFile = "collectDiagnosticsStatusLog.log"
# Set up output path
if ($outputLogPath = "") { 
    $outputLogPath = $env:SystemDrive;   
}

$outputPath = "$outputLogPath\diagnosticsData";
$zipDir = "$outputLogPath\DiagnosticsZipDir";

$currentDate = (Get-Date).ToString("MMddyyyy");
$currentTime = (Get-Date).ToString("HHmm");
$computerName = $env:COMPUTERNAME;
$zipPath = $zipDir + "\" + $computerName + "_diagnosticsData_" + $currentDate + "_" + $currentTime + ".zip";

# Helper function
# Set file/dir inheritance to false and remove user access
Function SetFilePermission (
		[parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]$path
	)
{
    icacls $path /inheritance:d /T;
	icacls $path /remove:g Users /T;
}

# Helper function
# Get Process id, image path, args and EnvironmentVariables for a process
Function GetProcessDetail(
        [parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]$processName
    ){

    $processActive = Get-Process -Name $processName -ErrorAction SilentlyContinue
    if($processActive -eq $null) {
        Write-Output "Process $processName not Found"
    }else { 
        Write-Output "Get infomation for process $processName :"
        $processDetails = Get-Process -Name $processName;
        foreach ($processDetail in $processDetails) { 
            Write-Output "PID = " $processDetail.Id;
            Write-Output "ImagePath = " $processDetail.Path;
            $startInfo = $processDetail.StartInfo;
            Write-Output "Args = "
            foreach($arg in $startInfo.Arguments) {
                Write-Output $arg;
            }
            Write-Output "EnvironmentVariables ="
            foreach ($envVaribable in $startInfo.EnvironmentVariables.Keys) {
                $value = $startInfo.EnvironmentVariables[$envVaribable];
                Write-Output "$envVaribable : $value";
            }            
        }
    }
}

# Helper function
# Convert tsf to csv and copy it to output path
Function ConvertAndCopyTablesAzSecPack (
		[parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]$tablePath,
        [parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]$table2CSVPath,
        [parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]$tsfFileList
	){

    Tee-Object $outputPath\$logFile -Append -InputObject "ConvertAndCopyTablesAzSecPack function called the table path passed as an argument is $tablePath and table2csv path is $table2CSVPath" | Write-Host
	Tee-Object $outputPath\$logFile -Append -InputObject "The outputpath is $outputPath" | Write-Host
	Tee-Object $outputPath\$logFile -Append -InputObject "The table2csvpath is $table2CSVPath" | Write-Host
    
    foreach ($tsfFile in $tsfFileList) {
        if (Test-Path "$tablePath\$tsfFile.tsf") {
            Tee-Object $outputPath\$logFile -Append -InputObject "Found $tablePath\$tsfFile.tsf trying to convert it to CSV and copying to diagnosticData directory." | Write-Host
            Tee-Object $outputPath\$logFile -Append -InputObject "The command is $table2CSVPath\table2csv.exe $tablePath\$tsfFile.tsf" | Write-Host		    
		    & $table2CSVPath\table2csv.exe $tablePath\$tsfFile.tsf
		    robocopy $tablePath $outputPath "$tsfFile.csv" /log+:$outputPath\copyTableStatus.log /tee
	    }else{
            Tee-Object $outputPath\$logFile -Append -InputObject "$tablePath\$tsfFile.tsf not found." | Write-Host
        }
    }    
}

if (Test-Path $outputPath) {
   Remove-Item -r $outputPath;        
}

New-Item $outputPath -type directory;
SetFilePermission -path $outputPath;      

if (Test-Path $zipPath) {
    Remove-Item -r $zipPath;
}

if ((Test-Path $zipDir) -eq $false) {
    New-Item $zipDir -type directory;  
    SetFilePermission -path $zipDir;
}

Tee-Object $outputPath\$logFile -Append -InputObject "Collect the list of processes running on the system right now at : $outputPath\tasklist.txt." | Write-Host
tasklist > $outputPath\tasklist.txt

Tee-Object $outputPath\$logFile -Append -InputObject "Collect the list of all the Publishers on this node at : $outputPath\AllPublishers.txt." | Write-Host
wevtutil ep > $outputPath\AllPublishers.txt

Tee-Object $outputPath\$logFile -Append -InputObject "Verify whether the Security-Scanner Publisher exists; results at : $outputPath\ASMPublisher.txt." | Write-Host
wevtutil gp Microsoft-Azure-Security-Scanner > $outputPath\ASMPublisher.txt 2>&1

Tee-Object $outputPath\$logFile -Append -InputObject "Verify whether the Microsoft AntiMalware engine is running on the system; result at : $outputPath\msmpsvc.txt." | Write-Host
sc query msmpsvc > $outputPath\msmpsvc.txt 2>&1

Tee-Object $outputPath\$logFile -Append -InputObject "Verify whether the AppLocker Publisher exists; results at : $outputPath\AppLockerPublisher.txt." | Write-Host
wevtutil gp Microsoft-Windows-AppLocker > $outputPath\AppLockerPublisher.txt

Tee-Object $outputPath\$logFile -Append -InputObject "Copy AppLocker event files to $outputPath" | Write-Host
wevtutil epl "Microsoft-windows-AppLocker/EXE and DLL" $outputPath\AppLockerEXEDLL.evtx
wevtutil epl "Microsoft-Windows-AppLocker/MSI and Script" $outputPath\AppLockerMSISCRIPT.evtx
wevtutil epl "Microsoft-Windows-AppLocker/Packaged app-Deployment" $outputPath\AppLockerPKGAPPDEPLOY.evtx
wevtutil epl "Microsoft-Windows-AppLocker/Packaged app-Execution" $outputPath\AppLockerPKGAPPEXEC.evtx

Tee-Object $outputPath\$logFile -Append -InputObject "Get local AppLocker policy; results at : $outputPath\AppLockerLocalPolicy.xml." | Write-Host
Get-AppLockerPolicy -Local -Xml > $outputPath\AppLockerLocalPolicy.xml

Tee-Object $outputPath\$logFile -Append -InputObject "Get effective AppLocker policy; results at : $outputPath\AppLockerEffectivePolicy.xml." | Write-Host
Get-AppLockerPolicy -Effective -Xml > $outputPath\AppLockerEffectivePolicy.xml

Tee-Object $outputPath\$logFile -Append -InputObject "Copy CodeIntegrity event files to $outputPath" | Write-Host
wevtutil epl "Microsoft-Windows-CodeIntegrity/Operational" $outputPath\CodeIntegrityEXEDLL.evtx
wevtutil gp Microsoft-Windows-CodeIntegrity > $outputPath\CodeIntegrityPublisher.txt

if (Test-Path $env:windir\\System32\\CodeIntegrity\\SiPolicy.p7b) {
    robocopy $env:windir\\System32\\CodeIntegrity $outputPath SiPolicy.p7b
}
else {
    Tee-Object $outputPath\$logFile -Append  -InputObject "The CodeIntegrity policy SiPolicy.p7b not found." | Write-Host
}

$dg = Get-CimInstance -ClassName Win32_DeviceGuard -Namespace root\Microsoft\Windows\DeviceGuard
Tee-Object $outputPath\$logFile -Append -InputObject ("{0} : {1}" -f "CodeIntegrityPolicyEnforcementStatus", $dg.CodeIntegrityPolicyEnforcementStatus) | Write-Host
Tee-Object $outputPath\$logFile -Append -InputObject ("{0}: {1}" -f "UsermodeCodeIntegrityPolicyEnforcementStatus", $dg.UsermodeCodeIntegrityPolicyEnforcementStatus) | Write-Host

# Copy Configuration, Package and Packets dir under monitoringPath to outputPath
if (($monitoringPath -eq "") -or ((Test-Path $monitoringPath) -eq $false)) {
    Tee-Object $outputPath\$logFile -Append -InputObject "The monitoring data directoiry is not specified or doesn't exist." | Write-Host
}else {
    if (Test-Path $monitoringPath\Configuration) {
        robocopy $monitoringPath\Configuration $outputPath\Configuration /E /log+:$outputPath\copyLogStatus.log /tee
    }else {
        Tee-Object $outputPath\$logFile -Append -InputObject "The Configuration directory under monitoring data directory not found." | Write-Host
    }

    if (Test-Path $monitoringPath\Package) {
        robocopy $monitoringPath\Package $outputPath\Package /E /log+:$outputPath\copyLogStatus.log /tee
    }else {
        Tee-Object $outputPath\$logFile -Append -InputObject "The Package directory under monitoring data directory not found." | Write-Host
    }

    if (Test-Path $monitoringPath\Packets) {
        robocopy $monitoringPath\Packets $outputPath\Packets /E /log+:$outputPath\copyLogStatus.log /tee
    }else {
        Tee-Object $outputPath\$logFile -Append -InputObject "The Packets directory under monitoring data directory not found." | Write-Host
    }
}
    
# Convert and copy tables under monitoringPath to output path
$tablePath = "$monitoringPath\Tables";
$currentPath = split-path -parent $MyInvocation.MyCommand.Definition;
$table2CSVPath = (get-item $currentPath).parent.parent.FullName;
$tsfFileList = "AsmScannerData", "AsmScannerDefaultEvents", "AsmScannerStatusEvents", "TraceEvents", 
                "MAEventTable", "LocalALEXE", "LocalALDel", "LocalALAPPEXE", "LocalALAPPDEP",
                "LocalALSCR", "LocalALSvcMgr", "LocalCIdel", "LocalCIExe", "LocalCIScr";

ConvertAndCopyTablesAzSecPack -tablePath $tablePath -table2CSVPath $table2CSVPath -tsfFileList $tsfFileList

# Copy all log, er, json and xml files from current dir, specified dir, $env:APPDATA\AzureSecurityPack and $env:TEMP\AzureSecurityPack to output path
Tee-Object $outputPath\$logFile -Append -InputObject "Copying all logs in current directory to $outputPath\currentDirLog, and status to $outputPath\copyLogStatus.log" | Write-Host
robocopy $currentPath $outputPath\currentDirLog *.log *.er *.json *.xml /E /log+:$outputPath\copyLogStatus.log /tee

if ($readLogPath -eq "" -or (Test-Path $readLogPath) -eq $false) {
    Tee-Object $outputPath\$logFile -Append -InputObject "readLogPath not specified or not found" | Write-Host
}else {
    Tee-Object $outputPath\$logFile -Append -InputObject "Copying all logs in specified directory $readLogPath to $outputPath\specifiedDirLog, and status to $outputPath\copyLogStatus.log" | Write-Host
    robocopy $readLogPath $outputPath\specifiedDirLog *.log *.er *.json *.xml /E /log+:$outputPath\copyLogStatus.log /tee
}

Tee-Object $outputPath\$logFile -Append -InputObject "Copying all logs in $env:APPDATA\AzureSecurityPack to $outputPath\appdataLog, and status to $outputPath\copyLogStatus.log" | Write-Host
robocopy $env:APPDATA\AzureSecurityPack $outputPath\appdataLog *.log *.er *.json *.xml /E /log+:$outputPath\copyLogStatus.log /tee

Tee-Object $outputPath\$logFile -Append -InputObject "Copying all logs in $env:TEMP\AzureSecurityPack to $outputPath\tempLog, and status to $outputPath\copyLogStatus.log" | Write-Host
robocopy $env:TEMP\AzureSecurityPack $outputPath\tempLog *.log *.er *.json *.xml /E /log+:$outputPath\copyLogStatus.log /tee


# Get SecurityScanMgr and MonAgentHost process details and log to $outputPath
GetProcessDetail -processName SecurityScanMgr >> $outputPath\SecurityScanMgrProcessInfo.log;
GetProcessDetail -processName MonAgentHost >> $outputPath\MonAgentHostProcessInfo.log;

# Zip all files
Set-Content -path $zipPath -value ("PK" + [char]5 + [char]6 + ("$([char]0)" * 18)) -ErrorAction Stop
$zipfile = $zipPath | Get-Item -ErrorAction Stop
$zipfile.IsReadOnly = $false  
#Creating Shell.Application
$shellApp = New-Object -com shell.application
$zipPackage = $shellApp.NameSpace($zipfile.fullname)
$target = Get-Item -Path $outputPath
$zipPackage.CopyHere($target.FullName)
# SIG # Begin signature block
# MIInwgYJKoZIhvcNAQcCoIInszCCJ68CAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCDVJZhajzRiReUz
# BA/saGGx3AsFr+whNm7oHbxuJ5eNYaCCDXYwggX0MIID3KADAgECAhMzAAACy7d1
# OfsCcUI2AAAAAALLMA0GCSqGSIb3DQEBCwUAMH4xCzAJBgNVBAYTAlVTMRMwEQYD
# VQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNy
# b3NvZnQgQ29ycG9yYXRpb24xKDAmBgNVBAMTH01pY3Jvc29mdCBDb2RlIFNpZ25p
# bmcgUENBIDIwMTEwHhcNMjIwNTEyMjA0NTU5WhcNMjMwNTExMjA0NTU5WjB0MQsw
# CQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9u
# ZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMR4wHAYDVQQDExVNaWNy
# b3NvZnQgQ29ycG9yYXRpb24wggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIB
# AQC3sN0WcdGpGXPZIb5iNfFB0xZ8rnJvYnxD6Uf2BHXglpbTEfoe+mO//oLWkRxA
# wppditsSVOD0oglKbtnh9Wp2DARLcxbGaW4YanOWSB1LyLRpHnnQ5POlh2U5trg4
# 3gQjvlNZlQB3lL+zrPtbNvMA7E0Wkmo+Z6YFnsf7aek+KGzaGboAeFO4uKZjQXY5
# RmMzE70Bwaz7hvA05jDURdRKH0i/1yK96TDuP7JyRFLOvA3UXNWz00R9w7ppMDcN
# lXtrmbPigv3xE9FfpfmJRtiOZQKd73K72Wujmj6/Su3+DBTpOq7NgdntW2lJfX3X
# a6oe4F9Pk9xRhkwHsk7Ju9E/AgMBAAGjggFzMIIBbzAfBgNVHSUEGDAWBgorBgEE
# AYI3TAgBBggrBgEFBQcDAzAdBgNVHQ4EFgQUrg/nt/gj+BBLd1jZWYhok7v5/w4w
# RQYDVR0RBD4wPKQ6MDgxHjAcBgNVBAsTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEW
# MBQGA1UEBRMNMjMwMDEyKzQ3MDUyODAfBgNVHSMEGDAWgBRIbmTlUAXTgqoXNzci
# tW2oynUClTBUBgNVHR8ETTBLMEmgR6BFhkNodHRwOi8vd3d3Lm1pY3Jvc29mdC5j
# b20vcGtpb3BzL2NybC9NaWNDb2RTaWdQQ0EyMDExXzIwMTEtMDctMDguY3JsMGEG
# CCsGAQUFBwEBBFUwUzBRBggrBgEFBQcwAoZFaHR0cDovL3d3dy5taWNyb3NvZnQu
# Y29tL3BraW9wcy9jZXJ0cy9NaWNDb2RTaWdQQ0EyMDExXzIwMTEtMDctMDguY3J0
# MAwGA1UdEwEB/wQCMAAwDQYJKoZIhvcNAQELBQADggIBAJL5t6pVjIRlQ8j4dAFJ
# ZnMke3rRHeQDOPFxswM47HRvgQa2E1jea2aYiMk1WmdqWnYw1bal4IzRlSVf4czf
# zx2vjOIOiaGllW2ByHkfKApngOzJmAQ8F15xSHPRvNMmvpC3PFLvKMf3y5SyPJxh
# 922TTq0q5epJv1SgZDWlUlHL/Ex1nX8kzBRhHvc6D6F5la+oAO4A3o/ZC05OOgm4
# EJxZP9MqUi5iid2dw4Jg/HvtDpCcLj1GLIhCDaebKegajCJlMhhxnDXrGFLJfX8j
# 7k7LUvrZDsQniJZ3D66K+3SZTLhvwK7dMGVFuUUJUfDifrlCTjKG9mxsPDllfyck
# 4zGnRZv8Jw9RgE1zAghnU14L0vVUNOzi/4bE7wIsiRyIcCcVoXRneBA3n/frLXvd
# jDsbb2lpGu78+s1zbO5N0bhHWq4j5WMutrspBxEhqG2PSBjC5Ypi+jhtfu3+x76N
# mBvsyKuxx9+Hm/ALnlzKxr4KyMR3/z4IRMzA1QyppNk65Ui+jB14g+w4vole33M1
# pVqVckrmSebUkmjnCshCiH12IFgHZF7gRwE4YZrJ7QjxZeoZqHaKsQLRMp653beB
# fHfeva9zJPhBSdVcCW7x9q0c2HVPLJHX9YCUU714I+qtLpDGrdbZxD9mikPqL/To
# /1lDZ0ch8FtePhME7houuoPcMIIHejCCBWKgAwIBAgIKYQ6Q0gAAAAAAAzANBgkq
# hkiG9w0BAQsFADCBiDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24x
# EDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlv
# bjEyMDAGA1UEAxMpTWljcm9zb2Z0IFJvb3QgQ2VydGlmaWNhdGUgQXV0aG9yaXR5
# IDIwMTEwHhcNMTEwNzA4MjA1OTA5WhcNMjYwNzA4MjEwOTA5WjB+MQswCQYDVQQG
# EwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwG
# A1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSgwJgYDVQQDEx9NaWNyb3NvZnQg
# Q29kZSBTaWduaW5nIFBDQSAyMDExMIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIIC
# CgKCAgEAq/D6chAcLq3YbqqCEE00uvK2WCGfQhsqa+laUKq4BjgaBEm6f8MMHt03
# a8YS2AvwOMKZBrDIOdUBFDFC04kNeWSHfpRgJGyvnkmc6Whe0t+bU7IKLMOv2akr
# rnoJr9eWWcpgGgXpZnboMlImEi/nqwhQz7NEt13YxC4Ddato88tt8zpcoRb0Rrrg
# OGSsbmQ1eKagYw8t00CT+OPeBw3VXHmlSSnnDb6gE3e+lD3v++MrWhAfTVYoonpy
# 4BI6t0le2O3tQ5GD2Xuye4Yb2T6xjF3oiU+EGvKhL1nkkDstrjNYxbc+/jLTswM9
# sbKvkjh+0p2ALPVOVpEhNSXDOW5kf1O6nA+tGSOEy/S6A4aN91/w0FK/jJSHvMAh
# dCVfGCi2zCcoOCWYOUo2z3yxkq4cI6epZuxhH2rhKEmdX4jiJV3TIUs+UsS1Vz8k
# A/DRelsv1SPjcF0PUUZ3s/gA4bysAoJf28AVs70b1FVL5zmhD+kjSbwYuER8ReTB
# w3J64HLnJN+/RpnF78IcV9uDjexNSTCnq47f7Fufr/zdsGbiwZeBe+3W7UvnSSmn
# Eyimp31ngOaKYnhfsi+E11ecXL93KCjx7W3DKI8sj0A3T8HhhUSJxAlMxdSlQy90
# lfdu+HggWCwTXWCVmj5PM4TasIgX3p5O9JawvEagbJjS4NaIjAsCAwEAAaOCAe0w
# ggHpMBAGCSsGAQQBgjcVAQQDAgEAMB0GA1UdDgQWBBRIbmTlUAXTgqoXNzcitW2o
# ynUClTAZBgkrBgEEAYI3FAIEDB4KAFMAdQBiAEMAQTALBgNVHQ8EBAMCAYYwDwYD
# VR0TAQH/BAUwAwEB/zAfBgNVHSMEGDAWgBRyLToCMZBDuRQFTuHqp8cx0SOJNDBa
# BgNVHR8EUzBRME+gTaBLhklodHRwOi8vY3JsLm1pY3Jvc29mdC5jb20vcGtpL2Ny
# bC9wcm9kdWN0cy9NaWNSb29DZXJBdXQyMDExXzIwMTFfMDNfMjIuY3JsMF4GCCsG
# AQUFBwEBBFIwUDBOBggrBgEFBQcwAoZCaHR0cDovL3d3dy5taWNyb3NvZnQuY29t
# L3BraS9jZXJ0cy9NaWNSb29DZXJBdXQyMDExXzIwMTFfMDNfMjIuY3J0MIGfBgNV
# HSAEgZcwgZQwgZEGCSsGAQQBgjcuAzCBgzA/BggrBgEFBQcCARYzaHR0cDovL3d3
# dy5taWNyb3NvZnQuY29tL3BraW9wcy9kb2NzL3ByaW1hcnljcHMuaHRtMEAGCCsG
# AQUFBwICMDQeMiAdAEwAZQBnAGEAbABfAHAAbwBsAGkAYwB5AF8AcwB0AGEAdABl
# AG0AZQBuAHQALiAdMA0GCSqGSIb3DQEBCwUAA4ICAQBn8oalmOBUeRou09h0ZyKb
# C5YR4WOSmUKWfdJ5DJDBZV8uLD74w3LRbYP+vj/oCso7v0epo/Np22O/IjWll11l
# hJB9i0ZQVdgMknzSGksc8zxCi1LQsP1r4z4HLimb5j0bpdS1HXeUOeLpZMlEPXh6
# I/MTfaaQdION9MsmAkYqwooQu6SpBQyb7Wj6aC6VoCo/KmtYSWMfCWluWpiW5IP0
# wI/zRive/DvQvTXvbiWu5a8n7dDd8w6vmSiXmE0OPQvyCInWH8MyGOLwxS3OW560
# STkKxgrCxq2u5bLZ2xWIUUVYODJxJxp/sfQn+N4sOiBpmLJZiWhub6e3dMNABQam
# ASooPoI/E01mC8CzTfXhj38cbxV9Rad25UAqZaPDXVJihsMdYzaXht/a8/jyFqGa
# J+HNpZfQ7l1jQeNbB5yHPgZ3BtEGsXUfFL5hYbXw3MYbBL7fQccOKO7eZS/sl/ah
# XJbYANahRr1Z85elCUtIEJmAH9AAKcWxm6U/RXceNcbSoqKfenoi+kiVH6v7RyOA
# 9Z74v2u3S5fi63V4GuzqN5l5GEv/1rMjaHXmr/r8i+sLgOppO6/8MO0ETI7f33Vt
# Y5E90Z1WTk+/gFcioXgRMiF670EKsT/7qMykXcGhiJtXcVZOSEXAQsmbdlsKgEhr
# /Xmfwb1tbWrJUnMTDXpQzTGCGaIwghmeAgEBMIGVMH4xCzAJBgNVBAYTAlVTMRMw
# EQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVN
# aWNyb3NvZnQgQ29ycG9yYXRpb24xKDAmBgNVBAMTH01pY3Jvc29mdCBDb2RlIFNp
# Z25pbmcgUENBIDIwMTECEzMAAALLt3U5+wJxQjYAAAAAAsswDQYJYIZIAWUDBAIB
# BQCgga4wGQYJKoZIhvcNAQkDMQwGCisGAQQBgjcCAQQwHAYKKwYBBAGCNwIBCzEO
# MAwGCisGAQQBgjcCARUwLwYJKoZIhvcNAQkEMSIEIO+XmCzQLb8dm2OgTdgFGWeW
# ttWuph91k72pMW0SODxvMEIGCisGAQQBgjcCAQwxNDAyoBSAEgBNAGkAYwByAG8A
# cwBvAGYAdKEagBhodHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20wDQYJKoZIhvcNAQEB
# BQAEggEADo4UPbT41WvBUEgGWPZORy6UIm5Z0P3Ql9J59uoSGtp9gsVdgmxpTMbN
# 3gv+ejxnQPebJXWnX/0f+eXkFZjO17m9bwuqzotj6tGX42LpeUgmsmWt6a61nLcP
# +kiy1aMBCxW5LGKJt9fCwA8K7JrX/JRAqiwrKHAS//G2dElL3k1y4hf24eVTWTlO
# +72HmuJgTtBpRzXQE+yC7CR9eauEoQZN9nP5NRmzO713HAzHh/JpoWMD7rkIpvTD
# E40K9f0KAAt89MVRUJf9adzirEi/3RTpJ5qtbJ2G/syk04sOA9hUxwLXq8/wsxFY
# d0+5jmDRAvzgDueQOsv0yBp3Tx6o96GCFywwghcoBgorBgEEAYI3AwMBMYIXGDCC
# FxQGCSqGSIb3DQEHAqCCFwUwghcBAgEDMQ8wDQYJYIZIAWUDBAIBBQAwggFZBgsq
# hkiG9w0BCRABBKCCAUgEggFEMIIBQAIBAQYKKwYBBAGEWQoDATAxMA0GCWCGSAFl
# AwQCAQUABCDmKJQVZrgD10ALQE7fbQ9arPBZGmEOjmiO26TfNl7VwwIGY+WRChHo
# GBMyMDIzMDIxNjIxMTA1Ni45ODNaMASAAgH0oIHYpIHVMIHSMQswCQYDVQQGEwJV
# UzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UE
# ChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMS0wKwYDVQQLEyRNaWNyb3NvZnQgSXJl
# bGFuZCBPcGVyYXRpb25zIExpbWl0ZWQxJjAkBgNVBAsTHVRoYWxlcyBUU1MgRVNO
# OkEyNDAtNEI4Mi0xMzBFMSUwIwYDVQQDExxNaWNyb3NvZnQgVGltZS1TdGFtcCBT
# ZXJ2aWNloIIRezCCBycwggUPoAMCAQICEzMAAAG4CNTBuHngUUkAAQAAAbgwDQYJ
# KoZIhvcNAQELBQAwfDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24x
# EDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlv
# bjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRpbWUtU3RhbXAgUENBIDIwMTAwHhcNMjIw
# OTIwMjAyMjE2WhcNMjMxMjE0MjAyMjE2WjCB0jELMAkGA1UEBhMCVVMxEzARBgNV
# BAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jv
# c29mdCBDb3Jwb3JhdGlvbjEtMCsGA1UECxMkTWljcm9zb2Z0IElyZWxhbmQgT3Bl
# cmF0aW9ucyBMaW1pdGVkMSYwJAYDVQQLEx1UaGFsZXMgVFNTIEVTTjpBMjQwLTRC
# ODItMTMwRTElMCMGA1UEAxMcTWljcm9zb2Z0IFRpbWUtU3RhbXAgU2VydmljZTCC
# AiIwDQYJKoZIhvcNAQEBBQADggIPADCCAgoCggIBAJwbsfwRHERn5C95QPGn37tJ
# 5vOiY9aWjeIDxpgaXaYGiqsw0G0cvCK3YulrqemEf2CkGSdcOJAF++EqhOSqrO13
# nGcjqw6hFNnsGwKANyzddwnOO0jz1lfBIIu77TbfNvnaWbwSRu0DTGHA7n7PR0MY
# J9bC/HopStpbFf606LKcTWnwaUuEdAhx6FAqg1rkgugiuuaaxKyxRkdjFZLKFXEX
# L9p01PtwS0fG6vZiRVnEKgeal2TeLvdAIqapBwltPYifgqnp7Z4VJMcPo0TWmRNV
# FOcHRNwWHehN9xg6ugIGXPo7hMpWrPgg4moHO2epc0T36rgm9hlDrl28bG5TakmV
# 7NJ98kbF5lgtlrowT6ecwEVtuLd4a0gzYqhanW7zaFZnDft5yMexy59ifETdzpwA
# rj2nJAyIsiq1PY3XPm2mUMLlACksqelHKfWihK/Fehw/mziovBVwkkr/G0F19OWg
# R+MBUKifwpOyQiLAxrqvVnfCY4QjJCZiHIuS15HCQ/TIt/Qj4x1WvRa1UqjnmpLu
# 4/yBYWZsdvZoq8SXI7iOs7muecAJeEkYlM6iOkMighzEhjQK9ThPpoAtluXbL7qI
# HGrfFlHmX/4soc7jj1j8uB31U34gJlB2XphjMaT+E+O9SImk/6GRV9Sm8C88Fnmm
# 2VdwMluCNAUzPFjfvHx3AgMBAAGjggFJMIIBRTAdBgNVHQ4EFgQUxP1HJTeFwzNY
# o1njfucXuUfQaW4wHwYDVR0jBBgwFoAUn6cVXQBeYl2D9OXSZacbUzUZ6XIwXwYD
# VR0fBFgwVjBUoFKgUIZOaHR0cDovL3d3dy5taWNyb3NvZnQuY29tL3BraW9wcy9j
# cmwvTWljcm9zb2Z0JTIwVGltZS1TdGFtcCUyMFBDQSUyMDIwMTAoMSkuY3JsMGwG
# CCsGAQUFBwEBBGAwXjBcBggrBgEFBQcwAoZQaHR0cDovL3d3dy5taWNyb3NvZnQu
# Y29tL3BraW9wcy9jZXJ0cy9NaWNyb3NvZnQlMjBUaW1lLVN0YW1wJTIwUENBJTIw
# MjAxMCgxKS5jcnQwDAYDVR0TAQH/BAIwADAWBgNVHSUBAf8EDDAKBggrBgEFBQcD
# CDAOBgNVHQ8BAf8EBAMCB4AwDQYJKoZIhvcNAQELBQADggIBAJ9uk8miwpMoKw3D
# 996piEzbegAGxkABHYn2vP2hbqnkS9U97s/6QlyZOhGFsVudaiLeRZZTsaG5hR0o
# CuBINZ/lelo5xzHc+mBOpBXpxSaW1hqoxaCLsVH1EBtz7in25Hjy+ejuBcilH6EZ
# 0ZtNxmWGIQz8R0AuS0Tj4VgJXHIlXP9dVOiyGo9Velrk+FGx/BC+iEuCaKd/Isyp
# HPiCUCh52DGc91s2S7ldQx1H4CljOAtanDfbvSejASWLo/s3w0XMAbDurWNns0Xi
# dAF2RnL1PaxoOyz9VYakNGK4F3/uJRZnVgbsCYuwNX1BmSwM1ZbPSnggNSGTZx/F
# Q20Jj/ulrK0ryAbvNbNb4kkaS4a767ifCqvUOFLlUT8PN43hhldxI6yHPMOWItJp
# EHIZBiTNKblBsYbIrghb1Ym9tfSsLa5ZJDzVZNndRfhUqJOyXF+CVm9OtVmFDG9k
# IwM6QAX8Q0if721z4VOzZNvD8ktg1lI+XjXgXDJVs3h47sMu9GXSYzky+7dtgmc3
# iRPkda3YVRdmPJtNFN0NLybcssE7vhFCij75eDGQBFq0A4KVG6uBdr6UTWwE0VKH
# xBz2BpGvn7BCs+5yxnF+HV6CUickDqqPi/II7Zssd9EbP9uzj4luldXDAPrWGtdG
# q+wK0odlGNVuCMxsL3hn8+KiO9UiMIIHcTCCBVmgAwIBAgITMwAAABXF52ueAptJ
# mQAAAAAAFTANBgkqhkiG9w0BAQsFADCBiDELMAkGA1UEBhMCVVMxEzARBgNVBAgT
# Cldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29m
# dCBDb3Jwb3JhdGlvbjEyMDAGA1UEAxMpTWljcm9zb2Z0IFJvb3QgQ2VydGlmaWNh
# dGUgQXV0aG9yaXR5IDIwMTAwHhcNMjEwOTMwMTgyMjI1WhcNMzAwOTMwMTgzMjI1
# WjB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMH
# UmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSYwJAYDVQQD
# Ex1NaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0EgMjAxMDCCAiIwDQYJKoZIhvcNAQEB
# BQADggIPADCCAgoCggIBAOThpkzntHIhC3miy9ckeb0O1YLT/e6cBwfSqWxOdcjK
# NVf2AX9sSuDivbk+F2Az/1xPx2b3lVNxWuJ+Slr+uDZnhUYjDLWNE893MsAQGOhg
# fWpSg0S3po5GawcU88V29YZQ3MFEyHFcUTE3oAo4bo3t1w/YJlN8OWECesSq/XJp
# rx2rrPY2vjUmZNqYO7oaezOtgFt+jBAcnVL+tuhiJdxqD89d9P6OU8/W7IVWTe/d
# vI2k45GPsjksUZzpcGkNyjYtcI4xyDUoveO0hyTD4MmPfrVUj9z6BVWYbWg7mka9
# 7aSueik3rMvrg0XnRm7KMtXAhjBcTyziYrLNueKNiOSWrAFKu75xqRdbZ2De+JKR
# Hh09/SDPc31BmkZ1zcRfNN0Sidb9pSB9fvzZnkXftnIv231fgLrbqn427DZM9itu
# qBJR6L8FA6PRc6ZNN3SUHDSCD/AQ8rdHGO2n6Jl8P0zbr17C89XYcz1DTsEzOUyO
# ArxCaC4Q6oRRRuLRvWoYWmEBc8pnol7XKHYC4jMYctenIPDC+hIK12NvDMk2ZItb
# oKaDIV1fMHSRlJTYuVD5C4lh8zYGNRiER9vcG9H9stQcxWv2XFJRXRLbJbqvUAV6
# bMURHXLvjflSxIUXk8A8FdsaN8cIFRg/eKtFtvUeh17aj54WcmnGrnu3tz5q4i6t
# AgMBAAGjggHdMIIB2TASBgkrBgEEAYI3FQEEBQIDAQABMCMGCSsGAQQBgjcVAgQW
# BBQqp1L+ZMSavoKRPEY1Kc8Q/y8E7jAdBgNVHQ4EFgQUn6cVXQBeYl2D9OXSZacb
# UzUZ6XIwXAYDVR0gBFUwUzBRBgwrBgEEAYI3TIN9AQEwQTA/BggrBgEFBQcCARYz
# aHR0cDovL3d3dy5taWNyb3NvZnQuY29tL3BraW9wcy9Eb2NzL1JlcG9zaXRvcnku
# aHRtMBMGA1UdJQQMMAoGCCsGAQUFBwMIMBkGCSsGAQQBgjcUAgQMHgoAUwB1AGIA
# QwBBMAsGA1UdDwQEAwIBhjAPBgNVHRMBAf8EBTADAQH/MB8GA1UdIwQYMBaAFNX2
# VsuP6KJcYmjRPZSQW9fOmhjEMFYGA1UdHwRPME0wS6BJoEeGRWh0dHA6Ly9jcmwu
# bWljcm9zb2Z0LmNvbS9wa2kvY3JsL3Byb2R1Y3RzL01pY1Jvb0NlckF1dF8yMDEw
# LTA2LTIzLmNybDBaBggrBgEFBQcBAQROMEwwSgYIKwYBBQUHMAKGPmh0dHA6Ly93
# d3cubWljcm9zb2Z0LmNvbS9wa2kvY2VydHMvTWljUm9vQ2VyQXV0XzIwMTAtMDYt
# MjMuY3J0MA0GCSqGSIb3DQEBCwUAA4ICAQCdVX38Kq3hLB9nATEkW+Geckv8qW/q
# XBS2Pk5HZHixBpOXPTEztTnXwnE2P9pkbHzQdTltuw8x5MKP+2zRoZQYIu7pZmc6
# U03dmLq2HnjYNi6cqYJWAAOwBb6J6Gngugnue99qb74py27YP0h1AdkY3m2CDPVt
# I1TkeFN1JFe53Z/zjj3G82jfZfakVqr3lbYoVSfQJL1AoL8ZthISEV09J+BAljis
# 9/kpicO8F7BUhUKz/AyeixmJ5/ALaoHCgRlCGVJ1ijbCHcNhcy4sa3tuPywJeBTp
# kbKpW99Jo3QMvOyRgNI95ko+ZjtPu4b6MhrZlvSP9pEB9s7GdP32THJvEKt1MMU0
# sHrYUP4KWN1APMdUbZ1jdEgssU5HLcEUBHG/ZPkkvnNtyo4JvbMBV0lUZNlz138e
# W0QBjloZkWsNn6Qo3GcZKCS6OEuabvshVGtqRRFHqfG3rsjoiV5PndLQTHa1V1QJ
# sWkBRH58oWFsc/4Ku+xBZj1p/cvBQUl+fpO+y/g75LcVv7TOPqUxUYS8vwLBgqJ7
# Fx0ViY1w/ue10CgaiQuPNtq6TPmb/wrpNPgkNWcr4A245oyZ1uEi6vAnQj0llOZ0
# dFtq0Z4+7X6gMTN9vMvpe784cETRkPHIqzqKOghif9lwY1NNje6CbaUFEMFxBmoQ
# tB1VM1izoXBm8qGCAtcwggJAAgEBMIIBAKGB2KSB1TCB0jELMAkGA1UEBhMCVVMx
# EzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoT
# FU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEtMCsGA1UECxMkTWljcm9zb2Z0IElyZWxh
# bmQgT3BlcmF0aW9ucyBMaW1pdGVkMSYwJAYDVQQLEx1UaGFsZXMgVFNTIEVTTjpB
# MjQwLTRCODItMTMwRTElMCMGA1UEAxMcTWljcm9zb2Z0IFRpbWUtU3RhbXAgU2Vy
# dmljZaIjCgEBMAcGBSsOAwIaAxUAcGteVqFx/IbTKXHLeuXCPRPMD7uggYMwgYCk
# fjB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMH
# UmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSYwJAYDVQQD
# Ex1NaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0EgMjAxMDANBgkqhkiG9w0BAQUFAAIF
# AOeYoQAwIhgPMjAyMzAyMTYyMDMzMDRaGA8yMDIzMDIxNzIwMzMwNFowdzA9Bgor
# BgEEAYRZCgQBMS8wLTAKAgUA55ihAAIBADAKAgEAAgIH4wIB/zAHAgEAAgITITAK
# AgUA55nygAIBADA2BgorBgEEAYRZCgQCMSgwJjAMBgorBgEEAYRZCgMCoAowCAIB
# AAIDB6EgoQowCAIBAAIDAYagMA0GCSqGSIb3DQEBBQUAA4GBAG8QVnzVpd6Op4Rd
# wKGaVKslPAh3WReY+WQCh9bJer6buRI8Q/aaK8dIVxJD2POQb5Nb2y7FoG8axOWa
# kf2mdORq0NWyS6Hdey901xnV4HWQA43jRlGqTn4CiC7gF0DpdUcVGKU31XlFLikp
# LTrEGAFh++AWyH6YU9KIHv3Ml+XMMYIEDTCCBAkCAQEwgZMwfDELMAkGA1UEBhMC
# VVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNV
# BAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRp
# bWUtU3RhbXAgUENBIDIwMTACEzMAAAG4CNTBuHngUUkAAQAAAbgwDQYJYIZIAWUD
# BAIBBQCgggFKMBoGCSqGSIb3DQEJAzENBgsqhkiG9w0BCRABBDAvBgkqhkiG9w0B
# CQQxIgQgaP1JMTgSpma8o9zFl5RzgJXFeKNCNjWM9we7/K5QUOowgfoGCyqGSIb3
# DQEJEAIvMYHqMIHnMIHkMIG9BCAo69Y4oHA7Q4pS+Y1NsBfrpIYTeWsPeGTami0X
# 0PD7HzCBmDCBgKR+MHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9u
# MRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRp
# b24xJjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAyMDEwAhMzAAAB
# uAjUwbh54FFJAAEAAAG4MCIEILV1wY9UptASqytcbC1lQGik7fCYVLH8HaXiYCiD
# BypwMA0GCSqGSIb3DQEBCwUABIICAHEHQp0Tsu4X3ZWmw1aPyJUMSVfDoCVJDWnv
# fRfkTi0LU8lMOpiamaPwalH7gMxBXwYX4bV8RjMOM9+2G69gaw81JaVVt5ub3Pwo
# DvF4OcjLsDXIuqeNqeh0CB18aypDmPukAoydOWpMvuE5mh5Etpn/ymUB2f5kG4nx
# VzK0HaLqoa0LYTKKrAkvmzGQaFrvBzYAHswS1/9viuHixd3sIm423509slaa23fG
# GW5zlfV5jtKMkZtNTkjj8Ue6Dq8TIA9ZQuCKqDEyvX0yGnQaG/f7y/oSRweXIyll
# d66vw2qCYizHM5/4Xs4uhX0rb84HCH/9A3kv9FGx46XSSgkQC0ry2qauqK+M7///
# zmr5ZGgisQ1UKBMck1SY1XNmDwyrNxszRO0WGZcLPMPAa6QLFTweHk7kaR+ZWbCg
# b9YhRP0dKCk4Ryx8Ed9LtgD9Q6ux6Hi1XE0fA7VZoGPjqiF8gYMYrCDAK00pFaNO
# c/odzboynj/kosmh4TSJ/0lQeXC67qJqgsktZHmSnaNndVD1h6Y08/HeQXASaXi+
# o6m3h3SvgvtIGRFmG67udlR5mKViDU0fOwZETqgi7EcW9+EVBIFqhXCiP/g/IJ2i
# a7V8Q+mBxrxNE7xirGwlm94sIxPoNTtGm7uu0dXS405j5w1zboydGi7Typ4Uskc3
# HxBbO61F
# SIG # End signature block
