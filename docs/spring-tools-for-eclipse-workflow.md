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

## Before A Pull Request

Run the final gate from the repository root:

```bash
./mvnw verify
```

Use Eclipse for fast feedback. Treat terminal `./mvnw verify` as the authoritative check because it matches the Maven build used by CI.
