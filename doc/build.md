# Building the app

**A tagged release now carries one built app, and it is the Windows one.**
A `v*` tag builds `ShelfScan-win-x64.zip` on a Windows runner and attaches it
to that release (`.github/workflows/release.yml`), so a reader who wants to
*run* the app on Windows downloads and extracts it and never comes to this
page. `README.md`'s *Windows: download and run* is that whole route.

**Everything else is still built here and nowhere else.** No installer, no
apk, no macOS or Linux binary is published, so this repository remains the
only way to have the app on any other platform -- and the only way to run a
change you have made, on any platform at all. That is who this page is for.

Only the app needs what follows. The CLI is plain Dart and needs none of it —
[`guide.md`](guide.md) walks one whole run with it, from nothing to an
imported collection.

Neither platform builds on a `flutter doctor` that prints green, and the
prerequisites each one is missing are written down rather than left to be
rediscovered:

- **Windows** — two things `flutter doctor` does not check at all, and the
  cache that breaks every later build if you clear `app\build\` by hand:
  below on this page.
- **Android** — the toolchain, and five failures: three that name something
  other than the missing step, one that does not fail the build at all and
  is invisible to every debug build, and one you cause by running the suites
  beside the build.
  [`android-build.md`](android-build.md). **Android Studio is not
  required**; the command-line SDK is enough, and that page is the shortest
  route from a bare Windows machine to an apk.

Neither is needed to run the suites, review a change, or work on
`shelfscan_core`.

**The platform folders are committed.** `flutter create` scaffolded
`app/windows/` and `app/android/` once; ever since they have been hand-edited
source carrying the release identity — `Runner.rc`, the `AndroidManifest.xml`,
the `applicationId`, the icons — and they are reviewed like any other file.
What is genuinely generated inside one is ignored by the `.gitignore` that
`flutter create` writes into that folder, and build output is a different path
again. The [`.gitignore`](../.gitignore) comment at the entry says the same at
more length.

**Do not run `flutter create` over this checkout.** It regenerates those
folders and hands back `com.example` in place of the identity above, and on
Android it also drops the `INTERNET` permission that a release build has no
other way to get — a loss no build fails on and no debug build reproduces. If
you have already run it, `git status` names every file it touched and
`git checkout --` on those files puts them back.

`flutter create` also writes two files from the default counter template that
are not part of this project and are not tracked here: `app/README.md` and
`app/test/widget_test.dart`. Delete both. The test pumps a `MyApp` that does
not exist here (this app is `ShelfscanApp`), so leaving it in place makes
`flutter test` fail on a file nobody wrote:

```
test/widget_test.dart:16:35: Error: Couldn't find constructor 'MyApp'.
```

Neither is gitignored, deliberately: being untracked and unignored is what
makes `git status` name them, and that is the only warning you get that the
command ran at all.

### Windows: two prerequisites `flutter doctor` will not tell you about

**A green `flutter doctor` does not mean the Windows build will work.** Its
Visual Studio check looks for the `Desktop development with C++` workload
plus exactly two components (`VC.Tools.x86.x64` and `VC.CMake.Project`),
and it has no Windows Developer Mode check at all — so it prints
`[✓] Visual Studio - develop Windows apps` while both of the things below
are missing. The first build of this app hit them in this order.

**1. Turn on Windows Developer Mode.** Without it `flutter create` and
every build that has plugins abort with:

```
Building with plugins requires symlink support.

Please enable Developer Mode in your system settings. Run
  start ms-settings:developers
