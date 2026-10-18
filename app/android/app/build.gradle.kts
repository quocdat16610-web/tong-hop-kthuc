plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "io.github.quocdat16610.so_tay_dsa"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "io.github.quocdat16610.so_tay_dsa"
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

    // Ký APK bằng MỘT khoá cố định để bản mới cài đè lên bản cũ (giữ nguyên dữ liệu người dùng).
    // Có thể thay bằng khoá riêng qua biến môi trường (GitHub Secrets) ANDROID_KEYSTORE_FILE / ANDROID_KEYSTORE_PASSWORD.
    signingConfigs {
        create("release") {
            val envFile = System.getenv("ANDROID_KEYSTORE_FILE")
            storeFile = if (!envFile.isNullOrEmpty()) file(envFile) else file("sotaydsa-release.jks")
            storePassword = System.getenv("ANDROID_KEYSTORE_PASSWORD")?.takeIf { it.isNotEmpty() } ?: "sotaydsa-public"
            keyAlias = System.getenv("ANDROID_KEY_ALIAS")?.takeIf { it.isNotEmpty() } ?: "sotaydsa"
            keyPassword = System.getenv("ANDROID_KEY_PASSWORD")?.takeIf { it.isNotEmpty() } ?: storePassword
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
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
