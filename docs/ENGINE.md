# Motor gráfico

Dono: `game-engineer`. Responsabilidade: mundo 3D, renderização, ambiente, universo, seleção e qualidade gráfica.
Valores de cor, luz e névoa não são repetidos aqui: vivem em `src/style/` (dono: `art-director`).

## Composição do mundo (`src/world/world.gd`, raiz de `scenes/world.tscn`)

O mundo é composto para o cenário ativo (`Simulation.scenario`, guardado em `world.scenario`) e
**recomposto** em `Simulation.scenario_changed`. Ordem dos filhos (a ordem importa para leitura de cena e
para `_unhandled_input`, que chega primeiro aos nós mais abaixo da árvore):

| # | Nó | Origem | Cenário | Observação |
|---|---|---|---|---|
| 1 | `WorldEnvironment` | `EnvironmentProfile.make_environment()` / `GenesisEnvironment.make_environment()` | ambos (recurso refeito por cenário) | um único `Environment`, exposto em `world.environment` |
| 2 | módulos do cenário | `MODULES_BY_SCENARIO[scenario]` | por cenário | ver tabelas abaixo; recompostos na troca |
| 3 | `Universe` | `src/world/universe.gd` | só ORIGIN | céu + sementes; instala o `Sky` no ambiente |
| 4 | `AudioDirector` | `src/audio/audio_director.gd` | ambos (persiste) | grupo `audio_director`; âncoras por meta (abaixo) |
| 5 | `CameraDirector` | `src/animation/camera_director.gd` | ambos (persiste) | posto no grupo `camera_director` pelo mundo |
| 6 | `Picker` | `src/world/picker.gd` | ambos (persiste) | sempre o último |

Módulos ORIGIN CHAMBER (`ORIGIN_MODULES`, também exposto como `MODULES`): `LightRig`
(`src/entities/light_rig.gd`), `ChamberArchitecture`, `OriginCore`, `FragmentStructure`,
`VerificationArray` (`src/entities/*.gd`), `ActivationPulse`, `DustField`, `EmissionSparks` (`src/fx/*.gd`).

Módulos GENESIS (`GENESIS_MODULES`, caminhos fixos do contrato da Fase B, dono: animator):

| Nó | Script |
|---|---|
| `GenesisLightRig` | `src/entities/genesis/genesis_light_rig.gd` |
| `Miku` | `src/entities/genesis/miku.gd` |
| `AuxiliaryHands` | `src/entities/genesis/auxiliary_hands.gd` |
| `FormingPlanet` | `src/entities/genesis/forming_planet.gd` |
| `OrbitalSystem` | `src/entities/genesis/orbital_system.gd` |
| `RelationThreads` | `src/entities/genesis/relation_threads.gd` |
| `Stardust` | `src/fx/genesis/stardust.gd` |
| `FormationGlow` | `src/fx/genesis/formation_glow.gd` |

- Todos os módulos são carregados **por caminho** (`load(path).new()`, construtor sem argumentos). Se o
  arquivo não existe (`ResourceLoader.exists`), o módulo é pulado com um `push_warning` (uma vez por
  caminho) e o mundo segue com o que existe. `World.load_module(path)` é estático e testável.
- Um módulo que declara a propriedade `environment` (ex.: `LightRig`, `GenesisLightRig`) recebe o
  `Environment` do mundo **antes** do `add_child`. No GENESIS o rig só pode modular
  `ambient_light_energy`; exposição, névoa e energia do céu por modo são do `GenesisEnvironment`.
- Recomposição (`_compose_scenario`): os módulos do cenário anterior e o `Universe` saem da árvore na hora
  (`remove_child`: grupos `entity_<id>` e corpos de seleção somem no mesmo quadro) e são liberados com
  `queue_free`; `Session.select(&"")`/`hover(&"")` limpam a seleção do cenário anterior; o novo ambiente é
  instalado; qualidade e modo são reaplicados; as âncoras de áudio são varridas de novo. Os módulos novos
  entram logo após o `WorldEnvironment` (`move_child`), então `AudioDirector`, `CameraDirector` e `Picker`
  mantêm a ordem.
- Sem `CameraDirector`, o mundo cria uma `Camera3D` de reserva (`FallbackCamera`, `current`) com um
  enquadramento fixo por modo e cenário (`FALLBACK_SHOTS`, `FALLBACK_SHOTS_GENESIS`), para nunca ficar
  sem câmera. No GENESIS o `CameraDirector` continua o mesmo nó (os planos GENESIS são do animator).
- `world.modules` guarda os nós encontrados por nome (inclui `AudioDirector` e `CameraDirector`);
  `world.scenario`, `world.universe` (null no GENESIS), `world.genesis_sky`, `world.audio_director`,
  `world.picker`, `world.environment`, `world.fallback_camera`, `world.scenario_nodes()` são públicos.
