/// The version this build declares, and the only copy of it in Dart.
///
/// It is `MAJOR.MINOR.PATCH+BUILD` per decision 0014 as amended, and the
/// `+BUILD` half is the load-bearing one: with no `+N` in `pubspec.yaml`
/// Flutter substitutes `1` and warns nobody, which is how every Android
/// package this project has produced came to declare `versionCode='1'`.
///
/// **Why a constant, when nothing else in this project duplicates a fact.**
/// Nothing readable at runtime carries this version without a new dependency.
/// `pubspec.yaml` is not a bundled asset; the Flutter tool writes no
/// `version.json` into the bundles this project builds (checked across every
/// bundle in `app/build/` -- debug, release and the unit-test bundle -- and
/// there is none); and `String.fromEnvironment` would move the failure to a
/// build flag whose absence is silent, which is the defect being removed
/// rather than a fix for it.
///
/// The dependency that would answer it is `package_info_plus`, which reads the
/// artefact itself -- Android's `PackageManager`, the Windows exe's version
/// resource. It was not taken: it adds a plugin to the release graph and a
/// notice `settings_licenses_test.dart` then has to be told to expect; it
/// answers only over a platform channel and so is a fake under `flutter test`
/// exactly where the display is asserted; and the two platforms hold the
/// number differently -- measured on this build, the apk's manifest carries
/// `versionName='0.2.0'` and `versionCode='2'` as two fields, while the
/// Windows exe's resource carries `0.2.0+2` whole -- so the displayed line
/// would have to be reassembled per platform to read alike. What it buys over
/// this constant is a disagreement that `app_version_test.dart` already fails
/// on.
///
/// So this is a second copy that is *checked*: that test reads both
/// `pubspec.yaml` files and this string and fails if any two differ, in the
/// shape `settings_licenses_test.dart` uses to hold `appLegalese` in step with
/// `LICENSE`. Bump the pubspecs and this line together; the test is what says
/// so if you do not.
library;

const appVersion = '0.2.0+2';
