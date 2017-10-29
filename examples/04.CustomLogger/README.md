Example 04 Custom Logger
========================

This small example shows how to pass your custom logging library to daemonize.

Explanation
===========

Create a synchronized class that implements the IDaemonLogger interface and wraps your logging library.

```
synchronized class MyLogger : IDaemonLogger
{
    private string file;

    this(string filePath) @trusted
    {
        file = filePath;
    }

    void logDebug(string message) nothrow
    {
        debug {
            import std.stdio : toFile;
            try message.toFile(file);
            catch (Exception) {}
        }
    }

    void logInfo(lazy string message) nothrow
    {
        import std.stdio : toFile;
        try message.toFile(file);
        catch (Exception) {}
    }
    /* ... */
}
```

Create your daemon template, then in your `main` function pass your logging class to daemonize:

```
alias daemon = Daemon!(
    "DaemonizeExample4", // unique name

    // Setting associative map signal -> callbacks
    KeyValueList!(
        // You can bind same delegate for several signals by Composition template
        // delegate can take additional argument to know which signal is caught
        Composition!(Signal.Terminate, Signal.Quit, Signal.Shutdown, Signal.Stop), (logger, signal)
        {
            logger.logInfo("Exiting...");
            return false; // returning false will terminate daemon
        },
        Composition!(Signal.HangUp,Signal.Pause,Signal.Continue), (logger)
        {
            logger.logInfo("Hello World!");
            return true; // continue execution
        }
    ),

    // Main function where your code is
    (logger, shouldExit) {
        // will stop the daemon in 5 minutes
        auto time = Clock.currSystemTick + cast(TickDuration)5.dur!"minutes";
        while(!shouldExit() && time > Clock.currSystemTick) {  }

        logger.logInfo("Exiting main function!");

        return 0;
    }
);

int main()
{
    // For windows is important to use absolute path for logging
    version(Windows) string logFilePath = "C:\\logfile.log";
    else string logFilePath = "logfile.log";

    return buildDaemon!daemon.run(new shared MyLogger(logFilePath));
}
```

