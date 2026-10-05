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
[[ "${APP_SERVICE_SKU:-}" == F1 ]] || die 'Esta versão usa F1. Ajuste APP_SERVICE_SKU=F1.'
[[ "${SQL_MODE:-}" == FreeServerless ]] || die 'Exporte SQL_MODE="FreeServerless" no terminal.'

printf 'Assinatura: %s\nGrupo: %s\nRegião: %s\nApp Service: %s\nSQL: %s\n' "$SUBSCRIPTION_ID" "$RESOURCE_GROUP" "$LOCATION" "$APP_SERVICE_SKU" "$SQL_MODE"
printf 'Os recursos podem consumir créditos. Confira os preços e as regiões permitidas.\n'
read -r -p 'Digite CRIAR para provisionar: ' answer
[[ "$answer" == CRIAR ]] || die 'Cancelado.'
if [[ "$(azc group exists --name "$RESOURCE_GROUP" --output tsv)" == true ]]; then require_group; fi
credentials
[[ ${#SQL_ADMIN_PASSWORD} -ge 8 && ${#SQL_ADMIN_PASSWORD} -le 128 ]] || die 'Senha SQL deve ter entre 8 e 128 caracteres.'
classes=0
[[ "$SQL_ADMIN_PASSWORD" =~ [A-Z] ]] && classes=$((classes+1))
[[ "$SQL_ADMIN_PASSWORD" =~ [a-z] ]] && classes=$((classes+1))
[[ "$SQL_ADMIN_PASSWORD" =~ [0-9] ]] && classes=$((classes+1))
[[ "$SQL_ADMIN_PASSWORD" =~ [^a-zA-Z0-9] ]] && classes=$((classes+1))
[[ $classes -ge 3 ]] || die 'Senha SQL precisa de pelo menos três categorias: maiúsculas, minúsculas, números e símbolos.'
[[ "$SQL_ADMIN_PASSWORD" != *"$SQL_ADMIN_USER"* ]] || die 'Senha não deve conter o nome do usuário SQL.'
# Necessário para as contas que ainda não registraram os provedores.
for provider in Microsoft.Web Microsoft.Sql Microsoft.Insights Microsoft.OperationalInsights; do
 azc provider register --namespace "$provider" --wait --output none
done
if ! az extension show --name application-insights --output none --only-show-errors 2>/dev/null; then
 az extension add --name application-insights --only-show-errors --output none
fi
azc group create --name "$RESOURCE_GROUP" --location "$LOCATION" --tags projeto=DimDimCP5 --output none
azc appservice plan create --name "$PLAN_NAME" --resource-group "$RESOURCE_GROUP" --location "$LOCATION" --is-linux --sku "$APP_SERVICE_SKU" --output none
azc webapp create --name "$WEBAPP_NAME" --resource-group "$RESOURCE_GROUP" --plan "$PLAN_NAME" --runtime 'JAVA:17-java17' --output none
azc webapp update --name "$WEBAPP_NAME" --resource-group "$RESOURCE_GROUP" --https-only true --output none
azc sql server create --name "$SQL_SERVER_NAME" --resource-group "$RESOURCE_GROUP" --location "$LOCATION" --admin-user "$SQL_ADMIN_USER" --admin-password "$SQL_ADMIN_PASSWORD" --minimal-tls-version 1.2 --enable-public-network true --output none
# Oferta gratuita baseada em vCore/serverless, não em DTU Basic.
azc sql db create --name "$DATABASE_NAME" --resource-group "$RESOURCE_GROUP" --server "$SQL_SERVER_NAME" \
 --edition GeneralPurpose --family Gen5 --capacity 2 --min-capacity 0.5 \
 --compute-model Serverless --auto-pause-delay 60 --max-size 32GB \
 --use-free-limit --free-limit-exhaustion-behavior AutoPause \
 --backup-storage-redundancy Local --zone-redundant false --output none
free_enabled="$(azc sql db show --name "$DATABASE_NAME" --resource-group "$RESOURCE_GROUP" --server "$SQL_SERVER_NAME" --query useFreeLimit --output tsv)"
free_behavior="$(azc sql db show --name "$DATABASE_NAME" --resource-group "$RESOURCE_GROUP" --server "$SQL_SERVER_NAME" --query freeLimitExhaustionBehavior --output tsv)"
[[ "$free_enabled" == true && "$free_behavior" == AutoPause ]] || die 'Oferta SQL gratuita/AutoPause não confirmada. Pare e confira o banco no portal; não houve fallback automático.'
printf 'Oferta gratuita do SQL confirmada, com AutoPause ao atingir a franquia.\n' 
azc monitor log-analytics workspace create --resource-group "$RESOURCE_GROUP" --workspace-name "$WORKSPACE_NAME" --location "$LOCATION" --sku PerGB2018 --retention-time 30 --output none
workspace_id="$(azc monitor log-analytics workspace show --resource-group "$RESOURCE_GROUP" --workspace-name "$WORKSPACE_NAME" --query id --output tsv)"
azc monitor app-insights component create --app "$INSIGHTS_NAME" --resource-group "$RESOURCE_GROUP" --location "$LOCATION" --application-type web --kind web --workspace "$workspace_id" --output none
unset SQL_ADMIN_USER SQL_ADMIN_PASSWORD
printf 'Recursos criados. Próximo: 02-configurar-aplicacao.sh.\n'
printf 'Se uma etapa falhou, recursos anteriores podem permanecer. Use 07-status.sh para verificar.\n'
