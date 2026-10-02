# Build Windows e validação

Dono: `game-engineer`. Responsabilidade: como gerar, verificar e validar o executável.

## Gerar

```bash
tools/setup_godot.sh        # uma vez: Godot 4.7.2 + templates (SHA512 verificado)
tools/export_windows.sh     # build/windows/KoriumUniverse.exe + build/KoriumUniverse-<ver>-windows-x86_64.zip(.sha256)
```

Preset: `export_presets.cfg` → "Windows Desktop", x86_64, PCK embutido, BPTC/S3TC,
metadados de versão no executável. Excluídos do pacote: `addons/gut`, `tests`, `tools`, `docs`, `.claude`, `build`.
`build/` entrou no `exclude_filter` no Loop 5 (Fase 3): no Godot 4 todo `.json` é recurso (`JSON`) e `all_resources`
o exporta — dumps do inspector ou capturas gravados em `build/` iam parar no PCK. Conferir o conteúdo do pacote:
`tools/pck_list.py build/windows/KoriumUniverse.exe [--grep=<trecho>] [--sizes]`.
No Windows com o editor instalado: *Project → Export → Windows Desktop*, ou
`Godot_v4.7.2-stable_win64.exe --headless --export-release "Windows Desktop" build/windows/KoriumUniverse.exe`.

## Reprodutibilidade

Um mesmo commit gera o mesmo `.exe` e o mesmo zip, byte a byte, em qualquer checkout limpo:

- `project.godot` → `editor/export/convert_text_resources_to_binary=false`. Com a conversão ligada
  (padrão do 4.7), o export carrega cada `.tscn` e o regrava como `.scn` binário em
  `.godot/exported/`; nossas cenas não trazem `unique_id=` nos nós, então o carregamento sorteia um
  ID por nó e o `.scn` (campo `node_ids`) muda a cada conversão — `hud.scn`, `main.scn` e `world.scn`
  diferiam entre dois checkouts do mesmo commit. Sem a conversão, as cenas vão ao PCK como o texto
  versionado e carregam normalmente (o smoke do pack as usa). Custo: poucos KB e parse de texto de
  três cenas pequenas no carregamento.
- Zip: arquivos em ordem fixa, `zip -X`, mtimes = data do último commit (`git log -1 --format=%ct`).
- Pré-requisito: árvore sem mudanças locais (o export usa os arquivos do disco, não o commit).
- Observação (Loop 5, Fase 3): o import do Godot regrava `default_bus_layout.tres` (acrescenta
  `uid="uid://fxi7fabt56xw"` e remove `bus/0/volume_db = 0.0`). A regravação é determinística — dois checkouts
  limpos ficam iguais —, mas um checkout em que o arquivo foi restaurado ao versionado exporta outro
  `uid_cache.bin` (sem esse UID) e o `.exe` muda. Correção definitiva: o dono (sound-designer) versionar o arquivo
  na forma regravada pelo motor. A ordem de `global_script_class_cache.cfg` também depende de o `.godot/` ser
  importado do zero ou incrementalmente: compare sempre exports com `.godot/` novo.

Verificação: dois checkouts limpos (`git worktree add`) do mesmo commit, cada um com `.godot/`
importado do zero, rodando `tools/export_windows.sh`, e um terceiro export num deles após apagar
`.godot/exported` → SHA-256 idênticos do `.exe` e do zip. Um editor Godot diferente de 4.7.2-stable
ou outros templates mudam o binário.

## Validação no contêiner (automatizada)

| Verificação | Comando |
|---|---|
| Export reproduzível (mesmo `.exe` e mesmo zip para o mesmo commit) | `tools/export_windows.sh` em dois checkouts limpos e comparar SHA-256 |
| Pacote exato do `.exe` executado no renderizador real | `tools/smoke_test.sh --pack build/windows/KoriumUniverse.exe` (o motor roda num diretório temporário vazio: com `--main-pack`, arquivos `res://` ausentes do pacote são lidos do diretório de trabalho — rodando da raiz do projeto, o que o export deixou de fora seria achado no disco) |
| Conteúdo do PCK (nada de `tools/`, `tests/`, `docs/`, `build/`) | `tools/pck_list.py build/windows/KoriumUniverse.exe --grep=tools/` (saída 1 = nada encontrado) |
| Jogo a partir do código | `tools/smoke_test.sh` e `tools/capture_evidence.sh` |
| Cenário GENESIS | `tools/smoke_test.sh --scenario=genesis`, `tools/capture_evidence.sh <dir> --scenario=genesis` |
| Style frames GENESIS (≥ 6, HUD oculto, 1920×1080) | `tools/style_frames.sh <dir> [--quality=<nível>]` (HIGH por padrão) |
| Vídeo do jogo real GENESIS com áudio (MP4 H.264 + AAC) | `tools/record_genesis.sh [--hud=off] [--resolution=WxH]` |
| Cenário LIVING (Loop 5): roteiro + pedidos reais + config mutada e revertida | `tools/smoke_test.sh --scenario=living`, `tools/capture_evidence.sh <dir> --scenario=living` |
| Vídeo do protótipo LIVING com interações reais e áudio | `tools/record_living.sh [--hud=off] [--resolution=WxH] [--until=<s>]` |
| Gate de causalidade de MIKU (dev) | `tools/record_living.sh --inspect-every=1 --causality=require`, `tools/inspector/causality.py <dumps>` (seção "Gate de causalidade"); o smoke LIVING relata `causality=PASS\|FAIL n/m` |

