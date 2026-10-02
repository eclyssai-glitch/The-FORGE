# Sistema de interação de MIKU (INTERACTION_SYSTEM)

Dono: `game-engineer`. Responsabilidade: vocabulário de ações, intents, parser local, porta de provider,
patch estruturado, esquema/validação/armazenamento da configuração de MIKU, roteador de interação e entrada
diegética do cenário `living` (Loop 5; ADR-015, ADR-016; contrato `docs/contracts/loop-05.md`).

**Character ≠ Provider ≠ Worker.** A personagem (runtime do animator) decide *como* se move; o sistema de
interação só decide *o quê* (uma sequência de ações do vocabulário) e aplica mudanças de configuração
validadas. Nenhum provider existe neste projeto: a porta é uma interface sem implementação, sem registro
próprio e sem conexão — a ligação futura prevista é ao provider registry da KORIUM, que **não** é acessado
(regra de isolamento do `CLAUDE.md`). Sem rede, sem tokens, sem chaves.

## Fluxo

```
USER ─ clique em MIKU ─────────────┐
     ─ clique num mundo ───────────┤   Session.entity_clicked(id)      (Picker, a cada clique)
     ─ Enter + texto + Enter ──────┤   Session.call_submitted(text)    (linha de chamada)
                                   ▼
                       LivingInteraction (src/world, módulo do cenário living)
                                   ▼
             InteractionRouter ── LocalParser ──► Intent (ATTENTION | WORLD_TARGET | CONFIG_PATCH | SEMANTIC | UNKNOWN)
                   │                                 route LOCAL ─────────────┐        route PROVIDER
                   │                                                          │        ProviderPort (indisponível)
                   ▼                                                          ▼              │ recusa graciosa
             StructuredPatch ─► ConfigValidator ─► (EDIT_FILE terminou) ─► MikuConfig.apply (atômico, user://)
                   │                                                          │
                   ▼                                                          ▼
             plano de ações ─► ActionExecutor ─► Miku.perform(action, args + request_id + step)   GAME STATE ─► Miku.on_config_changed
                                                 Miku.action_event(request_id, action, phase, info) ─► próximo passo
                                                 (só eventos do request/step em curso; timeout = estimativa × 2 + 3 s)
```

## Arquivos (`src/agent/`, lógica pura `RefCounted`, testável)

| Classe | Papel |
|---|---|
| `ActionVocabulary` | as 16 ações (`StringName`), especificação de argumentos, `validate`, `step`, `validate_plan`, `names` |
| `Intent` | `Kind` (ATTENTION, WORLD_TARGET, CONFIG_PATCH, SEMANTIC, UNKNOWN), `Route` (LOCAL, PROVIDER), `target`, `text`, `lang`, `patch`, `source`, `rule` |
| `LocalParser` | parser determinístico pt-BR + en (`parse(text, worlds) -> Intent`) |
| `ProviderPort` | porta sem implementação: `is_available() == false`, `request()` recusa, `validate_response()` (estático) |
| `StructuredPatch` | `{file, path, value}` absoluto ou relativo (`delta`); `from_mutation()` para respostas de provider |
| `ConfigSchema` | seções, propriedades (tipo, faixa, passo, ligação real), pedidos sem suporte (`ASSET_REQUESTS`) |
| `ConfigValidator` | `validate(patch, values) -> Result` (OK, CLAMPED, UNCHANGED, REJECTED, REQUIRES_ASSET + notas) |
| `MikuConfig` | store: padrão versionado `res://config/miku_default.json` + estado do usuário `user://miku/miku.config.json` |
| `ActionExecutor` | executor **nulo** (sem corpo): emite `accepted`/`started`/`finished` na hora, após `simulated_duration`/`durations[ação]` s de `advance(dt)`, ou por `finish()`/`fail()`; registra `calls` e `events` |
| `MikuNodeExecutor` | executor ligado ao nó `Miku` do animator (referência fraca); repassa `action_event`; caminho legado se o nó não tiver `action_event` |
| `InteractionRouter` | o pipeline; planos; `request_id`; correlação; fila/interrupção; timeout por passo; commit da mutação |

