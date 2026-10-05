# DimDim CP5 — comandos por etapa no Azure Cloud Shell

Esta versão não depende de config.sh nem common.sh. Defina as variáveis diretamente no terminal, como na aula. Use `export` para que cada script executado com `bash` receba esses valores. Uma nova sessão exige definir novamente as variáveis, mantendo os mesmos nomes de recursos.

Coloque a pasta scripts na raiz do clone Java, ao lado do pom.xml. Os scripts são Bash; não use o modo PowerShell. Se os scripts estão em outro repositório, copie a pasta scripts para dentro do clone Java antes do deploy. Substitua a pasta antiga inteira: config.sh e common.sh não são mais usados.

## 1. Definir variáveis — não cria recursos

Copie no Cloud Shell Bash:

```bash
export SUBSCRIPTION_ID="f2072a33-25ac-488a-9a88-3d5e2edfe3eb"
export LOCATION="mexicocentral"
export SUFFIX="dimdimcp5fc261004"
export RESOURCE_GROUP="rg-dimdim-cp5-${SUFFIX}"
export PLAN_NAME="plan-dimdim-${SUFFIX}"
export WEBAPP_NAME="app-dimdim-${SUFFIX}"
export SQL_SERVER_NAME="sql-dimdim-${SUFFIX}"
export DATABASE_NAME="dimdim"
export WORKSPACE_NAME="log-dimdim-${SUFFIX}"
export INSIGHTS_NAME="ai-dimdim-${SUFFIX}"
export APP_SERVICE_SKU="F1"
export SQL_MODE="FreeServerless"
export CLIENT_IPV4="$(curl -4 --fail --silent --show-error https://api.ipify.org)"
az account set --subscription "$SUBSCRIPTION_ID"
```

Confira CLIENT_IPV4: deve conter um IPv4 válido. O IP do Cloud Shell pode mudar entre sessões; atualize a variável e rode o script 02 novamente se necessário. Os nomes de SQL e Web App precisam estar disponíveis globalmente. A região e a oferta gratuita precisam ser aceitas pela sua assinatura.

SQL_MODE é um seletor próprio do script, não um nome de SKU do Azure. SQL usa General Purpose Serverless, --use-free-limit e --free-limit-exhaustion-behavior AutoPause. Não há fallback para B1, Basic ou cobrança por excedente. F1/SQL têm limites de uso. Application Insights/Log Analytics ainda podem consumir créditos. Os scripts não foram executados na Azure nesta entrega.

## 2. Verificar ambiente

```bash
bash scripts/00-verificar-ambiente.sh
```

Precisa de Git, Java 17, Maven, Azure CLI, Python 3, curl e sqlcmd. SQLCMD só é necessário se usar o script 03; pode usar o editor SQL do portal. Cloud Shell já autentica a sessão. Em outro terminal use az login ou az login --use-device-code.

## 3. Executar por etapa

```bash
# Criação: pede CRIAR e solicita usuário e senha SQL de forma oculta.
bash scripts/01-criar-recursos.sh
# Variáveis de ambiente do Web App, firewall e agente Application Insights.
bash scripts/02-configurar-aplicacao.sh
# Tabelas: ANTES do deploy.
bash scripts/03-executar-sql.sh ddl.sql
# Testes Maven, JAR e az webapp deploy.
bash scripts/04-deploy.sh
# Pausa a cada operação para mostrar SQL no outro terminal.
bash scripts/05-testar-api.sh --interativo
# Requisições e dependências SQL.
bash scripts/06-consultar-monitoramento.sh
# Inventário e estado.
bash scripts/07-status.sh
```

Use a mesma credencial SQL nos scripts 01, 02 e 03. Não grave usuário/senha reais no código nem os mostre no vídeo. Os scripts não imprimem configurações secretas; nunca use bash -x ou az --debug. Arquivos temporários de configuração são removidos ao concluir.

O script 01 valida a aplicação da oferta SQL gratuita e AutoPause depois de criar o banco. Se uma etapa falhar, recursos já criados podem permanecer: confira 07. Não há réplica, failover ou retenção de backups LTR, que são exercícios adicionais da aula e não requisitos do checkpoint.

O firewall limita o acesso ao IPv4 informado e aos IPs possíveis de saída do Web App, sem abrir todos os IPs. O professor usa uma regra ampla no laboratório; mantemos o mesmo método de configuração por CLI com acesso limitado.

O ddl.sql pode ser reaplicado sem apagar dados; cria objetos ausentes e não migra tabelas já existentes. Na configuração do Web App, Hikari usa minimumIdle=0 e idleTimeout=60000 para liberar conexões ociosas. Pausa/retomada do SQL depende do serviço e pode causar demora na primeira conexão. Se o banco estiver retomando, aguarde e tente de novo.

## 4. Persistência e vídeo

Em outro terminal, defina as MESMAS variáveis exportadas e execute após cada operação:

```bash
bash scripts/03-executar-sql.sh verificar-persistencia.sql
```

Ou execute o SQL no editor de consultas do banco correto, no portal. O teste 05 cria dados fictícios com valores únicos, faz POST/GET/PUT/DELETE em clientes e contas e remove somente os registros que ele criou. Sem --interativo roda sem pausas. Se falhar, pode deixar registros: use os IDs mostrados e exclua primeiro a conta, depois o cliente.

Para telemetria, execute 06 ou as consultas monitoramento.kql, uma por vez. No App Insights use requests/dependencies; no workspace use AppRequests/AppDependencies. Aguarde alguns minutos após gerar tráfego. No vídeo mostre também Performance/Transaction search e as dependências SQL. Actuator não substitui Application Insights.

Esta versão usa a opção Azure CLI + az webapp deploy aceita pelo checkpoint. GitHub Actions, usado na outra aula, é outra opção aceita e não está configurado aqui. Frontend é opcional para a pontuação adicional e não está incluído.

## 5. Limpeza

Guarde as evidências e considere o acesso do professor antes de retirar a aplicação do ar:

```bash
bash scripts/99-limpar-tudo.sh --aguardar
```

O script lista os recursos, confirma a assinatura e exige digitar o nome do grupo. Exclui o grupo inteiro e seu conteúdo, inclusive banco e monitoramento. Não remove locks/políticas e não toca em recursos de outros grupos. Sem --aguardar apenas solicita a exclusão; confira 07 depois. Custos anteriores não são estornados. Repositório e vídeo não são apagados.

## Verificação e referências

Sintaxe Bash verificada e fluxo de criação/configuração testado com Azure CLI simulado, incluindo recusa sem oferta gratuita confirmada. Validação real de região, quota, rede, deploy e telemetria ainda depende da sua assinatura.

- https://learn.microsoft.com/en-us/azure/azure-sql/database/free-offer
- https://learn.microsoft.com/en-us/cli/azure/sql/db
- https://learn.microsoft.com/en-us/azure/azure-monitor/app/codeless-app-service
- https://learn.microsoft.com/en-us/cli/azure/group
