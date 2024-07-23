#ifndef UNICODE
#define UNICODE
#endif

#ifndef _UNICODE
#define _UNICODE
#endif

#include <Windows.h>
#include <tlhelp32.h>
#include <tchar.h>

#define SUCCESS 0x00000000
#define NO_FLUENT_BIT_PROCESS 0x00000001
#define FILESYSTEM_WATCHER_FILE_EXISTS 0x00000002
#define CERTIFICATE_RENEWAL_REQUIRED 0x00000003
#define FLUENTDWINAKS_SERVICE_NOT_RUNNING 0x00000004
#define NO_WINDOWS_AMA_MONAGENTCORE_PROCESS 0x00000005
#define NO_TELEGRAF_PROCESS 0x00000006
#define UNEXPECTED_ERROR 0xFFFFFFFF

/*
  check if the process running or not for given exe file name
*/
bool IsProcessRunning(const wchar_t *const executableName)
{
    PROCESSENTRY32 entry;
    entry.dwSize = sizeof(PROCESSENTRY32);

    const auto snapshot = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);

    if (!Process32First(snapshot, &entry))
    {
        CloseHandle(snapshot);
        wprintf_s(L"ERROR:IsProcessRunning::Process32First failed");
        return false;
    }

    do
    {
        if (!_wcsicmp(entry.szExeFile, executableName))
        {
            CloseHandle(snapshot);
            return true;
        }
    } while (Process32Next(snapshot, &entry));

    CloseHandle(snapshot);
    return false;
}

/*
  check if the file exists
*/
bool IsFileExists(const wchar_t *const fileName)
{
    DWORD dwAttrib = GetFileAttributes(fileName);
    return dwAttrib != INVALID_FILE_SIZE;
}

/*
 Get the status of the service for given service name
*/
int GetServiceStatus(const wchar_t *const serivceName)
{
    SC_HANDLE theService, scm;
    SERVICE_STATUS_PROCESS ssStatus;
    DWORD dwBytesNeeded;

    scm = OpenSCManager(nullptr, nullptr, SC_MANAGER_ENUMERATE_SERVICE);
    if (!scm)
    {
        wprintf_s(L"ERROR:GetServiceStatus::OpenSCManager failed");
        return UNEXPECTED_ERROR;
    }

    theService = OpenService(scm, serivceName, SERVICE_QUERY_STATUS);
    if (!theService)
    {
        CloseServiceHandle(scm);
        wprintf_s(L"ERROR:GetServiceStatus::OpenService failed");
        return UNEXPECTED_ERROR;
    }

    auto result = QueryServiceStatusEx(theService, SC_STATUS_PROCESS_INFO,
                                       reinterpret_cast<LPBYTE>(&ssStatus), sizeof(SERVICE_STATUS_PROCESS),
                                       &dwBytesNeeded);

    CloseServiceHandle(theService);
    CloseServiceHandle(scm);

    if (result == 0)
    {
        wprintf_s(L"ERROR:GetServiceStatus:QueryServiceStatusEx failed");
        return UNEXPECTED_ERROR;
    }

    return ssStatus.dwCurrentState;
}

/**
 <exe> <servicename> <filesystemwatcherfilepath> <certificaterenewalpath>
**/
int _tmain(int argc, wchar_t *argv[])
{
    if (argc < 6)
    {
        wprintf_s(L"ERROR:unexpected number arguments and expected is 6");
        return UNEXPECTED_ERROR;
    }

    const DWORD bufferSize = 16;
    wchar_t enableCustomMetricsValue[bufferSize];
    wchar_t msiModeValue[bufferSize];
    wchar_t sidecarScrapingEnabled[bufferSize];
    wchar_t telegrafLivenessprobeEnabled[bufferSize];
    wchar_t telemetryCustomPromMonitorPods[bufferSize];
    GetEnvironmentVariable(L"ENABLE_CUSTOM_METRICS", enableCustomMetricsValue, bufferSize);
    GetEnvironmentVariable(L"USING_AAD_MSI_AUTH", msiModeValue, bufferSize);
    GetEnvironmentVariable(L"SIDECAR_SCRAPING_ENABLED", sidecarScrapingEnabled, bufferSize);
    GetEnvironmentVariable(L"AZMON_TELEGRAF_LIVENESSPROBE_ENABLED", telegrafLivenessprobeEnabled, bufferSize);
    GetEnvironmentVariable(L"TELEMETRY_CUSTOM_PROM_MONITOR_PODS", telemetryCustomPromMonitorPods, bufferSize);

    int argvNum = 2;
    bool telegrafChecked = false, fluentBitChecked = false, monAgentCoreChecked = false;
    for (int i = 1; i < argc; i++) {
        if (_wcsicmp(argv[i], L"telegraf.exe") == 0) {
            telegrafChecked = true;
            if (!IsProcessRunning(argv[i])) {
                wprintf_s(L"ERROR: Telegraf process is not running.\n");
                return NO_TELEGRAF_PROCESS;
            }
        } else if (_wcsicmp(argv[i], L"fluent-bit.exe" ) == 0 && _wcsicmp(sidecarScrapingEnabled, L"true") == 0 && _wcsicmp(telemetryCustomPromMonitorPods, L"true") == 0 && _wcsicmp(telegrafLivenessprobeEnabled, L"true") == 0) {
            fluentBitChecked = true;
            if (!IsProcessRunning(argv[i])) {
                wprintf_s(L"ERROR: Fluent-bit process is not running.\n");
                return NO_FLUENT_BIT_PROCESS;
            }
        } else if (_wcsicmp(argv[i], L"MonAgentCore.exe") == 0) {
            monAgentCoreChecked = true;
            if (!IsProcessRunning(argv[i])) {
                wprintf_s(L"ERROR: MonAgentCore process is not running.\n");
                return NO_WINDOWS_AMA_MONAGENTCORE_PROCESS;
            }
        }
    }
    if (telegrafChecked) argvNum++;

    if (_wcsicmp(enableCustomMetricsValue, L"true") == 0 || _wcsicmp(msiModeValue, L"true") != 0)
    {
        DWORD dwStatus = GetServiceStatus(argv[argvNum]);
        if (dwStatus != SERVICE_RUNNING)
        {
            wprintf_s(L"ERROR:Service:%s is not running\n", argv[argvNum]);
            return FLUENTDWINAKS_SERVICE_NOT_RUNNING;
        }
    }
    argvNum++;

    if (IsFileExists(argv[argvNum]))
    {
        wprintf_s(L"INFO:File:%s exists indicates Config Map Updated since agent started.\n", argv[argvNum]);
        return FILESYSTEM_WATCHER_FILE_EXISTS;
    }
    argvNum++;

    if (IsFileExists(argv[argvNum]))
    {
        wprintf_s(L"INFO:File:%s exists indicates Certificate needs to be renewed.\n", argv[argvNum]);
        return CERTIFICATE_RENEWAL_REQUIRED;
    }

    return SUCCESS;
}
