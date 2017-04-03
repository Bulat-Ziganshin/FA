### Option names
This is the C++ option definitions code as included in FA 0.11. The first column shows option names that may be used to [[modify/remove these builtin options|../Lua-code.md#options]].
```c++
{"deduplication_mode", deduplication_mode,     0, {"-dup",         "--deduplication"},                "global deduplication a-la ZPAQ"},
{"config_env",       config_env,               0, {"-envVAR"},                                        "read default options from environment VAR (default: DEFAULT_VALUE)", true /*for_preparsing*/},
{"config_file",      config_file,              0, {"-cfgFILE",     "--config=FILE"},                  "use configuration FILE (default: DEFAULT_VALUE)", true /*for_preparsing*/},
{"remark",           remark,                   0, {"-rem...",      "--rem..."},                       "remark (ignored commentary)"},
{"sort_order",       sort_order,               0, {"-dsORDER",     "--sort=ORDER"},                   "sort files in the order defined by chars 'gerpnsd' ('DEFAULT_VALUE' by default)"},
{"recursive",        recursive,                0, {"-r",           "--recursive"},                    "recursively find files to add (to do: or archives to list/extract)"},
{"answer_yes",       answer_yes,               0, {"-y",           "--answer-yes", "--yes"},          "answer Yes to all queries"},
{"test",             test,                     0, {"-t",           "--test"},                         "test archive after operation"},
{"keep_broken",      keep_broken,              0, {"-kb",          "--keep-broken", "--keepbroken"},  "keep extracted files that failed the CRC check"},
{"dirs",             dirs,                     0, {"",             "--dirs"},                         "add empty dirs to archive"},
{"no_dirs",          no_dirs,                  0, {"-ed",          "--no-dirs",     "--nodirs"},      "don't add empty dirs to archive"},
{"no_warnings",      no_warnings,              0, {"",             "--no-warnings", "--nowarnings"},  "don't print warning messages to console"},
{"no_read",          no_read,                  0, {"",             "--no-read",     "--noread"},      "only build list of files to compress"},
{"no_write",         no_write,                 0, {"",             "--no-write",    "--nowrite"},     "don't create archive file"},
{"no_data",          no_data,                  0, {"",             "--no-data",     "--nodata"},      "don't write compressed data to the archive"},
{"no_dir",           no_dir,                   0, {"",             "--no-dir",      "--nodir"},       "don't write archive directory"},
{"no_check",         no_check,                 0, {"",             "--no-check",    "--nocheck"},     "don't check SHA-256 hashes of extracted data"},
{"save_sha_hashes",  save_sha_hashes,          0, {"",             "--save-sha-hashes"},              "store in the archive SHA-256 hashes of the chunks"},
{"profiler",         profiler,                 0, {"",             "--profiler"},                     "print internal profiling stats"},
{"print_config",     print_config,             0, {"",             "--print-config"},                 "display built-in definitions of compression methods"},
{"num_threads",      num_threads,              0, {"-tNUM",        "--threads=NUM",   "-mtNUM"},      "worker threads (default: DEFAULT_VALUE)"},
{"io_threads",       io_threads,               0, {"-miNUM",       "--io-threads=NUM"},               "I/O threads"},
{"cache_size",      {cache_size,  'm'},        0, {"",             "--cache=BYTES"},                  "size of read-ahead cache"},
{"bufsize",         {buffer_size, 'm'},        0, {"-bBYTES",      "--bufsize=BYTES", "-mbBYTES"},    "buffer size"},
{"chunk_size",      {chunk_size,  'b'},        0, {"-cBYTES",      "--chunk=BYTES"},                  "average chunk size (default: DEFAULT_VALUE)"},
{"min_chunk",       {min_chunk,   'b'},        0, {"",             "--min-chunk=BYTES"},              "minimum chunk size (default: DEFAULT_VALUE)"},
{"logfile",          logfile,                  0, {"",             "--logfile=FILENAME"},             "log file"},
{"group_file",       group_file,               0, {"",             "--groups=FILE"},                  "name of groups file (DEFAULT_VALUE by default)"},
{"workdir",          workdir,                  0, {"-wDIRECTORY",  "--workdir=DIRECTORY"},            "DIRECTORY for temporary files"},
{"diskpath",         diskpath,                 0, {"-dpDIR",       "--diskpath=DIR"},                 "base DIR on disk"},
{"method",           ParseCompressionMethod,   0, {"-mMETHOD",     "--method=METHOD"},                "set compression method"},
{"solid",            ParseSolidOption,         0, {"-sGROUPING",   "--solid=GROUPING"},               "group files into solid blocks"},
{"ratio",            ParseRatio,               0, {"",             "--ratio=PERCENTS"},               "automatically store blocks with order-0 entropy >PERCENTS% ("+std::to_string(int(ratio))+" by default)"},
{"overwrite",        ParseOverwiteMode,        0, {"-oMODE",       "--overwrite=MODE"},               "existing files overwrite MODE (+/-/p)"},
```

<a name="fields"/>

### `command.*` pseudofields providing read/write access to values of corresponding C++ options
```c++
lua.register_var("cmd",             cmd);
lua.register_var("arcname",         arcname);
lua.register_var("filenames",       filenames);
lua.register_var("compression_groups", compression_groups);
lua.register_var("compression_methods", compression_methods);
lua.register_var("config_env",      config_env);
lua.register_var("config_file",     config_file);
lua.register_var("deduplication_mode", deduplication_mode);
lua.register_var("num_threads",     num_threads);
lua.register_var("io_threads",      io_threads);
lua.register_var("num_buffers",     num_buffers);
lua.register_var("ratio",           ratio);
lua.register_var("cache_size",      cache_size);
lua.register_var("buffer_size",     buffer_size);
lua.register_var("chunk_size",      chunk_size);
lua.register_var("min_chunk",       min_chunk);
lua.register_var("prefetch_threads",prefetch_threads);
lua.register_var("prefetch_cache",  prefetch_cache);
lua.register_var("logfile",         logfile);
lua.register_var("workdir",         workdir);
lua.register_var("diskpath",        diskpath);
lua.register_var("sort_order",      sort_order);
lua.register_var("group_file",      group_file);
lua.register_var("recursive",       recursive);
lua.register_var("answer_yes",      answer_yes);
lua.register_var("overwrite",       overwrite);
lua.register_var("test",            test);
lua.register_var("keep_broken",     keep_broken);
lua.register_var("dirs",            dirs);
lua.register_var("no_dirs",         no_dirs);
lua.register_var("no_warnings",     no_warnings);
lua.register_var("no_read",         no_read);
lua.register_var("no_write",        no_write);
lua.register_var("no_data",         no_data);
lua.register_var("no_dir",          no_dir);
lua.register_var("no_check",        no_check);
lua.register_var("save_sha_hashes", save_sha_hashes);
lua.register_var("print_config",    print_config);
lua.register_var("profiler",        profiler);
```
