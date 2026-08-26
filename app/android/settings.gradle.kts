pluginManagement {
    val flutterSdkPath =
        run {
            val properties = java.util.Properties()
            file("local.properties").inputStream().use { properties.load(it) }
            val flutterSdkPath = properties.getProperty("flutter.sdk")
            require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
            flutterSdkPath
        }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "9.1.0" apply false
    // Declared, never applied: with android.builtInKotlin=true nothing
    // applies it and AGP supplies Kotlin itself. It stays because that is
    // where built-in Kotlin reads the Kotlin version from -- delete the line
    // and the build falls to built-in Kotlin's own 2.2.10, which Flutter
    // refuses against its minimum of 2.2.20 (T-0399).
    id("org.jetbrains.kotlin.android") version "2.4.0" apply false
}

include(":app")