- **Validação de módulos**: `World.expected_module_names(id)` = módulos do cenário + `AudioDirector` +
  `CameraDirector` (ORIGIN 8 + 2 = 10; GENESIS 8 + 2 = 10; sem id = cenário ativo) e
  `world.missing_modules()` (do cenário composto). O smoke escreve `modules=N/M` e falha
  (`RESULT=FAIL`, e o `tools/smoke_test.sh` também confere a linha) se qualquer módulo esperado não
  carregou — o pulo tolerante vale para desenvolvimento, nunca para uma entrega. Enquanto os módulos
  GENESIS do animator não existem, `--scenario=genesis` reprova com `modules=2/10` (esperado).

## Qualidade e modo aplicados ao ambiente

- `Quality.profile_changed` → `MaterialLibrary.apply_quality(profile)` (oitavas de ruído dos materiais
  v2 em cache; sempre) + a parte do cenário: ORIGIN `EnvironmentProfile.apply_quality(env, profile)`
  (SSAO, SSIL, glow, volumétrica; sem volumétrica a névoa de profundidade começa mais perto); GENESIS
  `GenesisEnvironment.apply_quality(env, sky, profile)` (mesmos interruptores + `detail` do céu por
  `MaterialLibrary.SKY_DETAIL` + tamanho da radiância). Aplicado também no `_ready` e na recomposição.
- `Session.mode_changed` → ORIGIN: `EnvironmentProfile.apply_mode_fog(env, mode)` (FORGE fechado,
  UNIVERSE vê longe, OBSERVATORY recua) e `Universe.apply_mode(mode)` (brilho das estrelas); GENESIS:
  `GenesisEnvironment.apply_mode(env, sky, mode)`. Aplicado também no `_ready` e na recomposição.
- O resto do custo (viewport: escala, MSAA, FXAA, atlas de sombras) é do autoload `Quality`;
  partículas e luzes aplicam a parte delas no mesmo sinal.
- Chaves do perfil (`QualityProfiles.get_profile`): `level`, `render_scale`, `scaling_mode`, `msaa`, `fxaa`,
  `ssao`, `ssil`, `glow`, `volumetric_fog`, `shadow_size`, `shadows`, `shadow_splits`, `shadow_filter`,
  `particles`. `shadow_splits` = cascatas da luz direcional principal (4 em todos os níveis desde o Loop 4 r1);
  quem a aplica é o rig de luz (`directional_shadow_mode`), lendo `Quality.profile["shadow_splits"]`.
  Ver *Sombras direcionais* abaixo.

## Sombras direcionais (Loop 4 r1)

Diagnóstico (`sf_07_contraluz`, tronco e vestido de MIKU): a "escada" era **resolução**, não bias. Os style
frames da r1 saíram em AUTO, que sob llvmpipe detecta CPU → **LOW**: atlas direcional 2048 com 2 cascatas
(o rig então usa alcance 36 e blur 2,2) — a sombra do braço sobre o vestido caía numa cascata de ~1024 texels
para ~36 u e virava degraus de ~10–15 px na tela. O mesmo quadro em HIGH (4096, 4 cascatas, alcance 60) já
era liso. Correção do lado do mundo:

| Nível | Atlas direcional e posicional (`shadow_size`) | Cascatas (`shadow_splits`) | Filtro PCF (`shadow_filter`) |
|---|---|---|---|
| LOW | 4096 (era 2048) | 4 (era 2) | `SHADOW_QUALITY_SOFT_LOW` |
| MEDIUM | 4096 (era 2048) | 4 | `SHADOW_QUALITY_SOFT_MEDIUM` |
| HIGH | 4096 | 4 | `SHADOW_QUALITY_SOFT_HIGH` |
| ULTRA | 8192 (era 4096) | 4 | `SHADOW_QUALITY_SOFT_ULTRA` |

- O autoload `Quality` aplica o atlas (`RenderingServer.directional_shadow_atlas_set_size(size, true)` — 16 bits
  de profundidade bastam: a escada não era precisão — e `Viewport.positional_shadow_atlas_size`) e o filtro
  (`RenderingServer.directional_soft_shadow_filter_set_quality` e `positional_soft_shadow_filter_set_quality`),
  em todo `profile_changed`. `project.godot` mantém `soft_shadow_filter_quality=3` só como valor de partida.
- Custo: o GENESIS tem pouquíssimos projetores (só a key; cinturão, anel, fios, véu e halo com
  `cast_shadow` OFF), então 4 passes de cascata são baratos mesmo no LOW; 4096² a 16 bits = 32 MB.
