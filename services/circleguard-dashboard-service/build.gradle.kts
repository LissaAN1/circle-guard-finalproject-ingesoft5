plugins {
    id("org.springframework.boot")
    id("io.spring.dependency-management")
    kotlin("jvm")
    kotlin("plugin.spring")
    kotlin("plugin.jpa")
}

dependencies {
    implementation(platform("org.springframework.boot:spring-boot-dependencies:3.5.16"))
    testImplementation(platform("org.springframework.boot:spring-boot-dependencies:3.5.16"))

    implementation("org.springframework.boot:spring-boot-starter-web")
    // HU-14: Circuit Breaker + Retry on the calls to promotion-service (annotations need AOP).
    implementation("org.springframework.boot:spring-boot-starter-aop")
    implementation("io.github.resilience4j:resilience4j-spring-boot3:2.2.0")
    // HU-16: cache-aside of the promotion-service statistics in Redis.
    implementation("org.springframework.boot:spring-boot-starter-data-redis")
    implementation("org.springframework.boot:spring-boot-starter-data-jpa")
    implementation("org.flywaydb:flyway-core")
    runtimeOnly("org.postgresql:postgresql")
    testImplementation("org.springframework.boot:spring-boot-starter-test")
}
