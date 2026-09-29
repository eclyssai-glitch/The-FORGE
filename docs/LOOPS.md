# Registro de loops

Dono: coordenador. Responsabilidade: estado persistente de cada loop — entregue, verificado,
pendente e como retomar. Procedimento de fechamento: skill `loop-checkpoint`.

## Loop 1 — Fundação · concluído

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
  - `tools/run_tests.sh`: 30/30 (após correções da auditoria).
  - `tools/smoke_test.sh`: PASS (Forward+, llvmpipe) — 20/20 eventos, 7/7 objetivos, pausa e reset OK.
  - `tools/smoke_test.sh --pack build/windows/KoriumUniverse.exe`: PASS (pacote exato do .exe).
  - Captura `docs/evidence/loop-01/01_dormant_core.png`: pipeline 3D + selo DEMO MODE.
- Limitações registradas: `.exe` não roda no Wine 9.0 do contêiner (ADR-007); repositório novo
  não pôde ser criado pela integração (ADR-006).
- Auditoria: technical-auditor — APROVADO COM RESSALVAS (0 bloqueantes, 2 importantes, 14 menores).
  Corrigidos no loop: `--quality` não persiste mais (`Quality.override_for_session`); skills obsoletas
  do scaffold web arquivado deixaram de ser carregadas (pasta renomeada); smoke com timeout e falha
  por erro de script/sem RESULT; export limpa `build/windows` e gera zip reproduzível; setup com download
  atômico e referência com tipos embutidos; `EventTimeline` ordena a entrada e rejeita velocidade negativa;
  `EntityCatalog.layer_index` valida ids; limiar AUTO respeita a taxa de atualização; ícone do `.exe`;
  `docs/.gdignore`; posse de arquivos completa; docs ENGINE/PROCEDURAL/ANIMATION criados (a preencher
  pelos donos); controles marcados "a partir do Loop 3"; ADR-007 com evidência e cobertura explícita;
  9 testes novos (autoloads, CLI, catálogo, timeline).
  Adiado para o Loop 2 (registrado): núcleo dormente e selo usam EMBER — revisar com o art-director.
- Pendências → Loop 2: motor visual completo (substitui o esqueleto de `world.gd`/`hud.gd`).
- Retomada: iniciar Loop 2 pela Fase A (procedural-modeler + art-director em paralelo, áreas disjuntas),
  contratos de interface registrados na entrada do Loop 2.

## Loop 2 — Motor visual · em andamento

- Escopo: ambiente 3D, câmeras cinematográficas, construção procedural, materiais e iluminação,
  efeitos visuais, animação dirigida por eventos, qualidade gráfica aplicada ao mundo.
- Contratos de interface entre áreas: `docs/contracts/loop-02.md`.
- Plano de execução (escritor único por área, worktrees isoladas por agente):
  - Fase A (paralela): `procedural-modeler` → `src/procedural`; `art-director` → `src/style`.
  - Fase B (paralela, após merge de A): `animator` → `src/entities`, `src/animation`, `src/fx`;
    `game-engineer` → `src/world` (composição, universo, seleção, qualidade no ambiente).
  - Fase C: integração, capturas de todas as fases, revisão do `art-director`, auditoria do
    `technical-auditor`, correções pelos donos, checkpoint.
- Progresso:
  - Fase A concluída e integrada: `procedural-modeler` (89281af — blueprint de 5 anéis/96 segmentos,
    12 nervuras, builders de malha; 34 testes novos) e `art-director` (1453376 — MaterialLibrary, 5 shaders,
    EnvironmentProfile com luz por estágio; regra do selo e do núcleo dormente). Suíte: 57/57.
    Provas visuais revisadas pelo coordenador (estrutura "lanterna" arquitetônica; metal escuro com arcos EMBER finos).
  - Fase B concluída e integrada: `game-engineer` (c4e8eff — world, universo, picker) e `animator`
    (4772814 — 9 módulos, câmera, coreografia). Suíte 105/105; smoke PASS; capturas em `docs/evidence/loop-02/`.
  - Fase C: revisão `art-director` REPROVADO (fase lit escura, arcos como wireframe, sementes dentro da câmara);
    auditoria `technical-auditor` APROVADO COM RESSALVAS (clique×arrasto + 9 menores; robustez de seek/pausa/reset
    confirmada, sem vazamentos). Rodada de correção especificada em `docs/contracts/loop-02-fixes.md`.
  - Contêiner reiniciado durante a 1ª tentativa da rodada (sem trabalho perdido: worktrees vazias removidas).
- Retomada: executar `docs/contracts/loop-02-fixes.md` — etapa 1 (art-director, game-engineer,
  procedural-modeler) → merge → etapa 2 (animator) → merge → recapturar `docs/evidence/loop-02/` →
  reauditoria (art-director + technical-auditor) → checkpoint.

## Loop 3 — Experiência interativa + build Windows · pendente
