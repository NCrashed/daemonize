// This file is written in D programming language
/**
*    Implementation of cross-platform daemon API for Windows platform.
*
*   Copyright: © 2013-2014 Anton Gushcha
*   License: Subject to the terms of the MIT license, as written in the included LICENSE file.
*   Authors: NCrashed <ncrashed@gmail.com>
*/
module daemonize.windows;

version(Windows):

static if( __VERSION__ < 2066 ) private enum nogc;

import core.sys.windows.windows;
import core.thread;
import std.datetime;
import std.string;
import std.typetuple;
import std.utf;
import std.c.stdlib;
import std.conv : text;
import std.typecons;

import daemonize.daemon;
import daemonize.string;
import daemonize.keymap;
import daemonize.log;

/// Windows version doesn't use pid files
string defaultPidFile(string daemonName)
{
    return "";
}

/// Windows version doesn't use lock files
string defaultLockFile(string daemonName)
{
    return "";
}

/// Checks is $(B sig) is actually built-in
@nogc @safe bool isNativeSignal(Signal sig) pure nothrow
{
    switch(sig)
    {
        case(Signal.Stop):           return true;
        case(Signal.Continue):       return true;
        case(Signal.Pause):          return true;
        case(Signal.Shutdown):       return true;
        case(Signal.Interrogate):    return true;
        case(Signal.NetBindAdd):     return true;
        case(Signal.NetBindDisable): return true;
        case(Signal.NetBindEnable):  return true;
        case(Signal.NetBindRemove):  return true;
        case(Signal.ParamChange):    return true;
        default: return false;
    }
}

/// Checks is $(B sig) is not actually built-in
@nogc @safe bool isCustomSignal(Signal sig) pure nothrow
{
    return !isNativeSignal(sig);
}

