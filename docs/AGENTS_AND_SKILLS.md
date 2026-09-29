# Agentes e skills

Dono: coordenador. Responsabilidade: quem escreve o quê, e quais procedimentos reutilizáveis existem.
Definições oficiais: `.claude/agents/*.md` (subagentes do Claude Code) e `.claude/skills/*/SKILL.md`
(formato Agent Skills).

## Agentes (escritor único por área)

| Agente | Especialização | Escreve em |
|---|---|---|
| `art-director` | Direção artística, bíblia visual, materiais/shaders (inclui céu de nebulosa), ambiente de luz, UI nativa | `src/style/**`, `src/ui/**`, `tests/unit/test_ui_*.gd`, `tests/unit/test_style_*.gd`, `assets/fonts/**`, `icon.svg`, `icon.png`, `docs/VISUAL_DIRECTION.md`, `docs/art/**` |
| `game-engineer` | Engenharia de jogos 3D, eventos, mundo, qualidade, build | `project.godot`, `export_presets.cfg`, `scenes/**`, `src/core/**`, `src/events/**`, `src/world/**`, `tools/**` (exceto `tools/sculpt/**` e `tools/audio/**`), `tests/integration/**`, `tests/unit/test_event_system.gd`, `tests/unit/test_quality_profiles.gd`, `licenses/**`, `.gitignore`, `.gitattributes`, `.gutconfig.json`, `docs/ARCHITECTURE.md`, `docs/ENGINE.md`, `docs/DEMO_EVENTS.md`, `docs/BUILD.md` |
| `procedural-modeler` | Modelagem procedural e escultura offline (SDF → malha) | `src/procedural/**`, `tools/sculpt/**`, `assets/meshes/**`, `tests/unit/test_procedural_*.gd`, `docs/PROCEDURAL.md` |
| `animator` | Câmeras, animação por eventos, VFX | `src/animation/**`, `src/entities/**`, `src/fx/**`, `tests/unit/test_animation_*.gd`, `docs/ANIMATION.md` |
| `sound-designer` | Linguagem sonora, síntese offline, SFX/ambiência, mixagem, diretor de áudio | `src/audio/**`, `assets/audio/**`, `tools/audio/**`, `default_bus_layout.tres`, `tests/unit/test_audio_*.gd`, `docs/AUDIO.md` |
| `technical-auditor` | Auditoria técnica e visual | nada (somente leitura + execução) |
| `art-critic` | Crítica de arte independente (style frames, capturas, vídeo com áudio) | nada (somente leitura + execução) |
| coordenador (sessão principal) | Planejamento, integração, registros | `CLAUDE.md`, `README.md`, `.claude/**`, `docs/PRODUCT.md`, `docs/AGENTS_AND_SKILLS.md`, `docs/DECISIONS.md`, `docs/LOOPS.md`, `docs/evidence/**` |

Nota operacional: o Claude Code registra os subagentes de `.claude/agents/` no início da sessão.
Na sessão em que foram criados, as funções foram executadas por subagentes genéricos instruídos a
seguir integralmente o arquivo do agente (inclusive a proibição de escrita do auditor); após o reinício
do contêiner os tipos nativos (`art-director`, `game-engineer`, `procedural-modeler`, `animator`,
`technical-auditor`) passaram a ser usados diretamente, cada implementação numa worktree Git isolada
e integrada por merge pelo coordenador.

Regras: nenhum agente edita área alheia; delegações paralelas só entre áreas disjuntas;
quem implementa não aprova a própria entrega (o `technical-auditor` aprova; no visual/sonoro, também o `art-critic`).
Não há orquestrador próprio: a coordenação usa apenas os subagentes nativos do Claude Code.

## Skills

| Skill | Quando usar | Dono |
|---|---|---|
| `game-verification` | Validar qualquer mudança executando o jogo (testes, smoke, capturas, export) | technical-auditor |
| `loop-checkpoint` | Fechar ou interromper um loop (verificação, auditoria, registro, git) | coordenador |
| `demo-events` | Criar/alterar eventos simulados | game-engineer |

## Pesquisa prévia

Antes de criar as skills foi pesquisado o catálogo de skills e plugins disponível: não havia skill
de Godot; os resultados eram de outros domínios ou dependiam de serviços remotos/comerciais
(descartados pelas regras de isolamento). Nenhum componente de terceiros foi instalado no Claude Code.

## Ambiente na nuvem

`.claude/hooks/session-start.sh` (somente quando `CLAUDE_CODE_REMOTE=true`) instala Xvfb/Mesa e
executa `tools/setup_godot.sh` (Godot 4.7.2 + templates com verificação SHA512).
Também cria o venv de ferramentas `/opt/korium-py` (numpy, scipy, scikit-image — ADR-013), usado apenas
pelos geradores offline de `tools/sculpt` e `tools/audio`; o jogo não depende dele.
Execução síncrona: a sessão só começa com o ambiente pronto.