to open settings.
```

Flutter links plugin sources into the build with symlinks, and Windows
allows only administrators to create symlinks until Developer Mode is on.
Run that `start ms-settings:developers` command and flip the switch. It is
off on a fresh machine: the registry value it writes,
`HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock\AllowDevelopmentWithoutDevLicense`,
does not exist at all until Developer Mode is enabled the first time, and
reads `1` afterwards.

**2. Add the C++ ATL component to Visual Studio.** The
`Desktop development with C++` workload does not include ATL — it is a
separate entry under *Individual components*. Without it the build runs the
whole toolchain and then dies on a single plugin:

```
flutter_secure_storage_windows_plugin.cpp(6): fatal error C1083: Cannot open include file: 'atlstr.h': No such file or directory
```

Visual Studio Installer → Modify → **Individual components** → search
`ATL` → tick **C++ ATL for x64/x86 (Latest MSVC)**. That is the name in
Build Tools 2026; the wording tracks the toolset, so VS 2022 lists the same
thing as `C++ ATL for latest v143 build tools (x86 & x64)`. The name is
also translated in a localized installer, so the handle that always works
is the component id `Microsoft.VisualStudio.Component.VC.ATL`.

The compiler's error text is localized the same way: on a Russian install
that C1083 line reads `Не удается открыть файл включение: atlstr.h`. The
tokens that survive translation are `C1083` and `atlstr.h` — search your
console output for those, not for the English sentence.

The ATL dependency is ours rather than Flutter's: `flutter_secure_storage`,
which keeps the BYOK credentials in the OS keychain, is the only thing in
this project that includes `<atlstr.h>`.

### What the first successful build looks like

Measured on Flutter 3.47.0 stable, Visual Studio Build Tools 2026
18.9.12105.275 with MSVC 14.51.36231, Windows 11 25H2:

| Command | Cold build | Produces |
|---|---|---|
| `flutter build windows --debug` — what `flutter run -d windows` compiles | 124 s | `app\build\windows\x64\runner\Debug\shelfscan_app.exe` |
| `flutter build windows` | 164 s | `app\build\windows\x64\runner\Release\shelfscan_app.exe` |

Cold means nothing cached — no `build\`, no `.dart_tool\`. Expect a couple of
minutes and do not assume it has hung.

The release exe is only 90 KB and does not run alone: `flutter_windows.dll`,
`data\`, and one DLL per plugin sit beside it. Distribute the folder.

**The folder is not quite self-contained, measured on its own PE imports.**
`share_plus_plugin.dll` imports `MSVCP140.dll`, `VCRUNTIME140.dll` and
`VCRUNTIME140_1.dll`, and `dartjni.dll` imports the second of those. Those are
Microsoft's C++ runtime, they are not part of Windows, and neither Flutter nor
the packaging step copies them in -- so a machine that has never had the
redistributable installed answers with a missing-DLL box rather than a window.
Everything else the exe needs is beside it: the `api-ms-win-crt-*` imports are
the Universal CRT, which is in-box on Windows 10 and 11. All three READMEs name
this under the download, because it looks exactly like a broken download and is
not one.

**But do not distribute the folder YOU built** -- build locally to run and to
test, and let the tag produce what is published. Measured on a release build of
this tree: the AOT snapshot `datapp.so` carries the absolute path of the
directory it was compiled in, as one string ending
`app/.dart_tool/flutter_build/dart_plugin_registrant.dart`. The toolchain writes
it; nothing here asks for it and no build flag was found that removes it.

That one string is the *only* build-machine path in the whole folder, which is
the reason it is worth naming rather than worrying about generally. A sweep of
every file in a packaged build -- both UTF-8 and UTF-16LE, because a Windows
binary holds both -- returns exactly three other things that look like one and
none of them is yours: Flutter's own engine build path, baked into the
prebuilt `flutter_windows.dll` upstream; `C:\fakepath`, a web-platform
constant inside the same DLL; and the GOG Galaxy database location, which this
code holds on purpose. No credential of any shape is in it at all -- the
`client_secret` that turns up in the snapshot's symbol table is the name of an
OAuth form field, never a value.

So the zip a reader downloads is the one the Windows runner built
(`.github/workflows/release.yml`), where that string names a throwaway
workspace and discloses nothing about anyone.

### Do not delete `app\build\` by hand — use `flutter clean`

Clearing the build output by hand while leaving `app\.dart_tool\` in place is
the obvious reflex and it breaks every later build, debug and release alike.
The build compiles everything successfully and then dies at the INSTALL
project:

```
error MSB3073: "...\cmake.exe" -DBUILD_TYPE=Debug -P cmake_install.cmake [...\app\build\windows\x64\INSTALL.vcxproj]
```

Nothing in that names the cause. It is visible only by running that same
cmake line by hand from `app\build\windows\x64`:

```
CMake Error at cmake_install.cmake:231 (file):
  file INSTALL cannot find
  ".../app/build/native_assets/windows": No error.
```

**The cause: the incremental cache in `.dart_tool\flutter_build` outlived the
directory it describes in `build\`.** The `install_code_assets` stamp there
still validates, so the step that creates `build\native_assets\windows` is
skipped, while CMake's install step still requires that directory to exist.
`flutter pub get` does not clear the stamp and does not help.

The fix:

```
cd app
flutter clean
flutter pub get
flutter build windows --debug
```

`flutter clean` removes `build\` and `.dart_tool\` together, which is why it
works where deleting `build\` alone does not.

This is **not** a fresh-clone problem — a genuinely cold tree builds fine (the
table above), so there is no reason to run `flutter clean` after cloning.

As with the ATL error above, the MSBuild wrapper text is localized; the tokens
that survive translation are `MSB3073`, `cmake_install.cmake`,
`INSTALL.vcxproj` and `native_assets`.
