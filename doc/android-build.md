# Building for Android on Windows

Debug and release apks were built from this tree on 2026-08-23, on Flutter
3.47.0 stable, from a machine that had no JDK, no Android Studio and no Android
SDK on it. Getting there cost four diagnoses, and not one of them presents as a
missing step: three fail the build while naming something else, or naming
nothing at all, and the fourth does not fail the build. This page is those
diagnoses written down so that the next person pays for none of them.

Windows desktop has its own two undocumented prerequisites, and they are
elsewhere: [`README.md`](../README.md), *Setup → The app*.

## What you need, and what you do not

**Android Studio is not required.** It is the default answer everywhere and it
is the wrong one here: it is a gigabyte and a GUI installer, and this project
builds from the command-line SDK alone. Nothing in `app/android/` refers to it.

Two packages, both from `winget`:

```
winget install Microsoft.OpenJDK.17
winget install Google.AndroidCLI
```

JDK 17 rather than a newer one because the Gradle config pins Java 17
(`app/android/app/build.gradle.kts` sets both `sourceCompatibility` and the
Kotlin `jvmTarget` to 17).

`Google.AndroidCLI` installs the `android` command. **Open a new shell after
it** — the installer puts it on `PATH`, and an already-running shell does not
see that.

## The install path

Four SDK components: `platform-tools`, the **android-36** platform, the
matching `build-tools`, and **`cmdline-tools;19.0`**.

```
android --no-metrics sdk install platform-tools
android --no-metrics sdk install "platforms;android-36"
android --no-metrics sdk install "build-tools;<version>"
android --no-metrics sdk install "cmdline-tools;19.0"
```

Package coordinates are the standard Android SDK ones. `android sdk list` gives
the exact string for the `build-tools` release current when you read this, and
for anything above that has moved on. If your version of the CLI rejects
`--no-metrics` in that position, `android --help` says where it goes; do not
drop it, and see *What the Android CLI sends to Google* below for why.

**Android 36 is not a choice** — `compileSdk = 36` in
`app/android/app/build.gradle.kts` and in the `subprojects` hook in
`app/android/build.gradle.kts`, and trap 2 below is what happens when a plugin
compiles against anything lower.

`cmdline-tools;19.0` is trap 1, and there is a second half to it — read that
section before you build.

Then point Flutter at both toolchains:

```
flutter config --android-sdk <sdk path>
flutter config --jdk-dir <jdk path>
```

