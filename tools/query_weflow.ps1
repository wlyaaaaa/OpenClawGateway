$cfg=@{}
Get-Content 'E:\Projects\Tools\WeFlowBridge\.env' | Where-Object { $_ -match '^\s*[^#].*=' } | ForEach-Object { $k,$v=$_ -split '=',2; $cfg[$k.Trim()]=$v.Trim() }

$base = $cfg['WEFLOW_BASE_URL']
$token_val = $cfg['WEFLOW_TOKEN']
Write-Host "=== Config check ==="
Write-Host ("base: " + $base)
Write-Host ("token_hash: " + ($token_val.Substring(0,10)) + "...")

$headers = @{ Authorization="Bearer $token_val" }

Write-Host "=== Health with .env token ==="
try {
    $h2 = Invoke-RestMethod "$base/health" -Headers $headers
    Write-Host ("health: " + ($h2 | ConvertTo-Json))
} catch {
    Write-Host ("env_auth error: " + $_.Exception.Message)
}

# Search sessions for the B群 with root wxid
Write-Host "=== Sessions with keyword: 6期 狂野AI ==="
try {
    $r1 = Invoke-RestMethod "$base/api/v1/sessions?keyword=6期+&limit=20" -Headers $headers
    foreach ($s in $r1.data) { Write-Output ("name: " + $s.name + " | talker: " + $s.talker + " | lastMsgTime: " + $s.lastMsgTime) }
} catch {
    Write-Host ("keyword error: " + $_.Exception.Message)
}

# Search root account sessions
Write-Host "=== root wxid sessions ==="
try {
    $r2 = Invoke-RestMethod "$base/api/v1/sessions?wxid=wxid_2s7oyagbrnkw92_d047&limit=5" -Headers $headers
    foreach ($s in $r2.data) { Write-Output ("name: " + $s.name + " | talker: " + $s.talker + " | lastMsgTime: " + $s.lastMsgTime) }
} catch {
    Write-Host ("root error: " + $_.Exception.Message)
}
