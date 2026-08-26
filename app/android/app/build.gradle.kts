import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing (T-0398). The Android debug key is public and identical in
// every Flutter checkout, so an apk signed with it can be replaced by anybody
// and is accepted by no store. There is deliberately NO fallback to it: with
// key.properties absent or incomplete a release build FAILS, below. The
// fallback is what let `flutter create`'s TODO survive as far as a shipped
// apk -- a scaffold that silently works is one nobody revisits.
//
// key.properties and the keystore it names are gitignored and stay out of this
// repository; key.properties.example lists the keys it must hold. Debug and
// profile builds never read any of it.
val keyPropertiesFile = rootProject.file("key.properties")
val keyProperties: Properties? =
    if (keyPropertiesFile.isFile) {
        Properties().apply { keyPropertiesFile.inputStream().use { load(it) } }
    } else {
        null
    }
val blankKeys =
    listOf("storeFile", "storePassword", "keyAlias", "keyPassword")
        .filter { keyProperties?.getProperty(it).orEmpty().isBlank() }
val namedStore = keyProperties?.getProperty("storeFile").orEmpty().trim()
val resolvedStore = if (namedStore.isEmpty()) null else file(namedStore)

// Null once release signing is configured; otherwise what is wrong with it.
val signingProblem: String? =
    when {
        keyProperties == null ->
            "app/android/key.properties does not exist."
        blankKeys.isNotEmpty() ->
            "app/android/key.properties leaves ${blankKeys.joinToString(", ")} empty."
        resolvedStore?.isFile != true ->
            "storeFile in app/android/key.properties names no file: $resolvedStore"
        else -> null
    }

// The `android { }` accessor below is deprecated and AGP 10 removes it. It
// stays because the replacement needs android.newDsl=true, which the Flutter
// Gradle Plugin cannot be applied under -- gradle.properties says what fails
// (T-0399).
android {
    namespace = "io.github.shinkatana0.shelfscan"
    // Not flutter.compileSdkVersion: flutter_plugin_android_lifecycle, which
    // file_picker pulls in, requires its dependents to compile against 36 or
    // later, and the default resolved to 34 -- `checkDebugAarMetadata` fails
    // with that comparison spelled out (2026-08-23).
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // The release identity, and it is permanent: changing it after a
        // publish makes a different application. It matches the handle the
        // Windows Runner.rc carries as CompanyName and the repository the
        // project is published from (T-0194 is about losing exactly this to a
        // regenerated folder).
        applicationId = "io.github.shinkatana0.shelfscan"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (signingProblem == null) {
            create("release") {
                val configured = keyProperties!!
                storeFile = resolvedStore
                storePassword = configured.getProperty("storePassword")
                keyAlias = configured.getProperty("keyAlias")
                keyPassword = configured.getProperty("keyPassword")
                configured.getProperty("storeType")?.takeIf { it.isNotBlank() }
                    ?.let { storeType = it }
            }
        }
    }

    buildTypes {
        release {
            // findByName, never getByName("debug"): where there is no release
            // config the check below has already failed the build, so no path
            // through here signs a release with the debug key.
            signingConfig = signingConfigs.findByName("release")
        }
    }
}

if (signingProblem != null) {
    val refusal =
        """
        |Release signing is not configured, and this build will NOT fall back
        |to the debug key.
        |
        |  $signingProblem
        |
        |The Android debug key is public and identical in every Flutter
        |checkout: an apk signed with it can be replaced by anybody and is
        |accepted by no store. Failing here is the point -- a fallback ships
        |that apk without ever saying so.
        |
        |To configure release signing:
        |
        |  1. Create a keystore OUTSIDE this repository, using keytool from
        |     your JDK's bin directory (it is not on PATH):
        |
        |       keytool -genkeypair -v -keystore <path outside the repo>/<name>.jks \
        |         -storetype JKS -keyalg RSA -keysize 2048 -validity 10000 \
        |         -alias <alias>
        |
        |  2. Copy app/android/key.properties.example to
        |     app/android/key.properties and fill in storeFile, storePassword,
        |     keyAlias and keyPassword.
        |
        |  3. Back the keystore up. An installed Android app can only be
        |     updated by an artifact signed with the same key.
        |
        |Both files are gitignored; keep them and the keystore out of version
        |control. See doc/android-build.md, "Signing the release build".
        |
        |Debug and profile builds need none of this: flutter run,
        |flutter build apk --debug and flutter build apk --profile all work
        |with no key.properties at all.
        """.trimMargin()

    // The refusal is bound to the task graph, not to the buildType: it has to
    // fire for a release build and for nothing else, and `this` here is the
    // graph the Kotlin DSL hands an Action.
    gradle.taskGraph.whenReady {
        val wantsRelease =
            allTasks.any {
                it.path.startsWith(":app:") && it.name.contains("Release")
            }
        if (wantsRelease) {
            throw GradleException(refusal)
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
