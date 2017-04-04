
FA'Next 0.20 includes the following improvements:

- use of .arc archive format (the same as FreeArc), extended with support of file attributes and deduplication info

- encryption support, including all FreeArc options (-p -hp -kf -op -okf -ae) and algorithms (aes, blowfish, serpent, twofish, aes-128, aes/cfb, aes+serpent...)

- large part of program was rewritten in Lua and now shipped in the source form. Compared to FA'Next 0.11, amount of Lua code was increased from 500 to 3000 lines and now it's a third of entire program size. Overall, C++ code now handles only boring low-end details (back-end), while Lua code handles all interaction with user (UI, cmdline/inifile processing, compression and encryption methods management). Lua 5.3.4, Penlight 1.4.1 and LuaFileSystem 1.6.3 were incorporated into the executable. For the rest of us, this means that we can add new features just by dropping corresponding Lua scripts, provided by 3rd-party developers, into the program directory.

- UI/logging got the full Unicode support, display pretty the same information as FreeArc, and implements all features of the `-di` option

- compression methods are automatically limited to the RAM size, options -lc/-ld allows to further tune the RAM usage. Default settings for compression commands is `-lc75% -ld1600m`, so archives made with default `-ld` setting may encounter problems with extraction on 32-bit systems.

- 64-bit versions of arc*.sfx modules, unarc.exe and unarc.dll

- the Lizard compression library and support of CELS external algorithms

***

Table of contents:

