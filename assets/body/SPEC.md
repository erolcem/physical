# Body-graph layer assets — spec

Goal: replace the code-drawn polygon figure with **your handmade art**, while keeping
the two things that make it useful — each muscle is **tinted by its rank** and is
**tappable**. We do that with **one layer per muscle** (so the app can recolour each
independently) over a **base** layer.

## Canvas (must be identical for every layer of a view)
- **Portrait PNG, transparent background, 444 × 1260 px** (a 148:420 ratio, same as the
  current figure). Every layer for a view is this exact size, with the body drawn in
  the same position across all of them (so the muscles line up over the base).
- Three views: **front**, **back**, **inner** (inner = organs/skeleton; optional —
  front is the priority, it's what shows by default).

## Files (flat in `assets/body/`, lowercase)
For each view: a base + one file per muscle below.

- `front_base.png` … the body **minus** the tintable muscles: outline, skin, head,
  hands, shadows, any background. Drawn in its **final colours** (not tinted).
- `front_<muscle>.png` … just that one muscle, **in greyscale shading** (white = bright
  highlight, mid-grey = body, dark-grey = crease), transparent everywhere else.

### Why greyscale per muscle?
The app multiplies each muscle layer by its **rank colour** (e.g. gold, teal, red).
Greyscale × colour = a shaded, glossy, correctly-coloured muscle — so your shading is
preserved and the colour comes from the rank automatically. (A muscle with no logged
data is tinted neutral grey.)

## Muscle layers per view (filenames)
**front_**: `shoulders`, `shoulders_m` (side delts), `chest`, `biceps`, `forearms`,
`abs`, `quads`, `calves`

**back_**: `shoulders`, `shoulders_m`, `lats`, `lower_back`, `triceps`, `forearms`,
`glutes`, `hamstrings`, `calves`

**inner_** (optional): `brain`, `heart`, `lung_l`, `lung_r`, `core`, `full_body`,
`hand_l`, `hand_r`, `thigh_l`, `thigh_r`, `tibia_l`, `tibia_r`, `foot_l`, `foot_r`,
`platform`

## Which rank tints which muscle
| muscle | metric (rank source) |
|---|---|
| chest | bench | shoulders | ohp | shoulders_m | lateral_raise |
| biceps | curl | forearms | forearm_curl | abs | crunch |
| quads | squat | calves | calf_raise | lats | pullup |
| triceps | skull_crusher | glutes | hip_thrust | hamstrings | rdl |
| lower_back | (inert) | brain | sleep_score | heart | resting_hr |
| lung_l/r | vo2max | core | plank | full_body | body_fat_pct |
| hand_l/r | hrv | thigh_l/r | hamstring_mobility | tibia_l/r | run5k_kmh |
| foot_l/r | vert | platform | deadhang |

## What I do once the files are here
Render `*_base`, then each muscle layer tinted by its rank colour (gloss preserved),
composited in order; tap → the muscle whose layer is opaque under your finger →
its metric detail. Falls back to the current figure for any view whose `*_base` is
missing, so partial delivery is fine (e.g. just `front_*` first).
