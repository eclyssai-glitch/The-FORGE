# Modelagem procedural

Dono: `procedural-modeler`. Responsabilidade: geometria procedural (blueprints e malhas).
Código: `src/procedural/` · Testes: `tests/unit/test_procedural_*.gd`.

Regra da camada: **dados** (`StructureBlueprint`, `RefCounted` puro, testável sem render) separados
de **malha** (`MeshBuilder`, funções estáticas que devolvem `ArrayMesh`). Nenhuma geometria externa.
Malhas são geradas uma vez e reutilizadas (nunca por frame).

## Convenções

- Y para cima; núcleo suspenso na origem; piso da câmara em y = -3,2.
- Ângulos em torno de Y são medidos **a partir de +Z em direção a +X**: um ponto no ângulo `a` e raio
  `r` fica em `(r·sin a, y, r·cos a)` — exatamente o que `Basis(Vector3.UP, a)` faz com o eixo +Z.
- Todas as malhas: 1 superfície, `PRIMITIVE_TRIANGLES` indexada, normais unitárias, UV em [0,1],
  frente no sentido horário (convenção do Godot), sem triângulos degenerados — tudo verificado nos testes.
- Arestas vivas têm vértices separados (sombreamento nítido); paredes curvas têm normais suaves ao
  longo da curva.
- Malhas facetadas (`icosphere(flat)` e `shard`) levam cores de vértice baricêntricas
  (1,0,0)/(0,1,0)/(0,0,1) em `ARRAY_COLOR`, para shaders desenharem as arestas das facetas.

## Estrutura da ORIGIN CHAMBER — `StructureBlueprint`

Um "vaso" arquitetônico: 5 anéis finos segmentados, empilhados e espaçados em torno do núcleo, com
silhueta de lente (mais largo no equador) e 12 nervuras verticais finas (colunas) que atravessam
todos os anéis na forma final. Lido de baixo: laje, laje, cinta equatorial no plano do núcleo, laje,
laje — leitura de arquitetura (lajes + colunas), não de dispositivo.

`StructureBlueprint.build(layer_count := 5, seed := 7)`. Perfis (t ∈ [-1, 1] = posição relativa
da camada, a = |t|):

- `y = t · 1,84`; altura `lerp(0,19 → 0,14, a)`.
- raios em lente elíptica `r(a) = r_eq · sqrt(1 − k·a²)`, `k = 1 − (r_polo/r_eq)²`:
  externo 3,05 → 2,20; interno 2,10 → 1,40.
- contagem por camada ∝ peso em tenda `6 − 2a`, arredondada por maior resto para somar **96**
  (= `OriginChamberScript.FRAGMENT_COUNT`) para qualquer `layer_count`.
- `gap` = 0,05 unidade no raio médio (em radianos: 0,05 / r_médio); `angle_span = TAU/n − gap`.

| camada | nome (roteiro) | y | altura | r_int | r_ext | segmentos | span (rad) | gap (rad) |
|---|---|---|---|---|---|---|---|---|
| 0 | FOUNDATION | -1,840 | 0,140 | 1,400 | 2,200 | 16 | 0,3649 | 0,0278 |
| 1 | SPAN | -0,920 | 0,165 | 1,949 | 2,861 | 20 | 0,2934 | 0,0208 |
| 2 | GIRDLE | 0,000 | 0,190 | 2,100 | 3,050 | 24 | 0,2424 | 0,0194 |
| 3 | CROWN | 0,920 | 0,165 | 1,949 | 2,861 | 20 | 0,2934 | 0,0208 |
| 4 | APEX | 1,840 | 0,140 | 1,400 | 2,200 | 16 | 0,3649 | 0,0278 |

Limites garantidos por teste: raio interno mínimo 1,40 (> 1,1; o núcleo tem raio 0,55); raio
externo máximo 3,05 (≤ 3,2); anéis sem sobreposição vertical; núcleo no centro da camada do meio.

### Orientação dos segmentos (para o animador)

- A malha `MeshBuilder.annular_segment(**segment_mesh_params(camada))` é **centrada no ângulo 0 = eixo
  local +Z**, cobrindo `[-span/2, +span/2]`; o lado u = 1 fica para +X. O **eixo do anel está na
  origem local** (o segmento ocupa r_int..r_ext ao longo de +Z; y ∈ ±altura/2).
- `segment_transform(i, twist_amount)` = `Transform3D(Basis(UP, ângulo), (0, y_camada, 0))` com
  `ângulo = phase + TAU·k/n + twist_amount·twist`. `twist_amount = 1` é a pose de montagem (torcida);
  `0` é a forma final travada.
