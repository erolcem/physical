// data/pins.dart — AI PINS: short free-text goals/context the user pins for the
// coach to always remember ("cutting to 78 kg by September", "left knee is
// rehabbing — no deep squats"). They live in the Habits tab's pin section, ride
// every coach request as standing context, and are deleted manually when done.
// Distinct from PinnedCorrelation (metric-pair insight cards).
class AiPin {
  final String id;
  final String text;
  final String createdAt; // ISO-8601

  const AiPin({required this.id, required this.text, required this.createdAt});

  Map<String, dynamic> toJson() => {'id': id, 't': text, 'ts': createdAt};

  factory AiPin.fromJson(Map<String, dynamic> j) => AiPin(
        id: j['id'] as String,
        text: (j['t'] ?? '') as String,
        createdAt: j['ts'] as String? ?? '',
      );
}