Nós (fora de `src/agent`): `src/world/living_interaction.gd` (`LivingInteraction`, módulo do cenário),
`src/world/living_call_line.gd` (`LivingCallLine`, placeholder da linha de chamada),
`src/core/input_injector.gd` + `src/core/living_cue_player.gd` (automação: entrada real injetada).

## Vocabulário de ações

Passo de plano = `{"action": StringName, "args": Dictionary}`. Argumentos desconhecidos são recusados (um
provider não consegue contrabandear campos); `String`/`StringName` são intercambiáveis; floats inteiros valem
como `int` (JSON).

| Ação | Argumentos (`*` obrigatório) |
|---|---|
| `LOOK_AT_USER` | — |
| `LOOK_AT_WORLD` | `world*` (StringName) |
| `ACKNOWLEDGE` | `tone` ∈ warm, brief, curious, decline, puzzled · `reason` (String) |
| `THINK` | `seconds` 0..10 |
| `WORK` | `world` (StringName) · `resume` (bool) |
| `INSPECT` | `target` ("self", "file", id) · `path` ("section.key") |
| `SUMMON_HAND` | `side` ∈ left, right · `role` ("hold", "edit"…) |
| `SUMMON_HANDS` | `count*` 1..16 · `world` |
| `GRAB_FILE` | `file*` |
| `EDIT_FILE` | `file*` · `path*` · `value*` (qualquer) · `old_value` |
| `POINT` | `target*` |
| `DISCARD` | `file` · `applied` (bool) |
| `FRUSTRATED`, `ANGRY`, `SATISFIED` | `intensity` 0..1 |
| `RECOVER` | — |

## Parser local (pt-BR + en)

Regras, a primeira que casa vence (`LocalParser`):

1. **estruturado** — `appearance.height 1.04`, `chest_volume 0.52`, `set behaviour.patience 0.7`,
   `Miku, defina glow para 0,8` → CONFIG_PATCH absoluto. Chave nua exige valor numérico (ou ser um pedido de asset).
2. **composto** — contraste (`mas`, `porém`, `but`, `however`…) ou duas propriedades numa frase → SEMANTIC.
3. **asset** — traço sem suporte (asas, cabelo, roupa/vestido, olhos, cauda, chifres, pele, rosto, coroa…) →
   CONFIG_PATCH em `appearance.<traço>` (o validador responde REQUIRES_ASSET).
4. **aparência** — propriedade suportada + direção: "aumente sua altura" (+1 passo), "ombros um pouco mais largos"
   (+½ passo), "diminua muito o brilho" (−2 passos), "a bit taller", "fique menos alta" (adjetivo negado) →
   CONFIG_PATCH relativo (`delta = passo × magnitude × direção`). Sem direção → SEMANTIC.
5. **mundo** — por lado (esquerda/direita/centro, left/right/center, com "planeta/mundo/world/planet" ou
   "trabalhe/work") ou por nome (VESPER, CALYX, ORRIN, com ou sem acento) → WORLD_TARGET. Lado sem mundo → UNKNOWN.
6. **atenção** — só o nome e palavras de chamada ("Miku!", "Miku, olha aqui", "look at me") → ATTENTION.
7. **resto** — outras palavras → SEMANTIC (personalidade em linguagem natural — "fique mais curiosa" — é
   subjetiva por definição); nada → UNKNOWN.

Os lados vêm do que a câmera mostra (`LivingInteraction.world_directory()`: o mundo mais à esquerda na tela
é "esquerda"); sem câmera ou com menos de dois mundos visíveis, valem os lados de `LivingScript.WORLDS`.

## Configuração

