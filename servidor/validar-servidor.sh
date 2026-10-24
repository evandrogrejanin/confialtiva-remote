#!/usr/bin/env bash
# Valida as regras de seguranca do servidor Confialtiva Remote.
# Uso: sudo bash validar-servidor.sh
set -uo pipefail

DIR="/opt/confialtiva-remote"
FAIL=0
ok()   { echo "  [OK]    $1"; }
bad()  { echo "  [FALHA] $1"; FAIL=1; }
warn() { echo "  [AVISO] $1"; }

echo "1. Containers"
for c in confialtiva-hbbs confialtiva-hbbr; do
  if [ "$(docker inspect -f '{{.State.Running}}' "$c" 2>/dev/null)" = "true" ]; then ok "$c rodando"; else bad "$c parado"; fi
done
if docker inspect -f '{{join .Config.Cmd " "}}' confialtiva-hbbs 2>/dev/null | grep -q -- '-k _'; then
  ok "hbbs exige a chave do servidor (-k _)"
else
  bad "hbbs sem -k _: qualquer cliente RustDesk poderia usar este servidor"
fi

echo "2. Portas em escuta"
LISTEN="$(ss -Hltnu)"
for p in "tcp:21115" "tcp:21116" "udp:21116" "tcp:21117"; do
  proto="${p%%:*}"; port="${p##*:}"
  if echo "$LISTEN" | grep -E "^$proto" | grep -qE "[:.]$port\b"; then ok "$proto/$port escutando"; else bad "$proto/$port nao esta escutando"; fi
done
for port in 21114 21118 21119; do
  if echo "$LISTEN" | grep -qE "[:.]$port\b"; then warn "porta $port escutando (nao e usada; deve ficar bloqueada no firewall)"; fi
done

echo "3. Firewall (ufw)"
UFW="$(ufw status verbose 2>/dev/null)"
echo "$UFW" | grep -q "Status: active" && ok "ufw ativo" || bad "ufw inativo"
echo "$UFW" | grep -q "deny (incoming)" && ok "entrada bloqueada por padrao" || bad "entrada nao esta bloqueada por padrao"
ALLOWED="$(ufw status | grep -E 'ALLOW|LIMIT' | awk '{print $1}' | sort -u | tr '\n' ' ')"
echo "      portas liberadas: $ALLOWED"
for rule in $ALLOWED; do
  case "$rule" in
    21115/tcp|21116/tcp|21116/udp|21117/tcp|22|22/tcp) ;;
    *) bad "regra inesperada liberada: $rule" ;;
  esac
done
if ufw status | grep -E '^22(/tcp)? ' | grep -q 'Anywhere'; then
  warn "SSH aberto para qualquer IP: restrinja ao IP do administrador"
else
  ok "SSH restrito por IP"
fi

echo "4. SSH"
SSHD="$(sshd -T 2>/dev/null)"
echo "$SSHD" | grep -q '^permitrootlogin no' && ok "login root desativado" || warn "PermitRootLogin nao esta 'no'"
echo "$SSHD" | grep -q '^passwordauthentication no' && ok "login por senha desativado (somente chave)" || warn "login SSH por senha ativo: prefira chave SSH"
systemctl is-active --quiet fail2ban && ok "fail2ban ativo" || warn "fail2ban inativo"

echo "5. Chaves do servidor"
if [ -f "$DIR/data/id_ed25519" ]; then
  perm="$(stat -c '%a' "$DIR/data/id_ed25519")"
  [ "$perm" = "600" ] && ok "chave privada com permissao 600" || bad "chave privada com permissao $perm (use chmod 600)"
  echo "      chave publica: $(cat "$DIR/data/id_ed25519.pub")"
else
  bad "chave privada nao encontrada em $DIR/data"
fi

echo "6. Atualizacoes"
systemctl is-enabled --quiet unattended-upgrades && ok "atualizacoes automaticas de seguranca ativas" || warn "unattended-upgrades desativado"
PENDING="$(apt list --upgradable 2>/dev/null | grep -c security || true)"
[ "$PENDING" = "0" ] && ok "sem atualizacoes de seguranca pendentes" || warn "$PENDING atualizacoes de seguranca pendentes"

echo
if [ "$FAIL" = "0" ]; then echo "RESULTADO: aprovado (revise os AVISOS, se houver)"; else echo "RESULTADO: reprovado, corrija as FALHAS acima"; fi
exit "$FAIL"
