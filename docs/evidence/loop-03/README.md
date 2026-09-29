# Evidências — Loop 3 (experiência interativa + build Windows)

Dono: coordenador. Jogo completo com HUD nativo.

| Conjunto | Comando | Qualidade |
|---|---|---|
| `*.png` (raiz, 01–12) | `tools/capture_evidence.sh docs/evidence/loop-03 --quality=high` | HIGH (referência) |
| `low/*.png` | `tools/capture_evidence.sh docs/evidence/loop-03/low --quality=low` | LOW (perfil sem GPU dedicada) |
| `smoke_source.txt` | `tools/smoke_test.sh` (UI obrigatória) | AUTO (LOW neste contêiner) |
| `smoke_windows_pack.txt` | `tools/smoke_test.sh --pack build/windows/KoriumUniverse.exe` | AUTO |

Capturas 10–12 exercitam inspector, OBSERVATORY no meio da verificação e foco de câmera numa semente.
Renderização por software (Xvfb + Mesa lavapipe/llvmpipe), 1600×900, Forward+.
