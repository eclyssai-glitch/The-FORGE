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
| Drone | chão do universo | senoides em **Lá1 (55 Hz) + Mi2** e Lá2, cada uma com um parceiro desafinado (batimentos lentos de 8–14 s), respiração de 24 s |
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
- Hierarquia: momentos grandes (despertar, mãos, semente, estável) ≈ −16,5 LUFS de curto prazo;
  formações (camadas, anel, fios, poeira) ≈ −17,5; detalhes (luas, cinturão, crosta) ≈ −18; UI
  quase inaudível. Os momentos grandes abaixam a ambiência em 4 dB (ataque 0,6 s, 2,5 s, retorno 3 s).
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
- Ducking por *tween* de volume no `AudioDirector`, não por compressor sidechain: o
  `AudioEffectCompressor.sidechain` existe no 4.7, mas reagiria a qualquer SFX e dependeria do nível;
  o tween é determinístico e só atua nos momentos escolhidos (`DUCKING_SOUNDS`).
- Trims por som em `AudioDirector.SOUND_GAIN_DB` (ajuste de mix sem regenerar assets).
  Ambiência tocada a −2 dB (`AMBIENCE_DB`).
- Pico de cada asset ≤ −1,5 dBTP; a soma em jogo passa pelo limitador do Master.

## Proibições

Bleeps e bips de interface, alarmes, sirenes, "whooshes" e "impacts" de trailer, risers de EDM,
drops, sidechain pumping, trap, glitch/bitcrush cyberpunk, vozes com palavras, qualquer amostra de
terceiros, qualquer serviço/API de geração. Nada de som que sugira conexão real, rede ou erro.

## Evento → som

| Evento (`SimEvent.type`) | Som (`assets/audio/*.ogg`) | Bus | Posição | Duck |
|---|---|---|---|---|
| `miku.awaken` | `sfx_miku_awaken` — acorde que floresce: sinos subindo em Lá lídio + coro "oo→ah" | SFX | âncora `miku` | sim |
| `hands.summoned` | `sfx_hands_summon` — sub Lá1/Mi1, rumble de pedra, sopro "oo" grave | SFX | âncora `hands` | sim |
| `dust.gathered` | `sfx_dust_gather` — enxame granular que sobe e converge ao centro, brilho final | SFX | âncora `planet` | — |
| `planet.seeded` | `sfx_planet_seed` — sino cristalino grave (Lá2) + corpo quente Lá1/Lá2 | SFX | âncora `planet` | sim |
| `planet.layer` (`layer` 0) | `sfx_accretion_0` — magma: pilha harmônica de Lá1 que abre e fecha + murmúrio | SFX | âncora `planet` | — |
| `planet.layer` (`layer` 1) | `sfx_accretion_1` — crosta: cascalho macio sobre quinta "oh" (Mi3/Si3) | SFX | âncora `planet` | — |
| `planet.layer` (`layer` 2) | `sfx_accretion_2` — atmosfera: pad "oh→ah" Dó#4 Mi4 Lá4 + halo Ré#5 + ar | SFX | âncora `planet` | — |
| `moon.formed` (`index` 0 / 1) | `sfx_moon_form` — celesta Mi6→Si6 (índice 1: +1 tom) | SFX | âncora `planet` | — |
| `ring.formed` | `sfx_ring_form` — glissando pelos harmônicos de Lá2, cada harmônico girando no estéreo | SFX | âncora `planet` | — |
| `belt.formed` | `sfx_belt_form` — tilintar granular disperso, grãos distantes mais opacos | SFX | estéreo | — |
| `links.woven` | `sfx_links_woven` — arpejo de harpa pentatônica da esquerda para a direita | SFX | âncora `miku` | — |
| `planet.stable` | `sfx_planet_stable` — acorde de resolução Aadd9 (coro + sinos + raiz) | SFX | estéreo | sim |
| `session.opened`, `session.completed` | — (a ambiência já abre; a cauda do estável fecha) | — | — | — |
| tipos ORIGIN CHAMBER (`core.*`, `structure.*`, `verification.*`, `fragments.*`) | — **ignorados** de propósito: a câmara antiga fica só com a ambiência | — | — | — |
| (UI, via `play_ui`) | `ui_tick` (vidro E7 sobre madeira), `ui_select` (dois toques de vidro Lá6→Mi7) | UI | 2D | — |
| (sempre) | `amb_cosmos_loop` — 72 s, loop | Ambience | 2D | — |

## Níveis (medidos com ffmpeg `ebur128`, nos OGG versionados)

Alvos: ambiência integrado ≈ −24 LUFS; SFX −18 a −16 LUFS de curto prazo (máx.); pico ≤ −1 dBFS
(true peak ≤ −1,5 dBTP na síntese); UI por pico (−24 / −21 dBTP).

