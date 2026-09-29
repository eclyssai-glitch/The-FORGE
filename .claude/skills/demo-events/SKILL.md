---
name: demo-events
description: Procedimento para criar ou alterar eventos simulados (DEMO MODE) do KORIUM UNIVERSE — tipos, roteiro da ORIGIN CHAMBER, redução em WorldState, missão, entidades e testes. Use quando um evento fictício novo for necessário, quando a sequência ou os tempos da demo mudarem, ou quando o visual precisar reagir a um novo tipo de evento.
metadata:
  owner: game-engineer
---

# Eventos de demonstração

Eventos são **fictícios, locais e determinísticos**; nunca representam provedores, agentes ou
serviços reais (um teste verifica termos proibidos nos textos).

## Arquivos (fonte canônica é o código)

| Arquivo | Papel |
|---|---|
| `src/events/sim_event.gd` | Constantes de tipo + `ALL_TYPES`; evento imutável |
| `src/events/origin_chamber_script.gd` | Roteiro ordenado (segundos) |
| `src/events/world_state.gd` | `apply()` puro: evento → timestamps/fase |
| `src/events/event_timeline.gd` | Reprodução: start/pause/resume/reset/seek/advance |
| `src/events/mission.gd` | Objetivos derivados dos eventos (OBSERVATORY) |
| `src/events/entity_catalog.gd` | Entidades selecionáveis e status derivado |
| `docs/DEMO_EVENTS.md` | Semântica e intenção narrativa (não repete tempos) |

## Procedimento

1. Novo tipo → constante em `SimEvent` **e** em `ALL_TYPES`.
2. Evento no roteiro com `time` crescente e `id` único; `label` curto em maiúsculas, `detail` factual.
3. Tratar em `WorldState.apply()` (retorna `false` para desconhecidos — o teste acusa).
4. Se afeta objetivo ou entidade: `mission.gd` / `entity_catalog.gd`.
5. O visual reage lendo `Simulation.world` (timestamp) + `Simulation.time` — peça ao `animator`.
6. Testes em `tests/unit/test_event_system.gd`; `tools/run_tests.sh`.
7. Atualize a tabela semântica de `docs/DEMO_EVENTS.md` se surgiu tipo novo; tempos de captura
   em `src/core/automation.gd` se as fases mudaram de lugar.
