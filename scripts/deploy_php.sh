#!/usr/bin/env bash
# Deploy the PHP backend (and optionally run a migration) to the live server over FTP.
#
#   HR_FTP_PASS='...' scripts/deploy_php.sh                # upload code only
#   HR_FTP_PASS='...' scripts/deploy_php.sh 001_multitenant   # upload + run migration once
#
# Never uploads config/database.php (the server keeps its own real credentials).
set -euo pipefail
: "${HR_FTP_PASS:?Set HR_FTP_PASS in the environment}"
HR_FTP_HOST="${HR_FTP_HOST:?set HR_FTP_HOST}"
HR_FTP_USER="${HR_FTP_USER:?set HR_FTP_USER}"
HR_FTP_DIR="${HR_FTP_DIR:-domains/quadrocloud.net/public_html/public_html/AlanadHR}"
HR_SITE_URL="${HR_SITE_URL:-https://alanadhr.quadrocloud.net}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)/php-backend"
cd "$ROOT"
FTP="ftp://$HR_FTP_HOST/$HR_FTP_DIR"
up() { curl -sS --fail --ftp-create-dirs -T "$1" -u "$HR_FTP_USER:$HR_FTP_PASS" "$FTP/$2"; }

count=0
while IFS= read -r f; do
  f="${f#./}"
  case "$f" in uploads/employees/.htaccess) ;; config/*|migrations/*|tests/*|*.sql|*.md|seed_admin.php|uploads/*) continue;; esac
  up "$f" "$f"; count=$((count+1))
done < <(find . -type f \( -name '*.php' -o -name '.htaccess' \))
echo "Uploaded $count files."

if [ "${1:-}" != "" ]; then
  M="migrations/$1.php"; [ -f "$M" ] || { echo "No such migration: $M"; exit 1; }
  TOKEN="$(openssl rand -hex 16)"
  TMP="$(mktemp)"; sed "s/__MIGRATION_TOKEN__/$TOKEN/" "$M" > "$TMP"
  up "$TMP" "migrate_once.php"; rm -f "$TMP"
  echo "--- running $1"
  curl -sS -m 300 "$HR_SITE_URL/migrate_once.php?t=$TOKEN"
  curl -sS -u "$HR_FTP_USER:$HR_FTP_PASS" "ftp://$HR_FTP_HOST/" -Q "-DELE $HR_FTP_DIR/migrate_once.php" -o /dev/null || true
  code="$(curl -s -o /dev/null -w '%{http_code}' "$HR_SITE_URL/migrate_once.php")"
  echo "--- migration file removed from server (now HTTP $code)"
fi
curl -s "$HR_SITE_URL/health"; echo
