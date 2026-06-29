$cfg=@{}
Get-Content 'E:\WeFlowBridge\.env' | Where-Object { $_ -match '^\s*[^#].*=' } | ForEach-Object { $k,$v=$_ -split '=',2; $cfg[$k.Trim()]=$v.Trim() }

$base = $cfg['WEFLOW_BASE_URL']
$token_val = $cfg['WEFLOW_TOKEN']
$headers = @{ Authorization="Bearer $token_val" }

Write-Host "=== All sessions (root account) ==="
$r1 = Invoke-RestMethod "$base/api/v1/sessions?limit=50" -Headers $headers
$count = 0
foreach ($s in $r1.data) {
    $count++
    Write-Output ("[$count] id: $($s.id) | name: $(($s.name) -replace '(.*?)_(.*)','name:$($($1))') | talker_id: $($s.talker) | lastMsgTime: $($s.lastMsgTime)")
}

Write-Host "=== Search: 狂野AI ==="
$r2 = Invoke-RestMethod "$base/api/v1/sessions?keyword=6期&limit=10" -Headers $headers -ErrorAction SilentlyContinue
if ($r2.data) {
    foreach ($s in $r2.data) { Write-Output ("name: $($s.name) | talker: $($s.talker) | lastMsgTime: $($s.lastMsgTime)") }
} else {
    Write-Host "No results for '6期'"
}

Write-Host "=== Search: B群 ==="
$r3 = Invoke-RestMethod "$base/api/v1/sessions?keyword=B+群&limit=10" -Headers $headers -ErrorAction SilentlyContinue
if ($r3.data) {
    foreach ($s in $r3.data) { Write-Output ("name: $($s.name) | talker: $($s.talker) | lastMsgTime: $($s.lastMsgTime)") }
} else {
    Write-Host "No results for 'B群'"
}
