# Animação e câmeras

Dono: `animator`. Responsabilidade: câmeras, animação dirigida por eventos e efeitos visuais.
Código: `src/animation/`, `src/entities/`, `src/fx/` · Testes: `tests/unit/test_animation_*.gd`.
Tempos de eventos: `src/events/origin_chamber_script.gd` (nunca duplicados aqui nem no código de
animação: tudo é ancorado nos timestamps `*_at` de `Simulation.world`).
Dois cenários: **ORIGIN CHAMBER** (seções abaixo, v1) e **GENESIS** (seção "GENESIS" no fim;
tempos em `src/events/genesis_script.gd`, estado em `Simulation.genesis`).

## Princípio

O visual é **função** de `Simulation.world` + `Simulation.time`:
`p = Motion.progress(world.x_at, Simulation.time, duração)` com easing de `Tween.interpolate_value`.
Pausa congela, seek e reset reconstroem o quadro exato daquele instante — não existe estado de
animação que possa divergir da simulação. Toda regra de tempo está em `Choreography` (funções puras,
testadas); as entidades apenas empurram esses valores para nós e materiais.

- **Tempo real** só para movimento ambiente (rotação lenta do casco do núcleo, flutuação e giro dos
  fragmentos soltos, poeira) — continua na pausa — e para a câmera (transições de `Palette.T_CINEMATIC`
  com a curva de `Tween.interpolate_value` no relógio de parede — ver "Transições" abaixo). Esse
  "tempo real" vem sempre de `MotionClock.now()` (ver "Relógio de movimento").
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
| `src/entities/chamber_architecture.gd` | `ChamberArchitecture` | piso escuro, anel de pilares (MultiMesh), óculo (anel escuro alto; oculto no UNIVERSE), inlay BONE no piso |
| `src/entities/origin_core.gd` | `OriginCore` | casco facetado em placas separadas (`core_shell`) + coração (`core_heart`) visível pelas frestas |
| `src/entities/fragment_structure.gd` | `FragmentStructure` | uma MultiMesh por camada (instância k = `layer_first_segment(l)+k`), nervuras (MultiMesh), guias de construção |
| `src/entities/verification_array.gd` | `VerificationArray` | anel físico estacionado abaixo da estrutura + fita PALE vertical (`scan_ring`) apoiada sobre ele (`BAND_LIFT`); alimenta `scan_y`/`scan_strength` |
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
  A fita fica **sobre** a borda superior do anel físico (`BAND_LIFT`; centro da fita = `scan_y`):
  coplanares, o anel opaco escondia o meio da fita no lado próximo e sobravam duas lascas
  subpixel que liam como fio pontilhado. A fita é uma parede cilíndrica de espessura radial zero
  (`BAND_THICKNESS`): com espessura, as tampas (0,012 de largura, com o próprio falloff no meio)
  rasterizavam como um fio pontilhado subpixel nas bordas da fita, separado dela pelo falloff —
  pior no LOW, sem MSAA. Sem espessura as tampas não têm área; as paredes interna e externa
  coincidem e somam como antes (aditivo, sem culling), então o nível da fita não muda.
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
  quente perto do centro do quadro e as sementes se abrem à esquerda, ao alto e à direita. As três
  sementes (corpo, anéis de halo e deriva) ficam **na parte do quadro que o HUD deixa livre**
  (`universe_free_rect`: à direita do painel SITES, abaixo da barra de modos, acima do transporte e
  à esquerda da coluna do inspector/feed) em 1600×900 e em 1280×720 — o HUD tem tamanhos fixos em
  pixels, então 1280×720 é o quadro mais apertado. As sementes cobrem ~110° do lado de lá da câmara;
  caber nessa faixa pede lente mais aberta e câmera mais longe (`UNIVERSE_FOV`, `UNIVERSE_DISTANCE`)
  e um `UNIVERSE_OFFSET` que centra o leque na área livre. Custo: a câmara lê menor que no Loop 3
  inicial (raio ≈ 30 px em 1600×900), ainda legível como estrutura com o anel de pilares. Pitch
  alto o bastante para que o topo dos pilares da frente fique abaixo da estrutura na tela (nenhum
  pilar corta o quadro nem o sujeito). O óculo, que nesse plano lia como um anel solto sobre a
  câmara, fica oculto no UNIVERSE (malha e forma de seleção; `ChamberArchitecture.apply_mode`).
  Exposição do modo: `exposure_scale` de `EnvironmentProfile.mode_fog`, aplicada pelo `LightRig`.
