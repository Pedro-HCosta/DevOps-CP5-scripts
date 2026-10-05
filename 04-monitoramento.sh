#!/usr/bin/env bash
set +x
set -Eeuo pipefail
trap 'printf "Falha na linha %s. A execução foi interrompida.\n" "$LINENO" >&2' ERR
source "$(dirname -- "${BASH_SOURCE[0]}")/00-variaveis.sh"
validate_variables; azure_ready; require_group; need python3
if ! az account get-access-token --resource https://api.loganalytics.io --output none --only-show-errors 2>/dev/null; then
 printf 'A sessão precisa de autenticação para a API de logs.\n'
 tenant_id="$(az account show --subscription "$SUBSCRIPTION_ID" --query tenantId --output tsv)"
 az login --tenant "$tenant_id" --use-device-code --scope 'https://api.loganalytics.io/.default' --output none
 az account set --subscription "$SUBSCRIPTION_ID"
 az account get-access-token --resource https://api.loganalytics.io --output none --only-show-errors
fi
insights_id="$(azc monitor app-insights component show --resource-group "$RESOURCE_GROUP" --app "$INSIGHTS_NAME" --query id --output tsv)"
workspace_id="$(azc monitor app-insights component show --resource-group "$RESOURCE_GROUP" --app "$INSIGHTS_NAME" --query workspaceResourceId --output tsv)"
[[ "$workspace_id" == /subscriptions/* ]] || die 'Application Insights sem workspace associado. Reexecute 01-provisionar.sh.'
workspace_guid="$(az resource show --ids "$workspace_id" --api-version 2023-09-01 --query properties.customerId --output tsv --only-show-errors)"
umask 077
query_dir="$(mktemp -d)"
trap 'rm -rf -- "$query_dir"' EXIT
for table in AppRequests AppDependencies; do
 python3 - "$query_dir/query.json" "$table" "$insights_id" <<'QUERY'
import json,sys
file,table,resource=sys.argv[1:]
query=table+" | where TimeGenerated > ago(1h) | where _ResourceId =~ '"+resource+"'"
if table=='AppRequests': query+=' | project TimeGenerated, Name, ResultCode, Success, DurationMs'
else: query+=" | where DependencyType contains 'SQL' | project TimeGenerated, Name, Target, Success, DurationMs"
query+=' | order by TimeGenerated desc | take 50'
with open(file,'w') as f: json.dump({'query':query,'timespan':'PT1H'},f)
QUERY
 printf '\n%s (última hora):\n' "$table"
 # API pública v1; autenticação explícita para o público correto.
 az rest --method post --uri "https://api.loganalytics.azure.com/v1/workspaces/$workspace_guid/query" \
  --resource https://api.loganalytics.io --headers Content-Type=application/json \
  --body "@$query_dir/query.json" --output json --only-show-errors > "$query_dir/result.json"
 python3 - "$query_dir/result.json" <<'RESULT'
import json,sys
r=json.load(open(sys.argv[1]))
if 'error' in r: sys.exit('Consulta de logs retornou erro: '+str(r['error']))
for t in r.get('tables',[]):
 print(' | '.join(c['name'] for c in t['columns']))
 for row in t['rows']: print(' | '.join(str(v) for v in row))
 print('Linhas:',len(t['rows']))
RESULT
done
printf '\nSem dados? Aguarde alguns minutos e repita 04-monitoramento.sh.\n'
