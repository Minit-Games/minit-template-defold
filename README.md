# Defold Minit Template

> **Learn page:** [Defold on Minit](https://minit.studio/docs/defold) — the official guide this template implements.

A complete, working Minit game in Defold, kept deliberately tiny so the parts
around it are easy to read. Tap the ball to bounce it; each tap scores. A
30 second clock ends the run and reports the result.

Start here, replace the game, keep the plumbing.

```bash
tools/build.sh                     # HTML5 bundle -> dist/Defold Minit Template
tools/package.sh                   # regenerate assets, build, verify, zip for upload
tools/play.mjs "dist-debug/..."    # run the bundle in a real browser and screenshot it
```

The SDK is a [Defold library dependency](https://github.com/Minit-Games/minit-defold)
declared in `game.project`. In the editor use **Project → Fetch Libraries**;
`tools/build.sh` runs `bob resolve` for you on a fresh checkout.

## What the game shows you

| Where | What it demonstrates |
|---|---|
| `main/game.script` → `read_config()` | Config values, with defaults and clamping. Booleans follow the backend's coercion: anything but `"true"` is false. |
| `main/game.script` → `init()` | `minit.loading_done()` at the end, once the scene is built and placed. |
| `main/game.script` → `finish()` | `minit.report_result()` **exactly once**, with `flavor_text`, a persisted `user_data`, and a `delay` so the outro is seen. |
| `main/game.script` → `init()` | `minit.get_user_data()` read back as the player's previous best. |
| `modules/audio.lua` | The audio rules that matter inside the app. Read this before touching sound. |
| `modules/layout.lua` | No design resolution: every number derived from the live viewport. |
| `meta.json` | The three config keys the game reads, plus store copy and credits. |

## Read this before you touch audio

Sound is the one thing that behaves differently inside the Minit app than in a
browser, and it fails **silently in both directions**. This template already
handles it; the pieces are load-bearing.

**0. The host's volume message never arrives (the root cause).** The app tells a
game its volume with `window.postMessage(payload, window.location.origin)`. On
iOS the game is served from `minitlocal://`, a custom scheme whose origin is
**opaque** -- so `location.origin` is the string `"null"`, and `postMessage`
does not fail soft with that, it **throws**. Every volume message is discarded,
and the only value the page ever sees is the seed baked into the injection at
mount time -- which is `0` for a drop mounted before it was scrolled into view.
The game is then healthy and permanently inaudible, and only a foreground
transition fixes it, because `__minitResumeAudio` is a direct call rather than a
postMessage. That is exactly the "silent until you background and come back"
symptom.

The shell repairs the channel rather than guessing the volume: a same-window
`postMessage` rejected for its target origin is retried with `'*'`, so the
host's own message arrives and its real intent flows through untouched --
**including a deliberate mute**. Verified both ways: host says 1 and the game is
audible, host says 0 and it is silent. Tracked app-side as DROP-8164; the shell
keeps working either way.

**Defold discards audio while its context is suspended.** The web sound device
throws every buffer away and returns while the page's `AudioContext` is not
`running` — no error, no retry. So a loop started too early does not queue and
play later: its opening is gone, and you hear the track from wherever it had got
to. `audio.music_start()` therefore refuses until the context reports running,
and `game.script` retries four times a second until it takes.

**The host owns the output gain.** The app routes every game through a mute gain
it controls, seeded at zero and faded up. If that fade does not land, the game is
entirely healthy — context running, engine mixing, buffers queued — and
completely inaudible, with nothing observable from Lua. `web/minit.html` carries
the recovery: it resumes a suspended context on any gesture, on visibility and
focus changes, and on a watchdog; and it re-applies *the host's own* target
volume when the host says it wants sound while the gain is still at zero. It
never touches that gain when the host has deliberately muted or ducked the drop.

**Nothing plays before the game starts.** `audio.set_active(true)` is called on
the first tap, which is also the gesture that resumes the context.

If you take one thing from this template, take `web/minit.html` and
`modules/audio.lua`. `tools/package.sh` fails the build if the shim goes missing.

## Two more things that are not obvious

**There is no design resolution**, and this is a deliberate departure from the
SDK guide's GUI advice. The render script projects `0..window_width` by
`0..window_height`, so a world unit is a backbuffer pixel, and `layout.lua`
rebuilds from `window.get_size()` on every change. The Minit app's game slot is
roughly **2:3** — far wider relative to its height than a phone screen, because
the game sits between the app's header and its toolbar. A game drawn to a fixed
design width paints a fraction of that slot and leaves a band down one side, and
you cannot see it in a desktop browser at a phone viewport. Check both:
`tools/play.mjs <dir> --w 600 --h 900 --dpr 2`.

**Touch coordinates are not backbuffer pixels.** Measured against a release wasm
bundle in Chrome:

- `window.get_size()` returns **backbuffer** pixels (1170×2532, not 390×844).
- `action.x/action.y`, and every `action.touch[i].x/y`, are the normalised
  position times the `game.project` display size — a stretch mapping that
  ignores the real aspect ratio.
- Touch entries carry only `x`/`y`; there is no per-finger `screen_x`.

`layout.to_world()` does the conversion. Multi-touch works, with stable
per-finger ids; `on_input` handles both a touch list and a mouse.

## Cloning: this repo uses Git LFS

Art, audio and fonts are tracked with [Git LFS](https://git-lfs.com). Install it
once (`git lfs install`) before cloning, or the asset files arrive as small text
pointers and the build produces a game with no textures and no sound.

Already cloned without it? `git lfs install && git lfs checkout` fixes the
working tree in place.

Why, when the assets here are only ~540 KB: they are **generated**
(`tools/gen-*.mjs`), and regenerating them is the normal workflow. Git stores a
whole new blob for a compressed format every time, so without LFS the history
would grow by the full asset size on every palette or synthesis tweak. It also
sets the pattern before a fork commits a real sprite sheet. Note the remote you
push to must support LFS.

Only genuinely binary formats are tracked. Defold's `.atlas` / `.collection` /
`.go` / `.font` and Godot's `.tscn` / `.tres` / `.import` are text and stay out
of LFS, so they keep diffing and merging normally.

## Assets

No binary art or audio is authored by hand. `tools/gen-art.mjs` rasterises every
sprite from signed distance fields and emits `assets/atlas/game.atlas` beside
them so the two cannot drift; `tools/gen-audio.mjs` synthesises the effects.
Replace either wholesale when you bring your own — only the names matter.

The background music is the one third-party asset: a CC0 chiptune, converted by
`tools/gen-music.mjs` from 2.0 MB of 44.1 kHz stereo to 0.35 MB of 16 kHz mono.
Defold honours a WAV's declared sample rate rather than assuming 44100 (measured:
a 2.000 s tone at 16 kHz reports 1.989 s to its completion callback), so a
low-rate file plays at the right speed. That script also checks whether the loop
point is genuinely seamless before "fixing" it — this track's is, so it is left
exactly as the author wrote it. See `THIRD-PARTY-NOTICES.txt`.

## Testing

`tools/play.mjs` drives the actual bundle in Chrome over CDP with **no npm
dependencies** (Node 22 ships a global `WebSocket`). It taps, samples frame
timing from inside the page, and captures console output and screenshots.

Build with `VARIANT=debug` when testing: **`--variant release` compiles out
`print` and Lua error logging**, so a script that dies at `init` looks like a
black screen and nothing else. `minit.lua` degrades to `console.log` outside the
host, which is how a local run shows `loadingDone` and the final `reportResult`.

Audio cannot be heard from a headless browser, but it can be measured:
`sound.get_rms("master", …)` from inside the game proves the mixer is producing
signal. Note that reads the engine's internal mixer, *upstream* of the host's
gain — so it is non-zero even when the page is silent. To reproduce the app,
launch Chrome **without** `--autoplay-policy=no-user-gesture-required`
(`tools/cdp.mjs` takes `autoplay: false`) so the context starts suspended.

## Platform notes

- `--architectures wasm-web` pins a single non-pthread wasm. Without it bob also
  emits a `*_pthread.wasm` that the loader prefers wherever `SharedArrayBuffer`
  exists — and that needs a cross-origin-isolated page, which the Minit host does
  not serve. `tools/package.sh` fails the build if one appears.
- `[input] use_accelerometer` is off: the platform forbids device hardware, and
  it defaults to on.
- `[display] update_frequency = 60` caps the frame rate.
- A custom HTML5 shell **must** keep an element with id `app-container`;
  `dmloader.js`'s resize callback sets `.style` on it and throws otherwise.
- The bundle loads its own `archive/` payload over `XMLHttpRequest` from inside
  the ZIP. That is Defold's loader and the shape the Minit SDK ships; the game
  makes no network calls and touches no web storage.

## Shipping

`tools/package.sh` regenerates every asset, builds release, validates
`meta.json`, and writes `dist/defold-minit-template.zip` with `index.html`,
`meta.json` and the notices at the archive root. Pre-flight refuses a bundle
missing the audio shim, carrying a pthread wasm, containing project sources, or
over Minit's 50 MB limit.

Then, from the `minits` tooling repo:

```bash
npm run createProject defold-minit/dist/defold-minit-template.zip --dry-run
```

The project id it records lands in `publishing/meta.txt`.
