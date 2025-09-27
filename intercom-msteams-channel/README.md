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
- HTTP Request Teams (Graph) publica a mensagem em um canal do Microsoft Teams via Microsoft Graph.

Observação: o caminho “false” do IF foi corrigido para não enviar mensagens que não tenham o prefixo `/reply`.

## Estrutura

- `workflow.json` — workflow do n8n pronto para importação com todos os nodes e conexões.
- `assets/` — opcional para capturas de tela e diagramas.

## Placeholders que você deve preencher

Teams (Trigger e envio via Graph):
- `YOUR_TEAMS_CHANNEL_ID` — ID do canal monitorado pelo Microsoft Teams Trigger.
- `YOUR_TEAM_ID` — ID do time no Microsoft Teams (Graph API).
- `YOUR_CHANNEL_ID` — ID do canal no Microsoft Teams (Graph API) para onde publicar mensagens.
- `YOUR_MS_GRAPH_TOKEN` — token de acesso OAuth2 para Microsoft Graph (ou configure credencial OAuth2 no node em vez do header).

Intercom:
- `YOUR_INTERCOM_API_TOKEN` — token de API do Intercom com permissões para conversas.
- `YOUR_ADMIN_ID` — ID do admin (ou use o payload apropriado para usuário/conversa desejados).

Onde colocar: os placeholders aparecem nos parâmetros dos nodes HTTP Request (Intercom e Graph) e no Teams Trigger. Substitua-os por valores do seu ambiente ou configure credenciais no n8n e remova os headers manuais de Authorization.

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
3. Abra os nodes e substitua os placeholders pelos seus valores ou selecione credenciais configuradas no n8n.
4. Ative o workflow. Para o Webhook Inbound do Intercom, copie a URL gerada pelo n8n (Production URL) e configure no Intercom (eventos de conversa desejados).

## Exemplo de uso (/reply)
- No canal do Teams monitorado, envie: `/reply O cliente confirmou o horário.`
- O fluxo limpará o prefixo e enviará um comentário ao Intercom.
- Quando houver um novo evento no Intercom (ex.: resposta do usuário/admin), o Webhook aciona o fluxo e publica um resumo no canal do Teams.

## Encadeamento de mensagens (opcional, recomendado)
O template publica no canal (nova mensagem). Para responder em um tópico específico, salve o mapeamento `conversation_id (Intercom) ↔ message_id (Teams)` em um Data Store/DB e altere o endpoint Graph para replies:
- `POST /v1.0/teams/{team-id}/channels/{channel-id}/messages/{message-id}/replies`

Você pode adicionar:
- Node “n8n Data Store” (ou Postgres/SQLite) após o envio ao Intercom para registrar `conversation_id` ↔ `message_id`.
- No fluxo Intercom → Teams, buscar o `message_id` e usar o endpoint de replies em vez de criar uma nova mensagem.

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