- Prova (`--quality=low`, mesma pose `sf_07`): sem degraus; borda macia contínua no vestido e no tronco. HIGH
  continua liso; `sf_01_hero` (MIKU na cascata 3, ~23 u) liso nos três casos.
- Capturas e style frames rodam em HIGH por padrão (`docs/BUILD.md`, *Qualidade das capturas*), com o nível
  escrito em cada linha do log.

**O que o rig deve usar** (dono: animator; `GenesisLightRig._on_quality`):
- `shadow_enabled = profile["shadows"]`, `directional_shadow_mode = LightRig.shadow_mode_for(profile["shadow_splits"])`
  (sempre 4 agora; o ramo de 2 cascatas fica só como reserva).
- Alcance (`directional_shadow_max_distance`) o menor que cubra os planos de herói: hoje 60 u. Com MIKU a
  9–25 u da câmera, as divisões padrão (0,1/0,2/0,5 → 6/12/30 u) põem o tronco nas cascatas 2–3 (≈ 2048
  texels para 12–30 u). Encurtar para ~40 u (ou `directional_shadow_split_2/3` ≈ 0,25/0,6) adensa ainda mais;
  no UNIVERSE (câmera a ~68 u) a sombra some de qualquer forma.
- Suavidade: `shadow_blur` 1,0–2,0 (o kernel; os *taps* vêm do `shadow_filter` do perfil). Sem
  `light_angular_distance` (PCSS) — ruído pontilhado sem TAA (visto nos previews de escultura).
- Acne/terminador nas superfícies curvas: `shadow_normal_bias` 1,0–2,0 (hoje 1,4) e `shadow_bias` ≈ 0,03–0,1
  (padrão 0,1); `directional_shadow_blend_splits = true` evita a costura entre cascatas.
- Alternativa que o animator pode escolher: MIKU sem projetar sombra da key (`cast_shadow` OFF nas instâncias
  dela) e o AO por vértice + SSAO fazendo o assentamento — o mundo não depende disso.

## Ambiente GENESIS (`src/world/genesis_environment.gd`, `class_name GenesisEnvironment`)

Configuração pura (RefCounted), só com cores de `Palette`; bíblia §4 (luz), §5 (composição), §11 (custo).

- **Céu**: `Sky` com uma **duplicata** de `MaterialLibrary.nebula_sky()` (`world.genesis_sky`,
  `make_sky_material()`), `PROCESS_MODE_AUTOMATIC` (uniforms próprios → radiância refeita quando um
  uniform muda), radiância 32/64/64/128 por nível. Por ser duplicata, `MaterialLibrary.set_motion_time`
  não a toca: o mundo escreve o `motion_time` do céu quantizado em `SKY_MOTION_HZ` = 4 Hz
  (`sky_motion_step(t)` = `floor(t·4)/4`, escrito só quando muda → ≤ 4 re-renderizações da radiância por
  segundo); no LOW o céu fica estático (`sky_motion_enabled(profile)`).
- **Sem pops por modo/plano** (Loop 4 r1): a troca de modo no GENESIS não aplica mais os valores de uma vez.
  O mundo mistura todas as chaves de `MODES` (exposição, névoa de profundidade, comprimento da volumétrica,
  `sky_energy`/`star_intensity`/`nebula_intensity`) do valor **em tela** ao do novo modo em
  `GenesisEnvironment.MODE_BLEND` = `GenesisShots.T_USER` (3,51 s, a mesma duração do movimento de câmera da
  troca de modo), com peso `smoothstep` (`blend_settings`, `blend_weight`, `apply_settings`), em tempo real
  (`world._process` → `_step_environment(delta)`); uma troca no meio de outra parte do que está em tela. Os
  uniforms do céu só mudam durante a mistura (a radiância é refeita só nesses quadros). Composição/recomposição
  e as capturas aplicam direto: `world.snap_environment()` (a automação chama junto do `snap_to_mode_shot`).
  API: `world.environment_blending()`, `world.snap_environment()`.
- **Compensação de exposição pela câmera**: `world.set_exposure_trim(k)` (k × a exposição do modo, limitado a
  `TRIM_RANGE` 0,75–1,35) — o mundo aproxima exponencialmente (`smooth_toward`, `TRIM_TAU` 0,9 s), nunca salta;
  `exposure_trim_target()`; volta a 1 na recomposição. Só a exposição muda; o dono continua sendo o
  `GenesisEnvironment`. O `CameraDirector` é filho do mundo (`get_parent().call(&"set_exposure_trim", k)`).