- Índice global `i` (0..95): camada a camada, de baixo para cima; dentro da camada, ângulo crescente.
  `segment_layer(i)`, `segment_index_in_layer(i)`, `layer_first_segment(camada)` fazem o mapeamento.
- `segment_pivot(camada)` = centróide local do segmento ≈ (0, 0, (r_int+r_ext)/2). Para girar/escalar
  um fragmento "no lugar", gire em torno desse ponto (e não da origem, que é o eixo do anel).
- **MultiMesh:** cada camada tem sua própria malha de segmento (raios/altura/span diferentes), então a
  estrutura usa **uma MultiMesh por camada** (5 × 16–24 instâncias), instância `k` = segmento
  `layer_first_segment(camada) + k`.

### Fragmentos soltos (scatter) e montagem

- `scatter_transform(i)`: centróide do segmento numa casca de raio 3,5–4,8 em torno do núcleo (fora do
  vaso, dentro de 5,0), azimute ≈ ângulo final ± 0,8 rad (os fragmentos voam quase radialmente),
  componente vertical da direção em [-0,5, 0,72] (sempre acima do piso), rotação uniforme aleatória
  (Shoemake) e escala uniforme 0,35–0,6.
- `assembly_transform(i, t, twist_amount := 0.0)`: pose intermediária pronta — centróide em linha reta
  do scatter (t = 0) à pose final (t = 1), rotação por slerp e escala por lerp, tudo em torno do pivô.

### Nervuras

`rib_transforms()` → 12 transforms no raio 2,15 (dentro de [r_int, r_ext] de **todas** as camadas, por
isso atravessam todos os anéis), alinhadas a cada segunda junta do anel equatorial; +Z local (dorso
plano da lâmina) aponta para fora. `rib_mesh_params()` → `{height: 3,78, width: 0,055, depth: 0,08}`:
a pilha de anéis vai de y = −1,91 (face inferior do anel mais baixo) a +1,91 (face superior do mais
alto), 3,82; a nervura recua `RIB_INSET` = 0,02 em cada ponta, ficando de −1,89 a +1,89 — as pontas
ficam embutidas nos anéis polares (altura 0,14), sem sobra acima/abaixo da pilha ("vergalhão", revisão
de arte do Loop 2) e sem tampa coplanar à face do anel (z-fighting). A origem da nervura é o meio da
pilha (y = 0), então o crescimento `rib_growth` (escala Y em torno da origem) nunca sai da pilha.

### Variação por seed

A seed controla apenas a **pose**, nunca as dimensões: `phase` de cada anel (meio passo nas camadas
ímpares + jitter ±0,04 rad), `twist` de montagem (0,45–0,85 rad, sinal alternado por camada) e todos os
transforms de scatter (RNG separado, seed·7919 + 104729). Mesma seed ⇒ blueprint idêntico; seeds
diferentes ⇒ mesmas dimensões, outras fases/torções/dispersão. Para variar a forma (outras estruturas
futuras), altere as constantes de perfil ou `layer_count` (a soma continua 96).

## Malhas — `MeshBuilder`

| função | forma | UV | vértices / triângulos |
|---|---|---|---|
| `annular_segment(r_in, r_out, height, angle_span, arc_steps := 6)` | setor de coroa: topo, base, parede externa/interna, 2 tampas laterais | topo/base: u ao longo do arco, v radial; paredes: u arco, v vertical; tampas: u radial, v vertical | 8·(steps+1)+8 / 8·steps+4 → **64 / 52** (steps 6) |
| `icosphere(radius, subdivisions, flat := true)` | casca facetada (flat) ou lisa | flat: por faceta (0,0)(1,0)(0.5,1); lisa: esférica | flat: 60·4^s / 20·4^s (s1: **240/80**, s2: 960/320); lisa s2: 162/320 |
| `ring(radius, thickness, width, segments := 128)` | anel de seção retangular (thickness radial, width vertical) | u ao redor, v através da face | 8·(seg+1) / 8·seg → 48: 392/384 · 64: 520/512 · 96: 776/768 · **128: 1032/1024** · **160: 1288/1280** · 192: 1544/1536 |
| `rib(height, width, depth)` | lâmina vertical afilada (ponta = 0,5 da largura/profundidade no meio, perfil cosseno), dorso +Z plano; x ±w/2, z ∈ [-d/2, d/2] | faces: u através, v vertical | 16·12+8 / 8·12+4 → **200 / 100** |
| `shard(size, seed)` | bipirâmide triangular irregular (~size em Y, ≤ 0,5·size em XZ) | por faceta | **18 / 6** |