The SDK lands under `%LOCALAPPDATA%\Android\Sdk` unless you moved it, and the
JDK under `%ProgramFiles%\Microsoft\`. `flutter config` with no arguments
prints back what it has stored for both, which is the way to check they took —
and the way to answer "where is the SDK" without going looking for it.

Then, from `app/`:

```
flutter pub get
flutter build apk --debug
```

The apk lands at `app\build\app\outputs\flutter-apk\app-debug.apk` and carries
the `applicationId` set in `app/android/app/build.gradle.kts`.

`flutter build apk` gives you the release one. Both succeeded here on
2026-08-23: **debug 155 MB, release 50.9 MB**. R8 runs on the release build and
leaves a mapping file beside the apk. A debug apk three times the size of the
release one is not a symptom of anything — expect it.

**Test on a release build, not only a debug one.** Trap 4 below is invisible to
`flutter run`.

## The four traps, in the order they bite

Each one is written symptom first, because that is the half you arrive
holding. The first three fail the build. **The fourth does not**, which is why
it is last and why it is the worst of them.

### 1. The build dies with a negative exit value and names nothing

**Symptom.** Gradle reports only that a process finished with a non-zero exit
value, and the value is negative: **`-1073740791`**, which is **`0xC0000409`**
read as a signed 32-bit integer — `STATUS_STACK_BUFFER_OVERRUN`. Nothing in the
message names the SDK, `sdkmanager`, or `cmdline-tools`. Searching for it finds
nothing useful, because the string is a Windows crash code rather than an
Android one.

**Cause.** Google has deprecated `sdkmanager`. The current `cmdline-tools`
package, version **23.0**, no longer contains the classic tool — what is at
that path is a shim that delegates to the new `android` CLI. Under the
arguments Gradle passes it, the shim crashes.

What makes this one expensive is that the shim looks fine when you check it:
called directly with `--version` it answers normally. Only Gradle's arguments
kill it, so every direct test you run to narrow the fault comes back green.

**Fix.** Install `cmdline-tools;19.0`, which still carries the classic
`sdkmanager`, **and remove 23.0** — delete the `cmdline-tools\23.0` directory
from the SDK. Both halves are needed; 19.0 sitting alongside 23.0 does not fix
it.

### 2. `checkDebugAarMetadata` fails over an API level you already raised

**Symptom.** A plugin subproject's `checkDebugAarMetadata` task fails with a
message spelling out a comparison between two API levels and naming both
modules. Here it was `:file_picker`, compiled against `android-34`, and
`:flutter_plugin_android_lifecycle`, which `file_picker` pulls in and which
requires its dependents to compile against 36 or later.

**Cause.** `compileSdk` has to be raised in two places, and the second is the
one that matters. Raising it in `app/android/app/build.gradle.kts` fixes the
application only. Every plugin subproject takes its `compileSdk` from the
Flutter SDK's default rather than from your app, so they all stay where they
were.

**Fix.** A `subprojects` hook in the root `app/android/build.gradle.kts` that
sets `compileSdkVersion` on each subproject's `android` extension in
`afterEvaluate`. It is already in the tree, with the measurement in a comment
beside it. It is written once for all plugins rather than per plugin, because
the next plugin to want 36 would otherwise be diagnosed from scratch.

### 3. `Cannot run Project.afterEvaluate when the project is already evaluated`

**Symptom.** Exactly that sentence, thrown during configuration, after you add
the hook from trap 2.

**Cause.** The root `build.gradle.kts` has a second `subprojects` block that
calls `evaluationDependsOn(":app")`, and that evaluates the projects. An
`afterEvaluate` registered after it has nothing left to run against.

**Fix.** The hook must sit in the `subprojects` block **above**
`evaluationDependsOn(":app")`. Order within the file is load-bearing, which is
not something a Gradle file usually is, and it is the reason the two blocks are
not merged.

### 4. A release build has no network, and it fails the build in no way at all

**Symptom.** The release apk installs, launches and draws. Then every provider
call fails, with nothing the app can tell apart from a dead network — no
permission dialog, no error naming a permission, just a scan that cannot reach
anything. **A debug build does not reproduce it.**

That last sentence is the trap. `flutter run` and `flutter build apk --debug`
both work perfectly, so the obvious way to test a change proves nothing about
the build you would ship.

**Cause.** Flutter declares `android.permission.INTERNET` in
`app/android/app/src/debug/AndroidManifest.xml` and `src/profile/` only. The
main manifest — the one a release build uses — is generated without it.

**Fix.** Declare it in `app/android/app/src/main/AndroidManifest.xml`. It is
already there in this tree, with the reason in a comment beside it.

**Why this stays on the page even though it is fixed:** the fix lives in a
platform folder, and a platform folder is the thing somebody regenerates. Run
`flutter create` over `app/android/` one day and the empty manifest comes back,
exactly as `com.example` comes back over the Windows runner — which is the
defect T-0194 exists for.

The same manifest carries `android:label`, which Flutter fills with the project
name, `shelfscan_app`. It is now `shelfscan`, matching what `Runner.rc` and the
Windows window title already say. A regenerated folder undoes that too, and
unlike the permission it is visible: it is the name under the launcher icon.

Traps 2, 3 and 4 are recorded as comments at their sites as well. That reaches
somebody already editing those files; it does not reach somebody who has just
run `flutter build apk` for the first time, which is why they are also here.
Trap 1 has no site to live at, because the thing at fault is not in the tree.

## The release build is signed with the debug key

`app/android/app/build.gradle.kts` sets, under `buildTypes.release`:

```kotlin
signingConfig = signingConfigs.getByName("debug")
```

That is the Flutter template's line and it is still there, with the template's
`TODO` above it. Two things follow, and they are worth stating because a reader
who assumes the opposite will go and do unnecessary work:

- **You do not need a keystore to build a release apk.** It builds, installs
  and runs. Nothing on this page asks you to create one.
- **The apk is not publishable as it stands.** Google Play will not accept an
  artifact signed with the debug key, so a real signing config is a
  prerequisite of a release rather than of a build.

No signing procedure is written here, because none has been run here.

## What the Android CLI sends to Google

The new `android` CLI **reports usage data to Google by default** — commands,
sub-commands and flags. It accepts `--no-metrics`, which is why every
invocation on this page carries it.

The thing to know is that the opt-out is a *flag* and not a *setting*: there is
nothing to configure once. Anybody who types `android` without it has opted in,
silently, for that invocation. If you use the tool regularly, wrap it in a
shell alias or function that supplies the flag.

## `share_plus` applies the Kotlin Gradle Plugin, and one day the build will refuse

**Symptom.** Every `flutter build apk` prints this, and then builds anyway:

```
WARNING: Your app uses the following plugins that apply Kotlin Gradle Plugin (KGP): share_plus
Future versions of Flutter will fail to build if your app uses plugins that apply KGP.
```

**What it means.** Flutter is moving to Built-in Kotlin: the Flutter Gradle
plugin supplies Kotlin itself, and a plugin that applies KGP in its own Gradle
file stops building. Flutter publishes a guide each way —
[for app developers](https://docs.flutter.dev/release/breaking-changes/migrate-to-built-in-kotlin/for-app-developers)
and [for plugin authors](https://docs.flutter.dev/release/breaking-changes/migrate-to-built-in-kotlin/for-plugin-authors).

`share_plus` is not incidental here: it is the whole Android export path, the
share sheet `app/lib/export_saver.dart` raises. Dropping the dependency is not
an option, so this resolves by upgrading it or not at all.

**Is it fixed upstream? Yes. Can this tree take the fix? Not yet.** Measured
2026-08-23 on Flutter 3.47.0 / Dart 3.13.0, against `share_plus` 10.1.4 in the
lock.

`share_plus` **13.2.0** added it — *"FEAT: Add support of built-in Kotlin"* in
its changelog — and **13.3.0** is current. Raise the constraint and
`flutter build apk --release` prints no KGP warning at all. That build then
fails, at the Dart compile, on the `file_picker` errors below — but it fails
*past* the point the warning is printed: on 10.1.4 the warning is the second
line of the log, ahead of everything else, and on 13.3.0 the same search over a
log that got as far as `:app:compileFlutterBuildRelease` finds nothing. The
upgrade removes the warning. No apk has been produced on it.

**What blocks it is `win32`, not Kotlin.** `share_plus` >= 13.1.0 requires
`win32 ^6.0.1`; two other direct dependencies of this app pin `win32 ^5`, so
version solving fails — on `flutter_secure_storage ^9.2.2` first, and once that
is raised, on `file_picker ^8.0.0`. The resolution closes only with all three
moved: `share_plus` 13.3.0, `flutter_secure_storage` 11.0.0, `file_picker`
12.0.0.

With all three moved the app does not compile, and `share_plus` is the least of
it:

- **`file_picker` 12 is the cost.** It removes `FilePicker.platform` and makes
  `FilePicker` a `final` class. That is two errors in
  `lib/screens/scan_screen.dart` and the end of the fake-picker pattern the app
  test suite is built on — nearly every analyzer complaint comes from here.
- **`flutter_secure_storage` 11 is free.** Source-clean against this tree; it
  raised nothing.
- **`share_plus` 13 costs two lines.** Its 11.0.0 superseded the `Share` class
  with `SharePlus.instance.share(ShareParams(...))`. `Share.shareXFiles` still
  exists and still works, but is `@Deprecated`, and `flutter analyze` — which
  CI runs, and which fails on an `info` — reports it.

**So the constraint was deliberately left alone** (T-0293), because this is a
three-plugin upgrade with an API port in it and not a version bump. T-0304
holds the upgrade.

**When the build finally refuses**, that is the task to do, and none of it is
guesswork now: raise all three, port the `file_picker` call sites and the test
fakes, migrate `Share.shareXFiles` to `SharePlus.instance.share`. Then build a
release apk and check the warning is gone rather than assuming it. Nothing
above has been run on a device — T-0015 is still what verifies the share sheet
actually shares — so a green build is a green build and no more.

## Unresolved: `flutter doctor` reports the licence status unknown

`flutter doctor` reports **Android license status unknown** on this toolchain,
and it says so even though the SDK's licence file is present.

The cause is a seam between two versions rather than a missing acceptance.
Flutter 3.47 checks licences by driving the deprecated `sdkmanager`, which now
answers that `--licenses` is no longer needed. Flutter cannot parse that
answer, so it reports what it does when it cannot tell.

**The build is unaffected** — an apk was produced and carries the right
`applicationId`. This is recorded rather than fixed, because no workaround for
it has been run here, and a workaround nobody has run is worse than a stated
unknown. Do not spend an afternoon on it before you have tried building.
