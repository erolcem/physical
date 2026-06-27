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
    what: 'Vocal clarity + pitch stability.',
    how: 'Tap “Measure with mic” and sustain an “aaah” for ~3s — Praat extracts jitter, shimmer and harmonics-to-noise.',
    anchor: 'Clinical norms: jitter <1%, shimmer <3.8%, HNR >20 dB.',
    status: MeasureStatus.ready,
  ),
  'eye': AestheticGuide(
    what: 'Visual acuity — the sharpness of your sight.',
    how: 'Tap “Measure acuity”: calibrate with a card, set your distance, then read tumbling-E lines → logMAR.',
    anchor: '20/20 ≈ median young adult; 20/16+ is elite. Ranked (excluded from overall).',
    status: MeasureStatus.ready,
  ),
  'hair': AestheticGuide(
    what: 'Scalp hair density.',
    how: 'A macro-lens scalp photo counted into hairs per cm² (trichoscopy).',
    anchor: 'Healthy scalp ≈ 200–300 hairs/cm²; under ~150 = thinning.',
    status: MeasureStatus.planned,
  ),
  'skin': AestheticGuide(
    what: 'Acne, redness, pores, texture and evenness.',
    how: 'A well-lit selfie scored by a skin-analysis model.',
    anchor: 'Composite of the model’s calibrated sub-scores.',
    status: MeasureStatus.planned,
  ),
  'oral': AestheticGuide(
    what: 'Teeth whiteness + gum health.',
    how: 'A smile photo → tooth shade plus gum redness (inflammation).',
    anchor: 'VITA shade scale; redder gums mean more inflammation.',
    status: MeasureStatus.planned,
  ),
  'grooming': AestheticGuide(
    what: 'Overall upkeep.',
    how: 'A structured self-checklist: haircut freshness, facial/body hair, nails, brows.',
    anchor: 'No clinical norm exists — a weighted self-rating.',
    status: MeasureStatus.manual,
  ),
};