AABB das malhas do blueprint (seed 7): segmento da camada 2 ≈ 0,74 × 0,19 × 0,97 (x × y × z, z de
2,085 a 3,05); nervura 0,055 × 3,78 × 0,08.

## Orçamento por consumidor (medido)

Levantamento de **todas** as chamadas `MeshBuilder.*` em `src/entities`, `src/fx` e `src/world`,
medido chamando as próprias funções com os parâmetros reais (script headless, Loop 2, rodada de
correção). Os parâmetros **não** são repetidos aqui: a fonte é o arquivo/constante citado. As
contagens só dependem de `segments`/`subdivisions`/`arc_steps`/`RIB_STEPS` (raios e tamanhos não
mudam triângulos). "inst." = instâncias (MultiMesh ou nós). Cada malha é construída uma vez em
`_ready`/`_init`.

| consumidor (arquivo: constante / nó) | chamada | v / t por malha | inst. | triângulos |
|---|---|---|---|---|
| `fragment_structure.gd`: `Layer0..4` (MultiMesh por camada; parâmetros de `StructureBlueprint.segment_mesh_params`, `ARC_STEPS`) | `annular_segment` | 64 / 52 | 96 (16/20/24/20/16) | 4 992 |
| `fragment_structure.gd`: `Ribs` (MultiMesh; `rib_mesh_params`, `RIB_STEPS`) | `rib` | 200 / 100 | 12 | 1 200 |
| `fragment_structure.gd`: `Guide0..4` (literal 96 segmentos) | `ring` | 776 / 768 | 5 | 3 840 |
| `origin_core.gd`: `Heart` (`HEART_RADIUS`, s2 lisa) | `icosphere` | 162 / 320 | 1 | 320 |
| `origin_core.gd`: `Shell` (`SHELL_RADIUS`, s1 facetada, `_plated_shell` não muda contagem) | `icosphere` | 240 / 80 | 1 | 80 |
| `verification_array.gd`: `Ring` (`RADIUS`, literal 160) | `ring` | 1 288 / 1 280 | 1 | 1 280 |
| `verification_array.gd`: `Band` (`RADIUS`, `BAND_WIDTH`, literal 160) | `ring` | 1 288 / 1 280 | 1 | 1 280 |
| `chamber_architecture.gd`: `Oculus` (`OCULUS_RADIUS`, literal 128) | `ring` | 1 032 / 1 024 | 1 | 1 024 |
| `chamber_architecture.gd`: `Inlay` (`INLAY_RADIUS`, literal 128) | `ring` | 1 032 / 1 024 | 1 | 1 024 |
| `emission_sparks.gd`: `Sparks` (MultiMesh; `SIZE`, `SEED`, `MAX_SPARKS`) | `shard` | 18 / 6 | 72 | 432 |
| `activation_pulse.gd`: `Wave` (`WAVE_SECTION`, literal 160) | `ring` | 1 288 / 1 280 | 1 | 1 280 |
| `activation_pulse.gd`: `FinalHalo` (`HALO_RADIUS`, literal 192) | `ring` | 1 544 / 1 536 | 1 | 1 536 |
| `universe.gd`: `SEEDS` forma `orb` (corpo s1 + 1 anel de 96) | `icosphere` + `ring` | 240/80 + 776/768 | 1 + 1 | 848 |
| `universe.gd`: `SEEDS` forma `spindle` (corpo s0 + 2 anéis de 96) | `icosphere` + `ring` | 60/20 + 776/768 | 1 + 2 | 1 556 |
| `universe.gd`: `SEEDS` forma `armillary` (corpo s0 + 2 anéis de 96) | `icosphere` + `ring` | 60/20 + 776/768 | 1 + 2 | 1 556 |
| **total renderizado por `MeshBuilder`** (pior caso: tudo visível) | | | | **≈ 22 250** |

- Estrutura completa (segmentos + nervuras): 6 192 t; as guias (3 840 t) só aparecem durante a
  construção. Núcleo 400 t; verificação 2 560 t (a banda só durante a varredura); pulso de ativação
  2 816 t (onda e halo não ficam visíveis juntos o tempo todo); sementes 3 960 t.
- Se a forma `armillary` perder o anel vertical (pedido P2-14 ao `game-engineer`), as sementes caem
  768 t (total ≈ 21 480).
- Fora do `MeshBuilder` (primitivas do Godot, medidas pelo mesmo script): piso `CylinderMesh`
  (`chamber_architecture.gd`: `FLOOR_RADIUS`, 128 segmentos radiais) 768 t; pilares `BoxMesh`
  12 t × `PILLAR_COUNT` = 288 t; poeira `QuadMesh` 2 t × `dust_field.gd`: `MAX_AMOUNT`.
