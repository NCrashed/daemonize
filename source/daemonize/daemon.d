// This file is written in D programming language
/**
*   Copyright: © 2013-2014 Anton Gushcha
*   License: Subject to the terms of the MIT license, as written in the included LICENSE file.
*   Authors: NCrashed <ncrashed@gmail.com>
*/
module daemonize.daemon;

import daemonize.keymap;
import std.traits;

static if( __VERSION__ < 2066 ) private enum nogc;

enum Signal : string
{
    Abort     = "Abort",
    Terminate = "Terminate",
    Quit      = "Quit",
    Interrupt = "Interrupt",
    HangUp    = "HangUp"
}

@nogc Signal customSignal(string name) @safe pure nothrow 
{
    return cast(Signal)name;
}

template Daemon(
    string name,
    alias pSignalMap,
    int groupid = -1,
    int userid = -1)
{
    enum daemonName = name;
    alias signalMap = pSignalMap; 
    
    enum hasLockFile = false;
    enum hasPidFile = false;
    
    enum groupId = groupid;
    enum userId  = userid;
}

template Daemon(
    string name,
    alias pSignalMap,
    string pidFile,
    int groupid = -1,
    int userid = -1)
{
    enum daemonName = name;
    alias signalMap = pSignalMap; 
    
    enum hasLockFile = false;
    enum hasPidFile = true;
    
    enum lockFilePath = lockFile;
    
    enum groupId = groupid;
    enum userId  = userid;
}

template Daemon(
    string name,
    alias pSignalMap,
    string pidFile,
    string lockFile,
    int groupid = -1,
    int userid = -1)
{
    enum daemonName = name;
    alias signalMap = pSignalMap; 
    
    enum hasLockFile = true;
    enum hasPidFile = true;
    
    enum lockFilePath = lockFile;
    enum pidFilePath  = pidFile;
    
    enum groupId = groupid;
    enum userId  = userid;
}

template isDaemon(alias T)
{
    enum isDaemon = 
        __traits(compiles, T.daemonName) && is(typeof(T.daemonName) == string) &&
        __traits(compiles, T.signalMap) &&
        __traits(compiles, T.hasLockFile) && is(typeof(T.hasLockFile) == bool) &&
        __traits(compiles, T.hasPidFile) && is(typeof(T.hasPidFile) == bool) &&
        __traits(compiles, T.groupId) && is(typeof(T.groupId) == int) &&
        __traits(compiles, T.userId) && is(typeof(T.userId) == int);
}