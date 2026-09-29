<!-- Dono: coordenador. Responsabilidade: especificação do vídeo-review da v0.1.0 (roteiro + requisitos técnicos). -->
# Vídeo-review — KORIUM UNIVERSE v0.1.0

Objetivo: um vídeo-review honesto (~2 min 40 s) do jogo **rodando de verdade** (renderizador real, sem mockups),
gravado com o Movie Maker do Godot (`--write-movie`, tempo fixo, 30 fps) e codificado em MP4 H.264.
Sem áudio (o jogo ainda não tem som). Legendas em PT-BR desenhadas por uma camada de ferramenta — o jogo não muda.

## Requisitos técnicos

1. **Relógio de movimento (animator)** — `CameraDirector._now()` (ADR-011) e o movimento ambiente de
   `origin_core.gd` e `fragment_structure.gd` usam `Time.get_ticks_msec()`. No Movie Maker o tempo de parede
   não acompanha o tempo do jogo (cada quadro leva ~0,4 s para renderizar e representa 1/30 s), então
   transições sairiam instantâneas e o movimento ambiente acelerado. Criar um relógio único
   (`src/animation/motion_clock.gd`, `class_name MotionClock`, `static func now() -> float`) que devolve
   tempo de parede normalmente e, quando `Engine.get_write_movie_path() != ""`, o tempo acumulado dos quadros
   do jogo (delta fixo). Usar nos três pontos. Teste da lógica.
2. **Tour de gravação (game-engineer)** — `tools/review/review_tour.tscn` + `review_tour.gd` (fora do export):
   instancia `res://scenes/main.tscn`, força `Quality.override_for_session(HIGH)` (o AUTO mediria 30 fps fixos e
   rebaixaria), roda a sequência abaixo por **tempo de jogo** (delta), e desenha por cima (CanvasLayer acima do HUD):
   cartões de título/veredito em tela cheia, legenda inferior (lower third) centralizada acima do transporte e um
   cursor/anel discreto BONE nos pontos de clique. Interações pela interface real: teclas via
   `Input.parse_input_event`, cliques como `InputEventMouseButton` no centro dos controles (botões do transporte,
   abas, linhas das listas, FOCUS), arrasto da timeline como eventos de mouse reais. Estilo: `Palette`/`UiTheme`
   (BONE sobre PANEL, Plex Mono para rótulos, Inter para texto), sem EMBER/PALE na legenda. `tools/record_review.sh`:
   grava `build/review/korium_review.avi` com `--write-movie ... --fixed-fps 30 --resolution 1600x900` via
   `tools/_proc.sh`/Xvfb, depois ffmpeg → `build/review/korium_universe_review_v0.1.0.mp4`
   (libx264, CRF ~22, `-pix_fmt yuv420p`, `-movflags +faststart`, alvo < 30 MB).

## Roteiro (tempos aproximados, tempo de jogo)

| # | Duração | Ação | Legenda / cartão |
|---|---|---|---|
| 0 | 5 s | Cartão de título (fade in/out sobre VOID) | **KORIUM UNIVERSE** · v0.1.0 — Review · Godot 4.7 · Windows · DEMO MODE |
| 1 | 9 s | UNIVERSE, plano do modo | "Um universo onde agentes e projetos viram estruturas vivas. Nesta versão, tudo é simulado e local — nada se conecta a lugar nenhum." |
| 2 | 4 s | Clique na aba FORGE | "FORGE: a ORIGIN CHAMBER, onde o primeiro construto nasce." |
| 3 | 52 s | Clique em START; demo inteira a 1× com câmera cinematográfica | Legendas por fase (entram com os eventos): ativação — "O núcleo desperta. O âmbar só aparece onde há energia."; fragmentos — "96 fragmentos se soltam do núcleo."; camadas — "Cinco anéis se montam, um evento de cada vez."; materiais/luz — "Os fragmentos brutos viram metal; a luz da câmara sobe com a história."; verificação — "Uma varredura clara executa quatro checagens simuladas."; final — "Forma final: as colunas travam a estrutura." |
| 4 | 16 s | PAUSE; arrastar a timeline para ~T+20; clicar LAYER III na lista; FOCUS; retomar a 2× | "Tudo é função do tempo da simulação: pausar, voltar e avançar reconstrói o mundo exatamente." · "Qualquer entidade pode ser inspecionada e enquadrada." |
| 5 | 12 s | Tecla 3 (OBSERVATORY) no fim da demo | "OBSERVATORY: missão, verificações e o log completo — dados simulados, locais e determinísticos." |
| 6 | 14 s | Tecla 1 (UNIVERSE); clique em SEED · AUREL; FOCUS; pequeno voo WASD | "As sementes dormentes guardam lugar para os próximos construtos." |
| 7 | 7 s | Tecla 2; tecla H (HUD oculto); órbita lenta | "Com o HUD oculto, só o selo DEMO MODE permanece." |
| 8 | 14 s | Cartão de veredito | **Prós:** direção visual coesa e original · construção legível em 7 fases · pausa/seek exatos · UI nativa clara · 100% offline. **Contras:** conteúdo curto (uma demo de 50 s) · sem áudio · ainda não há decisões do jogador · execução nativa no Windows por validar. **Veredito:** fatia vertical promissora — 7/10 como protótipo. |

Total ≈ 2 min 13 s – 2 min 40 s (os tempos exatos seguem os eventos).
