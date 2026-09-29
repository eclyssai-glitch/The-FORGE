<!-- Dono: coordenador. Responsabilidade: brief criativo e contratos de interface do Loop 4 (ART DIRECTION RESET). -->
# Loop 4 — ART DIRECTION RESET · vertical slice "GENESIS"

A v0.1.0 foi aprovada tecnicamente e **rejeitada na direção artística**: parece protótipo técnico.
Este loop redefine a linguagem visual e sensorial. A arquitetura funcional é congelada e reaproveitada;
a estética atual (câmara de pilares, anéis segmentados frios, HUD de painéis) é **substituível**.

## Visão (do produto)

- **MIKU** — agente central, personagem original do universo KORIUM — permanece suspensa no espaço como núcleo criador.
- **Mãos auxiliares gigantes** ajudam a formar corpos celestes.
- **Planetas** = subagentes. **Luas** = documentação. **Anéis** = skills. **Cinturões/asteroides** = memória.
  **Artefatos** = pequenos cristais orbitais.
- Lógica relacional de um *vault* (notas ↔ links ↔ grafo), traduzida em **astronomia visual**: corpos são notas,
  fios gravitacionais de luz são links, órbitas agrupam, pulsos ao longo dos fios são "backlinks" se formando.
  Nada de copiar interface de app de notas.
- Estética-alvo: **contemplativa, cósmica, poética, elegante, cinematográfica**. VFX e SFX são obrigatórios.
- Proibido: personagens conhecidas, Y2K, cyberpunk genérico, UI corporativa fria, painel acima da cena.

## Proposta original de MIKU (ponto de partida — o art-director consolida na bíblia)

- **Tecelã celeste**: figura feminina alta e serena, proporções alongadas de estátua (≈ 9 cabeças), suspensa em pé,
  contrapposto leve, cabeça inclinada para a criação abaixo, braços abertos para a frente e para baixo como quem
  rege as mãos gigantes. Dignidade de escultura sacra, nunca sexualizada, nunca estética de idol/anime.
- **Corpo de porcelana lunar**: luz interna (translucidez), brilho perolado que desliza para rosa e ouro pálido em
  ângulos rasantes; sem roupas modeladas; da cintura para baixo um **vestido de luz** que se dissolve num rio de
  poeira estelar (sem pernas modeladas).
- **Rosto**: sereno, olhos fechados sugeridos pela forma, sem boca detalhada; um ponto de luz na testa (a semente).
- **Cabelos**: muito longos, uma única massa que flui para cima e para trás como filamentos de nebulosa
  (jamais duas mechas/“twin tails”, jamais azul-turquesa). Gradiente ouro pálido → rosa → violeta.
  **Os fios do cabelo se prolongam e viram os fios relacionais** que ligam MIKU aos planetas e luas: o cabelo é o grafo.
- **Halo**: arco incompleto fino, tipo astrolábio, atrás da cabeça, girando devagar.
- Diferenciação explícita de franquias: nenhuma paleta, penteado, figurino, microfone, número ou símbolo que remeta a
  personagens existentes (em particular, nada de mechas duplas turquesa).

## Mãos auxiliares (escultóricas e memoráveis)

- Duas mãos monumentais (≈ 7 u cada; o planeta final tem raio ≈ 1,6 u), **sem corpo**: os pulsos emergem da névoa.
- Material **pedra-noite**: basalto azul-profundo polido com micro-pontos de estrelas na pedra (como se esculpidas no
  céu noturno) e **veios de ouro (kintsugi)** que acendem quando trabalham.
- Poses: **esquerda** embala por baixo (palma para cima, dedos curvos); **direita** modela por cima (dedos pairando,
  indicador levemente estendido). Movimento lento, pesado, reverente.

## Cena herói "GENESIS" (layout inicial em unidades de mundo; donos podem refinar e registrar)

| Elemento | Posição / escala inicial |
|---|---|
| MIKU (coração) | (0, 4, 0); altura ≈ 6 u; cabelo até ≈ 10 u acima e atrás |
| Planeta em formação (subagente) | centro (0, 1.0, 4.0); raio final 1.6 |
| Mão esquerda / direita | ≈ (−3.0, −1.5, 4.6) / (3.2, 3.4, 4.8), orientadas para o planeta |
| Luas (documentação) ×2 | órbitas do planeta, raios 3.0 e 4.2 |
| Anel (skills) | em volta do planeta, raio 2.2–2.9, inclinado |
| Cinturão (memória) | em volta de MIKU, raio 16–19, fino |
| Planetas distantes (outros subagentes) ×2 | órbitas de MIKU em raios ≈ 11 e 24, com luas próprias, já formados, dim |
| Fios relacionais | do cabelo de MIKU → planeta → luas / anel / planetas distantes |
| Fundo | nebulosa profunda (sky shader) com núcleo quente atrás de MIKU (contraluz), estrelas em camadas |

