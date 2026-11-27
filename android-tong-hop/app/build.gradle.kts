plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "vn.hoitu.tonghop"
    compileSdk = 34

    defaultConfig {
        applicationId = "vn.hoitu.tonghop"
        minSdk = 24 // Android 7 trở lên (cần cho thao tác chạm của Trợ năng)
        targetSdk = 34
        versionCode = 7
        versionName = "1.6"
    }

    buildTypes {
        release {
            isMinifyEnabled = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"))
            signingConfig = signingConfigs.getByName("debug")
        }
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions {
        jvmTarget = "17"
    }
    testOptions {
        unitTests.isReturnDefaultValues = true
    }
}

dependencies {
    implementation(project(":vq"))
    implementation(project(":bs"))
    implementation(project(":cq"))
    implementation("com.google.mlkit:text-recognition:16.0.1") // đọc chữ trên máy, không cần mạng
}
