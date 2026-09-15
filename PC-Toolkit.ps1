$ErrorActionPreference = 'Continue'

$Host.UI.RawUI.BackgroundColor = 'Black'
$Host.UI.RawUI.ForegroundColor = 'White'
Clear-Host

$ToolkitRoot = $PSScriptRoot
$LogFolder = Join-Path $ToolkitRoot 'Logs'
$ReportFolder = Join-Path $ToolkitRoot 'Reports'

New-Item -ItemType Directory -Path $LogFolder -Force | Out-Null
New-Item -ItemType Directory -Path $ReportFolder -Force | Out-Null

$TimeStamp = Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'
$TranscriptPath = Join-Path $LogFolder "Toolkit_$TimeStamp.log"

try {
    Start-Transcript -Path $TranscriptPath -Append | Out-Null
} catch {
    Write-Warning 'Could not start the toolkit log.'
}

function Pause-Toolkit {
    Write-Host ''
    Read-Host 'Press Enter to return to the main menu'
}

function Confirm-ToolkitAction {
    param(
        [string]$Message = 'Type YES and press Enter to continue, or press Enter to cancel.'
    )

    Write-Host ''
    Write-Host $Message -ForegroundColor White
    $Answer = Read-Host 'Your answer'

    return ($Answer -match '^(Y|YES)$')
}

function Show-Header {
    Clear-Host
    Write-Host '==============================================' -ForegroundColor DarkRed
    Write-Host '           PORTABLE PC TECH TOOLKIT' -ForegroundColor DarkRed
    Write-Host '==============================================' -ForegroundColor DarkRed
    Write-Host "USB location: $ToolkitRoot" -ForegroundColor White
    Write-Host "Logs:         $LogFolder" -ForegroundColor White
    Write-Host "Reports:      $ReportFolder" -ForegroundColor White

    if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Host ''
        Write-Host 'WARNING: Toolkit is not running as Administrator. Some options may fail.' -ForegroundColor DarkRed
    }

    Write-Host ''
}

function Get-SystemReport {
    $Path = Join-Path $ReportFolder "System_Report_$TimeStamp.txt"

    Write-Host 'Collecting system information...' -ForegroundColor White

    $OS = Get-CimInstance Win32_OperatingSystem
    $Computer = Get-CimInstance Win32_ComputerSystem
    $BIOS = Get-CimInstance Win32_BIOS
    $CPU = Get-CimInstance Win32_Processor
    $Drives = Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3'
    $MemoryGB = [math]::Round($Computer.TotalPhysicalMemory / 1GB, 2)

    @"
PC TECH TOOLKIT - SYSTEM REPORT
Generated: $(Get-Date)

COMPUTER
Name: $env:COMPUTERNAME
Manufacturer: $($Computer.Manufacturer)
Model: $($Computer.Model)
Serial Number: $($BIOS.SerialNumber)

WINDOWS
Edition: $($OS.Caption)
Version: $($OS.Version)
Build: $($OS.BuildNumber)
Installed: $($OS.InstallDate)

HARDWARE
CPU: $($CPU.Name)
Installed RAM: $MemoryGB GB

STORAGE
$(
    $Drives | ForEach-Object {
        "$($_.DeviceID)  Size: $([math]::Round($_.Size / 1GB, 1)) GB  Free: $([math]::Round($_.FreeSpace / 1GB, 1)) GB"
    } | Out-String
)

NETWORK ADAPTERS
$(
    Get-NetAdapter -ErrorAction SilentlyContinue |
    Select-Object Name, Status, LinkSpeed, MacAddress |
    Format-Table -AutoSize | Out-String
)

ACTIVE NETWORK CONFIGURATION
$(
    ipconfig /all | Out-String
)
"@ | Out-File -FilePath $Path -Encoding utf8

    Write-Host "Saved: $Path" -ForegroundColor White
    Pause-Toolkit
}

