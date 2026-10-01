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

## ADR-008 — Supervisão de processos nas ferramentas de verificação
- Contexto: sob Xvfb + lavapipe o Godot pode não encerrar após concluir capturas/smoke, pendurando scripts.
- Decisão: `tools/_proc.sh` executa o jogo numa sessão própria (`setsid`), com timeout total e período de
  graça após o trabalho concluído; ao final sempre encerra a sessão inteira (godot, xvfb-run, Xvfb). No jogo,
  `automation.gd` agenda `OS.kill` do próprio processo 3 s após `quit()` (só nos modos de automação).
- Consequência: capturas/smoke nunca deixam órfãos; o veredito vem do log (`RESULT=`, PNGs gravados nesta execução).

## ADR-009 — Limiar único de clique × arrasto (`InputTuning`)
- Contexto: Picker (6 px em linha reta) e câmera (3 px acumulados) divergiam; arrastos orbitavam **e** selecionavam.
- Decisão: `src/core/input_tuning.gd` é a fonte única (`DRAG_THRESHOLD_PX`), medida por percurso acumulado,
  usada pelo Picker e pelo CameraDirector.

## ADR-010 — Movimento ambiente em tempo real
- Contexto: pausa/seek precisam ser exatos (ADR-004), mas um mundo totalmente congelado parece travado.
- Decisão: tudo que depende da simulação é função de `Simulation.world` + `Simulation.time`; apenas movimento
  ambiente sem significado narrativo (flutuação do núcleo, deriva de fragmentos soltos, deriva das sementes,
  poeira) usa tempo real e continua durante a pausa. Documentado em `docs/ANIMATION.md`.
- Consequência: capturas iguais em estado narrativo, com pequenas variações de pixel do movimento ambiente.

## ADR-011 — Transições de câmera no relógio de parede
- Contexto: o Godot limita o delta por frame (8/60 s); com frames lentos (ex.: renderização por software,
  ~0,4 s/frame) um `Tween` corria ~3× mais devagar que o tempo real, e o foco não assentava no tempo previsto.
- Decisão: o CameraDirector mistura planos com a mesma curva (`Tween.interpolate_value`, sine in-out,
  `Palette.T_CINEMATIC`) avaliada sobre `Time.get_ticks_msec()`. Atualiza a ADR-003 (Camera3D + curvas nativas;
  o nó Tween continua para a UI).
- Consequência: duração real idêntica em qualquer máquina; em hardware normal o resultado é o mesmo de um Tween.

## ADR-012 — Export Windows determinístico
- Contexto: com `editor/export/convert_text_resources_to_binary=true` (padrão), o export converte cada `.tscn`
  em `.scn` gravando IDs de nó aleatórios (as cenas não têm `unique_id=`); dois checkouts limpos do mesmo commit
  geravam `.exe` diferentes. Um arquivo de licença com CRLF na cópia de trabalho também divergia do commit.
- Decisão: `project.godot` → `editor/export/convert_text_resources_to_binary=false` (cenas vão ao PCK como texto
  versionado; scripts continuam como tokens). Cópia de trabalho normalizada para LF (`.gitattributes eol=lf`).
- Consequência: mesmo commit → `.exe` e zip idênticos byte a byte (verificado em dois checkouts limpos + re-export);
  o hash do zip depende do horário do commit (timestamps fixos = data do commit); o do `.exe`, não.

## ADR-007 — Validação do executável Windows
- Contexto: no contêiner Linux, o Wine disponível (9.0) aborta em qualquer binário Godot 4.7.2 antes
  do `main`: o runtime MinGW chama `VirtualProtect(..., lpflOldProtect=NULL)`, que o Windows
  rejeita com erro e o `kernelbase` do Wine 9.0 derreferencia. Wine mais novo (WineHQ) está bloqueado pela rede.
  Evidência: `docs/evidence/loop-01/wine_virtualprotect_trace.txt`. Numa reexecução da auditoria o Wine
  travou em loop de `RPC_S_SERVER_UNAVAILABLE` em vez de abortar — ambos são falhas do Wine antes do jogo.
- Decisão: validar (1) o export estrutural e reprodutível do `.exe` (PE32+ x86-64, PCK embutido,
  recursos/ícone/versão), e (2) o **pacote exato embutido no `.exe`**, executado com o runtime oficial
  4.7.2 (`--main-pack`, binário do editor Linux) no renderizador Forward+ real (Vulkan/lavapipe).
