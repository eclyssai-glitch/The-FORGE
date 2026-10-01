# Arquitetura

Dono: `game-engineer`. Responsabilidade: camadas, fluxo de dados, estrutura de diretórios.

## Camadas

```
src/events   (RefCounted puro)   SimEvent · EventTimeline · Scenario · ScenarioState · Mission
                                  ORIGIN: OriginChamberScript · WorldState · EntityCatalog
                                  GENESIS: GenesisScript · GenesisState · GenesisCatalog
                                  LIVING: LivingScript · LivingState · LivingCatalog
src/agent    (RefCounted puro)   sistema de interação de MIKU (ADR-016): ActionVocabulary · Intent ·
                                  LocalParser · ProviderPort · StructuredPatch · ConfigSchema ·
                                  ConfigValidator · MikuConfig · ActionExecutor/MikuNodeExecutor ·
                                  InteractionRouter (docs/AGENT.md)
     ▲
src/core     (autoloads)          Simulation (relógio + eventos)   Session (modo, seleção, foco, HUD)
                                  Shortcuts (teclado → autoloads) · InputTuning (limiar clique × arrasto)
src/world    (autoload + mundo)   Quality (perfil gráfico) · composição do mundo 3D ·
                                  LivingInteraction (entrada diegética do cenário living)
     ▲                    ▲
3D: src/world, src/entities, src/animation, src/fx, src/procedural, src/style
UI: src/ui (Control nativo), src/style (tema)
```

- **Um produtor de eventos**: `Simulation` avança `EventTimeline` em `_process`, aplica cada evento
  no estado do cenário ativo e emite `event_emitted`. `seek`/`reset`/`set_scenario` reconstroem o
  estado e emitem `world_rebuilt`.
- **Visual derivado**: entidades calculam seu estado a partir do estado do cenário (timestamps
  `*_at`: `Simulation.world` no ORIGIN CHAMBER, `Simulation.genesis` no GENESIS) e `Simulation.time`.
  Não há estado de animação que possa divergir da simulação.
- **UI ↔ 3D** só por autoloads (`Simulation`, `Session`, `Quality`). A UI não referencia nós 3D e vice-versa.
  - Seleção: `Session.select(id)` → `selection_changed(id)` (Picker 3D, listas da UI).
  - Foco de câmera: `Session.focus(id)` → `focus_requested(id)` (emite sempre). A câmera acha o alvo
    pelo grupo `Session.entity_group(id)` = `entity_<id>` (raiz visual de cada entidade selecionável).
  - HUD: `Session.hud_visible` + `hud_visibility_changed(visible)` (atalho H); só a UI reage.
  - Câmera cinematográfica: `Session.cinematic` + `cinematic_changed` (atalho V, menu da UI).
- **Teclado**: `Shortcuts` (`src/core/shortcuts.gd`, filho de `Main`) é o único leitor dos atalhos
  globais (Espaço, R, 1/2/3, Esc, F11, V, H) e só escreve nos autoloads; ignora teclas enquanto um
  `LineEdit`/`TextEdit`/`Range` da UI tem foco. Teclas de câmera são do `CameraDirector`.
- **Qualidade**: `Quality` aplica configurações de viewport e emite `profile_changed`; ambiente,
  luzes e efeitos aplicam a parte deles.

## Cenários (Loop 4)

Um cenário = roteiro de eventos + estado derivado + missão + catálogo de entidades, registrados em
`src/events/scenario.gd` (`Scenario`: `IDS`, `DEFAULT`, `build_events(id)`, `types(id)`, `new_state(id)`,
`derive(id, events)`, `entity_ids/entity_info/entity_status`). Hoje: `&"origin_chamber"` (padrão até
a virada da Fase C), `&"genesis"` e `&"living"` (Loop 5).

`Simulation` toca **um** cenário por vez:

| Membro | Tipo | Papel |
|---|---|---|
| `SCENARIOS` | `Array[StringName]` (const) | = `Scenario.IDS` |
| `scenario` | `StringName` | cenário ativo |
| `set_scenario(id) -> bool` | | troca roteiro (IDLE em 0, velocidade mantida) e estados; emite `scenario_changed(id)`, `world_rebuilt`, `playback_changed`. Mesmo id = nada muda; id desconhecido = `false` + aviso |
| `world` | `WorldState` | estado do ORIGIN CHAMBER |
| `genesis` | `GenesisState` | estado do GENESIS |
| `living` | `LivingState` | estado do LIVING (Loop 5) |
| `state` | `ScenarioState` (getter) | o estado do cenário ativo (`world`, `genesis` ou `living`) |

