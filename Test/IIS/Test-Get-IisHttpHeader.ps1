
$siteName = 'CarbonGetIisHttpHeader'
$sitePort = 47939

function Setup()
{
    & (Join-Path $TestDir ..\..\Carbon\Import-Carbon.ps1 -Resolve)
    Install-IisWebsite -Name $siteName -Path $TestDir -Binding ('http/*:{0}:*' -f $sitePort)
}

function Remove()
{
    Remove-IisWebsite -Name $siteName
    Remove-Module Carbon
}



function Test-ShouldAllowSearchingByWildcard
{
    $name = 'X-Carbon-GetIisHttpRedirect'
    $value = [Guid]::NewGuid()
    Set-IisHttpHeader -SiteName $siteName -Name $name -Value $value
    
    ($name, 'X-Carbon*' ) | ForEach-Object {
        $header = Get-IisHttpHeader -SiteName $siteName -Name $_
        Assert-NotNull $header
        Assert-Equal $name $header.Name
        Assert-Equal $value $header.Value
    }
    
    $header = Get-IisHttpHeader -SiteName $siteName -Name 'blah*'
    Assert-Null $header
}
