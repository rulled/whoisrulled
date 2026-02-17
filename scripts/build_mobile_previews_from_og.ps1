param(
  [switch]$DryRun
)

$ErrorActionPreference = "Stop"

$ffmpeg = (Get-Command "ffmpeg" -ErrorAction SilentlyContinue).Source
$ffprobe = (Get-Command "ffprobe" -ErrorAction SilentlyContinue).Source

if (-not $ffmpeg) { throw "ffmpeg was not found in PATH." }
if (-not $ffprobe) { throw "ffprobe was not found in PATH." }

Set-Location (Join-Path $PSScriptRoot "..")

$ogDir = "assets/previews/og"
$outDir = "assets/previews/mp4"
$reportPath = "assets/previews/preview-encode-report.csv"

New-Item -ItemType Directory -Force -Path $outDir | Out-Null

$items = @(
  @{ slug = "eikko-serious-sam"; start = "00:00:00"; end = "00:00:13" },
  @{ slug = "kayyo-emi4ka-overhype-sample-kit"; start = "00:00:00"; end = "00:00:06" },
  @{ slug = "kayyo-ilm"; start = "00:00:03"; end = "00:00:30" },
  @{ slug = "modeus-i-want-more"; start = "00:00:03"; end = "00:00:12" },
  @{ slug = "sqwore-beach-episode"; start = "00:00:00"; end = "00:00:10" },
  @{ slug = "sqwore-drunk"; start = "00:00:00"; end = "00:00:15" },
  @{ slug = "sqwore-ohwow"; start = "00:00:00"; end = "00:00:12" },
  @{ slug = "sqwore-protagonist"; start = "00:00:11"; end = "00:00:27" },
  @{ slug = "sqwore-tour-screens"; start = "00:00:00"; end = "00:00:12" },
  @{ slug = "tears-oyo-drowsyy-aktrisa"; start = "00:00:00"; end = "00:00:16" },
  @{ slug = "thes1cko-molniya-mcqueen"; start = "00:00:03"; end = "00:00:17" }
)

function Get-EvenInt([double]$value) {
  $result = [int][math]::Floor($value)
  if ($result % 2 -ne 0) { $result-- }
  if ($result -lt 2) { $result = 2 }
  return $result
}

$report = @()

