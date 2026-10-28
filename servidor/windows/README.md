# Servidor Confialtiva Remote em Windows Server (VM na empresa)

```
Cliente (internet) ──► remoto.confialtiva.com.br ──► IP público da empresa
                                                         │  FortiGate / Sophos / SonicWall
                                                         │  redireciona TCP 21115-21117 e UDP 21116
                                                         ▼
                                                    VM Windows Server (hbbs + hbbr)
```

## 1. Requisitos da VM

| Item | Recomendação |
|---|---|
| Sistema | Windows Server 2019, 2022 ou 2025, atualizado |
| Recursos | 2 vCPU, 2 GB de RAM e 20 GB de disco |
| IP interno | **Fixo** (reserva no DHCP ou IP estático), por exemplo `192.168.10.50` |
| Rede | De preferência numa **DMZ ou VLAN separada**, sem acesso à rede interna. Se ela for invadida, o atacante não chega aos outros servidores |
| Função | Dedicada. Não use um controlador de domínio, servidor de arquivos ou de banco de dados |

## 2. Descobrir se a empresa tem IP público fixo

1. Na VM, abra o PowerShell e rode o comando abaixo. Ele mostra o IP público de saída da empresa:

   ```powershell
   Invoke-RestMethod https://api.ipify.org
   ```

2. No firewall (FortiGate, Sophos ou SonicWall), veja o IP da **interface WAN**:

| WAN do firewall | O que significa | O que fazer |
|---|---|---|
| Igual ao IP do passo 1 | O IP público está direto no firewall | Ótimo, siga em frente |
| `192.168.x.x`, `10.x.x.x` ou `172.16-31.x.x` | Existe um modem ou roteador da operadora antes do firewall | Peça à operadora para colocar o modem em **modo bridge**, ou crie o redirecionamento também no modem |
| `100.64.x.x` a `100.127.x.x` | **CGNAT**: a operadora divide o IP com outros clientes, e conexões de fora não chegam | Contrate um **IP fixo** com a operadora. Sem isso, não funciona |

3. Para confirmar se o IP é **fixo**, consulte o contrato ou pergunte à operadora: "o link tem IP público fixo?". Links empresariais costumam ter. Se o IP for dinâmico, ele muda de tempos em tempos e os apps perdem a conexão até o DNS ser corrigido.

## 3. Instalar na VM

1. Copie a pasta `servidor\windows` para a VM, por exemplo em `C:\Instalacao\windows`.
2. Abra o **PowerShell como Administrador** nessa pasta e rode:

   ```powershell
   powershell -ExecutionPolicy Bypass -File .\instalar.ps1
   ```

O instalador faz o seguinte:
- Baixa o servidor oficial do RustDesk e **confere o hash SHA-256**. Se o arquivo tiver sido alterado, a instalação é abortada.
- Instala em `C:\ConfialtivaRemote-Server`. A pasta das chaves fica acessível só para SYSTEM e Administradores.
- Registra `hbbs` e `hbbr` para iniciarem com o Windows, como SYSTEM e com reinício automático em caso de falha.
- Cria as regras no Firewall do Windows, só para as portas necessárias e só para esses dois programas.
- No final, mostra a **chave pública**, o **IP interno** e o **IP público**. Anote os três.

**Faça backup** do arquivo `C:\ConfialtivaRemote-Server\data\id_ed25519` (a chave privada) num local seguro, como o cofre de senhas da TI. Se ele se perder, todos os clientes precisam de um novo instalador.

## 4. Redirecionamento no firewall da empresa

Crie **exatamente** estas regras, do IP público para o IP interno da VM:

| Porta externa | Protocolo | Destino interno | Origem permitida |
|---|---|---|---|
| 21115 | TCP | VM:21115 | Qualquer |
| 21116 | TCP | VM:21116 | Qualquer |
| 21116 | **UDP** | VM:21116 | Qualquer |
| 21117 | TCP | VM:21117 | Qualquer |

**Não redirecione** nenhuma outra porta para a VM, em especial: 3389 (RDP), 21114, 21118 e 21119. O acesso de administração à VM deve ser feito só pela rede interna ou pela VPN da empresa.

### FortiGate
1. **Policy & Objects → Virtual IPs → Create New → Virtual IP**:
   - Interface: a WAN. External IP: o IP público. Mapped IP: o IP interno da VM.
   - Ative **Port Forwarding**. Crie um VIP para TCP 21115-21117 (externa = mapeada) e outro para UDP 21116.