- **OBSERVATORY** (`OBSERVATORY_*`) — três-quartos elevado, mais baixo que antes (as paredes
  externas, o mesmo metal lido no FORGE, pesam mais que as tampas dos anéis); sujeito no centro dos
  62 % à direita (a folha nativa ocupa `OBSERVATORY_SHEET` = 38 % à esquerda).
- **Foco numa semente** usa lente própria (`SEED_FOCUS_FOV`): a lente aberta do UNIVERSE poria a
  câmara atrás da semente; o voo até a semente fecha a lente no caminho.

`test_animation_camera_shots.gd` fixa essas leituras: planos dentro dos limites, yaw do UNIVERSE entre
pilares, sementes dentro do quadro, acima da câmara e dos dois lados dela, pilares da frente abaixo
da estrutura; sementes e câmara dentro da área livre do HUD em 1600×900 e 1280×720 (projeção com a
câmera como o `Camera3D` a renderiza, `h_offset` incluído); sujeito do OBSERVATORY inteiro na área
à direita da folha.

### Deixas cinematográficas (FORGE com `Session.cinematic`)

`cue_dormant` (plano FORGE um pouco mais perto) → `cue_activation` (aproximação) → `cue_fragments`
(recuo) → `cue_building` (órbita lenta, `BUILD_ORBIT`) → `cue_finishing` (mesma órbita, mais perto)
→ `cue_verification` (ângulo baixo) → `cue_final` (órbita de revelação, `FINAL_ORBIT`).
O yaw das deixas é função do tempo de simulação (seek dá o mesmo enquadramento). Troca de deixa,
de modo, de `cinematic` e `camera_reset` = transição de um fator de blend (tempo real,
`Palette.T_CINEMATIC`, seno in-out) de um instantâneo para o alvo **vivo** (órbitas continuam
suaves). `Simulation.world_rebuilt` (seek/reset) → `snap_to_mode_shot()` sem tween — exceto quando
um enquadramento do usuário/foco está valendo fora de deixa (UNIVERSE, OBSERVATORY, FORGE sem
cinematic): aí ele fica (arrastar a linha do tempo não joga fora o foco numa semente).

### Transições

Todo rig passa por `CameraShots.clamp_rig` **depois** do blend, antes de chegar à câmera
(`CameraDirector._apply`): pitch no intervalo, alvo dentro de `FLY_RADIUS` e acima do piso, câmera
a `FLOOR_CLEARANCE` acima do piso. Um blend de dois planos válidos não é válido por construção
(pitch, distância e alvo interpolam separados: um plano baixo e perto indo para um longe com alvo
baixo atravessa o piso no meio). `clamp_rig` não mexe na distância (os limites por modo ficam em
`clamp_shot`), então uma transição entre modos mantém a curva de distância.

O fator de blend segue a curva de um Tween (`Tween.interpolate_value`, `TRANS_SINE`/`EASE_IN_OUT`)
com o tempo medido no relógio de parede (`MotionClock.now()`), não no delta do quadro: o motor
limita o delta de um quadro a `max_physics_steps_per_frame / physics_ticks_per_second` (8/60 s), e
num renderizador lento (lavapipe ≈ 0,4 s por quadro) um Tween por delta corria ~3× mais devagar
que o tempo real — um foco não assentava no tempo prometido. Em máquinas normais o resultado é
idêntico ao de um Tween.

### Relógio de movimento — `MotionClock` (`src/animation/motion_clock.gd`)

Fonte única do tempo real da animação: `CameraDirector._now()` (blends) e o movimento ambiente de
`OriginCore` (giro do casco e do coração, flutuação) e `FragmentStructure` (flutuação e giro dos
fragmentos soltos) leem `MotionClock.now()` (segundos). Nada mais de animação lê `Time` direto.

- **Jogo normal**: relógio de parede (`Time.get_ticks_msec`). A ADR-011 continua valendo como está:
  fora do Movie Maker o blend dura `T_CINEMATIC` de parede em qualquer máquina.
- **Movie Maker** (`--write-movie`, `Engine.get_write_movie_path() != ""`): cada quadro leva ~0,4 s
  para renderizar e representa 1/fps s do vídeo, então o relógio de parede faria as transições
  saírem quase instantâneas e o movimento ambiente acelerado ~12×. Aqui o relógio é o **tempo de jogo
  acumulado** dos quadros: `delta` de processo (fixo, 1/`--fixed-fps`) × quadros decorridos
  (`Engine.get_process_frames()`), somado uma vez por quadro — várias leituras no mesmo quadro dão o
  mesmo valor; quadros sem leitura também contam; nunca volta. O relógio começa em 0 no quadro 0.
- O passo de acumulação é a função pura `MotionClock.accumulate(game_time, last_frame, frame, delta)`,
  testada sem gravar (`test_animation_motion_clock.gd`).
