group = "ai.pushpilot.pushpilot_flutter"
version = "2.1.0"

buildscript {
    val kotlinVersion = "2.4.0"
    repositories {
        google()
        mavenCentral()
    }

    dependencies {
        classpath("com.android.tools.build:gradle:9.1.0")
        classpath("org.jetbrains.kotlin:kotlin-gradle-plugin:$kotlinVersion")
    }
}

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

plugins {
    id("com.android.library")
}

android {
    namespace = "ai.pushpilot.pushpilot_flutter"

    compileSdk = 36

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    sourceSets {
        getByName("main") {
            java.srcDirs("src/main/kotlin")
        }
    }

    defaultConfig {
        // The native SDK supports API 23; Flutter itself needs 24.
        minSdk = 24
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    // Native PushPilot Android SDK. Until it is on Maven Central, run `./gradlew :sdk:publishToMavenLocal`
    // in pushpilot-android and add mavenLocal() to the app's repositories (see README).
    implementation("ai.pushpilot:sdk:2.1.0")
    testImplementation("junit:junit:4.13.2")
}
