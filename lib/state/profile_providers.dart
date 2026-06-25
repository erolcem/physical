// state/profile_providers.dart — Riverpod wiring for the user profile, read/written
// through the same Repository seam as logs and habits.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/profile.dart';
import '../data/repository.dart';
import 'providers.dart';

final profileProvider =
    StateNotifierProvider<ProfileNotifier, ProfileData>((ref) {
  return ProfileNotifier(ref.watch(repositoryProvider));
});

class ProfileNotifier extends StateNotifier<ProfileData> {
  final Repository repo;
  ProfileNotifier(this.repo) : super(repo.loadProfile());

  void save(ProfileData profile) {
    repo.saveProfile(profile);
    state = profile;
  }
}
