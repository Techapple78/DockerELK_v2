param(
  [string]$ElasticsearchUrl = "http://localhost:9200",
  [string]$KibanaUrl = "http://localhost:5601",
  [int]$LogstashPort = 5044,
  [string]$ExpectedIndexPattern = "logstash-local-dev-*"
)

$ErrorActionPreference = "Stop"

function Assert-HttpOk {
  param([string]$Uri, [string]$Name)

  $response = Invoke-WebRequest -UseBasicParsing -Uri $Uri -TimeoutSec 15
  if ($response.StatusCode -lt 200 -or $response.StatusCode -ge 300) {
    throw "$Name returned HTTP $($response.StatusCode)"
  }
  Write-Host "OK $Name -> HTTP $($response.StatusCode)"
}

function Assert-TcpOpen {
  param([string]$HostName, [int]$Port, [string]$Name)

  $client = [System.Net.Sockets.TcpClient]::new()
  $async = $client.BeginConnect($HostName, $Port, $null, $null)
  if (-not $async.AsyncWaitHandle.WaitOne(5000)) {
    $client.Close()
    throw "$Name is not reachable on $HostName`:$Port"
  }
  $client.EndConnect($async)
  $client.Close()
  Write-Host "OK $Name -> TCP $HostName`:$Port"
}

Assert-HttpOk -Uri $ElasticsearchUrl -Name "Elasticsearch"
Assert-HttpOk -Uri "$KibanaUrl/api/status" -Name "Kibana"
Assert-TcpOpen -HostName "127.0.0.1" -Port $LogstashPort -Name "Logstash input"

try {
  $indicesUri = "$ElasticsearchUrl/_cat/indices/$ExpectedIndexPattern`?h=index,docs.count"
  $indices = Invoke-WebRequest -UseBasicParsing -Uri $indicesUri -TimeoutSec 15
  Write-Host "Indices matching ${ExpectedIndexPattern}:"
  Write-Host $indices.Content
} catch {
  Write-Host "No index matching ${ExpectedIndexPattern} yet."
}
