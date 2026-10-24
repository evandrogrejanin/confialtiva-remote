# Testa, de FORA do servidor (ex.: um notebook na internet), se so as portas certas respondem.
# Uso: powershell -ExecutionPolicy Bypass -File validar-externo.ps1 remoto.confialtiva.com.br
param([Parameter(Mandatory = $true)][string]$Servidor)

$falhou = $false
function Testar($porta) {
    $c = New-Object Net.Sockets.TcpClient
    try { return $c.ConnectAsync($Servidor, $porta).Wait(3000) -and $c.Connected } catch { return $false } finally { $c.Close() }
}

Write-Host "Servidor: $Servidor"
try { Write-Host "IP: $([Net.Dns]::GetHostAddresses($Servidor) -join ', ')" } catch { Write-Host "[FALHA] DNS nao resolve"; exit 1 }

Write-Host "`nPortas que DEVEM estar abertas:"
foreach ($p in 21115, 21116, 21117) {
    if (Testar $p) { Write-Host "  [OK]    TCP $p aberta" } else { Write-Host "  [FALHA] TCP $p fechada"; $falhou = $true }
}
Write-Host "  [INFO]  UDP 21116 nao pode ser testada assim; confirme pelo app (status 'Pronto')."

Write-Host "`nPortas que DEVEM estar fechadas:"
foreach ($p in 21114, 21118, 21119, 80, 443, 3389, 3306, 5432, 8080) {
    if (Testar $p) { Write-Host "  [FALHA] TCP $p aberta (deveria estar fechada)"; $falhou = $true } else { Write-Host "  [OK]    TCP $p fechada" }
}
if (Testar 22) { Write-Host "  [AVISO] TCP 22 (SSH) aberta para este IP: deve responder so do IP do administrador" } else { Write-Host "  [OK]    TCP 22 fechada para este IP" }

if ($falhou) { Write-Host "`nRESULTADO: reprovado"; exit 1 } else { Write-Host "`nRESULTADO: aprovado" }