- **Diagnóstico do "salto ~48–50 s"** (gravação real `--from=42`, câmera cinematográfica, HIGH; luma média
  por quadro com `signalstats`): não há descontinuidade de ambiente no GENESIS — a curva é contínua. Entre
  T+46,5 e T+50 a luma cai ~20 % (49 → 39 em 0–255) e volta a 47 em T+52: é o plano `cue_g_belt`
  (yaw 0,75) que tira o núcleo quente da nebulosa do quadro, seguido do cruzamento para `cue_g_threads`
  (yaw −0,62); numa sequência de 1 quadro/2 s isso lê como salto. Correção cabe ao desenho dos planos
  (animator), que pode também pedir `set_exposure_trim(~1,15)` durante o plano do cinturão. Depois de T+53 a
  luma sobe de forma contínua (46 → 69 até o fim do respiro): o clímax iluminando.
- **Tonemap** AgX, exposição 1,0 (1,05 no UNIVERSE). **Glow** contido: limiar HDR 1,0, `glow_bloom` 0,
  escala HDR 1,8, teto de luminância 8, níveis 2–5 (halo largo e macio só em emissão verdadeira: semente,
  kintsugi, magma, pulsos); ligado também no LOW.
- **Ambiente mínimo**: cor NEBULA, energia 0,3 (a luz vem do rig); reflexos do céu (radiância sem estrelas).
- **Névoa**: profundidade SPACE_DEEP com `fog_aerial_perspective` 0,6 (a distância afunda na nebulosa,
  nunca em cinza), sem afetar o céu; por modo: FORGE 26→90 u (densidade 0,55), UNIVERSE 60→180 (0,45,
  sistema inteiro: cinturão 16–19, planeta distante a 24), OBSERVATORY 22→80 (0,6). Volumétrica leve
  (densidade 0,006, albedo PEARL, anisotropia 0,6 — o contraluz ganha corpo) desligada no LOW, que
  compensa aproximando o início da névoa de profundidade (×0,75).
- **Energia do céu por modo** (uniforms `sky_energy`/`star_intensity`/`nebula_intensity`): FORGE
  1,0/0,85/1,0; UNIVERSE 1,0/1,0/0,9; OBSERVATORY 0,8/0,75/0,8 (a nebulosa recua para os fios lerem).
- SSAO suave (as esculturas já têm AO por vértice); SSIL só no ULTRA (perfil).
- **Restrição para o rig** (verificada com corpos substitutos): luzes direcionais enchem o volume
  volumétrico por igual e deixam a cena leitosa (a pedra-noite vira marrom-acinzentada). Direcionais do
  `GenesisLightRig` devem usar `light_volumetric_fog_energy` ≤ `GenesisEnvironment.DIRECTIONAL_FOG_ENERGY`
  (0,05); a névoa ganha corpo das luzes locais (brilho GOLD do planeta).
- Por quadro no GENESIS (`world._process`): `MaterialLibrary.set_motion_time(MotionClock.now())`.

## Áudio no mundo

- `AudioDirector` (sound-designer) composto por caminho em **ambos** os cenários, nome `AudioDirector`,
  grupo `audio_director` (`World.AUDIO_GROUP`), persistente na recomposição. No ORIGIN só a ambiência toca
  (tipos ORIGIN não têm som, `docs/AUDIO.md`).
- **Âncoras**: todo `Node3D` do mundo com meta `audio_anchor` (`&"planet"`, `&"miku"`, `&"hands"`) vira
  `AudioDirector.set_anchor(kind, node)`. O mundo varre a árvore depois de compor (e em cada
  recomposição) e escuta `SceneTree.node_added` para nós adicionados depois; a checagem é adiada para o fim
  do quadro (`call_deferred`), então uma meta posta no `_ready` do nó conta. Metas postas mais tarde exigem
  `world.register_audio_anchor(node)`. Âncoras liberadas saem sozinhas (`get_anchor` devolve null).
  API: `register_audio_anchors(root)`, `register_audio_anchor(node)`, `audio_anchor_kinds()`,
  `silence_audio()`.
- Smoke: linha `audio=present anchors=<kinds>`; no GENESIS faltar `planet`, `miku` ou `hands` reprova.
- **"resources still in use at exit"** (relatado na gravação de prova do sound-designer): investigado com
  `--verbose`. São a `AudioStreamOggVorbis` + `OggPacketSequence` da ambiência e suas playbacks: o
  `AudioServer` só libera uma playback parada no próximo passo de mixagem; se o motor encerra com a
  ambiência tocando, esse passo não acontece. Não vem da composição (nada vaza durante o jogo; reproduzido
  com `--quit-after`). Correção nas saídas roteirizadas: `Main.quit_game(code)` chama
  `world.silence_audio()` (para todos os players), espera 0,25 s e sai — usado pela automação (smoke,
  capturas, style frames) e pelo tour de review; o smoke GENESIS com `--verbose` não relata mais
  vazamentos. Encerramento forçado (`--quit-after`, usado na prova do Movie Maker) não passa por script:
  lá a mensagem pode aparecer e é inofensiva (fim de processo).

