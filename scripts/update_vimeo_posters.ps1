$ErrorActionPreference = "Stop"

$ffmpeg = (Get-Command "ffmpeg" -ErrorAction SilentlyContinue).Source
if (-not $ffmpeg) {
  throw "ffmpeg was not found in PATH."
}

Set-Location (Join-Path $PSScriptRoot "..")

$widthMap = @{}
if (Test-Path "assets/previews/ffprobe-adaptive-report.csv") {
  Import-Csv "assets/previews/ffprobe-adaptive-report.csv" | ForEach-Object {
    $widthMap[$_.slug] = [int]$_.chosen_width
  }
}

$items = @(
  @{ slug = "sqwore-ohwow"; href = "https://vimeo.com/1090646757" },
  @{ slug = "sqwore-drunk"; href = "https://vimeo.com/1163047065" },
  @{ slug = "sqwore-tour-screens"; href = "https://vimeo.com/1163048368" },
  @{ slug = "kayyo-ilm"; href = "https://player.vimeo.com/video/1090666938?h=bf2ee708f9" },
  @{ slug = "modeus-i-want-more"; href = "https://vimeo.com/1163049988" },
  @{ slug = "sqwore-protagonist"; href = "https://vimeo.com/1090653148" },
  @{ slug = "eikko-serious-sam"; href = "https://vimeo.com/1163049663" },
  @{ slug = "sqwore-beach-episode"; href = "https://vimeo.com/1163049430" },
  @{ slug = "thes1cko-molniya-mcqueen"; href = "https://vimeo.com/1090647765" },
  @{ slug = "tears-oyo-drowsyy-aktrisa"; href = "https://vimeo.com/1090647026" },
  @{ slug = "kayyo-emi4ka-overhype-sample-kit"; href = "https://vimeo.com/1090646413" }
)

New-Item -ItemType Directory -Force -Path "assets/previews/posters" | Out-Null

$rows = @()
foreach ($item in $items) {
  $slug = $item.slug
  $encodedUrl = [System.Uri]::EscapeDataString($item.href)
  $oembed = Invoke-RestMethod -Uri "https://vimeo.com/api/oembed.json?url=$encodedUrl&width=1280" -TimeoutSec 30
  $thumbUrl = $oembed.thumbnail_url

  $targetWidth = if ($widthMap.ContainsKey($slug)) { $widthMap[$slug] } else { 768 }
  $raw = "assets/previews/posters/$slug.tmp.jpg"
  $out = "assets/previews/posters/$slug.webp"

  Invoke-WebRequest -Uri $thumbUrl -OutFile $raw -TimeoutSec 30
  & $ffmpeg -y -hide_banner -loglevel error -i $raw -vf "scale='min($targetWidth,iw)':-2:flags=lanczos" -c:v libwebp -q:v 76 $out
  Remove-Item $raw -ErrorAction SilentlyContinue

  $rows += [pscustomobject]@{
    slug = $slug
    width = $targetWidth
    source_thumbnail = $thumbUrl
  }
}

$rows | Export-Csv -NoTypeInformation -Encoding UTF8 "assets/previews/vimeo-poster-report.csv"
Write-Host "Done. Updated posters from Vimeo."
