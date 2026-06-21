# Creating Coach Videos for a Theme

The coach hero at the top of the app plays short, silent, looping video clips.
Each theme ships its own set under
`app/KochiApp/Resources/Themes/<theme-id>/videos/`. This guide explains how to
author and name them.

## Naming convention

Every clip filename follows this exact pattern:

```
<label>-<variation>.mp4
```

Example: `idle-1.mp4`, `goal-3.mp4`

| Part | What it is | Allowed values |
|------|------------|----------------|
| `<label>` | Which coaching moment the clip is for (see the table below). | one of the 11 labels |
| `<variation>` | A numbered alternate so the coach doesn't look repetitive. | `1`, `2`, `3`, `4` |

- The theme folder itself identifies which coach set the clip belongs to, so the
  filename carries only the emotion and variation — no theme prefix.
- All lowercase. Separate the two parts with a single hyphen. Extension is
  `.mp4`.

## Labels

Provide a clip for each of these 11 labels. `idle` is the most important — it's
the resting loop shown whenever no meeting is active, and it's the fallback if
another clip is missing.

| Label | When it plays |
|---------|---------------|
| `idle` | Resting / breathing loop — no meeting active. **Required.** |
| `goal` | A goal was achieved — celebration. |
| `timing` | Time-management reminder (watch your pace). |
| `pause` | Take a pause / breathe. |
| `listen` | Active-listening prompt (let them talk). |
| `prompt` | Encourage speaking up / asking questions. |
| `mute` | Reduce talking / be concise. |
| `focus` | Focus and concentrate. |
| `check` | Check progress against goals. |
| `steady` | Maintain a good, steady pace. |
| `wrap` | Wrap up the meeting. |

## Variations

The app picks a variation at **random from `1` to `4`** each time a label plays.
So provide **four** clips per label: `…-1.mp4` through `…-4.mp4`. Fewer will work
but increases the odds a missing number is requested (the app then falls back to
the idle clip), so four is the supported set.

That's `11 labels × 4 variations = 44` clips for a complete coach set.

## Clip specs

