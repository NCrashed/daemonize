// written in the D programming language
/**
*   Copyright: © 2014-2016 Anton Gushcha
*   License: Subject to the terms of the MIT license, as written in the included LICENSE file.
*   Authors: Anton Gushcha <ncrashed@gmail.com>
*/
module daemonize.string;

import core.stdc.string;

static if (__VERSION__ < 2066) 
{
    // from upcoming release of phobos
    /**
    *   Returns a D-style array of $(B char) given a zero-terminated C-style string.
    *   The returned array will retain the same type qualifiers as the input.
    *
    *   $(B Important Note:) The returned array is a slice of the original buffer.
    *   The original data is not changed and not copied.
    */
    inout(char)[] fromStringz(inout(char)* cString) @system pure 
    {
        return cString ? cString[0 .. strlen(cString)] : null;
    }
}
else
{
    public import std.string;
}
