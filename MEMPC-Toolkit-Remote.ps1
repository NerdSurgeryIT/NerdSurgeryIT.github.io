# Nerd Surgery IT - Remote PC Toolkit
# Designed to be loaded into an interactive PowerShell session from GitHub.
# It does not create logs or report folders automatically. Some options may
# create a file only when Windows itself requires one (such as a battery report).

$ErrorActionPreference = 'Continue'

function Pause-Toolkit {
    Write-Host ''
    Read-Host 'Press Enter to return to the main menu'
}

function Confirm-ToolkitAction {
    param([string]$Message = 'Type YES and press Enter to continue, or press Enter to cancel.')
    Write-Host ''
    Write-Host $Message -ForegroundColor White
    return ((Read-Host 'Your answer') -match '^(Y|YES)$')
}

function Show-Header {
    Clear-Host
    Write-Host '==================================================' -ForegroundColor DarkCyan
    Write-Host '          NERD SURGERY IT - REMOTE TOOLKIT       ' -ForegroundColor Cyan
    Write-Host '==================================================' -ForegroundColor DarkCyan
    Write-Host 'Running in the current PowerShell session.' -ForegroundColor DarkGray
    if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Host ''
        Write-Host 'WARNING: Not running as Administrator. Some maintenance tasks may fail.' -ForegroundColor Yellow
    }
    Write-Host ''
}

function Get-SystemReport {
    Write-Host 'Collecting system information...' -ForegroundColor Cyan
    $OS = Get-CimInstance Win32_OperatingSystem
    $Computer = Get-CimInstance Win32_ComputerSystem
    $BIOS = Get-CimInstance Win32_BIOS
    $CPU = Get-CimInstance Win32_Processor
    $Drives = Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3'
    $MemoryGB = [math]::Round($Computer.TotalPhysicalMemory / 1GB, 2)

    $Report = @"
==================================================
NERD SURGERY IT - SYSTEM REPORT
Generated: $(Get-Date)
==================================================

COMPUTER
Name:          $env:COMPUTERNAME
Manufacturer:  $($Computer.Manufacturer)
Model:         $($Computer.Model)
Serial Number: $($BIOS.SerialNumber)

WINDOWS
Edition:       $($OS.Caption)
Version:       $($OS.Version) (Build $($OS.BuildNumber))
Installed:     $($OS.InstallDate)

HARDWARE
CPU:           $($CPU.Name)
Installed RAM: $MemoryGB GB

STORAGE
$($Drives | ForEach-Object { "Drive $($_.DeviceID)  Total: $([math]::Round($_.Size / 1GB, 1)) GB | Free: $([math]::Round($_.FreeSpace / 1GB, 1)) GB" } | Out-String)

NETWORK ADAPTERS
$(Get-NetAdapter -ErrorAction SilentlyContinue | Select-Object Name, Status, LinkSpeed, MacAddress | Format-Table -AutoSize | Out-String)
"@
    Write-Host $Report -ForegroundColor White
    Pause-Toolkit
}

function Get-BatteryReport {
    $Path = Join-Path $env:TEMP "NerdSurgery_Battery_Report_$env:COMPUTERNAME.html"
    Write-Host 'Creating a temporary Windows battery report...' -ForegroundColor Cyan
    powercfg /batteryreport /output $Path | Out-Null
    if (Test-Path $Path) {
        Write-Host "Created: $Path" -ForegroundColor Green
        Write-Host 'This option creates an HTML report in the Windows temporary folder.' -ForegroundColor DarkGray
    } else {
        Write-Host 'Battery report could not be created. This is normal on many desktops.' -ForegroundColor Yellow
    }
    Pause-Toolkit
}

function Get-DriverAndDeviceReport {
    Write-Host 'Checking installed devices for errors...' -ForegroundColor Cyan
    $ProblemDevices = Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue | Where-Object { $_.Status -ne 'OK' }
    if ($ProblemDevices) {
        $ProblemDevices | Select-Object Class, FriendlyName, Status, InstanceId | Format-Table -AutoSize | Out-Host
    } else { Write-Host 'No device errors were detected.' -ForegroundColor Green }
    Pause-Toolkit
}

