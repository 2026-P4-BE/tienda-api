# syntax=docker/dockerfile:1

# ---- Build stage: full JDK + Maven, discarded after the build ----
FROM maven:3.9-eclipse-temurin-17 AS build
WORKDIR /workspace
COPY pom.xml .
RUN mvn -B -q dependency:go-offline
COPY src ./src
# Tests, coverage and PMD already ran in the pipeline (./mvnw verify); the image only packages.
RUN mvn -B -q -DskipTests package

# ---- Runtime stage: slim JRE, non-root user ----
FROM eclipse-temurin:17-jre-alpine
RUN addgroup -S app && adduser -S app -G app
WORKDIR /app
COPY --from=build /workspace/target/tienda-api-*.jar app.jar
USER app
EXPOSE 8080
HEALTHCHECK --interval=10s --timeout=3s --start-period=20s --retries=5 \
  CMD wget -qO- http://localhost:8080/actuator/health || exit 1
ENTRYPOINT ["java", "-jar", "/app/app.jar"]
