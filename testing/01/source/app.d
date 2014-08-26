// This file is written in D programming language
/**
*   Copyright: © 2014 Anton Gushcha
*   License: Subject to the terms of the MIT license, as written in the included LICENSE file.
*   Authors: NCrashed <ncrashed@gmail.com>
*/
module test01;

import std.file;

import dlogg.strict;
import daemonize.d;

alias daemon = Daemon!(
    "Test1",
    
    KeyValueList!(),
    
    (logger, shouldExit) {
        write("output.txt", "Hello World!");
        return 0;
    }
);

int main()
{
    return buildDaemon!daemon.run(new shared StrictLogger("logfile.log")); 
}