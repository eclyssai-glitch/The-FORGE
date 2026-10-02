<!-- Dono: animator. Responsabilidade: pesquisa formal da pilha NATIVA de personagem do Godot 4.7.2 para MIKU (gate do Loop 5, Fase 4, sandbox). -->
# Pilha nativa de personagem no Godot 4.7.2 — o que executa o MOVIMENTO da MIKU

Origem: sandbox `sandbox/loop5-tooling` (a partir de `b9b8672`, branch local). Código do spike migrado para
`tools/research/native_character/` (fora do export; referência). Pesquisa e spike descartável; nada daqui entra
no produto sem passar pelo processo normal do loop (dono da área, testes, auditoria).

**Decisão proposta (resumo).** A MENTE e a INTENÇÃO continuam código próprio. O MOVIMENTO passa a ser
executado pela pilha nativa: `AnimationTree` em modo manual (estados de corpo, camadas, gestos) →
`SkeletonModifier3D` em ordem (olhar, IK, mira, torção, segurança anti-estalo) → `SpringBoneSimulator3D`
(movimento secundário). O que **não** existe nativamente fica próprio: **massa/atraso dos ALVOS** (molas de
segunda ordem), corpo das mãos-marionete, fios, matéria e câmera. Ninguém escreve ossos à mão.

Aviso sobre a fonte: `/opt/godot/doc/doc/classes/*.xml` do 4.7.2 instalado traz **só assinaturas** (sem
descrições). As APIs abaixo vêm desses XML; o **comportamento** foi medido nas sondas (seção 3), não
copiado da skill GodotPrompter (que tem exemplos desatualizados, ex.: `FABRIK3D.bone_chain`, que não existe
no 4.7).

## 1. Evidência (migrada do sandbox para o repositório no pré-voo da rodada 2)

| O quê | Caminho |
|---|---|
| Manequim sintético esfolado em código (40 ossos, pesos por vértice, saia em 4 cadeias, olhos) | `tools/research/native_character/nc_rig.gd` |
| Rig REAL do contrato (cópia somente-leitura de `claude/funny-hawking-air6xk` @ `b8ddadf`) | `src/procedural/{rig_data,miku_rig,hand_rig}.gd`, `assets/meshes/{miku,hand}_rig*.json` |
| Poses-chave geradas em código (`rest * delta`, só trilhas de rotação) | `tools/research/native_character/nc_poses.gd` |
| Personagem na pilha nativa (diretor → árvore → modificadores) | `tools/research/native_character/nc_miku.gd` |
| Mão-marionete (esqueleto próprio, `HandRig`), fio com tensão, mola | `nc_puppet_hand.gd`, `nc_thread.gd`, `nc_spring.gd` |
| Demo de 12 s com roteiro (calma → foco → falha → frustração → recuperação) | `nc_demo.gd`, `nc_demo.tscn` |
| Sondas (asserções medidas; linhas `R ...`) | `probe_basic.gd`, `probe_semantics.gd`, `probe_followup.gd`, `probe_followup2.gd`, `probe_real_rig.gd`, `probe_twist.gd` |
| Saída das sondas | `docs/research/evidence/native-character/probe_results.txt` |
| Custo de CPU (headless) e A/B renderizado | `tools/research/native_character/bench.gd` → `docs/research/evidence/native-character/bench_results.txt` |
| Gravação (Movie Maker, `--fixed-fps 30`, Forward+, Xvfb/llvmpipe) | `docs/research/evidence/native-character/native_character_demo.mp4` |
| Folha de contato (1 quadro a cada 0,5 s) | `docs/research/evidence/native-character/contact_sheet.jpg` (os 12 quadros cheios ficaram só no sandbox) |
| Gravar de novo | `tools/research/native_character/record.sh docs/research/evidence/native-character 12` |