Padrão versionado `res://config/miku_default.json` (exportado: `include_filter="config/*.json"`):

```json
{
  "format": "korium-universe/miku-config", "version": 1,
  "identity":   {"temperament": 0.35, "curiosity": 0.7, "patience": 0.6, "pride": 0.55},
  "appearance": {"height": 1.0, "shoulder_width": 1.0, "neck_length": 1.0, "chest_volume": 0.5,
                 "halo_radius": 1.0, "glow": 0.5},
  "behaviour":  {"frustration_threshold": 0.55, "aggression_peak": 0.7, "recovery_speed": 0.5,
                 "interruption_tolerance": 0.5}
}
```

| Propriedade | Faixa | Passo | Ligação real (quem consome) |
|---|---|---|---|
| `identity.temperament` | 0..1 | 0,1 | mente (0 sereno … 1 ardente) |
| `identity.curiosity` / `patience` / `pride` | 0..1 | 0,1 | mente |
| `appearance.height` | 0,9..1,1 | 0,03 | escala uniforme do osso `root` |
| `appearance.shoulder_width` | 0,85..1,15 | 0,04 | escala x de `clavicle.L/R` |
| `appearance.neck_length` | 0,9..1,12 | 0,03 | escala y de `neck` |
| `appearance.chest_volume` | 0,35..0,65 | 0,03 | escala xz de `chest` (0,5 = esculpido) |
| `appearance.halo_radius` | 0,8..1,25 | 0,06 | raio do halo |
| `appearance.glow` | 0..1 | 0,1 | energia de emissão do material |
| `behaviour.frustration_threshold` | 0,1..0,95 | 0,1 | limiar de perda de compostura |
| `behaviour.aggression_peak` | 0..1 | 0,1 | agressividade máxima das mãos |
| `behaviour.recovery_speed` | 0,1..1 | 0,1 | velocidade de recuperação |
| `behaviour.interruption_tolerance` | 0..1 | 0,1 | tolerância a ser interrompida |

Validação (`ConfigValidator`): arquivo (só `miku.config.json`) → caminho (chave na seção errada é movida para a
sua com nota; `ASSET_REQUESTS` → REQUIRES_ASSET) → tipo (só números finitos) → relativo resolvido → faixa
(clamp com explicação) → arredondamento a 3 casas → igual ao atual = UNCHANGED.

Store (`MikuConfig`): `reload()` lê o padrão e o arquivo do usuário saneando cada valor (desconhecidos
descartados, fora da faixa clampados, tipos errados ignorados, versão diferente ignorada — com avisos);
`apply(result)` grava o estado inteiro em `<arquivo>.tmp`, relê e valida o temporário e só então renomeia sobre o
arquivo do usuário (falha = memória e arquivo intactos; um `.tmp` completo sem o arquivo final é recuperado no
próximo `reload`); `reset()` apaga o arquivo do usuário; `snapshot()`/`restore_snapshot()` devolvem o estado do
jogador exatamente (smoke, capturas e tour usam isso). Nada de configuração vai ao repositório.

## Roteador e planos

| Pedido | Percepção imediata | Plano |
|---|---|---|
| atenção | `notice_user()` | LOOK_AT_USER, ACKNOWLEDGE(warm), WORK(resume) |
| mundo | `target_world(id)` | LOOK_AT_WORLD(world), POINT(world), SUMMON_HANDS(2, world), WORK(world) |
| config aplicada | — | LOOK_AT_USER, ACKNOWLEDGE(brief), SUMMON_HAND(left, hold), GRAB_FILE, SUMMON_HAND(right, edit), **EDIT_FILE(path, value, old_value) → commit**, INSPECT(self, path), SATISFIED(0,6), DISCARD(applied), WORK(resume) |
| config sem mudança | — | LOOK_AT_USER, ACKNOWLEDGE(brief), SUMMON_HAND(left, hold), GRAB_FILE, INSPECT(file, path), ACKNOWLEDGE(decline, unchanged), DISCARD(not applied), WORK(resume) |
| REQUIRES_ASSET | — | LOOK_AT_USER, THINK(1,5), INSPECT(self), ACKNOWLEDGE(decline, requires_asset), WORK(resume) |
| inválido / desconhecido | — | LOOK_AT_USER, THINK(1), ACKNOWLEDGE(puzzled, motivo), WORK(resume) |
| SEMANTIC sem provider | — | LOOK_AT_USER, THINK(1,5), ACKNOWLEDGE(decline, provider_unavailable), WORK(resume) |

