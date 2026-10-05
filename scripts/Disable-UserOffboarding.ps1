<#
.SYNOPSIS
    Offboards a departing user: records and removes group memberships, disables the
    account, scrambles the password, stamps the description, and moves it to the
    Terminated OU.
.EXAMPLE
    .\Disable-UserOffboarding.ps1 -Username jreed -Ticket "OFF-001"
#>
param(
    [Parameter(Mandatory)] [string]$Username,
    [string]$Ticket = "N/A",
    [string]$LogPath = "C:\LabScripts\offboarding-log.csv"
)

Import-Module ActiveDirectory

$domainDN     = (Get-ADDomain).DistinguishedName
$terminatedOU = "OU=Terminated,OU=_LAB,$domainDN"

$user = Get-ADUser -Filter "SamAccountName -eq '$Username'" -Properties MemberOf
if (-not $user) {
    Write-Host "User $Username not found." -ForegroundColor Red
    return
}

# 1. Record group memberships before removing them (for the ticket, audits, or a rehire)
$groups = $user.MemberOf | ForEach-Object { (Get-ADGroup $_).Name }
Write-Host "Current groups: $($groups -join ', ')" -ForegroundColor Cyan

# 2. Disable the account
Disable-ADAccount -Identity $user
Write-Host "Disabled $Username" -ForegroundColor Green

# 3. Replace the password with a random one so the old password can never be reused
$random = (-join ((33..126) | Get-Random -Count 24 | ForEach-Object { [char]$_ })) + "Aa1!"
Set-ADAccountPassword -Identity $user -Reset -NewPassword (ConvertTo-SecureString $random -AsPlainText -Force)
Write-Host "Password scrambled" -ForegroundColor Green

# 4. Remove from every group except Domain Users (the primary group can't be removed)
foreach ($dn in $user.MemberOf) {
    Remove-ADGroupMember -Identity $dn -Members $user -Confirm:$false
}
Write-Host "Removed from: $($groups -join ', ')" -ForegroundColor Green

# 5. Stamp the description so the next admin knows what happened
$date = Get-Date -Format "yyyy-MM-dd"
Set-ADUser -Identity $user -Description "Disabled $date - Ticket $Ticket - Groups removed: $($groups -join ', ')"
Write-Host "Description updated" -ForegroundColor Green

# 6. Move to the Terminated OU
Move-ADObject -Identity $user.DistinguishedName -TargetPath $terminatedOU
Write-Host "Moved to Terminated OU" -ForegroundColor Green

[pscustomobject]@{
    Time = Get-Date; User = $Username; Ticket = $Ticket
    GroupsRemoved = ($groups -join '; '); Result = "Offboarded"
} | Export-Csv $LogPath -NoTypeInformation -Append

Write-Host "`nDone. Log saved to $LogPath"