foreach ($item in $items) {
  $src = Join-Path $ogDir "$($item.slug).mp4"
  $out = Join-Path $outDir "$($item.slug).mp4"

  if (-not (Test-Path -LiteralPath $src)) {
    throw "Source file not found: $src"
  }

  $probeJson = & $ffprobe -v error -select_streams v:0 -show_entries stream=width,height,avg_frame_rate,bit_rate -show_entries format=duration,size,bit_rate -of json $src
  $probe = $probeJson | ConvertFrom-Json
  $stream = $probe.streams[0]
  $format = $probe.format

  $srcW = [double]$stream.width
  $srcH = [double]$stream.height
  $aspect = $srcW / $srcH

  $fpsParts = $stream.avg_frame_rate -split "/"
  $srcFps = if ($fpsParts.Count -eq 2 -and [double]$fpsParts[1] -ne 0) {
    [double]$fpsParts[0] / [double]$fpsParts[1]
  } else {
    24
  }
  if ($srcFps -lt 1) { $srcFps = 24 }

  $srcBitrate = if ([double]$stream.bit_rate -gt 0) { [double]$stream.bit_rate } else { [double]$format.bit_rate }
  if ($srcBitrate -le 0) { $srcBitrate = 4500000 }

  $srcDuration = [double]$format.duration
  $startSec = [timespan]::Parse($item.start).TotalSeconds
  $endSec = [timespan]::Parse($item.end).TotalSeconds
  $clipDuration = [math]::Max(0.5, $endSec - $startSec)
  $maxDurationFromStart = [math]::Max(0.5, $srcDuration - $startSec)
  if ($clipDuration -gt $maxDurationFromStart) {
    $clipDuration = $maxDurationFromStart
  }

  if ($aspect -ge 1.7) {
    $targetWidth = 960
  } elseif ($aspect -ge 1.2) {
    $targetWidth = 900
  } elseif ($aspect -ge 0.95) {
    $targetWidth = 860
  } else {
    $targetWidth = 720
  }
  if ($srcW -lt $targetWidth) { $targetWidth = [int]$srcW }
  $targetWidth = Get-EvenInt $targetWidth

  if ($srcFps -ge 29.5) {
    $targetFps = 30
  } elseif ($srcFps -ge 23.5) {
    $targetFps = 24
  } else {
    $targetFps = [math]::Max(12, [int][math]::Round($srcFps))
  }

  $targetHeight = Get-EvenInt ($targetWidth / $aspect)

  $bppf = $srcBitrate / ($srcW * $srcH * [math]::Max($srcFps, 1))
  $targetBppf = [math]::Min(0.095, [math]::Max(0.05, $bppf * 0.58))
  $targetBitrate = [int][math]::Round($targetBppf * $targetWidth * $targetHeight * $targetFps)

  if ($bppf -ge 0.18) {
    $targetCrf = 23
  } elseif ($bppf -ge 0.12) {
    $targetCrf = 24
  } elseif ($bppf -ge 0.08) {
    $targetCrf = 25
  } else {
    $targetCrf = 26
  }

  $maxrateK = [math]::Max(700, [int][math]::Round(($targetBitrate * 1.45) / 1000))
  $bufsizeK = $maxrateK * 2

  $filter = "fps=$targetFps,scale='min($targetWidth,iw)':-2:flags=lanczos,format=yuv420p"

  if (-not $DryRun) {
    & $ffmpeg -y -hide_banner -loglevel error -ss $item.start -i $src -t $clipDuration -an -vf $filter -c:v libx264 -preset slow -profile:v high -level 4.1 -crf $targetCrf -maxrate "${maxrateK}k" -bufsize "${bufsizeK}k" -movflags +faststart $out
  }

  $outProbeJson = & $ffprobe -v error -select_streams v:0 -show_entries stream=width,height,avg_frame_rate -show_entries format=duration,size,bit_rate -of json $out
  $outProbe = $outProbeJson | ConvertFrom-Json
  $outStream = $outProbe.streams[0]
  $outFmt = $outProbe.format

  $outFpsParts = $outStream.avg_frame_rate -split "/"
  $outFps = if ($outFpsParts.Count -eq 2 -and [double]$outFpsParts[1] -ne 0) {
    [double]$outFpsParts[0] / [double]$outFpsParts[1]
  } else {
    $targetFps
  }

  $report += [pscustomobject]@{
    slug = $item.slug
    start = $item.start
    end = $item.end
    clip_duration_s = [math]::Round($clipDuration, 3)
    src_resolution = "$([int]$srcW)x$([int]$srcH)"
    src_fps = [math]::Round($srcFps, 3)
    src_bitrate_kbps = [math]::Round($srcBitrate / 1000, 1)
    source_bppf = [math]::Round($bppf, 5)
    chosen_width = $targetWidth
    chosen_height_est = $targetHeight
    chosen_fps = $targetFps
    chosen_crf = $targetCrf
    chosen_maxrate_kbps = $maxrateK
    out_resolution = "$([int]$outStream.width)x$([int]$outStream.height)"
    out_fps = [math]::Round($outFps, 3)
    out_duration_s = [math]::Round([double]$outFmt.duration, 3)
    out_bitrate_kbps = [math]::Round(([double]$outFmt.bit_rate) / 1000, 1)
    out_size_mb = [math]::Round(([double]$outFmt.size) / 1MB, 3)
  }
}

$report | Sort-Object slug | Export-Csv -NoTypeInformation -Encoding UTF8 $reportPath
Write-Host "Done. Report: $reportPath"
