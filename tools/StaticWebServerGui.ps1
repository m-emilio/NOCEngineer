param(
  [switch]$Serve,
  [string]$Root,
  [int]$Port = 8080,
  [string]$HostName = "127.0.0.1",
  [string]$LogPath
)

Set-StrictMode -Version Latest

function Write-ServerLog {
  param([string]$Message)

  if ($LogPath) {
    $stamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Add-Content -LiteralPath $LogPath -Value "[$stamp] $Message"
  }
}

function Get-ContentType {
  param([string]$Path)

  switch ([System.IO.Path]::GetExtension($Path).ToLowerInvariant()) {
    ".html" { "text/html; charset=utf-8"; break }
    ".htm"  { "text/html; charset=utf-8"; break }
    ".css"  { "text/css; charset=utf-8"; break }
    ".js"   { "text/javascript; charset=utf-8"; break }
    ".json" { "application/json; charset=utf-8"; break }
    ".svg"  { "image/svg+xml"; break }
    ".png"  { "image/png"; break }
    ".jpg"  { "image/jpeg"; break }
    ".jpeg" { "image/jpeg"; break }
    ".gif"  { "image/gif"; break }
    ".webp" { "image/webp"; break }
    ".ico"  { "image/x-icon"; break }
    ".txt"  { "text/plain; charset=utf-8"; break }
    ".xml"  { "application/xml; charset=utf-8"; break }
    ".wasm" { "application/wasm"; break }
    default { "application/octet-stream" }
  }
}

function Send-TextResponse {
  param(
    [System.Net.HttpListenerResponse]$Response,
    [int]$StatusCode,
    [string]$Body,
    [string]$ContentType = "text/plain; charset=utf-8"
  )

  $bytes = [System.Text.Encoding]::UTF8.GetBytes($Body)
  $Response.StatusCode = $StatusCode
  $Response.ContentType = $ContentType
  $Response.ContentLength64 = $bytes.Length
  $Response.OutputStream.Write($bytes, 0, $bytes.Length)
  $Response.Close()
}

function Send-TcpResponse {
  param(
    [System.IO.Stream]$Stream,
    [int]$StatusCode,
    [string]$Reason,
    [byte[]]$BodyBytes,
    [string]$ContentType = "text/plain; charset=utf-8",
    [bool]$HeadOnly = $false
  )

  $headers = @(
    "HTTP/1.1 $StatusCode $Reason",
    "Content-Type: $ContentType",
    "Content-Length: $($BodyBytes.Length)",
    "Connection: close",
    "Cache-Control: no-cache",
    "",
    ""
  ) -join "`r`n"

  $headerBytes = [System.Text.Encoding]::ASCII.GetBytes($headers)
  $Stream.Write($headerBytes, 0, $headerBytes.Length)

  if (-not $HeadOnly -and $BodyBytes.Length -gt 0) {
    $Stream.Write($BodyBytes, 0, $BodyBytes.Length)
  }
}

function Send-TcpTextResponse {
  param(
    [System.IO.Stream]$Stream,
    [int]$StatusCode,
    [string]$Reason,
    [string]$Body,
    [string]$ContentType = "text/plain; charset=utf-8",
    [bool]$HeadOnly = $false
  )

  $bytes = [System.Text.Encoding]::UTF8.GetBytes($Body)
  Send-TcpResponse -Stream $Stream -StatusCode $StatusCode -Reason $Reason -BodyBytes $bytes -ContentType $ContentType -HeadOnly $HeadOnly
}

