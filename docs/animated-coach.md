# Animated coach

The app uses the workshop's original Mixamo mannequin and 35 authored animation
clips. The DEFAULT theme explicitly selects `"coachRenderer": "mannequin"`.
BRICKS, HERO, NOIR, and ZEN select `"coachRenderer": "video"` and play their
own bundled clips. Themes without an explicit renderer use video, except DEFAULT.
Switching themes reloads the coach surface and its playback state.

## Rendering

`MannequinCoachView` embeds a noninteractive, local `WKWebView` in the existing
coach card. Its camera is fixed at the same mid-chest bust framing as the browser
workshop. The camouflage background, pixel silhouette, skinned mesh, bone
proportions, and authored animation curves are preserved. The installed mannequin
has a glossy orange finish with a clear coat and locally baked studio reflections.
Its pigment follows the active theme's primary button color; the default is
`#EC5000`. Continuous color shading replaces the former grayscale quantization.
The existing native caption overlay remains outside the renderer.

`Resources/CoachMannequin` contains a binary glTF payload in a classic JavaScript
asset, bundled Three.js runtime, shared reaction director, background, and loading
poster. Everything loads from the app bundle, including on physical devices and
in release builds. There is no localhost dependency, CDN, network fetch, FBX
parsing, or video playback. The native surface uses ephemeral WebKit storage,
allows navigation only within its own resource directory, and passes cue data
with WebKit's structured JavaScript arguments.

Breathing runs before and during meetings. Reactions crossfade over 0.4 seconds
and return to breathing. Rendering is capped at 30 fps. Backgrounding pauses
updates, returning to the foreground resumes them, and Reduced Motion holds a
still breathing pose. A loading/recovery poster avoids an empty coach section.
Web content process termination reloads the player with the latest native state.
The original SpriteKit portrait code remains for historical rig checks.

## Coaching

`FoundationModelsService` generates a typed `CoachingDirective`: intent,
expression, gesture, intensity, and caption. `ContentView` rejects stale analysis
using cancellation and a per-meeting session identifier. `CoachPerformance`
accepts current meeting events, reserves goal celebrations for verified goal
completion, and limits rapid repeated gestures.

The embedded player uses the exact `reaction-policy.mjs` used by the workshop.
Native changes are coalesced until the renderer is ready. Each response gets a
session, sequence, and event ID, preventing duplicates and late responses from
replacing current state. The director chooses a contextual authored clip, adds
pacing between motions, and lets stronger redirects interrupt lighter reactions.
Caption wording never selects a gesture by keyword. See
[Character Workshop](character-workshop.md) for mappings and rehearsal.

The optional Debug Mac/simulator bridge still mirrors accepted responses to the
browser workshop when its Live coach switch is on. It is independent of the
installed renderer and is excluded on physical devices and release builds.

## Verification and rebuilding

`npm test` in `tools/coach-workshop` checks shared cue validation, response rules,
pacing, priority, stale/duplicate suppression, bind-pose conversion, and asset
assembly. `npm run build-native` regenerates the offline bundle from supplied
FBXs. `test/native-player.cjs` loads the exact bundled files without a server and
checks that all 35 clips remain visible with a fixed camera, that contextual
responses return to breathing, and that no network requests occur.

Launch a Debug app with `--selftest-mannequin` to exercise the actual WKWebView
player in the normal app layout. Its 22 checks cover loading, visible breathing,
contextual motions, framing, verified achievements, return to idle, background
pause/resume, and Reduced Motion. Results are written to
`Documents/mannequin-selftest.json` in the app container. No audio capture or
model call is made. The macOS `--selftest-avatar` also retains 113 policy and
legacy portrait geometry checks.

## Artwork provenance

The built-in imagegen tool generated the historical portrait assets using
`avatar/general.png` as the identity/style reference:

- `app/KochiApp/Resources/Themes/default/avatar/arm-parts.png`: transparent 3×2
  atlas. Upper sleeve, forearm sleeve, open palm; saluting hand, pointing hand,
  relaxed closed hand. The runtime crops each part and finds its wrist anchor.
- `app/KochiApp/Resources/Themes/default/avatar/arm-background.png`: empty wall
  revealed behind the moving arms, tiled at the original portrait's pixel scale.

Final atlas prompt:

> Use case: identity-preserve. Asset type: production pixel-art skeletal-rig sprite atlas for the military general in the reference. Create ONE transparent image with an EXACT 3-column by 2-row grid of equal cells, no grid lines and no labels. ONE isolated part centered in each cell with ample transparent gutter, no part crossing cells. All parts face front and are upright. Top row left: dark uniform UPPER ARM SLEEVE ONLY, a straight vertical padded charcoal sleeve, rounded shoulder cap at top, rounded elbow overlap at bottom, no hand, no shoulder medals. Top row middle: FOREARM SLEEVE ONLY, straight vertical dark sleeve, rounded elbow overlap at top and pale-gray cuff at bottom, no hand, no shoulder. Top row right: OPEN PALM hand only, palm facing viewer, four fingers and thumb naturally visible, fingertips pointing UP, wrist at BOTTOM. Bottom row left: SALUTING HAND only, four straight fingers held together pointing UP, thumb folded neatly across palm, wrist BOTTOM. Bottom row middle: POINTING HAND only, index finger pointing UP, other fingers curled, wrist BOTTOM. Bottom row right: RELAXED CLOSED HAND only, thumb visible, wrist at BOTTOM. Style must match supplied general: very chunky square pixel art, roughly 10 to 14 pixels across each part, thick near-black stepped outline, restrained gray highlights, gray skin, no color, hard edges, no antialiasing, no photorealism, no smooth vector shading, no gradients, no miniature extra icons. The sleeves use the general's charcoal uniform and similar broad gray planes. Each part is a clean solid cutout on actual transparent alpha. No background, no checkerboard, no character, no torso, no face, no text.

Final wall prompt:

> Use case: precise-object-edit. Edit target: supplied grayscale pixel-art military general portrait. Output ONLY the empty grayscale camouflage wall. Completely remove the general, including hat, face, shoulders, uniform, and both arms. Fill his entire silhouette with the same large angular gray camouflage shapes from the visible background. Preserve original portrait framing and aspect ratio, its neutral gray brightness, muted contrast, chunky pixel scale and faint square grid texture. This is the static wall BEHIND the original general in an animation; closely match the source backdrop. No person or body fragments, no silhouette, no clothing, no text, no new props, no gradients, no lighting change, no border.