* [User experience](#user-experience)
  * [New commands and options](#new-commands-and-options)
  * [.arc archive format](#arc-archive-format)
  * [Encryption](#encryption)
  * [Lizard and CELS compression](#lizard-and-cels-compression)
  * [UI and logfile](#ui-and-logfile)
* [Lua support](#lua-support)
  * [Program startup](#Program-startup)
  * [Services provided by the C++ code to the Lua code](#)
    * [Services](#)
    * [Variables](#)
  * [Services provided by the Lua code to itself](#)
  * [Services provided by the Lua code to the program](#)
    * [The event handling machinery](#The-event-handling-machinery)
    * [Method "filtering" events](#Method-filtering-events)
    * [Defining new options](#Defining-new-options)
    * [Defining new commands](#Defining-new-commands)
    * [UI implementation](#UI-implementation)


# User experience

## New commands and options

New commands (compatible with FreeArc):
```
lb|barelist   bare list of filenames in the archive
v[erblist]    verbosely list files in the archive
```

Now FA'Next supports all FreeArc archive listing operations and they display the same information as their FreeArc cousins. Additionally, file attributes are displayed in the same format as in RAR. Note that FA'Next reads archive directory about 100x faster than FreeArc (you can see that with `-di+$` option), so it's a preferable way to quickly list .arc archive contents in your tools.

New options, grouped by their purpose (most are compatible with FreeArc, remaining were borrowed from RAR):
```
-ai          --no-attrs               don't save/restore file attributes
-oc                                   restore NTFS Compressed file attribute
-ep3                                  keep drive/rootchar in filenames, useful for multi-disk backups
-k           --lock                   lock archive from further updates
-sfx[MODULE]                          add sfx MODULE ("freearc.sfx" by default)
-zFILE       --arccmt=FILE            read archive comment from FILE or stdin
             --archive-comment=COMMENT input archive COMMENT in cmdline
             --no-arc-ext             don't add default extension to archive name
             --no-crc                 don't compute/check CRC

-p[PASSWORD] --password=PASSWORD      encrypt/decrypt compressed data using PASSWORD
-hp[PASSWORD] --headers-password=PASSWORD encrypt/decrypt archive headers and data using PASSWORD
-kfKEYFILE   --keyfile=KEYFILE        encrypt/decrypt using KEYFILE (with or without password)
-opPASSWORD  --old-password=PASSWORD  old PASSWORD used only for decryption
-okfKEYFILE  --old-keyfile=KEYFILE    old KEYFILE used only for decryption
-aeALGORITHM --encryption=ALGORITHM   encryption ALGORITHM (aes, blowfish, serpent, twofish, aes+serpent...)

-dmMETHOD    --dirmethod=METHOD       compression method for archive directory
-lcN         --LimitCompMem=N         limit memory usage for compression to N mbytes (or N% of RAM)
-ldN         --LimitDecompMem=N       limit memory usage for decompression to N mbytes (or N% of RAM)
-mdN         --dictionary=N           set compression dictionary to N mbytes

-e[+]MASK                             include/exclude files based on file attributes (MASK is a number or [SHARD]+)
-taTIME      --time-after=TIME        select files modified after specified TIME (format: YYYYMMDDHHMMSS)
-tbTIME      --time-before=TIME       select files modified before specified TIME (format: YYYYMMDDHHMMSS)
-tnPERIOD    --time-newer=PERIOD      select files newer than specified time PERIOD (format: #d#h#m#s)
-toPERIOD    --time-older=PERIOD      select files older than specified time PERIOD (format: #d#h#m#s)

-diTYPES     --display=TYPES          select TYPES of information displayed ("haftnwk" by default)
-h           --help                   display help on commands and options
-ioff        --shutdown               shutdown computer when operation completed
             --queue                  queue operations across multiple FreeArc copies
```

Program can be called as `fa @commandfile` where commandfile is a file containing an entire command line. Note that command line in commandfile is split into separate arguments just by whitespace, there is no way yet to use quoting to provide arguments containing whitespace characters.

Option `-ds` now can reverse sort order by using '-' suffix after the sorting symbol, f.e. `--sort=ge-p-s` sorts by group, then extension and path in descending order, and finally by size.

Option `--prefetch` now supports `10%` syntax that limits prefetching to 10% of the RAM size.

Options -n/-x now support listfiles: `-x@excluded.lst`.

On the start, FA'Next reads contents of all `fa-*.ini` files in the executable directory and executes them in the same way as `fa.ini`. At the same time, all the `fa-*.lua` files are executed as Lua scripts, so you can you use either Lua files or Lua sections in ini files to define additional commands, options, event handlers and so on. `-cfg-` option disables processing of these files (as well as processing of `fa.ini` file and `FA_CFG` environment variable). Note that on Windows, this feature will work only if the executable directory doesn't have Unicode chars in the pathname.

All options now are parsed by the Lua code and most options are consumed by the Lua code. You can add new options and commands and modify existing ones by dropping Lua scripts into the executable directory. The entire cmdline/inifile parsing is implemented in Lua (main procedure is ParseCommandLine() in file Cmdline.lua), so you can modify it too.


## .arc archive format

Since now FA'Next supports the same .arc format as original FreeArc, archives made by FreeArc can be listed/extracted by FA'Next and vice versa - archives created by FA'Next can be processed with FreeArc, SFX modules, unarc.exe and unarc.dll. Moreover, we added x64 versions of these modules, so now you can extract f.e. archives with 4GB lzma dictionary.

Option `-sfx[MODULE]` can be used in compression command to prepend self-extracting module to the archive being created. If supplied module name has no path chars, the module will be searched in the FA'Next executable directory. Default module name is `freearc.sfx`.

FA'Next extends .arc format by storing OS attributes (read-only, hidden... on Windows and rwx-rwx-rwx on Unix) for each file/directory. The attributes are stored by compression commands, and restored by extraction ones. Archive listing commands show attributes in the same way as RAR does. Attributes stored on different OS (Unix/Windows) are displayed by archive listing commands, but cannot be restored on extraction. The attributes stored in archive ATM are ignored by old tools (including current versions of SFX/unarc modules). Option `-ai` AKA `--no-attrs` forces FA'Next to mimic old behavior - i.e. don't store file attributes when creating archive, and don't restore attributes on extraction. NTFS Compressed attribute is stored on Windows systems, but restored on extraction only when `-oc` option is specified.

Archives, created with `-dup` option, contain deduplication information required for extraction. Thus, old tools can't extract such archives, but can list their contents. Compression option `--save-sha-hashes` additionally store SHA256 checksum for each deduplicated chunk. These checksums are checked on extraction, unless `--no-check` option is specified.

Finally, option `--no-crc` disables CRC computation/check and can be used in any compression and extraction commands.

Options `-k` (lock archive from further updates), `-ep3` (keep full pathname on creation and extraction), `-zFILE` (add archive comment from FILE) and `--no-arc-ext` (don't add default .arc extension, even when archive name has no extension) should be familiar to FreeArc users, while option `--archive-comment=COMMENT` (add archive COMMENT specified literally) is more intended for tools.


## Encryption

FA'Next 0.20 provides the same encryption functionality as FreeArc:
```
-p[PASSWORD] --password=PASSWORD      encrypt/decrypt compressed data using PASSWORD
-hp[PASSWORD] --headers-password=PASSWORD encrypt/decrypt archive headers and data using PASSWORD
-kfKEYFILE   --keyfile=KEYFILE        encrypt/decrypt using KEYFILE (with or without password)
-opPASSWORD  --old-password=PASSWORD  old PASSWORD used only for decryption
-okfKEYFILE  --old-keyfile=KEYFILE    old KEYFILE used only for decryption
-aeALGORITHM --encryption=ALGORITHM   encryption ALGORITHM (aes, blowfish, serpent, twofish, aes+serpent...)
```

Encryption is enabled by using any of -p, -hp, -kf options. Option -p provides password and requests encryption of only data, while -hp requests encryption of both data and archive directory. Option -kf provides keyfile (equivalent to password stored in the file). Password and keyfile may be used simultaneously, in this case password is prepended to keyfile contents. If option -hp doesn't include password, it only enables archive directory encryption, while password/keyfile should be supplied with -p/-kf options.

Options -op/-okf may be used to specify any number of passwords/keyfiles that will be used only for decryption of existing data. When FA'Next extracts encrypted data, it tries all passwords specified by -p/-op options, then all keyfiles specified by -kf/-okf and finally all combinations of any password with any keyfile.

ATM FA'Next cannot request passwords interactively, so using -p/-p?/-hp/-hp? without providing password/keyfile in other way is impossible. Similarly, if data can't be decrypted with any password/keyfile provided, decompression fails.

***

Option -ae allows to specify encryption algorithm. Currently supported algorithms are:
- aes-128,192,256
- serpent-128,192,256
- twofish-128,192,256
- blowfish-64,72..448

Each algorithm can be used in CTR or CFB mode, f.e. `aes-256/ctr`. Keysize and/or mode can be omitted, in this case largest size and CTR mode are used: aes = aes-256 = aes/ctr = aes-256/ctr.

Finally, passwords are encrypted using PKCS5#2 algorithm. Number of algorithm iterations may be specified by ":n" parameter, f.e. "aes:n2000" and defaults to 1000.

Encryption algorithms can be chained similarly to TrueCrypt, f.e. "--encryption=aes+serpent/cfb+blowfish", or even "--encryption=aes+aes" which essentially increases key size to 2*256 bits.

The entire encryption management is implemented in Lua (file Encryption.lua), so you can further improve it. Only low-level routines, performing actual data encryption, are in C++.


## Lizard and CELS compression

We added the compression library Lizard (former LZ5 v2) by Przemyslaw Skibinski, that can be competitive with LZ4 and ZSTD. There are compression levels from `lizard:10` to `lizard:49` (default is 17), providing various cspeed/dspeed/ratio tradeoffs. Since the compression dictionary is limited to 16 MB, it may be especially useful with 4x4, f.e. `-m=4x4:b64m:lizard:49`.

FA'Next 0.20 also added support for CELS external compression libraries. CELS is the further development of CLS. CELS provides external compression libraries tight integration with FA'Next compression management code, that previously was available only to internal algorithms. This means that FA'Next can report and modify memory usage, dictionary/block size and other algorithm settings, tailoring compression algorithm to your computer and data being compressed. CELS libraries also can be used by unarc, sfx modules and unarc.dll.

Finally, the Delta filter got a 50% encoding speed boost: now it can process 250-300 MB/s on my i7-4770.


## UI and logfile

Option `-di` provides flexible configuration of the program output. Its parameter is a list of symbols enabling each part of the output:
- h: program header like `FreeArc'Next-x64 v0.20 (Mar 17 2017)`
- a: archive name and operation like `creating archive m:\a.arc`
- o: options read from environment/config like `using additional options: --logfile=c:\temp\fa.log --display=dnwl`
- c: compression method like `Compress with rep:512mb:c512+4x4:zstd:2:8mb, $compressed => rep:512mb:c512`
- m: memory requirements like `Compression memory 693mb + 8*1mb read-ahead buffers, decompression memory 528..674 MiB`
- f: compression/decompression totals like `Compressed: 21,000 -> 6,290 bytes. Ratio 29.95%`
- t: compression/decompression time like `Compression time: cpu 203.27 sec/real 41.22 sec = 493%. Speed 58.1 MiB/s`
- l: the long progress indicator (see below); it's the only suboption absent in original FreeArc
- d: archive directory original and compressed size like `Archive directory: 2,284,922 -> 675,257 bytes` (printed only when the directory size is >10KB)
- w: warning messages like `WARNING: can't open file "C:\base\Multimedia\foobar2000\running"`
- n: total number of warnings at the end of operation like `There were 2 warning(s)`
- k: `All OK` at the end of operation if there were no warnings/errors
- e: extra empty line at the end of output
- `$`: display profiling information on the screen
- `#`: write profiling information to the logfile
- `%`: display system memory info prior to operation

Also, `-di+CHARS` adds CHARS to the current `-di` config, while `-di-CHARS` removes these CHARS, so `-di=haoc -di-hc -di+l` is equivalent to `-di=aol`.

***

Default setting is `-di=haftnwk` displaying just essential information (default setting can be restored with `-di--`). Option `-di` without parameter enables all normal suboptions and is equivalent to '-di=haocmftdnwk'. Compare their output:
```
C:\test>fa create m:\a
FreeArc'Next-x64 v0.20 (Mar 17 2017) creating archive m:\a.arc
Found 2,511,674,419 bytes in 221 folders and 2,301 files
Compressed: 2,511,674,419 -> 319,468,222 bytes. Ratio 12.72%
Compression time: cpu 203.32 sec/real 41.31 sec = 492%. Speed 58.0 MiB/s
All OK

C:\test>fa create m:\a -di
FreeArc'Next-x64 v0.20 (Mar 17 2017) creating archive m:\a.arc using additional options: --logfile=c:\temp\fa.log
Found 2,511,674,419 bytes in 221 folders and 2,301 files
Compress with rep:512mb+dispack070+delta+4x4:lzma:96mb:normal:16:mc8, $obj => rep:512mb+delta+4x4:lzma:96mb:normal:16:mc8, $text => grzip:8mb:m1:l32:h15, $wav => tta, $bmp => mm+grzip:8mb:m1:l2048:h15:a, $compressed => rep:512mb+4x4:zstd:7:16m:h8m
Compression memory 3082mb + 8*1mb read-ahead buffers, decompression memory 735..2514 MiB.  Prefetch 256mb using 1 thread
Compressed: 2,511,674,419 -> 319,468,222 bytes. Ratio 12.72%
Compression time: cpu 203.27 sec/real 41.22 sec = 493%. Speed 58.1 MiB/s
Archive directory: 76,531 -> 27,199 bytes
All OK
```

***

If suboption 'l' is enabled, long progress indicator displayed for disk scan, compression and extraction operations:
```
C:\test>fa create m:\a -di+l
FreeArc'Next-x64 v0.20 (Mar 17 2017) creating archive m:\a.arc
Found 2,511,676,076 bytes in 221 folders and 2,301 files  (RAM 3 MiB, I/O 0.000 sec, cpu 0.000 sec, real 0.009 sec)
Compressed: 2,511,676,076 -> 319,470,935: 12.72%.  I/O 9.126 sec, cpu 11.8 MiB/s (202.318 sec), real 59.1 MiB/s (40.503 sec) = 500%
All OK
```

Without the 'l' suboption, the progress indicator sits on diet:
```
C:\base>fa create m:\a
FreeArc'Next-x64 v0.20 (Mar 17 2017) creating archive m:\a.arc
Found 33,269,658,966 bytes in 36,046 folders and 505,290 files (1.70 sec)
11%: 3,643 -> 197 MiB: 5.41%.  113 MiB/s = 77% (32 sec).  ETA 03:49
```

Once the compression/extraction operation is completed, the short progress indicator is replaced by summary lines produced by 'f' and 't' suboptions. If neither 'f' nor 't' are enabled, final output of the short progress indicator kept to show the result. If long progress indicator is enabled, 'ft' suboptions are ignored.


***

In `-dup` mode, extra information is displayed: deduplicated size between original and compressed sizes in the long progress indicator, and memory, that will be required for decompression, in the archive directory line. When --save-sha-hashes is enabled, the directory line also displays the hash storage size, which is usually much larger than the directory itself (and incompressible):

```
C:\base>fa create m:\a -dup --save-sha-hashes -di=ld
Found 2,512,004,907 bytes in 222 folders and 2,307 files  (RAM 3 MiB, I/O 0.016 sec, cpu 0.000 sec, real 0.016 sec)
Compressed: 2,512,004,907 -> 1,282,288,437 -> 199,824,807: 7.95%.  RAM 17 MiB.  I/O 4.446 sec, cpu 12.4 MiB/s (193.878 sec), real 68.3 MiB/s (35.065 sec) = 553%
Archive directory: 1,310,024 -> 578,805 bytes, SHA hashes: 8,356,097 bytes.  Decompression memory: 218 + N*361 = 579..3,106 MiB

C:\base>fa t m:\a -di=l
Testing 2,512,004,907 bytes in 222 folders and 2,307 files
Tested: 199,824,807 -> 1,282,288,437 -> 2,512,004,907: 7.95%.  RAM 0 / 218 MiB.  I/O 2.200 sec, cpu 17.7 MiB/s (135.112 sec), real 79.4 MiB/s (30.171 sec) = 448%
```

***

Operation logging (option --logfile) got a lot of improvements:
- each line in logfile is prefixed by PID (process ID) number, allowing to distinguish lines from multiple simultaneous runs
- log of each command starts with a line that includes command start time, current directory and command line with sensitive information (e.g. passwords) removed
- logfile gets the same information as should be printed to the screen if all additional display options will be enabled
- the only exceptions are symbol '$' that prints profiling info to the screen ('#' outputs the same info to the logfile), and '%' that can output memory info only to the screen
- 'l' suboption also outputs long operation results to the logfile
- all info saved to logfile is UTF-8 encoded

F.e., log of the previous operation:
```
10492: [Mon Mar 27 14:18:22 2017]  C:\base>fa t m:\a -di=l
10492: FreeArc'Next-x64 v0.20 (Mar 17 2017) testing archive m:\a.arc using additional options: --logfile=c:\temp\fa.log --display=dnwl
10492: Testing 2,512,004,907 bytes in 222 folders and 2,307 files
10492: Tested: 199,824,807 -> 1,282,288,437 -> 2,512,004,907: 7.95%.  RAM 0 / 218 MiB.  I/O 2.200 sec, cpu 17.7 MiB/s (135.112 sec), real 79.4 MiB/s (30.171 sec) = 448%
10492: All OK
```

The whole UI/logging is now implemented in Lua (file UI.lua), so you can further modify it to tailor your needs.


# Lua support

New Lua functionality can be split into 3 groups:
- services provided by the C++ code to the Lua code
- services provided by the Lua code to itself
- services provided by the Lua code to the program


## Program startup

At the program start, FA'Next creates a single Lua state, loads into this state built-in libraries, and then executes built-in Lua scripts. The rest of configfile/cmdline processing is implemented in these scripts, in particular ParseCommandLine() function that is called by the C++ code to parse command line and config files, and supplementary functions in Cmdline.lua called by ParseCommandLine().

The built-in ParseCommandLine() loads all `fa-*.ini` and executes all `fa-*.lua` files in the executable directory, unless `-cfg-` option was given. You can use these files to modify existing behavior or add new one. It can be implemented by defining new commands, options, event handlers, redefining existing ones and even redefining functions defined by the built-in Lua code.

If the executable directory contains `fa_init.lua` file, this file is executed instead of the built-in Lua scripts. The code of built-in scripts is provided in Lua directory of program distribution, as well as example of `fa_init.lua` that just executes these external scripts in the proper order. So by copying this file into the executable directory, you can replace execution of built-in code with execution of equivalent external code. And then you can modify these external scripts in the way you wish, totally replacing built-in Lua code with your own external one instead of replacing only individual functions using `fa-*.lua/ini` files.

Since the only one Lua instance exists, all calls to Lua code from different C++ threads are serialized. You can use global Lua variables to keep state between the calls (that is used a lot by the built-in Lua code).

A short summary of the built-in modules (in the order of loading):
- Startup.lua: should be loaded first. Imports Penlight, defines extra utility functions and Unicode-aware file operations, provides the event handling machinery and defines most of the built-in events
- OptionParser.lua: provides the option parsing and file-filtering machinery
- Cmdline.lua: parses command line and config files, in particular executes command/option handlers as necessary
- Compression.lua: provides the compression method string and compression groups handling machinery, implements most compression-related options
- CompressionMethod.lua: implements options `-m` and `-dm` and parses the `[Compression methods]` config file section defining rules for handling these options
- Encryption.lua: provides the encryption method handling machinery and implements encryption-related options
- Options.lua: implements all remaining options, including C++ ones
- UI.lua: defines console UI, logging, profiling and implements corresponding options, mainly `-di`


## Services provided by the C++ code to the Lua code

Changes in the built-in libraries:
- Lua itself was updated to latest version [5.3.4](https://www.lua.org/manual/5.3/)
- added [LuaFileSystem 1.6.3](http://keplerproject.github.io/luafilesystem/manual.html) that provides filesystem operations absent in the Lua itself
- added [Penlight 1.4.1](http://stevedonovan.github.io/Penlight/api/index.html) that is similar to the Python built-in library

The filesystem operations, provided by all these libraries, aren't Unicode-aware on Windows - instead they use filenames encoded by ANSI codepage. So, we added Unicode/UNC/LongName-aware operations:
- File.open(filename,mode) - replaces io.open
- File.exists(filename), Dir.exists(dirname) - return true if file/directory exists
- File.delete(filename), Dir.delete(dirname) - delete file/directory
- File.rename(oldname,newname) - change filename
- File.GetSize(filename), File.GetTime(filename), File.GetAttr(filename) - get file information
- File.SetAttr(filename,attr), File.SetTime(filename,time) - modify file information
- Dir.create(dirname), Dir.createRecursively(dirname) - create directory (including all intermediate directories)
- Dir.GetCurrent() - return current directory
- SetTempDir(dirname) - set directory for temporary files, that may be created by external compressors


### Services

New OS services:
- GetMaxBlockToAlloc() returns size of largest contiguous memory block we can alloc
- GetTotalMemoryToAlloc() returns total size of all memory blocks we can alloc
- TryToAlloc(size) returns true if a memory block with given size can be allocated
- TestMalloc() prints information requested by `-di%`
- PowerOffComputer() shutdowns the computer
- GetOSDisplayString() returns string describing OS version
- ExecutableFilename() returns full pathname of the executable, UTF8-encoded
- GetPID() returns the current process ID
- GetKernelTime() returns number of kernel (I/O) seconds spent in the current process

New program services:
- ClearExternalCompressorsTable() clears the external compressors table
- AddExternalCompressor(section) adds external compression, described by the `section`, to the table, returning zero if parsing was failed and non-zero on success
- SetCompressionLibDebugMode(1/0) enables/disables displaying of debugging/profiling messages in the Compression Library. Currently, debugging mode only forces printing of external compression command even in stdin-to-stdout mode
- AddFilenames(filenames) adds filenames in the list to the `command.filenames`
- AddListfile(listfile) adds filenames from listfile to the same `command.filenames`. Both are used during ParseCommandLine() and implemented in C++ to speed up the execution
- CppParseSolidOption(param) parses `-s` option parameter

New compression-related services:
- CanonizeCompressor(compressor,false) returns a canonical string representing a compressor
- CanonizeCompressor(compressor,true) returns purified compressor string, dropping parameters not required for decompression

New encryption-related services:
- GenerateRandomBytes(N) returns N bytes of absolutely random data (random bytes generated by the OS are mixed with Fortuna(SHA512) crypto-PRNG algorithm)
- `Pbkdf2Hmac(pwd, salt, numIterations, keySize)` generates keySize-long key from password and salt using numIterations of sha-512 hashing `(PKCS5#2)`


### Variables

New pseudo-table `archive` contains the following fields with information about the archive being processed: deduplication_mode, locked, comment, rr_settings, sfx_size, host_os.

The pseudo-table `command` includes the following fields:
- argv0 - original `argv[0]`
- argv - original cmdline, without `argv[0]`
- cmd, arcname, filenames - command name, archive name and filename list extracted from the cmdline
- sfxdata contains an SFX module that will be prepended to archive by compression commands
- group_data contains list of groups (multiline string) used as arc.groups contents
- ui_progress_interval is an UI refresh interval (see below)

Remaining `command` fields represent current values of the following options:
```C++
    // Option type, name and initial value:
    bool                deduplication_mode              = false;
    int                 num_threads                     = GetProcessorsCount();
    int                 io_threads                      = -1;
    TBufSize            cache_size                      = 0;
    int                 num_buffers;
    double              ratio                           = 99;
    std::string         directory_compressor            = "lzma:1m";
    StringVector        compression_groups;
    StringVector        compression_methods;
    TBufSize            buffer_size                     = 0;
    TBufSize            chunk_size                      = 4*kb;
    TBufSize            min_chunk                       = 48;
    int                 prefetch_threads                = 1;
    FileSize            prefetch_cache                  = 256*mb;
    std::string         diskpath                        = "";
    std::string         sort_order                      = "";
    std::string         archive_comment                 = "";
    bool                recursive                       = false;
    bool                test                            = false;
    bool                lock_archive                    = false;
    bool                keep_broken                     = false;
    int                 expand_paths                    = 0;
    bool                dirs                            = false;
    bool                no_dirs                         = false;
    bool                no_read                         = false;
    bool                no_write                        = false;
    bool                no_crc                          = false;
    bool                no_data                         = false;
    bool                no_dir                          = false;
    bool                no_attrs                        = false;
    bool                restore_compressed_attribute    = false;
    bool                no_check                        = false;
    bool                save_sha_hashes                 = false;
    bool                shutdown_mode                   = false;
    bool                global_queueing                 = false;
```


## Services provided by the Lua code to itself

WIP:
- new variables
- new utility functions
  - search_config_file, read_binary_file, read_text_file
- new compression-related functions
- new encryption-related functions


## Services provided by the Lua code to the program

The main service now implemented in Lua is `ParseCommandLine()` - it receives from C++ code the list of command arguments and does the following:
- parses & checks cmdline, config files and environment variable FA_CFG
- executes user-supplied Lua code
- returns command name, list of filespecs to process and values of program options

At the return from this function, the program is prepared to execute the command.

Another new service is UI (implemented by UI.lua). Lua code displays all the information user see on the screen, as well as dumps its "hard copy" to the logfile.

Finally, every compression method that is going to be used for compression/extraction or displayed, is "filtered" through the Lua functions that can modify it. This is used by the following modules:
- Encryption.lua adds encryption algorithm to the compression method and generates encryption keys
- Compression.lua limits memory usage according to the -lc/-ld options. `-lc` handler also "reduces" compression method if its blocksize/dictionary is larger than the solid block size.


### The event handling machinery

FA'Next 0.11 had a limited set of built-in events. Now there is a standard way to define new events and modify existing ones. `DeclareEvent("MyEventName")` declares a new event and `DeclareEvents("EventName1 EventName2...")` just calls DeclareEvent on each name.

After declaring an event:
- `EventHandlers.MyEventName` is a list of event handlers defined for this event
- `RemoveHandler.MyEventName("label")` removes handler with the specified label from the list
- `AddHandler.MyEventName(label="",priority=NORMAL_PRIORITY,handler)` adds a new handler function to the list, with specified label and priority. Note that label should be a string and priority should be a number, both may be omitted - in this case default values are used. If possible, use symbolic constants for priorities - HIGHEST_PRIORITY (largest number, executed first), HIGH_PRIORITY, NORMAL_PRIORITY, LOW_PRIORITY, LOWEST_PRIORITY. `onMyEventName` is defined as alias of `AddHandler.MyEventName`
- `RunEvent.MyEventName(arguments...)` runs handlers in the list, sorted by priority. All arguments are passed to each event handler. Execution stops at first positive result (i.e. not nil/false) returned by event handler, and this value is returned to the caller. Note that some events, defined in the built-in Lua code, have their own `RunEvent.EventName` implementations with different event handling strategy. You can do the same.

Small example:
```Lua
DeclareEvent("MyEvent")
onMyEvent("normal", function(...)
    print("Normal priority handler:", ...)
end)
onMyEvent("highest", HIGHEST_PRIORITY, function(...)
    print("Highest priority handler:", ...)
end)
onMyEvent("high", HIGH_PRIORITY, function(...)
    print("High priority handler:  ", ...)
    return "returned from high"
end)

print ("Result: "..RunEvent.MyEvent("first run",42), "\n===============")
RemoveHandler.MyEvent("high")
print (RunEvent.MyEvent("second run"))

--[[Output:
Highest priority handler: first run 42
High priority handler:    first run 42
Result: returned from high
===============
Highest priority handler: second run
Normal priority handler:  second run
]]
```

The full list of events defined in the built-in code:
- ProgramStart, CommandStart, ArchiveStart, SubCommandStart - called from the C++ code at the program start, command start, archive start, and sub-command start (f.e. "fa a archive -t" executes subcommand "t"). Now, the first 3 events are executed at the same time, but in the future FA'Next versions, single program invocation will be able to execute multiple commands and single command will be able to process multiple archives.
- ProgramDone, CommandDone, ArchiveDone, SubCommandDone - called once corresponding processing was finished. These and preceding events doesn't carry any parameters - use global Lua variables, especially `command.*, optvalue.* and archive.*` to get info about the current state.
- CompressionStart/CompressionDone and ExtractionStart/ExtractionDone called around main stage of execution. These events correspond to start and end of displaying the compress/extract progress indicator line. See UI.lua for their parameters.
- Warning(msg) and Error(msg) - called when program encountered a recoverable and unrecoverable problem, correspondingly
- RawCmdline and Cmdline - a way to define new commands (see below)
- PreparseOption, Option and PostOption - a way to define new options (see below)
- FileFilter - filtering files to process, nothing new since FA'Next 0.11
- events "filtering" a method string prior to displaying it or compressing/extracting a solid block (see below)


### Method "filtering" events

These events are called by the C++ code in two cases: 1) prior to displaying a method string, 2) prior to compression or extraction of each solid block. They provide Lua code a way to modify a method string - remove unnecessary information prior to displaying, add encryption parameters, limit memory usage for implementation of -lc/-ld options and so on.

`RunEvent` for these events is defined in the `ProcessEventByChainingHandlers()`. This procedure always calls all event handlers defined, and replaces the first parameter (method) with the result returned by event handler unless it was negative (i.e nil/false). I.e. event handler may either return modified method or return false/nil if it doesn't want to modify the method. `RunEvent` returns the combined result of all these modifications. Remaining `RunEvent` parameters are passed unchanged to each event handler, providing necessary contextual information.

- DisplayMethod(method) - filter method string prior to displaying it to the user. It may remove unnecessary or sensitive information (such as encryption keys).
- `CompressBlockMethod/ExtractBlockMethodfunction(method,is_header,blocksize)` - process method string before compressing/extracting each solid block. `blocksize` is the solid block size. Of course, on extraction, the method transformations should keep compatibility with already compressed data.
- `CompressHeaderBlockMethod/ExtractHeaderBlockMethod(method,blocksize)` - the same as above, but called only on header blocks (i.e. parts of the archive directory)
- `CompressDataBlockMethod/ExtractDataBlockMethod(method,blocksize)` - called only on data blocks, i.e. everything else

`ProcessEventByChainingHandlers()` may chain event handlers, i.e. when processing a sub-event, additionally runs handlers for its parent event. The C++ code never calls CompressBlockMethod/ExtractBlockMethod directly, instead they are chain-called by the Header/Data events, with extra `is_header` parameter added to distinguish between call sources.


### Defining new options

`AddOption(option)` got new features:
- `option.priority` defines a parsing priority. Unlike FA'Next 0.11, it cannot be specified in the list part of the `option` table. It is recommended to define all priorities using HIGHEST_PRIORITY..LOWEST_PRIORITY constants.
- `option.post_processing` defines a function that will be called after parsing all options. Unlike FA'Next 0.11, it cannot be specified in the list part of the `option` table.
- `option.post_priority` can be used to define the post_processing priority. All `post_processing` handlers and `PostOption` event handlers are executed together in their priority order.
- `option.default_value` specifies the default option value (written to `optvalue[OPTION_NAME]` instead of nil at the start of parsing) or a function retuning the default value. String "DEFAULT_VALUE" in the help string is replaced with this value when help is displayed.
- `option.for_preparsing` specifies that option should be handled at the preparsing stage too. Alternatively, you can define `PreparseOption` handler. In the built-in code, only `-cfg/-env` options are handled at this stage, so you hardly will ever need this feature.

`AddCppOption(option)` is intended to define C++ options, i.e. options used in the C++ code. AddCppOption calls `AddOption(option)` with a few modifications:
- high-level way of option definition doesn't require the option type - it's determined from the type of corresponding C++ variable, i.e. `command[option_name]`
- if `default_value` is specified, it's assigned to the `command[option_name]`, otherwise - it's read from this variable
- after successful call to option parser, value of `optvalue[option_name]` is assigned to the `command[option_name]`

`AddOptions(list)` and `AddCppOptions(list)` just call AddOption/AddCppOption on each element of the list.

Option parsers are now called with the additional argument containing the option name: `parser(param,name)`. Option post-processing handlers are called with name too: `post_processor([option_value,]name)`. As before, the `option_value` is passed only to options defined in the high-level way. Passing option name to handlers allow to use the same handler for multiple similar options, as well as to avoid duplication of option name in multiple parts of an option definition.


### Defining new commands

I added a highly experimental way to define new commands. Actually, you can do it any other way by redefining `ParseCommandLine()`. In the way I provided you can define new commands in the following ways:
- handling `RawCmdline` event. The handler function gets an `argv` list and should return negative answer (false/nil) if command should be further processed and positive answer otherwise (in this case `ParseCommandLine()` immediately returns). It can modify the `argv` list although it can't just replace it with a different table. It's called prior to any command line processing, allowing one to define "raw" commands that doesn't use existing option definitions, or preprocess the command line prior to option handling.
- handling `Cmdline` event. The handler function should read command/options from the usual global variables and can modify them. Return code is handled in the same way. It is called after all config-file/option parsing, but before the option post-processing.

Built-in `Options.lua` employs this feature to implement a few new commands, more for teaching purposes rather than something really useful:
- `fa run script [arguments...]` executes the Lua script, passing arguments in the global table arg
- `fa run` executes script from stdin
- `fa debug` starts Lua built-in debugging REPL
- `fa debug lua-code...` executes Lua code. Note that OS cmdline parsing may get into your way!
- `fa create-locked ...` is equivalent to `fa create --lock ...`


### UI implementation

UI implementation uses the following resources:
- usual events such as `onArchiveStart` used to inform user about the command progress. Event handlers are labeled 'UI' allowing user code to remove them
- `archive.*`, `command.*` and `optvalue.*` fields provide information about archive being processed and command being executed
- uiTransientMessage(msg), uiProgress(state), uiAskOverwrite(outname), uiWarning(message...), uiError(message...), uiProfiler(label) are Lua functions called from the C++ code to handle UI-specific events. They aren't defined using the event machinery since each one hardly need more than one handler function.

`uiProgress(state)` called by C++ code every `command.ui_progress_interval` seconds (by default 0.1) during disk scan, compression and extraction operations. `state` is a table carrying all necessary information about the current operation progress. UI.lua uses this information to show short or long progress indicator while operation proceeds. The `state` is a table with the following fields:
- stage: either 'SCAN_DISK', 'COMPRESS' or 'EXTRACT'
- final: true if it's the final results of operation. Always set on the last call to `uiProgress()` on the given stage
- dirs, files, totalsize: what's found so far for SCAN_DISK, total amount of data to process for other stages
- origsize, dedupsize, compsize: bytes processed so far for COMPRESS and EXTRACT
- allocated: memory allocated for storing list of found files for SCAN_DISK, memory used for deduplication index when creating a deduplicated archive
- ram, max_ram: current and maximum so far memory used for deduplicated block storage - only when extracting deduplicated archives

On Windows, UI uses the following services provided by C++ code, to improve user experience:
- EnvSetConsoleTitle(str)/EnvResetConsoleTitle() sets/resets title of the console window
- Taskbar_SetProgressValue(Completed,Total) displays progress indicator in the taskbar (where Completed and Total are 64-bit integers)
- Taskbar_Normal(), Taskbar_Error(), Taskbar_Pause(), Taskbar_Resume(), Taskbar_Done() changes the taskbar status (i.e. color of the taskbar progress indicator)
- WriteConsole(str) writes UTF8-encoded string to the console window associated with stderr (note that `print` on Windows displays string in the current console encoding that is OEM codepage by default)

The following services are provided by C++ code on Windows, but are not yet employed by UI.lua:
- SetConsoleCursorPosition(x,y), SetConsoleTextAttribute(foreground+16*background) allows to create colorful, full-screen UI in the console window
- GetConsoleScreenBufferInfo() returns table describing the console properties and current state. F.e. on my system:
```Lua
-- print(pretty.write(GetConsoleScreenBufferInfo()))
{
  CursorPosition = {X = 0, Y = 54},
  Attributes = 7,
  MaximumWindowSize = {X = 192, Y = 203},
  Size = {X = 192, Y = 192},
  Window = {Right = 191, Bottom = 54, Top = 0, Left = 0}
}
```

These services may be used to further extend the UI with the following features:
- colorized output, f.e. print warnings in yellow and errors in red
- multi-line progress indicator, combining completeness of long progress indicator with support of 80-char wide consoles
- full-screen console UI, like one that was present in rar, arjz and ace at the DOS times. It will be useful for integration of FA'Next into console archive managers such as FAR.
