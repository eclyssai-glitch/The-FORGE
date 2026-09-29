# Prova audível — sequência GENESIS pelo AudioDirector

Gravação feita com o Movie Maker do Godot 4.7.2 (`--write-movie genesis.avi --fixed-fps 30
--quit-after 1830`, 61 s, sob xvfb). O AVI inclui o áudio renderizado pelo motor. Uma cena
temporária (não versionada, apagada após a gravação) instanciou um `AudioDirector`, uma `Camera3D`
em (0, 2.5, 17) olhando para (0, 2, 2) e três âncoras registradas com `set_anchor`
(`planet` (0, 1, 4), `miku` (0, 4, 0), `hands` (0.1, 0.9, 4.7)) — os SFX ancorados tocaram em
`AudioStreamPlayer3D`. Os eventos foram emitidos por `Simulation.event_emitted` num relógio de
quadros (30 fps):

| t (s) | evento | som |
|---:|---|---|
| 0 | `session.opened` | — (ambiência entra em fade de 4 s) |
| 3 | `miku.awaken` | `sfx_miku_awaken` (duck) |
| 8 | `hands.summoned` | `sfx_hands_summon` (duck) |
| 13 | `dust.gathered` | `sfx_dust_gather` |
| 18 | `planet.seeded` | `sfx_planet_seed` (duck) |
| 22 / 27 / 32 | `planet.layer` 0 / 1 / 2 | `sfx_accretion_0/1/2` |
| 37 / 40 | `moon.formed` 0 / 1 | `sfx_moon_form` (1: +1 tom) |
| 43 | `ring.formed` | `sfx_ring_form` |
| 46 | `belt.formed` | `sfx_belt_form` |
| 50 | `links.woven` | `sfx_links_woven` |
| 53 | `planet.stable` | `sfx_planet_stable` (duck) |
| 56 | `session.completed` | — |

Arquivos: `genesis_mix_spectrogram.png` (1600x600, escala log 30 Hz–16 kHz),
`genesis_mix_waveform.png` (L em cima, R embaixo), `genesis_mix.ogg` (a mix inteira, Vorbis q2).
Regerar a partir de uma gravação: `tools/audio/render_proof.sh genesis.avi`.

## Medição (ffmpeg `ebur128`, mix extraída do AVI em PCM float)

| arquivo | dur (s) | I (LUFS) | S máx (LUFS) | M máx (LUFS) | true peak (dBTP) |
|---|---:|---:|---:|---:|---:|
| `genesis_mix.wav` | 61.00 | -19.9 | -15.8 | -15.1 | -6.1 |

Loudness K-ponderada por trecho (mesmo arquivo): 0,5–2,9 s (ambiência entrando) −37,5 LUFS;
5–7,9 s (cauda do despertar) −20,9; 9–12 s (mãos) −19,4; 20–21,9 s (cauda da semente, entre
eventos) −23,8; 34–36,9 s (atmosfera) −20,2; 57–61 s (cauda do estável) −19,7. A ambiência sozinha
fica em ≈ −26 LUFS (asset −24, `AMBIENCE_DB` −2), 6–10 dB abaixo dos momentos de formação.

## Inspeção

- Espectrograma: cada evento é legível no tempo — o arpejo de sinos subindo a partir de 3 s, o
  bloco grave das mãos em 8 s, o enxame granular de 13–17 s subindo até ~6 kHz, a semente em 18 s,
  o magma grave (22 s), os grãos da crosta (27–30 s, riscos verticais suaves até ~4 kHz), a
  atmosfera em formantes (32 s), as linhas finas da celesta das luas (37 e 40 s, a segunda mais
  alta), a diagonal do glissando harmônico do anel (43–47 s), o tilintar disperso do cinturão
  (46–50 s), o risco do arpejo de harpa (50–51 s) e o acorde amplo de resolução a partir de 53 s.
- Ambiência presente o tempo todo (drone grave contínuo e faixa de formantes do pad em torno de
  800 Hz) mas abaixo dos eventos; nada acima de −6 dBTP, nenhum clipping; o limitador do Master
  (−1 dB) não precisou atuar.
- Forma de onda: sem transientes isolados; entradas em crescendo e caudas longas.
