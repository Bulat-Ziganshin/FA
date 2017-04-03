- [Preface](#preface)
- [Archive structure](#archive-structure)
  - [No HEADER and FOOTER blocks](#no-header-and-footer-blocks)
  - [Structure of control blocks](#structure-of-control-blocks)
  - [Local descriptor](#local-descriptor)
- [Field formats](#field-formats)
  - [Storing integer values](#storing-integer-values)
  - [Storing filenames](#storing-filenames)
  - [Storing compression/encryption methods](#storing-compressionencryption-methods)
  - [Solid blocks info](#solid-blocks-info)
- [Speed requirements](#speed-requirements)

# Preface

My thoughts about possible new FreeArc archive format are ambivalent. OTOH, I know ways to improve the existing format. OTOH, this format serves good enough, so there are no real reasons to replace it except for passion to perfectness. So, my current plan is to start replacement from modes which are anyway unsupported by old FreeArc (such as deduplication), and use it for all archives only much later when most users will already upgrade to newer FreeArc versions. That follows isn't yet description of new format, but a collection of notes about its various aspects.

Goals:
- extensible - allow adding new features in FA and by 3rd-party developers
- compact - make smaller archives when standard compression/encryption algorithms are used and/or archive contains only a few files
- fast - allow encoding/decoding millions of files in a fraction of second
- reliable - accompany everything with wide checksums, allow to restore badly broken archives

Advanced features that should be covered:
- multi-volume archives
- recovery blocks and volumes
- multi-output compressors (like bcj2)
- interleaved solid blocks (a-la NanoZip)
- incremental/deduplicated archives (a-la zpaq)
- authenticated data



#Archive structure

### No HEADER and FOOTER blocks

Existing FreeArc archive format looks over-complicated. Header block, its descriptor, directory block, another descriptor, footer block and one more descriptor - six blocks is a minimum for any archive. This complicates archive creation and extraction code, and increases size of tiny archives. And to make things even worser, compression method is stored everywhere - the same string "storing" appears 5-6 times even in smallest archives! As a result, smallest FreeArc archive is 1.5-2 times bigger than 7z/rar ones.

Yet another point is that 10 years ago I expected FreeArc archives containing multiple directory blocks in order to minimize memory overhead on compression and decompression. In practice, this feature of archive format remained unrequested and memory-optimal decompression mode was implemented only by Unarc. Moreover, FA'Next reduced this memory overhead, so now one can open archive with million of files using just 50-100 MB of memory. This makes the concept of footer block, containing list of all directory blocks, pretty useless.

Taking that all into account, I want to drop header/footer blocks and use only directory blocks instead, with expectation that an archive, with very rare exceptions, will contain only one directory block. This makes the directory block more universal, capable to hold fields from both old directory block and old footer block. Header block is considered useless and replaced by a lone FreeArc signature prior to any data blocks.

Local descriptors are still required for the same purposes as before - they carry information necessary to decompress/decrypt corresponding control block, and they carry signature so they can be found even in badly broken archive.

Instead of storing all control block descriptors in the footer block, we chain-link all control blocks via their local descriptors. So, archive open operation now should start with decoding of local descriptor at the end of archive, then continue with decoding control block it describes and simultaneously decoding previous local descriptor (if any), pointed by the current one. This means that control blocks may be read only successively, so archives with many control blocks may still need to collect their descriptors in the last directory block, but implementation of such advanced feature can be postponed for a long time.

So, archive will start with FreeArc signature, then one or more solid block, then directory block and its local descriptor, and finally closing FreeArc signature. And that's all - for most of archives. The single directory block will contain all the archive metainformation.


### Structure of control blocks

Each contol block carries some set of fields - predefined by the archive format or self-decribing custom ones. Existing FreeArc format has two errors - first, all predefined fields are mandatory. This means that old fields can't be dropped in favor of new ones. For example, FreeArc includes per-file CRC-32 field and even new program version, employing better hashing algorithm, should include CRC-32 for every file.

The second error is support of self-decribing custom fields. It was included in initial archive fromat and was supported by earlier FreeArc versions. Each field started with variable-length signature and size sub-fields, allowing programs to use only fields they recognize and skip the rest. This is almost perfect extensible scheme, the problem is that there were no 3rd-party programs making their own FreeArc archives. And for archive format developed by a single organization, there is much simpler and less redundant approach - as new features are added to archive, corrresponding control block is just extended with new fields. Since decoder knows the decompressed size of control block, it can avoid attempts to read fields beyond the end of block. Finally, I dropped custom field support from decoder, replacing it with adding new fields to the end of block. But this scheme will fail for mandatory fields, i.e when archive shouldn't be updated/extracted/listed by versions not supporting this field.

Each predefined field presence/type should be indicated by a corresponding bit field. These bit fields are gathered together at the beginning of block. When new fields support is added, corresponding presence/type bit fields should be added at the free space. If there are many new fields added, we may also add some shortcut indicating that all new fields are enabled (probably it will be useful only for initial field set).


### Local descriptor

Local descriptor should start with a signature allowing to find the descriptor among raw data of broken archive. Usually, fixed 4-byte signatures are used, but my FAECC experience brings alternative approach - dynamic signature that is a function of first N bytes of the descriptor data. N should be fixed and set to the minimum possible descriptor size. This approach allows to find valid signatures by tracking rolling hash over N successive bytes through entire archive. This procedure is fast (f.e. updating rolling CRC/multiplicative hash is as fast as 1-2 CPU cycles/byte). I believe that in real files, computed signature has less chances to get too much repetitions, than the fixed one. Yet another beauty of this approach is that we can move descriptor's own checksum into the starting bytes, so checksums will recursively authenticate each other - signature verifies descriptor checksum, which verifies block checksum, which verifies all the metainformation including file checksums.

In general, local descriptor should provide information required to decode corresponding control block and find preceding local descriptor. But when control block isn't compressed/encrypted, we can omit these fields and indicate that with flags in descriptor header. Uncompressed+unencrypted control block can be "inlined" into its descriptor, so the single checksum will cover descriptor+block data. It's even possible to drop offset to preceding control block since directory block allows to compute this offset in most cases.



# Field formats

Shortcuts for describing field formats:
- UINT1..UINT64 and SINT1..SINT64 - unsigned and signed integers with fixed number of bits
- UINT and SINT - unsigned and signed integers with variable number of bytes
- UTF8Z - UTF-8 encoded string terminated with zero byte
- [Type] - optional value, whose presence determined by preceding boolean field
- Type1|Type2|... - field, whose type selected by preceding bit field
- {Type} - list of `Type` values, prefixed by count represented as UINT
- {Type1,Type2..} - list of `Type1` values, followed by list of `Type2` values..., all lists have the same length represented as UINT and placed at the start


### Storing integer values

Some integer fields like CRC and date/time are better represented with fixed-width fields. But such fields as filesizes, solid/control block sizes, list lengths, should allow large range - up to 2^32..2^64, although most values are pretty small. We may choose among the following representations for such fields:
- fixed-width, preferably the same width as elements of arrays used in the program for these data
- fixed-width, transposed, i.e. first byte of each value, then second byte of each value and so on
- variable-width with 7+1 encoding (high bit in every byte is "end of value" flag)
- variable-width discriminated by first byte (0..127 - single byte value, 128..191 - two bytes..., 255 - 9 bytes)

We can compare these approaches by the following criteria:
- decoding time (encoding time is rarely important)
- size in uncompressed form
- size in compressed form

Decoding time:
- fixed width is fastest of course, even if values should be extended/truncated during the decoding. It is as fast as load/store + possible SIMD pack or unpack operation
- transposed is a bit slower, it is load/store + byte shuffling
- variable-width discriminated by first byte require sequence of dependent memory loads, 2 loads/element i.e. 8 cycles/element. But it may run at ~2 cycles/element, if we can process multiple independent streams simultaneously
- 7+1 encoding require to run a loop for each value, so we may expect 14+ cycles/element

Uncompressed size - the same for both fixed-size forms. Also, if we want to support reduced-width variations, actual field width should be encoded. The size for both variable-size forms is also the same, and lower than for fixed-size forms.

Compressed size - looks pretty the same for all forms I tried, may be be a bit lower for transposed form (which I not tried).

As net result, currently I prefer the discriminated form (which is already used in .arc and .7z).


### Storing filenames

Filename information takes more place than any other metainformation, making its efficient representation especially important. Moreover, unfortunate format may even seriously slow down archive operations. For example, 7z format stores full pathname for every file - and in combination with optimal lzma parsing used for directory compression, it may significantly slowdown archive update operations (in one of my real-world tests, directory compression taked 10% of total compression time).

Existing FreeArc format goes one step further, storing each directory name only once, and storing the "directory number" for each file then. FA 0.11 gone one step more, storing "parent dir" for each file and marking as "virtual" entries used only to build the directory tree.

Another improvement that reduced compressed directory size by 10%, was separate field for file extension. It was implemented only once as internal FreeArc experiment and never gone to public versions.

It may be possible to store some dictionary of "spare parts" and construct each filename from one or more dictionary entries - at least on decoding phase it will be efficient, and on encoding phase it allows wide tradeoff between fast and tight encoding.


### Storing compression/encryption methods

7z format represents compression methods as variable-sized integers, plus fixed-sized fields describing method parameters, plus complex format describing connections between algorithms in single compression graph. OTOH, existing FreeArc format represents compression/encryption methods as strings, with parameters delimited by ":" and algorithms in compression chain combined by "+". Example: `rep:c512+tor:d1m:h2m`. This representation is easier to implement, but pretty inefficient.

We can improve the FreeArc format by replacing popular method strings with shorter codes, probably non-ASCII ones. F.e. we can represent "+rep:" as chr(1), "+lzma:" as chr(2) and so on, dropping any superfluous "+" and ":" after decoding. In similar fashion, we can assign chr(128)..chr(255) to popular parameter packs of each algorithm, so "rep:256:c256+lzma:max:64m" may be encoded f.e. as "\1\128\2\128\140" - four times shorter. Of course, this idea may be justified only for very small solid/control blocks, so it can be rendered useless if we will find other ways to reduce overhead costs for such cases. It also may lead to incompatibility with previous program versions not supporting new shortcuts, so we may prefer to add new aliases only when adding new compression/encryption method. Moreover, since FreeArc compression chains are more or less established now, we may just assign shortcuts to chains used by popular -m1..9 methods and never extend this set.

Multi-output methods such as BCJ2 may be represented (recursively) by compression tree for each method output described like that: `bcj2(storing,lzma:1m,lzma:1m,rep(lzma:1m,lzma:64m))`. Further going, we may choose single "main output" for every algorithm and describe its further compression in the usual way: `bcj2(storing,lzma:1m,lzma:1m)+rep(lzma:1m)+lzma:64m`. Moreover, each output may have default algo of further compression, employed when explicit specification is absent: `bcj2+rep+lzma:64m`. Since most multi-output methods has only one large output, dropping explicit compression method specification for other outputs will be insignificant. Alternative syntax is possible, f.e. `bcj2(storing|lzma:1m|lzma:1m)` or `bcj2(storing/lzma:1m/lzma:1m)`.

All encryption algorithms currently employed or planned for FreeArc are [block ciphers](https://en.wikipedia.org/wiki/Block_cipher) in [CTR/CFB mode](https://en.wikipedia.org/wiki/Block_cipher_mode_of_operation). This means that we can store all cipher params (salt+IV+checkCode) in fixed-width form, where width determined by a few parameters (key size, block size, checkCode size) instead of more universal, but less compact textual representation currently implemented by FreeArc.


### Solid blocks info

Existing FreeArc format supports only compression methods with single output, so entire solid block layout can be described with the single number - compressed size. With multi-output compressors, solid block will consist of multiple interleaved streams, so we need to store somewhere the interleaving information.

One possibility is to save outstream number and size at the start of each chunk, but it will require either to return back and overwrite old data (if we will chain-link each outstream separately), or skip other chunks searching for chunk of required outstream (if we will chain-link all outstreams together). This also means that each chunk has a few bytes overhead, so either input (in-memory) or output (on-disk) chunk size will be not a power of 2.

Another possibility is to save this information in the directory block among other solid block info. This inflates directory block with information that we need only for extraction.

Third option is to store this info in separate control blocks. The type or properties of the block would specify that it should be decoded onlyfor decompression (unlike directory block that should be decoded for listing files).

F.e., if we limit chunk size to 64 KB, then each chunk header may be about 4 bytes (outstream number plus chunk size). For archive 1 TB long, this info will be 64 MB. Not much, but definitely more than storing the next read position for a dozen of outstreams.

But that's not all. We can implement simultaneous compression of multiple solid blocks (like it already does NanoZip). In this case, chunks of multiple solid blocks will be interleaved. It can be handled in similar way as multiple outstreams for the single solid block, just outstream numbers should be global among all solid blocks interleaved.



# Speed requirements

Some operations on archive metainformation doesn't need to be fast. In particular, when new archive is created, time required just to open/close file being archived, is much higher than time required to add corresponding entry to the archive directory. OTOH, when archive is updated, it may be as fast as copying old data to the new archive file, and may be even faster - as writing new archive directory at the end of existing archive (in particular for ZPAQ-style incremental archives). So, we need to care only about speed of some operations, although I don't yet defined full set of such operations.

Most important is the speed of "archive open", in particular the following operations - list/extract single file or small group of files from (huge) archive, or show archive root directory in some GUI (it may be even non-root directory if GUI supports favorite directories inside archives!). Ideally, it should have "instant" execution i.e. in 0.2-0.3 seconds even for huge archives (just imagine backup of my whole HDD containing 3 millions of files). OTOH, archive directory with 3 million files is about 150 MB long. ZSTD algorithm can decompress it in about 10^9 CPU cycles. So, decoding one directory entry in 100 cycles is enough to make this time negligible compared even to fastest decompression.

Now let's analyze time required to decode one file entry. It includes:
- several fixed-size fields, such as CRC/date. Each require ~1 CPU cycle/value, so these times are negligible.
- several variable-size fields: filesize, parent dir number. Depending on encoding approach, they may need from 1 to ~16 cycles/value.
- one or two string fields - basename and may be extension. Each string field will probably require 1-2 cycles/byte plus 14 cycles/value - and even less if SIMD and/or CMOV instructions are employed.

Overall, it seems that we can fit in 100 cycles/file pretty easily.
