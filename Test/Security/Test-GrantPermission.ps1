# Copyright 2012 Aaron Jensen
# 
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
# 
#     http://www.apache.org/licenses/LICENSE-2.0
# 
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

$Path = $null
$user = 'CarbonGrantPerms'
$containerPath = $null

function Start-Test
{
    & (Join-Path $TestDir ..\..\Carbon\Import-Carbon.ps1 -Resolve)
    
    Install-User -Username $user -Password 'a1b2c3d4!' -Description 'User for Carbon Grant-Permission tests.'
    
    $containerPath = New-TempDir -Prefix 'Carbon_Test-GrantPermisssion'
    $Path = Join-Path -Path $containerPath -ChildPath ([IO.Path]::GetRandomFileName())
    $null = New-Item -ItemType 'File' -Path $Path
}

function Stop-Test
{
    if( Test-Path $containerPath )
    {
        Remove-Item $containerPath -Recurse
    }
    
    Remove-Module Carbon
}

function Invoke-GrantPermissions($Identity, $Permissions, $Path)
{
    $result = Grant-Permission -Identity $Identity -Permission $Permissions -Path $Path.ToString()
    Assert-NotNull $result
    Assert-Equal $Identity $result.IdentityReference
    Assert-Is $result ([Security.AccessControl.FileSystemAccessRule])
}

function Test-ShouldGrantPermissionOnFile
{
    $identity = 'BUILTIN\Administrators'
    $permissions = 'Read','Write'
    
    Invoke-GrantPermissions -Identity $identity -Permissions $permissions -Path $Path
    Assert-Permissions $identity $permissions
}

function Test-ShouldGrantPermissionOnDirectory
{
    $identity = 'BUILTIN\Administrators'
    $permissions = 'Read','Write'
    
    Invoke-GrantPermissions -Identity $identity -Permissions $permissions -Path $containerPath
    Assert-Permissions $identity $permissions -path $containerPath
}

function Test-ShouldGrantPermissionsOnRegistryKey
{
    $regKey = 'hkcu:\TestGrantPermissions'
    New-Item $regKey
    
    try
    {
        $result = Grant-Permission -Identity 'BUILTIN\Administrators' -Permission 'ReadKey' -Path $regKey
        Assert-NotNull $result
        Assert-Is $result ([Security.AccessControl.RegistryAccessRule]) 
        Assert-Equal $regKey $result.Path
        Assert-Permissions 'BUILTIN\Administrators' -Permissions 'ReadKey' -Path $regKey
    }
    finally
    {
        Remove-Item $regKey
    }
}

function Test-ShouldFailIfIncorrectPermissions
{
    $failed = $false
    $error.Clear()
    $result = Grant-Permission -Identity 'BUILTIN\Administrators' -Permission 'BlahBlahBlah' -Path $Path.ToString() -ErrorAction SilentlyContinue
    Assert-Null $result
    Assert-Equal 2 $error.Count
}

function Test-ShouldClearExistingPermissions
{
    Invoke-GrantPermissions 'Administrators' 'FullControl' -Path $Path
    
    $result = Grant-Permission -Identity 'Everyone' -Permission 'Read','Write' -Path $Path.ToString() -Clear
    Assert-NotNull $result
    Assert-Equal $Path $result.Path
    
    $acl = Get-Acl -Path $Path.ToString()
    
    $rules = $acl.Access |
                Where-Object { -not $_.IsInherited }
    Assert-NotNull $rules
    Assert-Equal 'Everyone' $rules.IdentityReference.Value
}

function Test-ShouldHandleNoPermissionsToClear
{
    $acl = Get-Acl -Path $Path.ToSTring()
    $rules = $acl.Access | 
                Where-Object { -not $_.IsInherited }
    if( $rules )
    {
        $rules |
            ForEach-Object { $acl.REmoveAccessRule( $rule ) }
        Set-Acl -Path $Path.ToString() -AclObject $acl
    }
    
    $error.Clear()
    $result = Grant-Permission -Identity 'Everyone' -Permission 'Read','Write' -Path $Path.ToSTring() -Clear -ErrorAction SilentlyContinue
    Assert-NotNull $result
    Assert-Equal 'Everyone' $result.IdentityReference
    Assert-Equal 0 $error.Count
    $acl = Get-Acl -Path $Path.ToString()
    $rules = $acl.Access | Where-Object { -not $_.IsInherited }
    Assert-NotNull $rules
    Assert-Like $rules.IdentityReference.Value 'Everyone'
}

