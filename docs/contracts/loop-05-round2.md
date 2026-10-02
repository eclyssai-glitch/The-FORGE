<!-- Dono: coordenador. Responsabilidade: contratos da rodada 2 do Loop 5 (diretiva "ROUND 2 APPROVED" do Owner). -->
# Loop 5 — Rodada 2 · runtime correto + migração nativa

Checkpoint pré-rodada: `06f8105` (remoto). Baseline visual/funcional = rodada 1. Pesquisa: `docs/research/native-character-runtime.md`.

## Bloco 1 — correção de runtime (antes da migração)

### Protocolo de ações correlacionadas (fixo; game-engineer + animator + art-director)

- Toda ação pedida pelo roteador leva `args.request_id: int` (> 0, único por sessão, atribuído pelo
  `InteractionRouter`) e `args.step: int` (índice no plano). Ações iniciadas pela própria MIKU (roteiro, agenda,
  autonomia) usam `request_id = 0`.
- `Miku` emite `action_event(request_id: int, action: StringName, phase: StringName, info: Dictionary)` com
  `phase` ∈ `&"accepted"`, `&"started"`, `&"progress"` (opcional, `info.t` 0..1), `&"finished"`, `&"failed"`,
  `&"cancelled"`. Exatamente um terminal (`finished|failed|cancelled`) por `perform` aceito. `action_finished(action)`
  continua por compatibilidade, mas o roteador **não** o usa mais.
- `Miku.estimate_duration(action: StringName, args: Dictionary) -> float` (segundos, estimativa honesta de tempo real
  na intenção atual). `Miku.cancel(request_id: int)` cancela as ações daquele request (termina com `cancelled`,
  limpa mãos/fios/artefatos que pertenciam a ele).
- Roteador: espera **só** eventos com seu `request_id` e `step`; timeout por passo = `estimate × 2 + 3 s`
  (falha registrada com motivo, plano segue ou aborta conforme a ação); fila com no máximo 1 plano em execução +
  fila FIFO; novo pedido de ATENÇÃO pode interromper (`interruption_tolerance`); `reset`/recomposição cancelam tudo
  e limpam. Nada bloqueia esperando evento externo.
- Smoke LIVING: orçamento derivado (duração do roteiro + soma das estimativas dos planos de teste + margem), espera
  por request (não por tempo global), relata `request_id`, passos, durações reais vs estimadas; sem timeout.

### Reconhecimento imediato (linha de chamada)

- `Session.interaction_started(report)` emitido pelo roteador **assim que** o pedido é reconhecido e o plano começa
  (antes de qualquer ação terminar), com `{id, request_id, kind, route, status: &"started", target, path, plan}`;
  `Session.interaction_reported(report)` continua no fim (resultado).
- UI: no `interaction_started` mostra na hora "→ <assunto>" (recognized); no `interaction_reported`, o resultado.
- MIKU: o primeiro passo de todo plano de usuário (`LOOK_AT_USER`/`LOOK_AT_WORLD`) começa em ≤ 0,3 s após o envio
  e é visível (olhar/cabeça) — a reação inicial acontece antes da tarefa terminar.

## Migração nativa (animator) — 5 checkpoints OLD vs NEW

`MikuBody` ganha seleção de backend (`--body=legacy|native`, e por camada quando possível) para comparar lado a lado.
Cada passo: vídeo lado a lado (mesma sequência, mesma câmera), dumps do inspector, testes, desempenho, avaliação
visual; substituir só quando NEW ≥ OLD. Não apagar `pose_rig`, `limb_ik`, `arm_channel`, `finger_set` antes das
comparações. Passos: (1) AnimationTree — CALM, FOCUSED, FRUSTRATED, ANGRY, RECOVERING; respiração, peso,
compostura, timing (perda ~0,25 s, recuperação ~1,2–1,6 s, validar); (2) atenção olhos→cabeça→peito com
LookAtModifier3D `relative=true`, overlap, sem snap; (3) braços TwoBoneIK3D com polos explícitos, OneShot + filtros,
Aim no indicador, BoneTwistDisperser3D no punho, LimitAngularVelocity só como proteção; (4) SpringBoneSimulator3D:
saia → dedos → cabelo (quando houver ossos); (5) mãos-marionete: corpo com mola/massa/atraso/velocidade/intenção
preservados; dedos/grip/pose/pointing nativos; 1, 2, 6 mãos.

## Gate de causalidade (inspector)

Para toda grande ação, a seção `miku` do `inspect_state()` registra uma linha do tempo por request/ação com
carimbos: `intent`, `anticipation`, `gesture`, `thread`, `hand`, `matter`, `result` (tempo de jogo). Um checador
(`tools/inspector/causality.py`) reprova se alguma etapa ocorrer antes da anterior ou sem ela.

## Desempenho

Medir após cada passo: MIKU, 1 mão, 2 mãos, 6 mãos, total (CPU por quadro; baseline 0,09 ms / 0,04 ms por mão).

## Depois da migração

Rig: olhos, cabelo, saia multi-cadeia (procedural-modeler). Direção: raiva com câmera aberta revelando poder;
configuração com MIKU protagonista; mundo indicado — MIKU percebe primeiro, câmera revela a relação espacial depois.
Fechamento: todos os testes, smokes ORIGIN/GENESIS/LIVING (sem timeout), export check, inspector, gravação real
(LIFE, PUPPET, WORLD WORK, FAILURE, ANGER, RECOVERY, USER ATTENTION, WORLD TARGET, CONFIGURATION MOCK) → art-critic
(12 perguntas) → correções → technical-auditor → correções.
