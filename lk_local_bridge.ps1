[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
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
            $buf = [System.Text.Encoding]::UTF8.GetBytes('{"ok":true,"version":"5.2.0"}')
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
            $cacheDir = Join-Path $env:LOCALAPPDATA "LunKengAutoVideo4K\CineFetchCache_v52\$theme"
            $binDir = Join-Path $env:LOCALAPPDATA "LunKengAutoVideo4K\bin"
            New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null
            New-Item -ItemType Directory -Path $binDir -Force | Out-Null

            $qMap = @{
                "nature"     = @("filetype:video waterfall forest river nature", "filetype:video mountain trees landscape")
                "ocean"      = @("filetype:video ocean waves beach sea", "filetype:video coral reef underwater coast")
                "street"     = @("filetype:video city traffic night street", "filetype:video urban highway timelapse")
                "space"      = @("filetype:video night sky stars aurora", "filetype:video earth space galaxy")
                "meditation" = @("filetype:video river waterfall stream calm", "filetype:video sunrise mist forest")
                "luxury"     = @("filetype:video aerial city skyline", "filetype:video yacht architecture modern")
                "ancient"    = @("filetype:video castle temple mountain", "filetype:video ruins stone architecture")
                "battle"     = @("filetype:video storm lightning clouds", "filetype:video fire smoke dramatic sky")
                "scifi"      = @("filetype:video aurora lights timelapse", "filetype:video technology abstract light")
                "horror"     = @("filetype:video fog mist dark forest", "filetype:video night moon clouds spooky")
                "romance"    = @("filetype:video sunset flowers clouds", "filetype:video beach golden hour waves")
                "history"    = @("filetype:video monument castle aerial", "filetype:video cathedral museum historic")
            }
            $queries = if ($qMap[$theme]) { $qMap[$theme] } else { $qMap["nature"] }

            $existing = @(Get-ChildItem -LiteralPath $cacheDir -File -ErrorAction SilentlyContinue | Where-Object { $_.Length -gt 60000 -and ($_.Extension -eq ".mp4" -or $_.Extension -eq ".webm") })
            $remoteUrls = @()
            $dlCount = $existing.Count

            # Dung curl.exe cua Windows 10/11 de truy van API va tai 6 file Video quay that ve o cung (Tranh 100% loi TLS 1.0 cua WebClient tren PowerShell 5.1!)
            foreach ($searchQuery in $queries) {
                $encQ = [System.Uri]::EscapeDataString($searchQuery)
                $apiUrl = "https://commons.wikimedia.org/w/api.php?action=query&generator=search&gsrnamespace=6&gsrsearch=$encQ&gsrlimit=30&prop=videoinfo&viprop=url|size|mime|derivatives|user|dimensions&format=json"
                $jsonTmp = Join-Path $cacheDir "api_resp.json"
                Remove-Item -LiteralPath $jsonTmp -Force -ErrorAction SilentlyContinue
                try {
                    Start-Process -FilePath "curl.exe" -ArgumentList "-L -s -A `"Mozilla/5.0 (Windows NT 10.0; Win64; x64) LunKengAutoVideo4K/5.2.0`" --max-time 10 `"$apiUrl`" -o `"$jsonTmp`"" -WindowStyle Hidden -Wait
                    if (Test-Path -LiteralPath $jsonTmp) {
                        $rawJson = [System.IO.File]::ReadAllText($jsonTmp, [System.Text.Encoding]::UTF8)
                        $apiJson = $rawJson | ConvertFrom-Json
                        if ($null -ne $apiJson.query -and $null -ne $apiJson.query.pages) {
                            foreach ($prop in $apiJson.query.pages.PSObject.Properties) {
                                $page = $prop.Value
                                $vInfoList = if ($null -ne $page.videoinfo) { $page.videoinfo } else { $page.imageinfo }
                                if ($null -ne $vInfoList -and $vInfoList.Count -gt 0) {
                                    $info = $vInfoList[0]
                                    if ($info.duration -and ($info.duration -lt 7 -or $info.duration -gt 1800)) { continue }
                                    $vidUrl = ""
                                    if ($null -ne $info.derivatives) {
                                        foreach ($d in $info.derivatives) {
                                            $dSrc = "" + $d.src
                                            if ($dSrc.StartsWith("//")) { $dSrc = "https:" + $dSrc }
                                            if ($dSrc -match "\.(webm|mp4)$" -and $dSrc -notmatch "\.(ogv|ogg|m3u8|mpd)$") {
                                                $w = if ($d.width) { [int]$d.width } else { 640 }
                                                if ($w -ge 200 -and $w -le 1300) {
                                                    $vidUrl = $dSrc
                                                    break
                                                }
                                                if ([string]::IsNullOrWhiteSpace($vidUrl)) {
                                                    $vidUrl = $dSrc
                                                }
                                            }
                                        }
                                    }
                                    if ([string]::IsNullOrWhiteSpace($vidUrl) -and $info.url) {
                                        $uOrig = "" + $info.url
                                        if ($uOrig.StartsWith("//")) { $uOrig = "https:" + $uOrig }
                                        if ($uOrig -match "\.(webm|mp4)$" -and (-not $info.size -or $info.size -lt 35000000)) {
                                            $vidUrl = $uOrig
                                        }
                                    }
                                    if (-not [string]::IsNullOrWhiteSpace($vidUrl)) {
                                        if ($dlCount -lt 6) {
                                            $ext = if ($vidUrl -match "\.mp4$") { ".mp4" } else { ".webm" }
                                            $nextNum = $dlCount + 1
                                            $outVid = Join-Path $cacheDir ("source_v52_" + $nextNum + "_" + $page.pageid + $ext)
                                            $tmpVid = $outVid + ".tmp"
                                            if (-not (Test-Path -LiteralPath $outVid)) {
                                                $pDl = Start-Process -FilePath "curl.exe" -ArgumentList "-L -f -s -A `"Mozilla/5.0 (Windows NT 10.0; Win64; x64) LunKengAutoVideo4K/5.2.0`" --max-time 14 `"$vidUrl`" -o `"$tmpVid`"" -WindowStyle Hidden -Wait -PassThru
                                                if ($pDl.ExitCode -eq 0 -and (Test-Path -LiteralPath $tmpVid) -and (Get-Item -LiteralPath $tmpVid).Length -gt 60000) {
                                                    Move-Item -LiteralPath $tmpVid -Destination $outVid -Force
                                                    $dlCount++
                                                } else {
                                                    Remove-Item -LiteralPath $tmpVid -Force -ErrorAction SilentlyContinue
                                                    $remoteUrls += ('"' + $vidUrl + '"')
                                                }
                                            } else {
                                                $dlCount++
                                            }
                                        } else {
                                            $remoteUrls += ('"' + $vidUrl + '"')
                                        }
                                    }
                                }
                            }
                        }
                    }
                } catch {}
                Remove-Item -LiteralPath $jsonTmp -Force -ErrorAction SilentlyContinue
            }

            # Du phong 2: Neu van chua du 4 file video tren o cung, dung yt-dlp.exe tai them tu YouTube!
            $cachedNow = @(Get-ChildItem -LiteralPath $cacheDir -File -ErrorAction SilentlyContinue | Where-Object { $_.Length -gt 60000 -and ($_.Extension -eq ".mp4" -or $_.Extension -eq ".webm") })
            if ($cachedNow.Count -lt 4) {
                $ytDlpExe = Join-Path $binDir "yt-dlp.exe"
                if (-not (Test-Path -LiteralPath $ytDlpExe)) {
                    $cmdYt = Get-Command yt-dlp -ErrorAction SilentlyContinue
                    if ($null -ne $cmdYt) {
                        $ytDlpExe = $cmdYt.Source
                    } else {
                        try {
                            Start-Process -FilePath "curl.exe" -ArgumentList "-L -f -s --max-time 18 `"https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp.exe`" -o `"$ytDlpExe`"" -WindowStyle Hidden -Wait
                        } catch {}
                    }
                }
                if (Test-Path -LiteralPath $ytDlpExe) {
                    try {
                        $ytQ = ($queries[0] -replace "filetype:video\s*", "") + " 4k no copyright"
                        $outTpl = Join-Path $cacheDir "yt_%(id)s.%(ext)s"
                        Start-Process -FilePath $ytDlpExe -ArgumentList "`"ytsearch4:$ytQ`" -f `"b[height<=720][ext=mp4]/b[ext=mp4]/b[ext=webm]/b`" --max-filesize 45M --no-playlist --no-warnings -o `"$outTpl`"" -WindowStyle Hidden -Wait
                    } catch {}
                }
            }

            $cachedFiles = @(Get-ChildItem -LiteralPath $cacheDir -File -ErrorAction SilentlyContinue | Where-Object { $_.Length -gt 60000 -and ($_.Extension -eq ".mp4" -or $_.Extension -eq ".webm") })
            $urlsArr = @()
            foreach ($cf in $cachedFiles) {
                $encPath = [System.Uri]::EscapeDataString($cf.FullName)
                $urlsArr += ('"http://localhost:48915/stock-cache?path=' + $encPath + '"')
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
                $cacheDir = Join-Path $env:LOCALAPPDATA "LunKengAutoVideo4K\CineFetchCache_v52\$theme"
                New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null

                $md5 = [System.Security.Cryptography.MD5]::Create()
                $hashBytes = $md5.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($remoteUrl))
                $hashHex = ([System.BitConverter]::ToString($hashBytes) -replace '-', '').Substring(0, 16).ToLower()
                $ext = if ($remoteUrl -match "\.mp4(\?|$)") { ".mp4" } else { ".webm" }
                $localFile = Join-Path $cacheDir ("proxy_" + $hashHex + $ext)
                $tmpFile = $localFile + ".tmp"

                if (-not (Test-Path -LiteralPath $localFile) -or (Get-Item -LiteralPath $localFile).Length -lt 50000) {
                    $p = Start-Process -FilePath "curl.exe" -ArgumentList "-L -f -s -A `"Mozilla/5.0 (Windows NT 10.0; Win64; x64) LunKengAutoVideo4K/5.2.0`" --max-time 12 `"$remoteUrl`" -o `"$tmpFile`"" -WindowStyle Hidden -Wait -PassThru
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