function Test-DiskHealth {
    Write-Host 'Physical disk status:' -ForegroundColor Cyan
    Get-PhysicalDisk -ErrorAction SilentlyContinue | Select-Object FriendlyName, MediaType, HealthStatus, OperationalStatus, Size | Format-Table -AutoSize | Out-Host
    Write-Host 'Running an online scan of C:. This does not schedule repairs or erase files.' -ForegroundColor Cyan
    chkdsk C: /scan
    Pause-Toolkit
}

function Start-WindowsRepair {
    param([switch]$SkipConfirmation)
    if (-not $SkipConfirmation -and -not (Confirm-ToolkitAction 'Type YES to run DISM followed by SFC, or press Enter to cancel.')) { Write-Host 'Skipped.' -ForegroundColor Yellow; Pause-Toolkit; return }
    Write-Host 'Running DISM component repair...' -ForegroundColor Cyan
    DISM /Online /Cleanup-Image /RestoreHealth
    Write-Host 'Running System File Checker...' -ForegroundColor Cyan
    sfc /scannow
    Write-Host 'Repair checks finished. Restart if either tool repaired files.' -ForegroundColor Green
    if (-not $SkipConfirmation) { Pause-Toolkit }
}

function Clear-SafeTempFiles {
    param([switch]$SkipConfirmation)
    if (-not $SkipConfirmation -and -not (Confirm-ToolkitAction 'Type YES to clear temporary files and the Recycle Bin, or press Enter to cancel.')) { Write-Host 'Skipped.' -ForegroundColor Yellow; Pause-Toolkit; return }
    @("$env:TEMP\*", "$env:WINDIR\Temp\*") | ForEach-Object { Remove-Item -Path $_ -Force -Recurse -ErrorAction SilentlyContinue }
    try { Clear-RecycleBin -Force -ErrorAction Stop; Write-Host 'Recycle Bin cleared.' -ForegroundColor Green } catch { Write-Host 'Recycle Bin was not cleared or was already empty.' -ForegroundColor DarkGray }
    Write-Host 'Temporary-file cleanup finished.' -ForegroundColor Green
    if (-not $SkipConfirmation) { Pause-Toolkit }
}

function Get-NetworkReport {
    Write-Host 'Network adapters:' -ForegroundColor Cyan
    Get-NetAdapter -ErrorAction SilentlyContinue | Select-Object Name, Status, LinkSpeed, MacAddress | Format-Table -AutoSize | Out-Host
    Write-Host 'DNS test:' -ForegroundColor Cyan
    Resolve-DnsName microsoft.com -ErrorAction SilentlyContinue | Select-Object Name, Type, IPAddress | Format-Table -AutoSize | Out-Host
    Write-Host 'Internet ping test:' -ForegroundColor Cyan
    Test-Connection 1.1.1.1 -Count 2 -ErrorAction SilentlyContinue | Select-Object Address, ResponseTime, Status | Format-Table -AutoSize | Out-Host
    Pause-Toolkit
}

function Get-RecentCriticalEvents {
    Write-Host 'Recent System critical/error events (last 7 days):' -ForegroundColor Cyan
    $Events = Get-WinEvent -FilterHashtable @{ LogName = 'System'; StartTime = (Get-Date).AddDays(-7) } -ErrorAction SilentlyContinue | Where-Object { $_.LevelDisplayName -in @('Critical', 'Error') }
    if ($Events) { $Events | Select-Object -First 15 TimeCreated, ProviderName, Id, LevelDisplayName, Message | Format-List | Out-Host } else { Write-Host 'No System critical or error events were found.' -ForegroundColor Green }
    Pause-Toolkit
}

function Set-HighPerformancePower {
    param([switch]$SkipPause)
    Write-Host 'Setting the High Performance power plan...' -ForegroundColor Cyan
    powercfg -duplicatescheme SCHEME_MIN | Out-Null
    powercfg /setactive SCHEME_MIN
    Write-Host 'High Performance plan enabled. This can reduce battery life on laptops.' -ForegroundColor Green
    if (-not $SkipPause) { Pause-Toolkit }
}

function Optimize-Drives {
    param([switch]$SkipConfirmation)
    if (-not $SkipConfirmation -and -not (Confirm-ToolkitAction 'Type YES to optimize drives, or press Enter to cancel.')) { Write-Host 'Skipped.' -ForegroundColor Yellow; Pause-Toolkit; return }
    Get-Volume | Where-Object { $_.DriveLetter } | ForEach-Object { $Drive = "$($_.DriveLetter):"; Write-Host "Optimizing $Drive..." -ForegroundColor Cyan; defrag $Drive /O }
    Write-Host 'Drive optimization complete.' -ForegroundColor Green
    if (-not $SkipConfirmation) { Pause-Toolkit }
}

