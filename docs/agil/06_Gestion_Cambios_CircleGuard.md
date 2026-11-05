# Proceso de Gestión de Cambios de CircleGuard

**Proyecto Final: Pipeline DevOps de Extremo a Extremo**  
**Tarea técnica:** TEC-06 · **Épica:** E1 · **Entregable:** E1.7  
**Equipo:** Angy María Hurtado Osorio · Daniel Stiven Trujillo Marín · Daniel Esteban Arcos Cerón · Hideki Tamura Hernández  
**Asignatura:** Ingeniería de Software V (09776 - TIC), Grupo 005 · Universidad Icesi · 2026-2

---

## 1. Introducción

Este documento define el proceso de gestión de cambios para el proyecto CircleGuard. Establece la plantilla de solicitud de cambio, la política de aprobación según el tipo de cambio y el esquema de versionado semántico con tags de Git. El proceso se integra con la estrategia de branching (TEC-02) y con los scripts de release de la HU-03.

---

## 2. Tipos de Cambio

| Tipo | Descripción | Riesgo | Tiempo disponible |
|---|---|---|---|
| **Estándar** | Cambio repetitivo, de bajo riesgo y con procedimiento conocido. Ejemplo: actualizar una dependencia menor, corregir documentación. | Bajo | Normal (dentro del sprint) |
| **Normal** | Cambio planificado que modifica comportamiento existente o agrega funcionalidad nueva. Requiere análisis de impacto. Ejemplo: nueva etapa en el pipeline, nuevo servicio en Compose. | Medio | Normal (dentro del sprint) |
| **Emergencia** | Cambio no planificado para corregir un fallo crítico en producción. Sigue el flujo `hotfix/` definido en TEC-02. | Alto | Urgente (< 24 h) |

---

## 3. Política de Aprobación

| Tipo | Autor | Revisor obligatorio | Aprobador final | Fusión |
|---|---|---|---|---|
| **Estándar** | Cualquier integrante | 1 integrante distinto del autor | Revisor (misma persona) | Squash merge hacia `dev` |
| **Normal** | Cualquier integrante | 1 integrante distinto del autor | Product Owner (Daniel Arcos) | Squash merge hacia `dev` |
| **Emergencia** | Cualquier integrante | Scrum Master (Angy Hurtado) | Product Owner (Daniel Arcos) | Merge commit hacia `main`, luego PR hacia `dev` |

> **Regla general:** ningún integrante aprueba ni fusiona su propio pull request. Las promociones de `dev` a `main` siempre las fusiona el Product Owner.

---

## 4. Plantilla de Solicitud de Cambio (RFC)

Cada cambio se registra como un pull request en GitHub usando la plantilla `.github/pull_request_template.md`. Para cambios normales y de emergencia se completa adicionalmente el siguiente formulario en la descripción del PR:

```markdown
### Solicitud de Cambio (RFC)

| Campo               | Valor |
|---------------------|-------|
| **ID del backlog**  | HU-XX / TEC-XX |
| **Clave Jira**      | PI-XX |
| **Tipo de cambio**  | Estándar / Normal / Emergencia |
| **Solicitante**     | Nombre del integrante |
| **Fecha**           | YYYY-MM-DD |
| **Ambiente(s)**     | dev / stage / prod |

#### Descripción del cambio
Explicar qué se modifica y por qué.

#### Análisis de impacto
- Servicios afectados:
- Dependencias modificadas:
- Riesgo de regresión:

#### Plan de rollback
Describir cómo revertir el cambio si falla (versión anterior a restaurar o rama a revertir).

#### Criterios de éxito
Condiciones verificables que confirman que el cambio fue exitoso.
```

---

## 5. Esquema de Versionado Semántico (tags vX.Y.Z)

Los tags siguen **SemVer** (`vMAJOR.MINOR.PATCH`) y se crean únicamente sobre los merge commits de `main`.

### 5.1 Reglas de incremento

| Tipo de commit (Conventional Commits) | Componente que incrementa | Ejemplo |
|---|---|---|
| `feat!:` o `BREAKING CHANGE` en el pie | **MAJOR** (X+1.0.0) | `v1.0.0` → `v2.0.0` |
| `feat:` | **MINOR** (X.Y+1.0) | `v1.0.0` → `v1.1.0` |
| `fix:` | **PATCH** (X.Y.Z+1) | `v1.0.0` → `v1.0.1` |
| `docs:`, `test:`, `chore:` | Sin incremento | — |

### 5.2 Versiones de referencia del proyecto

| Hito | Tag | Rama origen |
|---|---|---|
| Entrega Parte 1 (8-nov) | `v1.0.0` | `main` tras fusionar `dev` del Sprint 1 |
| Correcciones post-Parte 1 | `v1.0.x` | `main` (hotfix o nueva promoción) |
| Entrega Parte 2 (22-nov) | `v2.0.0` o `v1.x.0` | `main` tras fusionar `dev` del Sprint 2 |

### 5.3 Procedimiento para crear un tag

```bash
# 1. Situarse en main y asegurarse de que está limpio
git switch main && git pull origin main

# 2. Calcular la versión (lo hace el script automáticamente)
bash infra/release/version.sh        # imprime X.Y.Z

# 3. Ejecutar el flujo de release completo
bash infra/release/release.sh        # actualiza CHANGELOG.md, crea el tag y el commit

# 4. Publicar tag y rama
git push origin main v<X.Y.Z>

# 5. (Opcional) Construir y publicar imágenes en Nexus
REGISTRY=<ip>:8082 NEXUS_USER=... NEXUS_PASSWORD=... \
  bash infra/release/build-images.sh <X.Y.Z> --push
```

> El cálculo automático de versión lo realiza `infra/release/version.sh` leyendo los commits desde el último tag hasta `HEAD`. La generación de release notes la realiza `infra/release/changelog.sh` y el resultado se antepone a `CHANGELOG.md`.

---

## 6. Flujo de Cambio por Tipo

### 6.1 Cambio estándar
```
Integrante crea rama → commits → PR hacia dev → revisor aprueba → squash merge → rama eliminada
```

### 6.2 Cambio normal
```
Integrante crea rama → commits → PR hacia dev → revisor + Product Owner aprueban → squash merge
→ (cuando dev es estable) PR de promoción dev→main → Product Owner fusiona → tag vX.Y.Z
```

### 6.3 Cambio de emergencia (hotfix)
```
Integrante crea hotfix/ desde main → PR hacia main → Scrum Master revisa → Product Owner aprueba y fusiona
→ tag vX.Y.Z+1 → PR de integración hotfix/→dev → Scrum Master revisa → cualquier integrante fusiona
```

---

## 7. Trazabilidad

Cada cambio es trazable mediante:

1. **Tarjeta Jira** (PI-xx): registra el estado, el responsable y la evidencia.
2. **Nombre de rama**: `feature/HU-xx-descripcion` o `chore/TEC-xx-descripcion`.
3. **Pie del commit**: `Refs: PI-xx` enlaza automáticamente el commit con la tarjeta.
4. **Pull request**: contiene la RFC para cambios normales y de emergencia, el revisor y los checks.
5. **Tag en main**: vincula la versión con el commit exacto que se desplegó.