Comandos: `godot --headless --path . -s res://tools/research/native_character/<probe>.gd`;
`godot --headless --path . -s res://tools/research/native_character/bench.gd`;
`tools/_display.sh godot --path . res://tools/research/native_character/nc_demo.tscn -- --measure [--strip=modifiers|all] [--hands=N]`.

### Inspeção da gravação (quadros conferidos)

- 0–1,4 s: calma, olha o orbe; respiração aditiva e os laços a↔b dos estados mantêm o corpo vivo, sem pose congelada.
- 1,4–2,6 s: percebe o usuário. No inset da cabeça (canto inferior direito) o rosto fica frontal em 2,0 s.
  O peito chega por último (cadeia com atrasos).
- 2,3–3,0 s: invocação. O braço direito sobe por `TwoBoneIK3D`, com antecipação vinda da mola do alvo (`r < 0`).
  O fio **nasce do dedo** e cresce; **depois** a mão aparece e chega com massa (quadro 2,9 s: fio já
  desenhado, mão ainda surgindo).
- 3,4–6,0 s: foco. Conduz a mão, que segue o dedo ampliado com atraso; o indicador aponta para a mão (`AimModifier3D`).
- 6,0 s: o orbe falha (âmbar). Em 6,15 s ela perde a compostura: transição de 0,25 s para `frustrated`
  (rígida, ombros altos), olhar travado em bloco (molas da cadeia rígidas) e recuo do corpo, que faz a
  saia/dedos (`SpringBone`) seguirem. Em 6,35 s o *flick* do braço esquerdo (`OneShot` filtrado) convoca mais
  2 mãos. Fios esticados (sem barriga); controle seco e rápido.
- 8,6–10,4 s: recuperação. Expira fundo (Add2 com mais profundidade e menos frequência), olha a própria mão,
  as mãos extras se retiram e os fios afrouxam e somem.
- 10,4–12 s: calma; olha o usuário de novo.
- Defeitos vistos que **não** são da pilha: as mãos do `HandRig` leem como "capuz" (o toco do antebraço
  domina, vista de costas) e o recorte serrilhado da silhueta da escultura. Ficam para a direção de arte e o
  modelador. Pose de frustração do braço esquerdo (mão perto do rosto) legível mas pouco elegante: é
  tuning de chave, não limitação.

## 2. Arquitetura proposta (camadas)

```
MIKU MIND (próprio, puro)            humor, compostura, atenção, tarefa, agenda de micro-comportamentos
   │  intenções (vocabulário)
ACTION VOCABULARY (próprio)          LOOK_AT_USER, SUMMON_HAND, GRAB_FILE… → pedidos de movimento c/ tempos
   │
ANIMATION DIRECTOR (próprio)         escolhe/blenda. Escreve SÓ: parâmetros da árvore (travel, add_amount,
   │                                 blend_position, timescale, one-shot), alvos (Node3D) via molas de 2ª
   │                                 ordem, influências dos modificadores. NUNCA escreve osso.
ANIMATION TREE (nativo, manual)      SM de estados de corpo + camadas (Add2 respiração, Blend/BlendSpace
   │                                 de compostura, OneShot de gestos filtrados por osso, TimeScale = tempo)
SKELETON MODIFIERS (nativo, ordem)   LookAt peito→pescoço→cabeça(→olhos) · TwoBoneIK braços · Aim dedo/palma
   │                                 · BoneTwistDisperser antebraço · [modificador GDScript próprio, se
   │                                 preciso] · LimitAngularVelocity (rede de segurança)
SECONDARY MOTION (nativo)            SpringBoneSimulator3D: saia, cabelo (com ossos), dedos (MIKU e mãos)
   │  BoneAttachment3D (pose PÓS-modificador)
PUPPET HAND SYSTEM (próprio+nativo)  pool de N mãos: corpo da mão = mola própria (massa, atraso, overshoot,
                                     inclinação contra a aceleração). Dedos = AnimationTree próprio
                                     (BlendSpace1D grip) + SpringBone + LimitAngVel. Fios = geometria
                                     própria com tensão/presença. Matéria reage ao aperto.
```

