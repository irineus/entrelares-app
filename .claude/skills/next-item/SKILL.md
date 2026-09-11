---
name: next-item
description: Avança o trabalho no board do Entrelares no Notion — database "Backlog" sob "Entrelares — Backlog & Roadmap". Use sempre que o usuário disser "próxima tarefa", "próximo item", "novo item", "o que fazer agora", "vamos desenvolver o F-NN / L-NN", "concluí esse item", "marca como concluído/em andamento", "como está o board", "status do projeto", "cria um card para X", ou qualquer pedido para consultar, atualizar ou expandir o roadmap do Entrelares — mesmo que não mencione o Notion explicitamente. Cobre o app do produto (F-/U-/T-/S- em entrelares-app) e a landing (L- em entrelares-site).
---

# Próximo item — board do Entrelares

Este produto é rastreado no Notion. Os repositórios carregam o código; **o board e as Decisões
vigentes no Notion são a fonte da verdade** sobre o que fazer e o que já foi decidido.

> **Desde o T-63 (07/09/2026) o CARD é o registro do item.** Não existe mais espelho em markdown,
> não existe mais `tool/notion_mirror.py`, e o encerramento não move arquivo nenhum. `backlog/` no
> repositório é **história congelada** — os registros dos itens concluídos, que continuam valendo
> como memória e nunca mais são editados.

Interagir com o usuário em **PT-BR**. Conteúdo de card, página e documento em **English**, como
todo o resto do produto (só UI, notificações e e-mails são PT-BR).

## Identificadores

- Board (data source): `109b1b02-5b6b-48ef-b3b6-990374a3d10f`
- Database (página): `10744177ada74c6b95baedea8c71a96d`
- **Decisões vigentes** (página): `3d42f3f4-b9b2-819d-b0d8-c845b7aa1ae5` — ler as **seções 1 a 6**
- **📜 Decision history** (subpágina da anterior, onde entra a linha nova de cada item):
  `3d42f3f4-b9b2-817d-9681-d2e3a47f277d`
- Repositórios: `github.com/irineus/entrelares-app` (branch **`main`** = PRODUÇÃO) e
  `github.com/irineus/entrelares-site` (branch **`preview`**)
- **O prefixo do ID escolhe o repositório:** `L-*` → `entrelares-site`; todo o resto →
  `entrelares-app`. A coluna `Repo` pode estar com o valor pré-cutover em linha antiga — **o
  prefixo vence**.
- NÃO confundir com o board do **Gestão IM360** (`e50abe7f-1688-402a-96b5-c6049b24ce82`) nem com o
  do **Desmalha** (`d50a2925-fb74-4f67-b0db-af03ef41d1b4`). Projetos diferentes.

### Propriedades do card

| Propriedade | Tipo | Observação |
|---|---|---|
| `Item` | título | **não existe coluna `Nome`nem `Tarefa`** |
| `ID` | texto | na query é **`"userDefined:ID"`**, nunca `ID`. Chave estável (`F-`/`U-`/`T-`/`S-`/`L-` + número), **nunca reusada** — é a junção com todo o histórico dos repos |
| `Fase` | select | os 8 grupos do roadmap (`1 · …` a `8 · …`). **Eixo vivo**, e ele SOBREVIVE ao encerramento |
| `Ordem` | número | aceita decimal — inserção no meio da fila não renumera os demais |
| `Status` | select | `pending` · `in-progress` · `completed` · `skipped` |
| `Prioridade` | select | `critical` · `high` · `medium` · `low` |
| `Notas` | texto | contexto prático: `Origem:`, `Destrava:`, `DECISÃO`, `CONCLUÍDO <data>:` |
| `Tamanho` | select | `P`/`M`/`G`/`GG` = 1/3/5/8 pontos |
| `Tipo` | select | `Feature` · `UI/UX` · `Technical` · `Security` · `Landing` |
| `Conclusão` | data | na query use `date:Conclusão:start` |
| `Complexidade`, `Impacto` | select | `low`/`medium`/`high` |
| `Item pai` / `Sub-itens` | relation | hierarquia feature↔story |

**CONGELADAS — são história, não se preenchem mais** (T-63): `Esforço gasto (h)`,
`Esforço estimado (h)`, `Link`, `Fase de entrega (histórico)`, `Início`.

## Pré-requisito

MCP do Notion conectado na sessão. Se não estiver, **parar e avisar** — sem ele não há board nem
decisões, e adivinhar o status de um item é o defeito que esta regra existe para evitar.

