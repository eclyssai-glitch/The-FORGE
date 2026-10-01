# Eventos de demonstração

Dono: `game-engineer`. Responsabilidade: semântica e intenção narrativa dos eventos simulados.
Fonte canônica de tempos e textos: `src/events/origin_chamber_script.gd` (ORIGIN CHAMBER) e
`src/events/genesis_script.gd` (GENESIS) e `src/events/living_script.gd` (LIVING). Procedimento para alterar: skill `demo-events`.

Todos os eventos são fictícios. Nenhum representa, imita ou prepara integração com serviços reais.

Há três cenários (`src/events/scenario.gd`, detalhes em `docs/ARCHITECTURE.md`): **ORIGIN CHAMBER**
(padrão até a virada da Fase C do Loop 4), **GENESIS** (`--scenario=genesis`) e **LIVING**
(`--scenario=living`, Loop 5). `SimEvent.ORIGIN_TYPES`, `SimEvent.GENESIS_TYPES` e `SimEvent.LIVING_TYPES`
listam os tipos de cada roteiro; `SimEvent.ALL_TYPES` é a união (cada tipo uma vez). `session.opened` e
`session.completed` são comuns aos três.

## ORIGIN CHAMBER

| Tipo | Significado narrativo | Efeito no mundo (`WorldState`) |
|---|---|---|
| `session.opened` | Abre a sessão de demonstração | `session_at` |
| `core.activation` | O núcleo desperta | `core_activation_at`, fase ACTIVATING |
| `core.online` | Núcleo estável, energia disponível | `core_online_at`, fase CORE STABLE |
| `fragments.emitted` | Fragmentos geométricos liberados | `fragments_at`, `fragment_count`, fase FRAGMENTS |
| `structure.seeded` | Eixo de construção travado em torno do núcleo | `seeded_at`, fase BUILDING |
| `structure.layer_added` | Uma camada é montada a partir de fragmentos (`payload.layer`) | `layer_times[i]` |
| `structure.materials_applied` | Superfícies brutas viram acabamento | `materials_at`, fase FINISHING |
| `structure.lighting_applied` | Iluminação da câmara em nível de trabalho | `lighting_at` |
| `verification.started` | Anel de verificação começa a varrer a estrutura | `verification_at`, fase VERIFYING |
| `verification.check_passed` | Uma verificação simulada passa (`payload.check`) | `checks[]` |
| `verification.passed` | Todas as verificações passaram | `verified_at`, fase VERIFIED |
| `structure.finalized` | A estrutura trava na forma final | `finalized_at`, fase FINAL FORM |
| `session.completed` | Fim da demonstração | `completed_at`, fase COMPLETE |

Vocabulário exibido (Loop 3): o evento `core.online` aparece como **CORE STABLE** (título e fase) e o
status do núcleo como **ACTIVE** — nada na UI sugere conexão real. Os identificadores internos
(`core.online`, `CORE_ONLINE`, `core_online_at`) permanecem.

A missão exibida no OBSERVATORY (`src/events/mission.gd`) deriva seus 7 objetivos desses eventos.

## GENESIS (Loop 4)

MIKU desperta, as mãos auxiliares reúnem poeira estelar e modelam um mundo novo — **ILVARA-7**, um
subagente fictício — que ganha manto, crosta e céu, duas luas de documentação, um anel de skills; um
cinturão de memória assenta em volta de MIKU e, por fim, os fios de luz ligam tudo. Ritmo contemplativo:
~56 s, nenhum passo a menos de 3 s do anterior (um teste garante ≥ 2,5 s). Tempos são constantes de
`GenesisScript` (`T_*`, `LAYER_TIMES`, `MOON_TIMES`, `DURATION`); a tabela abaixo os espelha para
quem compõe animação, câmera e som, e deve mudar junto.

