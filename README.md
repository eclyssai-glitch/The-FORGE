# KORIUM UNIVERSE

Jogo desktop de simulação e visualização tridimensional: agentes e projetos representados como
estruturas vivas dentro de um universo imersivo. Feito com **Godot 4.7.2** para **Windows x86_64**.

> **DEMO MODE** — esta versão usa exclusivamente eventos simulados, locais e determinísticos.
> Funciona offline. Não se conecta a nenhum serviço, provedor ou sistema externo.

## Rodar

- Abrir no editor Godot 4.7.2 (`project.godot`) e pressionar F5, ou
- `godot --path .` (Linux) / baixar a build Windows gerada por `tools/export_windows.sh`.

Controles: `Espaço` iniciar/pausar · `R` reiniciar · `1` UNIVERSE · `2` FORGE · `3` OBSERVATORY ·
arrastar com o mouse para orbitar · roda para zoom · `WASD` para voar no UNIVERSE · `C` recentrar câmera ·
`Esc` limpar seleção · `F11` tela cheia.

## Desenvolvimento

```bash
tools/setup_godot.sh          # Godot 4.7.2 + templates (verificados)
tools/run_tests.sh            # testes GUT
tools/smoke_test.sh           # joga a demo no renderizador real e verifica
tools/capture_evidence.sh docs/evidence/latest
tools/export_windows.sh       # build Windows + zip + sha256
```

Documentação em `docs/` (índice em `CLAUDE.md`). Estado dos loops: `docs/LOOPS.md`.

## Licenças de terceiros

- Godot Engine — MIT (`licenses/GODOT_LICENSE.txt`, copiado para cada build exportada).
- GUT 9.7.0 — MIT (`addons/gut/LICENSE.md`; somente desenvolvimento, fora das builds).
- Inter e IBM Plex Mono — SIL Open Font License 1.1 (`licenses/*-OFL.txt`).
