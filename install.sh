#!/bin/sh
# Hunter Forkop 0.1.0-rc2; SPDX-License-Identifier: GPL-2.0-or-later
# Installer overlay for upstream Forkop, not a replacement firmware.
set -eu
umask 077
TAG=hunter-forkop-24-v0.1.0-rc2
BASE=https://raw.githubusercontent.com/gerser777/Hunter-Forkop/$TAG
ENGINE=1.14.1-extended-2.7.2
PARSER_SHA=6c6bd5b22608c7b604077681f9b038b5a34746f52408282e92208c9f9d1a6b71
WORK= BACKUP= WATCHDOG= MUTATED=0
fail() { echo "ERROR: $*" >&2; exit 1; }
sha() { sha256sum "$1" | awk '{print $1}'; }
fetch() {
    if command -v curl >/dev/null 2>&1; then
        curl --proto '=https' --tlsv1.2 -fL --connect-timeout 15 --max-time 600 "$1" -o "$2"
    else
        wget -T 60 -O "$2" "$1"
    fi
    [ "$(sha "$2")" = "$3" ] || fail "Checksum mismatch: $(basename "$2")"
}
cleanup() {
    code=$?
    trap - EXIT INT TERM
    if [ "$MUTATED" = 1 ] && [ -n "$BACKUP" ] && [ ! -f "$BACKUP/accepted" ]; then
        echo "Restoring backup: $BACKUP"
        sh "$BACKUP/rollback.sh" || echo "Manual rollback required: $BACKUP/rollback.sh" >&2
    fi
    [ -z "$WORK" ] || rm -rf "$WORK"
    rmdir /tmp/hunter-forkop.lock 2>/dev/null || true
    exit "$code"
}
preflight() {
    [ "$(id -u)" = 0 ] || fail 'Run as root'
    [ -r /etc/openwrt_release ] || fail 'OpenWrt required'
    release=$(sed -n "s/^DISTRIB_RELEASE='\(.*\)'/\1/p" /etc/openwrt_release)
    case "$release" in 24.10.*) ;; *) fail 'Only OpenWrt 24.10.x is supported by this release' ;; esac
    [ "$(uname -m)" = aarch64 ] || fail 'This release supports ARM64 (aarch64) only'
    command -v opkg >/dev/null || fail 'opkg required'
    for cmd in sha256sum tar gzip; do command -v "$cmd" >/dev/null || fail "$cmd required"; done
    command -v curl >/dev/null 2>&1 || command -v wget >/dev/null 2>&1 || fail 'curl or wget required'
    # Do not replace other routing stacks or unknown Forkop revisions.
    for pkg in podkop podkop-plus luci-app-passwall luci-app-passwall2 https-dns-proxy nextdns; do
        if opkg status "$pkg" 2>/dev/null | grep -q '^Status:.* installed'; then fail "Conflicting package: $pkg"; fi
    done
    version=$(opkg status forkop 2>/dev/null | sed -n 's/^Version: //p')
    [ -z "$version" ] || [ "$version" = 1.0.5 ] || fail "Unsupported Forkop version: $version"
    available=$(df -Pk /overlay | awk 'NR==2 {print $4}')
    [ "${available:-0}" -ge 35000 ] || fail 'At least 35 MB free overlay needed for install and rollback'
    memory=$(awk '/MemAvailable:/ {print $2}' /proc/meminfo)
    [ "${memory:-0}" -ge 130000 ] || fail 'At least 130 MB available RAM needed for download and unpacking'
    echo "Compatible platform: OpenWrt $release, ARM64; Forkop ${version:-not installed}"
}
backup() {
    BACKUP=/root/hunter-backups/installer-$(date -u +%Y%m%dT%H%M%SZ)-$$
    mkdir -p "$BACKUP"
    opkg list-installed > "$BACKUP/packages.before"
    paths='etc/config'
    for item in etc/forkop etc/sing-box etc/init.d/forkop etc/init.d/sing-box usr/lib/forkop/subscription/parser.uc usr/sbin/hunter-forkop; do
        [ ! -e "/$item" ] || paths="$paths $item"
    done
    tar -C / -czf "$BACKUP/config.tar.gz" $paths
    if [ -f /usr/bin/sing-box ]; then gzip -c /usr/bin/sing-box > "$BACKUP/sing-box.old.gz"; fi
    if pidof sing-box >/dev/null; then touch "$BACKUP/was-running"; fi
    cat > "$BACKUP/rollback.sh" <<'ROLLBACK'
#!/bin/sh
set -eu
B=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
mkdir "$B/rollback.lock" 2>/dev/null || exit 0
trap 'rmdir "$B/rollback.lock"' EXIT
[ ! -e /etc/init.d/forkop ] || /etc/init.d/forkop stop || true
[ ! -e /etc/init.d/sing-box ] || /etc/init.d/sing-box stop || true
# Remove only top-level packages that did not exist before this installer.
for p in luci-i18n-forkop-ru luci-app-forkop forkop sing-box; do
    if ! grep -q "^$p - " "$B/packages.before"; then opkg remove "$p" >/dev/null 2>&1 || true; fi
done
rm -f /etc/forkop/sing-box-variant /etc/forkop/sing-box-version /usr/sbin/hunter-forkop
if [ -f "$B/sing-box.old.gz" ]; then gzip -dc "$B/sing-box.old.gz" > /usr/bin/sing-box; chmod 755 /usr/bin/sing-box; fi
tar -C / -xzf "$B/config.tar.gz"
if [ -d /etc/forkop/subscription-cache ]; then
    mkdir -p /tmp/sing-box/subscriptions
    cp /etc/forkop/subscription-cache/* /tmp/sing-box/subscriptions/ 2>/dev/null || true
fi
if [ -f "$B/was-running" ]; then /etc/init.d/forkop start; fi
touch "$B/rolled-back"
ROLLBACK
    chmod 700 "$BACKUP/rollback.sh"
    sha256sum "$BACKUP"/*.gz > "$BACKUP/SHA256SUMS"
    echo "Backup: $BACKUP"
    echo "Rollback: sh $BACKUP/rollback.sh"
}
health() {
    # An HTTP request through the selected live outbound, not just a PID check.
    controller=$(ucode -e 'let f=require("fs");let c=json(f.readfile("/etc/sing-box/config.json"));print(c.experimental.clash_api.external_controller);')
    secret=$(ucode -e 'let f=require("fs");let c=json(f.readfile("/etc/sing-box/config.json"));print(c.experimental.clash_api.secret || "");')
    case "$controller" in *:*) ;; *) return 1 ;; esac
    tries=0
    while [ "$tries" -lt 20 ]; do
        if curl -fsS --max-time 8 -H "Authorization: Bearer $secret" \
            "http://$controller/proxies/main-out/delay?timeout=6000&url=https%3A%2F%2Fwww.gstatic.com%2Fgenerate_204" > "$WORK/health.json"; then
            if ucode -e 'let f=require("fs");let r=json(f.readfile(ARGV[0]));exit(type(r.delay)=="int" && r.delay>0 ? 0 : 1);' "$WORK/health.json"; then return 0; fi
        fi
        tries=$((tries+1)); sleep 2
    done
    return 1
}
case "${1:-install}" in
    --help|-h)
        echo 'Usage: sh install.sh [--check|install]'; exit 0 ;;
    --check) preflight; echo 'Read-only checks passed. No settings changed.'; exit 0 ;;
    install) ;;
    *) fail 'Unknown argument. Use --help' ;;
esac
preflight
mkdir /tmp/hunter-forkop.lock 2>/dev/null || fail 'Another installer is running'
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP
WORK=$(mktemp -d /tmp/hunter-forkop.XXXXXX)
# Network/download failures occur before any configuration change.
fetch "$BASE/parser.uc" "$WORK/parser.uc" "$PARSER_SHA"
fetch "https://github.com/shtorm-7/sing-box-extended/releases/download/v$ENGINE/sing-box-$ENGINE-linux-arm64-compressed.tar.gz" "$WORK/engine.tar.gz" b22d044c44922068d57a17edb69d84befae527bdf41b4851e56f7f5daed1d452
tar -xzf "$WORK/engine.tar.gz" -C "$WORK"
engine=$(find "$WORK" -type f -name sing-box)
[ -n "$engine" ] && [ "$(sha "$engine")" = 9ee361a7ec9c89806ff42b8088f275464c7443d07aed8cbe4d5fb2f1a9e26d34 ] || fail 'Unexpected engine archive'
chmod 700 "$engine"
fetch https://github.com/ushan0v/forkop/releases/download/1.0.5/forkop_1.0.5.ipk "$WORK/forkop.ipk" 61dd2c35853d986f90e233fca524996214606711a53547a9ba1187d7c8f3e1df
fetch https://github.com/ushan0v/forkop/releases/download/1.0.5/luci-app-forkop_1.0.5.ipk "$WORK/luci.ipk" 463cb5d1dc1de0edfc9ed8dd56b8d75f14bb8ffd7c8830cbb190f6aa50a082ef
fetch https://github.com/ushan0v/forkop/releases/download/1.0.5/luci-i18n-forkop-ru_1.0.5.ipk "$WORK/ru.ipk" 541d8e7f3170c680b66f3b46af7587358a3556ab4ccf27dd798c6a1f1f164186
backup
MUTATED=1
opkg update
if ! command -v timeout >/dev/null 2>&1; then opkg install coreutils-timeout; fi
timeout 40 "$engine" version >/dev/null
if [ -f /etc/sing-box/config.json ]; then timeout 60 "$engine" check -c /etc/sing-box/config.json -D /usr/share/sing-box; fi
# Preserve the existing Forkop revision and configuration; install only if absent.
if [ -z "$version" ]; then timeout 180 opkg install "$WORK/forkop.ipk" "$WORK/luci.ipk" "$WORK/ru.ipk"; fi
if ! opkg status sing-box 2>/dev/null | grep -q '^Status:.* installed'; then timeout 180 opkg install sing-box; fi
# The detached watchdog survives loss of the SSH connection.
sh -c 'trap "" HUP; sleep 900; [ -f "$1/accepted" ] || sh "$1/rollback.sh" >"$1/watchdog.log" 2>&1' sh "$BACKUP" </dev/null >/dev/null 2>&1 &
WATCHDOG=$!
/etc/init.d/forkop stop || true
/etc/init.d/sing-box stop || true
cat "$engine" > /usr/bin/sing-box
chmod 755 /usr/bin/sing-box
cp "$WORK/parser.uc" /usr/lib/forkop/subscription/parser.uc
mkdir -p /etc/forkop
printf 'extended-compressed\n' > /etc/forkop/sing-box-variant
printf '%s\n' "$ENGINE" > /etc/forkop/sing-box-version
if [ -f "$BACKUP/was-running" ]; then
    timeout 180 /etc/init.d/forkop start > "$BACKUP/start.log" 2>&1
    health || fail 'Live HTTPS health check failed'
    nslookup example.com 127.0.0.42 >/dev/null || fail 'DNS health check failed'
else
    echo 'Installed without starting VPN. Add your subscription in LuCI > Forkop first.'
fi
touch "$BACKUP/accepted"
echo 'Hunter Forkop installed. Verify browsing from a LAN device.'
echo 'Auto is configured per section in LuCI: priority group, direct first, LTE second.'
echo 'No subscription credentials are included. Your existing manual profiles are preserved.'
