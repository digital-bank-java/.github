# Spring Tools for Eclipse Workflow

Use Spring Tools for Eclipse (STS) for focused Java development and debugging. Use the Maven Wrapper in a terminal for the repository quality gate.

## Import And Refresh Maven Projects

Import a service as an existing Maven project. After changing `pom.xml`, refresh the project:

1. Right-click the project.
2. Select **Maven** > **Update Project...**.
3. Keep **Force Update of Snapshots/Releases** unchecked unless dependency resolution requires it.

The Maven update refreshes Eclipse's classpath. It does not replace the need to run the test suite.

## Run Tests

Use the scope that answers the question you have:

| Need | Eclipse action | Result |
| --- | --- | --- |
| Run one test method | Right-click the method, then **Run As** > **JUnit Test** | Executes only that test method. |
| Run one test class | Right-click the class, then **Run As** > **JUnit Test** | Executes every test method in the class. |
| Run all Maven tests | Right-click the project, then **Run As** > **Maven test** | Equivalent in intent to `./mvnw test`. |
| Run the final repository gate | Terminal: `./mvnw verify` | Runs the project lifecycle through verification and is the final pre-PR gate. |

The **JUnit** view shows test outcomes. A green bar means all selected tests passed. A red bar means at least one test failed or could not start. The **Console** contains application logs, test failures, and process exit status; normal Spring and Mockito warnings do not by themselves mean a test failed.

## Run The Application

For ordinary local execution, right-click the Spring Boot application class and select **Run As** > **Spring Boot App**. This starts the service using the launch configuration's environment and program settings.

The formal runtime profile is `sit`. When debugging a service from the workstation against SIT, follow [Workstation Debugging Against SIT](workstation-debugging-against-sit.md): use the `sit` profile, port-forward the necessary dependencies, scale the Kubernetes copy down, and supply temporary values through the launch configuration environment. Do not create or use a `local` profile.

## Debug A Test Or Application

Right-click a test method, test class, or Spring Boot application class and select **Debug As**. Add a breakpoint by double-clicking the editor gutter beside an executable statement, then start the debug session. The Debug view shows the suspended thread and call stack; the Variables view shows values in the selected stack frame.

Use the controls after execution reaches a breakpoint:

| Control | Use |
| --- | --- |
| **Resume** | Continue until the next breakpoint or the process exits. |
| **Step Over** | Execute the current line without entering a called method. |
| **Step Into** | Enter the called method when its implementation is relevant. |
| **Step Return** | Finish the current method and stop at its caller. |

Stepping may enter JUnit, Spring, or JDK implementation frames where source is unavailable. That is expected. Use **Step Return** to come back to application code or add a breakpoint on the next application statement.

## Stop And Return To Normal Work

Stop an active run or debug process with the red square **Terminate** button in the Console or Debug view. A terminated entry and exit value `0` in the Debug view mean the process completed successfully.

Remove breakpoints that are no longer needed by double-clicking their gutter markers or using the **Breakpoints** view. Before testing a restarted service, confirm a previous application process is not still holding its port.

## Trace A Layered HTTP Request

Use this exercise after a service has a controller, application service, domain logic, and persistence adapter. It demonstrates the request path without changing production behavior.

### Expected Request Flow

For a database-backed command such as opening an account, the call stack should follow this shape:

```text
HTTP request from Insomnia
  -> REST controller (input adapter)
  -> request validation and mapping
  -> application input port / application service
  -> domain object and business invariants
  -> repository output port
  -> JPA persistence adapter
  -> Spring Data repository and PostgreSQL
  -> response mapping
  -> HTTP response
```

The names differ between services, but the direction should remain the same: web and database details stay at the edges, while the application and domain layers coordinate the use case.

In Node.js terms, this is similar to:

```text
Express/Fastify route
  -> request schema validation
  -> use-case function
  -> domain module
  -> repository interface
  -> PostgreSQL adapter
```

Java interfaces such as input and output ports play a role similar to TypeScript interfaces or injected repository contracts. Spring dependency injection supplies the concrete adapter at runtime.

### Debugging Exercise

1. Start the service with **Debug As** > **Spring Boot App**, using the documented `sit` workstation configuration when connecting to SIT.
2. Put breakpoints on the controller entry point, application service, domain decision, output-port call, and persistence adapter. Breakpoints should be on executable statements, not annotations or blank lines.
3. Send one valid request from Insomnia. When Eclipse suspends, record the current class and method in the Debug view.
4. Use **Step Over** for statements in the current layer. Use **Step Into** only when the called application or domain method is the next part of the behavior being examined.
5. At the output-port breakpoint, inspect the domain identifier and non-sensitive business values. Do not inspect, copy, or log credentials, access tokens, full customer identity data, or database secrets.
6. Use **Step Return** after the layer has been understood, then **Resume** to reach the next breakpoint.
7. Confirm the request returns the expected HTTP status and that the database-backed state changed only when the use case is designed to write state.
8. Stop the debug session and remove the temporary breakpoints when the trace is complete.

### What To Record

The useful result is a short trace, not a screenshot of every stack frame:

```text
Request: <method and path>
Controller: <class and method>
Application service/input port: <class and method>
Domain decision: <invariant or state transition>
Output adapter: <port and adapter>
Persistence result: <created/read/rejected>
HTTP result: <status>
```

If the request stops in Spring, JUnit, JDK, or generated framework code, that is an implementation frame rather than a missing application layer. Use **Step Return**, **Resume**, or a breakpoint on the next application statement.

## Before A Pull Request

Run the final gate from the repository root:

```bash
./mvnw verify
```

Use Eclipse for fast feedback. Treat terminal `./mvnw verify` as the authoritative check because it matches the Maven build used by CI.
