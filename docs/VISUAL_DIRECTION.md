# Direção visual

Dono: `art-director`. Responsabilidade: identidade, composição, luz, materiais, movimento e UI.
Valores concretos vivem no código e não são repetidos aqui: cores, fontes e tempos em
`src/style/palette.gd`; materiais em `src/style/material_library.gd` e `src/style/shaders/`;
atmosfera e luz por estágio em `src/style/environment_profile.gd`.

## Sensação

Um universo misterioso que se transforma aos poucos. Silêncio, escala, precisão. O espectador
entende o que acontece pela luz e pela forma, não por texto.

## Princípios

1. **Um só ambiente.** UNIVERSE, FORGE e OBSERVATORY são o mesmo espaço visto de outra distância;
   nada de telas desconectadas.
2. **Monocromático com um acento.** Base VOID→BONE. EMBER é energia/ativação e só aparece quando
   algo recebe energia. PALE é exclusivo da verificação.
3. **Luz conta a história.** Câmara quase escura no início; a luz sobe com os eventos
   (ativação → iluminação da estrutura → verificação → forma final).
4. **Arquitetura, não dispositivo.** Formas de anéis, lâminas e colunas com proporção arquitetônica;
   bordas finas, superfícies escuras com brilho controlado.
5. **Movimento com função.** Cada movimento corresponde a um evento; o ambiente respira devagar.
6. **Texto mínimo.** Rótulos curtos em maiúsculas espaçadas, dados em mono. Sem texto decorativo.

## Evitar

Y2K, cyberpunk genérico, neon saturado, grades de "tron", robôs/cérebros, hologramas azuis,
dashboards corporativos, excesso de partículas, bloom estourado, lens flares, glitch,
efeitos sem função narrativa, cópia de projetos existentes.

## Composição

- FORGE: núcleo levemente acima do centro óptico; estrutura ocupa ~55% da altura; horizonte baixo.
- UNIVERSE: a câmara é um ponto de luz quente entre sementes dormentes frias; profundidade por névoa.
- OBSERVATORY: painel nativo à esquerda (~38% da largura); o mundo continua vivo à direita.
- UI nas bordas; o centro pertence ao mundo.

## Tipografia

Inter (UI) e IBM Plex Mono (dados, tempos, IDs). Rótulos 11–13 px, espaçamento amplo;
títulos raros. Ambas OFL, embarcadas.

## Regras de cor (quem pode usar cada tom)

| Tom | Significado | Onde aparece |
|---|---|---|
| VOID → BONE | matéria, espaço, informação neutra | superfícies, piso, arquitetura, texto de UI, seleção |
| **EMBER** (+ EMBER_DEEP) | energia fluindo **agora** | coração do núcleo e sua luz, aro do casco energizado, arestas em montagem, linhas de arco da forma final, halos de ativação/forma final |
| **PALE** | verificação | banda de varredura, anel de varredura, flash de checagem |

- EMBER nunca marca estado, status, seleção ou decoração. Sem energia, sem EMBER.
- PALE nunca é luz de cena nem texto comum; só existe enquanto a verificação acontece.
- Seleção/hover é BONE (hairlines + fresnel leve), nunca EMBER nem PALE.

### Núcleo dormente (resolve pendência do Loop 1)

Antes de `CORE_ACTIVATION` o núcleo **não tem EMBER**: casco `core_shell` com `energy = 0`
(metal GRAPHITE com fresnel BONE mínimo), coração `core_heart` com `energy = 0` (negro),
luz do núcleo desligada (`LIGHT.dormant.core`). O que o revela é só o contraluz frio (`RIM_COLOR`)
e o fresnel do casco — uma silhueta no escuro. EMBER entra com a ativação, subindo `energy`.

### Selo DEMO MODE

