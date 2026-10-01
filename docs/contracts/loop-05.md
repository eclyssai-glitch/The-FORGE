<!-- Dono: coordenador. Responsabilidade: brief e contratos do Loop 5 (MIKU LIVING CHARACTER V1). -->
# Loop 5 — MIKU LIVING CHARACTER V1 · protótipo de personagem viva

Fonte: diretiva do Owner "KORIUM UNIVERSE — MIKU LIVING CHARACTER LOOP V1". O GENESIS atual (Loop 4, checkpoint
`b9b8672`, tag local `checkpoint/loop4-genesis-r1`) é apenas **referência do problema**: animação rígida, elementos
colocados e não conectados, MIKU espectadora, mãos sem vontade, câmera/partículas sem causalidade, mundos que
aparecem em vez de serem construídos. **Não** reconstruir GENESIS agora; **não** polir o modelo — a escultura atual é
**manequim técnico** (será substituída por nova direção visual do Owner). Não gerar imagens. Sem voz, sem provider
real, sem chat SaaS.

## Objetivo

Uma cena pequena e controlada — **MIKU LIVING CHARACTER PROTOTYPE** — que prova, sem explicação, que:
"MIKU está pensando", "controla aquelas mãos", "está construindo aquilo", "percebeu que algo deu errado", "ficou
irritada", "se recompôs", "percebeu que eu a chamei", "entendeu qual mundo eu indiquei", "acabou de alterar algo em
si mesma".

## Personagem (resumo normativo; a diretiva do Owner é a referência completa)

- Não fala. Personalidade por olhar, postura, respiração, gestos pequenos, hesitação, curiosidade, dedos, peso,
  relação com objetos, controle das mãos, reação a sucesso/erro.
- Estado predominante: **divindade elegante + garota curiosa com poder absurdo** — delicada, controlada, bailarina,
  curiosa, observadora, segura.
- Erro: **não** há "modo demônio" — ela **perde a compostura**: postura rígida, movimentos secos, olhar fixo, menos
  delicadeza, fios tensos, controle agressivo das mãos, eficiência extrema, breves momentos não-humanos. Regra:
  *quanto mais calma, mais humana; quanto mais frustrada, mais percebemos que não é humana.* Depois, recupera.
- Viva sempre: sem idle em loop; variações (respirar, transferir peso, seguir objetos com os olhos, olhar o trabalho,
  corrigir postura, dedos, observar a mão, verificar o mundo, hesitar, ajustar, continuar) **ligadas ao estado mental
  e ao trabalho**, nunca aleatórias.

## Mãos e fios

- Mãos = **ferramentas sem consciência**, marionetes de MIKU; mesma família visual (direção futura: angelicais,
  elegantes, monumentais, idênticas em linguagem); **função vem da animação**; **quantidade dinâmica** (1, 2, 4, 6…
  sem limite arbitrário — pool).
- Fios = **intenção e controle**, não decoração: decide → gesto → fio aparece → tensiona → mão responde → tarefa →
  fio relaxa → some. Força ↔ tensão/presença; irritada → vários fios rápidos.

## Causalidade e princípios

`MIKU → intenção → antecipação → gesto → fio → mão → matéria → resultado` (nunca o inverso).
Antecipação, peso (mãos gigantes aceleram/desaceleram com massa), follow-through, overlap (nada responde no mesmo
quadro). Nada de tween linear: dinâmica de segunda ordem (molas amortecidas) e atrasos por cadeia.
Câmera conta a história (revelar, acompanhar, enfatizar, mostrar consequência; movimentos longos, com massa, poucos
cortes). Partículas só quando explicam uma ação (compressão de matéria, fragmentos, energia transferida, fio
tensionando, mundo se formando).

## Testes obrigatórios do protótipo

