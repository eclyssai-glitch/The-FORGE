# Prova audível — sequência GENESIS pelo AudioDirector (loop 4, rodada de correção 1)

Gravada com `tools/audio/record_proof.sh`: Movie Maker do Godot 4.7.2 (`--write-movie
--fixed-fps 30 --quit-after 1860`, 62 s de tempo de jogo, sob xvfb; o AVI leva a mix do próprio
motor, 48 kHz). A cena versionada `tools/audio/proof_rig/genesis_audio_proof.tscn` (fora do jogo,
não exportada) toca GENESIS do zero pela **`Simulation` real** (`set_scenario(&"genesis")` +
`start()`): os eventos chegam por `Simulation.event_emitted` nos tempos do roteiro e o
`AudioDirector` real os toca. Câmera (ouvinte) em (0, 2.5, 17) olhando para (0, 2, 2); âncoras
`planet` (0, 1, 4), `miku` (0, 4, 0), `hands` (0.1, 0.9, 4.7) — os SFX ancorados tocam em
`AudioStreamPlayer3D`.

| t (s) | evento | som | ambiência |
|---:|---|---|---|
| 0 | `session.opened` | — | fade de entrada de 4 s |
| 3 | `miku.awaken` | `sfx_miku_awaken` | duck −4 dB |
| 8 | `hands.summoned` | `sfx_hands_summon` | duck −4 dB + floor −8 dB (3,5 s) |
| 13 | `dust.gathered` | `sfx_dust_gather` | — |
| 18 | `planet.seeded` | `sfx_planet_seed` | duck −4 dB + floor −8 dB (2,5 s) |
| 22 / 27 / 32 | `planet.layer` 0 / 1 / 2 | `sfx_accretion_0/1/2` | magma: floor −8 dB (3,5 s) |
| 37 / 40 | `moon.formed` 0 / 1 | `sfx_moon_form` (1: +1 tom) | — |
| 43 | `ring.formed` | `sfx_ring_form` | — |
| 46 | `belt.formed` | `sfx_belt_form` | — |
| 50 | `links.woven` | `sfx_links_woven` | — |
| 53 | `planet.stable` | `sfx_planet_stable` (**clímax**) | só floor −8 dB (5 s); sem duck |
| 56 | `session.completed` | — | — |

Arquivos: `genesis_mix_spectrogram.png` (1600x600, log 30 Hz–16 kHz), `genesis_mix_waveform.png`
(L em cima, R embaixo), `genesis_mix.ogg` (a mix inteira, Vorbis q2). Medições:
`tools/audio/measure.py` e `tools/audio/bands.py` sobre o PCM extraído do AVI.

## Antes / depois (mesmo rig, mesma câmera; "antes" = assets e diretor do commit `6f96c75`)

ebur128 da mix inteira:

| | I (LUFS) | S máx (LUFS) | M máx (LUFS) | true peak (dBTP) | < 300 Hz (LUFS) | > 300 Hz (LUFS) |
|---|---:|---:|---:|---:|---:|---:|
| antes | −20,0 | −15,8 | −15,1 | −6,1 | −25,8 | −21,8 |
| depois | −19,8 | −14,8 | −13,3 | −3,0 | −26,8 | −21,3 |

(O art-critic mediu −25 / −21,6 com outro filtro de divisão; aqui a divisão é Butterworth de fase
zero em 300 Hz, `bands.py`.)

Energia por banda (dBFS RMS, sem ponderação) nos momentos graves que formavam o "carpete"; LOW =
35–80 Hz, WARM = 110–220 Hz (o que um alto-falante de notebook ainda toca), SUB = 20–35 Hz:

| momento | SUB antes → depois | LOW antes → depois | WARM antes → depois | WARM−LOW antes → depois |
|---|---:|---:|---:|---:|
| mãos 8–13 s | −43,2 → −58,9 | −19,3 → −34,5 | −30,6 → −26,0 | −11,2 → +8,5 |
| semente 18–21 s | −58,6 → −57,4 | −21,6 → −28,2 | −25,7 → −24,6 | −4,1 → +3,6 |
| magma 22–27 s | −58,3 → −60,5 | −26,9 → −37,6 | −23,3 → −23,1 | +3,5 → +14,4 |
| estável 53–57 s | −61,5 → −61,9 | −22,0 → −30,5 | −36,1 → −30,7 | −14,1 → −0,3 |
| cauda do estável 57–61 s | −65,9 → −67,9 | −23,2 → −38,3 | −39,5 → −33,7 | −16,4 → +4,6 |

Loudness de curto prazo máxima por momento (S, blocos de 3 s do próprio momento):

| | despertar | mãos | poeira | semente | magma | crosta | atmosfera | luas→fios | **estável** | cauda |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| antes | −19,5 | −19,1 | −19,0 | −18,9 | −19,1 | −20,4 | −19,6 | −17,1 | −15,8 | −16,2 |
| depois | −19,3 | −19,2 | −18,8 | −18,8 | −19,5 | −20,5 | −19,6 | −17,1 | **−14,8** | −16,0 |

O clímax (53 s) é o momento mais alto e mais pleno da mix: 2,3 LU acima de qualquer outro
(antes 1,3), MID (200 Hz–2 kHz) −15,3 dBFS (antes −17,0), HIGH −37,3 (antes −40,8).

## Inspeção

- Espectrograma: os blocos amarelos abaixo de 120 Hz das mãos (8–13 s) e do magma (22–27 s)
  sumiram; o peso dessas entradas aparece agora como faixa em 130–220 Hz. A semente (18 s) mostra
  o sino Lá2 e o corpo em 110–220 Hz. No clímax (53 s) a faixa 110–220 Hz e a região dos coros
  (300 Hz–2 kHz) acendem juntas, com a cascata de sinos até ~5 kHz e o halo de ar.
- Continuam legíveis: o arpejo de sinos do despertar (3 s), o enxame da poeira subindo até ~6 kHz
  (13–17 s), os grãos da crosta (27–30 s), os formantes da atmosfera (32 s), a celesta das luas
  (37/40 s), a diagonal do anel (43–47 s), o cinturão (46–50 s) e a harpa (50–51 s).
- Fica um leito grave contínuo e moderado (o drone Lá1/Mi2 e o pé do vento da ambiência, ~−45 a
  −50 dBFS por faixa do espectrograma). A coluna mais clara em ~45–49 s é a respiração de 24 s
  da própria ambiência (o stem floor sozinho mede o mesmo ali), LOW −30,5 dBFS — 11 dB abaixo do
  antigo bloco das mãos e fora de qualquer evento grave.
- Forma de onda: sem transientes isolados; o maior envelope é o do clímax (53–58 s); true peak
  −3,0 dBTP, o limitador do Master (−1 dB) não atua.
