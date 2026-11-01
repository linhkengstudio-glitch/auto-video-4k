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
            $buf = [System.Text.Encoding]::UTF8.GetBytes('{"ok":true,"version":"4.9.0"}')
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
            $cacheDir = Join-Path $env:LOCALAPPDATA "LunKengAutoVideo4K\StockCache_v45\$theme"
            New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null

            # Xoa thu muc StockCache cu (v4.0-v4.4) bi loi file cat ngang do timeout 8s
            $oldCacheDir = Join-Path $env:LOCALAPPDATA "LunKengAutoVideo4K\StockCache"
            if (Test-Path -LiteralPath $oldCacheDir) {
                Remove-Item -LiteralPath $oldCacheDir -Recurse -Force -ErrorAction SilentlyContinue
            }

            $qMap = @{
                "nature"     = "filetype:video waterfall forest river nature"
                "ocean"      = "filetype:video ocean waves beach sea"
                "street"     = "filetype:video city traffic night street"
                "space"      = "filetype:video night sky stars aurora"
                "meditation" = "filetype:video river waterfall stream calm"
                "luxury"     = "filetype:video aerial city skyline"
                "ancient"    = "filetype:video castle temple mountain"
                "battle"     = "filetype:video storm lightning clouds"
                "scifi"      = "filetype:video aurora lights timelapse"
                "horror"     = "filetype:video fog mist dark forest"
                "romance"    = "filetype:video sunset flowers clouds"
                "history"    = "filetype:video monument castle aerial"
            }
            $searchQuery = $qMap[$theme]
            if ([string]::IsNullOrWhiteSpace($searchQuery)) { $searchQuery = $qMap["nature"] }

            $remoteUrls = @()
            $existing = Get-ChildItem -LiteralPath $cacheDir -File -Include *.webm,*.mp4 -ErrorAction SilentlyContinue
            $encQ = [System.Uri]::EscapeDataString($searchQuery)
            # BAT BUOC dung prop=videoinfo&viprop=url|size|mime|derivatives|user|dimensions de lay luong video transcode .vp9.webm!
            $apiUrl = "https://commons.wikimedia.org/w/api.php?action=query&generator=search&gsrnamespace=6&gsrsearch=$encQ&gsrlimit=35&prop=videoinfo&viprop=url|size|mime|derivatives|user|dimensions&format=json"
            try {
                $wc = New-Object System.Net.WebClient
                $wc.Headers.Add("User-Agent", "LunKengAutoVideo4K/4.9.0 (Windows NT 10.0; Win64; x64)")
                $wc.Encoding = [System.Text.Encoding]::UTF8
                $apiJson = $wc.DownloadString($apiUrl) | ConvertFrom-Json
                if ($null -ne $apiJson.query -and $null -ne $apiJson.query.pages) {
                    $dlIdx = 1
                    foreach ($prop in $apiJson.query.pages.PSObject.Properties) {
                        $page = $prop.Value
                        $vInfoList = if ($null -ne $page.videoinfo) { $page.videoinfo } else { $page.imageinfo }
                        if ($null -ne $vInfoList -and $vInfoList.Count -gt 0) {
                            $info = $vInfoList[0]
                            if ($info.duration -and ($info.duration -lt 8 -or $info.duration -gt 1800)) { continue }
                            $vidUrl = ""
                            if ($null -ne $info.derivatives) {
                                foreach ($d in $info.derivatives) {
                                    if ($d.src -and ($d.src -match "480p\.vp9\.webm" -or $d.src -match "360p\.vp9\.webm" -or $d.src -match "720p\.vp9\.webm" -or $d.src -match "480p\.webm")) {
                                        if ($d.src.StartsWith("//")) { $vidUrl = "https:" + $d.src } else { $vidUrl = $d.src }
                                        break
                                    }
                                }
                            }
                            if ([string]::IsNullOrWhiteSpace($vidUrl) -and $info.url -and ($info.url -match "\.(webm|mp4)$") -and $info.size -lt 45000000) {
                                $vidUrl = $info.url
                            }
                            if (-not [string]::IsNullOrWhiteSpace($vidUrl)) {
                                if ($dlIdx -le 6 -and ($null -eq $existing -or $existing.Count -lt 6)) {
                                    $ext = if ($vidUrl -match "\.mp4$") { ".mp4" } else { ".webm" }
                                    $outVid = Join-Path $cacheDir ("source_v45_" + $dlIdx + $ext)
                                    $tmpVid = $outVid + ".tmp"
                                    if (-not (Test-Path -LiteralPath $outVid)) {
                                        $proc = Start-Process -FilePath "curl.exe" -ArgumentList "-L -f -s -A `"LunKengAutoVideo4K/4.9.0`" --max-time 20 `"$vidUrl`" -o `"$tmpVid`"" -WindowStyle Hidden -Wait -PassThru
                                        if ($proc.ExitCode -eq 0 -and (Test-Path -LiteralPath $tmpVid) -and (Get-Item -LiteralPath $tmpVid).Length -gt 50000) {
                                            Move-Item -LiteralPath $tmpVid -Destination $outVid -Force
                                        } else {
                                            Remove-Item -LiteralPath $tmpVid -Force -ErrorAction SilentlyContinue
                                        }
                                    }
                                    $dlIdx++
                                } else {
                                    $remoteUrls += ('"' + $vidUrl + '"')
                                }
                            }
                        }
                    }
                }
            } catch {}

            $cachedFiles = Get-ChildItem -LiteralPath $cacheDir -File -ErrorAction SilentlyContinue | Where-Object { $_.Length -gt 50000 -and $_.Extension -ne ".tmp" }
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

        if ($path -eq "/stock-cache") {
            $fPath = [System.Uri]::UnescapeDataString(($req.QueryString["path"] + ""))
            if (-not [string]::IsNullOrWhiteSpace($fPath) -and (Test-Path -LiteralPath $fPath)) {
                $vBytes = [System.IO.File]::ReadAllBytes($fPath)
                $res.ContentType = if ($fPath -match "\.mp4$") { "video/mp4" } else { "video/webm" }
                $res.ContentLength64 = $vBytes.Length
                $res.OutputStream.Write($vBytes, 0, $vBytes.Length)
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
