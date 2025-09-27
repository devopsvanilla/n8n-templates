# Intercom ↔ Microsoft Teams Template (n8n)

Automatize a comunicação entre Microsoft Teams e Intercom com um fluxo bidirecional pronto para importação no n8n.

## O que este template faz

Fluxo Teams → Intercom (comando /reply):
- Microsoft Teams Trigger escuta mensagens em um canal específico.
- IF verifica se a mensagem começa com `/reply`.
- Function Clean Prefix remove o prefixo e deixa apenas o conteúdo da resposta.
- HTTP Request Intercom envia um comentário para a conversa no Intercom (com placeholders de credenciais).

Fluxo Intercom → Teams (webhook):
- Webhook (Inbound) recebe eventos do Intercom (configurável na sua conta Intercom).
- Build Teams Message normaliza o payload e monta uma mensagem de resumo.
- Lookup Thread Mapping (PostgreSQL) consulta o mapeamento `conversation_id → message_id` em um banco PostgreSQL.
- IF Has Mapping: se existir `message_id`, publica como resposta no tópico correspondente; caso contrário, cria um novo tópico.
- Save Thread Mapping salva o `message_id` recém-criado para a próxima vez.

Observação: o caminho “false” do IF foi corrigido para não enviar mensagens que não tenham o prefixo `/reply`.

## Diagrama de recursos e processos

```mermaid
flowchart LR

  %% Camadas de recursos
  subgraph Teams[Microsoft Teams]
    TChan[Canal do Teams]
  end

  subgraph Intercom[Intercom]
    Conv[Conversa no Intercom]
    Events[Eventos de Webhook]
  end

  subgraph Infra[Infra / Serviços]
    DB[(PostgreSQL\nconversation_threads)]
    MSGraph[Microsoft Graph API]
  end

  subgraph n8n[n8n Workflow]
    Trigger[Teams Trigger]
    IfReply{IF startsWith '/reply'?}
    Clean[Function: Clean Prefix]
    IntercomHTTP[HTTP → Intercom (comment)]
    Webhook[Webhook (Inbound) Intercom]
    Build[Function: Build Teams Message]
    Sanitize[Function: Sanitize IDs]
    PGSelect[PostgreSQL: SELECT mapping]
    HasMap{Has mapping?}
    GraphReply[HTTP → Graph replies]
    GraphPost[HTTP → Graph post]
    ExtractId[Function: Extract Message ID]
    PGUpsert[PostgreSQL: UPSERT mapping]
  end

  %% Fluxo Teams → Intercom (/reply)
  TChan --> Trigger --> IfReply
  IfReply -- "sim" --> Clean --> IntercomHTTP --> Conv
  IfReply -- "não" -->|ignora| Trigger

  %% Fluxo Intercom → Teams (webhook)
  Events --> Webhook --> Build --> Sanitize --> PGSelect --> HasMap
  HasMap -- "sim" --> GraphReply --> MSGraph --> TChan
  HasMap -- "não" --> GraphPost --> MSGraph --> TChan
  GraphPost --> ExtractId --> PGUpsert

  %% Persistência/integrações
  PGSelect --- DB
  PGUpsert --- DB
  IntercomHTTP --- Conv
```

Legenda:
- Teams Trigger: escuta mensagens no canal configurado via env (`TEAMS_TRIGGER_CHANNEL_ID`).
- IF /reply: somente mensagens começando com `/reply` seguem para o Intercom.
- HTTP → Intercom: publica comentário na conversa usando `INTERCOM_API_TOKEN` e `INTERCOM_ADMIN_ID`.
- Webhook Inbound: recebe eventos do Intercom e inicia o fluxo para o Teams.
- PostgreSQL: guarda/consulta o mapeamento `conversation_id ↔ message_id` (tabela `conversation_threads`).
- HTTP → Graph: cria post ou resposta em thread no canal, autenticado via token/credencial do Graph.

## Estrutura

- `workflow.json` — workflow do n8n pronto para importação com todos os nodes e conexões.
- `assets/` — opcional para capturas de tela e diagramas.

## Placeholders que você deve preencher

Agora o workflow usa variáveis de ambiente (sem precisar editar o JSON):

- `TEAMS_TRIGGER_CHANNEL_ID` — canal monitorado pelo Microsoft Teams Trigger
- `TEAMS_TEAM_ID` — ID do time no Microsoft Teams (Graph)
- `TEAMS_CHANNEL_ID` — ID do canal no Microsoft Teams (Graph) para publicar
- `MS_GRAPH_TOKEN` — token OAuth2 de acesso ao Microsoft Graph
- `INTERCOM_API_TOKEN` — token de API do Intercom
- `INTERCOM_ADMIN_ID` — ID do admin do Intercom

Arquivo de exemplo: `.env.example` (copie para `.env` e preencha). O script `db/init_db.sh` carrega `.env` automaticamente; no n8n, defina as mesmas variáveis no ambiente do processo (Docker/env do host).