- O progresso da simulação continua em `Simulation.time`; o `MotionClock` só rege câmera e ambiente.

### Foco numa entidade (`Session.focus_requested(id)`)

- **Alvo**: nós do grupo `SessionState.entity_group(id)`. Limites = AABB local em
  `set_meta(CameraDirector.FOCUS_BOUNDS_META, aabb)` quando o nó a define, senão a união das AABBs
  dos `VisualInstance3D` descendentes (caso das sementes do `Universe`).

  | id | Nó do grupo | Limites |
  |---|---|---|
  | `origin_core` | `OriginCore` | esfera do casco |
  | `layer_0..4` | `MultiMeshInstance3D` da camada | o anel da camada (raio externo, altura, `y`) |
  | `fragment_field` | `FragmentStructure` | casca de dispersão (contém também a estrutura montada) |
  | `verification_array` | anel físico (`VerificationArray.ring`) | anel + fita, na altura do anel no pedido |
  | `origin_chamber` | `ChamberArchitecture` | anel de pilares, do piso ao topo |
  | `seed_*` | raiz da semente (`Universe`, do game-engineer) | união das malhas |

- **Enquadramento** (`CameraShots.focus_shot`, lógica pura): alvo = centro dos limites; mantém o
  modo (fov e `offset` do plano do modo, limites de `clamp_shot`) e o yaw atual (a câmera vai até a
  entidade em vez de girar em volta dela). A distância (`fit_distance`) trata a entidade como
  cilindro vertical (raio = metade do lado horizontal maior, sem inflar anéis pelos cantos da AABB)
  e, com perspectiva, faz a borda próxima ocupar no máximo `FOCUS_FILL` da meia-altura e da
  meia-largura úteis (descontado o `offset`). FORGE olha de cima ao menos `FOCUS_MIN_PITCH` (anel lê
  como anel); OBSERVATORY mantém pitch alto e o sujeito à direita do painel.
- **Alcance** (`FOCUS_REACH`): em FORGE/OBSERVATORY o alvo precisa estar na câmara (a distância
  fica no limite do modo); um pedido fora do alcance (semente vista do FORGE) é ignorado. No
  UNIVERSE o alcance vai até as sementes (`FLY_RADIUS`, com folga para a deriva).
- **Sementes** (UNIVERSE, alvo além de `FOCUS_FAR`): vistas de fora, `SEED_FOCUS_YAW` fora da linha
  radial, `SEED_FOCUS_OFFSET` na tela e `SEED_FOCUS_PITCH`: a semente no terço esquerdo, a câmara
  acesa ao fundo no terço direito — a semente dormente lida contra o lugar onde os constructos nascem.
- **Comportamento**: transição `T_CINEMATIC` do rig atual ao alvo do foco. O foco conta como input
  do usuário: a deixa só retoma `USER_HOLD` s depois de o enquadramento assentar; fora de deixa o
  foco fica até `camera_reset`, troca de modo ou novo input (que para a transição onde está e passa
  o controle ao usuário). Pedido repetido reenquadra. `focused()` / `focus_goal()` para testes/HUD.
- A captura `12_universe_seed_focus` (automação) pede o foco e espera 3,6 s: a transição (2,6 s de
  relógio) assenta antes.

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
- **DustField**: discos redondos e suaves (`MaterialLibrary.mote(BONE)`), poucos e de alfa baixo —
  textura do ar, nunca padrão. Precisam ler como poeira e não como estrela: as estrelas são pontos
  nítidos ASH; os motes são discos maiores e macios (`MOTE_SIZE`), de tom BONE (partículas fora de
  foco pegando a luz da câmara). Fade de entrada/saída na vida; `near_fade` apaga os que passam
  perto da lente; `amount_ratio` = `Quality.profile.particles` (sem reiniciar).
- Sombras: a key projeta sombras se `Quality.profile.shadows`, com os splits de
  `Quality.profile.shadow_splits` (`LightRig.shadow_mode_for`) e normal bias/blur de `LightRig`;
  com 2 splits (LOW) o alcance é menor e o blur maior (`LightRig.shadow_reach_for`,
  `KEY_SHADOW_*_2_SPLITS`): em 40 unidades os texels das 2 cascatas desenhavam manchas em degrau
  no topo dos anéis (OBSERVATORY); a câmara vista do FORGE e do OBSERVATORY fica dentro do alcance
  curto. Luz do núcleo sem sombra (fica dentro do casco).

## Luz por estágio

