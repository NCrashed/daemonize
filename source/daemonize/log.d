module daemonize.log;

version(Have_dlogg)
{
    import dlogg.log : LoggingLevel;
    alias DaemonLogLevel = LoggingLevel;
}
else
{
    /**
    *   Logging level options to control log output.
    */
    enum DaemonLogLevel
    {
        Notice,
        Warning,
        Debug,
        Fatal,
        Muted
    }
}

/**
*   The interface to use to pass a logger reference into the daemon runner.
*/
synchronized interface IDaemonLogger
{
    void logDebug(string message) nothrow;
    void logInfo(lazy string message) nothrow;
    void logWarning(lazy string message) nothrow;
    void logError(lazy string message) @trusted nothrow;
    DaemonLogLevel minLogLevel() @property;
    void minLogLevel(DaemonLogLevel level) @property;
    DaemonLogLevel minOutputLevel() @property;
    void minOutputLevel(DaemonLogLevel level) @property;
    void finalize() nothrow;
    void reload();
}

version(Have_dlogg)
{
    /**
    *   Light wrapper around the Dlogg logger.
    */
    synchronized class DloggLogger : IDaemonLogger
    {
        import dlogg.strict;

        this(string filePath, StrictLogger.Mode mode = StrictLogger.Mode.Rewrite) @trusted
        {
            logger = new shared StrictLogger(filePath, mode);
        }

        void logDebug(string message) nothrow
        {
            logger.logDebug(message);
        }

        void logInfo(lazy string message) nothrow
        {
            logger.logInfo(message);
        }

        void logWarning(lazy string message) nothrow
        {
            logger.logWarning(message);
        }

        void logError(lazy string message) @trusted nothrow
        {
            logger.logError(message);
        }

        DaemonLogLevel minLogLevel() @property
        {
            return logger.minLoggingLevel;
        }

        void minLogLevel(DaemonLogLevel level) @property
        {
            logger.minLoggingLevel = level;
        }

        DaemonLogLevel minOutputLevel() @property
        {
            return logger.minOutputLevel;
        }

        void minOutputLevel(DaemonLogLevel level) @property
        {
            logger.minOutputLevel = level;
        }

        void finalize() @trusted nothrow
        {
            logger.finalize;
        }

        void reload()
        {
            logger.reload;
        }

        private StrictLogger logger;
    }
}
