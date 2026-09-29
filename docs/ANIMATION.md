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
- **Sem alocação por frame** nas entidades; MultiMesh e `Environment` só são escritos quando o valor
  muda (caches de custom data, twist por camada, uniformes e níveis de ambiente); segmentos
  assentados não são reescritos.

## Fonte dos números

Este documento descreve **intenção e regras**; todo valor numérico (durações, níveis, planos,
limites, quantidades) vive como constante nomeada no código, e só lá:
`Choreography` (tempos e níveis de cada reação), `CameraShots` (planos, deixas, limites),
`CameraDirector` (input), `LightRig` (luz do núcleo, sombra da key), `DustField`, `EmissionSparks`,
`VerificationArray`, `ChamberArchitecture`, `InputTuning` (limiar clique × arrasto, do
`game-engineer`) e `EnvironmentProfile` (níveis de luz por estágio e `exposure_scale` por modo, do
`art-director`).

## Composição (ordem usada por `src/world/world.gd`)

Todos: `Node3D` (DustField: `GPUParticles3D`), construtor sem argumentos, filhos criados em `_ready`,
funcionam sozinhos lendo os autoloads `Simulation`, `Session`, `Quality`.

| Script | Classe | Papel |
|---|---|---|
| `src/entities/light_rig.gd` | `LightRig` | key/fill/rim direcionais + luz EMBER do núcleo; `var environment: Environment` (atribuir antes do `add_child`) recebe ambient, exposure (× `exposure_scale` do modo) e densidade volumétrica do estágio |
| `src/entities/chamber_architecture.gd` | `ChamberArchitecture` | piso escuro, anel de pilares (MultiMesh), óculo (anel escuro alto), inlay BONE no piso |
| `src/entities/origin_core.gd` | `OriginCore` | casco facetado em placas separadas (`core_shell`) + coração (`core_heart`) visível pelas frestas |
| `src/entities/fragment_structure.gd` | `FragmentStructure` | uma MultiMesh por camada (instância k = `layer_first_segment(l)+k`), nervuras (MultiMesh), guias de construção |
| `src/entities/verification_array.gd` | `VerificationArray` | anel físico estacionado abaixo da estrutura + fita PALE vertical (`scan_ring`); alimenta `scan_y`/`scan_strength` |
| `src/fx/activation_pulse.gd` | `ActivationPulse` | ondas EMBER no plano do núcleo + halo EMBER da forma final |
| `src/fx/dust_field.gd` | `DustField` | poeira fria esparsa, redonda e discreta (ambiente) |
| `src/fx/emission_sparks.gd` | `EmissionSparks` | estilhaços EMBER na emissão de fragmentos (determinístico) |
| `src/animation/camera_director.gd` | `CameraDirector` | única câmera; planos por modo, deixas por evento, input |

Lógica pura (RefCounted, testável): `Motion` (`motion.gd`: progress, eased, smooth, out, decay,
window, hash01), `Choreography` (`choreography.gd`: evento → valor visual) e `CameraShots`
(`camera_shots.gd`: planos, deixas, limites, blend).

## Mapeamento evento → visual

Entre parênteses, as constantes de `Choreography` (segundos de simulação / níveis) que regem cada passo.

- **Antes de `core_activation_at`** — núcleo sem EMBER: silhueta só pelo contraluz frio e fresnel
  do casco; luz do núcleo desligada; estágio de luz `dormant`.
- **`core.activation`** — energia sobe com batimento (`CORE_WAKE*`, `CORE_FLICKER_HZ`); onda EMBER
  larga (`WAVE_ACTIVATION`); estágio `active`.
- **`core.online`** — energia plena, respiração lenta (`CORE_BREATH`); onda menor (`WAVE_ONLINE`);
  surto no coração (`CORE_SURGE`).
- **`fragments.emitted`** — os fragmentos saem do núcleo até a casca de dispersão
  (`scatter_transform`), crescendo, com início escalonado (`EMIT_*`); estilhaços EMBER
  (`SPARK_DUR`); surto. Soltos, flutuam e giram em tempo real, crus (`INSTANCE_CUSTOM.r = 0`).
- **`structure.seeded`** — guias BONE finas no raio médio de cada camada, eixo travado (`GUIDE_*`).
- **`structure.layer_added` (l)** — os segmentos da camada voam do scatter à pose de montagem
  torcida, escalonados ao redor do anel (`ASSEMBLE_*`); arestas EMBER durante o voo (`BUILD_*`);
  a guia da camada some; surto no núcleo.
- **`structure.materials_applied`** — `finish` 0→1: cinza fosco → metal escuro (`FINISH_DUR`).
- **`structure.lighting_applied`** — estágio `lit` (key BONE sobe); inlay do piso sobe.
- **`verification.started`** — o anel sobe do estacionamento e varre de baixo a cima e volta
  (`SCAN_*`), com a fita PALE contida (`VerificationArray.BAND_LEVEL`, `BAND_WIDTH`: linha de
  varredura calma, sem florescer) e a banda na estrutura (`scan_y`, `scan_strength`); estágio `verify`.
