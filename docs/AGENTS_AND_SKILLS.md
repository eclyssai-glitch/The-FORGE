# Agentes e skills

Dono: coordenador. Responsabilidade: quem escreve o quê, e quais procedimentos reutilizáveis existem.
Definições oficiais: `.claude/agents/*.md` (subagentes do Claude Code) e `.claude/skills/*/SKILL.md`
(formato Agent Skills).

## Agentes (escritor único por área)

| Agente | Especialização | Escreve em |
|---|---|---|
| `art-director` | Direção artística, materiais, ambiente de luz, UI nativa | `src/style/**`, `src/ui/**`, `assets/fonts/**`, `docs/VISUAL_DIRECTION.md` |
| `game-engineer` | Engenharia de jogos 3D, eventos, mundo, qualidade, build | `project.godot`, `export_presets.cfg`, `scenes/**`, `src/core/**`, `src/events/**`, `src/world/**`, `tools/**`, `tests/integration/**`, `docs/ARCHITECTURE.md`, `docs/ENGINE.md`, `docs/DEMO_EVENTS.md`, `docs/BUILD.md` |
| `procedural-modeler` | Modelagem procedural | `src/procedural/**`, `tests/unit/test_procedural_*.gd`, `docs/PROCEDURAL.md` |
| `animator` | Câmeras, animação por eventos, VFX | `src/animation/**`, `src/entities/**`, `src/fx/**`, `tests/unit/test_animation_*.gd`, `docs/ANIMATION.md` |
| `technical-auditor` | Auditoria técnica e visual | nada (somente leitura + execução) |
| coordenador (sessão principal) | Planejamento, integração, registros | `CLAUDE.md`, `README.md`, `.claude/**`, `docs/PRODUCT.md`, `docs/AGENTS_AND_SKILLS.md`, `docs/DECISIONS.md`, `docs/LOOPS.md`, `docs/evidence/**` |

Regras: nenhum agente edita área alheia; delegações paralelas só entre áreas disjuntas;
quem implementa não aprova a própria entrega (o `technical-auditor` aprova).
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
Execução síncrona: a sessão só começa com o ambiente pronto.