- **Colisão (não renderizada, só picking):** `fragment_structure.gd` `PickLayer0..4` `ring`(48) →
  5 × 384 = 1 920 t; `verification_array.gd` `Pick` `ring`(64) → 512 t. Formas trimesh, criadas uma vez.
- A fórmula de triângulos do `ring` para 128 e 160 segmentos (e o padrão 128) é verificada em
  `test_procedural_meshes.gd::test_ring_triangle_formula_for_budget_segment_counts`.

## Verificação

- `tools/run_tests.sh`: `test_procedural_blueprint.gd` (soma 96, 16/20/24/20/16, determinismo por
  seed, limites de raio, y ordenado, mapeamento de índices, transform final × scatter, montagem,
  nervuras) e `test_procedural_meshes.gd` (contagens, normais unitárias, winding × normais, sem
  degenerados, AABB, UV em [0,1], determinismo do shard).
- Conferência visual (Loop 2): cena temporária com as 5 MultiMeshes, núcleo, nervuras e anel,
  renderizada via `tools/_display.sh` nas poses final, torcida, montagem (t = 0,6) e scatter.

---

# GENESIS (Loop 4) — esculturas offline e geradores em runtime

## Pipeline de escultura — `tools/sculpt/`

Ferramenta offline (ADR-013), Python do venv `/opt/korium-py` (numpy, scipy, scikit-image). Sem
rede, sem assets de terceiros, sem aleatoriedade. O jogo nunca roda Python: as saídas são
versionadas em `assets/meshes/`.

| arquivo | papel |
|---|---|
| `sdf.py` | biblioteca SDF vetorizada: `sphere`, `ellipsoid`, `capsule`, `round_cone` (exato), `round_box`, `halfspace`, `tube` (cadeia de round cones); `smin`/`smax` polinomiais com k em unidades de mundo; `union`, `blend`, `subtract`, `intersect`, `sculpt` (lista ordenada de add/sub); `place` (rotação + translação), `mirror_x`, `scale` (uniforme/por eixo), `bend`, `twist`, `cup` (arco transversal), `displace`, `offset`, `shell`. Cada forma carrega uma esfera envolvente (`f.bound`) e as booleanas só avaliam uma parte onde ela pode mudar o resultado (cull). |
| `mesher.py` | amostragem em banda estreita **hierárquica** (passos 16→8→4→2→1 da grade fina; só células a < 2 diagonais da superfície são subdivididas), `skimage.measure.marching_cubes` com `mask` (só células ativas), maior componente conexa (sem ilhas), **decimação QEM** vetorizada em lotes (com **importância** por vértice opcional), projeção dos vértices de volta à SDF (Newton), **normais = gradiente da SDF** (4 taps), **AO por vértice**, **`RadialWarp`** (refino local da grade) e escritor OBJ determinístico. |
| `hand.py` | mão paramétrica: palma, polegar, 4 dedos de 3 falanges, almofadas, nós, tendões, vincos, unha insinuada, antebraço fusiforme. |
| `giant_hands.py` | poses das mãos gigantes e referencial de exportação. |
| `miku.py` | a escultura de MIKU (rosto em relevo `face_relief`, calota e coque, braços, mãos, vestido), o cálculo das âncoras e `bake_spec()` (refino local da cabeça + importância da QEM). |
| `bake_all.py` / `bake_all.sh` | regenera tudo: `tools/sculpt/bake_all.sh` (≈ 14 min, MIKU ≈ 11,5 min; `--only hand_left`, `--quick` para iteração, `--out DIR`). |
| `preview/` | `render_previews.sh` + `preview.gd` + `views.py`: previews no Godot real (seção Previews). |

Determinismo: BLAS fixado em 1 thread, ordem de iteração fixa, números com casas fixas (`-0.0`
normalizado), JSON com chaves ordenadas. Verificado: duas execuções completas independentes
produziram os mesmos SHA-256 nos 6 arquivos (reverificado após o refino do Loop 4, com warp e
importância: `miku_body.obj` ce357962…, `hand_left.obj` 4adf4e9e…, `hand_right.obj` 4f05fb89…).

Algoritmos:
- **QEM em lote**: a cada passada calcula custo/posição ótima de todas as arestas (quádricas
  somadas, 3×3 pela adjunta; fallback ponto médio/extremos), escolhe um conjunto independente (a
  aresta é a mais barata no 2-anel dos dois extremos ⇒ estrelas disjuntas) e rejeita colapsos que
  violam a condição de link, deixam vizinho com grau < 3, invertem face (cos < 0,2) ou criam lasca.
  Arestas rejeitadas ficam fora por 8 passadas. Qualidade de triângulo (1º percentil) ≈ 0,6.
