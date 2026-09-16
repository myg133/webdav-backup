# integration-test.ps1 - OpenList WebDAV integration smoke tests (System.Net.Http)
# Run: powershell -ExecutionPolicy Bypass -File integration-test.ps1

$ErrorActionPreference = 'Continue'
Add-Type -AssemblyName System.Net.Http

$BaseUrl = 'http://192.168.31.101:8080/dav/test_backup_dav'
$User = 'testdav'
$Pass = 'testdav'
$AuthHeader = 'Basic ' + [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("$User`:$Pass"))
$Timestamp = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
$TestDir = "/dev-test-$Timestamp"
$TestFile = "dev_test_$Timestamp.bin"

$results = @()
function Add-Result($name, $pass, $detail) {
  $script:results += [pscustomobject]@{
    name = $name
    pass = $pass
    detail = $detail
  }
  $symbol = if ($pass) { '[PASS]' } else { '[FAIL]' }
  Write-Host "  $symbol $name : $detail"
}

$client = [System.Net.Http.HttpClient]::new()
$client.Timeout = [TimeSpan]::FromSeconds(60)

function Http-Request([string]$method, [string]$url, [byte[]]$body, [hashtable]$extraHeaders) {
  $req = [System.Net.Http.HttpRequestMessage]::new([System.Net.Http.HttpMethod]::new($method), $url)
  $req.Headers.Add('Authorization', $AuthHeader)
  if ($extraHeaders) {
    foreach ($k in $extraHeaders.Keys) {
      $req.Headers.TryAddWithoutValidation($k, $extraHeaders[$k]) | Out-Null
    }
  }
  if ($body) {
    $content = [System.Net.Http.ByteArrayContent]::new($body)
    if ($extraHeaders -and $extraHeaders.ContainsKey('Content-Type')) {
      $content.Headers.ContentType = [System.Net.Http.Headers.MediaTypeHeaderValue]::Parse($extraHeaders['Content-Type'])
    }
    $req.Content = $content
  }
  try {
    return $client.SendAsync($req).GetAwaiter().GetResult()
  } catch {
    return $_.Exception.Response
  }
}

function Get-StatusCode([object]$r) {
  if ($r -eq $null) { return 0 }
  $code = $r.StatusCode.value__ -as [int]
  if (-not $code) {
    if ($r -is [System.Net.Http.HttpResponseMessage]) { $code = $r.StatusCode.value__ -as [int] }
    else { $code = 0 }
  }
  return $code
}

# T1: HEAD root
Write-Host "`n[T1] testConnection (HEAD root)"
$r = Http-Request -method HEAD -url $BaseUrl -body $null -extraHeaders @{}
$code = Get-StatusCode $r
if ($code -eq 200) {
  Add-Result 'AC-01: HEAD root returns 200' $true "status=$code"
} else {
  Add-Result 'AC-01: HEAD root returns 200' $false "status=$code"
}

# T2: PROPFIND depth=1
Write-Host "`n[T2] PROPFIND depth=1 returns 207"
$xmlBody = '<?xml version="1.0"?><d:propfind xmlns:d="DAV:"><d:prop><d:displayname/><d:getcontentlength/><d:getlastmodified/><d:resourcetype/></d:prop></d:propfind>'
$xmlBytes = [Text.Encoding]::ASCII.GetBytes($xmlBody)
$r = Http-Request -method PROPFIND -url $BaseUrl -body $xmlBytes -extraHeaders @{ Depth = '1'; 'Content-Type' = 'application/xml' }
$code = Get-StatusCode $r
if ($code -eq 207) {
  Add-Result 'PROPFIND depth=1' $true 'status=207 Multi-Status'
} else {
  Add-Result 'PROPFIND depth=1' $false "status=$code"
}

