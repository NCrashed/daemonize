// This file is written in D programming language
/**
*   Copyright: © 2013-2014 Anton Gushcha
*   License: Subject to the terms of the MIT license, as written in the included LICENSE file.
*   Authors: NCrashed <ncrashed@gmail.com>
*/
module daemonize.windows;

version(Windows):

static if( __VERSION__ < 2066 ) private enum nogc;

import core.sys.windows.windows;
import core.runtime;
import core.thread;
import std.datetime;
import std.string;
import std.utf;
import std.c.stdlib;
import std.typecons;

import daemonize.daemon;
import daemonize.string;
import dlogg.log;

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

template runDaemon(alias DaemonInfo)
    if(isDaemon!DaemonInfo)
{
	int runDaemon(shared ILogger logger
        , string pidFilePath = "", string lockFilePath = ""
        , int userId = -1, int groupId = -1)
    { 
    	savedLogger = logger;
    	
//    	serviceRemove();
//    	return EXIT_SUCCESS;
    	
    	auto maybeStatus = queryServiceStatus();
    	if(maybeStatus.isNull)
    	{
    		savedLogger.logInfo("No service is installed!");
    		serviceInstall();
    		serviceStart();
    		return EXIT_SUCCESS;
    	} 
    	else
    	{
    		savedLogger.logInfo("Starting daemon process!");
    		return serviceInit();
    	}
    }
    
    private
    {
    	SERVICE_STATUS serviceStatus;
    	SERVICE_STATUS_HANDLE serviceStatusHandle;
    	shared ILogger savedLogger;
    	
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
    	
    	extern(System) static void serviceMain(uint argc, wchar** args) nothrow
    	{
    		try
    		{
	    		Runtime.initialize();
	    		scope(exit) 
	    		{
	    			serviceRemove();
	    			Runtime.terminate();
    			}
	    		
		        int code = EXIT_FAILURE;

	    		serviceStatus.dwServiceType = SERVICE_WIN32_OWN_PROCESS;
	    		
	    		import dlogg.strict;
	    		savedLogger = new shared StrictLogger("C:\\mylog.txt");
	    		savedLogger.minOutputLevel = LoggingLevel.Muted;
	    		savedLogger.logInfo("Registering control handler");
	    		
	    		serviceStatusHandle = RegisterServiceCtrlHandlerW(cast(LPWSTR)DaemonInfo.daemonName.toUTF16z, &controlHandler);
	    		if(serviceStatusHandle is null)
	    		{
	    			savedLogger.logError("Failed to register control handler!");
	    			savedLogger.logError(getLastErrorDescr);
	    			return;
	    		}
	    		
		        debug alias WhatToCatch = Throwable;
		        else  alias WhatToCatch = Exception;
		        
	    		savedLogger.logInfo("Running user main delegate");
	        	reportServiceStatus(SERVICE_RUNNING, NO_ERROR, 0.dur!"msecs");
	            try code = DaemonInfo.mainFunc(savedLogger);
	            catch (WhatToCatch ex) 
	            {
	                savedLogger.logError(text("Catched unhandled exception in daemon level: ", ex.msg));
	                savedLogger.logError("Terminating...");
	                reportServiceStatus(SERVICE_STOPPED, EXIT_FAILURE, 0.dur!"msecs");
	                return;
	            }
		        reportServiceStatus(SERVICE_STOPPED, NO_ERROR, 0.dur!"msecs");
	        }
    		catch(Throwable th)
    		{
    			savedLogger.logError(text("Internal daemon error, please bug report: ", th.msg));
                savedLogger.logError("Terminating...");
    		}
    	}
    	
    	extern(System) static void controlHandler(DWORD fdwControl)
    	{
    		// NEED TO CHANGE THIS
    		switch(fdwControl)
    		{
    			case(SERVICE_CONTROL_STOP):
    			{
    				savedLogger.logInfo("Stopping service...");
    				reportServiceStatus(SERVICE_STOPPED, NO_ERROR, 0.dur!"msecs");
    				return;
    			}
    			case(SERVICE_CONTROL_SHUTDOWN):
    			{
    				savedLogger.logInfo("Shutdowning service...");
    				reportServiceStatus(SERVICE_STOPPED, NO_ERROR, 0.dur!"msecs");
    				return;
    			}
    			default:
    			{
    				reportServiceStatus(SERVICE_STOPPED, NO_ERROR, 0.dur!"msecs");
    				return;
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
    	
    	/// Performs service initialization
    	int serviceInit()
    	{
	    	SERVICE_TABLE_ENTRY[2] serviceTable;
	    	serviceTable[0].lpServiceName = cast(LPWSTR)DaemonInfo.daemonName.toUTF16z;
	    	serviceTable[0].lpServiceProc = &serviceMain;
	    	serviceTable[1].lpServiceName = null;
	    	serviceTable[1].lpServiceProc = null;
	    	
	    	if(!StartServiceCtrlDispatcherW(serviceTable.ptr))
	    	{
	    		savedLogger.logError("Failed to start service dispatcher!");
	    		savedLogger.logError(getLastErrorDescr);
	    		return EXIT_FAILURE;
	    	}
	    	
	    	return EXIT_SUCCESS;
    	}
    	
    	/// Registers service in SCM database
    	void serviceInstall()
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
    			SERVICE_DEMAND_START,
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
    	
    	void serviceRemove()
    	{
    		auto manager = getSCManager();
    		scope(exit) CloseServiceHandle(manager);
    		
    		auto service = getService(manager, SERVICE_STOP | DELETE);
    		scope(exit) CloseServiceHandle(service);
    		
    		DeleteService(service);
    		savedLogger.logInfo("Service is removed successfully!");
    	}
    	
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
    			serviceStatus.dwControlsAccepted = SERVICE_ACCEPT_STOP | SERVICE_ACCEPT_SHUTDOWN; // Need to change this according DaemonInfo!
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
    }
}
// D runtime
private extern(C) nothrow
{
    // These are for control of termination
    void _STD_monitor_staticdtor();
    void _STD_critical_term();
    void gc_term();
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
}