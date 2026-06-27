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
    anchor: 'Ranked vs AVQI norm (healthy 2.3 ± 0.8, lower better). Vowel-only approximation — provisional; excluded from overall.',
    status: MeasureStatus.ready,
  ),
  'eye': AestheticGuide(
    what: 'Visual acuity — the sharpness of your sight.',
    how: 'Tap “Measure acuity”: calibrate with a card, set your distance, then read tumbling-E lines → logMAR. Test with your usual glasses/contacts.',
    anchor: 'Ranked vs general young men: 20/20 ≈ Gold, 20/16 ≈ Platinum, 20/10 ≈ Titan. Provisional; excluded from overall.',
    status: MeasureStatus.ready,
  ),
  'hair': AestheticGuide(
    what: 'Scalp hair coverage (a density proxy).',
    how: 'Tap “Measure from photo” and take a close-up of the scalp; CV measures dark-strand coverage of the patch.',
    anchor: 'Coverage % of the photographed area. (True hairs/cm² needs a macro lens + scale.)',
    status: MeasureStatus.ready,
  ),
  'skin': AestheticGuide(
    what: 'Skin clarity, evenness and blemishes.',
    how: 'Tap “Measure from photo” and face the camera; CV reads redness patchiness, tone evenness and blemish density on skin pixels.',
    anchor: 'Screening composite (no clinical absolute) — track the trend, lighting matters.',
    status: MeasureStatus.ready,
  ),
  'oral': AestheticGuide(
    what: 'Teeth whiteness + gum health.',
    how: 'Tap “Measure from photo” and smile; CV reads tooth brightness/yellowness and gum redness.',
    anchor: 'Screening composite — bright, even lighting gives the most consistent read.',
    status: MeasureStatus.ready,
  ),
  'grooming': AestheticGuide(
    what: 'Overall upkeep.',
    how: 'Tap “Grooming check” and rate each domain — haircut, facial/body hair, nails, brows — for a weighted score.',
    anchor: 'No clinical norm exists — an honest structured self-rating.',
    status: MeasureStatus.manual,
  ),
};
