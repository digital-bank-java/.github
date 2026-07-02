# Java Test Convention

This convention applies to Maven-based Java services in the Digital Bank Java platform.

## Goals

- Keep fast feedback fast.
- Separate pure unit tests from Spring, HTTP, database, and container-backed integration tests.
- Make local commands and CI stages predictable across services.
- Keep future quality gates easy to add without changing every service differently.

## Test Types

| Type | Purpose | Typical tools | Maven phase |
| --- | --- | --- | --- |
| Unit test | Validate isolated Java logic without Spring Boot startup, Docker, or external services. | JUnit, AssertJ, Mockito when needed | `test` |
| Integration test | Validate Spring wiring, HTTP controllers, persistence, Flyway, JPA, Config Client behavior, or Testcontainers-backed dependencies. | Spring Boot Test, MockMvc/RestTestClient, Testcontainers | `integration-test` and `verify` |
| Contract test | Validate API or event contracts between services. | OpenAPI, AsyncAPI, schema checks | future dedicated stage |
| SIT smoke test | Validate deployed services in Kubernetes through stable entry points. | `kubectl`, `curl`, Insomnia/manual checks | deployment validation |

Node.js analogy:

- Unit test is like a Jest test for a pure function or service class.
- Integration test is like a Supertest/NestJS test that starts the app and uses a real PostgreSQL container.
- SIT smoke test is like calling deployed services through an API Gateway after containers are running.

## Naming Convention

Use names that tell Maven and humans what kind of test is being executed.

| Test kind | Class name pattern | Example |
| --- | --- | --- |
| Unit test | `*Test` or `*Tests` | `CustomerServiceTest`, `AccountTest` |
| Integration test | `*IT` or `*IntegrationTest` | `CustomerApiIT`, `AccountPersistenceIntegrationTest` |

Recommended package placement:

```text
src/test/java/com/digitalbank/<service>/
├── domain/
│   └── AccountTest.java
├── application/
│   └── AccountServiceTest.java
└── integration/
    ├── AccountApiIT.java
    └── AccountPersistenceIT.java
```

The package structure is a readability convention. Maven decides what runs from the class name patterns configured in Surefire and Failsafe.

## Maven Commands

### Fast Local Feedback

```bash
./mvnw test
```

Expected behavior:

- Runs unit tests only.
- Does not start Testcontainers.
- Does not require Docker.
- Should be fast enough to run frequently while coding.

### Full Service Verification

```bash
./mvnw verify
```

Expected behavior:

- Runs unit tests.
- Runs integration tests.
- May start Testcontainers.
- May start a Spring Boot application context.
- Is the default command before opening or updating a pull request.

## Maven Plugin Convention

Use Maven Surefire for unit tests and Maven Failsafe for integration tests.

```xml
<build>
	<plugins>
		<plugin>
			<groupId>org.apache.maven.plugins</groupId>
			<artifactId>maven-surefire-plugin</artifactId>
			<configuration>
				<includes>
					<include>**/*Test.java</include>
					<include>**/*Tests.java</include>
				</includes>
				<excludes>
					<exclude>**/*IT.java</exclude>
					<exclude>**/*IntegrationTest.java</exclude>
					<exclude>**/*IntegrationTests.java</exclude>
				</excludes>
			</configuration>
		</plugin>
		<plugin>
			<groupId>org.apache.maven.plugins</groupId>
			<artifactId>maven-failsafe-plugin</artifactId>
			<configuration>
				<includes>
					<include>**/*IT.java</include>
					<include>**/*IntegrationTest.java</include>
					<include>**/*IntegrationTests.java</include>
				</includes>
			</configuration>
			<executions>
				<execution>
					<goals>
						<goal>integration-test</goal>
						<goal>verify</goal>
					</goals>
				</execution>
			</executions>
		</plugin>
	</plugins>
</build>
```

The exact plugin versions should normally come from `spring-boot-starter-parent` unless a service has a specific reason to override them.

## What Belongs In Unit Tests

Use unit tests for:

- Domain rules.
- Application service orchestration that can use fake ports or mocks.
- Value object validation.
- Mapper behavior when the mapper does not require Spring.
- Error handling logic that does not need HTTP serialization.

Unit tests should not:

- Start the full Spring Boot application.
- Start PostgreSQL, Kafka, Redis, or other containers.
- Depend on Kubernetes, Config Server, or real network calls.

## What Belongs In Integration Tests

Use integration tests for:

- REST API behavior.
- Request validation and error response serialization.
- Spring dependency injection and configuration binding.
- Flyway migrations.
- JPA mappings and repository behavior.
- PostgreSQL persistence through Testcontainers.
- Config Server and API Gateway routing behavior.

Integration tests may use:

- `@SpringBootTest`
- Spring MVC/WebFlux test clients
- Testcontainers
- Real database migrations
- Application test profiles

## CI Stage Convention

Recommended Java service CI stages:

1. Unit tests:

   ```bash
   ./mvnw test
   ```

2. Integration tests and package verification:

   ```bash
   ./mvnw verify
   ```

3. Container build and smoke test.

4. Helm lint/template validation.

5. Quality gates, such as Spotless, Checkstyle, SpotBugs, and SonarQube, when added.

The initial implementation may keep `./mvnw verify` as one job while services are small. As the project grows, CI can split unit and integration stages for clearer failure reporting and faster feedback.

## Migration Plan For Existing Services

Apply the convention incrementally:

1. Rename existing Spring/Testcontainers tests to `*IT` or `*IntegrationTest`.
2. Keep pure domain/application tests as `*Test` or `*Tests`.
3. Add Surefire/Failsafe plugin configuration.
4. Run:

   ```bash
   ./mvnw test
   ./mvnw verify
   ```

5. Update service README and CI workflow if command behavior changes.

Start with:

- `customer-service`
- `account-service`

Then apply the same convention to future services as they gain domain logic and persistence.
