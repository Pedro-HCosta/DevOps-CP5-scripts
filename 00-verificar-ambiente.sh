#!/usr/bin/env bash
set +x
set -Eeuo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
missing=0
for tool in bash git java mvn az python3 curl sqlcmd; do
 if command -v "$tool" >/dev/null 2>&1; then printf 'OK: %s\n' "$tool"; else printf 'FALTA: %s\n' "$tool"; missing=1; fi
done
for file in "$SCRIPT_DIR"/*.sh; do bash -n "$file"; done
printf 'Java 17 é necessário; sqlcmd só é necessário para 03-executar-sql.sh.\n'
printf 'Este script não autentica nem cria recursos.\n'
exit "$missing"
