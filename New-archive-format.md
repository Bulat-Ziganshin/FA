WIP describing my current vision of new archive format that may supersede .arc in future versions of FA'Next.
- [Local descriptor](#local-descriptor)
- [Ex-directory block](#ex-directory-block)
  - [archive info](#archive-info)
  - [solid blocks info](#solid-blocks-info)
  - [file info](#file-info)
  - [custom fields](#custom-fields)


## Local descriptor

<ul></ul>Immediately follows the block it describes, saved in REVERSED byte order. Fields are:
- signature: 4-byte checksum of the next 8 bytes (CRC-32c with "ArC\2" as starting value)
- descriptor checksum (4 bytes)
- block type and two flags (1 byte):
  - inline the described block (see below)
  - no more chain-linked blocks
- bit fields (1 byte):
  - 4/8/16/32-byte block checksum
  - compression algorithm: none/zstd:1m/lzma:1m/custom
  - encryption algorithm: none/aes/custom
  - original blocksize is <128KB and not encoded here
- block checksum
- custom compression algorithm
- custom encryption algorithm
- AES 256-bit salt, 128-bit IV, 16-bit checkcode as raw bytes
- compressed size
- original size
- offset to previous local descriptor (from signature to signature)

<ul></ul>Most fields are optional:
- custom algorithms are encoded only when corresponding bit fields set to "custom"
- AES parameters - only for encryption algo == aes == aes-256/ctr (custom encryption algos encode their params inside strings, as usual)
- original size - only when data are compressed (i.e. compression algo bit field != none) AND "blocksize not encoded" flag isn't set
- offset - only when chain-linking flag is set

<ul></ul>There is also special maximum-reduced descriptor form - with the block being inlined. It was optimized for storing small control blocks up to a few hundred bytes and includes only the following fields:
- signature
- descriptor+block checksum (4 bytes)
- block type and two flags (1 byte)
- block size
- offset to previous local descriptor (from signature to signature)
- block contents (not compressed nor encrypted)

Entire descriptor size (plus block size if inlined) should be no more than 4096 bytes and no less than 12 bytes (i.e signature plus 8 bytes it verifies).

So, the minimum archive size will be 2*4 bytes (initial/ending fixed signatures) + 4 bytes (descriptor signature) + 4 bytes (descriptor+block checksum) + 2 bytes (block type and size) = 18 bytes. Plus directory block and solid block contents. At last, minimum archive size should be smaller than rar (66 bytes) and 7z (91 bytes).



## Ex-directory block

This block may contain any archive meta-information, individual fields/groups are enabled by flags. All flags are placed at the block header, but as a matter of сonvenience, we describe them in corresponding chapters.

<ul></ul>Header flags:
- none/custom set of archive description fields
- none/default/custom set of solid block and file description fields


### Archive info

<ul></ul>Header flags describing archive properties:
- archive locked?

<ul></ul>Header flags describing presence of:
- archive comment
- SFX script
- ECC settings

<ul></ul>Fields:
- archive comment: {UINT8} interpreted as UTF-8 string for displaying purposes
- SFX script: {UINT8} interpreted as UTF-8 string for displaying purposes
- ECC settings: UTF8Z


### Solid blocks info

<ul></ul>Solid blocks are described by the following fields:
- offset to start (relative to start of the control block)
- compression algorithm
- encryption algorithm
- original size
- compressed size

<ul></ul>If compression algorithm has multiple outputs, it also needs a list of output blocks, where each record contains:
- output number
- block size

When multiple solid blocks may be interleaved, their output can be described with the same list, but output number should be global among all solid blocks in this directory block. It's important to allow correct processing even when archiver know only subset of compression algorithms and therefore cannot determine by itself number of output blocks for some algorithms.


### File info

....

### Custom fields

<ul></ul>Each custom field is represented by:
- ID: UINT/UTF8Z?
- data: {UINT8}

Even if program can't recognize some field ID, it knows how to entirely skip it and go to processing of the next field. Record with ID=0/"" is reserved for "EOF" flag and doesn't include data. Further bytes (if any) can be interpreted only by future FA versions. If there is no further data, record with ID=0/"" isn't necessary, since end of control block is interpreted as end of custom fields.

To do: some way to specify fields mandatory for open/list/extract/update operations - if program can't recognize field ID, it should refuse to perfrom these operations. Plus bit flag(s) specifying whether to copy unknown records to new archive.