function Test-ShouldSetInheritanceFlags
{
    function New-FlagsObject
    {
        param(
            [Security.AccessControl.InheritanceFlags]
            $InheritanceFlags,
            
            [Security.AccessControl.PropagationFlags]
            $PropagationFlags
        )
       
        New-Object PsObject -Property @{ 'InheritanceFlags' = $InheritanceFlags; 'PropagationFlags' = $PropagationFlags }
    }
    
    $IFlags = [Security.AccessControl.InheritanceFlags]
    $PFlags = [Security.AccessControl.PropagationFlags]
    $map = @{
        # ContainerInheritanceFlags                                    InheritanceFlags                     PropagationFlags
        'Container' =                                 (New-FlagsObject $IFlags::None                               $PFlags::None)
        'ContainerAndSubContainers' =                 (New-FlagsObject $IFlags::ContainerInherit                   $PFlags::None)
        'ContainerAndLeaves' =                        (New-FlagsObject $IFlags::ObjectInherit                      $PFlags::None)
        'SubContainersAndLeaves' =                    (New-FlagsObject ($IFlags::ContainerInherit -bor $IFlags::ObjectInherit)   $PFlags::InheritOnly)
        'ContainerAndChildContainers' =               (New-FlagsObject $IFlags::ContainerInherit                   $PFlags::NoPropagateInherit)
        'ContainerAndChildLeaves' =                   (New-FlagsObject $IFlags::ObjectInherit                      $PFlags::NoPropagateInherit)
        'ContainerAndChildContainersAndChildLeaves' = (New-FlagsObject ($IFlags::ContainerInherit -bor $IFlags::ObjectInherit)   $PFlags::NoPropagateInherit)
        'ContainerAndSubContainersAndLeaves' =        (New-FlagsObject ($IFlags::ContainerInherit -bor $IFlags::ObjectInherit)   $PFlags::None)
        'SubContainers' =                             (New-FlagsObject $IFlags::ContainerInherit                   $PFlags::InheritOnly)
        'Leaves' =                                    (New-FlagsObject $IFlags::ObjectInherit                      $PFlags::InheritOnly)
        'ChildContainers' =                           (New-FlagsObject $IFlags::ContainerInherit                   ($PFlags::InheritOnly -bor $PFlags::NoPropagateInherit))
        'ChildLeaves' =                               (New-FlagsObject $IFlags::ObjectInherit                      ($PFlags::InheritOnly -bor $PFlags::NoPropagateInherit))
        'ChildContainersAndChildLeaves' =             (New-FlagsObject ($IFlags::ContainerInherit -bor $IFlags::ObjectInherit)   ($PFlags::InheritOnly -bor $PFlags::NoPropagateInherit))
    }

    if( (Test-Path -Path $containerPath -PathType Container) )
    {
        Remove-Item -Recurse -Path $containerPath
    }
    
    $map.Keys |
        ForEach-Object {
            try
            {
                $containerInheritanceFlag = $_
                $containerPath = 'Carbon-Test-GrantPermissions-{0}-{1}' -f ($containerInheritanceFlag,[IO.Path]::GetRandomFileName())
                $containerPath = Join-Path $env:Temp $containerPath
                
                $null = New-Item $containerPath -ItemType Directory
                
                $childLeafPath = Join-Path $containerPath 'ChildLeaf'
                $null = New-Item $childLeafPath -ItemType File
                
                $childContainerPath = Join-Path $containerPath 'ChildContainer'
                $null = New-Item $childContainerPath -ItemType Directory
                
                $grandchildContainerPath = Join-Path $childContainerPath 'GrandchildContainer'
                $null = New-Item $grandchildContainerPath -ItemType Directory
                
                $grandchildLeafPath = Join-Path $childContainerPath 'GrandchildLeaf'
                $null = New-Item $grandchildLeafPath -ItemType File

                $flags = $map[$containerInheritanceFlag]
                #Write-Host ('{0}: {1}     {2}' -f $_,$flags.InheritanceFlags,$flags.PropagationFlags)
                $result = Grant-Permission -Identity $user -Path $containerPath -Permission Read -ApplyTo $containerInheritanceFlag
                Assert-NotNull $result
                Assert-Equal $containerPath $result.Path
                Assert-InheritanceFlags $containerInheritanceFlag $flags.InheritanceFlags $flags.PropagationFlags
            }
            finally
            {
                Remove-Item $containerPath -Recurse
            }                
        }
}

function Test-ShouldWriteWarningWhenInheritanceFlagsGivenOnLeaf
{
    $result = Grant-Permission -Identity $user -Permission Read -Path $Path -ApplyTo Container
    Assert-NotNull $result
    Assert-Equal $Path $result.Path
}