## Passos obrigatórios no início

1. Ler o `CLAUDE.md` do repositório em que se vai trabalhar.
2. Ler a página **Decisões vigentes**, seções **1 a 6**. **Em conflito com qualquer documento do
   repositório, a página vence** — ela é escrita no momento da decisão; o arquivo pode estar
   atrasado. Se a divergência for relevante, avisar o usuário e corrigir o repo na mesma entrega.
   Se a página não puder ser lida, dizer isso antes de seguir — não improvisar de memória.
3. **Não ler o log cronológico na partida.** Ele mora na subpágina **📜 Decision history** e se
   consulta quando a tarefa pedir — rastrear um item, um documento ou um defeito antigo.
4. **Nem as subpáginas de detalhe.** A §2 e a §3 guardam o **enunciado** de cada regra — o que vale
   hoje, onde ela mora no código — mais a **armadilha concreta** que aquela regra já custou, com
   teto de **6 linhas por regra**. O raciocínio, as medições e as contraprovas moram em **seis
   subpáginas por domínio**:

   | Subpágina | Quando abrir |
   |---|---|
   | Database, RLS and RPCs | política, trigger, `SECURITY DEFINER`, migração, comportamento do PostgREST |
   | Android, web and push | build de canal, service worker, FCM, canal de notificação, SDK vendorizado |
   | Billing and monetization | trilho Asaas, Play Billing, transição de plano, grace/dunning |
   | Tests, gates and CI | suíte que concorda com a coisa errada, fila do gate, flake, espelhos |
   | Design system and UX | tokens, os onze componentes, skeletons, tipografia, dark |
   | Legal, policy and analytics | versionamento de política, o método do S-15, sanitizador do Umami |

   Abre-se **a do domínio do item**, e só ela.

   ⚠️ **Ao encerrar item que gere decisão**, o enunciado curto vai para a §2/§3 (respeitando o teto
   de 6 linhas) e o raciocínio vai para a **subpágina do domínio** — nunca tudo na página-mãe.

## Consultar o board

Uma chamada só — a query é tarifada. Buscar tudo o que a sessão precisa de uma vez:

```sql
SELECT "userDefined:ID", "Item", "Status", "Fase", "Ordem", "Prioridade",
       "Tamanho", "Tipo", "Notas", url
FROM "collection://109b1b02-5b6b-48ef-b3b6-990374a3d10f"
WHERE "Status" IN ('pending', 'in-progress')
ORDER BY CAST(substr("Fase", 1, 2) AS INTEGER), "Ordem"
```

Armadilhas que já custaram tempo: a coluna é **`"userDefined:ID"`**, nunca `ID`; **um alias não
serve no `WHERE`**; e `substr("Fase", 1, 2)` funciona porque os grupos são `1 ·` a `8 ·` — se um dia
passarem de nove, o nome ganha zero à esquerda e essa expressão continua certa. Conferir o
resultado: se `CAST(...)` der 0 em toda linha, os nomes dos grupos mudaram.

## Escolher o item

**Com argumento** (`/next-item F-42`): é esse.

**Sem argumento — itens `in-progress` vêm primeiro e o usuário decide.** Antes de propor qualquer
`pending`:

1. Listar TODOS os `in-progress` na ordenação acima, com as **Notas completas** (elas dizem o que
   falta e de quem depende).
2. Perguntar com **AskUserQuestion** em qual seguir — uma opção por item em andamento, mais a opção
   de ir para o próximo `pending`. **Não escolher sozinho:** item em andamento costuma estar parado
   por dependência de terceiro (owner, Play Console, jurídico), e só o usuário sabe se destravou.
3. Sem nenhum `in-progress`, o próximo é o primeiro não concluído na ordenação, respeitando as
   dependências anotadas nas Notas.

Apresentar o item escolhido **com o corpo do card e as Notas completas** antes de começar — é ali
que está o registro inteiro e a decisão bloqueante.

## Renomear a sessão

Assim que o item estiver escolhido, renomear a sessão para **`<ID> — <Item>`** (ex.:
`F-50 — Viewer member`). Sem isso a lista de sessões não diz em que se trabalhou.

`set_session_title` exige o **id real** da sessão — `session_id: "self"` é recusado. O `"self"` só
vale no `get_session`, que é de onde o id sai:

1. `get_session` **sem** `session_id` → devolve `ccr.id` (`session_...`) desta sessão;
2. `set_session_title` com esse `session_id` e o título.

