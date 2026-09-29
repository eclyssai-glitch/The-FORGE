# Eventos de demonstração

Dono: `game-engineer`. Responsabilidade: semântica e intenção narrativa dos eventos simulados.
Fonte canônica de tempos e textos: `src/events/origin_chamber_script.gd` (este documento não os repete).
Procedimento para alterar: skill `demo-events`.

Todos os eventos são fictícios. Nenhum representa, imita ou prepara integração com serviços reais.

| Tipo | Significado narrativo | Efeito no mundo (`WorldState`) |
|---|---|---|
| `session.opened` | Abre a sessão de demonstração | `session_at` |
| `core.activation` | O núcleo desperta | `core_activation_at`, fase ACTIVATING |
| `core.online` | Núcleo estável, energia disponível | `core_online_at`, fase CORE STABLE |
| `fragments.emitted` | Fragmentos geométricos liberados | `fragments_at`, `fragment_count`, fase FRAGMENTS |
| `structure.seeded` | Eixo de construção travado em torno do núcleo | `seeded_at`, fase BUILDING |
| `structure.layer_added` | Uma camada é montada a partir de fragmentos (`payload.layer`) | `layer_times[i]` |
| `structure.materials_applied` | Superfícies brutas viram acabamento | `materials_at`, fase FINISHING |
| `structure.lighting_applied` | Iluminação da câmara em nível de trabalho | `lighting_at` |
| `verification.started` | Anel de verificação começa a varrer a estrutura | `verification_at`, fase VERIFYING |
| `verification.check_passed` | Uma verificação simulada passa (`payload.check`) | `checks[]` |
| `verification.passed` | Todas as verificações passaram | `verified_at`, fase VERIFIED |
| `structure.finalized` | A estrutura trava na forma final | `finalized_at`, fase FINAL FORM |
| `session.completed` | Fim da demonstração | `completed_at`, fase COMPLETE |

Vocabulário exibido (Loop 3): o evento `core.online` aparece como **CORE STABLE** (título e fase) e o
status do núcleo como **ACTIVE** — nada na UI sugere conexão real. Os identificadores internos
(`core.online`, `CORE_ONLINE`, `core_online_at`) permanecem.

A missão exibida no OBSERVATORY (`src/events/mission.gd`) deriva seus 7 objetivos desses eventos.
