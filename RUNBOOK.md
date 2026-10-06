# RUNBOOK: dictar la clase de CI/CD con `tienda-api`

Guion para usar de pie frente al curso. Qué es el repositorio y cómo está construido: [README.md](README.md).
Repositorio: <https://github.com/DaronArg/tienda-api> · Duración total: 45 a 60 minutos.

> **Verificado en GitHub (6 de octubre de 2026).** Cada demo se ejecutó de punta a punta tres veces (y `reset.sh` entre una y otra); los tiempos y resultados de este documento son los observados. **Limitación observada:** en este repositorio GitHub **no inició** ningún workflow por `push`, `pull_request` ni tag (0 runs de esos eventos, aun con Actions habilitado y sin incidentes en githubstatus). Solo funciona `workflow_dispatch`. Por eso `scripts/demo.sh` espera unos segundos y, si no aparece el run, lo inicia con `workflow_dispatch` (`gh workflow run <workflow> --ref <rama o tag>`) y lo avisa con `[WARN]`. El pipeline que se ve es idéntico; lo único distinto es el disparador (columna *Event* de Actions: `workflow_dispatch` en lugar de `push`/`pull_request`). Si GitHub vuelve a disparar solo, el script no hace nada extra. Conviene explicarlo a los alumnos como "el disparador manual del mismo workflow".

## Antes de la clase

```bash
scripts/doctor.sh
```

Todo debe estar en `[ OK ]`. Si algo falla, el script imprime el comando que lo arregla.

