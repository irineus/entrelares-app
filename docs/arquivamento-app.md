# Arquivamento do `entrelares-app`

**Aberto e FECHADO em 24/08/2026.** Objetivo: tornar o repositório `entrelares-app`
**arquivado** — sem precisar ser atualizado e, principalmente, **sem precisar ser consultado**.
Tudo que diz respeito ao aplicativo Entrelares passa a viver aqui, no `entrelares-flutter`. O
`entrelares-site` continua existindo e responde por tudo do site.

> **FECHADO em 25/08/2026.** As dezessete fatias entraram, incluindo a última — o
> **desligamento do cliente Blazor**, que o plano deixava sem data. Ele não chegou pela medição
> da decisão 7: o owner declarou a rota de rollback desnecessária, que é a decisão que a medição
> existia para provocar. As ações de console foram executadas e conferidas no dia seguinte, e o
> `entrelares-app` está **arquivado**. O passo a passo, e os dois achados que só apareceram ao
> executá-lo, estão em [§ O fecho operacional](#o-fecho-operacional--executado-em-25082026).

> **Este documento REVOGA uma decisão escrita.** O plano de cutover
> (`entrelares-app/docs/flutter-cutover.md`, § *"Onde o rollback morre"*, 23/08/2026) diz:
> *"o repo `entrelares-app` **NÃO** é aposentado: ele continua sendo o repo do banco, das
> Edge Functions, do backlog e do gate de integração"*. Essa frase valia enquanto o repo
> Flutter era a aposta e o Blazor era o produto. O cutover inverteu os dois papéis no dia
> seguinte, e manter a memória, o banco e o gate num repositório que ninguém mais abre é o
> caminho mais curto para perdê-los. A decisão nova é do owner, de 24/08/2026, e substitui
> aquela.

## O que foi medido antes de decidir

Três medições, feitas e não estimadas, porque as três decisões mais caras dependiam delas:

1. **Destacar o gate de banco do Blazor é quase de graça.** Os 52 arquivos / 7.489 linhas da
   suíte de integração dependem do projeto Blazor por apenas `Entrelares.Models` (767 linhas
   de POCOs cuja única dependência é o pacote NuGet `Supabase`) e três helpers estáticos
   puros. Recortado num projeto de contratos, o conjunto compila em **6,6 s, zero avisos,
   221 testes descobertos, nenhuma linha de teste reescrita**.
2. **O gate de fluxo é o problema difícil, não o de banco.** Playwright são **62 testes em
   14 classes**, em todo push (`p0` em `dev`, completo em `master`). A lane
   `integration_test` daqui são **5 `testWidgets` em 2 packs**, agendada, em emulador.
3. **Este repo não tem estágio de homologação.** Ele tem só `main`, e todo push em `main`
   publica produção. A promoção em dois estágios que o `entrelares-app` mantém já morreu
   para o app no dia do cutover.

## As oito decisões (owner, 24/08/2026)

| # | Decisão | Consequência que ela aceita |
|---|---|---|
| 1 | **Faseado**: esvaziar agora, arquivar no dia do desligamento do Blazor | O `archive` de fato vira um passo de um parágrafo, não um projeto |
| 2 | **O gate de banco é PORTADO para Dart** | O caminho mais caro dos avaliados; mitigado pela ordem de execução (abaixo) |
| 3 | **Gate de fluxo:** `flutter drive` + chromedriver rodando `integration_test` no Chrome headless, por push | Depende de um spike: plugins nativos (Play Billing, share sheet) não sobem no web |
| 4 | **A memória (backlog, archive, docs) vem para cá**, e a regra "este repo nunca carrega backlog próprio" é revogada com data e motivo | A regra nasceu quando este repo era spike; a premissa expirou em 23/08 |
| 5 | **O deploy do banco vem para cá**: PR aplica no projeto dev, merge em `main` aplica em prod | Preserva o invariante T-29 (schema e app viajam no mesmo push) e assume o mesmo risco que o app já assume: `main` é produção, sem janela |
| 6 | **`backup.yml` e `keepalive-dev.yml` vêm junto; `publish-release.yml` morre** | Arquivar um repo desliga seus workflows agendados — o backup semanal cifrado de PRODUÇÃO morreria com ele |
| 7 | ~~**O desligamento do Blazor tem condição medida**: N dias consecutivos sem acesso a `legado.entrelares.app`~~ **Ultrapassada em 24/08/2026** | Ela trocava "quando o owner constatar" por um gatilho verificável, para que o passo final não ficasse à deriva. Funcionou como pretendido e nunca precisou disparar: o owner constatou no mesmo dia. Uma condição medida é um seguro contra a decisão que não vem — não um requisito da decisão que vem |
| 8 | **Os commits presos em `dev` são promovidos** assim que o E2E fechar | É a última promoção do Blazor. **Bloqueada em 24/08/2026** por um ruleset que exige o status check `deploy` — o check da esteira que o desligamento remove; ver § O que falta |

## O princípio que ordena a execução

**Tocar o `entrelares-app` o menos possível.** Cada toque custa uma promoção `dev`→`master`
por um gate hoje vermelho. E há um acoplamento que impede limpeza precoce:
`Entrelares.E2ETests` referencia `Entrelares.IntegrationTests` por `ProjectReference` (reusa
o `E2EFamilyFixture`), então **a suíte de banco não pode sair de lá enquanto o Playwright
viver lá**.

Consequência: durante a travessia **nada se remove** do `entrelares-app` — tudo se **copia**
para cá, e este repo passa a ser a autoridade por declaração. A duplicação é temporária e
barata (o histórico git fica preservado dos dois lados), e o esvaziamento acontece num
**único PR tardio**.

A mesma lógica é o que torna a decisão 2 segura: a suíte C# viaja **primeiro como está**, e
cada PR de port apaga a classe C# que acabou de ganhar equivalente em Dart — o gate nunca
fica descoberto durante a travessia.

## O fatiamento

| # | Repo | O que entrega |
|---|---|---|
| **1** ✅ | flutter | **Ferramental de sessão** (PR #57, 24/08/2026): `tool/notion_mirror.py` enxerga os três repos e agrega entregas cross-repo; a skill `next-item` muda de casa e de rota; este documento |
| **2** ✅ | flutter | **O gate de banco muda de casa, ainda em C#** (24/08/2026): `db-gate/` — `Entrelares.DbContracts` (15 modelos + 2 helpers, 1.010 linhas) e a suíte intacta (52 arquivos, 7.419 linhas, 221 testes, 42 classes), mais o job `db-gate` no `verify.yml` bloqueando o `deploy-web` |
| **3** ✅ | flutter | **Banco e ops** (24/08/2026): `supabase/` inteiro (70 migrations, 12 functions, o runbook de 1.442 linhas), o deploy PR→dev / `main`→prod na ordem migrations → functions → app, mais `backup.yml` e `keepalive-dev.yml`. Tudo **auto-desarmante**: entra sem os secrets e só passa a valer quando o owner os define |
| **4a** ✅ | flutter | **A memória, parte mecânica** (24/08/2026): `backlog/` inteiro (6 + 8 de `archive/`), `docs/`, `database/`, `GitHelp.md`, e o changelog do README do app como `docs/changelog-blazor.md` (138 versões). O espelho passou a ler os registros daqui, e a regra do backlog foi revogada no `CLAUDE.md` — ela era consequência direta desta mudança, não do 4b |
| **4b** ✅ | flutter | **A memória, parte de julgamento** (24/08/2026): sete seções triadas das 900 linhas do `CLAUDE.md` do app — convenções, working agreement, modelo de domínio, invariantes, seção legal, board/esforço e 13 *gotchas* de banco e plataforma. Ficaram para trás os que morrem com o cliente (escopos do Blazor, `RetryHelper`, gotrue-csharp, Realtime em WASM, versionamento por `csproj`, todos os de Playwright). Mais a frase do esforço, que virou falsa, e o parágrafo do roadmap que ainda chamava a 1.8.13 de produção |
| **5** ⚠️ | flutter | **Gate de fluxo — entregue** (24/08/2026): os MESMOS arquivos `integration_test/` rodam num Chrome headless via `flutter drive` + chromedriver, **144 s para os dois packs** contra 10–15 min do emulador. Entrou no `needs:` do `deploy-web` em 24/08/2026. **⚠️ CORRIGIDO em 25/08/2026: ele não estava barrando nada** — a sonda que o aprovou falhava um CORPO de teste, e a suíte falhava no `setUpAll`, que **não** deixa o job vermelho. Detalhe e lição no registro do item; o conserto é do PR #81, de outra sessão, ainda aberto |
| **4c** ✅ | flutter | **A presença de loja** (24/08/2026): `store/` — a cópia das listagens (PT-BR + en-US), os dois masters da marca, `brand-icons.py` (reapontado para os sete arquivos que este repo consome, e **verificado**: reproduz os sete byte a byte), o gráfico de destaque com seu gerador e um `README.md` triado. Ficou para trás o pacote TWA (`twa-manifest.json`, Bubblewrap, o `store/.gitignore` que só listava saída de build). Devia ter vindo no 4a e não veio — o item estava escrito e foi esquecido; é o achado que fez o PR F conferir o repositório inteiro em vez de conferir a lista |
| **6…16** ✅ | flutter | **O port do gate para Dart** (24/08/2026), suíte por suíte — o fatiamento detalhado está na seção seguinte. O PR 6 levou a fundação (contratos erguidos, clientes por identidade, fixture) e uma suíte real como prova; o 16 apagou `db-gate/` e o lane `dotnet`. As 225 asserções são todas Dart |
| **F** ✅ | app | **O esvaziamento, num toque só** (24/08/2026, [`entrelares-app` #309](https://github.com/irineus/entrelares-app/pull/309)): 242 arquivos, −46.941 linhas. Sobra o cliente Blazor, sua suíte unitária e um `deploy.yml` reduzido à metade que publica — o deploy de QA que seguiu o merge fechou **verde em 1 min 39 s**, contra os ~15 min do gate antigo. Saíram também, por decisão do owner, as DUAS suítes C# e o `dependabot.yml`; o que ficou para trás e por quê está no registro do T-56. Não arquiva ainda |
| **G** ✅ | app | **O desligamento** (24/08/2026, [`entrelares-app` #310](https://github.com/irineus/entrelares-app/pull/310)): sai o `deploy.yml` inteiro — a metade que publicava —, sai o modelo de PR que ainda instruía um fluxo sem deploy atrás dele, e os dois documentos passam a descrever um arquivo em vez de um cliente publicado. `E2ETests` e `IntegrationTests` já tinham saído no PR F. Com ele morrem o alias de QA `qa.entrelares.app` e a última esteira fora daqui que ainda alcançava produção |
| **∅** ✅ | app | **O console do owner, em 25/08/2026**: ruleset, promoção `dev`→`master`, domínios e projeto Pages removidos, allow-list e Site URL do Auth limpos nos dois projetos, e o repositório **arquivado**. Conferido de fora da conta — a tabela está em § O fecho operacional. **O T-56 acaba aqui** |

## O port do gate para Dart (PRs 6 a 16)

### A autorização de merge, com data e escopo

O `CLAUDE.md` diz, e continua dizendo: *"PR + squash-merge só com o OK explícito do dono —
nunca automático"*. **Em 24/08/2026 o owner abriu uma exceção com escopo EXCLUSIVO aos PRs 6
a 16 deste port**: cada um vai a PR, espera o CI e é mergeado por quem o abriu **se fechar
verde**. Está registrado aqui para que nenhuma sessão futura leia esses merges como violação
da regra — e para que o escopo fique estreito: a exceção morre com o PR 16, não se estende a
nenhum outro trabalho neste repo.

Três condições vieram junto com ela, e são o que a torna segura:

- **Só se mergeia o seguinte quando o anterior fechou verde.** Enquanto o CI de um roda, o
  próximo pode ser escrito, nunca mergeado.
- **CI vermelho é prioridade máxima** — conserta-se antes de seguir, LENDO o erro. Reexecutar
  até passar é proibido: o último vermelho do gate parecia vazamento de RLS e era
  `statement timeout`.
- **Para-se e pergunta-se ao owner quando a decisão for dele** — com ou sem vermelho.

### As três medições que desenharam o port

1. **Os contratos já existiam em Dart.** Os 12 modelos de tabela em
   `apps/entrelares_app/lib/models/` (816 linhas) eram Dart puro, importando só `dart:convert`
   e `entrelares_core`. Erguê-los para `packages/entrelares_db_contracts` é a simetria exata
   do que `Entrelares.DbContracts` fez em C# — e é o que permite ao gate ler o MESMO contrato
   que o app lê, de modo que uma coluna renomeada não pode ficar verde de um lado e vermelha
   do outro.
2. **41 das 43 classes C# compartilham UMA família** via `[Collection("e2e-family")]`. No
   `dart test` cada ARQUIVO roda em isolate próprio e `setUpAll` é por arquivo, então um port
   ingênuo criaria 41 famílias por execução e martelaria o projeto de QA. A saída é um
   **entrypoint agregador** (`test/db_gate_test.dart`): as suítes são bibliotecas que
   REGISTRAM seus grupos contra uma fixture recebida, e só esse arquivo tem `setUpAll`.
3. **O pacote é o `supabase` puro, NUNCA `supabase_flutter`.** O gate precisa de vários
   clientes autenticados vivos no mesmo processo — é assim que RLS se testa — e o
   `supabase_flutter` inicializa um singleton por processo (lição 8 do piloto), então
   caberia exatamente uma identidade nele.

### O fatiamento, e a aritmética que o verifica

| PR | Grupo | Linhas C# de origem |
|---|---|---|
| 6 ✅ | **Fundação**: `entrelares_db_contracts`, `entrelares_db_gate`, clientes por identidade, fixture completa + `FamilyIsolationTests` como prova | 856 |
| 7 ✅ | RLS, adversarial e consentimento | 752 |
| 8 ✅ | Regras de dia (proteção, transição T-27, horizonte, concorrência) | 647 |
| 9 ✅ | Workflow de troca (auto-aprovação, mensagens, reversão, log) | 618 |
| 10 ✅ | Conta e exclusão (conta, família, perfil, idioma) | 812 |
| 11 ✅ | Convites e multi-cuidador | 628 |
| 12 ✅ | Operador de plataforma + RPCs de admin | 698 |
| 13 ✅ | Sudo, papéis customizados, settings, auth de functions | 997 |
| 14 ✅ | Billing do rail web | 1.064 |
| 15 ✅ | Billing de loja e webhook | 436 |
| 16 ✅ | Apaga `db-gate/` e a lane `dotnet` do workflow | — |

**Cada PR apaga as classes C# que acabou de traduzir**, no mesmo commit. É isso que impede o
gate de ficar descoberto: uma suíte só sai de um lado quando já existe do outro. E a
verificação é uma soma — **`testes C# + testes Dart` tem que continuar 225**. O lado C# é
contado por `python3 tool/count_csharp_tests.py` (que sabe que um `[Theory]` vale um caso por
`[InlineData]`, e não um por método); o lado Dart sai do relatório do `dart test`. O
`verify.yml` imprime a soma no summary de cada run, e o corpo de cada PR a repete.

Os dois lados rodam **como passos do mesmo job**, não como dois jobs: cada um inventa sua
própria família `E2E-<runId>` e as duas varreduras de órfãos poupam o que tem menos de 2 h,
então eles não colidem em FAMÍLIAS — mas colidiriam nas seeds de billing do T-39, que usam
ids externos FIXOS. Um job só, sob o `concurrency: db-gate` que já existia, resolve isso por
construção.

### O que o PR 6 mexeu fora do gate

Ele é o único do port que **podia quebrar o aplicativo**: mover os 12 modelos para
`packages/entrelares_db_contracts` reescreveu 148 imports em 46 arquivos do app. A verificação
foi mecânica (`flutter analyze` + `flutter test`, ambos limpos), e o app não muda mais do PR 7
em diante. Uma única mudança de comportamento veio junto: `Member` ganhou `familyId`,
opcional, porque o app nunca precisa dele (RLS já estreita toda leitura) e o gate precisa —
provar que RLS vale é justamente nomear a família que uma linha declara.

### O que a travessia encontrou (fechada em 24/08/2026)

Os onze PRs fecharam no mesmo dia em que abriram. A aritmética fechou: **225 no começo, 225 no
fim**, com a soma impressa no summary de cada run e repetida no corpo de cada PR. O que sobra
registrado não é o placar, são os quatro achados — três deles coisas que só aparecem quando o
gate roda contra o banco de verdade, e um sobre método.

- **Um defeito de produção, achado pelo PR 7.** `FamilyDeletionRequest.fromJson` lia
  `created_at`; a coluna chama `requested_at` e a tabela não tem a outra. O app parseia por essa
  MESMA fábrica e a tela de Família renderiza `requestedAt`, então **a tela quebrava para toda
  família com pedido de exclusão pendente** — em produção, desde o cutover. Nenhum teste de
  widget podia pegar: eles constroem o objeto em memória, e o nome da coluna é uma afirmação
  sobre uma tabela que ninguém estava perguntando. Isto é o argumento inteiro para um gate de
  banco, e vale mais do que os 225 verdes.
- **A varredura adversarial precisou de uma tradução INFIEL, de propósito.**
  `CrossFamilyAuditLog_IsNotReadable` lia `activity_logs` sem filtro e explodia o
  `statement_timeout` de 8 s conforme o projeto de QA acumulava linhas — o teste morria antes da
  asserção, parecendo vazamento de RLS. A versão Dart filtra pelo id da linha da outra família e
  afirma que veio vazio: mesma afirmação, custo constante. O cabeçalho da suíte diz isso, para
  que a divergência não se leia como descuido.
- **Uma armadilha de string, cara porque mentia sobre a causa.** O sufixo do `runId` era hex
  de caixa mista; o GoTrue guarda e-mail em MINÚSCULAS, então toda busca por endereço errava —
  e o sintoma era `Bad state: No element` num `.single`, que se lê como "a regra não disparou" e
  é "a string não bate". O `runId` é minúsculo desde o PR 7.
- **Analisar a árvore de trabalho não é analisar o commit.** Um PR foi vermelho porque um
  arquivo novo ficou fora do `git add`: o `analyze` local via os dois, o CI via um. Desde então a
  verificação é `git stash push --keep-index -u` → `analyze` → `git stash pop`, que mostra ao
  analisador exatamente o que está no índice.

**Um achado posterior, de 25/08/2026, que muda a leitura da fatia 5.** A lane `web-e2e` entrou
como gate da publicação web sobre uma sonda que provou uma coisa e foi lida como provando outra:
ela falhava um CORPO de teste e o job ficava vermelho; a suíte, porém, estava estourando no
`setUpAll` — e nessa forma o `flutter drive` segue imprimindo "All tests passed" dois segundos
depois de o debug service conectar, tempo em que nenhuma chamada real ao Supabase cabe. Resultado:
**a lane aprovou sem executar asserção nenhuma em todo merge que publicou produção desde 24/08**,
os PRs deste próprio item inclusive. O defeito de fixture é mais velho que o T-56 (o
`e2e_family.dart` lê `roles.role_name`, coluna que nunca existiu — é `role` desde o baseline — e
veio com a lane no lote 3 do T-53, em 19/08); o que é do T-56 é ter promovido a suíte a gate sobre
uma verificação que não cobria a classe de falha que estava acontecendo. Achado pela sessão que
investiga a lane E2E e conferido aqui: no run `32839960732` dela, removido o defeito, o `web-e2e`
ficou **vermelho**. **A lição de método:** uma sonda prova o que ela exercita e nada mais — quando
o teste existe porque a FERRAMENTA mente sobre sucesso, a sonda precisa cobrir todas as formas de
o run terminar, e o registro precisa dizer quais foram cobertas.

Uma consequência de escopo, para não ficar implícita: **a autorização de merge desta seção morre
aqui**. Do próximo item em diante vale de novo a regra do `CLAUDE.md` — PR e squash-merge só com
o OK explícito do owner. (Os dois PRs que fecharam o item — o dos espelhos aqui e o do
desligamento lá — foram autorizados um a um, não por ela.)

~~O que a travessia **não** resolveu: os quatro espelhos C#↔Deno.~~ **Resolvido no mesmo dia**,
depois do desligamento — `packages/entrelares_core/test/mirrors/`. Ficaram no pacote CORE, e não
no app, porque não precisam de Flutter e o lane do core roda primeiro: um drift fica vermelho no
job mais barato do run.

**E o port de um deles achou uma metade faltando, que é o argumento inteiro para tê-los
reposto.** O `AuthMailMirrorTests` afirmava que o cliente escreve `?lang=` no `redirect_to` do
reset; o app Flutter nunca escreveu. Nada estava quebrado, e é exatamente por isso que
atravessou o cutover sem ninguém notar: a `send-auth-email` tem o `profiles.language_detected`
como terceiro sinal e o app escreve essa coluna, então quem já entrou uma vez continuava
recebendo o idioma certo. Mas o sinal 2 é o único que serve para quem **não consegue entrar** —
que é a definição de quem pede uma redefinição de senha — e estava sempre ausente. Reposto com
`DeepLinkUrls.updatePasswordFor(idioma)` e a chave compartilhada em `AuthMail.languageQueryParam`.
A pior hipótese foi conferida contra o CÓDIGO e não herdada do registro do Blazor: se a
allow-list de Redirect URLs não casar com query string, o GoTrue cai no Site URL — e o
`AuthChangeEvent.passwordRecovery` roteia para `/update-password` de onde o app estiver.

O espelho do reset é a única tradução que FORTALECE o original: o C# fixava um método pelo nome
e este app tem dois pontos de reset, então a versão Dart lê todos os call sites de
`resetPasswordForEmail` sob `lib/`. Os quatro foram medidos antes de merecerem confiança, com
cinco sondas vermelhas de propósito — mesma disciplina do gate de fluxo do PR 5.

## O armamento do PR 3 — FEITO (conferido em 24/08/2026)

O código do PR 3 entrou desarmado: sem os secrets, cada passo pulava com nota no summary em vez
de pintar o `main` de vermelho. **O owner armou tudo no mesmo dia**, e isto foi conferido contra
o CI, não contra a memória:

- o job **`db-prod` rodou verde** no push de `main` que fechou o PR 16 — logo os três secrets de
  produção existem e é este repo que aplica schema em produção;
- o **`backup.yml` daqui fechou verde** num `workflow_dispatch` — logo os quatro secrets do R2
  existem;
- as duas cópias antigas estão **`disabled_manually`** no `entrelares-app` desde 24/08 — o
  handover foi `gh workflow disable`, não apagar secrets, porque aquele `backup.yml` **falha**
  com secret ausente por decisão de projeto e apagá-los trocaria "dois backups por semana" por
  "um vermelho por semana".

O `keepalive-dev.yml` daqui não precisou de secret novo: a URL do dev é pública (a mesma do
`env.dart`) e a `SUPABASE_SERVICE_ROLE_DEV` já existia aqui.

## O fecho operacional — EXECUTADO em 25/08/2026

Quatro passos de console, nenhum deles código, todos feitos e conferidos **de fora da conta**:

| Verificação, em 25/08/2026 | Resultado |
|---|---|
| `origin/master` do `entrelares-app` | `800d3ec` — o commit do desligamento, e `.github/` não existe mais no branch |
| `https://legado.entrelares.app/` | não resolve |
| `https://qa.entrelares.app/` | não resolve |
| `https://web.entrelares.app/` | **200** — produção intacta |
| `https://entrelares.app/` | **200** — landing intacta |
| zona `entrelares.app` | 13 registros, nenhum `legado`, nenhum `qa`, nenhum pendurado |
| Workers & Pages | `entrelares-web`, `entrelares-site`, `entrelares-site-preview`, `desmalha` — o `entrelares-app` não existe mais |
| allow-list do Auth, prod | `web.entrelares.app/**` e `app.guardacompartilhada.com/**` (este ainda responde 301, então não está pendurado — é resíduo do F-54 e sai com o T-52). **T-52, 09/09/2026:** a segunda entrada sai do dashboard nesta entrega — passo de console do owner, ao lado da remoção da declaração do pacote legado no `assetlinks.json` |
| allow-list do Auth, dev | uma entrada só: `web.entrelares.app/**`; Site URL corrigido |
| `irineus/entrelares-app` | **archived: true**, somente-leitura desde 25/08/2026 |

As seções abaixo ficam como o registro de COMO e POR QUÊ — a ordem tem motivo, e dois passos
dela não estavam no plano original.

### 1. O ruleset do `master` — RESOLVIDO em 25/08/2026, e não por apagá-lo

A promoção da decisão 8 foi RECUSADA por ele: exigia o status check **`deploy`**, produzido
pela esteira que o desligamento remove. Cadeado que sobreviveu à porta — protegia uma produção
que o desligamento acabou de aposentar, e satisfazê-lo significaria recolocar uma esteira num
arquivo.

**Ler a regra antes de agir mudou a ação.** O ruleset é o `protect-master` (id `18872971`,
criado em 13/07/2026) e tem **três** regras, não uma:

| Regra | O que faz | Bloqueava a promoção? |
|---|---|---|
| `deletion` | impede apagar o branch | não |
| `non_fast_forward` | impede force-push e reescrita de histórico | **não** — a promoção é `--ff-only` |
| `required_status_checks` → contexto `deploy` | exige o check da esteira removida | **sim, só esta** |

Então o certo não era *Delete ruleset*, era desmarcar **Require status checks to pass** e salvar:
o `master` continua protegido contra deleção e reescrita, que é o que aquele ruleset existia
para fazer. Feito assim.

### 2. Promover `dev`→`master` — FEITO em 25/08/2026

`origin/master` está em `800d3ec` — *"chore: o cliente Blazor desliga — a rota de rollback deixa
de existir (#310)"* —, e `.github/` não existe mais naquele branch. Com isso morre o risco que
tornava este passo mais que cosmético: o `master` anterior ainda carregava o `deploy.yml`
PRÉ-esvaziamento, com os passos *"Aplicar migrations e functions em PRODUÇÃO"* apontando para um
`supabase/` parado desde o PR 3 — dois escritores no mesmo banco, que é o que a decisão 5 existe
para impedir.

### 3. Cloudflare e Supabase — FEITO em 25/08/2026, e a ordem tinha motivo

> **Duas travas antes de começar.**
> **(a) Não toque no projeto `entrelares-web`** — é ele que serve `web.entrelares.app`, a
> produção. O que morre é o **`entrelares-app`**. Os nomes são parecidos e ficam lado a lado na
> mesma lista.
> **(b) Não apague a linha `cutover.web_date` do `app_settings`.** Parece lixo do cutover, e o
> gate de banco a fixa: `packages/entrelares_db_gate/test/suites/app_settings.dart` afirma que
> ela existe com `value_type = 'string'`. Apagar deixa o `db-gate` vermelho, e ele bloqueia a
> publicação web. O cabeçalho daquela suíte já diz que a chave está escrita à mão ali justamente
> porque o helper que a possuía morreu com o Blazor.

**Por que a ordem importa.** Um domínio customizado de Pages é um **CNAME na zona apontando para
`entrelares-app.pages.dev`**. Apagar o projeto primeiro e deixar o CNAME de pé cria um registro
*pendurado* — apontando para um alvo que deixou de ser nosso —, e aqui isso é pior que o normal:
`legado.entrelares.app` **ainda está na allow-list de Redirect URLs do Auth** (passo 4b do
runbook do cutover). Quem tomasse o subdomínio receberia link de recuperação de senha. Remover o
domínio ANTES de apagar o projeto faz o CNAME sair junto.

**3a — remover os domínios customizados.**
→ https://dash.cloudflare.com → **Workers & Pages** → projeto **`entrelares-app`** → aba
**Custom domains**: remover **`legado.entrelares.app`** e **`qa.entrelares.app`** (o alias de QA
que o branch `dev` alimentava; sai de cena com a esteira).
*Sucesso:* a aba fica sem domínios, só o `entrelares-app.pages.dev`.

**3b — conferir que o DNS foi junto.**
→ mesma dashboard → zona **`entrelares.app`** → **DNS → Records**: procurar `legado` e `qa`; se
sobrou registro, apagar à mão. **É o passo que fecha a janela descrita acima** — não pule.
*Sucesso:* nenhum registro `legado` nem `qa`. O `web` continua lá e não se mexe.

**3c — apagar o projeto Pages.**
→ projeto `entrelares-app` → **Settings** → fim da página → **Delete project**, confirmando o nome.
*Sucesso:* a lista passa a mostrar só `entrelares-web`, `entrelares-site` e `entrelares-site-preview`.

**3d — tirar `legado.entrelares.app` das Redirect URLs do Supabase.**
Foi acrescentado no dia do corte para que recuperação de senha e convites funcionassem pela rota
de rollback; sem a rota, é entrada morta numa allow-list de autenticação.
→ produção: https://supabase.com/dashboard/project/jptqbwfziyzlhlmoekzu/auth/url-configuration
→ dev/QA, por garantia: https://supabase.com/dashboard/project/buroanotfjcgvbfmacuh/auth/url-configuration
Remover as entradas com `legado.entrelares.app`. **Não mexa nas de `web.entrelares.app`** — a
§5.3 do runbook registra que um projeto cuja allow-list não inclui a própria URL do app volta
silenciosamente a mandar todo mundo para o Site URL, sem erro em lugar nenhum.
*Sucesso:* nenhuma linha com `legado.` na lista.

**3e — conferir o SITE URL dos dois projetos, não só a allow-list.** *(achado em 25/08/2026, ao
conferir os prints do passo 3 — não estava previsto)*
O passo 3d tira `legado.` da lista de Redirect URLs, e é fácil parar aí. Mas o **Site URL** é
outro campo, na mesma tela, e é ele que o GoTrue usa quando um `redirect_to` NÃO casa com a
allow-list — silenciosamente, sem erro em lugar nenhum (§5.3 do runbook). O projeto **dev** tinha
`https://qa.entrelares.app` como Site URL, e o `qa.` acabou de morrer com o projeto Pages: o
fallback do dev passou a apontar para um host que não resolve.
→ dev: trocar o Site URL para **`https://web.entrelares.app`** — é o host que o app dev de fato
manda no `redirect_to` (o `DeepLinkUrls` não é por flavor), já está na allow-list de lá, e está
vivo. → prod: conferir que continua `https://web.entrelares.app`.
Na mesma tela do dev, remover as entradas mortas: `https://qa.entrelares.app/**` e
`https://dev.sharedparentalcustody.pages.dev/**` (alias do projeto Pages pré-rebrand, que não
resolve mais — é a MESMA forma de alvo pendurado que o passo 3b fecha, num nome `.pages.dev` que
alguém pode reivindicar). Os dois `localhost` são portas do Blazor local: inofensivos, limpeza
quando der.
*Sucesso:* nenhum host morto no Site URL nem na allow-list dos dois projetos.

> **Por que isto ficou mais grave do que era.** O `?lang=` que o T-56 repôs no `redirect_to` do
> reset é exatamente o caso em que a allow-list pode não casar — uma entrada sem query string
> contra uma URL com `?lang=pt-BR`. Quando isso acontece o GoTrue cai no Site URL, e o registro
> deste item afirma que a pior hipótese é BRANDA porque o `passwordRecovery` roteia para
> `/update-password` de onde o app estiver. **Essa afirmação só vale enquanto o Site URL for um
> host vivo.** Com o dev apontando para o `qa.` morto, a pior hipótese deixava de ser branda
> naquele projeto. Vale como padrão: uma mitigação que depende de configuração precisa ser
> reconferida toda vez que a configuração muda.

**Verificação do passo 3, de fora da conta:**

```powershell
curl.exe -s -o NUL -w "legado: %{http_code}`n" https://legado.entrelares.app/
curl.exe -s -o NUL -w "web:    %{http_code}`n" https://web.entrelares.app/
```

`legado` deve parar de resolver (erro de DNS) ou devolver 404; **`web` tem de continuar 200**.

### 4. Arquivar o repositório — FEITO em 25/08/2026, por último

→ https://github.com/irineus/entrelares-app/settings → **Danger Zone** →
**Archive this repository** → confirmar digitando `irineus/entrelares-app`.
*Sucesso:* a faixa *"This repository has been archived by the owner"* aparece e o repo fica
somente-leitura.
*Por último de propósito:* arquivar desliga agendamentos — e é por isso que o `backup.yml` e o
`keepalive-dev.yml` vieram para cá no PR 3, meses antes de precisarem. Os dois já rodaram verde
aqui, então não há janela descoberta.
*Reversível:* desarquivar é um clique.

## Pontas soltas registradas

- ~~**Este trabalho não tem ID de backlog.**~~ **Resolvido em 24/08/2026: é o T-56**
  ([linha no board](https://app.notion.com/p/3c62f3f4b9b2810fb092ce9aef103ac0)), aberto
  depois que os três primeiros PRs já tinham entrado — o item foi proposto pelo primeiro
  deles. Do quarto em diante os commits levam `Backlog: T-56` e se creditam sozinhos; os
  três anteriores entraram na tabela `HAND_REVIEWED` do espelho. O **registro versionado**
  nasce em `backlog/technical.md` no PR 4a, quando o backlog muda de casa; até lá o corpo
  da página no Notion é provisório.
- ~~**O select `Repo` do board não tem opção `flutter`**.~~ **Resolvido em 24/08/2026:** a opção existe (roxa, ao lado de `app` e `landing`) e o T-56 é o primeiro item marcado com ela. Conferido que os IDs das opções antigas não mudaram — as 182 linhas mantiveram seu valor. **O backfill histórico NÃO foi feito**: T-53, T-54, T-55, U-27 e U-28 foram entregues no repo Flutter mas continuam marcados como `app`, porque eram itens do app quando foram executados. Reescrever isso é decisão de outra natureza — diz respeito ao que a coluna significa (onde o código vive HOJE, ou onde o item foi feito), e fica com o owner.
- **O modelo de esforço mudou de sinal.** Com as entregas cross-repo, o T-53 passou de
  10,4 h (3 commits creditados) para **28,0 h** (41), contra ~14 h de trabalho real
  relatado pelo owner. Não é defeito do espelho: o modelo mede tempo DECORRIDO entre
  merges, e um item densamente creditado passa a absorver as folgas entre eles. Corrigir
  exige retunar `SESSION_GAP`/`SESSION_START`/`MIN_COST`, o que **move o esforço de todos
  os 180 itens do board** — decisão própria, deliberadamente não tomada aqui.
- **`tool/port_catalogs.py` para de ter função.** Quando os catálogos Dart viraram a fonte,
  ele deixou de sincronizar e passou a ser só o registro de como o port foi feito — que é o
  que o próprio cabeçalho dele já diz. Fica, com nota, no PR 4a.
- ~~**`store/` se parte**: textos de listagem e assets de marca são presença de loja viva e
  vêm no PR 4a.~~ **O 4a não o levou** — a ponta ficou escrita e não foi executada, e o repo
  Flutter passou o dia inteiro com o `pubspec.yaml` dizendo, num comentário, que não sabia
  regerar o próprio ícone de launcher e que a arte estava "no outro repositório". **Resolvido no
  PR 4c (24/08/2026)**: vieram as listagens, os dois masters, o `brand-icons.py` reapontado, o
  gráfico de destaque e um `README.md` triado. O projeto TWA (Bubblewrap, `twa-manifest.json`) é
  o pacote morto e ficou para trás com o **T-52**, item próprio **concluído em 09/09/2026**. **A lição de método:**
  uma lista de "o que vem" escrita antes da execução não é conferência — o que confere é olhar o
  repositório de origem inteiro no fim, que é o que o PR F faz.
- ~~**O esvaziamento abriu uma lacuna, e ela é do port.**~~ **Fechada em 24/08/2026, no mesmo
  dia em que abriu.** Os quatro espelhos C#↔Deno viraram suítes Dart em
  `packages/entrelares_core/test/mirrors/`, e o port de um deles achou uma metade faltando no
  app (o `?lang=` do reset) — o detalhe está na seção do port. A lacuna durou horas, mas vale
  registrada: ela não apareceu na lista do que vinha, apareceu ao reler o repositório de origem
  inteiro. É a mesma lição de método do `store/`, cobrada duas vezes no mesmo dia.
- **O `git push` não autenticou na sessão que entregou o PR F** (leitura autorizada, escrita
  não: o proxy repassa o push cru e quem recusa é o GitHub). O esvaziamento foi entregue pela
  API — 234 deleções, uma chamada por arquivo, colapsadas pelo squash — e o conteúdo conferido
  byte a byte contra a árvore validada localmente. Fica registrado porque muda o custo de uma
  entrega: **binário não atravessa uma API que recebe conteúdo como string**, então um PR com
  assets depende de push de verdade.

- **O cancelamento do `verify.yml` era do WORKFLOW, e por isso alcançava o `db-gate`.** O achado
  ficou escrito no PR de documentação e deliberadamente não corrigido lá; foi corrigido em
  24/08/2026, junto com os espelhos. Um job **não consegue** se eximir de um cancelamento de
  nível de workflow, então o grupo serializado do `db-gate` — que existe justamente para duas
  suítes nunca se sobreporem — vinha sendo morto no meio assim mesmo, e um run morto antes do
  teardown deixa família órfã para a varredura recolher duas horas depois. O cancelamento desceu
  para os jobs que podem pagá-lo (`verify`, `apk`, `e2e`, `web-e2e`); o `db-gate` mantém o grupo
  de repo inteiro, e **`db-prod` e `deploy-web` passam a ENFILEIRAR** — essa última parte é mais
  larga que o achado e foi tomada de propósito: era o grupo de workflow que os protegia, e
  removê-lo sem repor deixaria um push concorrente capaz de interromper um deploy de produção
  pela metade.

- **Um required status check é uma dependência da EXISTÊNCIA de uma esteira.** A promoção da
  decisão 8 foi recusada por um ruleset que exige o check `deploy` — o check da esteira que o
  próprio desligamento remove. Não era ordem errada da entrega: qualquer ordem esbarraria nisso,
  porque o commit que apaga a esteira é o commit que precisa do check dela. A generalização vale
  para a próxima vez: **toda entrega que remove uma esteira deve perguntar o que ainda exige os
  checks dela** — branch protection, ruleset, badge, automação externa.
  **Resolvido em 25/08/2026, e o desbloqueio ensinou uma segunda coisa:** a primeira instrução
  escrita aqui era "apagar o ruleset", porque ninguém tinha LIDO a regra. Lida, ela tem três
  partes e só uma bloqueava — desmarcar *Require status checks* resolveu sem abrir mão da
  proteção contra deleção e reescrita que o resto do ruleset dá. **Uma regra que atrapalha não é
  automaticamente uma regra para apagar**, e a diferença entre as duas ações custa um `curl` de
  leitura.

- **A allow-list de Redirect URLs do Auth não estava na lista do desligamento, e devia.** O passo
  4b do runbook do cutover acrescentou `legado.entrelares.app` a ela; o inverso não foi escrito
  em lugar nenhum. Sozinha é entrada morta, mas combinada com um CNAME pendurado — que é o que
  sobra se o projeto Pages for apagado antes do domínio — vira caminho para receber link de
  recuperação de senha de um subdomínio nosso que alguém reivindique. Está na sequência do § O
  fecho operacional, com a ordem que fecha a janela. **O padrão a levar: toda configuração
  externa acrescentada por um runbook precisa da linha que a desfaz, escrita no mesmo runbook.**

- ~~**`env.dart` ainda nomeia `qa.entrelares.app` no flavor dev**~~ **Corrigido em 25/08/2026**
  para `dev.web.entrelares.app`. Era inerte — o dev tem `umamiWebsiteId` vazio de propósito,
  então `AnalyticsService.isEnabled` é falso e o rótulo nunca sai —, mas nomeava um host que
  deixou de existir. **A troca não é de nome, é de espécie:** aquele valor era um host REAL que
  por acaso servia de rótulo, e desde o desligamento não existe implantação web de dev nenhuma,
  então qualquer host real ali estaria morto ou seria de outra pessoa. Agora é sintético e
  simétrico ao vizinho `dev.app.entrelares.app`, e o comentário do campo diz por quê — que é o
  que impede alguém de repor um host real no lugar.
