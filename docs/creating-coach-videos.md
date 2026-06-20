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

(Files named `*-waiting-*.mp4` are legacy and not used — you can ignore that label.)

## Variations

The app picks a variation at **random from `1` to `4`** each time a label plays.
So provide **four** clips per label: `…-1.mp4` through `…-4.mp4`. Fewer will work
but increases the odds a missing number is requested (the app then falls back to
the idle clip), so four is the supported set.

That's `11 labels × 4 variations = 44` clips for a complete coach set.

## Clip specs

- **Format:** `.mp4` (H.264).
- **Audio:** none. Clips are played muted, so export **silent** to save space.
- **Loop:** clips are restarted seamlessly end-to-end, so design them to loop
  cleanly (the first and last frames should match).
- **Length:** short — roughly **3–6 seconds** (the existing clips are ~5s).
- **Size:** match the existing clips' frame size, **664 × 540** (≈ 5:4 landscape).
  Other sizes work — the video is scaled to fill a rounded frame — but keeping
  the aspect ratio avoids cropping.

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

