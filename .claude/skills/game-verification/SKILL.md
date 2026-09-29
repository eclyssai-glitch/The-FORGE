---
name: game-verification
description: Verifica o KORIUM UNIVERSE executando o jogo de verdade — testes GUT, smoke test no renderizador real, capturas de cada fase da ORIGIN CHAMBER e de cada modo, export Windows e execução do pacote exportado — e inspeciona as imagens contra a direção visual. Use para validar qualquer mudança, antes de declarar algo concluído e ao fechar um loop.
compatibility: Requer Godot 4.7.2 (tools/setup_godot.sh). Em Linux sem display usa xvfb-run com Mesa (lavapipe/llvmpipe).
metadata:
  owner: technical-auditor
---

# Verificação do jogo

Compilar não prova nada. Esta skill produz evidência do jogo **rodando**.

## Passos

1. **Testes** — `tools/run_tests.sh`. Esperado: `All tests passed` e nenhuma linha de erro de parse
   (o script falha sozinho se houver).
2. **Smoke** — `tools/smoke_test.sh`. Esperado: `RESULT=PASS`, `events_received` = `expected`,
   `mission_objectives=7/7`, `pause_holds=true`, `reset_ok=true`. Registre `renderer`, `adapter`, `avg_fps`.
3. **Capturas** — `tools/capture_evidence.sh docs/evidence/loop-NN`. Gera
   `01_dormant_core` … `07_final_form`, `08_universe`, `09_observatory` (tempos em
   `src/core/automation.gd`). Em renderização por software, cada captura leva segundos: normal.
4. **Inspeção** — abra **cada** PNG e descreva o que aparece. Checklist:
   - [ ] Selo **DEMO MODE** visível em todas.
   - [ ] Cada fase distinguível só pela imagem (núcleo dormente → ativo → fragmentos → camadas →
         materiais/luz → varredura → forma final).
   - [ ] Um acento (EMBER) com função; PALE só na verificação; base monocromática.
   - [ ] Sujeito legível; UI não cobre o núcleo; hierarquia clara.
   - [ ] UNIVERSE, FORGE, OBSERVATORY são o mesmo universo.
   - [ ] Sem excesso de partículas, texto decorativo, estética genérica.
   - [ ] Nada sugere conexão real.
5. **Export** (quando o loop toca build) — `tools/export_windows.sh`, depois
   `tools/smoke_test.sh --pack build/windows/KoriumUniverse.exe` (roda o pacote exato do .exe).
   Execução nativa do `.exe` exige Windows; ver limitações em `docs/BUILD.md`.

## Saída

Comandos + resultados, lista de capturas com uma observação cada, itens do checklist que falharam, veredito.
