param(
    [string]$Arg = ''
)

try {
    $baseVersion = $null

    $versionCode = [int](git rev-list --count HEAD).Trim()

    $commitHash = (git rev-parse HEAD).Trim()
    $shortHash = $commitHash.Substring(0, 9)

    $updatedContent = foreach ($line in (Get-Content -Path 'pubspec.yaml' -Encoding UTF8)) {
        if ($line -match '^\s*version:\s*([\d\.]+)') {
            $baseVersion = $matches[1]
            "version: $baseVersion+$versionCode"
        }
        else {
            $line
        }
    }

    if ($null -eq $baseVersion) {
        throw 'version not found'
    }

    $updatedContent | Set-Content -Path 'pubspec.yaml' -Encoding UTF8

    $versionName = "${baseVersion}_$shortHash"
    $releaseVersion = "$versionName+$versionCode"
    $packageVersion = "${baseVersion}+git.$shortHash.$versionCode"

    $buildTime = [int]([DateTimeOffset]::Now.ToUnixTimeSeconds())

    $data = @{
        'pili.name' = $versionName
        'pili.code' = $versionCode
        'pili.hash' = $commitHash
        'pili.time' = $buildTime
    }

    $data | ConvertTo-Json -Compress | Out-File 'pili_release.json' -Encoding UTF8

    if ($env:GITHUB_ENV) {
        Add-Content -Path $env:GITHUB_ENV -Value "version=$releaseVersion"
        Add-Content -Path $env:GITHUB_ENV -Value "package_version=$packageVersion"
    }
}
catch {
    Write-Error "Prebuild Error: $($_.Exception.Message)"
    exit 1
}
