# Direção visual: bíblia GENESIS (v2)

Dono: `art-director`. Responsabilidade: identidade, composição, luz, materiais, movimento, UI e o resumo da
linguagem sonora. Valores concretos vivem no código e não se repetem aqui: cores e tempos em
`src/style/palette.gd`; materiais em `src/style/material_library.gd` + `src/style/shaders/genesis/`; atmosfera em
`src/style/environment_profile.gd`. Diagnóstico da versão anterior: `docs/art/v0.1-postmortem.md`. Registros de
lookdev (primitivas substitutas, não usados no jogo): `docs/art/lookdev/` (`06–12`: refinos da Fase B,
`_v1` antes / `_v2` depois).

## 1. Conceito: MIKU, a tecelã celeste

Um único ambiente: o espaço profundo diante de uma nebulosa quente. No centro, **MIKU**, personagem original do
universo KORIUM, suspensa em pé, tece corpos celestes. Os agentes que ela cria são planetas; o que eles sabem são
luas; o que sabem fazer são anéis; o que lembram são cinturões. **O cabelo de MIKU é o grafo**: seus filamentos
se prolongam e viram os fios de luz que ligam cada corpo a ela e entre si (notas ↔ links ↔ grafo, traduzidos
em astronomia, sem copiar interface de app de notas). Sensação: contemplativa, cósmica, poética, elegante,
cinematográfica. O espectador entende pela luz, pela forma e pelo som, não por texto.

### MIKU: especificação e diferenciação

- Figura feminina alta e serena, proporção de estátua (≈ 9 cabeças), suspensa em pé, contrapposto leve, cabeça
  inclinada para a criação abaixo, braços abertos para a frente e para baixo, regendo as mãos. Dignidade de
  escultura sacra.
- **Porcelana lunar**: sem roupa modelada. Da cintura para baixo, um **vestido de luz** que se dissolve num rio de
  poeira estelar (sem pernas). Rosto sereno, olhos fechados sugeridos pela forma, sem boca detalhada; um ponto de
  luz GOLD na testa (a semente).
- **Cabelo**: uma única massa muito longa que flui para cima e para trás como filamentos de nebulosa; gradiente
  ouro pálido → rosa crepúsculo → lilás. **Halo**: arco incompleto fino de astrolábio atrás da cabeça, girando devagar.
- **Diferenciação de franquias (obrigatória)**: nada de mechas duplas/"twin tails", nada de azul-turquesa ou
  verde-água, nada de microfone, headset, número, tatuagem/insígnia, gravata, saia plissada, braçadeiras,
  uniforme escolar ou figurino de idol. Nenhuma pose de palco, nenhum olhar para a câmera, nenhum sorriso.
  Estética **não** anime/idol: a referência é escultura (mármore, porcelana, estatuária votiva), não ilustração.
  Nunca sexualizada: sem ênfase anatômica; o volume do corpo é contido e o vestido de luz começa na cintura.

## 2. Paleta v2 (`Palette`)

Noite índigo como base, luz quente de criação, porcelana e gelo. Baixa saturação (HSV ≤ 0,6, testado), sem neon.
**GOLD é o acento narrativo**: só aparece onde algo está sendo criado ou foi criado (semente, kintsugi aceso,
magma, borda de acreção, pulso de link).

| Token | Hex | Papel |
|---|---|---|
| `SPACE_DEEP` | #05060b | fundo do céu, névoa de profundidade; nunca preto puro |
| `INDIGO` | #141a30 | corpo da noite, ambiente, sombra da matéria |
| `NEBULA` | #3a2d63 | nuvens violeta da nebulosa, fill |
| `LILAC` | #9a88c6 | pontas do cabelo, início dos fios, realces da nebulosa |
| `DUSK_ROSE` | #c48b9f | núcleo quente da nebulosa, contraluz, meio do cabelo, borda de atmosfera |
| `PEARL` | #f4efe9 | porcelana de MIKU, estrelas brancas |
| `BLUSH` | #f2d6d0 | translucidez da porcelana, estrelas quentes |
| `GOLD` | #e9b872 | criação: semente, kintsugi, magma quente, acreção, pulsos |
| `MAGMA` | #c47a50 | tom médio do magma (cobre fundido, não laranja) |
| `GOLD_DEEP` | #7d5836 | magma resfriado, fundo das fendas, ouro apagado do kintsugi |
| `ICE` | #a9c6e8 | conhecimento/documentação: luas, atmosfera, rim frio |
| `STONE` | #1b1e2e | pedra-noite das mãos, crosta, asteroides |