**Ordem por quadro** (determinística sob Movie Maker; ADR-015, `MotionClock`):
1. `dt` do `MotionClock`. Mente → vocabulário → diretor (atualiza molas dos alvos e parâmetros).
2. `AnimationTree.advance(dt)` (modo `MANUAL`; **síncrono**: a pose sai na hora).
3. `Skeleton3D.advance(dt)` (modo `MANUAL`; **adiado**: os modificadores rodam no update do esqueleto, no fim do quadro).
4. Em `skeleton_updated` (ou lendo `BoneAttachment3D`): âncoras pós-modificador (ponta do dedo) → fios →
   alvos das mãos → `step` das mãos → matéria. No spike, as mãos leem a âncora do quadro anterior (1 quadro
   de atraso), o que serve de *overlap* mas precisa ser consciente. Para o mesmo quadro, dirigir as mãos a
   partir de `skeleton_updated`.

### Cadeia causal INTENÇÃO → ANTECIPAÇÃO → GESTO → FIO → MÃO → MATÉRIA → RESULTADO

| Elo | Quem executa | Como se preserva a ordem |
|---|---|---|
| Intenção | MIND | evento → intenção (vocabulário) |
| Antecipação | DIRECTOR + TREE | o olhar sai antes (molas rápidas olhos/cabeça, peito por último). O alvo do braço com `r < 0` recua antes de ir. Chaves de antecipação no `OneShot` (o *flick* recua aos 0,28 s antes de sair) |
| Gesto | TREE (OneShot/estado) + IK (influência por mola) | a influência do IK sobe por mola, sem degrau |
| Fio | PUPPET (próprio) | presença do fio **gated** pelo progresso do gesto (no produto: `IK influence > ~0,7` ou marcador do OneShot); nasce da ponta lida **pós-modificador** |
| Mão | PUPPET (mola própria + árvore/springs nativos) | presença **gated** pelo fio ter chegado. A mola tem massa: nunca responde no mesmo quadro |
| Matéria | mundo-obra (próprio) | reage ao aperto/posição da mão, não ao relógio |
| Resultado | MIND | sucesso/falha volta como evento |

No spike os elos foram roteirizados em tempos fixos (2,3 → 2,4 → 2,75 s). No produto cada elo deve ser
disparado pelo **estado** do elo anterior, e não pelo relógio, para a cadeia nunca inverter.

### O que continua procedural próprio, e por quê

- **Mente, compostura, agenda**: é a personalidade, e nenhum nó a substitui.
- **Molas de 2ª ordem nos ALVOS** (olhar por estágio, alcance, polo, influências, raiz flutuante): os
  modificadores nativos resolvem *geometria* sem massa. `LookAt.duration` é uma interpolação temporal de
  troca de alvo e **não** dá atraso a um alvo em movimento (sonda P-10). `LimitAngularVelocity` dá rampa
  **linear** (P-11). Antecipação (`r<0`), overshoot (`zeta<1`) e *overlap* por estágio vêm das molas.
- **Corpo das mãos-marionete** (posição/orientação com massa) e **pool**: não há nó nativo de "corpo
  rígido cinemático com massa até um alvo".
- **Fios** (curva, tensão, presença): não são ossos. `SplineIK3D` move ossos ao longo de curva, não desenha corda.
- **Raiz da figura flutuante** (flutuar, recuo na falha, inclinar): transform do nó por mola.
- **Mapeamento compostura → parâmetros** (sintonia das molas, profundidade/frequência da respiração,
  `blend` de compostura, limiar do limitador): é aqui que "quanto mais frustrada, menos humana" vira número.

## 3. Comportamento medido no 4.7.2 (sondas)

