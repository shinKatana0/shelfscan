allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)

    // Plugin subprojects take their compileSdk from the Flutter SDK, not from
    // app/build.gradle.kts, so raising it there fixes the application and
    // leaves every plugin on the old one. Measured 2026-08-23: :file_picker
    // compiled against android-34 while :flutter_plugin_android_lifecycle,
    // which it pulls in, requires 36 or later -- checkDebugAarMetadata fails
    // naming both. Raised here rather than per plugin, because the next one
    // to want 36 would otherwise be diagnosed from scratch.
    //
    // It must live in THIS block: the `evaluationDependsOn(":app")` below
    // evaluates the projects, and an afterEvaluate registered after that
    // fails with "Cannot run Project.afterEvaluate when the project is
    // already evaluated".
    afterEvaluate {
        extensions.findByName("android")?.let { ext ->
            ext.javaClass.methods.firstOrNull {
                it.name == "setCompileSdkVersion" && it.parameterTypes.size == 1 &&
                    it.parameterTypes[0] == Int::class.javaPrimitiveType
            }?.invoke(ext, 36)
        }
    }
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
