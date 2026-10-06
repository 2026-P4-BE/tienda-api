# tienda-api: CI/CD con GitHub Actions

[![CI](https://github.com/DaronArg/tienda-api/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/DaronArg/tienda-api/actions/workflows/ci.yml)
[![CodeQL](https://github.com/DaronArg/tienda-api/actions/workflows/codeql.yml/badge.svg?branch=main)](https://github.com/DaronArg/tienda-api/actions/workflows/codeql.yml)

> Cada cambio recibe retroalimentación automática y rápida, `main` está siempre en verde, y un tag de Git alcanza para producir un artefacto versionado, trazable y desplegable.

Caso práctico de la Unidad 5 (CI/CD) de Programación IV – Back End (UTN FRC). Es una API REST de productos (Java 17, Spring Boot 3.5, Maven) cuyo único propósito es **tener un pipeline completo que se pueda romper y arreglar en vivo**.

- **Para dictar la clase:** [RUNBOOK.md](RUNBOOK.md) (qué explicar, qué ejecutar, qué mirar).
- **Este documento:** qué es el repositorio, cómo está construido y cómo prepararlo.

## Camino rápido

```bash
scripts/setup-github.sh     # una sola vez: repo público, ramas y entornos
scripts/doctor.sh           # verificación previa a cada clase
scripts/demo.sh green-pr    # una demo (ver RUNBOOK)
scripts/reset.sh            # vuelta al estado inicial, local y en GitHub
```

Los scripts corren en Git Bash (Windows), Linux y macOS; necesitan `git` y `gh` con sesión iniciada.

## Las 7 etapas del pipeline y dónde están implementadas

| # | Etapa | Dónde está | Qué hace |
|---|-------|-----------|----------|
| 1 | Checkout | `ci.yml`, `release.yml`: step `Checkout` (`actions/checkout@v7`) | Descarga el código del commit que disparó el pipeline |
| 2 | Build (Maven) | `ci.yml` > job `build-test`; `pom.xml` | Compila con JDK 17 y caché de dependencias; usa `./mvnw` (misma versión de Maven en cualquier máquina) |
| 3 | Testing automatizado | `ci.yml` > step `Verify (tests, coverage gate, PMD)`; `src/test/`; `jacoco-maven-plugin` | Tests unitarios (Mockito), de integración (`@SpringBootTest` + MockMvc + H2) y **quality gate: cobertura de líneas >= 80%**. Falla temprano |
| 4 | Análisis estático / SAST | `codeql.yml`; `maven-pmd-plugin` + `config/pmd-ruleset.xml` dentro de `verify` | CodeQL busca vulnerabilidades; PMD verifica estilo y malas prácticas y hace fallar el build |
| 5 | Empaquetado | `ci.yml` > job `package`; `Dockerfile` | Jar versionado e imagen Docker multi-stage (etapa Maven, JRE slim, usuario no root). Se prueba (`/actuator/health`) pero no se publica |
| 6 | Release | `release.yml` > job `release` | Valida que el tag coincida con el `pom.xml`, repite `verify`, publica `ghcr.io/<owner>/tienda-api:<versión>` y `:latest`, y crea el GitHub Release con notas automáticas y el `.jar` |
| 7 | Despliegue | `release.yml` > `deploy-staging` (automático) y `deploy-production` (aprobación manual) | Descargan la imagen ya publicada y la prueban. **Son simulaciones** |

## Workflows

| Workflow | Disparador | Jobs | Permisos |
|----------|-----------|------|----------|
| `ci.yml` | push a `main`, `develop`, `feature/**`, `release/**`, `hotfix/**`; PR hacia `main` o `develop` | `build-test` > `package` | `contents: read` |
| `codeql.yml` | PR hacia `main`/`develop`, push a `main`, lunes 06:00 UTC | `analyze` | `security-events: write`, `actions: read`, `contents: read` |
| `release.yml` | tag `v*.*.*` | `release` > `deploy-staging` > `deploy-production` | `release`: `contents: write`, `packages: write`; deploys: `packages: read` |

Un push a una rama con PR abierto dispara `ci.yml` dos veces (por `push` y por `pull_request`); coincide con el ejemplo del material de la cátedra. Las ramas `demo/*` solo disparan `ci.yml` a través del PR.

Otras prácticas aplicadas:

| Práctica | Dónde |
|----------|-------|
| Pipeline corto (< 10 min) | `timeout-minutes` en cada job; `verify` tarda unos 30 s en local |
| Sin credenciales en el repositorio | Solo `secrets.GITHUB_TOKEN`, generado en cada ejecución |
| Mínimo privilegio | `permissions: contents: read` por defecto; cada job pide solo lo que necesita |
| Cancelar ejecuciones obsoletas | `concurrency` con `cancel-in-progress` en `ci.yml` |
| Artefacto inmutable | La imagen se construye una vez en `release`; los deploys solo hacen `docker pull` |
| Reportes siempre disponibles | `ci.yml` sube Surefire, JaCoCo y PMD aunque el build falle (`if: always()`); el nombre incluye `run_attempt` para soportar re-ejecuciones |
| Resumen que no rompe el build | El job summary tiene `continue-on-error: true` |

Versiones de las acciones (el material de la cátedra usa `@v4`; acá se usan las últimas mayores existentes): `actions/checkout@v7`, `actions/setup-java@v6`, `actions/upload-artifact@v7`, `docker/login-action@v4`, `github/codeql-action@v4`. Fijar la versión mayor recibe correcciones pero evita cambios incompatibles; fijar el SHA es más estricto.

## Scripts

| Script | Qué hace |
|--------|----------|
| `scripts/setup-github.sh [owner/nombre] [--private]` | Crea el repo (público, `<tu usuario>/tienda-api` por defecto) si no existe, empuja `main` y `develop`, crea los entornos `staging` y `production` con el usuario actual como reviewer. Idempotente |
| `scripts/doctor.sh` | Chequeo previo en segundos: sesión `gh` y scope `workflow`, visibilidad del repo, ramas, Actions, entornos y reviewer, árbol local limpio en `main`, sin restos de demos, último CI en verde |
| `scripts/demo.sh <escenario>` | `green-pr`, `break-test`, `drop-coverage`, `pmd-violation`, `release [versión]`, `status`. Cada uno aplica un parche conocido, empuja y abre el PR (o el tag). Se puede ejecutar dos veces: indica qué ya existe. `--no-push` deja todo solo en local |
| `scripts/reset.sh [--dry-run] [--runs]` | Vuelve al estado inicial, local y remoto. Ver reglas abajo |
| `scripts/lib.sh` | Funciones compartidas (no se ejecuta) |

Cómo reconoce `reset.sh` lo que puede borrar: ramas `demo/*` y `feature/demo-*`; PR con título `[DEMO]` desde esas ramas; tags anotados con mensaje `[tienda-api demo]` (y su Release). Todo lo demás se rechaza con una explicación. No toca versiones de imágenes en GHCR (necesitaría el scope `delete:packages`); el historial de runs solo se borra con `--runs`.

Los scripts empujan usando el token de `gh` (`gh auth git-credential`) y no el Git Credential Manager, para no abrir ventanas de login.

## Git Flow

`main` (producción), `develop` (próxima versión), `feature/*`, `release/*`, `hotfix/*`. Detalle y tabla de qué rama dispara qué: [RUNBOOK](RUNBOOK.md#git-flow-qué-rama-dispara-qué).

## Ejecutar localmente

Requisitos: JDK 17 y Docker (opcional).

```bash
./mvnw -B clean verify          # tests + cobertura (>= 80%) + PMD
./mvnw spring-boot:run          # API en http://localhost:8080
curl localhost:8080/api/products
curl localhost:8080/api/version
curl localhost:8080/actuator/health

docker build -t tienda-api:local .
docker run --rm -p 8080:8080 tienda-api:local
```

Reportes locales: `target/site/jacoco/index.html` (cobertura) y `target/reports/pmd.html` (PMD).

Endpoints: `GET/POST /api/products`, `GET/PUT/DELETE /api/products/{id}`, `GET /api/version`, `GET /actuator/health`. Cuerpo de ejemplo: `{"name": "Headset", "price": 59.90, "stock": 10}`.

> Usar siempre `clean` al comprobar la cobertura en local. JaCoCo acumula datos en `target/jacoco.exec`; sin `clean`, tests borrados "siguen contando" y el quality gate no falla. En GitHub no ocurre porque cada ejecución parte de un checkout limpio.

## Configuración inicial en GitHub (una sola vez, para quien hace un fork)

1. `gh auth login` y luego `gh auth refresh -h github.com -s workflow`: sin el scope `workflow` GitHub rechaza cualquier push que incluya `.github/workflows/`.
2. `scripts/setup-github.sh` (equivale a: repo, `git push -u origin main develop`, entornos `staging` y `production`, y a tu usuario como **Required reviewer** de `production` sin "prevent self-review").
3. `scripts/doctor.sh`.
4. Opcional: proteger `main` y `develop` exigiendo el check `Build, test and quality gates`.

### Hechos que hay que tener claros

- **CodeQL (code scanning) solo corre en repositorios públicos** (o con Code Security, pago). `codeql.yml` tiene `if: github.event.repository.private == false`: en un repo privado el job se omite y PMD queda como análisis estático. Los **required reviewers** de los entornos dependen del plan de la cuenta u organización; en un repo privado sin plan compatible el entorno `production` no pedirá aprobación.
- **Los despliegues son simulaciones.** Descargan la imagen publicada y la ejecutan dentro del runner, hacen un smoke test y la eliminan. Lo real: el orden de los jobs, los entornos, la aprobación manual y la verificación de que la imagen publicada arranca.
- La imagen se publica en `ghcr.io/<owner en minúsculas>/tienda-api`. GHCR rechaza mayúsculas, por eso `release.yml` convierte el owner (`DaronArg` pasa a `daronarg`).
- El paquete se crea privado la primera vez. Para `docker pull` desde fuera, cambiar su visibilidad en **Packages > Package settings**.
- Si el entorno `production` no existe, GitHub lo crea solo al primer despliegue **sin** reviewers: por eso `doctor.sh` lo verifica.

## Estructura del proyecto

```text
.github/workflows/   ci.yml, codeql.yml, release.yml
config/              pmd-ruleset.xml
scripts/             setup-github.sh, doctor.sh, demo.sh, reset.sh, lib.sh
src/main/java/...    product/ (controller, service, repository), version/
src/test/java/...    pruebas unitarias y de integración
Dockerfile           build multi-stage, usuario no root
pom.xml              JaCoCo (gate 80%) y PMD ligados a la fase verify
RUNBOOK.md           guion de la clase
```

## Estado de verificación

Local: `./mvnw -B clean verify` en verde (12 tests, cobertura de líneas 96%), imagen Docker probada, `actionlint` sin hallazgos, scripts probados en modo local. Los workflows **todavía no se ejecutaron en GitHub** (la organización tiene Actions deshabilitado para este repo y no admite *required reviewers* en repos privados; ver [RUNBOOK](RUNBOOK.md#pendiente-antes-de-la-primera-clase)).
