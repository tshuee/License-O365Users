<#
	.SYNOPSIS
	 Updates Office 365 licenses of users from a CSV file
	.DESCRIPTION
	 THIS SCRIPT REQUIRES POWERSHELL VERSION 5 TO RUN (https://www.microsoft.com/en-us/download/details.aspx?id=50395). This script will set or update the Office 365 
	 UsageLocation and licenses assigned to the users in the specified CSV file. If the CSV does not already exist, the script can create it with the current set of 
	 licenses using the GenerateCSVFile parameter. To add a feature of a license to a user, put a 1 in the field. To add all features of a license to a user, put a 1 
	 in all fields for the license. To remove a feature of a license from a user, put a 0 in the field. To remove all features of a license from a user, put a 0 in all 
	 fields for the license. To not modify a feature, license or UsageLocation for a user, leave the field blank.
	.EXAMPLE
	 .\License-O365Users.ps1 -GenerateCSVFile
	 Runs the script to generate the LicenseInfo.csv file containing the required headers and licenses from the currently logged in Office 365 subscription
	.EXAMPLE
	 .\License-O365Users.ps1
	 Runs the script using the default CSV file .\LicenseInfo.csv
	.NOTES
	 Created by Andy Meyers, Anexinet
	 Created on 11/03/2016
	 Version 1.0
	 REQUIRES POWERSHELL VERSION 5
	 https://www.microsoft.com/en-us/download/details.aspx?id=50395
	 - Initial version
	 Version 1.1
	 - 12/09/2016
	 - Prioritized changes to process removes first
	 - Added PendingProvisioning state to indicate Plan is enabled
	 Version 1.2
	 - 01/13/2017
	 - Fixed wrong variable used to add features causing error
	 - Added PS version check
#>

[CmdletBinding()]
Param(
 [Parameter(Mandatory=$False,Position=1)]
   [String]$LicenseFilePath = "$($PSScriptRoot)\LicenseInfo.csv",
 [Parameter(Mandatory=$False,Position=2)]
   [Switch]$GenerateCSVFile
)

# Region Log files and Setup
# Create log files
$Global:LogFilePath = "C:\temp\License-O365Users_$(Get-date -f yyyy-MM-dd-HH-mm-ss).log"
Add-Content $Global:LogFilePath -Value ("$(get-date -f s) Log File Started")
$Global:old_ErrorActionPreference = $ErrorActionPreference
$ErrorActionPreference = "Stop"

# EndRegion Log files and Setup
#################################################################################################################
# Define Functions
#################################################################################################################
# Region Functions

Function Check-PSVersion
{
	Try
	{
		Add-Content $Global:LogFilePath -Value ("$(Get-Date -f s) Checking PowerShell version") -PassThru | Write-Host
		If ($PSVersionTable.PSVersion.Major -lt 5)
		{
			Add-Content $Global:LogFilePath -Value ("$(Get-Date -f s) This script requires at least PowerShell V5. You are on V$($PSVersionTable.PSVersion.Major). Please install PowerShell V5 from https://www.microsoft.com/en-us/download/details.aspx?id=50395. Exiting") -PassThru | Write-Host -ForegroundColor Red
			End-Script
		}
	}
	Catch
	{
		Add-Content $Global:LogFilePath -Value ("$(Get-Date -f s) Error encountered checking PowerShell version. Exiting: $_") -PassThru | Write-Host -ForegroundColor Red
		End-Script
	}

}

Function Test-MsolConnection
{
	Try
	{
		Add-Content $Global:LogFilePath -Value ("$(Get-Date -f s) Checking connectivity to Office 365") -PassThru | Write-Host
		Get-MsolAccountSku -ErrorAction Stop | Out-Null
	}
	Catch
	{
		If ($_.Exception.Message -eq "You must call the Connect-MsolService cmdlet before calling any other cmdlets.")
			{Make-MsolConnection}
		Else
		{
			Add-Content $Global:LogFilePath -Value ("$(Get-Date -f s) Error checking connectivity to Office 365. Exiting: $_") -PassThru | Write-Host -ForegroundColor Red
			End-Script
		}
	}
}

Function Make-MsolConnection
{
	Try
	{
		Add-Content $Global:LogFilePath -Value ("$(Get-Date -f s) Connecting to Office 365") -PassThru | Write-Host
		Connect-MsolService -Credential (Get-Credential) -ErrorAction Stop
	}
	Catch
	{
		Add-Content $Global:LogFilePath -Value ("$(Get-Date -f s) Error connecting to Office 365. Exiting: $_") -PassThru | Write-Host -ForegroundColor Red
		End-Script
	}
}

Function Generate-CSVFile
{
	Try
	{
		Add-Content $Global:LogFilePath -Value ("$(Get-Date -f s) Generating CSV file with all license SKUs from Office 365") -PassThru | Write-Host
		"UserPrincipalName,UsageLocation,"+((Get-MsolAccountSku | Select SkuPartNumber -ExpandProperty ServiceStatus | Select SkuPartNumber -ExpandProperty ServicePlan | % {"$($_.SkuPartNumber):$($_.ServiceName)"}) -Join ",") | Out-File "$($PSScriptRoot)\LicenseInfo.csv" -Encoding ASCII -NoClobber
		Add-Content $Global:LogFilePath -Value ("$(Get-Date -f s) Succesfully generated CSV file ""$($PSScriptRoot)\LicenseInfo.csv"" with all license SKUs from Office 365. Please fill out the CSV and rerun the script") -PassThru | Write-Host
		End-Script
	}
	Catch
	{
		Add-Content $Global:LogFilePath -Value ("$(Get-Date -f s) Error generating CSV file with all license SKUs from Office 365 subscription. Exiting: $_") -PassThru | Write-Host -ForegroundColor Red
		End-Script
	}
}

Function End-Script
{
	Add-Content $Global:LogFilePath -Value ("$(Get-Date -f s) Script complete. Exiting") -PassThru | Write-Host -ForegroundColor Green

	$ErrorActionPreference = $Global:old_ErrorActionPreference
	Exit
}

# EndRegion Functions
#################################################################################################################
# Begin Script
#################################################################################################################

# Verify at least PowerShell V5
Check-PSVersion

# Verify connection to Office 365
Test-MsolConnection

# If switch passed to generate the CSV file
If ($GenerateCSVFile)
	{Generate-CSVFile}

# Import the input file
Try
{
	Add-Content $Global:LogFilePath -Value ("$(Get-Date -f s) Reading input file") -PassThru | Write-Host
	$Data = Import-Csv $LicenseFilePath
}
Catch
{
	Add-Content $Global:LogFilePath -Value ("$(Get-Date -f s) Error reading input file. Exiting: $_") -PassThru | Write-Host -ForegroundColor Red
	End-Script
}

Try
{
	Add-Content $Global:LogFilePath -Value ("$(Get-Date -f s) Verifying headers of input file") -PassThru | Write-Host
	$Headers = ($Data | Get-Member -MemberType NoteProperty | select Name | % {$_.Name.Split(":")[0]} | Select-Object -Unique)
	$Licenses = (Get-MsolAccountSku).AccountSkuId
	$CompanyPrefix = ($Licenses | % {$_.Split(":")[0]} | Select-Object -Unique)
	If (-not ($Headers.Contains("UserPrincipalName")))
	{
		Add-Content $Global:LogFilePath -Value ("$(Get-Date -f s) Input file does not have a ""UserPrincipalName"" header. Run "".\License-O365Users -GenerateCSVFile"" to create one with the required headers. Exiting") -PassThru | Write-Host -ForegroundColor Red
		End-Script
	}
	If (-not ($Headers.Contains("UsageLocation")))
	{
		Add-Content $Global:LogFilePath -Value ("$(Get-Date -f s) Input file does not have a ""UsageLocation"" header. Run "".\License-O365Users -GenerateCSVFile"" to create one with the required headers. Exiting") -PassThru | Write-Host -ForegroundColor Red
		End-Script
	}
	If ((Compare-Object ($Headers | ? {($_ -notmatch "UserPrincipalName") -and ($_ -notmatch "UsageLocation")}) ($Licenses | % {$_.Split(":")[1]})) -ne $null)
	{
		Add-Content $Global:LogFilePath -Value ("$(Get-Date -f s) Input file header licenses do not match licenses in tenant. Run "".\License-O365Users -GenerateCSVFile"" to create one with the required headers. Exiting") -PassThru | Write-Host -ForegroundColor Red
		End-Script
	}
}
Catch
{
	Add-Content $Global:LogFilePath -Value ("$(Get-Date -f s) Error verifying headers of input file. Exiting: $_") -PassThru | Write-Host -ForegroundColor Red
	End-Script
}

ForEach ($User in $Data)
{
	$LicensesFromFile = ($User | Get-Member -MemberType NoteProperty | select Definition).Definition.Replace("string ","")
	$UserLicensesTable = @()
	
	# Create a table of the current user's desired license settings
	ForEach ($LicenseFromFile in ($LicensesFromFile | ? {$_ -notmatch "INTUNE_O365"}))
	{
		$Info = New-Object PSObject
		$Info | Add-Member -MemberType NoteProperty -Name "License" -Value ($LicenseFromFile | % {$_.Substring(0,($_.IndexOf("=")))})
		$Info | Add-Member -MemberType NoteProperty -Name "NeededValue" -Value ($LicenseFromFile | % {$_.Substring(($_.IndexOf("=")+1))})
		$Info | Add-Member -MemberType NoteProperty -Name "CurrentValue" -Value 0
		$Info | Add-Member -MemberType NoteProperty -Name "FinalValue" -Value ""
		$UserLicensesTable += $Info
	}
	
	# Get the current user's licensing info from Office 365
	$MsolUser = $null
	Try
	{
		Add-Content $Global:LogFilePath -Value ("$(Get-Date -f s) Finding user in Office 365 with UPN $($User.UserPrincipalName)") -PassThru | Write-Host
		$MsolUser = Get-MsolUser -UserPrincipalName $User.UserPrincipalName -ErrorAction Stop
	}
	Catch
		{Add-Content $Global:LogFilePath -Value ("$(Get-Date -f s) Error finding user in Office 365 with UPN $($User.UserPrincipalName): $_") -PassThru | Write-Host -ForegroundColor Red}

	If ($MsolUser)
	{
		# Set UsageLocation if specified
		If (($User.UsageLocation) -and ($User.UsageLocation -ne $MsolUser.UsageLocation))
		{
			Try
			{
				Add-Content $Global:LogFilePath -Value ("$(Get-Date -f s) Changing $($User.UserPrincipalName) UsageLocation from ""$($MsolUser.UsageLocation)"" to ""$($User.UsageLocation)""") -PassThru | Write-Host
				Set-MsolUser -UserPrincipalName $User.UserPrincipalName -UsageLocation $User.UsageLocation
			}
			Catch
			{Add-Content $Global:LogFilePath -Value ("$(Get-Date -f s) Error changing $($User.UserPrincipalName) UsageLocation from ""$($MsolUser.UsageLocation)"" to ""$($User.UsageLocation)"": $_") -PassThru | Write-Host -ForegroundColor Red}
		}
		# Loop through all the assigned licenses
		ForEach ($License in $MsolUser.Licenses)
		{
			$Processing = $UserLicensesTable | ? {$_.License.Split(":")[0] -eq ($License.AccountSkuId.Split(":")[1])}
			If ($Processing -ne $null)
			{
				# Loop through all of the license services, and set Current Value to 1 if they are enabled
				ForEach ($ServicePlan in ($License.ServiceStatus | ? {$_.ServicePlan.ServiceName -notmatch "INTUNE_O365"}))
				{
					If (($ServicePlan.ProvisioningStatus -eq "Success") -or ($ServicePlan.ProvisioningStatus -eq "PendingActivation") -or ($ServicePlan.ProvisioningStatus -eq "PendingInput") -or ($ServicePlan.ProvisioningStatus -eq "PendingProvisioning"))
						{($UserLicensesTable | ? {($_.License.Split(":")[0] -eq ($License.AccountSkuId.Split(":")[1])) -and ($_.License.Split(":")[1] -eq ($ServicePlan.ServicePlan.ServiceName.Split(":")[0]))}).CurrentValue = 1}
				}
			}
			Remove-Variable Processing
		}
		
		# Group all of the licenses by Account SKU and work on each one individually
		$AccountSkus = $UserLicensesTable | Group-Object {$_.License.Split(":")[0]} | ? {($_.Name -ne "UserPrincipalName") -and ($_.Name -ne "UsageLocation")}
		$AllEnabled = @()
		$FinalDisabledPlans = @()
		$CurrentDisabledPlans = ($AccountSkus.Group | ? {$_.CurrentValue -eq 0}).License
		$NewDisabledPlans = @()
		$NewEnabledPlans = @()
		ForEach ($AccountSku in $AccountSkus)
		{
			ForEach ($Item in $AccountSku.Group)
			{	
				If ($Item.NeededValue -eq 1)
					{$Item.FinalValue = 1}
				ElseIf ($Item.NeededValue -eq 0)
					{$Item.FinalValue = 0}
				Else
					{$Item.FinalValue = $Item.CurrentValue}
			}
			$FinalValueStats = $AccountSku.Group.FinalValue | Measure-Object -Sum
			$ChangesNeeded = @()
			$ChangesNeeded = $AccountSku.Group | ? {$_.CurrentValue -ne $_.FinalValue}
			If (($FinalValueStats.Count -eq $FinalValueStats.Sum) -and (($AccountSku.Group.CurrentValue | Measure-Object -Sum).Sum -eq 0))
			{
				# All features need enabled, none currently are
				$AllEnabled += $AccountSku.Name
			}		
			ElseIf (($FinalValueStats.Sum -eq 0) -and (($AccountSku.Group.CurrentValue | Measure-Object -Sum).Sum -gt 0))
			{
				# All features need disabled, at least one currently is, always process removes first
				Try
				{
					Add-Content $Global:LogFilePath -Value ("$(Get-Date -f s) Removing all features of $($AccountSku.Name) to $($User.UserPrincipalName)") -PassThru | Write-Host
					Set-MsolUserLicense -UserPrincipalName $User.UserPrincipalName -RemoveLicenses "$($CompanyPrefix):$($AccountSku.Name)" -ErrorAction Stop
				}
				Catch
					{Add-Content $Global:LogFilePath -Value ("$(Get-Date -f s) Error removing all features of $($AccountSku.Name) to $($User.UserPrincipalName): $_") -PassThru | Write-Host -ForegroundColor Red}
			}
			ElseIf (@($ChangesNeeded).Count -gt 0)
			{
				ForEach ($DisablePlan in ($AccountSku.Group | ? {$_.FinalValue -eq 0}))
					{$FinalDisabledPlans += $DisablePlan.License}
				ForEach ($ChangeNeeded in $ChangesNeeded)
				{
					If (($ChangeNeeded.NeededValue -eq 0) -and ($ChangeNeeded.CurrentValue -eq 1))
						{$NewDisabledPlans += $ChangeNeeded.License}
					ElseIf (($ChangeNeeded.NeededValue -eq 1) -and ($ChangeNeeded.CurrentValue -eq 0))
						{$NewEnabledPlans += $ChangeNeeded.License}
				}
			}
		}

		# Process features to be newly disabled first
		ForEach ($NewDisabledPlan in ($NewDisabledPlans | Group-Object {$_.Split(":")[0]}))
		{
			$Disable = @()
			ForEach ($DisablePlanName in $NewDisabledPlan.Group)
			{
				Add-Content $Global:LogFilePath -Value ("$(Get-Date -f s) Disabling feature $($DisablePlanName.Split(":")[1]) in $($DisablePlanName.Split(":")[0]) for $($User.UserPrincipalName)") -PassThru | Write-Host
				$Disable += $DisablePlanName.Split(":")[1]
			}
			ForEach ($DisablePlanName in ($CurrentDisabledPlans | ? {$_ -match $NewDisabledPlan.Group.Split(":")[0]}))
				{$Disable += $DisablePlanName.Split(":")[1]}
			Try
			{
				$SkuOptions = New-MsolLicenseOptions -AccountSkuId "$($CompanyPrefix):$($NewDisabledPlan.Name)" -DisabledPlans $Disable
				Set-MsolUserLicense -UserPrincipalName $User.UserPrincipalName -LicenseOptions $SkuOptions -ErrorAction Stop
			}
			Catch
				{Add-Content $Global:LogFilePath -Value ("$(Get-Date -f s) Error disabling feature(s) in $($NewDisabledPlan.Name) for $($User.UserPrincipalName): $_") -PassThru | Write-Host -ForegroundColor Red}
		}

		# Process features to be newly added second
		ForEach ($NewEnabledPlan in ($NewEnabledPlans | Group-Object {$_.Split(":")[0]}))
		{
			ForEach ($EnablePlanName in $NewEnabledPlan.Group)
				{Add-Content $Global:LogFilePath -Value ("$(Get-Date -f s) Enabling feature $($EnablePlanName.Split(":")[1]) in $($EnablePlanName.Split(":")[0]) for $($User.UserPrincipalName)") -PassThru | Write-Host}
			$Disable = @()
			Try
			{
				$Disable += $FinalDisabledPlans | ? {$_.Split(":") -eq $NewEnabledPlan.Name} | % {$_.Split(":")[1]}
				$SkuOptions = New-MsolLicenseOptions -AccountSkuId "$($CompanyPrefix):$($NewEnabledPlan.Name)" -DisabledPlans $Disable
				If ((($UserLicensesTable | ? {$_.License.Split(":")[0] -eq $NewEnabledPlan.Name}).CurrentValue | Measure-Object -Sum).Sum -eq 0)
					{Set-MsolUserLicense -UserPrincipalName $User.UserPrincipalName -AddLicenses "$($CompanyPrefix):$($NewEnabledPlan.Name)" -LicenseOptions $SkuOptions -ErrorAction Stop}
				Else
					{Set-MsolUserLicense -UserPrincipalName $User.UserPrincipalName -LicenseOptions $SkuOptions -ErrorAction Stop}
			}
			Catch
				{Add-Content $Global:LogFilePath -Value ("$(Get-Date -f s) Error enabling feature(s) in $($NewEnabledPlan.Name) for $($User.UserPrincipalName): $_") -PassThru | Write-Host -ForegroundColor Red}
		}

		# Finally, process entire licenses that need to be enabled
		ForEach ($AllEnable in $AllEnabled)
		{
			Try
			{
				Add-Content $Global:LogFilePath -Value ("$(Get-Date -f s) Adding all features of $($AllEnable) to $($User.UserPrincipalName)") -PassThru | Write-Host
				Set-MsolUserLicense -UserPrincipalName $User.UserPrincipalName -AddLicenses "$($CompanyPrefix):$($AllEnable)" -ErrorAction Stop
			}
			Catch
				{Add-Content $Global:LogFilePath -Value ("$(Get-Date -f s) Error adding all features of $($AllEnable) to $($User.UserPrincipalName): $_") -PassThru | Write-Host -ForegroundColor Red}
		}
	}
}

End-Script

# EndRegion Main Script
#################################################################################################################
# End Script
#################################################################################################################
