param(
  [string]$ElasticsearchUrl = "http://localhost:9200",
  [string]$IndexPattern = "logstash-local-dev-*",
  [int]$MinimumCount = 1
)

$ErrorActionPreference = "Stop"

Start-Sleep -Seconds 5
$response = Invoke-RestMethod -Method Get -Uri "$ElasticsearchUrl/$IndexPattern/_count" -TimeoutSec 15
if ($response.count -lt $MinimumCount) {
  throw "Expected at least $MinimumCount documents in $IndexPattern, found $($response.count)"
}

Write-Host "OK ingestion -> $($response.count) docs in $IndexPattern"
