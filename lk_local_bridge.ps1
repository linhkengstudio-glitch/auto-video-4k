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

# 2. Chi dang ky http://localhost:48930/ de Windows http.sys cho phep user thuong (khong can quyen Admin) va khong bao gio bi loi HTTP 400 Invalid Hostname!
$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://localhost:48930/")
try {
    $listener.Start()
} catch {
    exit
}

# 3. Tai san yt-dlp.exe o hau canh ngay khi vua bat phan mem
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
            $buf = [System.Text.Encoding]::UTF8.GetBytes('{"ok":true,"version":"5.7.0","port":48930}')
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
            $cacheDir = Join-Path $env:LOCALAPPDATA "LunKengAutoVideo4K\CineFetchCache_v57\$theme"
            $binDir = Join-Path $env:LOCALAPPDATA "LunKengAutoVideo4K\bin"
            New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null
            New-Item -ItemType Directory -Path $binDir -Force | Out-Null

            $mixkitTagMap = @{
                "nature"     = @("nature", "forest", "waterfall")
                "ocean"      = @("sea", "beach", "water")
                "street"     = @("city", "street", "traffic")
                "space"      = @("space", "night", "sky")
                "meditation" = @("forest", "water", "sunset")
                "luxury"     = @("city", "luxury", "sunset")
                "ancient"    = @("mountain", "forest", "sky")
                "battle"     = @("fire", "storm", "smoke")
                "scifi"      = @("space", "abstract", "light")
                "horror"     = @("night", "smoke", "forest")
                "romance"    = @("sunset", "flower", "beach")
                "history"    = @("mountain", "clouds", "sunset")
            }
            $ytMap = @{
                "nature"     = @("cinematic forest mist drone b-roll no copyright", "waterfall river nature stock footage 4k no copyright")
                "ocean"      = @("cinematic ocean waves aerial drone b-roll no copyright", "sunset beach sea waves stock footage no copyright")
                "street"     = @("cinematic city night street rain b-roll no copyright", "urban highway traffic night timelapse stock footage")
                "space"      = @("galaxy stars milky way timelapse stock footage", "aurora borealis night sky b-roll no copyright")
                "meditation" = @("calm zen river forest morning mist b-roll", "peaceful waterfall sunlight trees stock footage")
                "luxury"     = @("luxury city skyline sunset aerial drone b-roll", "modern architecture yacht coast aerial stock footage")
                "ancient"    = @("ancient temple mountain mist aerial drone b-roll", "historic castle ruins dramatic sky stock footage")
                "battle"     = @("dramatic storm clouds lightning timelapse b-roll", "dark cinematic clouds mountain storm stock footage")
                "scifi"      = @("futuristic cyberpunk neon lights b-roll", "aurora borealis cosmic sky timelapse stock footage")
                "horror"     = @("dark misty forest fog cinematic b-roll", "spooky night woods moonlight stock footage")
                "romance"    = @("golden sunset meadow flowers cinematic b-roll", "beach sunset waves golden hour stock footage")
                "history"    = @("ancient monument castle aerial drone b-roll", "historic architecture ruins stock footage")
            }
            $mkTags = if ($mixkitTagMap[$theme]) { $mixkitTagMap[$theme] } else { $mixkitTagMap["nature"] }
            $queries = if ($ytMap[$theme]) { $ytMap[$theme] } else { $ytMap["nature"] }

            $existing = @(Get-ChildItem -LiteralPath $cacheDir -File -ErrorAction SilentlyContinue | Where-Object { $_.Length -gt 80000 -and ($_.Extension -eq ".mp4" -or $_.Extension -eq ".webm") })

            if ($existing.Count -lt 8) {
                $dlProcs = @()
                $dlTargets = @()

                # ENGINE 1: Mixkit by Envato (assets.mixkit.co/videos/{ID}/{ID}-720.mp4) - Tai truc tiep .MP4 HD bang curl.exe trong 2 giay, khong can API key, khong bi chan tai Viet Nam!
                $mkIds = @()
                $seenMk = @{}
                foreach ($tag in $mkTags) {
                    $mkHtmlTmp = Join-Path $cacheDir ("mk_" + $tag + ".html")
                    Remove-Item -LiteralPath $mkHtmlTmp -Force -ErrorAction SilentlyContinue
                    Start-Process -FilePath "curl.exe" -ArgumentList "-L -s -A `"Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/126.0.0.0 Safari/537.36`" --max-time 6 `"https://mixkit.co/free-stock-video/$tag/`" -o `"$mkHtmlTmp`"" -WindowStyle Hidden -Wait
                    if (Test-Path -LiteralPath $mkHtmlTmp) {
                        $mkHtml = [System.IO.File]::ReadAllText($mkHtmlTmp, [System.Text.Encoding]::UTF8)
                        Remove-Item -LiteralPath $mkHtmlTmp -Force -ErrorAction SilentlyContinue
                        $mIds = [regex]::Matches($mkHtml, '(?:assets\.mixkit\.co/videos/|/free-stock-video/[a-z0-9-]+-)(\d{3,7})(?:/|-)')
                        $cTag = 0
                        foreach ($m in $mIds) {
                            $idVal = $m.Groups[1].Value
                            if (-not $seenMk.ContainsKey($idVal)) {
                                $seenMk[$idVal] = $true
                                $mkIds += $idVal
                                $cTag++
                                if ($cTag -ge 5) { break }
                            }
                        }
                    }
                    if ($mkIds.Count -ge 10) { break }
                }

                # Bo sung danh sach ID Mixkit da xac thuc tren CDN assets.mixkit.co phong khi mang cham
                foreach ($fallbackId in @("2213", "41576", "42648", "2385", "35889", "4701", "1038", "4661", "30012", "4547", "4855", "4830", "40248")) {
                    if (-not $seenMk.ContainsKey($fallbackId)) {
                        $seenMk[$fallbackId] = $true
                        $mkIds += $fallbackId
                    }
                }

                $mkStarted = 0
                foreach ($mId in $mkIds) {
                    if ($mkStarted -ge 8) { break }
                    $outMk = Join-Path $cacheDir ("envato_mixkit_" + $mId + ".mp4")
                    $tmpMk = $outMk + ".tmp"
                    if (-not (Test-Path -LiteralPath $outMk) -or (Get-Item -LiteralPath $outMk).Length -lt 80000) {
                        $mkUrl = "https://assets.mixkit.co/videos/$mId/$mId-720.mp4"
                        $pMk = Start-Process -FilePath "curl.exe" -ArgumentList "-L -f -s --max-time 12 `"$mkUrl`" -o `"$tmpMk`"" -WindowStyle Hidden -PassThru
                        $dlProcs += $pMk
                        $dlTargets += @{ tmp = $tmpMk; final = $outMk }
                        $mkStarted++
                    }
                }

                # ENGINE 2: YouTube (yt-dlp.exe voi bo loc do dai Video nguon TOI DA 30 PHUT: 15s <= duration <= 1800s!)
                $ytDlpExe = Join-Path $binDir "yt-dlp.exe"
                if (-not (Test-Path -LiteralPath $ytDlpExe) -or (Get-Item -LiteralPath $ytDlpExe).Length -lt 1000000) {
                    $cmdYt = Get-Command yt-dlp -ErrorAction SilentlyContinue
                    if ($null -ne $cmdYt) {
                        $ytDlpExe = $cmdYt.Source
                    }
                }

                $vidIds = @()
                $seenVid = @{}
                foreach ($qStr in $queries) {
                    $encQ = [System.Uri]::EscapeDataString($qStr)
                    foreach ($spFilter in @("EgIQAQ%3D%3D", "EgQQARgD")) {
                        $searchUrl = "https://www.youtube.com/results?search_query=$encQ&sp=$spFilter"
                        $htmlTmp = Join-Path $cacheDir "yt_search.html"
                        Remove-Item -LiteralPath $htmlTmp -Force -ErrorAction SilentlyContinue
                        Start-Process -FilePath "curl.exe" -ArgumentList "-L -s -A `"Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/126.0.0.0 Safari/537.36`" --max-time 6 `"$searchUrl`" -o `"$htmlTmp`"" -WindowStyle Hidden -Wait
                        if (Test-Path -LiteralPath $htmlTmp) {
                            $rawHtml = [System.IO.File]::ReadAllText($htmlTmp, [System.Text.Encoding]::UTF8)
                            Remove-Item -LiteralPath $htmlTmp -Force -ErrorAction SilentlyContinue
                            # Tach tung khoi videoRenderer (khong bi loi ngoac nhon long nhau cua accessibilityData!)
                            $chunks = $rawHtml -split '"videoRenderer":\{"videoId":"'
                            $takenFromQ = 0
                            for ($cIdx = 1; $cIdx -lt $chunks.Count; $cIdx++) {
                                $chunk = $chunks[$cIdx]
                                if ($chunk.Length -lt 11) { continue }
                                $vId = $chunk.Substring(0, 11)
                                if ($vId -notmatch '^[a-zA-Z0-9_-]{11}$') { continue }
                                $subChunk = if ($chunk.Length -gt 3500) { $chunk.Substring(0, 3500) } else { $chunk }
                                $durMatch = [regex]::Match($subChunk, '"simpleText":"([0-9]+:[0-9:]+)"')
                                if ($durMatch.Success) {
                                    $parts = $durMatch.Groups[1].Value -split ':'
                                    $durSec = 0
                                    if ($parts.Count -eq 2) {
                                        $durSec = ([int]$parts[0] * 60) + [int]$parts[1]
                                    } elseif ($parts.Count -eq 3) {
                                        $durSec = ([int]$parts[0] * 3600) + ([int]$parts[1] * 60) + [int]$parts[2]
                                    }
                                    # RANG BUOC CHINH XAC: Video nguon tu 15 giay den TOI DA 30 PHUT (<= 1800 giay)!
                                    if ($durSec -ge 15 -and $durSec -le 1800 -and (-not $seenVid.ContainsKey($vId))) {
                                        $seenVid[$vId] = $true
                                        $vidIds += $vId
                                        $takenFromQ++
                                        if ($takenFromQ -ge 3) { break }
                                    }
                                }
                            }
                        }
                        if ($vidIds.Count -ge 6) { break }
                    }
                    if ($vidIds.Count -ge 6) { break }
                }

                if ((Test-Path -LiteralPath $ytDlpExe) -and $vidIds.Count -gt 0) {
                    $countStarted = 0
                    foreach ($vId in $vidIds) {
                        if ($countStarted -ge 4) { break }
                        $existingVid = Get-ChildItem -LiteralPath $cacheDir -Filter ("yt_" + $vId + ".*") -File -ErrorAction SilentlyContinue | Where-Object { $_.Length -gt 80000 }
                        if ($null -eq $existingVid -or $existingVid.Count -eq 0) {
                            $outTpl = Join-Path $cacheDir ("yt_" + $vId + ".%(ext)s")
                            $pYt = Start-Process -FilePath $ytDlpExe -ArgumentList "`"https://www.youtube.com/watch?v=$vId`" -f `"bv*[height<=720][ext=mp4]/b[height<=720][ext=mp4]/18/b`" --match-filter `"duration >= 15 & duration <= 1800`" --max-filesize 350M --no-playlist --no-part --no-warnings -o `"$outTpl`"" -WindowStyle Hidden -PassThru
                            $dlProcs += $pYt
                            $countStarted++
                        }
                    }
                }

                # Cho cac tien trinh tai song song (ngay khi du >= 6 video .mp4 la tra ve ngay!)
                $tStart = [DateTime]::UtcNow
                while (([DateTime]::UtcNow - $tStart).TotalMilliseconds -lt 18000) {
                    foreach ($t in $dlTargets) {
                        if ((Test-Path -LiteralPath $t.tmp) -and (Get-Item -LiteralPath $t.tmp).Length -gt 80000) {
                            Move-Item -LiteralPath $t.tmp -Destination $t.final -Force -ErrorAction SilentlyContinue
                        }
                    }
                    $readyNow = @(Get-ChildItem -LiteralPath $cacheDir -File -ErrorAction SilentlyContinue | Where-Object { $_.Length -gt 80000 -and ($_.Extension -eq ".mp4" -or $_.Extension -eq ".webm") })
                    if ($readyNow.Count -ge 6) { break }
                    $runningNow = @($dlProcs | Where-Object { -not $_.HasExited })
                    if ($runningNow.Count -eq 0) { break }
                    Start-Sleep -Milliseconds 400
                }
                foreach ($t in $dlTargets) {
                    if ((Test-Path -LiteralPath $t.tmp) -and (Get-Item -LiteralPath $t.tmp).Length -gt 80000) {
                        Move-Item -LiteralPath $t.tmp -Destination $t.final -Force -ErrorAction SilentlyContinue
                    }
                }
            }

            $cachedFiles = @(Get-ChildItem -LiteralPath $cacheDir -File -ErrorAction SilentlyContinue | Where-Object { $_.Length -gt 80000 -and ($_.Extension -eq ".mp4" -or $_.Extension -eq ".webm") })
            $urlsArr = @()
            foreach ($cf in $cachedFiles) {
                $encPath = [System.Uri]::EscapeDataString($cf.FullName)
                $urlsArr += ('"http://localhost:48930/stock-cache?path=' + $encPath + '"')
            }
            $json = '{"ok":true,"urls":[' + ($urlsArr -join ',') + ']}'
            $buf = [System.Text.Encoding]::UTF8.GetBytes($json)
            $res.ContentType = "application/json; charset=utf-8"
            $res.OutputStream.Write($buf, 0, $buf.Length)
            $res.Close()
            continue
        }

        if ($path -eq "/stock-cache") {
            $fPath = [System.Uri]::UnescapeDataString(($req.QueryString["path"] + ""))
            if (-not [string]::IsNullOrWhiteSpace($fPath) -and (Test-Path -LiteralPath $fPath)) {
                $fileBytes = [System.IO.File]::ReadAllBytes($fPath)
                $res.ContentType = if ($fPath -match "\.mp4$") { "video/mp4" } else { "video/webm" }
                $res.StatusCode = 200
                $res.ContentLength64 = $fileBytes.Length
                $res.OutputStream.Write($fileBytes, 0, $fileBytes.Length)
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
