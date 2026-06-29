$root = "C:\Users\user\Downloads\New folder"
$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://localhost:8000/")
$listener.Prefixes.Add("http://127.0.0.1:8000/")
$listener.Start()
$mime = @{
  ".html"="text/html; charset=utf-8"; ".htm"="text/html; charset=utf-8";
  ".js"="text/javascript; charset=utf-8"; ".mjs"="text/javascript; charset=utf-8";
  ".css"="text/css; charset=utf-8"; ".json"="application/json; charset=utf-8";
  ".jpg"="image/jpeg"; ".jpeg"="image/jpeg"; ".png"="image/png"; ".gif"="image/gif";
  ".svg"="image/svg+xml"; ".webp"="image/webp"; ".ico"="image/x-icon";
  ".mp3"="audio/mpeg"; ".wav"="audio/wav"; ".ogg"="audio/ogg"; ".m4a"="audio/mp4";
  ".woff"="font/woff"; ".woff2"="font/woff2"
}
$noCache = @('.html','.htm','.js','.mjs','.css','.json')
while ($listener.IsListening) {
  try {
    $ctx = $listener.GetContext()
    $req = $ctx.Request; $res = $ctx.Response
    $path = [System.Uri]::UnescapeDataString($req.Url.AbsolutePath).TrimStart('/')
    if ([string]::IsNullOrEmpty($path)) { $path = "index.html" }
    $full = Join-Path $root $path
    if (-not (Test-Path $full -PathType Leaf)) {
      $res.StatusCode = 404
      $b = [System.Text.Encoding]::UTF8.GetBytes("404 Not Found: $path")
      $res.OutputStream.Write($b, 0, $b.Length); $res.OutputStream.Close(); continue
    }
    $ext = [System.IO.Path]::GetExtension($full).ToLower()
    $ct = $mime[$ext]; if (-not $ct) { $ct = "application/octet-stream" }
    $res.ContentType = $ct
    $res.Headers.Add("Accept-Ranges", "bytes")
    if ($noCache -contains $ext) { $res.Headers.Add("Cache-Control", "no-cache, must-revalidate") }
    else { $res.Headers.Add("Cache-Control", "public, max-age=600") }
    $fs = [System.IO.File]::OpenRead($full)
    try {
      $total = $fs.Length
      $range = $req.Headers["Range"]
      if ($range -and ($range -match 'bytes=(\d*)-(\d*)')) {
        $start = if ($matches[1] -ne '') { [int64]$matches[1] } else { [int64]0 }
        $end   = if ($matches[2] -ne '') { [int64]$matches[2] } else { [int64]($total - 1) }
        if ($end -ge $total) { $end = $total - 1 }
        if ($start -lt 0 -or $start -gt $end) { $start = 0 }
        $len = $end - $start + 1
        $res.StatusCode = 206
        $res.Headers.Add("Content-Range", "bytes $start-$end/$total")
        $res.ContentLength64 = $len
        $fs.Seek($start, [System.IO.SeekOrigin]::Begin) | Out-Null
        $buf = New-Object byte[] 65536
        $remaining = $len
        while ($remaining -gt 0) {
          $toRead = [Math]::Min([int]$buf.Length, [int]$remaining)
          $read = $fs.Read($buf, 0, $toRead)
          if ($read -le 0) { break }
          $res.OutputStream.Write($buf, 0, $read)
          $remaining -= $read
        }
      } else {
        $res.StatusCode = 200
        $res.ContentLength64 = $total
        $buf = New-Object byte[] 65536
        while (($read = $fs.Read($buf, 0, $buf.Length)) -gt 0) { $res.OutputStream.Write($buf, 0, $read) }
      }
    } finally { $fs.Close() }
    $res.OutputStream.Close()
  } catch {}
}