1. **LIFE** — viva o tempo todo, sem idle robótico.
2. **PUPPET** — controla 1 mão, depois 2, depois várias; fios aparecem/somem; causalidade imediata.
3. **WORLD WORK** — constrói/manipula um mundo **em etapas** com as mãos (nunca aparece pronto).
4. **FAILURE** — algo dá errado; tenta corrigir com elegância; falha de novo; perde a compostura; controle agressivo
   de várias mãos; corrige/desmonta; recupera a elegância.
5. **USER ATTENTION** — usuário chama; ela percebe, olha, reage conforme o estado, volta ao trabalho.
6. **WORLD TARGET** — usuário seleciona um mundo; ela olha, reposiciona a atenção, convoca mãos, começa a trabalhar nele.
7. **CONFIGURATION MOCK** — "Miku, altere uma propriedade sua": pedido → reação → artefato de arquivo aparece → mão
   segura → outra mão edita → validação → **alteração real** de uma propriedade suportada → MIKU reage à própria
   alteração → arquivo some. Sem provider.

Critérios de reprovação e as 12 perguntas da rodada: diretiva do Owner (copiados em `docs/LOOPS.md` na entrada do
Loop 5 a cada rodada).

## Arquitetura (aditiva; ORIGIN e GENESIS continuam funcionando)

- Cenário novo `&"living"` (prototype) no registro de cenários; cena composta pelo `world.gd` como os outros.
  Personagem viva é **estado em tempo real** (molas, mente) — **não** é função de `Simulation.time` e não suporta
  seek (ADR-015); o `Simulation` continua dono dos eventos de demonstração (ordens de trabalho do roteiro do
  protótipo); a mente reage a eventos e a intervenções do usuário.
- **Character ≠ Provider ≠ Worker** (ADR-016). Fluxo de mutação:
  `USER → MIKU → INTENT → LOCAL PARSER | PROVIDER PORT → STRUCTURED PATCH → VALIDATION → CONFIG MUTATION →
  GAME STATE → MIKU REACTION`. Providers nunca tocam ossos, AnimationTree, transforms, câmera ou internals: só
  devolvem **ações do vocabulário** + **patch estruturado**. O jogo decide *como* MIKU executa; a personalidade é da
  runtime dela.
- **Provider port**: apenas uma interface (porta) sem implementação e **sem registro próprio**; a ligação futura é ao
  provider registry da KORIUM (não acessado nem conectado neste loop — regra de isolamento continua). Sem provider
  disponível, pedidos SEMANTIC recebem reação de MIKU ("não posso agora") e nada é aplicado. Voz futura = mesmo input
  do chat.
- **Vocabulário de ações** (mínimo): `LOOK_AT_USER, LOOK_AT_WORLD, ACKNOWLEDGE, THINK, WORK, INSPECT, SUMMON_HAND,
  SUMMON_HANDS, GRAB_FILE, EDIT_FILE, POINT, DISCARD, FRUSTRATED, ANGRY, RECOVER, SATISFIED`.
- **Configuração** em três seções (`identity`, `appearance`, `behaviour`) com esquema (tipo, faixa, suporte real):
  - `identity`: `temperament`, `curiosity`, `patience`, `pride` (modulam a mente);
  - `appearance`: só o que tem suporte real no rig/material — ex.: `height`, `shoulder_width`, `neck_length`,
    `chest_volume` (escala de osso), `halo_radius`, `glow` (material). Pedidos sem suporte (novos assets) são
    classificados `REQUIRES_ASSET` e recusados com reação;
  - `behaviour`: `frustration_threshold`, `aggression_peak`, `recovery_speed`, `interruption_tolerance`.
  Persistência em `user://` (nunca no repositório), padrão versionado em `res://`.
- **Dois caminhos**: `DETERMINISTIC/LOCAL` (comandos estruturados ou frases simples reconhecidas pelo parser local, sem
  tokens) e `SEMANTIC/PROVIDER` (natural/subjetivo → porta de provider; aqui sem provider → recusa graciosa).
- **Entrada do usuário (diegética, não SaaS)**: clicar em MIKU = chamar a atenção; clicar num mundo = indicar;
  uma linha de chamada fina no mundo ("sussurro", tecla Enter) aceita texto ("Miku, …") que vai ao mesmo pipeline.