| # | Achado | Medida |
|---|---|---|
| P-01 | `Skeleton3D.advance()` em `MANUAL` é **adiado**; a saída dos modificadores é **transitória** (após o update a pose volta à pré-modificador) | `get_bone_pose_rotation` após `advance` = identidade; em `modification_processed` = olhando o alvo; quadro seguinte = identidade |
| P-02 | Ler pose pós-modificador: **`BoneAttachment3D`** ou dentro de `skeleton_updated`. `get_bone_global_pose` no `_process` devolve a pose **pré**-modificador | mão R: attachment (-0,35, 1,25, 0,35) = alvo; `_process` (-0,305, 0,91, 0,02) = repouso |
| P-03 | `skeleton_updated` não é emitido quando nenhum modificador válido processa | `updates=0` sem modificadores / só um IK inválido |
| P-04 | `AnimationTree.advance(dt)` em `MANUAL` é **síncrono** | pose escrita na chamada |
| P-05 | Transição `Start→estado` padrão é `ADVANCE_MODE_ENABLED`: a SM fica presa em `Start` (pose de repouso, sem erro). Usar `AUTO` ou `start()` | `advance_mode` padrão = 1 |
| P-06 | `Add2` é aditivo **relativo ao REST** (também em repouso não-identidade) | rig real: base `rest·Rx(0,10)` + add `rest·Rx(-0,05)` → `0,0500` |
| P-07 | `Add2`/`Blend2` com `sync=false`: entrada com peso 0 **congela o relógio**. Camada contínua (respiração) precisa de `sync=true` | após 0,5 s em 0 → 1: peito −0,049 (`sync=false`) vs −0,103 (`true`) |
| P-08 | `OneShot` com filtro de osso isola o gesto | `upper_arm.L` 63,6°; ossos fora do filtro intactos |
| P-09 | `travel()` com `xfade_time`/`xfade_curve` faz transição suave | clavícula 2,0°→8,5° em 0,6 s |
| P-10 | `LookAtModifier3D.relative` (padrão `false` no 4.7) **descarta** a pose animada do osso; `true` preserva | inclinação animada 17,2° → 0,0° (`false`) / 17,2° (`true`); rig real: erro 0,00°, cadeia distribui (peito 16°, pescoço 30°, cabeça 48°) |
| P-11 | `primary/secondary_limit_angle` é o **arco total** (±metade) | limite 60/120/160 → 30/60/80° |
| P-12 | `LookAt.duration`: interpolação temporal na **troca/salto** de alvo (linear 1 s: 3°…90°), **sem atraso** com alvo em movimento contínuo. `is_interpolating()` vem **invertido** (false durante, true no fim) | `get_interpolation_remaining` 0,97→0 com `is_interpolating=false`; 0 → `true` |
| P-13 | `LimitAngularVelocityModifier3D` = teto de velocidade constante → **rampa linear**. Limita a saída dos modificadores anteriores na ordem. Só atua nos ossos das cadeias. `joint_count` lê 0 antes do 1º update | 180°/s → exatamente 6°/quadro; osso fora da cadeia moveu 68,8° num quadro |
| P-14 | `TwoBoneIK3D` com **nó de polo**: exato; fora de alcance estica na direção do alvo. **Sem nó de polo** (nem com `pole_direction` enum/vetor) **não faz nada, em silêncio**, nos dois rigs | erro 0,0000 (com polo) vs mão parada (sem polo) |
| P-15 | IK iterativo com padrões (`max_iterations=4`, `angular_delta_limit=2°`) **não converge** (a pose é restaurada a cada quadro; sem *warm start*) | erro constante 0,546 m; com 16 it/30°: CCD 0,0003, FABRIK 0,0001, Jacobian 0,0188 |
| P-16 | `SpringBoneSimulator3D` é determinístico com `dt` manual e **assenta na pose animada** (não no repouso) | 2 execuções idênticas; osso girado pela animação assenta em (0, 0,878, −0,479) = pose animada |
| P-17 | Appearance: trilhas **só de rotação** preservam escala/posição de repouso+pose. Uma trilha de **posição** apaga a appearance a cada quadro | escala do peito (1,2, 1, 1,15) mantida; pescoço 0,273 → 0,21 com trilha de posição |
| P-18 | Modificadores respeitam appearance aplicada antes **e** mudada em runtime (rig real, `MikuRig.apply_appearance`) | IK erro 0,0000, LookAt 0,00° nos dois casos |
| P-19 | `AimModifier3D` exato; `CopyTransformModifier3D` funciona | erro 3e-6°; eixos globais iguais |
| P-20 | `BoneTwistDisperser3D` só funciona se a fonte da torção estiver **além** do osso final (`extend_end_bone` ou `end = middle.0.R`) **e** com `twist_from_rest=true`; sem isso produz lixo | 80° no pulso: sem config 0/0/80; sem `from_rest` −46/−52/−190; `even` 27/30/29; `weighted forearm→middle.0` 40/42 |
| P-21 | Modificador GDScript próprio (`_process_modification_with_delta`) roda na ordem dos filhos | `NCStamp` cronometra a pilha |
| P-22 | 4.7: `AnimationNodeBlendSpace1D.add_blend_point` sem nome gera aviso de depreciação | passar `name` |

