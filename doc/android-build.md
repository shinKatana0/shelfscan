# Building for Android on Windows

Debug and release apks were built from this tree on 2026-08-23, on Flutter
3.47.0 stable, from a machine that had no JDK, no Android Studio and no Android
SDK on it. Getting there cost four diagnoses, and not one of them presents as a
missing step: three fail the build while naming something else, or naming
nothing at all, and the fourth does not fail the build. This page is those
diagnoses written down so that the next person pays for none of them -- plus a
fifth trap that belongs to nobody's first day (T-0365) and, below them, what
the plugin upgrade later cost, which is the same kind of knowledge arriving
from a different direction.

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

**And run that build alone in its worktree** — no `flutter analyze`, no
`flutter test`, no `flutter pub get` beside it. Trap 5 below is what happens
when one of them lands while the apk is building.

## The five traps, in the order they bite

Each one is written symptom first, because that is the half you arrive
holding. Four of the five fail the build. **The fourth does not** — it is the
one that ships — and that is why it is the worst of them.

The order is when you meet them, not how bad they are. Traps 1 to 3 are the
toolchain and stand between you and your first apk. Traps 4 and 5 are on the
other side of it, once you are building routinely with the suites running
beside the build.

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
`:flutter_plugin_android_lifecycle`, which `file_picker` pulled in then and
which requires its dependents to compile against 36 or later. `file_picker` 12
does not pull it in any more — see *The `compileSdk` hook forces 36 onto a
plugin that declares 37* below, which is what that leaves behind.

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

### 5. `compileReleaseJavaWithJavac` fails on a package you never depended on

**Symptom.** The release build dies compiling a file you have never edited:

```
GeneratedPluginRegistrant.java:34: error: package dev.flutter.plugins.integration_test does not exist
      flutterEngine.getPlugins().add(new dev.flutter.plugins.integration_test.IntegrationTestPlugin());
```

under `Execution failed for task ':app:compileReleaseJavaWithJavac'`.
`integration_test` is a **dev** dependency, so it is not on the release compile
classpath and that line should not be in the file. The file is generated and
gitignored, so the failure reads as a defect in the tree. It is not one, and
nothing in `app/` is wrong. A debug build does not reproduce it, and running
the release build a second time usually clears it — which is the other half of
why this costs twenty minutes rather than two.

**Cause. Two flutter commands write that file, and the last writer wins.**
Every flutter command regenerates `GeneratedPluginRegistrant.java` a few seconds
after it starts, and there are two versions of it:

- `flutter pub get`, `flutter analyze` and `flutter test` write the version that
  **includes dev-dependency plugins**, `integration_test` among them.
- `flutter build apk` writes the version that **excludes** them.

Each is right on its own, and the release build's write wins whenever it runs
alone: it rewrites the file about six seconds in, and Gradle then compiles for
one to two minutes. **Those minutes are the hole.** Any other flutter command
started in the same worktree during them puts the dev-dependency version back,
and `compileReleaseJavaWithJavac` runs late enough to compile what it finds.

Measured 2026-08-24 on Flutter 3.47.0, five release builds. A build in a
worktree whose registrant already named `integration_test` succeeded — twice,
from two differently-prepared worktrees — because it rewrote the file before
Gradle started. The same build with one `flutter analyze` fired into its Gradle
phase failed with the error above. **What a worktree has run before the build
does not matter. What runs during it does.**

**Fix.** Build alone. Do not run the suites in one shell while the apk builds
in another: they look independent, they touch no file of yours in common, and
they share this one generated file. If you already have the error, you need
neither `flutter clean` nor a change to `app/pubspec.yaml` — run
`flutter build apk` again with nothing beside it, and it regenerates the
registrant correctly.

**This is not the Gradle-daemon collision**, which is a separate hazard: two
*builds* at once contend for one daemon and one lock. Trap 5 needs no second
build. One `flutter analyze`, which finishes in under ten seconds, is enough.

Traps 2, 3 and 4 are recorded as comments at their sites as well. That reaches
somebody already editing those files; it does not reach somebody who has just
run `flutter build apk` for the first time, which is why they are also here.
Traps 1 and 5 have no site to live at: what is at fault in trap 1 is not in the
tree, and trap 5's file is generated on every command and gitignored, so a
comment in it would be overwritten within seconds of being written.

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

## `share_plus` applied the Kotlin Gradle Plugin, and getting off it moved three plugins

**Symptom, and it is history: until T-0304 every `flutter build apk` printed
this, and then built anyway.**

```
WARNING: Your app uses the following plugins that apply Kotlin Gradle Plugin (KGP): share_plus
Future versions of Flutter will fail to build if your app uses plugins that apply KGP.
```

