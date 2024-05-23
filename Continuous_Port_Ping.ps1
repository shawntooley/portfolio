$target = "10.20.0.219"
$port = 443

while ($true) {
    $tcpClient = New-Object System.Net.Sockets.TcpClient
    $result = $tcpClient.BeginConnect($target, $port, $null, $null)
    $wait = $result.AsyncWaitHandle.WaitOne(1000, $false)

    if ($wait -and $tcpClient.Connected) {
        Write-Host "Port $port on $target is open"
    } else {
        Write-Host "Port $port on $target is closed"
    }

    $tcpClient.Close()

    Start-Sleep -Seconds 3
}