Regras: UI nunca usa GOLD (a UI não cria nada); ICE nunca vira turquesa; brancos são sempre PEARL/BLUSH.
Os tokens v1 (VOID…EMBER/PALE) ficam até a virada da Fase C (seção 10).

## 3. Materiais (`MaterialLibrary`, `shaders/genesis/`)

Instâncias em cache e compartilhadas; corpos com estado próprio usam `.duplicate()`. Toda cor vem de `Palette`
(teste). **Nenhum shader lê `TIME`**: o movimento ambiente usa o uniform `motion_time`, alimentado por
`MaterialLibrary.set_motion_time(MotionClock.now())` uma vez por quadro (e pelo dono de cada duplicata). O
progresso narrativo (`formation`, `heat`, `veins`…) vem de `Simulation.genesis` + `Simulation.time`.
`MaterialLibrary.apply_quality(profile)` ajusta as oitavas de ruído (`detail`) por perfil.

| Getter | Aparência | Controles |
|---|---|---|
| `miku_body()` | **porcelana fosca luminosa**: dielétrico pérola de rugosidade ~0,5 e especular baixo e largo (`light()` próprio: Blinn-Phong normalizado), luz que envolve a forma (`wrap_amount`) com **espalhamento BLUSH** na faixa além do terminador e sombras direcionais nunca pretas (`shadow_lift`, tingido BLUSH); sheen pérola → rosa → ouro pálido só em ângulo rasante; todo termo rasante com **Fresnel antisserrilhado** (`fwidth`, sem contorno "adesivo"); abaixo de `dissolve_top` a saia **vira luz e se dissolve em grãos** (frente fbm quebrada por ruído fino, lábio luminoso, nunca barra dura); **estatuária, não entalhe**: no rosto a normal de sombreamento se inclina para o elipsoide da cabeça (`face_soften`) e o AO é mais leve (`face_ao`) — pálpebras, arcada e lábios leem como massa; no corpete a direção horizontal da normal vem em parte do torso redondo (`torso_soften`: derrete facetas de decimação, mantém as pregas); vincos estreitos e sulcos do cabelo esculpido recebem luz BLUSH espalhada (`hollow_fill` pelo AO, `crease_fill` pela curvatura em tela), nunca linha preta; **despertar** = `reveal` 0..1 radial a partir da semente da testa (`reveal_origin`, até `reveal_reach`), opaco (discard) com borda ouro→pérola suave quebrada por ruído — substitui a transparência global (que mostrava a parede interna da saia); AO = `COLOR.r`. O motor multiplica `DIFFUSE_LIGHT` pelo `ALBEDO` depois do `light()`: nenhum `light()` multiplica por `ALBEDO` (teste) e luz colorida que não deve herdar o albedo vai em `SPECULAR_LIGHT` | `awaken`, `breath`, `select`, `albedo_level`, `wrap_amount`, `scatter_amount`, `shadow_lift`, `sheen`, `hollow_fill`, `crease_fill`, `face_soften`, `face_ao`, `torso_soften`, `dissolve_top`/`dissolve_bottom`, `grain_scale`, `lip_intensity`, `light_turn`, `reveal`, `reveal_origin`, `reveal_reach`, `reveal_edge`, `reveal_glow`, `motion_time` |
| `miku_hair()` | **uma massa de nebulosa** de fitas aditivas; ouro pálido (raiz) → rosa → lilás (ponta), filamentos internos, borda suave, cintilação lenta rumo às pontas; **cada tufo** (CUSTOM0.g) puxa para seu tom (rosa ↔ lilás ↔ pérola, `tone_variation`) e sua opacidade (`opacity_variation`); a raiz única é contida (`root_level`/`root_length`: as raízes aditivas empilhadas nunca viram um ponto estourado); **fios de link** (CUSTOM0.x) são fibras finas e claras (`link_core`, `link_intensity`) que vão até a ponta e passam rosa → ICE → ouro pálido (`MaterialLibrary.hair_link_tip()`), exatamente a cor com que o `relation_thread` começa: cabelo e grafo são uma só fibra; `link_pulse` leva um pulso GOLD só pelos fios de link (o pulso do clímax saindo do cabelo). Malha: `HairRibbons` (UV.x raiz→ponta, UV.y através; alpha do vértice = opacidade; CUSTOM0 = link, tufo, comprimento) | `reveal`, `motion_time`, `intensity`, `seed`, `tone_variation`, `opacity_variation`, `root_level`, `root_length`, `link_intensity`, `link_core`, `link_pulse` |
| `miku_gown()` | véu de luz aditivo **só nas faces da frente** (sem espessura interna), mais claro em ângulo rasante (Fresnel antisserrilhado), comido de cima para baixo (Y do objeto) por uma frente que se quebra em grãos com lábio luminoso, deixando grãos de estrela que passam ao rio do `Stardust` | `fade_top`, `fade_bottom`, `presence`, `motion_time`, `grain_scale` |
| `halo_arc()` | arco de astrolábio incompleto + arco interno oposto + graduação fina; linhas de largura constante em pixels (quad); com `arc_span` → 1 as duas pontas afiladas se fundem num anel inteiro **sem costura** (em 1 a máscara é exatamente 1) | `strength`, `breath`, `arc_span`, `inner_span` |
| `hand_stone()` | **pedra-noite legível**: basalto STONE acetinado (clearcoat baixo, relevo fino por ruído), **profundidade**: nuvem nebular e estrelas vistas um pouco dentro da pedra (paralaxe no espaço do objeto), **rim ICE** fino antisserrilhado, kintsugi seletivo (bordas de Voronoi em 1–2 caminhos longos + ramos por hash da borda) sempre visível como ouro apagado (`vein_rest`); `veins` espalha e acende; o **antebraço se dissolve em grãos** a partir do pulso (`MaterialLibrary.set_hand_wrist`) | `veins`, `motion_time`, `select`, `vein_scale`, `star_scale`, `vein_share`, `vein_path_scale`, `wrist_point`/`forearm_end`/`wrist_fade`, `bump_strength` |
| `planet_forming()` | `formation` acreção por grãos com borda GOLD → `heat` lago de lava (rios finos em duas escalas) → `crust` placas Voronoi assentando; bordas abertas esfriam com o calor (mundo formado não é "bola de gude rachada") → `atmosphere` **dispersão**: limbo ICE no lado diurno, faixa DUSK_ROSE no terminador (`light()` próprio), névoa suave; o **mundo formado** (com `atmosphere`) é o corpo mais bonito do quadro mesmo com key fraca: bacias viram **mares** azul-ICE profundos com rasos claros junto a costas nítidas e fractais (mais mar que terra) e brilho suave (`glint_amount`), a terra fica rosa quente em regiões largas (sem mosaico de placas, costuras seladas somem), **nuvens** PEARL finas em estrias de latitude derivam (`cloud_amount`), luz que envolve levemente (`wrap_amount`); terminador e limbo são luz colorida (canal especular, independem do albedo) e somam com o key/aura do clímax sem estourar. `world_style` dá famílias aos mundos distantes (x faixas ICE, y poeira rosa; `MaterialLibrary.set_far_world_style`) | `formation`, `heat`, `crust`, `atmosphere`, `motion_time`, `seed`, `detail`, `select`, `open_share`, `world_style`, `scatter_amount`, `terminator_amount` |
| `moon_doc()` | gelo fosco com estratos finos (páginas), rim ICE fino, acreção igual ao planeta | `formation`, `glow`, `seed`, `select` |
| `ring_skill()` | bandas finas douradas com vãos escuros sobre quad (raio do UV); formação varre o círculo com borda quente, início suave e fechamento sem costura (em `formation` 1 todo ângulo acende) | `formation`, `inner`, `outer`, `bands`, `intensity` |
| `asteroid_memory()` | pedra rugosa com normais curvadas para a esfera da rocha (`smooth_shape`: facetas lidas como pedra gasta), rim rosa-lilás largo e antisserrilhado (rochas pequenas nunca viram buraco preto); ~5 % das rochas (por `INSTANCE_ID`) guardam um brilho GOLD discreto | `memory`, `glint_share`, `rim_intensity`, `smooth_shape` |
| `orbit_line()` | linha fina aditiva, mais clara logo atrás do corpo; o tubo é refeito no vértice como **fita voltada à câmera** e o núcleo tem ~`line_px` px constantes (sem "régua", sem contas por segmento); some quando o plano da órbita fica de perfil (`edge_on_fade`) e afina até sumir perto do corpo (`body_gap`) | `head`, `trail`, `base`, `formation`, `line_px`, `edge_on_fade`, `body_gap`, `tube_radius` |
| `relation_thread()` | fibra de luz que começa com a cor da ponta dos fios de link do cabelo (`hair_link_tip()`, ouro pálido) → cor do alvo (ICE luas, GOLD planeta): núcleo de ~`line_px` px constantes, cada fita pesada por n·v² (das duas cruzadas, a que fica de perfil passa a linha à outra: nunca uma "tira"), afina e some perto dos dois corpos; pulso GOLD viajante = backlink | `pulse`, `woven`, `color_to`, `intensity`, `line_px`, `end_fade` |
| `nebula_sky()` | céu: nebulosa índigo/violeta por fbm deformado, faixa larga e **núcleo quente atrás de MIKU** (`warm_dir`, padrão −Z levemente acima do horizonte) que é **luz, não tinta**: coração perolado-dourado, corpo GOLD, bordas DUSK_ROSE → LILAC, carregado por **filamentos de gás** iluminados por dentro (cristas do campo deformado + leve fluxo radial, sem raios) e cortado pelas lanes de poeira — um halo liso vira "lama" bege sob AgX; estruturas **poucas e grandes** (`nebula_scale`), **vazios escuros** de verdade (`void_scale`), filamentos só perto do núcleo, lanes finas e quebradas (nada de "lápide"), faixa inclinada (nada de coluna violeta); 3 camadas de estrelas de tamanho em pixel, cintilação sutil, **dithering**; passe de radiância sem estrelas | `warm_dir`, `motion_time`, `detail`, `sky_energy`, `star_intensity`, `warm_intensity`, `core_intensity`, `filament_strength` |

