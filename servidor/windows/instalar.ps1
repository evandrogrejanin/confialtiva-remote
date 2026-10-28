#Requires -RunAsAdministrator
# Instala o servidor Confialtiva Remote (hbbs + hbbr) em Windows Server 2019/2022/2025.
# Uso (PowerShell como Administrador, na pasta deste arquivo):
#   powershell -ExecutionPolicy Bypass -File .\instalar.ps1
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$Version = '1.1.16'
$ZipUrl  = "https://github.com/rustdesk/rustdesk-server/releases/download/$Version/rustdesk-server-windows-x86_64-unsigned.zip"
# SHA-256 publicado pelo GitHub para este arquivo do release oficial.
$ZipHash = 'B865A3A62FC8755B45480C508F1C4871C3338590408DDA8C58C7E9C373B7ADB0'
$Dir     = 'C:\ConfialtivaRemote-Server'
$Bin     = "$Dir\bin"
$Data    = "$Dir\data"

Write-Host '==> Baixando o servidor oficial do RustDesk' $Version
New-Item -ItemType Directory -Force $Bin, $Data | Out-Null
$zip = "$env:TEMP\rustdesk-server-$Version.zip"
Invoke-WebRequest -UseBasicParsing $ZipUrl -OutFile $zip
$hash = (Get-FileHash $zip -Algorithm SHA256).Hash
if ($hash -ne $ZipHash) { throw "Hash do download nao confere ($hash). Instalacao abortada." }
Write-Host '    hash SHA-256 conferido'

foreach ($t in 'Confialtiva hbbs', 'Confialtiva hbbr') {
    if (Get-ScheduledTask -TaskName $t -ErrorAction SilentlyContinue) {
        Stop-ScheduledTask -TaskName $t -ErrorAction SilentlyContinue
        Unregister-ScheduledTask -TaskName $t -Confirm:$false
    }
}
Get-Process hbbs, hbbr -ErrorAction SilentlyContinue | Stop-Process -Force
$tmp = "$env:TEMP\rustdesk-server-$Version"
if (Test-Path $tmp) { Remove-Item -Recurse -Force $tmp }
Expand-Archive $zip $tmp
Copy-Item "$tmp\x86_64\hbbs.exe", "$tmp\x86_64\hbbr.exe" $Bin -Force
Remove-Item -Recurse -Force $tmp, $zip

Write-Host '==> Restringindo a pasta de dados (chaves) a SYSTEM e Administradores'
# SIDs em vez de nomes: funciona em Windows em qualquer idioma.
icacls $Data /inheritance:r /grant:r '*S-1-5-18:(OI)(CI)F' '*S-1-5-32-544:(OI)(CI)F' | Out-Null

Write-Host '==> Registrando hbbs e hbbr para iniciar com o Windows'
$principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
    -ExecutionTimeLimit ([TimeSpan]::Zero) -RestartCount 999 -RestartInterval (New-TimeSpan -Minutes 1) `
    -MultipleInstances IgnoreNew -StartWhenAvailable
$trigger = New-ScheduledTaskTrigger -AtStartup
foreach ($svc in 'hbbr', 'hbbs') {
    # -k _ : so aceita clientes que tenham a chave publica deste servidor
    $action = New-ScheduledTaskAction -Execute "$Bin\$svc.exe" -Argument '-k _' -WorkingDirectory $Data
    Register-ScheduledTask -TaskName "Confialtiva $svc" -Action $action -Trigger $trigger `
        -Principal $principal -Settings $settings -Description "Servidor Confialtiva Remote ($svc)" | Out-Null
    Start-ScheduledTask -TaskName "Confialtiva $svc"
}

Write-Host '==> Liberando as portas no Firewall do Windows'
Get-NetFirewallRule -DisplayName 'Confialtiva Remote*' -ErrorAction SilentlyContinue | Remove-NetFirewallRule
New-NetFirewallRule -DisplayName 'Confialtiva Remote hbbs TCP' -Direction Inbound -Action Allow -Protocol TCP -LocalPort 21115,21116 -Program "$Bin\hbbs.exe" -Profile Any | Out-Null
New-NetFirewallRule -DisplayName 'Confialtiva Remote hbbs UDP' -Direction Inbound -Action Allow -Protocol UDP -LocalPort 21116 -Program "$Bin\hbbs.exe" -Profile Any | Out-Null
New-NetFirewallRule -DisplayName 'Confialtiva Remote hbbr TCP' -Direction Inbound -Action Allow -Protocol TCP -LocalPort 21117 -Program "$Bin\hbbr.exe" -Profile Any | Out-Null

$pub = "$Data\id_ed25519.pub"
for ($i = 0; $i -lt 30 -and -not (Test-Path $pub); $i++) { Start-Sleep 1 }
if (-not (Test-Path $pub)) { throw "A chave nao foi gerada em $Data. Veja se as tarefas 'Confialtiva hbbs/hbbr' estao em execucao." }

try { $ip = (Invoke-RestMethod -UseBasicParsing 'https://api.ipify.org' -TimeoutSec 15).Trim() } catch { $ip = '(nao foi possivel consultar)' }
$lan = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -notlike '127.*' -and $_.IPAddress -notlike '169.254.*' } | Select-Object -First 1).IPAddress

Write-Host ''
Write-Host '================================================================'
Write-Host ' Servidor instalado.'
Write-Host ''
Write-Host ' Chave publica (CONFIALTIVA_SERVER_KEY no GitHub):'
Write-Host ''
Write-Host "   $((Get-Content $pub -Raw).Trim())"
Write-Host ''
Write-Host " IP interno desta VM : $lan   (destino do redirecionamento no firewall)"
Write-Host " IP publico de saida : $ip   (valor do registro DNS 'remoto')"
Write-Host ''
Write-Host " Faca backup seguro de $Data\id_ed25519 (chave privada)."
Write-Host ' Se ela for perdida, todos os clientes precisam de um novo instalador.'
Write-Host ' Proximo passo: powershell -ExecutionPolicy Bypass -File .\validar-servidor.ps1'
Write-Host '================================================================'