- **Refino local (`RadialWarp`)**: o marching cubes roda num espaço u deformado, mundo =
  c + (u − c)·φ(r)/r com φ' = 1/m dentro de r0 e transição suave (smoothstep) até 1 em r1; o
  mapa nunca expande distâncias, então f(mundo(u)) continua sendo um limite de distância e o
  recorte da banda estreita segue conservador. Os vértices voltam ao mundo pelo mesmo mapa e são
  projetados na SDF real. MIKU usa m = 1,8 em volta da cabeça (r0 0,34, r1 0,62): grade efetiva
  0,004 no rosto contra 0,0072 no resto.
- **Importância na QEM**: `decimate(importance=f)` multiplica as quádricas (e o termo de
  comprimento) de cada vértice pelo peso f(p) ≥ 1; o vértice sobrevivente herda o maior peso.
  MIKU: 1 + 11 na cabeça, +150 na frente do rosto (praticamente não simplificado), +4 nas mãos
  (`miku.bake_spec()`). Sem isso a saia/vestido consumia o orçamento (a cabeça ficava com ~3,8k
  triângulos no bake anterior).
- **AO**: em 6 escalas h (MIKU 0,012–0,45; mãos 0,06–1,4) amostra a SDF ao longo da normal e de 4
  direções num cone de 31°: `occ += w·clamp((h − d)/h)`; `ao = 1 − occ/Σw`. Guardado **linear** em
  cinza (R = G = B), 1 = aberto.
- Garantias por peça, checadas no bake (aborta se falharem): 0 arestas de borda, 0 não-manifold,
  1 componente; os bakes finais têm Euler 2 (gênero 0).

## Formato: OBJ com cor de vértice (decisão)

Testado no Godot 4.7.2 (projeto descartável, `load()` + `surface_get_arrays`): linhas
`v x y z r g b` chegam como `ARRAY_COLOR` (quantizadas em 8 bits: 0,5 → 0,498); faces OBJ
anti-horárias vistas de fora viram a frente horária do Godot. Por isso **OBJ** (sem escritor glTF
próprio). Importador `wavefront_obj` com os padrões: `generate_lods = true` (LODs automáticos),
`generate_shadow_mesh = true`, compressão ligada. Sem UV: os materiais usam `COLOR.r` como AO e
coordenadas de objeto — é o que `MaterialLibrary.miku_body()`/`hand_stone()` fazem.

Carregar: `var mesh: Mesh = load("res://assets/meshes/miku_body.obj")` → `MeshInstance3D.mesh`.
Metadados: `JSON.parse_string(FileAccess.get_file_as_string("res://assets/meshes/miku_body.json"))`
(âncoras em coordenadas do mesh; aplique o transform do nó).

## MIKU — `assets/meshes/miku_body.obj` + `.json`

Estátua sacra estilizada original (abstração tipo Brancusi, "Musa adormecida" / mármore art déco),
não anime: ~11 cabeças (cabeça 0,53 u do queixo ao alto), cabeça curvada ~17° para a frente/baixo,
levemente inclinada e girada; pescoço longo, clavículas e esternocleidomastoides suaves, busto
discreto, contrapposto (ombros e quadril inclinados em sentidos opostos, tronco girado), braços
longos abertos para a frente e para baixo. Da cintura: vestido em sino alongado (quadril, leve
estreitamento, alargamento final), pregas verticais com torção lenta, leve varrida para trás, perna
relaxada insinuada sob o tecido, **aberto embaixo** (casca de 3–4 cm, domo interno em y ≈ −1,7)
com barra irregular suave. Sem pés, sem pernas.

**Rosto (refino do Loop 4)** — um único oval contínuo, sem aresta dura. O rosto é um **relevo**
(campo de altura z = f(x, y) no referencial da cabeça, com distância normalizada pelo gradiente)
sobre um oval em ovo com queixo afinado; toda feição é uma elevação ou depressão gaussiana suave:
testa lisa e cheia; arcada superciliar sutil que flui para a raiz do nariz; nariz fino e reto
(projeção ≈ 0,04 u, ponta pequena); cavidade orbital rasa com a **pálpebra fechada em amêndoa**
(borda superior macia, linha dos cílios em arco suave para baixo, pálpebra inferior leve); maçãs e
bochechas suaves, têmporas levemente recuadas; boca só como relevo de lábios (divisão quase
imperceptível); queixo pequeno e delicado; a linha da mandíbula sobe do queixo para a orelha (corte
inclinado atrás), sem papada. Todo limite (clamp) do relevo é suave: uma quina no campo aparece como
costura nas normais. Perfil: testa 0,22 · glabela 0,224 · raiz 0,22 · ponta do nariz 0,253 ·
subnasal 0,215 · lábios 0,222/0,21 · queixo 0,21 (z no referencial da cabeça).

