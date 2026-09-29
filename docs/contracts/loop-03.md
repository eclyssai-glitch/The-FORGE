<!-- Dono: coordenador. Responsabilidade: contratos de interface entre áreas no Loop 3 (histórico; a API vigente é a do código). -->
# Loop 3 — Experiência interativa + build Windows

Objetivo: primeira versão jogável. Três ambientes integrados (UNIVERSE, FORGE, OBSERVATORY) sobre o
mesmo mundo 3D, UI nativa (nós `Control` + `Theme`), ORIGIN CHAMBER controlável de ponta a ponta,
DEMO MODE sempre identificado, build Windows validada.

Regras que continuam: UI e 3D só conversam por autoloads (`Simulation`, `Session`, `Quality`);
UI nunca referencia nós 3D; cores/tempos de `Palette`; nada sugere conexão real; sem assets externos.

## Etapa 1 — game-engineer (antes das demais: publica API usada por UI e câmera)

`src/core/session.gd`:
- `signal focus_requested(id: StringName)` e `func focus(id: StringName) -> void` (emite sempre, mesmo repetido).
- `signal panel_toggled(panel: StringName, visible: bool)` não é necessário — painéis são estado da UI.

`src/core/shortcuts.gd` (novo nó adicionado por `main.gd`), `_unhandled_input`, ações já no `project.godot`:
- `demo_toggle` → `Simulation.toggle()`; `demo_reset` → `Simulation.reset()`;
- `mode_universe/forge/observatory` → `Session.set_mode(...)`; `deselect` → `Session.select(&"")`;
- `toggle_fullscreen` (mover de `main.gd`). Nova ação `toggle_cinematic` (tecla `V`) → `Session.set_cinematic(!...)`;
  nova ação `toggle_hud` (tecla `H`) — só emite `Session.hud_visibility_changed(visible)` (novo sinal + `var hud_visible := true`).
- Não consumir teclas quando um `LineEdit`/`Slider` da UI tem foco (ver `get_viewport().gui_get_focus_owner()`).

`src/core/automation.gd`: capturas passam a incluir o HUD real (já incluem, pois capturam o viewport). Novas capturas:
`10_forge_inspector` (t=30.5, FORGE, `Session.select(&"layer_2")`), `11_observatory_mid` (t=37, OBSERVATORY),
`12_universe_seed_focus` (t=49, UNIVERSE, `Session.select(&"seed_aurel")` + `Session.focus(&"seed_aurel")`).
Smoke: além do atual, exercitar a UI: localizar nós por grupo `"ui_transport"` e acionar os botões
(start → pause → reset) via `pressed.emit()` e verificar `Simulation.status`; exigir que exista um nó no grupo
`"demo_badge"` visível com texto contendo "DEMO".

Testes de integração do fluxo: atalhos alteram estado; foco emite sinal; UI não quebra em headless.
Docs: `docs/ENGINE.md`/`ARCHITECTURE.md` (Shortcuts, focus, hud_visible).

## Etapa 2 (paralela) — art-director (UI) e animator (câmera/entidades)

### art-director → `src/ui/**`, `src/style/**` (tema), `scenes/hud.tscn` NÃO (cena é do game-engineer; o HUD
é construído em código a partir de `src/ui/hud.gd`, que já é o script da cena)

HUD nativo em `src/ui/` (dividido em componentes: `ui_theme.gd` (Theme a partir de Palette + fontes),
`demo_badge.gd`, `mode_bar.gd`, `transport.gd`, `event_feed.gd`, `inspector.gd`, `forge_panel.gd`,
`observatory_panel.gd`, `universe_panel.gd`, `settings_menu.gd`):
- **Selo DEMO MODE** (grupo `"demo_badge"`): BONE em Plex Mono sobre PANEL, sempre visível em todos os modos.
- **Barra de modos** UNIVERSE / FORGE / OBSERVATORY (+ atalhos 1/2/3 exibidos discretamente).
- **Transporte** (grupo `"ui_transport"`, botões com `name` `Start`, `Pause`, `Reset`): iniciar/pausar/reiniciar,
  linha do tempo arrastável (`Simulation.seek`) com marcas das fases (dos tempos de `OriginChamberScript`/eventos),
  tempo `T+00.0 / 50.0`, fase atual (`WorldState.phase_name()`), velocidade (0.5×/1×/2×/4× → `Simulation.set_speed`).
- **Feed de eventos**: últimos eventos com `format_time()` + label; reconstrói em `world_rebuilt`.
- **Inspector** (quando `Session.selected` ≠ vazio): `EntityCatalog.info` + `status(Simulation.world)`, eventos
  relacionados (`event.entity == id`), botão "Focus" → `Session.focus(id)`.
- **FORGE**: lista das 5 camadas com status (clicável → select), núcleo, verificação.
- **OBSERVATORY**: painel à esquerda (~38%): missão (`Mission.evaluate`, objetivos ✓), log completo de eventos
  (rolável), resultados (checks com tempo, status das entidades, progresso %), rótulo "Simulated data".
- **UNIVERSE**: lista de sítios (ORIGIN CHAMBER + 3 sementes DORMANT) clicável → select + focus; dica de navegação (WASD/arrastar).
- **Configurações**: qualidade (AUTO/LOW/MEDIUM/HIGH/ULTRA → `Quality.set_auto/set_level`), câmera cinematográfica (on/off).
- Respeitar `Session.hud_visible`. Transições de modo com Tween (Palette.T_*). Texto mínimo, rótulos curtos.
- Não interceptar input 3D fora dos painéis (`mouse_filter` correto) para não quebrar órbita/picking.
Doc: `docs/VISUAL_DIRECTION.md` (seção UI).

### animator → `src/animation/**`, `src/entities/**`, `src/fx/**`
- `CameraDirector` escuta `Session.focus_requested(id)`: enquadra a entidade (núcleo, camada i, verificação,
  câmara, sementes em `Universe.seed_base_position` — posições via grupo/nó? usar `get_tree().get_nodes_in_group("entity_" + id)`)
  com Tween; em FORGE/OBSERVATORY limita ao alvo da câmara; suspende deixas como input do usuário.
- Cada entidade selecionável entra no grupo `"entity_<id>"` (a raiz visual da entidade) para foco.
- OBSERVATORY: plano deixa ~38% à esquerda livre (já existe) — ajustar se o painel real cobrir o sujeito.
Doc: `docs/ANIMATION.md`.

(game-engineer: sementes em `universe.gd` entram no grupo `"entity_<id>"` — incluir na etapa 1.)

## Etapa 3 — integração, build Windows, auditoria

Coordenador: merge, `tools/run_tests.sh`, `tools/smoke_test.sh`, capturas 01–12 em `docs/evidence/loop-03/`,
`tools/export_windows.sh`, smoke do pack, registro em `docs/BUILD.md` (zip + SHA-256 + commit),
revisão `art-director` + auditoria `technical-auditor`, correções pelos donos, checkpoint, README/PRODUCT.
