# Style guide

## Reference analysis
No external reference. The reference is the real product: macOS menu bar apps such as Control Center and the Wi-Fi menu.
Palette: wallpaper #0e2747 → #22356f → #3a2c63 with teal and violet glows; app UI in light mode with the default macOS blue accent; agent colors Claude #D9785A, Codex #4079F5, pi #9461E0 (from the app).
Typography: SF Pro (system font) everywhere, as macOS draws it. End card: SF Pro 600 at 92 px, subline 400 at 34 px.
Composition: a 1600×900 pt Mac screen scaled into 1920×1080. The panel hangs from the SkillsPack icon in the menu bar, right of center.
Pacing: one UI change every 1.3–1.7 s, like a person who knows the app.
Motion: cuts inside the app (the app swaps screens in 0.12 s), a hand-paced cursor, one slow camera push.
Texture: none. Clean screen pixels.

## Direction
Push: the camera eases in 1.35× on the panel after it opens, and back out after it closes. The view never leaves the screen.
Alternative, Static: no camera move, like an unedited screen recording.

## Motion
Cursor      eased travel, slight arc, arrives 0.12 s before each click   inOutCubic, ≤ 1 s
Click       cursor dips to 88 % for 0.14 s                               sine
App screens cross-fade 0.12 s, the app's own speed                       linear
Panel       fades in 0.12 s on click, out 0.16 s                         outCubic
Camera      smooth, almost invisible                                     inOutCubic, 1.2–1.3 s
End card    text settles 14 px, once                                     outExpo 0.6 s

## Banned defaults
Centred text on a gradient, everything fading in, logo pop, particles, lens flares, captions, whooshes, music, fake UI, invented numbers.
