#Requires -RunAsAdministrator
# Valida as regras de seguranca do servidor Confialtiva Remote no Windows Server.
# Uso: powershell -ExecutionPolicy Bypass -File .\validar-servidor.ps1 [-Dominio remoto.confialtiva.com.br]
param([string]$Dominio = 'remoto.confialtiva.com.br')

$Dir  = 'C:\ConfialtivaRemote-Server'
$Data = "$Dir\data"
$script:falhou = $false
function Ok($m)    { Write-Host "  [OK]    $m" }
function Falha($m) { Write-Host "  [FALHA] $m"; $script:falhou = $true }
function Aviso($m) { Write-Host "  [AVISO] $m" }

Write-Host '1. Processos e inicializacao automatica'
foreach ($svc in 'hbbs', 'hbbr') {
    $task = Get-ScheduledTask -TaskName "Confialtiva $svc" -ErrorAction SilentlyContinue
    if (-not $task) { Falha "tarefa 'Confialtiva $svc' nao existe"; continue }
    if ($task.Triggers | Where-Object { $_.CimClass.CimClassName -eq 'MSFT_TaskBootTrigger' }) { Ok "$svc inicia com o Windows" } else { Falha "$svc nao inicia com o Windows" }
    $p = Get-CimInstance Win32_Process -Filter "Name='$svc.exe'"
    if (-not $p) { Falha "$svc nao esta em execucao"; continue }
    Ok "$svc em execucao (PID $($p.ProcessId -join ','))"
    if ($p.CommandLine -match '-k\s+_') { Ok "$svc exige a chave do servidor (-k _)" } else { Falha "$svc sem -k _: qualquer cliente RustDesk poderia usar este servidor" }
}

Write-Host '2. Portas em escuta'
$tcp = Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue
foreach ($port in 21115, 21116, 21117) {
    if ($tcp | Where-Object LocalPort -eq $port) { Ok "TCP $port escutando" } else { Falha "TCP $port nao esta escutando" }
}
if (Get-NetUDPEndpoint -LocalPort 21116 -ErrorAction SilentlyContinue) { Ok 'UDP 21116 escutando' } else { Falha 'UDP 21116 nao esta escutando' }
foreach ($port in 21118, 21119) {
    if ($tcp | Where-Object LocalPort -eq $port) { Aviso "TCP $port escutando (cliente web, nao usado): NAO redirecione esta porta no firewall da empresa" }
}

Write-Host '3. Firewall do Windows'
foreach ($prof in Get-NetFirewallProfile) {
    if ($prof.Enabled) { Ok "perfil $($prof.Name) ativo" } else { Falha "perfil $($prof.Name) desativado" }
}
$rules = Get-NetFirewallRule -DisplayName 'Confialtiva Remote*' -ErrorAction SilentlyContinue | Where-Object Enabled -eq 'True'
if (@($rules).Count -eq 3) { Ok 'regras Confialtiva Remote presentes (hbbs TCP/UDP, hbbr TCP)' } else { Falha "esperadas 3 regras 'Confialtiva Remote', encontradas $(@($rules).Count)" }
$extra = Get-NetFirewallRule -Direction Inbound -Action Allow -Enabled True -ErrorAction SilentlyContinue |
    Get-NetFirewallPortFilter -ErrorAction SilentlyContinue |
    Where-Object { $_.LocalPort -in '21114', '21118', '21119' }
if ($extra) { Falha 'ha regra de entrada liberando 21114/21118/21119' } else { Ok '21114, 21118 e 21119 sem regra de liberacao' }
$rdp = Get-ItemProperty 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -ErrorAction SilentlyContinue
if ($rdp -and $rdp.fDenyTSConnections -eq 0) { Aviso 'RDP ativo nesta VM: garanta que a porta 3389 NAO esta redirecionada no firewall da empresa' }

Write-Host '4. Chave privada'
$key = "$Data\id_ed25519"
if (Test-Path $key) {
    $acl = (Get-Acl $key).Access | Where-Object { $_.AccessControlType -eq 'Allow' }
    $sids = $acl | ForEach-Object { try { $_.IdentityReference.Translate([Security.Principal.SecurityIdentifier]).Value } catch { $_.IdentityReference.Value } }
    $outros = $sids | Where-Object { $_ -notin 'S-1-5-18', 'S-1-5-32-544' }
    if ($outros) { Falha "chave privada acessivel por outras contas: $($outros -join ', ')" } else { Ok 'chave privada acessivel so por SYSTEM e Administradores' }
    Write-Host "      chave publica: $((Get-Content "$Data\id_ed25519.pub" -Raw).Trim())"
} else {
    Falha "chave privada nao encontrada em $Data"
}

Write-Host '5. IP publico e DNS'
try { $ip = (Invoke-RestMethod -UseBasicParsing 'https://api.ipify.org' -TimeoutSec 15).Trim(); Ok "IP publico de saida: $ip" } catch { $ip = $null; Aviso 'nao foi possivel consultar o IP publico' }
try {
    $dns = (Resolve-DnsName $Dominio -Type A -Server 1.1.1.1 -ErrorAction Stop | Where-Object Type -eq 'A').IPAddress
    if ($ip -and ($dns -contains $ip)) { Ok "$Dominio aponta para $ip na internet" } else { Falha "$Dominio aponta para $($dns -join ', ') na internet (esperado $ip)" }
} catch { Falha "$Dominio nao resolve na internet (registro A ainda nao criado?)" }

Write-Host '6. Atualizacoes do Windows'
$last = Get-HotFix -ErrorAction SilentlyContinue | Where-Object InstalledOn | Sort-Object InstalledOn -Descending | Select-Object -First 1
if ($last -and $last.InstalledOn -gt (Get-Date).AddDays(-45)) { Ok "ultima atualizacao em $($last.InstalledOn.ToString('dd/MM/yyyy'))" } else { Aviso 'sem atualizacoes do Windows nos ultimos 45 dias' }

Write-Host ''
if ($script:falhou) { Write-Host 'RESULTADO: reprovado, corrija as FALHAS acima'; exit 1 }
Write-Host 'RESULTADO: aprovado (revise os AVISOS, se houver)'
