#!/usr/bin/env bash
# helios-watch-auth.sh : bloque (ipset helios-blacklist) toute source ayant plus de 5 echecs SSH sur 10 min
# codes retour : 0 nominal, 2 si une instance tourne deja
set -Eeuo pipefail
IFS=$'\n\t'

TAG=helios-watch-auth
SEUIL=5
FENETRE='-10min'
IPSET=helios-blacklist
LISTE=/var/lib/helios/blocked.txt
BLANCHE=(192.168.56.1)
VERROU=/run/lock/helios-watch-auth.lock

log() { logger -t "$TAG" -- "$*"; }

exec 9>"$VERROU"
if ! flock -n 9; then
    log "instance deja en cours : abandon"
    exit 2
fi

touch "$LISTE"

while read -r ip; do
    [[ -n "$ip" ]] || continue
    firewall-cmd --ipset="$IPSET" --query-entry="$ip" >/dev/null 2>&1 \
        || firewall-cmd --ipset="$IPSET" --add-entry="$ip" >/dev/null
done < "$LISTE"

COMPTES=$(journalctl -u sshd --since "$FENETRE" -o cat --no-pager 2>/dev/null | awk '
    /Failed (password|publickey) for invalid user/ { next }
    /Invalid user [^ ]+ from [0-9.]+/ || /Failed (password|publickey) for [^ ]+ from [0-9.]+/ {
        for (i = 1; i <= NF; i++) if ($i == "from") { c[$(i+1)]++; break }
    }
    END { for (ip in c) print c[ip], ip }') || true

while read -r n ip; do
    [[ -n "${ip:-}" ]] || continue
    (( n > SEUIL )) || continue
    for w in "${BLANCHE[@]}"; do [[ "$ip" == "$w" ]] && continue 2; done
    grep -qxF "$ip" "$LISTE" && continue
    firewall-cmd --ipset="$IPSET" --add-entry="$ip" >/dev/null
    echo "$ip" >> "$LISTE"
    log "ALERTE : $ip bloquee ($n echecs sur $FENETRE)"
done <<< "$COMPTES"

exit 0
