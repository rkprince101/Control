plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.control"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.control"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
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

    lint {
        // local.properties is written by the Flutter tool with unescaped
        // Windows paths. It is machine-local, is not checked in, and is not
        // ours to reformat, so the check is off rather than the whole build
        // failing on it.
        disable += "PropertyEscape"
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
