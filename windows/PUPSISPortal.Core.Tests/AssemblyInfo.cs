// The stores expose a process-wide test directory (SetTestDirectory), so store-
// touching tests across classes must not run concurrently or they'd stomp each
// other's directory. The suite is tiny (runs in tens of ms), so serializing it
// costs nothing and removes the race.
[assembly: Xunit.CollectionBehavior(DisableTestParallelization = true)]