## Universo (`src/world/universe.gd`, `class_name Universe`)

- **Céu**: `Sky` com `ShaderMaterial` de `src/world/universe_sky.gdshader` (`shader_type sky`),
  instalado por `Universe.apply_sky(env)` (`background_mode = BG_SKY`). O fundo continua VOID;
  por cima, estrelas esparsas e frias (duas camadas numa grade de faces de cubo, tamanho em pixels
  de tela a partir de `fwidth(EYEDIR)`, sem costuras) e uma faixa de poeira distante quase
  invisível (grande círculo, ruído de baixa frequência). Cores só de `Palette` (VOID, ASH, BONE).
  Sem `TIME`: o fundo é desenhado a cada quadro (depende da câmera), mas o cubemap de radiância
  (`PROCESS_MODE_AUTOMATIC`, `radiance_size` 64) só é refeito quando um uniform muda.
  `render_mode disable_fog` (a névoa de profundidade cobriria o céu). O passe de cubemap
  (reflexos) não tem estrelas: devolve VOID + `band_color · radiance_lift · smoothstep(-0.1, 0.8, y)`
  (`radiance_lift` 0,05), um gradiente vertical tênue para que metais que refletem o céu não fiquem
  pretos. A luz ambiente continua vindo da cor (`AMBIENT_SOURCE_COLOR`).
  Brilho das estrelas por modo (`Universe.STAR_INTENSITY`): UNIVERSE 0,55 · OBSERVATORY 0,3 ·
  FORGE 0,22 (atrás da câmara o céu não compete com a estrutura). `faint_density` 0,03.
  O shader está em `src/world/` por ser do universo; a revisão estética é do `art-director`.
- **Sementes dormentes**: além da câmara (o piso termina no raio 34), a 60–70 unidades do centro
  (`SEEDS`, coordenadas cilíndricas raio/ângulo/altura): `seed_aurel` r62/−100°/h8 (orbe facetado +
  anel, size 2,2), `seed_vesper` r70/150°/h−1 (fuso + dois anéis, 1,7), `seed_lattice` r66/205°/h14
  (icosaedro + dois anéis cruzados, ambos inclinados — nenhum anel vertical, 1,8).
  Malhas de `MeshBuilder.icosphere`/`ring` (seção do anel proporcional ao size: `RING_THICKNESS`,
  `RING_WIDTH`); cada semente tem sua própria cópia de `MaterialLibrary.dormant_seed()` e de `halo()`
  (BONE, `HALO_STRENGTH` 0,18 em repouso; sem energia, sem EMBER). Cada semente
  tem um `StaticBody3D` (nó `Pick`, máscara 0, `meta entity_id`) com esfera de colisão
  generosa (`PICK_RADIUS_SCALE`). A raiz de cada semente entra no grupo `entity_<id>`
  (`SessionState.entity_group(id)`), alvo de foco da câmera.
- **Seleção só onde é visível** (pendência [IMPORTANTE] do Loop 2): fora do UNIVERSE a névoa de
  profundidade termina em 34 (FORGE) / 30 (OBSERVATORY) e as sementes (60–70) ficam invisíveis. Por
  isso `Universe.apply_mode(mode)` chama `set_seeds_pickable(seeds_pickable_in(mode))`: no UNIVERSE os
  corpos ficam na camada 2; em FORGE/OBSERVATORY, `collision_layer = 0` (o raio do Picker atravessa).
  Estado inicial: não selecionáveis até o primeiro `apply_mode` (o mundo aplica no `_ready`).
  Testado com a câmera do plano FORGE (`CameraShots.mode_shot`) virada para cada semente e com uma
  varredura 17×9 do quadro FORGE; sem a correção a varredura seleciona `seed_*`.
- **Destaque de seleção/hover** (Loop 3): nível por semente, alvo 1 se `Session.selected == id`,
  `HOVER_LEVEL` 0,5 se `Session.hovered == id`, 0 caso contrário **ou fora do UNIVERSE**
  (`highlight_target(id, selected, hovered, pickable)`, estático). O nível anda em tempo real
  (`move_toward`, 0→1 em `Palette.T_FAST`) em `update_highlight(delta)`, chamado do `_process`, e só
  escreve uniformes quando muda. `_apply_highlight` escreve **só** o uniform `select` (= nível) do
  corpo e o `strength` do halo (0,18 → `HALO_STRENGTH_SELECTED` 0,3). Cor e intensidade da seleção
  (`select_color` BONE, `select_energy`) são do `MaterialLibrary.dormant_seed()` (art-director); o
  repouso do corpo (`cold_color`, `cold_energy`) nunca é tocado pelo destaque e o `universe.gd` não
  usa `Palette.BONE/ASH` no corpo. `energy` fica em 0 (nunca EMBER, nunca PALE).
