# Eventos de demonstração

Dono: `game-engineer`. Responsabilidade: semântica e intenção narrativa dos eventos simulados.
Fonte canônica de tempos e textos: `src/events/origin_chamber_script.gd` (ORIGIN CHAMBER) e
`src/events/genesis_script.gd` (GENESIS). Procedimento para alterar: skill `demo-events`.

Todos os eventos são fictícios. Nenhum representa, imita ou prepara integração com serviços reais.

Há dois cenários (`src/events/scenario.gd`, detalhes em `docs/ARCHITECTURE.md`): **ORIGIN CHAMBER**
(padrão até a virada da Fase C do Loop 4) e **GENESIS** (`--scenario=genesis`). `SimEvent.ORIGIN_TYPES`
e `SimEvent.GENESIS_TYPES` listam os tipos de cada roteiro; `SimEvent.ALL_TYPES` é a união (cada tipo
uma vez). `session.opened` e `session.completed` são comuns aos dois.

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