# T3: PUT small file
Write-Host "`n[T3] PUT small test file"
$smallBytes = [byte[]]::new(1024)
(New-Object Random).NextBytes($smallBytes)
$remotePath = "$TestDir/$TestFile"
$remoteUrl = $BaseUrl + $remotePath
$r = Http-Request -method PUT -url $remoteUrl -body $smallBytes -extraHeaders @{ 'Content-Type' = 'application/octet-stream' }
$code = Get-StatusCode $r
if ($code -eq 201) {
  Add-Result 'AC-04: PUT small file' $true 'status=201 Created'
} else {
  Add-Result 'AC-04: PUT small file' $false "status=$code"
}

# T4: HEAD reports size
Write-Host "`n[T4] HEAD returns Content-Length"
$r = Http-Request -method HEAD -url $remoteUrl -body $null -extraHeaders @{}
$code = Get-StatusCode $r
$len = $null
if ($r.Content) { $len = $r.Content.Headers.ContentLength }
elseif ($r -is [System.Net.Http.HttpResponseMessage] -and $r.Content) {
  $len = $r.Content.Headers.ContentLength
}
if ($code -eq 200 -and $len -eq 1024) {
  Add-Result 'AC-07: HEAD reports correct size' $true "Content-Length=$len"
} else {
  Add-Result 'AC-07: HEAD reports correct size' $false "Content-Length=$len, status=$code"
}

# T5: GET Range 0-99
Write-Host "`n[T5] GET Range 0-99 returns 206"
$r = Http-Request -method GET -url $remoteUrl -body $null -extraHeaders @{ Range = 'bytes=0-99' }
$code = Get-StatusCode $r
if ($code -eq 206) {
  $bodyLen = 0
  if ($r.Content) { $bodyLen = $r.Content.ReadAsByteArrayAsync().Result.Length }
  Add-Result 'AC-10: Range GET 0-99' $true "status=206, body=$bodyLen bytes"
} else {
  Add-Result 'AC-10: Range GET 0-99' $false "status=$code"
}

# T6: GET Range 100-199
Write-Host "`n[T6] GET Range 100-199 returns 206"
$r = Http-Request -method GET -url $remoteUrl -body $null -extraHeaders @{ Range = 'bytes=100-199' }
$code = Get-StatusCode $r
if ($code -eq 206) {
  Add-Result 'AC-10: Range GET 100-199' $true 'status=206 Partial Content'
} else {
  Add-Result 'AC-10: Range GET 100-199' $false "status=$code"
}

# T7: PUT overwrite smaller body
Write-Host "`n[T7] PUT overwrite smaller body simulates 'retransmit whole file'"
$smallerBytes = [byte[]]::new(512)
(New-Object Random).NextBytes($smallerBytes)
$r = Http-Request -method PUT -url $remoteUrl -body $smallerBytes -extraHeaders @{ 'Content-Type' = 'application/octet-stream' }
$code = Get-StatusCode $r
if ($code -eq 201) {
  Add-Result 'AC-07: PUT overwrite smaller (retransmit)' $true 'status=201'
} else {
  Add-Result 'AC-07: PUT overwrite smaller (retransmit)' $false "status=$code"
}

# T8: HEAD after overwrite
Write-Host "`n[T8] HEAD after overwrite shows new length"
$r = Http-Request -method HEAD -url $remoteUrl -body $null -extraHeaders @{}
$code = Get-StatusCode $r
$len = $null
if ($r -is [System.Net.Http.HttpResponseMessage] -and $r.Content) {
  $len = $r.Content.Headers.ContentLength
}
if ($code -eq 200 -and $len -eq 512) {
  Add-Result 'AC-07: HEAD after PUT shows new size' $true "Content-Length=$len (was 1024)"
} else {
  Add-Result 'AC-07: HEAD after PUT shows new size' $false "Content-Length=$len, status=$code"
}