Planos: **FORGE** = herói (MIKU no terço superior central, planeta e mãos no terço inferior, leve contra-plongée);
**UNIVERSE** = sistema inteiro (cinturão, planetas distantes); **OBSERVATORY** = vista relacional ¾ alta, fios e
rótulos diegéticos em destaque.

## Roteiro de eventos "GENESIS" (fictício, ~56 s; game-engineer finaliza os tempos)

`session.opened` → `miku.awaken` → `hands.summoned` → `dust.gathered` → `planet.seeded` →
`planet.layer` ×3 (payload `layer`: 0 manto incandescente, 1 crosta, 2 atmosfera) → `moon.formed` ×2 (payload `index`,
`name`) → `ring.formed` → `belt.formed` → `links.woven` → `planet.stable` (payload `name`) → `session.completed`.

## Contratos de interface (nomes fixos; valores são do dono)

- **Eventos (game-engineer)** — aditivo, sem quebrar o main: novas constantes em `SimEvent` com os nomes acima;
  `src/events/genesis_script.gd` (`class_name GenesisScript`, `static build()`), `src/events/genesis_state.gd`
  (`class_name GenesisState`, mesmo padrão de `WorldState`: `*_at` = −1 se não ocorreu; `planet_layer_times[3]`,
  `moon_times[2]`, `ring_at`, `belt_at`, `links_at`, `stable_at`, `hands_at`, `dust_at`, `seeded_at`, `awaken_at`,
  `completed_at`, `phase` + `phase_name()`); cenário selecionável em `Simulation` (`&"origin_chamber"` padrão até a
  virada, `&"genesis"`), `Simulation.world` passa a ser o estado do cenário ativo. Missão e catálogo de entidades do
  GENESIS (`miku`, `hand_left`, `hand_right`, `planet_forming`, `moon_0/1`, `ring_skill`, `belt_memory`,
  `planet_far_0/1`, `relations`).
- **Paleta (art-director)** — `Palette` ganha: `SPACE_DEEP`, `INDIGO`, `NEBULA`, `DUSK_ROSE`, `PEARL`, `BLUSH`,
  `GOLD` (criação), `ICE` (conhecimento/documentação), `STONE` (mãos). Constantes antigas ficam até a limpeza.
- **Materiais (art-director)** — `MaterialLibrary`: `miku_body()`, `miku_hair()`, `miku_gown()`, `halo_arc()`,
  `hand_stone()` (uniform `veins` 0..1), `planet_forming()` (uniforms `heat`, `crust`, `atmosphere`, `formation`
  0..1), `moon_doc()`, `ring_skill()`, `asteroid_memory()`, `orbit_line()`, `relation_thread()` (uniform `pulse`),
  `nebula_sky()` (material de `Sky`), `mote(color)`/`spark(color)` existentes.
- **Esculturas (procedural-modeler)** — pipeline offline SDF → marching cubes em `tools/sculpt/` (Python do venv
  `/opt/korium-py`), saídas versionadas em `assets/meshes/`: `miku_body.obj`, `hand_left.obj`, `hand_right.obj` com
  normais suaves e **AO por vértice** (cor de vértice) + `*.json` de metadados (bounds, pontos de ancoragem: topo da
  cabeça, testa, palmas de MIKU; palma e pontas dos dedos das mãos gigantes). Geradores em runtime em
  `src/procedural/`: `HairRibbons` (curvas → fitas), `OrbitLine` (elipse), `PlanetSphere` (UV + tangentes),
  `AsteroidField` (transforms determinísticos), `RelationThread` (arco entre dois pontos).
- **Áudio (sound-designer)** — `src/audio/audio_director.gd` (`class_name AudioDirector`, Node, construtor sem
  argumentos; composto pelo `world.gd` por caminho como os outros módulos), reage a `Simulation.event_emitted`
  pelos tipos acima, ambiência em loop, buses em `default_bus_layout.tres`.