## 4. Avaliação por recurso

| Recurso | Para quê na MIKU | Decisão | Por quê / armadilhas 4.7.2 | Custo (µs/rig/quadro, CPU) |
|---|---|---|---|---|
| `AnimationTree` (manual) | estados de corpo, camadas, gestos | **ADOTAR** | síncrono e determinístico com `dt` do `MotionClock`. Só trilhas de rotação (P-17) | 42–57 (árvore completa da MIKU) |
| `AnimationNodeStateMachine` | modos discretos: calm/focus/frustrated/recover (não "idle/walk/run") | **ADOTAR** | `travel` + xfade por aresta (perde a compostura em 0,25 s, recupera em 1,2–1,6 s). `Start→` em `AUTO` (P-05) | incl. acima |
| `AnimationNodeBlendTree` + `Add2` | respiração, peso, micro-vida aditiva | **ADOTAR** | aditivo relativo ao repouso (P-06); **`sync=true`** (P-07); profundidade = `add_amount`, frequência = `TimeScale` | incl. |
| `Blend2/3`, `BlendSpace1D` | **contínuo de compostura** (humana ↔ não-humana) dentro de um estado; dedos das mãos (grip) | **ADOTAR** | a emoção é contínua, a SM é discreta: a SM escolhe o modo, o blend dá o grau. Nomear pontos (P-22) | incl. |
| `AnimationNodeOneShot` (+ filtros) | gestos com antecipação (flick, apontar, chamar), por parte do corpo | **ADOTAR** | filtro de osso isola (P-08). `fadein/out` curtos. Antecipação vai nas chaves | incl. |
| Filtros de ossos | camadas por região (tronco/braço E/D/dedos) | **ADOTAR** | `set_filter_path("Skeleton3D:osso")` | — |
| `AnimationNodeTimeScale` | tempo da mente (`tempo()` da rodada 1) | **ADOTAR** | respiração e loops seguem o humor | — |
| `SkeletonModifier3D` (ordem/influência) | pipeline após a árvore | **ADOTAR** | ordem = filhos. Saída transitória (P-01/P-02). Influência é o botão do diretor | — |
| `LookAtModifier3D` | olhar peito→pescoço→cabeça(→olhos) com limites | **ADOTAR** | `relative=true` (P-10); limites = arco total (P-11). Atrasos **só** via molas próprias nos alvos (P-12). `is_interpolating` invertido | 3–4 por osso; 11–14 cadeia de 5 |
| `AimModifier3D` | indicador aponta a mão/obra; palma para o objeto | **ADOTAR** | exato, barato; eixo `+Y` no rig do contrato | 2–4 |
| `TwoBoneIK3D` | braços/mãos alcançando alvos procedurais | **ADOTAR** | **nó de polo obrigatório** (P-14); o osso final herda a rotação local (orientar a mão com Aim/animação) | 7–8 |
| `CCDIK3D` / `FABRIK3D` | dedos em contato com objeto, cadeia de coluna inclinando para alvo | **CONDICIONAL** | só com `max_iterations`/`angular_delta_limit` ajustados (P-15) e limites (`JointLimitationCone3D`). Não para o braço (move a clavícula junto) | 9–15 (16 it) |
| `JacobianIK3D` | — | **REJEITAR** | 2–4× o custo e convergência pior aqui | 30–32 |
| `ChainIK3D` / `IterateIK3D` | bases abstratas | n/a | não se instanciam | — |
| `SplineIK3D` | cabelo/cauda ao longo de curva (se houver ossos) | **CONDICIONAL (não agora)** | roda, mas o resultado não foi verificado visualmente; o fio de intenção **não** é cadeia de ossos | 6–7 |
| `SpringBoneSimulator3D` | saia, cabelo (com ossos), follow-through de dedos (MIKU e mãos) | **ADOTAR** | determinístico (P-16); assenta na pose animada. Uma cadeia de saia balança como bloco (pedir multi-cadeia) | 16–24 (5 cadeias) |
| `SpringBoneCollision*` | saia contra quadris/coxas | **CONDICIONAL** | útil com saia multi-cadeia; não validado contra penetração no spike | — |
| `BoneConstraint3D` | base de Aim/Copy/Convert | n/a | — | — |
| `CopyTransformModifier3D` | acoplamentos (espelhar curvatura de dedos, ribcage↔chest) | **CONDICIONAL** | funciona (P-19); sem necessidade imediata | 2–3 |
| `ConvertTransformModifier3D` | acoplar canais (ex.: flexão do punho → abertura dos dedos) | **CONDICIONAL** | só API conferida, não exercitado | — |
| `LimitAngularVelocityModifier3D` | rede de segurança anti-estalo (troca de alvo, teleporte, influência em degrau) | **ADOTAR só como segurança** | rampa **linear** (P-13) = proibido como dinâmica. Limiar alto (300–900°/s); nunca como "peso" | 2–3 |
| `BoneTwistDisperser3D` | candy-wrapper no pulso (o rig não tem ossos de torção) | **ADOTAR (config. específica)** | fonte além do osso final + `twist_from_rest` (P-20). Configuração do spike: `forearm.R → middle.0.R`, `WEIGHTED` | 2–3 |
| `BoneAttachment3D` | âncoras pós-modificador (ponta do dedo para o fio, cabeça para câmera) | **ADOTAR** | única leitura pós-modificador fora do sinal (P-02) | — |
| Modificador GDScript próprio | camada própria **dentro** do pipeline, se algo precisar de ossos após a árvore | **CONDICIONAL** | funciona (P-21); usar só se um efeito não couber em alvos/parâmetros | — |
| `RetargetModifier3D`, `XR*Modifier3D`, `SkeletonIK3D` (antigo) | — | **REJEITAR** | sem fontes externas de animação; `SkeletonIK3D` é legado | — |

