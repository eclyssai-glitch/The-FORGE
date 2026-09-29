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
plano da lâmina) aponta para fora. `rib_mesh_params()` → `{height: 4,06, width: 0,055, depth: 0,08}`
(cobre da base do anel inferior ao topo do superior + 0,12 de cada lado).

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
2,085 a 3,05); nervura 0,055 × 4,06 × 0,08.

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
