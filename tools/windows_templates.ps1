# Shared Windows build validation. This file is compatible with Windows PowerShell 5.1.
# Downloading dependencies is deliberately outside the build commands.

function Assert-LedgerPlainPath([string]$Path) {
    $cursor = [IO.Path]::GetFullPath($Path)
    while ($cursor) {
        if (Test-Path -LiteralPath $cursor) {
            $item = Get-Item -LiteralPath $cursor -Force
            if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
                throw "Reparse points are not allowed in build inputs: $cursor"
            }
        }
        $next = [IO.Path]::GetDirectoryName($cursor)
        if ($next -eq $cursor) { break }
        $cursor = $next
    }
}

function Assert-LedgerX64Pe([string]$Path) {
    $stream = [IO.File]::OpenRead($Path)
    $reader = New-Object IO.BinaryReader($stream)
    try {
        if ($stream.Length -lt 70 -or $reader.ReadUInt16() -ne 0x5a4d) { throw "Invalid PE file: $Path" }
        $stream.Position = 0x3c
        $offset = $reader.ReadUInt32()
        if ($offset -lt 64 -or $offset -gt ($stream.Length - 6)) { throw "Invalid PE header offset: $Path" }
        $stream.Position = $offset
        if ($reader.ReadUInt32() -ne 0x00004550 -or $reader.ReadUInt16() -ne 0x8664) {
            throw "Expected a Windows x64 PE file: $Path"
        }
    } finally { $reader.Dispose() }
}

function Get-LedgerFileRecord([string]$Path, [string]$RelativePath) {
    Assert-LedgerPlainPath $Path
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Missing file: $Path" }
    $item = Get-Item -LiteralPath $Path -Force
    if ($item.Length -eq 0) { throw "Empty file: $Path" }
    [pscustomobject][ordered]@{
        path = $RelativePath.Replace('\', '/')
        size_bytes = [long]$item.Length
        sha256 = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
    }
}

function Get-VerifiedWindowsTemplates([string]$TemplatesDir, [string]$Version) {
    if ([string]::IsNullOrWhiteSpace($TemplatesDir)) { throw 'A verified Windows template directory is required.' }
    $directory = [IO.Path]::GetFullPath($TemplatesDir).TrimEnd([IO.Path]::DirectorySeparatorChar)
    Assert-LedgerPlainPath $directory
    if (-not (Test-Path -LiteralPath $directory -PathType Container)) { throw "Windows templates are missing: $directory" }
    $manifestPath = Join-Path $directory 'provenance.json'
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) { throw "Template provenance is missing: $manifestPath" }
    $null = Get-LedgerFileRecord $manifestPath 'provenance.json'
    foreach ($item in @(Get-ChildItem -LiteralPath $directory -Force)) {
        if ($item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
            throw "Unexpected template directory entry: $($item.Name)"
        }
    }
    $manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($manifest.schema_version -ne 1 -or $manifest.version -cne $Version -or $Version -cne '4.7.2.stable') {
        throw "Template manifest version does not match the engine: $Version"
    }
    $officialUrl = 'https://github.com/godotengine/godot-builds/releases/download/4.7.2-stable/Godot_v4.7.2-stable_export_templates.tpz'
    $officialSha512 = 'ca4d71c4d7b81dfc15d1a98baa07534aa95b03fdda78a0075b06672e1648d2e5f40980c9adc28d23e1b92e732ee7bf3461997aa804af74ec2fcd7a93ccb84079'
    $officialSha256 = 'f298490b8d44d934be425a5a65a51bf15f422428b229a06a6e11d9ffea248011'
    if ($manifest.source.url -cne $officialUrl -or $manifest.source.sha512 -ine $officialSha512 -or $manifest.source.sha256 -ine $officialSha256) {
        throw 'Template provenance does not identify the pinned official archive.'
    }
    $versionPath = Join-Path $directory 'version.txt'
    if (-not (Test-Path -LiteralPath $versionPath -PathType Leaf) -or (Get-Content -LiteralPath $versionPath -Raw -Encoding UTF8).Trim() -cne $Version) {
        throw "Template version.txt does not match the engine: $Version"
    }
    $records = @($manifest.files)
    $names = @{}
    foreach ($record in $records) {
        $name = [string]$record.path
        if ($name -cnotmatch '^(version\.txt|windows_release_x86_64\.exe|accesskit\.x86_64\.dll|icudt_godot\.dat)$' -or $names.ContainsKey($name)) {
            throw "Invalid or duplicate template file: $name"
        }
        $names[$name] = $true
        $actual = Get-LedgerFileRecord (Join-Path $directory $name) $name
        if ([string]$record.sha256 -notmatch '^[a-fA-F0-9]{64}$' -or $actual.sha256 -ine [string]$record.sha256 -or $actual.size_bytes -ne $record.size_bytes) {
            throw "Template checksum or size mismatch: $name"
        }
        if ($name -match '\.(exe|dll)$') { Assert-LedgerX64Pe (Join-Path $directory $name) }
    }
    if (-not $names.ContainsKey('version.txt') -or -not $names.ContainsKey('windows_release_x86_64.exe')) {
        throw 'The template manifest must include version.txt and windows_release_x86_64.exe.'
    }
    foreach ($item in @(Get-ChildItem -LiteralPath $directory -Force)) {
        if ($item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -or ($item.Name -cne 'provenance.json' -and -not $names.ContainsKey($item.Name))) {
            throw "Unexpected template directory entry: $($item.Name)"
        }
    }
    [pscustomobject]@{ Directory = $directory; Manifest = $manifest }
}

function Copy-VerifiedWindowsTemplates($Verified, [string]$Destination, [string]$Version) {
    # Recheck the source immediately before copying; don't copy arbitrary neighboring files.
    $current = Get-VerifiedWindowsTemplates $Verified.Directory $Version
    Assert-LedgerPlainPath $Destination
    if (Test-Path -LiteralPath $Destination) { throw "Template destination already exists: $Destination" }
    New-Item -ItemType Directory -Force -Path $Destination | Out-Null
    foreach ($record in $current.Manifest.files) {
        Copy-Item -LiteralPath (Join-Path $current.Directory $record.path) -Destination $Destination
    }
    Copy-Item -LiteralPath (Join-Path $current.Directory 'provenance.json') -Destination $Destination
    $copy = Get-VerifiedWindowsTemplates $Destination $Version
    $before = (Get-FileHash -LiteralPath (Join-Path $current.Directory 'provenance.json') -Algorithm SHA256).Hash
    $after = (Get-FileHash -LiteralPath (Join-Path $copy.Directory 'provenance.json') -Algorithm SHA256).Hash
    if ($before -cne $after) { throw 'Copied template provenance differs from its source.' }
    $copy
}

function Get-LedgerPackageFiles([string]$Directory) {
    $directoryPath = [IO.Path]::GetFullPath($Directory).TrimEnd([IO.Path]::DirectorySeparatorChar)
    Assert-LedgerPlainPath $directoryPath
    foreach ($item in @(Get-ChildItem -LiteralPath $directoryPath -Recurse -Force | Sort-Object FullName)) {
        if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "Reparse point in package: $($item.FullName)" }
        if (-not $item.PSIsContainer -and $item.FullName -cne (Join-Path $directoryPath 'package-provenance.json')) {
            $relative = $item.FullName.Substring($directoryPath.Length + 1)
            Get-LedgerFileRecord $item.FullName $relative
        }
    }
}
