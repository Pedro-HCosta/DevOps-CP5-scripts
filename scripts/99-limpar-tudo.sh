#!/usr/bin/env bash
set +x
set -Eeuo pipefail
trap 'printf "Falha na linha %s. A execução foi interrompida.\n" "$LINENO" >&2' ERR
source "$(dirname -- "${BASH_SOURCE[0]}")/00-variaveis.sh"
validate_variables; azure_ready
wait_delete=false
case "${1:-}" in
 '') ;;
 --aguardar) wait_delete=true ;;
 *) die 'Use: bash scripts/99-limpar-tudo.sh [--aguardar]' ;;
esac
if [[ "$(azc group exists --name "$RESOURCE_GROUP" --output tsv)" != true ]]; then
 printf 'Grupo já não existe: %s\n' "$RESOURCE_GROUP"; exit 0
fi
require_group
printf 'Assinatura: %s\nGrupo que será EXCLUÍDO: %s\n' "$SUBSCRIPTION_ID" "$RESOURCE_GROUP"
azc resource list --resource-group "$RESOURCE_GROUP" --query '[].{nome:name,tipo:type}' --output table
printf 'A operação exclui TODO o conteúdo desse grupo, inclusive banco e monitoramento.\n'
printf 'Guarde vídeo/evidências antes. A aplicação ficará indisponível ao professor.\n'
read -r -p 'Digite o nome completo do grupo para confirmar: ' confirmation
[[ "$confirmation" == "$RESOURCE_GROUP" ]] || die 'Nome diferente. Exclusão cancelada.'
# Azure Resource Manager exclui os recursos filhos junto com o grupo.
# Locks/políticas que impedem exclusão NÃO são removidos por este script.
azc group delete --name "$RESOURCE_GROUP" --yes --no-wait
printf 'Exclusão solicitada. Ainda pode estar em andamento.\n'
if [[ "$wait_delete" == true ]]; then
 azc group wait --name "$RESOURCE_GROUP" --deleted --interval 15 --timeout 1800
 [[ "$(azc group exists --name "$RESOURCE_GROUP" --output tsv)" == false ]] || die 'Exclusão ainda não confirmada.'
 printf 'Exclusão confirmada: grupo e recursos removidos.\n'
else
 azc group exists --name "$RESOURCE_GROUP" --output tsv
 printf 'true: exclusão em andamento; false: grupo removido.\n' 
fi
