param(
  [double]$ClipStartSec = 0.35,
  [double]$MinDurationSec = 2.6,
  [double]$MaxDurationSec = 3.4,
  [int]$DesktopFps = 24,
  [int]$MobileFps = 24,
  [double]$DesktopWidthScale = 2.0,
  [int]$DesktopWebmCrf = 32,
  [int]$MobileWebmCrf = 34
)

$ErrorActionPreference = "Stop"

$ffmpeg = (Get-Command "ffmpeg" -ErrorAction SilentlyContinue).Source
$ffprobe = (Get-Command "ffprobe" -ErrorAction SilentlyContinue).Source

if (-not $ffmpeg) { throw "ffmpeg was not found in PATH." }
if (-not $ffprobe) { throw "ffprobe was not found in PATH." }

Set-Location (Join-Path $PSScriptRoot "..")

$items = @(
  @{ id = "1090646757"; slug = "sqwore-ohwow" },
  @{ id = "1163047065"; slug = "sqwore-drunk"; clip_start_offset_s = 2.0 },
  @{ id = "1163048368"; slug = "sqwore-tour-screens" },
  @{ id = "1090666938"; slug = "kayyo-ilm"; clip_start_offset_s = 2.0 },
  @{ id = "1163049988"; slug = "modeus-i-want-more"; clip_start_offset_s = 2.0 },
  @{ id = "1090653148"; slug = "sqwore-protagonist" },
  @{ id = "1163049663"; slug = "eikko-serious-sam" },
  @{ id = "1163049430"; slug = "sqwore-beach-episode" },
  @{ id = "1090647765"; slug = "thes1cko-molniya-mcqueen" },
  @{ id = "1090647026"; slug = "tears-oyo-drowsyy-aktrisa" },
  @{ id = "1090646413"; slug = "kayyo-emi4ka-overhype-sample-kit" }
)

function Get-EvenInt([double]$value) {
  $result = [int][math]::Floor($value)
  if ($result % 2 -ne 0) { $result-- }
  if ($result -lt 2) { $result = 2 }
  return $result
}

function Resolve-PreviewSource([string]$slug, [string]$id) {
  $candidates = @(
    "assets/previews/og/$slug.mp4",
    "assets/previews/src/$slug-$id.mp4",
    "assets/previews/mp4/$slug.mp4"
  )

  foreach ($candidate in $candidates) {
    if (Test-Path -LiteralPath $candidate) {
      return $candidate
    }
  }

  $srcMatch = Get-ChildItem "assets/previews/src" -Filter "$slug-*.mp4" -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($srcMatch) {
    return $srcMatch.FullName
  }

  throw "No preview source found for $slug."
}

function Get-TargetWidths([double]$aspect) {
  if ($aspect -ge 1.65) {
    return @{ desktop = 620; mobile = 380 }
  }
  if ($aspect -ge 1.15) {
    return @{ desktop = 560; mobile = 360 }
  }
  if ($aspect -ge 0.95) {
    return @{ desktop = 500; mobile = 320 }
  }

  return @{ desktop = 420; mobile = 280 }
}

function Encode-PreviewWebM(
  [string]$source,
  [string]$outFile,
  [double]$clipStart,
  [double]$clipDuration,
  [int]$fps,
  [int]$width,
  [int]$crf
) {
  $filter = "fps=$fps,scale='min($width,iw)':-2:flags=lanczos"

  & $ffmpeg `
    -y `
    -hide_banner `
    -loglevel error `
    -ss $clipStart `
    -t $clipDuration `
    -i $source `
    -an `
    -sn `
    -vf $filter `
    -c:v libvpx-vp9 `
    -pix_fmt yuv420p `
    -b:v 0 `
    -crf $crf `
    -row-mt 1 `
    -deadline good `
    -cpu-used 2 `
    $outFile
}

New-Item -ItemType Directory -Force -Path `
  "assets/previews/video/desktop", `
  "assets/previews/video/mobile" | Out-Null

$report = @()

foreach ($item in $items) {
  $source = Resolve-PreviewSource $item.slug $item.id
  $desktopWebmOut = "assets/previews/video/desktop/$($item.slug).webm"
  $mobileWebmOut = "assets/previews/video/mobile/$($item.slug).webm"

  $probeJson = & $ffprobe -v error -select_streams v:0 -show_entries stream=width,height -show_entries format=duration -of json $source
  $probe = $probeJson | ConvertFrom-Json
  $stream = $probe.streams[0]
  $format = $probe.format

  $srcW = [double]$stream.width
  $srcH = [double]$stream.height
  $srcDuration = [double]$format.duration
  $aspect = $srcW / $srcH

  $targetWidths = Get-TargetWidths $aspect
  $desktopWidthTarget = $targetWidths.desktop * $DesktopWidthScale
  $desktopWidth = Get-EvenInt ([math]::Min($srcW, $desktopWidthTarget))
  $mobileWidth = Get-EvenInt ([math]::Min($srcW, $targetWidths.mobile))
  $desktopHeight = Get-EvenInt ($desktopWidth / $aspect)
  $mobileHeight = Get-EvenInt ($mobileWidth / $aspect)

  $clipStartOffset = if ($null -ne $item.clip_start_offset_s) { [double]$item.clip_start_offset_s } else { 0.0 }
  $effectiveClipStart = [math]::Min([math]::Max(0.0, $ClipStartSec + $clipStartOffset), [math]::Max(0.0, $srcDuration - 0.8))

  $desiredDuration = [math]::Round($srcDuration * 0.28, 2)
  $clipDuration = [math]::Min($MaxDurationSec, [math]::Max($MinDurationSec, $desiredDuration))
  $maxDurationFromStart = [math]::Max(0.8, $srcDuration - $effectiveClipStart)
  if ($clipDuration -gt $maxDurationFromStart) {
    $clipDuration = $maxDurationFromStart
  }

  Encode-PreviewWebM $source $desktopWebmOut $effectiveClipStart $clipDuration $DesktopFps $desktopWidth $DesktopWebmCrf
  Encode-PreviewWebM $source $mobileWebmOut $effectiveClipStart $clipDuration $MobileFps $mobileWidth $MobileWebmCrf

  $desktopWebmKb = [math]::Round((Get-Item $desktopWebmOut).Length / 1kb, 1)
  $mobileWebmKb = [math]::Round((Get-Item $mobileWebmOut).Length / 1kb, 1)

  $report += [pscustomobject]@{
    slug = $item.slug
    source = $source
    clip_start_s = [math]::Round($effectiveClipStart, 2)
    clip_duration_s = [math]::Round($clipDuration, 2)
    desktop_width = $desktopWidth
    desktop_height = $desktopHeight
    desktop_webm_kb = $desktopWebmKb
    mobile_width = $mobileWidth
    mobile_height = $mobileHeight
    mobile_webm_kb = $mobileWebmKb
  }
}

$report | Sort-Object slug | Export-Csv -NoTypeInformation -Encoding UTF8 "assets/previews/video-report.csv"
Write-Host "Done. Report: assets/previews/video-report.csv"
