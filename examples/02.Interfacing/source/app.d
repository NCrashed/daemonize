// This file is written in D programming language
/**
*   The example shows how to send signals to daemons created by
*   daemonize.
*
*   Copyright: © 2014 Anton Gushcha
*   License: Subject to the terms of the MIT license, as written in the included LICENSE file.
*   Authors: NCrashed <ncrashed@gmail.com>
*/
module example02;

import std.datetime;

import dlogg.strict;
import daemonize.d;

// Describing custom signals
enum RotateLogSignal = "RotateLog".customSignal;
enum DoSomethingSignal = "DoSomething".customSignal;

version(DaemonServer)
{
    // Full description for daemon side
    alias daemon = Daemon!(
        "DaemonizeExample2",
        
        KeyValueList!(
            Signal.Terminate, (logger)
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
        )
    );
    
    int main()
    {
        auto logger = new shared StrictLogger("daemon.log");
        return runDaemon!daemon(logger, 
            () {
                // will stop the daemon in 5 minutes
                auto time = Clock.currSystemTick;
                while(time + cast(TickDuration)5.dur!"minutes" > Clock.currSystemTick) {}
                logger.logInfo("Timeout. Exiting");
                return 0;
            }); 
    }
}
version(DaemonClient)
{
    import core.thread;
    import core.time;
    
    // For client you don't need full description of the daemon
    // the truncated description consists only of name and a list of
    // supported signals
    alias daemon = DaemonClient!(
        "DaemonizeExample2",
        Signal.Terminate,
        Signal.HangUp,
        RotateLogSignal,
        DoSomethingSignal
    );
    
    void main()
    {
        sendSignal!daemon(Signal.HangUp);
        sendSignal!daemon(RotateLogSignal);
        sendSignal!daemon(DoSomethingSignal);
        
        Thread.sleep(1.dur!"seconds");        
        sendSignal!daemon(Signal.Terminate);
    }
}