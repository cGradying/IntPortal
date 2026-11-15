import org.jetbrains.kotlin.gradle.dsl.JvmTarget

plugins {
    id("com.android.library")
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "ph.intportal.camera"
    compileSdk = 36
    defaultConfig { minSdk = 24 }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_1_8
        targetCompatibility = JavaVersion.VERSION_1_8
    }
}

kotlin {
    compilerOptions { jvmTarget = JvmTarget.JVM_1_8 }
}

dependencies {
    implementation("androidx.core:core-ktx:1.9.0")
    implementation("androidx.exifinterface:exifinterface:1.3.7")
    implementation("com.fasterxml.jackson.core:jackson-databind:2.15.3")
    // Google Play services' ML Kit: the models (and their ~25 MB of native
    // code) stay out of the APK and download once, at install from Play or on
    // the first scan (see read()). Phones without Play services can't scan.
    implementation("com.google.android.gms:play-services-mlkit-text-recognition:19.0.1")
    implementation("com.google.android.gms:play-services-mlkit-barcode-scanning:18.3.1")
    implementation("com.google.android.gms:play-services-base:18.5.0")
    implementation(project(":tauri-android"))
}
