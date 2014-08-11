// This file is written in D programming language
/**
*   Module holds compile-time associative map with heterogeneous keys and values.
*
*   Copyright: © 2013-2014 Anton Gushcha
*   License: Subject to the terms of the MIT license, as written in the included LICENSE file.
*   Authors: NCrashed <ncrashed@gmail.com>
*/
module daemonize.keymap;

import std.traits;
import std.typetuple;

/**
*   Simple expression list wrapper.
*
*   See_Also: Expression list at dlang.org documentation.
*/
template ExpressionList(T...)
{
    alias ExpressionList = T;
}
/// Example
unittest
{
    static assert([ExpressionList!(1, 2, 3)] == [1, 2, 3]);
}

/**
*   Sometimes we don't want to auto expand expression ExpressionLists.
*   That can be used to pass several lists into templates without
*   breaking their boundaries.
*/
template StrictExpressionList(T...)
{
    alias expand = T;
}
/// Example
unittest
{
    template Test(alias T1, alias T2)
    {
        static assert([T1.expand] == [1, 2]);
        static assert([T2.expand] == [3, 4]);
        enum Test = true;
    }
    
    static assert(Test!(StrictExpressionList!(1, 2), StrictExpressionList!(3, 4)));
}

/**
*   Same as std.typetyple.staticMap, but passes two arguments to the first template.
*/
template staticMap2(alias F, T...)
{
    static assert(T.length % 2 == 0);
    
    static if (T.length < 2)
    {
        alias staticMap2 = ExpressionList!();
    }
    else static if (T.length == 2)
    {
        alias staticMap2 = ExpressionList!(F!(T[0], T[1]));
    }
    else
    {
        alias staticMap2 = ExpressionList!(F!(T[0], T[1]), staticMap2!(F, T[2  .. $]));
    }
}
/// Example
unittest
{
    template Test(T...)
    {
        enum Test = T[0] && T[1];
    }
    
    static assert([staticMap2!(Test, true, true, true, false)] == [true, false]);
}

/**
*   Performs filtering of expression tuple $(B T) one by one by function or template $(B F). If $(B F)
*   returns $(B true) the resulted element goes to returned expression tuple, else it is discarded.
*/
template staticFilter(alias F, T...)
{
    static if(T.length == 0)
    {
        alias staticFilter = ExpressionList!();
    }
    else
    {
        static if(F(T[0]))
        {
            alias staticFilter = ExpressionList!(T[0], staticFilter!(F, T[1 .. $]));
        } 
        else
        {
            alias staticFilter = ExpressionList!(staticFilter!(F, T[1 .. $]));
        }
    }
}
/// Example
unittest
{
    import std.conv;
    
    bool testFunc(int val)
    { 
        return val <= 15;
    }
    
    static assert(staticFilter!(testFunc, ExpressionList!(42, 108, 15, 2)) == ExpressionList!(15, 2));
}

/**
*   Performs filtering of expression tuple $(B T) by pairs by function or template $(B F). If $(B F)
*   returns $(B true) the resulted pair goes to returned expression tuple, else it is discarded.
*/
template staticFilter2(alias F, T...)
{
    static assert(T.length % 2 == 0);
    
    static if (T.length < 2)
    {
        alias staticFilter2 = ExpressionList!();
    }
    else
    {
        static if(F(T[0], T[1]))
        {
            alias staticFilter2 = ExpressionList!(T[0], T[1], staticFilter2!(F, T[2 .. $]));
        }
        else
        {
            alias staticFilter2 = ExpressionList!(staticFilter2!(F, T[2 .. $]));
        }
    }
}
/// Example
unittest
{
    import std.conv;
    
    bool testFunc(string val1, int val2)
    { 
        return val1.to!int == val2;
    }
    
    static assert(staticFilter2!(testFunc, ExpressionList!("42", 42, "2", 108, "15", 15, "1", 2)) == ExpressionList!("42", 42, "15", 15));
}

