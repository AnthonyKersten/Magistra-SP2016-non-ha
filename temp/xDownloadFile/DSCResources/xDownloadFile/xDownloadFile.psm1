function Get-TargetResource
{
	[CmdletBinding()]
	[OutputType([System.Collections.Hashtable])]
	param
	(
		[parameter(Mandatory = $true)]
		[System.String]
		$SourcePath,
		
		[parameter(Mandatory = $true)]
		[System.String]
		$FileName,

        [parameter(Mandatory = $true)]
		[System.String]
		$DestinationDirectoryPath
	)

	#Write-Verbose "Use this cmdlet to deliver information about command processing."

	#Write-Debug "Use this cmdlet to write debug information while troubleshooting."

	$returnValue = @{
		SourcePath = $SourcePath
		FileName  = $FileName
        DestinationDirectoryPath = $DestinationDirectoryPath
	}
    $returnValue
}


function Set-TargetResource
{
	[CmdletBinding()]
	param
	(
		[parameter(Mandatory = $true)]
		[System.String]
		$SourcePath,
		
		[parameter(Mandatory = $true)]
		[System.String]
		$FileName,

        [parameter(Mandatory = $true)]
		[System.String]
		$DestinationDirectoryPath
	)

    Write-Verbose "Create Destination Directory"
	if(!(Test-Path $DestinationDirectoryPath))
	{
		New-Item -Path $DestinationDirectoryPath -ItemType Directory -Force
	}
	
    $output = Join-Path $DestinationDirectoryPath $FileName
	$startTime = [System.DateTimeOffset]::Now
    Write-Verbose "Start to download file from $SourcePath"
    Get-BitsTransfer | Remove-BitsTransfer
    $downloadJob = Start-BitsTransfer -Source $SourcePath -Destination $output -DisplayName "Download" -Asynchronous -RetryInterval 60 -Priority Foreground

	while (-not ((Get-BitsTransfer -JobId $downloadJob.JobId).JobState -eq "Transferred"))
	{
		Start-Sleep -Seconds (2 * 60)
		Write-Verbose -Verbose -Message ("Waiting for $SourcePath, time taken: {0}" -f ([System.DateTimeOffset]::Now - $startTime).ToString())
        Write-Verbose -Message ($downloadJob | Format-List | Out-String)
	}
    Complete-BitsTransfer -BitsJob $downloadJob
    Write-Verbose "Complete download file from $SourcePath"
}


function Test-TargetResource
{
	[CmdletBinding()]
	[OutputType([System.Boolean])]
	param
	(
		[parameter(Mandatory = $true)]
		[System.String]
		$SourcePath,
		
		[parameter(Mandatory = $true)]
		[System.String]
		$FileName,

        [parameter(Mandatory = $true)]
		[System.String]
		$DestinationDirectoryPath
	)
	$output = Join-Path $DestinationDirectoryPath $FileName
	Test-Path $output
}


Export-ModuleMember -Function *-TargetResource

