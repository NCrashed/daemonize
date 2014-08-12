// This file is written in D programming language
/**
*   Copyright: © 2013-2014 Anton Gushcha
*   License: Subject to the terms of the MIT license, as written in the included LICENSE file.
*   Authors: NCrashed <ncrashed@gmail.com>
*/
module daemonize.linux;

version(linux):

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

template runDaemon(alias DaemonInfo)
    if(isDaemon!DaemonInfo)
{
    int runDaemon(shared ILogger logger, int delegate() main
        , string pidFilePath = "", string lockFilePath = ""
        , int userId = -1, int groupId = -1)
    {
        savedLogger = logger;
        savedPidFilePath = pidFilePath;
        savedLockFilePath = lockFilePath;
        
        // Local locak file
        if(lockFilePath == "")
        {
            lockFilePath = expandTilde(buildPath("~", ".daemonize", DaemonInfo.daemonName ~ ".lock"));  
        }
        
        // Local pid file
        if(pidFilePath == "")
        {
            pidFilePath = expandTilde(buildPath("~", ".daemonize", DaemonInfo.daemonName ~ ".pid"));  
        }
        
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
        
        assert(canFitRealtimeSignals, "Cannot fit all custom signals to real-time signals range!");
        foreach(signame; customSignals.keys)
        {
            bindSignal(mapRealTimeSignal(signame), &signal_handler_daemon);
        }

        int code = EXIT_FAILURE;
        debug
        {
            try code = main();
            catch (Throwable ex) 
            {
                savedLogger.logError(text("Catched unhandled throwable in daemon level: ", ex.msg));
                savedLogger.logError("Terminating...");
            } 
            finally 
            {
                deleteLockFile(lockFilePath);
                deletePidFile(pidFilePath);
                terminate(code);
            }
        }
        else
        {
            try code = main();
            catch (Exception ex) 
            {
                savedLogger.logError(text("Catched unhandled exception in daemon level: ", ex.msg));
                savedLogger.logError("Terminating...");
            } 
            finally 
            {
                deleteLockFile(lockFilePath);
                deletePidFile(pidFilePath);
                terminate(code);
            }
        }
        
        return 0;
    }
    
    /// Checks is $(B sig) is actually built-in
    @safe @nogc bool isNativeSignal(Signal sig) pure nothrow 
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
    bool isCustomSignal(Signal sig)
    {
        return !isNativeSignal(sig);
    }
        
    private
    {   
        shared ILogger savedLogger;
        string savedPidFilePath;
        string savedLockFilePath;
        
        alias customSignals = DaemonInfo.signalMap.filterByKey!isCustomSignal;
         
        /** 
        *   Checks if all not native signals can be binded 
        *   to real-time signals.
        */
        bool canFitRealtimeSignals()
        {
            return customSignals.length <= __libc_current_sigrtmax - __libc_current_sigrtmin;
        }
        
        /// Converts platform independent signal to native
        @safe int mapSignal(Signal sig) pure nothrow 
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
        @safe int mapRealTimeSignal(Signal sig) pure nothrow 
        {
            assert(!isNativeSignal(sig));
            
            int counter = 0;
            foreach(key; customSignals.keys)
            {                
                if(sig == key) return counter;
                else counter++;
            }
            
            assert(false, "Parameter signal not in daemon description!");
        }
        
        /// Actual signal handler
        extern(C) void signal_handler_daemon(int sig) nothrow
        {
            foreach(key; DaemonInfo.signalMap.keys)
            {
                if(mapSignal(key) == sig)
                {
                    if(!DaemonInfo.signalMap.get!key(savedLogger))
                    {
                        try
                        {
                            deleteLockFile(savedLockFilePath);
                            deletePidFile(savedPidFilePath);
                        } catch(Throwable th) {}
                        
                        terminate(EXIT_SUCCESS);
                    } 
                    else return;
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
                savedLogger.logError("Daemon is terminating with code: " ~ to!string(code));
                savedLogger.finalize();
            
                gc_term();
                _STD_critical_term();
                _STD_monitor_staticdtor();
            }
            
            exit(code);
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
}