- **Deriva**: oscilação lenta (período ~46 s, ±0,35 un.) e giro lento, em tempo real. É respiração
  ambiente, não estado de simulação: não depende de `Simulation.time` e não precisa de seek.
- API: `seed_ids()`, `seed_node(id)`, `seed_base_position(s)`, `drift_offset(t, phase)`,
  `make_sky_material()`, `apply_sky(env)`, `apply_mode(mode)`, `star_intensity_for(mode)`, `sky_material`,
  `seeds_pickable_in(mode) -> bool` (estático), `set_seeds_pickable(enabled)`, `seeds_pickable() -> bool`,
  `update_highlight(delta)`, `highlight_target(...)` (estático), `seed_highlight(id) -> float`,
  `seed_body_material(id)`, `seed_halo_material(id)`.

## Seleção (`src/world/picker.gd`, `class_name Picker`)

- Raio da câmera ativa (`get_viewport().get_camera_3d()`) contra a camada de colisão 2; o id vem do
  meta `entity_id` do colisor (ou do pai). Consulta física em `_physics_process`.
- Clique × arrasto: limiar único em `src/core/input_tuning.gd` (`InputTuning.DRAG_THRESHOLD_PX` = 4,
  `InputTuning.is_drag(travel)`), compartilhado com a câmera. Conta o **percurso acumulado** do
  ponteiro entre press e release (soma de cada movimento), não o deslocamento líquido: um arrasto
  de ida e volta (160 px) que termina onde começou continua sendo arrasto e não seleciona; 3 px
  seleciona. Clique no vazio → `Session.select(&"")`. A ação `deselect` (Esc) é do `Shortcuts`
  (`src/core/shortcuts.gd`), não do Picker.
- Movimento do mouse → `Session.hover(id)` (congelado durante arrasto).
- Usa `_unhandled_input`: eventos consumidos pela UI não chegam; o Picker nunca marca eventos como
  tratados, para a câmera receber os mesmos arrastos.
- Hover sobre a UI (Loop 3, M-2): `_input` (antes da UI) marca cada movimento como "não chegou";
  `_unhandled_input` marca "chegou". Se o último movimento de um passo de física não chegou ao mundo
  (um painel STOP, slider etc. o consumiu), `Session.hovered` é limpo — um painel sobre uma semente
  não a deixa destacada. `NOTIFICATION_WM_MOUSE_EXIT` (ponteiro sai da janela) também limpa.
  Detecção por consumo em vez de `gui_get_hovered_control()`: vale para qualquer controle que
  consuma o evento e é testável headless (lá a GUI não roteia o ponteiro, sem janela sob o mouse).
- Contrato para quem é selecionável: `StaticBody3D` com `collision_layer = 2` e
  `set_meta("entity_id", StringName)` (ids de `EntityCatalog`).
- API: `pick_at(screen_pos)`, `pick_ray(from, to)`, `path_length(points)`, `is_click_path(points)`,
  `entity_id_of_hit(hit)`, `entity_id_of(collider)`.

## Atalhos, foco e visibilidade do HUD

- `src/core/shortcuts.gd` (`class_name Shortcuts`), nó `Shortcuts` adicionado por `main.gd` como
  último filho de `Main` (o primeiro a ver `_unhandled_input`). Mapeia ações do `project.godot` para
  os autoloads: `demo_toggle` (Espaço) → `Simulation.toggle()`; `demo_reset` (R) → `Simulation.reset()`;
  `mode_universe/forge/observatory` (1/2/3) → `Session.set_mode`; `deselect` (Esc) → `Session.select(&"")`;
  `toggle_fullscreen` (F11, saiu de `main.gd`); `toggle_cinematic` (V) → `Session.set_cinematic(!cinematic)`;
  `toggle_hud` (H) → `Session.toggle_hud()`.
- Só teclas pressionadas, sem eco, modificadores exatos (Ctrl+R não reinicia). Tecla que dispara um
  atalho é marcada como tratada. Com `LineEdit`/`TextEdit`/`Range` (Slider, SpinBox) da UI em foco
  (`get_viewport().gui_get_focus_owner()`), atalhos são ignorados e o evento segue intocado.
  Teclas de câmera (WASD, C, mouse) continuam do `CameraDirector`.
- `Session.focus(id)` emite `focus_requested(id)` sempre (repetido também); não seleciona.
  `Session.hud_visible` + `hud_visibility_changed(visible)` (emite só quando muda); o mundo 3D ignora.
- API estática testável: `Shortcuts.action_for(event)`, `Shortcuts.blocks_shortcuts(focus_owner)`,
  `Shortcuts.apply(action) -> bool`, `Shortcuts.ACTIONS`.

