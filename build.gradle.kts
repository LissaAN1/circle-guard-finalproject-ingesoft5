plugins {
    id("org.springframework.boot") version "3.2.4" apply false
    id("io.spring.dependency-management") version "1.1.4" apply false
    kotlin("jvm") version "1.9.24" apply false
    kotlin("plugin.spring") version "1.9.24" apply false
    kotlin("plugin.jpa") version "1.9.24" apply false
}

allprojects {
    group = "com.circleguard"
    version = "1.0.0-SNAPSHOT"

    repositories {
        mavenCentral()
    }
}

subprojects {
    apply(plugin = "java")
    apply(plugin = "org.jetbrains.kotlin.jvm")
    apply(plugin = "jacoco")
    extensions.configure<JavaPluginExtension> {
        toolchain {
            languageVersion.set(JavaLanguageVersion.of(21))
        }
    }

    dependencies {
        "implementation"(platform("org.springframework.boot:spring-boot-dependencies:3.2.4"))
        "testImplementation"(platform("org.springframework.boot:spring-boot-dependencies:3.2.4"))
        "compileOnly"("org.projectlombok:lombok")
        "annotationProcessor"("org.projectlombok:lombok")
        "testCompileOnly"("org.projectlombok:lombok")
        "testAnnotationProcessor"("org.projectlombok:lombok")
        "implementation"("org.jetbrains.kotlin:kotlin-reflect")
        "testImplementation"("org.springframework.boot:spring-boot-starter-test")
        "testRuntimeOnly"("com.h2database:h2")
    }

    tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile> {
        kotlinOptions {
            freeCompilerArgs = listOf("-Xjsr305=strict")
            jvmTarget = "21"
        }
    }

    // HU-05: line coverage for every module. SonarQube reads the XML report and enforces the 60 % gate
    // (ci/units.conf marks the units that are gated); the HTML report is published by Jenkins.
    extensions.configure<JacocoPluginExtension> {
        toolVersion = "0.8.12"
    }

    tasks.withType<Test> {
        // Tests tagged "integration" need Docker (Testcontainers); they belong to HU-06 and run with
        // ./gradlew integrationTest, so the unit-test gate (test + coverage) never depends on Docker.
        useJUnitPlatform { excludeTags("integration") }
        // HU-05: the main application.yml files leave every secret empty (no secrets in Git), so the
        // Spring test contexts need throwaway values. They are test-only and never reach an image.
        environment("JWT_SECRET", "test-only-jwt-secret-key-with-at-least-32-bytes")
        environment("QR_SECRET", "test-only-qr-secret-key-with-at-least-32-bytes")
        finalizedBy("jacocoTestReport")
    }

    tasks.register<Test>("integrationTest") {
        description = "Runs the tests tagged integration (Testcontainers; Docker required)."
        group = "verification"
        val unitTests = tasks.named<Test>("test").get()
        testClassesDirs = unitTests.testClassesDirs
        classpath = unitTests.classpath
        useJUnitPlatform { includeTags("integration") }
        // Must not clash with the coverage data of the unit-test run
        extensions.configure<JacocoTaskExtension> { isEnabled = false }
    }

    // No dependsOn(test): a finalizer that depends on its failed finalized task would be skipped, and the
    // coverage report is most needed exactly when a test fails.
    tasks.withType<JacocoReport> {
        reports {
            xml.required.set(true)
            html.required.set(true)
        }
    tasks.named<Test>("test") {
        useJUnitPlatform { excludeTags("integration") }
    }

    val integrationTest by tasks.registering(Test::class) {
        group = "verification"
        description = "Pruebas de integracion con Testcontainers (requiere Docker)."
        val testSourceSet = project.extensions.getByType<SourceSetContainer>()["test"]
        testClassesDirs = testSourceSet.output.classesDirs
        classpath = testSourceSet.runtimeClasspath
        useJUnitPlatform { includeTags("integration") }
        shouldRunAfter(tasks.named("test"))
        maxParallelForks = 1
    }
}
