[CmdletBinding()]
param(
    [Parameter()]
    [string]$DevEcoPath,

    [Parameter()]
    [string]$ProjectPath = (Get-Location).Path,

    [Parameter()]
    [switch]$Json
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function New-ProbeResult {
    param(
        [string]$Component,
        [ValidateSet('FOUND', 'NOT_FOUND', 'INVALID', 'UNKNOWN')]
        [string]$Status,
        [string]$Source,
        [string]$Path,
        [string]$Evidence
    )

    [pscustomobject]@{
        component = $Component
        status    = $Status
        source    = $Source
        path      = $Path
        evidence  = $Evidence
    }
}

function Get-ScopedEnvironmentCandidates {
    param([string]$Name)

    $items = [System.Collections.Generic.List[object]]::new()
    foreach ($scope in @('Process', 'User', 'Machine')) {
        $value = [Environment]::GetEnvironmentVariable($Name, $scope)
        if (-not [string]::IsNullOrWhiteSpace($value)) {
            $items.Add([pscustomobject]@{ Source = "$scope environment"; Path = $value })
        }
    }
    return $items.ToArray()
}

function Get-FirstLine {
    param([object[]]$Output)

    if ($null -eq $Output -or $Output.Count -eq 0) {
        return 'command completed without version text'
    }
    return ([string]$Output[0]).Trim()
}

function Test-ExecutableCandidate {
    param(
        [string]$Component,
        [object[]]$Candidates,
        [string[]]$Arguments
    )

    $sawInvalid = $false
    foreach ($candidate in $Candidates) {
        if ([string]::IsNullOrWhiteSpace([string]$candidate.Path)) {
            continue
        }
        if (-not (Test-Path -LiteralPath $candidate.Path -PathType Leaf)) {
            $sawInvalid = $true
            continue
        }
        try {
            $previousPreference = $ErrorActionPreference
            $ErrorActionPreference = 'Continue'
            try {
                $output = & $candidate.Path @Arguments 2>&1
                $exitCode = $LASTEXITCODE
            }
            finally {
                $ErrorActionPreference = $previousPreference
            }
            if ($exitCode -eq 0) {
                return New-ProbeResult $Component 'FOUND' $candidate.Source $candidate.Path (Get-FirstLine $output)
            }
            $sawInvalid = $true
        }
        catch {
            $sawInvalid = $true
        }
    }

    if ($sawInvalid) {
        return New-ProbeResult $Component 'INVALID' 'bounded candidates' $null 'candidate path or executable validation failed'
    }
    return New-ProbeResult $Component 'NOT_FOUND' 'bounded candidates' $null 'no candidate found'
}

function Test-SdkCandidate {
    param([object[]]$Candidates)

    $sawInvalid = $false
    foreach ($candidate in $Candidates) {
        if ([string]::IsNullOrWhiteSpace([string]$candidate.Path)) {
            continue
        }
        if (-not (Test-Path -LiteralPath $candidate.Path -PathType Container)) {
            $sawInvalid = $true
            continue
        }
        $markers = @('default', 'openharmony', 'hms', 'toolchains')
        $foundMarker = $false
        foreach ($marker in $markers) {
            if (Test-Path -LiteralPath (Join-Path $candidate.Path $marker)) {
                $foundMarker = $true
                break
            }
        }
        if ($foundMarker) {
            return New-ProbeResult 'SDK' 'FOUND' $candidate.Source $candidate.Path 'SDK directory contains a recognized family or toolchain directory'
        }
        $sawInvalid = $true
    }

    if ($sawInvalid) {
        return New-ProbeResult 'SDK' 'INVALID' 'bounded candidates' $null 'directory exists or is configured but expected SDK structure was not found'
    }
    return New-ProbeResult 'SDK' 'NOT_FOUND' 'bounded candidates' $null 'no SDK candidate found'
}

$resolvedProject = $null
if (-not [string]::IsNullOrWhiteSpace($ProjectPath) -and (Test-Path -LiteralPath $ProjectPath -PathType Container)) {
    $resolvedProject = (Resolve-Path -LiteralPath $ProjectPath).Path
}

$rootCandidates = [System.Collections.Generic.List[object]]::new()
if (-not [string]::IsNullOrWhiteSpace($DevEcoPath)) {
    $rootCandidates.Add([pscustomobject]@{ Source = 'parameter'; Path = $DevEcoPath })
}
foreach ($variableName in @('DEVECO_HOME', 'DEVECO_STUDIO_HOME')) {
    foreach ($item in Get-ScopedEnvironmentCandidates $variableName) {
        $rootCandidates.Add($item)
    }
}
foreach ($sdkItem in Get-ScopedEnvironmentCandidates 'DEVECO_SDK_HOME') {
    $sdkPath = [string]$sdkItem.Path
    if ((Split-Path -Leaf $sdkPath) -ieq 'sdk') {
        $rootCandidates.Add([pscustomobject]@{ Source = "derived from $($sdkItem.Source)"; Path = (Split-Path -Parent $sdkPath) })
    }
}
foreach ($nodeItem in Get-ScopedEnvironmentCandidates 'NODE_HOME') {
    $nodePath = [string]$nodeItem.Path
    if ((Split-Path -Leaf $nodePath) -ieq 'node' -and (Split-Path -Leaf (Split-Path -Parent $nodePath)) -ieq 'tools') {
        $rootCandidates.Add([pscustomobject]@{ Source = "derived from $($nodeItem.Source)"; Path = (Split-Path -Parent (Split-Path -Parent $nodePath)) })
    }
}
foreach ($javaItem in Get-ScopedEnvironmentCandidates 'JAVA_HOME') {
    $javaPath = [string]$javaItem.Path
    if ((Split-Path -Leaf $javaPath) -ieq 'jbr') {
        $rootCandidates.Add([pscustomobject]@{ Source = "derived from $($javaItem.Source)"; Path = (Split-Path -Parent $javaPath) })
    }
}
foreach ($programRoot in @([Environment]::GetFolderPath('ProgramFiles'), [Environment]::GetFolderPath('ProgramFilesX86'))) {
    if (-not [string]::IsNullOrWhiteSpace($programRoot)) {
        $rootCandidates.Add([pscustomobject]@{ Source = 'standard installation directory'; Path = (Join-Path $programRoot 'Huawei\DevEco Studio') })
    }
}

foreach ($registryPath in @(
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
)) {
    try {
        foreach ($entry in Get-ItemProperty -Path $registryPath -ErrorAction SilentlyContinue) {
            if ($entry.DisplayName -like '*DevEco Studio*' -and -not [string]::IsNullOrWhiteSpace([string]$entry.InstallLocation)) {
                $rootCandidates.Add([pscustomobject]@{ Source = 'installation registry'; Path = [string]$entry.InstallLocation })
            }
        }
    }
    catch {
        # Registry discovery is optional and read-only.
    }
}

$devEcoRoot = $null
$sawDevEcoInvalid = $false
foreach ($candidate in $rootCandidates) {
    if (-not (Test-Path -LiteralPath $candidate.Path -PathType Container)) {
        if ($candidate.Source -eq 'parameter') {
            $sawDevEcoInvalid = $true
        }
        continue
    }
    $hasNode = Test-Path -LiteralPath (Join-Path $candidate.Path 'tools\node\node.exe') -PathType Leaf
    $hasHvigor = Test-Path -LiteralPath (Join-Path $candidate.Path 'tools\hvigor\bin\hvigorw.js') -PathType Leaf
    $hasSdk = Test-Path -LiteralPath (Join-Path $candidate.Path 'sdk') -PathType Container
    $hasJbr = Test-Path -LiteralPath (Join-Path $candidate.Path 'jbr\bin\java.exe') -PathType Leaf
    if ($hasNode -and ($hasHvigor -or $hasSdk -or $hasJbr)) {
        $devEcoRoot = (Resolve-Path -LiteralPath $candidate.Path).Path
        $devEcoResult = New-ProbeResult 'DevEco Studio' 'FOUND' $candidate.Source $devEcoRoot 'recognized bundled Node plus Hvigor, SDK, or JBR'
        break
    }
    $sawDevEcoInvalid = $true
}
if ($null -eq $devEcoRoot) {
    if ($sawDevEcoInvalid) {
        $devEcoResult = New-ProbeResult 'DevEco Studio' 'INVALID' 'bounded candidates' $null 'candidate directory did not contain expected tools or SDK structure'
    }
    else {
        $devEcoResult = New-ProbeResult 'DevEco Studio' 'UNKNOWN' 'bounded candidates' $null 'installation not identified; pass -DevEcoPath for a nonstandard location'
    }
}

$nodeCandidates = [System.Collections.Generic.List[object]]::new()
$nodeCommand = Get-Command node -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
if ($null -ne $nodeCommand) {
    $nodeCandidates.Add([pscustomobject]@{ Source = 'PATH'; Path = $nodeCommand.Source })
}
foreach ($item in Get-ScopedEnvironmentCandidates 'NODE_HOME') {
    $nodeCandidates.Add([pscustomobject]@{ Source = $item.Source; Path = (Join-Path $item.Path 'node.exe') })
}
if ($null -ne $devEcoRoot) {
    $nodeCandidates.Add([pscustomobject]@{ Source = 'DevEco bundled'; Path = (Join-Path $devEcoRoot 'tools\node\node.exe') })
}
$nodeResult = Test-ExecutableCandidate 'Node' $nodeCandidates.ToArray() @('--version')

$sdkCandidates = [System.Collections.Generic.List[object]]::new()
foreach ($item in Get-ScopedEnvironmentCandidates 'DEVECO_SDK_HOME') {
    $sdkCandidates.Add($item)
}
if ($null -ne $devEcoRoot) {
    $sdkCandidates.Add([pscustomobject]@{ Source = 'DevEco bundled'; Path = (Join-Path $devEcoRoot 'sdk') })
}
$sdkResult = Test-SdkCandidate $sdkCandidates.ToArray()

$javaCandidates = [System.Collections.Generic.List[object]]::new()
$javaCommand = Get-Command java -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
if ($null -ne $javaCommand) {
    $javaCandidates.Add([pscustomobject]@{ Source = 'PATH'; Path = $javaCommand.Source })
}
foreach ($item in Get-ScopedEnvironmentCandidates 'JAVA_HOME') {
    $javaCandidates.Add([pscustomobject]@{ Source = $item.Source; Path = (Join-Path $item.Path 'bin\java.exe') })
}
if ($null -ne $devEcoRoot) {
    $javaCandidates.Add([pscustomobject]@{ Source = 'DevEco bundled JBR'; Path = (Join-Path $devEcoRoot 'jbr\bin\java.exe') })
}
$javaResult = Test-ExecutableCandidate 'JBR/Java' $javaCandidates.ToArray() @('-version')

$hvigorCandidates = [System.Collections.Generic.List[object]]::new()
if ($null -ne $resolvedProject) {
    foreach ($name in @('hvigorw.bat', 'hvigorw', 'hvigorw.js')) {
        $hvigorCandidates.Add([pscustomobject]@{ Source = 'project'; Path = (Join-Path $resolvedProject $name) })
    }
}
if ($null -ne $devEcoRoot) {
    $hvigorCandidates.Add([pscustomobject]@{ Source = 'DevEco bundled'; Path = (Join-Path $devEcoRoot 'tools\hvigor\bin\hvigorw.js') })
}
$hvigorFound = $hvigorCandidates | Where-Object { Test-Path -LiteralPath $_.Path -PathType Leaf } | Select-Object -First 1
if ($null -ne $hvigorFound) {
    $hvigorResult = New-ProbeResult 'Hvigor' 'FOUND' $hvigorFound.Source $hvigorFound.Path 'wrapper or JavaScript entrypoint exists'
}
elseif ($hvigorCandidates.Count -gt 0) {
    $hvigorResult = New-ProbeResult 'Hvigor' 'INVALID' 'bounded candidates' $null 'expected candidate paths were absent'
}
else {
    $hvigorResult = New-ProbeResult 'Hvigor' 'NOT_FOUND' 'bounded candidates' $null 'no project or DevEco candidate available'
}

$hdcCandidates = [System.Collections.Generic.List[object]]::new()
$hdcCommand = Get-Command hdc -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
if ($null -ne $hdcCommand) {
    $hdcCandidates.Add([pscustomobject]@{ Source = 'PATH'; Path = $hdcCommand.Source })
}
if ($sdkResult.status -eq 'FOUND') {
    foreach ($relative in @('toolchains\hdc.exe', 'default\openharmony\toolchains\hdc.exe', 'default\hms\toolchains\hdc.exe')) {
        $hdcCandidates.Add([pscustomobject]@{ Source = 'SDK'; Path = (Join-Path $sdkResult.path $relative) })
    }
}
$hdcResult = Test-ExecutableCandidate 'hdc' $hdcCandidates.ToArray() @('-v')

$signToolPath = $null
if ($sdkResult.status -eq 'FOUND') {
    foreach ($relative in @('toolchains\lib\hap-sign-tool.jar', 'default\openharmony\toolchains\lib\hap-sign-tool.jar', 'default\hms\toolchains\lib\hap-sign-tool.jar')) {
        $candidatePath = Join-Path $sdkResult.path $relative
        if (Test-Path -LiteralPath $candidatePath -PathType Leaf) {
            $signToolPath = $candidatePath
            break
        }
    }
    if ($null -eq $signToolPath) {
        $signToolPath = Get-ChildItem -LiteralPath $sdkResult.path -Filter 'hap-sign-tool.jar' -File -Recurse -ErrorAction SilentlyContinue |
            Select-Object -First 1 -ExpandProperty FullName
    }
}
if ($null -ne $signToolPath) {
    $signToolResult = New-ProbeResult 'hap-sign-tool' 'FOUND' 'SDK' $signToolPath 'official signing tool JAR found; inspect local help before use'
}
elseif ($sdkResult.status -eq 'INVALID') {
    $signToolResult = New-ProbeResult 'hap-sign-tool' 'UNKNOWN' 'SDK' $null 'SDK is invalid, so bounded tool discovery is inconclusive'
}
else {
    $signToolResult = New-ProbeResult 'hap-sign-tool' 'NOT_FOUND' 'SDK' $null 'JAR not found under the selected SDK'
}

$results = @($devEcoResult, $nodeResult, $sdkResult, $javaResult, $hvigorResult, $hdcResult, $signToolResult)

if ($Json) {
    $results | ConvertTo-Json -Depth 4
}
else {
    $results | Format-Table component, status, source, path, evidence -AutoSize
}