Contratos de malha: linhas (órbitas, fios) funcionam melhor como **fitas cruzadas** (duas larguras ortogonais)
ou tubo fino, porque uma fita plana some de lado. Planetas/luas: qualquer esfera (padrões no espaço da direção).
Esculturas (`miku_body.obj`, mãos) não precisam de UV. `mote(color)`/`spark(color)` seguem para poeira e faíscas. Motes da família GOLD (r − b > `GOLD_MOTE_WARMTH`) são menores (`GOLD_MOTE_DISC`) e em menor número (`GOLD_MOTE_KEEP`) a partir da 9ª instância de cada nuvem (semente, clarões e brilhos ficam intactos): poeira, nunca bokeh. Todos os shaders passam pela verificação estática de NaN (`tests/unit/test_style_shader_safety.gd`: `pow` com base limitada, `sqrt`/`log` de valores limitados, `k_safe_normalize`, `k_angle01`, divisões protegidas).

## 4. Iluminação

- **Contraluz primeiro**: a fonte motivada é o núcleo quente da nebulosa atrás de MIKU. Uma direcional quente
  (DUSK_ROSE→GOLD) vinda de trás recorta MIKU, as mãos e o planeta; um rim frio ICE de trás/lado separa as formas.
- **Key suave de ¾ lateral** (PEARL, energia moderada), nunca frontal: luz frontal achata a porcelana (verificado
  no lookdev). Fill violeta (NEBULA) muito baixo. Ambiente INDIGO, baixo: sombras são noite, não cinza.
