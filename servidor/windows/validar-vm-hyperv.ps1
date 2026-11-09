#Requires -RunAsAdministrator
# Confere, pelo host Hyper-V, se a VM esta pronta para ser o servidor Confialtiva Remote.
# Funciona com a VM desligada (le apenas a configuracao).
# Uso, no host Hyper-V (ou num PC com permissao de administrador do Hyper-V no host):
#   powershell -ExecutionPolicy Bypass -File .\validar-vm-hyperv.ps1 -VMName "NOME DA VM" [-ComputerName HOST]
param(
    [Parameter(Mandatory = $true)][string]$VMName,
    [string]$ComputerName = $env:COMPUTERNAME
)

$script:falhou = $false
function Ok($m)    { Write-Host "  [OK]    $m" }
function Falha($m) { Write-Host "  [FALHA] $m"; $script:falhou = $true }
function Aviso($m) { Write-Host "  [AVISO] $m" }

try { $vm = Get-VM -Name $VMName -ComputerName $ComputerName -ErrorAction Stop }
catch { Write-Host "VM '$VMName' nao encontrada em $ComputerName. VMs existentes:"; Get-VM -ComputerName $ComputerName | Select-Object Name, State | Format-Table -AutoSize; exit 1 }

Write-Host "VM: $($vm.Name)  Host: $ComputerName  Estado: $($vm.State)  Geracao: $($vm.Generation)"

Write-Host '1. Recursos'
if ($vm.ProcessorCount -ge 2) { Ok "$($vm.ProcessorCount) vCPU" } else { Aviso "$($vm.ProcessorCount) vCPU (recomendado: 2)" }
$memGB = [math]::Round($vm.MemoryStartup / 1GB, 1)
if ($vm.DynamicMemoryEnabled) {
    $minGB = [math]::Round($vm.MemoryMinimum / 1GB, 1)
    if ($minGB -ge 1) { Ok "memoria dinamica: inicial $memGB GB, minimo $minGB GB" } else { Aviso "memoria dinamica com minimo de $minGB GB (recomendado: 1 GB ou mais)" }
} elseif ($memGB -ge 2) { Ok "$memGB GB de RAM" } else { Aviso "$memGB GB de RAM (recomendado: 2 GB)" }
foreach ($d in Get-VMHardDiskDrive -VM $vm) {
    try {
        $vhd = Get-VHD -Path $d.Path -ComputerName $ComputerName -ErrorAction Stop
        $size = [math]::Round($vhd.Size / 1GB); $used = [math]::Round($vhd.FileSize / 1GB)
        if ($size -ge 20) { Ok "disco $([IO.Path]::GetFileName($d.Path)): $size GB (arquivo ocupa $used GB)" } else { Aviso "disco com $size GB (recomendado: 20 GB ou mais)" }
    } catch { Aviso "nao foi possivel ler o disco $($d.Path)" }
}

Write-Host '2. Inicializacao com o host'
if ($vm.AutomaticStartAction -eq 'Start') { Ok 'liga sozinha quando o host liga' }
elseif ($vm.AutomaticStartAction -eq 'StartIfRunning') { Aviso 'liga com o host so se estava ligada antes: prefira "Sempre iniciar" (Start)' }
else { Falha 'nao liga com o host: apos reiniciar o servidor, ninguem consegue conectar. Ajuste com: Set-VM -Name "<VM>" -AutomaticStartAction Start' }
if ($vm.AutomaticStopAction -eq 'ShutDown') { Ok 'desliga corretamente quando o host desliga' } else { Aviso "acao ao desligar o host: $($vm.AutomaticStopAction) (recomendado: ShutDown)" }

Write-Host '3. Rede'
$switches = Get-VMSwitch -ComputerName $ComputerName
foreach ($nic in Get-VMNetworkAdapter -VM $vm) {
    $sw = $switches | Where-Object Name -eq $nic.SwitchName
    if (-not $nic.SwitchName) { Falha "placa '$($nic.Name)' sem switch virtual conectado"; continue }
    if ($sw.SwitchType -eq 'External') { Ok "placa '$($nic.Name)' no switch externo '$($nic.SwitchName)'" }
    else { Falha "placa '$($nic.Name)' no switch '$($nic.SwitchName)' do tipo $($sw.SwitchType): precisa ser Externo para receber conexoes da rede" }
    $vlan = Get-VMNetworkAdapterVlan -VMNetworkAdapter $nic
    if ($vlan.OperationMode -eq 'Access') { Ok "VLAN $($vlan.AccessVlanId) (confira se e a DMZ/VLAN separada)" } else { Aviso 'sem VLAN definida: a VM fica na mesma rede dos demais servidores (recomendado: DMZ/VLAN separada)' }
    if ($nic.MacAddressSpoofing -eq 'Off') { Ok 'MAC spoofing desativado' } else { Aviso 'MAC spoofing ativado (desnecessario para este servidor)' }
    if ($nic.DhcpGuard -eq 'On') { Ok 'DHCP guard ativo' } else { Aviso 'DHCP guard desativado (recomendado: ativar)' }
    if ($nic.RouterGuard -eq 'On') { Ok 'Router guard ativo' } else { Aviso 'Router guard desativado (recomendado: ativar)' }
    if ($nic.IPAddresses) { Ok "IP(s) atual(is): $($nic.IPAddresses -join ', ')" }
}

Write-Host '4. Seguranca e integracao'
if ($vm.Generation -eq 2) {
    $fw = Get-VMFirmware -VM $vm
    if ($fw.SecureBoot -eq 'On') { Ok 'Secure Boot ativo' } else { Aviso 'Secure Boot desativado' }
}
$ts = Get-VMIntegrationService -VM $vm | Where-Object { $_.Name -match 'Time|Hora' }
if ($ts -and $ts.Enabled) { Ok 'sincronizacao de horario com o host ativa' } else { Aviso 'sincronizacao de horario desativada: garanta NTP dentro da VM' }
$snaps = @(Get-VMSnapshot -VM $vm)
if ($snaps.Count -gt 0) { Aviso "$($snaps.Count) checkpoint(s): ao restaurar um, confira se a chave em C:\ConfialtivaRemote-Server\data continua a mesma" }

Write-Host ''
if ($vm.State -ne 'Running') {
    Write-Host "A VM esta '$($vm.State)'. Para ligar: Start-VM -Name '$($vm.Name)' -ComputerName $ComputerName"
    Write-Host 'Depois, dentro da VM, rode instalar.ps1 e validar-servidor.ps1.'
}
if ($script:falhou) { Write-Host 'RESULTADO: reprovado, corrija as FALHAS acima'; exit 1 }
Write-Host 'RESULTADO: aprovado (revise os AVISOS, se houver)'