`Choreography.light_levels` mistura `EnvironmentProfile.LIGHT` em sequência
(dormant → active em `core_activation_at` → lit em `lighting_at` → verify em `verification_at` →
final em `finalized_at`), cada passo em `T_CINEMATIC`, partindo do nível corrente (contínuo).
Cada luz recebe `EnvironmentProfile.FOG_LIGHT` em `light_volumetric_fog_energy`. Direções: key alta
pela frente-esquerda, fill baixa e fria pela frente-direita, rim alta por trás (o reflexo do rim
no piso fica fora de quadro). Luz do núcleo (`LightRig.CORE_*`): ilumina as faces internas dos anéis
e cai antes das paredes externas; especular baixo (`CORE_SPECULAR`: o reflexo cobre num único
segmento lia como seleção — agora é um brilho quente e macio espalhado pelo anel sob o núcleo);
modulada pelo pulso. O `LightRig` só escreve no `Environment` quando ambient/exposure/fog mudam, lê
o `exposure_scale` do modo na troca de modo (não por frame) e esquece o cache em
`Simulation.world_rebuilt` (o quadro seguinte reescreve o ambiente).

## Custo

Headless (sem render), todos os módulos ativos: ~1–2 ms de `_process` por frame em qualquer fase.
No lavapipe (CPU, 1600×900) o custo é de renderização: LOW ≈ 5 fps com tudo × ≈ 7 fps com a cena
vazia; HIGH ≈ 2,5 fps.

## Verificação

`tools/run_tests.sh`: `test_animation_motion.gd`, `test_animation_motion_clock.gd` (parede fora do
Movie Maker; acumulação por quadro: uma vez por quadro, quadros pulados contam, não volta),
`test_animation_choreography.gd`,
`test_animation_camera_shots.gd` (planos, deixas, limites, UNIVERSE entre pilares com as sementes em
quadro e fora do HUD em 1600×900 e 1280×720, OBSERVATORY na área livre, `clamp_rig` segura o blend
acima do piso; foco: `fit_distance` preenche ~`FOCUS_FILL` com perspectiva, `focus_shot` mantém o modo e
centra a entidade, distância limitada à câmara, alcance por modo, semente com a câmara ao fundo no
terço oposto), `test_animation_entities.gd` (composição headless na ordem do world.gd, corpos de
seleção e piso não selecionável, câmera e limiar de arrasto compartilhado, seek, `segment_state` antes
da emissão, luz → ambiente com `exposure_scale` e cache — zerado em `world_rebuilt`, splits por
qualidade (alcance/blur da sombra com 2 splits), varredura → material, fita sobre o anel e sem
tampas, câmera acima do piso no meio de uma transição, óculo só fora do UNIVERSE, seleção, input; foco:
grupos de todas as entidades e limites, foco na camada suspende a deixa e `camera_reset` volta,
alvos desconhecidos/fora de alcance ignorados, input durante o foco devolve o controle, foco
sobrevive a seek fora de deixa). Capturas de todas as fases e modos: `tools/capture_evidence.sh`.

## GENESIS (Loop 4 — cena herói viva)

Mesmo princípio: tudo que é narrativo = f(`Simulation.genesis`, `Simulation.time`) por funções puras
de `GenesisChoreography` (`src/animation/genesis_choreography.gd`); movimento ambiente (respiração,
cabelo, deriva das mãos, giro do halo, órbitas, deriva do cinturão, pulsos dos fios já tecidos,
balanço da câmera) em `MotionClock`. Pausa congela a história e deixa o ambiente respirar; seek e reset
reconstroem o quadro exato. Nada pisca nem estoura: toda formação é inchaço/acreção (`Palette.T_SWELL`),
todos os valores são contínuos (testado a cada 0,02 s). Materiais: `.duplicate()` da `MaterialLibrary`
por corpo; os módulos escrevem só estado (`awaken`, `veins`, `formation`, `heat`…) e `motion_time` das
próprias duplicatas.

### Composição (`GenesisLayout`, `src/entities/genesis/genesis_layout.gd`)

Fonte única de posições (módulos, câmera, testes). Âncoras das esculturas sempre lidas do JSON ao lado
do `.obj` (`GenesisLayout.anchors/anchor/bounds`). Refinada com os style frames a partir do layout do
contrato: MIKU maior (escala 1,2 ≈ 7,4 u) e o mundo novo **abaixo e à frente da barra do vestido** — no
layout inicial as mãos e o planeta ficavam diante do tronco e escondiam a figura. Leitura vertical do
plano herói: cabelo (sai do quadro) → halo e rosto (terço superior) → vestido derramando poeira → o mundo
entre as mãos (terço inferior). Rodada de correção 1 (art-critic): MIKU subiu (origem y 8,4) e a mão
direita desceu para a direita (`HAND_RIGHT_POS`/`EULER`) — **espaço negativo**: no plano herói as pontas
dos dedos ficam ~0,1 da altura do quadro abaixo da barra do vestido (antes tocavam a barra); NAUVE-2
começa fora do quadro herói (`FAR_PHASES`). Mãos na escala 0,72 (punho→ponta ≈ 4,7 u, ≈ 1,5× o diâmetro final do
planeta): monumentais diante do mundo que seguram, abaixo de MIKU na hierarquia; pontas dos dedos a
≥ 0,05 u da superfície final (quase-toque; teste). Cinturão r 16–19 inclinado (frente alta, fundo baixo)
para a câmera herói nunca atravessar rochas; mundos antigos em r 30/42, raios 1,9/2,5 (além da câmera
herói: discretos no FORGE, inteiros no UNIVERSE).

