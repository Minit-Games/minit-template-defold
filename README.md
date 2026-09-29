# Minit Games: Defold template

A Defold project that already works inside Minit Games: a 10-second tap round you replace with your own game. See [minit-sample-defold](https://github.com/Minit-Games/minit-sample-defold) for a finished example.

1. **Get the project.** In Defold, choose New Project from the Minit template (once Defold lists it), or Download ZIP / clone this repo, then File > Open From Disk and pick `game.project`.
2. **Project > Fetch Libraries.** A `minit` folder appears.
3. **Build** or **Build HTML5** to play. Audio unlocks on the first tap; the skeleton ships no sounds.
4. **Name your game** in Project Settings > Title. Players see it; with Defold's New Project it is already set.
5. **Make your game** in `main/game.script`. The parts marked `PLACEHOLDER` are yours to replace.
6. **Describe your game** in `meta.json` (recommended). `controls` and `logic` appear under How to play (the (i) button under the game), `description` behind Show more. minit.studio reads them on the first upload only; edit them there later. The title is not in `meta.json`. See the [meta.json reference](https://minit.studio/docs/meta-json-reference), [Writing your description](https://minit.studio/docs/writing-your-description) and [Limits & Constraints](https://minit.studio/docs/limits-and-constraints).
7. **Project > Minit: Package for Upload.** It checks everything, lists what is missing, and writes `dist/<your title>.zip`.
8. **Upload** that ZIP at [minit.studio](https://minit.studio).

## Don't edit `minit_platform/`

It is what makes the game work in the Minit app: audio that plays and is audible there, layout for the app's game slot, and touch mapping. Change your game in `main/` instead.

## AI agents

With the editor open, the packaging also runs headless over its HTTP `/eval` route; see the header of `editor/minit_package.lua`.
