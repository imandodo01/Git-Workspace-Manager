$modulePath = Join-Path $PSScriptRoot '..\src\GWM.Core.psm1'
Import-Module -Name $modulePath -Force

Describe 'GWM state classification' {
    It 'classifies an up-to-date clean branch' {
        $result = Get-GwmStateClassification -Branch 'main' -UpstreamAvailable $true -StatusLines @() -Ahead 0 -Behind 0
        $result.Status | Should Be 'UP_TO_DATE'
    }

    It 'does not classify dirty repositories as safe to update' {
        $result = Get-GwmStateClassification -Branch 'main' -UpstreamAvailable $true -StatusLines @('?? draft.txt') -Ahead 0 -Behind 2
        $result.Status | Should Be 'NEEDS_ATTENTION'
    }

    It 'detects diverged branches' {
        $result = Get-GwmStateClassification -Branch 'main' -UpstreamAvailable $true -StatusLines @() -Ahead 1 -Behind 2
        $result.Status | Should Be 'DIVERGED'
    }

    It 'detects detached HEAD' {
        $result = Get-GwmStateClassification -Branch '' -UpstreamAvailable $true -StatusLines @() -Ahead 0 -Behind 0
        $result.Status | Should Be 'NEEDS_ATTENTION'
    }

    It 'detects a branch without upstream' {
        $result = Get-GwmStateClassification -Branch 'main' -UpstreamAvailable $false -StatusLines @() -Ahead $null -Behind $null
        $result.Status | Should Be 'NEEDS_ATTENTION'
    }
}
