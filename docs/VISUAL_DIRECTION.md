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
A luz âmbar pontual do esqueleto do Loop 1 (`src/world/world.gd`) deve sair (pedido ao game-engineer).

### Selo DEMO MODE (implementação na UI do Loop 3)

O selo é informação permanente, não energia: **texto BONE** em IBM Plex Mono, rótulo curto em
maiúsculas espaçadas, sobre fundo `PANEL` com contorno `PANEL_LINE`; opcionalmente um marcador
quadrado ASH à esquerda. Nunca EMBER (sugeriria atividade/alerta) e nunca PALE (é da verificação).
Fica num canto, pequeno, sempre visível e legível em 1280×720.

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
| `particle(color)` | poeira/faíscas | unshaded, aditivo, billboard de partículas, alpha pela cor do sistema |

### Estrutura: estados

- **INSTANCE_CUSTOM** (por segmento): `r` montagem (0 fragmento solto, 1 assentado),
  `g` flash de verificação (PALE), `b` seleção/hover (BONE), `a` energia de construção (EMBER nas arestas).
- **Uniformes**: `finish` (0 bruto → 1 acabado), `scan_y` + `scan_strength` (banda PALE em Y mundial),
  `final_lock` (linhas EMBER de arco), `energy` (multiplicador global de todo EMBER; padrão 1).
- **Bruto**: cinza fosco claro (ASH→BONE), dielétrico, com costuras finas mais escuras que leem o corte.
  **Opaco de propósito**: translucidez num MultiMesh de 96 instâncias sobrepostas não ordena entre instâncias
  (artefatos), perde sombras e SSAO e custa overdraw em hardware modesto; o "inacabado" é dito pelo valor claro e fosco.
- **Acabado**: metal escuro SLATE, rugosidade média, chanfro fino de tamanho físico que pega a luz e hairline BONE.
  O acabamento só vale para segmentos assentados (`finish × r`).
- **Arestas**: vêm do UV (0..1 por face, garantido pelo MeshBuilder): distância à borda convertida em pixels →
  hairlines de largura constante, com fade quando a face fica pequena na tela (sem cintilação à distância).
- **Montagem** (`a`): todas as arestas do segmento em EMBER, transitório.
- **Forma final** (`final_lock`): EMBER só nas arestas de **arco** (bordas v), que se unem em anéis contínuos
  ao redor da estrutura — discreto, sem contorno de "wireframe".
- **Varredura**: banda gaussiana em Y que acende hairlines e chanfros em PALE; o flash `g` marca checagens.

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
| `active` | `CORE_ACTIVATION` → `MATERIALS_APPLIED` | o núcleo é a fonte: luz EMBER local, key mal existe |
| `lit` | `LIGHTING_APPLIED` | key BONE sobe, a estrutura acabada aparece inteira |
| `verify` | `VERIFICATION_STARTED` → `VERIFICATION_PASSED` | key recua um pouco para a banda PALE ler |
| `final` | `STRUCTURE_FINALIZED` em diante | nível mais alto, núcleo pleno, arcos EMBER |

- Cores: `KEY_COLOR` (BONE, quente-neutro), `FILL_COLOR` e `RIM_COLOR` (ASH, frios), `CORE_COLOR` (EMBER, a única luz quente).
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
  UNIVERSE vê longe (sementes a 18–30 unidades legíveis).

## Custo

Estrutura: um único draw (MultiMesh), opaco, algumas derivadas por pixel, sem texturas. Emissivos de anel são
aditivos sem escrita de profundidade. Os efeitos caros (volumétrica, SSAO, SSIL, glow) obedecem ao perfil de `Quality`.
