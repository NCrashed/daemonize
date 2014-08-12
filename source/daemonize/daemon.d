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
    alias pSignalMap)
{
    enum daemonName = name;
    alias signalMap = pSignalMap; 
}

template isDaemon(alias T)
{
    enum isDaemon = 
        __traits(compiles, T.daemonName) && is(typeof(T.daemonName) == string) &&
        __traits(compiles, T.signalMap);
}