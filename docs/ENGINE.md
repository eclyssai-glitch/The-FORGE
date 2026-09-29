# Motor gráfico

Dono: `game-engineer`. Responsabilidade: mundo 3D, renderização, ambiente, universo, seleção e qualidade gráfica.
Valores de cor, luz e névoa não são repetidos aqui: vivem em `src/style/` (dono: `art-director`).

## Composição do mundo (`src/world/world.gd`, raiz de `scenes/world.tscn`)

Ordem dos filhos (a ordem importa para leitura de cena e para `_unhandled_input`, que chega
primeiro aos nós mais abaixo da árvore):

| # | Nó | Origem | Observação |
|---|---|---|---|
| 1 | `WorldEnvironment` | `EnvironmentProfile.make_environment()` | um único `Environment`, exposto em `world.environment` |
| 2 | `LightRig` | `src/entities/light_rig.gd` | recebe `environment` por propriedade **antes** do `add_child` |
| 3 | `ChamberArchitecture` | `src/entities/chamber_architecture.gd` | |
| 4 | `OriginCore` | `src/entities/origin_core.gd` | |
| 5 | `FragmentStructure` | `src/entities/fragment_structure.gd` | |
| 6 | `VerificationArray` | `src/entities/verification_array.gd` | |
| 7 | `ActivationPulse`, `DustField`, `EmissionSparks` | `src/fx/*.gd` | |
| 8 | `Universe` | `src/world/universe.gd` | céu + sementes; instala o `Sky` no ambiente |
| 9 | `CameraDirector` | `src/animation/camera_director.gd` | posto no grupo `camera_director` pelo mundo |
| 10 | `Picker` | `src/world/picker.gd` | sempre o último |

- Módulos 2–7 e 9 são carregados **por caminho** (`load(path).new()`, construtor sem argumentos).
  Se o arquivo não existe (`ResourceLoader.exists`), o módulo é pulado com um `push_warning`
  (uma vez por caminho) e o mundo segue com o que existe. `World.load_module(path)` é estático e testável.
- Sem `CameraDirector`, o mundo cria uma `Camera3D` de reserva (`FallbackCamera`, `current`) com um
  enquadramento fixo por modo (`FALLBACK_SHOTS`), para nunca ficar sem câmera.
- `world.modules` guarda os nós encontrados por nome; `world.universe`, `world.picker`,
  `world.environment`, `world.fallback_camera` são públicos (para testes e ferramentas).
- **Validação de módulos**: `World.expected_module_names()` (os 8 de `MODULES` + `CameraDirector` = 9)
  e `world.missing_modules()`. O smoke escreve `modules=N/9` e falha (`RESULT=FAIL`, e o
  `tools/smoke_test.sh` também confere a linha) se qualquer módulo esperado não carregou — o pulo
  tolerante vale para desenvolvimento, nunca para uma entrega.

## Qualidade e modo aplicados ao ambiente

- `Quality.profile_changed` → `EnvironmentProfile.apply_quality(env, profile)` (SSAO, SSIL, glow,
  volumétrica; sem volumétrica a névoa de profundidade começa mais perto). Aplicado também no
  `_ready` com `Quality.profile`.
- `Session.mode_changed` → `EnvironmentProfile.apply_mode_fog(env, mode)` (FORGE fechado, UNIVERSE
  vê longe, OBSERVATORY recua) e `Universe.apply_mode(mode)` (brilho das estrelas). Aplicado também
  no `_ready` com `Session.mode`.
- O resto do custo (viewport: escala, MSAA, FXAA, atlas de sombras) é do autoload `Quality`;
  partículas e luzes aplicam a parte delas no mesmo sinal.
- Chaves do perfil (`QualityProfiles.get_profile`): `render_scale`, `scaling_mode`, `msaa`, `fxaa`,
  `ssao`, `ssil`, `glow`, `volumetric_fog`, `shadow_size`, `shadows`, `shadow_splits`, `particles`.
  `shadow_splits` = cascatas da luz direcional principal (LOW 2, MEDIUM/HIGH/ULTRA 4); quem a aplica
  é o `LightRig` (`directional_shadow_mode`), lendo `Quality.profile["shadow_splits"]`.

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
  escreve uniformes quando muda. Efeito, sempre BONE: fresnel `cold_color` ASH→BONE e `cold_energy`
  `COLD_ENERGY_BASE` 0,55 → `COLD_ENERGY_SELECTED` 1,5; halo `strength` 0,18 → `HALO_STRENGTH_SELECTED`
  0,6. `energy` fica em 0 (nunca EMBER, nunca PALE). Usa só uniformes existentes do `dormant_seed`
  (sem uniform dedicado de seleção; ver pedido ao `art-director` no relatório do Loop 3).
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
`[nome, t, modo, (selecionado), (foco)]`. Loop 3: `10_forge_inspector` (t=30,5, FORGE, `layer_2`),
`11_observatory_mid` (t=37, OBSERVATORY), `12_universe_seed_focus` (t=49, UNIVERSE, seleciona e foca
`seed_aurel`).

Smoke (`--smoke-test`), depois da demo e de pausa/reinício: exercita a UI real por grupos —
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
destaque de seleção/hover das sementes (materiais próprios, transição gradual, hover 0,5, seleção 1 com
fresnel BONE, desmarcar volta ao repouso, `energy` 0 e halo BONE, nenhum destaque fora do UNIVERSE).
`tests/integration/test_interaction_flow.gd`: ações e teclas (V, H, Espaço, R, 1/2/3, Esc, F11; soltar,
eco e Ctrl não disparam), atalhos alteram `Simulation`/`Session`, `focus` emite sempre, `hud_visible`
alterna com sinal, `LineEdit`/`HSlider` em foco bloqueiam e `Button` não, `main.tscn` compõe `Shortcuts`
e a UI sobrevive a modos/seleção/foco/HUD em headless, `CAPTURES` 10–12, e o smoke de UI
(`_smoke_ui`: ausente reprova sem a flag; UI conforme de teste passa; selo oculto reprova).
`tests/unit/test_quality_profiles.gd`: perfis completos (inclui `shadow_splits`), custo monotônico,
`shadow_splits` LOW 2 e demais 4.
