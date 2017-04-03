# 1
Modern media lose data in whole blocks, which (depending on media) may be anything from 512 bytes to hundreds KBs. So, the right approach to FEC is to protect entire blocks: if any byte in block is lost - entire block is lost. I call a minimal entity protected by such a program "sector" - it's not necessarily 512 bytes, f.e. I've used 4KB sectors in my research program.

So, we split entire dataset into N data sectors, compute M ECC sectors and data can be recovered from any N survived sectors. And there is no difference whether ECC sectors goes after data sectors or they are interleaved.

Of course, with large N we need too much memory to work with all sectors simultaneously, but it may be solved by limiting N to ~64K and pseudo-random interleaving of independently protected sector sets (cohorts).


# 2
So far, storing ECC data at the end of archive is perfectly ok. It even has some advantages, allowing to quickly add recovery data to the usual archive and strip it back. In particular, existing FreeArc format just creates full archive including archive directory, then optionally adds recovery record covering everything up to this point including the archive directory. If we lose some bytes at archive end, we just lose part of recovery record, while the archive itself will be fine.

Actually, losing archive tail is the best scenario, since we if we lose up to M sectors - we even don't need to calculate recovered sectors, and when we lose more than M sectors - full recovery is impossible anyway, and we again lose minimal amount of data sectors and again don't need to calculate any recovered sectors.

Unfortunately, this great idea is not well implemented. In particular, FreeArc can't search through entire archive looking for directory records, but it's only matter of adding some code to FreeArc.

More important problem, though, is that recovery record as well as directory record, isn't self-recovering. We can lose just a single byte in the record header to lose entire record. Moreover, since all records are checked by their CRC, it's enough to lose any byte to lose an entire record (and if we disable CRC checking, we cannot say which part of record is correct and which part is just a junk)

So, the real problem isn't the regular data (source and ECC sectors), but metainformation


# 3
Existing FreeArc RR can be ruined just by 2 deliberate "shots" - changing first byte of directory record and first byte of recovery record is enough to kill the entire archive with RR of any size. What we need is to distribute directory+recovery metainfo records among entire archive and protect them with the same ECC technique.

Let's start with directory record. It contains info about one ore more solid blocks including filelist for each solid block. In order to increase recovery chances, we may split directory record into smaller independent records up to a single solid block per record.

Recovery metainfo mainly consists of checksums for each source/ECC sector. It can be split into records of any covenient size.

What we really need is to make each record self-describing, so we can extract useful information just from the record itself, and ECC-protect every record. Moreover, since metainfo is much smaller and more important than usual info, we may prefer to boost its recovery chances. F.e. if user requested adding 1% of recovery info to archive, we can protect metainfo with 10% redundancy.


# 4
Self-describing directory record only needs to know its own archive position, so it can map its solid blocks to archive sectors.

Self-describing recovery metainfo should contain FEC geometry (i.e. values of N, M and cohort size), and define range of sectors whose checksums are stored here.

It may be a good idea to combine directory and checksums for data sectors of its solid blocks into the single record.


# 5
So, now we have some data+ECC sectors. ECC sectors can be stored at archive end or in separate file(s) - examples of later are RAR recovery volumes and PAR2 format.

We also have some set of recovery metainfo records, whose size is fully controlled by placing more or less checksums into each record. Plus number of directory records, whose size is partially controlled by combining more or less solid blocks into single directory record.

Our goal is to add some ECC info to these records and then distribute all those meta+metaECC info through entire archive to maximize recovery chances.


# 6
Let's start with the simple case - ignore directory records for a moment. We can split recovery metainfo into N1 equal-sized records, compute M1 meta-ECC records of the same size, or just inflate each recovery record with meta-ECC info. In order to evenly distribute these records through the archive, we need to reserve archive sectors at regular basis, f.e. skip 1 sector after each K sectors written to the archive. We can tune number of sectors each RR describes in order to fit RR exactly into the sector size.

The reserved sectors may be used exclusively for metainfo, with ECC sectors placed at the end of archive, or both recovery records and ECC sectors may be distributed through entire archive.

The interesting point, though, is that we may prefer to store geometry/ID/checksum with every data sector and/or every ECC sector. This drops the need to ECC-protect these checksums - i.e. we usually will lose both sector and its checksum, or keep both. Essentially, it makes each sector self-described and ready-to-use without any other metadata.


# 7
For simplicity of implementation, we can protect directory records just like usual sectors. I think that even if directory will be placed at the end of archive, followed by ECC sectors, it will not lower the recovery chances (compared to interlerleaved data/ECC sectors) as far as ECC metainfo is distributed over entire archive.


# 8
Finally, let's look into protection of directory records. They contain very important info and tend to be very small. So, we can raise their redundancy ratio ~10x (as was proposed above), or alloc fixed part of total ECC space (1-10%) for directory protection, or use smart formula like dataECC/directoryECC = sqrt (datasize/dirsize). This means that for many archives directory ECC redundancy will be more than 100%, making important to distribute ECC sectors for directory records over entire archive.

Small size and high redundancy ratio means that sector size for directory records may be lowered to 128-512 bytes. We can compute optimal size for each archive based on other parameters, such as overall directory size, number of directory records and directory redundancy ratio.

Since directory records may have arbitrary size and we have only limited control of it (unlike recovery records), we can't ensure that each directory record fills whole number of sectors. Instead, we may start new sector with each new record, or pack them, or start new sector only if entire record can't be packed into the rest of last sector, or even duplicate sectors containing data from multiple directory records.

Each directory record should store info enough to map it to the "directory data sector" range. Archive will contain directory records considered as "directory data sectors" plus directory ECC sectors distributed over entire archive. I think that there is no much need to distribute directory records themself over archive: if they are large enough, they will be somewhat distributed anyway, and if they are small enough, then directory ECC redundancy will be >100% and it will be enough that directory ECC sectors are distributed.
