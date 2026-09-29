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

## Loop 3 — Experiência interativa + build Windows · concluído

- Escopo: UNIVERSE / FORGE / OBSERVATORY integrados, UI nativa, ORIGIN CHAMBER jogável de ponta a ponta,
  DEMO MODE sempre identificado, build Windows validada. Contratos: `docs/contracts/loop-03.md` e
  `docs/contracts/loop-03-fixes.md`.
- Entregue:
  - game-engineer: atalhos (Espaço/R/1/2/3/V/H/Esc/C/F11), `Session.focus`/`hud_visible`/`entity_group`,
    automação com capturas 01–13 e `--resolution`, smoke que exige UI nativa, seleção das sementes só no UNIVERSE,
    hover limpo sobre a UI, vocabulário ACTIVE/CORE STABLE, export determinístico (ADR-012), build registrada.
  - art-director: HUD nativo completo (selo DEMO MODE BONE sempre visível, barra de modos, transporte com timeline
    marcada por fases e velocidades, feed, inspector com FOCUS, painéis por modo, OBSERVATORY com missão/verificações/
    entidades/log, configurações de qualidade e câmera), isolamento da roda do mouse, uniform de seleção das sementes,
    piso com borda dissolvida, conciliação LOW×HIGH.
  - animator: foco de câmera em qualquer entidade (ADR-011), planos UNIVERSE/OBSERVATORY cientes da UI, câmera sempre
    acima do piso inclusive em transições, banda de verificação contínua, poeira, sombras no LOW.
  - procedural-modeler: nervuras rentes à pilha.
- Verificação: `tools/run_tests.sh` 182/182; smoke com UI obrigatória PASS (fonte e pack); build final do commit
  `214a02a` (zip `26af2ef5…c1e95f`, exe `a4fcdc5b…ec6a81`) reproduzida em checkouts limpos pelo game-engineer e pelo
  auditor; evidências 13 HIGH + 13 LOW + 13 em 1280×720 em `docs/evidence/loop-03/`; probe com HUD 678 checks sem falhas
  nem vazamentos.
- Auditoria: art-director APROVADO COM RESSALVAS (P1 resolvido na rodada final); technical-auditor — auditoria final
  APROVADO COM RESSALVAS → fechamento APROVADO COM RESSALVAS (0 bloqueantes, 0 importantes; critérios 1–8 atendidos
  no contêiner).
- Decisões: ADR-011 (transições de câmera no relógio de parede), ADR-012 (export determinístico).
- Limitação: execução nativa do `.exe` no Windows depende de validação local (ADR-007; checklist em `docs/BUILD.md`).
- Backlog (próxima versão, todos MENOR):
  - animator: em 1280×720 o painel EVENTS cobre ~40 px da ponta da banda PALE (captura `720p/06`) — plano FORGE ciente da UI em 720p.
  - art-director: traços brancos curtos nas tampas da camada selecionada no LOW (`low/10`).
  - animator/procedural: guias de construção pontilhadas no LOW (`low/04`, geometria subpixel sem MSAA).
  - animator/art-director: degrau suave residual na sombra do anel inferior no LOW.
  - Validar o `.exe` numa máquina Windows e registrar o resultado em `docs/BUILD.md`.
- Retomada: versão 0.1.0 concluída; próximos passos dependem de decisão de produto (novo conteúdo além da ORIGIN CHAMBER).

## Vídeo-review v0.1.0 · concluído

- Especificação e roteiro: `docs/contracts/review-video.md`.
- animator: `MotionClock` (relógio de movimento que segue o tempo do jogo no Movie Maker; ADR-011 vale fora dele).
- game-engineer: `tools/review/review_tour.*` (tour roteirizada com interações reais pela UI, legendas PT-BR,
  cartões de título/veredito; fora do export) e `tools/record_review.sh` (Movie Maker 30 fps → ffmpeg H.264).
- Resultado: `build/review/korium_universe_review_v0.1.0.mp4` — 1600×900, 30 fps, 2 min 13 s (3 991 quadros),
  17,5 MB, sem áudio; gravado em 26 min por renderização em software (Forward+, HIGH). Não versionado (build/).
  Quadros conferidos em todos os trechos do roteiro. Reproduzir: `tools/record_review.sh`.
- Verificação: `tools/run_tests.sh` 193/193.

## Loop 4 — ART DIRECTION RESET · em andamento

- Motivo: v0.1.0 aprovada tecnicamente, **reprovada na direção artística** (parece protótipo técnico; sem VFX/SFX
  memoráveis). Nova visão: MIKU (agente central original) suspensa no espaço, mãos auxiliares gigantes formando
  corpos celestes, planetas = subagentes, luas = documentação, anéis = skills, cinturões = memória, lógica
  relacional de vault em astronomia visual; estética contemplativa, cósmica, poética, cinematográfica.
- Brief e contratos: `docs/contracts/loop-04.md`. Novos agentes: `sound-designer`, `art-critic` (somente leitura).
  Decisão: ADR-013 (escultura/áudio offline, venv `/opt/korium-py`).
- Arquitetura congelada e reaproveitada: `Simulation`/`Session`/`Quality`, padrão `EventTimeline`/estado derivado,
  automação/smoke/capturas, export determinístico. Estética v0.1 (câmara, anéis, HUD de painéis) substituível.
- Fases: A (postmortem + bíblia + shaders · esculturas · áudio · eventos GENESIS) → B (cena animada, VFX, câmeras,
  UI diegética, mixagem) → C (virada para GENESIS, style frames, capturas, vídeo com áudio, art-critic +
  technical-auditor, correções, export, checkpoint).
- Retomada: ver o estado das fases abaixo; worktrees de agentes interrompidos sem commits podem ser removidas e
  relançadas a partir do contrato.
- Estado: Fase A — game-engineer integrado (`e854114`, 217/217, smoke PASS nos dois cenários; ADR-014);
  art-director e sound-designer integrados (245/245); procedural-modeler em andamento.
