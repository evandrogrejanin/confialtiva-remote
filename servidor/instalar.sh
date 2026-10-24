#!/usr/bin/env bash
# Instala o servidor Confialtiva Remote em Ubuntu 22.04/24.04.
# Uso: sudo bash instalar.sh <IP_DO_ADMINISTRADOR>
#   IP_DO_ADMINISTRADOR: IP publico de onde a TI acessa o SSH (ex.: IP fixo do escritorio).
#   Sem ele o SSH fica aberto para qualquer IP (protegido apenas pelo fail2ban).
set -euo pipefail

ADMIN_IP="${1:-}"
DIR="/opt/confialtiva-remote"
SRC="$(cd "$(dirname "$0")" && pwd)"

if [ "$(id -u)" -ne 0 ]; then
  echo "Execute com sudo: sudo bash instalar.sh <IP_DO_ADMINISTRADOR>"; exit 1
fi

CURRENT_IP="${SSH_CLIENT%% *}"
if [ -n "$ADMIN_IP" ] && [ -n "$CURRENT_IP" ] && [ "$CURRENT_IP" != "$ADMIN_IP" ]; then
  echo "Voce esta conectado de $CURRENT_IP, mas informou $ADMIN_IP."
  echo "O firewall bloquearia esta sessao SSH. Confira o IP e rode de novo."
  exit 1
fi

echo "==> Atualizando o sistema"
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get upgrade -y
apt-get install -y docker.io docker-compose-v2 ufw fail2ban unattended-upgrades
systemctl enable --now docker
dpkg-reconfigure -f noninteractive unattended-upgrades

echo "==> Firewall (ufw)"
ufw --force reset
ufw default deny incoming
ufw default allow outgoing
if [ -n "$ADMIN_IP" ]; then
  ufw allow from "$ADMIN_IP" to any port 22 proto tcp comment 'SSH admin'
else
  echo "AVISO: SSH liberado para qualquer IP. Rode novamente informando o IP do administrador."
  ufw limit 22/tcp comment 'SSH'
fi
ufw allow 21115/tcp comment 'Confialtiva teste NAT'
ufw allow 21116/tcp comment 'Confialtiva ID/registro'
ufw allow 21116/udp comment 'Confialtiva ID/registro UDP'
ufw allow 21117/tcp comment 'Confialtiva relay'
ufw --force enable

echo "==> fail2ban para SSH"
systemctl enable --now fail2ban

echo "==> Subindo hbbs/hbbr"
mkdir -p "$DIR/data"
cp "$SRC/docker-compose.yml" "$DIR/docker-compose.yml"
cd "$DIR"
docker compose pull
docker compose up -d

for _ in $(seq 1 30); do
  [ -f "$DIR/data/id_ed25519.pub" ] && break
  sleep 1
done
chmod 600 "$DIR/data/id_ed25519"

echo
echo "================================================================"
echo " Servidor instalado."
echo " Chave publica (CONFIALTIVA_SERVER_KEY no GitHub):"
echo
cat "$DIR/data/id_ed25519.pub"; echo
echo
echo " Guarde uma copia segura de $DIR/data/id_ed25519 (chave privada)."
echo " Se ela for perdida, todos os clientes precisam ser reinstalados."
echo " Proximo passo: sudo bash validar-servidor.sh"
echo "================================================================"