2. **Policy & Objects → Firewall Policy → Create New**:
   - Incoming: WAN. Outgoing: a interface ou VLAN da VM. Source: all. Destination: os dois VIPs.
   - Service: crie serviços personalizados com TCP 21115-21117 e UDP 21116. Action: ACCEPT. NAT: desativado. Ative o log.

### Sophos Firewall (XGS / SFOS)
1. **Rules and policies → NAT rules → Add NAT rule → Server access assistant (DNAT)**.
2. Informe o IP interno da VM, o IP público (WAN) e os serviços TCP 21115-21117 e UDP 21116.
3. O assistente cria a regra de firewall correspondente. Confira se ela libera só esses serviços.

### SonicWall
1. **Quick Configuration → Public Server Wizard** (ou **Policy → Rules and Policies → NAT Policies** + **Access Rules**).
2. Server type: Other. Services: crie um grupo com TCP 21115-21117 e UDP 21116.
3. Private IP: a VM. Public IP: o IP da WAN. O assistente cria a política de NAT e a regra WAN→LAN/DMZ.

## 5. DNS no Microsoft 365

1. Acesse **admin.microsoft.com → Configurações → Domínios** e clique em `confialtiva.com.br`.
2. Abra a aba **Registros DNS → + Adicionar registro**.
3. Preencha: Tipo **A**, Nome **remoto**, Endereço IPv4: **o IP público**, TTL: **1 hora**. Salve.
4. Em alguns minutos, confira em qualquer computador:

   ```powershell
   Resolve-DnsName remoto.confialtiva.com.br -Server 1.1.1.1
   ```

Se a opção de adicionar registros não aparecer, o DNS do domínio está em outro lugar (Registro.br, provedor da hospedagem etc.). Nesse caso, crie o mesmo registro A lá.

### Computadores dentro da empresa

De dentro da rede, `remoto.confialtiva.com.br` aponta para o IP público, e alguns firewalls não deixam a rede "sair e voltar" (hairpin NAT). Escolha uma solução:
- **DNS interno (recomendado):** se a empresa tem Active Directory, crie no DNS interno uma zona `remoto.confialtiva.com.br` com um registro A (nome em branco) apontando para o **IP interno** da VM.
- Ou ative o **hairpin/loopback NAT** no firewall.

## 6. Gerar o app apontando para o servidor

Com a chave pública em mãos, siga a **seção 5 do [README principal](../README.md)**: definir as variáveis `CONFIALTIVA_RENDEZVOUS_SERVER` e `CONFIALTIVA_SERVER_KEY` no GitHub e rodar o build. Se preferir, me passe a chave que eu faço essa parte.

## 7. Validar as regras de segurança

1. **Na VM**, em PowerShell como Administrador:

   ```powershell
   powershell -ExecutionPolicy Bypass -File .\validar-servidor.ps1
   ```

   O script confere processos e inicialização automática, `-k _`, portas, Firewall do Windows, RDP, permissão da chave privada, IP público × DNS e atualizações do Windows. O resultado precisa ser **"aprovado"**.

2. **De fora da empresa**, num notebook no 4G, use o script `validar-externo.ps1`, que fica na pasta `servidor`:

   ```powershell
   powershell -ExecutionPolicy Bypass -File validar-externo.ps1 remoto.confialtiva.com.br
   ```

   Ele confirma que só 21115, 21116 e 21117 respondem pela internet. É o teste que comprova que o firewall da empresa não expõe mais nada da VM, como RDP ou SMB.

3. **No app:** faça os 9 testes da **seção 6.3 do [README principal](../README.md)**: senha única, chave obrigatória, servidor travado, relay etc.

## 8. Manutenção

| Tarefa | Como |
|---|---|
| Ver se está rodando | Agendador de Tarefas → tarefas "Confialtiva hbbs" e "Confialtiva hbbr" |
| Reiniciar | `Stop-ScheduledTask "Confialtiva hbbs"; Start-ScheduledTask "Confialtiva hbbs"` (o mesmo para hbbr) |
| Atualizar para uma versão nova | Atualizar `$Version` e `$ZipHash` no `instalar.ps1` e rodar de novo. As chaves em `data` são mantidas |
| Validação | Mensal e após qualquer mudança no firewall: `validar-servidor.ps1` e `validar-externo.ps1` |