function Get-BatteryReport {
    $Path = Join-Path $ReportFolder "Battery_Report_$TimeStamp.html"

    Write-Host 'Creating battery report...' -ForegroundColor White
    powercfg /batteryreport /output $Path

    if (Test-Path $Path) {
        Write-Host "Saved: $Path" -ForegroundColor White
        Start-Process $Path
    } else {
        Write-Host 'Battery report could not be created. This is normal on many desktops.' -ForegroundColor DarkRed
    }

    Pause-Toolkit
}

function Get-DriverAndDeviceReport {
    $Path = Join-Path $ReportFolder "Drivers_and_Device_Issues_$TimeStamp.txt"

    Write-Host 'Checking installed drivers and problem devices...' -ForegroundColor White

    @"
PC TECH TOOLKIT - DRIVERS AND DEVICE ISSUES
Generated: $(Get-Date)

DEVICES REPORTING A PROBLEM
$(
    Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue |
    Where-Object { $_.Status -ne 'OK' } |
    Select-Object Class, FriendlyName, Status, InstanceId |
    Format-Table -AutoSize | Out-String
)

SIGNED DRIVERS
$(
    Get-CimInstance Win32_PnPSignedDriver |
    Sort-Object DeviceName |
    Select-Object DeviceName, DriverVersion, DriverDate, Manufacturer |
    Format-Table -AutoSize | Out-String
)
"@ | Out-File -FilePath $Path -Encoding utf8

    Write-Host "Saved: $Path" -ForegroundColor White
    Pause-Toolkit
}

function Test-DiskHealth {
    Write-Host 'Checking disk health and NTFS status...' -ForegroundColor White

    Get-PhysicalDisk -ErrorAction SilentlyContinue |
        Select-Object FriendlyName, MediaType, HealthStatus, OperationalStatus, Size |
        Format-Table -AutoSize

    Write-Host ''
    Write-Host 'Running an online scan of C:. This does not schedule repairs or erase files.' -ForegroundColor DarkRed
    chkdsk C: /scan

    Pause-Toolkit
}

function Start-WindowsRepair {
    param(
        [switch]$SkipConfirmation
    )

    Write-Host 'This step will run DISM followed by SFC to repair Windows system files. It can take a while.' -ForegroundColor DarkRed

    if (-not $SkipConfirmation) {
        if (-not (Confirm-ToolkitAction 'Type YES and press Enter to run the repair checks, or press Enter to skip this step.')) {
            Write-Host 'Skipped.' -ForegroundColor DarkRed
            Pause-Toolkit
            return
        }
    }

    Write-Host ''
    Write-Host 'Running DISM component repair...' -ForegroundColor White
    DISM /Online /Cleanup-Image /RestoreHealth

    Write-Host ''
    Write-Host 'Running System File Checker...' -ForegroundColor White
    sfc /scannow

    Write-Host ''
    Write-Host 'Repair checks finished. Restart Windows if either tool repaired files.' -ForegroundColor White

    if (-not $SkipConfirmation) {
        Pause-Toolkit
    }
}

function Clear-SafeTempFiles {
    param(
        [switch]$SkipConfirmation
    )

    Write-Host 'This step will remove temporary files and empty the Recycle Bin.' -ForegroundColor DarkRed
    Write-Host 'It does not touch Documents, Pictures, Downloads, or installed apps.' -ForegroundColor DarkRed

    if (-not $SkipConfirmation) {
        if (-not (Confirm-ToolkitAction 'Type YES and press Enter to run cleanup, or press Enter to skip this step.')) {
            Write-Host 'Skipped.' -ForegroundColor DarkRed
            Pause-Toolkit
            return
        }
    }

    $Targets = @(
        "$env:TEMP\*",
        "$env:WINDIR\Temp\*"
    )

    foreach ($Target in $Targets) {
        Write-Host "Cleaning $Target" -ForegroundColor White
        Remove-Item -Path $Target -Force -Recurse -ErrorAction SilentlyContinue
    }

    try {
        Clear-RecycleBin -Force -ErrorAction Stop
        Write-Host 'Recycle Bin cleared.' -ForegroundColor White
    } catch {
        Write-Host 'Recycle Bin was not cleared or was already empty.' -ForegroundColor DarkRed
    }

    Write-Host 'Temporary-file cleanup finished.' -ForegroundColor White

    if (-not $SkipConfirmation) {
        Pause-Toolkit
    }
}

