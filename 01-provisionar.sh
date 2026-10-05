#!/usr/bin/env bash
set +x
set -Eeuo pipefail
trap 'printf "Falha na linha %s. A execução foi interrompida.\n" "$LINENO" >&2' ERR
source "$(dirname -- "${BASH_SOURCE[0]}")/00-variaveis.sh"
validate_variables; azure_ready
if ! command -v sqlcmd >/dev/null 2>&1 && [[ ! -x "$HOME/.local/bin/sqlcmd" ]]; then die 'sqlcmd é dependência obrigatória.'; fi
trap 'unset SQL_ADMIN_USER SQL_ADMIN_PASSWORD' EXIT
: "${SQL_LOCATION:?Defina SQL_LOCATION em 00-variaveis.sh.}"
[[ "${APP_SERVICE_SKU:-}" == F1 ]] || die 'Esta versão usa F1. Ajuste APP_SERVICE_SKU=F1.'
[[ "${SQL_MODE:-}" == FreeServerless ]] || die 'Exporte SQL_MODE="FreeServerless" no terminal.'

printf 'Assinatura: %s\nGrupo: %s\nRegião: %s\nApp Service: %s\nSQL: %s\n' "$SUBSCRIPTION_ID" "$RESOURCE_GROUP" "$LOCATION" "$APP_SERVICE_SKU" "$SQL_MODE"
printf 'Os recursos podem consumir créditos. Confira os preços e as regiões permitidas.\n'
if [[ "${AUTO_CONFIRM:-false}" != true ]]; then
 read -r -p 'Digite CRIAR para provisionar: ' answer
 [[ "$answer" == CRIAR ]] || die 'Cancelado.'
fi
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
# Reexecução retoma recursos existentes e não redefine senha do servidor SQL.
if ! azc appservice plan show --name "$PLAN_NAME" --resource-group "$RESOURCE_GROUP" --output none 2>/dev/null; then
 azc appservice plan create --name "$PLAN_NAME" --resource-group "$RESOURCE_GROUP" --location "$LOCATION" --is-linux --sku "$APP_SERVICE_SKU" --output none
fi
actual_sku="$(azc appservice plan show --name "$PLAN_NAME" --resource-group "$RESOURCE_GROUP" --query sku.name --output tsv)"
[[ "$actual_sku" == F1 ]] || die 'O plano existente não é F1. Confira antes de continuar.'
if ! azc webapp show --name "$WEBAPP_NAME" --resource-group "$RESOURCE_GROUP" --output none 2>/dev/null; then
 azc webapp create --name "$WEBAPP_NAME" --resource-group "$RESOURCE_GROUP" --plan "$PLAN_NAME" --runtime 'JAVA:17-java17' --output none
fi
azc webapp update --name "$WEBAPP_NAME" --resource-group "$RESOURCE_GROUP" --https-only true --output none
if ! azc sql server show --name "$SQL_SERVER_NAME" --resource-group "$RESOURCE_GROUP" --output none 2>/dev/null; then
 azc sql server create --name "$SQL_SERVER_NAME" --resource-group "$RESOURCE_GROUP" --location "$SQL_LOCATION" --admin-user "$SQL_ADMIN_USER" --admin-password "$SQL_ADMIN_PASSWORD" --minimal-tls-version 1.2 --enable-public-network true --output none
fi
actual_location="$(azc sql server show --name "$SQL_SERVER_NAME" --resource-group "$RESOURCE_GROUP" --query location --output tsv)"
[[ "$actual_location" == "$SQL_LOCATION" ]] || die "Servidor existente em $actual_location; esperado $SQL_LOCATION."
# Oferta gratuita baseada em vCore/serverless, não em DTU Basic.
if ! azc sql db show --name "$DATABASE_NAME" --resource-group "$RESOURCE_GROUP" --server "$SQL_SERVER_NAME" --output none 2>/dev/null; then
 # Mesma oferta serverless, agora na região que funcionou na assinatura.
 azc sql db create --name "$DATABASE_NAME" --resource-group "$RESOURCE_GROUP" --server "$SQL_SERVER_NAME" \
  --edition GeneralPurpose --family Gen5 --capacity 2 --min-capacity 0.5 \
  --compute-model Serverless --auto-pause-delay 60 --max-size 32GB \
  --use-free-limit --free-limit-exhaustion-behavior AutoPause \
  --backup-storage-redundancy Local --zone-redundant false --output none
fi
free_enabled="$(azc sql db show --name "$DATABASE_NAME" --resource-group "$RESOURCE_GROUP" --server "$SQL_SERVER_NAME" --query useFreeLimit --output tsv)"
free_behavior="$(azc sql db show --name "$DATABASE_NAME" --resource-group "$RESOURCE_GROUP" --server "$SQL_SERVER_NAME" --query freeLimitExhaustionBehavior --output tsv)"
[[ "$free_enabled" == true && "$free_behavior" == AutoPause ]] || die 'Oferta SQL gratuita/AutoPause não confirmada. Interrompido sem fallback pago. Consulte az sql db show.'
printf 'Região SQL: %s\n' "$SQL_LOCATION"
printf 'Oferta gratuita do SQL confirmada, com AutoPause ao atingir a franquia.\n' 
azc monitor log-analytics workspace create --resource-group "$RESOURCE_GROUP" --workspace-name "$WORKSPACE_NAME" --location "$LOCATION" --sku PerGB2018 --retention-time 30 --output none
workspace_id="$(azc monitor log-analytics workspace show --resource-group "$RESOURCE_GROUP" --workspace-name "$WORKSPACE_NAME" --query id --output tsv)"
azc monitor app-insights component create --app "$INSIGHTS_NAME" --resource-group "$RESOURCE_GROUP" --location "$LOCATION" --application-type web --kind web --workspace "$workspace_id" --output none
azc monitor app-insights component update --app "$INSIGHTS_NAME" --resource-group "$RESOURCE_GROUP" --workspace "$workspace_id" --output none
validate_variables; azure_ready; require_group; need python3
export CLIENT_IPV4="$(curl -4 --fail --silent --show-error https://api.ipify.org)"
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
executar_sql ddl.sql
printf 'Recursos, configuração e tabelas prontos. Próximo: 02-deploy.sh.\n'