### Módulos (nomes de nó fixos; compostos por `world.gd` em `GENESIS_MODULES`)

| Script | Nó | Papel |
|---|---|---|
| `entities/genesis/genesis_light_rig.gd` | `GenesisLightRig` | contraluz quente (DUSK_ROSE→GOLD com o calor), rim ICE, key PEARL ¾ lateral (única com sombra, por perfil; sem energia na névoa: as sombras na névoa desenhavam faixas escuras no céu; filtro mais suave, `normal_bias` 2, cascatas mescladas; **MIKU não projeta sombra** — a escada da sombra no torso/vestido sumiu, AO assado + SSAO a modelam), fill NEBULA mínimo, brilho do planeta (omni GOLD/MAGMA ∝ calor × formação; repouso de 30 % depois da crosta; no clímax vira a luz do céu do mundo, PEARL/ICE, com alcance maior). Níveis de `GenesisChoreography.light_levels` (adormecida → desperta). Só escreve `environment.ambient_light_energy` (quando muda); direcionais com `light_volumetric_fog_energy` ≤ `GenesisEnvironment.DIRECTIONAL_FOG_ENERGY` |
| `entities/genesis/miku.gd` | `Miku` | escultura + `miku_body()` (`awaken`, `breath`, `select`); cabelo em 3 camadas de `HairRibbons` saindo da coroa (âncora `hair_root`, para trás e para cima) + mechas das têmporas, cada camada balança com período próprio; o cabelo **desenrola por escala** a partir da coroa no despertar; halo `halo_arc()` num quad atrás da cabeça (uma volta por `T_HALO_TURN`); semente GOLD na testa (motes HDR contidos + omni fraca): brasa que respira no escuro antes do despertar, floresce (`seed_bloom`: a omni cresce para 4,3 u) e **revela a porcelana** (`body_presence` → `transparency`; oculta antes), depois pulsa a cada ato de criação; sem sombra própria (`cast_shadow` off); no clímax ergue a cabeça (`head_lift`: a figura inclina para trás na cintura) e o halo fecha o círculo (`halo_close` → `arc_span`/`inner_span`); flutuação de 8 s; vestido de luz = casca da saia (triângulos da escultura no envelope da saia, deslocados pela normal) com `miku_gown()` — **desligado** (`GOWN_VEIL`) até a correção do shader (ver "Pendências"); a dissolução em poeira é o rio do `Stardust` |
| `entities/genesis/auxiliary_hands.gd` | `AuxiliaryHands` | duas esculturas + `hand_stone()` por mão; esperam na névoa (ocultas), sobem em `HANDS_RISE` com ease e pequeno assentamento (`hands_rise`), surgem da névoa por `transparency`; o trabalho (`hands_work`) aproxima-as do mundo; a direita pressiona e inclina a cada ato de formação (`sculpt_press`), a esquerda ergue-se para embalar; `veins` acende com trabalho e pressão e **esfria** depois de `planet.stable`; no clímax as mãos **soltam** o mundo (`hands_release`: recuam cada uma na sua direção e a palma abre); deriva lenta ambiente; névoa de motes NEBULA/LILAC em volta de cada antebraço + **poeira que se desprende** do fim da pedra (`Shed`, ciclo ambiente) — o antebraço se dissolve na névoa; gancho para o shader: `dissolve_origin`/`dissolve_axis`/`dissolve_span` escritos quando `hand_stone` os declarar |
| `entities/genesis/forming_planet.gd` | `FormingPlanet` | `PlanetSphere` (densidade por qualidade) + `planet_forming()`: `formation` (acreção da semente), raio por passos (semente 0,55 → manto 1,2 → crosta 1,48 → céu 1,6), `heat` (semente 0,72 → manto 1 → esfria com a crosta), `crust`, `atmosphere`; rotação axial ambiente |
| `entities/genesis/orbital_system.gd` | `OrbitalSystem` | luas `moon_doc()` (nascem por acreção + inchaço, órbitas em pivôs), anel `ring_skill()` (condensa por inchaço + fade), cinturão `AsteroidField` + `asteroid_memory()` (rochas incham uma a uma, `memory` acende os brilhos, deriva lenta), **poeira do cinturão** (3 200 motes finos entre as rochas, 5 % brilhos GOLD; escritos uma vez, giram com as rochas, entram com o cinturão), 2 400 rochas, NAUVE-2 (anel próprio) e KESTRE-4 (duas luas) já formados, linhas `orbit_line()` em tubo com `head` = fase do corpo |
| `entities/genesis/relation_threads.gd` | `RelationThreads` | os 8 `GenesisScript.LINKS`: fibras cruzadas (`RelationThread`) que partem de pontos dentro da pluma do cabelo e terminam **no limbo** dos corpos (raio × `LIMB_CLEARANCE` na direção da outra ponta, nunca no centro), finas (`WIDTH` 0,05 dos de MIKU, 0,034 entre corpos, 0,022 planeta → lua); tecidas em sequência como **arcos parciais** que crescem pelo próprio caminho (subdivisão de Bézier); depois, pulsos GOLD (par de motes) viajam origem → alvo a cada 7,5–12,5 s; no clímax **um pulso único** (`stable_wave`) percorre o grafo inteiro em largura a partir de MIKU (salto 0: fios dela; salto 1: os que saem dos corpos alcançados), acendendo cada fio enquanto passa; fios planeta → luas vivem numa réplica do pivô da lua; fios aos mundos distantes são refeitos só quando uma ponta anda > 0,06 u |
| `fx/genesis/stardust.gd` | `Stardust` | rio de poeira do vestido (ambiente; dobra-se e alimenta o mundo de `dust.gathered` a `planet.stable`), disco de poeira que converge em espiral para a semente (função do tempo de simulação), disco de acreção em 3 bandas (presença narrativa, rotação ambiente), motes do ar |
| `fx/genesis/formation_glow.gd` | `FormationGlow` | clarão contido da semente, faíscas de formação (semente, camadas, luas, anel) e brilhos de chegada dos fios |
| `fx/genesis/mote_cloud.gd` | (auxiliar `MoteCloud`) | MultiMesh de motes (`MaterialLibrary.mote`) com buffer reaproveitado, cor HDR só nos núcleos, contagem por `Quality.profile.particles` |

