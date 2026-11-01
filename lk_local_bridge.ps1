$ErrorActionPreference = "SilentlyContinue"
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

# Tu dong tat tien trinh lk_local_bridge cu dang chiem cong 48915 de luon chay ban moi nhat!
try {
    Get-NetTCPConnection -LocalPort 48915 -ErrorAction SilentlyContinue | ForEach-Object {
        if ($_.OwningProcess -ne $PID -and $_.OwningProcess -gt 4) {
            Stop-Process -Id $_.OwningProcess -Force -ErrorAction SilentlyContinue
        }
    }
    Start-Sleep -Milliseconds 350
} catch {}

$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://localhost:48915/")
try {
    $listener.Start()
} catch {
    exit
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

        if ($req.HttpMethod -eq "OPTIONS") {
            $res.StatusCode = 200
            $res.Close()
            continue
        }

        $path = $req.Url.AbsolutePath

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
            $buf = [System.Text.Encoding]::UTF8.GetBytes('{"ok":true,"version":"5.0.0"}')
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
            $cacheDir = Join-Path $env:LOCALAPPDATA "LunKengAutoVideo4K\CineFetchCache_v50\$theme"
            $binDir = Join-Path $env:LOCALAPPDATA "LunKengAutoVideo4K\bin"
            New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null
            New-Item -ItemType Directory -Path $binDir -Force | Out-Null

            $ytMap = @{
                "nature"     = "4k forest waterfall river nature relaxation no copyright"
                "ocean"      = "4k ocean waves beach sea aerial no copyright"
                "street"     = "4k city night street traffic drone no copyright"
                "space"      = "4k galaxy stars nebula aurora night sky no copyright"
                "meditation" = "4k calm river zen waterfall meditation nature no copyright"
                "luxury"     = "4k luxury skyline yacht aerial drone no copyright"
                "ancient"    = "4k ancient temple mountain mist aerial no copyright"
                "battle"     = "4k storm lightning dark clouds cinematic no copyright"
                "scifi"      = "4k aurora borealis cyberpunk lights timelapse no copyright"
                "horror"     = "4k dark spooky fog forest mist cinematic no copyright"
                "romance"    = "4k golden sunset flowers clouds cinematic no copyright"
                "history"    = "4k ancient castle monument aerial drone no copyright"
            }
            $envatoMap = @{
                "nature"     = "forest+waterfall+nature"
                "ocean"      = "ocean+waves+beach"
                "street"     = "city+street+night"
                "space"      = "stars+galaxy+nebula"
                "meditation" = "zen+river+waterfall"
                "luxury"     = "luxury+skyline+aerial"
                "ancient"    = "ancient+temple+mountain"
                "battle"     = "storm+lightning+clouds"
                "scifi"      = "aurora+futuristic+lights"
                "horror"     = "dark+fog+forest"
                "romance"    = "sunset+clouds+flowers"
                "history"    = "castle+monument+aerial"
            }
            $ytQuery = if ($ytMap[$theme]) { $ytMap[$theme] } else { $ytMap["nature"] }
            $envatoSlug = if ($envatoMap[$theme]) { $envatoMap[$theme] } else { $envatoMap["nature"] }

            $existing = Get-ChildItem -LiteralPath $cacheDir -File -Include *.mp4,*.webm -ErrorAction SilentlyContinue | Where-Object { $_.Length -gt 80000 }

            # Buoc 1: Quet va tai tu Envato Elements Video Previews (.mp4 CDN truc tiep - giong het CineFetch_AI!)
            if ($null -eq $existing -or $existing.Count -lt 6) {
                try {
                    $envUrl = "https://elements.envato.com/stock-video/$envatoSlug"
                    $envHtml = & curl.exe -L -s -A "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/124.0.0.0 Safari/537.36" --max-time 10 "$envUrl"
                    if ($envHtml) {
                        $matches = [regex]::Matches($envHtml, 'https://video-previews\.elements\.envatousercontent\.com/[^"''\s\<>]+\.mp4')
                        $eIdx = 1
                        $seenEnv = @{}
                        foreach ($m in $matches) {
                            if ($eIdx -gt 6) { break }
                            $mp4Url = $m.Value
                            if (-not $seenEnv.ContainsKey($mp4Url)) {
                                $seenEnv[$mp4Url] = $true
                                $outEnv = Join-Path $cacheDir ("envato_" + $theme + "_" + $eIdx + ".mp4")
                                $tmpEnv = $outEnv + ".tmp"
                                if (-not (Test-Path -LiteralPath $outEnv)) {
                                    $pEnv = Start-Process -FilePath "curl.exe" -ArgumentList "-L -f -s -A `"Mozilla/5.0`" --max-time 14 `"$mp4Url`" -o `"$tmpEnv`"" -WindowStyle Hidden -Wait -PassThru
                                    if ($pEnv.ExitCode -eq 0 -and (Test-Path -LiteralPath $tmpEnv) -and (Get-Item -LiteralPath $tmpEnv).Length -gt 80000) {
                                        Move-Item -LiteralPath $tmpEnv -Destination $outEnv -Force
                                        $eIdx++
                                    } else {
                                        Remove-Item -LiteralPath $tmpEnv -Force -ErrorAction SilentlyContinue
                                    }
                                } else {
                                    $eIdx++
                                }
                            }
                        }
                    }
                } catch {}
            }

            # Buoc 2: Quet va tai tu YouTube bang yt-dlp.exe (Chinh la nhan cot loi cua CineFetch_AI!)
            $existing = Get-ChildItem -LiteralPath $cacheDir -File -Include *.mp4,*.webm -ErrorAction SilentlyContinue | Where-Object { $_.Length -gt 80000 }
            if ($null -eq $existing -or $existing.Count -lt 8) {
                $ytDlpExe = Join-Path $binDir "yt-dlp.exe"
                if (-not (Test-Path -LiteralPath $ytDlpExe)) {
                    $cmdYt = Get-Command yt-dlp -ErrorAction SilentlyContinue
                    if ($null -ne $cmdYt) {
                        $ytDlpExe = $cmdYt.Source
                    } else {
                        # Tim yt-dlp.exe trong thu muc CineFetch_AI tren may neu co
                        $foundCine = Get-ChildItem -Path "$env:USERPROFILE" -Filter "yt-dlp.exe" -Recurse -Depth 3 -ErrorAction SilentlyContinue | Select-Object -First 1
                        if ($null -ne $foundCine) {
                            $ytDlpExe = $foundCine.FullName
                        } else {
                            try {
                                Start-Process -FilePath "curl.exe" -ArgumentList "-L -f -s --max-time 20 `"https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp.exe`" -o `"$ytDlpExe`"" -WindowStyle Hidden -Wait
                            } catch {}
                        }
                    }
                }
                if (Test-Path -LiteralPath $ytDlpExe) {
                    try {
                        $outTpl = Join-Path $cacheDir "yt_%(id)s.%(ext)s"
                        Start-Process -FilePath $ytDlpExe -ArgumentList "`"ytsearch6:$ytQuery`" -f `"18/best[ext=mp4][height<=720]/best[ext=mp4]`" --match-filter `"duration >= 12 & duration <= 1800`" --max-filesize 55M --no-playlist --no-warnings -o `"$outTpl`"" -WindowStyle Hidden -Wait
                    } catch {}
                }
            }

            $cachedFiles = Get-ChildItem -LiteralPath $cacheDir -File -ErrorAction SilentlyContinue | Where-Object { $_.Length -gt 80000 -and ($_.Extension -eq ".mp4" -or $_.Extension -eq ".webm") }
            $urlsArr = @()
            foreach ($cf in $cachedFiles) {
                $encPath = [System.Uri]::EscapeDataString($cf.FullName)
                $urlsArr += ('"http://localhost:48915/stock-cache?path=' + $encPath + '"')
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
