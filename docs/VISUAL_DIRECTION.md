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
| `miku_body()` | porcelana perolada: albedo pérola/blush, mármore de contraste mínimo, **sheen iridescente** em ângulo rasante pérola → rosa → ouro pálido, translucidez falsa na silhueta (emissão dependente da vista), luz interna suave; AO = `COLOR.r` do vértice | `awaken`, `breath`, `select`, `inner_glow`, `sheen`, `backlight_amount`, `ao_strength` |
| `miku_hair()` | fitas aditivas; ouro pálido (raiz) → rosa → lilás (ponta), filamentos internos, borda suave, cintilação lenta rumo às pontas. Malha: UV.x raiz→ponta, UV.y através; alpha do vértice = opacidade do fio | `reveal`, `motion_time`, `intensity`, `seed` |
| `miku_gown()` | véu de luz aditivo, mais claro em ângulo rasante, comido por ruído de cima para baixo (Y do objeto), deixando grãos de estrela | `fade_top`, `fade_bottom`, `presence`, `motion_time` |
| `halo_arc()` | arco de astrolábio incompleto + arco interno oposto + graduação fina; linhas de largura constante em pixels (quad) | `strength`, `breath`, `arc_span` |
| `hand_stone()` | basalto azul-noite polido (clearcoat) com estrelas dentro da pedra (espaço do objeto) e **kintsugi seletivo**: só algumas bordas de Voronoi são fraturas remendadas — as que seguem 1–2 caminhos longos (crista de ruído de baixa frequência) mais uma pequena fração de ramos escolhidos pelo hash da própria borda (`k_voronoi2`/`k_edge_hash`); o resto da rede não existe (nada de grade). Ouro sempre presente e apagado; `veins` espalha e acende | `veins`, `motion_time`, `select`, `vein_scale`, `star_scale`, `vein_share`, `vein_path_scale` |
| `planet_forming()` | `formation` acreção por muitos grãos que se juntam (nunca um borrão solitário) com borda GOLD → `heat` **lago de lava**: pele escura resfriada cortada por rios incandescentes finos em duas escalas e poucas ressurgências (meios-tons raros: nada de "mancha") → `crust` placas (Voronoi com deformação forte) assentando uma a uma; só parte das bordas fica aberta e acesa (`open_share`), as outras são costuras seladas; tom por placa e por "continente"; a rede de fendas some quando as células ficam pequenas na tela (planeta distante mostra continentes, não colmeia) → `atmosphere` névoa de limbo + aro fino ICE→DUSK_ROSE | `formation`, `heat`, `crust`, `atmosphere`, `motion_time`, `seed`, `detail`, `select`, `open_share` |
| `moon_doc()` | gelo fosco com estratos finos (páginas), rim ICE fino, acreção igual ao planeta | `formation`, `glow`, `seed`, `select` |
| `ring_skill()` | bandas finas douradas com vãos escuros sobre quad (raio do UV); formação varre o círculo com borda quente | `formation`, `inner`, `outer`, `bands`, `intensity` |
| `asteroid_memory()` | pedra rugosa, rim rosa-lilás; ~5 % das rochas (por `INSTANCE_ID`) guardam um brilho GOLD discreto | `memory`, `glint_share` |
| `orbit_line()` | linha fina aditiva, mais clara logo atrás do corpo, desvanecendo ao longo do arco | `head`, `trail`, `base`, `formation` |
| `relation_thread()` | fibra de luz LILAC (sai do cabelo) → cor do alvo (ICE luas, GOLD planeta), afinando nas pontas; pulso GOLD viajante = backlink | `pulse`, `woven`, `color_to`, `intensity` |
| `nebula_sky()` | céu: nebulosa índigo/violeta por fbm deformado, faixa larga e **núcleo quente atrás de MIKU** (`warm_dir`, padrão −Z levemente acima do horizonte) que é **luz, não tinta**: coração perolado-dourado, corpo GOLD, bordas DUSK_ROSE → LILAC, carregado por **filamentos de gás** iluminados por dentro (cristas do campo deformado + leve fluxo radial, sem raios) e cortado pelas lanes de poeira — um halo liso vira "lama" bege sob AgX; 3 camadas de estrelas de tamanho em pixel, cintilação sutil, **dithering**; passe de radiância sem estrelas | `warm_dir`, `motion_time`, `detail`, `sky_energy`, `star_intensity`, `warm_intensity`, `core_intensity`, `filament_strength` |

Contratos de malha: linhas (órbitas, fios) funcionam melhor como **fitas cruzadas** (duas larguras ortogonais)
ou tubo fino, porque uma fita plana some de lado. Planetas/luas: qualquer esfera (padrões no espaço da direção).
Esculturas (`miku_body.obj`, mãos) não precisam de UV. `mote(color)`/`spark(color)` seguem para poeira e faíscas.

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

- **Selo** DEMO MODE: anel pequeno + "DEMO MODE" em mono espaçado + "all events simulated" apagado; sem
  caixa, sem cara de alerta; sempre visível (também com H). Grupo `demo_badge`.
- **Modos**: UNIVERSE · FORGE · OBSERVATORY, a palavra ativa em tinta plena, um fio curto desliza sob ela.
- **Transporte**: arco fino (órbita rasa) no centro inferior com um ponto por evento e o playhead; revela
  controles (reiniciar/tocar/pausar em glifos; fase, relógio e velocidades em palavras) quando o ponteiro
  chega à borda inferior (`UI_REVEAL_ZONE`), quando a demo não está tocando ou ao arrastar; recolhe após
  `T_REVEAL_LINGER`. Hover no arco nomeia o evento. Grupo `ui_transport` com `Start`/`Pause`/`Reset`.
- **Sussurros**: o rótulo do evento sobe, repousa e se dissolve acima do arco; uma linha por vez; seek/reset
  dissolve (o passado não é relido como texto).
- **Rótulos no espaço**: nome projetado da posição 3D do corpo com fio-guia (diagonal + corrida
  horizontal), no lado de fora da tela, evitando outros rótulos e outros corpos. FORGE/UNIVERSE: só o corpo
  em hover/seleção. OBSERVATORY: todos, com o signo (planeta ● subagente, lua ◗ documentação, anel skills,
  cinturão memória, fio link) e o tipo simbólico, mais uma legenda mínima — o vault lido como astronomia.
  Corpo ainda não formado (status UNFORMED) não é nomeado.
- **Cartão** do corpo selecionado: pequeno, ao lado do corpo (fio-guia até ele), signo + tipo, nome,
  status, uma frase, FOCUS e fechar; sem corpo na tela, repousa à direita. Rótulos sob o cartão recuam.
- **Missão** (OBSERVATORY): nome poético + uma linha por objetivo (em curso em tinta plena com anel,
  cumpridos suaves, por vir apagados); sem contagens nem porcentagens.
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