## Credenciais e permissões

### Microsoft Graph (Teams)

1) Registrar aplicativo no Azure AD
- Azure Portal → Microsoft Entra ID → Registros de aplicativos → Novo registro.
- Anote: Application (client) ID, Directory (tenant) ID.

2) Permissões Graph mínimas sugeridas
- `ChannelMessage.Send` (delegada ou app-only) para postar em canais.
- `Team.ReadBasic.All` para resolver times/canais conforme necessário.
- Se for usar chat privado/thread: avalie `Chat.ReadWrite` (delegada) ou RSC/app-only com escopos por recurso.

3) Segredo/Tokens
- Crie um Client Secret (Certificados e segredos) se for usar app-only com Client Credentials.
- Se usar fluxo Delegated (OAuth2 Authorization Code), crie a credencial OAuth2 no n8n (Credenciais → OAuth2) apontando para Microsoft Graph, e selecione essa credencial no node HTTP Request (em vez de header Authorization manual).
- Para testes rápidos, você pode usar um token de Bearer no header `Authorization: Bearer YOUR_MS_GRAPH_TOKEN` (não recomendado em produção).

### Intercom
- Intercom → Developer Hub → Create access token.
- Escopos típicos: `write_conversations`, `read_conversations` (ajuste conforme seu uso).
- Anote o token e o `admin_id` que enviará comentários.

## Importar o workflow no n8n

1. Abra seu n8n → Workflows → Import.
2. Cole o conteúdo de `intercom-templates/workflow.json` e confirme.
3. Não é necessário editar o JSON. Defina as variáveis de ambiente e, no n8n, selecione credenciais (PostgreSQL e, opcionalmente, OAuth2 do Graph) nos nodes apropriados quando importar.
4. Ative o workflow. Para o Webhook Inbound do Intercom, copie a URL gerada pelo n8n (Production URL) e configure no Intercom (eventos de conversa desejados).

## Exemplo de uso (/reply)
- No canal do Teams monitorado, envie: `/reply O cliente confirmou o horário.`
- O fluxo limpará o prefixo e enviará um comentário ao Intercom.
- Quando houver um novo evento no Intercom (ex.: resposta do usuário/admin), o Webhook aciona o fluxo e publica um resumo no canal do Teams.

## Encadeamento de mensagens (incluído)

Agora o template tenta responder no tópico correto quando possível:
- Se já existir mapeamento `conversation_id (Intercom) ↔ message_id (Teams)`, usa `POST /v1.0/teams/{team-id}/channels/{channel-id}/messages/{message-id}/replies`.
- Se ainda não existir mapeamento, cria um novo tópico com `POST /v1.0/teams/{team-id}/channels/{channel-id}/messages` e salva o `message_id` retornado para uso futuro.

Como funciona o mapeamento (agora em PostgreSQL):
- Tabela `conversation_threads` com as colunas: `intercom_conversation_id` (PK), `team_id`, `channel_id`, `teams_message_id`, timestamps.
- Lookup via SELECT busca `teams_message_id` para um `intercom_conversation_id` + `team_id` + `channel_id`.
- Quando não existir, ao criar um novo tópico no Teams, fazemos UPSERT para registrar o `teams_message_id`.

## Banco de dados PostgreSQL

Arquivos:
- `db/init.sql` — cria a tabela `conversation_threads` e trigger de updated_at.
- `db/init_db.sh` — script para criar o banco (se não existir) e aplicar o schema.

Configuração e inicialização:

1. Exportar variáveis de ambiente (ou passar inline):

```bash
export PGHOST=localhost
export PGPORT=5432
export PGUSER=postgres
export PGPASSWORD=secret
export DB_NAME=n8n_intercom
```

2. Rodar o script:

```bash
./intercom-templates/db/init_db.sh
```

3. No n8n, crie uma credencial do tipo PostgreSQL com os mesmos dados (host, porta, usuário, senha, database). Atribua essa credencial aos nodes Postgres do workflow (Lookup/Upsert).

Placeholders relacionados ao DB no workflow:
- As queries usam `TEAMS_TEAM_ID` e `TEAMS_CHANNEL_ID` via variáveis de ambiente para filtrar por time/canal.


## Boas práticas
- Não commit/armazenar tokens ou segredos no repositório.
- Usar credenciais do n8n (OAuth2/Token) e variáveis de ambiente.
- Menor privilégio possível nas permissões do Graph e Intercom.
- Validar payloads do Webhook do Intercom (assinaturas, se habilitadas).

## Solução de problemas
- Mensagem não publica no Teams: verifique permissões do Graph, validade do token e IDs de team/channel.
- Intercom não aciona Webhook: confira a URL pública do n8n (Production URL) e eventos selecionados.
- `/reply` não dispara: confirme `YOUR_TEAMS_CHANNEL_ID` e que a mensagem inicia exatamente com `/reply` (case-sensitive por padrão).

## Licença
MIT (ver arquivo `LICENSE`).