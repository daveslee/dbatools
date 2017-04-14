﻿Function Export-DbaScript {
    <#
	.SYNOPSIS
	Exports scripts from SQL Management Objects (SMO)

	.DESCRIPTION
	Exports scripts from SQL Management Objects

	.PARAMETER InputObject
	A SQL Managment Object such as the one returned from Get-DbaLogin
		
	.PARAMETER Path
	The output filename and location. If no path is specified, one will be created 
		
	.PARAMETER Append
	Append contents to existing file. If append is not specified and the path exists, the export will be skipped.
		
	.PARAMETER Encoding
	Specifies the file encoding. The default is UTF8.
		
	Valid values are:

	-- ASCII: Uses the encoding for the ASCII (7-bit) character set.

	-- BigEndianUnicode: Encodes in UTF-16 format using the big-endian byte order.

	-- Byte: Encodes a set of characters into a sequence of bytes.

	-- String: Uses the encoding type for a string.

	-- Unicode: Encodes in UTF-16 format using the little-endian byte order.

	-- UTF7: Encodes in UTF-7 format.

	-- UTF8: Encodes in UTF-8 format.

	-- Unknown: The encoding type is unknown or invalid. The data can be treated as binary.

	.PARAMETER Passthru
	Output script to console

	.PARAMETER WhatIf 
	Shows what would happen if the command were to run. No actions are actually performed

	.PARAMETER Confirm 
	Prompts you for confirmation before executing any changing operations within the command

	.PARAMETER Silent 
	Use this switch to disable any kind of verbose messages

	.NOTES
	Tags: Migration, Backup, Export
	
	Website: https://dbatools.io
	Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
	License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

	.LINK
	https://dbatools.io/Export-DbaScript
	
	.EXAMPLE
	Get-DbaAgentJob -SqlInstance sql2016 | Export-DbaScript
	
	Exports all jobs on the SQL Server sql2016 instance using a trusted connection - automatically determines filename as .\servername-jobs-date.sql
	
	.EXAMPLE 
	Get-DbaAgentJob -SqlInstance sql2016 -Jobs syspolicy_purge_history, 'Hourly Log Backups' -SqlCredential (Get-Credetnial sqladmin) | Export-DbaScript -Path C:\temp\export.sql
		
	Exports only syspolicy_purge_history and 'Hourly Log Backups' to C:temp\export.sql and uses the SQL login "sqladmin" to login to sql2016
	
	.EXAMPLE 
	Get-DbaAgentJob -SqlInstance sql2014 | Export-DbaJob -Passthru | ForEach-Object { $_.Replace('sql2014','sql2016') } | Set-Content -Path C:\temp\export.sql
		
	Exports jobs and replaces all instances of the servername "sql2014" with "sql2016" then writes to C:\temp\export.sql
	
	.EXAMPLE
	$options = New-DbaScriptingOption
	$options.Options.ScriptDrops = $false
	$options.Options.WithDependencies = $true
	Get-DbaAgentJob -SqlInstance sql2016 | Export-DbaScript -ScriptingOptionObject $options
	
	Exports Agent Jobs with the Scripting Options ScriptDrops set to $false and WithDependencies set to true.

	#>
	
	[CmdletBinding(SupportsShouldProcess = $true)]
	param (
		[parameter(Mandatory = $true, ValueFromPipeline = $true)]
		[object[]]$InputObject,
		[Microsoft.SqlServer.Management.Smo.ScriptingOptions]$ScriptingOptionObject,
		[string]$Path,
		[ValidateSet('ASCII', 'BigEndianUnicode', 'Byte', 'String', 'Unicode', 'UTF7', 'UTF8', 'Unknown')]
		[string]$Encoding = 'UTF8',
		[switch]$Append,
		[switch]$Passthru,
		[switch]$Silent
	)
	
	begin {
		$executinguser = [Security.Principal.WindowsIdentity]::GetCurrent().Name
		$commandname = $MyInvocation.MyCommand.Name
		$timenow = (Get-Date -uformat "%m%d%Y%H%M%S")
	}
	
	process {
		foreach ($object in $inputobject) {
			
			# Find the server object to pass on to the function
			$parent = $object.parent
			
			do {
				$parent = $parent.parent
			}
			until (($parent.urn.type -eq "Server") -or (-not $parent))
			
			if (-not $parent) {
				Stop-Function -Message "Failed to find valid server object in input: $object. Did you pass an SQL Management Object?" -Silent $Silent -Category InvalidData -Continue -Target $object
			}
			
			$server = $parent
			$servername = $server.name.replace('\', '$')
			
			if (!$passthru) {
				if ($path) {
					$actualpath = $path
				}
				else {
					$actualpath = "$servername-$smoname-$timenow.sql"
				}
			}
			
			$prefix = "
/*			
	Created by $executinguser using dbatools $commandname for objects on $servername at $(Get-Date)
	See https://dbatools.io/$commandname for more information
*/"
			
			if (!$Append -and !$Passthru) {
				if (Test-Path -Path $actualpath) {
					Stop-Function -Message "OutputFile $actualpath already exists and Append was not specified." -Target $actualpath -Continue
				}
			}
			
			if ($passthru) {
				$prefix | Out-String
			}
			else {
				Write-Message -Level Output -Message "Exporting objects on $servername to $actualpath"
				$prefix | Out-File -FilePath $actualpath -Encoding $encoding -Append
			}
			
			foreach ($export in $exports) {
				If ($Pscmdlet.ShouldProcess($env:computername, "Exporting $export from $server to $actualpath")) {
					Write-Message -Level Verbose -Message "Exporting $export"
					
					if ($passthru) {
						$export.Script($ScriptingOptionsObject) | Out-String
					}
					else {
						$export.Script($ScriptingOptionsObject) | Out-File -FilePath $actualpath -Encoding $encoding -Append
					}
				}
			}
			
			if (!$passthru) {
				Write-Message -Level Output -Message "Completed export for $server"
			}
		}
	}
}