#!/usr/bin/bash
# helios-suivi-publish.sh — publie www/etat.json depuis la derniere ligne de telemetrie.
# Sortie : 0 OK · 1 erreur interne · 2 verrou deja pris · 3 prerequis manquant
set -Eeuo pipefail
IFS=$'\n\t'
readonly SRC="${HELIOS_SRC:-/var/lib/helios/telemetry.csv}"
readonly WWW=/srv/helios/suivi/www
readonly OUT="${WWW}/etat.json"
readonly TAG=helios-suivi-publish
TMP=""

log() { logger -t "$TAG" -p "daemon.${1}" -- "$2" ; }
die() { log err "$1" ; exit "${2:-1}" ; }
cleanup() { local rc=$? ; [[ -n "$TMP" ]] && rm -f -- "$TMP" ; log info "fin d execution rc=${rc}" ; return 0 ; }
trap cleanup EXIT
trap 'die "erreur inattendue ligne ${LINENO}" 1' ERR
trap 'die "interrompu par signal" 1' INT TERM

exec 9<"$0"                              # verrou sur le script : pas d'ecriture necessaire
flock -n 9 || { log warning "une autre instance tourne deja" ; exit 2 ; }

[[ -r "$SRC" ]] || die "telemetrie illisible : ${SRC}" 3
[[ -d "$WWW" && -w "$WWW" ]] || die "repertoire non inscriptible : ${WWW}" 3
log info "demarrage"

line="$(tail -n 1 -- "$SRC")"
[[ -n "$line" ]] || die "telemetrie vide : ${SRC}" 1
IFS=, read -r ts load mem extra <<< "$line"
re_ts='^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}[+-][0-9]{2}:[0-9]{2}$'
[[ "$ts" =~ $re_ts && "$load" =~ ^[0-9]+(\.[0-9]+)?$ && "$mem" =~ ^[0-9]+$ && -z "$extra" ]] \
    || die "ligne de telemetrie invalide : ${line}" 1
n="$(wc -l < "$SRC")"

TMP="$(mktemp "${WWW}/.etat.json.XXXXXX")"
printf '{"genere":"%s","hote":"%s","derniere_mesure":"%s","charge_1min":%s,"mem_dispo_ko":%s,"mesures":%s}\n' \
    "$(date --iso-8601=seconds)" "$(uname -n)" "$ts" "$load" "$mem" "$n" > "$TMP"
python3 -m json.tool "$TMP" > /dev/null || die "json invalide" 1
chmod 0640 -- "$TMP"
mv -f -- "$TMP" "$OUT"                   # rename atomique : jamais de fichier a moitie ecrit
TMP=""
log info "publie ${OUT} (mesures=${n}, derniere=${ts})"
exit 0