function Get-NetworkReport {
    $Path = Join-Path $ReportFolder "Network_Report_$TimeStamp.txt"

    Write-Host 'Testing basic network connectivity...' -ForegroundColor White

    @"
PC TECH TOOLKIT - NETWORK REPORT
Generated: $(Get-Date)

NETWORK ADAPTERS
$(
    Get-NetAdapter -ErrorAction SilentlyContinue |
    Select-Object Name, Status, LinkSpeed, MacAddress, InterfaceDescription |
    Format-Table -AutoSize | Out-String
)

IP CONFIGURATION
$(
    Get-NetIPConfiguration -Detailed -ErrorAction SilentlyContinue | Out-String
)

DNS TEST
$(
    Resolve-DnsName microsoft.com -ErrorAction SilentlyContinue | Out-String
)

INTERNET PING TEST
$(
    Test-Connection 1.1.1.1 -Count 4 -ErrorAction SilentlyContinue | Out-String
)
"@ | Out-File -FilePath $Path -Encoding utf8

    Write-Host "Saved: $Path" -ForegroundColor White
    Pause-Toolkit
}

function Get-RecentCriticalEvents {
    $Path = Join-Path $ReportFolder "Recent_Critical_Events_$TimeStamp.txt"

    Write-Host 'Collecting recent Windows critical and error events...' -ForegroundColor White

    Get-WinEvent -FilterHashtable @{
        LogName = 'System'
        StartTime = (Get-Date).AddDays(-7)
    } -ErrorAction SilentlyContinue |
        Where-Object { $_.LevelDisplayName -in @('Critical', 'Error') } |
        Select-Object TimeCreated, ProviderName, Id, LevelDisplayName, Message |
        Format-List | Out-File -FilePath $Path -Encoding utf8

    Write-Host "Saved: $Path" -ForegroundColor White
    Pause-Toolkit
}

function Open-WindowsMaintenancePages {
    Write-Host 'Opening Windows Update and Storage settings...' -ForegroundColor White
    Start-Process 'ms-settings:windowsupdate'
    Start-Process 'ms-settings:storagesense'
    Pause-Toolkit
}

function Set-HighPerformancePower {
    param(
        [switch]$SkipPause
    )

    Write-Host 'Setting power plan to High Performance...' -ForegroundColor White

    powercfg -duplicatescheme SCHEME_MIN | Out-Null
    powercfg /setactive SCHEME_MIN

    Write-Host 'High Performance plan enabled and activated.' -ForegroundColor White
    Write-Host 'Note: This can reduce battery life on laptops.' -ForegroundColor DarkRed

    if (-not $SkipPause) {
        Pause-Toolkit
    }
}

function Optimize-Drives {
    param(
        [switch]$SkipConfirmation
    )

    Write-Host 'This step runs Windows drive optimization.' -ForegroundColor DarkRed
    Write-Host 'Windows will TRIM SSDs and optimize or defragment hard drives as appropriate.' -ForegroundColor DarkRed

    if (-not $SkipConfirmation) {
        if (-not (Confirm-ToolkitAction 'Type YES and press Enter to optimize drives, or press Enter to skip this step.')) {
            Write-Host 'Skipped.' -ForegroundColor DarkRed
            Pause-Toolkit
            return
        }
    }

    Get-Volume | Where-Object { $_.DriveLetter } | ForEach-Object {
        $Drive = "$($_.DriveLetter):"
        Write-Host "Optimizing $Drive ..." -ForegroundColor White
        defrag $Drive /O
    }

    Write-Host 'Drive optimization complete.' -ForegroundColor White

    if (-not $SkipConfirmation) {
        Pause-Toolkit
    }
}

