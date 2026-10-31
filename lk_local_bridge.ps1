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

        if ($path -eq "/ping") {
            $buf = [System.Text.Encoding]::UTF8.GetBytes('{"ok":true,"version":"4.4.0"}')
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
            $ms = New-Object System.IO.MemoryStream
            $req.InputStream.CopyTo($ms)
            $rawBytes = $ms.ToArray()
            $ms.Close()

            # Neu may co ffmpeg va luong ghi la WebM (0x1A 0x45 0xDF 0xA3) thi tu dong chuyen sang MP4 chuan H.264, neu da la MP4 thi ghi thang!
            $ffCmd = Get-Command ffmpeg -ErrorAction SilentlyContinue
            if ($null -ne $ffCmd -and $rawBytes.Length -gt 4 -and $rawBytes[0] -eq 0x1A -and $rawBytes[1] -eq 0x45) {
                $tmpWebm = $fullOutPath + ".tmp.webm"
                [System.IO.File]::WriteAllBytes($tmpWebm, $rawBytes)
                Start-Process -FilePath "ffmpeg" -ArgumentList "-y -i `"$tmpWebm`" -c:v libx264 -preset ultrafast -crf 22 -c:a aac `"$fullOutPath`"" -WindowStyle Hidden -Wait
                Remove-Item -LiteralPath $tmpWebm -Force -ErrorAction SilentlyContinue
                if (-not (Test-Path -LiteralPath $fullOutPath)) {
                    [System.IO.File]::WriteAllBytes($fullOutPath, $rawBytes)
                }
            } else {
                [System.IO.File]::WriteAllBytes($fullOutPath, $rawBytes)
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
            $theme = [System.Uri]::UnescapeDataString(($req.QueryString["theme"] + "nature"))
            $cacheDir = Join-Path $env:LOCALAPPDATA "LunKengAutoVideo4K\StockCache\$theme"
            New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null

            $qMap = @{
                "nature"     = "filetype:video forest waterfall nature -cartoon -animation"
                "ocean"      = "filetype:video ocean waves beach sea -cartoon"
                "street"     = "filetype:video city traffic night street"
                "space"      = "filetype:video night sky stars aurora"
                "meditation" = "filetype:video river waterfall stream"
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

            $existing = Get-ChildItem -LiteralPath $cacheDir -File -Include *.webm,*.mp4 -ErrorAction SilentlyContinue
            if ($null -eq $existing -or $existing.Count -lt 40) {
                $encQ = [System.Uri]::EscapeDataString($searchQuery)
                $apiUrl = "https://commons.wikimedia.org/w/api.php?action=query&generator=search&gsrnamespace=6&gsrsearch=$encQ&gsrlimit=45&prop=imageinfo&iiprop=url|size|derivatives&format=json"
                try {
                    $wc = New-Object System.Net.WebClient
                    $wc.Headers.Add("User-Agent", "LunKengAutoVideo4K/4.4.0 (Windows NT 10.0; Win64; x64)")
                    $wc.Encoding = [System.Text.Encoding]::UTF8
                    $apiJson = $wc.DownloadString($apiUrl) | ConvertFrom-Json
                    if ($null -ne $apiJson.query -and $null -ne $apiJson.query.pages) {
                        $dlIdx = 1
                        foreach ($prop in $apiJson.query.pages.PSObject.Properties) {
                            if ($dlIdx -gt 40) { break }
                            $page = $prop.Value
                            if ($null -ne $page.imageinfo -and $page.imageinfo.Count -gt 0) {
                                $info = $page.imageinfo[0]
                                $vidUrl = ""
                                if ($null -ne $info.derivatives) {
                                    foreach ($d in $info.derivatives) {
                                        if ($d.src -and ($d.src -match "480p\.vp9\.webm" -or $d.src -match "360p\.vp9\.webm")) {
                                            $vidUrl = $d.src
                                            break
                                        }
                                    }
                                }
                                if ([string]::IsNullOrWhiteSpace($vidUrl) -and $info.url -and ($info.url -match "\.(webm|mp4)$") -and $info.size -lt 600000000) {
                                    $vidUrl = $info.url
                                }
                                if (-not [string]::IsNullOrWhiteSpace($vidUrl)) {
                                    $ext = if ($vidUrl -match "\.mp4$") { ".mp4" } else { ".webm" }
                                    $outVid = Join-Path $cacheDir ("cam_clip_" + $dlIdx + $ext)
                                    if (-not (Test-Path -LiteralPath $outVid)) {
                                        Start-Process -FilePath "curl.exe" -ArgumentList "-L -s -A `"LunKengAutoVideo4K/4.4.0`" --max-time 8 `"$vidUrl`" -o `"$outVid`"" -WindowStyle Hidden -Wait
                                    }
                                    if ((Test-Path -LiteralPath $outVid) -and (Get-Item -LiteralPath $outVid).Length -gt 20000) {
                                        $dlIdx++
                                    } else {
                                        Remove-Item -LiteralPath $outVid -Force -ErrorAction SilentlyContinue
                                    }
                                }
                            }
                        }
                    }
                } catch {}
            }

            $cachedFiles = Get-ChildItem -LiteralPath $cacheDir -File -ErrorAction SilentlyContinue | Where-Object { $_.Length -gt 20000 }
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
