# Minit Games: Defold template

A Defold project that already works inside Minit Games: a 10-second tap round you replace with your own game. See [minit-sample-defold](https://github.com/Minit-Games/minit-sample-defold) for a finished example.

1. **Get the project.** In Defold, choose New Project from the Minit template (once Defold lists it), or Download ZIP / clone this repo, then File > Open From Disk and pick `game.project`.
2. **Project > Fetch Libraries.** The Minit SDK downloads as a `minit` folder under **Dependencies** in Defold's Assets pane, not into your project folder. Quick check: press Ctrl+P and type `minit.lua`.
3. **Build** or **Build HTML5** to play. Audio unlocks on the first tap; the skeleton ships no sounds.
4. **Name your game** in Project Settings > Title. Players see it; with Defold's New Project it is already set.
5. **Make your game** in `main/game.script`. The parts marked `PLACEHOLDER` are yours to replace.
6. **Describe your game** in `meta.json` (recommended). `controls` and `logic` appear under How to play (the (i) button under the game), `description` behind Show more. minit.studio reads them on the first upload only; edit them there later. The title is not in `meta.json`. See the [meta.json reference](https://minit.studio/docs/meta-json-reference), [Writing your description](https://minit.studio/docs/writing-your-description) and [Limits & Constraints](https://minit.studio/docs/limits-and-constraints).
7. **Project > Minit: Package for Upload.** It checks everything, lists what is missing, and writes `dist/<your title>.zip`. Add a THIRD-PARTY-NOTICES.txt for your own assets (fonts, music, art); the packager adds the Defold, third-party and SDK notices itself. From an older template, remove the Defold and Minit SDK sections from your THIRD-PARTY-NOTICES.txt.
8. **Upload** that ZIP at [minit.studio](https://minit.studio).
9. **Test on your phone:** on the game's page in minit.studio, click the QR button in the Live preview panel, then Generate preview link, and scan the code. With the Minit app installed, the game opens in the app; without it, it plays on a web page with links to download the app. The link works for 15 minutes. See [Testing Your Game on Device](https://minit.studio/docs/sharing-a-preview-link).

Textures are compressed by the SDK's texture profile, set in `game.project`; atlases under any `uncompressed/` folder stay uncompressed, e.g. pixel art that must stay pixel-exact. The `.atlas` file's folder counts, not its images' folder.

## Device-adaptive effects

The example in `main/game.script` adjusts its tap pop for motion quality and device tier, skips the pop when reduced motion is preferred, and runs its end shake only at full motion quality when reduced motion is not preferred. On a facade without these getters, the example falls back to the browser's reduced-motion setting. The `?motionQuality=reduced`, `?deviceTier=low`, and `?reducedMotion=1` URL overrides take effect once the pinned minit-defold facade provides the getters. See [Device-Adaptive Effects](https://minit.studio/docs/device-adaptive-effects).

## Screen and camera

- The camera in `main/main.collection` fits the 960×1480 display size into the app's game slot and shows more world on the longer side instead of black bars.
- Switch it to Auto Cover, or move it, as your game needs.
- Anchor GUI nodes to the screen edges they belong to.
- Place physics bodies once against 960×1480; never move them on resize.
- Convert taps to world coordinates with `layout.to_world(action.x, action.y, "/camera#camera")`.
- For things that should fill the slot, query `layout.visible_rect("/camera#camera")` in `update`, not `init`, and re-query it after a resize.

## Don't edit `minit_platform/audio.lua`

It makes audio play and stay audible in the Minit app. `minit_platform/layout.lua` (the tap helper), the camera and the `game.project` render script setting (Defold's built-in one) are defaults you may change.

## AI agents

With the editor open, the packaging also runs headless over its HTTP `/eval` route; evaluate `require("minit.editor.minit_package").run().ok` there, as the header of `minit/editor/minit_package.lua` in the Minit SDK describes.