- Emissão conta a criação: o planeta ilumina as palmas por baixo (luz local GOLD/MAGMA com `heat`); o kintsugi
  acende quando as mãos trabalham.
- Tonemap AgX; glow com limiar ≥ 1, só emissão verdadeira floresce; **nada de bloom estourado**. Exposição por
  plano, não por evento.
- Rig do lookdev (referência para a composição de Fase B): rim quente 2,2 de (0,3,−10); rim frio ICE 0,8 de (10,6,−6);
  key PEARL 1,0 de (−12,7,3) com sombra; ambiente 0,25.

## 5. Composição (um só espaço, três distâncias)

- **FORGE (herói)**: MIKU no terço superior central, recortada contra o núcleo quente; planeta em formação e mãos
  no terço inferior, em primeiro plano; leve contra-plongée (câmara abaixo do peito de MIKU olhando para cima). O
  cabelo sobe para fora do quadro: escala. Assimetria: mão esquerda baixa à esquerda, direita alta à direita.
- **UNIVERSE (sistema)**: vista alta e afastada; órbitas finas, cinturão de memória, planetas distantes com suas
  luas; MIKU é uma chama perolada no centro, e o cabelo, uma pluma que abre em fios para cada corpo.
- **OBSERVATORY (relacional)**: ¾ alto, mais próximo; fios relacionais e pulsos em destaque, rótulos diegéticos
  junto dos corpos; a nebulosa recua (menos `sky_energy`) para os fios lerem.

