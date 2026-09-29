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
  `RING_WIDTH`); materiais `MaterialLibrary.dormant_seed()` (compartilhado) e uma cópia de `halo()`
  (BONE, `HALO_STRENGTH` 0,18; sem energia, sem EMBER). Cada semente
  tem um `StaticBody3D` (`collision_layer = 2`, máscara 0, `meta entity_id`) com esfera de colisão
  generosa (`PICK_RADIUS_SCALE`).
- **Deriva**: oscilação lenta (período ~46 s, ±0,35 un.) e giro lento, em tempo real. É respiração
  ambiente, não estado de simulação: não depende de `Simulation.time` e não precisa de seek.
- API: `seed_ids()`, `seed_node(id)`, `seed_base_position(s)`, `drift_offset(t, phase)`,
  `make_sky_material()`, `apply_sky(env)`, `apply_mode(mode)`, `star_intensity_for(mode)`, `sky_material`.

## Seleção (`src/world/picker.gd`, `class_name Picker`)

- Raio da câmera ativa (`get_viewport().get_camera_3d()`) contra a camada de colisão 2; o id vem do
  meta `entity_id` do colisor (ou do pai). Consulta física em `_physics_process`.
- Clique × arrasto: limiar único em `src/core/input_tuning.gd` (`InputTuning.DRAG_THRESHOLD_PX` = 4,
  `InputTuning.is_drag(travel)`), compartilhado com a câmera. Conta o **percurso acumulado** do
  ponteiro entre press e release (soma de cada movimento), não o deslocamento líquido: um arrasto
  de ida e volta (160 px) que termina onde começou continua sendo arrasto e não seleciona; 3 px
  seleciona. Clique no vazio → `Session.select(&"")`. Ação `deselect` (Esc) limpa.
- Movimento do mouse → `Session.hover(id)` (congelado durante arrasto).
- Usa `_unhandled_input`: eventos consumidos pela UI não chegam; o Picker nunca marca eventos como
  tratados, para a câmera receber os mesmos arrastos.
- Contrato para quem é selecionável: `StaticBody3D` com `collision_layer = 2` e
  `set_meta("entity_id", StringName)` (ids de `EntityCatalog`).
- API: `pick_at(screen_pos)`, `pick_ray(from, to)`, `path_length(points)`, `is_click_path(points)`,
  `entity_id_of_hit(hit)`, `entity_id_of(collider)`.

## Automação

`src/core/automation.gd` (capturas): depois de `Session.set_mode` + `Simulation.seek`, chama
`snap_to_mode_shot()` em todos os nós do grupo `camera_director` antes de esperar o assentamento.

## Testes

`tests/integration/test_world_composition.gd`: ambiente e céu instalados, esqueleto do Loop 1
removido, módulo ausente pulado, ordem dos módulos presentes, relatório de módulos coerente com os
scripts, sempre há câmera ativa, qualidade liga/desliga SSAO/SSIL/volumétrica, modo altera a névoa
e o brilho das estrelas, uniform `radiance_lift` presente, 3 sementes com colisores/metas/distância
60–72 e fora do piso, anéis nunca verticais, deriva limitada, lógica de clique (limiar, percurso
acumulado), raycast e clique/arrasto/ida-e-volta/vazio/Esc via `_unhandled_input`.
`tests/unit/test_quality_profiles.gd`: perfis completos (inclui `shadow_splits`), custo monotônico,
`shadow_splits` LOW 2 e demais 4.
