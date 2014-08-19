// This file is written in D programming language
/**
*   The example demonstrates how to run vibe.d server
*   in daemon mode.
*   
*   If SIGTERM is received, daemon terminates. If SIGHUP is received,
*   daemon prints "Hello World!" message to logg.
*
*   Copyright: © 2014 Anton Gushcha
*   License: Subject to the terms of the MIT license, as written in the included LICENSE file.
*   Authors: NCrashed <ncrashed@gmail.com>
*/
module example03;

import dlogg.strict;
import daemonize.d;

// cannot use vibe.d due symbol clash for logging
import vibe.core.core;
import vibe.core.log : setLogLevel, setLogFile, VibeLogLevel = LogLevel;
import vibe.http.server;

// Simple daemon description
alias daemon = Daemon!(
    "DaemonizeExample3", // unique name
    
    KeyValueList!(
        Composition!(Signal.Terminate, Signal.Quit, Signal.Shutdown, Signal.Stop), (logger)
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
    ),
    
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

// Vibe handler
void handleRequest(HTTPServerRequest req,
                   HTTPServerResponse res)
{
    res.writeBody("Hello World!", "text/plain");
}

int main()
{
    // Setting vibe logger 
    // daemon closes stdout/stderr and vibe logger will crash
    // if not suppress printing to console
    version(Windows) enum vibeLogName = "C:\\vibe.log";
	else enum vibeLogName = "vibe.log";
	
    setLogLevel(VibeLogLevel.none); // no stdout/stderr output
    setLogFile(vibeLogName, VibeLogLevel.info);
    setLogFile(vibeLogName, VibeLogLevel.error);
    setLogFile(vibeLogName, VibeLogLevel.warn);
            
    version(Windows) enum logFileName = "C:\\logfile.log";
	else enum logFileName = "logfile.log";
	
    auto logger = new shared StrictLogger(logFileName);
    return buildDaemon!daemon.run(logger); 
}