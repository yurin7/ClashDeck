import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// 发布签名：android/key.properties 的 storeFile 指向一把固定 keystore。本机把 keystore
// 放仓库外（%USERPROFILE%\.clashdeck\，由 tool/setup_signing.ps1 生成），CI 由 Secrets
// 还原到临时目录；仓库里不保存任何签名材料。每次构建都用同一个 key，新包才能覆盖安装升级。
// 缺 key.properties 或它指向的 keystore 不存在时回退到 debug 签名（CI 每次新生成，
// 那种包签名不同，必须卸载才能重装）。
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
if (keystorePropertiesFile.exists()) {
    keystorePropertiesFile.inputStream().use { keystoreProperties.load(it) }
}
val releaseKeystorePath = keystoreProperties.getProperty("storeFile")
val releaseKeystoreFile = releaseKeystorePath?.let { file(it) }
val hasReleaseKeystore =
    keystorePropertiesFile.exists() &&
        releaseKeystoreFile != null &&
        releaseKeystoreFile.exists()

android {
    namespace = "dev.clashdeck"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "dev.clashdeck"
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

        // 注意：这里不要写 ndk { abiFilters } —— Flutter Gradle 插件在本文件之后
        // 用 -Ptarget-platform 覆盖它。只想打 64 位包时用：
        //   flutter build apk --target-platform android-arm64,android-x64
        // 目前只交叉编译了 arm64-v8a / x86_64 两个内核；缺内核的 ABI 上启动会
        // 走到 MihomoCore.start 的"找不到内核文件"分支并报错，不会崩。
    }

    signingConfigs {
        if (hasReleaseKeystore) {
            create("release") {
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
            }
        }
    }

    buildTypes {
        release {
            // 有固定 keystore 就用它，没有就退回 debug（能跑，但每次签名不同，装不上旧包）。
            signingConfig =
                if (hasReleaseKeystore) {
                    signingConfigs.getByName("release")
                } else {
                    signingConfigs.getByName("debug")
                }
        }
    }

    packaging {
        jniLibs {
            // libmihomo.so 是 Go 静态二进制，不是普通 NDK 产物：不能让 AGP 去 strip。
            keepDebugSymbols += "**/libmihomo.so"
            // 必须解压到 nativeLibraryDir，内核才有可执行权限（AGP 8+ 默认压缩进 APK）。
            useLegacyPackaging = true
        }
    }

    externalNativeBuild {
        cmake {
            // fork + execv 的小 shim：Java 的 ProcessBuilder 会关掉 TUN fd。
            path = file("src/main/cpp/CMakeLists.txt")
            version = "3.22.1"
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