## 6. Movimento

- **Tudo respira**: períodos de 4–8 s (`T_BREATH` 6 s, `T_BREATH_SLOW` 8 s), só senoides; nada pisca.
- **Formação = inchaço/acreção** (`T_SWELL`): matéria se junta, a borda brilha, o volume incha; nunca flash, nunca pop.
- Mãos: lentas, pesadas, reverentes; antecipação e assentamento. Halo: uma volta em `T_HALO_TURN`.
- Câmara: grua/dolly lenta (`T_CRANE`), sem órbita constante, sem corte seco entre planos.
- Pulsos de link viajam do cabelo para o alvo em ~2 s, com easing, espaçados.

## 7. Linguagem sonora (resumo; detalhe do `sound-designer` em `docs/AUDIO.md`)

Drone grave ~55 Hz + quinta; pad aéreo formântico; brilhos cristalinos esparsos; vento cósmico filtrado. SFX de
formação são **sinos/harpa em escala pentatônica** (acreção = arpejo ascendente, crosta = sino grave, atmosfera =
pad que abre, lua = sino alto, anel = glissando de harpa, link = nota curta ao chegar o pulso). Nunca bleeps, UI
sonora de sistema, whooshes de trailer ou impactos. O som também respira.

## 8. UI diegética (`src/ui/genesis/`, Fase B)

A cena é o herói; a UI é tinta perolada nas bordas e nomes escritos no espaço. Nada de caixas acima da
cena. Tinta em poucos níveis (`UI_INK` → `UI_INK_SOFT` → `UI_INK_FAINT` → `UI_THREAD` → `UI_THREAD_FAINT`,
todos PEARL com alfa) sobre véu noturno (`UI_VEIL`, `UI_SHADE`, SPACE_DEEP); **nunca GOLD** (a UI não
cria nada). Maiúsculas finas com espaçamento largo para palavras/sussurros; minúsculas **nunca** espaçadas
(`Note`); Plex Mono só para tempo. Movimento: fades senoidais (`T_WHISPER_*`, `T_REVEAL`, `T_CONCEAL`,
`T_LABEL`), nada surge de repente. Dois dialetos no `Hud` por cenário (`scenario_changed`): ORIGIN mantém os
painéis v1 até a virada; GENESIS usa `GenesisHud`.

- **Selo** DEMO MODE: anel pequeno + "DEMO MODE" em mono espaçado + "all events simulated" apagado com
  sombra noturna discreta (`SealNote`, legível sobre a nebulosa clara); sem caixa, sem cara de alerta; sempre visível (também com H). Grupo `demo_badge`.
- **Modos**: UNIVERSE · FORGE · OBSERVATORY, a palavra ativa em tinta plena, um fio curto desliza sob ela.
- **Transporte**: arco fino (órbita rasa) no centro inferior com um ponto por evento e o playhead; revela
  controles (reiniciar/tocar/pausar em glifos; fase, relógio e velocidades em palavras) quando o ponteiro
  chega à borda inferior (`UI_REVEAL_ZONE`), quando a demo não está tocando ou ao arrastar; recolhe após
  `T_REVEAL_LINGER`. Hover no arco nomeia o evento. Grupo `ui_transport` com `Start`/`Pause`/`Reset`.
- **Sussurros**: o rótulo do evento sobe, repousa e se dissolve acima do arco; uma linha por vez — um evento novo
  primeiro dissolve o que está na tela (`T_WHISPER_HANDOFF` a partir da tinta cheia) e só então sobe; duas palavras
  nunca se sobrepõem; seek/reset
  dissolve (o passado não é relido como texto).
