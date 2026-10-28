# Servidor Confialtiva Remote

O servidor tem dois serviços:

- **hbbs**: registro de IDs e intermediação das conexões.
- **hbbr**: relay, que repassa o tráfego quando a conexão direta entre os computadores não é possível.

Todo o tráfego entre técnico e cliente é criptografado de ponta a ponta. O servidor não vê a tela nem os arquivos.

> **Servidor Windows (VM na empresa):** siga o guia [windows/README.md](windows/README.md). Este documento cobre o VPS Linux, mas as seções 5 (gerar o app) e 6.3 (testes no app) valem para os dois.

## 1. Contratar o servidor

| Item | Recomendação |
|---|---|
| Tipo | VPS Linux com IP público fixo |
| Sistema | Ubuntu Server 24.04 LTS |
| Recursos | 1 vCPU e 1 GB de RAM atendem cerca de 100 técnicos simultâneos. Use 2 vCPU e 2 GB para folga |
| Disco | 20 GB |
| Tráfego | Pelo menos 1 TB/mês. O relay consome banda quando a conexão direta falha |
| Região | **Brasil (São Paulo)**: menor latência e dados no país, o que ajuda na LGPD |

Ao criar o servidor, cadastre uma **chave SSH**. Evite usar só senha.

## 2. Criar o endereço (DNS)

No DNS do domínio `confialtiva.com.br`, crie um registro:

| Tipo | Nome | Valor |
|---|---|---|
| A | `remoto` | IP público do servidor |

O endereço final fica `remoto.confialtiva.com.br`. Usar um nome em vez do IP permite trocar de servidor sem reinstalar os clientes.

## 3. Firewall do provedor (Security Group)

Se o provedor tiver firewall próprio (AWS, Azure, Oracle, GCP, Hostinger etc.), configure as mesmas regras lá, além do firewall do servidor:

| Porta | Protocolo | Origem | Para que serve |
|---|---|---|---|
| 21115 | TCP | Qualquer | Teste de tipo de NAT |
| 21116 | TCP | Qualquer | Registro de ID e conexão |
| 21116 | **UDP** | Qualquer | Registro de ID e conexão direta |
| 21117 | TCP | Qualquer | Relay |
| 22 | TCP | **Só o IP do administrador** | SSH para manutenção |
| Qualquer outra | — | — | **Bloqueada** |

As portas 21114, 21118 e 21119 são do console web e do cliente web (versão Pro). Elas **não** são usadas e devem ficar fechadas.

## 4. Instalar

Do seu computador, envie esta pasta para o servidor e conecte por SSH:

```bash
scp -r servidor ubuntu@remoto.confialtiva.com.br:~/
```

```bash
ssh ubuntu@remoto.confialtiva.com.br
```

No servidor, rode o instalador informando o IP público de onde a TI faz a manutenção. Para descobrir esse IP, acesse https://ifconfig.me a partir do escritório:

```bash
sudo bash ~/servidor/instalar.sh SEU_IP_DO_ESCRITORIO
```

No final ele mostra a **chave pública** do servidor, um texto de cerca de 44 caracteres terminado em `=`. Guarde esse valor.

**Faça backup** do arquivo `/opt/confialtiva-remote/data/id_ed25519` (a chave privada) num local seguro. Se ele se perder, todos os clientes precisam de um novo instalador.

## 5. Gerar o instalador apontando para o servidor

No computador onde o projeto está, rode os três comandos abaixo, trocando a chave pela que o instalador mostrou:

```bash
gh variable set CONFIALTIVA_RENDEZVOUS_SERVER --repo evandrogrejanin/confialtiva-remote --body "remoto.confialtiva.com.br"
```

```bash
gh variable set CONFIALTIVA_SERVER_KEY --repo evandrogrejanin/confialtiva-remote --body "COLE_A_CHAVE_PUBLICA_AQUI"
```

```bash
gh workflow run confialtiva-windows.yml --repo evandrogrejanin/confialtiva-remote
```

