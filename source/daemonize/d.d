// This file is written in D programming language
/**
*   Copyright: © 2013-2014 Anton Gushcha
*   License: Subject to the terms of the MIT license, as written in the included LICENSE file.
*   Authors: NCrashed <ncrashed@gmail.com>
*/
module daemonize.d;

public
{
    import daemonize.log;
    import daemonize.daemon;
    import daemonize.keymap;
}

version(Windows)
{
    public import daemonize.windows;
}
else version(linux)
{
    public import daemonize.linux;
}
