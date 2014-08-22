Example 01 HelloWorld
=====================

The example demonstrates simple daemon that prints `"Hello World!"` to log when receiving SIGHUP signal.

Explanation
===========

The first thing you should do is to import `daemonize.d` package that exporting all inner modules
taking in account current OS. Also daemonize package depends on `dlogg` package for easy handling
of concurrent and lazy logging:
```D
import dlogg.strict;
import daemonize.d;
```

Next step is daemon description. The package uses template to collect all daemon specific info in
one place:
```D
alias daemon = Daemon!(
```
First goes daemon name, it's very important to choose unique name as the name is used as pid/lock
file names (in linux if you don't specify your own paths) and as a service name in Windows. 
Daemonize prevents from running duplicating daemons (in linux you can change lock & pid file paths to
override the behavior):
```D
    "MyDaemonName", // unique name
```
Next goes info about signals that should be caught and processed. Some signals are occupied by druntime
(SIGUSR1 and SIGUSR2 are taken by GC), daemonize only exports `Signal`s that is safe to catch. In Windows
native linux signals are transformed to corresponding events (see also *here insert link to wiki*). 

You can bind one delegate for each native and custom signal (processed by realtime signals in linux). If
you return false - `shouldExit` function in daemon main will return true. 
Also the daemon logger is passed into each signal handler:
```D
    // Setting associative map signal -> callbacks
    KeyValueList!(
        // You can bind same delegate for several signals by Composition template
        // delegate can take additional argument to know which signal is caught
        Composition!(Signal.Terminate, Signal.Quit, Signal.Shutdown, Signal.Stop), (logger, signal)
        {
            logger.logInfo("Exiting...");
            return false; // returning false will terminate daemon
        },
        Signal.HangUp, (logger)
        {
            logger.logInfo("Hello World!");
            return true; // continue execution
        }
    )
);
```

Main function of the daemon goes further:
```D
    (logger, shouldExit) {
        // will stop the daemon in 5 minutes
        auto time = Clock.currSystemTick + cast(TickDuration)5.dur!"minutes";
        bool timeout = false;
        while(!shouldExit() && time > Clock.currSystemTick) {  }
        
        logger.logInfo("Exiting main function!");
        
        return 0;
    }
```
`shouldExit` should be `int function(shared ILogger, bool function())` type and is used to stop main function from
signal callbacks. As soon as main delegate returns, the daemon terminates. At the example the daemon will auto-stop after 5 minutes.


And last step is starting the daemon. Before the daemon is ran, you should initialize a logger:
```D
int main()
{
    // For windows is important to use absolute path for logging
    version(Windows) string logFilePath = "C:\\logfile.log";
    else string logFilePath = "logfile.log";
    
    auto logger = new shared StrictLogger(logFilePath);
```

And then:
```D
    return buildDaemon!daemon.run(logger); 
}
```

`buildDaemon` template takes daemon description and provides a set of functions (see also *wiki link*) to control described daemon.
`run` function takes initiated logger and starts the daemon.

Pid and lock files
==================
By default daemonize creates pid and lock files at `"~/.daemonize/$(daemon_name)[.pid,.lock]"` (or `"%appdata%/.daemonize/%daemon_name%[.pid,.lock]"` for Windows).
To change the behavior you can pass the paths into `run` function.

Privileges lowing
==================
For linux platform daemonize can drop root access. If you pass `groupid` and `userid` daemon will change permissions for lock/pid files and
change it own privileges to the specified values.