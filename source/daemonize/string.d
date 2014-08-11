// written in the D programming language
/*
*   This file is part of DrossyStars.
*   
*   DrossyStars is free software: you can redistribute it and/or modify
*   it under the terms of the GNU General Public License as published by
*   the Free Software Foundation, either version 3 of the License, or
*   (at your option) any later version.
*   
*   DrossyStars is distributed in the hope that it will be useful,
*   but WITHOUT ANY WARRANTY; without even the implied warranty of
*   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
*   GNU General Public License for more details.
*   
*   You should have received a copy of the GNU General Public License
*   along with DrossyStars.  If not, see <http://www.gnu.org/licenses/>.
*/
/**
*   Copyright: © 2014 Anton Gushcha
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