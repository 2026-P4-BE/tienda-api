# tienda-api: CI/CD con GitHub Actions

> Cada cambio recibe retroalimentación automática y rápida, `main` está siempre en verde, y un tag de Git alcanza para producir un artefacto versionado, trazable y desplegable.

Caso práctico de la Unidad 5 (CI/CD) de Programación IV – Back End (UTN FRC). Es una API REST de productos (Java 17, Spring Boot 3.5, Maven) cuyo único propósito es **tener un pipeline completo que se pueda romper y arreglar en vivo**.

## Camino rápido

1. Crear el repositorio en GitHub y subir el código (ver [Configuración inicial](#configuración-inicial-una-sola-vez)).
2. Hacer un push a una rama `feature/*`: se ejecuta `ci.yml` (pestaña **Actions**).
3. Crear el tag `v1.0.0`: se ejecuta `release.yml` y aparecen la imagen en GHCR, el Release y los despliegues.

## Las 7 etapas del pipeline y dónde están implementadas

| # | Etapa | Dónde está | Qué hace |
|---|-------|-----------|----------|
| 1 | Checkout | `ci.yml`, `release.yml`: step `Checkout` (`actions/checkout@v7`) | Descarga el código del commit que disparó el pipeline |
| 2 | Build (Maven) | `ci.yml` → job `build-test`, steps `Set up Temurin 17 with Maven cache` y `Verify`; `pom.xml` | Compila con JDK 17 y caché de dependencias; usa `./mvnw` (misma versión de Maven en cualquier máquina) |
| 3 | Testing automatizado | `ci.yml` → step `Verify (tests, coverage gate, PMD)`; `src/test/`; plugin `jacoco-maven-plugin` en `pom.xml` | Tests unitarios (Mockito), de integración (`@SpringBootTest` + MockMvc + H2) y **quality gate: cobertura de líneas >= 80%**. Falla temprano: si algo falla, los jobs siguientes no corren |
| 4 | Análisis estático / SAST | `codeql.yml` (CodeQL para Java); `maven-pmd-plugin` + `config/pmd-ruleset.xml` ejecutado dentro de `verify` | CodeQL busca vulnerabilidades; PMD verifica estilo y malas prácticas y hace fallar el build |
| 5 | Empaquetado | `ci.yml` → job `package`; `Dockerfile` | Genera el `.jar` versionado (`tienda-api-1.0.0.jar`) y la imagen Docker multi-stage (etapa Maven, etapa JRE slim, usuario no root). La imagen se prueba (`/actuator/health`) pero no se publica |
| 6 | Release / publicación | `release.yml` → job `release` | Valida que el tag coincida con el `pom.xml`, repite `verify`, publica `ghcr.io/<owner>/tienda-api:<versión>` y `:latest` en GitHub Container Registry y crea el GitHub Release con notas automáticas y el `.jar` adjunto |
| 7 | Despliegue | `release.yml` → jobs `deploy-staging` (automático) y `deploy-production` (con aprobación manual) | Descargan la imagen ya publicada y la prueban. **Son simulaciones** (ver más abajo) |

Otras prácticas aplicadas:

| Práctica | Dónde |
|----------|-------|
| Pipeline corto (< 10 min) | `timeout-minutes: 10` en cada job; el `verify` tarda unos 40 segundos en local con dependencias en caché |
| Sin credenciales en el repositorio | Solo se usa `secrets.GITHUB_TOKEN`, que GitHub genera en cada ejecución |
| Mínimo privilegio | `permissions: contents: read` por defecto; cada job pide solo lo que necesita |
| Cancelar ejecuciones obsoletas | `concurrency` con `cancel-in-progress` en `ci.yml` |
| Artefacto inmutable | La imagen se construye una vez en `release` y los despliegues solo hacen `docker pull` de esa misma versión |
| Reportes siempre disponibles | `ci.yml` sube Surefire, JaCoCo (HTML) y PMD como artefactos incluso si el build falla (`if: always()`) |

### Versiones de las acciones

El material de la cátedra usa `@v4`. Al momento de armar este caso, las últimas versiones mayores son distintas:

| Acción | Versión usada |
|--------|---------------|
| `actions/checkout` | `v7` |
| `actions/setup-java` | `v6` |
| `actions/upload-artifact` | `v7` |
| `docker/login-action` | `v4` |
| `github/codeql-action` (`init`, `analyze`) | `v4` |

Conviene explicar a los estudiantes que fijar la versión mayor (`@v7`) es un compromiso: recibe correcciones automáticamente pero evita cambios incompatibles. Fijar el SHA del commit es aún más estricto.

## Git Flow y cuándo corre cada workflow

| Evento | `ci.yml` | `codeql.yml` | `release.yml` |
|--------|:--------:|:------------:|:-------------:|
| Push a `feature/**`, `release/**`, `hotfix/**` | sí | no | no |
| Push a `develop` | sí | no | no |
| Push a `main` | sí | sí | no |
| Pull request hacia `main` o `develop` | sí | sí | no |
| Tag `v*.*.*` | no | no | sí |
| Semanal (lunes 06:00 UTC) | no | sí | no |

Un push a una rama con PR abierto dispara `ci.yml` dos veces (por `push` y por `pull_request`). Es esperado y coincide con el ejemplo del material de la cátedra.

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

## Configuración inicial (una sola vez)

1. Crear un repositorio **público** vacío en GitHub (ver nota sobre planes más abajo).
2. Subir el código:
   ```bash
   git remote add origin https://github.com/<usuario>/tienda-api.git
   git push -u origin main develop
   ```
3. En **Settings → Environments** crear dos entornos: `staging` y `production`.
4. En el entorno `production`, activar **Required reviewers** y agregar a la persona que aprueba (el docente).
5. Recomendado: en **Settings → Branches** proteger `main` y exigir que el check `Build, test and quality gates` pase antes de hacer merge.
6. En **Settings → Actions → General**, verificar que los workflows estén habilitados.

### Hechos que hay que tener claros

- **CodeQL (code scanning) y Required reviewers de los entornos son gratuitos en repositorios públicos.** En repositorios privados necesitan un plan de pago (GitHub Team/Enterprise y, para CodeQL, GitHub Advanced Security). En un repositorio privado gratuito el job de CodeQL falla y el entorno `production` no pedirá aprobación.
- **Los despliegues son simulaciones.** `deploy-staging` y `deploy-production` descargan la imagen publicada y la ejecutan dentro del runner de GitHub, hacen un smoke test y la eliminan. No existe ningún servidor ni clúster. Lo que sí es real: el orden de los jobs, los entornos, la aprobación manual y la verificación de que la imagen publicada arranca.
- La imagen se publica en GHCR bajo `ghcr.io/<owner en minúsculas>/tienda-api`. GHCR rechaza mayúsculas, por eso `release.yml` convierte el owner (por ejemplo `DaronArg` pasa a `daronarg`).
- El paquete se crea privado la primera vez. Para poder hacer `docker pull` desde fuera, cambiar su visibilidad en **Packages → Package settings**.

## Guion de demostración para el docente

Cada ejercicio parte de `develop` limpio. Tiempo estimado total: 30 a 40 minutos.

### Ejercicio 1: pipeline en verde con Git Flow

**Hacer:**
```bash
git switch develop
git switch -c feature/add-stock-to-version
# cambio trivial, por ejemplo un comentario en README.md
git commit -am "docs: touch readme"
git push -u origin feature/add-stock-to-version
```
Abrir un Pull Request hacia `develop`.

**Observar:** en la pestaña Actions corre `CI` (`build-test` y luego `package`); en el PR aparecen los checks, y `CodeQL` también. Mostrar el job summary (tests y cobertura) y los artefactos descargables (reportes de Surefire, JaCoCo y PMD). Se hace merge solo si todo está en verde.

### Ejercicio 2: romper un test (falla temprano)

**Hacer:** en `ProductServiceTest`, cambiar `isEqualTo(5)` por `isEqualTo(6)` en `createSavesNewProduct`, commit y push.

**Observar:** `build-test` queda en rojo y el log muestra qué assertion falló. El job `package` **ni siquiera arranca** (`needs: build-test`): no se gasta tiempo construyendo una imagen de código roto. Los reportes igual se suben.

### Ejercicio 3: bajar la cobertura de 80% (quality gate)

**Hacer:** borrar `src/test/java/ar/edu/utn/frc/tienda/product/ProductApiIntegrationTest.java`, commit y push.

**Observar:** todos los tests restantes pasan, pero el build falla con `Rule violated for bundle tienda-api: lines covered ratio is 0.66, but expected minimum is 0.80`. Mensaje para la clase: que los tests pasen no alcanza; el quality gate protege contra tests que dejan de existir. Para mostrarlo en local: `./mvnw -B clean verify`.

### Ejercicio 4: violación de PMD

**Hacer:** en `ProductService.findAll()` agregar `System.out.println("listing");` antes del `return`.

**Observar:** los tests pasan, la cobertura sigue bien, pero falla PMD: `Rule:SystemPrintln ... Usage of System.out/err`. Mostrar `config/pmd-ruleset.xml` (8 reglas explícitas) y el reporte `pmd.html` en los artefactos. Diferencia con CodeQL: PMD revisa estilo y malas prácticas; CodeQL busca vulnerabilidades de seguridad.

### Ejercicio 5: release con tag (Continuous Delivery)

**Hacer:** con `develop` en verde, hacer merge a `main` (idealmente vía `release/1.0.0`) y luego:
```bash
git switch main && git pull
git tag v1.0.0
git push origin v1.0.0
```

**Observar, en orden:**
1. `release` verifica que el tag `v1.0.0` coincide con `pom.xml`, corre `verify`, publica `ghcr.io/<owner>/tienda-api:1.0.0` y `:latest`, y crea el GitHub Release con notas automáticas y el `.jar` adjunto (ver pestañas **Releases** y **Packages**).
2. `deploy-staging` corre solo, sin intervención.
3. `deploy-production` queda **en espera** ("Waiting for review"). El docente aprueba en la interfaz y recién entonces corre.

Esto es **Continuous Delivery**: todo es automático hasta producción, donde una persona decide.

**Para convertirlo en Continuous Deployment:** quitar los Required reviewers del entorno `production` en Settings (no hace falta tocar el YAML). El mismo pipeline desplegaría a producción sin pausa, y por eso exige muy buena cobertura de tests y un smoke test confiable.

**Extra (1 minuto):** repetir con `git tag v1.0.1 && git push origin v1.0.1` sin cambiar el `pom.xml`. El job falla enseguida con el mensaje `Git tag is 'v1.0.1' but pom.xml version is '1.0.0'`. Un tag nunca debe publicar un artefacto con otro número.

### Ejercicio 6: pregunta de SemVer

Versión actual: `1.0.0` (`MAJOR.MINOR.PATCH`). Preguntar a la clase qué número subir en cada caso:

| Cambio | Nueva versión | Motivo |
|--------|---------------|--------|
| Corregir un bug de validación sin cambiar la API | `1.0.1` | PATCH: corrección compatible |
| Agregar el endpoint `GET /api/products/search` | `1.1.0` | MINOR: funcionalidad nueva compatible |
| Renombrar `/api/products` a `/api/v2/products` | `2.0.0` | MAJOR: rompe a los clientes existentes |
| Corregir un error urgente en producción | `1.0.1` desde `hotfix/*` | PATCH, con rama hotfix desde `main` |

Para aplicar el número, se cambia `<version>` en `pom.xml`, se hace commit y se crea el tag con el mismo número.

## Estructura del proyecto

```text
.github/workflows/   ci.yml, codeql.yml, release.yml
config/              pmd-ruleset.xml
src/main/java/...    product/ (controller, service, repository), version/
src/test/java/...    pruebas unitarias y de integración
Dockerfile           build multi-stage, usuario no root
pom.xml              JaCoCo (gate 80%) y PMD ligados a la fase verify
```

## Lista de verificación previa a la clase

- [ ] El repositorio es público y `develop` y `main` están subidos.
- [ ] Existen los entornos `staging` y `production`, este último con Required reviewers.
- [ ] Un push de prueba dejó `CI` en verde.
- [ ] El docente conoce su usuario de GitHub en minúsculas para ubicar la imagen en GHCR.
