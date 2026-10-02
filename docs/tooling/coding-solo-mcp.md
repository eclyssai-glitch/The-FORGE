# Coding-Solo/godot-mcp — teste em sandbox (Loop 5, gate de ferramentas)

- Fonte fixada: https://github.com/Coding-Solo/godot-mcp @ `1209744fad78f3998f98c7394fd0f6ef50da5281`
  (merge do PR #99 "fix/rce-arbitrary-script-instantiation", 2026-04-16), `package.json` 0.1.1, MIT.
- Instalação no scratchpad (fora do projeto): `git clone` + `git checkout <sha>` + `npm ci --ignore-scripts`
  (`package-lock.json` do repositório; 44 pacotes; nenhum pacote com `hasInstallScript`) + `tsc` + `node scripts/build.js`.
  Nunca `npx` (baixaria a última versão).
- Dependências diretas: `@modelcontextprotocol/sdk@0.6.0`, `axios@1.12.2` (declarada, **não usada** no código
  compilado), `fs-extra@11.3.0`. Lifecycle: `prepare` (= build) — evitado com `--ignore-scripts`.
- Processos: `execFile(godot, ['--version'])`; `spawn(godot, ['-d', '--path', P, cena?])` para `run_project`;
  `spawn(godot, ['-e', '--path', P])` para `launch_editor`; operações de cena rodam `godot --headless --script
  build/scripts/godot_operations.gd` (escreve `.tscn`/`.tres`/uids no projeto — **não usar no projeto principal**).
- Rede: nenhuma chamada no código (sem fetch/http/sockets); só stdio MCP. Filesystem: leitura do projeto
  (`get_project_info` percorre a árvore); escrita apenas pelas ferramentas de edição de cena.

## Resultado do teste (Godot 4.7.2, xvfb + lavapipe) — `_mcp_probe/mcp_run.out.txt`

| Requisito | Resultado |
|---|---|
| 1. localizar o projeto | PASS (`list_projects`, `get_project_info`) |
| 2. executar Godot 4.7.2 | PASS (`get_godot_version` → 4.7.2.stable.official.ed1daf0bf) |
| 3. iniciar uma cena | PASS (`run_project` com `scene`; também a cena principal) |
| 4. capturar debug output | PASS (`get_debug_output`: stdout/stderr do processo) |
| 5. detectar erros de script | PASS — erro de runtime e de parse com arquivo:linha (`Debugger Break, Reason: …`, `*Frame 0 - res://…:7`) |
| 6. encerrar o processo | PASS (`stop_project`; nenhum processo Godot órfão depois) |

Limites: roda em `-d` (depurador local) — num erro, o jogo **pausa** no prompt `debug>` até `stop_project`; não
observa scene tree em execução, não captura quadro, não injeta input (não é runtime inspector). Requer display
(xvfb no contêiner; nativo no Windows).

Proposta de uso (somente quando aprovado): `.mcp.json` do sandbox apontando para o build local fixado
(`node <caminho>/build/index.js`, `GODOT_PATH=<godot 4.7.2>`), sem tocar `project.godot` nem `export_presets.cfg`.
