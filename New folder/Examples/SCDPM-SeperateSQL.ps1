#requires -Version 5

Configuration DPM
{
    Import-DscResource -Module xDismFeature
    Import-DscResource -Module xDeploy

    $SystemCenter2012R2DataProtectionManagerDatabaseServer = $AllNodes.Where{$_.Roles | Where-Object {$_ -eq "System Center 2012 R2 Data Protection Manager Database Server"}}.NodeName
    $SystemCenter2012R2DataProtectionManagerServers = @($AllNodes.Where{$_.Roles | Where-Object {$_ -eq "System Center 2012 R2 Data Protection Manager Server"}}.NodeName)
        
    Node $AllNodes.NodeName
    {
        # Set LCM to reboot if needed since there are several reboots during DPM install
        LocalConfigurationManager
        {
            DebugMode = $true
            RebootNodeIfNeeded = $true
        }

        # Install .NET Framework 3.5 on database and server nodes
        WindowsFeature "NET-Framework-Core"
        {
            Ensure = "Present"
            Name = "NET-Framework-Core"
            Source = $Node.SourcePath + "\WindowsServer2012R2\sources\sxs"
        }

        # Install SQL on database node and SQL management tools on server nodes
        $Features = ""
        if($Node.NodeName -eq $SystemCenter2012R2DataProtectionManagerDatabaseServer)
        {
            $Features = "SQLENGINE,RS,"
        }
        if ($SystemCenter2012R2DataProtectionManagerServers | Where-Object {$_ -eq $Node.NodeName})
        {
            $Features += "SSMS,ADV_SSMS"
        }
        $Features = $Features.Trim(",")
        xSqlServerSetup "MSSQLSERVER"
        {
            DependsOn = "[WindowsFeature]NET-Framework-Core"
            SourcePath = $Node.SourcePath
            Credential = $Node.InstallerServiceAccount
            InstanceName = "MSSQLSERVER"
            Features = $Features
            SQLSysAdminAccounts = $Node.AdminAccount
            SQLSvcAccount = $Node.LocalSystemAccount
            AgtSvcAccount = $Node.LocalSystemAccount
            RSSvcAccount = $Node.LocalSystemAccount
        }

        # DPM database server
        if($Node.NodeName -eq $SystemCenter2012R2DataProtectionManagerDatabaseServer)
        {
            # Set SQL firewall rule on database node
            xSQLServerFirewall MSSQLSERVER
            {
                DependsOn = "[xSqlServerSetup]MSSQLSERVER"
                Ensure = "Present"
                SourcePath = $Node.SourcePath
                Features = $Features
                InstanceName = "MSSQLSERVER"
            }

            # Set SSRS secure connection level on database node
            xSQLServerRSSecureConnectionLevel MSSQLSERVER
            {
                DependsOn = "[xSqlServerSetup]MSSQLSERVER"
                InstanceName = "MSSQLSERVER"
                SecureConnectionLevel = 0
                Credential = $Node.InstallerServiceAccount
            }
        }

        # Install DPM database support on database server if it is seperate from the DPM server
        if(($Node.NodeName -eq $SystemCenter2012R2DataProtectionManagerDatabaseServer) -and (!($SystemCenter2012R2DataProtectionManagerServers | Where-Object {$_ -eq $Node.NodeName})))
        {
            xSCDPMDatabaseServerSetup "DPMDB"
            {
                DependsOn = "[xSqlServerSetup]MSSQLSERVER"
                Ensure = "Present"
                SourcePath = $Node.SourcePath
                Credential = $Node.InstallerServiceAccount
            }
        }

        # DPM servers
        if ($SystemCenter2012R2DataProtectionManagerServers | Where-Object {$_ -eq $Node.NodeName})
        {
            # Install Single Instance Storage
            xDismFeature "SIS-Limited"
            {
                Ensure = "Present"
                Name = "SIS-Limited"
            }

            if($Node.NodeName -ne $SystemCenter2012R2DataProtectionManagerDatabaseServer)
            {
                xSCDPMDatabaseServerSetup "DPMDB"
                {
                    Ensure = "Absent"
                    SourcePath = $Node.SourcePath
                    Credential = $Node.InstallerServiceAccount
                }
            }

            # Wait for DPM database server install, firewall, and config
            WaitForAll "DPMDB"
            {
                NodeName = $SystemCenter2012R2DataProtectionManagerDatabaseServer
                ResourceName = "[xSqlServerSetup]MSSQLSERVER"
                Credential = $Node.InstallerServiceAccount
                RetryIntervalSec = 5
                RetryCount = 720
            }

            WaitForAll "DPMFW"
            {
                NodeName = $SystemCenter2012R2DataProtectionManagerDatabaseServer
                ResourceName = "[xSQLServerFirewall]MSSQLSERVER"
                Credential = $Node.InstallerServiceAccount
                RetryIntervalSec = 5
                RetryCount = 720

            }

            WaitForAll "DPMRS"
            {
                NodeName = $SystemCenter2012R2DataProtectionManagerDatabaseServer
                ResourceName = "[xSQLServerRSSecureConnectionLevel]MSSQLSERVER"
                Credential = $Node.InstallerServiceAccount
                RetryIntervalSec = 5
                RetryCount = 720
            }

            # Wait for all DPM servers before this one
            $DPMDependsOn = @(
                "[WindowsFeature]NET-Framework-Core",
                "[xSCDPMDatabaseServerSetup]DPMDB"
                "[xDismFeature]SIS-Limited",
                "[WaitForAll]DPMDB",
                "[WaitForAll]DPMFW",
                "[WaitForAll]DPMRS"
            )
            $DPMServers = @()
            $ThisDPMServer = $false
            foreach($DPMServer in $SystemCenter2012R2DataProtectionManagerServers)
            {
                if(!($ThisDPMServer) -and ($Node.NodeName -ne $DPMServer))
                {
                    $DPMServers += $DPMServer
                }
                else
                {
                    $ThisDPMServer = $true
                }
            }
            if($DPMServers)
            {
                WaitForAll "DPM"
                {
                    NodeName = $DPMServers
                    ResourceName = "[xSCDPMServerSetup]DPM"
                    Credential = $Node.InstallerServiceAccount
                    RetryIntervalSec = 5
                    RetryCount = 720
                }
                $DPMDependsOn += @("[WaitForAll]DPM")
            }

            xSCDPMServerSetup "DPM"
            {
                DependsOn = $DPMDependsOn
                Ensure = "Present"
                SourcePath = $Node.SourcePath
                Credential = $Node.InstallerServiceAccount
                YukonMachineName = $SystemCenter2012R2DataProtectionManagerDatabaseServer
                YukonInstanceName = "MSSQLSERVER"
                ReportingMachineName = $SystemCenter2012R2DataProtectionManagerDatabaseServer
                ReportingInstanceName = "MSSQLSERVER"
                YukonMachineCredential = $Node.InstallerServiceAccount
                ReportingMachineCredential = $Node.InstallerServiceAccount
            }
        }
    }
}

