---
name: loop-checkpoint
description: Fecha um loop de desenvolvimento do KORIUM UNIVERSE com verificação do jogo rodando, auditoria independente, registro persistente e commit/push Git. Use ao terminar o escopo de um loop, antes de iniciar o próximo, ou quando o trabalho precisar ser interrompido preservando o estado para retomada.
metadata:
  owner: coordinator
---

# Checkpoint de loop

Um loop só está concluído quando **todos** os passos têm evidência.

1. **Verificação** — skill `game-verification` completa (testes, smoke, capturas em
   `docs/evidence/loop-NN/`, export se aplicável). Vermelho → corrigir, não avançar.
2. **Auditoria independente** — agente `technical-auditor`; se houve mudança visível, também
   `art-director` sobre as capturas. BLOQUEANTE/P0 corrigidos pelo dono da área no mesmo loop e reauditados.
3. **Registro** — entrada em `docs/LOOPS.md` (modelo abaixo); decisões em `docs/DECISIONS.md`;
   atualizar só o documento dono de cada assunto alterado.
4. **Git** — commit `loop NN: <resultado verificável>` e push para o branch de trabalho.
   Builds (`build/`) não são versionados; registre tamanho e SHA-256 do zip em `docs/BUILD.md`.

## Modelo (docs/LOOPS.md)

```markdown
## Loop NN — <título> · <concluído | em andamento | interrompido>
- Escopo: …
- Entregue: …
- Verificação: testes X/X · smoke PASS (renderer, fps) · capturas docs/evidence/loop-NN/
- Auditoria: technical-auditor <veredito>; art-director <veredito>; achados tratados: …
- Decisões: ADR-…
- Pendências: …
- Retomada: <próximo comando/passo exato>
```

## Interrupção

Registre status `interrompido`, último passo concluído e próximo comando; commit
`loop NN (wip): …` e push. Nenhum estado só em memória.