O smoke reprova se: `RESULT=FAIL`, falta a linha `RESULT`, há `SCRIPT ERROR`/`Parse Error` no log,
a linha `modules=N/M` tem N ≠ M (script de entidade, fx, áudio ou câmera do cenário ativo ausente/quebrado;
ORIGIN e GENESIS esperam 10 cada, `AudioDirector` incluso), o mundo não está composto para o cenário
ativo, faltam no GENESIS as âncoras de áudio `planet`/`miku`/`hands` (linha `audio=present anchors=`), falta a linha
`ui=` ou ela é `ui=absent` (HUD sem os grupos `ui_transport`/`demo_badge`), ou o tempo esgota.
Com UI presente, o jogo aciona `Start`/`Pause`/`Reset` do transporte e exige o selo DEMO visível nos três
modos. `SMOKE_ALLOW_MISSING_UI=1 tools/smoke_test.sh` passa `--allow-missing-ui` ao jogo e tolera
apenas `ui=absent` (branches em que a UI ainda não existe); nunca usar para validar uma entrega.
Argumentos extras chegam ao jogo: `tools/smoke_test.sh --scenario=genesis` joga o cenário GENESIS
(relatório com `scenario=genesis`, `phase=COMPLETE layers=3/3 moons=2/2`, `mission_objectives=10/10`).
Até o animator entregar os módulos GENESIS esse smoke reprova com `modules=2/10` e
`FAIL audio anchors missing` — esperado na Fase B; o ORIGIN (padrão) segue PASS com `modules=10/10`.
Sem placa de som (Linux sem `/dev/snd`, contêiner/CI), smoke, capturas e style frames passam
`--audio-driver Dummy` ao jogo (`GODOT_AUDIO_FLAGS`, `tools/_proc.sh`; `AUDIO_DRIVER=<nome>` força outro):
o `AudioDirector` roda igual, nada é ouvido, e o log não traz mais as falhas do ALSA.

Encerramento robusto (Xvfb + lavapipe às vezes não encerra o Godot após o último quadro):

- Os dois scripts rodam o jogo numa sessão própria (`setsid`, `tools/_proc.sh`) e, ao final — normal,
  por tempo, por Ctrl-C/TERM —, matam a sessão inteira (godot, xvfb-run, Xvfb): nenhum processo órfão.
- Smoke: `TIMEOUT` (padrão 240 s) total; após a linha `RESULT=` o motor tem `SMOKE_GRACE` s
  (padrão 15) para sair, senão é encerrado ("forced exit after result") e o veredito vem do log. No
  LIVING o jogo anuncia `smoke_deadline_seconds=N` (pior caso de uma execução correta, derivado dos planos) e o
  script passa a usar `N + SMOKE_BOOT_SLACK` (30 s) como guarda contra travamento, se maior que `TIMEOUT`
  (`PROC_TIMEOUT_FN` em `tools/_proc.sh`). Não é um timeout global maior: quem reprova por tempo é o próprio
  jogo, pelo orçamento derivado (abaixo).
- Capturas: `--timeout=<s>` ou `CAPTURE_TIMEOUT` (padrão 900 s). A lista de PNG esperados vem de
  `CAPTURES` em `src/core/automation.gd` (ou `CAPTURES_GENESIS` com `--scenario=genesis`, que também é
  repassado ao jogo; filtrada por `--capture-only`); só contam PNG gravados
  nesta execução. Todos presentes → saída 0, mesmo se foi preciso encerrar o motor
  ("forced exit after captures", `CAPTURE_GRACE` s após o último, padrão 15); falta algum → saída 1.
  `--resolution=WxH` (padrão 1600x900) define a janela do jogo e a tela do Xvfb (ex.: conjunto
  1280×720 com `--resolution=1280x720`); formato inválido → saída 2.
- Style frames: `tools/style_frames.sh <dir>` roda `--scenario=genesis --style-frames=<dir>` em janela e
  Xvfb 1920×1080; `--timeout=<s>` ou `STYLE_TIMEOUT` (padrão 600 s), `STYLE_GRACE` (15 s). Saída 0 só se o
  manifesto `style_frames.txt` e cada PNG listado foram gravados nesta execução, são ≥ 6 e cada um mede
  1920×1080 (lido do cabeçalho IHDR do PNG).
