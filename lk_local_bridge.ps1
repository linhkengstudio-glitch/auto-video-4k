[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
$ErrorActionPreference = "SilentlyContinue"
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

# 1. Tat triet de tien trinh lk_local_bridge cu qua WMI Win32_Process
try {
    Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object {
        $_.ProcessId -ne $PID -and $_.Name -match "powershell" -and $_.CommandLine -match "lk_local_bridge"
    } | ForEach-Object {
        Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
    }
    Start-Sleep -Milliseconds 200
} catch {}

# 2. Lang nghe tren ca 127.0.0.1:48930 va localhost:48930 ngay lap tuc
$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://127.0.0.1:48930/")
$listener.Prefixes.Add("http://localhost:48930/")
try {
    $listener.Start()
} catch {
    $listener = New-Object System.Net.HttpListener
    $listener.Prefixes.Add("http://localhost:48930/")
    try { $listener.Start() } catch { exit }
}

# 3. Tai san yt-dlp.exe o hau canh ngay khi vua bat phan mem (trong luc nguoi dung dang chon file Word & Audio)
$binDirInit = Join-Path $env:LOCALAPPDATA "LunKengAutoVideo4K\bin"
New-Item -ItemType Directory -Path $binDirInit -Force | Out-Null
$ytExeInit = Join-Path $binDirInit "yt-dlp.exe"
if (-not (Test-Path -LiteralPath $ytExeInit) -or (Get-Item -LiteralPath $ytExeInit).Length -lt 1000000) {
    Start-Process -FilePath "curl.exe" -ArgumentList "-L -f -s --max-time 30 `"https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp.exe`" -o `"$ytExeInit`"" -WindowStyle Hidden
}

function Show-TopMostFolderDialog($desc) {
    $topForm = New-Object System.Windows.Forms.Form
    $topForm.TopMost = $true
    $topForm.StartPosition = "CenterScreen"
    $topForm.Width = 1
    $topForm.Height = 1
    $topForm.ShowInTaskbar = $false
    $topForm.FormBorderStyle = "None"
    $topForm.Opacity = 0.01
    $topForm.Show()
    $topForm.Activate()

    $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
    $dlg.Description = $desc
    $dlg.ShowNewFolderButton = $true
    $res = $dlg.ShowDialog($topForm)
    $selected = ""
    if ($res -eq [System.Windows.Forms.DialogResult]::OK -and $dlg.SelectedPath) {
        $selected = $dlg.SelectedPath
    }
    $topForm.Close()
    $topForm.Dispose()
    return $selected
}

while ($listener.IsListening) {
    try {
        $context = $listener.GetContext()
        $req = $context.Request
        $res = $context.Response
        $res.Headers.Add("Access-Control-Allow-Origin", "*")
        $res.Headers.Add("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        $res.Headers.Add("Access-Control-Allow-Headers", "*")
        $res.Headers.Add("Access-Control-Allow-Private-Network", "true")

        if ($req.HttpMethod -eq "OPTIONS") {
            $res.StatusCode = 200
            $res.Close()
            continue
        }

        $path = $req.Url.AbsolutePath

        if ($path -eq "/app" -or $path -eq "/") {
            $htmlFile = Join-Path $env:LOCALAPPDATA "LunKengAutoVideo4K\auto_video_editor.html"
            if (Test-Path -LiteralPath $htmlFile) {
                $htmlBytes = [System.IO.File]::ReadAllBytes($htmlFile)
                $res.ContentType = "text/html; charset=utf-8"
                $res.ContentLength64 = $htmlBytes.Length
                $res.OutputStream.Write($htmlBytes, 0, $htmlBytes.Length)
                $res.Close()
                continue
            }
        }

        if ($path -eq "/bridge-alive.js") {
            $jsBytes = [System.Text.Encoding]::UTF8.GetBytes("if (window.__LK_BRIDGE_READY_CALLBACK__) window.__LK_BRIDGE_READY_CALLBACK__();")
            $res.ContentType = "application/javascript; charset=utf-8"
            $res.OutputStream.Write($jsBytes, 0, $jsBytes.Length)
            $res.Close()
            continue
        }

        if ($path -eq "/memory-vault") {
            $vaultPath = Join-Path $env:LOCALAPPDATA "LunKengAutoVideo4K\system_memory_vault.json"
            if ($req.HttpMethod -eq "POST") {
                $sr = New-Object System.IO.StreamReader($req.InputStream, [System.Text.Encoding]::UTF8)
                $bodyStr = $sr.ReadToEnd()
                $sr.Close()
                if (-not [string]::IsNullOrWhiteSpace($bodyStr)) {
                    [System.IO.File]::WriteAllText($vaultPath, $bodyStr, [System.Text.Encoding]::UTF8)
                }
                $buf = [System.Text.Encoding]::UTF8.GetBytes('{"ok":true}')
                $res.ContentType = "application/json; charset=utf-8"
                $res.OutputStream.Write($buf, 0, $buf.Length)
                $res.Close()
                continue
            } else {
                if (Test-Path -LiteralPath $vaultPath) {
                    $jsonBytes = [System.IO.File]::ReadAllBytes($vaultPath)
                    $res.ContentType = "application/json; charset=utf-8"
                    $res.OutputStream.Write($jsonBytes, 0, $jsonBytes.Length)
                    $res.Close()
                    continue
                } else {
                    $buf = [System.Text.Encoding]::UTF8.GetBytes('{"usedClipIds":{},"videoHistory":[]}')
                    $res.ContentType = "application/json; charset=utf-8"
                    $res.OutputStream.Write($buf, 0, $buf.Length)
                    $res.Close()
                    continue
                }
            }
        }

        if ($path -eq "/ping") {
            $buf = [System.Text.Encoding]::UTF8.GetBytes('{"ok":true,"version":"5.6.0","port":48930}')
            $res.ContentType = "application/json; charset=utf-8"
            $res.OutputStream.Write($buf, 0, $buf.Length)
            $res.Close()
            continue
        }

        if ($path -eq "/pick-folder") {
            $chosen = Show-TopMostFolderDialog "Chon thu muc luu Video 4K xuat ra (LK_Auto_Edit_Video):"
            if (-not [string]::IsNullOrWhiteSpace($chosen)) {
                $escaped = $chosen.Replace('\', '\\').Replace('"', '\"')
                $json = '{"ok":true,"path":"' + $escaped + '"}'
            } else {
                $json = '{"ok":false,"cancelled":true}'
            }
            $buf = [System.Text.Encoding]::UTF8.GetBytes($json)
            $res.ContentType = "application/json; charset=utf-8"
            $res.OutputStream.Write($buf, 0, $buf.Length)
            $res.Close()
            continue
        }

        if ($path -eq "/pick-stock-folder") {
            $chosen = Show-TopMostFolderDialog "Chon thu muc chua cac file suoc Video (.mp4 / .webm / .mov) tren may tinh:"
            if (-not [string]::IsNullOrWhiteSpace($chosen) -and (Test-Path -LiteralPath $chosen)) {
                $vidFiles = Get-ChildItem -LiteralPath $chosen -File -Recurse -Include *.mp4,*.webm,*.mov,*.mkv | Select-Object -First 300
                $arr = @()
                foreach ($vf in $vidFiles) {
                    $arr += ('"' + $vf.FullName.Replace('\', '\\').Replace('"', '\"') + '"')
                }
                $json = '{"ok":true,"folder":"' + $chosen.Replace('\', '\\').Replace('"', '\"') + '","files":[' + ($arr -join ',') + ']}'
            } else {
                $json = '{"ok":false,"cancelled":true}'
            }
            $buf = [System.Text.Encoding]::UTF8.GetBytes($json)
            $res.ContentType = "application/json; charset=utf-8"
            $res.OutputStream.Write($buf, 0, $buf.Length)
            $res.Close()
            continue
        }

        if ($path -eq "/save-video" -and $req.HttpMethod -eq "POST") {
            $qFolder = [System.Uri]::UnescapeDataString(($req.QueryString["folder"] + ""))
            $qFile = [System.Uri]::UnescapeDataString(($req.QueryString["filename"] + ""))
            if ([string]::IsNullOrWhiteSpace($qFile)) {
                $qFile = "Video_4K_Output.mp4"
            }
            if ([string]::IsNullOrWhiteSpace($qFolder)) {
                $qFolder = Join-Path $env:USERPROFILE "Downloads"
            }
            if (-not (Test-Path -LiteralPath $qFolder)) {
                try { New-Item -ItemType Directory -Path $qFolder -Force | Out-Null } catch {
                    $qFolder = Join-Path $env:USERPROFILE "Downloads"
                }
            }
            if ($qFile -match '\.webm$') {
                $qFile = ($qFile -replace '\.webm$', '.mp4')
            } elseif ($qFile -notmatch '\.mp4$') {
                $qFile = $qFile + ".mp4"
            }
            $fullOutPath = Join-Path $qFolder $qFile
            $tmpStreamFile = $fullOutPath + ".part"
            $fs = [System.IO.File]::Create($tmpStreamFile)
            $req.InputStream.CopyTo($fs)
            $fs.Flush()
            $fs.Close()

            $headerBytes = New-Object byte[] 4
            $fsRead = [System.IO.File]::OpenRead($tmpStreamFile)
            $readCount = $fsRead.Read($headerBytes, 0, 4)
            $fsRead.Close()

            $ffCmd = Get-Command ffmpeg -ErrorAction SilentlyContinue
            if ($null -ne $ffCmd -and $readCount -ge 2 -and $headerBytes[0] -eq 0x1A -and $headerBytes[1] -eq 0x45) {
                Start-Process -FilePath "ffmpeg" -ArgumentList "-y -i `"$tmpStreamFile`" -c:v libx264 -preset ultrafast -crf 23 -c:a aac `"$fullOutPath`"" -WindowStyle Hidden -Wait
                Remove-Item -LiteralPath $tmpStreamFile -Force -ErrorAction SilentlyContinue
                if (-not (Test-Path -LiteralPath $fullOutPath)) {
                    Move-Item -LiteralPath $tmpStreamFile -Destination $fullOutPath -Force -ErrorAction SilentlyContinue
                }
            } else {
                Move-Item -LiteralPath $tmpStreamFile -Destination $fullOutPath -Force
            }

            $escapedOut = $fullOutPath.Replace('\', '\\').Replace('"', '\"')
            $json = '{"ok":true,"savedPath":"' + $escapedOut + '"}'
            $buf = [System.Text.Encoding]::UTF8.GetBytes($json)
            $res.ContentType = "application/json; charset=utf-8"
            $res.OutputStream.Write($buf, 0, $buf.Length)
            $res.Close()
            continue
        }

        if ($path -eq "/fetch-online-videos") {
            $theme = [System.Uri]::UnescapeDataString(($req.QueryString["theme"] + ""))
            if ([string]::IsNullOrWhiteSpace($theme)) { $theme = "nature" }
            $cacheDir = Join-Path $env:LOCALAPPDATA "LunKengAutoVideo4K\CineFetchCache_v56\$theme"
            $binDir = Join-Path $env:LOCALAPPDATA "LunKengAutoVideo4K\bin"
            New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null
            New-Item -ItemType Directory -Path $binDir -Force | Out-Null

            # Cac cum tu khoa B-Roll quay that (khop phong cach kenh The Chosen Flame: canh rung suong som, thac nuoc, may troi, song bien, nui non hung vi)
            $ytMap = @{
                "nature"     = @("cinematic forest mist drone b-roll no copyright", "waterfall river nature stock footage 4k no copyright", "mountain clouds sunset aerial drone b-roll")
                "ocean"      = @("cinematic ocean waves aerial drone b-roll no copyright", "sunset beach sea waves stock footage no copyright", "coastline cliff waves drone b-roll")
                "street"     = @("cinematic city night street rain b-roll no copyright", "urban highway traffic night timelapse stock footage", "downtown skyline night aerial b-roll")
                "space"      = @("galaxy stars milky way timelapse stock footage", "aurora borealis night sky b-roll no copyright", "deep space nebula stars stock video")
                "meditation" = @("calm zen river forest morning mist b-roll", "peaceful waterfall sunlight trees stock footage", "golden hour mountain lake aerial b-roll")
                "luxury"     = @("luxury city skyline sunset aerial drone b-roll", "modern architecture yacht coast aerial stock footage", "penthouse skyline view b-roll")
                "ancient"    = @("ancient temple mountain mist aerial drone b-roll", "historic castle ruins dramatic sky stock footage", "ancient cathedral light rays b-roll")
                "battle"     = @("dramatic storm clouds lightning timelapse b-roll", "dark cinematic clouds mountain storm stock footage", "fire embers dramatic sky b-roll")
                "scifi"      = @("futuristic cyberpunk neon lights b-roll", "aurora borealis cosmic sky timelapse stock footage", "digital abstract light tunnel b-roll")
                "horror"     = @("dark misty forest fog cinematic b-roll", "spooky night woods moonlight stock footage", "abandoned dark ruins mist b-roll")
                "romance"    = @("golden sunset meadow flowers cinematic b-roll", "beach sunset waves golden hour stock footage", "autumn leaves sunlight forest b-roll")
                "history"    = @("ancient monument castle aerial drone b-roll", "historic architecture ruins stock footage", "old library candlelight cinematic b-roll")
            }
            $queries = if ($ytMap[$theme]) { $ytMap[$theme] } else { $ytMap["nature"] }

            $existing = @(Get-ChildItem -LiteralPath $cacheDir -File -ErrorAction SilentlyContinue | Where-Object { $_.Length -gt 100000 -and ($_.Extension -eq ".mp4" -or $_.Extension -eq ".webm") })

            if ($existing.Count -lt 6) {
                # 1. Dam bao co yt-dlp.exe trong $binDir
                $ytDlpExe = Join-Path $binDir "yt-dlp.exe"
                if (-not (Test-Path -LiteralPath $ytDlpExe) -or (Get-Item -LiteralPath $ytDlpExe).Length -lt 1000000) {
                    $cmdYt = Get-Command yt-dlp -ErrorAction SilentlyContinue
                    if ($null -ne $cmdYt) {
                        $ytDlpExe = $cmdYt.Source
                    } else {
                        Start-Process -FilePath "curl.exe" -ArgumentList "-L -f -s --max-time 25 `"https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp.exe`" -o `"$ytDlpExe`"" -WindowStyle Hidden -Wait
                    }
                }

                # 2. Quet danh sach videoId YouTube voi gioi han do dai Video nguon TOI DA 30 PHUT (15s <= duration <= 1800s)!
                $vidIds = @()
                $seenVid = @{}
                foreach ($qStr in $queries) {
                    $encQ = [System.Uri]::EscapeDataString($qStr)
                    # Quet ca video ngan & video trung binh/dai (toi da 30 phut = 1800 giay)
                    foreach ($spFilter in @("EgIQAQ%3D%3D", "EgQQARgD", "EgQQARgB")) {
                        $searchUrl = "https://www.youtube.com/results?search_query=$encQ&sp=$spFilter"
                        $htmlTmp = Join-Path $cacheDir "yt_search.html"
                        Remove-Item -LiteralPath $htmlTmp -Force -ErrorAction SilentlyContinue
                        Start-Process -FilePath "curl.exe" -ArgumentList "-L -s -A `"Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36`" --max-time 7 `"$searchUrl`" -o `"$htmlTmp`"" -WindowStyle Hidden -Wait
                        if (Test-Path -LiteralPath $htmlTmp) {
                            $rawHtml = [System.IO.File]::ReadAllText($htmlTmp, [System.Text.Encoding]::UTF8)
                            Remove-Item -LiteralPath $htmlTmp -Force -ErrorAction SilentlyContinue
                            $vrMatches = [regex]::Matches($rawHtml, '"videoRenderer":\{"videoId":"([a-zA-Z0-9_-]{11})".*?"lengthText":\{[^}]*?"simpleText":"([0-9:]+)"')
                            $takenFromQ = 0
                            foreach ($m in $vrMatches) {
                                $vId = $m.Groups[1].Value
                                $timeStr = $m.Groups[2].Value
                                $parts = $timeStr -split ':'
                                $durSec = 0
                                if ($parts.Count -eq 2) {
                                    $durSec = ([int]$parts[0] * 60) + [int]$parts[1]
                                } elseif ($parts.Count -eq 3) {
                                    $durSec = ([int]$parts[0] * 3600) + ([int]$parts[1] * 60) + [int]$parts[2]
                                }
                                # RANG BUOC CHINH XAC: Chi lay Video nguon co do dai tu 15 giay den TOI DA 30 PHUT (<= 1800 giay)!
                                if ($durSec -ge 15 -and $durSec -le 1800 -and (-not $seenVid.ContainsKey($vId))) {
                                    $seenVid[$vId] = $true
                                    $vidIds += $vId
                                    $takenFromQ++
                                    if ($takenFromQ -ge 3) { break }
                                }
                            }
                        }
                        if ($vidIds.Count -ge 9) { break }
                    }
                    if ($vidIds.Count -ge 9) { break }
                }

                # 3. Chay song song cac tien trinh yt-dlp.exe voi --match-filter "duration >= 15 & duration <= 1800" (toi da 30 phut) & --max-filesize 350M!
                if ((Test-Path -LiteralPath $ytDlpExe) -and $vidIds.Count -gt 0) {
                    $procs = @()
                    $countStarted = 0
                    foreach ($vId in $vidIds) {
                        if ($countStarted -ge 7) { break }
                        $existingVid = Get-ChildItem -LiteralPath $cacheDir -Filter ("yt_" + $vId + ".*") -File -ErrorAction SilentlyContinue | Where-Object { $_.Length -gt 100000 }
                        if ($null -eq $existingVid -or $existingVid.Count -eq 0) {
                            $outTpl = Join-Path $cacheDir ("yt_" + $vId + ".%(ext)s")
                            $p = Start-Process -FilePath $ytDlpExe -ArgumentList "`"https://www.youtube.com/watch?v=$vId`" -f `"18/b[height<=720][ext=mp4]/b[ext=mp4]/b`" --match-filter `"duration >= 15 & duration <= 1800`" --max-filesize 350M --no-playlist --no-part --no-warnings -o `"$outTpl`"" -WindowStyle Hidden -PassThru
                            $procs += $p
                            $countStarted++
                        }
                    }
                    $tStart = [DateTime]::UtcNow
                    while (([DateTime]::UtcNow - $tStart).TotalMilliseconds -lt 26000) {
                        $readyFiles = @(Get-ChildItem -LiteralPath $cacheDir -File -ErrorAction SilentlyContinue | Where-Object { $_.Length -gt 100000 -and ($_.Extension -eq ".mp4" -or $_.Extension -eq ".webm") })
                        if ($readyFiles.Count -ge 6) { break }
                        $stillRunning = @($procs | Where-Object { -not $_.HasExited })
                        if ($stillRunning.Count -eq 0) { break }
                        Start-Sleep -Milliseconds 500
                    }
                }
            }

            $cachedFiles = @(Get-ChildItem -LiteralPath $cacheDir -File -ErrorAction SilentlyContinue | Where-Object { $_.Length -gt 100000 -and ($_.Extension -eq ".mp4" -or $_.Extension -eq ".webm") })
            $urlsArr = @()
            foreach ($cf in $cachedFiles) {
                $encPath = [System.Uri]::EscapeDataString($cf.FullName)
                $urlsArr += ('"http://127.0.0.1:48930/stock-cache?path=' + $encPath + '"')
            }
            $json = '{"ok":true,"urls":[' + ($urlsArr -join ',') + ']}'
            $buf = [System.Text.Encoding]::UTF8.GetBytes($json)
            $res.ContentType = "application/json; charset=utf-8"
            $res.OutputStream.Write($buf, 0, $buf.Length)
            $res.Close()
            continue
        }

        if ($path -eq "/proxy-video") {
            $remoteUrl = [System.Uri]::UnescapeDataString(($req.QueryString["url"] + ""))
            $theme = [System.Uri]::UnescapeDataString(($req.QueryString["theme"] + ""))
            if ([string]::IsNullOrWhiteSpace($theme)) { $theme = "nature" }
            if (-not [string]::IsNullOrWhiteSpace($remoteUrl) -and $remoteUrl -match "^https?://") {
                $cacheDir = Join-Path $env:LOCALAPPDATA "LunKengAutoVideo4K\CineFetchCache_v56\$theme"
                New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null

                $md5 = [System.Security.Cryptography.MD5]::Create()
                $hashBytes = $md5.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($remoteUrl))
                $hashHex = ([System.BitConverter]::ToString($hashBytes) -replace '-', '').Substring(0, 16).ToLower()
                $ext = if ($remoteUrl -match "\.mp4(\?|$)") { ".mp4" } else { ".webm" }
                $localFile = Join-Path $cacheDir ("proxy_" + $hashHex + $ext)
                $tmpFile = $localFile + ".tmp"

                if (-not (Test-Path -LiteralPath $localFile) -or (Get-Item -LiteralPath $localFile).Length -lt 50000) {
                    $p = Start-Process -FilePath "curl.exe" -ArgumentList "-L -f -s --max-time 12 `"$remoteUrl`" -o `"$tmpFile`"" -WindowStyle Hidden -Wait -PassThru
                    if ($p.ExitCode -eq 0 -and (Test-Path -LiteralPath $tmpFile) -and (Get-Item -LiteralPath $tmpFile).Length -gt 50000) {
                        Move-Item -LiteralPath $tmpFile -Destination $localFile -Force
                    } else {
                        Remove-Item -LiteralPath $tmpFile -Force -ErrorAction SilentlyContinue
                    }
                }

                if (Test-Path -LiteralPath $localFile) {
                    $fileInfo = Get-Item -LiteralPath $localFile
                    $totalLen = $fileInfo.Length
                    $res.ContentType = if ($localFile -match "\.mp4$") { "video/mp4" } else { "video/webm" }
                    $res.Headers.Add("Accept-Ranges", "bytes")

                    $rangeHeader = $req.Headers["Range"]
                    $fs = [System.IO.File]::Open($localFile, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
                    try {
                        if (-not [string]::IsNullOrWhiteSpace($rangeHeader) -and $rangeHeader -match "bytes=(\d+)-(\d*)") {
                            $start = [int64]$Matches[1]
                            $end = if (-not [string]::IsNullOrWhiteSpace($Matches[2])) { [int64]$Matches[2] } else { $totalLen - 1 }
                            if ($end -ge $totalLen) { $end = $totalLen - 1 }
                            $chunkLen = ($end - $start) + 1
                            $res.StatusCode = 206
                            $res.Headers.Add("Content-Range", "bytes $start-$end/$totalLen")
                            $res.ContentLength64 = $chunkLen
                            $fs.Seek($start, [System.IO.SeekOrigin]::Begin) | Out-Null
                            $buf = New-Object byte[] 65536
                            $rem = $chunkLen
                            while ($rem -gt 0) {
                                $toRead = [Math]::Min($buf.Length, $rem)
                                $read = $fs.Read($buf, 0, $toRead)
                                if ($read -le 0) { break }
                                $res.OutputStream.Write($buf, 0, $read)
                                $rem -= $read
                            }
                        } else {
                            $res.StatusCode = 200
                            $res.ContentLength64 = $totalLen
                            $fs.CopyTo($res.OutputStream)
                        }
                    } finally {
                        $fs.Close()
                    }
                    $res.Close()
                    continue
                }
            }
            $res.StatusCode = 404
            $res.Close()
            continue
        }

        if ($path -eq "/stock-cache") {
            $fPath = [System.Uri]::UnescapeDataString(($req.QueryString["path"] + ""))
            if (-not [string]::IsNullOrWhiteSpace($fPath) -and (Test-Path -LiteralPath $fPath)) {
                $fileInfo = Get-Item -LiteralPath $fPath
                $totalLen = $fileInfo.Length
                $res.ContentType = if ($fPath -match "\.mp4$") { "video/mp4" } else { "video/webm" }
                $res.Headers.Add("Accept-Ranges", "bytes")

                $rangeHeader = $req.Headers["Range"]
                $fs = [System.IO.File]::Open($fPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
                try {
                    if (-not [string]::IsNullOrWhiteSpace($rangeHeader) -and $rangeHeader -match "bytes=(\d+)-(\d*)") {
                        $start = [int64]$Matches[1]
                        $end = if (-not [string]::IsNullOrWhiteSpace($Matches[2])) { [int64]$Matches[2] } else { $totalLen - 1 }
                        if ($end -ge $totalLen) { $end = $totalLen - 1 }
                        $chunkLen = ($end - $start) + 1
                        $res.StatusCode = 206
                        $res.Headers.Add("Content-Range", "bytes $start-$end/$totalLen")
                        $res.ContentLength64 = $chunkLen
                        $fs.Seek($start, [System.IO.SeekOrigin]::Begin) | Out-Null
                        $buf = New-Object byte[] 65536
                        $rem = $chunkLen
                        while ($rem -gt 0) {
                            $toRead = [Math]::Min($buf.Length, $rem)
                            $read = $fs.Read($buf, 0, $toRead)
                            if ($read -le 0) { break }
                            $res.OutputStream.Write($buf, 0, $read)
                            $rem -= $read
                        }
                    } else {
                        $res.StatusCode = 200
                        $res.ContentLength64 = $totalLen
                        $fs.CopyTo($res.OutputStream)
                    }
                } finally {
                    $fs.Close()
                }
                $res.Close()
                continue
            }
            $res.StatusCode = 404
            $res.Close()
            continue
        }

        $res.StatusCode = 404
        $res.Close()
    } catch {
        try { $context.Response.Close() } catch {}
    }
}
