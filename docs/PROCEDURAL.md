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
| `mesher.py` | limpeza de lascas `clean_slivers`; amostragem em banda estreita **hierárquica** (passos 16→8→4→2→1 da grade fina; só células a < 2 diagonais da superfície são subdivididas), `skimage.measure.marching_cubes` com `mask` (só células ativas), maior componente conexa (sem ilhas), **decimação QEM** vetorizada em lotes (com **importância** por vértice opcional), projeção dos vértices de volta à SDF (Newton), **normais = gradiente da SDF** (4 taps), **AO por vértice**, **`RadialWarp`** (refino local da grade) e escritor OBJ determinístico. |
| `hand.py` | mão paramétrica: palma, polegar, 4 dedos de 3 falanges esculpidas (`_phalanx`: seção elíptica, dorso plano, haste cintada, afunilamento `TIP_TAPER`), almofadas, metacarpos, tendões, vincos, leito de unha, antebraço fusiforme. |
| `giant_hands.py` | poses das mãos gigantes e referencial de exportação. |
| `miku.py` | a escultura de MIKU (rosto em relevo `face_relief`, massa de cabelo `_hair` + coque `_knot`, tronco, corpete drapeado `_bodice`, braços, mãos, vestido), o cálculo das âncoras e `bake_spec()` (refino local da cabeça + importância da QEM). |
| `bake_all.py` / `bake_all.sh` | regenera tudo: `tools/sculpt/bake_all.sh` (≈ 14 min, MIKU ≈ 11,5 min; `--only hand_left`, `--quick` para iteração, `--out DIR`). |
| `preview/` | `render_previews.sh` + `preview.gd` (argila) + `game_look.gd` (material real, ambiente e rig GENESIS) + `views.py`: previews no Godot real (seção Previews). |

Determinismo: BLAS fixado em 1 thread, ordem de iteração fixa, números com casas fixas (`-0.0`
normalizado), JSON com chaves ordenadas. Verificado: duas execuções completas independentes
produzem os mesmos SHA-256 (reverificado na rodada de correção do Loop 4, com corpete, cabelo,
falanges e `clean_slivers`: `miku_body.obj` 79ab78ab…, `hand_left.obj` 450812d7…, `hand_right.obj`
b9ca9eba…).

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
- **Limpeza de lascas (`clean_slivers`, rodada de correção do Loop 4)**: depois da projeção final,
  faces de área ~0 (< 0,002 × aresta média²) ou cuja normal de enrolamento discorda das normais da
  SDF nos vértices (cos < 0,2) têm só os seus vértices relaxados para o centróide do 1-anel e
  reprojetados na SDF (até 6 passadas, determinístico). MIKU 459 → 2, mãos 78–80 → 0; contagem nos
  `stats` do bake (`slivers_before`, `slivers`).
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

Estátua sacra estilizada original — **estatuária votiva** (korai, mármore art déco), não anime nem
manequim: ~11 cabeças (cabeça 0,53 u do queixo ao alto, sem o cabelo), cabeça curvada ~17° para a
frente/baixo, levemente inclinada e girada; pescoço longo, contrapposto (ombros e quadril inclinados
em sentidos opostos, tronco girado), braços longos abertos para a frente e para baixo. Veste um
único vestido: **corpete drapeado** do ombro à cintura que continua, sem costura nem cós, no sino
alongado da saia (pregas verticais com torção lenta, leve varrida para trás, perna relaxada
insinuada), **aberto embaixo** (casca de 3–4 cm, domo interno em y ≈ −1,7) com barra irregular
suave. Sem pés, sem pernas.

**Rodada de correção do Loop 4 (art-critic: "manequim/alienígena careca")** — o que mudou:
- **Rosto como massa**: a arcada superciliar é um plano contínuo da testa à raiz do nariz (perfil
  grego) com o rebordo orbital em **massa** que avança sobre o olho (+0,011) e faz sombra; cavidade
  mais funda sob a arcada; a **pálpebra fechada é uma amêndoa convexa** (+0,012, borda inferior
  macia) sobre o globo, sem sulco de cílio; **lábios como volumes** (superior com arco do cupido,
  inferior mais cheio, altura afinando para os cantos — nada de "caixa"), divisão só onde as duas
  massas se encontram, cantos recolhidos e leve concavidade sob o lábio inferior; queixo definido.
