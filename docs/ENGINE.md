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

## Qualidade e modo aplicados ao ambiente

- `Quality.profile_changed` → `EnvironmentProfile.apply_quality(env, profile)` (SSAO, SSIL, glow,
  volumétrica; sem volumétrica a névoa de profundidade começa mais perto). Aplicado também no
  `_ready` com `Quality.profile`.
- `Session.mode_changed` → `EnvironmentProfile.apply_mode_fog(env, mode)` (FORGE fechado, UNIVERSE
  vê longe, OBSERVATORY recua). Aplicado também no `_ready` com `Session.mode`.
- O resto do custo (viewport: escala, MSAA, FXAA, atlas de sombras) é do autoload `Quality`;
  partículas e luzes aplicam a parte delas no mesmo sinal.

## Universo (`src/world/universe.gd`, `class_name Universe`)

- **Céu**: `Sky` com `ShaderMaterial` de `src/world/universe_sky.gdshader` (`shader_type sky`),
  instalado por `Universe.apply_sky(env)` (`background_mode = BG_SKY`). O fundo continua VOID;
  por cima, estrelas esparsas e frias (duas camadas numa grade de faces de cubo, tamanho em pixels
  de tela a partir de `fwidth(EYEDIR)`, sem costuras) e uma faixa de poeira distante quase
  invisível (grande círculo, ruído de baixa frequência). Cores só de `Palette` (VOID, ASH, BONE).
  Sem `TIME`: o céu é estático. `render_mode disable_fog` (a névoa de profundidade cobriria o céu);
  o passe de cubemap (reflexos) devolve VOID puro; `radiance_size` 64. A luz ambiente continua
  vindo da cor (`AMBIENT_SOURCE_COLOR`), então o céu não muda a iluminação.
  O shader está em `src/world/` por ser do universo; a revisão estética é do `art-director`.
- **Sementes dormentes**: `seed_aurel` (orbe facetado + anel), `seed_vesper` (fuso + dois anéis),
  `seed_lattice` (icosaedro + anéis cruzados), a 21–26 unidades do centro (`SEEDS`, coordenadas
  cilíndricas). Malhas de `MeshBuilder.icosphere`/`ring`; materiais `MaterialLibrary.dormant_seed()`
  (compartilhado) e uma cópia de `halo()` (BONE, força baixa; sem energia, sem EMBER). Cada semente
  tem um `StaticBody3D` (`collision_layer = 2`, máscara 0, `meta entity_id`) com esfera de colisão
  generosa (`PICK_RADIUS_SCALE`).
- **Deriva**: oscilação lenta (período ~46 s, ±0,35 un.) e giro lento, em tempo real. É respiração
  ambiente, não estado de simulação: não depende de `Simulation.time` e não precisa de seek.
- API: `seed_ids()`, `seed_node(id)`, `seed_base_position(s)`, `drift_offset(t, phase)`,
  `make_sky_material()`, `apply_sky(env)`, `sky_material`.

## Seleção (`src/world/picker.gd`, `class_name Picker`)

- Raio da câmera ativa (`get_viewport().get_camera_3d()`) contra a camada de colisão 2; o id vem do
  meta `entity_id` do colisor (ou do pai). Consulta física em `_physics_process`.
- Clique esquerdo = press + release a menos de 6 px (`CLICK_MAX_DISTANCE`); acima disso é arrasto de
  órbita e não seleciona. Clique no vazio → `Session.select(&"")`. Ação `deselect` (Esc) limpa.
- Movimento do mouse → `Session.hover(id)` (congelado durante arrasto).
- Usa `_unhandled_input`: eventos consumidos pela UI não chegam; o Picker nunca marca eventos como
  tratados, para a câmera receber os mesmos arrastos.
- Contrato para quem é selecionável: `StaticBody3D` com `collision_layer = 2` e
  `set_meta("entity_id", StringName)` (ids de `EntityCatalog`).
- API: `pick_at(screen_pos)`, `pick_ray(from, to)`, `is_click(press, release)`,
  `entity_id_of_hit(hit)`, `entity_id_of(collider)`.

## Automação

`src/core/automation.gd` (capturas): depois de `Session.set_mode` + `Simulation.seek`, chama
`snap_to_mode_shot()` em todos os nós do grupo `camera_director` antes de esperar o assentamento.

## Testes

`tests/integration/test_world_composition.gd`: ambiente e céu instalados, esqueleto do Loop 1
removido, módulo ausente pulado, ordem dos módulos presentes, sempre há câmera ativa, qualidade
liga/desliga SSAO/SSIL/volumétrica, modo altera a névoa, 3 sementes com colisores/metas/distância,
deriva limitada, lógica de clique, raycast e clique/arrasto/vazio/Esc via `_unhandled_input`.