Decisão (Fase A, aditiva): `world` **continua `WorldState`** em vez de virar o estado do cenário
ativo. Motivo: ~40 leitores atuais (entidades, fx, câmera, UI, testes) fazem `var w := Simulation.world`
e leem campos do ORIGIN; tipar `world` como base comum quebra a inferência de tipo (erro de parse) em
todos eles. Por isso cada cenário tem seu estado tipado e **só o ativo recebe eventos**; o inativo fica
"fresco" (nada aconteceu), sempre não-nulo — no GENESIS o visual do ORIGIN repousa DORMANT sem erros.
Leitores independentes de cenário (fase, fim de sessão, status de entidade) usam `Simulation.state`
(`ScenarioState`: `apply`, `phase_index`, `phase_name`, `is_complete`, `session_at`, `completed_at`,
estáticos `since`/`progress`). Na Fase C, quando o visual do ORIGIN sair, `world` pode ser retipado.

Linha de comando: `--scenario=<origin_chamber|genesis|living>`, lido pelo próprio autoload `Simulation` no
`_ready` (`Simulation.scenario_from_args`; autoloads ficam prontos antes da cena principal, então o mundo
já compõe o cenário pedido, sem montar e desmontar o ORIGIN). O smoke é agnóstico de cenário
(`tools/smoke_test.sh --scenario=genesis`): conta eventos do roteiro ativo, `Simulation.state.is_complete()`,
missão do cenário, reset para `phase_index() == 0`, módulos do cenário composto. Capturas por cenário:
`automation.gd CAPTURES` (ORIGIN) e `CAPTURES_GENESIS`; style frames GENESIS em `StyleFrames`
(`src/core/style_frames.gd`).

### Mundo por cenário (Fase B)

O mundo 3D segue o cenário ativo: `world.gd` compõe os módulos de `MODULES_BY_SCENARIO[Simulation.scenario]`
e **recompõe** em `Simulation.scenario_changed` (módulos antigos saem da árvore na hora — grupos
`entity_<id>` e corpos de seleção vão junto — e são liberados no fim do quadro; o `Environment` é refeito
para o cenário; seleção e hover do cenário anterior são limpos). Persistem entre cenários: `AudioDirector`,
`CameraDirector` e `Picker`. Módulos GENESIS leem `Simulation.genesis` + `Simulation.time` e o relógio de
movimento `MotionClock`; o mundo alimenta `MaterialLibrary.set_motion_time(MotionClock.now())` uma vez por
quadro no GENESIS. Detalhes (ordem, ambiente, âncoras de áudio) em `docs/ENGINE.md`.

Áudio: o `AudioDirector` (sound-designer) é um módulo do mundo como os outros (por caminho, grupo
`audio_director`); reage só a sinais do `Simulation`. A UI toca sons por
`get_tree().call_group(&"audio_director", &"play_ui", ...)`, sem referenciar o nó. O mundo registra como
âncora de som todo `Node3D` com meta `audio_anchor`.

## Cenas

`scenes/main.tscn` (raiz: `main.gd`) → `World` (`scenes/world.tscn`) + `HUD` (`scenes/hud.tscn`)
+ camada de fade + `Shortcuts` (criado em `main.gd`). `main.gd` também ativa automação por argumentos
(`--smoke-test`, `--allow-missing-ui`, `--capture=`, `--capture-only=`, `--style-frames=`, `--quality=`;
`--scenario=` é do `Simulation`) e oferece `quit_game(code)` (silencia o áudio do mundo, espera 0,25 s,
sai) para saídas roteirizadas.

`World` (`src/world/world.gd`) compõe, nesta ordem: `WorldEnvironment` → módulos do cenário ativo
(ORIGIN: entidades `src/entities` + efeitos `src/fx`; GENESIS: `src/entities/genesis` + `src/fx/genesis`)
→ `Universe` (só ORIGIN) → `AudioDirector` (`src/audio`) → `CameraDirector` (`src/animation`) → `Picker`.
Módulos de outras áreas entram por caminho e são pulados se ausentes (detalhes em `docs/ENGINE.md`).
Seleção 3D: `Picker` faz raycast na camada de colisão 2 e escreve em `Session`; a UI lê `Session`.

