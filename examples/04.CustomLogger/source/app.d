// This file is written in D programming language
/**
*   The example demonstrates using a custom logger with daemonize.
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
module example04;

import std.datetime;

import daemonize.d;

synchronized class MyLogger : IDaemonLogger
{
    private string file;

    this(string filePath) @trusted
    {
        file = filePath;
    }

    void logDebug(string message) nothrow
    {
        logInfo(message);
    }

    void logInfo(lazy string message) nothrow
    {
        static if( __VERSION__ > 2071 )
        {
            import std.stdio : toFile;
            try message.toFile(file);
            catch (Exception) {}
        }
    }

    void logWarning(lazy string message) nothrow
    {
        logInfo(message);
    }

    void logError(lazy string message) @trusted nothrow
    {
        logInfo(message);
    }

    DaemonLogLevel minLogLevel() @property
    {
        return DaemonLogLevel.Notice;
    }

    void minLogLevel(DaemonLogLevel level) @property {}

    DaemonLogLevel minOutputLevel() @property
    {
        return DaemonLogLevel.Notice;
    }

    void minOutputLevel(DaemonLogLevel level) @property {}
    void finalize() @trusted nothrow {}
    void reload() {}
}

// First you need to describe your daemon via template
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
