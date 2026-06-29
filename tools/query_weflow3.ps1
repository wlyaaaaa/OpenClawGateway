$cfg=@{}
Get-Content 'E:\WeFlowBridge\.env' | Where-Object { $_ -match '^\s*[^#].*=' } | ForEach-Object { $k,$v=$_ -split '=',2; $cfg[$k.Trim()]=$v.Trim() }

$base = $cfg['WEFLOW_BASE_URL']
$token_val = $cfg['WEFLOW_TOKEN']
$headers = @{ Authorization="Bearer $token_val" }

Write-Host "=== All sessions (top 30) ==="
$r1 = Invoke-RestMethod "$base/api/v1/sessions?limit=30" -Headers $headers
$count = $r1.data.Count
Write-Output ("Total count: " + $count)
if ($count -gt 0) {
    Write-Host "--- Data sample ---"
    $r1.data[0] | ConvertTo-Json -Depth 3
} else {
    Write-Host "data array is empty, checking raw response:"
    $r1.PSObject.Properties | ForEach-Object { Write-Output ($_.Name + ": " + ($_.Value | ConvertTo-Json)) }
}

Write-Host ""
Write-Host "=== Contacts (root) ==="
$r2 = Invoke-RestMethod "$base/api/v1/contacts?limit=5" -Headers $headers
if ($r2.data) { foreach($c in $r2.data){ Write-Output ("name: "+$c.name+" | weId: "+($c.weId+'')) } } else { Write-Host "No contacts" }

Write-Host ""
Write-Host "=== Sessions with chatlab keyword ==="
$r3 = Invoke-RestMethod "$base/api/v1/sessions?keyword=all&limit=50" -Headers $headers
Write-Output ("count: " + ($r3.data).Count)
