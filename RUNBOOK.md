# RUNBOOK: dictar la clase de CI/CD con `tienda-api`

Guion para usar de pie frente al curso. Qué es el repositorio y cómo está construido: [README.md](README.md).
Repositorio: <https://github.com/DaronArg/tienda-api> · Duración total: 45 a 60 minutos.

> **Estado de verificación (leer una vez).** Los scripts y los parches de cada demo se probaron en local (los tres fallos se reproducen con el mensaje exacto indicado, `verify` tarda unos 30 s, la imagen arranca y responde `/actuator/health` y `/api/version`). Los workflows pasaron `actionlint`, pero **todavía no se ejecutaron en GitHub**: la organización tiene deshabilitado GitHub Actions para este repositorio y no admite *required reviewers* en repos privados (ver [Pendiente antes de la primera clase](#pendiente-antes-de-la-primera-clase)). Los tiempos de GitHub y lo que dice "qué deberían ver" son **estimados**, no observados. Hacer una pasada completa antes de la clase y corregir este documento con lo real.

## Antes de la clase

```bash
scripts/doctor.sh
```

Todo debe estar en `[ OK ]`. Si algo falla, el script imprime el comando que lo arregla.

- [ ] `gh` con sesión iniciada y scope `workflow`.
- [ ] Repositorio con `main` y `develop` en GitHub y **Actions habilitado** para el repo. Es **privado**: CodeQL se omite (ver [Límites](#límites-honestos)).
- [ ] Entornos `staging` y `production`; `production` con un reviewer (vos).
- [ ] Árbol local limpio y en `main`; sin ramas, PR, tags ni releases de demos anteriores (`scripts/reset.sh` los borra).
- [ ] Último CI en `main` en verde: es el **plan B** si Internet o GitHub fallan.
- [ ] Pestañas abiertas: Actions, Pull requests, Releases, Packages, Settings > Environments.

Un solo comando para empezar de cero en cualquier momento: `scripts/reset.sh`.

## Orden recomendado

| # | Demo | Comando | Tiempo (estimado) |
|---|------|---------|-------------------|
| 1 | Pipeline verde con Git Flow | `scripts/demo.sh green-pr` | 6 a 8 min |
| 2 | Test roto: falla temprano | `scripts/demo.sh break-test` | 3 min |
| 3 | Cobertura bajo 80% | `scripts/demo.sh drop-coverage` | 3 min |
| 4 | Violación de PMD | `scripts/demo.sh pmd-violation` | 3 min |
| 5 | Release + aprobación manual | `scripts/demo.sh release` | 8 a 10 min |
| 6 | Tag que no coincide con el pom | `scripts/demo.sh release 1.0.1` | 2 min |

Tiempos de cada workflow en un runner de GitHub (estimados, sin medir): `CI` 3 a 4 min (`build-test` ~2, `package` ~2), `CodeQL` 3 a 5 min, `Release` ~4 min más ~1 min por cada deploy. Todos quedan bajo el objetivo de 10 minutos del material. Los demos 2, 3 y 4 fallan en el primer job, así que dan feedback en 1 a 2 minutos.

---

## Demo 1: pipeline en verde con Git Flow

**Objetivo.** Ver las etapas 1 a 5 funcionando y cómo se integra un cambio por Pull Request.
**Tiempo.** 6 a 8 min.

**Qué explicar antes**
- CI/CD es la cadena de valor desde el commit hasta el usuario. Hoy vemos las primeras etapas: checkout, build, tests, análisis estático y empaquetado.
- Nadie hace push a `develop` o `main`: se trabaja en `feature/*` y se integra por PR. El pipeline es el revisor que nunca se cansa.
- El mismo pipeline corre en cada cambio, en un entorno limpio y reproducible (un runner nuevo, `./mvnw`, Docker).
- Si todo pasa, `develop` queda siempre en un estado desplegable.

**Pasos**
1. `scripts/demo.sh green-pr` crea `feature/demo-green-pr` desde `develop`, empuja un cambio de documentación y abre un PR hacia `develop`. Abrir la URL que imprime.
2. En el PR, pestaña **Checks**: aparece `CI`. El workflow `CodeQL` figura como **Skipped** porque el repositorio es privado (ver Límites).
3. Pestaña **Actions** > `CI`: abrir el run. Mostrar los jobs `Build, test and quality gates` y, después, `Package and smoke-test Docker image`.
4. En el run, **Summary**: la tabla de tests y cobertura. Al final, **Artifacts**: `reports-<n>-<intento>` (Surefire, JaCoCo, PMD).
5. (Solo si el repo es público) **Security > Code scanning**: resultado de CodeQL.

**Qué deberían ver** (esperado): dos runs de `CI` para la misma rama (uno por `push` y otro por `pull_request`), `CodeQL` omitido (repo privado), summary con `Tests run: 12 (failures: 0, errors: 0)` y `Line coverage: 96.1%`.

**Qué remarcar.** El push y el PR disparan el workflow cada uno; es esperado (el material de la cátedra usa `on: [push, pull_request]`). El job `package` solo arranca si `build-test` pasó (`needs`).

**Preguntas**
- *¿Por qué `package` espera a `build-test`?* Para no gastar tiempo ni minutos empaquetando código que no pasó las pruebas (fallar temprano).
- *¿Qué ventaja tiene que los reportes se suban aunque el build falle?* Se puede diagnosticar sin reproducir el fallo en local (`if: always()`).

**Si algo falla.** Mostrar el último run verde de `main` en Actions. No hacer merge del PR (el reset lo cierra).

---

## Demo 2: un test roto detiene el pipeline

**Objetivo.** Mostrar el principio de fallar temprano y el feedback inmediato.
**Tiempo.** 3 min.

**Qué explicar antes**
- La etapa de testing es la primera barrera: tests unitarios (Mockito) e integración (`@SpringBootTest` con H2).
- Si un test falla, el pipeline se corta; los jobs siguientes no se ejecutan.
- Un fallo detectado en minutos cuesta mucho menos que uno detectado en producción.

**Pasos**
1. `scripts/demo.sh break-test` cambia una aserción en `ProductServiceTest` (`isEqualTo(5)` por `isEqualTo(6)`), empuja `demo/break-test` y abre el PR.
2. Abrir el PR > **Checks** > `CI`: el job `Build, test and quality gates` queda en rojo.
3. Abrir el log del step `Verify (tests, coverage gate, PMD)` y buscar `ProductServiceTest.createSavesNewProduct`.
4. Volver al run: el job `Package and smoke-test Docker image` figura **Skipped**.
5. Abrir **Artifacts**: el reporte de Surefire está igual.

**Qué deberían ver** (reproducido en local): `Tests run: 6, Failures: 1` y `expected: 6` / `but was: 5` en `ProductServiceTest`; `BUILD FAILURE`. En GitHub: el segundo job omitido.

**Qué remarcar.** El rojo está en el step de tests, no en un paso posterior. Nadie construyó una imagen de código roto. El PR no se puede mergear (o no debería) con el check en rojo.

**Preguntas**
- *¿Qué mecanismo del YAML evita que corra `package`?* `needs: build-test`.
- *¿Se borra el test para que pase?* No: el siguiente demo muestra por qué eso tampoco funciona.

**Si algo falla.** Mostrar el output de `./mvnw -B clean verify` en esa rama (`git switch demo/break-test`) o capturas de un run anterior.

---

## Demo 3: la cobertura bajo 80% bloquea el build

**Objetivo.** Entender un quality gate: pasar los tests no alcanza.
**Tiempo.** 3 min.

**Qué explicar antes**
- Cobertura: líneas, ramas y métodos son métricas distintas; acá el gate mide **líneas** (>= 80%) con JaCoCo.
- "Una cobertura alta no garantiza calidad, pero una cobertura baja indica riesgo."
- Un quality gate convierte una política en una regla automática y no negociable.

**Pasos**
1. `scripts/demo.sh drop-coverage` borra `ProductApiIntegrationTest`, empuja `demo/drop-coverage` y abre el PR.
2. PR > **Checks** > `CI` en rojo. Abrir el log de `Verify`.
3. Buscar la línea de JaCoCo y mostrar el summary del run (el porcentaje cae).
4. Abrir el artefacto y el reporte JaCoCo (`index.html`): las clases sin cubrir.

**Qué deberían ver** (reproducido en local): todos los tests restantes pasan (`Tests run: 7`), y luego
`Rule violated for bundle tienda-api: lines covered ratio is 0.66, but expected minimum is 0.80` y `BUILD FAILURE`.

**Qué remarcar.** Ningún test falló; falló la **política**. Si alguien borra tests para "arreglar" un rojo, el gate lo detecta.

**Preguntas**
- *¿Cobertura 100% significa que no hay bugs?* No: indica que las líneas se ejecutaron, no que se verificó lo correcto.
- *¿Qué diferencia hay entre cobertura de líneas y de ramas?* Una línea con un `if` puede estar cubierta sin haber probado ambos caminos.

**Si algo falla.** Mostrar `./mvnw -B clean verify` en local sobre esa rama. Usar siempre `clean`: sin él JaCoCo reutiliza datos viejos.

---

## Demo 4: análisis estático con PMD

**Objetivo.** Diferenciar tests, cobertura y análisis estático (etapa 4).
**Tiempo.** 3 min.

**Qué explicar antes**
- El análisis estático (SAST) examina el código **sin ejecutarlo**; puede bloquear el build.
- Herramientas del material: SonarQube, CodeQL, OWASP Dependency Check, PMD / estilo de código.
- Acá hay dos: **PMD** (estilo y malas prácticas, dentro de `verify`, siempre activo) y **CodeQL** (vulnerabilidades, workflow aparte). CodeQL solo corre si el repositorio es público; en este repo privado PMD es el análisis estático en acción.

**Pasos**
1. `scripts/demo.sh pmd-violation` agrega `System.out.println("listing");` en `ProductService.findAll()` y abre el PR.
2. PR > **Checks** > `CI` en rojo; log del step `Verify`: buscar `PMD Failure`.
3. Abrir `config/pmd-ruleset.xml` (reglas explícitas) y el reporte `pmd.html` del artefacto.

**Qué deberían ver** (reproducido en local): tests en verde, cobertura bien y
`PMD Failure: ar.edu.utn.frc.tienda.product.ProductService:16 Rule:SystemPrintln Priority:2 Usage of System.out/err.`

**Qué remarcar.** Tests y cobertura pasan y aun así el código no está listo. Cada herramienta ve algo distinto.

**Preguntas**
- *¿Por qué `System.out.println` es mala práctica en un servicio?* No tiene niveles ni formato, no se puede configurar ni enviar a un sistema de logs.
- *¿Qué detecta CodeQL que no detecta PMD?* Flujos de datos inseguros (inyección SQL, XSS, etc.).

**Si algo falla.** Mostrar `./mvnw -B clean verify` en esa rama.

---

## Demo 5: release, registro de imágenes y aprobación manual

**Objetivo.** Etapas 6 y 7: un tag produce un artefacto versionado, y una persona decide producción.
**Tiempo.** 8 a 10 min.

**Qué explicar antes**
- Release: el artefacto se publica en un registro (acá GitHub Container Registry) con un tag de Git `v1.0.0` y notas de cambios, **solo si las etapas anteriores pasaron**.
- Lo que se prueba es exactamente lo que se despliega: la imagen se construye **una vez** y los despliegues solo hacen `docker pull`.
- Staging se despliega solo; producción espera aprobación humana: eso es Continuous **Delivery**.
- Los despliegues de esta demo son simulaciones dentro del runner: lo real es el orden, los entornos y la aprobación.

**Pasos**
1. `scripts/demo.sh release` crea el tag anotado `v1.0.0` sobre `main` y lo empuja (usa la versión del `pom.xml`).
2. **Actions > Release**: abrir el run. Job `Verify, publish image and create GitHub Release`: mostrar el step `Check that the Git tag matches the pom.xml version`, luego `Verify` y `Push image to GHCR`.
3. **Releases** (barra lateral del repo): aparece `v1.0.0` con notas generadas y el `.jar` adjunto.
4. **Packages**: `tienda-api` con las etiquetas `1.0.0` y `latest` (`ghcr.io/daronarg/tienda-api`; el owner va en minúsculas).
5. Volver al run: `Deploy to staging (simulated)` corre solo. Abrir el step `Smoke test staging` (health y versión).
6. `Deploy to production` queda en **Waiting**. Hacer clic en **Review deployments**, marcar `production` y **Approve and deploy**. Alternativa por API:
   ```bash
   RUN=$(gh run list --workflow release.yml --limit 1 --json databaseId --jq '.[0].databaseId')
   ENV=$(gh api repos/{owner}/{repo}/actions/runs/$RUN/pending_deployments --jq '.[0].environment.id')
   gh api -X POST repos/{owner}/{repo}/actions/runs/$RUN/pending_deployments \
     -F "environment_ids[]=$ENV" -f state=approved -f comment="approved in class"
   ```
7. Opcional, para mostrar el rechazo: repetir con `-f state=rejected`. El job de producción termina en rojo y nada se despliega.
8. **Settings > Environments** o la pestaña de entornos: historial de despliegues de `staging` y `production`.

**Qué deberían ver** (esperado): el run con tres jobs encadenados; el segundo en verde sin intervención; el tercero con el candado amarillo hasta aprobar. El Release con `tienda-api-1.0.0.jar`.

**Qué remarcar.** La aprobación no está en el YAML: son los **Required reviewers** del entorno `production`. El pipeline es el mismo hasta ese punto; solo cambia quién aprieta el botón.

**Preguntas**
- *¿Por qué el job de deploy no reconstruye la imagen?* Porque lo desplegado debe ser el mismo artefacto que se probó.
- *¿Qué pasa si se vuelve a empujar el tag `v1.0.0`?* Hay que borrarlo primero (`scripts/reset.sh`); un tag es una referencia fija a un commit.
- *¿Qué cambiaría para tener Continuous Deployment?* Ver [Continuous Delivery vs Deployment](#continuous-delivery-vs-continuous-deployment).

**Si algo falla.** Mostrar el run exitoso de plan B (ver [Repetir la clase](#repetir-la-clase)) o el Release y el paquete ya publicados. Si GHCR rechaza el push, revisar el log del step `Push image to GHCR`.

---

## Demo 6: un tag que no coincide con la versión del pom

**Objetivo.** Un tag nunca debe publicar un artefacto con otro número.
**Tiempo.** 2 min.

**Qué explicar antes**
- El número de versión vive en un solo lugar (`pom.xml`) y el tag debe coincidir: es trazabilidad.
- El pipeline protege contra el error humano más común al versionar.

**Pasos**
1. `scripts/demo.sh release 1.0.1` (el `pom.xml` sigue en `1.0.0`). Si no hiciste el reset, primero `scripts/reset.sh`.
2. **Actions > Release**: el job falla en el step `Check that the Git tag matches the pom.xml version`.
3. Abrir el log y la anotación roja.

**Qué deberían ver** (esperado): `Git tag is 'v1.0.1' but pom.xml version is '1.0.0'. Update the pom.xml version (or tag the right commit) and try again.` No hay Release, no hay imagen, los deploys no corren.

**Qué remarcar.** Falla en el primer step útil, antes de compilar y de publicar nada.

**Preguntas**
- *¿Cómo se publica 1.0.1 correctamente?* Cambiar `<version>` en el `pom.xml`, commit en `hotfix/*` o `release/*`, merge a `main`, y recién entonces el tag.

**Si algo falla.** Mostrar el mensaje del workflow en el YAML (`release.yml`, step `meta`).

---

## Las 7 etapas y dónde viven

| # | Etapa | Dónde |
|---|-------|-------|
| 1 | Checkout (disparador push/PR, trazabilidad) | `actions/checkout` en todos los workflows |
| 2 | Build (Maven, entorno limpio, define el artefacto inmutable) | `ci.yml` > `build-test`; `pom.xml`; `./mvnw` |
| 3 | Testing automatizado (unitarios, integración H2, cobertura JaCoCo, falla temprano) | `./mvnw verify`; `src/test/`; gate de 80% en `pom.xml` |
| 4 | Análisis estático / SAST | PMD en `verify`; `codeql.yml` |
| 5 | Empaquetado (jar versionado, imagen multi-stage) | `ci.yml` > `package`; `Dockerfile` |
| 6 | Release (registro, tag, changelog, solo si lo anterior pasó) | `release.yml` > `release` |
| 7 | Deploy (automático o con aprobación; entornos) | `release.yml` > `deploy-staging`, `deploy-production` |

CI son las etapas 1 a 4 y es la condición previa de CD. Los workflows del material usan `on: [push, pull_request]` y `on: push: tags: 'v*.*.*'`; acá se refinó para respetar Git Flow.

## Git Flow: qué rama dispara qué

| Rama | Rol | `ci.yml` | `codeql.yml` | `release.yml` |
|------|-----|:--------:|:------------:|:-------------:|
| `main` | producción | push | push | solo por tag |
| `develop` | próxima versión | push | no (sí en PR) | no |
| `feature/*` | trabajo diario | push y PR | PR a `develop`/`main` | no |
| `release/*` | congelar y estabilizar | push y PR | PR a `main` | no |
| `hotfix/*` | arreglo urgente desde `main` | push y PR | PR a `main` | no |

Flujo: `feature/*` sale de `develop` > merge a `develop` > `release/1.0.0` > merge a `main` y tag `v1.0.0` > deploy > `hotfix/1.0.1` desde `main` si hace falta.
Proceso de release: congelar, build y test, tag y release, deploy, monitoreo posterior y plan de rollback.

Opcional (valor didáctico, no está configurado): en **Settings > Branches** proteger `main` y `develop` exigiendo el check `Build, test and quality gates`. Así el rojo de las demos 2 a 4 **impide** el merge, no solo lo advierte.

## SemVer: ¿qué número subo?

Versión actual `1.0.0` (`MAJOR.MINOR.PATCH`: cambio incompatible / funcionalidad compatible / corrección).

| Pregunta | Respuesta |
|----------|-----------|
| Corrijo un bug de validación sin cambiar la API | `1.0.1` (PATCH) |
| Agrego `GET /api/products/search` | `1.1.0` (MINOR) |
| Renombro `/api/products` a `/api/v2/products` | `2.0.0` (MAJOR, rompe clientes) |
| Arreglo urgente en producción | `1.0.1` desde `hotfix/*` creada desde `main` |

## Continuous Delivery vs Continuous Deployment

- **Delivery**: el artefacto siempre queda listo; una persona decide producción. Es lo que hace este repo: `deploy-production` espera al reviewer del entorno `production`.
- **Deployment**: automático hasta producción, sin pausa humana.

Para pasar a Deployment **no se toca el YAML**: en **Settings > Environments > production** desactivar **Required reviewers**. Verificarlo con `gh api repos/{owner}/{repo}/environments/production`. Para volver: `scripts/setup-github.sh` lo reconfigura. Advertencia para la clase: Deployment exige muy buena cobertura y un smoke test confiable.

## Volver al estado inicial

```bash
scripts/reset.sh            # todo lo creado por las demos
scripts/reset.sh --dry-run  # solo muestra qué haría
scripts/reset.sh --runs     # además borra el historial de runs (opcional)
```

| Dónde | Qué hace |
|-------|----------|
| GitHub | cancela runs en curso de las demos, cierra los PR `[DEMO]`, borra el Release y el tag de la demo, borra las ramas `demo/*` y `feature/demo-*` |
| Local | vuelve a `main`, borra las ramas y tags de las demos, actualiza `main` y `develop` desde `origin` |

Solo toca lo que reconoce como suyo (ramas con esos nombres, PR con título `[DEMO]`, tags anotados con `[tienda-api demo]`); lo demás lo rechaza con una explicación. Es idempotente. Termina imprimiendo la verificación; para confirmar a mano: `scripts/doctor.sh`.

## Repetir la clase

Persiste a propósito: el **historial de runs** (sirve de plan B; `--runs` lo borra) y las **versiones de la imagen en GHCR** (borrarlas requiere el scope `delete:packages`, que el token no tiene; se pueden borrar a mano en Packages > Package settings).
Repetir `v1.0.0` es posible: el tag y el Release se borran con el reset y el nuevo push de la imagen `:1.0.0` y `:latest` sobreescribe las etiquetas existentes (esperado, no verificado todavía).
Plan B: dejar un run de `Release` exitoso en el historial y anotar acá su URL: _pendiente (se completa tras la primera ejecución real)_.

## Límites honestos

- Los deploys son **simulaciones**: la imagen corre dentro del runner y se elimina. No hay servidor ni clúster.
- **CodeQL (SAST) solo corre si el repositorio es público** (o con el add-on pago Code Security). En este repo privado el job se omite y PMD cubre el análisis estático. Para mostrarlo en vivo: `gh repo edit --visibility public --accept-visibility-change-consequences`.
- Los *required reviewers* de `production` dependen del plan de la organización: en esta organización GitHub rechazó crearlos en un repo privado (HTTP 422, "billing plan"). Sin reviewers, `deploy-production` corre sin esperar y el demo es Continuous Deployment, no Delivery.
- La primera vez que se publica la imagen el paquete es **privado**. Los jobs de deploy lo leen con `GITHUB_TOKEN` (permiso `packages: read`); para hacer `docker pull` desde tu máquina hay que cambiar su visibilidad.
- El push y el PR disparan `CI` dos veces; es esperado.

## Pendiente antes de la primera clase

1. Un administrador de la organización `DaronArg` debe habilitar GitHub Actions para el repositorio `tienda-api` (Organization settings > Actions > General > Policies). Hoy `gh api repos/{owner}/{repo}/actions/permissions` devuelve `enabled: false` y la API responde `Actions is disabled on this repository by the organization`; no hay runs.
2. Resolver los *required reviewers*: `PUT .../environments/production` con reviewers devuelve HTTP 422 ("billing plan"). Opciones: revisar el plan de facturación de la organización, o hacer público el repo (`gh repo edit --visibility public --accept-visibility-change-consequences`), lo que además activa CodeQL.
3. `scripts/setup-github.sh` (idempotente: vuelve a configurar entornos y reviewer) y `scripts/doctor.sh`.
4. Correr las demos 1 a 6 una vez, `scripts/reset.sh`, y reemplazar en este documento los tiempos estimados por los medidos y la URL del run de plan B.
