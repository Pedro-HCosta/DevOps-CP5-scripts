#!/usr/bin/env bash
# Carregado automaticamente pelos scripts numerados; não execute manualmente.
# Valores não sensíveis da implantação. Para outra implantação, edite SUFFIX/nomes aqui.
export SUBSCRIPTION_ID="f2072a33-25ac-488a-9a88-3d5e2edfe3eb"
export LOCATION="mexicocentral"
export SQL_LOCATION="brazilsouth"
export SUFFIX="dimdimcp5fc261004"
export RESOURCE_GROUP="rg-dimdim-cp5-${SUFFIX}"
export PLAN_NAME="plan-dimdim-${SUFFIX}"
export WEBAPP_NAME="app-dimdim-${SUFFIX}"
export SQL_SERVER_NAME="sql-dimdim-${SUFFIX}-br"
export DATABASE_NAME="free-sql-db-0377722"
export WORKSPACE_NAME="log-dimdim-${SUFFIX}"
export INSIGHTS_NAME="ai-dimdim-${SUFFIX}"
export APP_SERVICE_SKU="F1"
export SQL_MODE="FreeServerless"
export BACKEND_DIR="$HOME/API-dimdim-CP5"
# O IP é detectado pelo script 02, no momento de configurar o firewall.

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
die() { printf '%s\n' "$*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || die "Instale o comando: $1"; }
validate_variables() {
 : "${SUBSCRIPTION_ID:?Confira 00-variaveis.sh.}"
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
 [[ "$(azc group exists --name "$RESOURCE_GROUP" --output tsv)" == true ]] || die 'Grupo inexistente. Execute 01-provisionar.sh.'
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

executar_sql() {
 local file="${1:---console}" sqlcmd_bin
 sqlcmd_bin="$(command -v sqlcmd || true)"
 if [[ -z "$sqlcmd_bin" && -x "$HOME/.local/bin/sqlcmd" ]]; then sqlcmd_bin="$HOME/.local/bin/sqlcmd"; fi
 [[ -n "$sqlcmd_bin" ]] || die 'sqlcmd não encontrado; instale a dependência antes de executar.'
 credentials
 local args=(-S "tcp:${SQL_SERVER_NAME}.database.windows.net,1433" -d "$DATABASE_NAME" -U "$SQL_ADMIN_USER" -N -b -l 60)
 if [[ "$file" == --console ]]; then
  printf '\nConsole SQL: digite SELECT; GO executa; EXIT retorna ao teste.\n'
  SQLCMDPASSWORD="$SQL_ADMIN_PASSWORD" "$sqlcmd_bin" "${args[@]}"
 else
  [[ "$file" == ddl.sql || "$file" == verificar-persistencia.sql ]] || die 'Arquivo SQL não permitido.'
  SQLCMDPASSWORD="$SQL_ADMIN_PASSWORD" "$sqlcmd_bin" "${args[@]}" -i "$SCRIPT_DIR/$file"
 fi
}