- Cobertura: (2) valida todo o conteúdo do jogo (cenas, scripts, recursos). **Não** cobre o código
  específico do Windows — o template `windows_release_x86_64`, drivers Vulkan/D3D12/OpenGL do Windows,
  janela e ícone. Isso só é validado executando o `.exe` no Windows (checklist em `docs/BUILD.md`).

## ADR-013 — Escultura e áudio gerados offline (venv de ferramentas)
- Contexto: o Loop 4 (ART DIRECTION RESET) exige personagem e mãos esculturais e som original. Primitivas
  montadas em runtime não alcançam formas orgânicas; raymarching de SDF em runtime custa caro no LOW/iGPU;
  amostras ou geradores comerciais (inclusive as ferramentas Higgsfield disponíveis na sessão) violam as regras
  de originalidade/sem API comercial sem autorização.
- Decisão: ferramentas Python offline, determinísticas (seed fixa), em `tools/sculpt/` (SDF → marching cubes →
  OBJ com AO por vértice em `assets/meshes/`) e `tools/audio/` (síntese → OGG Vorbis em `assets/audio/`).
  Os resultados são **versionados**; o jogo não roda Python. Venv `/opt/korium-py` (numpy, scipy, scikit-image,
  fora do repositório, criado pelo hook SessionStart). Nenhum asset de terceiros.
- Consequência: assets reproduzíveis a partir do código; regenerá-los exige o venv; o export continua offline e
  determinístico.

## ADR-014 — Cenários de simulação com estados tipados separados
- Contexto: o Loop 4 introduz o cenário GENESIS ao lado da ORIGIN CHAMBER. Tipar `Simulation.world` com uma base
  comum quebrava ~40 leitores (`var w := Simulation.world` + campos da ORIGIN → "Cannot infer the type").
- Decisão: `Simulation.world: WorldState` (ORIGIN) e `Simulation.genesis: GenesisState` coexistem; só o estado do
  cenário ativo recebe eventos; `Simulation.state` devolve o ativo (`ScenarioState`). `Scenario` registra roteiro,
  tipos, estado e catálogo por id; `--scenario=` na linha de comando. Módulos GENESIS leem `Simulation.genesis`.
- Consequência: mudança aditiva; na virada (Loop 4, Fase C) `world` pode ser retipado quando os consumidores da
  ORIGIN saírem.

## ADR-015 — Personagem viva é estado em tempo real
- Contexto: Loop 5 (MIKU LIVING CHARACTER). Vida, antecipação, follow-through e reações a intervenções do usuário
  exigem dinâmica com estado (molas de segunda ordem, mente com emoção/compostura, agenda de micro-comportamentos),
  incompatível com "visual = f(Simulation.time)" e com seek.
- Decisão: no cenário `living`, a personagem e suas mãos/fios são uma simulação em tempo real dirigida por
  `MotionClock` (determinística sob Movie Maker com `--fixed-fps`); o `Simulation` continua o único produtor de
  eventos de demonstração (ordens de trabalho do roteiro); intervenções do usuário entram pelo sistema de interação.
  Sem seek nesse cenário (reset = recompor). Variação de comportamento vem do estado, não de aleatoriedade; ruído
  só com semente fixa.
- Consequência: ORIGIN/GENESIS mantêm ADR-004/010; o cenário `living` documenta a exceção.

## ADR-016 — Character ≠ Provider ≠ Worker; mutações só por patch validado
- Contexto: o Owner prevê conectar MIKU a CLIs/providers (via provider registry da KORIUM) e configurá-la por
  conversa, sem que MIKU vire "um provider com skin" e sem dar a providers acesso arbitrário a arquivos/internals.
- Decisão: `src/agent/` define vocabulário de ações, intents, parser local determinístico, **porta** de provider
  (interface sem implementação, sem registro próprio — a ligação futura é ao registry da KORIUM, que este projeto
  não acessa nem conecta; regra de isolamento mantida), patch estruturado, esquema e validação de configuração
  (`identity`/`appearance`/`behaviour`). Providers só devolvem ações + patch; a runtime de MIKU decide a execução.
  `appearance` só expõe propriedades com suporte real (ossos/materiais); o resto é `REQUIRES_ASSET`.
- Consequência: trocar/perder provider não muda a personagem; pedidos locais não gastam tokens; voz futura reusa o
  mesmo input.