/**
*   Static version of std.algorithm.reduce (or fold). Expects that $(B F)
*   takes accumulator as first argument and a value as second argument.
*
*   First value of $(B T) have to be a initial value of accumulator.
*/
template staticFold(alias F, T...)
{
    static if(T.length == 0) // invalid input
    {
        alias staticFold = ExpressionList!(); 
    }
    else static if(T.length == 1)
    {
        static if(is(T[0]))
            alias staticFold = T[0];
        else
            enum staticFold = T[0];
    }
    else 
    {
        alias staticFold = staticFold!(F, F!(T[0], T[1]), T[2 .. $]);
    }
}
/// Example
unittest
{
    template summ(T...)
    {
        enum summ = T[0] + T[1];
    }
    
    static assert(staticFold!(summ, 0, 1, 2, 3, 4) == 10);
    
    template preferString(T...)
    {
        static if(is(T[0] == string))
            alias preferString = T[0];
        else
            alias preferString = T[1];
    }
    
    static assert(is(staticFold!(preferString, void, int, string, bool) == string));
    static assert(is(staticFold!(preferString, void, int, double, bool) == bool));
}

/**
*   Compile-time variant of std.range.robin for expression ExpressionLists.
*   
*   Template expects $(B StrictExpressionList) list as parameter and returns
*   new expression list where first element is from first expression ExpressionList,
*   second element is from second ExpressionList and so on, until one of input ExpressionLists
*   doesn't end.
*/
template staticRobin(SF...)
{
    // Calculating minimum length of all ExpressionLists
    private template minimum(T...)
    {
        enum length = T[1].expand.length;
        enum minimum = T[0] > length ? length : T[0];
    }
    
    enum minLength = staticFold!(minimum, size_t.max, SF);
    
    private template robin(ulong i)
    {        
        private template takeByIndex(alias T)
        {
            static if(is(T.expand[i]))
                alias takeByIndex = T.expand[i];
            else
                enum takeByIndex = T.expand[i];
        }
        
        static if(i >= minLength)
        {
            alias robin = ExpressionList!();
        }
        else
        {
            alias robin = ExpressionList!(staticMap!(takeByIndex, SF), robin!(i+1));
        }
    }
    
    alias staticRobin = robin!0; 
}
/// Example
unittest
{
    alias test = staticRobin!(StrictExpressionList!(int, int, int), StrictExpressionList!(float, float));
    static assert(is(test == ExpressionList!(int, float, int, float)));
    
    alias test2 = staticRobin!(StrictExpressionList!(1, 2), StrictExpressionList!(3, 4, 5), StrictExpressionList!(6, 7));
    static assert([test2]== [1, 3, 6, 2, 4, 7]);
}

