<!-- Dono: sound-designer. Responsabilidade: linguagem sonora, assets de áudio, mixagem e AudioDirector. -->
# Áudio — KORIUM UNIVERSE · GENESIS

## Conceito

O som de GENESIS é **o espaço respirando enquanto algo nasce**. Não há "interface" sonora: tudo é
matéria (pedra estelar, poeira, vidro, cristal) e ar (voz sem palavras, vento cósmico). A cena tem
uma única tonalidade, e cada formação acrescenta uma cor a esse acorde, até o planeta estável
resolver tudo num acorde amplo. Contemplativo, cósmico, poético, elegante, cinematográfico —
cinema de observatório, nunca trailer.

## Paleta tímbrica

| Família | Uso | Construção (offline, `tools/audio/`) |
|---|---|---|
| Drone | chão do universo | **Lá1 (55 Hz) + Mi2** e Lá2, cada um com 4 harmônicos de peso real (1 : 0,62 : 0,36 : 0,2) e um parceiro desafinado (batimentos lentos de 8–14 s), respiração de 24 s |
| Raiz harmônica | mãos, semente, magma, estável | `harmonic_root`: Lá1 com o peso nos harmônicos **Lá2 Mi3 Lá3 (110–220 Hz)** (1 : 0,45 → 2 : 0,85, 3 : 0,62, 4 : 0,4, 5–6 leves), cada parcial com gêmeo desafinado; o ouvido reconstrói o Lá1 mesmo em alto-falante de notebook |
| Coro etéreo | MIKU, atmosfera, resolução | síntese aditiva com envelope de formantes (vogais "oo/oh/ah"), vozes com deriva lenta de afinação aleatória (sem vibrato operístico), abertas no estéreo |
| Sinos cristalinos | despertar, semente, brilhos | parciais quase harmônicos (1, 2, 3.01, 4.16, 5.43, 6.79) com pares desafinados que cintilam; parciais altos decaem antes |
| Celesta | luas (documentação) | barra percutida: fundamental + oitava + 4º harmônico, baqueta macia |
| Harpa | fios relacionais | Karplus-Strong com excitação suavizada (dedo, não palheta) |
| Pedra | mãos, crosta | grãos de ruído filtrado graves/médios, ataques ≥ 3–7 ms, densidade que respira |
| Vento cósmico | ambiência | ruído sintetizado no domínio da frequência em 5 bandas com movimento lento independente |
| Espaço | tudo | reverb por convolução com IR sintética (ruído estéreo decorrelacionado, decaimento exponencial por banda, RT60 0,8–7 s) |

## Tonalidade

