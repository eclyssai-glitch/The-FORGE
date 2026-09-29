<!-- Dono: coordenador. Responsabilidade: especificação da rodada final de correção do Loop 3 (histórico). -->
# Loop 3 — rodada final de correção

Origem: revisão final do `art-director` (APROVADO COM RESSALVAS; P1 semente selecionada) e auditoria final do
`technical-auditor` (APROVADO COM RESSALVAS; I-1 scroll atravessa o HUD, I-2 build não registrada, 9 menores).
Evidências de referência: `docs/evidence/loop-03/` (HIGH) e `low/`.

Contrato compartilhado (permite execução paralela): `dormant_seed.gdshader` ganha
`uniform float select : hint_range(0,1) = 0.0`, `uniform vec3 select_color : source_color`, `uniform float select_energy = 0.35`,
com emissão de seleção `select_color * pow(1.0 - nv, 3.0) * select * select_energy`. O `universe.gd` só escreve `select`.

## art-director — `src/style/**`, `src/ui/**`, `tests/unit/test_ui_*.gd`, `docs/VISUAL_DIRECTION.md`
- [P1] Uniform `select`/`select_color`/`select_energy` no `dormant_seed.gdshader`; `MaterialLibrary.dormant_seed()` injeta
  `select_color = Palette.BONE`, `select = 0`. Piso de emissão fria do corpo 0.06 → ~0.03 (corpo quase preto sob exposure 1.5).
- [I-1] Roda do mouse sobre painéis não pode chegar à câmera: `mouse_force_pass_scroll_events = false` em todos os painéis
  STOP (inclui ListRow e o log do OBSERVATORY) + teste.
- [M-4] OBSERVATORY: só o check corrente aparece RUNNING; os seguintes PENDING.
- [P2] OBSERVATORY: detalhe (Body) só no evento mais recente/selecionado, demais em uma linha; margem esquerda 24 px (largura 38%).
- [P2] UNIVERSE: dica de navegação alinhada (mesma altura de linha Caption/Data).
- [P2] Estrutura: `select_px_scale` 1.5→2.0 e `sel_line` atenuada ~50% nas tampas (fio pleno na parede externa).
- [P2] Piso: `edge_fade` (raio 0.85→1.0) levando albedo/especular a zero na borda do disco.
- [M-9] Sombra no LOW: manchas no topo dos anéis — ajustar bias/perfil em `EnvironmentProfile`/materiais (ou pedir ao animator).

## game-engineer — `src/world/**`, `src/core/**`, `src/events/**`, `tools/**`, `tests/integration/**`, testes/docs próprios
- [P1] `universe.gd._apply_highlight`: só `set_shader_parameter("select", h)`; `cold_color`/`cold_energy` fixos no repouso;
  remover uso direto de `Palette.BONE/ASH` no corpo; `HALO_STRENGTH_SELECTED` 0.6→0.3. Ajustar teste.
- [M-2] Picker: limpar `Session.hovered` quando o cursor entra num Control que consome o mouse (ex.: checar
  `get_viewport().gui_get_hovered_control()` no movimento, ou limpar em `mouse_exited` do viewport 3D) + teste.
- [P2] Vocabulário: "ONLINE" → "ACTIVE" (status do núcleo) e fase "CORE ONLINE" → "CORE STABLE"; nomes internos podem
  ficar; atualizar testes próprios e `docs/DEMO_EVENTS.md`. Relatar se algum teste de UI (art-director) cita "ONLINE".
- Evidências: automação ganha `13_hud_hidden` (t=49, FORGE, `Session.set_hud_visible(false)` — o selo deve continuar) e
  `tools/capture_evidence.sh` aceita `--resolution=WxH` (padrão 1600x900) para o conjunto 1280×720.

## animator — `src/animation/**`, `src/entities/**`, `src/fx/**`, testes/docs próprios
- [M-1] Aplicar `clamp_shot` ao rig **depois** do blend (câmera nunca abaixo de piso + folga, inclusive em transições) + teste.
- [M-3] Fio pontilhado da banda de verificação no lado de trás (sobretudo LOW) — eliminar (largura mínima em px / ordem de desenho).
- [M-5/P2] Plano UNIVERSE: as 3 sementes dentro de x∈[310,1270], y∈[70,680] em 1600×900 (fora do painel SITES e da barra de modos),
  mantendo o vão entre pilares (ex.: yaw TAU*3/24, pitch ~0.36) + teste.
- [P2] Plano OBSERVATORY: pitch 0.62→~0.45, distância 14.5→~15.5 (paredes dominam as tampas; mesmo material lido no FORGE).

## coordenador
- README (controles atuais, V/H), mapa de posse com `tests/unit/test_ui_*.gd`, registro da build (via game-engineer em
  `docs/BUILD.md` após o commit final), LOOPS, checkpoint.
