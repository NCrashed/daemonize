// This file is written in D programming language
/**
*   Daemon implementation for GNU/Linux platform.
*
*   The main symbols you might be interested in:
*   * $(B sendSignalDynamic) and $(B endSignal) - is easy way to send signals to created daemons
*   * $(B runDaemon) - forks daemon process and places hooks that are described by $(B Daemon) template
*
*   Copyright: © 2013-2014 Anton Gushcha
*   License: Subject to the terms of the MIT license, as written in the included LICENSE file.
*   Authors: NCrashed <ncrashed@gmail.com>
*/
module daemonize.linux;

version(linux):

static if( __VERSION__ < 2066 ) private enum nogc;

import std.conv;
import std.exception;
import std.file;
import std.path;
import std.process;
import std.stdio;
import std.string;

import std.c.linux.linux;
import std.c.stdlib;
import core.sys.linux.errno;
    
import daemonize.daemon;
import daemonize.string;
import daemonize.keymap;
import dlogg.log;

/// Returns local pid file that is used when no custom one is specified
string defaultPidFile(string daemonName)
{
    return expandTilde(buildPath("~", ".daemonize", daemonName ~ ".pid"));  
}

/// Returns local lock file that is used when no custom one is specified
string defaultLockFile(string daemonName)
{
    return expandTilde(buildPath("~", ".daemonize", daemonName ~ ".lock"));  
}

/// Checks is $(B sig) is actually built-in
@nogc @safe bool isNativeSignal(Signal sig) pure nothrow 
{
    switch(sig)
    {
        case(Signal.Abort):     return true;
        case(Signal.HangUp):    return true;
        case(Signal.Interrupt): return true;
        case(Signal.Quit):      return true;
        case(Signal.Terminate): return true;
        default: return false;
    }
}

/// Checks is $(B sig) is not actually built-in
@nogc @safe bool isCustomSignal(Signal sig) pure nothrow 
{
    return !isNativeSignal(sig);
}

