# Character Workshop

## Browser workshop and contextual reactions

Run `npm run dev` in `tools/coach-workshop`, then open
<http://127.0.0.1:4173>. The browser workshop uses the supplied FBX characters
and 35 imported motions. New files in `imports/` are discovered automatically.
The camera stays fixed in bust view while animations play.

**Coach responses** rehearses structured coaching responses. The director selects
motions from the response's intent, expression, gesture, and intensity:

| Response | Preferred motion |
| --- | --- |
| Quiet listening | Breathing Idle |
| Acknowledgment / agreement | acknowledging / head nod yes |
| Strong agreement | Hard Head Nod |
| Considering / correcting | Thinking / thoughtful head shake |
| Explaining / refocusing | Talking / Pointing |
| Relief / uncertainty | relieved sigh / Shrugging |
| Encouragement | happy hand gesture or a restrained nod |
| Verified goal completion | Salute; Cheering for a high-intensity cue |
| Sign-off | Waving |

One-shot reactions blend back to breathing. Pacing limits repeated gestures;
urgent redirects and verified achievements can interrupt lighter reactions.
Manual previews and paused inspection are protected. Angry, annoyed, sarcastic,
cocky, dismissive, and glance-away clips remain available for explicit rehearsal;
caption keywords never activate them. The native coaching model is instructed
to give grounded, professional responses and cannot select those harsh attitudes.

With **Live coach** enabled, a Debug Mac or iOS simulator build forwards accepted
coach responses to the workshop on the same Mac. Reopen the app after rebuilding.
The bridge sends the coaching caption and performance cues over loopback;
it does not send transcripts. Closing the workshop leaves coaching operational.
This is a development preview; physical devices and release builds do not use
the development bridge. The installed app renders its own bundled mannequin locally.

For programmatic rehearsal, use `window.coach.rehearse(cue)`. For paced live
responses, use `window.coach.react(cue)` or `POST /api/react`:

```json
{
  "intent": "steady",
  "expression": "attentive",
  "gesture": "acknowledge",
  "intensity": 0.4,
  "caption": "Give them a moment to respond."
}
```

The response panel displays the caption, selected clip, and selection or
suppression reason. Legacy explicit `{ "animation": "Salute", "once": true }`
cues still work for asset inspection.

## Installed app preview

Launch the Mac app with `--character-workshop`. This page previews the installed
mannequin with ten response buttons, including quiet listening. Rehearsal bypasses
live pacing so you can compare responses immediately. It does not start a meeting,
use the microphone, alter goals, or change the live coach. Each reaction returns
to breathing. The previous portrait proportion controls are no longer the active
Character page; edit character geometry and motion in the browser workshop.
The iOS app has no Character settings section; its coach uses the installed
mannequin and responds automatically during meetings.

## Updating the installed assets

After adding FBXs or changing the shared policy/player source, run:

```sh
cd tools/coach-workshop
npm ci
npm run build-native
```

This compiles `Breathing Idle.fbx` plus all animation FBXs into a compact binary
glTF payload and bundles the renderer and response policy with esbuild. Character
variants remain in the browser workshop; the installed coach uses the original
mannequin. `Resources/CoachMannequin/manifest.json` records source hashes and clip
names/durations. The classic-script payload loads from the app bundle without
file-origin module requests, network access, or a development server.

Rebuild the app after generating resources. The existing `poster.png` is a still
of breathing idle used during startup/recovery. Regenerate and verify it with
`node tools/coach-workshop/test/native-player.cjs` from the repository root (the
browser harness expects the local Playwright installation configured in that file).

Launch a Debug app with `--selftest-mannequin` to verify the real WKWebView surface
without microphone capture or an AI request. It writes `mannequin-selftest.json`
inside the app's Documents directory. `--character-workshop` opens the installed
preview page directly.
