# Animação e câmeras

Dono: `animator`. Responsabilidade: câmeras, animação dirigida por eventos e efeitos visuais.
Código: `src/animation/`, `src/entities/`, `src/fx/` · Testes: `tests/unit/test_animation_*.gd`.
Tempos de eventos: `src/events/origin_chamber_script.gd` (nunca duplicados aqui nem no código de
animação: tudo é ancorado nos timestamps `*_at` de `Simulation.world`).

## Princípio

O visual é **função** de `Simulation.world` + `Simulation.time`:
`p = Motion.progress(world.x_at, Simulation.time, duração)` com easing de `Tween.interpolate_value`.
Pausa congela, seek e reset reconstroem o quadro exato daquele instante — não existe estado de
animação que possa divergir da simulação. Toda regra de tempo está em `Choreography` (funções puras,
testadas); as entidades apenas empurram esses valores para nós e materiais.

- **Tempo real** só para movimento ambiente (rotação lenta do casco do núcleo, flutuação e giro dos
  fragmentos soltos, poeira) — continua na pausa — e para a câmera (Tweens de `Palette.T_CINEMATIC`).
- **Sem Tween** para progresso da simulação; **sem `TIME`** nos shaders; pulsos derivam de `Simulation.time`.
- **Sem alocação por frame** nas entidades; MultiMesh só é escrito quando o valor muda (caches de
  custom data, twist por camada e uniformes); segmentos assentados não são reescritos.

## Composição (ordem usada por `src/world/world.gd`)

Todos: `Node3D` (DustField: `GPUParticles3D`), construtor sem argumentos, filhos criados em `_ready`,
funcionam sozinhos lendo os autoloads `Simulation`, `Session`, `Quality`.

| Script | Classe | Papel |
|---|---|---|
| `src/entities/light_rig.gd` | `LightRig` | key/fill/rim direcionais + luz EMBER do núcleo; `var environment: Environment` (atribuir antes do `add_child`) recebe ambient, exposure e densidade volumétrica do estágio |
| `src/entities/chamber_architecture.gd` | `ChamberArchitecture` | piso (disco r 34 em y −3,2), 24 pilares (MultiMesh, r 24), óculo (anel escuro em y 10,5), inlay BONE no piso |
| `src/entities/origin_core.gd` | `OriginCore` | casco facetado em placas separadas (`core_shell`) + coração (`core_heart`) visível pelas frestas |
| `src/entities/fragment_structure.gd` | `FragmentStructure` | 5 MultiMesh (uma por camada, instância k = `layer_first_segment(l)+k`), nervuras (MultiMesh), guias de construção |
| `src/entities/verification_array.gd` | `VerificationArray` | anel físico estacionado abaixo da estrutura + fita PALE vertical (`scan_ring`); alimenta `scan_y`/`scan_strength` |
| `src/fx/activation_pulse.gd` | `ActivationPulse` | ondas EMBER no plano do núcleo + halo EMBER da forma final |
| `src/fx/dust_field.gd` | `DustField` | poeira fria esparsa (ambiente) |
| `src/fx/emission_sparks.gd` | `EmissionSparks` | estilhaços EMBER na emissão de fragmentos (determinístico) |
| `src/animation/camera_director.gd` | `CameraDirector` | única câmera; planos por modo, deixas por evento, input |

Lógica pura (RefCounted, testável): `Motion` (`motion.gd`: progress, eased, smooth, out, decay,
window, hash01), `Choreography` (`choreography.gd`: evento → valor visual) e `CameraShots`
(`camera_shots.gd`: planos, deixas, limites, blend).

## Mapeamento evento → visual

Durações = constantes de `Choreography` (segundos de simulação).

