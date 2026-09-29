<!-- Dono: coordenador. Responsabilidade: contratos de interface entre áreas no Loop 2 (histórico; a API vigente é a do código). -->
# Loop 2 — Contratos de interface (motor visual)

Projeto: /home/user/The-FORGE (Godot 4.7.2, GDScript tipado). Leia CLAUDE.md, docs/ARCHITECTURE.md,
docs/VISUAL_DIRECTION.md, docs/DEMO_EVENTS.md e src/events/*.gd, src/core/*.gd, src/style/palette.gd antes.
Referência de classes oficial offline: /opt/godot/doc/doc/classes/<Classe>.xml — confira toda API antes de usar.
Coordenadas: Y para cima; núcleo suspenso na origem (0, 0, 0); piso da câmara em y = -3.2.
Fatos fixos: OriginChamberScript.LAYER_COUNT = 5, FRAGMENT_COUNT = 96, CHECKS = 4 (integrity, alignment, load, resonance).
Tempos dos eventos: src/events/origin_chamber_script.gd (não duplicar números: leia sempre de Simulation.world).

## A. procedural-modeler → src/procedural/

### class_name StructureBlueprint (RefCounted) — src/procedural/structure_blueprint.gd
Dados puros, determinísticos. Forma: um "vaso" de anéis segmentados empilhados em torno do núcleo
(silhueta de lente/ampulheta suave), cada anel = N segmentos de coroa circular (annular sector).
- `static func build(layer_count: int = 5, seed: int = 7) -> StructureBlueprint`
- `var layers: Array[Dictionary]` — por camada: `{"index", "y", "height", "radius_inner", "radius_outer",
  "segment_count", "gap" (radianos entre segmentos), "twist" (rad, rotação de montagem que vai a 0 na forma final),
  "phase" (rad, offset angular de cada anel)}`. Contagens somam exatamente 96 (ex.: 16,20,24,20,16).
  y de baixo (≈ -2.0) para cima (≈ +2.0), núcleo (raio ≈0.55) no centro da camada do meio; raio interno
  mínimo > 1.1 (não intersecta o núcleo); raio externo ≤ 3.2.
- `func segment_count_total() -> int`
- `func segment_layer(i: int) -> int` e `func segment_index_in_layer(i: int) -> int` (i global 0..95, ordem por camada)
- `func segment_transform(i: int, twist_amount: float = 0.0) -> Transform3D` — transform final do segmento i
  (rotação em Y para seu ângulo + phase + twist*layer.twist, translação em y). A malha do segmento é centrada no
  ângulo 0 (ver MeshBuilder), então o transform é só rotação em Y + altura.
- `func segment_mesh_params(layer: int) -> Dictionary` → parâmetros para MeshBuilder.annular_segment desta camada.
- `func scatter_transform(i: int) -> Transform3D` — posição/rotação "fragmento solto" determinística
  (casca esférica raio 3.2–5.0 ao redor do núcleo, rotação aleatória, escala 0.35–0.6).
- `func rib_transforms() -> Array[Transform3D]` — nervuras verticais finas que aparecem na forma final ligando
  as camadas (8–12 nervuras) + `rib_mesh_params()`.

### class_name MeshBuilder (RefCounted) — src/procedural/mesh_builder.gd  (static funcs, retornam ArrayMesh)
- `annular_segment(r_in, r_out, height, angle_span, arc_steps := 6) -> ArrayMesh` — setor de coroa com
  faces superior/inferior/interna/externa/laterais, normais corretas (flat nas arestas), UV: u ao longo do arco 0..1,
  v 0..1 (radial nas tampas, vertical nas paredes). Centrado no ângulo 0 (eixo +Z... documente), base y=-h/2..h/2.
- `icosphere(radius, subdivisions, flat := true) -> ArrayMesh` — casca facetada do núcleo.
- `ring(radius, thickness, width, segments := 128) -> ArrayMesh` — anel fino (fita/torus de seção retangular),
  para anel de verificação, halos e anéis do piso.
- `rib(height, width, depth) -> ArrayMesh` — lâmina vertical afilada (topo e base mais finos).
- `shard(size, seed) -> ArrayMesh` — estilhaço irregular (tetra/prisma) para faíscas de emissão.
Testes: tests/unit/test_procedural_blueprint.gd, test_procedural_meshes.gd (contagens, soma 96, determinismo por seed,
raios/limites, AABB, normais unitárias, sem triângulos degenerados, transform final vs scatter).
Doc: docs/PROCEDURAL.md (formas, parâmetros, contagens de triângulos).

## B. art-director → src/style/

### class_name MaterialLibrary (RefCounted) — src/style/material_library.gd
Materiais compartilhados (cache estático; mesma instância a cada chamada):
- `structure() -> ShaderMaterial` com shader `src/style/shaders/structure.gdshader` (spatial). Usado por um MultiMesh
  com `use_custom_data = true`. Por instância (INSTANCE_CUSTOM): `r` = montagem 0..1 (0 = fragmento bruto solto,
  1 = assentado), `g` = flash de verificação 0..1, `b` = destaque de seleção/hover 0..1, `a` = energia de construção 0..1
  (brilho EMBER nas arestas durante a montagem). Uniformes globais do material:
  `finish` (0 bruto → 1 acabado: de cinza fosco claro para metal escuro com arestas finas), `scan_y` (y mundial da
  varredura), `scan_strength` (0..1, banda PALE), `final_lock` (0..1, arestas EMBER discretas e contínuas na forma final),
  `energy` (0..1 global). Arestas via UV (bordas do u/v) — sem textura externa.
- `core_shell() -> ShaderMaterial` (facetado escuro, fresnel BONE sutil; uniforme `energy` 0..1),
  `core_heart() -> ShaderMaterial` (emissivo EMBER; uniforme `energy` 0..1 e `pulse` 0..1),
  `scan_ring() -> ShaderMaterial` (PALE emissivo, `strength`), `halo() -> ShaderMaterial` (anel emissivo sutil, `color`, `strength`),
  `floor() -> StandardMaterial3D` (quase preto, rugoso, leve reflexo), `architecture() -> StandardMaterial3D` (pilares/colunas),
  `dormant_seed() -> ShaderMaterial` (semente fria, `energy`), `particle(color: Color) -> StandardMaterial3D` (unshaded, additive, billboard).
- Todas as cores de `Palette`. Nada de texturas externas.

### class_name EnvironmentProfile (RefCounted) — src/style/environment_profile.gd
- `static func make_environment() -> Environment` — fundo VOID, AgX, glow contido (sem estouro), fog de profundidade,
  volumetric fog tênue (densidade baixa, albedo frio, sem névoa "leitosa"), SSAO moderado, ajuste de contraste leve.
- `static func apply_quality(env: Environment, profile: Dictionary) -> void` — liga/desliga ssao/ssil/glow/volumetric_fog
  conforme `profile` (chaves em src/world/quality_profiles.gd); com volumetric off, compensar com fog de profundidade.
- `const LIGHT` — Dictionary com níveis por estágio: `"dormant"`, `"active"`, `"lit"`, `"verify"`, `"final"`, cada um
  `{"key": energia, "fill": ..., "rim": ..., "core": ..., "ambient": ..., "exposure": ..., "fog": densidade volumétrica}`
  + cores: `KEY_COLOR`, `FILL_COLOR`, `RIM_COLOR` (derivadas de Palette).
- `static func mode_fog(mode: int) -> Dictionary` — ajustes de névoa/profundidade por modo (UNIVERSE vê longe).
Doc: docs/VISUAL_DIRECTION.md (atualizar: materiais, luz por estágio, justificativas).

## C. animator → src/animation/, src/entities/, src/fx/  (Fase 2)

Todas as entidades: `class_name X extends Node3D`, construtor sem argumentos, constroem filhos em `_ready`,
leem `Simulation.world`/`Simulation.time`, escutam `Simulation.world_rebuilt` quando precisarem ressincronizar e
`Quality.profile_changed` para custo. Seleção: cada entidade selecionável tem um `StaticBody3D` filho com
`CollisionShape3D` e `set_meta("entity_id", StringName)` (layer 1 de colisão = 2, "pickable"). Destaque de seleção:
ler `Session.selected` / `Session.hovered`.
- `OriginCore` (src/entities/origin_core.gd), `FragmentStructure` (src/entities/fragment_structure.gd) — MultiMesh
  com 96 instâncias (uma por segmento do blueprint): oculto → espalhado (fragmentos) → montagem por camada → acabamento
  → flashes de verificação → trava final (twist→0) + nervuras; colliders por camada (`layer_i`) e `fragment_field`.
  `VerificationArray` (src/entities/verification_array.gd) — anel que varre y e alimenta `scan_y/scan_strength` do material.
  `ChamberArchitecture` (src/entities/chamber_architecture.gd) — piso, anel de pilares (MultiMesh), óculo; colisor `origin_chamber`.
  `LightRig` (src/entities/light_rig.gd) — luzes key/fill/rim/core; interpola `EnvironmentProfile.LIGHT` por estágio segundo
  os eventos; recebe `environment: Environment` via propriedade para ajustar ambient/exposure/fog.
- `src/fx/`: `ActivationPulse` (onda em anel na ativação e na forma final), `DustField` (GPUParticles3D esparso,
  `amount` × Quality.profile.particles), `EmissionSparks` (explosão curta quando fragmentos são emitidos).
- `CameraDirector` (src/animation/camera_director.gd, Node3D com Camera3D filha `current = true`):
  rig órbita (target, yaw, pitch, distance, fov); input: arrastar botão esquerdo/direito = orbitar, roda = zoom,
  WASD = voar (UNIVERSE), `camera_reset` = volta ao plano do modo; planos por modo (`CameraShots` em
  src/animation/camera_shots.gd, dados puros testáveis) e deixas por evento quando `Session.cinematic`
  (ativação: aproximação; fragmentos: recuo; verificação: ângulo baixo; final: órbita lenta de revelação).
  Input do usuário suspende deixas por ~6 s. Transições com Tween (tempo real, Palette.T_CINEMATIC).
  Em `Simulation.world_rebuilt` (seek) salta direto para o plano do estado atual sem tween.
  Expor `func snap_to_mode_shot() -> void` (usado pela automação de captura).

## D. game-engineer → src/world/  (Fase 2)
- `world.gd`: compõe WorldEnvironment (EnvironmentProfile), LightRig, ChamberArchitecture, OriginCore, FragmentStructure,
  VerificationArray, fx, Universe, CameraDirector e Picker; aplica `EnvironmentProfile.apply_quality` em
  `Quality.profile_changed`; névoa por modo em `Session.mode_changed`.
- `universe.gd` (class Universe): céu procedural (estrelas esparsas e frias, sem nebulosa colorida), 3 sementes
  dormentes (seed_aurel/vesper/lattice) a 18–30 unidades com colisores, faixa de poeira distante.
- `picker.gd` (class Picker): raycast da câmera no clique/hover (máscara de colisão 2) → `Session.select/hover`;
  clique no vazio limpa seleção; ignora eventos consumidos pela UI.