function Get-DirectoryListing {
  param(
    [string]$RootDirectory,
    [string]$Directory,
    [string]$RequestPath
  )

  $items = Get-ChildItem -LiteralPath $Directory -Force |
    Sort-Object @{ Expression = { -not $_.PSIsContainer } }, Name

  $rows = foreach ($item in $items) {
    $name = [System.Net.WebUtility]::HtmlEncode($item.Name)
    $hrefName = [uri]::EscapeDataString($item.Name)
    $slash = if ($item.PSIsContainer) { "/" } else { "" }
    $href = ($RequestPath.TrimEnd("/") + "/" + $hrefName + $slash)
    if ($href -notmatch "^/") {
      $href = "/" + $href
    }
    "<li><a href=""$href"">$name$slash</a></li>"
  }

  $relative = $Directory.Substring($RootDirectory.Length).TrimStart("\", "/")
  if (-not $relative) {
    $relative = "/"
  }

  @"
<!doctype html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Index of $relative</title>
  <style>
    body { background:#0b1020; color:#d7e0ea; font:14px Segoe UI, sans-serif; padding:24px; }
    a { color:#60d5ff; text-decoration:none; }
    a:hover { text-decoration:underline; }
    code { color:#9ef0b8; }
    li { margin:6px 0; }
  </style>
</head>
<body>
  <h1>Index of <code>$relative</code></h1>
  <ul>
    $($rows -join "`n    ")
  </ul>
</body>
</html>
"@
}

function Start-StaticFileServer {
  if (-not $Root -or -not (Test-Path -LiteralPath $Root -PathType Container)) {
    throw "Root directory does not exist: $Root"
  }

  $rootInfo = Get-Item -LiteralPath $Root
  $rootFullName = $rootInfo.FullName.TrimEnd("\", "/")
  $ipAddress = switch ($HostName) {
    "0.0.0.0" { [System.Net.IPAddress]::Any }
    "localhost" { [System.Net.IPAddress]::Loopback }
    default { [System.Net.IPAddress]::Parse($HostName) }
  }

  $listener = [System.Net.Sockets.TcpListener]::new($ipAddress, $Port)
  $listener.Start()

  Write-ServerLog "Serving '$rootFullName' on http://$HostName`:$Port/"

  try {
    while ($true) {
      $client = $listener.AcceptTcpClient()

      try {
        $stream = $client.GetStream()
        $buffer = New-Object byte[] 16384
        $read = $stream.Read($buffer, 0, $buffer.Length)

        if ($read -le 0) {
          continue
        }

        $requestText = [System.Text.Encoding]::ASCII.GetString($buffer, 0, $read)
        $requestLine = ($requestText -split "`r?`n", 2)[0]
        $parts = $requestLine -split " "

        if ($parts.Count -lt 3) {
          Send-TcpTextResponse -Stream $stream -StatusCode 400 -Reason "Bad Request" -Body "Bad Request"
          Write-ServerLog "400 malformed request"
          continue
        }

        $method = $parts[0].ToUpperInvariant()
        $rawTarget = ($parts[1] -split "\?", 2)[0]
        $headOnly = $method -eq "HEAD"

        if ($method -ne "GET" -and $method -ne "HEAD") {
          Send-TcpTextResponse -Stream $stream -StatusCode 405 -Reason "Method Not Allowed" -Body "Method Not Allowed" -HeadOnly $headOnly
          Write-ServerLog "405 $rawTarget"
          continue
        }

        $relativeUrl = [System.Uri]::UnescapeDataString($rawTarget).TrimStart("/")
        $relativePath = $relativeUrl -replace "/", [System.IO.Path]::DirectorySeparatorChar
        $targetPath = [System.IO.Path]::GetFullPath((Join-Path $rootFullName $relativePath))

        if (-not $targetPath.StartsWith($rootFullName, [System.StringComparison]::OrdinalIgnoreCase)) {
          Send-TcpTextResponse -Stream $stream -StatusCode 403 -Reason "Forbidden" -Body "Forbidden" -HeadOnly $headOnly
          Write-ServerLog "403 $rawTarget"
          continue
        }

        if (Test-Path -LiteralPath $targetPath -PathType Container) {
          $indexHtml = Join-Path $targetPath "index.html"
          $indexHtm = Join-Path $targetPath "index.htm"

          if (Test-Path -LiteralPath $indexHtml -PathType Leaf) {
            $targetPath = $indexHtml
          } elseif (Test-Path -LiteralPath $indexHtm -PathType Leaf) {
            $targetPath = $indexHtm
          } else {
            $listing = Get-DirectoryListing -RootDirectory $rootFullName -Directory $targetPath -RequestPath $rawTarget
            Send-TcpTextResponse -Stream $stream -StatusCode 200 -Reason "OK" -Body $listing -ContentType "text/html; charset=utf-8" -HeadOnly $headOnly
            Write-ServerLog "200 $rawTarget"
            continue
          }
        }

        if (-not (Test-Path -LiteralPath $targetPath -PathType Leaf)) {
          Send-TcpTextResponse -Stream $stream -StatusCode 404 -Reason "Not Found" -Body "Not Found" -HeadOnly $headOnly
          Write-ServerLog "404 $rawTarget"
          continue
        }

        $bytes = [System.IO.File]::ReadAllBytes($targetPath)
        Send-TcpResponse -Stream $stream -StatusCode 200 -Reason "OK" -BodyBytes $bytes -ContentType (Get-ContentType -Path $targetPath) -HeadOnly $headOnly
        Write-ServerLog "200 $rawTarget"
      } catch {
        try {
          Send-TcpTextResponse -Stream $stream -StatusCode 500 -Reason "Server Error" -Body "Server Error"
        } catch {}
        Write-ServerLog "500 $($_.Exception.Message)"
      } finally {
        $client.Close()
      }
    }
  } finally {
    $listener.Stop()
    Write-ServerLog "Server stopped"
  }
}

if ($Serve) {
  try {
    Start-StaticFileServer
  } catch {
    Write-ServerLog "Fatal: $($_.Exception.Message)"
    throw
  }
  return
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$scriptPath = $PSCommandPath
$servers = New-Object System.Collections.ArrayList

function New-Label {
  param([string]$Text, [int]$X, [int]$Y, [int]$Width = 90)
  $label = [System.Windows.Forms.Label]::new()
  $label.Text = $Text
  $label.Location = [System.Drawing.Point]::new($X, $Y)
  $label.Size = [System.Drawing.Size]::new($Width, 22)
  $label
}

function Add-UiLog {
  param([string]$Message)
  $stamp = Get-Date -Format "HH:mm:ss"
  $logBox.AppendText("[$stamp] $Message`r`n")
}

function Get-SelectedServerItems {
  @($serverList.SelectedItems)
}

function Refresh-ServerRows {
  foreach ($item in $serverList.Items) {
    $server = $item.Tag
    if ($server.Process -and -not $server.Process.HasExited) {
      $item.SubItems[3].Text = "Running"
    } else {
      $item.SubItems[3].Text = "Stopped"
    }
  }
}

function Start-GuiServer {
  $root = $directoryBox.Text.Trim()
  $portValue = 0

  if (-not (Test-Path -LiteralPath $root -PathType Container)) {
    [System.Windows.Forms.MessageBox]::Show("Choose an existing directory.", "Missing directory") | Out-Null
    return
  }

  if (-not [int]::TryParse($portBox.Text.Trim(), [ref]$portValue) -or $portValue -lt 1 -or $portValue -gt 65535) {
    [System.Windows.Forms.MessageBox]::Show("Enter a port from 1 to 65535.", "Invalid port") | Out-Null
    return
  }

  $hostValue = [string]$hostBox.SelectedItem
  if (-not $hostValue) {
    $hostValue = "127.0.0.1"
  }

  $openHost = if ($hostValue -eq "0.0.0.0") { "127.0.0.1" } else { $hostValue }
  $url = "http://$openHost`:$portValue/"
  $logPath = Join-Path $env:TEMP ("simple-webserver-{0}-{1}.log" -f $portValue, (Get-Date -Format "yyyyMMdd-HHmmss"))
  $escapedScript = $scriptPath.Replace("'", "''")
  $escapedRoot = $root.Replace("'", "''")
  $escapedHost = $hostValue.Replace("'", "''")
  $escapedLog = $logPath.Replace("'", "''")
  $command = "& '$escapedScript' -Serve -Root '$escapedRoot' -Port $portValue -HostName '$escapedHost' -LogPath '$escapedLog'"
  $encodedCommand = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($command))

  try {
    $process = Start-Process -FilePath "powershell.exe" `
      -ArgumentList @("-NoProfile", "-ExecutionPolicy", "Bypass", "-EncodedCommand", $encodedCommand) `
      -WindowStyle Hidden `
      -PassThru

    Start-Sleep -Milliseconds 450

    $server = [pscustomobject]@{
      Directory = $root
      Url = $url
      Process = $process
      LogPath = $logPath
    }

    [void]$servers.Add($server)

    $item = [System.Windows.Forms.ListViewItem]::new($root)
    [void]$item.SubItems.Add($url)
    [void]$item.SubItems.Add([string]$process.Id)
    [void]$item.SubItems.Add("Running")
    [void]$item.SubItems.Add($logPath)
    $item.Tag = $server
    [void]$serverList.Items.Add($item)

    Add-UiLog "Started $url -> $root"
  } catch {
    [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, "Start failed") | Out-Null
    Add-UiLog "Start failed: $($_.Exception.Message)"
  }
}

function Stop-GuiServer {
  param([System.Windows.Forms.ListViewItem]$Item)

  $server = $Item.Tag
  if ($server.Process -and -not $server.Process.HasExited) {
    try {
      Stop-Process -Id $server.Process.Id -Force -ErrorAction Stop
      $Item.SubItems[3].Text = "Stopped"
      Add-UiLog "Stopped $($server.Url)"
    } catch {
      Add-UiLog "Stop failed for $($server.Url): $($_.Exception.Message)"
    }
  } else {
    $Item.SubItems[3].Text = "Stopped"
  }
}

$form = [System.Windows.Forms.Form]::new()
$form.Text = "Simple Static Web Servers"
$form.Size = [System.Drawing.Size]::new(860, 560)
$form.StartPosition = "CenterScreen"
$form.MinimumSize = [System.Drawing.Size]::new(760, 500)

$directoryLabel = New-Label -Text "Directory" -X 14 -Y 18
$form.Controls.Add($directoryLabel)

$directoryBox = [System.Windows.Forms.TextBox]::new()
$directoryBox.Location = [System.Drawing.Point]::new(105, 15)
$directoryBox.Size = [System.Drawing.Size]::new(570, 25)
$directoryBox.Text = (Get-Location).Path
$form.Controls.Add($directoryBox)

$browseButton = [System.Windows.Forms.Button]::new()
$browseButton.Text = "Browse..."
$browseButton.Location = [System.Drawing.Point]::new(690, 13)
$browseButton.Size = [System.Drawing.Size]::new(120, 29)
$browseButton.Add_Click({
  $dialog = [System.Windows.Forms.FolderBrowserDialog]::new()
  $dialog.Description = "Select a directory to serve"
  $dialog.SelectedPath = $directoryBox.Text
  if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
    $directoryBox.Text = $dialog.SelectedPath
  }
})
$form.Controls.Add($browseButton)

$portLabel = New-Label -Text "Port" -X 14 -Y 58
$form.Controls.Add($portLabel)

$portBox = [System.Windows.Forms.TextBox]::new()
$portBox.Location = [System.Drawing.Point]::new(105, 55)
$portBox.Size = [System.Drawing.Size]::new(90, 25)
$portBox.Text = "8080"
$form.Controls.Add($portBox)

$hostLabel = New-Label -Text "Host" -X 220 -Y 58 -Width 50
$form.Controls.Add($hostLabel)

$hostBox = [System.Windows.Forms.ComboBox]::new()
$hostBox.Location = [System.Drawing.Point]::new(270, 55)
$hostBox.Size = [System.Drawing.Size]::new(145, 25)
$hostBox.DropDownStyle = "DropDownList"
[void]$hostBox.Items.Add("127.0.0.1")
[void]$hostBox.Items.Add("localhost")
[void]$hostBox.Items.Add("0.0.0.0")
$hostBox.SelectedIndex = 0
$form.Controls.Add($hostBox)

$startButton = [System.Windows.Forms.Button]::new()
$startButton.Text = "Start Server"
$startButton.Location = [System.Drawing.Point]::new(440, 53)
$startButton.Size = [System.Drawing.Size]::new(115, 30)
$startButton.Add_Click({ Start-GuiServer })
$form.Controls.Add($startButton)

$openButton = [System.Windows.Forms.Button]::new()
$openButton.Text = "Open"
$openButton.Location = [System.Drawing.Point]::new(560, 53)
$openButton.Size = [System.Drawing.Size]::new(80, 30)
$openButton.Add_Click({
  foreach ($item in Get-SelectedServerItems) {
    Start-Process $item.Tag.Url
  }
})
$form.Controls.Add($openButton)

$stopButton = [System.Windows.Forms.Button]::new()
$stopButton.Text = "Stop Selected"
$stopButton.Location = [System.Drawing.Point]::new(645, 53)
$stopButton.Size = [System.Drawing.Size]::new(115, 30)
$stopButton.Add_Click({
  foreach ($item in Get-SelectedServerItems) {
    Stop-GuiServer -Item $item
  }
})
$form.Controls.Add($stopButton)

$stopAllButton = [System.Windows.Forms.Button]::new()
$stopAllButton.Text = "Stop All"
$stopAllButton.Location = [System.Drawing.Point]::new(765, 53)
$stopAllButton.Size = [System.Drawing.Size]::new(65, 30)
$stopAllButton.Anchor = "Top,Right"
$stopAllButton.Add_Click({
  foreach ($item in @($serverList.Items)) {
    Stop-GuiServer -Item $item
  }
})
$form.Controls.Add($stopAllButton)

$serverList = [System.Windows.Forms.ListView]::new()
$serverList.Location = [System.Drawing.Point]::new(15, 100)
$serverList.Size = [System.Drawing.Size]::new(815, 260)
$serverList.Anchor = "Top,Bottom,Left,Right"
$serverList.View = "Details"
$serverList.FullRowSelect = $true
$serverList.GridLines = $true
[void]$serverList.Columns.Add("Directory", 280)
[void]$serverList.Columns.Add("URL", 150)
[void]$serverList.Columns.Add("PID", 70)
[void]$serverList.Columns.Add("Status", 90)
[void]$serverList.Columns.Add("Log", 210)
$serverList.Add_DoubleClick({
  foreach ($item in Get-SelectedServerItems) {
    Start-Process $item.Tag.Url
  }
})
$form.Controls.Add($serverList)

$viewLogButton = [System.Windows.Forms.Button]::new()
$viewLogButton.Text = "View Log"
$viewLogButton.Location = [System.Drawing.Point]::new(15, 370)
$viewLogButton.Size = [System.Drawing.Size]::new(90, 30)
$viewLogButton.Anchor = "Bottom,Left"
$viewLogButton.Add_Click({
  foreach ($item in Get-SelectedServerItems) {
    if (Test-Path -LiteralPath $item.Tag.LogPath) {
      Start-Process notepad.exe $item.Tag.LogPath
    }
  }
})
$form.Controls.Add($viewLogButton)

$refreshButton = [System.Windows.Forms.Button]::new()
$refreshButton.Text = "Refresh Status"
$refreshButton.Location = [System.Drawing.Point]::new(115, 370)
$refreshButton.Size = [System.Drawing.Size]::new(115, 30)
$refreshButton.Anchor = "Bottom,Left"
$refreshButton.Add_Click({ Refresh-ServerRows })
$form.Controls.Add($refreshButton)

$logBox = [System.Windows.Forms.TextBox]::new()
$logBox.Location = [System.Drawing.Point]::new(15, 410)
$logBox.Size = [System.Drawing.Size]::new(815, 95)
$logBox.Anchor = "Bottom,Left,Right"
$logBox.Multiline = $true
$logBox.ScrollBars = "Vertical"
$logBox.ReadOnly = $true
$form.Controls.Add($logBox)

$statusTimer = [System.Windows.Forms.Timer]::new()
$statusTimer.Interval = 2000
$statusTimer.Add_Tick({ Refresh-ServerRows })
$statusTimer.Start()

$form.Add_FormClosing({
  $running = @($serverList.Items | Where-Object { $_.Tag.Process -and -not $_.Tag.Process.HasExited })
  if ($running.Count -gt 0) {
    $answer = [System.Windows.Forms.MessageBox]::Show(
      "Stop running web servers before closing?",
      "Servers still running",
      [System.Windows.Forms.MessageBoxButtons]::YesNoCancel,
      [System.Windows.Forms.MessageBoxIcon]::Question
    )

    if ($answer -eq [System.Windows.Forms.DialogResult]::Cancel) {
      $_.Cancel = $true
      return
    }

    if ($answer -eq [System.Windows.Forms.DialogResult]::Yes) {
      foreach ($item in $running) {
        Stop-GuiServer -Item $item
      }
    }
  }
})

Add-UiLog "Ready. Select a directory, choose a port, then start a server."
[void]$form.ShowDialog()