- **Rótulos no espaço**: nome projetado da posição 3D do corpo com fio-guia (diagonal + corrida
  horizontal), **radial** (para fora do centro do quadro, girando até achar lugar fora dos corpos e dos
  outros rótulos — nada de pilha num lado), sobre um **véu noturno esfumado** (legível sobre a nebulosa
  clara e o cabelo). FORGE/UNIVERSE: só o corpo
  em hover/seleção. OBSERVATORY: todos, com o signo (planeta ● subagente, lua ◗ documentação, anel skills,
  cinturão memória, fio link) e o tipo simbólico, mais uma legenda mínima — o vault lido como astronomia.
  Corpo ainda não formado (status UNFORMED) não é nomeado.
- **Cartão** do corpo selecionado: **sem moldura** (véu esfumado + tinta + fio-guia até o corpo), ao lado
  do corpo e deslocado para fora dos outros corpos (nenhum corpo desenhado através do texto); signo + tipo,
  nome, status, uma frase, FOCUS e fechar; sem corpo na tela, repousa à direita. Rótulos sob o cartão recuam.
- **Missão** (OBSERVATORY): nome poético + só o objetivo **em curso** (tinta plena, anel) precedido dos
  dois últimos versos vividos bem apagados (`UI_THREAD`); o que vem não está escrito; sem contagens nem
  porcentagens.
- **Configurações**: signo de afinação → cartão com qualidade, câmera cinematográfica, volumes
  Master/Ambience/SFX (`AudioDirector.set_bus_volume_db`) e as poucas teclas. Sons de UI (`ui_tick`,
  `ui_select`) só em interação do usuário, via grupo `audio_director`.
- **H** esconde tudo exceto o selo. Nenhum controle toma o foco do teclado; o centro da tela é do mundo.

Contrato com o mundo 3D (rótulos e cartão): a raiz visual de cada entidade entra no grupo
`Session.entity_group(id)` e fica invisível enquanto o corpo não existe. Metadados opcionais na raiz:
`label_anchor` (Vector3 local ou Node3D: o ponto nomeado; **obrigatório** para `belt_memory` e
`relations`, cujas raízes ficam no centro de outro corpo) e `label_radius` (float, unidades de mundo; sem
ele usa-se o AABB da primeira malha). Registros: `docs/art/ui-genesis/` (capturas do jogo real; `11–14`
com corpos substitutos de lookdev).

## 9. Proibições

Y2K; cyberpunk genérico; neon saturado; grades "tron", hairlines técnicas de CAD, hologramas azuis; UI corporativa
fria (dashboards, listas de status, logs como imagem principal); **turquesa, mechas duplas ou qualquer traço de
personagem conhecida**; estética idol/anime; sexualização; robôs/cérebros; bloom estourado, lens flare, glitch,
aberração cromática; excesso de partículas; texto decorativo; flash como transição; imagem estática simulando 3D.

## 10. Legado v1 (cenário ORIGIN, até a virada da Fase C)

Enquanto `&"origin_chamber"` for o cenário padrão, valem as regras v1 (detalhe no histórico git deste arquivo,
commit 5c4f2e9): base VOID→BONE; EMBER só onde há energia agora; PALE só durante a verificação; a UI nunca usa
EMBER/PALE; seleção/hover em BONE; estrutura opaca (MultiMesh sem ordenação); luz por estágio
(`EnvironmentProfile.LIGHT`: dormant/active/lit/verify/final); névoa DEPTH escura; glow contido; efeitos caros
por perfil de `Quality`. Esses tokens e materiais são removidos pelos donos na limpeza da Fase C.

## 11. Custo

Shaders v2 usam só ruído de valor por hash e um Voronoi 3×3×3 (planeta, mãos), com laços de limite constante;
`detail` por perfil (céu 3/4/5/5, planeta 3/3/4/4 para LOW/MEDIUM/HIGH/ULTRA). Aditivos sem escrita de profundidade.
Céu: com `Sky.PROCESS_MODE_AUTOMATIC` a radiância é refeita quando um uniform muda. Atualizar `motion_time` do céu
a ≤ 5 Hz (ou manter estático no LOW); o passe de radiância não tem estrelas e usa ≤ 2 oitavas.
Fase B: mãos e planeta usam `k_voronoi2` (mesmo laço 3×3×3, guarda também o id da 2ª célula); o planeta
ganhou 3 amostras de ruído de deformação; o céu, 3 cristas (filamentos) — custo fixo, sem novos laços.
A UI GENESIS desenha só enquanto há algo visível (rótulos: ≤ 11 projeções por quadro, sem nós extras).
