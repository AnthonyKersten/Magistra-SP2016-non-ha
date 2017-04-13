Function Get-TargetResource
{
    [CmdletBinding()]
     param
    (
	[Parameter(Mandatory=$true)]
    [string]$Name
    )

    $ComponentBasedServicing = (Get-ItemProperty 'hklm:SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\').RebootPending -ne $null
    $WindowsUpdate = (Get-ItemProperty 'hklm:SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\').RebootRequired -ne $null
    $PendingFileRename = (Get-ItemProperty 'hklm:\SYSTEM\CurrentControlSet\Control\Session Manager\').PendingFileRenameOperations -ne $null

    return @{
    Name = $Name
    ComponentBasedServicing = $ComponentBasedServicing
    WindowsUpdate = $WindowsUpdate
    PendingFileRename = $PendingFileRename
    }
}

Function Set-TargetResource
{
    [CmdletBinding()]
     param
    (
	[Parameter(Mandatory=$true)]
    [string]$Name
    )

    if ((Test-TargetResource @PSBoundParameters) -eq $false) {
        
        Write-Verbose 'A pending reboot was found.'
        
        Write-Verbose 'Setting the DSCMachineStatus global variable to 1.'
        $global:DSCMachineStatus = 1
        }
    else {Write-Verbose 'No pending reboots found.'}
}

Function Test-TargetResource
{
    [CmdletBinding()]
     param
    (
	[Parameter(Mandatory=$true)]
    [string]$Name
    )

    $regRebootLocations += @{'HKLM:SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\'='RebootPending'}
    $regRebootLocations += @{'HKLM:SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\'='RebootRequired'}
    $regRebootLocations += @{'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\'='PendingFileRenameOperations'}

    $RebootPendingTest = $false
    foreach ($reg in $regRebootLocations.keys) {
        if ((Get-ItemProperty $reg).($regRebootLocations[$reg]) -eq $Null) {
            $RebootPendingTest = $true}
        }

    return $RebootPendingTest
}

Export-ModuleMember -Function *-TargetResource