| Evento (`WorldState`) | Visual | Duração |
|---|---|---|
| antes de `core_activation_at` | núcleo **sem EMBER** (energy 0): silhueta só pelo contraluz frio e fresnel do casco; luz do núcleo desligada; estágio de luz `dormant` | — |
| `core.activation` | energia sobe a 0,6 com batimento (1,3 Hz); onda EMBER (r 0,7→6); estágio `active` | 2,4 (rampa), 2,2 (onda) |
| `core.online` | energia 1, respiração lenta (3,2 s); onda menor (r 0,7→3,2); surto no coração | 0,8 |
| `fragments.emitted` | 96 fragmentos saem do núcleo até a casca de dispersão (`scatter_transform`), escala 0,08→1, início escalonado; estilhaços EMBER; surto | 1,7 + até 0,6 de atraso; faíscas 1,2 |
| fragmentos soltos | flutuação/giro ambiente (tempo real) em torno do centróide, crus (INSTANCE_CUSTOM.r = 0) | contínuo |
| `structure.seeded` | guias BONE finas no raio médio de cada camada (eixo travado) | 1,2 (entra) |
| `structure.layer_added` (l) | segmentos da camada voam do scatter à pose de montagem torcida (`assembly_transform(i, t, twist=1)`), escalonados ao redor do anel; arestas EMBER (`a`) durante o voo; guia da camada some; surto no núcleo | 1,5 por segmento, espalhamento 1,1, EMBER apaga em 1,6 |
| `structure.materials_applied` | `finish` 0→1 (cinza fosco → metal escuro com hairlines) | 2,4 |
| `structure.lighting_applied` | estágio `lit` (key BONE sobe); inlay do piso sobe | 2,6 (`T_CINEMATIC`) |
| `verification.started` | anel sobe do estacionamento (y −2,6) e varre de baixo a cima e volta (±2,25, meio período 2,4 s); banda PALE na estrutura (`scan_y`, `scan_strength`); estágio `verify` | entrada 0,9 |
| `verification.check_passed` | flash PALE (`g`) que parte da altura do anel naquele instante e se propaga por camada (5 u/s) | 1,1 |
| `verification.passed` | banda apaga, anel volta ao estacionamento | 1,6 |
| `structure.finalized` | twist 1→0 (anéis travam), nervuras crescem do equador (EMBER transitório), arcos EMBER (`final_lock` até 0,7), onda EMBER larga (r 3,2→13), halo EMBER no equador, pico do coração; estágio `final` | trava 2,6; nervuras 0,4+2,4; arcos 0,9+2,2; halo 1,2+2,6 |
| `session.completed` | nada novo: a forma final respira; órbita lenta da câmera continua | — |

Testes garantem que cada passo termina antes do seguinte (fragmentos em repouso antes do `seeded`,
cada camada assentada antes da próxima e dos materiais, trava completa antes do `session.completed`)
e que todos os valores são contínuos (sem saltos entre amostras de 0,02 s).

## Estados de instância da estrutura

`INSTANCE_CUSTOM` por segmento: `r` montagem, `g` flash de verificação, `b` seleção/hover (BONE),
`a` energia de construção. Uniformes do material compartilhado `MaterialLibrary.structure()`:
`finish`, `final_lock`, `energy` (FragmentStructure) e `scan_y`, `scan_strength` (VerificationArray).
`FragmentStructure.segment_state(i)` devolve o último custom data escrito (debug/testes; o buffer da
MultiMesh não é legível no renderizador headless).

## Seleção

Cada entidade tem `StaticBody3D` filho, `collision_layer = 2`, `set_meta("entity_id", id)`:

| id | Corpo | Destaque (`Session.selected` 1,0 / `hovered` 0,5–0,55, suavizado em tempo real) |
|---|---|---|
| `origin_chamber` | cilindro fino do piso | inlay BONE do piso |
| `origin_core` | esfera r 0,63 | fresnel BONE do casco (`rim_energy`) |
| `fragment_field` | uma esfera por fragmento solto (movida só quando a pose muda; desligada quando assentado) | `b` nos fragmentos soltos (ou em todos, quando já montado) |
| `layer_0..4` | trimesh do anel da camada (centro vazado: o núcleo continua clicável); ligado só com a camada inteira assentada | `b` nas instâncias da camada |
| `verification_array` | trimesh do anel (acompanha a varredura) | emissão BONE no anel físico |

## Câmera — `CameraDirector` + `CameraShots`

Rig órbita: `target`, `yaw` (em torno de +Y a partir de +Z), `pitch` (elevação), `distance`,
`fov` (vertical) e `offset` (deslocamento do sujeito em NDC aplicado por `Camera3D.h_offset`, sem
mudar a perspectiva). Grupo `camera_director`; `camera.current = true`.

### Planos por modo

| Modo | target | yaw | pitch | dist. | fov | offset | Leitura |
|---|---|---|---|---|---|---|---|
| FORGE | (0, −0,45, 0) | 0,42 | 0,04 | 11,2 | 36 | 0 | estrutura ≈55 % da altura, núcleo levemente acima do centro, horizonte baixo |
| UNIVERSE | (0, 1, 0) | 0,62 | 0,38 | 52 | 44 | 0 | câmara como ponto quente; sementes a 18–30 u cabem ao redor |
| OBSERVATORY | (0, −0,3, 0) | −0,62 | 0,62 | 14,5 | 40 | +0,38 | alto/oblíquo; sujeito no centro dos 62 % à direita (painel à esquerda) |

### Deixas cinematográficas (FORGE com `Session.cinematic`)