- **Massa de cabelo esculpida** (`_hair`, `_knot`): espessura real sobre o crânio (2,0 cm na linha do
  cabelo → +2,0 no alto, +3,0 nas faixas que cobrem as orelhas, +1,2 atrás; 1 cm ≈ 0,023 u), linha
  do cabelo com rolo macio (rampa 0,087 u), **21 mechas largas** penteadas para trás (meridianos em
  torno do eixo rosto → coque, ondulação 0,1 rad, relevo 0,0095 entre crista e sulco) com 3 fios
  finos por mecha; convergem num **coque enrolado alto** na parte de trás da cabeça (elipsoide
  0,105 × 0,088 × 0,085 com torção em espiral) que termina numa **cauda curta** de 0,13 u ao longo
  da saída das fitas (50° acima da horizontal, para trás): `hair_root` é a ponta dessa cauda — onde
  a escultura vira a nebulosa de luz (`HairRibbons.nebula`). A cabeça ganhou volume nobre na
  silhueta e não lê careca em nenhum ângulo.
- **Ombros caídos com clavícula**: trapézio numa linha longa e descendente do pescoço (y 1,07) a um
  ombro baixo e estreito (articulação em (±0,40, 0,76), antes (±0,42, 0,79); jugo 0,33 de largura,
  antes 0,40); clavículas afinando (0,021 → 0,017) com as fossas supraclaviculares suaves acima.
- **Sem seios modelados**: o peito é um **corpete drapeado** (`_bodice`) — o tecido passa como um
  plano do ombro à cintura (casca 1,1 cm sobre o tronco + volume de drapeado frontal), decote
  em concha suave abaixo das clavículas (mais baixo nas costas), **swags em U** do cowl sob o decote
  (0,013) e **pregas largas** (7, amplitude 0,017) que nascem dos ombros em diagonal e convergem na
  cintura, acalmando sobre o peito e os ombros. Sem cava recortada (os braços se fundem sobre o
  tecido no ombro: uma borda de tecido junto à pele fechava túneis na axila).
- **Sem cós**: removida a faixa da cintura; acima da cintura a saia mergulha sob o corpete (máximo
  suave de y, 0,6 × y) e a união usa k 0,07 — uma superfície contínua, sem lábio. O quadril da saia
  ficou mais macio (0,13 em vez de 0,17, sem o estreitamento de "saia lápis").
- **Braços**: ombro→cotovelo→punho mais afastados do corpo (cotovelos (±0,78, 0,0), punhos (1,10,
  −0,47) / (−1,10, −0,40)) — o braço não "derrete" no quadril de perfil; braço 0,102 → 0,07 no
  cotovelo; **antebraço mais cheio** (tubo 0,07 → 0,086 → 0,07 → 0,048 + dois ventres musculares,
  antes 0,068 → 0,078 → 0,062 → 0,045). Mãos de MIKU com leque um pouco mais aberto (+0,12 → −0,24
  rad) — os dedos não se tocam na grade (gênero 0).

**"Buraco escuro" no tronco e braço "derretendo" (sf_05/g12)** — investigado: a malha não tem furo
(0 arestas de borda, Euler 2, 1 componente) nem normais invertidas na região; a mancha é a **sombra
projetada do braço direito pela key** (vinda do lado direito dela) sobre o flanco, com o serrilhado
do mapa de sombra; o "derreter" era o braço quase encostado ao quadril na projeção. Prova:
`game_look.gd --shadows=0` no mesmo enquadramento do `sf_05` remove a mancha (seção Previews). Com
os braços mais afastados, a sombra cai mais na saia; o resto é do rig (animator/game-engineer:
sombra suave/sem escada ou MIKU sem auto-sombra da key).

- Referencial: +Y para cima, **frente +Z**, **origem no centro da cintura**; mão esquerda dela em +X.
- Bounds: min (−1,458, −4,334, −1,623), max (1,494, 1,791, 1,175) → **6,12 u de altura** (barra
  irregular: −4,15 ± 0,19); antes (−1,444, −4,334, −1,610) / (1,424, 1,760, 1,191), 6,09 u.
