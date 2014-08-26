import std.stdio;
import std.exception;
import std.process;
import std.file;
import core.thread;
import core.time;

enum testNumber = 1;

void customShell(string command, lazy string error)
{
    auto res = executeShell(command);
    if(res.status != 0) throw new Exception(error ~ " " ~ res.output); 
}

void checkOutput(string filename, string expected)
{
    enforce(filename.exists, "Cannot find output file " ~ filename);

    auto str = filename.readText;
    enforce(filename.readText == expected, "Expected '" ~ expected ~ "' but got '" ~ str ~ "'");
    
    filename.remove;
}

void main()
{
    writeln("Running test ", testNumber, "... ");
    customShell("dub build", "Failed to build testing example!");
    customShell("dub run", "Failed to execute daemon!");
    Thread.sleep(100.dur!"msecs");
    
    checkOutput("output.txt", "Hello World!");
}