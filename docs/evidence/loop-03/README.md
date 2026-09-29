# Evidências — Loop 3 (experiência interativa + build Windows)

Dono: coordenador. Jogo completo com HUD nativo.

| Conjunto | Comando | Qualidade |
|---|---|---|
| `*.png` (raiz, 01–13) | `tools/capture_evidence.sh docs/evidence/loop-03 --quality=high` | HIGH (referência) |
| `low/*.png` | `tools/capture_evidence.sh docs/evidence/loop-03/low --quality=low` | LOW (perfil sem GPU dedicada) |
| `720p/*.png` | `tools/capture_evidence.sh docs/evidence/loop-03/720p --quality=high --resolution=1280x720` | HIGH, 1280×720 |
| `smoke_source.txt` | `tools/smoke_test.sh` (UI obrigatória) | AUTO (LOW neste contêiner) |
| `smoke_windows_pack.txt` | `tools/smoke_test.sh --pack build/windows/KoriumUniverse.exe` | AUTO |

Capturas 10–13 exercitam inspector, OBSERVATORY no meio da verificação, foco de câmera numa semente e HUD oculto (H) com o selo mantido.
Conjunto final após a rodada `docs/contracts/loop-03-fixes.md`.
Renderização por software (Xvfb + Mesa lavapipe/llvmpipe), 1600×900, Forward+.