## Automação

`src/core/automation.gd` (capturas): depois de `Session.set_mode` + `Simulation.seek`, aplica a
seleção da captura (`Session.select`, vazia se não houver), chama `snap_to_mode_shot()` em todos os
nós do grupo `camera_director` e, se a captura pede foco, `Session.focus(id)` e espera
`FOCUS_SETTLE` (3,6 s) em vez de `CAPTURE_SETTLE` (2,4 s). Entrada de `CAPTURES`:
`[nome, t, modo, (selecionado), (foco), (opções)]` — o Dictionary final opcional traz opções por
captura (`{"hud": false}` esconde o HUD via `Session.set_hud_visible`; as demais capturas mostram o
HUD, e ele volta visível no fim). Leitura por `capture_selected(c)`, `capture_focus(c)`,
`capture_options(c)` (estáticos). Loop 3: `10_forge_inspector` (t=30,5, FORGE, `layer_2`),
`11_observatory_mid` (t=37, OBSERVATORY), `12_universe_seed_focus` (t=49, UNIVERSE, seleciona e foca
`seed_aurel`), `13_hud_hidden` (t=49, FORGE, HUD oculto — o selo DEMO continua).
`tools/capture_evidence.sh --resolution=WxH` (padrão 1600x900) define janela e tela Xvfb; o conjunto
1280×720 usa `--resolution=1280x720`. O log `[capture]` registra `hud=` e o tamanho da imagem.

**Capturas GENESIS** (`CAPTURES_GENESIS`, escolhidas por `captures_for(Simulation.scenario)`;
`tools/capture_evidence.sh <dir> --scenario=genesis`): `g01_still` 1,5 · `g02_awaken` 5,5 · `g03_hands`
10,5 · `g04_dust` 15,5 · `g05_seeded` 19,5 · `g06_mantle` 24,5 · `g07_crust` 29,5 · `g08_sky` 34,5 ·
`g09_moons` 41,5 · `g10_ring` 44,5 (FORGE) · `g11_belt_universe` 48 (UNIVERSE) · `g12_links_observatory`
51,5 (OBSERVATORY) · `g13`–`g15` estável 55,5 nos três modos · `g16_planet_inspector` (seleciona
`planet_forming`) · `g17_planet_focus` (UNIVERSE, seleciona e foca `planet_forming`) · `g18_hud_hidden`.

**Style frames** (`--style-frames=<dir>`, `tools/style_frames.sh <dir> [--quality=high]`): força GENESIS,
redimensiona a janela para 1920×1080 (`StyleFrames.SIZE`), oculta o HUD (o selo fica) e, para cada pose,
`Session.set_mode` + `Simulation.seek` + `snap_to_mode_shot` e põe uma `Camera3D` própria
(`StyleFrameCamera`, `current`, sem deriva nem tween) na pose; grava `<name>.png` e, no fim, o manifesto
`style_frames.txt`. O script confere o manifesto desta execução, ≥ 6 quadros e 1920×1080 em cada PNG.
Poses (`src/core/style_frames.gd`, `class_name StyleFrames`): Dictionary `{name, time, mode, position,
target, fov}`; o `CameraDirector` pode fornecê-las pelo método **opcional** `style_frame_poses() -> Array`
(usado se tiver ≥ `MIN_FRAMES` = 6 poses válidas; senão `DEFAULT_POSES`). Padrão (layout do contrato):
`sf_01_hero` (t 55, FORGE, contra-plongée), `sf_02_awakening` (6,5), `sf_03_cradle` (25,5), `sf_04_crust`
(30,5), `sf_05_moons_ring` (45), `sf_06_system` (55, UNIVERSE), `sf_07_threads` (52, OBSERVATORY),
`sf_08_silhouette` (55, perfil em contraluz).

Saída: `_quit` passa por `Main.quit_game` (áudio silenciado antes; ver *Áudio no mundo*), com o mesmo
watchdog de 3 s. Sem placa de som (Linux sem `/dev/snd`) os scripts pedem `--audio-driver Dummy`
(`GODOT_AUDIO_FLAGS` em `tools/_proc.sh`; `AUDIO_DRIVER=<nome>` força outro).

Smoke (`--smoke-test`): o mundo tem de estar composto para o cenário ativo (`world.scenario`), com
`modules=N/N` e a linha `audio=` (âncoras obrigatórias no GENESIS). Depois da demo e de pausa/reinício: exercita a UI real por grupos —
`ui_transport` (botões `Start`, `Pause`, `Reset` via `pressed.emit()`, conferindo
`Simulation.status` PLAYING → PAUSED (tempo parado) → IDLE (t=0)) e `demo_badge` (um nó visível com
"DEMO" no `text`, dele ou de um descendente, em UNIVERSE/FORGE/OBSERVATORY, até 1,5 s por modo).
Linhas `ui=present|absent`, `ui_transport start= pause= reset=`, `ui_demo_badge=N/3`. Sem nenhum dos
dois grupos → `ui=absent` e FAIL, exceto com `--allow-missing-ui` (só `SMOKE_ALLOW_MISSING_UI=1` no
`tools/smoke_test.sh`, para branches sem a UI). UI presente mas incompleta/oculta reprova sempre.

