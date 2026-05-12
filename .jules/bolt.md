## 2024-04-17 - Fast Startup by Resolving N+1 DB Queries
**Learning:** Sequential DB reads iterating over sessions during initial app startup (N+1 query) severely degrades startup time on Flutter/Dart due to repetitive thread boundary and IPC overhead associated with SQLite bindings.
**Action:** Replaced sequential awaits on db queries in a `for` loop with `Future.wait(...)` coupled with `.map` to execute memory retrieval concurrently during the initialization phase.