function Review-StartupPrograms {
    Write-Host 'Startup programs currently configured to launch at boot:' -ForegroundColor White

    Get-CimInstance Win32_StartupCommand |
        Select-Object Name, Command, Location |
        Format-Table -AutoSize

    Write-Host ''
    Write-Host 'Use Task Manager > Startup apps to disable unwanted startup programs.' -ForegroundColor DarkRed
    Write-Host 'Opening Task Manager...' -ForegroundColor White

    Start-Process 'taskmgr.exe' -ArgumentList '/7' -ErrorAction SilentlyContinue

    Pause-Toolkit
}

function Disable-VisualEffectsForPerformance {
    param(
        [switch]$SkipConfirmation
    )

    Write-Host 'This step sets Windows visual effects to "Adjust for best performance".' -ForegroundColor DarkRed
    Write-Host 'This disables some animations, shadows, and appearance effects.' -ForegroundColor DarkRed
    Write-Host 'This makes a registry setting change for the current user only.' -ForegroundColor DarkRed

    if (-not $SkipConfirmation) {
        if (-not (Confirm-ToolkitAction 'Type YES and press Enter to change visual effects, or press Enter to skip this step.')) {
            Write-Host 'Skipped.' -ForegroundColor DarkRed
            Pause-Toolkit
            return
        }
    }

    $RegistryPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects'

    if (-not (Test-Path $RegistryPath)) {
        New-Item -Path $RegistryPath -Force | Out-Null
    }

    Set-ItemProperty -Path $RegistryPath -Name 'VisualFXSetting' -Value 2 -Type DWord -Force

    Write-Host 'Visual effects set to best performance. Sign out and back in for full effect.' -ForegroundColor White

    if (-not $SkipConfirmation) {
        Pause-Toolkit
    }
}

function Clear-WindowsUpdateCache {
    param(
        [switch]$SkipConfirmation
    )

    Write-Host 'This step clears downloaded Windows Update files only.' -ForegroundColor DarkRed
    Write-Host 'It does not remove installed updates, personal files, or applications.' -ForegroundColor DarkRed

    if (-not $SkipConfirmation) {
        if (-not (Confirm-ToolkitAction 'Type YES and press Enter to clear the update cache, or press Enter to skip this step.')) {
            Write-Host 'Skipped.' -ForegroundColor DarkRed
            Pause-Toolkit
            return
        }
    }

    Write-Host 'Stopping Windows Update service...' -ForegroundColor White
    Stop-Service -Name wuauserv -Force -ErrorAction SilentlyContinue

    Write-Host 'Clearing SoftwareDistribution download cache...' -ForegroundColor White
    Remove-Item -Path "$env:WINDIR\SoftwareDistribution\Download\*" -Recurse -Force -ErrorAction SilentlyContinue

    Write-Host 'Restarting Windows Update service...' -ForegroundColor White
    Start-Service -Name wuauserv -ErrorAction SilentlyContinue

    Write-Host 'Windows Update cache cleared.' -ForegroundColor White

    if (-not $SkipConfirmation) {
        Pause-Toolkit
    }
}

function Run-DiskCleanupUtility {
    Write-Host 'Launching Windows Disk Cleanup.' -ForegroundColor White
    Write-Host 'Select a drive, choose the cleanup categories you want, then click OK.' -ForegroundColor DarkRed

    Start-Process 'cleanmgr.exe' -Wait

    Pause-Toolkit
}