- **117 998 triângulos**, 59 001 vértices, grade 0,0072 u (0,004 efetiva na cabeça, `RadialWarp`
  m = 1,8), marching cubes 2,17 M → QEM com importância (rosto ≈ sem simplificação); OBJ 8,9 MB.
  AO mín 0,12, média 0,83. Euler 2 (gênero 0), 1 componente, 0 arestas de borda; lascas 459 → 2
  (`clean_slivers`). Bake ≈ 16 min (o corpete avalia o tronco duas vezes).

Âncoras (coordenadas do mesh) — **antes → depois** da rodada de correção:

| âncora | antes | depois | por quê |
|---|---|---|---|
| `head_top` | (−0,023, 1,729, 0,263) | (−0,022, 1,752, 0,271) | volume do cabelo no alto |
| `forehead` | (0,001, 1,515, 0,417) | igual | semente de luz no mesmo lugar |
| `hair_root` | (−0,081, 1,584, −0,152) | **(−0,077, 1,750, −0,118)** | coque alto + cauda (≈ o valor de fallback dos consumidores, (−0,08, 1,73, −0,11)) |
| `hair_root_tangent` | (−0,074, 0,703, −0,708) | **(−0,072, 0,795, −0,603)** | saída 50° acima da horizontal, para trás |
| `palm_left` / `_normal` | (1,204, −0,584, 0,892) / (0,680, −0,150, −0,718) | (1,265, −0,589, 0,867) / (0,655, −0,162, −0,738) | braços afastados do corpo |
| `palm_right` / `_normal` | (−1,028, −0,611, 0,991) / (−0,722, −0,232, −0,652) | (−1,101, −0,622, 0,974) / (−0,697, −0,244, −0,674) | idem |
| `chest` | (−0,015, 0,610, 0,207) | (−0,012, 0,608, 0,259) | superfície do corpete (5 cm à frente) |
| `gown_hem_center` / `_radius` | (−0,180, −4,116, −0,344) / 1,161 | (−0,180, −4,116, −0,345) / 1,174 | saia sem cós, quadril mais macio |

## Mãos gigantes — `assets/meshes/hand_left.obj`, `hand_right.obj` + `.json`

Anatômicas e estilizadas: eminências tenar/hipotenar e oco da palma, arco transversal, falanges
esculpidas, vincos palmares suaves, tendões extensores suaves, cabeças dos metacarpos em bloco
arredondado no dorso, estiloides do punho, antebraço fusiforme que se afina num fim macio (fica na
névoa). Pulso → ponta do médio **desdobrado = 7,0 u**; na pose a corda é 6,54 (esq.) / 6,47 (dir.) —
campo `wrist_to_middle_tip`.

**Dedos (rodada de correção do Loop 4: nada de "salsicha segmentada")** — cada falange é um
`_phalanx` (`hand.py`): cone arredondado no referencial do dedo com **seção elíptica** (1,07 × a
espessura, achatada para 0,83 no dorso), **dorso mais plano e haste levemente cintada no meio**
(achatamento −0,10 e largura −0,06 no meio da falange) — as articulações leem como **planos de nós**
onde as hastes planas se encontram, sem contas/esferas nas juntas (as esferas dorsais e as caixas
de nó testadas antes viravam "anéis"); **afunilamento** extra por junta `TIP_TAPER` (1, 0,97, 0,92,
0,80 — a ponta fica com 80% do raio antigo); almofadas palmares baixas (elipsoide 0,78 × 0,66 do raio
médio); vincos palmares rasos (cápsula 0,04, k 0,12); **unha insinuada** como leito plano rebaixado
(plano a 0,83 do raio da ponta, mais estreito que o dedo: 0,72 r de cada lado, k 0,12) — dobras
laterais macias, sem corte retangular. O fim do antebraço afina para 0,24 (antes 0,20 num coto
mais curto; 0,12 lia "cenoura"). As mãos pequenas de MIKU (`detail=False`) continuam com o núcleo
de cones arredondados.

