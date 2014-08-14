Example 03 Integration with vibe.d
==================================

The example shows how to create vibe.d daemon. The example http server binds
to localhost:8080 and responds with simple hello-world page.

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
        Signal.Terminate, (logger)
        {
            logger.logInfo("Exiting...");
            
            // No need to force exit here
            // main will stop after the call 
            exitEventLoop();
            return true; 
        },
        Signal.HangUp, (logger)
        {
            logger.logInfo("Hello World!");
            return true;
        }
    )
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
    enum vibeLogName = "vibe.log";
    setLogLevel(VibeLogLevel.none); // no stdout/stderr output
    setLogFile(vibeLogName, VibeLogLevel.info);
    setLogFile(vibeLogName, VibeLogLevel.error);
    setLogFile(vibeLogName, VibeLogLevel.warn);
```

Default vibe initialization should be performed after daemon forking:
```D
    auto logger = new shared StrictLogger("logfile.log");
    return runDaemon!daemon(logger, 
        () {
            // Default vibe initialization
            auto settings = new HTTPServerSettings;
            settings.port = 8080;
            settings.bindAddresses = ["127.0.0.1"];
            
            listenHTTP(settings, &handleRequest);
        
            // All exceptions are caught by daemonize
            return runEventLoop();
        }); 
```