function Update-AvailableDrivers {
    Write-Host 'This step checks Windows Update for available driver updates.' -ForegroundColor DarkRed
    Write-Host 'It installs drivers Microsoft offers through Windows Update.' -ForegroundColor DarkRed
    Write-Host 'An internet connection is required.' -ForegroundColor DarkRed

    if (-not (Confirm-ToolkitAction 'Type YES and press Enter to scan for and install available driver updates, or press Enter to cancel.')) {
        Write-Host 'Cancelled.' -ForegroundColor DarkRed
        Pause-Toolkit
        return
    }

    try {
        Write-Host ''
        Write-Host 'Connecting to Windows Update and scanning for driver updates...' -ForegroundColor White

        $UpdateSession = New-Object -ComObject Microsoft.Update.Session
        $UpdateSearcher = $UpdateSession.CreateUpdateSearcher()
        $SearchResult = $UpdateSearcher.Search("IsInstalled=0 and Type='Driver'")

        if ($SearchResult.Updates.Count -eq 0) {
            Write-Host 'No available driver updates were found through Windows Update.' -ForegroundColor White
            Pause-Toolkit
            return
        }

        Write-Host ''
        Write-Host 'Available driver updates:' -ForegroundColor White

        $UpdatesToInstall = New-Object -ComObject Microsoft.Update.UpdateColl

        for ($i = 0; $i -lt $SearchResult.Updates.Count; $i++) {
            $Update = $SearchResult.Updates.Item($i)
            Write-Host " - $($Update.Title)" -ForegroundColor Yellow

            if (-not $Update.EulaAccepted) {
                $Update.AcceptEula()
            }
            $UpdatesToInstall.Add($Update) | Out-Null
        }

        Write-Host ''
        Write-Host 'Downloading driver updates...' -ForegroundColor White

        $Downloader = $UpdateSession.CreateUpdateDownloader()
        $Downloader.Updates = $UpdatesToInstall
        $DownloadResult = $Downloader.Download()

        if ($DownloadResult.ResultCode -ne 2 -and $DownloadResult.ResultCode -ne 3) {
            Write-Host 'Windows Update could not download all selected driver updates.' -ForegroundColor DarkRed
            Pause-Toolkit
            return
        }

        Write-Host 'Installing downloaded driver updates...' -ForegroundColor White

        $Installer = $UpdateSession.CreateUpdateInstaller()
        $Installer.Updates = $UpdatesToInstall
        $InstallationResult = $Installer.Install()

        Write-Host ''
        Write-Host "Installation result code: $($InstallationResult.ResultCode)" -ForegroundColor White

        if ($InstallationResult.RebootRequired) {
            Write-Host 'A restart is required to finish installing one or more driver updates.' -ForegroundColor DarkRed
        } else {
            Write-Host 'Driver update pass finished. Restarting is still recommended.' -ForegroundColor White
        }
    } catch {
        Write-Host ''
        Write-Host 'Driver update check failed.' -ForegroundColor DarkRed
        Write-Host "Details: $($_.Exception.Message)" -ForegroundColor DarkRed
        Write-Host 'Confirm that the PC is online, Windows Update services are running, and the toolkit is elevated as Administrator.' -ForegroundColor White
    }

    Pause-Toolkit
}

function Start-FullOptimizationPass {
    Write-Host 'Full optimization will do the following:' -ForegroundColor DarkRed
    Write-Host '  1. Set the High Performance power plan' -ForegroundColor White
    Write-Host '  2. Clear safe temp files and the Recycle Bin' -ForegroundColor White
    Write-Host '  3. Clear the Windows Update download cache' -ForegroundColor White
    Write-Host '  4. Optimize all drives' -ForegroundColor White
    Write-Host '  5. Set visual effects to best performance' -ForegroundColor White
    Write-Host ''
    Write-Host 'This does not remove documents, pictures, installed apps, or installed Windows updates.' -ForegroundColor DarkRed

    if (-not (Confirm-ToolkitAction 'Type YES and press Enter to run the full optimization pass, or press Enter to cancel.')) {
        Write-Host 'Cancelled.' -ForegroundColor DarkRed
        Pause-Toolkit
        return
    }

    Set-HighPerformancePower -SkipPause
    Clear-SafeTempFiles -SkipConfirmation
    Clear-WindowsUpdateCache -SkipConfirmation
    Optimize-Drives -SkipConfirmation
    Disable-VisualEffectsForPerformance -SkipConfirmation

    Write-Host ''
    Write-Host 'Full optimization pass finished.' -ForegroundColor White
    Pause-Toolkit
}

