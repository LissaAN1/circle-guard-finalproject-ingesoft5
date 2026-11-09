package com.circleguard.form.integration;

import com.circleguard.form.model.HealthSurvey;
import com.circleguard.form.model.Question;
import com.circleguard.form.model.QuestionType;
import com.circleguard.form.model.Questionnaire;
import com.circleguard.form.model.ValidationStatus;
import com.circleguard.form.repository.HealthSurveyRepository;
import com.circleguard.form.repository.QuestionnaireRepository;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.apache.kafka.clients.consumer.ConsumerConfig;
import org.apache.kafka.clients.consumer.ConsumerRecord;
import org.apache.kafka.clients.consumer.KafkaConsumer;
import org.apache.kafka.common.serialization.StringDeserializer;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Tag;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.web.client.TestRestTemplate;
import org.springframework.http.ResponseEntity;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.testcontainers.containers.KafkaContainer;
import org.testcontainers.containers.PostgreSQLContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;
import org.testcontainers.utility.DockerImageName;

import java.time.Duration;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Properties;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * HU-06 - Integracion de form-service con PostgreSQL y Kafka reales (sin mocks
 * de infraestructura).
 *
 * Valida el lado productor del contrato que consume promotion-service:
 * POST /api/v1/surveys -> fila en PostgreSQL (JSONB) + evento
 * "survey.submitted"
 * POST /api/v1/certificates/{id}/validate -> estado en PostgreSQL + evento
 * "certificate.validated"
 *
 * Los eventos se leen como JSON crudo desde el broker, es decir, tal como
 * viajan por el cable.
 * Se ejecuta con: ./gradlew :services:circleguard-form-service:integrationTest
 */
@Tag("integration")
@Testcontainers
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
class SurveyPublishingIntegrationTest {

    private static final String TOPIC_SURVEY_SUBMITTED = "survey.submitted";
    private static final String TOPIC_CERTIFICATE_VALIDATED = "certificate.validated";

    @Container
    static final PostgreSQLContainer<?> POSTGRES = new PostgreSQLContainer<>("postgres:16-alpine");

    @Container
    static final KafkaContainer KAFKA = new KafkaContainer(DockerImageName.parse("confluentinc/cp-kafka:7.6.0"))
            .withKraft() // sin ZooKeeper: un proceso menos en el agente de CI
            .withEnv("KAFKA_HEAP_OPTS", "-Xms128m -Xmx384m");

    @DynamicPropertySource
    static void infrastructure(DynamicPropertyRegistry registry) {
        registry.add("spring.datasource.url", POSTGRES::getJdbcUrl);
        registry.add("spring.datasource.username", POSTGRES::getUsername);
        registry.add("spring.datasource.password", POSTGRES::getPassword);
        registry.add("spring.datasource.driver-class-name", () -> "org.postgresql.Driver");
        registry.add("spring.jpa.hibernate.ddl-auto", () -> "create-drop");
        // Hibernate usa H2Dialect en test/application.yml; sobrescribir aqui para que
        // DDL generado sea compatible con el contenedor PostgreSQL.
        registry.add("spring.jpa.database-platform", () -> "org.hibernate.dialect.PostgreSQLDialect");
        // Permite carga lazy de colecciones fuera del scope de transaccion (p.ej. serializacion
        // de respuesta HTTP despues del commit de @Transactional en submitSurvey).
        registry.add("spring.jpa.properties.hibernate.enable_lazy_load_no_trans", () -> "true");
        // Solo se sobreescribe el broker. Los serializadores son los de
        // application.yml: si faltan,
        // esta prueba debe fallar porque el servicio tampoco funcionaria en produccion.
        registry.add("spring.kafka.bootstrap-servers", KAFKA::getBootstrapServers);
    }

    @Autowired
    private TestRestTemplate rest;
    @Autowired
    private QuestionnaireRepository questionnaireRepository;
    @Autowired
    private HealthSurveyRepository surveyRepository;
    @Autowired
    private ObjectMapper mapper;

    private UUID feverQuestionId;

    @BeforeEach
    void seedActiveQuestionnaire() {
        questionnaireRepository.deleteAll();

        Questionnaire questionnaire = Questionnaire.builder()
                .title("Cuestionario diario")
                .version(1)
                .isActive(true)
                .build();
        Question fever = Question.builder()
                .questionnaire(questionnaire)
                .text("Do you have fever?") // SymptomMapper busca "fever", "cough" o "breathing"
                .type(QuestionType.YES_NO)
                .orderIndex(0)
                .build();
        questionnaire.setQuestions(new ArrayList<>(List.of(fever)));

        feverQuestionId = questionnaireRepository.save(questionnaire).getQuestions().get(0).getId();
    }

