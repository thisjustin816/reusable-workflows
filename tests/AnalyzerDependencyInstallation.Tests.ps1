BeforeAll {
    $path = Join-Path $PSScriptRoot '../.github/workflows/ps-scriptAnalyzer.yml'
    $workflow = Get-Content -LiteralPath $path -Raw
    $pattern = '(?ms)^      - name: Run PSScriptAnalyzer\r?\n.*?        run: \|\r?\n(?<script>.*?)(?=^      - name:|\z)'
    $step = [Regex]::Match($workflow, $pattern)
    if (-not $step.Success) {
        throw 'Analyzer installation step was not found.'
    }
    $script:analyzerStep = [ScriptBlock]::Create(($step.Groups['script'].Value -replace '(?m)^          ', ''))
    <#
    .SYNOPSIS
    Test double for analyzer settings export.
    #>
    function Export-PSModuleAnalyzerSettings {
        param($Path, [Switch]$Force)
        $null = $PSBoundParameters
    }
    <#
    .SYNOPSIS
    Test double for source analysis.
    #>
    function Invoke-PSModuleAnalyzer {
        param($SourceDirectory, $Settings)
        $null = $PSBoundParameters
    }
    <#
    .SYNOPSIS
    Test double for SARIF conversion.
    #>
    function ConvertTo-SARIF {
        [CmdletBinding()]
        param([Parameter(ValueFromPipeline)]$InputObject, $FilePath)
        process { $null = $PSBoundParameters }
    }
}

Describe 'Analyzer dependency installation' {
    BeforeEach {
        $script:original = @{}
        $names = @(
            'USE_LOCAL_PSMODULEUTILS'
            'PSMODULEUTILS_VERSION'
            'INPUT_PATH'
            'INPUT_SETTINGS'
            'RUNNER_TEMP'
        )
        foreach ($name in $names) {
            $script:original[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
        }
        $env:USE_LOCAL_PSMODULEUTILS = 'false'
        $env:PSMODULEUTILS_VERSION = '5.0.0'
        $env:INPUT_PATH = 'src'
        $env:INPUT_SETTINGS = ''
        $env:RUNNER_TEMP = $TestDrive
        Mock Get-Module { [PSCustomObject]@{ Name = 'ConvertToSARIF' } }
        Mock Get-Module { $null } -ParameterFilter {
            $ListAvailable -and $FullyQualifiedName -and $FullyQualifiedName.Name -eq 'PSModuleUtils'
        }
        Mock Import-Module {}
        Mock Install-Module {
            if (-not $AllowClobber) {
                throw 'Get-EnvironmentVariable already exists; explicit clobber permission is required.'
            }
        }
        Mock Export-PSModuleAnalyzerSettings {}
        Mock Invoke-PSModuleAnalyzer { [PSCustomObject]@{ RuleName = 'FixtureRule' } }
        Mock ConvertTo-SARIF {}
    }

    AfterEach {
        foreach ($name in $script:original.Keys) {
            [Environment]::SetEnvironmentVariable($name, $script:original[$name], 'Process')
        }
    }

    It 'installs the pinned analyzer tool despite an existing dependency command and reaches analysis' {
        & $script:analyzerStep
        Should -Invoke Install-Module -Times 1 -Exactly -ParameterFilter {
            $Name -eq 'PSModuleUtils' -and $RequiredVersion -eq [Version]'5.0.0' -and $AllowClobber
        }
        Should -Invoke Invoke-PSModuleAnalyzer -Times 1 -Exactly
        Should -Invoke ConvertTo-SARIF -Times 1 -Exactly -ParameterFilter { $FilePath -eq 'results.sarif' }
    }

    It 'reuses the installed exact version without installing it again' {
        Mock Get-Module { [PSCustomObject]@{ Name = 'PSModuleUtils' } } -ParameterFilter {
            $ListAvailable -and $FullyQualifiedName -and $FullyQualifiedName.Name -eq 'PSModuleUtils'
        }
        & $script:analyzerStep
        Should -Invoke Install-Module -Times 0
        Should -Invoke Invoke-PSModuleAnalyzer -Times 1 -Exactly
    }

    It 'propagates an actual dependency installation failure before analysis' {
        Mock Install-Module { throw 'Dependency download failed.' }
        { & $script:analyzerStep } | Should -Throw '*Dependency download failed*'
        Should -Invoke Invoke-PSModuleAnalyzer -Times 0
    }
}