- **Módulos da cena (animator, Fase B)** — `src/entities/genesis/`: `miku.gd`, `auxiliary_hands.gd`,
  `forming_planet.gd`, `orbital_system.gd` (luas, anel, cinturão, planetas distantes, fios), `src/fx/genesis/`
  (acreção, faíscas, motes), planos de câmera v2. Mesmos princípios: visual = f(`Simulation.world`, `Simulation.time`),
  movimento ambiente via `MotionClock`, seleção por `StaticBody3D` layer 2 + meta `entity_id` + grupo `entity_<id>`.
- **UI (art-director, Fase B)** — discreta e diegética: selo DEMO MODE pequeno; modos como três rótulos mínimos;
  transporte recolhido num arco fino que aparece ao passar o mouse; rótulos de entidades no mundo (Label3D com fio
  guia) em vez de painéis; OBSERVATORY mostra o grafo com rótulos no espaço; H esconde tudo exceto o selo.
  Contratos do smoke (grupos `ui_transport` com `Start`/`Pause`/`Reset`, `demo_badge`) continuam.

## Fases

- **A (paralela, aditiva — o main continua verde)**: art-director (postmortem + bíblia + paleta + shaders v2),
  procedural-modeler (esculturas + geradores), sound-designer (síntese + assets + AudioDirector),
  game-engineer (eventos GENESIS + cenários).
- **B (paralela)**: animator (módulos da cena, VFX, câmeras), game-engineer (composição por cenário, céu/ambiente v2,
  capturas e style frames, smoke), art-director (UI diegética + refino de materiais nos meshes reais),
  sound-designer (mixagem contra o timing real).
- **C**: virada do cenário padrão para GENESIS, limpeza da estética antiga pelos donos, style frames, capturas
  HIGH/LOW, vídeo com áudio, revisão **art-critic** + auditoria **technical-auditor**, rodadas de correção,
  export Windows, checkpoint.

## Critérios de aceitação do Loop 4

1. `docs/art/v0.1-postmortem.md` — por que a v0.1.0 falha artisticamente (objetivo, com capturas).
2. Bíblia visual curta em `docs/VISUAL_DIRECTION.md`: paleta, materiais, iluminação, composição, movimento,
   linguagem sonora (detalhe em `docs/AUDIO.md`).
3. Cena herói com MIKU, ≥ 2 mãos, planeta em formação, luas/anel/cinturão, fios relacionais.
4. VFX (partículas leves, linhas orbitais, brilhos controlados) e SFX (ambiência + formação) audíveis no jogo e no vídeo.
5. UI discreta/diegética; a cena é o herói.
6. Style frames (≥ 6, HUD oculto, 1920×1080), capturas HIGH/LOW, vídeo com áudio.
7. Vertical slice funcionando: testes verdes, smoke PASS, export Windows.
8. Revisão visual forte: `art-critic` ≥ APROVADO COM RESSALVAS com nota ≥ 7 para "início de um universo autoral
   memorável", e auditoria técnica sem bloqueantes.

## Notas de integração

- Fase A · game-engineer integrado (`e854114`): `Simulation.world` continua `WorldState` (ORIGIN); o estado
  GENESIS é `Simulation.genesis` (`GenesisState`), `Simulation.state` = ativo, `Simulation.scenario_changed`
  (ADR-014). Módulos GENESIS leem `Simulation.genesis` + `Simulation.time`; a UI escuta `scenario_changed` e usa
  `Scenario.entity_*`, `Mission.title_for`, `Simulation.state.phase_name()`. Nomes fictícios: planeta ILVARA-7,
  luas ALMANAC/GLOSSARY, distantes NAUVE-2/KESTRE-4; tempos em `GenesisScript` (`docs/DEMO_EVENTS.md`).
- Fase A · art-director integrado (`b90a604`): bíblia GENESIS em `docs/VISUAL_DIRECTION.md`, postmortem em
  `docs/art/v0.1-postmortem.md`, lookdev em `docs/art/lookdev/`. `MaterialLibrary` devolve `ShaderMaterial`
  **em cache** — use `.duplicate()` para estado por corpo; chame `MaterialLibrary.set_motion_time(MotionClock.now())`
  uma vez por quadro e `apply_quality(profile)` ao trocar perfil. Progresso narrativo (`formation`, `heat`, `veins`…)
  é escrito pelos módulos da Fase B. Luz: contraluz quente atrás de MIKU + rim ICE + key lateral ¾ (sem key frontal;
  seção 4 da bíblia). Céu: atualizar `motion_time` do sky ≤ 5 Hz (radiância). Órbitas/fios: fitas cruzadas ou tubos
  finos. Ressalvas para a Fase B: kintsugi uniforme demais (poucas bordas devem ser ouro), magma inicial com leitura
  de "mancha", planeta herói carregado; crosta distante regular.