| Deixa | Quando | Plano |
|---|---|---|
| `cue_dormant` | antes da ativação | plano FORGE a 10,2 |
| `cue_activation` | `core_activation_at` | aproximação: dist. 7, pitch 0,2, fov 34 |
| `cue_fragments` | `fragments_at` | recuo: dist. 15, pitch 0,2 |
| `cue_building` | `seeded_at` | órbita lenta (0,011 rad/s de simulação), dist. 12,4 |
| `cue_finishing` | `materials_at` | mesma órbita, dist. 11 |
| `cue_verification` | `verification_at` | ângulo baixo: pitch −0,1, dist. 10,4 |
| `cue_final` | `finalized_at` | órbita de revelação (0,05 rad/s), dist. 12,2 |

O yaw das deixas é função do tempo de simulação (seek dá o mesmo enquadramento). Troca de deixa,
de modo, de `cinematic` e `camera_reset` = Tween de um fator de blend (tempo real,
`Palette.T_CINEMATIC`, seno in-out) de um instantâneo para o alvo **vivo** (órbitas continuam
suaves). `Simulation.world_rebuilt` (seek/reset) → `snap_to_mode_shot()` sem tween.

### Input (`_unhandled_input`: a UI consome primeiro)

- Arrastar com botão esquerdo ou direito (após 3 px — clique simples fica para o Picker): orbita.
- Roda: zoom (×1,1 por passo). WASD (`camera_forward/back/left/right`): voa no UNIVERSE.
- `camera_reset`: volta ao plano do estado atual (com tween).
- Input suspende as deixas por 6 s (`USER_HOLD`); fora de deixa (UNIVERSE, OBSERVATORY, FORGE sem
  cinematic) o enquadramento do usuário fica até reset ou troca de modo.
- Limites (`CameraShots.clamp_shot`): pitch −0,32…1,35; distância por modo (UNIVERSE 14–140,
  FORGE 4,8–15,5, OBSERVATORY 6–30); câmera nunca abaixo de y = −3,2 + 0,45; alvo dentro de 70 u.
  Os pilares (r 24) ficam além do limite do FORGE e nunca bloqueiam a vista.

## Efeitos

- **ActivationPulse**: anel unitário escalado em XZ (fita fina radial, parede vertical 0,05), material
  `halo()` duplicado em EMBER; força `strength·(1−p)^1,5`. Halo final: anel r 3,3 no equador, 0,4.
- **EmissionSparks**: 72 estilhaços (`MeshBuilder.shard`) em MultiMesh, direções fixas por seed,
  trajetória cúbica ease-out e encolhimento — função do tempo desde `fragments_at`.
  `visible_instance_count` = 72 × `Quality.profile.particles` (mín. 8).
- **DustField**: 600 partículas, caixa 18×11×18, vida 22 s, pré-processadas; alpha 0,2 com fade de
  entrada/saída; fade por distância da câmera (2–5 u) para não virar quadrado perto da lente;
  `amount_ratio` = `Quality.profile.particles` (sem reiniciar).
- Sombras: key projeta sombras se `Quality.profile.shadows`; luz do núcleo sem sombra (fica dentro do casco).

## Luz por estágio

`Choreography.light_levels` mistura `EnvironmentProfile.LIGHT` em sequência
(dormant → active em `core_activation_at` → lit em `lighting_at` → verify em `verification_at` →
final em `finalized_at`), cada passo em `T_CINEMATIC`, partindo do nível corrente (contínuo).
Cada luz recebe `EnvironmentProfile.FOG_LIGHT` em `light_volumetric_fog_energy`. Direções: key alta
pela frente-esquerda, fill baixa e fria pela frente-direita, rim a ~40° por trás (o reflexo do rim
no piso fica fora de quadro). Luz do núcleo: alcance 8 (ilumina faces internas dos anéis),
modulada pelo pulso (0,82 + 0,3·pulso).

## Custo

Headless (sem render), todos os módulos ativos: ~1–2 ms de `_process` por frame em qualquer fase.
No lavapipe (CPU, 1600×900) o custo é de renderização: LOW ≈ 5 fps com tudo × ≈ 7 fps com a cena
vazia; HIGH ≈ 2,5 fps.

## Verificação

`tools/run_tests.sh`: `test_animation_motion.gd`, `test_animation_choreography.gd`,
`test_animation_camera_shots.gd`, `test_animation_entities.gd` (composição headless na ordem do
world.gd, corpos de seleção, câmera, seek, luz → ambiente, varredura → material, seleção, input).
Capturas das fases: cena de prova fora do repositório (Loop 2) e `tools/capture_evidence.sh` quando o
`world.gd` compuser os módulos.
