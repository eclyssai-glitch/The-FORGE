<!-- Dono: coordenador. Responsabilidade: rodada de correção artística do Loop 4 a partir da revisão do art-critic. -->
# Loop 4 — rodada de correção 1 (art-critic: REPROVADO, 6/10)

Revisão completa: `docs/evidence/loop-04/critic-r1.md` (commit `eaa03d1`; style frames `sf_01…08`, capturas
`g01…g18`, previews de escultura, prova de áudio). Veredito: conceito, paleta, luz, composição herói e UI já em
7–8; execução da personagem e acabamento puxam para 6 — "à distância, concept art de jogo autoral; de perto e nos
planos de sistema, vertical slice de estudante".

**Meta desta rodada: ≥ 8.** Imagem-assinatura a conquistar: *a tecelã cujo cabelo é o grafo*.

Regras: escritor único por área; interfaces existentes preservadas (âncoras JSON, nomes de módulo, APIs da
`MaterialLibrary`, grupos/metas de rótulo e áudio); cada dono prova no jogo real (`tools/style_frames.sh`,
`tools/capture_evidence.sh --scenario=genesis`) e inspeciona; commits WIP frequentes.

## procedural-modeler (`tools/sculpt/**`, `assets/meshes/**`, `src/procedural/**`)

- [P0] MIKU deixa de ser manequim: estatuária votiva — pálpebras, arcada e lábios como **massa**, não vinco;
  **massa de cabelo esculpida sobre o crânio** (penteada para trás, volume nobre, nasce o coque/raiz das fitas) — ela
  não pode ler careca; ombros caídos com clavícula; antebraços mais cheios; **remover o ressalto do cós** (o vestido
  não pode ler calça/saia lápis); peito abstraído num **corpete drapeado** (plano de tecido do ombro à cintura, pregas
  largas), sem seios modelados.
- [P0] Verificar "buraco escuro" no tronco/cintura e braço esquerdo "derretendo" no quadril (`sf_05`, `g12`):
  normais/autossombra/interpenetração; afastar o braço do quadril se preciso. Limpar as lascas sub-pixel do
  marching cubes (faces de área ~0, normais opostas).
- [P1] Mãos gigantes: planos de nós dos dedos, afunilamento, insinuação de unha; nada de "salsicha segmentada".
  Mão direita: gesto próprio de **tecer** (dedos entreabertos como quem passa fios entre eles), não o indicador de
  "Criação de Adão".
- [P1] `HairRibbons`: cabelo como **uma massa de nebulosa** — raiz única, curva em S para trás e para cima, fios
  agrupados em **tufos de 5–10** com comprimentos variados, pontas que se abrem como filamentos; API para marcar
  alguns fios longos como "fios de link" (ponto final configurável) para a continuidade cabelo → grafo.

## art-director (`src/style/**`, `src/ui/**`)

- [P0] `miku_body`: porcelana fosca luminosa — rugosidade 0,45–0,6, especular baixo, wrap/translucidez quente nas
  sombras (BLUSH, não cinza-lilás), sheen só em ângulo rasante; rim por **Fresnel liso** (sem limiar ruidoso —
  contorno "adesivo" serrilhado em MIKU e planetas distantes).
- [P0] `miku_gown`: vestido de **luz** — a metade inferior dissolve em grãos por ruído (nunca barra dura), sem
  espessura interna visível; alimenta o rio do `Stardust`. (NaN já tratados na correção anterior.)
- [P1] `hand_stone`: pedra-noite **legível** — base STONE com profundidade estelar, rim ICE, ouro apagado sempre
  visível, clearcoat bem menor; parâmetro para fade alpha/dissolução no pulso (distância da palma).
- [P1] `planet_forming` estável: atmosfera com gradiente de dispersão, terminador DUSK_ROSE, limbo ICE, continentes
  legíveis — o planeta pronto deve ser **o corpo mais bonito do quadro**, não uma bola cinza. Planetas distantes
  distintos (um com faixas ICE, outro poeira rosa), asteroides com rim e formas mais suaves.
- [P1] `orbit_line`/`relation_thread`: largura ~constante em pixels, fade pelo ângulo de visão da fita (nada de
  "réguas"), fios finos que afinam e somem perto dos corpos.
- [P1] `nebula_sky`: menos estruturas e maiores, variação de densidade, áreas escuras de verdade, filamentos
  brilhantes só perto do núcleo; remover a "lápide" escura e a coluna violeta sem motivo; coração menos cremoso.
- [P1] UI: véu escuro sob rótulos em fundo claro e posicionamento radial fora do casco (MIKU legível sobre o cabelo,
  nada de pilha à esquerda do planeta); missão mostra só o objetivo em curso + passados bem apagados; cartão sem
  moldura (tinta + fio-guia), sem corpo desenhado através do texto; sombra discreta em "all events simulated";
  motes GOLD menores e em menor número.