function Test-ShouldChangePermissions
{
    $rule = Grant-Permission -Identity $user -Permission FullControl -Path $containerPath -ApplyTo Container
    Assert-NotNull $rule
    Assert-True (Test-Permission -Identity $user -Permission FullControl -Path $containerPath -ApplyTo Container -Exact)
    $rule = Grant-Permission -Identity $user -Permission Read -Path $containerPath -Apply Container
    Assert-NotNull $rule
    Assert-True (Test-Permission -Identity $user -Permission Read -Path $containerPath -ApplyTo Container -Exact)
}

function Test-ShouldNotReapplyPermissionsAlreadyGranted
{
    $rule = Grant-Permission -Identity $user -Permission FullControl -Path $containerPath
    Assert-NotNull $rule
    Assert-True (Test-Permission -Identity $user -Permission FullControl -Path $containerPath -Exact)
    $rule = Grant-Permission -Identity $user -Permission FullControl -Path $containerPath
    Assert-Null $rule
    Assert-True (Test-Permission -Identity $user -Permission FullControl -Path $containerPath -Exact)
}

function Test-ShouldChangeInheritanceFlags
{
    Grant-Permission -Identity $user -Permission FullControl -Path $containerPath -ApplyTo ContainerAndLeaves
    Assert-True (Test-Permission -Identity $user -Permission FullControl -Path $containerPath -ApplyTo ContainerAndLeaves -Exact)
    Grant-Permission -Identity $user -Permission Read -Path $containerPath -Apply Container
    Assert-True (Test-Permission -Identity $user -Permission Read -Path $containerPath -ApplyTo Container -Exact)
}


function Test-ShouldReapplySamePermissions
{
    Grant-Permission -Identity $user -Permission FullControl -Path $containerPath -ApplyTo ContainerAndLeaves
    Assert-True (Test-Permission -Identity $user -Permission FullControl -Path $containerPath -ApplyTo ContainerAndLeaves -Exact)
    Grant-Permission -Identity $user -Permission FullControl -Path $containerPath -Apply ContainerAndLeaves -Force
    Assert-True (Test-Permission -Identity $user -Permission FullControl -Path $containerPath -ApplyTo ContainerAndLeaves -Exact)
}

function Assert-InheritanceFlags
{
    param(
        [string]
        $ContainerInheritanceFlags,
        
        [Security.AccessControl.InheritanceFlags]
        $InheritanceFlags,
        
        [Security.AccessControl.PropagationFlags]
        $PropagationFlags
    )

    #Write-Host ('{0}: {1}     {2}' -f $ContainerInheritanceFlags,$InheritanceFlags,$PropagationFlags)
    $ace = Get-Permission $containerPath -Identity $user
                
    Assert-NotNull $ace $ContainerInheritanceFlags
    $expectedRights = [Security.AccessControl.FileSystemRights]::Read -bor [Security.AccessControl.FileSystemRights]::Synchronize
    Assert-Equal $expectedRights $ace.FileSystemRights ('{0} file system rights' -f $ContainerInheritanceFlags)
    Assert-Equal $InheritanceFlags $ace.InheritanceFlags ('{0} inheritance flags' -f $ContainerInheritanceFlags)
    Assert-Equal $PropagationFlags $ace.PropagationFlags ('{0} propagation flags' -f $ContainerInheritanceFlags)
}

function Assert-Permissions($identity, $permissions, $path = $Path)
{
    $providerName = (Get-PSDrive (Split-Path -Qualifier (Resolve-Path $path)).Trim(':')).Provider.Name
    
    $rights = 0
    foreach( $permission in $permissions )
    {
        $rights = $rights -bor ($permission -as "Security.AccessControl.$($providerName)Rights")
    }
    
    $ace = Get-Permission -Path $path -Identity $identity
    Assert-NotNull $ace "Didn't get access control rule for $path."
    
    $expectedInheritanceFlags = [Security.AccessControl.InheritanceFlags]::None
    if( Test-Path $path -PathType Container )
    {
        $expectedInheritanceFlags = [Security.AccessControl.InheritanceFlags]::ContainerInherit -bor `
                                    [Security.AccessControl.InheritanceFlags]::ObjectInherit
    }
    Assert-Equal $expectedInheritanceFlags $ace.InheritanceFlags
    Assert-Equal ([Security.AccessControl.PropagationFlags]::None) $ace.PropagationFlags
    Assert-Equal ($ace."$($providerName)Rights" -band $rights) $rights
}

