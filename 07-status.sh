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
validate_variables; azure_ready
if [[ "$(azc group exists --name "$RESOURCE_GROUP" --output tsv)" != true ]]; then
 printf 'Grupo inexistente: %s. Não há recursos ativos dentro desse grupo.\n' "$RESOURCE_GROUP"; exit 0
fi
require_group
azc group show --name "$RESOURCE_GROUP" --query '{grupo:name,estado:properties.provisioningState}' --output table
azc resource list --resource-group "$RESOURCE_GROUP" --query '[].{nome:name,tipo:type,regiao:location}' --output table
printf 'Confira também o estado no portal. Exclusão em andamento não significa exclusão concluída.\n'
