// This file is written in D programming language
/**
*   The example demonstrates basic daemonize features. Described
*   daemon responds to SIGTERM and SIGHUP signals.
*   
*   If SIGTERM is received, daemon terminates. If SIGHUP is received,
*   daemon prints "Hello World!" message to logg.
*
*   Daemon will auto-terminate after 5 minutes of running.
*
*   Copyright: © 2014 Anton Gushcha
*   License: Subject to the terms of the MIT license, as written in the included LICENSE file.
*   Authors: NCrashed <ncrashed@gmail.com>
*/
module example01;

import std.datetime;

import dlogg.strict;
import daemonize.d;

// First you need to describe your daemon via template
alias daemon = Daemon!(
    "DaemonizeExample1", // unique name
    
    // Setting associative map signal -> callbacks
    KeyValueList!(
        Composition!(Signal.Terminate, Signal.Quit, Signal.Shutdown), (logger, signal)
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

int main()
{
    auto logger = new shared StrictLogger("logfile.log");
    return runDaemon!daemon(logger, 
        // Main function where your code is
        () {
            // will stop the daemon in 5 minutes
            auto time = Clock.currSystemTick;
            while(time + cast(TickDuration)5.dur!"minutes" > Clock.currSystemTick) {}
            logger.logInfo("Timeout. Exiting");
            return 0;
        }); 
}