$SecurePassword = ConvertTo-SecureString -String "Pass@word1" -AsPlainText -Force
$InstallerServiceAccount = New-Object System.Management.Automation.PSCredential ("CONTOSO\!Installer", $SecurePassword)
$LocalSystemAccount = New-Object System.Management.Automation.PSCredential ("SYSTEM", $SecurePassword)

$ConfigurationData = @{
    AllNodes = @(
        @{
            NodeName = "*"
            SourcePath = "\\RD01\Installer"
            InstallerServiceAccount = $InstallerServiceAccount
            LocalSystemAccount = $LocalSystemAccount
            PSDscAllowPlainTextPassword = $true
            AdminAccount = "CONTOSO\Administrator"
        }
        @{
            NodeName = "DPMDB.contoso.com"
            Roles = @("System Center 2012 R2 Data Protection Manager Database Server")
        }
        @{
            NodeName = "DPM01.contoso.com"
            Roles = @("System Center 2012 R2 Data Protection Manager Server")
        }
    )
}

foreach($Node in $ConfigurationData.AllNodes)
{
    if($Node.NodeName -ne "*")
    {
        Start-Process -FilePath "robocopy.exe" -ArgumentList ("`"C:\Program Files\WindowsPowerShell\Modules`" `"\\" + $Node.NodeName + "\c$\Program Files\WindowsPowerShell\Modules`" /e /purge /xf") -NoNewWindow -Wait
    }
}

DPM -ConfigurationData $ConfigurationData
Set-DscLocalConfigurationManager -Path .\DPM -Verbose
Start-DscConfiguration -Path .\DPM -Verbose -Wait -Force