Poses próprias (a direita **não** é espelho da esquerda — o teste compara as pontas):
- **esquerda** embala por baixo: palma para cima, arco transversal forte, dedos curvos em concha
  rasa (flexão crescente do indicador ao mínimo), polegar aberto e erguido formando a borda.
- **direita** — **gesto de tecer** (substitui o indicador estendido que remetia à "Criação de
  Adão"): palma para baixo; **dedos entreabertos** em leque (abertura +0,20 / +0,05 / −0,12 / −0,30
  rad do indicador ao mínimo), **curvos em profundidades escalonadas** como quem passa fios entre
  eles (flexão indicador 0,24/0,30/0,18, médio 0,34/0,40/0,24, anelar 0,27/0,34/0,20, mínimo
  0,40/0,46/0,28 — o anelar menos curvo que o médio quebra a cascata), **polegar aberto e solto** ao
  lado do indicador (sem pinça); arco 0,30; antebraço curto (2,4 u).

Referencial de exportação, **origem = centro da palma** (na superfície palmar):

| | dedos | palma (`palm_normal`) | antebraço (`forearm_dir`) | polegar |
|---|---|---|---|---|
| esquerda | +X | +Y (0,017, 1,000, −0,005) | −X (−0,989, 0,138, −0,059) | −Z |
| direita | −X | −Y (−0,017, −1,000, 0,004) | +X (0,954, 0,286, −0,095) | +Z |

Outras âncoras: `wrist_center` (esq. (−2,05, −0,42, 0), dir. (2,05, 0,43, 0)), `forearm_end`,
`tip_thumb/index/middle/ring/little`. Bounds esq. 9,79 × 3,27 × 3,71 (inclui ~3,6 u de antebraço);
dir. 8,40 × 3,27 × 4,24 (antes 8,56 × 3,40 × 3,13: o polegar aberto aumenta a profundidade).
**57 998 triângulos** cada (29 001 vértices), grade 0,022 u; OBJ 4,3 MB cada; Euler 2; lascas 0.

Âncoras que mudaram na rodada de correção (antes → depois; `palm_center`, `palm_normal`,
`wrist_center`, `forearm_dir`, `forearm_end` iguais a menos de 0,001):
- esquerda (só afunilamento): `tip_index` (4,026, 1,086, −1,097) → (3,992, 1,052, −1,098);
  `tip_middle` (4,277, 1,343, −0,317) → (4,246, 1,304, −0,318); `tip_ring` (3,873, 1,406, 0,436) →
  (3,848, 1,367, 0,437); `tip_little` (2,907, 1,248, 1,054) → (2,889, 1,212, 1,058); `tip_thumb` igual.
- direita (gesto de tecer): `tip_thumb` (−1,804, −1,738, 0,685) → (−1,497, −1,730, 2,424);
  `tip_index` (−4,344, −0,415, 1,381) → (−4,032, −0,938, 1,539); `tip_middle` (−4,138, −1,483,
  0,358) → (−4,121, −1,466, 0,467); `tip_ring` (−3,178, −1,917, −0,429) → (−4,091, −1,068, −0,652);
  `tip_little` (−1,939, −1,692, −0,944) → (−2,846, −1,231, −1,395).

`AuxiliaryHands` lê as pontas do JSON (foco/rótulo), sem constantes a ajustar. Na cena, a esquerda
aponta os dedos para o planeta com a palma para cima e a direita paira sobre ele com a palma para
baixo; ajuste fino girando `palm_normal` para o planeta.

## Geradores em runtime — `src/procedural/` (RefCounted, estáticos, determinísticos)

Convenções: 1 superfície, triângulos indexados com frente horária (Godot), normais unitárias,
UV em [0,1]. Construir uma vez; nunca por frame.

