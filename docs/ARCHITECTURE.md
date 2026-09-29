# Arquitetura

Dono: `game-engineer`. Responsabilidade: camadas, fluxo de dados, estrutura de diretórios.

## Camadas

```
src/events   (RefCounted puro)   SimEvent · OriginChamberScript · EventTimeline · WorldState · Mission · EntityCatalog
     ▲
src/core     (autoloads)          Simulation (relógio + eventos)   Session (modo, seleção, foco, HUD)
                                  Shortcuts (teclado → autoloads) · InputTuning (limiar clique × arrasto)
src/world    (autoload + mundo)   Quality (perfil gráfico) · composição do mundo 3D
     ▲                    ▲
3D: src/world, src/entities, src/animation, src/fx, src/procedural, src/style
UI: src/ui (Control nativo), src/style (tema)
```

- **Um produtor de eventos**: `Simulation` avança `EventTimeline` em `_process`, aplica cada evento
  em `WorldState` e emite `event_emitted`. `seek`/`reset` reconstroem o mundo e emitem `world_rebuilt`.
- **Visual derivado**: entidades calculam seu estado a partir de `Simulation.world` (timestamps
  `*_at`) e `Simulation.time`. Não há estado de animação que possa divergir da simulação.
- **UI ↔ 3D** só por autoloads (`Simulation`, `Session`, `Quality`). A UI não referencia nós 3D e vice-versa.
  - Seleção: `Session.select(id)` → `selection_changed(id)` (Picker 3D, listas da UI).
  - Foco de câmera: `Session.focus(id)` → `focus_requested(id)` (emite sempre). A câmera acha o alvo
    pelo grupo `Session.entity_group(id)` = `entity_<id>` (raiz visual de cada entidade selecionável).
  - HUD: `Session.hud_visible` + `hud_visibility_changed(visible)` (atalho H); só a UI reage.
  - Câmera cinematográfica: `Session.cinematic` + `cinematic_changed` (atalho V, menu da UI).
- **Teclado**: `Shortcuts` (`src/core/shortcuts.gd`, filho de `Main`) é o único leitor dos atalhos
  globais (Espaço, R, 1/2/3, Esc, F11, V, H) e só escreve nos autoloads; ignora teclas enquanto um
  `LineEdit`/`TextEdit`/`Range` da UI tem foco. Teclas de câmera são do `CameraDirector`.
- **Qualidade**: `Quality` aplica configurações de viewport e emite `profile_changed`; ambiente,
  luzes e efeitos aplicam a parte deles.

## Cenas

`scenes/main.tscn` (raiz: `main.gd`) → `World` (`scenes/world.tscn`) + `HUD` (`scenes/hud.tscn`)
+ camada de fade + `Shortcuts` (criado em `main.gd`). `main.gd` também ativa automação por argumentos
(`--smoke-test`, `--allow-missing-ui`, `--capture=`, `--capture-only=`, `--quality=`).

`World` (`src/world/world.gd`) compõe, nesta ordem: `WorldEnvironment` → entidades
(`src/entities`) → efeitos (`src/fx`) → `Universe` → `CameraDirector` (`src/animation`) → `Picker`.
Módulos de outras áreas entram por caminho e são pulados se ausentes (detalhes em `docs/ENGINE.md`).
Seleção 3D: `Picker` faz raycast na camada de colisão 2 e escreve em `Session`; a UI lê `Session`.

## Diretórios

| Diretório | Conteúdo | Escritor |
|---|---|---|
| `src/events` | Lógica pura de eventos, mundo, missão, entidades | game-engineer |
| `src/core` | Autoloads Simulation/Session, main, atalhos, automação | game-engineer |
| `src/world` | Quality, composição do mundo, universo (céu + sementes), seleção (Picker) | game-engineer |
| `src/procedural` | Blueprints e builders de malha | procedural-modeler |
| `src/entities`, `src/animation`, `src/fx` | Entidades, câmeras, efeitos | animator |
| `src/style`, `src/ui` | Paleta, materiais, ambiente, tema, HUD | art-director |
| `tests/unit`, `tests/integration` | GUT | dono de cada área |
| `tools` | Scripts de teste, captura, export, setup | game-engineer |
| `addons/gut` | GUT 9.7.0 vendorizado (MIT) — não editar | — |
