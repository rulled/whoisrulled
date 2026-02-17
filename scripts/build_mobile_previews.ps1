param(
  [switch]$KeepSource,
  [int]$MaxDurationSec = 12,
  [int]$MinDurationSec = 8,
  [double]$DurationRatio = 0.45
)

$ErrorActionPreference = "Stop"

$yt = (Get-Command "yt-dlp" -ErrorAction SilentlyContinue).Source
$ffmpeg = (Get-Command "ffmpeg" -ErrorAction SilentlyContinue).Source
$ffprobe = (Get-Command "ffprobe" -ErrorAction SilentlyContinue).Source

if (-not $yt) { throw "yt-dlp was not found in PATH." }
if (-not $ffmpeg) { throw "ffmpeg was not found in PATH." }
if (-not $ffprobe) { throw "ffprobe was not found in PATH." }

Set-Location (Join-Path $PSScriptRoot "..")

$items = @(
  @{ id = "1090646757"; slug = "sqwore-ohwow"; href = "https://vimeo.com/1090646757" },
  @{ id = "1163047065"; slug = "sqwore-drunk"; href = "https://vimeo.com/1163047065" },
  @{ id = "1163048368"; slug = "sqwore-tour-screens"; href = "https://vimeo.com/1163048368" },
  @{ id = "1090666938"; slug = "kayyo-ilm"; href = "https://player.vimeo.com/video/1090666938?h=bf2ee708f9" },
  @{ id = "1163049988"; slug = "modeus-i-want-more"; href = "https://vimeo.com/1163049988" },
  @{ id = "1090653148"; slug = "sqwore-protagonist"; href = "https://vimeo.com/1090653148" },
  @{ id = "1163049663"; slug = "eikko-serious-sam"; href = "https://vimeo.com/1163049663" },
  @{ id = "1163049430"; slug = "sqwore-beach-episode"; href = "https://vimeo.com/1163049430" },
  @{ id = "1090647765"; slug = "thes1cko-molniya-mcqueen"; href = "https://vimeo.com/1090647765" },
  @{ id = "1090647026"; slug = "tears-oyo-drowsyy-aktrisa"; href = "https://vimeo.com/1090647026" },
  @{ id = "1090646413"; slug = "kayyo-emi4ka-overhype-sample-kit"; href = "https://vimeo.com/1090646413" }
)

New-Item -ItemType Directory -Force -Path "assets/previews/src", "assets/previews/mp4", "assets/previews/posters" | Out-Null

$sourceReport = @()
$adaptiveReport = @()

