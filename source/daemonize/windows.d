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
import std.datetime;
import std.string;
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
	int runDaemon(shared ILogger logger, int delegate() main
        , string pidFilePath = "", string lockFilePath = ""
        , int userId = -1, int groupId = -1)
    { 
    	savedLogger = logger;
    	logger.minLoggingLevel = LoggingLevel.Muted;
    	savedMain = main;
    	
//    	serviceRemove();
//    	return EXIT_SUCCESS;
    	
    	auto maybeStatus = queryServiceStatus();
    	if(maybeStatus.isNull)
    	{
    		savedLogger.logInfo("No service is installed!");
    		serviceInstall();
    		//serviceStart();
    		return EXIT_SUCCESS;
    	} 
    	else
    	{
    		return serviceInit();
    	}
    }
    
/*
    		auto status = maybeStatus.get;
    		
    		if( status.dwCurrentState == SERVICE_RUNNING ||
    			status.dwCurrentState == SERVICE_START_PENDING)
    		{
    			savedLogger.logInfo("Service is already running!");
    			return EXIT_FAILURE;
    		}
    		else if(status.dwCurrentState == SERVICE_STOPPED)
    		{
    			savedLogger.logInfo("Service is stopped! Starting...");
    			serviceStart();
    			return EXIT_SUCCESS;
    		} 
    		else
    		{
    			savedLogger.logInfo("Unknown state of service!");
    			return EXIT_FAILURE;
    		}
*/
    private
    {
    	SERVICE_STATUS serviceStatus;
    	SERVICE_STATUS_HANDLE serviceStatusHandle;
    	shared ILogger savedLogger;
    	int delegate() savedMain;
    	
    	extern(System) void serviceMain(DWORD argc, LPTSTR* argv)
    	{
    		serviceStatus.dwServiceType = SERVICE_WIN32_OWN_PROCESS;
    		
    		serviceStatusHandle = RegisterServiceCtrlHandlerA(cast(LPSTR)DaemonInfo.daemonName.toStringz, &controlHandler);
    		if(serviceStatusHandle is null)
    		{
    			savedLogger.logError("Failed to register control handler!");
    			savedLogger.logError(getLastErrorDescr);
    			return;
    		}
    		
    		reportServiceStatus(SERVICE_START_PENDING, NO_ERROR, 500.dur!"msecs");
    		
	        int code = EXIT_FAILURE;
	        debug
	        {
	        	reportServiceStatus(SERVICE_RUNNING, NO_ERROR, 0.dur!"msecs");
	            try code = savedMain();
	            catch (Throwable ex) 
	            {
	                savedLogger.logError(text("Catched unhandled throwable in daemon level: ", ex.msg));
	                savedLogger.logError("Terminating...");
	                reportServiceStatus(SERVICE_STOPPED, EXIT_FAILURE, 0.dur!"msecs");
	                return;
	            }
	        }
	        else
	        {
	        	reportServiceStatus(SERVICE_RUNNING, NO_ERROR, 0.dur!"msecs");
	            try code = savedMain();
	            catch (Exception ex) 
	            {
	                savedLogger.logError(text("Catched unhandled exception in daemon level: ", ex.msg));
	                savedLogger.logError("Terminating...");
	                reportServiceStatus(SERVICE_STOPPED, EXIT_FAILURE, 0.dur!"msecs");
	                return;
	            }
	        }
	        
	        reportServiceStatus(SERVICE_STOPPED, NO_ERROR, 0.dur!"msecs");
    	}
    	
    	extern(System) void controlHandler(DWORD fdwControl)
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
    		auto manager = OpenSCManagerA(null, null, SC_MANAGER_ALL_ACCESS);
    		if(manager is null)
    		{
    			savedLogger.logError("Failed to open SC manager!");
    			savedLogger.logError(getLastErrorDescr);
    			throw new Exception(text("Failed to open SC manager!", getLastErrorDescr));
    		}
    		return manager;
    	}
    	
    	/// Wrapper for getting service handle
    	SC_HANDLE getService(SC_HANDLE manager, DWORD accessFlags, bool supressLogging = false)
    	{
    		auto service = OpenServiceA(manager, DaemonInfo.daemonName.toStringz, accessFlags);
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
	    	serviceTable[0].lpServiceName = cast(LPSTR)DaemonInfo.daemonName.toStringz;
	    	serviceTable[0].lpServiceProc = &serviceMain;
	    	serviceTable[1].lpServiceName = null;
	    	serviceTable[1].lpServiceProc = null;
	    	
	    	if(!StartServiceCtrlDispatcherA(serviceTable.ptr))
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
    		{
    			savedLogger.logError("Cannot install service!");
    			savedLogger.logError(getLastErrorDescr);
    			return;
    		}
    		
    		auto manager = getSCManager();
    		scope(exit) CloseServiceHandle(manager);
    		
    		auto servname = cast(LPSTR)DaemonInfo.daemonName.toStringz;
    		auto service = CreateServiceA(
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
    		{
    			savedLogger.logError("Failed to create service!");
    			savedLogger.logError(getLastErrorDescr);
    			return;
    		}
    		
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
    		
    		if(!StartServiceA(service, 0, null))
    		{
    			savedLogger.logError("Failed to start service!");
    			savedLogger.logError(getLastErrorDescr);
    			throw new Exception(text("Failed to start service! ", getLastErrorDescr));
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
    			scope(exit) CloseServiceHandle(service);
			} catch(Exception e)
    		{
    			Nullable!SERVICE_STATUS ret;
    			return ret;
    		}
    		
    		SERVICE_STATUS status;
    		if(!QueryServiceStatus(service, &status))
    		{
    			savedLogger.logError("Failed to query service!");
    			savedLogger.logError(getLastErrorDescr);
    			throw new Exception(text("Failed to query service! ", getLastErrorDescr));
    		}
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
    }
}
// winapi defines
private extern(System) 
{
	struct SERVICE_TABLE_ENTRY 
	{
		LPTSTR                  lpServiceName;
		LPSERVICE_MAIN_FUNCTION lpServiceProc;
	}
	alias LPSERVICE_TABLE_ENTRY = SERVICE_TABLE_ENTRY*;
	
	alias LPSERVICE_MAIN_FUNCTION = void function(DWORD dwArgc, LPTSTR* lpszArgv);
	
	BOOL StartServiceCtrlDispatcherA(const SERVICE_TABLE_ENTRY* lpServiceTable);
	
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
	
	alias LPHANDLER_FUNCTION = void function(DWORD fdwControl);
	SERVICE_STATUS_HANDLE RegisterServiceCtrlHandlerA(LPCTSTR lpServiceName, LPHANDLER_FUNCTION lpHandlerProc);
	
	SC_HANDLE OpenSCManagerA(LPCTSTR lpMachineName, LPCTSTR lpDatabaseName, DWORD dwDesiredAccess);
	
	// dwDesiredAccess
	enum SC_MANAGER_ALL_ACCESS = 0xF003F;
	enum SC_MANAGER_CREATE_SERVICE = 0x0002;
	enum SC_MANAGER_CONNECT = 0x0001;
	enum SC_MANAGER_ENUMERATE_SERVICE = 0x0004;
	enum SC_MANAGER_LOCK = 0x0008;
	enum SC_MANAGER_MODIFY_BOOT_CONFIG = 0x0020;
	enum SC_MANAGER_QUERY_LOCK_STATUS = 0x0010;
	
	SC_HANDLE CreateServiceA(
	  	SC_HANDLE hSCManager,
	  	LPCTSTR lpServiceName,
	  	LPCTSTR lpDisplayName,
	  	DWORD dwDesiredAccess,
	  	DWORD dwServiceType,
	  	DWORD dwStartType,
	  	DWORD dwErrorControl,
	  	LPWSTR lpBinaryPathName,
	 	LPCTSTR lpLoadOrderGroup,
	  	LPDWORD lpdwTagId,
	  	LPCTSTR lpDependencies,
	  	LPCTSTR lpServiceStartName,
	  	LPCTSTR lpPassword
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
	
	SC_HANDLE OpenServiceA(
		SC_HANDLE hSCManager,
		LPCTSTR lpServiceName,
		DWORD dwDesiredAccess
	);
	
	BOOL DeleteService(
		SC_HANDLE hService
	);
	
	BOOL StartServiceA(
		SC_HANDLE hService,
		DWORD dwNumServiceArgs,
		LPCTSTR *lpServiceArgVectors
	);
	
	BOOL QueryServiceStatus(
		SC_HANDLE hService,
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