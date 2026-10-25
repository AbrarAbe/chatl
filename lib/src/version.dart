/// The version this binary was built from.
///
/// `pubspec.yaml` is the single source of truth; release builds inject it via
/// `--define=CHATL_VERSION=<version>` and an unbuilt `dart run` reports `dev`,
/// so a missing injection is obvious rather than silently wrong.
const String chatlVersion = String.fromEnvironment(
  'CHATL_VERSION',
  defaultValue: 'dev',
);