/**
*    The template holds a set of functions that build, run and send signals to daemons
*    that are built with $(B Daemon) or $(B DaemonClient) template.
*
*    Truncated $(B DaemonClient) aren't able to run described daemon, only signal sending
*    and daemon uninstalling.
*/
template buildDaemon(alias DaemonInfo, DWORD startType =  SERVICE_DEMAND_START)
    if(isDaemon!DaemonInfo || isDaemonClient!DaemonInfo)
{
    /// Support functions
    private alias daemon = readDaemonInfo!DaemonInfo;

    // DaemonClient cannot run daemon
    static if(isDaemon!DaemonInfo)
    {
        /**
        *    Starts daemon that is described by $(B DaemonInfo). Daemon is implemented as
        *    windows service and auto-installed in SC manager. If you want to uninstall the
        *    service, you can use $(B uninstall) function or system call:
        *    ----------
        *    C:\Windows\System32\sc.exe delete <daemonName>
        *    ----------
        *
        *    If the service is already installed and is stopped, the function tries to start daemon.
        *    Otherwise it fails and returns EXIT_FAILURE code.
        *
        *    $(B logger) is a initialized logger for the daemon, you should
        *    use absolute names for Windows for logger files.
        *
        *    $(B pidFilePath), $(B lockFilePath), $(B userId) and $(B groupId)
        *    are ignored for Windows platform.
        *
        *    See_Also: $(B uninstall)
        *
        *    Example:
        *    ----------
        *   // First you need to describe your daemon via template
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
        *   //...
        *   buildDaemon!daemon.run(new shared DloggLogger(logFilePath));
        *    ----------
        */
        int run(shared IDaemonLogger logger
            , string pidFilePath = "", string lockFilePath = ""
            , int userId = -1, int groupId = -1)
        {
            savedLogger = logger;

            auto maybeStatus = queryServiceStatus();
            if(maybeStatus.isNull)
            {
                savedLogger.logInfo("No service is installed!");
                serviceInstall(startType);
                serviceStart();
                return EXIT_SUCCESS;
            }
            else
            {
                auto initResult = serviceInit();
                if(initResult == ServiceInitState.NotService)
                {
                    auto state = maybeStatus.get.dwCurrentState;
                    if(state == SERVICE_STOPPED)
                    {
                        savedLogger.logInfo("Starting installed service!");
                        serviceStart();
                    }
                } else if(initResult == initResult.OtherError)
                {
                    savedLogger.logError("Service is already running!");
                    return EXIT_FAILURE;
                }

                return EXIT_SUCCESS;
            }
        }
    }

    /**
    *   Utility function that helps to uninstall the service from the system.
    *
    *   Note: Can be used with $(B DaemonClient) template, actually you can ommit signal list for the template.
    */
    void uninstall(shared IDaemonLogger logger)
    {
        savedLogger = logger;

        auto maybeStatus = queryServiceStatus();
        if(!maybeStatus.isNull)
        {
            serviceRemove();
        }
        else
        {
            savedLogger.logWarning("Cannot find service in SC manager! No uninstallation action is performed.");
        }
    }

    /**
    *   Sends singal $(B sig) for described daemon. All signals are sent via $(B ControlService) WINAPI function.
    *
    *   $(B logger) is used to log all errors.
    *
    *   $(B pidFilePath) is ignored for Windows platform.
    *
    *   Note: Can be used with $(B DaemonClient) template.
    */
    void sendSignal(shared IDaemonLogger logger, Signal sig, string pidFilePath = "")
    {
        savedLogger = logger;

        auto manager = getSCManager;
        scope(exit) CloseServiceHandle(manager);

        auto service = getService(manager, daemon.getControlAccessFlag(sig));
        scope(exit) CloseServiceHandle(service);

        if(!ControlService(service, daemon.mapSignal(sig), &serviceStatus))
            throw new LoggedException(text("Failed to send signal to service ", DaemonInfo.daemonName, ". Details: ", getLastErrorDescr));

        logger.logInfo(text("Sending signal ", sig, " to daemon ", DaemonInfo.daemonName));
    }

    /// ditto with dynamic service name
    void sendSignalDynamic(shared IDaemonLogger logger, string serviceName, Signal sig, string pidFilePath = "")
    {
        savedLogger = logger;

        auto manager = getSCManager;
        scope(exit) CloseServiceHandle(manager);

        auto service = OpenServiceW(manager, cast(LPWSTR)serviceName.toUTF16z, daemon.getControlAccessFlag(sig));
        if(service is null) throw new LoggedException(text("Failed to open service! ", getLastErrorDescr));
        scope(exit) CloseServiceHandle(service);

        if(!ControlService(service, daemon.mapSignal(sig), &serviceStatus))
            throw new LoggedException(text("Failed to send signal to service ", serviceName, ". Details: ", getLastErrorDescr));

        logger.logInfo(text("Sending signal ", sig, " to daemon ", serviceName));
    }

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
        __gshared SERVICE_STATUS serviceStatus;
        __gshared SERVICE_STATUS_HANDLE serviceStatusHandle;
        shared IDaemonLogger savedLogger;

        bool shouldExit()
        {
            return serviceStatus.dwCurrentState == SERVICE_STOPPED;
        }

        static if(isDaemon!DaemonInfo)
        {
            extern(System) static void serviceMain(uint argc, wchar** args) nothrow
            {
                try
                {
                    // Windows don't know anything about our runtime
                    // so register the thread at druntime's thread subsystem
                    // and manually run all TLS constructors and destructors
                    thread_attachThis();
                    rt_moduleTlsCtor();
                    scope(exit) rt_moduleTlsDtor();

                    int code = EXIT_FAILURE;

                    serviceStatus.dwServiceType = SERVICE_WIN32_OWN_PROCESS;

                    savedLogger.reload;
                    savedLogger.minOutputLevel = DaemonLogLevel.Muted;
                    savedLogger.logInfo("Registering control handler");

                    serviceStatusHandle = RegisterServiceCtrlHandlerW(cast(LPWSTR)DaemonInfo.daemonName.toUTF16z, &controlHandler);
                    if(serviceStatusHandle is null)
                    {
                        savedLogger.logError("Failed to register control handler!");
                        savedLogger.logError(getLastErrorDescr);
                        return;
                    }

                    savedLogger.logInfo("Running user main delegate");
                    reportServiceStatus(SERVICE_RUNNING, NO_ERROR, 0.dur!"msecs");
                    try code = DaemonInfo.mainFunc(savedLogger, &shouldExit);
                    catch (Throwable ex)
                    {
                        savedLogger.logError(text("Catched unhandled throwable at daemon level at ", ex.file, ":", ex.line, ": ", ex.msg));
                        savedLogger.logError("Terminating...");
                        reportServiceStatus(SERVICE_STOPPED, EXIT_FAILURE, 0.dur!"msecs");
                        return;
                    }
                    reportServiceStatus(SERVICE_STOPPED, NO_ERROR, 0.dur!"msecs");
                }
                catch(Throwable th)
                {
                    savedLogger.logError(text("Internal daemon error, please bug report: ", th.file, ":", th.line, ": ", th.msg));
                    savedLogger.logError("Terminating...");
                }
            }

            extern(System) static void controlHandler(DWORD fdwControl) nothrow
            {
                switch(fdwControl)
                {
                    foreach(signal; DaemonInfo.signalMap.keys)
                    {
                        alias handler = DaemonInfo.signalMap.get!signal;

                        static if(isComposition!signal)
                        {
                            foreach(subsignal; signal.signals)
                            {
                                case(daemon.mapSignal(subsignal)):
                                {
                                    savedLogger.logInfo(text("Caught signal ", subsignal));
                                    bool res = true;
                                    try
                                    {
                                        static if(__traits(compiles, handler(savedLogger, subsignal)))
                                            res = handler(savedLogger, subsignal);
                                        else
                                            res = handler(savedLogger);

                                        if(!res) reportServiceStatus(SERVICE_STOPPED, NO_ERROR, 0.dur!"msecs");
                                    }
                                    catch(Throwable th)
                                    {
                                        savedLogger.logError(text("Caught a throwable at signal ", subsignal, " handler: ", th));
                                    }
                                    return;
                                }
                            }
                        }
                        else
                        {
                            case(daemon.mapSignal(signal)):
                            {
                                savedLogger.logInfo(text("Caught signal ", signal));
                                bool res = true;
                                try
                                {
                                    static if(__traits(compiles, handler(savedLogger, signal)))
                                        res = handler(savedLogger, signal);
                                    else
                                        res = handler(savedLogger);

                                    if(!res) reportServiceStatus(SERVICE_STOPPED, NO_ERROR, 0.dur!"msecs");
                                }
                                catch(Throwable th)
                                {
                                    savedLogger.logError(text("Caught a throwable at signal ", signal, " handler: ", th));
                                }
                                return;
                            }
                        }
                    }
                    default:
                    {
                        savedLogger.logWarning(text("Caught signal ", fdwControl, ". But don't have any handler binded!"));
                    }
                }
            }
        }

        /// Wrapper for getting service manager
        SC_HANDLE getSCManager()
        {
            auto manager = OpenSCManagerW(null, null, SC_MANAGER_ALL_ACCESS);
            if(manager is null)
                throw new LoggedException(text("Failed to open SC manager!", getLastErrorDescr));

            return manager;
        }

        /// Wrapper for getting service handle
        SC_HANDLE getService(SC_HANDLE manager, DWORD accessFlags, bool supressLogging = false)
        {
            auto service = OpenServiceW(manager, cast(LPWSTR)DaemonInfo.daemonName.toUTF16z, accessFlags);
            if(service is null)
            {
                if(!supressLogging)
                {
                    savedLogger.logError("Failed to open service!");
                    savedLogger.logError(getLastErrorDescr);
                }
                throw new Exception(text("Failed to open service! ", getLastErrorDescr));
            }
            return service;
        }

        static if(isDaemon!DaemonInfo)
        {
            enum ServiceInitState
            {
                ServiceIsOk, // dispatcher has run successfully
                NotService,  // dispatcher failed with specific error
                OtherError
            }

            /// Performs service initialization
            /**
            *    If inner $(B StartServiceCtrlDispatcherW) fails due reason that
            *    the code is running in userspace, the function returns ServiceInitState.NotService.
            *
            *    If the code is run under SC manager, the dispatcher operates and the function
            *    returns ServiceInitState.ServiceIsOk at the end of service execution.
            *
            *    If something wrong happens, the function returns ServiceInitState.OtherError
            */
            ServiceInitState serviceInit()
            {
                SERVICE_TABLE_ENTRY[2] serviceTable;
                serviceTable[0].lpServiceName = cast(LPWSTR)DaemonInfo.daemonName.toUTF16z;
                serviceTable[0].lpServiceProc = &serviceMain;
                serviceTable[1].lpServiceName = null;
                serviceTable[1].lpServiceProc = null;

                if(!StartServiceCtrlDispatcherW(serviceTable.ptr))
                {
                    if(GetLastError == ERROR_FAILED_SERVICE_CONTROLLER_CONNECT)
                    {
                        return ServiceInitState.NotService;
                    }
                    else
                    {
                        savedLogger.logError("Failed to start service dispatcher!");
                        savedLogger.logError(getLastErrorDescr);
                        return ServiceInitState.OtherError;
                    }
                }

                return ServiceInitState.ServiceIsOk;
            }
        }

        /// Registers service in SCM database
        void serviceInstall(DWORD startType)
        {
            wchar[MAX_PATH] path;
            if(!GetModuleFileNameW(null, path.ptr, MAX_PATH))
                throw new LoggedException("Cannot install service! " ~ getLastErrorDescr);

            auto manager = getSCManager();
            scope(exit) CloseServiceHandle(manager);

            auto servname = cast(LPWSTR)DaemonInfo.daemonName.toUTF16z;
            auto service = CreateServiceW(
                manager,
                servname,
                servname,
                SERVICE_ALL_ACCESS,
                SERVICE_WIN32_OWN_PROCESS,
                startType,
                SERVICE_ERROR_NORMAL,
                path.ptr,
                null,
                null,
                null,
                null,
                null);
            scope(exit) CloseServiceHandle(service);

            if(service is null)
                throw new LoggedException("Failed to create service! " ~ getLastErrorDescr);

            savedLogger.logInfo("Service installed successfully!");
        }

        /// Removing service from SC manager
        void serviceRemove()
        {
            auto manager = getSCManager();
            scope(exit) CloseServiceHandle(manager);

            auto service = getService(manager, SERVICE_STOP | DELETE);
            scope(exit) CloseServiceHandle(service);

            DeleteService(service);
            savedLogger.logInfo("Service is removed successfully!");
        }

        /// Tries to start service and checks the running state
        void serviceStart()
        {
            auto manager = getSCManager();
            scope(exit) CloseServiceHandle(manager);

            auto service = getService(manager, SERVICE_START);
            scope(exit) CloseServiceHandle(service);

            if(!StartServiceW(service, 0, null))
                throw new LoggedException(text("Failed to start service! ", getLastErrorDescr));


            auto maybeStatus = queryServiceStatus();
            if(maybeStatus.isNull)
            {
                throw new LoggedException("Failed to start service! There is no service registered!");
            }
            else
            {
                Thread.sleep(500.dur!"msecs");

                auto status = maybeStatus.get;
                auto stamp = Clock.currSystemTick;
                while(status.dwCurrentState != SERVICE_RUNNING)
                {
                    if(stamp + cast(TickDuration)30.dur!"seconds" < Clock.currSystemTick)
                        throw new LoggedException("Cannot start service! Timeout");
                    if(status.dwWin32ExitCode != 0)
                        throw new LoggedException(text("Failed to start service! Service error code: ", status.dwWin32ExitCode));
                    if(status.dwCurrentState == SERVICE_STOPPED)
                        throw new LoggedException("Failed to start service! The service remains in stop state!");

                    auto maybeStatus2 = queryServiceStatus();
                    if(maybeStatus2.isNull)
                    {
                        throw new LoggedException("Failed to start service! There is no service registered!");
                    }
                    else
                    {
                        status = maybeStatus2.get;
                    }
                }
            }

            savedLogger.logInfo("Service is started successfully!");
        }

        /**
        *    Checks if the service is exist and returns its status.
        *
        *    If no service is installed, will return Nothing.
        */
        Nullable!SERVICE_STATUS queryServiceStatus()
        {
            auto manager = getSCManager();
            scope(exit) CloseServiceHandle(manager);

            SC_HANDLE service;
            try
            {
                service = getService(manager, SERVICE_QUERY_STATUS, true);
            } catch(Exception e)
            {
                Nullable!SERVICE_STATUS ret;
                return ret;
            }
            scope(exit) CloseServiceHandle(service);

            SERVICE_STATUS status;
            if(!QueryServiceStatus(service, &status))
                throw new LoggedException(text("Failed to query service! ", getLastErrorDescr));

            return Nullable!SERVICE_STATUS(status);
        }

        /// Sets current service status and reports it to the SCM
        void reportServiceStatus(DWORD currentState, DWORD exitCode, Duration waitHint)
        {
            static DWORD checkPoint = 1;

            serviceStatus.dwCurrentState = currentState;
            serviceStatus.dwWin32ExitCode = exitCode;
            serviceStatus.dwWaitHint = cast(DWORD)waitHint.total!"msecs";

            if(currentState == SERVICE_START_PENDING)
            {
                serviceStatus.dwControlsAccepted = 0;
            }
            else
            {
                serviceStatus.dwControlsAccepted = daemon.makeUsingFlag;
            }

            SetServiceStatus(serviceStatusHandle, &serviceStatus);
        }

        /// Reads last error id and formats it into a man-readable message
        string getLastErrorDescr()
        {
            char* buffer;
            auto error = GetLastError();

            FormatMessageA(
                FORMAT_MESSAGE_FROM_SYSTEM | FORMAT_MESSAGE_ALLOCATE_BUFFER | FORMAT_MESSAGE_IGNORE_INSERTS, null, error, MAKELANGID(LANG_ENGLISH, SUBLANG_DEFAULT), cast(LPSTR)&buffer, 0, null);
            scope(exit) LocalFree(cast(void*)buffer);

            return buffer.fromStringz[0 .. $-1].idup;
        }
    } // private
}
private
{
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

        DWORD mapSignal(Signal sig)
        {
            switch(sig)
            {
                case(Signal.Stop):           return SERVICE_CONTROL_STOP;
                case(Signal.Continue):       return SERVICE_CONTROL_CONTINUE;
                case(Signal.Pause):          return SERVICE_CONTROL_PAUSE;
                case(Signal.Shutdown):       return SERVICE_CONTROL_SHUTDOWN;
                case(Signal.Interrogate):    return SERVICE_CONTROL_INTERROGATE;
                case(Signal.NetBindAdd):     return SERVICE_CONTROL_NETBINDADD;
                case(Signal.NetBindDisable): return SERVICE_CONTROL_NETBINDDISABLE;
                case(Signal.NetBindEnable):  return SERVICE_CONTROL_NETBINDENABLE;
                case(Signal.NetBindRemove):  return SERVICE_CONTROL_NETBINDREMOVE;
                case(Signal.ParamChange):    return SERVICE_CONTROL_PARAMCHANGE;
                default: return mapCustomSignal(sig);
            }
        }

        DWORD mapCustomSignal(Signal sig)
        {
            assert(!isNativeSignal(sig));

            DWORD counter = 0;
            foreach(key; customSignals)
            {
                if(key == sig) return 128 + counter;
                counter++;
            }

            assert(false, "Signal isn't in custom list! Impossible state!");
        }

        DWORD makeUsingFlag()
        {
            DWORD accum = 0;

            foreach(signal; nativeSignals)
            {
                static if(signal == Signal.Stop)            accum |= SERVICE_ACCEPT_STOP;
                static if(signal == Signal.Continue)        accum |= SERVICE_ACCEPT_PAUSE_CONTINUE;
                static if(signal == Signal.Pause)           accum |= SERVICE_ACCEPT_PAUSE_CONTINUE;
                static if(signal == Signal.Shutdown)        accum |= SERVICE_ACCEPT_SHUTDOWN;
                static if(signal == Signal.Interrogate)     accum |= 0;
                static if(signal == Signal.NetBindAdd)      accum |= SERVICE_ACCEPT_NETBINDCHANGE;
                static if(signal == Signal.NetBindDisable)  accum |= SERVICE_ACCEPT_NETBINDCHANGE;
                static if(signal == Signal.NetBindEnable)   accum |= SERVICE_ACCEPT_NETBINDCHANGE;
                static if(signal == Signal.NetBindRemove)   accum |= SERVICE_ACCEPT_NETBINDCHANGE;
                static if(signal == Signal.ParamChange)     accum |= SERVICE_ACCEPT_PARAMCHANGE;
            }

            return accum;
        }

        DWORD getControlAccessFlag(Signal sig)
        {
            switch(sig)
            {
                case(Signal.Stop):           return SERVICE_STOP;
                case(Signal.Continue):       return SERVICE_PAUSE_CONTINUE;
                case(Signal.Pause):          return SERVICE_PAUSE_CONTINUE;
                case(Signal.Shutdown):       throw new Error("Cannot send the shutdown signal!");
                case(Signal.Interrogate):    return SERVICE_INTERROGATE ;
                case(Signal.NetBindAdd):     return SERVICE_PAUSE_CONTINUE;
                case(Signal.NetBindDisable): return SERVICE_PAUSE_CONTINUE;
                case(Signal.NetBindEnable):  return SERVICE_PAUSE_CONTINUE;
                case(Signal.NetBindRemove):  return SERVICE_PAUSE_CONTINUE;
                case(Signal.ParamChange):    return SERVICE_PAUSE_CONTINUE;
                default: return SERVICE_USER_DEFINED_CONTROL;
            }
        }
    }
}
private
{
    extern (C) void  rt_moduleTlsCtor();
    extern (C) void  rt_moduleTlsDtor();
}
// winapi defines
private extern(System)
{
    struct SERVICE_TABLE_ENTRY
    {
        LPWSTR                  lpServiceName;
        LPSERVICE_MAIN_FUNCTION lpServiceProc;
    }
    alias LPSERVICE_TABLE_ENTRY = SERVICE_TABLE_ENTRY*;

    alias extern(System) void function(DWORD dwArgc, LPWSTR* lpszArgv) LPSERVICE_MAIN_FUNCTION;

    BOOL StartServiceCtrlDispatcherW(const SERVICE_TABLE_ENTRY* lpServiceTable);

    struct SERVICE_STATUS
    {
        DWORD dwServiceType;
        DWORD dwCurrentState;
        DWORD dwControlsAccepted;
        DWORD dwWin32ExitCode;
        DWORD dwServiceSpecificExitCode;
        DWORD dwCheckPoint;
        DWORD dwWaitHint;
    }
    alias LPSERVICE_STATUS = SERVICE_STATUS*;

    alias SERVICE_STATUS_HANDLE = HANDLE;
    alias SC_HANDLE = HANDLE;

    // dwServiceType
    enum SERVICE_FILE_SYSTEM_DRIVER = 0x00000002;
    enum SERVICE_KERNEL_DRIVER = 0x00000001;
    enum SERVICE_WIN32_OWN_PROCESS = 0x00000010;
    enum SERVICE_WIN32_SHARE_PROCESS = 0x00000020;
    enum SERVICE_INTERACTIVE_PROCESS = 0x00000100;

    // dwCurrentState
    enum SERVICE_CONTINUE_PENDING = 0x00000005;
    enum SERVICE_PAUSE_PENDING = 0x00000006;
    enum SERVICE_PAUSED = 0x00000007;
    enum SERVICE_RUNNING = 0x00000004;
    enum SERVICE_START_PENDING = 0x00000002;
    enum SERVICE_STOP_PENDING = 0x00000003;
    enum SERVICE_STOPPED = 0x00000001;

    // dwControlsAccepted
    enum SERVICE_ACCEPT_NETBINDCHANGE = 0x00000010;
    enum SERVICE_ACCEPT_PARAMCHANGE = 0x00000008;
    enum SERVICE_ACCEPT_PAUSE_CONTINUE = 0x00000002;
    enum SERVICE_ACCEPT_PRESHUTDOWN = 0x00000100;
    enum SERVICE_ACCEPT_SHUTDOWN = 0x00000004;
    enum SERVICE_ACCEPT_STOP = 0x00000001;

    enum NO_ERROR = 0;

    alias extern(System) void function(DWORD fdwControl) LPHANDLER_FUNCTION;
    SERVICE_STATUS_HANDLE RegisterServiceCtrlHandlerW(LPWSTR lpServiceName, LPHANDLER_FUNCTION lpHandlerProc);

    SC_HANDLE OpenSCManagerW(LPWSTR lpMachineName, LPWSTR lpDatabaseName, DWORD dwDesiredAccess);

    // dwDesiredAccess
    enum SC_MANAGER_ALL_ACCESS = 0xF003F;
    enum SC_MANAGER_CREATE_SERVICE = 0x0002;
    enum SC_MANAGER_CONNECT = 0x0001;
    enum SC_MANAGER_ENUMERATE_SERVICE = 0x0004;
    enum SC_MANAGER_LOCK = 0x0008;
    enum SC_MANAGER_MODIFY_BOOT_CONFIG = 0x0020;
    enum SC_MANAGER_QUERY_LOCK_STATUS = 0x0010;

    SC_HANDLE CreateServiceW(
          SC_HANDLE hSCManager,
          LPWSTR lpServiceName,
          LPWSTR lpDisplayName,
          DWORD dwDesiredAccess,
          DWORD dwServiceType,
          DWORD dwStartType,
          DWORD dwErrorControl,
          LPWSTR lpBinaryPathName,
         LPWSTR lpLoadOrderGroup,
          LPDWORD lpdwTagId,
          LPWSTR lpDependencies,
          LPWSTR lpServiceStartName,
          LPWSTR lpPassword
    );

    // dwStartType
    enum SERVICE_AUTO_START = 0x00000002;
    enum SERVICE_BOOT_START = 0x00000000;
    enum SERVICE_DEMAND_START = 0x00000003;
    enum SERVICE_DISABLED = 0x00000004;
    enum SERVICE_SYSTEM_START = 0x00000001;

    // dwDesiredAccess CreateService
    enum SERVICE_ALL_ACCESS = 0xF01FF;
    enum SERVICE_CHANGE_CONFIG = 0x0002;
    enum SERVICE_ENUMERATE_DEPENDENTS = 0x0008;
    enum SERVICE_INTERROGATE = 0x0080;
    enum SERVICE_PAUSE_CONTINUE = 0x0040;
    enum SERVICE_QUERY_CONFIG = 0x0001;
    enum SERVICE_QUERY_STATUS = 0x0004;
    enum SERVICE_START = 0x0010;
    enum SERVICE_STOP = 0x0020;
    enum SERVICE_USER_DEFINED_CONTROL = 0x0100;

    // dwErrorControl
    enum SERVICE_ERROR_CRITICAL = 0x00000003;
    enum SERVICE_ERROR_IGNORE = 0x00000000;
    enum SERVICE_ERROR_NORMAL = 0x00000001;
    enum SERVICE_ERROR_SEVERE = 0x00000002;

    bool CloseServiceHandle(SC_HANDLE hSCOjbect);

    SC_HANDLE OpenServiceW(
        SC_HANDLE hSCManager,
        LPWSTR lpServiceName,
        DWORD dwDesiredAccess
    );

    BOOL DeleteService(
        SC_HANDLE hService
    );

    BOOL StartServiceW(
        SC_HANDLE hService,
        DWORD dwNumServiceArgs,
        LPWSTR *lpServiceArgVectors
    );

    BOOL QueryServiceStatus(
        SC_HANDLE hService,
        LPSERVICE_STATUS lpServiceStatus
    );

    BOOL SetServiceStatus(
        SERVICE_STATUS_HANDLE hServiceStatus,
        LPSERVICE_STATUS lpServiceStatus
    );

    BOOL ControlService(
        SC_HANDLE hService,
          DWORD dwControl,
          LPSERVICE_STATUS lpServiceStatus
    );

    enum SERVICE_CONTROL_CONTINUE = 0x00000003;
    enum SERVICE_CONTROL_INTERROGATE = 0x00000004;
    enum SERVICE_CONTROL_NETBINDADD = 0x00000007;
    enum SERVICE_CONTROL_NETBINDDISABLE = 0x0000000A;
    enum SERVICE_CONTROL_NETBINDENABLE = 0x00000009;
    enum SERVICE_CONTROL_NETBINDREMOVE = 0x00000008;
    enum SERVICE_CONTROL_PARAMCHANGE = 0x00000006;
    enum SERVICE_CONTROL_PAUSE = 0x00000002;
    enum SERVICE_CONTROL_SHUTDOWN = 0x00000005;
    enum SERVICE_CONTROL_STOP = 0x00000001;

    enum ERROR_FAILED_SERVICE_CONTROLLER_CONNECT = 1063;
}