### Custos medidos

CPU headless (4 vCPU compartilhadas com outros workers do Godot, N=16 rigs, 120 quadros; variação de
±30% entre execuções; arquivo `bench_results.txt`):
- MIKU completa no rig real: **árvore ~43 µs + pilha de modificadores ~43 µs** por quadro (LookAt×3, TwoBoneIK,
  Aim, TwistDisperser, LimitAngVel, SpringBone 11 cadeias).
- Mão-marionete (árvore BlendSpace + SpringBone 5 cadeias + LimitAngVel + molas próprias): **35–45 µs/mão**.
  32 mãos ≈ 1,1 ms/quadro. O "quantidade sem limite arbitrário" cabe com folga até dezenas.
- No demo renderizado: árvore 85–150 µs e pilha 60–105 µs por quadro (HUD). O quadro inteiro no llvmpipe
  (1600×900, sombras, glow, inset) leva centenas de ms e é **dominado pelo render**; o A/B com camadas
  desligadas fica dentro do ruído de carga (seção "A/B renderizado" em `bench_results.txt`). Skinning é na
  GPU e não foi medido aqui.

## 5. Bugs e comportamentos estranhos do 4.7.2

1. `TwoBoneIK3D` sem nó de polo não faz nada, sem erro nem aviso (também com `pole_direction` enum/vetor). Se for
   o único modificador, o esqueleto nem emite `skeleton_updated` (P-03/P-14).