## Testes

`tests/integration/test_world_composition.gd`: ambiente e céu instalados, esqueleto do Loop 1
removido, módulo ausente pulado, ordem dos módulos presentes, relatório de módulos coerente com os
scripts, sempre há câmera ativa, qualidade liga/desliga SSAO/SSIL/volumétrica, modo altera a névoa
e o brilho das estrelas, uniform `radiance_lift` presente, 3 sementes com colisores/metas/distância
60–72 e fora do piso, anéis nunca verticais, deriva limitada, lógica de clique (limiar, percurso
acumulado), raycast e clique/arrasto/ida-e-volta/vazio via `_unhandled_input`, grupos `entity_<id>` das
sementes, sementes selecionáveis só no UNIVERSE (camada por modo, além do fim da névoa FORGE/OBSERVATORY,
câmera do plano FORGE virada para cada semente + varredura do quadro FORGE, câmera do plano UNIVERSE),
destaque de seleção/hover das sementes (materiais próprios, transição gradual, `select` 0,5 no hover e 1
na seleção, `cold_color`/`cold_energy` fixos no valor da biblioteca, halo 0,3, desmarcar volta ao repouso,
`energy` 0 e halo BONE, nenhum destaque fora do UNIVERSE), hover limpo quando a UI consome o movimento
ou o ponteiro sai da janela.
`tests/integration/test_interaction_flow.gd`: ações e teclas (V, H, Espaço, R, 1/2/3, Esc, F11; soltar,
eco e Ctrl não disparam), atalhos alteram `Simulation`/`Session`, `focus` emite sempre, `hud_visible`
alterna com sinal, `LineEdit`/`HSlider` em foco bloqueiam e `Button` não, `main.tscn` compõe `Shortcuts`
e a UI sobrevive a modos/seleção/foco/HUD em headless, `CAPTURES` 10–13 (13 com HUD oculto), e o smoke de UI
(`_smoke_ui`: ausente reprova sem a flag; UI conforme de teste passa; selo oculto reprova).
`tests/integration/test_scenario_composition.gd`: módulos esperados por cenário (caminhos GENESIS do
contrato), ORIGIN por padrão, AudioDirector no grupo `audio_director`, recomposição GENESIS ↔ ORIGIN
(módulos e sementes saem, seleção limpa, AudioDirector/Picker persistem, ambiente refeito, nós antigos
liberados), ambiente GENESIS (céu = duplicata do `nebula_sky`, AgX, glow com limiar ≥ 1 sem bloom,
névoa SPACE_DEEP, ambiente ≤ 0,4, reflexos do céu), qualidade/modo GENESIS (LOW sem volumétrica,
`detail` do céu e do planeta por nível, radiância, OBSERVATORY com menos `sky_energy`, UNIVERSE mais
longe), `motion_time` do céu ≤ 4 mudanças/s e estático no LOW, `set_motion_time` por quadro, âncoras de
áudio por meta (antes/depois do `add_child`, fora do mundo ignorado, varredura explícita, âncora liberada
some), âncoras após recomposição, relatório `audio=` do smoke, `silence_audio`, Picker com entidade
GENESIS falsa (camada 2 + `entity_id`) e sem sementes no GENESIS, planos de reserva, `--scenario=` pelo
`Simulation`, poses de style frame (padrão válidas, três modos, do diretor ≥ 6 ou padrão, `apply_pose`),
lista `CAPTURES_GENESIS`.
`tests/unit/test_quality_profiles.gd`: perfis completos (inclui `shadow_splits`, `shadow_filter`), custo
monotônico (também o filtro), 4 cascatas em todos os níveis, atlas ≥ 4096 e filtro ≥ SOFT_LOW (HIGH = SOFT_HIGH).
`tests/integration/test_scenario_composition.gd` (Loop 4 r1): troca de modo GENESIS sem salto (nada muda no
quadro da troca; quadro a quadro a 30 fps monotônico e ≤ 8 % da diferença por quadro; chega ao alvo em
`MODE_BLEND`; `snap_environment` aplica direto), trim de exposição (suave, limitado, zerado na recomposição),
helpers de mistura e argumentos do `genesis_tour` (HUD, nível, tamanho, 0,5 + 56 + 4 s).