/**
*   Static associative map.
*
*   $(B Pairs) is a list of pairs key-value.
*/
template KeyValueList(Pairs...)
{
    static assert(Pairs.length % 2 == 0, text("KeyValueList is expecting even count of elements, not ", Pairs.length));
    
    /// Number of entries in the map
    enum length = Pairs.length / 2;
    
    /**
    *   Getting values by keys. If $(B Keys) is a one key, then
    *   returns unwrapped value, else a ExpressionExpressionList of values.
    */
    template get(Keys...)
    {
        static assert(Keys.length > 0, "KeyValueList.get is expecting an argument!");
        static if(Keys.length == 1)
        {
            static if(is(Keys[0])) { 
                alias Key = Keys[0];
            } else {
                enum Key = Keys[0];
                static assert(__traits(compiles, Key == Key), text(typeof(Key).stringof, " must have a opCmp!"));
            }
            
            private static template innerFind(T...)
            {
                static if(T.length == 0) {
                    alias innerFind = ExpressionList!();
                } else
                {
                    static if(is(Keys[0])) { 
                        static if(is(T[0] == Key)) {
                            static if(is(T[1])) {
                                alias innerFind = T[1];
                            } else {
                                enum innerFind = T[1];
                            }
                        } else {
                            alias innerFind = innerFind!(T[2 .. $]);
                        }
                    } else
                    {
                        static if(T[0] == Key) {
                            static if(is(T[1])) {
                                alias innerFind = T[1];
                            } else {
                                // hack to avoid compile-time lambdas
                                // see http://forum.dlang.org/thread/lkl0lp$204h$1@digitalmars.com
                                static if(__traits(compiles, {enum innerFind = T[1];}))
                                {
                                    enum innerFind = T[1];
                                } else
                                {
                                    alias innerFind = T[1];
                                }
                            }
                        } else {
                            alias innerFind = innerFind!(T[2 .. $]);
                        }
                    }
                }
            }

            alias get = innerFind!Pairs; 
        } else {
            alias get = ExpressionList!(get!(Keys[0 .. $/2]), get!(Keys[$/2 .. $]));
        }
    }
    
    /// Returns true if map has a $(B Key)
    template has(Key...)
    {
        static assert(Key.length == 1);
        enum has = ExpressionList!(get!Key).length > 0; 
    }
    
    /// Setting values to specific keys (or adding new key-values)
    template set(KeyValues...)
    {
        static assert(KeyValues.length >= 2, "KeyValueList.set is expecting at least one pair!");
        static assert(KeyValues.length % 2 == 0, "KeyValuesExpressionList.set is expecting even count of arguments!");
        
        template inner(KeyValues...)
        {
            static if(KeyValues.length == 2) {
                static if(is(KeyValues[0])) {
                    alias Key = KeyValues[0];
                } else {
                    enum Key = KeyValues[0];
                }
                
                static if(is(KeyValues[1])) {
                    alias Value = KeyValues[1];
                } else {
                    enum Value = KeyValues[1];
                }
                
                private template innerFind(T...)
                {
                    static if(T.length == 0) {
                        alias innerFind = ExpressionList!(Key, Value);
                    } else
                    {
                        static if(is(Key)) { 
                            static if(is(T[0] == Key)) {
                                alias innerFind = ExpressionList!(Key, Value, T[2 .. $]);
                            } else {
                                alias innerFind = ExpressionList!(T[0 .. 2], innerFind!(T[2 .. $]));
                            }
                        } else
                        {
                            static if(T[0] == Key) {
                                alias innerFind = ExpressionList!(Key, Value, T[2 .. $]);
                            } else {
                                alias innerFind = ExpressionList!(T[0 .. 2], innerFind!(T[2 .. $]));
                            }
                        }
                    }
                }
    
                alias inner = innerFind!Pairs; 
            } else {
                alias inner = ExpressionList!(inner!(KeyValues[0 .. $/2]), inner!(KeyValues[$/2 .. $]));
            }
        }
        alias set = KeyValueList!(inner!KeyValues);
    }
    
    /// Applies $(B F) template for each pair (key-value).
    template map(alias F)
    {
        alias map = KeyValueList!(staticMap2!(F, Pairs));
    }
    
    private static template getKeys(T...)
    {
        static if(T.length == 0) {
            alias getKeys = ExpressionList!();
        } else {
            alias getKeys = ExpressionList!(T[0], getKeys!(T[2 .. $]));
        }
    }
    /// Getting expression list of all keys
    alias keys = getKeys!Pairs;
    
    private static template getValues(T...)
    {
        static if(T.length == 0) {
            alias getValues = ExpressionList!();
        } else {
            alias getValues = ExpressionList!(T[1], getValues!(T[2 .. $]));
        }
    }
    /// Getting expression list of all values
    alias values = getValues!Pairs;
    
    /** 
    *   Filters entries with function or template $(B F), leaving entry only if
    *   $(B F) returning $(B true).
    */
    static template filter(alias F)
    {
        alias filter = KeyValueList!(staticFilter2!(F, Pairs));
    } 
    
    /** 
    *   Filters entries with function or template $(B F) passing only a key from an entry, leaving entry only if
    *   $(B F) returning $(B true).
    */
    static template filterByKey(alias F)
    {
        private alias newKeys = staticFilter!(F, keys);
        private alias newValues = staticMap!(get, newKeys);
        alias filterByKey = KeyValueList!(staticRobin!(StrictExpressionList!(newKeys, newValues)));
    }
}
///
unittest
{
    alias map = KeyValueList!("a", 42, "b", 23);
    static assert(map.get!"a" == 42);
    static assert(map.get!("a", "b") == ExpressionList!(42, 23));
    static assert(map.get!"c".length == 0);
    
    alias map2 = KeyValueList!(int, float, float, double, double, 42);
    static assert(is(map2.get!int == float));
    static assert(is(map2.get!float == double));
    static assert(map2.get!double == 42); 
    
    static assert(map.has!"a");
    static assert(map2.has!int);
    static assert(!map2.has!void);
    static assert(!map.has!"c");
    
    alias map3 = map.set!("c", 4);
    static assert(map3.get!"c" == 4);
    alias map4 = map.set!("c", 4, "d", 8);
    static assert(map4.get!("c", "d") == ExpressionList!(4, 8));
    alias map5 = map.set!("a", 4);
    static assert(map5.get!"a" == 4);
    
    template inc(string key, int val)
    {
        alias inc = ExpressionList!(key, val+1);
    }
    
    alias map6 = map.map!inc;
    static assert(map6.get!"a" == 43);
    static assert(map6.get!("a", "b") == ExpressionList!(43, 24));
    
    static assert(map.keys == ExpressionList!("a", "b"));
    static assert(map.values == ExpressionList!(42, 23));
}