Se a ferramenta não estiver exposta, dizer isso **uma vez** e pedir que o usuário renomeie na UI —
nunca pular em silêncio.

## Analisar antes de escrever — o ritmo do Entrelares

**Análise detalhada + gap questions (AskUserQuestion) ANTES de qualquer código.** Escopo, arquivos
tocados, riscos, dependências, plano de teste, e se o item precisa de migração ou Edge Function.
Só implementar depois que as decisões estiverem travadas. Item grande: propor divisão em 2–3 PRs
incrementais e deixar o usuário escolher.

**Um escopo por sessão.**

## Executar

1. Marcar o card como **`in-progress`** ao começar.
2. **Branch nova a partir da base ATUAL** (`main` no app, `preview` na landing) — nunca reusar
   branch já mergeada, que o squash órfã. Nome sugerido: `feature/<id>-<slug>`.
   Quando a branch designada da sessão for a própria `main`, **não commitar nela**.
3. Testes vão junto com a feature, no mesmo item: regra pura → espelho em
   `packages/entrelares_core` com `dart test`; tela → widget test; **regra de banco →
   `packages/entrelares_db_gate`** (suíte em `test/suites/`, ligada ao entrypoint agregador);
   fluxo de dois usuários → lane `integration_test`.
4. **Rodar o gate localmente antes do push** — o lane core usa `--fatal-infos` e é o PRIMEIRO passo,
   então uma info derruba o job e os lanes de app e web nem começam:
   ```
   cd packages/entrelares_core && fvm dart analyze --fatal-infos && fvm dart test
   cd app && fvm flutter analyze && fvm flutter test
   ```
   Item que tocou o banco roda também o DB gate (exige a service_role do **dev**, nunca a de
   produção):
   ```
   cd packages/entrelares_db_gate && E2E_SUPABASE_SERVICE_ROLE_KEY=<chave dev> fvm dart test
   ```
5. **Version bump na MESMA entrega** para qualquer mudança funcional: `version:` em
   `app/pubspec.yaml` (`2.6.x+NN` — as DUAS metades) **e `Env.appVersion` em
   `app/lib/env.dart`**, que o `env_version_test` prende ao pubspec: bumpar só um
   deixa a suíte do app vermelha (T-52, 09/09/2026). Trabalho só de documentação interna pula.
6. Se a nota do card divergir do que faz sentido, **não seguir em silêncio nem inventar escopo**:
   fazer o que é coerente e registrar a divergência e o motivo nas Notas e na subpágina de
   resultado.

## Ação que só o owner pode fazer — handoff OBRIGATÓRIO

Quase todo item deste produto encosta numa tela que só o owner abre: secret do GitHub, secret de
Edge Function, webhook no Asaas, promoção de bundle na Play, variável no Cloudflare, flip de
`app_settings` em produção, domínio, chave de provedor. **Nunca encerrar — nem pausar — com
instrução genérica** ("configure o webhook", "adicione o secret").

Escrever um **bloco de handoff** por ação, no formato completo definido em `~/.claude/CLAUDE.md`
(seção *Handoff de ação manual*): **o quê** (e o que quebra sem isso) · **onde** (URL clicável direta
+ caminho na UI como plano B) · **quando** (e o que falha fora de ordem) · **como** (valores
literais, copiáveis, campo por campo) · **como conferir** (a evidência visível) · **o que eu faço
depois**.

As URLs reais dos consoles deste produto, com os ids já preenchidos, estão na tabela
**"Consoles — where an OWNER-ONLY action actually happens"** do `CLAUDE.md` do repositório. **Montar
a URL a partir dela, não de memória** — e se o link exato exigir um id interno que o repo não tem
(id numérico do app na Play, account id do Cloudflare), dizer isso e **pedir o link colado uma vez**,
em vez de inventar uma URL que dá 404.

Além do bloco no chat, **registrar nas `Notas` do card** a linha

```
AÇÃO DO OWNER PENDENTE: <o que falta, em uma linha> — <console>
```

Um item que fica `in-progress` esperando clique de terceiro é exatamente o que a seção *Escolher o
item* manda listar no começo da sessão seguinte — e sem essa linha nas Notas, a sessão seguinte não
tem como saber o que era.

Essa linha vai na **mesma `update_properties`** de qualquer outra propriedade que esteja mudando
naquele momento (um `PARCIAL`, um `Status`), nunca numa chamada só para ela — cada escrita no Notion
é uma aprovação do owner (ver *Encerrar o item*).