**`HairRibbons`**
- **`nebula(root, direction, seed, tufts := 9, length := 10.0, link_ends := PackedVector3Array(),
  options := {}) -> Dictionary`** (rodada de correção do Loop 4) — o cabelo como **uma massa de
  nebulosa**: todos os fios nascem na **raiz única** (`root_radius` 0,035), saem por `direction`
  (para trás) e sobem numa **curva em S** (o rumo gira para o UP do mundo em `lift` rad ao longo do
  fio, com ondulação em S `s_amount`: sobe, recua, sobe); agrupados em `tufts` **tufos de 5–10 fios**
  (`strands_min/max`) que compartilham o caminho do tufo; **comprimentos variados** (tufo 0,55–1,15 ×
  `length`, fio 0,6–1,0 do tufo); **pontas que se abrem** em filamentos (afastamento quadrático até
  `tip_open` · comprimento do tufo) e onda lateral pequena por fio. Rumos dos tufos distribuídos
  por ângulo num cone de meia-abertura `spread` 0,38 (sem aglomerados). Retorna `{"curves":
  Array[PackedVector3Array], "links": PackedInt32Array, "groups": PackedInt32Array}`.
  **Fios de link**: para cada ponto de `link_ends` (mesmo referencial de `root`) acrescenta um fio
  longo que sai da raiz dentro do tufo cuja ponta aponta mais para o ponto, segue o S do tufo e
  **termina exatamente no ponto** (`link_curve`); `links[i]` é o índice desse fio em `curves`. Uso
  previsto: `link_ends` = início de cada fio de relação (`RelationThreads.HAIR_SOURCES`), assim o
  fio de luz do grafo continua o fio de cabelo. `options` sobrescreve `NEBULA_DEFAULTS`.
  Custo: tufos × ~7,5 fios × `2·(samples−1)` t (×2 cruzado); ex. 10 tufos + 4 links, 56 amostras,
  cruzado ≈ 79 fios × 110 × 2 ≈ 17,4k t.
- `s_path(root, heading, length, points, lift := 0.75, s_amount := 0.42, phase := 0.0)` — o caminho
  em S de um tufo; `link_curve(root, heading, end_point, points := 16, lift, s_amount, phase)` —
  mesmo S na raiz (tangente preservada) com correção suave (smootherstep) até `end_point`.
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
  Parâmetros finais opcionais (compatíveis): `links: PackedInt32Array` (fios de link: mantêm
  `LINK_TIP_RATIO` 0,55 da largura e alfa `LINK_TIP_ALPHA` 0,8 na ponta — o fio de relação continua
  dali; os demais fios somem na ponta como antes) e `groups: PackedInt32Array` (tufo de cada fio).
  **CUSTOM0** (RGBA float, sempre presente) = (1 se fio de link senão 0, tufo / (tufos − 1),
  comprimento do fio / maior fio, 0) — para o shader diferenciar fios de link e variar por tufo
  (`miku_hair` atual só usa `COLOR.a`; a máscara está disponível ao art-director).

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

`tools/sculpt/previews/` (1600×900): 26 PNG de argila — `miku_{front,q34,side,back,low,bust_q34}`,
`miku_head_{face,q34l,sidel}` (frente, ¾ e perfil **no referencial da cabeça**, luz de estúdio),
`miku_head_soft` (luz lateral suave, sombra de penumbra larga), `miku_head_hard` (luz dura quase
frontal, sem fill — expõe qualquer vinco), `miku_hand_left`, `hand_{left,right}_{q34,front,top,
under,low,soft,hard}` — argila neutra × AO do vértice. Estúdio: key quente com sombra, recorte frio
forte, fill fraco. **Provas com o material real** (JPEG): `game_miku_{portrait,face,bust_q34,full,
highside}` e `game_hand_{left,right}_{hero,close}` — `preview/game_look.gd`, rodado **dentro do
projeto principal**: `MaterialLibrary.miku_body()` / `hand_stone()` (veins 0,35) desperto, ambiente
GENESIS (céu de nebulosa, AgX, glow, névoa), rig GENESIS nos níveis despertos (back DUSK_ROSE 2,3,
rim ICE 1,25, key PEARL 1,05 = única sombra, fill NEBULA 0,12, brilho do planeta), no transform do
jogo (`GenesisLayout`); MIKU com a prova do cabelo `HairRibbons.nebula` (2 camadas + 4 fios de link
até `RelationThreads.HAIR_SOURCES`). Diagnóstico: `--shadows=0` (sem a sombra da key) e `--clay=1`;
`diag_sf05_key_shadow_on_off.png` = enquadramento do `sf_05`, com/sem a sombra da key (a mancha
escura do flanco some). `ingame_sf_0{1,2,5}*.jpg`: quadros do jogo real (`tools/style_frames.sh`)
com as malhas desta rodada. ~7 MB no total. Regerar: `tools/sculpt/preview/render_previews.sh
[MESH_DIR] [OUT_DIR]` (projeto Godot descartável próprio em `tools/sculpt/preview/` para a argila,
ignorado pelo projeto principal via `.gdignore`; câmeras em `views.py`).

