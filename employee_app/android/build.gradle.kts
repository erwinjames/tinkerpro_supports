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

    // Some Flutter plugins (e.g. file_picker) still compile against API 34
    // while a transitive dependency (flutter_plugin_android_lifecycle) now
    // demands 36, which fails the AAR metadata check. Force every Android
    // plugin module up to compileSdk 36. Reflection keeps this independent of
    // the AGP classpath in the root Kotlin DSL. Registered here (before the
    // evaluationDependsOn block below) so the hook lands before evaluation.
    afterEvaluate {
        val androidExt = project.extensions.findByName("android") ?: return@afterEvaluate
        try {
            androidExt.javaClass
                .getMethod("compileSdkVersion", Int::class.javaPrimitiveType)
                .invoke(androidExt, 36)
        } catch (_: Exception) {
            // Not an Android module, or an incompatible AGP — leave as-is.
        }
    }
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