- A mudança acontece **quando a mão termina de editar**: o patch é validado de novo contra a configuração
  daquele instante e aplicado; se já não há o que mudar (ou a escrita falha), o resto do plano vira
  ACKNOWLEDGE(decline), DISCARD(not applied), WORK(resume) — sem SATISFIED.
- Relatório de cada pedido (`request_finished` / `Session.interaction_reported`, no **fim** do plano): `id,
  request_id, kind, route, text, rule, target, status, plan, path, old_value, new_value, notes, reason, source,
  steps, failures, estimate, duration, interrupted, request_ids`. `steps[i]` = `{step, action, estimate, timeout,
  elapsed, latency, result (finished|failed|timeout|cancelled|interrupted), reason}`. Status: `attention`,
  `world_target`, `applied`, `unchanged`, `rejected`, `requires_asset`, `provider_unavailable`, `provider_invalid`,
  `provider_actions`, `unknown`, `commit_failed`, `cancelled`.
- Início (`request_started` / `Session.interaction_started`), emitido **antes** do primeiro passo (portanto antes
  de qualquer ação terminar): `{id, request_id, kind, route, status: &"started", target, path, plan, text, source,
  expected_status, estimate, deadline, restart}`. `id`, `request_id` e `source` são os mesmos do relatório final
  (num plano reiniciado por interrupção, o `request_id` do último `started` é o do resultado; `id` nunca muda).

### Protocolo de ações correlacionadas (Loop 5 R2, `docs/contracts/loop-05-round2.md`)

- Cada pedido recebe `request_id` (int > 0, contador estático do processo: nunca se repete, nem após recomposição).
  Cada passo despachado leva `args.request_id` e `args.step` (índice no plano) — chaves reservadas
  (`ActionVocabulary.CORRELATION_ARGS`), recusadas pela validação (um provider não as forja).
- O roteador escuta `executor.action_event(request_id, action, phase, info)` e aceita **só** eventos do pedido
  ativo e do passo em curso (`info.step`; sem `step`, o nome da ação precisa casar). Eventos com `request_id` 0
  (ações da própria MIKU: roteiro `living.hands`, agenda), de outro pedido/passo ou atrasados são ignorados
  (`ignored_events`). Fases: `accepted`, `started` (marca `latency`), `progress`, e um terminal: `finished`
  (próximo passo; commit se for o `EDIT_FILE`), `failed` (`info.reason`), `cancelled` não pedido pelo roteador
  (= falha).
- Timeout por passo = `executor.estimate_duration(action, args) × 2 + 3 s` (`TIMEOUT_FACTOR`, `TIMEOUT_MARGIN`),
  medido no relógio do roteador — `LivingInteraction` alimenta `tick(dt)` com `MotionClock` (o relógio de MIKU),
  no máximo 0,5 s por quadro. Passo vencido: `executor.cancel(request_id)` no corpo, falha registrada com motivo
  (`timeout after Xs (estimate Ys)`, `push_warning`).
- Falha (`failed`, `cancelled` alheio, timeout): o plano **segue**, exceto `GRAB_FILE`/`EDIT_FILE` de um plano de
  configuração antes do commit — aí nada é aplicado e o resto vira ACKNOWLEDGE(decline), DISCARD(not applied),
  WORK(resume) com status `commit_failed` e o motivo. Um `perform` recusado pelo corpo (`false`) falha na hora.