O selo é informação permanente, não energia: **texto BONE** em IBM Plex Mono ("DEMO MODE", + "SIMULATED
EVENTS" em tom apagado), sobre fundo `PANEL` com contorno `PANEL_LINE` e um marcador quadrado ASH à esquerda.
Nunca EMBER (sugeriria atividade/alerta) e nunca PALE (é da verificação). Canto superior esquerdo, pequeno,
sempre visível — inclusive com o HUD oculto (H) — e legível em 1280×720 (`src/ui/demo_badge.gd`).

## UI (HUD nativo, `src/ui/`)

Nós `Control` + `Theme` construídos em código (`UiTheme`, a partir de `Palette` e das fontes embarcadas);
a UI só conversa com o mundo por `Simulation`, `Session` e `Quality`.

- **Composição**: a UI mora nas bordas, o centro é do mundo. Topo: selo (esquerda), modos (centro, com as
  teclas 1/2/3 discretas), SETTINGS (direita). Esquerda: painel do modo. Direita: inspector (quando há
  seleção) e feed de eventos acima do transporte. Base: transporte em faixa única.
- **Por modo**: FORGE — lista CONSTRUCT (núcleo, camadas I–V, verificação; clique seleciona).
  UNIVERSE — SITES (câmara + 3 sementes; clique seleciona e enquadra) + dica de navegação.
  OBSERVATORY — folha à esquerda (38% da largura, sem feed): missão com ✓ e progresso, verificação (checks com
  tempo), entidades, log completo rolável e rodapé "SIMULATED DATA"; o inspector desce para o canto inferior
  direito para não cobrir a estrutura enquadrada à direita.
- **Hierarquia de texto**: rótulos em Inter maiúsculas espaçadas (`Caption` apagado 11 px, `RowText` 11 px,
  `Title` 13–15 px); dados, tempos e status em IBM Plex Mono (`Data` BONE, `DataDim` apagado). Prosa só no
  resumo do inspector e no detalhe do log (`Body`). Nada de texto decorativo.
- **Cor**: tudo VOID→BONE. Painéis `PANEL` translúcido + hairline `PANEL_LINE`; hover/seleção são lavagens BONE
  (`PANEL_HOVER`/`PANEL_ACTIVE`) com um fio BONE à esquerda da linha selecionada; texto secundário `TEXT_DIM`.
  **A UI nunca usa EMBER nem PALE** (teste `test_ui_theme`).
- **Linha do tempo**: fio fino; trecho decorrido ASH; uma marca por mudança de fase (derivada dos eventos),
  BONE quando já passou; cabeça BONE. Arrastar/clicar faz `Simulation.seek`.
- **Movimento**: troca de modo faz cross-fade dos painéis (`T_BASE` entrando, `T_FAST` saindo); H esmaece tudo
  menos o selo. Tempo/fase atualizam a 10 Hz (`T_UI_REFRESH`); listas só em eventos e `world_rebuilt`.
- **Input**: nós de layout com `MOUSE_FILTER_IGNORE` (órbita e picking livres fora dos painéis); painéis
  param o mouse só no próprio retângulo. Nenhum botão pega foco de teclado (Espaço/R/1–3 sempre chegam aos
  atalhos globais).
- **Nada sugere conexão real**: nenhum vocabulário de rede/conta (connect, sync, cloud, server, login —
  teste `test_ui_hud`); o rodapé do OBSERVATORY diz
  "SIMULATED DATA · LOCAL · DETERMINISTIC".

## Materiais (`MaterialLibrary`)

Instâncias compartilhadas (cache estático). Quem precisa de valores próprios usa `.duplicate()`.
Nenhuma textura; toda cor vem de `Palette` e é injetada pela biblioteca (os shaders não têm literais de cor).
Nenhum shader usa `TIME`: pulsos e animações são dirigidos por `Simulation.time`, então pausa/seek ficam consistentes.

| Getter | Uso | Aparência / controle |
|---|---|---|
| `structure()` | 96 segmentos (MultiMesh, `use_custom_data`) | bruto → acabado por `finish`; ver abaixo |
| `core_shell()` | casco facetado do núcleo | metal escuro, fresnel BONE sutil; `energy` acende aro EMBER |
| `core_heart()` | coração do núcleo | EMBER emissivo sem sombreamento; `energy`, `pulse` |
| `scan_ring()` | anel da varredura | PALE aditivo com borda suave; `strength` |
| `halo()` | halos (ativação, forma final, piso) | aditivo sutil; `color` (BONE por padrão, EMBER só com energia), `strength` |
| `floor()` | piso da câmara | quase preto, rugoso, especular baixo (leve reflexo) |
| `architecture()` | pilares, colunas, óculo | GRAPHITE fosco; nunca mais brilhante que a estrutura |
| `dormant_seed()` | sementes do UNIVERSE | corpo quase preto com fresnel ASH frio; `energy` aquece para EMBER |
| `mote(color)` | poeira (quad de `GPUParticles3D`) | `ShaderMaterial` (`particle_mote.gdshader`): unshaded, aditivo, billboard de partículas (mantém escala/giro), disco redondo e suave, alpha pela rampa de cor do sistema; `near_fade` (Vector2, metros de vista) esconde o que passa rente à lente; cache por cor |
| `spark(color)` | faíscas sólidas (malha `shard`, sem billboard) | `StandardMaterial3D` unshaded, aditivo, dupla face, cor só do material; cache por cor |

### Estrutura: estados

- **INSTANCE_CUSTOM** (por segmento): `r` montagem (0 fragmento solto, 1 assentado),
  `g` flash de verificação (PALE), `b` seleção/hover (BONE), `a` energia de construção (EMBER nas arestas).
- **Uniformes**: `finish` (0 bruto → 1 acabado), `scan_y` + `scan_strength` (banda PALE em Y mundial),
  `final_lock` (linhas EMBER de arco), `energy` (multiplicador global de todo EMBER; padrão 1).
- **Bruto**: cinza fosco claro (ASH→BONE), dielétrico, com costuras finas mais escuras que leem o corte.
  **Opaco de propósito**: translucidez num MultiMesh de 96 instâncias sobrepostas não ordena entre instâncias
  (artefatos), perde sombras e SSAO e custa overdraw em hardware modesto; o "inacabado" é dito pelo valor claro e fosco.
- **Acabado**: meio-metal escuro (SLATE puxado para ASH), rugosidade média (0.42: o reflexo EMBER do núcleo se
  espalha pelo anel em vez de acender um só segmento, que lia como "selecionado"), chanfro fino de tamanho físico
  que pega a luz e hairline BONE discreta (`finished_line` 0.18, `finished_chamfer` 0.08: o anel acabado/verificado
  lê como uma superfície, não como grade de blocos contornados). Metal demais com albedo escuro vira buraco: sem nada para refletir, a parede
  some no VOID. Por isso o metal é parcial (a key ainda ilumina o difuso) e o ambiente reflete o céu
  (`reflected_light_source = SKY`, cujo passe de radiância é um VOID levemente erguido — dono: game-engineer).
  O acabamento só vale para segmentos assentados (`finish × r`).
- **Arestas**: vêm do UV (0..1 por face, garantido pelo MeshBuilder): distância à borda convertida em pixels →
  hairlines de largura constante, com fade quando a face fica pequena na tela (sem cintilação à distância).
- **Montagem** (`a`): todas as arestas do segmento em EMBER, transitório.
- **Forma final** (`final_lock`): **um anel EMBER por camada** — só a borda superior da **parede externa**
  (máscara `v_outer` calculada no espaço da malha, cuja origem é o eixo do anel; `lock_px_scale` alarga a linha).
  As paredes externas dos segmentos se unem num círculo contínuo. Tampas, bordas internas e laterais ficam
  sem EMBER: nada de contorno de "wireframe".
- **Varredura**: banda gaussiana em Y que acende hairlines e chanfros em PALE. O flash `g` marca checagens com
  energia própria (`flash_edge_energy` 0.7, abaixo da banda) e só na parede externa (máscara `v_outer`, a mesma
  do `final_lock`), para ler como um lampejo ao longo do anel, não como grade.
- **Seleção/hover** (`b`): hairline BONE um pouco mais larga que a das arestas (`select_px_scale` 1.5), para não
  se quebrar em tracejado nas tampas rasantes sem MSAA (LOW), + fresnel leve.

### Contrato de malha com os consumidores

- Segmentos: UV 0..1 por face (u ao longo do arco, v radial nas tampas e vertical nas paredes).
- Anéis com `scan_ring()`/`halo()`: v atravessa a largura **visível** da fita (0..1), u ao longo do anel.
  O anel de varredura deve ser uma fita vertical (ou de seção retangular), não uma fita plana horizontal:
  vista de lado, a fita plana some em traços serrilhados.

## Luz por estágio (`EnvironmentProfile.LIGHT`)

A luz conta a história; o `LightRig` interpola os níveis (em `Palette.T_CINEMATIC`) segundo os eventos:

| Estágio | Eventos | Leitura |
|---|---|---|
| `dormant` | até `CORE_ACTIVATION` | quase escuro: só contraluz frio e ambiente mínimo; sem EMBER |
| `active` | `CORE_ACTIVATION` → `LIGHTING_APPLIED` | o núcleo é a fonte: luz EMBER local, key mal existe |
| `lit` | `LIGHTING_APPLIED` | key BONE sobe, a estrutura acabada aparece inteira |
| `verify` | `VERIFICATION_STARTED` → `VERIFICATION_PASSED` | key recua um pouco para a banda PALE ler |
| `final` | `STRUCTURE_FINALIZED` em diante | nível mais alto, núcleo pleno, arcos EMBER |

- Cores: `KEY_COLOR` (BONE, quente-neutro), `FILL_COLOR` e `RIM_COLOR` (ASH, frios), `CORE_COLOR` (EMBER, a única luz quente),
  `AMBIENT_COLOR` (ASH: o ambiente só pesa quando a energia do estágio sobe — `lit`/`final` revelam as paredes
  que a key não alcança; em `dormant` continua desprezível).
- As paredes de frente para a câmera FORGE recebem pouca key: quem as desenha é o fill (frio) e o ambiente.
- `FOG_LIGHT`: as direcionais quase não entram na névoa volumétrica (é o que a tornaria leitosa);
  o volume ganha corpo só em volta do núcleo.

## Atmosfera (`EnvironmentProfile.make_environment`)

- Fundo VOID, tonemap AgX, ajuste leve de contraste e saturação.
- **Glow contido**: limiar HDR acima de 1 — só emissão real (hairlines, coração, anel) floresce, com raio curto.
- **Névoa de profundidade** em modo DEPTH, cor VOID: a distância afunda no preto e bordas de piso/pilares se
  dissolvem em vez de cortar um horizonte. **Volumétrica tênue** (albedo ASH, densidade por estágio).
- **SSAO** moderado assenta segmentos e pilares.
- `apply_quality(env, profile)`: liga/desliga SSAO, SSIL, glow e volumétrica pelo perfil de `Quality`;
  sem volumétrica (LOW) a névoa de profundidade começa mais perto para manter a profundidade.
- `mode_fog(mode)` / `apply_mode_fog(env, mode)`: FORGE fechado, OBSERVATORY recua o mundo atrás do painel,
  UNIVERSE vê longe (sementes além da câmara, a 60–70 unidades, legíveis) e mais claro (`exposure_scale` 1.5).
  No UNIVERSE o volume volumétrico é curto (`UNIVERSE_VOLUMETRIC_LENGTH`): visto a ~80 unidades, um volume que
  alcançava a câmara absorvia a maior parte da luz dela — o HIGH ficava muito mais escuro que o LOW (sem
  volumétrica). Com o volume curto os dois perfis leem igual (mediana do centro 10 vs 12/255, p99 43 vs 49).
  A chave `exposure_scale` (todos os modos; não é propriedade do `Environment`, `apply_mode_fog` a ignora)
  é multiplicada pelo `LightRig` sobre a exposição do estágio.
- **Reflexos**: `reflected_light_source = SKY` explícito (ver "Acabado").

## Custo

Estrutura: 5 MultiMesh (um por camada) + nervuras, opacos, algumas derivadas por pixel, sem texturas. Emissivos de anel são
aditivos sem escrita de profundidade. Os efeitos caros (volumétrica, SSAO, SSIL, glow) obedecem ao perfil de `Quality`.