**Lá lídio / Lá pentatônico maior.** Drone em Lá1 (55 Hz) com a quinta (Mi). Os SFX usam a
pentatônica (Lá Si Dó# Mi Fá#) e a quarta aumentada lídia (Ré#) apenas como cor suspensa
(despertar de MIKU, halo da atmosfera, acorde Amaj7#11 do pad). Nenhum som sai da tonalidade;
a segunda lua toca um tom acima (Mi→Fá#, Si→Dó#), ainda na pentatônica.

## Dinâmica

- Nada começa com transiente duro. Mãos, magma e atmosfera entram em crescendo (0,8–2,4 s);
  sinos e harpa têm ataque de 3–15 ms com cauda longa.
- Hierarquia: **clímax** (`planet.stable`, 53 s) −15 LUFS de curto prazo — o momento mais pleno
  e mais alto da mix, alinhado ao pico de luz visual; momentos grandes (despertar, mãos, semente)
  ≈ −16,5; formações (camadas, anel, fios, poeira) ≈ −17,5; detalhes (luas, cinturão, crosta)
  ≈ −18; UI quase inaudível. Despertar, mãos e semente abaixam a ambiência inteira em 4 dB
  (ataque 0,6 s, 2,5 s, retorno 3 s); o clímax não: a ambiência fica sob ele.
- Clímax: o acorde chega de uma vez (cacho de sinos Lá3 Mi4 Lá4 no próprio evento, cascata até
  Mi6 em 0,9 s) e continua abrindo — coro grave Aadd9 "oh→ah" (0,9 s), coro agudo "ah" Lá4 Dó#5
  Mi5 (1,4 s), raiz harmônica (0,6 s) e halo de ar em ~6 kHz: todos os registros ao mesmo tempo.

## Grave (correção do loop 4: "carpete de subgrave")

O grave de GENESIS é **sentido, não empilhado**. Regras:

- Todo SFX passa por um passa-altas causal (sem pré-eco) Butterworth de 6ª ordem em **33 Hz**
  (`SFX_HPF_HZ`; −15 dB em 25 Hz, −25 dB em 20 Hz, plano a partir de 45 Hz: Lá1 intacto).
- Nada de Mi1 (41 Hz) nem saturação de Lá1+Mi1 (intermodulação a 14 Hz). Mãos, semente, magma e
  estável usam a raiz harmônica (tabela acima): energia em 110–220 Hz, Lá1 ~6 dB abaixo do Lá2.
- A ambiência é tocada em **dois stems complementares** do mesmo loop — `amb_cosmos_floor`
  (abaixo de ~230 Hz: drone e pé do vento; transição cosseno em escala log 180–300 Hz, fase
  linear, circular) e `amb_cosmos_air` (o resto); `floor + air` = o loop original, ambos sem
  emenda. O jogo os toca travados amostra a amostra (`AudioStreamSynchronized`) e, sob os
  momentos graves (`LOW_RECESS`: mãos 3,5 s, semente 2,5 s, magma 3,5 s, estável 5 s), **recua só
  o floor em 8 dB** (ataque 0,8 s, retorno 3,5 s): o grave do evento ocupa o lugar do grave do
  ambiente, em vez de somar a ele.
- Por que stems e não EQ no bus: o `AudioEffectEQ21` do Godot 4.7 é um banco de passa-faixas em
  paralelo — medido no Movie Maker, plano a 0 dB ele soma +3,5 dB com ondulação de ±1 dB em todo
  o espectro, e −6 dB numa banda rende ~−5 dB. Ficaria colorindo a ambiência o tempo todo. Os
  stems são cruzados offline com reconstrução exata; a sincronia do `AudioStreamSynchronized` foi
  verificada (ruído + ruído invertido = −240 dBFS) e o volume por stem muda ao vivo.
- Verificação: `tools/audio/bands.py` (ebur128 abaixo/acima de 300 Hz e energia por banda —
  SUB 20–35, LOW 35–80, BODY 80–200, WARM 110–220, MID 200–2k, HIGH 2k–16k — em cada momento).
- Pausa: SFX fazem fade (0,35 s) e ficam pausados; a ambiência cai ~6 dB e escurece
  (passa-baixa do bus Ambience 20 kHz → 2,4 kHz); ao tocar, tudo volta.

## Espacialização

- Ambiência e acordes envolventes (cinturão, estável) são estéreo, não posicionais.
- SFX com fonte clara usam `AudioStreamPlayer3D` quando o mundo registra a âncora:
  `miku` (despertar, fios), `hands` (mãos), `planet` (poeira, semente, camadas, luas, anel).
  Atenuação inversa suave (`unit_size` 16: nível cheio até 16 u, −6 dB por dobra de distância
  depois), `panning_strength` 0,7, sem passa-baixa de distância (as caudas já são macias).
- Sem âncora (ou âncora liberada) → `AudioStreamPlayer` 2D no bus SFX.

## Regras de mix

- Buses (`res://default_bus_layout.tres`, carregado pelo Godot por padrão —
  `audio/buses/default_bus_layout` = `res://default_bus_layout.tres`; `project.godot` não muda):
  **Master** (HardLimiter, teto −1 dB) · **Ambience** → Master (passa-baixa "AmbienceTone",
  aberto em 20 kHz) · **SFX** → Master · **UI** → Master.
  O arquivo está versionado na forma canônica que o Godot 4.7.2 grava ao importar (com
  `uid://fxi7fabt56xw`, volumes 0 dB omitidos); `godot --headless --import` não o altera mais.
- Ducking por *tween* de volume no `AudioDirector`, não por compressor sidechain: o
  `AudioEffectCompressor.sidechain` existe no 4.7, mas reagiria a qualquer SFX e dependeria do nível;
  o tween é determinístico e só atua nos momentos escolhidos (`DUCKING_SOUNDS`: ambiência inteira;
  `LOW_RECESS`: só o stem floor, ver "Grave").
- Trims por som em `AudioDirector.SOUND_GAIN_DB` (ajuste de mix sem regenerar assets).
  Ambiência tocada a −2 dB (`AMBIENCE_DB`).
- Pico de cada asset ≤ −1,5 dBTP; a soma em jogo passa pelo limitador do Master.

## Proibições

Bleeps e bips de interface, alarmes, sirenes, "whooshes" e "impacts" de trailer, risers de EDM,
drops, sidechain pumping, trap, glitch/bitcrush cyberpunk, vozes com palavras, qualquer amostra de
terceiros, qualquer serviço/API de geração. Nada de som que sugira conexão real, rede ou erro.

## Evento → som

Duck: ambiência inteira −4 dB (`DUCKING_SOUNDS`). Floor: recuo de −8 dB só do stem grave da
ambiência (`LOW_RECESS`, tempo de sustentação).

| Evento (`SimEvent.type`) | Som (`assets/audio/*.ogg`) | Bus | Posição | Duck | Floor |
|---|---|---|---|---|---|
| `miku.awaken` | `sfx_miku_awaken` — acorde que floresce: sinos subindo em Lá lídio + coro "oo→ah" | SFX | âncora `miku` | sim | — |
| `hands.summoned` | `sfx_hands_summon` — raiz harmônica de Lá1 (peso em Lá2 Mi3 Lá3), rumble de pedra em 75–260 Hz, sopro "oo" grave | SFX | âncora `hands` | sim | 3,5 s |
| `dust.gathered` | `sfx_dust_gather` — enxame granular que sobe e converge ao centro, brilho final | SFX | âncora `planet` | — | — |
| `planet.seeded` | `sfx_planet_seed` — sino cristalino grave (Lá2) + corpo quente (raiz harmônica de Lá1) | SFX | âncora `planet` | sim | 2,5 s |
| `planet.layer` (`layer` 0) | `sfx_accretion_0` — magma: pilha harmônica de Lá1/Mi2 que abre e fecha (fundamentais afinadas: peso em 110–220 Hz) + murmúrio 90–320 Hz | SFX | âncora `planet` | — | 3,5 s |
| `planet.layer` (`layer` 1) | `sfx_accretion_1` — crosta: cascalho macio sobre quinta "oh" (Mi3/Si3) | SFX | âncora `planet` | — | — |
| `planet.layer` (`layer` 2) | `sfx_accretion_2` — atmosfera: pad "oh→ah" Dó#4 Mi4 Lá4 + halo Ré#5 + ar | SFX | âncora `planet` | — | — |
| `moon.formed` (`index` 0 / 1) | `sfx_moon_form` — celesta Mi6→Si6 (índice 1: +1 tom) | SFX | âncora `planet` | — | — |
| `ring.formed` | `sfx_ring_form` — glissando pelos harmônicos de Lá2, cada harmônico girando no estéreo | SFX | âncora `planet` | — | — |
| `belt.formed` | `sfx_belt_form` — tilintar granular disperso, grãos distantes mais opacos | SFX | estéreo | — | — |
| `links.woven` | `sfx_links_woven` — arpejo de harpa pentatônica da esquerda para a direita | SFX | âncora `miku` | — | — |
| `planet.stable` | `sfx_planet_stable` — **clímax**: cacho de sinos no evento em cascata até Mi6, coro Aadd9 grave + coro "ah" agudo, raiz harmônica, halo de ar; −15 LUFS S | SFX | estéreo | **não** (a ambiência fica sob o clímax) | 5 s |
| `session.opened`, `session.completed` | — (a ambiência já abre; a cauda do estável fecha) | — | — | — | — |
| tipos ORIGIN CHAMBER (`core.*`, `structure.*`, `verification.*`, `fragments.*`) | — **ignorados** de propósito: a câmara antiga fica só com a ambiência | — | — | — | — |
| (UI, via `play_ui`) | `ui_tick` (vidro E7 sobre madeira), `ui_select` (dois toques de vidro Lá6→Mi7) | UI | 2D | — | — |
| (sempre) | `amb_cosmos_floor` + `amb_cosmos_air` — 72 s, loop, travados num `AudioStreamSynchronized` | Ambience | 2D | — | — |

## Níveis (medidos com ffmpeg `ebur128`, nos OGG versionados)

Alvos: ambiência integrado ≈ −24 LUFS (floor + air; o gerador mede a soma: −24,0); SFX −18 a
−16 LUFS de curto prazo (máx.), clímax −15; pico ≤ −1 dBFS (true peak ≤ −1,5 dBTP na síntese);
UI por pico (−24 / −21 dBTP).

| arquivo | dur (s) | I (LUFS) | S máx (LUFS) | M máx (LUFS) | true peak (dBTP) |
|---|---:|---:|---:|---:|---:|
| `amb_cosmos_air.ogg` | 72.00 | -25.8 | -22.9 | -21.5 | -13.2 |
| `amb_cosmos_floor.ogg` | 72.00 | -29.4 | -27.2 | -26.0 | -17.5 |
| `sfx_accretion_0.ogg` | 7.66 | -18.2 | -17.0 | -15.4 | -8.1 |
| `sfx_accretion_1.ogg` | 5.89 | -19.0 | -18.2 | -16.1 | -5.8 |
| `sfx_accretion_2.ogg` | 8.00 | -19.2 | -17.5 | -15.3 | -8.4 |
| `sfx_belt_form.ogg` | 8.00 | -19.8 | -18.0 | -15.2 | -8.3 |
| `sfx_dust_gather.ogg` | 7.22 | -18.9 | -17.5 | -14.8 | -7.8 |
| `sfx_hands_summon.ogg` | 8.00 | -18.0 | -16.5 | -14.0 | -5.8 |
| `sfx_links_woven.ogg` | 6.41 | -17.1 | -17.6 | -13.6 | -4.3 |
| `sfx_miku_awaken.ogg` | 8.00 | -18.0 | -16.5 | -14.0 | -6.7 |
| `sfx_moon_form.ogg` | 5.54 | -17.8 | -18.0 | -12.4 | -7.5 |
| `sfx_planet_seed.ogg` | 8.00 | -19.4 | -17.0 | -12.9 | -6.0 |
| `sfx_planet_stable.ogg` | 8.00 | -16.6 | -15.0 | -13.6 | -3.4 |
| `sfx_ring_form.ogg` | 8.00 | -19.0 | -17.6 | -15.4 | -9.5 |
| `ui_select.ogg` | 1.01 | -33.0 | n/a (< 3 s) | -29.0 | -21.2 |
| `ui_tick.ogg` | 0.59 | -38.1 | n/a (< 3 s) | -38.1 | -23.9 |

Total de `assets/audio`: ≈ 2,4 MB (OGG Vorbis q5, 48 kHz, estéreo).

## Loop sem emenda

A ambiência não usa crossfade: é **periódica por construção** em T = 72 s. Frequências de
osciladores, batimentos e LFOs são múltiplos inteiros de 1/T; o vento é ruído sintetizado por
FFT sobre T amostras; os grãos de brilho dão a volta no fim; o reverb é convolução **circular**
(a cauda do fim entra no começo). O salto entre a última e a primeira amostra é da ordem de um
passo normal entre amostras (o gerador imprime `seam_jump`). A divisão floor/air é feita no
domínio da frequência sobre o loop inteiro (circular), então cada stem também é periódico; os
dois têm exatamente o mesmo comprimento e `loop=true` no `.import`.

## AudioDirector (`src/audio/audio_director.gd`)

`class_name AudioDirector extends Node`, construtor sem argumentos; composto pelo `world.gd` por
caminho na Fase B (funciona sozinho quando adicionado à árvore; exige os autoloads).

- Tabelas puras: `EVENT_SOUNDS`, `LAYER_SOUNDS`, `UI_SOUNDS`, `SOUND_ANCHORS`, `SOUND_GAIN_DB`,
  `DUCKING_SOUNDS`, `LOW_RECESS` (som → sustentação do recuo do floor), `AMBIENCE_STEMS`
  (`amb_cosmos_floor`, `amb_cosmos_air`; índice `AMB_FLOOR` = 0); estáticas
  `sound_for(event) -> StringName`, `pitch_for(event)`, `is_late(event, now)`,
  `sound_path(sound)`, `all_sounds()`.
- `handle_event(event, now) -> StringName` (toca, ou `&""` se sem som/atrasado >
  `LATE_TOLERANCE` = 0,5 s), `play_sound(sound, pitch)`, `play_ui(sound)`, `stop_all_sfx(fade)`,
  `set_paused(bool)`, `duck()`, `recess_floor(hold)`, `start_ambience()`, `active_voices()`,
  `ambience_db()`, `ambience_floor_db()`.
- `ambience_player.stream` é um `AudioStreamSynchronized` (floor, air) montado em código; o
  volume do floor (`set_sync_stream_volume`) segue `_amb_floor_db` a cada quadro.
- `set_anchor(kind: StringName, node: Node3D)` / `get_anchor(kind)` — `&"planet"`, `&"miku"`,
  `&"hands"`; `null` remove.
- Buses (estáticas): `set_bus_volume_db(bus, db)`, `get_bus_volume_db(bus)`,
  `set_bus_mute(bus, muted)`, `is_bus_muted(bus)`; sem persistência por enquanto.
- Sinais: `Simulation.event_emitted` → `handle_event(e, Simulation.time)`;
  `world_rebuilt` → fade de 0,25 s e stop de todos os SFX, ducking e recuo zerados (sem rajadas);
  `playback_changed` → PAUSED pausa/abaixa, outro estado retoma.
- Pools fixos: 8 `AudioStreamPlayer` + 6 `AudioStreamPlayer3D` (roubo da voz mais antiga) e
  1 player de UI (polifonia 4). Nenhuma alocação por evento.

## Como regenerar

```
tools/audio/build_all.sh                  # síntese → build/audio/wav → assets/audio/*.ogg + tabela ebur128
tools/audio/build_all.sh --check          # refaz só os WAV e compara com tools/audio/wav.sha256
tools/audio/build_all.sh --update-hashes  # build completo + reescreve wav.sha256
tools/audio/inspect.sh                    # espectrograma + forma de onda de cada som (build/audio/inspect)
tools/audio/record_proof.sh [OUT]         # grava GENESIS (Simulation + AudioDirector reais, Movie Maker) e gera a prova
tools/audio/render_proof.sh REC.avi       # prova audível a partir de qualquer gravação Movie Maker (ex.: a do jogo)
tools/audio/bands.py FILE                 # ebur128 abaixo/acima de 300 Hz + energia por banda e S máx por momento
```

A prova (`tools/audio/proof/`, README com antes/depois) vem de `record_proof.sh`: a cena
`tools/audio/proof_rig/genesis_audio_proof.tscn` (fora do jogo, não exportada) toca GENESIS do
zero pela `Simulation` real com câmera e âncoras fixas — repetível, ~3–6 min sob xvfb.

Requer o venv `/opt/korium-py` (numpy, scipy — ADR-013; `KORIUM_PY` para outro Python) e
`ffmpeg` com `libvorbis`. Depois de regenerar, rode `godot --headless --import` (os `.import` dos
dois stems da ambiência mantêm `loop=true`). **Reprodutibilidade:** a síntese é determinística (sementes fixas);
o mesmo comando gera WAV idênticos byte a byte (verificado por `--check`). Os bytes do OGG podem
variar entre versões do libvorbis/ffmpeg (o encoder não é contratual); por isso só os WAV têm hash.
`tools/audio/.gdignore` impede o Godot de importar os scripts e PNGs da prova.

Arquivos: `dsp.py` (osciladores, envelopes, IR, loudness BS.1770, limitador), `synth_ambience.py`,
`synth_sfx.py`, `measure.py`, `bands.py`, `build_all.sh`, `inspect.sh`, `record_proof.sh`,
`render_proof.sh`, `proof_rig/`, `proof/`.