- No jogo (`automation.gd`, só em `--capture`/`--smoke-test`/`--style-frames`): o fade de entrada é
  concluído antes da 1ª captura (brilho determinístico); a saída passa por `Main.quit_game` (para todos
  os players de áudio e espera 0,25 s, para o `AudioServer` liberar as playbacks — sem isso o motor relata
  "resources still in use at exit" da ambiência) e, se o laço principal não terminar em 3 s, o processo
  se mata (`OS.kill`).

Limitação registrada (ADR-007): o `.exe` não executa sob o Wine 9.0 disponível neste ambiente
(falha do Wine anterior ao código do jogo). O conteúdo do jogo dentro do `.exe` é validado
executando-o com o runtime oficial Godot 4.7.2. O código específico do Windows (template,
drivers gráficos do Windows, janela) só é validado pelo checklist abaixo, numa máquina Windows.

## Validação local no Windows (checklist)

1. Extraia o zip; confira o SHA-256 (`certutil -hashfile <zip> SHA256`) com o `.sha256`.
2. Execute `KoriumUniverse.exe`. Esperado: janela maximizada, fade de entrada, selo **DEMO MODE ·
   SIMULATED EVENTS** no canto superior esquerdo (visível em todos os modos, também com o HUD oculto).
3. HUD: barra de modos no topo, SETTINGS no canto superior direito (qualidade AUTO/LOW/MEDIUM/HIGH/ULTRA,
   câmera cinematográfica ON/OFF, lista de teclas), transporte embaixo (START ou PAUSE conforme o estado,
   RESET, linha do tempo, tempo, fase, velocidade 0.5×/1×/2×/4×).
4. Teclado: `Espaço` inicia/pausa, `R` reinicia, `1/2/3` alternam UNIVERSE/FORGE/OBSERVATORY, `V` liga/desliga
   a câmera cinematográfica, `H` oculta/mostra o HUD, `Esc` limpa a seleção, `C` reposiciona a câmera,
   `F11` alterna tela cheia. Mouse: arrastar orbita, roda aproxima/afasta.
5. Painéis por modo: FORGE mostra CONSTRUCT (camadas) + EVENTS; UNIVERSE mostra SITES + EVENTS;
   OBSERVATORY mostra a folha MISSION/VERIFICATION/ENTITIES/EVENT LOG. Clicar numa entidade (no mundo ou
   numa lista) abre o inspetor à direita; **FOCUS** enquadra a entidade, `×` ou `Esc` limpa a seleção.
6. Assista à demo completa (~50 s): 7 fases visíveis; OBSERVATORY mostra 7/7 objetivos.
7. Opcional, teste automatizado: `KoriumUniverse.exe -- --smoke-test` e leia
   `%APPDATA%\Godot\app_userdata\KORIUM UNIVERSE\smoke_report.txt` (esperado `modules=10/10`, `audio=present`,
   `ui=present` e `RESULT=PASS`; um módulo do mundo que não carregou ou a UI ausente reprova o smoke).

## Builds registradas

`.exe` e zip são reproduzíveis por commit (ver *Reprodutibilidade*); hashes registrados por commit de origem.

| Versão | Commit de origem | Zip (bytes) | SHA-256 do zip | SHA-256 do `.exe` | Smoke | Reproduzido em checkout limpo |
|---|---|---|---|---|---|---|
| 0.1.0 | `214a02a` | `KoriumUniverse-0.1.0-windows-x86_64.zip` (38 716 033) | `26af2ef57f95b72d23f2a066b7f9ffdb36baf136f0330166648855e1a0c1e95f` | `a4fcdc5b4c7d0eaab2029405babe9aa12e9107601745b578eca4d86f27ec6a81` | smoke do pack PASS (modules 9/9, ui=present, selo 3/3) | sim |

## Vídeo-review

Roteiro e requisitos: `docs/contracts/review-video.md`. Ferramenta (fora do export: `tools/*` está em
`exclude_filter`): `tools/review/review_tour.tscn` + `review_tour.gd` instanciam `scenes/main.tscn`, forçam
HIGH (`Quality.override_for_session`) e seguem o roteiro por **tempo de jogo** (soma de `delta`), com
interações reais — teclas via `Input.parse_input_event`, cliques/arrasto da timeline/órbita como
`InputEventMouseButton`/`InputEventMouseMotion` no centro dos controles do HUD. Legendas de fase entram com
`Simulation.event_emitted`; legenda, cartões e anel do ponteiro ficam numa CanvasLayer acima do HUD (Palette/UiTheme).

```bash
tools/record_review.sh                                   # 1600x900 → build/review/korium_universe_review_v0.1.0.mp4
tools/record_review.sh --until=15 --resolution=960x540   # prévia curta → ..._preview.mp4
```

