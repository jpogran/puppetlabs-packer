$ErrorActionPreference = "Stop"

. A:\windows-env.ps1

# Boxstarter options
$Boxstarter.RebootOk=$true # Allow reboots?
$Boxstarter.NoPassword=$false # Is this a machine with no login password?
$Boxstarter.AutoLogin=$true # Save my password securely and auto-login after a reboot

if (Test-PendingReboot){ Invoke-Reboot }

# Need to guard against system going into standby for long updates
Write-BoxstarterMessage "Disabling Sleep timers"
Disable-PC-Sleep

# Need to use WUServer as updates won't work from main MS Servers - similar to Win-2013 issues
reg.exe ADD "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate"    /v "WUServer"       /t REG_SZ /d "http://10.32.163.228:8530" /f
reg.exe ADD "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate"    /v "WUStatusServer" /t REG_SZ /d "http://10.32.163.228:8530" /f

reg.exe ADD "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" /v "NoAutoUpdate" /t REG_DWORD /d 0 /f
reg.exe ADD "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" /v "AUOptions" /t REG_DWORD /d 2 /f
reg.exe ADD "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" /v "ScheduledInstallDay" /t REG_DWORD /d 0 /f
reg.exe ADD "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" /v "ScheduledInstallTime" /t REG_DWORD /d 3 /f
reg.exe ADD "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" /v "UseWUServer" /t REG_DWORD /d 1 /f

# Make sure network connection is private
Write-BoxstarterMessage "Setting network adapters to private"
$networkListManager = [Activator]::CreateInstance([Type]::GetTypeFromCLSID([Guid]"{DCB00C01-570F-4A9B-8D69-199FDBA5723B}"))
$connections = $networkListManager.GetNetworkConnections()

if (-not (Test-Path "A:\NET35.Installed"))
{
  # Install .Net 3.5.1
  Write-Host ".Net 3.5.1"
  Download-File "http://buildsources.delivery.puppetlabs.net/windows/win-2008-ps2/dotnetfx35setup.exe"  "$ENV:TEMP\dotnetfx35setup.exe"
  Start-Process -Wait "$ENV:TEMP\dotnetfx35setup.exe" -ArgumentList "/q"
  Write-Host ".Net 3.5.1 Installed"
  Touch-File "A:\NET35.Installed"
  if (Test-PendingReboot) { Invoke-Reboot }
}

if (-not (Test-Path "A:\WinUpdate.Installed"))
{
  # Install .Net 3.5.1
  Write-Host "Updating Windows Update agent"
  Download-File "http://buildsources.delivery.puppetlabs.net/windows/win-2008-ps2/windowsupdateagent30-x64.exe"  "$ENV:TEMP\windowsupdateagent30-x64.exe"
  Start-Process -Wait "$ENV:TEMP\windowsupdateagent30-x64.exe" -ArgumentList "/q"
  Write-Host "Updating Windows Update agent"
  Touch-File "A:\WinUpdate.Installed"
  if (Test-PendingReboot) { Invoke-Reboot }
}

if (-not (Test-Path "A:\Win2008.Patches"))
{
  $patches = @(
    'http://download.windowsupdate.com/d/msdownload/update/software/secu/2016/04/windows6.0-kb3153199-x64_ff7991c9c3465327640c5fdf296934ac12467fd0.msu',
    "http://download.windowsupdate.com/d/msdownload/update/software/secu/2016/04/windows6.0-kb3145739-x64_918212eb27224cf312f865e159f172a4b8a75b76.msu"
  )
  $patches | % { Install_Win_Patch -PatchUrl $_ }

  Touch-File "A:\Win2008.Patches"
  if (Test-PendingReboot) { Invoke-Reboot }
}

if (-not (Test-Path "A:\NET45.installed"))
{
  # Install .Net Framework 4.5.2
  Write-BoxstarterMessage "Installing .Net 4.5"
  choco install dotnet4.5 -y
  Touch-File "A:\NET45.installed"
  if (Test-PendingReboot) { Invoke-Reboot }
}

# Install Updates and reboot until this is completed.
try {
    Install-WindowsUpdate -AcceptEula
}
catch {
    Write-Host "Ignoring first Update error."
}
if (Test-PendingReboot) { Invoke-Reboot }
Install-WindowsUpdate -AcceptEula
if (Test-PendingReboot) { Invoke-Reboot }

# Enable RDP
Write-BoxstarterMessage "Enable Remote Desktop"
Enable-RemoteDesktop
netsh advfirewall firewall add rule name="Remote Desktop" dir=in localport=3389 protocol=TCP action=allow

# Add WinRM Firewall Rule
Write-BoxstarterMessage "Adding Firewall rules for win-rm"
netsh advfirewall firewall add rule name="WinRM-HTTP" dir=in localport=5985 protocol=TCP action=allow

Write-BoxstarterMessage "Setup PSRemoting"
$enableArgs=@{Force=$true}
try {
 $command=Get-Command Enable-PSRemoting
  if($command.Parameters.Keys -contains "skipnetworkprofilecheck"){
      $enableArgs.skipnetworkprofilecheck=$true
  }
}
catch {
  $global:error.RemoveAt(0)
}
Write-BoxstarterMessage "Enable PS-Remoting -Force"
try {
  Enable-PSRemoting @enableArgs
}
catch {
  Write-BoxstarterMessage "Ignoring PSRemoting Error"
}

Write-BoxstarterMessage "Enable WSMandCredSSP"
Enable-WSManCredSSP -Force -Role Server


# NOTE - This is insecure but can be shored up in later customisation.  Required for Vagrant and other provisioning tools
Write-BoxstarterMessage "WinRM Settings"
winrm set winrm/config/client/auth '@{Basic="true"}'
winrm set winrm/config/service/auth '@{Basic="true"}'
winrm set winrm/config/service '@{AllowUnencrypted="true"}'
winrm set winrm/config/winrs '@{MaxMemoryPerShellMB="2048"}'
# Set service to start automatically (not delayed)
Set-Service "WinRM" -StartupType Automatic

Write-BoxstarterMessage "WinRM setup complete"

# End