O mesmo pode ser feito pelo site: **Settings → Secrets and variables → Actions → Variables** e depois **Actions → Confialtiva Remote - Windows → Run workflow**.

O app sai com servidor e chave **travados**: o usuário não consegue trocá-los nas configurações.

## 6. Validar as regras de segurança

Faça as três etapas. Só considere o servidor pronto quando todas passarem.

### 6.1 No servidor

```bash
sudo bash ~/servidor/validar-servidor.sh
```

O script confere:

| # | Regra | Esperado |
|---|---|---|
| 1 | Containers hbbs e hbbr | Rodando, com `-k _` (só aceita clientes com a chave) |
| 2 | Portas em escuta | 21115/tcp, 21116/tcp, 21116/udp e 21117/tcp |
| 3 | Firewall (ufw) | Ativo, entrada bloqueada por padrão, só as portas da tabela liberadas |
| 4 | SSH | Restrito ao IP do admin, sem login root, de preferência só com chave |
| 5 | Chave privada | Permissão 600 |
| 6 | Atualizações | Atualizações automáticas de segurança ativas |

O resultado precisa ser **"aprovado"**. Itens marcados como `[AVISO]` são recomendações; itens marcados como `[FALHA]` precisam ser corrigidos.

### 6.2 De fora do servidor

Num notebook **fora da rede do servidor** (por exemplo, no 4G), abra o PowerShell na pasta `servidor`:

```bash
powershell -ExecutionPolicy Bypass -File validar-externo.ps1 remoto.confialtiva.com.br
```

Esse script testa duas coisas: se 21115, 21116 e 21117 respondem, e se todas as outras portas comuns estão **fechadas**, incluindo banco de dados, RDP e painel web.

### 6.3 Testes no aplicativo

| # | Teste | Como fazer | Esperado |
|---|---|---|---|
| 1 | Conexão com o servidor | Abra o Confialtiva Remote | Status **"Pronto"** embaixo, com um ID de 9 dígitos |
| 2 | Servidor travado | Configurações → Rede | Servidor e chave aparecem e não podem ser editados |
| 3 | Chave obrigatória | Num PC de teste, instale o RustDesk **oficial**, aponte para `remoto.confialtiva.com.br` **sem** a chave e tente conectar num cliente Confialtiva | A conexão **falha**: o servidor recusa quem não tem a chave |
| 4 | Senha única | Conecte usando a senha de 8 caracteres que aparece no cliente | Conecta, e **a senha muda** logo em seguida no cliente |
| 5 | Senha reutilizada | Encerre a sessão e tente de novo com a mesma senha | **Recusada**: a senha só vale uma vez |
| 6 | Tentativas erradas | Erre a senha 10 vezes seguidas | A senha é trocada automaticamente |
| 7 | Aceite por clique | Conecte sem informar a senha | O cliente vê quem está pedindo e precisa clicar em **Aceitar** |
| 8 | Sem senha permanente | Configurações → Segurança | Não é possível definir senha permanente |
| 9 | Relay | Conecte entre duas redes diferentes (ex.: 4G e escritório) | Conecta; no servidor, `docker logs confialtiva-hbbr` mostra a sessão |

Registre a data e o resultado de cada teste. Esse registro serve como evidência de segurança para a LGPD (art. 46 e 49).

## 7. Manutenção

| Tarefa | Frequência | Comando |
|---|---|---|
| Rodar a validação | Mensal e após qualquer mudança | `sudo bash ~/servidor/validar-servidor.sh` |
| Ver os logs | Quando houver problema | `docker logs --tail 200 confialtiva-hbbs` |
| Atualizar o servidor RustDesk | Quando sair versão nova (troque a tag em `/opt/confialtiva-remote/docker-compose.yml`) | `cd /opt/confialtiva-remote && sudo docker compose pull && sudo docker compose up -d` |
| Conferir o backup da chave privada | Semestral | — |
