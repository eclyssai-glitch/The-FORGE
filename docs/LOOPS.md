# Registro de loops

Dono: coordenador. Responsabilidade: estado persistente de cada loop — entregue, verificado,
pendente e como retomar. Procedimento de fechamento: skill `loop-checkpoint`.

## Loop 1 — Fundação · em andamento (aguardando auditoria independente)

- Escopo: ambiente, Godot + ferramentas, projeto independente, pesquisa, agentes/skills,
  sistema básico de cenas, sistema de eventos, exportação Windows.
- Entregue:
  - Godot 4.7.2-stable (editor Linux + templates Windows/Linux x86_64) com SHA512 verificado;
    referência de classes offline via `--doctool`; `tools/setup_godot.sh` idempotente.
  - Projeto `project.godot` (Forward+, fallbacks D3D12/OpenGL, input map, autoloads).
  - Eventos puros: `SimEvent`, `OriginChamberScript` (20 eventos, 50 s), `EventTimeline`,
    `WorldState`, `Mission` (7 objetivos), `EntityCatalog`.
  - Autoloads `Simulation`, `Session`, `Quality` (perfis LOW→ULTRA, AUTO por GPU + queda por FPS).
  - Cenas `main` / `world` / `hud` (esqueleto), automação `--smoke-test`, `--capture=`, `--quality=`.
  - 5 agentes (`art-director`, `game-engineer`, `procedural-modeler`, `animator`,
    `technical-auditor`), 3 skills (`game-verification`, `loop-checkpoint`, `demo-events`),
    hook SessionStart para a nuvem.
  - Export Windows (`tools/export_windows.sh`) com zip + SHA-256 e licenças.
- Verificação:
  - `tools/run_tests.sh`: 21/21 (423 asserts).
  - `tools/smoke_test.sh`: PASS (Forward+, llvmpipe) — 20/20 eventos, 7/7 objetivos, pausa e reset OK.
  - `tools/smoke_test.sh --pack build/windows/KoriumUniverse.exe`: PASS (pacote exato do .exe).
  - Captura `docs/evidence/loop-01/01_dormant_core.png`: pipeline 3D + selo DEMO MODE.
- Limitações registradas: `.exe` não roda no Wine 9.0 do contêiner (ADR-007); repositório novo
  não pôde ser criado pela integração (ADR-006).
- Auditoria: ver entrada abaixo.
- Pendências → Loop 2: motor visual completo (substitui o esqueleto de `world.gd`).

## Loop 2 — Motor visual · pendente

## Loop 3 — Experiência interativa + build Windows · pendente