The clips that ship in the repo are all normalized to the same compact spec
(see [Compressing source clips](#compressing-source-clips) for how to get there):

- **Container:** `.mp4`.
- **Codec:** **HEVC / H.265** (`libx265`), `yuv420p`, tagged `hvc1` so
  AVFoundation/QuickTime plays it. Raw exports are usually H.264 — re-encode them.
- **Frame size:** **664 × 540** (≈ 5:4 landscape). Other sizes play (the video is
  scaled to fill a rounded frame) but matching this avoids surprises.
- **Audio:** none. Clips are played muted, so strip audio entirely.
- **Frame rate:** 24 fps.
- **Loop:** clips are restarted seamlessly end-to-end, so design them to loop
  cleanly (the first and last frames should match).
- **Length:** short — roughly **3–6 seconds** (the existing clips are ~5s).
- **Weight:** ~**150–205 KB** per clip (≈ 225–310 kbps), so a full coach set is
  ~9 MB. A raw H.264 export is ~2.8 MB/clip (≈ 4.5 Mbps) — ~15× heavier.

## Compressing source clips

Freshly generated/exported clips are typically H.264, slightly oversized, and
~4.5 Mbps — about **15× larger** than they need to be (a whole theme's raw set
runs ~38 MB vs. ~9 MB compressed). Every shipped theme except a freshly-added one
has been run through this pass; the `bricks` theme is the example of clips that
have **not** yet been shrunk.

Normalize each clip with `ffmpeg` (install via `brew install ffmpeg`):

```bash
ffmpeg -i in.mp4 -an -vf scale=664:540 -c:v libx265 -crf 34 -pix_fmt yuv420p -tag:v hvc1 out.mp4
```

What each flag does:

- `-an` — drop the audio track (clips play muted).
- `-vf scale=664:540` — resize to the exact target frame size.
- `-c:v libx265 -crf 34` — encode HEVC at constant quality (see CRF note below).
- `-pix_fmt yuv420p` — broad-compatibility chroma.
- `-tag:v hvc1` — tag the HEVC track so AVFoundation/QuickTime will play it
  (without this, the clip can decode to black on Apple platforms).

To shrink a whole theme folder **in place** (e.g. `bricks`):

```bash
cd app/KochiApp/Resources/Themes/bricks/videos
for f in *.mp4; do
  ffmpeg -y -loglevel error -i "$f" \
    -an -vf scale=664:540 -c:v libx265 -crf 34 -pix_fmt yuv420p -tag:v hvc1 \
    "tmp-$f" && mv "tmp-$f" "$f"
done
```

### Picking the CRF

`-crf` is the quality dial — **lower = better quality + bigger file**. The shipped
clips land at ~225–310 kbps (150–205 KB). Measured on a `bricks` clip, these CRFs
bracket that target:

| CRF | Size | Bitrate | Notes |
|-----|------|---------|-------|
| 31  | ~268 KB | ~417 kbps | sharper than the shipped clips |
| 33  | ~199 KB | ~307 kbps | matches the upper end of the shipped set |
| **34** | **~171 KB** | **~263 kbps** | **recommended — middle of the shipped band** |
| 36  | ~126 KB | ~192 kbps | smaller, slightly softer |

Exact bytes depend on how busy the clip is, so confirm the result rather than
trusting the number:

```bash
# Per-clip codec / size / bitrate
ffprobe -v error -select_streams v \
  -show_entries stream=codec_name,width,height,bit_rate \
  -of default=noprint_wrappers=1 idle-1.mp4

# Whole-folder weight — aim for ~9 MB
du -sh app/KochiApp/Resources/Themes/bricks/videos
```

## Where they go

Drop the files in your theme's `videos/` folder:

```
app/KochiApp/Resources/Themes/<theme-id>/
  theme.json
  videos/
    idle-1.mp4
    idle-2.mp4
    …
    wrap-4.mp4
```

Because `Resources/Themes/` is a single Xcode folder reference, adding the folder
+ clips and rebuilding is all that's needed — no project or code changes.

## Generation prompts

Prompts used to generate each label's clips. Every prompt should bake in the
hard requirements: a **seamless loop** (first and last frame match), a **static
background** that doesn't move or change, **slow/subtle** motion, and **no
audio**. Append your character/style description (e.g. "LEGO minifigure", "Army
general") for the specific theme.

| Label | Prompt |
|---------|--------|
| `idle` | Idle animation with breathing. Slow motion. Background doesn't move or change. Seamless loop (first and last frame match), ~5 seconds, silent. |
| `prompt` | Coach tosses a glowing question mark toward you, nodding to cue engagement. Slow motion. Background doesn't move or change. Seamless loop (first and last frame match), ~5 seconds, silent. |
| `mute` | Exaggerated zip-mouth lips gesture with wide eyes to stop over-talking. Slow motion. Background doesn't move or change. Seamless loop (first and last frame match), ~5 seconds, silent. |
| `timing` | Taps wrist with one finger while glancing down to check watch. Slow motion. Background doesn't move or change. Seamless loop (first and last frame match), ~5 seconds, silent. |
| `pause` | Two open palms held out with slight shake to signal a pause or reset. Slow motion. Background doesn't move or change. Seamless loop (first and last frame match), ~5 seconds, silent. |
| `goal` | Animated clipboard appears and checkmark pops up to confirm goal hit. Slow motion. Background doesn't move or change. Seamless loop (first and last frame match), ~5 seconds, silent. |
| `wrap` | Palm rotates forward in a circular motion to signal wrapping up. Slow motion. Background doesn't move or change. Seamless loop (first and last frame match), ~5 seconds, silent. |
| `listen` | Hand cups ear, head tilts slightly to prompt active listening. Slow motion. Background doesn't move or change. Seamless loop (first and last frame match), ~5 seconds, silent. |
| `steady` | Coach raises a clock prop with raised brows to signal time awareness. Slow motion. Background doesn't move or change. Seamless loop (first and last frame match), ~5 seconds, silent. |
| `focus` | Two fingers point to eyes, then forward to refocus your attention. Slow motion. Background doesn't move or change. Seamless loop (first and last frame match), ~5 seconds, silent. |
| `check` | Slowly smile and give a thumbs up to confirm good progress. Slow motion. Background doesn't move or change. Seamless loop (first and last frame match), ~5 seconds, silent. |

> Tip: prepend a style cue to any prompt for a themed coach — e.g. `8-bit pixel art, …` or `LEGO minifigure, …`.

