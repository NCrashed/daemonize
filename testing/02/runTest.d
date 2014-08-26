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

void testPass(string expected, string buildVer)
{
    customShell("dub run", "Failed to execute daemon!");
    Thread.sleep(100.dur!"msecs");
    customShell("dub --config="~buildVer, "Failed to execute client part!");
    checkOutput("output.txt", expected);
}

void main()
{
    writeln("Running test ", testNumber, "... ");
    customShell("dub build", "Failed to build testing example!");
    
    testPass("Test string 1", "test1");
    testPass("Test string 1", "test2");
    testPass("Test string 1", "test3");
    testPass("Test string 1", "test4");
    testPass("Test string 2", "test5");
}