## animator (`src/entities/**`, `src/fx/**`, `src/animation/**`)

- [P0] Abertura: começa no escuro com só a **semente GOLD** da testa; a luz nasce dela e revela a porcelana, vestido
  ainda em poeira (ou close na semente + grua para trás no despertar). Nenhum quadro de silhueta escura humanoide.
- [P0] Religar o véu (`GOWN_VEIL`, `GOWN_FADE/STRETCH/FLARE`) com a dissolução em grãos + `Stardust`.
- [P0] Sombras em MIKU sem escada: ajuste do rig (PCF suave, `normal_bias`, ou key sem sombra em MIKU com AO fazendo
  o trabalho) — coordene com o game-engineer (atlas/filtro).
- [P1] Clímax em 53 s (`planet.stable`): pico de luz reservado; mãos se retiram devagar num gesto de soltar,
  kintsugi esfria; MIKU ergue a cabeça; halo completa a volta; **um pulso único percorre todos os fios**; grua para
  trás.
- [P1] Pulsos das mãos dissolvem na névoa (fade + poeira); espaço negativo claro: mão direita longe da barra do
  vestido e de NAUVE-2; nenhum enquadramento corta MIKU na cintura.
- [P1] Cabelo com a nova `HairRibbons` (tufos, S); alguns fios longos **visivelmente viram os links** — continuidade
  cabelo → grafo legível no herói e no OBSERVATORY. Links das luas presos ao limbo, finos, não ao centro.
- [P1] UNIVERSE povoado: cinturão denso (milhares de instâncias finas, rim e glints GOLD), planetas distantes
  distintos com luas/anel próprios, núcleo quente enquadrado atrás do sistema.
- [P1] Câmera com 3–4 movimentos desenhados na câmera cinematográfica: grua de aproximação no despertar, dolly baixo
  até o berço no manto, subida no anel/cinturão, recuo no estável; sem pop de exposição (~48–50 s).
- [P2] Gesto de tecer da mão direita (fios de luz passando entre os dedos).

## game-engineer (`src/world/**`, `src/core/**`, `tools/**`)

- [P0] Sombras direcionais GENESIS: atlas/tamanho, filtro suave e splits por perfil sem escada (com o animator).
- [P1] Exposição estável ao longo da sequência (sem pop por modo/plano).
- [P1] **Gravação do jogo real com áudio**: `tools/record_genesis.sh` (Movie Maker, `--scenario=genesis`, câmera
  cinematográfica, 56 s + respiro, áudio no AVI → MP4 H.264 + AAC), para o critério 6 e para a remixagem.

## sound-designer (`src/audio/**`, `assets/audio/**`, `tools/audio/**`)

- [P1] Subgrave: HPF 30–35 Hz nos SFX, recuo de 80–200 Hz da ambiência durante mãos/semente/magma/estável (EQ
  dinâmica ou ducking por banda), peso em harmônicos de 110–220 Hz (lê em alto-falante de notebook). Clímax sonoro
  em 53 s alinhado ao novo clímax visual. Remix contra a gravação do jogo real quando existir.

## Integração da rodada 1

- sound-designer (`cea3000`): HPF 33 Hz nos SFX, raiz harmônica 110–220 Hz, ambiência em stems `floor`/`air`
  (`AudioStreamSynchronized`) com recuo de −8 dB só no floor nos eventos grandes (`LOW_RECESS`), clímax em 53 s
  como pico da mix; prova reprodutível `tools/audio/record_proof.sh` + `bands.py`.
- art-director (`4672a05`): shaders NaN-safe + `test_style_shader_safety.gd`; porcelana fosca com Fresnel liso e
  dissolução em grãos abaixo de `dissolve_top`; vestido só faces frontais; pedra-noite legível; planeta com
  terminador/limbo/continentes e `world_style` para distantes; asteroides com rim; órbitas/fios em pixels constantes
  com fade de perfil e perto dos corpos; nebulosa com vazios (sem "lápide"/coluna); UI radial com véu, missão
  enxuta, cartão sem moldura, sombra no selo.
  **Ganchos para a 2ª passada do animator:** `MaterialLibrary.set_hand_wrist(mat, wrist_center, forearm_end)` em
  `auxiliary_hands.gd`; `MaterialLibrary.set_far_world_style(mat, i)` em `orbital_system._build_far`; religar o véu
  (`GOWN_VEIL = true`, `GOWN_FADE = (-0.35, -5.4)`, `GOWN_STRETCH = 0.75`, `GOWN_FLARE = 0.3`) e a varredura do anel;
  opcionais por órbita `tube_radius`/`body_gap`; `miku_body` dirigível (`dissolve_top/bottom`, `light_turn`,
  `lip_intensity`). Ressalva: planeta herói ainda escuro sob o rig (key no planeta).