- Fila: 1 plano em execução + FIFO (máx. `MAX_QUEUE` = 4 esperando; o mais antigo esperando é descartado como
  `cancelled`). **Interrupção por ATENÇÃO** (`should_interrupt()`): um novo pedido de atenção interrompe o plano em
  curso se ele não for de atenção, se não estiver na seção do arquivo (de `GRAB_FILE` até o commit no
  `EDIT_FILE`: o arquivo está nas mãos dela) e se a fração do plano que falta for maior que
  `1 − behaviour.interruption_tolerance` (0 = nunca; 0,5 = só se falta mais da metade; 1 = sempre). O plano
  interrompido é cancelado no corpo (`executor.cancel`) e volta à fila logo depois da atenção com **novo**
  `request_id`, recomeçando do primeiro passo (nada foi aplicado); se a mudança já tinha sido aplicada, o pedido
  termina ali (`interrupted`, nota). Sem interrupção a atenção espera na fila FIFO (a percepção `notice_user()` já
  aconteceu na hora).
- `cancel()` (reset/recomposição: `LivingInteraction._exit_tree`) cancela o plano em curso no corpo e descarta a
  fila (`cancelled`); eventos atrasados são ignorados. Trocar de executor no meio de um passo = falha
  ("executor replaced") e o plano segue no novo. Nada espera evento externo sem timeout; `perform` nunca bloqueia.
- Reentrância: o `MikuNodeExecutor` entrega ao roteador os eventos **terminais** do nó (e o `action_finished`
  legado) adiados para o fim do quadro (`defer_terminal`), então o próximo `perform` nunca roda dentro da emissão
  do próprio corpo (o `tick` de MIKU limpa o canal logo depois de emitir o fim; um `perform` síncrono ali era
  apagado — o ACKNOWLEDGE perdido do smoke). `accepted`/`started`/`progress` seguem na hora.
- Compatibilidade (**legado**): se o nó `Miku` não tiver `action_event`, o `MikuNodeExecutor` emite
  `accepted`/`started` ele mesmo e converte o `action_finished(action)` não correlacionado em `finished` do passo
  pendente quando o nome casa (o comportamento antigo, sujeito a consumir ações da própria MIKU) — só para um
  corpo antigo continuar rodando. Sem `estimate_duration`, valem as durações nominais
  `ActionVocabulary.NOMINAL_SECONDS`.

### Contrato da porta de provider

Resposta esperada de um provider (futuro): `{"ok": true, "actions": [{"action", "args"}…], "mutation": {"file",
"path", "value"}}`. `ProviderPort.validate_response` recusa a resposta inteira se houver ação/argumento fora do
vocabulário, campo desconhecido ou mutação malformada; a mutação vira `StructuredPatch` (`source = provider`) e
passa pelo **mesmo** `ConfigValidator`. As ações do provider abrem o plano; se ele não trouxer `EDIT_FILE`, o
roteador acrescenta a sequência padrão de edição (a mudança sempre é mostrada); se trouxer, os argumentos do
`EDIT_FILE` viram o valor validado. Neste projeto `is_available()` é sempre `false`.

## API para o animator (nó `Miku`, `res://src/miku/miku.gd`)

O `LivingInteraction` procura o irmão chamado `Miku` (ou o primeiro nó do grupo `living_miku`) com `perform()`.

- Obrigatório (protocolo R2): `perform(action: StringName, args := {}) -> bool` (args com `request_id`, `step`),
  sinal `action_event(request_id: int, action: StringName, phase: StringName, info: Dictionary)` — `accepted`,
  `started`, `progress` (opcional, `info.t`), exatamente um terminal `finished|failed|cancelled` por `perform`
  aceito, `info.step` = `args.step`; ações da própria MIKU com `request_id = 0` —,
  `estimate_duration(action: StringName, args: Dictionary) -> float` (segundos reais, honesto),
  `cancel(request_id: int)` (termina as ações daquele pedido com `cancelled` e limpa mãos/fios/artefatos dele),
  `notice_user()`, `target_world(id: StringName)`. `action_finished(action)` pode continuar existindo, mas o
  roteador não o usa (só no caminho legado, se faltar `action_event`).
