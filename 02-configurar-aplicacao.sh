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
validate_variables; azure_ready; require_group; need python3
python3 - "$CLIENT_IPV4" <<'CHECK'
import ipaddress,sys
try: ipaddress.IPv4Address(sys.argv[1])
except ValueError: sys.exit('Edite CLIENT_IPV4 com o IPv4 público do seu terminal.')
CHECK
credentials
azc sql server firewall-rule create --resource-group "$RESOURCE_GROUP" --server "$SQL_SERVER_NAME" --name TerminalCheckpoint --start-ip-address "$CLIENT_IPV4" --end-ip-address "$CLIENT_IPV4" --output none
# Libera todos os IPs de saída possíveis do Web App, sem liberar toda a Azure.
outbound="$(azc webapp show --resource-group "$RESOURCE_GROUP" --name "$WEBAPP_NAME" --query possibleOutboundIpAddresses --output tsv)"
[[ -n "$outbound" && "$outbound" != None ]] || die 'Não foi possível obter os IPs de saída do Web App.'
IFS=',' read -r -a addresses <<< "$outbound"
for ip in "${addresses[@]}"; do
 rule="WebApp-${ip//./-}"
 azc sql server firewall-rule create --resource-group "$RESOURCE_GROUP" --server "$SQL_SERVER_NAME" --name "$rule" --start-ip-address "$ip" --end-ip-address "$ip" --output none
done
# Não imprime segredos; escreve arquivo temporário com permissão restrita.
umask 077
settings_file="$(mktemp)"
trap 'rm -f -- "$settings_file"; unset SQL_ADMIN_PASSWORD SQL_ADMIN_USER' EXIT
export DIMDIM_SQL_SERVER="$SQL_SERVER_NAME" DIMDIM_DATABASE="$DATABASE_NAME"
export DIMDIM_INSIGHTS_CONNECTION="$(azc monitor app-insights component show --resource-group "$RESOURCE_GROUP" --app "$INSIGHTS_NAME" --query connectionString --output tsv)"
[[ -n "$DIMDIM_INSIGHTS_CONNECTION" ]] || die 'Connection string do Application Insights ausente.'
python3 - "$settings_file" <<'SETTINGS'
import json,os,sys
settings={
 'DB_URL':f"jdbc:sqlserver://{os.environ['DIMDIM_SQL_SERVER']}.database.windows.net:1433;databaseName={os.environ['DIMDIM_DATABASE']};encrypt=true;trustServerCertificate=false;loginTimeout=30;",
 'DB_USERNAME':os.environ['SQL_ADMIN_USER'],
 'DB_PASSWORD':os.environ['SQL_ADMIN_PASSWORD'],
 'APPLICATIONINSIGHTS_CONNECTION_STRING':os.environ['DIMDIM_INSIGHTS_CONNECTION'],
 'ApplicationInsightsAgent_EXTENSION_VERSION':'~3',
 'APPLICATIONINSIGHTS_ROLE_NAME':'dimdim-backend',
 'SCM_DO_BUILD_DURING_DEPLOYMENT':'false',
 'SERVER_PORT':'8080',
 'SPRING_DATASOURCE_HIKARI_MINIMUM_IDLE':'0',
 'SPRING_DATASOURCE_HIKARI_IDLE_TIMEOUT':'60000'
}
with open(sys.argv[1],'w') as f: json.dump(settings,f)
SETTINGS
azc webapp config appsettings set --resource-group "$RESOURCE_GROUP" --name "$WEBAPP_NAME" --settings "@$settings_file" --output none
azc webapp config set --resource-group "$RESOURCE_GROUP" --name "$WEBAPP_NAME" --min-tls-version 1.2 --output none
azc webapp restart --resource-group "$RESOURCE_GROUP" --name "$WEBAPP_NAME" --output none
unset DIMDIM_INSIGHTS_CONNECTION DIMDIM_SQL_SERVER DIMDIM_DATABASE
printf 'Conexão, firewall e agente Application Insights configurados.\n'
printf 'Agora execute 03-executar-sql.sh ddl.sql ANTES do deploy.\n'
