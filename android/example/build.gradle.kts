// A small test app for the SDK: type a mobile key, open the chat, try identify / reset. Built by CI as a debug APK.
plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "com.maurieai.chat.example"
    compileSdk = 35
    defaultConfig {
        applicationId = "com.maurieai.chat.example"
        minSdk = 24
        targetSdk = 35
        versionCode = 1
        versionName = "0.1.0"
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions { jvmTarget = "17" }
}

dependencies {
    implementation(project(":maurie-chat"))
    implementation("androidx.activity:activity-ktx:1.9.3")
}
