# HU-05 — Quality gate con cobertura mínima

Extiende el pipeline de la HU-04: mide la cobertura con JaCoCo, la analiza en SonarQube y **bloquea** el
empaquetado si el quality gate falla.

## Criterios de aceptación

| # | Criterio | Implementación |
|---|----------|----------------|
| 1 | Cobertura de líneas ≥ 60 % en auth, identity, promotion, form y gateway | JaCoCo en todos los módulos (`build.gradle.kts`); gate `CircleGuard` en SonarQube con `coverage < 60` → falla |
| 2 | Si el quality gate falla, el pipeline falla y no se empaqueta | `cgAnalysis` ejecuta el scanner con `sonar.qualitygate.wait=true`; la etapa `Analysis` va antes de `Package` |
| 3 | Las pruebas que hoy fallan se corrigen | Ver «Pruebas corregidas» |
| 4 | El informe de cobertura se publica en Jenkins | `cgCoverage`: plugin JaCoCo (tendencia en la página del build) y HTML archivado |

## Cómo funciona

```
Build → Test (JUnit + JaCoCo) → Analysis (SonarQube, gate bloqueante) → Package → Publish
```

1. **JaCoCo** (`build.gradle.kts`): todos los módulos generan `build/reports/jacoco/test/` (XML y HTML) al terminar
   `test`, incluso si alguna prueba falla (`finalizedBy`).
2. **Test** (`cgTest` → `cgCoverage`): publica JUnit y la cobertura en Jenkins.
3. **Analysis** (`cgAnalysis`): para cada unidad modificada con `quality=gate` en `ci/units.conf` corre
   `sonar-scanner` con el XML de JaCoCo y espera el veredicto del servidor. Si el gate falla, el scanner termina
   con error → la etapa falla → `Package` y `Publish` no se ejecutan.
4. La etapa se activa cuando Jenkins conoce `SONAR_HOST_URL`. Sin él se omite (por ejemplo, un Jenkins sin SonarQube).

### Qué unidades pasan por el gate

`ci/units.conf` tiene una cuarta columna `quality`:

| Unidad | quality |
|--------|---------|
| auth, identity, promotion, form, gateway | `gate` |
| notification, file, dashboard, web | `none` |

Cambiar una unidad a `gate` no requiere tocar el pipeline.

## Despliegue

SonarQube (crea el gate `CircleGuard`, idempotente):

```bash
bash infra/bootstrap-sonarqube.sh
```

Jenkins (token de análisis y URL; el token se crea una vez en la EC2 de SonarQube y se lee desde allí, nunca se
escribe ni se imprime):

```bash
SONAR_HOST_URL=http://<ip-privada-sonarqube>:9000 bash infra/bootstrap-ci.sh
```

Requisitos: las EC2 de Jenkins y SonarQube encendidas (`infra/power.sh start jenkins sonarqube`) y tu IP permitida en
el SG `cicd`. El nodo de build debe alcanzar el puerto 9000 de SonarQube por la red privada de la VPC.

## Verificación

Offline (sin servidores):

```bash
python -m unittest discover -s ci/tests
python -m unittest discover -s infra/bootstrap/tests
```

En Jenkins:

1. Push a una rama con cambios en un servicio `gate`: la etapa **Analysis** debe terminar en verde y el build mostrar
   el gráfico de cobertura de JaCoCo.
2. Prueba negativa: subir temporalmente el umbral (`GATE_THRESHOLD` en `infra/bootstrap/sonarqube/configure.py`) a
   `99` y volver a ejecutar `bootstrap-sonarqube.sh`; el build debe fallar en **Analysis** y no llegar a **Package**.
   Restaurar `60` después.

## Pruebas corregidas

Ver `docs/operaciones/hallazgos_tecnicos.md`.
