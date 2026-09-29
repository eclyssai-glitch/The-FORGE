# Produto — KORIUM UNIVERSE

Dono: coordenador. Responsabilidade: visão, escopo e critérios de aceitação.

## Visão

Um jogo desktop de simulação e visualização em que agentes e projetos aparecem como estruturas
vivas dentro de um único universo tridimensional. O jogador observa a criação, o
desenvolvimento e a evolução dessas estruturas — cada evento tem uma consequência visível.

## Versão 0.1 — DEMO MODE

Todos os eventos são **simulados, locais e determinísticos**. Não há rede, provedores,
contas, telemetria nem conexão com a KORIUM original. A interface identifica o modo em todas as telas.

## Ambientes (um único mundo, três modos)

| Modo | Propósito |
|---|---|
| UNIVERSE | Explorar o universo 3D: a ORIGIN CHAMBER e sementes dormentes de futuros construtos |
| FORGE | Acompanhar de perto a construção visual das estruturas |
| OBSERVATORY | Interface nativa de eventos, missões e resultados |

## Demonstração ORIGIN CHAMBER

1. O núcleo é ativado. 2. Fragmentos geométricos surgem. 3. A estrutura é semeada.
4. Camadas são adicionadas progressivamente. 5. A estrutura recebe materiais e iluminação.
6. Uma sequência de verificação é executada. 7. A estrutura assume a forma final.
O jogador pode iniciar, pausar, reiniciar, navegar no tempo e observar de qualquer ângulo.

## Critérios de aceitação (v0.1)

| # | Critério | Evidência exigida |
|---|---|---|
| 1 | Projeto Godot funcional | `tools/run_tests.sh` verde; jogo abre sem erros |
| 2 | Ambiente 3D navegável | Órbita/zoom/voo de câmera no jogo; capturas de UNIVERSE |
| 3 | Construção progressiva | Capturas das 7 fases; testes de blueprint procedural |
| 4 | Câmeras e animações | Planos por evento e por modo; transições suaves; capturas |
| 5 | Interface nativa funcional | Controles start/pause/reset/timeline, modos, inspector, observatory |
| 6 | Sistema de eventos simulados | Testes de roteiro/timeline/mundo; smoke `events_received = expected` |
| 7 | Testes e documentação | GUT + smoke + docs atualizados por loop |
| 8 | Build Windows exportada | `tools/export_windows.sh`; zip + SHA-256; pacote executado (ver `docs/BUILD.md`) |

## Estado de aceitação (v0.1.0, fechamento do Loop 3)

Critérios 1–7 atendidos com evidência em `docs/evidence/loop-03/` e auditoria em `docs/LOOPS.md`.
Critério 8 atendido no contêiner (export determinístico, SHA-256 registrado, pacote exato executado no
renderizador real); a execução nativa no Windows aguarda validação local pelo checklist de `docs/BUILD.md`.

## Fora de escopo nesta versão

Integrações reais, multiplayer, salvamento de progresso, áudio, localização, conteúdo além da ORIGIN CHAMBER.
