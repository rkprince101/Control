import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing reads android/key.properties, which is never committed (see
// key.properties.example). Without it a release build is signed with the debug
// key, so `flutter run --release` keeps working on a machine with no keystore.
val releaseSigning = Properties().apply {
    val file = rootProject.file("key.properties")
    if (file.exists()) file.inputStream().use { load(it) }
}

android {
    namespace = "com.rkprince.control"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // Permanent once published: Play, the accessibility grant and device
        // owner are all tied to it.
        applicationId = "com.rkprince.control"
        // Android 7.0. Everything the enforcement layer uses works here: usage
        // events are API 21, the step counter is 19, device admin is 21, and
        // every newer call is already behind a version check. Health Connect
        // will need 26 when it lands, and can gate itself at runtime rather
        // than costing every Android 7 user the whole app.
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (!releaseSigning.isEmpty) {
            create("release") {
                keyAlias = releaseSigning.getProperty("keyAlias")
                keyPassword = releaseSigning.getProperty("keyPassword")
                storeFile = rootProject.file(releaseSigning.getProperty("storeFile"))
                storePassword = releaseSigning.getProperty("storePassword")
            }
        }
    }

    lint {
        // local.properties is written by the Flutter tool with unescaped
        // Windows paths. It is machine-local, is not checked in, and is not
        // ours to reformat, so the check is off rather than the whole build
        // failing on it.
        disable += "PropertyEscape"
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.findByName("release")
                ?: signingConfigs.getByName("debug")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    // Pure-JVM tests for the tamper rules. They decide whether the Settings app
    // opens at all, so they are worth a real test target.
    testImplementation("junit:junit:4.13.2")
    // The android.jar used for unit tests stubs org.json and throws on every
    // call. The real implementation on the test classpath shadows the stub.
    testImplementation("org.json:json:20240303")
}

flutter {
    source = "../.."
}
