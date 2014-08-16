// This file is written in D programming language
/**
*   Platform independent parts of the library. Defines common signals
*   that safe to catch, utilities for describing daemons and some
*   utitility templates for duck typing.
*
*   Copyright: © 2013-2014 Anton Gushcha
*   License: Subject to the terms of the MIT license, as written in the included LICENSE file.
*   Authors: NCrashed <ncrashed@gmail.com>
*/
module daemonize.daemon;

import daemonize.keymap;
import std.traits;
import std.typetuple;

static if( __VERSION__ < 2066 ) private enum nogc;

/**
*   Native signals that can be hooked. There arn't all
*   linux native signals due safety.
*
*   Most not listed signals are already binded by druntime (sigusr1 and
*   sigusr2 are occupied by garbage collector) and rebinding
*   cause a program hanging or ignoring all signal callbacks.
*
*   You can define your own signals by $(B customSignal) function.
*   These signals are mapped to realtime signals in linux.
*
*   Note: Signal enum is based on string to map signals on winapi events. 
*/
enum Signal : string
{
	// Linux native requests
    Abort     = "Abort",
    Terminate = "Terminate",
    Quit      = "Quit",
    Interrupt = "Interrupt",
    HangUp    = "HangUp",
    
    // Windows native requests
    Stop           = "Stop",
    Continue       = "Continue",
    Pause          = "Pause",
    Shutdown       = "Shutdown",
    Interrogate    = "Interrogate",
    NetBindAdd     = "NetBindAdd",
    NetBindDisable = "NetBindDisable",
    NetBindEnable  = "NetBindEnable",
    NetBindRemove  = "NetBindRemove",
    ParamChange    = "ParamChange",
    
}

/**
*   Creating your own custom signal. Theese signals are binded to
*   realtime signals in linux and to winapi events in Windows.
*
*   Example:
*   --------
*   enum LogRotatingSignal = "LogRotate".customSignal;
*   --------
*/
@nogc Signal customSignal(string name) @safe pure nothrow 
{
    return cast(Signal)name;
}

/**
*	Signal OR composition.
*
*	If you'd like to hook several signals by one handler, you
*	can use the template in place of signal in $(B KeyValueList)
*	signal map.
*
*	In that case the handler should also accept a Signal value
*	as it second parameter.
*/
template Composition(Signals...)
{    
	alias signals = Signals;
}

/**
*   Template for describing daemon in the package. 
*
*   To describe new daemon you should set unique name
*   and signal -> callbacks mapping.
*
*   $(B name) is used to name default pid and lock files
*   of the daemon and also it is a service name in Windows.
*
*   $(B pSignalMap) is a $(B KeyValueList) template where
*   keys are $(B Signal) values and values are delegates of type:
*   ----------
*   bool delegate(shared ILogger)
*   ----------
*   If the delegate returns $(B false), daemon terminates.
*
*   Example:
*   -----------
*   alias daemon = Daemon!(
*       "DaemonizeExample1",
*       
*       KeyValueList!(
*           Signal.Terminate, (logger)
*           {
*               logger.logInfo("Exiting...");
*               return false; // returning false will terminate daemon
*           },
*           Signal.HangUp, (logger)
*           {
*               logger.logInfo("Hello World!");
*               return true; // continue execution
*           }
*       )
*   );
*   -----------
*/
template Daemon(
    string name,
    alias pSignalMap,
    alias pMainFunc)
{
    enum daemonName = name;
    alias signalMap = pSignalMap;
    alias mainFunc = pMainFunc; 
}

/// Duck typing $(B Daemon) description
template isDaemon(alias T)
{
    static if(__traits(compiles, T.daemonName) && __traits(compiles, T.signalMap)
    	&& __traits(compiles, T.mainFunc))
        enum isDaemon = is(typeof(T.daemonName) == string);
    else
        enum isDaemon = false;
}

/**
*   Truncated description of daemon for use with $(B sendSignal) function.
*   You need to pass a daemon $(B name) and a list of signals to $(B Signals) 
*   expression list.
*
*   Example:
*   --------
*   // Full description of daemon
*   alias daemon = Daemon!(
*       "DaemonizeExample2",
*       
*       KeyValueList!(
*           Signal.Terminate, (logger)
*           {
*               logger.logInfo("Exiting...");
*               return false;
*          },
*           Signal.HangUp, (logger)
*           {
*               logger.logInfo("Hello World!");
*               return true;
*           },
*           RotateLogSignal, (logger)
*           {
*               logger.logInfo("Rotating log!");
*               logger.reload;
*               return true;
*           },
*           DoSomethingSignal, (logger)
*           {
*               logger.logInfo("Doing something...");
*               return true;
*           }
*       )
*   );
*
*   // Truncated description for client
*   alias daemon = DaemonClient!(
*       "DaemonizeExample2",
*       Signal.Terminate,
*       Signal.HangUp,
*       RotateLogSignal,
*       DoSomethingSignal
*   );
*   ----------------
*/
template DaemonClient(
    string name,
    Signals...)
{
    private template isSignal(T...)
    {
        enum isSignal = is(typeof(T[0]) == Signal);
    }
    
    static assert(allSatisfy!(isSignal, Signals), "All values of Signals parameter have to be of Signal type!");
    
    enum daemonName = name;
    alias signals = Signals;
}

/// Duck typing of $(B DaemonClient)
template isDaemonClient(alias T)
{
    private template isSignal(T...)
    {
        enum isSignal = is(typeof(T[0]) == Signal);
    }
    
    static if(__traits(compiles, T.daemonName) && __traits(compiles, T.signals))
        enum isDaemonClient = is(typeof(T.daemonName) == string) && allSatisfy!(isSignal, T.signals);
    else
        enum isDaemonClient = false;
}
unittest
{
    alias TestClient = DaemonClient!(
        "DaemonizeExample2",
        Signal.Terminate,
        Signal.HangUp);
    static assert(isDaemonClient!TestClient);
}