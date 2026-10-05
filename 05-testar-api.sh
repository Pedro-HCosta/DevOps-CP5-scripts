#!/usr/bin/env bash
# Script independente. Defina/exporte as variáveis no Cloud Shell conforme o README.
set +x
set -Eeuo pipefail
trap 'printf "Falha na linha %s. A execução foi interrompida.\n" "$LINENO" >&2' ERR
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
die() { printf '%s\n' "$*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || die "Instale o comando: $1"; }
validate_variables() {
 : "${SUBSCRIPTION_ID:?Defina as variáveis do README no Cloud Shell.}"
 : "${RESOURCE_GROUP:?}" "${LOCATION:?}" "${WEBAPP_NAME:?}" "${SQL_SERVER_NAME:?}"
 : "${DATABASE_NAME:?}" "${PLAN_NAME:?}" "${WORKSPACE_NAME:?}" "${INSIGHTS_NAME:?}"
 [[ "$SUBSCRIPTION_ID" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$ ]] || die 'SUBSCRIPTION_ID inválido.'
 [[ "${SUFFIX:-}" =~ ^[a-z0-9]{6,20}$ ]] || die 'SUFFIX deve ter 6 a 20 letras minúsculas/dígitos.'
 [[ "$RESOURCE_GROUP" == "rg-dimdim-cp5-${SUFFIX}" ]] || die 'Use o grupo dedicado rg-dimdim-cp5-SUFFIX.'
}

azc() { az "$@" --subscription "$SUBSCRIPTION_ID" --only-show-errors; }
azure_ready() {
 need az
 az account show --output none --only-show-errors || die 'Entre primeiro: az login (ou az login --use-device-code).'
 az account set --subscription "$SUBSCRIPTION_ID" --only-show-errors
}
require_group() {
 [[ "$(azc group exists --name "$RESOURCE_GROUP" --output tsv)" == true ]] || die 'Grupo inexistente. Execute 01-criar-recursos.sh.'
 [[ "$(azc group show --name "$RESOURCE_GROUP" --query tags.projeto --output tsv)" == DimDimCP5 ]] || die 'Grupo sem a tag projeto=DimDimCP5. Operação recusada.'
}
credentials() {
 if [[ -z "${SQL_ADMIN_USER:-}" ]]; then
  read -r -s -p 'Usuário administrador SQL (oculto): ' SQL_ADMIN_USER; printf '\n'
 fi
 if [[ -z "${SQL_ADMIN_PASSWORD:-}" ]]; then
  read -r -s -p 'Senha SQL (oculta): ' SQL_ADMIN_PASSWORD; printf '\n'
 fi
 [[ -n "$SQL_ADMIN_USER" && -n "$SQL_ADMIN_PASSWORD" ]] || die 'Credenciais vazias.'
 export SQL_ADMIN_USER SQL_ADMIN_PASSWORD
}
need curl; need python3
interactive=false
if [[ "${1:-}" == --interativo ]]; then interactive=true; shift; fi
if [[ $# -gt 1 ]]; then die 'Use: 05-testar-api.sh [--interativo] [URL_BASE]'; fi
if [[ $# -eq 1 ]]; then base="${1%/}"; else
 validate_variables; azure_ready; require_group
 host="$(azc webapp show --resource-group "$RESOURCE_GROUP" --name "$WEBAPP_NAME" --query defaultHostName --output tsv)"
 base="https://$host"
fi
[[ "$base" == https://* || "$base" == http://localhost:* || "$base" == http://127.0.0.1:* ]] || die 'Use uma URL HTTPS ou localhost.'
umask 077
body_file="$(mktemp)"
trap 'rm -f -- "$body_file"' EXIT
call() {
 local method="$1" path="$2" expected="$3" body="${4:-}" code
 local args=(--silent --show-error --connect-timeout 15 --max-time 60 --request "$method" --output "$body_file" --write-out '%{http_code}')
 if [[ -n "$body" ]]; then args+=(--header 'Content-Type: application/json' --data "$body"); fi
 code="$(curl "${args[@]}" "$base$path")"
 printf '\n%s %s -> HTTP %s\n' "$method" "$path" "$code"
 [[ "$code" == "$expected" ]] || { cat "$body_file"; die "Esperado HTTP $expected. Interrompido; registros já criados podem permanecer."; }
 if [[ -s "$body_file" ]]; then python3 -m json.tool "$body_file"; fi
}
evidence() {
 if [[ "$interactive" == true ]]; then
  printf 'Em OUTRO terminal, execute 03-executar-sql.sh verificar-persistencia.sql e mostre o resultado.\n'
  read -r -p 'Depois da evidência, pressione Enter para continuar: ' _
 fi
}
get_id() { python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["id"])' "$body_file"; }
# Valores fictícios exclusivos de cada execução.
stamp="$(python3 -c 'import time; print(time.time_ns())')"
call POST /api/clientes 201 "{\"nome\":\"Cliente CP5 Demo\",\"email\":\"cp5-$stamp@example.com\"}"
cliente_id="$(get_id)"; printf 'ID criado do cliente: %s\n' "$cliente_id"; evidence
call GET /api/clientes 200; evidence
call GET "/api/clientes/$cliente_id" 200; evidence
call PUT "/api/clientes/$cliente_id" 200 "{\"nome\":\"Cliente CP5 Atualizado\",\"email\":\"cp5-$stamp@example.com\"}"; evidence
call POST /api/contas 201 "{\"numero\":\"$stamp\",\"tipo\":\"CORRENTE\",\"saldo\":100.00,\"clienteId\":$cliente_id}"
conta_id="$(get_id)"; printf 'ID criado da conta: %s\n' "$conta_id"; evidence
call GET /api/contas 200; evidence
call GET "/api/contas/$conta_id" 200; evidence
call PUT "/api/contas/$conta_id" 200 "{\"numero\":\"$stamp\",\"tipo\":\"POUPANCA\",\"saldo\":250.00,\"clienteId\":$cliente_id}"; evidence
call DELETE "/api/contas/$conta_id" 204; evidence
call DELETE "/api/clientes/$cliente_id" 204; evidence
printf '\nCRUD completo nas duas tabelas. Os registros criados neste teste foram excluídos.\n'
