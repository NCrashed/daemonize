Example 03 Integration with vibe.d
==================================

The example shows how to create [vibe.d](http://vibed.org/) daemon. The example http server binds
to `localhost:8080` and responds with simple hello-world page.

Explanation
===========

The vibe and dlogg package use same names for logging utilities, thats why we need some qualified imports:
```D
import dlogg.strict;
import daemonize.d;

// cannot use vibe.d due symbol clash for logging
import vibe.core.core;
import vibe.core.log : setLogLevel, setLogFile, VibeLogLevel = LogLevel;
import vibe.http.server;
```

Daemon description from [example01](https://github.com/NCrashed/daemonize/tree/master/examples/01.HelloWorld), the main difference is that you don't
need manually stop daemon via `false` return. The `exitEventLoop` will stop main execution.
```D
alias daemon = Daemon!(
    "DaemonizeExample3", // unique name
    
    KeyValueList!(
        Composition!(Signal.Terminate, Signal.Quit, Signal.Shutdown, Signal.Stop), (logger)
        {
            logger.logInfo("Exiting...");
            
            // No need to force exit here
            // main will stop after the call 
            exitEventLoop(true);
            return true; 
        },
        Signal.HangUp, (logger)
        {
            logger.logInfo("Hello World!");
            return true;
        }
    ),
    
    // Default vibe initialization should be performed after daemon forking as inner vibe resources are thread local
    (logger, shouldExit) {
        // Default vibe initialization
        auto settings = new HTTPServerSettings;
        settings.port = 8080;
        settings.bindAddresses = ["127.0.0.1"];

        listenHTTP(settings, &handleRequest);

        // All exceptions are caught by daemonize
        return runEventLoop();
    }
);

```

The simpliest vibe handler that responds with `"Hello World!"` to any request:
```D
void handleRequest(HTTPServerRequest req,
                   HTTPServerResponse res)
{
    res.writeBody("Hello World!", "text/plain");
}
```

The most important part is to configure vibe logger or you will get 'Invalid file handle' error at application initialization:
```D
int main()
{
    // Setting vibe logger 
    // daemon closes stdout/stderr and vibe logger will crash
    // if not suppress printing to console
    version(Windows) enum vibeLogName = "C:\\vibe.log";
    else enum vibeLogName = "vibe.log";

    // no stdout/stderr output
    version(Windows) {}
    else setLogLevel(VibeLogLevel.none);

    setLogFile(vibeLogName, VibeLogLevel.info);

    version(Windows) enum logFileName = "C:\\logfile.log";
    else enum logFileName = "logfile.log";
    
    auto logger = new shared StrictLogger(logFileName);
    return buildDaemon!daemon.run(logger); 
}
```
