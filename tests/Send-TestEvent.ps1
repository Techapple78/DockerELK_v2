param(
  [int]$Port = 5044,
  [string]$HostName = "127.0.0.1",
  [string]$Path = "/scalability-test",
  [string]$UserAgent = "DockerELKScaleTest/1.0"
)

$ErrorActionPreference = "Stop"

$timestamp = [DateTimeOffset]::Now.ToUniversalTime().ToString("dd/MMM/yyyy:HH:mm:ss +0000", [System.Globalization.CultureInfo]::InvariantCulture)
$line = "127.0.0.1 - - [$timestamp] `"GET $Path HTTP/1.1`" 200 42 `"-`" `"$UserAgent`" 0.012`n"

$client = [System.Net.Sockets.TcpClient]::new($HostName, $Port)
$stream = $client.GetStream()
$bytes = [System.Text.Encoding]::UTF8.GetBytes($line)
$stream.Write($bytes, 0, $bytes.Length)
$stream.Close()
$client.Close()

Write-Host "sent test event to $HostName`:$Port"
