package com.circleguard.promotion.service;

import com.circleguard.promotion.model.graph.CircleNode;
import com.circleguard.promotion.model.graph.UserNode;
import com.circleguard.promotion.repository.graph.CircleNodeRepository;
import com.circleguard.promotion.repository.graph.UserNodeRepository;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Tag;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.mock.mockito.MockBean;
import org.springframework.kafka.core.KafkaTemplate;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.testcontainers.containers.GenericContainer;
import org.testcontainers.containers.Neo4jContainer;
import org.testcontainers.containers.PostgreSQLContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;

import static org.assertj.core.api.Assertions.assertThat;

@SpringBootTest
@Tag("integration")
@Testcontainers
public class AdministrativeCorrectionTest {

    @Container
    static Neo4jContainer<?> neo4j = new Neo4jContainer<>("neo4j:5.12.0")
            .withAdminPassword("password");

    @Container
    @SuppressWarnings("resource")
    static GenericContainer<?> redis = new GenericContainer<>("redis:7.2.1")
            .withExposedPorts(6379);

    @Container
    static PostgreSQLContainer<?> postgres = new PostgreSQLContainer<>("postgres:16-alpine");

    @DynamicPropertySource
    static void properties(DynamicPropertyRegistry registry) {
        registry.add("spring.neo4j.uri", neo4j::getBoltUrl);
        registry.add("spring.neo4j.authentication.username", () -> "neo4j");
        registry.add("spring.neo4j.authentication.password", () -> "password");
        registry.add("spring.data.redis.host", redis::getHost);
        registry.add("spring.data.redis.port", redis::getFirstMappedPort);
        // updateStatus llama a systemSettingsRepository (JPA) que necesita PostgreSQL real.
        // test/application.yml tiene ddl-auto=none, Flyway crea el schema.
        registry.add("spring.datasource.url", postgres::getJdbcUrl);
        registry.add("spring.datasource.username", postgres::getUsername);
        registry.add("spring.datasource.password", postgres::getPassword);
        registry.add("spring.datasource.driver-class-name", () -> "org.postgresql.Driver");
        registry.add("spring.flyway.enabled", () -> "true");
        registry.add("spring.flyway.url", postgres::getJdbcUrl);
        registry.add("spring.flyway.user", postgres::getUsername);
        registry.add("spring.flyway.password", postgres::getPassword);
        // KafkaTemplate mockeado; evitar reintentos de conexion al broker inexistente.
        registry.add("spring.kafka.listener.auto-startup", () -> "false");
    }

    @Autowired
    private HealthStatusService statusService;

    @Autowired
    private CircleService circleService;

    @Autowired
    private UserNodeRepository userRepository;

    @Autowired
    private CircleNodeRepository circleRepository;

    @MockBean
    private KafkaTemplate<String, Object> kafkaTemplate;

    @BeforeEach
    void setup() {
        circleRepository.deleteAll();
        userRepository.deleteAll();
    }

    @Test
    void invalidateCircle_PreventsPropagation() {
        // 1. Setup: A -> Circle (Invalid) -> B
        UserNode a = UserNode.builder().anonymousId("A").status("ACTIVE").build();
        UserNode b = UserNode.builder().anonymousId("B").status("ACTIVE").build();
        userRepository.save(a);
        userRepository.save(b);

        CircleNode circle = circleService.createCircle("RiskGroup", "loc1");
        userRepository.recordEncounter("A", "B", System.currentTimeMillis(), "loc1"); // Backdoor encounter
        // Wait, I'll use the circle membership
        circleRepository.joinCircle("A", circle.getInviteCode());
        circleRepository.joinCircle("B", circle.getInviteCode());

        // Invalidate circle
        circleService.toggleCircleValidity(circle.getId());

        // 2. Action: Purge encounters to isolate circle test, then promote A
        userRepository.purgeStaleEncounters(System.currentTimeMillis() + 10000); 
        statusService.updateStatus("A", "CONFIRMED");

        // 3. Verify: B should NOT be affected through the invalid circle
        statusService.getCachedStatus("B");
        // Since circle is invalid, B remains ACTIVE (unless updateStatus is called)
        // Wait, updateStatus only returns affected. Let's check DB.
        assertThat(userRepository.findById("B").get().getStatus()).isEqualTo("ACTIVE");
    }

    @Test
    void forceFence_PromotesAllMembers() {
        // 1. Setup: A and B in Circle
        UserNode a = UserNode.builder().anonymousId("A").status("ACTIVE").build();
        UserNode b = UserNode.builder().anonymousId("B").status("ACTIVE").build();
        userRepository.save(a);
        userRepository.save(b);

        CircleNode circle = circleService.createCircle("Forced containment", "loc2");
        circleRepository.joinCircle("A", circle.getInviteCode());
        circleRepository.joinCircle("B", circle.getInviteCode());

        // 2. Action: Force fence
        circleService.forceFenceCircle(circle.getId());

        // 3. Verify: Both should be PROBABLE
        assertThat(userRepository.findById("A").get().getStatus()).isEqualTo("PROBABLE");
        assertThat(userRepository.findById("B").get().getStatus()).isEqualTo("PROBABLE");
    }
}
