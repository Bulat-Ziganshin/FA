Archive consists of blocks. These includes so-called SOLID BLOCKS, containing contents of files stored in the archive, and all remaining block type, collectively called CONTROL BLOCKS, holding meta-information about archive and files it contain.

Currently, there are the following types of control blocks:
- HEADER block is the first block of any archive. It starts with FreeArc arhive signature, plus contains info about archiver version.
- DIRECTORY blocks describes solid blocks stored in the archive, and files whose contents stored in these solid blocks
- FOOTER block is the last block of the archive. It describes DIRECTORY blocks stored in the archive plus contains common archive information such as archive comment.
- RECOVERY block, if present, is placed after all archive blocks including the FOOTER block. It contains ECC data that may help to restore damaged archive.

Each directory block is placed right after the solid blocks it describes. Archive may contain multiple directory blocks and multiple solid blocks per directory block.

Numbers in control block are stored in variable 1-9 byte format, except for CRC/time/signature having a fixed width of 4 bytes. Block type and boolean flags are stored as 1 byte. Strings (filenames, compression/encryption algorithms) are stored with trailing NUL byte. Lists are preceded with number of their elements and stored in the struct-of-arrays order (as opposite to array-of-structs). CRC algorithm used is pkzip's CRC-32.

### Local descriptor

Each control block is immediately followed by it's LOCAL DESCRIPTOR, that includes the following info:
- signature
- block type (i.e. HEADER...RECOVERY)
- compression/encryption algorithm
- original and compressed size
- CRC of original data
- CRC of descriptor itself

This allows to find each descriptor in archive by the signature, then decode it, verify by CRC and finaly decode and verify the contol block itself. This means that even seriously broken archive can be restored by scanning the raw data and recovering each control block that wasn't damaged, but this feature isn't implemented yet by FreeArc. Earlier FreeArc versions contained local descriptor after each solid block too, but later this feature was dropped.


### Directory block

Each directory block describes solid blocks it immediately follows. It consists of three parts. The first part is list of solid blocks, each described with the following information:
- number of files in the solid block
- compression/encryption algorithm
- initial block offset in archive, relative to start of the directory block
- compressed size

The second part is list of directory names.

The third part is list of files, each described with the following information:
- base name
- directory number (from the preceding list)
- size
- time
- "is directory?" flag
- CRC

Files are stored in the solid block order, so, knowing number of files in each solid block, it's easy to map each file to its solid block and position inside this block.


### Footer block

The footer block describes all preceding control blocks of the archive, i.e. all control blocks except for optional recovery block, plus a general archive information. So, it begins with list, describing each preceding control block with the following info:
- block type (i.e. HEADER...RECOVERY)
- compression/encryption algorithm
- position in archive, relative to start of the footer block
- original and compressed size
- CRC of original data

As you can see, it's very like the local descriptor info, only dropping unnecessary signature/own-CRC fields and adding necessary position field.

Then block contains:
- "archive is locked?" flag
- recovery record settings string
- archive commentary as array of arbitrary bytes (interpreted as UTF-8 for displaying)

Since all control blocks are described in the footer, there is no need to find them using local descriptors (except for archive recovery purposes). The only block that should be found by its local descriptor is the footer block itself. So, archive open starts with searching for local descriptor in the last 4096 bytes of archive, then the descriptor found used to decode footer block and information about all remaining blocks is extracted from the footer block.


### Recovery block

Deliberately isn't described here since its format as well as ECC algorithm (plain XOR) is a long time outdated. But it still has one exiting feature - when recovery block is added to archive, it's written after the usual footer block so the footer block can be recovered too. But after the recovery block, another footer block is written again, this time also including descriptor of the recovery block. So, archives with recovery info contain two copies of footer blocks. By default, last footer block is used, but if it's damaged, then recovery block may be used to recover the first copy.