foreach ($item in $items) {
  $src = "assets/previews/src/$($item.slug)-$($item.id).mp4"
  $mp4 = "assets/previews/mp4/$($item.slug).mp4"
  $poster = "assets/previews/posters/$($item.slug).webp"

  & $yt --no-playlist -S "res:1080,codec:h264" -f "bv*[ext=mp4]/bv*" -o $src $item.href

  $sourceJson = & $ffprobe -v error -select_streams v:0 -show_entries stream=width,height,avg_frame_rate,bit_rate -show_entries format=duration,bit_rate,size -of json $src
  $srcObj = $sourceJson | ConvertFrom-Json
  $stream = $srcObj.streams[0]
  $fmt = $srcObj.format

  $srcW = [double]$stream.width
  $srcH = [double]$stream.height
  $srcDuration = [double]$fmt.duration
  $srcBitrate = if ([double]$stream.bit_rate -gt 0) { [double]$stream.bit_rate } else { [double]$fmt.bit_rate }
  if ($srcBitrate -le 0) { $srcBitrate = 3500000 }

  $fpsParts = $stream.avg_frame_rate -split "/"
  $srcFps = if ($fpsParts.Count -eq 2 -and [double]$fpsParts[1] -ne 0) { [double]$fpsParts[0] / [double]$fpsParts[1] } else { 24 }
  if ($srcFps -lt 10) { $srcFps = 24 }

  $aspect = $srcW / $srcH
  $bppf = $srcBitrate / ($srcW * $srcH * [math]::Max($srcFps, 1))

  $targetFps = if ($srcFps -ge 30) { 30 } elseif ($srcFps -ge 24) { 24 } else { [math]::Round($srcFps) }
  $targetWidth = if ($aspect -ge 1.3) { 768 } elseif ($aspect -ge 0.9) { 720 } else { 640 }
  if ($srcW -lt $targetWidth) { $targetWidth = [int]$srcW }
  if ($targetWidth % 2 -ne 0) { $targetWidth-- }

  $targetCrf = if ($bppf -ge 0.15) { 27 } elseif ($bppf -ge 0.10) { 28 } elseif ($bppf -ge 0.07) { 29 } elseif ($bppf -ge 0.05) { 30 } else { 31 }
  $targetDuration = [math]::Min($MaxDurationSec, [math]::Max($MinDurationSec, [math]::Floor($srcDuration * $DurationRatio)))
  $posterSecond = [math]::Min(1.5, [math]::Max(0.8, $targetDuration * 0.2))

  $previewFilter = "fps=$targetFps,scale='min($targetWidth,iw)':-2:flags=lanczos,format=yuv420p"
  $posterFilter = "scale='min($targetWidth,iw)':-2:flags=lanczos"

  & $ffmpeg -y -hide_banner -loglevel error -ss 0.35 -i $src -t $targetDuration -an -vf $previewFilter -c:v libx264 -preset veryfast -crf $targetCrf -movflags +faststart $mp4

  $posterSaved = $false
  try {
    $encodedUrl = [System.Uri]::EscapeDataString($item.href)
    $oembed = Invoke-RestMethod -Uri "https://vimeo.com/api/oembed.json?url=$encodedUrl&width=1280" -TimeoutSec 30
    if ($oembed.thumbnail_url) {
      $posterRaw = "assets/previews/posters/$($item.slug).tmp.jpg"
      Invoke-WebRequest -Uri $oembed.thumbnail_url -OutFile $posterRaw -TimeoutSec 30
      & $ffmpeg -y -hide_banner -loglevel error -i $posterRaw -vf $posterFilter -c:v libwebp -q:v 76 $poster
      Remove-Item $posterRaw -ErrorAction SilentlyContinue
      $posterSaved = $true
    }
  } catch {
    $posterSaved = $false
  }

  if (-not $posterSaved) {
    & $ffmpeg -y -hide_banner -loglevel error -ss $posterSecond -i $src -frames:v 1 -vf $posterFilter -c:v libwebp -q:v 76 $poster
  }

  $outJson = & $ffprobe -v error -select_streams v:0 -show_entries stream=width,height,avg_frame_rate -show_entries format=duration,size,bit_rate -of json $mp4
  $outObj = $outJson | ConvertFrom-Json
  $outStream = $outObj.streams[0]
  $outFmt = $outObj.format

  $sourceReport += [pscustomobject]@{
    slug = $item.slug
    src_w = [int]$srcW
    src_h = [int]$srcH
    src_fps = [math]::Round($srcFps, 2)
    src_duration_s = [math]::Round($srcDuration, 2)
    src_bitrate_kbps = [math]::Round($srcBitrate / 1000, 1)
    src_size_kb = [math]::Round(([double]$fmt.size) / 1kb, 1)
    src_bppf = [math]::Round($bppf, 4)
  }

  $adaptiveReport += [pscustomobject]@{
    slug = $item.slug
    chosen_width = $targetWidth
    chosen_fps = $targetFps
    chosen_crf = $targetCrf
    chosen_duration_s = $targetDuration
    out_w = [int]$outStream.width
    out_h = [int]$outStream.height
    out_duration_s = [math]::Round([double]$outFmt.duration, 2)
    out_bitrate_kbps = [math]::Round(([double]$outFmt.bit_rate) / 1000, 1)
    out_size_kb = [math]::Round(([double]$outFmt.size) / 1kb, 1)
  }
}

$sourceReport | Sort-Object slug | Export-Csv -NoTypeInformation -Encoding UTF8 "assets/previews/source-ffprobe-report.csv"
$adaptiveReport | Sort-Object slug | Export-Csv -NoTypeInformation -Encoding UTF8 "assets/previews/ffprobe-adaptive-report.csv"

if (-not $KeepSource) {
  Remove-Item -Recurse -Force "assets/previews/src" -ErrorAction SilentlyContinue
}

Write-Host "Done. Reports: assets/previews/source-ffprobe-report.csv and assets/previews/ffprobe-adaptive-report.csv"
