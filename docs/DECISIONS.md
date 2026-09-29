# Decisões técnicas

Dono: coordenador. Formato: ADR curto (contexto → decisão → consequência).

## ADR-001 — Godot 4.7.2-stable, GDScript, Forward+
- Contexto: jogo desktop nativo para Windows; exigido Godot 4; sem motor próprio.
- Decisão: 4.7.2-stable (último estável, 2026-08-18), build padrão (não-.NET) com GDScript tipado;
  renderizador Forward+ (volumetric fog, SSAO, glow, AgX), com fallback automático D3D12/OpenGL no Windows.
- Consequência: nenhum SDK externo; binários oficiais verificados por SHA512 (`tools/setup_godot.sh`).

## ADR-002 — GUT 9.7.0 para testes
- Contexto: pesquisa de frameworks — GUT 9.7.0 declara compatibilidade com Godot 4.7; gdUnit4 6.2.1
  lista suporte até 4.7.1.
- Decisão: GUT 9.7.0 (MIT), vendorizado em `addons/gut`, excluído do export.
- Consequência: `tools/run_tests.sh` também falha em erro de parse, porque o GUT apenas avisa
  quando não consegue carregar um script de teste.

## ADR-003 — Câmera com Camera3D + Tween nativos (Phantom Camera avaliado e não adotado)
- Contexto: Phantom Camera v0.7.2 (MIT) oferece câmeras por prioridade com tweens.
- Decisão: usar `Camera3D` + `Tween` do motor num diretor de câmera próprio pequeno.
  Necessidades atuais (órbita, voo livre, planos por evento/modo) são cobertas pelo motor;
  o addon traria plugin de editor + autoload extra sem compatibilidade declarada com 4.7.2.
- Consequência: reavaliar se surgirem blends complexos entre muitos alvos.

## ADR-004 — Visual como função da simulação
- Decisão: entidades derivam o estado visual de `Simulation.world` (timestamps) + `Simulation.time`.
- Consequência: pausa, seek e reset são exatos; capturas determinísticas; sem tweens de simulação.

## ADR-005 — Fontes Inter e IBM Plex Mono (OFL) embarcadas
- Decisão: arquivos oficiais do repositório google/fonts com as licenças OFL em `licenses/`.
- Consequência: identidade tipográfica funciona offline.

## ADR-006 — Repositório de trabalho
- Contexto: a criação de um novo repositório privado foi negada à integração (HTTP 403,
  "Resource not accessible by integration").
- Decisão: desenvolver no repositório privado e vazio `eclyssai-glitch/The-FORGE`, branch
  `claude/funny-hawking-air6xk`, sem nenhum conteúdo da KORIUM. O histórico é transferível
  integralmente para um repositório novo quando ele existir.

## ADR-007 — Validação do executável Windows
- Contexto: no contêiner Linux, o Wine disponível (9.0) aborta em qualquer binário Godot 4.7.2 antes
  do `main`: o runtime MinGW chama `VirtualProtect(..., lpflOldProtect=NULL)`, que o Windows
  rejeita com erro e o `kernelbase` do Wine 9.0 derreferencia. Wine mais novo (WineHQ) está bloqueado pela rede.
- Decisão: validar (1) o export estrutural e reprodutível do `.exe`, e (2) o **pacote exato embutido
  no `.exe`**, executado com o runtime oficial 4.7.2 (`--main-pack`) no renderizador Forward+ real
  (Vulkan/lavapipe). A execução nativa no Windows fica registrada como validação local (`docs/BUILD.md`).
