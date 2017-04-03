FA 0.11 has the following major drawbacks:
- .arc format isn't yet supported (sheduled for FA 0.12)
- existing archives cannot be modified, only archive creation is supported
- on archive extraction, entire archive is decompressed in memory (it cannot skip solid blocks not required for current operation)

Other missing features can be seen from comparison of command/option sets. The remaining sections briefly describe new features in FA'Next compared to FreeArc:
- [32 & 64 bit, Windows and Linux versions](#versions)
- [Deduplication](#deduplication)
- [ZSTD support](#zstd-support)
- [Lua programming](#lua-programming)
- [Prefetching](#prefetching)

<a name="versions"/>

### 32 & 64 bit, Windows and Linux versions
At last!!! 64-bit executables mean that you can use memory-hungry compression methods. In particular, LZMA now supports dictionaries up to 4000mb. Unfortunately, REP dictionary is still limited to 2 GB.

FA added support for 64-bit CLS DLLs. "foo" compression method tries to load cls64-foo.dll and then cls-foo.dll in 64-bit executable, while in 32-bit executable it tries cls32-foo.dll and then cls-foo.dll.

### Deduplication
`-dup` option enables full-archive deduplication similar to ZPAQ: input data are split into fixed-size buffers (`--bufsize` option), each buffer split into content-defined chunks (`--chunk/--min-chunk` option specify average/minimum chunk size), duplicate chunks are eliminated while remaining data are recombined into fixed-size buffers once again, and each buffer compressed with algorithm specified by `-m` options. FA doesn't try to compress deduplicated blocks whose order-0 entropy is >99% (threshold set by `--ratio` option, use `--ratio=100` to disable the check).

And of course, files are sorted and split into groups according to arc.groups order, and compression algorithm for each block chosen based on the group name (\$text, \$bmp and so) - but, unlike usual mode, each buffer (as recombined after deduplication) compressed independently of other buffers. This opens (not yet implemented) possibility to decompress only subset of blocks when part of archive need to be extracted.

`--threads` option selects number of worker threads performing CPU-intensive deduplication and compression operations (default = number of CPU threads), each thread requires 2 buffers (for input and output data) of `--bufsize` bytes. Extra buffers for read-ahead may be specified by `--io-threads` option (defaults to 1), or by `--cache`.

By default, chunks are deduplicated using very fast VMAC hashing algorithm, and these hashes aren't stored in the archive. `--save-sha-hashes` option employs SHA-256 hashes instead and stores them into archive. These hashes are then checked on extraction, ensuring data integrity. Even if archive contains SHA-256 hashes, you can disable their checking on extraction with `--no-check` option.

Decompression of these archives uses Future-LZ algorithm previously developed for SREP - unlike ZPAQ, it keeps data for all future matches in memory, so it doesn't need to reread these data from disk, but requires more RAM. This means that on decompression, speed is guaranteed but memory usage is unpredictable, while ZPAQ is on opposite side.

Compared to ZPAQ:
- FA is much faster and produces more compact archives by not storing SHA hashes by default
- Compression memory is limited, but decompression memory is unpredictable, usually about 10% of uncompressed size
- FA can't update archives yet, so it cannot be used for incremental backups
- FA selects compression algorithm for each buffer based on filenames (as specified in arc.groups), rather than data themself

Full-archive deduplication may be also considered as alternative to the REP filter. Usually, replacing REP with deduplication makes archive bigger, but reduces memory required for decompression. In my experiment with compression of 4.7 GB, `-m4 -dup` produced archive 4% larger than `-m4`, but decompression memory was dropped from 735 to 179 MB, while compression and decompression speeds kept unchanged. Unfortunately, memory required for decompression cannot be controlled, and isn't known until archive is created.

Using `-dup` and REP filter simultaneously is a bad idea, so shipped fa.ini includes [Lua code] section that removes REP from compression algos when `-dup` is enabled. You may disable this section as experiment. Consider this code as demo of using Lua to deal with compression method.

### ZSTD support
FA incorporates ZSTD 1.1, and shipped fa.ini replaces Tornado with ZSTD in -m1/m2 modes.

Example of compression method with all parameters specified: `zstd:19:d4m:c1m:h4m:l16:b4:t64:s7`.

Description of all parameters:
- :19  = compression level (profile), 1..22 : larger == more compression
- :d4m = dictionary size in bytes, AKA largest match distance : larger == more compression, more memory needed during compression and decompression
- :c1m = fully searched segment : larger == more compression, slower, more memory (useless for fast strategy)
- :h4m = hash size in bytes : larger == faster and more compression, more memory needed during compression
- :l16 = chain length, AKA number of searches : larger == more compression, slower
- :b4  = minimum match length : larger == faster decompression, sometimes less compression
- :t64 = target length AKA fast bytes - acceptable match size (only for optimal parser AKA btopt strategy) : larger == more compression, slower
- :s7  = parsing strategy: fast=1, dfast=2, greedy=3, lazy=4, lazy2=5, btlazy2=6, btopt=7

By default, compression level parameter is set to 1, and other parameters are set to 0, that means "use default values as specified in the [table](https://github.com/facebook/zstd/blob/v1.1.0/lib/compress/zstd_compress.c#L3044)".

### Lua programming
Major new feature of FA is its [[Lua programmability|Lua code]].
You can use Lua code to add/change/remove options, execute actions on operation start/finish, on warnings and errors,
including sophosticated manipulations on compression methods, analysis of operation being performed and option settings. FA automatically executes `[Lua code]` sections from your `fa.ini`.

Most of program options are already implemented by the built-in Lua code,
and you can [[browse this code|FA 0.11 builtin Lua option definitions]] in order to learn how to add your own options. 

[[`--filter` option|Lua-code#file-filtering]] allows to select files to process with arbitrary Lua predicate based on file name, type, size, time and attr.

### Prefetching
12 years ago FreeArc pioneered reading-ahead technique that significantly improved speed, when lots of small files are compressed, by prefetching them into large buffer (so-called read-ahead cache) in parallel with compression operation.

Now FA improves this technique by prefetching directly into OS cache. This avoids extra memory copy operation, avoids allocation of extra buffer in application and allows to read-ahead as much data as OS cache can hold. My benchmarks show that new technique allows FA to outperform fastest NanoZip compression modes in real SSD operation.

Default option setting is equivalent to `--prefetch:1:256mb`, i.e. 1 thread prefetching up to 256 MB. `--prefetch` option without parameters is equivalent to `--prefetch:8:2gb`. Overall, 1 thread is optimal for HDD, multiple threads - for SSD, and lookahead amount should fit into OS cache available during operation. Automatic tuning of this option may be a good application of [Lua programming](#lua-programming).

Prefetching can be disabled with `--prefetch-` option.

FA also includes traditional read-ahead cache, that can be controlled via options `--cache`, `--io-threads` and `--bufsize`. Essentially, `cache_size = num_io_threads * buffer_size`. So, if you are going to disable prefetching to OS cache, you may want to raise size of the read-ahead cache.
