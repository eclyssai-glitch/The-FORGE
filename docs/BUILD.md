# Build Windows e validação

Dono: `game-engineer`. Responsabilidade: como gerar, verificar e validar o executável.

## Gerar

```bash
tools/setup_godot.sh        # uma vez: Godot 4.7.2 + templates (SHA512 verificado)
tools/export_windows.sh     # build/windows/KoriumUniverse.exe + build/KoriumUniverse-<ver>-windows-x86_64.zip(.sha256)
```

Preset: `export_presets.cfg` → "Windows Desktop", x86_64, PCK embutido, BPTC/S3TC,
metadados de versão no executável. Excluídos do pacote: `addons/gut`, `tests`, `tools`, `docs`, `.claude`.
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

Verificação: dois checkouts limpos (`git worktree add`) do mesmo commit, cada um com `.godot/`
importado do zero, rodando `tools/export_windows.sh`, e um terceiro export num deles após apagar
`.godot/exported` → SHA-256 idênticos do `.exe` e do zip. Um editor Godot diferente de 4.7.2-stable
ou outros templates mudam o binário.

## Validação no contêiner (automatizada)

| Verificação | Comando |
|---|---|
| Export reproduzível (mesmo `.exe` e mesmo zip para o mesmo commit) | `tools/export_windows.sh` em dois checkouts limpos e comparar SHA-256 |
| Pacote exato do `.exe` executado no renderizador real | `tools/smoke_test.sh --pack build/windows/KoriumUniverse.exe` |
| Jogo a partir do código | `tools/smoke_test.sh` e `tools/capture_evidence.sh` |

O smoke reprova se: `RESULT=FAIL`, falta a linha `RESULT`, há `SCRIPT ERROR`/`Parse Error` no log,
a linha `modules=N/M` tem N ≠ M (script de entidade, fx ou câmera ausente/quebrado), falta a linha
`ui=` ou ela é `ui=absent` (HUD sem os grupos `ui_transport`/`demo_badge`), ou o tempo esgota.
Com UI presente, o jogo aciona `Start`/`Pause`/`Reset` do transporte e exige o selo DEMO visível nos três
modos. `SMOKE_ALLOW_MISSING_UI=1 tools/smoke_test.sh` passa `--allow-missing-ui` ao jogo e tolera
apenas `ui=absent` (branches em que a UI ainda não existe); nunca usar para validar uma entrega.

Encerramento robusto (Xvfb + lavapipe às vezes não encerra o Godot após o último quadro):

- Os dois scripts rodam o jogo numa sessão própria (`setsid`, `tools/_proc.sh`) e, ao final — normal,
  por tempo, por Ctrl-C/TERM —, matam a sessão inteira (godot, xvfb-run, Xvfb): nenhum processo órfão.
- Smoke: `TIMEOUT` (padrão 240 s) total; após a linha `RESULT=` o motor tem `SMOKE_GRACE` s
  (padrão 15) para sair, senão é encerrado ("forced exit after result") e o veredito vem do log.
- Capturas: `--timeout=<s>` ou `CAPTURE_TIMEOUT` (padrão 900 s). A lista de PNG esperados vem de
  `CAPTURES` em `src/core/automation.gd` (filtrada por `--capture-only`); só contam PNG gravados
  nesta execução. Todos presentes → saída 0, mesmo se foi preciso encerrar o motor
  ("forced exit after captures", `CAPTURE_GRACE` s após o último, padrão 15); falta algum → saída 1.
  `--resolution=WxH` (padrão 1600x900) define a janela do jogo e a tela do Xvfb (ex.: conjunto
  1280×720 com `--resolution=1280x720`); formato inválido → saída 2.
- No jogo (`automation.gd`, só em `--capture`/`--smoke-test`): o fade de entrada é concluído antes da
  1ª captura (brilho determinístico) e, se `quit()` não encerrar o laço principal em 3 s, o processo
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
   `%APPDATA%\Godot\app_userdata\KORIUM UNIVERSE\smoke_report.txt` (esperado `modules=9/9`,
   `ui=present` e `RESULT=PASS`; um módulo do mundo que não carregou ou a UI ausente reprova o smoke).

## Builds registradas

| Versão | Commit de origem | Zip | SHA-256 |
|---|---|---|---|
| (`.exe` e zip são reproduzíveis por commit — ver *Reprodutibilidade*; hashes registrados por commit de origem) | | | |