| arquivo | dur (s) | I (LUFS) | S máx (LUFS) | M máx (LUFS) | true peak (dBTP) |
|---|---:|---:|---:|---:|---:|
| `amb_cosmos_loop.ogg` | 72.00 | -24.1 | -21.4 | -20.4 | -11.4 |
| `sfx_accretion_0.ogg` | 7.70 | -18.2 | -17.0 | -15.5 | -8.5 |
| `sfx_accretion_1.ogg` | 5.89 | -18.9 | -18.1 | -16.1 | -6.1 |
| `sfx_accretion_2.ogg` | 8.00 | -19.2 | -17.5 | -15.3 | -8.3 |
| `sfx_belt_form.ogg` | 8.00 | -19.8 | -18.0 | -15.2 | -8.2 |
| `sfx_dust_gather.ogg` | 7.22 | -18.9 | -17.5 | -14.7 | -7.9 |
| `sfx_hands_summon.ogg` | 8.00 | -17.9 | -16.5 | -14.7 | -4.9 |
| `sfx_links_woven.ogg` | 6.41 | -17.1 | -17.6 | -13.6 | -4.2 |
| `sfx_miku_awaken.ogg` | 8.00 | -18.0 | -16.5 | -14.0 | -6.8 |
| `sfx_moon_form.ogg` | 5.53 | -17.8 | -18.0 | -12.4 | -7.3 |
| `sfx_planet_seed.ogg` | 8.00 | -18.3 | -17.0 | -14.7 | -7.9 |
| `sfx_planet_stable.ogg` | 8.00 | -17.6 | -16.0 | -15.2 | -6.6 |
| `sfx_ring_form.ogg` | 8.00 | -19.0 | -17.6 | -15.3 | -9.3 |
| `ui_select.ogg` | 1.01 | -33.0 | n/a (< 3 s) | -29.0 | -21.1 |
| `ui_tick.ogg` | 0.59 | -38.4 | n/a (< 3 s) | -38.4 | -24.1 |

Total de `assets/audio`: ≈ 2,1 MB (OGG Vorbis q5, 48 kHz, estéreo).

## Loop sem emenda

A ambiência não usa crossfade: é **periódica por construção** em T = 72 s. Frequências de
osciladores, batimentos e LFOs são múltiplos inteiros de 1/T; o vento é ruído sintetizado por
FFT sobre T amostras; os grãos de brilho dão a volta no fim; o reverb é convolução **circular**
(a cauda do fim entra no começo). O salto entre a última e a primeira amostra é da ordem de um
passo normal entre amostras (o gerador imprime `seam_jump`). O `.import` do OGG tem `loop=true`.

## AudioDirector (`src/audio/audio_director.gd`)

`class_name AudioDirector extends Node`, construtor sem argumentos; composto pelo `world.gd` por
caminho na Fase B (funciona sozinho quando adicionado à árvore; exige os autoloads).

- Tabelas puras: `EVENT_SOUNDS`, `LAYER_SOUNDS`, `UI_SOUNDS`, `SOUND_ANCHORS`, `SOUND_GAIN_DB`,
  `DUCKING_SOUNDS`; estáticas `sound_for(event) -> StringName`, `pitch_for(event)`,
  `is_late(event, now)`, `sound_path(sound)`, `all_sounds()`.
- `handle_event(event, now) -> StringName` (toca, ou `&""` se sem som/atrasado >
  `LATE_TOLERANCE` = 0,5 s), `play_sound(sound, pitch)`, `play_ui(sound)`, `stop_all_sfx(fade)`,
  `set_paused(bool)`, `duck()`, `start_ambience()`, `active_voices()`, `ambience_db()`.
- `set_anchor(kind: StringName, node: Node3D)` / `get_anchor(kind)` — `&"planet"`, `&"miku"`,
  `&"hands"`; `null` remove.
- Buses (estáticas): `set_bus_volume_db(bus, db)`, `get_bus_volume_db(bus)`,
  `set_bus_mute(bus, muted)`, `is_bus_muted(bus)`; sem persistência por enquanto.
- Sinais: `Simulation.event_emitted` → `handle_event(e, Simulation.time)`;
  `world_rebuilt` → fade de 0,25 s e stop de todos os SFX, ducking zerado (sem rajadas);
  `playback_changed` → PAUSED pausa/abaixa, outro estado retoma.
- Pools fixos: 8 `AudioStreamPlayer` + 6 `AudioStreamPlayer3D` (roubo da voz mais antiga) e
  1 player de UI (polifonia 4). Nenhuma alocação por evento.

## Como regenerar

```
tools/audio/build_all.sh                  # síntese → build/audio/wav → assets/audio/*.ogg + tabela ebur128
tools/audio/build_all.sh --check          # refaz só os WAV e compara com tools/audio/wav.sha256
tools/audio/build_all.sh --update-hashes  # build completo + reescreve wav.sha256
tools/audio/inspect.sh                    # espectrograma + forma de onda de cada som (build/audio/inspect)
tools/audio/render_proof.sh REC.avi       # prova audível a partir de uma gravação Movie Maker
```

Requer o venv `/opt/korium-py` (numpy, scipy — ADR-013; `KORIUM_PY` para outro Python) e
`ffmpeg` com `libvorbis`. Depois de regenerar, rode `godot --headless --import` (o `.import` da
ambiência mantém `loop=true`). **Reprodutibilidade:** a síntese é determinística (sementes fixas);
o mesmo comando gera WAV idênticos byte a byte (verificado por `--check`). Os bytes do OGG podem
variar entre versões do libvorbis/ffmpeg (o encoder não é contratual); por isso só os WAV têm hash.
`tools/audio/.gdignore` impede o Godot de importar os scripts e PNGs da prova.

Arquivos: `dsp.py` (osciladores, envelopes, IR, loudness BS.1770, limitador), `synth_ambience.py`,
`synth_sfx.py`, `measure.py`, `build_all.sh`, `inspect.sh`, `render_proof.sh`, `proof/`.
