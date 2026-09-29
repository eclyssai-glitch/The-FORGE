# Evidências — Loop 2 (motor visual)

Dono: coordenador. Jogo completo integrado (commit de captura: ver `git log -- docs/evidence/loop-02`).

| Conjunto | Comando | Qualidade | Uso |
|---|---|---|---|
| `*.png` (raiz) | `tools/capture_evidence.sh docs/evidence/loop-02 --quality=high` | HIGH | referência visual revisada pelo art-director |
| `low/*.png` | `tools/capture_evidence.sh docs/evidence/loop-02/low --quality=low` | LOW | perfil que o AUTO escolhe em GPU fraca/sem GPU e o do smoke; divergências registradas para o Loop 3 |
| `smoke_source.txt` | `tools/smoke_test.sh` | AUTO (LOW neste contêiner) | smoke do jogo a partir do código |

Renderização por software (Xvfb + Mesa lavapipe/llvmpipe), 1600×900, Forward+.