/**
*   Main template in the module that actually creates daemon process.
*   $(B DaemonInfo) is a $(B Daemon) instance that holds name of the daemon
*   and hooks for numerous $(B Signal)s.
*
*   Daemon is detached from terminal, therefore it needs a preinitialized $(B logger).
*
*   As soon as daemon is ready the function executes $(B main) delegate that returns
*   application return code. 
*
*   Daemon uses pid and lock files. Pid file holds process id for communications with
*   other applications. If $(B pidFilePath) isn't set, the default path to pid file is 
*   '~/.daemonize/<daemonName>.pid'. Lock file prevents from execution of numerous copies
*   of daemons. If $(B lockFilePath) isn't set, the default path to lock file is
*   '~/.daemonize/<daemonName>.lock'. If you want several instances of one daemon, redefine
*   pid and lock files paths.
*
*   Sometimes lock and pid files are located at `/var/run` directory and needs a root access.
*   If $(B userId) and $(B groupId) parameters are set, daemon tries to create lock and pid files
*   and drops root privileges.
*
*   Example:
*   ---------
*  
*   alias daemon = Daemon!(
*       "DaemonizeExample1", // unique name
*       
*       // Setting associative map signal -> callbacks
*       KeyValueList!(
*           Composition!(Signal.Terminate, Signal.Quit, Signal.Shutdown, Signal.Stop), (logger, signal)
*           {
*               logger.logInfo("Exiting...");
*               return false; // returning false will terminate daemon
*           },
*           Signal.HangUp, (logger)
*           {
*               logger.logInfo("Hello World!");
*               return true; // continue execution
*           }
*       ),
*       
*       // Main function where your code is
*       (logger, shouldExit) {
*           // will stop the daemon in 5 minutes
*           auto time = Clock.currSystemTick + cast(TickDuration)5.dur!"minutes";
*           bool timeout = false;
*           while(!shouldExit() && time > Clock.currSystemTick) {  }
*           
*           logger.logInfo("Exiting main function!");
*           
*           return 0;
*       }
*   );
*
*   return buildDaemon!daemon.run(logger); 
*   ---------
*/
template buildDaemon(alias DaemonInfo)
    if(isDaemon!DaemonInfo || isDaemonClient!DaemonInfo)
{
    alias daemon = readDaemonInfo!DaemonInfo;
 
    static if(isDaemon!DaemonInfo)
    {
        int run(shared ILogger logger
            , string pidFilePath = "", string lockFilePath = ""
            , int userId = -1, int groupId = -1)
        {        
            // Local locak file
            if(lockFilePath == "")
            {
                lockFilePath = defaultLockFile(DaemonInfo.daemonName);  
            }
            
            // Local pid file
            if(pidFilePath == "")
            {
                pidFilePath = defaultPidFile(DaemonInfo.daemonName);
            }
            
            savedLogger = logger;
            savedPidFilePath = pidFilePath;
            savedLockFilePath = lockFilePath;
            
            // Handling lockfile if any
            enforceLockFile(lockFilePath, userId);
            scope(exit) deleteLockFile(lockFilePath);
            
            // Saving process ID and session ID
            pid_t pid, sid;
            
            // For off the parent process
            pid = fork();
            if(pid < 0)
            {
                savedLogger.logError("Failed to start daemon: fork failed");
                
                // Deleting fresh lockfile
                deleteLockFile(lockFilePath);
                    
                terminate(EXIT_FAILURE);
            }
            
            // If we got good PID, then we can exit the parent process
            if(pid > 0)
            {
                // handling pidfile if any
                writePidFile(pidFilePath, pid, userId);
    
                savedLogger.logInfo(text("Daemon is detached with pid ", pid));
                terminate(EXIT_SUCCESS, false);
            }
            
            // dropping root privileges
            dropRootPrivileges(groupId, userId);
            
            // Change the file mode mask and suppress printing to console
            umask(0);
            savedLogger.minOutputLevel(LoggingLevel.Muted);
            
            // Handling of deleting pid file
            scope(exit) deletePidFile(pidFilePath);
            
            // Create a new SID for the child process
            sid = setsid();
            if (sid < 0)
            {
                deleteLockFile(lockFilePath);
                deletePidFile(pidFilePath);
                    
                terminate(EXIT_FAILURE);
            }
    
            // Close out the standard file descriptors
            close(0);
            close(1);
            close(2);
    
            void bindSignal(int sig, sighandler_t handler)
            {
                enforce(signal(sig, handler) != SIG_ERR, text("Cannot catch signal ", sig));
            }
            
            // Bind native signals
            // other signals cause application to hang or cause no signal detection
            // sigusr1 sigusr2 are used by garbage collector
            bindSignal(SIGABRT, &signal_handler_daemon);
            bindSignal(SIGTERM, &signal_handler_daemon);
            bindSignal(SIGQUIT, &signal_handler_daemon);
            bindSignal(SIGINT,  &signal_handler_daemon);
            bindSignal(SIGQUIT, &signal_handler_daemon);
            bindSignal(SIGHUP, &signal_handler_daemon);
            
            assert(daemon.canFitRealtimeSignals, "Cannot fit all custom signals to real-time signals range!");
            foreach(signame; daemon.customSignals)
            {
                bindSignal(daemon.mapRealTimeSignal(signame), &signal_handler_daemon);
            }
    
            int code = EXIT_FAILURE;
            try code = DaemonInfo.mainFunc(savedLogger, &shouldExitFunc );
            catch (Throwable th) 
            {
                savedLogger.logError(text("Catched unhandled throwable at daemon level at ", th.file, ": ", th.line, " : ", th.msg));
                savedLogger.logError("Terminating...");
            } 
            finally 
            {
                deleteLockFile(lockFilePath);
                deletePidFile(pidFilePath);
            }
            
            terminate(code);
            return 0;
        }
    }
    
    /**
    *   As custom signals are mapped to realtime signals at runtime, it is complicated
    *   to calculate signal number by hands. The function simplifies sending signals
    *   to daemons that were created by the package.
    *
    *   The $(B DaemonInfo) could be a full description of desired daemon or simplified one
    *   (template ($B DaemonClient). That info is used to remap custom signals to realtime ones.
    *
    *   $(B daemonName) is passed as runtime parameter to be able read service name at runtime.
    *   $(B signal) is the signal that you want to send. $(B pidFilePath) is optional parameter
    *   that overrides default algorithm of finding pid files (calculated from $(B daemonName) in form
    *   of '~/.daemonize/<daemonName>.pid').   
    *
    *   See_Also: $(B sendSignal) version of the function that takes daemon name from $(B DaemonInfo). 
    */
    void sendSignalDynamic(shared ILogger logger, string daemonName, Signal signal, string pidFilePath = "")
    {
        // Try to find at default place
        if(pidFilePath == "")
        {
            pidFilePath = defaultPidFile(daemonName);
        }
        
        // Reading file
        int pid = readPidFile(pidFilePath);
        
        logger.logInfo(text("Sending signal ", signal, " to daemon ", daemonName));
        kill(pid, readDaemonInfo!DaemonInfo.mapSignal(signal));
    }
    
    /// ditto
    void sendSignal(shared ILogger logger, Signal signal, string pidFilePath = "")
    {
        sendSignalDynamic(logger, DaemonInfo.daemonName, signal, pidFilePath);
    }

    /**
    *   In GNU/Linux daemon doesn't require deinstallation.
    */
    void uninstall() {}
    
    /**
    *   Saves info about exception into daemon $(B logger)
    */
    static class LoggedException : Exception
    {
        @safe nothrow this(string msg, string file = __FILE__, size_t line = __LINE__, Throwable next = null)
        {
            savedLogger.logError(msg);
            super(msg, file, line, next);
        }
    
        @safe nothrow this(string msg, Throwable next, string file = __FILE__, size_t line = __LINE__)
        {
            savedLogger.logError(msg);
            super(msg, file, line, next);
        }
    }
    
    private
    {   
        shared ILogger savedLogger;
        string savedPidFilePath;
        string savedLockFilePath;
        
        __gshared bool shouldExit;
        
        bool shouldExitFunc()
        {
            return shouldExit;
        } 
        
        /// Actual signal handler
        static if(isDaemon!DaemonInfo) extern(C) void signal_handler_daemon(int sig) nothrow
        {
            foreach(signal; DaemonInfo.signalMap.keys)
            {
                alias handler = DaemonInfo.signalMap.get!signal;
                
                static if(isComposition!signal)
                {
                    foreach(subsignal; signal.signals)
                    {
                        if(daemon.mapSignal(subsignal) == sig)
                        {
                            try
                            {
                                static if(__traits(compiles, handler(savedLogger, subsignal)))
                                    bool res = handler(savedLogger, subsignal);
                                else
                                    bool res = handler(savedLogger);
                                    
                                if(!res)
                                {
                                    deleteLockFile(savedLockFilePath);
                                    deletePidFile(savedPidFilePath);
                                    
                                    shouldExit = true;
                                    //terminate(EXIT_SUCCESS);
                                } 
                                else return;
                                
                            } catch(Throwable th) 
                            {
                                savedLogger.logError(text("Caught at signal ", subsignal," handler: ", th));
                            }
                        }
                    }
                } else
                {
                    if(daemon.mapSignal(signal) == sig)
                    {
                        try
                        {
                            static if(__traits(compiles, handler(savedLogger, signal)))
                                bool res = handler(savedLogger, signal);
                            else
                                bool res = handler(savedLogger);
                                
                            if(!res)
                            {
                                deleteLockFile(savedLockFilePath);
                                deletePidFile(savedPidFilePath);
                                
                                shouldExit = true;
                                //terminate(EXIT_SUCCESS);
                            } 
                            else return;
                        } 
                        catch(Throwable th) 
                        {
                            savedLogger.logError(text("Caught at signal ", signal," handler: ", th));
                        }
                    }
                }
             }
        }
        
        /**
        *   Checks existence of special lock file at $(B path) and prevents from
        *   continuing if there is it. Also changes permissions for the file if
        *   $(B userid) not -1.
        */
        void enforceLockFile(string path, int userid)
        {
            if(path.exists)
            {
                savedLogger.logError(text("There is another daemon instance running: lock file is '",path,"'"));
                savedLogger.logInfo("Remove the file if previous instance if daemon has crashed");
                terminate(-1);
            } else
            {
                if(!path.dirName.exists)
                {
                    mkdirRecurse(path.dirName);
                }
                auto file = File(path, "w");
                file.close();
            }
            
            // if root, change permission on file to be able to remove later
            if (getuid() == 0 && userid >= 0) 
            {
                savedLogger.logDebug("Changing permissions for lock file: ", path);
                executeShell(text("chown ", userid," ", path.dirName));
                executeShell(text("chown ", userid," ", path));
            }
        }
        
        /**
        *   Removing lock file while terminating.
        */
        void deleteLockFile(string path)
        {
            if(path.exists)
            {
                try
                {
                    path.remove();
                }
                catch(Exception e)
                {
                    savedLogger.logWarning(text("Failed to remove lock file: ", path));
                    return;
                }
            }
        }
        
        /**
        *   Writing down file with process id $(B pid) to $(B path) and changes
        *   permissions to $(B userid) (if not -1 and there is root dropping).
        */
        void writePidFile(string path, int pid, uint userid)
        {
            try
            {
                if(!path.dirName.exists)
                {
                    mkdirRecurse(path.dirName);
                }
                auto file = File(path, "w");
                scope(exit) file.close();
                
                file.write(pid);
                
                // if root, change permission on file to be able to remove later
                if (getuid() == 0 && userid >= 0) 
                {
                    savedLogger.logDebug("Changing permissions for pid file: ", path);
                    executeShell(text("chown ", userid," ", path.dirName));
                    executeShell(text("chown ", userid," ", path));
                }
            } catch(Exception e)
            {
                savedLogger.logWarning(text("Failed to write pid file: ", path));
                return;
            }
        }
        
        /// Removing process id file
        void deletePidFile(string path)
        {
            try
            {
                path.remove();
            } catch(Exception e)
            {
                savedLogger.logWarning(text("Failed to remove pid file: ", path));
                return;
            }
        }
        
        /**
        *   Dropping root privileges to $(B groupid) and $(B userid).
        */
        void dropRootPrivileges(int groupid, int userid)
        {
            if (getuid() == 0) 
            {
                if(groupid < 0 || userid < 0)
                {
                    savedLogger.logWarning("Running as root, but doesn't specified groupid and/or userid for"
                        " privileges lowing!");
                    return;
                }
                
                savedLogger.logInfo("Running as root, dropping privileges...");
                // process is running as root, drop privileges 
                if (setgid(groupid) != 0)
                {
                    savedLogger.logError(text("setgid: Unable to drop group privileges: ", strerror(errno).fromStringz));
                    assert(false);
                }
                if (setuid(userid) != 0)
                {
                    savedLogger.logError(text("setuid: Unable to drop user privileges: ", strerror(errno).fromStringz));
                    assert(false);
                }
            }
        }
        
        /// Terminating application with cleanup
        void terminate(int code, bool isDaemon = true) nothrow
        {
            if(isDaemon)
            {
                savedLogger.logInfo("Daemon is terminating with code: " ~ to!string(code));
                savedLogger.finalize();
            
                gc_term();
                _STD_critical_term();
                _STD_monitor_staticdtor();
            }
            
            exit(code);
        }
        
        /// Tries to read a number from $(B filename)
        int readPidFile(string filename)
        {
            if(!filename.exists)
                throw new LoggedException("Cannot find pid file at '" ~ filename ~ "'!");
            
            auto file = File(filename, "r");
            return file.readln.to!int;
        }
    }
}
private
{
    // https://issues.dlang.org/show_bug.cgi?id=13282
    extern (C) nothrow
    {
        int __libc_current_sigrtmin();
        int __libc_current_sigrtmax();
    }
    extern (C) nothrow
    {
        // These are for control of termination
        void _STD_monitor_staticdtor();
        void _STD_critical_term();
        void gc_term();
        
        alias int pid_t;
        
        // daemon functions
        pid_t fork();
        int umask(int);
        int setsid();
        int close(int fd);

        // Signal trapping in Linux
        alias void function(int) sighandler_t;
        sighandler_t signal(int signum, sighandler_t handler);
        char* strerror(int errnum) pure;
    }
    
    /// Handles utilities for signal mapping from local representation to GNU/Linux one
    template readDaemonInfo(alias DaemonInfo)
        if(isDaemon!DaemonInfo || isDaemonClient!DaemonInfo)
    {
        template extractCustomSignals(T...)
        {
            static if(T.length < 2) alias extractCustomSignals = T[0];
            else static if(isComposition!(T[1])) alias extractCustomSignals = StrictExpressionList!(T[0].expand, staticFilter!(isCustomSignal, T[1].signals));
            else static if(isCustomSignal(T[1])) alias extractCustomSignals = StrictExpressionList!(T[0].expand, T[1]);
            else alias extractCustomSignals = T[0];
        }
        
        template extractNativeSignals(T...)
        {
            static if(T.length < 2) alias extractNativeSignals = T[0];
            else static if(isComposition!(T[1])) alias extractNativeSignals = StrictExpressionList!(T[0].expand, staticFilter!(isNativeSignal, T[1].signals));
            else static if(isNativeSignal(T[1])) alias extractNativeSignals = StrictExpressionList!(T[0].expand, T[1]);
            else alias extractNativeSignals = T[0];
        }
        
        static if(isDaemon!DaemonInfo)
        {
            alias customSignals = staticFold!(extractCustomSignals, StrictExpressionList!(), DaemonInfo.signalMap.keys).expand; //pragma(msg, [customSignals]);
            alias nativeSignals = staticFold!(extractNativeSignals, StrictExpressionList!(), DaemonInfo.signalMap.keys).expand; //pragma(msg, [nativeSignals]);
        } else
        { 
            alias customSignals = staticFold!(extractCustomSignals, StrictExpressionList!(), DaemonInfo.signals).expand; //pragma(msg, [customSignals]);
            alias nativeSignals = staticFold!(extractNativeSignals, StrictExpressionList!(), DaemonInfo.signals).expand; //pragma(msg, [nativeSignals]);
        }
        
        /** 
        *   Checks if all not native signals can be binded 
        *   to real-time signals.
        */
        bool canFitRealtimeSignals()
        {
            return customSignals.length <= __libc_current_sigrtmax - __libc_current_sigrtmin;
        }
        
        /// Converts platform independent signal to native
        @safe int mapSignal(Signal sig) nothrow 
        {
            switch(sig)
            {
                case(Signal.Abort):     return SIGABRT;
                case(Signal.HangUp):    return SIGHUP;
                case(Signal.Interrupt): return SIGINT;
                case(Signal.Quit):      return SIGQUIT;
                case(Signal.Terminate): return SIGTERM;
                default: return mapRealTimeSignal(sig);                    
            }
        }
        
        /// Converting custom signal to real-time signal
        @trusted int mapRealTimeSignal(Signal sig) nothrow 
        {
            assert(!isNativeSignal(sig));
            
            int counter = 0;
            foreach(key; customSignals)
            {                
                if(sig == key) return counter + __libc_current_sigrtmin;
                else counter++;
            }
            
            assert(false, "Parameter signal not in daemon description!");
        }
    }
}