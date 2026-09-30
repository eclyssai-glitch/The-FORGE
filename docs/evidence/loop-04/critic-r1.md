# Loop 4 — revisão art-critic, rodada 1 (commit `eaa03d1`)

Revisor: `art-critic` (independente, somente leitura). Material: style frames 1920×1080 `sf_01…08`
(`tools/style_frames.sh`), capturas `g01…g18` (`tools/capture_evidence.sh --scenario=genesis`), sequência de
movimento (1 quadro/2 s), previews de escultura, UI (`docs/art/ui-genesis/`), prova de áudio
(`tools/audio/proof/`), comparação com `docs/evidence/loop-03/`. Áudio julgado por métricas (ebur128: I −20,0 LUFS,
LRA 6,1 LU, TP −6,3 dBFS; < 300 Hz −25 LUFS, > 300 Hz −21,6).

**Veredito: REPROVADO (perto do corte) — nota 6/10** para "parece o início de um universo autoral memorável".

## Primeira impressão
De longe, um quadro de criação cósmica com poesia real; de perto, a protagonista é um manequim de vinil entre duas
luvas de borracha preta, e a abertura (g01) mostra uma silhueta escura de alienígena.

## Pontos fortes
- Salto enorme sobre a v0.1 (gaiola de anéis): assunto, gesto de criação, contraluz motivada, clima.
- Composição herói forte (`sf_01`, `g13`, `g18`); `sf_03` (berço com magma e kintsugi) é o quadro mais memorável.
- Paleta disciplinada (índigo, rosa, ouro, pérola; sem neon nem turquesa); diferenciação de franquias respeitada.
- Fase de magma (20–28 s) é o momento de espetáculo que funciona.
- UI é o maior acerto: selo pequeno, três palavras, transporte em arco, fases poéticas; a cena é de fato o herói;
  OBSERVATORY lê "vault como astronomia".
- Som coerente com a bíblia: tonalidade única, eventos legíveis, sem clipping, sem bleeps.

## Problemas (resumo; lista acionável por dono em `docs/contracts/loop-04-fixes.md`)
- [P0] MIKU lê como manequim/alienígena/boneca de vinil (careca com ponto na testa, planos de vitrine, ombros
  quadrados, braços finos, "cós" na cintura, látex brilhante com especular nos seios).
- [P0] Abertura (0–4 s) inquietante: figura alta, escura, careca, palmas abertas ("grey alien").
- [P0] O "vestido de luz" não existe: bainha opaca de cetim, barra dura, espessura interna; véu desligado por NaN.
- [P0] Artefatos de render nos style frames: sombra em escada no torso/vestido; buraco escuro no tronco e braço
  "derretendo" no quadril; contorno claro serrilhado (efeito adesivo) em MIKU e planetas distantes.
- [P1] Mãos parecem luvas de látex preto (clearcoat forte, quase preto, dedos "salsicha", corte cilíndrico no pulso).
- [P1] Tangências: indicador da mão direita toca a barra do vestido e NAUVE-2; enquadramentos cortam MIKU na cintura.
- [P1] Clímax anticlimático: planeta estável é bola cinza-escura; `planet.stable` sem batida visual.
- [P1] Links das luas parecem modelo molecular (hastes do centro).
- [P1] Órbitas/cinturão de lado viram "réguas".
- [P1] UNIVERSE vazio (cinturão de uma dúzia de pontos, planetas distantes idênticos e pretos, "lápide" no céu).
- [P1] Asteroides/planetas distantes com cara de placeholder.
- [P1] Cabelo não é "uma massa de nebulosa" (leque radial/eletrizado); continuidade cabelo → fios não se lê.
- [P1] Nebulosa com ruído "plasma/neurônio" em escala uniforme.
- [P1] Câmera quase travada por 56 s; salto de exposição ~48–50 s.
- [P1] Colisões de rótulos no OBSERVATORY; missão lê como checklist.
- [P1] Carpete de subgrave (20–120 Hz) nos eventos grandes; falta vídeo do jogo real com áudio.
- [P2] Subtítulo do selo some sobre a nebulosa clara; cartão com moldura; planeta em close como "bola de gude
  rachada"; motes como bokeh; gesto do indicador remete à "Criação de Adão".

## Ainda parece protótipo técnico?
Não como diagrama de engenharia — essa fase acabou. Mas o acabamento ainda é de protótipo: protagonista-manequim,
mãos de borracha, artefatos de render, UNIVERSE vazio e clímax que apaga.

Para ≥ 7: os quatro P0. Para ≥ 8: somar mãos em pedra-noite legível, clímax com resolução visual, UNIVERSE povoado,
continuidade cabelo → fios visível, câmera com 3–4 movimentos desenhados e vídeo do jogo real com áudio limpo.