Sombras das previews = as do jogo (`LightRig`): **PCF** suavizado por `shadow_blur` (dura 1,0,
estúdio 1,8, lateral suave 3,0), `shadow_normal_bias` 2,0, `soft_shadow_filter_quality` 3 e
`light_angular_distance` **sempre 0**. Correção do Loop 4: as previews usavam PCSS (ângulo 6° na luz
suave, 1,5° no estúdio); o PCSS amostra a penumbra com ruído rotacionado por pixel e, num quadro
único sem TAA, esse ruído aparecia como pontilhado/quadriculado regular em toda penumbra (queixo
sobre o pescoço, nariz sobre a bochecha, entre os dedos das mãos gigantes). Diagnóstico: o padrão
continua com AO desligado, some com sombra desligada ou com PCF, e não depende de bias. A malha foi
inspecionada na mesma região (pescoço/mandíbula e bochecha): qualidade de triângulo p1 0,39/0,49,
normal do vértice × normal da face ≥ 0,79 (p0,1), AO sem ruído entre vizinhos. Malhas **não** mudaram.
Lascas de marching cubes (antes: MIKU 26 faces de área ~0 e 20 com normal de vértice oposta à
face; mãos 4–8 e 5–19): tratadas por `clean_slivers` (acima).

Inspeção (rodada de correção do Loop 4, argila + material real + jogo real): MIKU lê como estátua
votiva vestida — cabelo esculpido com mechas onduladas e coque (não lê careca em nenhum ângulo; no
retrato do jogo a massa de cabelo emoldura o rosto sob as fitas), pálpebras/arcada/lábios como
volumes, ombros caídos com clavículas, corpete com cowl e decote, vestido contínuo sem cós; de
perfil o braço não encosta no quadril. Mãos gigantes: dedos afunilados com dorso plano e juntas
discretas, leito de unha; a direita tece (dedos entreabertos em profundidades escalonadas).
Limites conhecidos: sob luz dura/close extremo as cristas das mechas acima da orelha mostram
pequenas facetas (sulco em V + QEM fora da zona de importância máxima); o material atual
(`miku_body`, rim por limiar) contorna toda borda de relevo e serrilha a silhueta — correção do
art-director; a sombra da key em MIKU tem escada — rig (animator/game-engineer); o fim do antebraço
das mãos gigantes depende do fade no pulso de `hand_stone` (art-director).

## Testes — `tests/unit/test_procedural_genesis.gd`

Cabelo-nebulosa: `nebula` determinística por seed, 5–10 fios por tufo, raiz única, todos sobem e
recuam, comprimentos variados (maior/menor > 1,6), pontas abrem (> 3× o afastamento na raiz), S com
≥ 2 inflexões; fios de link terminam exatamente no ponto, saem com a massa, CUSTOM0 marca link/tufo,
fios comuns somem e fios de link ficam visíveis na ponta. Esculturas: carregam como `Mesh` de 1 superfície; triângulos ≤ orçamento (120k / 60k); cor de
vértice presente, cinza e com contraste; normais unitárias; enrolamento coerente com as normais
(< 0,1% de exceções); AABB = `bounds` do JSON; altura de MIKU 5,8–6,2 com a origem dentro; âncoras
presentes, dentro dos bounds e com a orientação do contrato; mãos com origem na palma, corda
pulso→médio 5,6–7,2, palma para cima/baixo, direita não-espelho. Geradores: mesma seed ⇒ mesmos
arrays, seed diferente ⇒ outros; UV em [0,1]; sem degenerados; frente horária; contagens;
tangentes = SurfaceTool; transforms dentro do anel; alfa do cabelo; variantes cruzadas/tubo.
