[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
$ErrorActionPreference = "SilentlyContinue"
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

# Tat triet de tien trinh powershell lk_local_bridge cu qua WMI Win32_Process (Khong dung Get-NetTCPConnection vi http.sys luon bao PID=4!)
try {
    Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object {
        $_.ProcessId -ne $PID -and $_.Name -match "powershell" -and $_.CommandLine -match "lk_local_bridge"
    } | ForEach-Object {
        Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
    }
    Start-Sleep -Milliseconds 300
} catch {}

$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://localhost:48930/")
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
            $buf = [System.Text.Encoding]::UTF8.GetBytes('{"ok":true,"version":"5.4.0","port":48930}')
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
            $cacheDir = Join-Path $env:LOCALAPPDATA "LunKengAutoVideo4K\CineFetchCache_v53\$theme"
            $binDir = Join-Path $env:LOCALAPPDATA "LunKengAutoVideo4K\bin"
            New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null
            New-Item -ItemType Directory -Path $binDir -Force | Out-Null

            $archMap = @{
                "nature"     = "waterfall nature OR forest river nature"
                "ocean"      = "ocean waves beach OR sea coast underwater"
                "street"     = "city traffic night OR street cars urban"
                "space"      = "galaxy stars space OR aurora night sky"
                "meditation" = "calm river waterfall OR zen nature mist"
                "luxury"     = "city skyline aerial OR modern architecture"
                "ancient"    = "ancient temple ruins OR castle mountain"
                "battle"     = "storm lightning clouds OR thunderstorm sky"
                "scifi"      = "aurora timelapse OR futuristic neon light"
                "horror"     = "dark forest fog OR spooky night mist"
                "romance"    = "sunset flowers nature OR golden hour beach"
                "history"    = "historic castle monument OR ancient ruins"
            }
            $ytMap = @{
                "nature"     = "4k waterfall forest river nature relaxation no copyright"
                "ocean"      = "4k ocean waves beach sea aerial no copyright"
                "street"     = "4k city traffic night street timelapse no copyright"
                "space"      = "4k galaxy stars aurora night sky no copyright"
                "meditation" = "4k calm river zen waterfall meditation no copyright"
                "luxury"     = "4k city skyline luxury aerial drone no copyright"
                "ancient"    = "4k ancient temple castle mountain aerial no copyright"
                "battle"     = "4k storm lightning dark clouds cinematic no copyright"
                "scifi"      = "4k aurora borealis cyberpunk lights no copyright"
                "horror"     = "4k dark spooky fog forest mist no copyright"
                "romance"    = "4k golden sunset flowers beach clouds no copyright"
                "history"    = "4k historic castle monument aerial no copyright"
            }
            $archQ = if ($archMap[$theme]) { $archMap[$theme] } else { $archMap["nature"] }
            $ytQ = if ($ytMap[$theme]) { $ytMap[$theme] } else { $ytMap["nature"] }

            $existing = @(Get-ChildItem -LiteralPath $cacheDir -File -ErrorAction SilentlyContinue | Where-Object { $_.Length -gt 60000 -and ($_.Extension -eq ".mp4" -or $_.Extension -eq ".webm") })
            $remoteUrls = @()

            # Nguon 1: Internet Archive Open Video (.MP4 H.264 truc tiep - khong bi chan tai Viet Nam nhu upload.wikimedia.org!)
            if ($existing.Count -lt 6) {
                $fullArchQ = "mediatype:movies AND ($archQ) AND NOT collection:tvarchive AND NOT collection:newsandpublicaffairs"
                $encArchQ = [System.Uri]::EscapeDataString($fullArchQ)
                $archApiUrl = "https://archive.org/advancedsearch.php?q=$encArchQ&fl[]=identifier&rows=12&page=1&output=json"
                $archJsonTmp = Join-Path $cacheDir "arch_search.json"
                Remove-Item -LiteralPath $archJsonTmp -Force -ErrorAction SilentlyContinue
                try {
                    Start-Process -FilePath "curl.exe" -ArgumentList "-L -s --max-time 7 `"$archApiUrl`" -o `"$archJsonTmp`"" -WindowStyle Hidden -Wait
                    if (Test-Path -LiteralPath $archJsonTmp) {
                        $archData = [System.IO.File]::ReadAllText($archJsonTmp, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
                        $docs = $archData.response.docs
                        $dlProcs = @()
                        $dlTargets = @()
                        $idx = 1
                        foreach ($doc in $docs) {
                            if ($idx -gt 8) { break }
                            $id = "" + $doc.identifier
                            if ([string]::IsNullOrWhiteSpace($id)) { continue }
                            $metaTmp = Join-Path $cacheDir ("meta_" + $idx + ".json")
                            Remove-Item -LiteralPath $metaTmp -Force -ErrorAction SilentlyContinue
                            Start-Process -FilePath "curl.exe" -ArgumentList "-L -s --max-time 5 `"https://archive.org/metadata/$id`" -o `"$metaTmp`"" -WindowStyle Hidden -Wait
                            if (Test-Path -LiteralPath $metaTmp) {
                                $metaObj = [System.IO.File]::ReadAllText($metaTmp, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
                                Remove-Item -LiteralPath $metaTmp -Force -ErrorAction SilentlyContinue
                                if ($null -ne $metaObj.files) {
                                    $bestMp4 = ""
                                    foreach ($f in $metaObj.files) {
                                        $fName = "" + $f.name
                                        $fSize = if ($f.size) { [int64]$f.size } else { 0 }
                                        if ($fName -match "\.mp4$" -and ($fSize -eq 0 -or ($fSize -gt 80000 -and $fSize -lt 45000000))) {
                                            $encName = [System.Uri]::EscapeDataString($fName) -replace '%2F', '/'
                                            $bestMp4 = "https://archive.org/download/$id/$encName"
                                            if ($fSize -gt 150000 -and $fSize -le 18000000) { break }
                                        }
                                    }
                                    if (-not [string]::IsNullOrWhiteSpace($bestMp4)) {
                                        $remoteUrls += ('"' + $bestMp4 + '"')
                                        if ($dlProcs.Count -lt 5) {
                                            $outMp4 = Join-Path $cacheDir ("arch_" + $idx + ".mp4")
                                            $tmpMp4 = $outMp4 + ".tmp"
                                            if (-not (Test-Path -LiteralPath $outMp4)) {
                                                $p = Start-Process -FilePath "curl.exe" -ArgumentList "-L -f -s --max-time 14 `"$bestMp4`" -o `"$tmpMp4`"" -WindowStyle Hidden -PassThru
                                                $dlProcs += $p
                                                $dlTargets += @{ tmp = $tmpMp4; final = $outMp4 }
                                            }
                                        }
                                        $idx++
                                    }
                                }
                            }
                        }
                        # Cho cac tien trinh curl.exe tai song song (toi da 14 giay cho ca 5 video!)
                        $waitStart = [DateTime]::UtcNow
                        foreach ($p in $dlProcs) {
                            $remMs = [Math]::Max(500, 14000 - [int]([DateTime]::UtcNow - $waitStart).TotalMilliseconds)
                            try { $p.WaitForExit($remMs) | Out-Null } catch {}
                        }
                        foreach ($t in $dlTargets) {
                            if ((Test-Path -LiteralPath $t.tmp) -and (Get-Item -LiteralPath $t.tmp).Length -gt 60000) {
                                Move-Item -LiteralPath $t.tmp -Destination $t.final -Force -ErrorAction SilentlyContinue
                            } else {
                                Remove-Item -LiteralPath $t.tmp -Force -ErrorAction SilentlyContinue
                            }
                        }
                    }
                } catch {}
                Remove-Item -LiteralPath $archJsonTmp -Force -ErrorAction SilentlyContinue
            }

            # Nguon 2: Neu co yt-dlp (hoac python -m yt_dlp tu CineFetch_AI), tai them luong .MP4 tu YouTube!
            $cachedNow = @(Get-ChildItem -LiteralPath $cacheDir -File -ErrorAction SilentlyContinue | Where-Object { $_.Length -gt 60000 -and ($_.Extension -eq ".mp4" -or $_.Extension -eq ".webm") })
            if ($cachedNow.Count -lt 3) {
                $ytDlpExe = Join-Path $binDir "yt-dlp.exe"
                if (-not (Test-Path -LiteralPath $ytDlpExe)) {
                    $cmdYt = Get-Command yt-dlp -ErrorAction SilentlyContinue
                    if ($null -ne $cmdYt) {
                        $ytDlpExe = $cmdYt.Source
                    }
                }
                if (Test-Path -LiteralPath $ytDlpExe) {
                    try {
                        $outTpl = Join-Path $cacheDir "yt_%(id)s.%(ext)s"
                        $pYt = Start-Process -FilePath $ytDlpExe -ArgumentList "`"ytsearch4:$ytQ`" -f `"b[height<=720][ext=mp4]/b[ext=mp4]/18/b`" --max-filesize 40M --no-playlist --no-warnings -o `"$outTpl`"" -WindowStyle Hidden -PassThru
                        $pYt.WaitForExit(14000) | Out-Null
                    } catch {}
                } else {
                    $pyCmd = Get-Command python -ErrorAction SilentlyContinue
                    if ($null -ne $pyCmd) {
                        try {
                            $outTpl = Join-Path $cacheDir "yt_%(id)s.%(ext)s"
                            $pPy = Start-Process -FilePath "python" -ArgumentList "-m yt_dlp `"ytsearch4:$ytQ`" -f `"b[height<=720][ext=mp4]/b[ext=mp4]/18/b`" --max-filesize 40M --no-playlist --no-warnings -o `"$outTpl`"" -WindowStyle Hidden -PassThru
                            $pPy.WaitForExit(14000) | Out-Null
                        } catch {}
                    }
                }
            }

            $cachedFiles = @(Get-ChildItem -LiteralPath $cacheDir -File -ErrorAction SilentlyContinue | Where-Object { $_.Length -gt 60000 -and ($_.Extension -eq ".mp4" -or $_.Extension -eq ".webm") })
            $urlsArr = @()
            foreach ($cf in $cachedFiles) {
                $encPath = [System.Uri]::EscapeDataString($cf.FullName)
                $urlsArr += ('"http://localhost:48930/stock-cache?path=' + $encPath + '"')
            }
            $urlsArr += $remoteUrls
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
                $cacheDir = Join-Path $env:LOCALAPPDATA "LunKengAutoVideo4K\CineFetchCache_v53\$theme"
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