function Start-GuidedMaintenance {
    Write-Host 'Guided maintenance will do the following:' -ForegroundColor DarkRed
    Write-Host '  1. Save a full system report to the USB drive' -ForegroundColor White
    Write-Host '  2. Clear safe temporary files and the Recycle Bin' -ForegroundColor White
    Write-Host '  3. Run a non-destructive disk scan of C:' -ForegroundColor White
    Write-Host '  4. Run DISM and SFC Windows repair checks' -ForegroundColor White
    Write-Host ''
    Write-Host 'This may take a while depending on the PC.' -ForegroundColor DarkRed

    if (-not (Confirm-ToolkitAction 'Type YES and press Enter to begin guided maintenance, or press Enter to cancel.')) {
        Write-Host 'Cancelled.' -ForegroundColor DarkRed
        Pause-Toolkit
        return
    }

    Get-SystemReport
    Clear-SafeTempFiles -SkipConfirmation
    Test-DiskHealth
    Start-WindowsRepair -SkipConfirmation

    Write-Host ''
    Write-Host 'Guided maintenance finished.' -ForegroundColor White
    Pause-Toolkit
}

while ($true) {
    Show-Header

    Write-Host '1.  Save full system / hardware / network report' -ForegroundColor Yellow
    Write-Host '2.  Create battery health report' -ForegroundColor Yellow
    Write-Host '3.  Check drivers and devices with errors' -ForegroundColor Yellow
    Write-Host '4.  Check disk health and scan C:' -ForegroundColor Yellow
    Write-Host '5.  Repair Windows image and system files (DISM + SFC)' -ForegroundColor Yellow
    Write-Host '6.  Clear safe temporary files and Recycle Bin' -ForegroundColor Yellow
    Write-Host '7.  Save network diagnostic report' -ForegroundColor Yellow
    Write-Host '8.  Export recent critical/error system events' -ForegroundColor Yellow
    Write-Host '9.  Open Windows Update and Storage settings' -ForegroundColor Yellow
    Write-Host '10. Run guided maintenance' -ForegroundColor Yellow

    Write-Host ''
    Write-Host '--- Optimization ---' -ForegroundColor DarkRed

    Write-Host '11. Set High Performance power plan' -ForegroundColor Yellow
    Write-Host '12. Optimize drives (TRIM SSD / optimize HDD)' -ForegroundColor Yellow
    Write-Host '13. Review startup programs' -ForegroundColor Yellow
    Write-Host '14. Set visual effects to best performance' -ForegroundColor Yellow
    Write-Host '15. Clear Windows Update download cache' -ForegroundColor Yellow
    Write-Host '16. Launch Disk Cleanup utility' -ForegroundColor Yellow
    Write-Host '17. Run full optimization pass' -ForegroundColor Yellow
    Write-Host '18. Check for and install available driver updates' -ForegroundColor Yellow
    Write-Host '0.  Exit' -ForegroundColor Yellow
    Write-Host ''

    $Choice = Read-Host 'Choose an option'

    switch ($Choice) {
        '1'  { Get-SystemReport }
        '2'  { Get-BatteryReport }
        '3'  { Get-DriverAndDeviceReport }
        '4'  { Test-DiskHealth }
        '5'  { Start-WindowsRepair }
        '6'  { Clear-SafeTempFiles }
        '7'  { Get-NetworkReport }
        '8'  { Get-RecentCriticalEvents }
        '9'  { Open-WindowsMaintenancePages }
        '10' { Start-GuidedMaintenance }
        '11' { Set-HighPerformancePower }
        '12' { Optimize-Drives }
        '13' { Review-StartupPrograms }
        '14' { Disable-VisualEffectsForPerformance }
        '15' { Clear-WindowsUpdateCache }
        '16' { Run-DiskCleanupUtility }
        '17' { Start-FullOptimizationPass }
        '18' { Update-AvailableDrivers }
        '0'  { break }

        default {
            Write-Host 'Invalid choice.' -ForegroundColor DarkRed
            Start-Sleep -Seconds 1
        }
    }
}

try {
    Stop-Transcript | Out-Null
} catch {
}

Write-Host 'Toolkit closed.' -ForegroundColor DarkRed
