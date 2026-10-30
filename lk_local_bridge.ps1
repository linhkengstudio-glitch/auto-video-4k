$ErrorActionPreference = "SilentlyContinue"
$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://127.0.0.1:48915/")
try {
    $listener.Start()
} catch {
    exit
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
            $buf = [System.Text.Encoding]::UTF8.GetBytes('{"ok":true,"version":"3.4.0"}')
            $res.ContentType = "application/json; charset=utf-8"
            $res.OutputStream.Write($buf, 0, $buf.Length)
            $res.Close()
            continue
        }

        if ($path -eq "/pick-folder") {
            $shell = New-Object -ComObject Shell.Application
            $folder = $shell.BrowseForFolder(0, "Chon thu muc luu Video 4K (LK_Auto_Edit_Video):", 0x0040, 17)
            if ($null -ne $folder -and $null -ne $folder.Self -and $folder.Self.Path) {
                $chosenPath = $folder.Self.Path.Replace('\', '\\').Replace('"', '\"')
                $json = '{"ok":true,"path":"' + $chosenPath + '"}'
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
                $qFile = "Video_4K_Output.webm"
            }
            if ([string]::IsNullOrWhiteSpace($qFolder) -or -not (Test-Path -LiteralPath $qFolder)) {
                $qFolder = Join-Path $env:USERPROFILE "Downloads"
            }
            $fullOutPath = Join-Path $qFolder $qFile
            $ms = New-Object System.IO.MemoryStream
            $req.InputStream.CopyTo($ms)
            [System.IO.File]::WriteAllBytes($fullOutPath, $ms.ToArray())
            $ms.Close()

            $escapedOut = $fullOutPath.Replace('\', '\\').Replace('"', '\"')
            $json = '{"ok":true,"savedPath":"' + $escapedOut + '"}'
            $buf = [System.Text.Encoding]::UTF8.GetBytes($json)
            $res.ContentType = "application/json; charset=utf-8"
            $res.OutputStream.Write($buf, 0, $buf.Length)
            $res.Close()
            continue
        }

        $res.StatusCode = 404
        $res.Close()
    } catch {
        try { $context.Response.Close() } catch {}
    }
}