**What it means, and Built-in Kotlin is still coming.** Flutter is moving to
it: the Flutter Gradle plugin supplies Kotlin itself, and a plugin that applies
KGP in its own Gradle file stops building. This tree is past that for the
plugins it has today, and a plugin added tomorrow can put the warning back —
the two guides are worth keeping to hand for when it does.
[For app developers](https://docs.flutter.dev/release/breaking-changes/migrate-to-built-in-kotlin/for-app-developers)
and [for plugin authors](https://docs.flutter.dev/release/breaking-changes/migrate-to-built-in-kotlin/for-plugin-authors).

`share_plus` was never incidental here: it is the whole Android export path,
the share sheet `app/lib/export_saver.dart` raises. Dropping the dependency was
not an option, so this could only resolve by upgrading it.

**Cause of the delay — `win32`, not Kotlin. This is the half worth keeping.**
`share_plus` 13.2.0 added Built-in Kotlin support, so the fix existed upstream
before this tree could take it. `share_plus` >= 13.1.0 requires `win32 ^6.0.1`,
and two other direct dependencies pinned `win32 ^5`, so version solving failed
— on `flutter_secure_storage ^9.2.2` first, and once that was raised, on
`file_picker ^8.0.0`. The resolution closed only with all three moved:
`share_plus` 13.3.0, `flutter_secure_storage` 11.0.0, `file_picker` 12.0.0.

**The shape to recognise, if a plugin upgrade refuses here again.** The package
the solver names is rarely the one you asked about; raising it moves the
failure one package along rather than clearing it; and what actually binds is a
shared transitive major — here `win32` — that several direct dependencies pin
below the version your target needs. Read such a failure as a set of packages
to move together, not as one blocker to argue with.

**What the three cost, priced twice, because the price moved.**

- **`file_picker` 12 was the expensive one, and it got cheaper while it
  waited.** It removes `FilePicker.platform` and makes `FilePicker` a `final`
  class, so the fake-picker pattern the app test suite was built on stopped
  compiling: priced against the tree of the day, 90 of 94 analyzer complaints,
  spread over nine test files. By the time the upgrade was taken, T-0305 had
  put the picker behind `app/lib/input_picker.dart` and that pattern was
  already gone — the same upgrade then raised four issues in one adapter.
  **The general case:** an upgrade is priced against the tree it was priced
  on, and an intervening refactor can move that price by more than an order of
  magnitude. Re-price before you plan around an old estimate.
- **`flutter_secure_storage` 11 was source-clean**, on both pricings — it
  raised nothing at all, which is the opposite of what one expects of the
  keychain path (decision 0011). It was not behaviour-clean, and the Android
  credential note below is the whole of what it did cost.
- **`share_plus` 13 cost two lines.** Its 11.0.0 superseded the `Share` class
  with `SharePlus.instance.share(ShareParams(...))`. `Share.shareXFiles` still
  exists and still works, but is `@Deprecated`, and `flutter analyze` — which
  CI runs, and which fails on an `info` — reports it.

**Fix, taken in T-0304.** All three constraints moved together, the
`file_picker` call sites and the `Share` call were ported, and a release apk
was built and its whole log searched for the warning: nothing, against the two
lines above on a build with the old constraints restored. `app/pubspec.yaml`
pins `share_plus: ^13.2.0` rather than `^13.3.0` — 13.2.0 is the release that
added the support, so the constraint records the reason for the number, and
13.3.0 is what resolves. `doc/reports/T-0304.md` holds the measurement and the
full list of what moved with them.

Nothing here has been run on a device — T-0015 is still what verifies the share
sheet actually shares — so a green build is a green build and no more.

## Three notes from the plugin upgrade, in the order they bite

Three things came out of that upgrade that a reader here needs. The first fails
the build the moment you pull the change; the second is silent and only on
Android; the third does not bite at all yet.

### Upgrading over an existing checkout fails inside `share_plus`'s own Kotlin

**Symptom.** `flutter build apk --release` fails at
`:share_plus:compileReleaseKotlin` with `Unresolved reference
'SharePlusPendingIntent'` and two type errors, all three at line 185 of the
plugin's own `Share.kt`. Everything the message names is inside the plugin, so
it reads as the plugin being broken, and the obvious response — pin
`share_plus` back — is the wrong one.

**Fix.** `flutter clean`, then `flutter pub get`, then build again. The same
checkout that had just failed then produced a release apk of 50.8 MB, beside
the 50.9 MB recorded above for a release build made before the upgrade.

**Cause — inferred rather than measured, and the next paragraph is part of
this one.** This tree is on AGP 9.1.0 (`app/android/settings.gradle.kts`).
`share_plus` 13.3.0's `android/build.gradle.kts` applies the Kotlin Android
plugin **only when the AGP major is below 9**, so here it does not: the
subproject relies on AGP 9's Built-in Kotlin instead, which is exactly why the
KGP warning above went away. `share_plus` 10.1.4 applied `kotlin-android`
unconditionally. So the same subproject, writing into the same build directory,
changed Kotlin pipelines between the two versions — and incremental state
written by the old pipeline and then reused by the new one is what best
explains a partial recompile in which `Share.kt` was built without its
neighbour `SharePlusPendingIntent.kt` visible. `internal` visibility depends on
module membership, which is precisely what that state describes.

**Nobody reproduced this deliberately.** What was observed is the failure, and
that `flutter clean` cleared it; the mechanism above is the best explanation
available from the two plugins' Gradle files and nothing more. Proving it means
seeding a build directory from 10.1.4 and upgrading over it, which has not been
done here.

**Why it was not caught before the merge.** T-0304 was verified in a fresh git
worktree, where `app/build/` is gitignored and therefore absent, so its release
build ran from an empty build directory. That establishes that the upgrade
builds from scratch. It says nothing about building over an existing checkout,
which is what everybody who pulls the change has.

The general case is worth one line: **a plugin changing *how* it is compiled is
invisible in a version number**, so `flutter clean` after any plugin major is
cheap insurance.

### Android credentials from an earlier build become unreadable

**Symptom.** An Android install that had keys entered from an apk built before
this change behaves afterwards as though no key were configured. What the
settings screen shows while it does is one of the two unknowns below.

**Cause.** `flutter_secure_storage` went **9.2.4 → 11.0.0 in one step**. Its
11.0.0 changelog says that data written with what v10 deprecated is unusable
after the upgrade, and that you should install v10 first, which migrates it. On
Android, 11 removes `StorageCipherAlgorithm.AES_CBC_PKCS7Padding` and
`KeyCipherAlgorithm.RSA_ECB_PKCS1Padding` — what 9.x wrote with — and removes
the `encryptedSharedPreferences` backend.

**There is no migration path here, and this page will not imply one.** Version
10 does not satisfy the `win32` major that `share_plus` 13 requires, which is
the whole reason the three plugins had to move together, so the intermediate
release cannot be resolved in this tree at all. For a published application the
answer would be to ship v10 first and v11 after it; that option does not exist
here.

**Windows is unaffected, and that was checked rather than assumed** — worth
saying, because a reader who hears that the storage format moved will fear for
both platforms. `flutter_secure_storage_windows` went 3.1.2 → 4.2.2 with no
storage-format change: 4.0.0 is an SDK, analyzer and `win32` migration, 4.2.0
fixes the DPAPI FFI calls for `win32` 6.0.0, and 4.2.1 and 4.2.2 fix
concurrency bugs. The encrypted-file storage introduced in 2.0.0 is untouched,
so credentials already stored on Windows stay readable.

**Fix.** Re-enter the keys on the settings screen. Nothing recovers the old
store and nothing tries to. The damage is bounded by the project being
bring-your-own-key: the keys belong to whoever entered them and they still have
them, so the cost is entering them once more.

**Two things nobody knows, and both need an Android device** — T-0017 is the
task that verifies settings persistence there:

- Whether the read **fails soft**, returning null so the settings screen simply
  shows empty fields, or **throws**, which on that screen would look like the
  application being broken rather than like a key needing re-entry.
- Whether a partial read leaves the store in a state where **writing fresh keys
  also fails**.

### The `compileSdk` hook forces 36 onto a plugin that declares 37

**Symptom.** None. The release build succeeds and produces an apk, and that is
the reason to write this down rather than the reason not to.

Trap 2's hook in `app/android/build.gradle.kts` reflectively sets `compileSdk`
to 36 on every plugin subproject. `flutter_secure_storage` 11.0.0 declares
`compileSdk = 37` in its own `android/build.gradle`, so the hook now overrides a
plugin **downwards**, below the level it states it needs. Nothing exercises the
difference today. The next plugin that does will fail with a message about aar
metadata — trap 2's symptom — rather than with one about this hook.

**The recorded reason for 36 no longer matches the graph.** Both comments, at
the hook and above `compileSdk = 36` in `app/android/app/build.gradle.kts`, name
`flutter_plugin_android_lifecycle`, which `file_picker` used to pull in.
`file_picker` 12 does not, and `flutter pub get` reported that package as no
longer depended on. So the value is explained by a package that has left the
graph, while sitting below one that is in it.

**What the check found, and what it cannot settle.** Asked whether anything
currently in the graph still needs the hook: nothing is on record as requiring
36, the package that did require it has gone, and the one plugin whose level is
on record declares 37 — above the hook rather than below it. That is checked
against this tree and against T-0304's measurements, not against every current
plugin's own Gradle file. And it does **not** show the hook to be dead weight:
every build since trap 2 has run with it in place, and a build with the hook
cannot say what a build without it would do. Only a build with the hook removed
can.

**So the hook is left exactly as it is.** Removing it, or making it take the
higher of the plugin's declared level and a floor, is a change rather than a
note and needs a build to prove it. `flutter_secure_storage` 11.0.0 also raises
its own `minSdk` to 24 while `app/android/app/build.gradle.kts` takes `minSdk`
from `flutter.minSdkVersion`; whether the app's floor is now set by the plugin
rather than by Flutter has not been checked either.

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
