// data/aesthetic_guides.dart — for each aesthetic: what the score represents, how
// it's captured, the clinical reference it's scored against, and how far along the
// measurement is. Surfaced in the metric detail sheet so a score is never a mystery.
enum MeasureStatus { ready, manual, planned }

class AestheticGuide {
  final String what; // what the score (or unit) represents
  final String how; // how it's captured
  final String anchor; // the clinical reference it's scored against
  final MeasureStatus status;
  const AestheticGuide(
      {required this.what, required this.how, required this.anchor, required this.status});
}

const Map<String, AestheticGuide> aestheticGuides = {
  'voice': AestheticGuide(
    what: 'Vocal clarity + pitch stability (AVQI).',
    how: 'Tap “Measure with mic” and sustain an “aaah” for ~3s — Praat computes the Acoustic Voice Quality Index (CPPS, HNR, shimmer, spectral tilt).',
    anchor: 'Ranked vs AVQI norm (healthy 2.3 ± 0.8, lower better). Vowel-only approximation — provisional; counts toward Aesthetics.',
    status: MeasureStatus.ready,
  ),
  'eye': AestheticGuide(
    what: 'Visual acuity — the sharpness of your sight.',
    how: 'Tap “Measure acuity”: calibrate with a card, set your distance, then read tumbling-E lines → logMAR. Test with your usual glasses/contacts.',
    anchor: 'Ranked vs general young men: 20/20 ≈ Gold, 20/16 ≈ Platinum, 20/10 ≈ Titan. Provisional; counts toward Aesthetics.',
    status: MeasureStatus.ready,
  ),
  'hair': AestheticGuide(
    what: 'Scalp hair density (hairs/cm²).',
    how: 'Tap “Measure from photo”, set your macro lens’ field-of-view (mm), and shoot a scalp close-up; CV counts strands ÷ area.',
    anchor: 'Ranked vs trichoscopy norm ~230 ± 45 hairs/cm² (young men). Provisional (counts merge where hair overlaps); counts toward Aesthetics.',
    status: MeasureStatus.ready,
  ),
  'skin': AestheticGuide(
    what: 'Skin clarity, evenness and blemishes.',
    how: 'Tap “Measure from photo” and face the camera; CV reads redness patchiness, tone evenness and blemish density on skin pixels.',
    anchor: '⚠ Ranked on an ASSUMED distribution (no validated population data). Provisional; counts toward Aesthetics; lighting matters.',
    status: MeasureStatus.ready,
  ),
  'oral': AestheticGuide(
    what: 'Teeth whiteness + gum health.',
    how: 'Tap “Measure from photo” and smile; CV reads tooth brightness/yellowness and gum redness.',
    anchor: '⚠ Ranked on an ASSUMED distribution (shade norms exist but aren’t calibrated here). Provisional; counts toward Aesthetics.',
    status: MeasureStatus.ready,
  ),
  'grooming': AestheticGuide(
    what: 'Overall upkeep.',
    how: 'Tap “Grooming check” and rate each domain — haircut, facial/body hair, nails, brows — for a weighted score.',
    anchor: '⚠ Ranked on an ASSUMED distribution (no clinical norm; informed by ~5/10 crowd ratings). Provisional; counts toward Aesthetics.',
    status: MeasureStatus.manual,
  ),
  'ear': AestheticGuide(
    what: 'Hearing acuity — the quietest tones you can detect.',
    how: 'Tap “Measure hearing” with headphones in a quiet room; a tone fades in at 1/4/8 kHz and you tap the instant you hear it. Detecting quieter = higher score.',
    anchor: '⚠ Uncalibrated screening (app level, not clinical dB HL) on an ASSUMED distribution. Provisional; counts toward Aesthetics; headphones + quiet room matter.',
    status: MeasureStatus.ready,
  ),
};
