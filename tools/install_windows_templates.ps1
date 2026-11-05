# Install only the pinned Windows x64 release files from an official Godot TPZ.
# Download/install is a dependency change: obtain the user's authorization first.
param(
    [string]$ArchivePath = '',
    [switch]$Download
)
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$version = '4.7.2.stable'
$asset = 'Godot_v4.7.2-stable_export_templates.tpz'
$url = "https://github.com/godotengine/godot-builds/releases/download/4.7.2-stable/$asset"
$sha256 = 'f298490b8d44d934be425a5a65a51bf15f422428b229a06a6e11d9ffea248011'
$sha512 = 'ca4d71c4d7b81dfc15d1a98baa07534aa95b03fdda78a0075b06672e1648d2e5f40980c9adc28d23e1b92e732ee7bf3461997aa804af74ec2fcd7a93ccb84079'
$cache = Join-Path $root 'tools/godot'
New-Item -ItemType Directory -Force -Path $cache | Out-Null
if (-not $ArchivePath) { $ArchivePath = Join-Path $cache $asset }
$ArchivePath = [IO.Path]::GetFullPath($ArchivePath)
if ($Download -and -not (Test-Path -LiteralPath $ArchivePath -PathType Leaf)) {
    $partial = "$ArchivePath.partial"
    & curl.exe --fail --location --retry 3 --silent --show-error --output $partial $url
    if ($LASTEXITCODE -ne 0) { throw "Official template download failed ($LASTEXITCODE)." }
    # Promote only after verifying both independently published digests below.
    $inputArchive = $partial
} else { $inputArchive = $ArchivePath }
if (-not (Test-Path -LiteralPath $inputArchive -PathType Leaf)) { throw 'Template archive missing. Use -ArchivePath or explicitly authorize -Download.' }
$archive = Get-Item -LiteralPath $inputArchive -Force
if (($archive.Attributes -band [IO.FileAttributes]::ReparsePoint) -or $archive.Length -ne 1281349702) { throw 'Unexpected official archive size or reparse point.' }
if ((Get-FileHash -LiteralPath $inputArchive -Algorithm SHA256).Hash.ToLowerInvariant() -cne $sha256) { throw 'Official archive SHA256 mismatch.' }
if ((Get-FileHash -LiteralPath $inputArchive -Algorithm SHA512).Hash.ToLowerInvariant() -cne $sha512) { throw 'Official archive SHA512 mismatch.' }
if ($inputArchive -ne $ArchivePath) { Move-Item -LiteralPath $inputArchive -Destination $ArchivePath }

$parent = Join-Path $cache 'export-templates'
New-Item -ItemType Directory -Force -Path $parent | Out-Null
$destination = Join-Path $parent $version
$token = [guid]::NewGuid().ToString('N')
$stage = Join-Path $parent ".$version.staging-$token"
$backup = Join-Path $parent "$version.previous-$token"
New-Item -ItemType Directory -Path $stage | Out-Null
$published = $false
$oldMoved = $false
$zip = $null
try {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [IO.Compression.ZipFile]::OpenRead($ArchivePath)
    $files = @()
    foreach ($name in @('version.txt', 'windows_release_x86_64.exe', 'icudt_godot.dat')) {
        $matches = @($zip.Entries | Where-Object { $_.FullName -ceq "templates/$name" })
        if ($matches.Count -ne 1 -or $matches[0].Length -le 0) { throw "Official archive is missing a unique nonempty templates/$name." }
        $target = Join-Path $stage $name
        [IO.Compression.ZipFileExtensions]::ExtractToFile($matches[0], $target, $false)
        $files += [ordered]@{ path = $name; sha256 = (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash.ToLowerInvariant(); size_bytes = (Get-Item -LiteralPath $target).Length }
    }
    $zip.Dispose()
    $zip = $null
    if ((Get-Content -LiteralPath (Join-Path $stage 'version.txt') -Raw).Trim() -cne $version) { throw 'Official archive version mismatch.' }
    [ordered]@{
        schema_version = 1
        version = $version
        source = [ordered]@{ url = $url; sha256 = $sha256; sha512 = $sha512 }
        files = $files
    } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $stage 'provenance.json') -Encoding UTF8
    . (Join-Path $PSScriptRoot 'windows_templates.ps1')
    $null = Get-VerifiedWindowsTemplates -TemplatesDir $stage -Version $version
    if (Test-Path -LiteralPath $destination) {
        $existing = Get-Item -LiteralPath $destination -Force
        if (-not $existing.PSIsContainer -or ($existing.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'Existing template path is not an ordinary directory.' }
        Move-Item -LiteralPath $destination -Destination $backup
        $oldMoved = $true
    }
    try {
        Move-Item -LiteralPath $stage -Destination $destination
        $published = $true
    } catch {
        if ($oldMoved -and -not (Test-Path -LiteralPath $destination)) { Move-Item -LiteralPath $backup -Destination $destination }
        throw
    }
    Write-Host "Verified Windows release templates: $destination"
} finally {
    if ($zip) { $zip.Dispose() }
    if (-not $published -and (Test-Path -LiteralPath $stage -PathType Container)) {
        $resolved = (Resolve-Path -LiteralPath $stage).ProviderPath
        if ($resolved -eq [IO.Path]::GetFullPath($stage) -and $resolved.StartsWith([IO.Path]::GetFullPath($parent) + '\', [StringComparison]::OrdinalIgnoreCase) -and -not ((Get-Item -LiteralPath $stage -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) {
            Remove-Item -LiteralPath $stage -Recurse -Force
        } else { Write-Warning "Temporary path changed; left intact: $stage" }
    }
}
