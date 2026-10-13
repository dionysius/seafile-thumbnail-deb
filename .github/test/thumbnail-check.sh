#!/bin/bash
# Exercise the thumbnail server through seafile-server's nginx example: set
# ENABLE_THUMBNAIL_SERVER in seahub_settings.py and uncomment the example's /thumbnail/ route,
# then fetch a thumbnail per sample file and check that seahub's listing offers the server's
# thumbnails. Run after seafile-deb's proxy-check.sh, which sets up nginx under
# seafile.example.com and the proxytest account.
#
# Runs IN PLACE as root, requires systemd - ephemeral testbed only.
#
# Usage: thumbnail-check.sh [--out FILE]
set -u
OUT="${OUT:-/dev/stdout}"
HOST=seafile.example.com
B="https://$HOST"
U=proxytest@example.com; P=proxytest-password-123
PY=/usr/lib/seafile-thumbnail-server/venv/bin/python
SITE=/etc/nginx/sites-available/seafile
info()  { printf '\n========== %s ==========\n' "$1"; }
error() { local code="$1"; shift; echo "$*" >&2; exit "$code"; }
while [ $# -gt 0 ]; do
  case "$1" in
    --out) OUT="$2"; shift 2 ;;
    -h|--help) sed -n '2,10p' "$0"; exit 0 ;;
    *) error 2 "unknown option: $1" ;;
  esac
done
[ -d /run/systemd/system ] || error 4 "systemd is not running (/run/systemd/system missing)"
[ -f "$SITE" ] || error 4 "$SITE missing, run seafile-deb's proxy-check.sh first"
rc=0; rows=()
ok()   { echo "OK   $1"; rows+=("| $1 | ✅ |"); }
fail() { echo "FAIL $1${2:+: $2}"; rows+=("| $1 | ❌ |"); rc=1; }
http() { curl -sS -k -o /dev/null -w '%{http_code}' --max-time 30 "$@" 2>/dev/null || echo 000; }

info "Switch seahub and the proxy to the thumbnail server"
# set the value instead of uncommenting the template's
sed -i -E 's|^#? *ENABLE_THUMBNAIL_SERVER *=.*|ENABLE_THUMBNAIL_SERVER = True|' /etc/seafile/seahub_settings.py
grep -q '^ENABLE_THUMBNAIL_SERVER = True' /etc/seafile/seahub_settings.py \
  || echo 'ENABLE_THUMBNAIL_SERVER = True' >> /etc/seafile/seahub_settings.py
sed -i '/#location \/thumbnail\//,/#}/ s|^    #|    |' "$SITE"
sed -n '/^    location \/thumbnail\//,/}/p' "$SITE" | grep -q 'proxy_pass http://127.0.0.1:8088;' \
  && ok "nginx example routes /thumbnail/ to 127.0.0.1:8088" || fail "nginx example routes /thumbnail/ to 127.0.0.1:8088"
nginx -t 2>&1 | tail -1
systemctl reload nginx
# both are Type=notify: restart returns once they listen
systemctl restart seahub.service seaf-thumbnail-server.service && ok "seahub and seaf-thumbnail-server restart" \
  || fail "seahub and seaf-thumbnail-server restart" "$(systemctl is-active seahub.service seaf-thumbnail-server.service | tr '\n' ' ')"
code=$(http "$B/thumbnail/ping")
[ "$code" = 200 ] && ok "ping via /thumbnail/" || fail "ping via /thumbnail/" "HTTP $code"

info "Login and a test library"
cj=$(mktemp)
http -c "$cj" "$B/accounts/login/" >/dev/null
csrf=$(awk '/sfcsrftoken/{print $7}' "$cj")
http -b "$cj" -c "$cj" -H "Origin: $B" -e "$B/accounts/login/" \
  -d "login=$U&password=$P&csrfmiddlewaretoken=$csrf" "$B/accounts/login/" >/dev/null
T=$(curl -sSk -d "username=$U&password=$P" "$B/api2/auth-token/" | sed -E 's/.*"token": ?"([^"]+)".*/\1/')
RID=$(curl -sSk -H "Authorization: Token $T" -d "name=thumbtest" "$B/api2/repos/" | grep -oE '"repo_id": ?"[0-9a-f-]{36}"' | grep -oE '[0-9a-f-]{36}')
UL=$(curl -sSk -H "Authorization: Token $T" "$B/api2/repos/$RID/upload-link/" | tr -d '"')
grep -q sessionid "$cj" && [ -n "$RID" ] && ok "login and test library" || fail "login and test library"

info "A thumbnail per sample file"
# Image.init() registers the JPEG codec the PDF writer needs
"$PY" -I -c "from PIL import Image; Image.init(); Image.new('RGB',(64,64),(30,200,30)).save('/tmp/ts.png'); Image.new('RGB',(200,280),(30,30,200)).save('/tmp/ts.pdf')"
# the server grabs the frame at 5 s
ffmpeg -loglevel error -y -f lavfi -i testsrc=duration=6:size=320x240:rate=10 -pix_fmt yuv420p /tmp/ts.mp4
echo '{"version": 1, "children": [{"type": "title", "id": "t1", "children": [{"text": "thumbtest", "id": "t2"}]}]}' > /tmp/ts.sdoc
for f in ts.png ts.pdf ts.mp4 ts.sdoc; do http -H "Authorization: Token $T" -F file=@/tmp/$f -F parent_dir=/ "$UL" >/dev/null; done
for f in ts.png ts.pdf ts.mp4 ts.sdoc; do
  code=$(curl -sSk -b "$cj" -o /tmp/thumb.out -w '%{http_code}' --max-time 90 "$B/thumbnail/$RID/256/$f")
  [ "$code" = 200 ] && [ -s /tmp/thumb.out ] && ok "thumbnail: $f" || fail "thumbnail: $f" "HTTP $code"
done

info "Seahub's listing offers the server's thumbnails"
curl -sSk -H "Authorization: Token $T" "$B/api/v2.1/repos/$RID/dir/?p=/&with_thumbnail=true" > /tmp/dir.json
missing=$("$PY" -I -c '
import json, sys
d = {e["name"]: e for e in json.load(open(sys.argv[1]))["dirent_list"]}
print(" ".join(n for n in ("ts.mp4", "ts.sdoc") if not d.get(n, {}).get("encoded_thumbnail_src")))
' /tmp/dir.json 2>&1)
[ -z "$missing" ] && ok "listing offers the server's thumbnails" || fail "listing offers the server's thumbnails" "$missing"

if [ "$rc" != 0 ]; then
  echo "--- nginx error log ---"; tail -n 30 /var/log/nginx/error.log 2>/dev/null || true
  echo "--- seaf-thumbnail-server journal ---"; journalctl -u seaf-thumbnail-server.service --no-pager -n 60 || true
  echo "--- seahub journal ---"; journalctl -u seahub.service --no-pager -n 40 || true
fi

info "Summary"
[ "$rc" -eq 0 ] && verdict="✅ thumbnail server: thumbnails through the shipped nginx example" \
                || verdict="❌ thumbnail server: see failures above"
[ "$OUT" = /dev/stdout ] || mkdir -p "$(dirname "$OUT")"
{
  echo ""
  echo "| Thumbnail check (nginx example) | Result |"
  echo "|---|---|"
  printf '%s\n' "${rows[@]}"
  echo ""
  echo "$verdict"
} | if [ "$OUT" = /dev/stdout ]; then cat; else cat >> "$OUT"; fi

[ "$rc" -eq 0 ] && echo "RESULT: PASS" || echo "RESULT: FAIL"
exit "$rc"
