---
name: demo-events
description: Procedimento para criar ou alterar eventos simulados (DEMO MODE) do KORIUM UNIVERSE — tipos, roteiros dos cenários (ORIGIN CHAMBER, GENESIS), redução em WorldState/GenesisState, missão, entidades e testes. Use quando um evento fictício novo for necessário, quando a sequência ou os tempos da demo mudarem, ou quando o visual precisar reagir a um novo tipo de evento.
metadata:
  owner: game-engineer
---

# Eventos de demonstração

Eventos são **fictícios, locais e determinísticos**; nunca representam provedores, agentes ou
serviços reais (um teste verifica termos proibidos nos textos).

## Arquivos (fonte canônica é o código)

| Arquivo | Papel |
|---|---|
| `src/events/sim_event.gd` | Constantes de tipo + `ORIGIN_TYPES`/`GENESIS_TYPES`/`ALL_TYPES` (união); evento imutável |
| `src/events/scenario.gd` | Registro de cenários: roteiro, tipos, estado, catálogo por id |
| `src/events/scenario_state.gd` | Base dos estados (`apply`, `phase_*`, `progress`) |
| `src/events/origin_chamber_script.gd` / `genesis_script.gd` | Roteiros ordenados (segundos) |
| `src/events/world_state.gd` / `genesis_state.gd` | `apply()` puro: evento → timestamps/fase |
| `src/events/genesis_catalog.gd` | Entidades GENESIS (tipo simbólico: subagente, documentação, skill, memória) |
| `src/events/event_timeline.gd` | Reprodução: start/pause/resume/reset/seek/advance |
| `src/events/mission.gd` | Objetivos derivados dos eventos (OBSERVATORY) |
| `src/events/entity_catalog.gd` | Entidades selecionáveis e status derivado |
| `docs/DEMO_EVENTS.md` | Semântica e intenção narrativa (não repete tempos) |

## Procedimento

1. Novo tipo → constante em `SimEvent` **e** na lista do cenário (`ORIGIN_TYPES`/`GENESIS_TYPES`); `ALL_TYPES` é a união.
2. Evento no roteiro com `time` crescente e `id` único; `label` curto em maiúsculas, `detail` factual.
3. Tratar no `apply()` do estado do cenário (`WorldState`/`GenesisState`) (retorna `false` para desconhecidos — o teste acusa).
4. Se afeta objetivo ou entidade: `mission.gd` / `entity_catalog.gd`.
5. O visual reage lendo o estado (`Simulation.world` na ORIGIN, `Simulation.genesis` no GENESIS; `Simulation.state` = ativo) + `Simulation.time` — peça ao `animator`.
6. Testes em `tests/unit/test_event_system.gd` / `tests/unit/test_genesis_events.gd`; `tools/run_tests.sh`.
7. Atualize a tabela semântica de `docs/DEMO_EVENTS.md` se surgiu tipo novo; tempos de captura
   em `src/core/automation.gd` se as fases mudaram de lugar.
