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

## Loop 2 — Motor visual · concluído

- Escopo: ambiente 3D, câmeras cinematográficas, construção procedural, materiais e iluminação,
  efeitos visuais, animação dirigida por eventos, qualidade gráfica aplicada ao mundo.
- Execução (escritor único por área, worktrees isoladas): contratos em `docs/contracts/loop-02.md`;
  Fase A procedural-modeler + art-director; Fase B animator + game-engineer; Fase C revisão/auditoria;
  rodada de correção `docs/contracts/loop-02-fixes.md` (duas etapas).
- Entregue: blueprint de 5 anéis/96 segmentos + 12 nervuras e builders de malha; MaterialLibrary + 6 shaders +
  EnvironmentProfile (luz por estágio, névoa por modo, exposure_scale); 9 módulos (LightRig, câmara, núcleo,
  estrutura, verificação, pulso, poeira, faíscas, CameraDirector) dirigidos por `Simulation.world`+`time`;
  universo (céu procedural, 3 sementes a 62–70 u), Picker, qualidade aplicada ao ambiente/sombras;
  ferramentas com supervisão de processos e checagem de módulos.
- Verificação: `tools/run_tests.sh` 117/117; smoke PASS `modules=9/9` (fonte e pack do .exe); 9 capturas HIGH
  + 9 LOW em `docs/evidence/loop-02/` (README descreve qualidade); probe de robustez de 600 passos sem erros
  nem vazamentos.
- Auditoria: art-director — 1ª revisão REPROVADO → após correção APROVADO COM RESSALVAS (3 P0 resolvidos);
  technical-auditor — APROVADO COM RESSALVAS (9/9 achados anteriores tratados; 2 importantes novos levados ao Loop 3).
- Decisões: ADR-008 (supervisão de processos), ADR-009 (InputTuning), ADR-010 (movimento ambiente).
- Pendências → Loop 3 (`docs/contracts/loop-03.md`): sementes selecionáveis invisíveis no FORGE; UNIVERSE
  subexposto no HIGH e divergência LOW×HIGH; flash/verificação com leitura de grade; reflexo do núcleo; fio da
  banda pontilhado; motes; nervuras longas; `particle()` morto; invalidar cache do LightRig em `world_rebuilt`.
- Retomada: Loop 3, etapa 1 (game-engineer) conforme `docs/contracts/loop-03.md`.

## Loop 3 — Experiência interativa + build Windows · pendente