- **`verification.check_passed`** — flash PALE (`g`) que parte da altura do anel naquele instante e
  se propaga por camada (`FLASH_*`).
- **`verification.passed`** — a banda apaga e o anel volta ao estacionamento (`SCAN_EXIT`).
- **`structure.finalized`** — twist 1→0, anéis travam (`LOCK_DUR`); nervuras crescem do equador
  (`RIB_*`); arcos EMBER na parede externa (`ARC_*`, `FINAL_LOCK_LEVEL`); onda EMBER larga
  (`WAVE_FINAL`); halo EMBER no equador (`FINAL_HALO_*`); pico do coração; estágio `final`.
- **`session.completed`** — nada novo: a forma final respira; a órbita lenta da câmera continua.

Testes garantem que cada passo termina antes do seguinte (fragmentos em repouso antes do `seeded`,
cada camada assentada antes da próxima e dos materiais, trava completa antes do `session.completed`)
e que todos os valores são contínuos (sem saltos entre amostras de 0,02 s).

## Estados de instância da estrutura

`INSTANCE_CUSTOM` por segmento: `r` montagem, `g` flash de verificação, `b` seleção/hover (BONE),
`a` energia de construção. Uniformes do material compartilhado `MaterialLibrary.structure()`:
`finish`, `final_lock`, `energy` (FragmentStructure) e `scan_y`, `scan_strength` (VerificationArray).
O custom data é calculado para todo (world, time) — inclusive antes de `FRAGMENTS_EMITTED` (tudo
zero, camadas ocultas) — e escrito só quando muda. `FragmentStructure.segment_state(i)` devolve esse
valor (debug/testes; o buffer da MultiMesh não é legível no renderizador headless).

## Seleção

Cada entidade tem `StaticBody3D` filho, `collision_layer = 2`, `set_meta("entity_id", id)`.
Destaque: forte em `Session.selected`, meio em `hovered`, suavizado em tempo real.

| id | Corpo | Destaque |
|---|---|---|
| `origin_chamber` | caixas dos pilares + anel do óculo. **O piso não é selecionável**: ele está sob toda vista do FORGE, então clique no vazio não acerta nada e limpa a seleção | inlay BONE do piso |
| `origin_core` | esfera do núcleo | fresnel BONE do casco (`rim_energy`) |
| `fragment_field` | uma esfera por fragmento solto (movida só quando a pose muda; desligada quando assentado) | `b` nos fragmentos soltos (ou em todos, quando já montado) |
| `layer_0..4` | trimesh do anel da camada (centro vazado: o núcleo continua clicável); ligado só com a camada inteira assentada | `b` nas instâncias da camada |
| `verification_array` | trimesh do anel (acompanha a varredura) | emissão BONE no anel físico |

## Câmera — `CameraDirector` + `CameraShots`

Rig órbita: `target`, `yaw` (em torno de +Y a partir de +Z), `pitch` (elevação), `distance`,
`fov` (vertical) e `offset` (deslocamento do sujeito em NDC aplicado por `Camera3D.h_offset`, sem
mudar a perspectiva). Grupo `camera_director`; `camera.current = true`.

### Planos por modo (`CameraShots.mode_shot`)

- **FORGE** — três-quartos leve (`FORGE_YAW`); estrutura ≈55 % da altura, núcleo levemente acima do
  centro óptico, horizonte baixo.
- **UNIVERSE** (`UNIVERSE_*`) — de fora do anel de pilares, com o yaw exatamente num vão entre dois
  pilares, de frente para as três sementes (`Universe.SEEDS`, além da câmara): a câmara é o ponto
  quente no meio-baixo do quadro e as sementes se abrem à esquerda, ao alto e à direita. Pitch alto
  o bastante para que o topo dos pilares da frente fique abaixo da estrutura na tela (nenhum pilar
  corta o quadro nem o sujeito). Exposição do modo: `exposure_scale` de `EnvironmentProfile.mode_fog`,
  aplicada pelo `LightRig`.
- **OBSERVATORY** — alto e oblíquo; sujeito no centro dos 62 % à direita (painel à esquerda).

`test_animation_camera_shots.gd` fixa essas leituras: planos dentro dos limites, yaw do UNIVERSE entre
pilares, sementes dentro do quadro, acima da câmara e dos dois lados dela, pilares da frente abaixo
da estrutura.

### Deixas cinematográficas (FORGE com `Session.cinematic`)