**Cabelo** — calota presa ao crânio (espessura 0,9 cm na frente → 2,6 cm atrás), com rampa larga na
linha do cabelo (sem ressalto/faixa na testa); a linha do cabelo é função do azimute: testa → têmpora
→ desce na frente da orelha (não modelada) até o meio dela → contorna por trás → nuca, cobrindo a
orelha e deixando a mandíbula livre (sem capuz). 22 sulcos rasos de penteado (0,15 cm) varrem da
testa para trás e convergem, escondidos, sob um **coque baixo** (elipsoide largo na região
occipital + fluxo curto) de onde partem as fitas (`hair_root`); sem chifre, sem mecha lateral.

**Braços** — anatomia estilizada mantendo o alongamento: deltoide cheio, ventres do bíceps e do
tríceps, cotovelo macio, massa do antebraço logo abaixo do cotovelo afunilando para um **punho fino
e achatado** (fino na direção da palma). Raios ≈ 0,10 (ombro/deltoide) → 0,068 (cotovelo) → 0,08
(antebraço) → 0,045 × 0,035 (punho); antes 0,10 → 0,064 → 0,071 → 0,046 em tubo liso.

**Mãos de MIKU** — dedos separados e legíveis à distância: leque pequeno (abertura +0,09 → −0,19
rad do indicador ao mínimo), flexão crescente para o mínimo, fusão só na base (`fuse_k` 0,05, antes
0,28, que dava uma "luva"); polegar solto. Gênero 0 verificado.

- Referencial: +Y para cima, **frente +Z**, **origem no centro da cintura**; mão esquerda dela em +X.
- Bounds: min (−1,444, −4,334, −1,610), max (1,424, 1,760, 1,191) → **6,09 u de altura** (barra
  irregular: −4,15 ± 0,19).
- **117 998 triângulos**, 59 001 vértices, grade 0,0072 u (0,004 efetiva na cabeça, `RadialWarp`
  m = 1,8), marching cubes 2,13 M → QEM com importância (rosto ≈ sem simplificação); OBJ 8,9 MB.
  AO mín 0,11, média 0,82. Euler 2 (gênero 0), 1 componente, 0 arestas de borda. Bake ≈ 11,5 min.

| âncora (mesh) | valor | antes do refino |
|---|---|---|
| `head_top` | (−0,023, 1,729, 0,263) — topo ao longo do eixo da cabeça curvada | (−0,021, 1,771, 0,278) |
| `forehead` | (0,001, 1,515, 0,417) — semente de luz | (0,002, 1,516, 0,423) |
| `hair_root` | (−0,081, 1,584, −0,152) — fim do coque baixo | (−0,078, 1,726, −0,113) |
| `hair_root_tangent` | (−0,074, 0,703, −0,708) — 45° acima da horizontal, para trás | (−0,070, 0,845, −0,531) |
| `palm_left` / `palm_left_normal` | (1,204, −0,584, 0,892) / (0,680, −0,150, −0,718) | igual |
| `palm_right` / `palm_right_normal` | (−1,028, −0,611, 0,991) / (−0,722, −0,232, −0,652) | igual |
| `chest` | (−0,015, 0,610, 0,207) | igual |
| `gown_hem_center` / `gown_hem_radius` | (−0,180, −4,116, −0,344) / 1,161 | igual |

## Mãos gigantes — `assets/meshes/hand_left.obj`, `hand_right.obj` + `.json`

Anatômicas e estilizadas: eminências tenar/hipotenar e oco da palma, arco transversal, nós dos
dedos, falanges com almofadas palmares e nós dorsais, vincos palmares suaves, unha insinuada (plano
raso com borda de cutícula macia), tendões extensores suaves (refino: mais finos e mais fundos,
fillet maior), nós dos dedos (cabeças dos metacarpos) mais salientes no dorso, estiloides do punho,
antebraço fusiforme que se afina num fim macio (fica na névoa). Pulso → ponta do médio
**desdobrado = 7,0 u**; na pose a corda é 6,58 (esq.) / 6,49 (dir.) — campo `wrist_to_middle_tip`.

Poses próprias (a direita **não** é espelho da esquerda — o teste compara as pontas):
- **esquerda** embala por baixo: palma para cima, arco transversal forte, dedos curvos em concha
  rasa (flexão crescente do indicador ao mínimo), polegar aberto e erguido formando a borda.