    @Test
    void surveyWithSymptoms_isPersistedInPostgresAndPublishedToKafka() throws Exception {
        UUID user = UUID.randomUUID();

        ResponseEntity<Map> response = postSurvey(user, "YES", null);

        assertThat(response.getStatusCode().is2xxSuccessful()).isTrue();
        UUID surveyId = UUID.fromString((String) response.getBody().get("id"));

        HealthSurvey stored = surveyRepository.findById(surveyId).orElseThrow();
        assertThat(stored.getAnonymousId()).isEqualTo(user);
        assertThat(stored.getHasFever()).isTrue();
        // Verifica el mapeo JSONB real, que H2 no reproduce.
        assertThat(stored.getResponses()).containsEntry(feverQuestionId.toString(), "YES");

        JsonNode event = awaitEvent(TOPIC_SURVEY_SUBMITTED, user.toString());
        assertThat(event.get("anonymousId").asText()).isEqualTo(user.toString());
        assertThat(event.get("hasSymptoms").asBoolean()).isTrue();
        assertThat(event.get("timestamp").asLong()).isPositive();
    }

    @Test
    void surveyWithoutSymptoms_publishesEventWithHasSymptomsFalse() throws Exception {
        UUID user = UUID.randomUUID();

        ResponseEntity<Map> response = postSurvey(user, "NO", null);

        assertThat(response.getStatusCode().is2xxSuccessful()).isTrue();
        UUID surveyId = UUID.fromString((String) response.getBody().get("id"));
        assertThat(surveyRepository.findById(surveyId).orElseThrow().getHasFever()).isFalse();

        JsonNode event = awaitEvent(TOPIC_SURVEY_SUBMITTED, user.toString());
        assertThat(event.get("hasSymptoms").asBoolean()).isFalse();
    }

    @Test
    void approvedCertificate_updatesPostgresAndPublishesCertificateValidated() throws Exception {
        UUID user = UUID.randomUUID();
        UUID admin = UUID.randomUUID();

        ResponseEntity<Map> submitted = postSurvey(user, "YES", "certificado.pdf");
        UUID surveyId = UUID.fromString((String) submitted.getBody().get("id"));
        assertThat(surveyRepository.findById(surveyId).orElseThrow().getValidationStatus())
                .isEqualTo(ValidationStatus.PENDING);

        ResponseEntity<Void> validated = rest.postForEntity(
                "/api/v1/certificates/{id}/validate?status=APPROVED&adminId={admin}",
                null, Void.class, surveyId, admin);
        assertThat(validated.getStatusCode().is2xxSuccessful()).isTrue();

        HealthSurvey stored = surveyRepository.findById(surveyId).orElseThrow();
        assertThat(stored.getValidationStatus()).isEqualTo(ValidationStatus.APPROVED);
        assertThat(stored.getValidatedBy()).isEqualTo(admin);

        JsonNode event = awaitEvent(TOPIC_CERTIFICATE_VALIDATED, user.toString());
        assertThat(event.get("anonymousId").asText()).isEqualTo(user.toString());
        assertThat(event.get("status").asText()).isEqualTo("APPROVED");
        assertThat(event.get("adminId").asText()).isEqualTo(admin.toString());
    }

    // ------------------------------------------------------------------ helpers

    private ResponseEntity<Map> postSurvey(UUID anonymousId, String answer, String attachmentPath) {
        Map<String, Object> body = new HashMap<>();
        body.put("anonymousId", anonymousId.toString());
        body.put("responses", Map.of(feverQuestionId.toString(), answer));
        if (attachmentPath != null) {
            body.put("attachmentPath", attachmentPath);
        }
        return rest.postForEntity("/api/v1/surveys", body, Map.class);
    }

    /**
     * Lee el topic desde el inicio con un consumidor propio y devuelve el primer
     * JSON con esa clave.
     */
    private JsonNode awaitEvent(String topic, String key) throws Exception {
        Properties props = new Properties();
        props.put(ConsumerConfig.BOOTSTRAP_SERVERS_CONFIG, KAFKA.getBootstrapServers());
        props.put(ConsumerConfig.GROUP_ID_CONFIG, "form-it-" + UUID.randomUUID());
        props.put(ConsumerConfig.AUTO_OFFSET_RESET_CONFIG, "earliest");
        props.put(ConsumerConfig.KEY_DESERIALIZER_CLASS_CONFIG, StringDeserializer.class.getName());
        props.put(ConsumerConfig.VALUE_DESERIALIZER_CLASS_CONFIG, StringDeserializer.class.getName());

        try (KafkaConsumer<String, String> consumer = new KafkaConsumer<>(props)) {
            consumer.subscribe(List.of(topic));
            long deadline = System.currentTimeMillis() + 30_000;
            while (System.currentTimeMillis() < deadline) {
                for (ConsumerRecord<String, String> record : consumer.poll(Duration.ofMillis(500))) {
                    if (key.equals(record.key())) {
                        return mapper.readTree(record.value());
                    }
                }
            }
        }
        throw new AssertionError("No llego ningun evento a '" + topic + "' con clave " + key + " en 30 s");
    }
}