Grava `build/review/korium_review.avi` com o Movie Maker (`--write-movie`, `--fixed-fps 30`) sob Xvfb
(`tools/_proc.sh`; `--timeout=<s>`/`REVIEW_TIMEOUT`, padrão 5400 s — renderização em software, dezenas de
minutos) e codifica com ffmpeg (libx264, CRF 22, yuv420p, `+faststart`, sem áudio); imprime duração e tamanho.
O Movie Maker grava no tamanho de janela do projeto (1600x900) qualquer que seja `--resolution`; o MP4 é
escalado para a resolução pedida. Log: `build/review/record.log`. Depuração sem gravar:
`godot --path . res://tools/review/review_tour.tscn -- --review-snap=<dir>` salva PNG após cada passo.

## Gravação GENESIS com áudio (`tools/record_genesis.sh`, Loop 4 r1)

Grava o **jogo real** jogando o cenário GENESIS com som, para a revisão do art-critic (critério 6) e para a
remixagem do sound-designer. Ferramenta fora do export: `tools/review/genesis_tour.tscn` + `genesis_tour.gd`
instanciam `scenes/main.tscn` (o jogo roda com `--scenario=genesis`), forçam a qualidade
(`Quality.override_for_session`, HIGH por padrão — o AUTO mediria os 30 fps fixos e rebaixaria), põem FORGE +
câmera cinematográfica (`Session.set_cinematic(true)`: os planos da história do animator), HUD visível ou oculto
(`Session.set_hud_visible`; o selo DEMO fica sempre), esperam 0,5 s no quadro parado (fade de entrada), chamam
`Simulation.start()` e, 56 s + 4 s de respiro depois, saem por `Main.quit_game` (áudio silenciado antes).
Tudo por tempo de jogo (soma de `delta` = 1/30 s com o Movie Maker); nenhuma interação simulada.

```bash
tools/record_genesis.sh                                   # 1920x1080, HUD on → build/review/genesis_1920x1080_hud-on.mp4
tools/record_genesis.sh --hud=off                         # tomada limpa (só o selo DEMO)
tools/record_genesis.sh --until=12 --resolution=960x540   # prévia curta → ..._preview.mp4
tools/record_genesis.sh --from=42 --resolution=960x540    # só um trecho: seek para T+42 antes de começar
```

Opções: `--hud=on|off`, `--resolution=WxH` (janela, tela Xvfb e vídeo; padrão 1920x1080), `--until=<s>`
(segundos de tour; o demo começa em 0,5 s), `--from=<s>` (seek antes do start), `--quality=low|medium|high|ultra`,
`--crf=<n>` (x264, padrão 18), `--timeout=<s>`/`GENESIS_TIMEOUT` (padrão 5400 s), `GENESIS_GRACE` (120 s após
`[genesis] done`). Saída: `build/review/genesis_<W>x<H>_hud-<on|off>[_from<s>][_preview].{avi,mp4,log}`.

- **Movie Maker** (`--write-movie`, `--fixed-fps 30`): com ele o Godot mistura o áudio pelo driver Dummy do próprio
  motor e grava PCM 16 bits 48 kHz estéreo no AVI (não precisa de placa de som). O script reprova se o AVI não tem
  stream de áudio.
- **Tamanho do vídeo**: o Movie Maker dimensiona o AVI por `display/window/size/viewport_width/height`, ignorando
  `--resolution` e redimensionamentos posteriores (quadros reescalados para 1600x900 — por isso o
  `record_review.sh` sai sempre 1600x900). O script escreve um `override.cfg` do Godot na raiz do projeto
  (tamanho pedido, janela normal), apaga-o assim que o motor iniciou (linha `Movie Maker mode enabled`; também no
  `trap` de saída) e confere que a gravação saiu no tamanho pedido. Se já existir um `override.cfg`, recusa rodar
  (nunca sobrescreve). `/override.cfg` está no `.gitignore`.
- **Codificação**: ffmpeg H.264 (`-preset slow -crf 18`, yuv420p, `+faststart`) + AAC 192 kb/s 48 kHz. O script
  imprime duração, quadros, tamanho, streams (`video h264,W,H,30/1 · audio aac,48000,2`) e o EBU R128 do áudio
  gravado (`I`, `LRA`, pico verdadeiro).
- Custo no contêiner (llvmpipe): ~0,7 s por quadro em 960x540 (~25 min para a tomada inteira); 1920x1080 leva
  ~4×. A duração do MP4 é a do tour + ~0,25 s (o silêncio de `quit_game`).

Prova (r1): `--until=12 --resolution=960x540` → `genesis_960x540_hud-on_preview.mp4`, 12,27 s, 368 quadros,
`h264 960x540 30/1` + `aac 48000 2`, I −20,7 LUFS, LRA 12,0 LU, pico −8,0 dBFS; quadros em 1/4/8/11,5 s
inspecionados (MIKU despertando no plano cinematográfico, legendas de fase, HUD, selo DEMO;
`docs/evidence/loop-04/engine-r1/record_preview12_frames.jpg`). Tomada inteira `--resolution=960x540 --hud=off`:
1179 s de gravação, `genesis_960x540_hud-off.mp4` 60,77 s, 1823 quadros, 26,2 MB, `aac 48000 2`, I −21,2 LUFS,
LRA 8,1 LU, pico −6,1 dBFS; tour `done t=60.52 sim=T+56.00 status=COMPLETE`; quadros em 2/25/48/58 s em
`record_full_frames.jpg` (só o selo DEMO; a maior variação de luma entre quadros é 2,1/255 — `docs/ENGINE.md`).

