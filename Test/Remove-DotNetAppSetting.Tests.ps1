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

& (Join-Path -Path $PSScriptRoot -ChildPath 'Import-CarbonForTest.ps1' -Resolve)

Describe 'Remove-DotNetAppSetting' {
    $appSettingName = "TEST_APP_SETTING_NAME"
    $appSettingValue = "TEST_APP_SETTING_VALUE"

    function Assert-AppSetting($Name, $value, [Switch]$Framework, [Switch]$Framework64, [Switch]$Clr2, [Switch]$Clr4)
    {
        $command = {
            param(
                $Name
            )
            
            Add-Type -AssemblyName System.Configuration
            
            $config = [Configuration.ConfigurationManager]::OpenMachineConfiguration()
            
            $appSettings = $config.AppSettings.Settings
            
            if( $appSettings[$Name] )
            {
                $appSettings[$Name].Value
            }
            else
            {
                $null
            }
        }
        
        $runtimes = @()
        if( $Clr2 )
        {
            $runtimes += 'v2.0'
        }
        if( $Clr4 )
        {
            $runtimes += 'v4.0'
        }
        
        if( $runtimes.Length -eq 0 )
        {
            throw "Must supply either or both the Clr2 and Clr2 switches."
        }
        
        $runtimes | ForEach-Object {
            $params = @{
                Command = $command
                Args = $Name
                Runtime = $_
            }
            
            if( $Framework64 )
            {
                $actualValue = Invoke-PowerShell @params
                $actualValue | Should Be $Value
            }
            
            if( $Framework )
            {
                $actualValue = Invoke-PowerShell @params -x86
                $actualValue | Should Be $Value
            }
        }
    }

    function Remove-AppSetting
    {
        $command = {
            param(
                [Parameter(Position=0)]
                $Name
            )
            
            Add-Type -AssemblyName System.Configuration
            
            $config = [Configuration.ConfigurationManager]::OpenMachineConfiguration()
            $appSettings = $config.AppSettings.Settings
            if( $appSettings[$Name] )
            {
                $appSettings.Remove( $Name )
                $config.Save()
            }
        }
        
        if( (Test-DotNet -V2) )
        {
            Invoke-PowerShell -Command $command -Args $appSettingName -x86 -Runtime 'v2.0'
            Invoke-PowerShell -Command $command -Args $appSettingName -Runtime 'v2.0'
        }
    
        if( (Test-DotNet -V4 -Full) )
        {
            Invoke-PowerShell -Command $command -Args $appSettingName -x86 -Runtime 'v4.0'
            Invoke-PowerShell -Command $command -Args $appSettingName -Runtime 'v4.0'
        }
    }
    
    BeforeEach {
        $Global:Error.Clear()
        if( $Host.Name -ne 'Windows PowerShell ISE Host' ) 
        {
            Set-DotNetAppSetting -Name $appSettingName -Value $appSettingValue -Framework64 -Clr2 -Framework -Clr4
        }
    }
    
    AfterEach {
        if( $Host.Name -ne 'Windows PowerShell ISE Host' ) 
        {
            Remove-AppSetting
        }
    }
    
    if( $Host.Name -ne 'Windows PowerShell ISE Host' )
    {
        It 'should update machine config .NET 2 x64' {
            if( -not (Test-DotNet -V2) )
            {
                Fail ('.NET v2 is not installed')
            }
    
            Remove-DotNetAppSetting -Name $appSettingName -Framework64 -Clr2
            Assert-AppSetting -Name $appSettingName -Value $null -Framework64 -Clr2
            Assert-AppSetting -Name $appSettingName -Value $appSettingValue -Framework64 -Clr4
            Assert-AppSetting -Name $appSettingName -Value $appSettingValue -Framework -Clr2
            Assert-AppSetting -Name $appSettingName -Value $appSettingValue -Framework -Clr4
        }
    
        It 'should update machine config .NET 2 x86' {
            if( -not (Test-DotNet -V2) )
            {
                Fail ('.NET v2 is not installed')
            }
    
            Remove-DotNetAppSetting -Name $appSettingName -Framework -Clr2
            Assert-AppSetting -Name $appSettingName -Value $appSettingValue -Framework64 -Clr2
            Assert-AppSetting -Name $appSettingName -Value $appSettingValue -Framework64 -Clr4
            Assert-AppSetting -Name $appSettingName -Value $null -Framework -Clr2
            Assert-AppSetting -Name $appSettingName -Value $appSettingValue -Framework -Clr4
        }
    
        It 'should update machine config .NET 4 x64' {
            if( -not (Test-DotNet -V4 -Full) )
            {
                Fail ('.NET v4 full is not installed')
            }
    
            Remove-DotNetAppSetting -Name $appSettingName -Framework64 -Clr4
            Assert-AppSetting -Name $appSettingName -Value $appSettingValue -Framework64 -Clr2
            Assert-AppSetting -Name $appSettingName -Value $null -Framework64 -Clr4
            Assert-AppSetting -Name $appSettingName -Value $appSettingValue -Framework -Clr2
            Assert-AppSetting -Name $appSettingName -Value $appSettingValue -Framework -Clr4
        }
    
        It 'should update machine config .NET 4 x86' {
            if( -not (Test-DotNet -V4 -Full) )
            {
                Fail ('.NET v4 full is not installed')
            }
    
            Remove-DotNetAppSetting -Name $appSettingName -Framework64 -Clr4
            Assert-AppSetting -Name $appSettingName -Value $appSettingValue -Framework64 -Clr2
            Assert-AppSetting -Name $appSettingName -Value $null -Framework64 -Clr4
            Assert-AppSetting -Name $appSettingName -Value $appSettingValue -Framework -Clr2
            Assert-AppSetting -Name $appSettingName -Value $appSettingValue -Framework -Clr4
        }
    
        It 'should remove app setting with sensitive characters' {
            $name = $value = '`1234567890-=qwertyuiop[]\a sdfghjkl;''zxcvbnm,./~!@#$%^&*()_+QWERTYUIOP{}|ASDFGHJKL:"ZXCVBNM<>?'
            Set-DotNetAppSetting -Name $name -Value $value -Framework64 -Clr4
            Assert-AppSetting -Name $name -Value $value -Framework64 -Clr4
            Remove-DotNetAppSetting -Name $name -Framework64 -Clr4
            Assert-AppSetting -Name $name -Value $null -Framework64 -Clr4
        }    
    }
    
    It 'should require a framework flag' {
        $error.Clear()
        Remove-DotNetAppSetting -Name $appSettingName -Clr2 -ErrorACtion SilentlyContinue
        $error.Count | Should Be 1
        ($error[0].Exception -like '*You must supply either or both of the Framework and Framework64 switches.') | Should Be $true
    }
    
    It 'should require a clr switch' {
        $error.Clear()
        Remove-DotNetAppSetting -Name $appSettingName -Framework -ErrorAction SilentlyContinue
        $error.Count | Should Be 1
        ($error[0].Exception -like '*You must supply either or both of the Clr2 and Clr4 switches.') | Should Be $true
    }
}