2. `LookAtModifier3D.is_interpolating()` retorna o inverso do esperado (P-12).
3. `BoneTwistDisperser3D` com a configuração "natural" (`root=upper_arm`, `end=hand`) não faz nada; com
   `twist_from_rest=false` produz torções absurdas (−190°) (P-20).
4. IK iterativo com valores padrão parece "não funcionar" (erro constante) por não acumular entre quadros (P-15).
5. A SM de código fica presa em `Start` sem aviso se a 1ª transição não for `AUTO` (P-05).
6. `sync=false` (padrão) congela o relógio de entradas com peso 0 em nós de blend (P-07).
7. `LookAtModifier3D.relative` padrão `false` (mudança do 4.7) apaga a pose animada do osso (P-10).
8. `add_blend_point` sem nome está depreciado (aviso) (P-22).
9. Em todas as execuções headless do 4.7.2, ao sair aparecem avisos de RID/ObjectDB "leaked at exit". O mesmo acontece no
   projeto; não é do spike.
10. (rodada 2, STEP 1) `AnimationNodeAdd2.add_amount` começa em **0**: um ramo aditivo de peso cheio fica mudo,
   sem aviso, até ser aberto (`= 1`). Achado na 1ª tomada OLD vs NEW (peso, tensão e one-shots sem efeito).
11. (rodada 2, STEP 1) `AnimationNodeStateMachinePlayback.travel()` pedido **durante** um xfade não o
   interrompe: o novo xfade só começa quando o atual termina (sonda: a→b de 1 s, `travel(c)` aos 0,5 s → b
   completo em 1,0 s, depois b→c). Sem estalo, mas com atraso de até um xfade inteiro: a resposta imediata
   precisa de uma camada contínua (o `BlendSpace1D` de compostura). `AnimationNodeTimeScale` acima da máquina
   escala também os xfades (1 s a ×2 = 0,5 s): para xfades em segundos reais, o `TimeScale` vai dentro de cada estado.

## 6. Ligação com o rig do procedural-modeler

Testado no rig REAL (`MikuRig`, 49 ossos; `HandRig`, 23 ossos; convenção `+Y` junta→filha, `+Z` lado da dobra,
`+X = Y×Z`, `+X` flexiona, `.R` espelhado em Y/Z):
- Funciona como está: LookAt em `chest/neck/head` (`forward_axis=+Z`); TwoBoneIK em
  `upper_arm/forearm/hand` (com polo); Aim em `index.0.R` (`+Y`); SpringBone em `skirt.0..2` e em todos os
  dedos (`*.0 → *.tip`: as pontas como ossos ajudam); `HandRig` com SpringBone nos 5 dedos e BlendSpace de
  grip (`+X` curva); `apply_appearance` antes e durante a execução (P-18).
- Poses em código: chave = `rest * Quaternion.from_euler(delta)` com `delta` na convenção do rig. Uma trilha de
  rotação guarda a pose local **absoluta** (não um offset). O `Add2` faz o offset relativo ao repouso.
- **Appearance**: o animador escreve **só rotação**. Nenhuma trilha de posição/escala em ossos de appearance
  (`root`, `upper_arm.*`, `neck`, `head`, `ribcage`) (P-17).