| T (s) | Tipo | Rótulo | Significado simbólico | Efeito (`GenesisState`) |
|---|---|---|---|---|
| 0 | `session.opened` | SESSION OPENED | Abre a sessão (simulada) | `session_at` |
| 3 | `miku.awaken` | MIKU AWAKENS | O agente central desperta; o halo começa a girar | `awaken_at`, fase AWAKENING |
| 8 | `hands.summoned` | THE HANDS ARRIVE | As mãos auxiliares emergem da névoa (`payload.hands`) | `hands_at`, fase THE HANDS |
| 13 | `dust.gathered` | DUST GATHERS | Poeira estelar em disco entre as mãos: matéria-prima | `dust_at`, fase GATHERING |
| 18 | `planet.seeded` | A WORLD IS SEEDED | Nasce um subagente: núcleo incandescente (`payload.name`) | `seeded_at`, `planet_name`, fase SEEDED |
| 22 | `planet.layer` (0) | MANTLE | Manto incandescente | `planet_layer_times[0]`, fase FORMING |
| 27 | `planet.layer` (1) | CRUST | O manto esfria em crosta | `planet_layer_times[1]` |
| 32 | `planet.layer` (2) | SKY | Atmosfera fina sobre a crosta | `planet_layer_times[2]` |
| 37 | `moon.formed` (0) | FIRST MOON · ALMANAC | Documentação: o almanaque de como o mundo funciona | `moon_times[0]`, `moon_names[0]`, fase MOONRISE |
| 40 | `moon.formed` (1) | SECOND MOON · GLOSSARY | Documentação: o glossário das palavras do mundo | `moon_times[1]`, `moon_names[1]` |
| 43 | `ring.formed` | A RING OF SKILLS | Skills do subagente (`payload.skills`: weaving, charting, listening, mending) | `ring_at`, fase RING OF SKILLS |
| 46 | `belt.formed` | THE MEMORY BELT | Memória: cinturão fino de fragmentos em volta de MIKU | `belt_at`, fase MEMORY BELT |
| 50 | `links.woven` | THREADS OF LIGHT | Links do grafo: fios de luz entre os corpos (`payload.count` = `GenesisScript.LINKS.size()`, 8, incluindo um backlink de NAUVE-2 para ILVARA-7) | `links_at`, `link_count`, fase WEAVING |
| 53 | `planet.stable` | A WORLD HOLDS | O subagente entra em órbita estável (`payload.name`) | `stable_at`, fase STABLE |
| 56 | `session.completed` | SESSION COMPLETE | Fim da demonstração; nada foi enviado ou recebido | `completed_at`, fase COMPLETE |

Fases (`GenesisState.PHASE_NAMES`): STILLNESS → AWAKENING → THE HANDS → GATHERING → SEEDED → FORMING →
MOONRISE → RING OF SKILLS → MEMORY BELT → WEAVING → STABLE → COMPLETE.

Nomes fictícios: planeta em formação **ILVARA-7**; planetas distantes (subagentes já formados, sem
eventos) **NAUVE-2** e **KESTRE-4**; luas **ALMANAC** e **GLOSSARY**. Nenhum imita produto, provedor ou
agente real (teste de termos proibidos em rótulos, detalhes e catálogo).

Entidades (`src/events/genesis_catalog.gd`, `GenesisCatalog`): `miku` (CENTRAL AGENT), `hand_left`,
`hand_right` (AUXILIARY HAND), `planet_forming`, `planet_far_0`, `planet_far_1` (SUBAGENT), `moon_0`,
`moon_1` (DOCUMENTATION), `ring_skill` (SKILLS), `belt_memory` (MEMORY), `relations` (RELATIONS). Cada
linha traz `title`, `kind`/`kind_name` (o que simboliza), `body` (forma celeste) e `summary`; `status(id,
g)` deriva o estado (ex.: planeta UNFORMED → GATHERING DUST → SEEDED → MANTLE · 1/3 … → STABLE).
Os fios tecidos por `links.woven` estão em `GenesisScript.LINKS` (pares de entidades).

Missão (`Mission.evaluate(emitted, &"genesis")`, título `Mission.GENESIS_TITLE`): 10 objetivos, de
"Wake MIKU" a "Hold a stable orbit"; todos completos no fim do roteiro.

Helpers puros para o visual (`GenesisState`/`ScenarioState`): `progress(at, now, ramp)` (0..1 com
smoothstep; 0 antes do evento ou se não ocorreu), `since(at, now)`, `layer_progress(i, now, ramp)`,
`moon_progress(i, now, ramp)`, `formation(now, ramp)` (0 antes da semente, 1 só com o planeta estável,
monotônico), `layers_formed()`, `moons_formed()`, `layer_at(i)`, `moon_at(i)`.

## LIVING (Loop 5 — protótipo MIKU LIVING CHARACTER)

O `Simulation` emite as **ordens de trabalho** e seus desfechos; a mente de MIKU (animator) **reage** a eles
em tempo real (ADR-015: sem seek; reset = recompor a cena). A vida dela (segmento 1) não tem eventos: é dela.
Os testes 5–7 são abertos por marcos; o que acontece neles vem do usuário (sistema de interação,
`docs/AGENT.md`). Tempos: constantes de `LivingScript` (`MILESTONE_TIMES`, `HAND_CUES`, `STEP_CUES`,
`FAIL_CUES`, `T_*`, `USER_CUES`, `DURATION` = 140 s).

