plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.tinkerpro.employee_app"
    // Some plugins (flutter_plugin_android_lifecycle via file_picker) now
    // require compiling against API 36+; pin it instead of inheriting the
    // older flutter.compileSdkVersion.
    compileSdk = maxOf(36, flutter.compileSdkVersion)
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.tinkerpro.employee_app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // flutter_webrtc requires 23+; mobile_scanner requires 21+.
        minSdk = maxOf(23, flutter.minSdkVersion)
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
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

// Strip the desktop-only RustDesk binaries (~105 MB: a Linux AppImage + a
// Windows .exe) out of the Android APK. They're declared in pubspec's
// assets/rustdesk/ because the Windows/Linux desktop builds extract and run
// them for remote-desktop support — but that feature is hidden on mobile, so
// the phone never loads them and they're pure dead weight that makes the APK
// huge and slow to install.
//
// aapt's ignoreAssetsPattern can't reach files nested under flutter_assets/,
// so instead we physically delete them from the merged-assets output. Flutter's
// `copyFlutterAssets{Variant}` task is what copies flutter_assets into the
// merged dir (after mergeAssets), so we hook ITS doLast: the rustdesk files are
// removed right after they land and before `compress{Variant}Assets` snapshots
// its inputs — deleting any later (e.g. in compress's own doFirst) makes the
// compress worker fail on now-missing input files. Only the Android build is
// affected; the Windows/Linux desktop bundles keep the binaries.
tasks.whenTaskAdded {
    if (name.startsWith("copyFlutterAssets")) {
        doLast {
            delete(fileTree(layout.buildDirectory) {
                include("**/merge*Assets/**/assets/rustdesk/**")
                include("**/flutter_assets/assets/rustdesk/**")
            })
        }
    }
}
