# Review 1: skillspack-demo-wide.mp4 (24.0 s, 60 fps)

Verdict: not ready. Sound sync and assets are solid. Realism breaks on whole-screen dissolves, the open has no hook, and the poster frame has no product in it.

## Checklist
| Item | Result | Proof |
| --- | --- | --- |
| Text readable at 360 px | FAIL | t006.60: row titles are about 22 px at 1920, so about 4 px at 360. t021.00: subline 34 px becomes about 6 px. Only "SkillsPack" survives. |
| Nothing crosses safe area | FAIL | t003.10, t009.25, t017.00: the panel top (y≈45) is above the dashed line (y≈65) for the whole push. The panel bottom touches it at y≈1015. |
| Real product assets only | PASS | All app states are real SwiftUI renders. Counts stay consistent: 239/5 off (t001.60), 239/6 off (t006.60), 240/6 off (t017.00). |
| Type and color consistent | PASS | SF Pro, light UI, agent colors #D9785A/#4079F5/#9461E0 are the same in t004.85, t009.25, t015.60. |
| No awkward mid-transition frames | FAIL | t003.10: list and bro detail fully superimposed ("Search" on top of "B", "Claude" on "pfw-composable"). Also t007.85 and t009.25 (ghost rows offset about 60 px). |
| Cuts and sounds on grid (±1 frame) | PASS | `silencedetect` onsets match every grid value within 1 ms (1.500, 1.575 … 19.275). The cursor sits on target at 14.25 before the 14.30 Find click (extra/clicks.png). |
| First 2 s hold a hook | FAIL | t000.80, extra/t1.45: an empty desktop and a small cursor for 1.5 s. At 1.55 the panel is still a translucent ghost. |
| Last frame works as a poster | FAIL | t023.90: wordmark and subline on a bare wallpaper. No panel, no icon, no product. |
| No banned defaults | FAIL (borderline) | t021.00–t023.90: text on a gradient (bottom-left, not centred). Panel, screens and end card all fade in. |

## Scores
Hook 1 · Readability 2 · Continuity 3 · Motion 3 · Sound sync 5 · Brand fidelity 3

## Three largest defects

1. Whole-screen dissolves look fake (3.04–3.20, 7.75–7.90, 9.15–9.30).
Evidence: in t003.10 and extra/cut3.png, two full screens are superimposed for about 6 frames, and every text line collides. In t009.25 the Health list shows two copies of itself, 60 px apart, with ghost "Broken link" text under "No problems found." A real recording shows one screen at a time. In-place edits animate only the rows that change.
Fix: in the app-screen transition, replace the 0.12 s linear cross-fade with a hard cut. If a blend is kept, make it 2 frames (0.033 s) at most. For the 9.1 Fix state, do not cross-fade the whole screen. Fade only the problem row out, then move the lower sections up 60 px over 0.25 s with outCubic.

2. There is no hook in the first 1.5 s (0.0–1.55).
Evidence: t000.80 and extra/t1.45 show only the wallpaper and a cursor at about 15 px. Nothing tells the viewer what the app is until about 2.4 s.
Fix: start the cursor 40–60 px from the SkillsPack menu bar icon, not mid-screen. Then the 1.5 s click is the first thing the eye follows. Also start the camera push at 1.5 s with the click, not after the fade. The panel must be readable by 2.0 s, and the push sheet shows it is still small at 2.10.

3. The end card and poster lose the product (19.3–24.0).
Evidence: extra/t20.0 and t20.5 show 1.5 s of empty desktop after the panel closes. In t020.00 the camera pull-out also crops "Help" at the left. t023.90 is text on wallpaper only, with a 6 px subline at phone size.
Fix: keep the panel open (Skills list, t017.00 state, without the toast) behind the end card. Do not return to an empty desktop. Put the wordmark in the empty left area of the frame, at x≈115–900. Raise the subline from 34 px to 48 px. Cut the empty hold from 19.3 to 20.8 s, or shorten the film to about 22 s.

Also fix: the panel crosses the top safe line during the push. Move the camera target down 25 px, or reduce the push from 1.35× to 1.3×.

## Repair notes
1. Cross-fades: fixed. Screen changes blend over 2 frames (1/30 s). See reviews/round2/cut-sheet.png (2.18–2.27 s).
2. Hook: fixed. The cursor starts 64 pt from the icon, the panel opens at 0.7 s, and the camera push starts on the click. See reviews/round2/beats/t000.80.png and t001.30.png.
3. End card: fixed. The panel stays open on the final list (toast gone at 19.06 s), the camera holds 1.35×, the wordmark is 104 px, the subline 44 px on two lines, left of the panel. The empty desktop is cut, and the film is 21.5 s. See reviews/round2/beats/t021.40.png.
Not fixed: the panel top above the safe line. The panel hangs from the menu bar at the top of the screen; keeping it inside the safe area would move the camera past the screen's top edge, which no real recording shows.