## Qualidade das capturas

`tools/capture_evidence.sh` e `tools/style_frames.sh` rodam em **HIGH** salvo `--quality=<nível>` (`auto` mantém a
detecção). Motivo (Loop 4 r1): sob Xvfb + llvmpipe o AUTO detecta CPU → LOW, e os quadros julgados pelo
art-critic saíam em LOW (sem MSAA, sombra mais grossa) em vez do perfil-alvo (desktop com GPU dedicada). Cada
linha `[capture]`/`[style-frame]` do log traz `quality=<nível>`. Smoke continua em AUTO.

## LIVING (Loop 5): smoke, capturas e gravação com interações reais

**Smoke** — `tools/smoke_test.sh --scenario=living`: o roteiro (140 s) a 8×, depois nove pedidos pelos caminhos
reais da `Session` (clique em MIKU, clique em VESPER, "Miku!", "Miku, trabalhe no planeta da direita", "Miku,
aumente sua altura", `appearance.height 1.04`, "Miku, ombros um pouco mais largos", "Miku, me dê asas", "Miku,
fique mais curiosa, mas menos impulsiva"); cada um precisa terminar com o status esperado (`request ... ->
KIND/ROUTE status`, `requests=9/9`), a configuração precisa mudar de verdade (`config_mutated=true`, altura
1,000 → 1,040) e voltar exatamente ao estado do jogador (`config_reverted=true`, snapshot do arquivo de
`user://miku`). Depois: pausa segura, `seek_refused=true`, `reset_ok=true recomposed=true` e a UI. Linha
`interaction executor=miku|null provider=unavailable` e `interaction protocol=correlated|legacy`.

*Orçamento derivado (Loop 5 R2, sem timeout fixo).* Antes de jogar, `Automation.living_budget()` pré-visualiza os
planos dos nove pedidos (`InteractionRouter.preview_plan`, sem efeitos) e soma as estimativas do corpo
(`estimate_plan` → `Miku.estimate_duration`; sem ela, `ActionVocabulary.NOMINAL_SECONDS`):
`orçamento = roteiro + Σ estimativas + margem`, `margem = 30 s + 0,5 × Σ estimativas + 3 s por pedido`; o roteiro
vale o tempo real **medido** dele (nunca menos que o nominal 140 s / 8 = 17,5 s — no llvmpipe, a ~2 fps, o teto de
delta por quadro faz o roteiro levar ~66 s).
Usar mais que o orçamento reprova (`FAIL living_budget used=… budget=…`). Cada pedido é esperado **pelo seu id**:
`Session.interaction_started` (reconhecimento em ≤ 2 s, senão FAIL) → `Session.interaction_reported` com o mesmo
`id`, até o pior caso do plano (`started.deadline` = Σ timeouts dos passos) + 3 s — o roteador sempre termina um
plano até lá. Relatório por pedido: `request #<request_id> … steps=n/n real=…s est=…s ack=…s first_step=…s
failures= timeouts= cancelled=` e uma linha por passo (`step i AÇÃO finished|failed|timeout|cancelled real= est=
timeout=`); no fim `step_failures= timeouts= cancellations= ignored_events=`. Com corpo correlacionado, um passo
por timeout reprova o pedido; no caminho legado (corpo sem `action_event`) vira `WARN`. Primeiro passo iniciado
depois de 0,3 s do envio: `WARN`. Enquanto os módulos do animator não existem,
`SMOKE_ALLOW_MISSING_MODULES=1` (passa `--allow-missing-modules`) transforma a falta em `WARN` — nunca usar para
validar a entrega integrada.

**Capturas** — `tools/capture_evidence.sh <dir> --scenario=living`: sem seek, o cenário **joga em tempo real**
desde T+0 e cada PNG de `CAPTURES_LIVING` (15: vida, 1/2/4 mãos, etapas, falha, compostura perdida, recuperação,
atenção, alvo, arquivo de config, config aplicada, SEMANTIC recusado, HUD oculto) sai quando `Simulation.time`
chega ao tempo dele; os `LivingScript.USER_CUES` são injetados como entrada real (`LivingCuePlayer`). A
configuração do jogador é zerada para a execução e restaurada no fim. Limite padrão 2400 s (`--timeout`).

**Gravação** — `tools/record_living.sh` (baseado em `record_genesis.sh`: Movie Maker 30 fps, `override.cfg`
temporário, MP4 H.264 + AAC, EBU R128): `tools/review/living_tour.tscn` joga o protótipo com câmera
cinematográfica e, nos testes 5–7, **injeta interações reais** por `Input.parse_input_event` (`InputInjector`):
clique do mouse num ponto do corpo de seleção de MIKU que o `Picker` resolve para `miku` (T+90), clique em VESPER
(T+102), Enter + "Miku, aumente sua altura" digitado caractere a caractere na linha de chamada + Enter (T+115) e o
pedido SEMANTIC sem provider (T+130). Cada cue imprime `[living] cue ... real input` ou, se não houver corpo
clicável/linha focada, `fallback` (o pedido entra pela `Session` e o log diz). A tomada sempre começa do MIKU
versionado (configuração do jogador zerada e restaurada: `config_restored=true` na linha `[living] done`).
Opções: `--hud=on|off`, `--resolution=WxH`, `--until=<s>` (prévia), `--quality=`, `--crf=`,
`--timeout=`/`LIVING_TIMEOUT` (9000 s), `LIVING_GRACE` (120 s), `--inspect-every=<s>` (dumps do inspector),
`--causality[=require]` (gate de causalidade nos dumps; seção "Gate de causalidade"). Saída:
`build/review/living_<W>x<H>_hud-<on|off>[_preview].{avi,mp4,log}`.

## Inspector de desenvolvimento (Loop 5, Fase 3)

Ciclo **inspect → run → see → correct** sem MCP nem conexão: cada quadro capturado ganha um JSON com o estado do
jogo naquele mesmo quadro. **Somente desenvolvimento**: nunca vai ao `.exe`.

**Isolamento**

- Código em `tools/inspector/` (`dev_inspector.gd` — nó: dumps por captura, periódicos e F9, poses finais dos
  esqueletos; `inspector_collect.gd` — coleta pura; `summarize.py` — leitura), excluído do export por `tools/*`.
  Sem `class_name` (não entra no cache global de classes do pacote), sem autoload, nada em `project.godot`.
- Carregado **por caminho** (`load()`, nunca `preload`) por `Automation.load_inspector()` (`src/core/automation.gd`)
  só quando há `--inspect`/`--inspect-every` na linha de comando; `Main` cria a `Automation` também nesses casos.
  Sem o flag nada é carregado (`tests/integration/test_dev_inspector.gd`). Arquivo ausente (pacote exportado) →
  aviso `dev inspector ... not found (exported build?) - --inspect ignored.` e o jogo segue normal.
- O único vestígio no código de produção é o protocolo passivo `inspect_state()` (grupo `dev_inspect`; contrato em
  `docs/ARCHITECTURE.md`), que ninguém chama no jogo.

**Uso** (argumentos depois de `--`; os scripts repassam)

| Comando | Saída |
|---|---|
| `tools/capture_evidence.sh <dir> --scenario=living --inspect` | `<dir>/l07_failure.png` + `<dir>/l07_failure.json` (mesmo quadro) para cada captura; o script exige os dois |
| `tools/style_frames.sh <dir> --inspect` | `<frame>.json` ao lado de cada style frame |
| `godot --path . -- --scenario=living --inspect=build/inspect --inspect-every=2` | jogo normal + dump a cada 2 s de tempo de jogo (`inspect_<n>_f<quadro>.json` + `.png` do mesmo quadro; `--inspect-png=off` sem PNG; headless nunca grava PNG) e **F9** = dump agora |
| `tools/record_living.sh --inspect-every=1` | dumps sem PNG em `build/review/living_..._inspect/` (o vídeo tem os quadros; `motion_time` do dump = tempo do vídeo) |
| `tools/smoke_test.sh --inspect=build/inspect` | `smoke_end.json` com o estado ao fim do smoke |

Diretório: `--inspect=<dir>` (relativo à raiz do projeto, ou `user://…`); padrão `user://inspect`. Grave em
`docs/evidence/…`, `build/…` ou `user://` — pastas fora do export (um `.json` numa pasta exportada viraria recurso
do pacote).

**Conteúdo do JSON** (`format: korium-inspect/1`, chaves ordenadas, floats arredondados a 1e-5; ~70 KB no
GENESIS, ~170 KB com MIKU + uma mão)

- `frame`, `time`, `motion_time`, `movie`, `sim_time`, `sim_status`, `sim_speed`, `scenario`, `phase`, `mode`,
  `selected`, `hud`, `cinematic`, `call_line_open`, `quality`, `viewport`, `context` (captura, imagem, gatilho);
- `camera`: caminho, posição, direção, fov/near/far e, com `CameraDirector`, o rig (`target`, yaw, pitch, distância);
- `tree`: `{caminho: "Classe [script.gd] [hidden]"}` de todos os nós (limite 4000);
- `nodes`: nós relevantes — grupos `entity_*` e `dev_inspect`, `Skeleton3D`, `AnimationTree`, `AnimationPlayer`,
  `Camera3D`, `BoneAttachment3D` (classe, script, grupos, visível, transform global; limite 400);
- `skeletons`: por osso (limite 256) `index`, `parent`, `enabled`, `rest`, `pose` (pose de entrada, local),
  `pose_global`, `final`/`final_global` (pose **após** a cadeia de `SkeletonModifier3D`, gravada no sinal
  `skeleton_updated` — fora dele o Godot devolve a pose de entrada) e `world_position`; cada transform =
  `{pos, quat, euler_deg (YXZ), scale}`. `modifiers`: nome, classe, `active`, `influence`, propriedades próprias da
  classe (tudo abaixo de `Node3D`: ossos, alvos, eixos, limites, `settings/<i>/…` dos IK, variáveis de script),
  `targets` (NodePath → nó + posição no mundo) e `status` (`LookAtModifier3D`: interpolando, restante, alvo dentro
  do limite);
- `animation_trees`: `active`, raiz, `anim_player`, todos os `parameters/*` não-objeto e cada playback de state
  machine (`current_node`, `travel_path`, posição/duração, fade); `animation_players`: animação atual, posição;
- `sections`: `inspect_state()` de cada nó do grupo `dev_inspect` (no `living` hoje: `interaction` — ação do
  vocabulário em execução, plano, fila, último pedido, configuração; MIKU/mãos/fios/mundo-obra entram quando o
  animator implementar o contrato); `errors`: violações do contrato (não fatais).

**Leitura e correção**

```bash
tools/inspector/summarize.py <dir>/l07_failure.json                               # resumo
tools/inspector/summarize.py <dir>/l07_failure.json --bones=all --section=interaction
tools/inspector/summarize.py --diff antes/l07_failure.json depois/l07_failure.json --only=skeletons,sections
```

O diff compara folhas (números dentro de `--tol`, padrão 1e-4, são iguais), ignora `time`/`motion_time`/`frame` e
os rótulos da árvore (lista nós adicionados/removidos); `--all` inclui tudo.

**Prova de não contaminação (Fase 3, commit `f88c372`)**

- `tools/pck_list.py` no `.exe` de dois checkouts limpos (clone do commit, `.godot/` novo): 311 arquivos, nenhum em
  `tools/`, `tests/`, `docs/`, `build/`, `addons/gut/`; `uid_cache.bin` e `global_script_class_cache.cfg` do
  pacote sem caminho `res://tools/`; a única menção ao inspector no pacote é a string do caminho dentro de
  `automation.gdc` (o `load()` protegido). (`src/ui/inspector.gd` é o painel de entidade do HUD, outra coisa.)
- O primeiro export desta fase, feito com capturas de prova em `build/inspector-proof/`, empacotou os `.json` e
  `.png.import` delas (338 arquivos): origem da inclusão de `build/*` no `exclude_filter`.
- Pacote exportado com `--inspect --inspect-every=1`: `tools/smoke_test.sh --pack <exe> --inspect --inspect-every=1`
  → aviso `... not found (exported build?) - --inspect ignored.`, `modules=10/10`, `ui=present`, `RESULT=PASS`.
  Rodando o mesmo pacote a partir da raiz do projeto, o inspector **carregava** (fallback de `res://` para o disco):
  por isso o smoke de pacote agora roda num diretório vazio.
- Reprodutível: os dois checkouts limpos e um terceiro export num deles após apagar `.godot/exported` geraram o
  mesmo `.exe` (`6a04e64efce857e0ebfb366c28bf6725361a533751a5820f7ac0250e25a319f2`) e o mesmo zip
  (`4a211f7dffc2a7125ad4ef8f066d35b9279be0bd9053a982abe8b8833a6a0352`).

## Gate de causalidade (Loop 5 R2, `tools/inspector/causality.py`)

Contrato: `docs/contracts/loop-05-round2.md` ("Gate de causalidade"); formato dos carimbos: `docs/ANIMATION.md`
("Linha do tempo causal"). Cada dump do inspector traz em `sections.Miku` (`inspect_state()` de MIKU) o `clock` e
`causality`: as últimas 48 execuções `{request_id, step, action, channel, stage, phase, t: {intent, anticipation,
gesture, thread, hand, matter, result}}`. **Somente desenvolvimento** (stdlib Python; `tools/` fora do export).

```bash
tools/inspector/causality.py build/review/living_640x360_hud-on_inspect            # tabela + resumo
tools/inspector/causality.py <dir_ou_dumps...> --require                          # + cadeia completa nas grandes
tools/inspector/causality.py <dir> --failures-only                                # só as reprovadas
```

- **União**: dumps lidos em ordem de `frame`; uma execução = (sessão, `request_id`, `step`, `action`, `channel`,
  `stage`, `t.intent`) — o carimbo `intent` separa as repetições das ações dela (`request_id` 0); a sessão muda
  quando o relógio dela volta (reset/recomposição). Fica a cópia mais completa (mais carimbos, depois terminal).
  Uma cópia posterior que **muda** um carimbo, perde um, ou volta de terminal para "em curso" reprova.
- **Regras** (toda entrada): `intent` presente; as etapas presentes formam um prefixo de
  intent → anticipation → gesture → thread → hand → matter (`thread without gesture`); tempos não decrescentes
  (`gesture 12.4 before anticipation 12.5`); `result` existe exatamente quando `phase` é terminal e é ≥ todas
  (`result 5.0 before matter 6.0`); canal/fase/etapa conhecidos.
- **`--require`** (lista `REQUIRED` no script): uma execução **finished** de ação grande precisa da cadeia inteira
  até a etapa exigida — WORK no canal `task` com etapa de mundo (GATHER/CORE/LAYERS/ADJUST, inclui a história de
  falha: fissura, colapso e reconstrução furiosa são etapas da mesma obra) → `matter`; SUMMON_HANDS → `hand`;
  EDIT_FILE → `matter`; DISCARD → `gesture`; FRUSTRATED/ANGRY/RECOVER → `gesture`. Canceladas, falhas e em curso
  são verificadas só na ordem (uma ação interrompida pode parar cedo).
- Janela cheia sem nenhuma execução em comum com o dump anterior: `WARNING possible gap` (não reprova; aumente a
  frequência dos dumps).
- Saída: tabela por execução (PASS/FAIL + motivo, cadeia com `intent` absoluto e o resto relativo), resumo e a
  última linha `causality=PASS|FAIL <aprovadas>/<execuções>`. Exit 0 = tudo PASS, 1 = alguma FAIL, 2 = erro/sem dados.

**Integração**

| Comando | O que faz |
|---|---|
| `tools/record_living.sh --inspect-every=1 --causality[=require]` | no fim, checa `<base>_inspect/`; tabela em `<base>_causality.txt`; exit 1 em FAIL (depois de gravar o vídeo) |
| `tools/capture_evidence.sh <dir> --scenario=living --inspect --causality[=require]` | checa os `<shot>.json` desta execução (capturas espaçadas: lacunas são esperadas; a prova densa é a gravação) |
| `tools/smoke_test.sh --scenario=living` | o jogo grava a linha do tempo de MIKU a cada 0,5 s (`--causality-dir=<tmp>`, `causality_<n>_f<quadro>.json`, do início do roteiro ao fim dos pedidos + uma amostra final antes do reset; código do jogo, funciona com `--pack`) e relata `causality_samples=N`; o script roda `causality.py --require --failures-only` e imprime `causality=PASS|FAIL n/m`. FAIL = `WARN` (não reprova) até a violação conhecida abaixo ser corrigida; `SMOKE_CAUSALITY_STRICT=1` reprova; `SMOKE_CAUSALITY=0` desliga; sem `python3` = `causality=SKIPPED` |

**Testes**: `python3 tools/inspector/test_causality.py` (13 testes; fixtures em `tools/inspector/testdata/causality/`:
execução que evolui entre dumps, ordem invertida, etapa pulada, resultado antes da matéria, `--require` incompleto,
carimbo alterado, reset de sessão, lacuna, sem dados). `tests/integration/test_causality_gate.gd` roda esses testes
por `OS.execute("python3", …)` e passa dumps **reais** do inspector (nó com `inspect_state()` no formato do contrato)
pelo checador — PASS, depois FAIL com o motivo ao inverter uma ordem (pendente sem `python3`).

**Prova real (Loop 5 R2, código de `1e42982` + este gate; llvmpipe, Xvfb)**

- Gravação completa `tools/record_living.sh --resolution=640x360 --inspect-every=1` (4343 quadros, 144 dumps,
  T+0…T+144) → `causality.py --require`: **`causality=FAIL 34/36`**, `--require 13/13`, nenhuma lacuna. As 2
  reprovações são etapas da obra no canal `task`: `WORK task CORE` (intent 39,500) e `WORK task LAYERS` (intent
  58,033): `matter 39.500 before hand 40.467` — a matéria é carimbada no **mesmo quadro** em que a etapa abre,
  antes da mão dela. Causa (`src/miku/miku.gd`, `_drive_work`): `data["work"]` da etapa anterior continua ativo e as
  mãos da etapa anterior ainda estão tensas no lugar, então `k > 0,05` carimba `matter` da entrada nova. Correção
  pertence ao animator (dono de `src/miku`).
- Smoke `tools/smoke_test.sh --scenario=living` (8×, 248 amostras, 68 execuções): `RESULT=PASS`,
  **`causality=FAIL 65/68`** (WARN): três etapas `task` (LAYERS, ADJUST, GATHER) terminaram **sem** `matter`
  (ordem correta; só o `--require` reprova) — a 8× com ~2 fps o roteiro avança a etapa antes de a matéria responder
  às mãos dela.
- Prévia `tools/record_living.sh --until=30 --resolution=320x180 --inspect-every=1 --causality=require`:
  `causality=PASS 3/3`; `tools/capture_evidence.sh … --scenario=living --inspect --causality=require
  --capture-only=l02`: `causality=PASS 1/1`.