- Fase A · sound-designer integrado: `AudioDirector` (`src/audio/audio_director.gd`), buses em
  `default_bus_layout.tres`, 15 OGG originais (2,2 MB) em `assets/audio/`, prova em `tools/audio/proof/`.
  Fase B: `world.gd` compõe o AudioDirector por caminho e registra âncoras `set_anchor(&"planet"|&"miku"|&"hands",
  node)`; remix contra o timing real; o grave (50–300 Hz) está denso e constante na mix de prova — abrir espaço;
  investigar "4 resources still in use at exit" observado na gravação de prova.

## Fase B — contratos (cena GENESIS viva)

Princípio: GENESIS é composto **ao lado** da ORIGIN; o padrão continua ORIGIN até a virada (Fase C). Tudo que é
narrativo = f(`Simulation.genesis`, `Simulation.time`); ambiente via `MotionClock`.

- **game-engineer** (`src/world/**`, `src/core/**`, `scenes/**`, `tools/**`, `project.godot`):
  - `world.gd` compõe módulos **por cenário** (`MODULES_BY_SCENARIO`; GENESIS = caminhos abaixo) e recompõe em
    `Simulation.scenario_changed`; `modules=N/M` do smoke conta os módulos do cenário ativo. ORIGIN intacta.
  - GENESIS: `Universe`/sementes da ORIGIN desligados; `WorldEnvironment` v2 (céu `MaterialLibrary.nebula_sky()`,
    AgX, glow contido, névoa/volumétrica leve se couber no LOW, ambiente mínimo — a luz vem do rig), atualização do
    `motion_time` do céu ≤ 5 Hz, `MaterialLibrary.set_motion_time(MotionClock.now())` por quadro e
    `apply_quality()` ao trocar perfil.
  - Áudio: compõe `res://src/audio/audio_director.gd` (nome `AudioDirector`, grupo `audio_director`) em ambos os
    cenários; após compor, registra âncoras: todo nó com meta `audio_anchor` (`&"planet"|&"miku"|&"hands"`) vira
    `set_anchor(kind, node)`.
  - Automação GENESIS: lista de capturas própria (fases-chave × modos, HUD visível) + **style frames**
    (`--style-frames=<dir>`: ≥ 6 enquadramentos herói com HUD oculto, 1920×1080), smoke GENESIS exigindo módulos
    N/N, UI e selo; `tools/capture_evidence.sh --scenario=genesis`. Picker funciona com entidades GENESIS
    (`StaticBody3D` layer 2 + meta `entity_id`).
- **animator** (`src/entities/**`, `src/fx/**`, `src/animation/**`) — módulos GENESIS (caminhos fixos):
  `src/entities/genesis/genesis_light_rig.gd`, `miku.gd`, `auxiliary_hands.gd`, `forming_planet.gd`,
  `orbital_system.gd` (luas, anel, cinturão, planetas distantes, linhas orbitais), `relation_threads.gd` (fios do
  cabelo → corpos, pulsos), `src/fx/genesis/stardust.gd` (poeira/acreção/vestido), `src/fx/genesis/formation_glow.gd`
  (brilhos controlados, faíscas de formação); câmera: planos GENESIS no `CameraDirector` por modo (FORGE herói,
  UNIVERSE sistema, OBSERVATORY relacional) + deriva cinematográfica lenta; foco em qualquer entidade GENESIS.
  Âncoras de áudio por meta `audio_anchor`. Seleção: grupo `entity_<id>` + corpo pickável.
- **art-director** (`src/ui/**`, `src/style/**`): UI diegética GENESIS ciente do cenário (ver bíblia §8), refino dos
  materiais nos meshes reais (ressalvas da Fase A) e `EnvironmentProfile` GENESIS se necessário. UI sons via
  `get_tree().call_group(&"audio_director", &"play_ui", &"ui_tick"|&"ui_select")`; volumes por bus via funções
  estáticas de `AudioDirector`. Contratos do smoke (`ui_transport` com Start/Pause/Reset, `demo_badge`) mantidos.
- **sound-designer**: remix contra o timing real quando a cena existir.
