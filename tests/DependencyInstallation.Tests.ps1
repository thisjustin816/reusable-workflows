BeforeAll {
    $workflowPath = Join-Path $PSScriptRoot '../.github/workflows/ps-ci.yml'
    $workflow = Get-Content -LiteralPath $workflowPath -Raw
    $pattern = '(?ms)^      - name: Install Module Dependencies\r?\n.*?        run: \|\r?\n(?<script>.*?)(?=^      - name:|\z)'
    $step = [Regex]::Match($workflow, $pattern)
    if (-not $step.Success) {
        throw 'Module dependency installation step was not found.'
    }
    $script:installStep = [ScriptBlock]::Create(($step.Groups['script'].Value -replace '(?m)^          ', ''))
}

Describe 'Manifest dependency installation' {
    BeforeEach {
        $script:originalModulePath = $env:PSModulePath
        $moduleRoot = New-Item -ItemType Directory -Path "$TestDrive/modules/WorkflowProbe/1.2.0" -Force
        New-ModuleManifest -Path "$moduleRoot/WorkflowProbe.psd1" -ModuleVersion '1.2.0'
        $env:PSModulePath = "$TestDrive/modules" + [IO.Path]::PathSeparator + $env:PSModulePath
        New-Item -ItemType Directory -Path "$TestDrive/src" -Force | Out-Null
        Push-Location -LiteralPath $TestDrive
        Mock Install-Module {}
    }

    AfterEach {
        Pop-Location
        $env:PSModulePath = $script:originalModulePath
    }

    It 'reuses a dependency declared by name alone' {
        Set-Content -LiteralPath './src/Consumer.psd1' -Value "@{ RequiredModules = @('WorkflowProbe') }"
        & $script:installStep
        Should -Invoke Install-Module -Times 0
    }

    It 'installs a missing dependency declared by name alone' {
        Set-Content -LiteralPath './src/Consumer.psd1' -Value "@{ RequiredModules = @('MissingWorkflowProbe') }"
        & $script:installStep
        Should -Invoke Install-Module -Times 1 -Exactly -ParameterFilter {
            $Name -eq 'MissingWorkflowProbe' -and -not $RequiredVersion -and -not $MinimumVersion
        }
    }

    It 'reuses an installed exact version' {
        Set-Content -LiteralPath './src/Consumer.psd1' -Value "@{ RequiredModules = @(@{ ModuleName = 'WorkflowProbe'; RequiredVersion = '1.2.0' }) }"
        & $script:installStep
        Should -Invoke Install-Module -Times 0
    }

    It 'installs the requested version when another version is available' {
        Set-Content -LiteralPath './src/Consumer.psd1' -Value "@{ RequiredModules = @(@{ ModuleName = 'WorkflowProbe'; RequiredVersion = '2.0.0' }) }"
        & $script:installStep
        Should -Invoke Install-Module -Times 1 -Exactly -ParameterFilter {
            $Name -eq 'WorkflowProbe' -and $RequiredVersion -eq '2.0.0'
        }
    }

    It 'reuses a dependency within its allowed range' {
        Set-Content -LiteralPath './src/Consumer.psd1' -Value "@{ RequiredModules = @(@{ ModuleName = 'WorkflowProbe'; ModuleVersion = '1.0.0'; MaximumVersion = '1.9.0' }) }"
        & $script:installStep
        Should -Invoke Install-Module -Times 0
    }

    It 'propagates a failed dependency installation' {
        Set-Content -LiteralPath './src/Consumer.psd1' -Value "@{ RequiredModules = @('MissingWorkflowProbe') }"
        Mock Install-Module { throw 'Dependency download failed.' }
        { & $script:installStep } | Should -Throw '*Dependency download failed*'
    }
}