Enquanto a ação não acontecer: **entregar tudo o que NÃO depende dela** e dizer, com essas palavras,
o que ficou parado — nunca declarar o item completo.

## Encerrar o item

**Cada escrita no Notion é uma aprovação do owner, e nenhuma configuração a cala.** As ferramentas
de escrita do conector do Notion vêm marcadas pelo próprio servidor como exigindo aprovação a cada
chamada (`requiresUserInteraction`, verificado em 11/09/2026): regra de `allow`, modo `auto` e até
`bypassPermissions` não pulam o prompt, e ele nunca oferece "não perguntar de novo". Leitura
(`fetch`, `search`, `query`) não pergunta. Por isso o encerramento se desenha pelo número de
**escritas**: `notion-update-page` aceita **um `command` por chamada** (corpo e propriedades não
se juntam), então a regra é **uma chamada por página** e **todas as propriedades do card numa única
`update_properties`**. E as escritas saem em **bloco contíguo, no fim** — uma agora e outra dali a
dez minutos é o que transforma aprovação em interrupção. **Antes de abrir o bloco, dizer ao usuário
quantas aprovações virão:** até **3** sem decisão (2 se não houver resultado extenso), até **6**
com. Medido em 11/09/2026: eram 4 e 7, porque `Notas` e `Status`/`Conclusão` iam em duas chamadas.

1. **Resultado extenso** (especificação, medição, relatório, ADR): criar como **subpágina do card**
   (`parent: {page_id: <card-id>}`), nunca solta na raiz do workspace. *1 escrita.*
2. **Corpo do card**: é o registro do item — atualizar o que a entrega mudou no enunciado dele
   (`update_content`). *1 escrita.*
3. **Propriedades do card, TODAS numa única `update_properties`.** *1 escrita:*
   - **`Notas`**: o campo é **sobrescrito** — ler o valor atual primeiro (`fetch`, não pergunta) e
     reenviar o texto completo, preservando a linha `Origem:`. Prefixar o que foi feito com
     `CONCLUÍDO <data>:`, com o link do PR;
   - **`Status` = `completed`** e **`Conclusão` = a data de hoje**. As duas coisas, sempre;
   - **`Tamanho`** e **`Tipo`**, se o card ainda não tiver;
   - **`Fase` NÃO se limpa** — ela diz em que grupo o item foi entregue.

   Partir isso em duas chamadas é uma aprovação a mais por item e nenhum benefício.
4. **Decisões vigentes**, se o item gerou decisão (arquitetura, regra, schema, parâmetro, risco). A
   decisão se escreve em **três lugares diferentes** — são três páginas, logo *3 escritas*, e não
   há como fundir sem mudar a estrutura do T-63:
   - **o enunciado** vai para a seção da página-mãe, com `update_content` (**nunca**
     `replace_content`), dentro do teto de 6 linhas;
   - **o raciocínio, as medições e as contraprovas** vão para a **subpágina do domínio**, com
     `insert_content`;
   - **a linha do log** vai para **📜 Decision history**, com `insert_content` e
     `position: start`, com data e item de origem.

   Decisão revogada é a única que volta para a página-mãe: vai para a §6 "Superseded decisions",
   com o motivo. **Não apagar a antiga** — saber o que foi tentado e por que caiu evita refazer a
   discussão.
5. **Varredura de documentação, na MESMA entrega.** `grep -rn '<ID>'` nos `README.md` e `CLAUDE.md`
   dos repos que o item tocou, e corrigir todo acerto que ainda descreva o item como pendente ou
   futuro: tabelas de capacidade ganham a feature entregue; inventários de suíte refletem arquivos
   de teste novos; o `CLAUDE.md` só muda no que mudou em PRODUÇÃO. **Nada disso toca `backlog/`**,
   que é história congelada.
6. Terminar a sessão com um **bloco de resumo** para o board. Se sobrou ação do owner, o resumo
   **abre** com a lista numerada dessas ações (só os títulos — os blocos completos já estão acima),
   antes de qualquer outra coisa: o que vem depois de um resumo longo não é lido.

## Ciclo do Git

**`main` é produção.** Não há branch de QA: um merge em `main` publica `web.entrelares.app` pelo job
`deploy-web`, e a QA que antes acontecia depois do merge tem de acontecer **antes** — no gate verde
do PR, e num build de flavor dev quando a mudança precisa de aparelho real (`workflow_dispatch` →
`build-apk`). O canal Android é a exceção: só sai quando o owner promove um bundle no Play Console.

