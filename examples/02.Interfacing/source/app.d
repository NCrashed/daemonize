// This file is written in D programming language
/**
*   Copyright: © 2013-2014 Anton Gushcha
*   License: Subject to the terms of the MIT license, as written in the included LICENSE file.
*   Authors: NCrashed <ncrashed@gmail.com>
*/
module example02;

import std.datetime;

import dlogg.strict;
import daemonize.d;

enum RotateLogSignal = "RotateLog".customSignal;

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
        }
    )
);

version(DaemonServer)
{
    
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
    
    void main()
    {
        sendSignal!daemon(Signal.HangUp);
        sendSignal!daemon(RotateLogSignal);
        
        Thread.sleep(2.dur!"seconds");        
        sendSignal!daemon(Signal.Terminate);
    }
}