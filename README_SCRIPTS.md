# DimDim CP5 — fluxo enxuto no Cloud Shell

Dois repositórios separados: API Java e scripts. Clone ambos, entre na pasta `scripts` deste repositório e execute em ordem. O professor deve ter as dependências: Bash, Git, Azure CLI, Java 17/Maven, Python 3, curl e sqlcmd. Nenhum script instala dependências.

```bash
cd ~
git clone <URL_GITHUB_API> API-dimdim-CP5
git clone <URL_GITHUB_SCRIPTS> DevOps-CP5-scripts
cd ~/DevOps-CP5-scripts/scripts
bash 01-provisionar.sh
bash 02-deploy.sh
bash 03-testar-api.sh --console
bash 04-monitoramento.sh
```

Substitua as URLs. Se os scripts estão na raiz do seu clone, use `cd ~/DevOps-CP5-scripts`. Os executáveis funcionam nas duas posições; para entrega, mantenha a pasta `scripts` pedida no PDF. Mantenha links cruzados nos READMEs dos dois repositórios.

## Arquivos

| Arquivo | Função |
| --- | --- |
| 00-variaveis.sh | Variáveis e funções compartilhadas; carregado automaticamente, não precisa executar |
| 01-provisionar.sh | Cria recursos, configura firewall/aplicação/Insights e executa ddl.sql com sqlcmd |
| 02-deploy.sh | Compila e testa a API no outro clone, publica o JAR e espera health UP |
| 03-testar-api.sh | Testa CRUD de clientes e contas e abre console SQL para você conferir persistência |
| 04-monitoramento.sh | Consulta requisições HTTP e dependências SQL pela API v1 de Log Analytics |
| 99-limpar-tudo.sh | Exclui o grupo dedicado e todo seu conteúdo, após confirmação |

DDL e consultas ficam em `ddl.sql` e `verificar-persistencia.sql`. `monitoramento.kql` contém consultas de referência. Cinco scripts de execução; `00` é apenas o arquivo compartilhado numerado. Não há instalador, verificador separado, script de status ou orquestrador adicional.

## Variáveis automáticas

Não precisa digitar export nem source. `00-variaveis.sh` usa os valores da solução existente: assinatura Azure for Students, F1 em mexicocentral, SQL gratuito em brazilsouth, servidor terminado em -br e banco free-sql-db-0377722. Backend em `$HOME/API-dimdim-CP5`; o nome do usuário do Cloud Shell não é fixado. O IP do terminal é detectado automaticamente por 01 no momento de configurar o firewall.

Se mudar assinatura, pasta ou implantação, edite somente 00-variaveis.sh. Para nova implantação, escolha outro SUFFIX (nomes são derivados dele) e, se quiser, DATABASE_NAME=dimdim. Disponibilidade de nomes, quota e oferta depende da assinatura. Não coloque credenciais nesse arquivo ou no GitHub.

## Provisionamento

01 solicita CRIAR e usuário/senha SQL ocultos. Os parâmetros secretos não são impressos nem gravados no repositório. Recursos existentes são reutilizados: não redefine senha do servidor e não apaga registros. Para servidor existente, informe suas credenciais reais.

SQL usa --use-free-limit e AutoPause. Se oferta gratuita não for confirmada, interrompe sem fallback pago. Servidor deve estar em SQL_LOCATION e plano existente deve ser F1. Os recursos anteriores a um erro podem permanecer no grupo. Monitoramento pode consumir créditos conforme ingestão; o SQL gratuito não torna toda solução gratuita. Não cria réplicas, failover ou LTR.

O DDL é reaplicável: cria objetos ausentes sem migrar nem apagar tabelas existentes. sqlcmd usa SQLCMDPASSWORD no ambiente, -N para criptografia e validação de certificado (sem -C). Localiza sqlcmd no PATH ou em ~/.local/bin. Banco pausado pode precisar retomar; se houver erro de retomada, aguarde e repita 01.

02 executa mvn clean verify no clone da API e az webapp deploy. A alternativa Azure CLI + az webapp deploy é aceita no checkpoint; GitHub Actions não é obrigatório nessa opção.

## Consultas feitas por você

03 --console faz uma operação HTTP, imprime status/JSON e abre sqlcmd no banco. Você digita:

```sql
SELECT * FROM dbo.clientes;
SELECT * FROM dbo.contas;
GO
```

Mostre os resultados após cada operação. `GO` executa o lote. Digite `EXIT` para encerrar apenas o sqlcmd e continuar a próxima operação do teste. O mesmo fluxo acontece nas duas tabelas. O script exclui somente os registros que criou. Falhas podem deixar registros: use os IDs impressos para excluir a conta antes do cliente. Feche o console ao terminar para não impedir pausa do SQL.

Outros modos opcionais: 03 --sql consulta automaticamente após cada operação; 03 --sql --interativo também aguarda Enter; 03 sem opções apenas testa a API.

## Monitoramento no console

04 consulta o workspace realmente associado ao Insights, filtrando AppRequests e AppDependencies para este recurso, por az rest e API pública v1. Se o Cloud Shell não emitir token para a API de logs, inicia login por código de dispositivo. Pode exigir abrir a página de autenticação uma vez. Nenhuma configuração de recursos exige portal; autenticação depende das políticas da conta. Pode consultar depois de alguns minutos se a ingestão ainda não tiver chegado. Resultados vazios não comprovam monitoramento: confirme registros HTTP e SQL com sucesso.

## Solução existente e entrega

Você pode executar 01 para validar/completar configuração e DDL sem excluir os recursos existentes. Isso não é evidência de criação do zero no vídeo. Para mostrar criação integral, planeje outro grupo/SUFFIX ou limpeza da implantação dedicada depois de guardar evidências.

O PDF pede código completo, DDL/CLI na pasta scripts, arquitetura, tutorial README, JSON da API, vídeo falado mínimo 720p mostrando criação/deploy/CRUD, SQL após cada operação nas duas tabelas e Application Insights. PDF final somente grupo, integrantes/RMs e links; nomenclatura <grupo>_webapp.pdf. Frontend opcional para ponto adicional.

Após guardar evidências e considerar o acesso do professor:

```bash
bash 99-limpar-tudo.sh --aguardar
```

Exclui todos os recursos do grupo, incluindo ambos os servidores SQL, bancos, plano, aplicação e monitoramento. Exige nome completo do grupo e tag projeto=DimDimCP5. Não remove locks/políticas e não toca em outros grupos. Não estorna custos anteriores.

## Validação

Sintaxe Bash e cenários com Azure CLI/sqlcmd simulados verificados localmente, incluindo oferta gratuita recusada e 10 aberturas de console após CRUD. A nova criação por CLI em Brazil South e autenticação/consulta real de logs ainda dependem da sua assinatura; não foram executadas pelo assistente. A versão anterior já teve deploy, CRUD e telemetria HTTP/SQL confirmados por você.

Referências: https://learn.microsoft.com/en-us/cli/azure/sql/db ; https://learn.microsoft.com/en-us/sql/tools/sqlcmd/sqlcmd-download-install ; https://learn.microsoft.com/en-us/azure/azure-monitor/logs/api/request-format
