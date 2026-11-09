package com.circleguard.promotion.integration;

import com.circleguard.promotion.model.graph.UserNode;
import com.circleguard.promotion.repository.graph.UserNodeRepository;
import org.apache.kafka.clients.producer.ProducerConfig;
import org.apache.kafka.common.serialization.StringSerializer;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Tag;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.kafka.core.DefaultKafkaProducerFactory;
import org.springframework.kafka.core.KafkaTemplate;
import org.springframework.kafka.support.serializer.JsonSerializer;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.testcontainers.containers.GenericContainer;
import org.testcontainers.containers.KafkaContainer;
import org.testcontainers.containers.Neo4jContainer;
import org.testcontainers.containers.PostgreSQLContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;
import org.testcontainers.utility.DockerImageName;

import java.util.Map;
import java.util.UUID;
import java.util.concurrent.TimeUnit;

import static org.assertj.core.api.Assertions.assertThat;
import static org.awaitility.Awaitility.await;

/**
 * HU-06 - Integracion de promotion-service con Kafka, Neo4j y Redis reales (sin mocks de infraestructura).
 *
 * Los eventos se publican con el mismo serializador y la misma forma de mensaje que usa form-service
 * (KafkaTemplate + JsonSerializer + Map.of), de modo que el consumidor real (SurveyListener) recibe
 * el contrato tal como lo emite form. El efecto se verifica en Neo4j (estado del nodo) y en Redis
 * (clave user:status:{id}, la que lee el gateway).
 *
 * Se ejecuta con: ./gradlew :services:circleguard-promotion-service:integrationTest
 */
@Tag("integration")
@Testcontainers
@SpringBootTest
class SurveyEventsIntegrationTest {

    private static final String TOPIC_SURVEY_SUBMITTED = "survey.submitted";
    private static final String TOPIC_CERTIFICATE_VALIDATED = "certificate.validated";
    private static final String STATUS_KEY_PREFIX = "user:status:";

    // Misma imagen que las pruebas Testcontainers existentes de promotion (se reutiliza la capa en cache).
    @Container
    static final Neo4jContainer<?> NEO4J = new Neo4jContainer<>("neo4j:5.12.0")
            .withAdminPassword("password")
            .withEnv("NEO4J_server_memory_heap_initial__size", "256m")
            .withEnv("NEO4J_server_memory_heap_max__size", "512m")
            .withEnv("NEO4J_server_memory_pagecache_size", "128m");

    // application.yml de promotion usa PostgreSQL con Flyway: sin este contenedor el contexto intenta
    // conectarse a localhost:5432 y no arranca. Flyway aplica las migraciones reales sobre una base vacia.
    @Container
    static final PostgreSQLContainer<?> POSTGRES = new PostgreSQLContainer<>("postgres:16-alpine");

    @Container
    static final GenericContainer<?> REDIS = new GenericContainer<>("redis:7.2.1")
            .withExposedPorts(6379);

    @Container
    static final KafkaContainer KAFKA = new KafkaContainer(DockerImageName.parse("confluentinc/cp-kafka:7.6.0"))
            .withKraft()
            .withEnv("KAFKA_HEAP_OPTS", "-Xms128m -Xmx384m");

    @DynamicPropertySource
    static void infrastructure(DynamicPropertyRegistry registry) {
        registry.add("spring.datasource.url", POSTGRES::getJdbcUrl);
        registry.add("spring.datasource.username", POSTGRES::getUsername);
        registry.add("spring.datasource.password", POSTGRES::getPassword);
        registry.add("spring.datasource.driver-class-name", () -> "org.postgresql.Driver");
        // Re-enable Flyway so the real migrations run on the test container and all tables exist.
        // The test application.yml disables Flyway to keep unit tests fast; integration tests need the schema.
        registry.add("spring.flyway.enabled", () -> "true");
        registry.add("spring.flyway.url", POSTGRES::getJdbcUrl);
        registry.add("spring.flyway.user", POSTGRES::getUsername);
        registry.add("spring.flyway.password", POSTGRES::getPassword);
        // En produccion el secreto llega por la variable JWT_SECRET; su valor por defecto es vacio y
        // jjwt rechaza claves de menos de 256 bits. Este valor solo existe dentro de la prueba.
        registry.add("jwt.secret", () -> "integration-test-secret-key-at-least-32-bytes-long");

        registry.add("spring.neo4j.uri", NEO4J::getBoltUrl);
        registry.add("spring.neo4j.authentication.username", () -> "neo4j");
        registry.add("spring.neo4j.authentication.password", () -> "password");
        registry.add("spring.data.redis.host", REDIS::getHost);
        registry.add("spring.data.redis.port", REDIS::getFirstMappedPort);
        registry.add("spring.kafka.bootstrap-servers", KAFKA::getBootstrapServers);
        // Si el evento llega antes de que el listener tenga particiones asignadas, no se pierde.
        registry.add("spring.kafka.consumer.auto-offset-reset", () -> "earliest");
        // Sin headers __TypeId__ el deserializador necesita un tipo concreto para convertir el
        // JSON plano. LinkedHashMap es el tipo natural de un Map<String,Object> en Jackson.
        registry.add("spring.kafka.consumer.properties.spring.json.value.default.type",
                () -> "java.util.HashMap");
    }