### Mapeamento evento → visual (constantes em `GenesisChoreography`)

- **Antes de `miku.awaken`**: **escuro, só a semente** — brasa GOLD na testa (`SEED_DORMANT`, respira
  em tempo real); corpo oculto, cabelo apagado, sem halo; luz `LIGHT_ASLEEP` mínima (nenhuma silhueta
  humanoide escura contra a nebulosa); o vestido ainda é só poeira (rio do `Stardust` fraco).
- **`miku.awaken`**: a semente floresce (`SEED_DUR`, `seed_bloom`: a luz dela se abre) e **revela a
  porcelana** (`REVEAL_DELAY`, `REVEAL_DUR`); key/rim/ambiente sobem primeiro (`FRONT_LIGHT_DUR`), a
  contraluz depois (`BACK_LIGHT_DELAY`) — o corpo surge iluminado, nunca recortado; o cabelo desenrola
  (`HAIR_GROW_DUR`), o halo incha depois de `HALO_DELAY`.
- **`hands.summoned`**: as mãos sobem da névoa (`HANDS_RISE`, `HANDS_SETTLE`, `HANDS_OVERSHOOT`);
  kintsugi em repouso (`VEINS_SUMMONED`).
- **`dust.gathered`**: o disco de poeira converge (`DUST_CONVERGE`); o rio do vestido dobra-se para o
  mundo; começa o trabalho das mãos (`WORK_*`).
- **`planet.seeded`**: clarão da semente, acreção (`ACCRETE_DUR`), o núcleo incha; faíscas; pressão da
  mão direita (`SCULPT_*`); disco de acreção (`DISC_*`).
- **`planet.layer` 0/1/2**: manto (incha, calor pleno), crosta (placas assentam em `CRUST_DUR`, esfria em
  `COOL_DUR`), céu (`SKY_DUR`); cada camada = faíscas + pressão + surto da semente.
- **`moon.formed` i**: a lua incha por acreção (`MOON_SWELL`); a órbita é traçada atrás dela.
- **`ring.formed`**: o anel condensa (`RING_SWEEP`) + faíscas ao longo do círculo.
- **`belt.formed`**: as rochas incham uma a uma (`BELT_FORM`, `BELT_ROCK_SWELL`); acendem os brilhos de memória.
- **`links.woven`**: fios tecidos em sequência (`LINK_STAGGER`, `LINK_WEAVE`; todos prontos antes do
  pulso do clímax), brilho na chegada, depois pulsos.
