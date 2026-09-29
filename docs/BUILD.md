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

## Validação no contêiner (automatizada)

| Verificação | Comando |
|---|---|
| Export reproduzível (mesmo `.exe` e mesmo zip a cada execução) | `tools/export_windows.sh` duas vezes e comparar SHA-256 |
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
2. Execute `KoriumUniverse.exe`. Esperado: janela maximizada, fade de entrada, selo **DEMO MODE**.
3. (a partir do Loop 3) `Espaço` inicia/pausa, `R` reinicia, `1/2/3` alternam UNIVERSE/FORGE/OBSERVATORY,
   `V` liga/desliga a câmera cinematográfica, `H` oculta/mostra o HUD, `Esc` limpa a seleção, `F11` tela cheia.
4. (a partir do Loop 3) Assista à demo completa (~50 s): 7 fases visíveis; OBSERVATORY mostra 7/7 objetivos.
5. Opcional, teste automatizado: `KoriumUniverse.exe -- --smoke-test` e leia
   `%APPDATA%\Godot\app_userdata\KORIUM UNIVERSE\smoke_report.txt` (esperado `modules=9/9`,
   `ui=present` e `RESULT=PASS`; um módulo do mundo que não carregou ou a UI ausente reprova o smoke).

## Builds registradas

| Versão | Commit de origem | Zip | SHA-256 |
|---|---|---|---|
| (o zip é reproduzível para um mesmo commit: timestamps = data do commit; hashes registrados por commit de origem) | | | |