    @Autowired
    private UserNodeRepository userRepository;
    @Autowired
    private StringRedisTemplate redis;

    // El KafkaTemplate interno de HealthStatusService no forma parte de lo que
    // verifican estos tests (que prueban Neo4j y Redis). Mockearlo evita que
    // cualquier excepcion del productor interno sea tragada por el try-catch de
    // SurveyListener e impida la actualizacion de estado.
    @org.springframework.boot.test.mock.mockito.MockBean
    private org.springframework.kafka.core.KafkaTemplate<String, Object> kafkaTemplate;

    private KafkaTemplate<String, Object> formLikeProducer;

    @BeforeEach
    void createProducer() {
        Map<String, Object> config = Map.of(
                ProducerConfig.BOOTSTRAP_SERVERS_CONFIG, KAFKA.getBootstrapServers(),
                ProducerConfig.KEY_SERIALIZER_CLASS_CONFIG, StringSerializer.class,
                ProducerConfig.VALUE_SERIALIZER_CLASS_CONFIG, JsonSerializer.class,
                // Map.of() devuelve ImmutableCollections$MapN, que Jackson no puede
                // deserializar si el header __TypeId__ apunta a esa clase interna.
                // Sin headers el consumer recibe JSON plano y lo deserializa como LinkedHashMap,
                // que es el tipo esperado por el listener (Map<String, Object>).
                JsonSerializer.ADD_TYPE_INFO_HEADERS, false);
        formLikeProducer = new KafkaTemplate<>(new DefaultKafkaProducerFactory<>(config));
    }

    @AfterEach
    void closeProducer() {
        formLikeProducer.destroy();
    }

    @Test
    void surveyWithSymptoms_promotesUserToSuspect_inNeo4jAndRedis() {
        String user = newUser("ACTIVE");

        formLikeProducer.send(TOPIC_SURVEY_SUBMITTED, user, surveyEvent(user, true));

        await().atMost(30, TimeUnit.SECONDS).untilAsserted(() -> {
            assertThat(statusInNeo4j(user)).isEqualTo("SUSPECT");
            assertThat(redis.opsForValue().get(STATUS_KEY_PREFIX + user)).isEqualTo("SUSPECT");
        });
    }

    @Test
    void surveyWithoutSymptoms_leavesUserActive() {
        String healthy = newUser("ACTIVE");
        String sick = newUser("ACTIVE");

        // Misma clave => misma particion => se consumen en orden. Cuando 'sick' ya fue procesado,
        // el evento de 'healthy' tambien lo fue, y se puede afirmar que no cambio nada.
        formLikeProducer.send(TOPIC_SURVEY_SUBMITTED, "orden", surveyEvent(healthy, false));
        formLikeProducer.send(TOPIC_SURVEY_SUBMITTED, "orden", surveyEvent(sick, true));

        await().atMost(30, TimeUnit.SECONDS)
                .untilAsserted(() -> assertThat(statusInNeo4j(sick)).isEqualTo("SUSPECT"));

        assertThat(statusInNeo4j(healthy)).isEqualTo("ACTIVE");
        assertThat(redis.opsForValue().get(STATUS_KEY_PREFIX + healthy)).isNull();
    }

    /**
     * Se siembra el nodo SUSPECT sin statusUpdatedAt para ejercitar solo el camino Kafka -> listener ->
     * servicio -> Neo4j/Redis. La ventana de aislamiento obligatorio (FenceException) no forma parte de
     * esta prueba; ver nota sobre HealthStatusService.checkFenceWindow en la entrega de la HU-06.
     */
    @Test
    void approvedCertificate_restoresUserToActive_inNeo4jAndRedis() {
        String user = newUser("SUSPECT");

        formLikeProducer.send(TOPIC_CERTIFICATE_VALIDATED, user, Map.of(
                "anonymousId", user,
                "status", "APPROVED",
                "adminId", UUID.randomUUID().toString(),
                "timestamp", System.currentTimeMillis()));

        await().atMost(30, TimeUnit.SECONDS).untilAsserted(() -> {
            assertThat(statusInNeo4j(user)).isEqualTo("ACTIVE");
            assertThat(redis.opsForValue().get(STATUS_KEY_PREFIX + user)).isEqualTo("ACTIVE");
        });
    }

    // ------------------------------------------------------------------ helpers

    private String newUser(String status) {
        String id = UUID.randomUUID().toString();
        userRepository.save(UserNode.builder().anonymousId(id).status(status).build());
        return id;
    }

    private String statusInNeo4j(String anonymousId) {
        return userRepository.findById(anonymousId).orElseThrow().getStatus();
    }

    /** Misma forma que HealthSurveyService.submitSurvey en form-service. */
    private static Map<String, Object> surveyEvent(String anonymousId, boolean hasSymptoms) {
        return Map.of(
                "anonymousId", anonymousId,
                "hasSymptoms", hasSymptoms,
                "timestamp", System.currentTimeMillis());
    }
}