- **`planet.stable` — clímax** (a sessão termina 3 s depois e o último instante fica congelado, então
  cada batida se resolve até 56 s): o **pico de luz da sessão** (`climax`: `LIGHT_CLIMAX` + luz do céu do
  mundo `PLANET_LIGHT_CLIMAX`; teste: nenhum instante anterior é mais claro), a semente surge; as mãos
  **soltam** o mundo devagar (`RELEASE_*`) e o kintsugi **esfria** (`VEINS_COOL_DUR` → `VEINS_STABLE`);
  MIKU **ergue a cabeça** (`HEAD_LIFT_*`); o halo **fecha a volta** (`HALO_CLOSE_*`); **um pulso único**
  percorre todos os fios (`WAVE_DELAY`, `WAVE_HOP`); o disco se dissolve, o rio relaxa; a câmera **recua**.

### Câmera GENESIS (`GenesisShots`, `src/animation/genesis_shots.gd`)

`CameraDirector` usa `GenesisShots` quando `Simulation.scenario == GENESIS` (planos, deixas, limites,
foco); a ORIGIN continua com `CameraShots` sem mudança. Troca de cenário = snap no plano do novo cenário.

- **FORGE** herói: levemente de baixo (câmera abaixo do peito, `FORGE_PITCH`), lente 36,5°; o teste fixa
  MIKU no terço superior, o mundo no inferior, centrado.
- **UNIVERSE**: afastado e baixo o bastante para **enquadrar o núcleo quente atrás do sistema** (o
  sistema no terço inferior, o núcleo no superior). **OBSERVATORY**: ¾ alto (fios e rótulos).
- **Deixas** (FORGE + `Session.cinematic`): estações de **um caminho contínuo** (`cue_path`, função pura
  do estado e do tempo de simulação) + balanço ambiente minúsculo (`SWAY_*`, MotionClock). Abre perto da
  semente, no escuro (`SEED_POSE`, um pouco acima, olhando para baixo, mundos distantes fora do quadro),
  depois quatro movimentos desenhados, cada um com ease in-out a partir do seu evento: (1) **grua para
  trás no despertar** até MIKU inteira (`CRANE_BACK`), enquanto a luz da semente a revela; recuo até o
  herói enquanto as mãos sobem (`HERO_DOLLY_DUR`); (2) **dolly baixo até o berço** no manto
  (`cue_g_cradle`, pela esquerda: a mão esquerda embala em primeiro plano, a direita longe do vestido);
  (3) **subida** nas luas/anel/cinturão até ¾ alto onde os fios saem do cabelo (`RISE_DUR`); (4) **recuo**
  no estável (`RECEDE_DUR`). Ids: `cue_g_portrait` → `cue_g_hero` → `cue_g_cradle` → `cue_g_orbits` →
  `cue_g_belt` → `cue_g_threads` → `cue_g_stable`. Como o caminho é contínuo, trocar de deixa não faz
  blend (`CONTINUOUS_CUES`; teste: nenhum salto a cada 0,02 s) — o giro brusco entre deixas (~48–50 s)
  que lia como "pop de exposição" sumiu. Voltar às deixas depois do usuário = grua de `Palette.T_CRANE`;
  mudanças do usuário (modo, foco, reset) em `T_USER`. Teste: nenhuma estação corta MIKU na cintura.
- **Limites**: pitch −0,55…1,35, distância por modo, alvo dentro de `FLY_RADIUS` (50), câmera nunca
  abaixo da névoa (`MIN_CAMERA_Y`).
- **Foco**: qualquer entidade GENESIS em qualquer modo (`focus_shot`: mantém lente e yaw, preenche
  `FOCUS_FILL`). Raiz de cada entidade no grupo `entity_<id>` com `focus_bounds` quando a malha não basta.
- **Style frames**: `CameraDirector.style_frame_poses()` → `GenesisShots.style_frame_poses()` (8 poses:
  herói, retrato, berço, detalhe do mundo, fios, sistema, silhueta, plano aberto).

### Seleção, rótulos e áudio