## Diretórios

| Diretório | Conteúdo | Escritor |
|---|---|---|
| `src/events` | Lógica pura de eventos, mundo, missão, entidades | game-engineer |
| `src/agent` | Sistema de interação de MIKU: vocabulário, intents, parser, porta de provider, configuração, roteador | game-engineer |
| `config` | Configuração padrão versionada de MIKU (`miku_default.json`) | game-engineer |
| `src/miku` | Runtime da personagem viva (mente, corpo procedural, execução das ações) | animator |
| `src/core` | Autoloads Simulation/Session, main, atalhos, automação, style frames | game-engineer |
| `src/world` | Quality, composição do mundo por cenário, ambiente GENESIS, universo ORIGIN (céu + sementes), seleção (Picker) | game-engineer |
| `src/procedural` | Blueprints e builders de malha | procedural-modeler |
| `src/entities`, `src/animation`, `src/fx` | Entidades, câmeras, efeitos | animator |
| `src/style`, `src/ui` | Paleta, materiais, ambiente, tema, HUD | art-director |
| `src/audio` | AudioDirector (som por eventos, âncoras, buses) | sound-designer |
| `tests/unit`, `tests/integration` | GUT | dono de cada área |
| `tools` | Scripts de teste, captura, export, setup | game-engineer |
| `addons/gut` | GUT 9.7.0 vendorizado (MIT) — não editar | — |

## Cenário LIVING e sistema de interação (Loop 5)

Exceção registrada (ADR-015): no `&"living"` a personagem, as mãos e os fios são **estado em tempo real**
(molas, mente; relógio `MotionClock`), não função de `Simulation.time`. O `Simulation` continua o único produtor
de eventos (ordens de trabalho do roteiro, `LivingScript`); a mente **reage** a eles e às intervenções do usuário.
Consequências no código:

- `Scenario.supports_seek(&"living") == false`: `Simulation.seek()` é recusado ali (um aviso por execução,
  nada muda); `Simulation.reset()` emite `world_rebuilt` e o `World` **recompõe** a cena (mente, mãos e mundos
  novos; o `LivingInteraction` antigo cancela o que não foi aplicado). Ao trocar para o `living` a recomposição
  não se repete (`_skip_rebuild`).
- Ambiente: o `living` reaproveita o céu/ambiente GENESIS (`World.uses_nebula_environment()`).
- Módulos (`World.LIVING_MODULES`, por caminho, ausentes listados em `missing_modules()`): `LivingLightRig`
  (`src/entities/living/living_light_rig.gd`), `Miku` (`src/miku/miku.gd`), `HandPool`, `IntentThreads`,
  `WorkWorld` (`src/entities/living/*`), `CausalParticles` (`src/fx/living/causal_particles.gd`) — do animator —
  e por último `LivingInteraction` (`src/world/living_interaction.gd`, game-engineer). A câmera narrativa é do
  `CameraDirector`.

**Character ≠ Provider ≠ Worker** (ADR-016): `USER → INTENT → LOCAL|PROVIDER → PATCH → VALIDATION → MUTATION →
GAME STATE`, com um plano de ações do vocabulário executado pelo corpo de MIKU. Detalhes, APIs e contratos em
`docs/AGENT.md`.

Entrada diegética, só por autoloads (`Session`):

| Membro de `Session` | Papel |
|---|---|
| `entity_clicked(id)` / `click(id)` | o `Picker` chama `click(id)` em todo clique numa entidade (emite sempre, depois `select(id)`); clique no vazio continua `select(&"")` |
| `call_line_open`, `call_line_changed(open)`, `open_call_line()`, `close_call_line()` | linha de chamada; `Shortcuts` abre com Enter (ação `call_line`) só no `living` |
| `call_submitted(text)`, `submit_call(text)` | texto da linha (fecha a linha antes; vazio só fecha; máx. `CALL_MAX_CHARS`) |
| `interaction_reported(report)`, `report_interaction(report)` | resultado de cada pedido para retorno diegético da UI |

O `LivingInteraction` escuta `entity_clicked` (MIKU = chamar atenção; mundo = indicar) e `call_submitted`
(texto → roteador). A linha de chamada final é da UI (grupo `living_call_line_ui`); sem ela aparece o placeholder
mínimo `LivingCallLine` (CanvasLayer + LineEdit, cores da `Palette`). Não há painel nem menu de configuração.
