#!/usr/bin/bash
# helios-suivi-backup.sh — archive le service de suivi (tar.gz + ACL + sha256), garde 7 archives.
# Sortie : 0 OK · 1 erreur interne · 2 verrou deja pris · 3 prerequis manquant
set -Eeuo pipefail
IFS=$'\n\t'
readonly DEST="${HELIOS_DEST:-/srv/helios/archives/suivi}"
readonly KEEP=7
readonly TAG=helios-suivi-backup
readonly ITEMS=(
    srv/helios/suivi
    etc/systemd/system/helios-suivi.service
    etc/systemd/system/helios-suivi-publish.service
    etc/systemd/system/helios-suivi-publish.timer
    etc/systemd/system/helios-suivi-backup.service
    etc/systemd/system/helios-suivi-backup.timer
    etc/sudoers.d/92-helios-suivi
    etc/zabbix/zabbix_agent2.d/helios-suivi.conf
    usr/local/sbin/helios-suivi-publish.sh
    usr/local/sbin/helios-suivi-backup.sh
)
TMP=""

log() { logger -t "$TAG" -p "daemon.${1}" -- "$2" ; }
die() { log err "$1" ; exit "${2:-1}" ; }
cleanup() { local rc=$? ; [[ -n "$TMP" ]] && rm -f -- "$TMP" ; log info "fin d execution rc=${rc}" ; return 0 ; }
trap cleanup EXIT
trap 'die "erreur inattendue ligne ${LINENO}" 1' ERR
trap 'die "interrompu par signal" 1' INT TERM

exec 9<"$0"
flock -n 9 || { log warning "une autre instance tourne deja" ; exit 2 ; }

command -v tar >/dev/null && command -v sha256sum >/dev/null || die "tar ou sha256sum absent" 3
[[ -d "${DEST%/*}" ]] || die "repertoire parent absent : ${DEST%/*}" 3
for f in "${ITEMS[@]}"; do [[ -e "/$f" ]] || die "element a sauvegarder absent : /$f" 3 ; done
log info "demarrage"

install -d -o helios -g helios -m 0750 "$DEST"
name="suivi-$(date +%Y%m%d-%H%M%S).tar.gz"
TMP="$(mktemp "${DEST}/.suivi.XXXXXX")"
tar --acls -czpf "$TMP" -C / -- "${ITEMS[@]}"
tar -tzf "$TMP" > /dev/null || die "archive illisible" 1
chown helios:helios "$TMP" ; chmod 0640 "$TMP"
mv -f -- "$TMP" "${DEST}/${name}"
TMP=""
( cd "$DEST" && sha256sum "$name" > "${name}.sha256" )
chown helios:helios "${DEST}/${name}.sha256" ; chmod 0640 "${DEST}/${name}.sha256"

mapfile -t all < <(find "$DEST" -maxdepth 1 -type f -name 'suivi-*.tar.gz' | sort)
if (( ${#all[@]} > KEEP )); then
    for f in "${all[@]:0:${#all[@]}-KEEP}"; do rm -f -- "$f" "${f}.sha256" ; done
fi
log info "archive ${DEST}/${name} creee (${#all[@]} presentes, ${KEEP} conservees)"
exit 0