- **direita** — gesto de escultor, modela por cima: palma para baixo; o **indicador lidera**, quase
  estendido e levemente curvo (flexão 0,12/0,20/0,13 rad); **médio, anelar e mínimo em cascata**
  (0,30/0,44/0,28 → 0,46/0,62/0,36 → 0,62/0,76/0,42) com leque leve; **polegar em oposição**, vindo
  para a frente sob o indicador como quem belisca a argila; antebraço mais curto antes do corte
  (2,4 u, antes 3,6).

Referencial de exportação, **origem = centro da palma** (na superfície palmar):

| | dedos | palma (`palm_normal`) | antebraço (`forearm_dir`) | polegar |
|---|---|---|---|---|
| esquerda | +X | +Y (0,017, 1,000, −0,005) | −X (−0,989, 0,138, −0,059) | −Z |
| direita | −X | −Y (−0,017, −1,000, 0,004) | +X (0,954, 0,286, −0,095) | +Z |

Outras âncoras: `wrist_center` (esq. (−2,05, −0,42, 0), dir. (2,05, 0,43, 0)), `forearm_end`,
`tip_thumb/index/middle/ring/little`. Bounds esq. 9,82 × 3,27 × 3,74 (inclui ~3,6 u de antebraço);
dir. 8,56 × 3,40 × 3,13 (antes 9,71 × 4,15 × 3,61; ~2,4 u de antebraço). **57 998 triângulos**
cada (29 001 vértices), grade 0,022 u; OBJ 4,3 MB cada; Euler 2.

Âncoras da mão direita que mudaram (antes → depois): `forearm_end` (5,323, 1,514, −0,362) →
(4,179, 1,170, −0,248); `tip_thumb` (−1,252, −2,348, 1,630) → (−1,804, −1,738, 0,685);
`tip_index` (−4,356, −0,346, 1,458) → (−4,344, −0,415, 1,381); `tip_middle` (−4,202, −1,399,
0,386) → (−4,138, −1,483, 0,358); `tip_ring` (−3,727, −1,523, −0,488) → (−3,178, −1,917, −0,429);
`tip_little` (−2,757, −1,325, −1,157) → (−1,939, −1,692, −0,944). A mão esquerda só mudou no
relevo (tendões/nós), âncoras iguais a menos de 0,001. Na cena do contrato (esq. ≈ (−3,0, −1,5, 4,6), dir. ≈ (3,2, 3,4, 4,8), planeta
(0, 1, 4)), com rotação identidade a esquerda aponta os dedos para o planeta com a palma para cima e
a direita paira sobre ele com a palma para baixo; ajuste fino girando `palm_normal` para o planeta.

## Geradores em runtime — `src/procedural/` (RefCounted, estáticos, determinísticos)

Convenções: 1 superfície, triângulos indexados com frente horária (Godot), normais unitárias,
UV em [0,1]. Construir uma vez; nunca por frame.

**`HairRibbons`**
- `curve_point(points, t)`, `sample_curve(points, samples)` — Catmull-Rom.
- `generate_curves(root, direction, count, seed, length := 10.0, points := 9, spread := 0.5,
  wave_amplitude := 0.45, waves := 1.4, rise := 0.9, root_radius := 0.05) -> Array[PackedVector3Array]`
  — leque num cone de meia-abertura `spread`, ondas longas, direção que sobe progressivamente
  (`rise`), comprimentos 0,72–1,08 × `length`. Use `hair_root`/`hair_root_tangent` (no mundo).
- `build(curves, width := 0.06, tip_ratio := 0.15, samples := 48, facing := Vector3.BACK,
  crossed := false) -> ArrayMesh` — UV.x raiz→ponta por comprimento de arco, UV.y na largura;
  largura afina até `tip_ratio`; UV2 = (índice do fio normalizado, hash 0..1); COLOR branco com
  **alfa = opacidade** (0,55–1 por fio → 0 na ponta), como `miku_hair()` espera; TANGENT ao longo
  do fio; referencial por transporte paralelo. `crossed` duplica cada fio a 90° (não some de
  perfil). Custo `2·(samples−1)` t por fio (×2 cruzado): 64 fios × 48 amostras = 6 016 t.

**`OrbitLine`** (plano XZ; fase p → ângulo 2πp a partir de +Z para +X)
- `point(rx, rz, phase)`, `outward(rx, rz, phase)`.
- `build(rx, rz, width, segments := 256)` — faixa plana, UV.x = fase, UV.y interno→externo, normal +Y; `2·segments` t.
- `build_tube(rx, rz, radius, segments := 256, radial := 4)` — tubo fino, UV.x = fase, UV.y em volta; `2·segments·radial` t.
- `build_line(rx, rz, segments := 256)` — `PRIMITIVE_LINE_STRIP` fechado, UV.x = fase.