- Pedidos ao modelador (para a próxima rodada, se a direção quiser):
  1. ossos de olho `eye.L/R` (filhos de `head`, `+Z` à frente) **ou** olhar por shader. Sem eles a cadeia termina na cabeça;
  2. cadeia de cabelo sob `hair_root` (`hair.0..n`) se o cabelo for de ossos (SpringBone). Senão o cabelo
     continua procedural (fitas) preso em `hair_root`;
  3. saia em várias cadeias (ex.: `skirt.f/b/l/r.0..2`). Uma cadeia só balança a saia como bloco;
  4. torção: `BoneTwistDisperser3D` resolve o candy-wrapper do pulso sem ossos novos (P-20).

## 7. Plano de migração do spike da rodada 1 (sem perder aprendizado)

A rodada 1 do animador (`src/miku/{mind,motion,body}`, `src/entities/living/*`) escreve ossos à mão
(`pose_rig.gd: set_bone_pose_rotation`, `limb_ik.gd`, saia pendular, cadeia de olhar em matemática própria).

| Rodada 1 | Destino | Mantém |
|---|---|---|
| `mind/miku_mind.gd`, `micro_agenda.gd`, `miku_params.gd` | **ficam** (MIND) | tudo |
| `motion/second_order*.gd` | **ficam**, movidos para os ALVOS (olhar por estágio, alcance, polo, influências, raiz) | parâmetros f/zeta/r |
| `motion/miku_motor.gd` (camadas) | vira o **ANIMATION DIRECTOR**: mesmas entradas, saídas = parâmetros/alvos/influências | constantes de tuning (ex.: `SHARE_CHEST/NECK/HEAD` → influências; `NECK_LAG/CHEST_LAG` → frequência das molas por estágio; `EYES/HEAD_CALM/STIFF` → sintonia por rigidez) |
| `motion/pose_rig.gd` | **sai**. As poses viram `Animation` geradas em código (`rest*delta`) | os valores das poses |
| `motion/limb_ik.gd`, `arm_channel.gd` | **saem** → `TwoBoneIK3D` + polo (+ Aim para a mão) | os alvos/polos que `ArmChannel` calculava |
| `motion/finger_set.gd`, `hand_poses.gd` | **saem** → chaves + `BlendSpace1D` + SpringBone | as poses de dedos |
| saia pendular | **sai** → SpringBone | rigidez/arrasto como ponto de partida |
| `entities/living/hand_dynamics.gd`, `hand_pool.gd`, `puppet_hand.gd` | **ficam** (corpo da mão = mola) + árvore/springs nativos nos dedos | massa/atraso/força |
| `intent_threads.gd`, `thread_cycle.gd`, mundo-obra | **ficam** | — |

Passos (cada um gravado lado a lado com o anterior, para a regressão aparecer no vídeo e não só no código):
1. Diretor + árvore com as poses da rodada 1 assadas em `Animation` (sem modificadores); paridade visual.
2. Olhar → LookAt ×3 com as molas da rodada 1 nos alvos.
3. Braços → TwoBoneIK (polo obrigatório) + Aim; remover `limb_ik`.
4. Secundário → SpringBone (saia, dedos); remover o pêndulo.
5. Remover `pose_rig`. Testes: manter os de lógica pura (molas, mente). Adicionar testes de **configuração** (todo
   `TwoBoneIK3D` tem polo; `Start` em `AUTO`; `relative=true`; camadas contínuas com `sync=true`; nenhuma trilha de
   posição/escala em ossos de appearance) e de **mapeamento** do diretor (compostura → parâmetros).

## 8. Limites do spike

- llvmpipe e máquina compartilhada: os custos de CPU são ordem de grandeza; não há medição de GPU/skinning no
  alvo Windows.
- `SplineIK3D`, `ConvertTransformModifier3D` e colisões de SpringBone: só API/custo, sem verificação visual.
- O roteiro do demo usa tempos fixos (ver a cadeia causal: no produto, gating por estado).
- O rig real foi copiado (somente leitura) para o sandbox. A fonte é do procedural-modeler.
