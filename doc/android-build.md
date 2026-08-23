# Building for Android on Windows

A debug apk was built from this tree on 2026-08-23, on Flutter 3.47.0 stable,
from a machine that had no JDK, no Android Studio and no Android SDK on it.
Getting there cost three diagnoses, and none of the three presents as a missing
step — each one presents as a build failure that names something else, or names
nothing at all. This page is those diagnoses written down so that the next
person pays for none of them.

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

## The three traps, in the order they bite

Each one is written symptom first, because that is the half you arrive
holding.

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

Traps 2 and 3 are recorded as comments at their sites as well. That reaches
somebody already editing those files; it does not reach somebody who has just
run `flutter build apk` for the first time, which is why they are also here.

## What the Android CLI sends to Google

The new `android` CLI **reports usage data to Google by default** — commands,
sub-commands and flags. It accepts `--no-metrics`, which is why every
invocation on this page carries it.

The thing to know is that the opt-out is a *flag* and not a *setting*: there is
nothing to configure once. Anybody who types `android` without it has opted in,
silently, for that invocation. If you use the tool regularly, wrap it in a
shell alias or function that supplies the flag.

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
