<#
.SYNOPSIS
    Creates new domain users from a CSV file and adds them to their department group.
.DESCRIPTION
    Reads users.csv (FirstName, LastName, Username, Department, Title).
    For each row it creates the user in OU=<Department>,OU=_LAB, sets a temporary
    password the user must change at first logon, and adds them to SG-<Department>.
    Creates the department security groups in OU=Groups if they don't exist yet.
    Skips users that already exist and writes a log of every action.
.EXAMPLE
    .\New-UserOnboarding.ps1
    .\New-UserOnboarding.ps1 -CsvPath C:\LabScripts\newhires.csv
#>
param(
    [string]$CsvPath = "C:\LabScripts\users.csv",
    [string]$LogPath = "C:\LabScripts\onboarding-log.csv"
)

Import-Module ActiveDirectory

$domainDN = (Get-ADDomain).DistinguishedName
$domain   = (Get-ADDomain).DNSRoot
$labOU    = "OU=_LAB,$domainDN"
$groupsOU = "OU=Groups,$labOU"

if (-not (Test-Path $CsvPath)) {
    Write-Host "CSV not found: $CsvPath" -ForegroundColor Red
    return
}

$users = Import-Csv $CsvPath

# Ask for the temporary password instead of saving it in the script
$tempPassword = Read-Host "Enter a temporary password for the new users" -AsSecureString

$log = @()

# 1. Make sure each department has a security group
foreach ($dept in ($users.Department | Sort-Object -Unique)) {
    $groupName = "SG-$dept"
    if (-not (Get-ADGroup -Filter "Name -eq '$groupName'")) {
        New-ADGroup -Name $groupName -GroupScope Global -GroupCategory Security `
            -Path $groupsOU -Description "$dept department staff"
        Write-Host "Created group $groupName" -ForegroundColor Cyan
    }
}

# 2. Create each user
foreach ($u in $users) {
    $sam = $u.Username.Trim()
    $ou  = "OU=$($u.Department),$labOU"

    if (Get-ADUser -Filter "SamAccountName -eq '$sam'") {
        Write-Host "Skipped $sam (already exists)" -ForegroundColor Yellow
        $log += [pscustomobject]@{ Time = Get-Date; User = $sam; Result = "Skipped - already exists" }
        continue
    }

    try {
        New-ADUser -Name "$($u.FirstName) $($u.LastName)" `
            -GivenName $u.FirstName -Surname $u.LastName `
            -SamAccountName $sam -UserPrincipalName "$sam@$domain" `
            -DisplayName "$($u.FirstName) $($u.LastName)" `
            -Title $u.Title -Department $u.Department `
            -Path $ou -AccountPassword $tempPassword `
            -ChangePasswordAtLogon $true -Enabled $true -ErrorAction Stop

        Add-ADGroupMember -Identity "SG-$($u.Department)" -Members $sam -ErrorAction Stop

        Write-Host "Created $sam in $($u.Department)" -ForegroundColor Green
        $log += [pscustomobject]@{ Time = Get-Date; User = $sam; Result = "Created in $($u.Department), added to SG-$($u.Department)" }
    }
    catch {
        Write-Host "Failed $sam : $($_.Exception.Message)" -ForegroundColor Red
        $log += [pscustomobject]@{ Time = Get-Date; User = $sam; Result = "Failed - $($_.Exception.Message)" }
    }
}

$log | Export-Csv $LogPath -NoTypeInformation -Append
Write-Host "`nDone. Log saved to $LogPath"