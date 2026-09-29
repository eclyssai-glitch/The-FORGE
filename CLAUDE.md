# KORIUM UNIVERSE — regras permanentes

Jogo desktop (Godot 4.7, GDScript) de simulação e visualização 3D: agentes e projetos como
estruturas vivas num universo imersivo. Alvo: executável nativo **Windows x86_64**.
**Versão atual: DEMO MODE — somente eventos simulados, locais e determinísticos.**

## Isolamento (inegociável)

- Projeto independente. Nunca acessar, importar, modificar ou conectar qualquer componente,
  repositório, dado ou infraestrutura da KORIUM original.
- Nunca conectar provedores reais, APIs comerciais, rede, telemetria, autenticação ou pagamentos.
  O jogo funciona 100% offline. Nada na UI pode sugerir conexão real.
- Nunca usar Next.js, React Three Fiber ou arquitetura dependente de navegador.
- Nunca versionar segredos. Nenhuma variável de ambiente é necessária.
- Não usar imagens estáticas para simular funcionalidade 3D não implementada.

## Stack

Godot **4.7.2-stable** (Forward+, fallback D3D12/OpenGL no Windows) · GDScript tipado ·
GUT 9.7.0 (testes, vendorizado em `addons/gut`) · fontes OFL em `assets/fonts`.
Nada de motor gráfico próprio: usar nós, recursos e shaders do Godot.
Novo addon/asset só com necessidade concreta, licença verificada, auditoria e registro em `docs/DECISIONS.md`.

## Arquitetura (detalhes em `docs/ARCHITECTURE.md`)

- `src/events` é lógica pura (RefCounted): sem nós, sem relógio, sem aleatoriedade.
- O autoload `Simulation` é o único produtor de eventos; o visual é função de
  `Simulation.world` + `Simulation.time` (pausa/seek/reset sempre consistentes).
- `Session` guarda modo/seleção; `Quality` guarda o perfil gráfico. UI e mundo 3D só
  conversam por esses autoloads.
- `src/style/palette.gd` é a única fonte de cor, tipografia e tempos de movimento.

## Escritor único por área

Cada área tem **um** agente escritor (mapa completo em `docs/AGENTS_AND_SKILLS.md`).
Nenhum agente edita área alheia; pede a mudança ao dono. O `technical-auditor` nunca escreve código.

## Comandos

- `tools/run_tests.sh` — testes GUT headless (falha também em erro de parse)
- `tools/smoke_test.sh [--pack build/windows/KoriumUniverse.exe]` — joga a demo no renderizador real
- `tools/capture_evidence.sh docs/evidence/loop-NN` — capturas de cada fase e modo
- `tools/export_windows.sh` — build Windows em `build/windows/` + zip + sha256
- `tools/setup_godot.sh` — instala Godot 4.7.2 + templates (verificação SHA512)

## Processo

- Loops de escopo delimitado; estado persistente em `docs/LOOPS.md`. Fechar com a skill `loop-checkpoint`.
- Nada é "concluído" sem evidência: testes verdes, smoke PASS e capturas do jogo rodando, inspecionadas.
- Quem implementa não aprova sozinho: auditoria pelo `technical-auditor` (+ `art-director` se visual).
- Decisões técnicas → `docs/DECISIONS.md`.

## Documentos (um dono, uma responsabilidade)

`docs/PRODUCT.md` visão/escopo/aceitação · `docs/ARCHITECTURE.md` camadas e fluxo ·
`docs/VISUAL_DIRECTION.md` direção de arte · `docs/ENGINE.md` mundo, render, qualidade ·
`docs/PROCEDURAL.md` modelagem procedural · `docs/ANIMATION.md` câmeras, animação, VFX ·
`docs/DEMO_EVENTS.md` eventos simulados · `docs/BUILD.md` build Windows e validação ·
`docs/AGENTS_AND_SKILLS.md` agentes/skills · `docs/DECISIONS.md` · `docs/LOOPS.md`.