`cue_dormant` (plano FORGE um pouco mais perto) → `cue_activation` (aproximação) → `cue_fragments`
(recuo) → `cue_building` (órbita lenta, `BUILD_ORBIT`) → `cue_finishing` (mesma órbita, mais perto)
→ `cue_verification` (ângulo baixo) → `cue_final` (órbita de revelação, `FINAL_ORBIT`).
O yaw das deixas é função do tempo de simulação (seek dá o mesmo enquadramento). Troca de deixa,
de modo, de `cinematic` e `camera_reset` = Tween de um fator de blend (tempo real,
`Palette.T_CINEMATIC`, seno in-out) de um instantâneo para o alvo **vivo** (órbitas continuam
suaves). `Simulation.world_rebuilt` (seek/reset) → `snap_to_mode_shot()` sem tween.

### Input (`_unhandled_input`: a UI consome primeiro)

- Arrastar com botão esquerdo ou direito orbita **só depois** que o percurso acumulado do press é
  arrasto para `InputTuning.is_drag` — o mesmo limiar (`InputTuning.DRAG_THRESHOLD_PX`) do Picker;
  um press é clique **ou** órbita, nunca os dois. Ida-e-volta conta percurso.
- Roda: zoom (`ZOOM_STEP`). WASD (`camera_forward/back/left/right`): voa no UNIVERSE.
- `camera_reset`: volta ao plano do estado atual (com tween).
- Input suspende as deixas por `USER_HOLD`; fora de deixa (UNIVERSE, OBSERVATORY, FORGE sem
  cinematic) o enquadramento do usuário fica até reset ou troca de modo.
- Limites (`CameraShots.clamp_shot`): pitch, distância por modo (`DISTANCE_LIMITS`), câmera sempre
  acima do piso (`FLOOR_Y + FLOOR_CLEARANCE`), alvo dentro de `FLY_RADIUS`. Os pilares ficam além do
  limite do FORGE e nunca bloqueiam a vista.

## Efeitos

- **ActivationPulse**: anel unitário escalado em XZ (fita fina radial), material `halo()` duplicado
  em EMBER; força decai com o progresso. Halo final no equador.
- **EmissionSparks**: estilhaços (`MeshBuilder.shard`) em MultiMesh com `MaterialLibrary.spark(EMBER)`,
  direções fixas por seed, trajetória cúbica ease-out e encolhimento — função do tempo desde
  `fragments_at`. `visible_instance_count` escala com `Quality.profile.particles` (com mínimo).
- **DustField**: discos redondos e suaves (`MaterialLibrary.mote(ASH)`), poucos, minúsculos e de
  alfa baixo — textura do ar, nunca padrão. Fade de entrada/saída na vida; `near_fade` apaga os que
  passam perto da lente; `amount_ratio` = `Quality.profile.particles` (sem reiniciar).
- Sombras: a key projeta sombras se `Quality.profile.shadows`, com os splits de
  `Quality.profile.shadow_splits` (`LightRig.shadow_mode_for`) e normal bias/blur de `LightRig`;
  luz do núcleo sem sombra (fica dentro do casco).

## Luz por estágio

`Choreography.light_levels` mistura `EnvironmentProfile.LIGHT` em sequência
(dormant → active em `core_activation_at` → lit em `lighting_at` → verify em `verification_at` →
final em `finalized_at`), cada passo em `T_CINEMATIC`, partindo do nível corrente (contínuo).
Cada luz recebe `EnvironmentProfile.FOG_LIGHT` em `light_volumetric_fog_energy`. Direções: key alta
pela frente-esquerda, fill baixa e fria pela frente-direita, rim alta por trás (o reflexo do rim
no piso fica fora de quadro). Luz do núcleo (`LightRig.CORE_*`): ilumina as faces internas dos anéis
e cai antes das paredes externas; especular baixo (sem ponto quente no metal); modulada pelo pulso.
O `LightRig` só escreve no `Environment` quando ambient/exposure/fog mudam e lê o `exposure_scale`
do modo na troca de modo (não por frame).

## Custo

Headless (sem render), todos os módulos ativos: ~1–2 ms de `_process` por frame em qualquer fase.
No lavapipe (CPU, 1600×900) o custo é de renderização: LOW ≈ 5 fps com tudo × ≈ 7 fps com a cena
vazia; HIGH ≈ 2,5 fps.

## Verificação

`tools/run_tests.sh`: `test_animation_motion.gd`, `test_animation_choreography.gd`,
`test_animation_camera_shots.gd` (planos, deixas, limites, UNIVERSE entre pilares com as sementes em
quadro), `test_animation_entities.gd` (composição headless na ordem do world.gd, corpos de seleção e
piso não selecionável, câmera e limiar de arrasto compartilhado, seek, `segment_state` antes da
emissão, luz → ambiente com `exposure_scale` e cache, splits por qualidade, varredura → material,
seleção, input). Capturas de todas as fases e modos: `tools/capture_evidence.sh`.
