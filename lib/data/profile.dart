// data/profile.dart — the user's profile (PDF Part 1: age, gender, height,
// weight, body fat). Local-first like the rest of the app; pure model so it's
// unit-tested. Weight/body-fat also flow from logs, but the profile is the one
// place to set the static identity fields (age/gender/height) the engine will use
// once it grows beyond the single young-male cohort.
class ProfileData {
  final int? age;
  final String gender; // 'male' | 'female' | 'other'
  final double? heightCm;
  final double? weightKg;
  final double? bodyFatPct;

  const ProfileData({
    this.age,
    this.gender = 'male',
    this.heightCm,
    this.weightKg,
    this.bodyFatPct,
  });

  static const empty = ProfileData();

  ProfileData copyWith({
    int? age,
    String? gender,
    double? heightCm,
    double? weightKg,
    double? bodyFatPct,
  }) =>
      ProfileData(
        age: age ?? this.age,
        gender: gender ?? this.gender,
        heightCm: heightCm ?? this.heightCm,
        weightKg: weightKg ?? this.weightKg,
        bodyFatPct: bodyFatPct ?? this.bodyFatPct,
      );

  Map<String, dynamic> toJson() => {
        'age': age,
        'gender': gender,
        'height': heightCm,
        'weight': weightKg,
        'bodyFat': bodyFatPct,
      };

  factory ProfileData.fromJson(Map<String, dynamic> j) => ProfileData(
        age: (j['age'] as num?)?.toInt(),
        gender: j['gender'] as String? ?? 'male',
        heightCm: (j['height'] as num?)?.toDouble(),
        weightKg: (j['weight'] as num?)?.toDouble(),
        bodyFatPct: (j['bodyFat'] as num?)?.toDouble(),
      );

  /// BMI from height + weight, or null if either is missing.
  double? get bmi {
    final h = heightCm, w = weightKg;
    if (h == null || w == null || h <= 0) return null;
    final m = h / 100;
    return w / (m * m);
  }
}