**Por isso o Entrelares NÃO copia o merge automático do Gestão** (lá `develop` é do CI e `main` é do
dono; aqui só existe `main`, e ela é o dono).

1. Commit em **PT-BR**, conventional-commit (`feat(calendario): …`).
2. Push: `git push -u origin <branch>`.
3. **PR + squash-merge só com o OK explícito do usuário — nunca automático.**
   **Exceção permanente:** gate VERMELHO consertado corrigindo os TESTES (flake, rate-limit,
   asserção errada — sem mudança de comportamento) pode ser mergeado direto.
4. `verify.yml` roda no próprio PR (gatilho `pull_request`), então o gate fica verde **antes** do
   merge.
5. Em sessão do Claude Code na web o `gh` **não** existe — usar as ferramentas MCP do GitHub.
6. **Vermelho entra no laço de correção, não para o item.** Parar e não mergear só quando: a falha
   se repetir pela mesma razão depois de uma tentativa; na terceira tentativa; ou o conserto exigir
   ação que só o usuário pode fazer (secret, conta externa, decisão de produto). Em qualquer um dos
   três: dizer qual foi e por quê, com o log. No terceiro caso, o log **não basta** — vai com o
   bloco de handoff completo (ver *Ação que só o owner pode fazer*).
7. Se a sessão acabar no meio do ciclo, o resumo tem de dizer **em que ponto parou** — branch
   empurrada? PR aberto? mergeado? A sessão seguinte começa daí.

### Limpeza de branch depois do merge

**Não decidir por git, decidir pelo GitHub.** Com squash a ponta da branch deixa de ser ancestral,
e TODA heurística local erra a partir daí — inclusive as duas que já foram recomendadas aqui:

- `git branch --merged` não lista a branch, mesmo com tudo integrado;
- `git cherry`, que compara por *patch-id*, **só acerta em branch de UM commit**. Um squash
  transforma N commits em um só, cujo patch é a união deles: nenhum dos N patch-ids casa. Medido
  em 11/09/2026 (T-66): uma branch de 5 commits, squashed e mergeada, acusou `5` "pendentes",
  enquanto as três de um commit cada acusaram `0`;
- `git diff main...origin/<branch>` engana pelo mesmo motivo — o commit do squash não é ancestral,
  então a base de comparação é antiga e o diff mostra o trabalho da branch como se fosse novidade.

Quem sabe é o GitHub, e ele responde direto:

```bash
gh pr view <N> --json number,state,mergeCommit,headRefName
# MERGED + o sha do merge = integrado, pode remover
```

**Em sessão na nuvem, apagar branch remota é impossível — não tentar.** Todo o tráfego de git passa
por um proxy com *push protection*: apagar a ref de outra branch devolve `HTTP 403` de forma
determinística, e nenhuma configuração muda isso. Dizer no resumo quais branches estão prontas para
remoção, com o link `https://github.com/irineus/entrelares-app/branches`, e **nunca dar a
limpeza como feita**.

## Criar cards novos

**Card primeiro, sem registro em markdown.** `notion-create-pages` com
`parent: {data_source_id: "109b1b02-5b6b-48ef-b3b6-990374a3d10f"}`.

- O **ID** é o próximo número livre da categoria (`F-`/`U-`/`T-`/`S-` no app, `L-` na landing) —
  IDs são estáveis e **nunca reusados**.
- Já nascer com `Fase`, `Ordem`, `Tipo` e `Tamanho` — card sem tamanho some da conta de prazo.
- Nas **Notas** de todo card novo, registrar a **origem** (`Origem: <item ou decisão que gerou
  este>`) e o que ele destrava. Um card sem contexto de origem é inútil três semanas depois.
- O **corpo** do card é o registro: o que o item É, por que existe, escopo, aceitação.
- Pendência registrada nas Decisões vigentes que prometa um card deve virar card de verdade;
  pendência sem card é pendência esquecida.

## Proibições

- **Nunca deletar cards.**
- **Nunca tocar em outro database do workspace** (Gestão IM360, Desmalha) a partir deste projeto.
- **Nunca editar `backlog/`** no repositório: é história congelada desde o T-63.
- IDs de página em **UUID hifenizado** nas chamadas de atualização.
- Nunca aplicar SQL manualmente em produção — migração pelo CI.
