# Review 2: skillspack-demo-wide.mp4

## Checklist
- FAIL. Text readable at 360 px. The panel is 648 of 1920 px wide after the push (t002.25). Row titles are about 16 px, so about 3 px on a phone. Only the end card is readable (t021.40).
- FAIL (minor). Safe area. The menu-bar clock "Thu 8 Oct 9:41" crosses the right safe line in every pushed frame (t002.25, t008.35). The panel bottom sits on the bottom line with 0 px margin (extra/t2.233). The end-card text starts exactly on the left line (extra/end-crop.png).
- PASS. Real assets. The UI is the real app (list, bro detail, Health, Add Skills), with a real menu bar and an arrow cursor. Counts stay consistent: 239/5 off, then 6 off (t006.95), then 240 (t016.05).
- PASS. Type and color. SF Pro throughout. Agent colors match the guide (Claude toggle orange, Codex blue, pi violet in t003.95). The end card is a 600/400 pair.
- FAIL. Mid-transition frames. extra/t2.267 is a double exposure: the list rows show through the bro detail ("pfw-composable-architecture" over the Claude row). extra/t12.600 shows the placeholder and the pasted URL blended: "bttps://githubb.com/teprikegomareli".
- PASS. Sync. Every click changes the UI 4 frames after the press tick, so it lands on the release tick ±1 frame (frame-diff check: 2.2 -> f136, 3.9 -> f238, 16.0 -> f964). That is mouse-up behavior, as in real macOS. Paste shows at f756, 2 frames after the ⌘V release.
- FAIL. Hook. 0.0-0.7 s is an empty wallpaper with the cursor moving (extra/t0.00, t0.60). The first 2 s show only a list opening. There is no problem and no action yet.
- PASS (weak). Poster. extra/t21.483 has the title, the subline, and the real list. But the cursor sits alone in the empty wallpaper at about (1690, 970), and the panel crowds the right edge.
- PASS. Banned defaults. No music, whooshes, particles, or logo pop. The end card is left-aligned, not centred.

## Scores (1-5)
Hook 2 · Readability 2 · Continuity 4 · Motion 3 · Sound sync 4 · Brand fidelity 4

## Three largest defects
1. 2.2-16.0 s, UI text unreadable on a phone.
   Evidence: t003.95. The toggle labels and paths are about 3 px tall at 360 px wide. In t008.35 the "Fix" button is a dot.
   Fix: in the camera, raise the push from 1.35× to about 2.2×. Re-centre the push on the active element for each beat: the Agents rows at 3.9, the Fix button at 8.3, the URL field at 12.1. Each re-centre is one 1.2 s inOutCubic move.
2. 2.267 s and 12.600 s, double-exposure frames break the screen-recording look.
   Evidence: extra/t2.267 shows two full screens at 50 % each. extra/t12.600 shows the placeholder text ghosted under the pasted URL. A real text field never blends its contents.
   Fix 1: in the URL field, swap placeholder to URL on one frame (f756), with no opacity blend.
   Fix 2: for screen changes, cut on the release frame, or render the app's real push transition. A plain 0.12 s opacity mix of two PNGs is not what NavigationStack draws.
   Fix 3: at 12.1 s, draw the focus ring and caret. The field click changes nothing visible now (frames 726-750 have zero diff).
3. 17.8-21.5 s, the ending turns the recording into an overlay ad.
   Evidence: in t018.40 / extra/t18.000, the title fades in at 17.82 s while the "Installed product-thinking…" toast still covers the last rows (the toast leaves at 19.07 s). The panel never closes and the camera never eases out, against style-guide Direction.
   Fix: close the panel with a click on the menu-bar icon at about 17.3 s (0.16 s fade out). Ease the camera out over 1.2 s. Start the end-card settle after the camera stops. Move the text 40 px inside the left safe line. Park the cursor on the menu-bar icon, not in the empty wallpaper.

## Minor
- The Codex switch flips in 3 frames (f238-240). A real macOS switch animates for about 0.2 s.
- The bro row shows no pressed highlight on its click (extra/t2.233-t2.250).

## Repair notes
1. Readability: fixed as far as a 16:9 desktop allows. Auto-zoom follows the action: 1.6× on the list, 2.0× on the switches and on Health, 1.9× on Add Skills (two framings: header and field, then results and Install). Row titles grow from about 22 px to about 31 px at 1920.
2. Blended frames: fixed. Screens cut on the click with no blend. Only the Codex switch animates, 0.2 s, in its own area. The URL field cuts from placeholder to the pasted link, and a caret blinks after the field click.
3. Ending: fixed in part. The cursor rests on the menu bar icon, the camera eases out to 1.35× at 16.35 s, the toast goes at 19.06 s, and the end card settles at 19.3 s, 40 px inside the safe line. The panel stays open, as review 1 asked, so the poster shows the product.
Not fixed: the bro row press highlight (the captured states have no pressed row).