| T (s) | Tipo | Rótulo | Significado | Efeito (`LivingState`) |
|---|---|---|---|---|
| 0 | `session.opened` | SESSION OPENED | Abre a sessão (simulada) | `session_at` |
| 0,5 | `living.milestone` (1) | TEST 1 · LIFE | Ela vive antes de qualquer trabalho | `test`, fase LIFE |
| 12 | `living.milestone` (2) | TEST 2 · PUPPET | Marionetes | fase PUPPET |
| 13 / 19 / 25 | `living.hands` (1 / 2 / 4) | 1 HAND · 2 HANDS · 4 HANDS | O trabalho pede 1, 2, depois 4 mãos | `hands`, `hands_at` |
| 31 | `living.milestone` (3) | TEST 3 · WORLD WORK | Construir um mundo | fase WORLD WORK |
| 31,5 | `living.work_order` | WORK ORDER · CALYX | Ordem `wo-calyx`: 5 etapas (`payload.steps`) | `order_*` |
| 33 / 39 / 45 / 51 | `living.work_step` (0–3) | GATHER · COMPRESS · MANTLE · CRUST | Reunir matéria, comprimir o núcleo, manto, crosta (`payload.hands` 2/2/3/4) | `step`, `step_name`, `attempt`, `step_times`, `hands` |
| 57 | `living.milestone` (4) | TEST 4 · FAILURE | Algo dá errado | fase FAILURE |
| 57,5 | `living.work_step` (4, tentativa 1) | SKY | Tecer o céu (2 mãos) | idem |
| 61 | `living.work_failed` (1) | SKY FAILS | O céu rasga | `failures`, `failed_at` |
| 64,5 | `living.work_step` (4, tentativa 2) | SKY · ATTEMPT 2 | Correção elegante (2 mãos) | idem |
| 68 | `living.work_failed` (2) | SKY FAILS AGAIN | Falha de novo: ela perde a compostura | idem |
| 70,5 | `living.work_dismantled` | TORN DOWN | O céu defeituoso é desmontado por 6 mãos (controle agressivo) | `dismantled_at`, `hands` = 6 |
| 75 | `living.work_step` (4, tentativa 3) | SKY · ATTEMPT 3 | Refaz (4 mãos) | idem |
| 79 | `living.work_recovered` | THE SKY HOLDS | O céu se sustenta: recuperação | `recovered_at` |
| 83 | `living.world_complete` | CALYX IS WHOLE | O mundo está completo | `world_complete_at` |
| 89 | `living.milestone` (5) | TEST 5 · USER ATTENTION | Janela para chamar MIKU (cue de automação: clique em MIKU em 90) | fase USER ATTENTION |
| 101 | `living.milestone` (6) | TEST 6 · WORLD TARGET | Janela para indicar um mundo (cue: clique em VESPER em 102) | fase WORLD TARGET |
| 114 | `living.milestone` (7) | TEST 7 · CONFIGURATION | Janela para mudar uma propriedade (cues: "Miku, aumente sua altura" em 115; pedido SEMANTIC sem provider em 130) | fase CONFIGURATION |
| 140 | `session.completed` | SESSION COMPLETE | Fim; nada foi enviado ou recebido | fase COMPLETE |

Fases (`LivingState.PHASE_NAMES`): STILLNESS → LIFE → PUPPET → WORLD WORK → FAILURE → USER ATTENTION →
WORLD TARGET → CONFIGURATION → COMPLETE. `steps_done()` conta as etapas concluídas (a que falha só conta depois
de `work_recovered`); `is_failing()` vale entre uma falha e a recuperação.

Mundos (`LivingScript.WORLDS`, ids fictícios): **VESPER** (`world_vesper`, esquerda), **CALYX** (`world_calyx`,
centro — o mundo da ordem roteirizada), **ORRIN** (`world_orrin`, direita), com âncoras padrão para o layout do
animator. Entidades (`LivingCatalog`): `miku` + os três mundos; status: MIKU STILL → fase / STRAINED durante a
falha; mundo WAITING / ORDERED / `<ETAPA> · n/5` / FAILING / WHOLE.

`USER_CUES` só servem à automação (capturas, tour de gravação), que os injeta como **entrada real**
(`LivingCuePlayer`); jogando, o usuário age quando quiser.

Missão (`Mission.evaluate(emitted, &"living")`, `Mission.LIVING_TITLE`): 9 objetivos (vida, marionetes,
ordem, 5 etapas, 2 falhas, desmontagem, recuperação, mundo inteiro, abrir os testes 5–7).