**`PlanetSphere`**
- `build(radius, sectors := 96, rings := 48)` — esfera UV (UV.x longitude com costura duplicada,
  UV.y = 0 no polo norte), normais e **tangentes analíticas** (d/dφ, w = +1, iguais às de
  `SurfaceTool.generate_tangents` — testado), polos sem degenerados; `triangle_count = 2·s·(r−1)`.
- `segments_for_level(level)` / `build_for_level(radius, level)` por `QualityProfiles.Level`:
  LOW 48×24 (2 208 t), MEDIUM 64×32 (3 968 t), HIGH 96×48 (9 024 t), ULTRA 128×64 (16 128 t).

**`AsteroidField`**
- `transforms(count, inner_radius, outer_radius, thickness, seed, min_scale := 0.05,
  max_scale := 0.4, scale_bias := 3.0) -> Array[Transform3D]` — raio uniforme em área, altura
  triangular em ±espessura/2, rotação uniforme (Shoemake), escala com viés de potência.
- `build_multimesh(mesh, xforms) -> MultiMesh` (TRANSFORM_3D; `asteroid_memory()` usa INSTANCE_ID).
- `rock_mesh(seed, radius := 1.0, subdivisions := 1, roughness := 0.3)` — icosfera achatada e
  amassada por seed, facetada, UV por faceta e cor baricêntrica; 80 t (s1) / 320 t (s2).

**`RelationThread`** (Bezier quadrática; ápice a `height` do ponto médio, curvando para `up`)
- `bulge_dir`, `arc_point(a, b, height, t, up)`, `arc_tangent(...)`, `arc_points(a, b, height, segments := 48, up)`.
- `build(a, b, height, width, segments := 48, up, facing := Vector3.ZERO)` — fita (no plano do arco por padrão); `2·segments` t.
- `build_crossed(a, b, height, width, segments := 48, up)` — duas fitas a 90°; `4·segments` t.
- `build_tube(a, b, height, radius, segments := 48, radial := 5, up)` — tubo; `2·segments·radial` t.
  UV.x 0→1 de `a` para `b` em todos (pulso), UV.y na largura/em volta.

## Previews (Godot real, Forward+ via xvfb)

`tools/sculpt/previews/` (26 PNG 1600×900, 4,7 MB): `miku_{front,q34,side,back,low,bust_q34}`,
`miku_head_{face,q34l,sidel}` (frente, ¾ e perfil **no referencial da cabeça**, luz de estúdio),
`miku_head_soft` (luz lateral suave, sombra de penumbra larga), `miku_head_hard` (luz dura quase
frontal, sem fill — expõe qualquer vinco), `miku_hand_left`, `hand_{left,right}_{q34,front,top,
under,low,soft,hard}` — argila neutra × AO do vértice. Estúdio: key quente com sombra, recorte frio
forte, fill fraco. Regerar: `tools/sculpt/preview/render_previews.sh [MESH_DIR] [OUT_DIR]` (projeto
Godot descartável próprio em `tools/sculpt/preview/`, ignorado pelo projeto principal via
`.gdignore`; câmeras em `views.py`).

Inspeção (refino do Loop 4): a faixa/vinco da testa sumiu; testa lisa, olhos fechados lidos como
amêndoas serenas, perfil com nariz fino, lábios e queixo delicado, calota com coque baixo sem capuz.
Limites conhecidos: sob luz dura e close extremo a linha dos cílios mostra leve serrilhado (feição
de ~2 células da grade fina); a borda da unha do polegar da mão direita marca como um traço sob luz
dura; a mandíbula em perfil ainda é cheia (estilização).

## Testes — `tests/unit/test_procedural_genesis.gd`

Esculturas: carregam como `Mesh` de 1 superfície; triângulos ≤ orçamento (120k / 60k); cor de
vértice presente, cinza e com contraste; normais unitárias; enrolamento coerente com as normais
(< 0,1% de exceções); AABB = `bounds` do JSON; altura de MIKU 5,8–6,2 com a origem dentro; âncoras
presentes, dentro dos bounds e com a orientação do contrato; mãos com origem na palma, corda
pulso→médio 5,6–7,2, palma para cima/baixo, direita não-espelho. Geradores: mesma seed ⇒ mesmos
arrays, seed diferente ⇒ outros; UV em [0,1]; sem degenerados; frente horária; contagens;
tangentes = SurfaceTool; transforms dentro do anel; alfa do cabelo; variantes cruzadas/tubo.
