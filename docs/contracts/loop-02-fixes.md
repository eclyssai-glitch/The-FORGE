<!-- Dono: coordenador. Responsabilidade: especificação da rodada de correção do Loop 2 (histórico). -->
# Loop 2 — rodada de correção

Origem: revisão visual do `art-director` (REPROVADO: fase lit escura, arcos finais como wireframe,
sementes dentro da câmara) e auditoria do `technical-auditor` (APROVADO COM RESSALVAS: clique×arrasto
e 9 menores). Capturas de referência: `docs/evidence/loop-02/`.

Execução em duas etapas: (1) art-director, game-engineer e procedural-modeler em paralelo;
(2) animator, depois do merge de (1), porque consome `exposure_scale`, `InputTuning` e `shadow_splits`.
Valores são pontos de partida; o dono ajusta pela imagem e registra o valor final no código.

## art-director — `src/style/**`, `docs/VISUAL_DIRECTION.md`

- **P0-1 Metal acabado apaga a fase lit**: `structure()` finished_color → `Palette.SLATE.lerp(Palette.ASH, 0.3)`;
  `structure.gdshader` METALLIC `mix(0.0,0.74,f)`→`mix(0.0,0.5,f)`, ROUGHNESS `mix(0.9,0.44,f)`→`mix(0.9,0.34,f)`;
  `make_environment()` explícito `reflected_light_source = REFLECTION_SOURCE_SKY`. Se a fase lit seguir escura:
  `LIGHT.lit.key` 1.5→1.9, `lit.exposure` 1.0→1.1.
- **P0-3 Arcos finais como wireframe**: termo `final_lock` restrito à parede externa, borda superior
  (normal em mundo via varying; `outer = smoothstep(0.8,0.95,dot(normalize(n.xz),normalize(v_world.xz)))*(1-abs(n.y))`,
  combinado com a borda de v correta — ver orientação de UV em `src/procedural/mesh_builder.gd`) → um anel por camada;
  `lock_edge_share` 0.32→0.5.
- **P1-6 UNIVERSE**: `mode_fog(UNIVERSE)` fog_depth_begin 24→45, end 150→220; chave `"exposure_scale"` em todos
  os modos (UNIVERSE 1.25, FORGE 1.0, OBSERVATORY 1.0); `apply_mode_fog` ignora chaves que não são propriedades do Environment.
- **P1-8 Poeira quadrada**: `particle()` → ShaderMaterial com `src/style/shaders/particle_mote.gdshader`
  (unshaded, blend_add, billboard de partículas, `ALPHA = COLOR.a * smoothstep(0.5, 0.15, length(UV - 0.5))`, sem TIME),
  cache por cor.
- **P1-9 PALE floresce**: `scan_ring().intensity` 1.8→1.0; `glow_hdr_threshold` 1.1→1.25.
- **P1-10 Flash vira grade**: uniform separado `flash_edge_energy = 1.2` para o flash `g`.
- **Docs**: sementes "além da câmara, 60–70 u"; remover pedido já atendido da luz âmbar do world.gd;
  "5 MultiMesh + nervuras" (não um único draw); estágio `active` vai até LIGHTING_APPLIED; registrar
  `exposure_scale` e o material de partícula.

## game-engineer — `src/world/**`, `src/core/**`, `tools/**`, `tests/integration/**`, docs próprios

- **P0-2 Reflexo**: `universe_sky.gdshader` AT_CUBEMAP_PASS → `void_color + band_color*radiance_lift*smoothstep(-0.1,0.8,EYEDIR.y)`,
  `radiance_lift = 0.05`; corrigir comentário "rendered once".
- **P0-4 Sementes**: aurel r62/−100°/h8; vesper r70/150°/h−1; lattice r66/205°/h14; `size` ×2.
- **P1-11 Estrelas por modo**: `star_intensity` UNIVERSE 0.55 · FORGE 0.22 · OBSERVATORY 0.3; `faint_density` 0.045→0.03.
- **P2-14 Sementes**: `HALO_STRENGTH` 0.32→0.18; sem anel vertical na forma `armillary`.
- **IMPORTANTE clique×arrasto**: `src/core/input_tuning.gd` (`class_name InputTuning`, `const DRAG_THRESHOLD_PX := 4.0`);
  Picker usa percurso acumulado; teste: ida-e-volta de 160 px não seleciona, 3 px seleciona.
- **MENOR módulos**: smoke falha se algum módulo de `World.MODULES` não carregou (`modules=N/N`).
- **MENOR sombras LOW**: chave `"shadow_splits"` em `quality_profiles.gd` (LOW 2, demais 4) + teste.
- **Docs**: ENGINE.md (sementes, picking, shadow_splits, validação de módulos).

## procedural-modeler — `src/procedural/**`, testes e doc próprios

- `docs/PROCEDURAL.md`: orçamento real por consumidor (anel/banda de verificação usam 160 segmentos), medido
  com as próprias funções; teste da fórmula de triângulos de `MeshBuilder.ring` (128 e 160 segmentos).

## animator — `src/entities/**`, `src/animation/**`, `src/fx/**`, testes e doc próprios (etapa 2)

- **P1-5 Plano UNIVERSE**: `camera_shots.gd` yaw 0.62→0.524 (entre pilares), distance 52→90, pitch 0.38→0.32,
  fov 44→40 (limites de distância já cobrem); ajustar para as sementes a 60–70 u.
- **P1-6**: LightRig multiplica `tonemap_exposure` por `EnvironmentProfile.mode_fog(Session.mode).get("exposure_scale", 1.0)`.
- **P1-7**: `core.omni_range` 8→12 (validar no FORGE).
- **P1-8 Poeira**: `MAX_AMOUNT` 600→220, `quad.size` 0.024→0.014, `scale_max` 1.4→1.0, `NEAR_FADE` (2,5)→(3.5,8),
  alfa da rampa 0.2→0.12.
- **P1-9**: `verification_array.gd` `BAND_LEVEL` 0.7→0.5, `BAND_WIDTH` 0.24→0.16.
- **P2-12/13/16 luz**: `core.omni_attenuation` 1.5→2.2; `core.light_specular` 0.6→0.35;
  `key.shadow_normal_bias` 2.0, `key.shadow_blur` 1.8; `key.directional_shadow_mode` a partir de
  `Quality.profile.get("shadow_splits", 4)`.
- **IMPORTANTE clique×arrasto**: câmera usa `InputTuning.DRAG_THRESHOLD_PX` (percurso acumulado).
- **MENOR**: LightRig só escreve no Environment quando o valor muda (cache); `segment_state()` função de
  (world, time) também antes de FRAGMENTS_EMITTED; piso não é selecionável como `origin_chamber`
  (clique no vazio limpa seleção); ANIMATION.md referencia constantes do código em vez de duplicar tabelas
  e remove a nota desatualizada sobre "cena de prova".