# T9: PUT Content-Range ignored
Write-Host "`n[T9] PUT with Content-Range is ignored"
$fullBytes = [byte[]]::new(2048)
(New-Object Random).NextBytes($fullBytes)
$half = [byte[]]::new(1024)
[Array]::Copy($fullBytes, 1024, $half, 0, 1024)
$r = Http-Request -method PUT -url $remoteUrl -body $half -extraHeaders @{ 'Content-Type' = 'application/octet-stream'; 'Content-Range' = 'bytes 1024-2047/2048' }
$code = Get-StatusCode $r
if ($code -eq 201) {
  $r2 = Http-Request -method HEAD -url $remoteUrl -body $null -extraHeaders @{}
  $len = $null
  if ($r2 -is [System.Net.Http.HttpResponseMessage] -and $r2.Content) {
    $len = $r2.Content.Headers.ContentLength
  }
  if ($len -eq 1024) {
    Add-Result 'openlist-compat: Content-Range PUT ignored' $true 'final size=1024 (not appended)'
  } else {
    Add-Result 'openlist-compat: Content-Range PUT ignored' $false "final size=$len (expected 1024)"
  }
} else {
  Add-Result 'openlist-compat: Content-Range PUT ignored' $false "PUT status=$code"
}

# T10: DELETE returns 403
Write-Host "`n[T10] DELETE returns 403 (defense-in-depth)"
$r = Http-Request -method DELETE -url $remoteUrl -body $null -extraHeaders @{}
$code = Get-StatusCode $r
if ($code -eq 403) {
  Add-Result 'AC-09: DELETE blocked by server' $true 'status=403'
} else {
  Add-Result 'AC-09: DELETE blocked by server' $false "status=$code"
}

# T11: HEAD after DELETE
Write-Host "`n[T11] HEAD after DELETE shows file still exists"
$r = Http-Request -method HEAD -url $remoteUrl -body $null -extraHeaders @{}
$code = Get-StatusCode $r
$len = $null
if ($r -is [System.Net.Http.HttpResponseMessage] -and $r.Content) {
  $len = $r.Content.Headers.ContentLength
}
if ($code -eq 200 -and $len) {
  Add-Result 'AC-09: file still on server after DELETE' $true "status=$code, length=$len"
} else {
  Add-Result 'AC-09: file still on server after DELETE' $false "status=$code"
}

# T12: PROPFIND lists files
Write-Host "`n[T12] PROPFIND after PUT shows new file"
$secondBytes = [byte[]]::new(256)
(New-Object Random).NextBytes($secondBytes)
$secondPath = "$TestDir/dev_second_$Timestamp.bin"
$secondUrl = $BaseUrl + $secondPath
$putR = Http-Request -method PUT -url $secondUrl -body $secondBytes -extraHeaders @{ 'Content-Type' = 'application/octet-stream' }
$dirUrl = $BaseUrl + $TestDir
$r = Http-Request -method PROPFIND -url $dirUrl -body $xmlBytes -extraHeaders @{ Depth = '1'; 'Content-Type' = 'application/xml' }
$code = Get-StatusCode $r
$bodyText = ''
if ($r -is [System.Net.Http.HttpResponseMessage] -and $r.Content) {
  $bodyText = $r.Content.ReadAsStringAsync().Result
}
if ($code -eq 207 -and $bodyText -match $TestFile -and $bodyText -match 'dev_second') {
  Add-Result 'PROPFIND shows uploaded files' $true 'both files listed'
} else {
  Add-Result 'PROPFIND shows uploaded files' $false "status=$code, content length=$(if ($bodyText) { $bodyText.Length } else { 0 })"
}

Write-Host "`n====== Summary ======"
$pass = ($results | Where-Object { $_.pass }).Count
$fail = ($results | Where-Object { -not $_.pass }).Count
Write-Host "Total: $($results.Count), Passed: $pass, Failed: $fail"

$json = $results | ConvertTo-Json -Depth 2
$json | Out-File -FilePath "integration-result.json" -Encoding ASCII

if ($fail -gt 0) {
  exit 1
}