#!/usr/bin/env bash
set +x
set -Eeuo pipefail
trap 'printf "Falha na linha %s. A execução foi interrompida.\n" "$LINENO" >&2' ERR
source "$(dirname -- "${BASH_SOURCE[0]}")/00-variaveis.sh"
PROJECT_ROOT="$BACKEND_DIR"
validate_variables; azure_ready; require_group; need mvn; need java; need curl
[[ -f "$PROJECT_ROOT/pom.xml" ]] || die "pom.xml não encontrado em $PROJECT_ROOT"
cd "$PROJECT_ROOT"
mvn -B -ntp clean verify
[[ -f target/dimdim-backend.jar ]] || die 'JAR target/dimdim-backend.jar não encontrado.'
azc webapp deploy --resource-group "$RESOURCE_GROUP" --name "$WEBAPP_NAME" --src-path target/dimdim-backend.jar --type jar --output none
host="$(azc webapp show --resource-group "$RESOURCE_GROUP" --name "$WEBAPP_NAME" --query defaultHostName --output tsv)"
base="https://$host"
printf 'Deploy enviado. Aguardando health: %s/actuator/health\n' "$base"
for ((attempt=1; attempt<=24; attempt++)); do
 if response="$(curl --silent --show-error --fail --connect-timeout 10 --max-time 20 "$base/actuator/health" 2>/dev/null)" && [[ "$response" == *'"status":"UP"'* ]]; then
  printf 'Aplicação saudável: %s\n' "$base"; exit 0
 fi
 sleep 10
done
die 'Health não ficou UP. Confira o DDL, credenciais, firewall e Log stream no portal. O deploy pode ter ocorrido.'