function Review-StartupPrograms {
    Get-CimInstance Win32_StartupCommand | Select-Object Name, Command, Location | Format-Table -AutoSize | Out-Host
    Write-Host 'Review or disable startup apps in Task Manager as needed.' -ForegroundColor DarkGray
    Pause-Toolkit
}

function Clear-WindowsUpdateCache {
    param([switch]$SkipConfirmation)
    if (-not $SkipConfirmation -and -not (Confirm-ToolkitAction 'Type YES to clear the Windows Update download cache, or press Enter to cancel.')) { Write-Host 'Skipped.' -ForegroundColor Yellow; Pause-Toolkit; return }
    Stop-Service -Name wuauserv -Force -ErrorAction SilentlyContinue
    Stop-Service -Name bits -Force -ErrorAction SilentlyContinue
    Remove-Item -Path "$env:WINDIR\SoftwareDistribution\Download\*" -Recurse -Force -ErrorAction SilentlyContinue
    Start-Service -Name wuauserv -ErrorAction SilentlyContinue
    Start-Service -Name bits -ErrorAction SilentlyContinue
    Write-Host 'Windows Update download cache cleared.' -ForegroundColor Green
    if (-not $SkipConfirmation) { Pause-Toolkit }
}

function Start-FullOptimizationPass {
    Write-Host 'This will set High Performance, clear temporary files, clear the Windows Update cache, and optimize drives.' -ForegroundColor Yellow
    if (-not (Confirm-ToolkitAction 'Type YES to run the full optimization pass, or press Enter to cancel.')) { Write-Host 'Cancelled.' -ForegroundColor Yellow; Pause-Toolkit; return }
    Set-HighPerformancePower -SkipPause
    Clear-SafeTempFiles -SkipConfirmation
    Clear-WindowsUpdateCache -SkipConfirmation
    Optimize-Drives -SkipConfirmation
    Write-Host 'Full optimization pass finished.' -ForegroundColor Green
    Pause-Toolkit
}

while ($true) {
    Show-Header
    Write-Host '1.  System specifications and hardware overview' -ForegroundColor White
    Write-Host '2.  Create temporary battery health report' -ForegroundColor White
    Write-Host '3.  Check driver and hardware errors' -ForegroundColor White
    Write-Host '4.  Check physical disk health and scan C:' -ForegroundColor White
    Write-Host '5.  Repair Windows image and system files (DISM + SFC)' -ForegroundColor White
    Write-Host '6.  Clear safe temporary files and Recycle Bin' -ForegroundColor White
    Write-Host '7.  Network and DNS connectivity test' -ForegroundColor White
    Write-Host '8.  Review recent System critical/error events' -ForegroundColor White
    Write-Host '9.  Review startup programs' -ForegroundColor White
    Write-Host '10. Clear Windows Update download cache' -ForegroundColor White
    Write-Host '11. Optimize drives (TRIM SSDs / optimize HDDs)' -ForegroundColor White
    Write-Host '12. Set High Performance power plan' -ForegroundColor White
    Write-Host '13. Run full optimization pass' -ForegroundColor Green
    Write-Host '0.  Exit' -ForegroundColor Yellow
    Write-Host ''
    switch (Read-Host 'Select an option') {
        '1' { Get-SystemReport }; '2' { Get-BatteryReport }; '3' { Get-DriverAndDeviceReport }; '4' { Test-DiskHealth }
        '5' { Start-WindowsRepair }; '6' { Clear-SafeTempFiles }; '7' { Get-NetworkReport }; '8' { Get-RecentCriticalEvents }
        '9' { Review-StartupPrograms }; '10' { Clear-WindowsUpdateCache }; '11' { Optimize-Drives }; '12' { Set-HighPerformancePower }
        '13' { Start-FullOptimizationPass }; '0' { break }
        default { Write-Host 'Invalid choice.' -ForegroundColor Red; Start-Sleep -Seconds 1 }
    }
}
Write-Host 'Toolkit closed.' -ForegroundColor Cyan
