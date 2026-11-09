# Hallazgos técnicos

## Resueltos en la HU-05

- **dashboard:** las pruebas de `circleguard-dashboard-service` pasan (2 de 2); la unidad pasó de `report` a `enforce` en
  `ci/units.conf`.
- **auth, identity, form, promotion:** los contextos de Spring de prueba fallaban por configuración, no por el código:
  - secretos vacíos (`JWT_SECRET`, `QR_SECRET`): `build.gradle.kts` entrega valores de prueba a las tareas `test`;
  - auth: faltaba `spring.ldap.*` en el `application.yml` de prueba;
  - form: las pruebas intentaban conectarse a PostgreSQL y Flyway; ahora usan H2 en memoria;
  - promotion: `HealthStatusControllerTest` usaba `authorities` donde el controlador exige `hasRole`.
- **Pruebas con Testcontainers (promotion):** necesitan Docker, así que llevan `@Tag("integration")` y quedan fuera de
  `test`. Se ejecutan con `./gradlew integrationTest` (pertenecen a la HU-06).

## Cobertura de líneas (JaCoCo, mínimo 60 %)

| Servicio | Cobertura |
|----------|-----------|
| auth | 81 % |
| identity | 74 % |
| form | 84 % |
| promotion | 67 % |
| gateway | 81 % |

## Cliente web (mobile)

- El error de Babel (`.plugins is not a valid Plugin property`) ya no se reproduce con una instalación limpia
  (`npm ci`) con las versiones del `package-lock.json`.
- `hooks/useQrToken.test.ts` estaba desactualizado: el hook ahora recibe `anonymousId` y `authToken` y pide el token por
  HTTP, mientras la prueba esperaba un token síncrono. Se reescribió con `axios` simulado; las 8 pruebas del cliente
  pasan con `npm test`.

## Pendientes

- La unidad `web` sigue en `skip` en `ci/units.conf`: el pipeline todavía no ejecuta Jest. Ejecutar las pruebas del
  cliente en Jenkins (contenedor Node) queda para la HU-06/HU-07.