| id | Raiz visual (grupo `entity_<id>`) | Corpo de seleção (layer 2) |
|---|---|---|
| `miku` | `Miku/Figure` (`focus_bounds` = bounds da escultura, `label_anchor` acima da cabeça) | cápsula |
| `hand_left`, `hand_right` | pivô de cada mão (foco na mão sem o antebraço) | trimesh da escultura (desligado na névoa) |
| `planet_forming` | `FormingPlanet/Pivot/Body` (oculto até `planet.seeded`) | esfera que acompanha o raio |
| `moon_0/1` | malha da lua (oculta até nascer) | esfera |
| `ring_skill` | quad do anel | anel trimesh |
| `belt_memory` | `OrbitalSystem/Belt` (centro em MIKU; `label_anchor` num ponto do cinturão) | anel trimesh |
| `planet_far_0/1` | raiz do mundo | esfera |
| `relations` | `RelationThreads` (`label_anchor` no fio MIKU → planeta) | cápsulas ao longo desse fio |

Contrato da UI (bíblia §8): raiz invisível enquanto o corpo não existe; `label_anchor`/`label_radius`.
Âncoras de áudio (meta `audio_anchor` definida antes do fim do `_ready`): `miku` = coração, `hands` =
entre as palmas, `planet` = centro do mundo. Destaque de seleção/hover pelo uniform `select`
(suavizado em tempo real).

### Pendências (fora da área do animator)

- **Revelação radial e véu** (art-director): a porcelana surge hoje por `transparency` uniforme sob a luz
  da semente; um uniform de revelação a partir da testa (`reveal_origin`/`reveal_radius`) daria a luz
  nascendo dela pela pele. `hand_stone`: declarar `dissolve_origin`/`dissolve_axis`/`dissolve_span`
  (já escritos pelas mãos quando existirem). Segunda passada do animator: religar `GOWN_VEIL` com a
  dissolução em grãos, usar a nova `HairRibbons` (tufos, fios de link) e as metas dos novos materiais.
- **Céu no escuro da abertura** (game-engineer): o céu da nebulosa tem energia fixa por modo; antes do
  despertar o quadro já é escuro pela câmera (perto da semente, olhando abaixo do núcleo quente), mas
  no plano herói livre o céu continua claro (sem figura, só a semente).
- **Shaders com `pow` de base negativa** (art-director): `exp(-pow(x / w, 2.0))` com `x` com sinal gera NaN
  no llvmpipe (e em drivers que não reescrevem `pow(x, 2.0)` como `x*x`): `miku_gown` (lábio da
  dissolução), `miku_hair` (frente do `reveal`), `relation_thread` (frente do `woven` e `pulse`),
  `ring_skill` (frente da varredura). Em `miku_gown`, também `pow(1.0 - nv, 1.6)` com
  `nv = abs(dot(NORMAL, VIEW))` levemente > 1 (verificado: com `clamp` somem os borrões). Enquanto isso a
  cena usa só os caminhos seguros (`reveal` = 1, `woven` = 1, `pulse` < 0, anel com `formation` = 1, véu
  desligado) e faz crescimento, tecelagem, pulsos e condensação por geometria e motes. Depois da
  correção: ligar `Miku.GOWN_VEIL` e restaurar a dissolução (`GOWN_FADE`, `GOWN_STRETCH`, `GOWN_FLARE`).

### Custo

Sem alocação por quadro nos módulos (buffers de MultiMesh reaproveitados, caches de uniform); fios
refeitos só enquanto são tecidos ou quando uma ponta orbital anda. Motes: rio 300, poeira 420 (só entre
`dust.gathered` e a semente), disco 3 × 120 (posições fixas, só gira), ar 160, névoa 2 × 90, poeira dos
antebraços 2 × 70, faíscas 72, poeira do cinturão 3 200 (escrita uma vez; só gira) — × `Quality.profile.particles`
(LOW 0,35). Cinturão: rochas por `GenesisLayout.BELT_ROCKS` (LOW ≥ 45 %).

### Verificação

`tests/unit/test_animation_genesis.gd` (lógica pura: repouso antes dos eventos, assentamento, continuidade
a cada 0,02 s, o planeta só cresce, subida e assentamento das mãos, pressão por camada, ordem dos fios, a
luz cresce com o despertar, composição herói projetada, deixas por fase e determinismo, limites, foco em
tudo, style frames válidos, âncoras do JSON, mãos sem atravessar o mundo, órbitas, arco parcial, pulsos)
e `tests/unit/test_animation_genesis_modules.gd` (composição como no `world.gd`, raiz + corpo de seleção
por entidade do catálogo, corpos ocultos até existirem, âncoras de áudio, planeta/mãos/MIKU/órbitas/fios
seguem seek e reset, o rig só escreve o ambiente e respeita a névoa, a câmera usa `GenesisShots` e foca
todas as entidades, destaque de seleção, partículas por qualidade). Smoke:
`tools/smoke_test.sh --scenario=genesis`. Style frames: `tools/style_frames.sh <dir>`; capturas:
`tools/capture_evidence.sh <dir> --scenario=genesis`.
