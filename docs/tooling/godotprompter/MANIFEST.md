# GodotPrompter — importação parcial (sandbox)

Fonte: https://github.com/jame581/GodotPrompter @ 3e8d0f005f9604e1dbdad3de693e39555384c5af (v1.14.0, 2026-09-20), MIT.
Não importados: hooks/ (SessionStart), roteador using-godot-prompter, scripts/, plugin.json/package.json, commands/, demais skills e agentes.
O agente godot-animator foi copiado apenas como documento de referência (não registrado como agente).

| arquivo | sha256 |
|---|---|
| `.claude/skills/3d-essentials/SKILL.md` | `1208b31c061edddf…` |
| `.claude/skills/3d-essentials/references/common-pitfalls.md` | `d02b05d9732c29df…` |
| `.claude/skills/3d-essentials/references/decals.md` | `0ecfdb7f480564fe…` |
| `.claude/skills/3d-essentials/references/environment-and-post.md` | `bfc80aeb2207c3f4…` |
| `.claude/skills/3d-essentials/references/fog-recipes.md` | `9cfac460f5bf790f…` |
| `.claude/skills/3d-essentials/references/global-illumination.md` | `7a6bbb4ce5d59dbf…` |
| `.claude/skills/3d-essentials/references/godot-4.7-additions.md` | `139c091917de0bb1…` |
| `.claude/skills/3d-essentials/references/lod-and-culling.md` | `6fe802e4966d12fa…` |
| `.claude/skills/3d-essentials/references/materials-and-lighting-recipes.md` | `3426c885efc58eeb…` |
| `.claude/skills/3d-essentials/references/renderer-comparison.md` | `e3b67b68e678799a…` |
| `.claude/skills/animation-system/SKILL.md` | `a77e5974560e4337…` |
| `.claude/skills/animation-system/references/bone-constraints.md` | `720864a282ea7bb7…` |
| `.claude/skills/animation-system/references/common-pitfalls.md` | `afc349b7d04e088f…` |
| `.claude/skills/animation-system/references/common-recipes.md` | `09e7cb4d6d338054…` |
| `.claude/skills/animation-system/references/ik-recipes.md` | `9093bb6424f8a525…` |
| `.claude/skills/animation-system/references/ik-solver-comparison.md` | `0b4de6959288f168…` |
| `.claude/skills/animation-system/references/retargeting.md` | `f317f406a4f3e05e…` |
| `.claude/skills/animation-system/references/skeleton-modifiers.md` | `281527db39762ff6…` |
| `.claude/skills/animation-system/references/sprite-animation.md` | `5e28741e05638dec…` |
| `.claude/skills/animation-system/references/state-machine-examples.md` | `a1f5889ca4451b94…` |
| `.claude/skills/state-machine/SKILL.md` | `2aa1e3eacd63fdaa…` |
| `.claude/skills/state-machine/references/hierarchical-and-parallel.md` | `4a21b680490e763e…` |
| `docs/tooling/godotprompter/LICENSE.txt` | `075667c180b39c81…` |
| `docs/tooling/godotprompter/godot-animator.reference.md` | `03eaa6f89ea70e0f…` |

Verificação: `.claude/hooks/`, `.claude/settings.json`, `.claude/agents/` e `CLAUDE.md` idênticos ao checkpoint (`git diff b9b8672 -- .claude/hooks .claude/settings.json .claude/agents CLAUDE.md` vazio).


Localização: as 3 skills e o agente de referência permanecem **somente** no sandbox local `/home/user/sandbox-loop5` (decisão do Owner: skills isoladas no sandbox). Este manifesto foi migrado para o repositório como registro.
