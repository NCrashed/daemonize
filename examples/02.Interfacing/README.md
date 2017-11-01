Example 02 Interfacing
======================

This small examples shows usage of custom signals and signaling to created daemons from D code.

The example has two configurations: `daemon` and `client`. `daemon` configuration creates sample
daemon and `client` creates application that sends signals to the daemon from another configuration.

To check example to be operational:
```bash
dub --config=daemon
dub --config=client
```
And check `daemon.log`, it should be something like this:
```
[2014-08-12T19:29:01.9054406]: Notice: Daemon is detached with pid 28841
[2014-08-12T19:29:11.1554692]: Notice: Doing something...
[2014-08-12T19:29:11.1555849]: Notice: Rotating log!
[2014-08-12T19:29:11.1556184]: Notice: Hello World!
[2014-08-12T19:29:12.1555279]: Notice: Exiting...
[2014-08-12T19:29:12.155748]: Notice: Daemon is terminating with code: 0
```

Explanation
===========

At the example we use custom signals, they are defined with `customSignal` function:
```D
enum RotateLogSignal = "RotateLog".customSignal;
enum DoSomethingSignal = "DoSomething".customSignal;
```

Cusom signals are mapped to realtime signals in GNU\Linux platform and to winapi events in Windows.

Daemon description is similar to [Example 01](https://github.com/NCrashed/daemonize/tree/master/examples/01.HelloWorld) one:
```D
    // Full description for daemon side
    alias daemon = Daemon!(
        "DaemonizeExample2",
        
        KeyValueList!(
            Composition!(Signal.Terminate, Signal.Quit, Signal.Shutdown, Signal.Stop), (logger)
            {
                logger.logInfo("Exiting...");
                return false;
            },
            Signal.HangUp, (logger)
            {
                logger.logInfo("Hello World!");
                return true;
            },
            RotateLogSignal, (logger)
            {
                logger.logInfo("Rotating log!");
                logger.reload;
                return true;
            },
            DoSomethingSignal, (logger)
            {
                logger.logInfo("Doing something...");
                return true;
            }
        ),
        
        (logger, shouldExit) 
        {
            // will stop the daemon in 5 minutes
            auto time = Clock.currSystemTick + cast(TickDuration)5.dur!"minutes";
            bool timeout = false;
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

        auto logger = new shared DloggLogger(logFilePath);
        return buildDaemon!daemon.run(logger);
    }
```

As custom signals are mapped to native ones at runtime, guessing the actual signal id is a quite
complicated task (Windows version binds to string names, that is much more repitable). `daemonize`
provides utilities to control created daemons from D code.

First you need a simplified description of the daemon (note: you can use full description too):
```D
    alias daemon = DaemonClient!(
        "DaemonizeExample2",
        Signal.Terminate,
        Signal.HangUp,
        RotateLogSignal,
        DoSomethingSignal
    );
```

Using the $(daemon) description `daemonize` is able recalculate signals mapping. Sending signals 
now as simple as:
```D
    alias daemon = buildDaemon!client;
    alias send = daemon.sendSignal;

    send(logger, Signal.HangUp);
    send(logger, RotateLogSignal);
    send(logger, DoSomethingSignal);
```

Manual signal sending
=====================

If you need to send signal from bash script (or none D program), you can manually calculate signal
index:
```
    signal_id = NumberOfCustomSignalInDescription + SIGRTMIN (or __libc_current_sigrtmin)
```
Or for windows (the id could be sent via `ControlService` winapi function):
```
    signal_id = NumberOfCustomSignalInDescription + 128;
```
`NumberOfCustomSignalInDescription` - counts only custom signals, native ones are skipped.

Uninstalling windows service
============================
Windows implementation uses service API and registers the daemon in global service manager.
You can uninstall the service via system tool:
```
> C:\Windows\System32\sc delete <ServiceName>
```

Or by calling:
```D
alias daemon = buildDaemon!client;
daemon.uninstall(logger);
```