- [ ] `gh` con sesión iniciada y scope `workflow`.
- [ ] Repositorio **público** con `main` y `develop` en GitHub y Actions habilitado (público: CodeQL y los required reviewers lo necesitan; ver [Límites](#límites-honestos)).
- [ ] Entornos `staging` y `production`; `production` con un reviewer (vos).
- [ ] Árbol local limpio y en `main`; sin ramas, PR, tags ni releases de demos anteriores (`scripts/reset.sh` los borra).
- [ ] Último CI en `main` en verde: es el **plan B** si Internet o GitHub fallan.
- [ ] Pestañas abiertas: Actions, Pull requests, Releases, Packages, Settings > Environments.

Un solo comando para empezar de cero en cualquier momento: `scripts/reset.sh`.

## Orden recomendado

| # | Demo | Comando | Tiempo (medido) |
|---|------|---------|-------------------|
| 1 | Pipeline verde con Git Flow | `scripts/demo.sh green-pr` | 3 a 5 min |
| 2 | Test roto: falla temprano | `scripts/demo.sh break-test` | 1 a 2 min |
| 3 | Cobertura bajo 80% | `scripts/demo.sh drop-coverage` | 1 a 2 min |
| 4 | Violación de PMD | `scripts/demo.sh pmd-violation` | 1 a 2 min |
| 5 | Release + aprobación manual | `scripts/demo.sh release` | 6 a 8 min (con explicación) |
| 6 | Tag que no coincide con el pom | `scripts/demo.sh release 1.0.1` | 1 min |

Duración de cada workflow en GitHub (medida en 3 pasadas): `CI` verde **98 a 112 s** (`build-test` 32 s, `package` 58 s); `CI` rojo en `Verify` **19 a 42 s**; `CodeQL` **93 a 104 s**; `Release` **101 a 106 s** (job `release`) + **13 a 24 s** (staging) + **15 a 19 s** (producción, después de aprobar), unos 2 min 40 s en total sin contar la espera de la aprobación. Todo queda muy por debajo del objetivo de 10 minutos del material. Los demos 2, 3 y 4 fallan en el primer job, así que dan feedback en menos de un minuto.

---

## Demo 1: pipeline en verde con Git Flow

**Objetivo.** Ver las etapas 1 a 5 funcionando y cómo se integra un cambio por Pull Request.
**Tiempo.** 3 a 5 min.

**Qué explicar antes**
- CI/CD es la cadena de valor desde el commit hasta el usuario. Hoy vemos las primeras etapas: checkout, build, tests, análisis estático y empaquetado.
- Nadie hace push a `develop` o `main`: se trabaja en `feature/*` y se integra por PR. El pipeline es el revisor que nunca se cansa.
- El mismo pipeline corre en cada cambio, en un entorno limpio y reproducible (un runner nuevo, `./mvnw`, Docker).
- Si todo pasa, `develop` queda siempre en un estado desplegable.

**Pasos**
1. `scripts/demo.sh green-pr` crea `feature/demo-green-pr` desde `develop`, empuja un cambio de documentación y abre un PR hacia `develop`. Abrir la URL que imprime.
2. En el PR, pestaña **Checks** (puede tardar unos segundos en mostrar los runs iniciados por `demo.sh`): aparecen `CI` y `CodeQL`. Si no aparecen, ir a la pestaña **Actions**.
3. Pestaña **Actions** > `CI`: abrir el run. Mostrar los jobs `Build, test and quality gates` y, después, `Package and smoke-test Docker image`.
4. En el run, **Summary**: la tabla de tests y cobertura. Al final, **Artifacts**: `reports-<n>-<intento>` (Surefire, JaCoCo, PMD).
5. **Security > Code scanning**: resultado de CodeQL (sin alertas). El run de CodeQL dura unos 100 s.

**Qué deberían ver** (observado): `CI` verde en unos 100 s con los dos jobs (`build-test` 32 s, `package` 58 s) y `CodeQL` (`Analyze Java`) verde en unos 100 s. El run de CI tiene un artefacto `reports-<n>-1`. El summary lista `Tests run: 12 (failures: 0, errors: 0)` y `Line coverage: 96.1%` (mismo script comprobado en local). La columna *Event* muestra `workflow_dispatch` (ver nota inicial).

**Qué remarcar.** El job `package` solo arranca si `build-test` pasó (`needs`). Con disparo automático real, un push a una rama con PR abierto corre `CI` dos veces (`push` y `pull_request`), como en el ejemplo del material de la cátedra; con el disparo manual de `demo.sh` aparece un solo run.

**Preguntas**
- *¿Por qué `package` espera a `build-test`?* Para no gastar tiempo ni minutos empaquetando código que no pasó las pruebas (fallar temprano).
- *¿Qué ventaja tiene que los reportes se suban aunque el build falle?* Se puede diagnosticar sin reproducir el fallo en local (`if: always()`).

**Si algo falla.** Mostrar el último run verde de `main` en Actions. No hacer merge del PR (el reset lo cierra).

---

## Demo 2: un test roto detiene el pipeline

**Objetivo.** Mostrar el principio de fallar temprano y el feedback inmediato.
**Tiempo.** 1 a 2 min (el run falla a los 20 a 40 s).

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

**Qué deberían ver** (observado en local y en GitHub): `Tests run: 6, Failures: 1` y `expected: 6` / `but was: 5` en `ProductServiceTest`; `BUILD FAILURE`. En GitHub: el segundo job omitido.

**Qué remarcar.** El rojo está en el step de tests, no en un paso posterior. Nadie construyó una imagen de código roto. El PR no se puede mergear (o no debería) con el check en rojo.

**Preguntas**
- *¿Qué mecanismo del YAML evita que corra `package`?* `needs: build-test`.
- *¿Se borra el test para que pase?* No: el siguiente demo muestra por qué eso tampoco funciona.

**Si algo falla.** Mostrar el output de `./mvnw -B clean verify` en esa rama (`git switch demo/break-test`) o capturas de un run anterior.

---

## Demo 3: la cobertura bajo 80% bloquea el build

**Objetivo.** Entender un quality gate: pasar los tests no alcanza.
**Tiempo.** 1 a 2 min (el run falla a los 20 s).

**Qué explicar antes**
- Cobertura: líneas, ramas y métodos son métricas distintas; acá el gate mide **líneas** (>= 80%) con JaCoCo.
- "Una cobertura alta no garantiza calidad, pero una cobertura baja indica riesgo."
- Un quality gate convierte una política en una regla automática y no negociable.

**Pasos**
1. `scripts/demo.sh drop-coverage` borra `ProductApiIntegrationTest`, empuja `demo/drop-coverage` y abre el PR.
2. PR > **Checks** > `CI` en rojo. Abrir el log de `Verify`.
3. Buscar la línea de JaCoCo y mostrar el summary del run (el porcentaje cae).
4. Abrir el artefacto y el reporte JaCoCo (`index.html`): las clases sin cubrir.

**Qué deberían ver** (observado en local y en GitHub): todos los tests restantes pasan (`Tests run: 7`), y luego
`Rule violated for bundle tienda-api: lines covered ratio is 0.66, but expected minimum is 0.80` y `BUILD FAILURE`.

**Qué remarcar.** Ningún test falló; falló la **política**. Si alguien borra tests para "arreglar" un rojo, el gate lo detecta.

**Preguntas**
- *¿Cobertura 100% significa que no hay bugs?* No: indica que las líneas se ejecutaron, no que se verificó lo correcto.
- *¿Qué diferencia hay entre cobertura de líneas y de ramas?* Una línea con un `if` puede estar cubierta sin haber probado ambos caminos.

**Si algo falla.** Mostrar `./mvnw -B clean verify` en local sobre esa rama. Usar siempre `clean`: sin él JaCoCo reutiliza datos viejos.

---

## Demo 4: análisis estático con PMD

**Objetivo.** Diferenciar tests, cobertura y análisis estático (etapa 4).
**Tiempo.** 1 a 2 min (el run falla a los 30 s).

**Qué explicar antes**
- El análisis estático (SAST) examina el código **sin ejecutarlo**; puede bloquear el build.
- Herramientas del material: SonarQube, CodeQL, OWASP Dependency Check, PMD / estilo de código.
- Acá hay dos: **PMD** (estilo y malas prácticas, dentro de `verify`) y **CodeQL** (vulnerabilidades, workflow aparte; corre porque el repositorio es público, y se omite solo si alguien lo vuelve privado).

**Pasos**
1. `scripts/demo.sh pmd-violation` agrega `System.out.println("listing");` en `ProductService.findAll()` y abre el PR.
2. PR > **Checks** > `CI` en rojo; log del step `Verify`: buscar `PMD Failure`.
3. Abrir `config/pmd-ruleset.xml` (reglas explícitas) y el reporte `pmd.html` del artefacto.

**Qué deberían ver** (observado en local y en GitHub): tests en verde, cobertura bien y
`PMD Failure: ar.edu.utn.frc.tienda.product.ProductService:16 Rule:SystemPrintln Priority:2 Usage of System.out/err.`

**Qué remarcar.** Tests y cobertura pasan y aun así el código no está listo. Cada herramienta ve algo distinto.

**Preguntas**
- *¿Por qué `System.out.println` es mala práctica en un servicio?* No tiene niveles ni formato, no se puede configurar ni enviar a un sistema de logs.
- *¿Qué detecta CodeQL que no detecta PMD?* Flujos de datos inseguros (inyección SQL, XSS, etc.).

**Si algo falla.** Mostrar `./mvnw -B clean verify` en esa rama.

---

## Demo 5: release, registro de imágenes y aprobación manual

**Objetivo.** Etapas 6 y 7: un tag produce un artefacto versionado, y una persona decide producción.
**Tiempo.** 6 a 8 min (el pipeline completo dura unos 3 min más la espera de la aprobación).

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

**Qué deberían ver** (observado): el run `Release` con tres jobs encadenados. `Verify, publish image and create GitHub Release` tarda unos 105 s y deja el Release `v1.0.0` con el asset `tienda-api-1.0.0.jar` (las notas automáticas solo traen el enlace *Full Changelog* porque en este repositorio no hay PRs mergeados: para que muestren cambios hay que mergear PRs antes del tag). `Deploy to staging (simulated)` arranca solo (13 a 24 s) y descarga la imagen con `GITHUB_TOKEN`. `Deploy to production` queda en **Waiting** hasta aprobar y tarda 15 a 19 s después. Al rechazar, ese job termina en **Failure** y el run en rojo.

**Qué remarcar.** La aprobación no está en el YAML: son los **Required reviewers** del entorno `production`. El pipeline es el mismo hasta ese punto; solo cambia quién aprieta el botón.

**Preguntas**
- *¿Por qué el job de deploy no reconstruye la imagen?* Porque lo desplegado debe ser el mismo artefacto que se probó.
- *¿Qué pasa si se vuelve a empujar el tag `v1.0.0`?* Hay que borrarlo primero (`scripts/reset.sh`); un tag es una referencia fija a un commit.
- *¿Qué cambiaría para tener Continuous Deployment?* Ver [Continuous Delivery vs Deployment](#continuous-delivery-vs-continuous-deployment).

**Si algo falla.** Mostrar el run exitoso de plan B (ver [Repetir la clase](#repetir-la-clase)) o el Release y el paquete ya publicados. Si GHCR rechaza el push, revisar el log del step `Push image to GHCR`.

---

## Demo 6: un tag que no coincide con la versión del pom

**Objetivo.** Un tag nunca debe publicar un artefacto con otro número.
**Tiempo.** 1 min (falla a los 20 s).

**Qué explicar antes**
- El número de versión vive en un solo lugar (`pom.xml`) y el tag debe coincidir: es trazabilidad.
- El pipeline protege contra el error humano más común al versionar.

**Pasos**
1. `scripts/demo.sh release 1.0.1` (el `pom.xml` sigue en `1.0.0`). Si no hiciste el reset, primero `scripts/reset.sh`.
2. **Actions > Release**: el job falla en el step `Check that the Git tag matches the pom.xml version`.
3. Abrir el log y la anotación roja.

**Qué deberían ver** (observado): el job falla en 20 s en el step `Check that the Git tag matches the pom.xml version` con `Git tag is 'v1.0.1' but pom.xml version is '1.0.0'. Update the pom.xml version (or tag the right commit) and try again.` No hay Release, no hay imagen, los dos deploys figuran **Skipped**.

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

Repetir `v1.0.0` funciona (verificado tres veces seguidas): el reset borra el tag y el Release, el nuevo release sobreescribe las etiquetas `:1.0.0` y `:latest` de la imagen, y los deploys descargan la imagen nueva.

**Plan B** (run de `Release` completo, con staging y producción aprobada): <https://github.com/DaronArg/tienda-api/actions/runs/37479599931>. Los runs de CI y CodeQL de las demos quedan en la pestaña Actions con su rama (`demo/break-test`, etc.); si Internet o GitHub fallan en clase se pueden abrir ahí.

## Límites honestos

- Los deploys son **simulaciones**: la imagen corre dentro del runner y se elimina. No hay servidor ni clúster.
- **CodeQL y los required reviewers dependen de que el repositorio sea público** (o de un plan pago). Si alguien lo vuelve privado: el job de CodeQL se omite solo (`if: github.event.repository.private == false`) y PMD queda como único análisis estático; y `production` deja de pedir aprobación si el plan no admite reviewers.
- Los workflows **no se inician solos** por push, PR ni tag en este repositorio (ver nota inicial); `demo.sh` los inicia con `workflow_dispatch`. Los tres workflows aceptan ese disparo manual: `gh workflow run ci.yml --ref <rama>`, `gh workflow run codeql.yml --ref <rama>` y `gh workflow run release.yml --ref v1.0.0` (la referencia debe ser un tag existente).
- La imagen queda en `ghcr.io/daronarg/tienda-api`. Los jobs de deploy la descargan con `GITHUB_TOKEN` (verificado). Para `docker pull` desde tu máquina hay que revisar la visibilidad del paquete en Packages > Package settings.
- Las notas del Release dependen de los PRs mergeados entre tags; sin PRs solo muestran el enlace *Full Changelog*.
