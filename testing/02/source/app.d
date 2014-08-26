// This file is written in D programming language
/**
*   Copyright: © 2014 Anton Gushcha
*   License: Subject to the terms of the MIT license, as written in the included LICENSE file.
*   Authors: NCrashed <ncrashed@gmail.com>
*/
module test02;

import std.file;

import dlogg.strict;
import daemonize.d;

version(Server)
{
    alias daemon = Daemon!(
        "Test2",
        
        KeyValueList!(
            Composition!(Signal.Terminate, Signal.Quit, Signal.Shutdown, Signal.Stop), (shared ILogger logger, Signal signal)
            {
                write("output.txt", "Test string 1");
                return false; 
            },
            Signal.HangUp, (logger)
            {
                write("output.txt", "Test string 2");
                return false;
            }),
        
        (logger, shouldExit) {
            while(!shouldExit()) {}
            return 0;
        }
    );
    
    int main()
    {
        return buildDaemon!daemon.run(new shared StrictLogger("logfile.log")); 
    }
} 
else
{
    alias daemon = DaemonClient!(
        "Test2",
        Composition!(Signal.Terminate, Signal.Quit, Signal.Shutdown, Signal.Stop),
        Signal.HangUp
    );
    
    int main()
    {
        alias client = buildDaemon!daemon;
        
        Signal sig;
        version(Test1) sig = Signal.Terminate;
        version(Test2) sig = Signal.Quit;
        version(Test3) sig = Signal.Shutdown;
        version(Test4) sig = Signal.Stop;
        version(Test5) sig = Signal.HangUp;
        
        client.sendSignal(new shared StrictLogger("logfile.log"), sig);
        return 0;
    }
}