- Opcional (chamado se existir): `apply_config(values: Dictionary)` na ligação (configuração inteira, seções →
  chave → float) e `on_config_changed(path: String, old_value, new_value)` depois de cada mudança real.
- Ao ser recomposto (reset), o nó novo é ligado de novo; o antigo deixa de ser chamado (referência fraca).
- Para os cliques: cada corpo de seleção na camada de colisão 2 com meta `entity_id` (`miku`, `world_vesper`,
  `world_calyx`, `world_orrin`) e a raiz visual no grupo `Session.entity_group(id)` (os lados "esquerda/direita"
  são calculados a partir dela).
- A câmera (`CameraDirector`) deve ignorar WASD enquanto `Session.call_line_open` (o voo do modo UNIVERSE lê
  `Input.get_vector`).

## API para o art-director (UI)

- Linha de chamada: um nó no grupo `living_call_line_ui` substitui o placeholder. Ele ouve
  `Session.call_line_changed(open)`, envia com `Session.submit_call(text)` (fecha a linha e emite
  `call_submitted`) e fecha com `Session.close_call_line()`. Enter (`call_line`, só no `living`) chama
  `Session.open_call_line()`; `Session.CALL_MAX_CHARS` = 200.
- Reconhecimento imediato: `Session.interaction_started(report)` assim que o plano começa (antes de qualquer
  ação terminar), com `status: &"started"`, `kind`, `route`, `target`, `path`, `plan`, `source`, `id`,
  `request_id` — mostrar na hora "→ <assunto>" (recognized) para `source == "text"`.
- Retorno diegético: `Session.interaction_reported(report)` (campos acima) no fim — o resultado; casar com o
  `started` pelo `id`. Artefato de arquivo, mão segurando e
  mão editando são do corpo (animator) a partir de GRAB_FILE / EDIT_FILE / DISCARD.
- Nada de painel/menu de configuração: a única via é falar com MIKU.

## Automação

- `tools/smoke_test.sh --scenario=living`: roteiro inteiro a 8×, nove pedidos reais (2 cliques, 7 textos)
  esperados um a um pelo `id` com orçamento derivado das estimativas (`docs/BUILD.md`),
  `config_mutated=true`/`config_reverted=true`, seek recusado, reset recompõe. Até o animator entregar os
  módulos, use `SMOKE_ALLOW_MISSING_MODULES=1` (só nesse caso).
- `tools/capture_evidence.sh <dir> --scenario=living`: joga em tempo real e injeta os cues como entrada real.
- `tools/record_living.sh`: vídeo MP4 com áudio do protótipo com as interações reais (`docs/BUILD.md`).

## Testes

`tests/unit/test_agent_vocabulary.gd`, `test_agent_parser.gd`, `test_agent_config.gd` (store num diretório
temporário de `user://`), `test_agent_router.gd` (executor nulo, executor de nó legado e correlacionado, provider
de teste que passa pela mesma validação, porta indisponível; correlação — outro request/step e `request_id` 0
ignorados —, timeout por passo derivado da estimativa, falha crítica de `GRAB_FILE`/`EDIT_FILE`, fila FIFO,
interrupção por tolerância, seção do arquivo, cancelamento/reset, troca de executor, `interaction_started` antes
de qualquer `finished`), `tests/integration/test_living_scenario.gd` (`Session.interaction_started` antes do
resultado com os mesmos `id`/`request_id`/`source`; reset cancela no corpo; orçamento derivado do smoke).