## Áreas e contratos (escritor único)

- **procedural-modeler** — rig do manequim: `tools/sculpt/rig*` (bake offline de esqueleto + pesos por vértice a
  partir das primitivas da escultura) e `src/procedural/` (montagem em runtime: `Skeleton3D` + `Skin` + malha com
  `ARRAY_BONES/WEIGHTS`). Ossos nomeados mínimos de MIKU: `root, hips, spine, chest, neck, head, clavicle.L/R,
  upper_arm.L/R, forearm.L/R, hand.L/R, thumb.L/R(2), index.L/R(2), middle.L/R(2), ring.L/R(2), skirt.0/1/2`
  (`hair_root` como ponto de fixação no `head`). Mão angelical genérica rigada: `wrist, palm, thumb(3), index(3),
  middle(3), ring(3), little(3)` (o mesmo rig serve para N instâncias, espelhado quando preciso). API:
  `MikuRig.build() -> Node3D` (com `Skeleton3D` acessível) e `HandRig.build(side) -> Node3D`; pose de repouso = pose
  esculpida; escala de osso suportada (para `appearance`). Testes: pesos normalizados, sem vértice órfão,
  deformação sem rasgos em poses-limite.
- **animator (CHARACTER_MOTION)** — `src/miku/**` (runtime da personagem: mente/estado emocional e de compostura,
  agenda de micro-comportamentos ligada ao trabalho, execução das ações do vocabulário em movimento, corpo
  procedural em camadas: respiração, peso, cadeia de olhar olhos→cabeça→peito, gestos de braço/dedos, molas de
  segunda ordem com overlap), `src/entities/living/**` (pool de mãos-marionete com peso/inércia, fios de intenção
  com tensão, mundo-obra construído em etapas com falha deliberada e desmontagem), `src/fx/living/**` (partículas
  causais), câmera narrativa do protótipo, testes `tests/unit/test_animation_living*.gd`, `docs/ANIMATION.md`.
  API para o sistema de interação: `Miku.perform(action: StringName, args := {})`, `Miku.notice_user()`,
  `Miku.target_world(id)`, sinais `action_started/finished(action)`, `mood_changed(state)`.
- **game-engineer (INTERACTION_SYSTEM)** — `src/agent/**` (vocabulário, intents, parser local pt-BR/en, porta de
  provider sem implementação, patch estruturado, esquema/validação, store de configuração em `user://`, padrão em
  `res://config/`), cenário `living` + composição + roteiro do protótipo (ordens de trabalho, falha deliberada),
  entrada do usuário (clique em MIKU/mundo, linha de chamada), automação (smoke `--scenario=living`, capturas,
  `tools/record_living.sh` com interações reais injetadas e áudio), testes `tests/unit/test_agent_*.gd` +
  integração, docs (ARCHITECTURE/ENGINE/BUILD + `docs/AGENT.md`).
- **art-director** — materiais placeholder: mão angelical (pérola/marfim luminoso, mesma família), fio de intenção
  (uniform `tension` 0..1, `presence` 0..1), artefato de arquivo de configuração (cartão de luz com glifos), mundo-obra
  (estados de construção e falha), linha de chamada e glifos de UI diegética do cenário `living`. Sem polimento do
  manequim.
- **sound-designer** (rodada 2) — sons causais: tensão do fio, convocação de mão, compressão de matéria, falha,
  frustração, recuperação, reconhecimento do usuário.
- **art-critic** e **technical-auditor** — revisam cada rodada (as 12 perguntas + critérios de reprovação; runtime,
  performance, erros, arquitetura, regressões).

## Rodadas

OBSERVE → PLAN → IMPLEMENT → RUN → RECORD (gravação real com interações) → ART CRITIC → TECHNICAL AUDIT → CORRECT →
RUN AGAIN, até `READY_FOR_OWNER_REVIEW` ou `OWNER_ATTENTION_REQUIRED`.
