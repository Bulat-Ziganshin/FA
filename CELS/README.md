* [Architecture](#architecture)
* [Application usage](#application-usage)
  * [Minimal example: streaming compression](#minimal-example-streaming-compression)
  * [Passing userdata to the callback](#passing-userdata-to-the-callback)
  * [Memory buffer compression](#memory-buffer-compression)
  * [Mixed-mode compression](#mixed-mode-compression)
  * [Formatting a method string](#formatting-a-method-string)
  * [Generic method parameters](#generic-method-parameters)
    * [Querying method parameters](#querying-method-parameters)
    * [Modification of method parameters](#modification-of-method-parameters)
    * [Full list of supported parameters](#full-list-of-supported-parameters)
  * [Low-level access to parsed method](#low-level-access-to-parsed-method)
  * [Caching](#caching)
  * [Loading and registering codecs](#loading-and-registering-codecs)
  * [Providing smooth progress indicator](#providing-smooth-progress-indicator)
  * [Buffer-sharing API](#buffer-sharing-api)
* [Codec development](#codec-development)
  * [Minimal example: streaming compression](#minimal-example-streaming-compression2)
  * [Registering codec](#registering-codec)
  * [Memory buffer compression and mixed-mode compression](#memory-buffer-compression-and-mixed-mode-compression)
  * [Providing smooth progress indicator](#providing-smooth-progress-indicator2)
  * [Getting method parameters](#getting-method-parameters)
  * [Parsing a method string](#parsing-a-method-string)
  * [Unparsing a method structure](#unparsing-a-method-structure)
  * [Default implementation of (un)parsing services](#default-implementation-of-unparsing-services)
  * [Using the parsed method structure](#using-the-parsed-method-structure)
  * [Setting method parameters](#setting-method-parameters)
  * [Meaning of method parameters](#meaning-of-method-parameters)
  * [Caching](#caching2)
  * [Registering codecs: the full API](#registering-codecs-the-full-api)
    * [Module-level services](#module-level-services)
    * [Codec-level services](#codec-level-services)
    * [Instance-level services](#instance-level-services)
  * [The Cels() algorithm](#the-cels-algorithm)
  * [Rules for choosing codes for new services](#rules-for-choosing-codes-for-new-services)
  * [Buffer-sharing API](#buffer-sharing-api)


## Architecture

CELS stands for Compression/Encryption Library Standard and is an enhanced version of CLS.

CELS is the API and framework that binds together applications using compression/encryption and codecs implementing such algorithms. The central idea of the API is use of single function Cels() to provide all framework services to an application and single function CelsMain() to provide all services defined by a codec. These functions are quite similar:

```C
CelsResult Cels (const void* method, int service, void* inbuf, CelsNum insize, void* outbuf, CelsNum outsize, void* ud, CelsCallback* cb);
CelsResult CelsMain (void* self, int service, void* inbuf, CelsNum insize, void* outbuf, CelsNum outsize, void* ud, CelsCallback* cb);

typedef CelsResult CelsCallback (void* self, int service, void* inbuf, CelsNum insize, void* outbuf, CelsNum outsize, void* ud, CelsCallback* cb);
typedef long long CelsResult, CelsNum;
```

The service parameter represents concrete service requested by an application from the framework, or by the framework from a codec. The method parameter represents method string or binary method object created by preceding call to Cells(). Remaining parameters are passed intact from application to codec and their interpretation defined by concrete service, but there is an agreement that the cb parameter defines callback that codec may use to request services back from an application, while the ud (userdata) parameter is passed as first argument (self) to this callback. The last callback parameters again are the ud/cb pair, so the chain of nested callbacks may become arbitrarily deep.

The combination of two pointers (inbuf/outbuf), two long integers (insize/outsize) and the callback should provide enough parameters to 99% of services we may imagine. A few remaining ones may pass extra parameters either via structures pointed by inbuf/outbuf, or by the callback processing requests with various service numbers. This makes a single function the entire API, universal enough to cover all our needs.

The use of single-function API, while having well-known drawbacks, provides some advantages:

- Portability: in order to provide CELS binding for other language, it's enough to bind CelsLoad() and Cels() and translate `CELS_*` constant definitions from CELS.h to this language with a simple awk/sed script. This immediately makes all CELS services available to applications. CELS itself is written in the common subset of ANSI C99 and C++98, making it compatible with virtually every C/C++ compiler.

- Extensibility: despite the name, CELS doesn't provide any compression/encryption services. All it does - registers codecs and then dispatches Cels() calls to appropriate CelsMain() instances.


To some degree, `CELS.h` defines the CELS API, while `CELS.cpp` provides the framework implementation. Thus, application using the CELS framework should be linked with CELS.cpp, while codec doesn't need that, since it doesn't use the framework - on opposite, the framework uses services that codec provided.



## Application usage

### Minimal example: streaming compression

Minimal complete example (provided in simple_host.cpp):

```C
#include <stdio.h>  // for fread/fwrite/printf
#include "CELS.h"

CelsResult __cdecl ReadWrite (void* self, int service, void* inbuf, CelsNum insize, void* outbuf, CelsNum outsize, void* ud, CelsCallback0* cb)
{
    switch(service)
    {
        case CELS_READ:   return fread ( inbuf, 1,  insize, stdin);
        case CELS_WRITE:  return fwrite(outbuf, 1, outsize, stdout);
        default:          return CELS_ERROR_NOT_IMPLEMENTED;
    }
}

int main (int argc, char **argv)
{
    CelsLoad();
    CelsResult result = CelsCompress("test", NULL, ReadWrite);
    if (result < CELS_OK)  {printf("%s\n", CelsErrorMessage(result)); return 1;}
    return 0;
}
```
Function CelsLoad() loads codecs from cels*.dll files. Other ways to register codecs are described in the section WIP.

Next, CelsCompress() is called to perform compression using codec "test" with data exchange implemented by the callback ReadWrite(). Decompression can be performed by CelsDecompress() in the similar way.

CELS functions usually return CelsResult, which is defined to 64-bit signed integer. Return values of CELS_OK (defined to 0) and higher are considered as OK result, while negative values are error codes (defined as CELS_ERROR_* constants in CELS.h). In most cases, you should check return value and raise an error on negative code. One important exception, though, is CELS_ERROR_NOT_IMPLEMENTED code - you can ignore this code if you can live without the requested facility or try other way (usually legacy or less efficient) to get required functionality from a codec.

Function CelsErrorMessage() returns English description of error code.

Finally, CelsCompress()/CelsDecompress() call the callback each time they need to read or write data:
- for reading: `service`=CELS_READ, buffer to fill with data in the `inbuf`, and buffer size in the `insize`
- for writing: `service`=CELS_WRITE, buffer with data in the `outbuf`, and datasize in the `outsize`

Note that the callback should always fill entire input buffer and write entire output buffer. The only exception is end of input data when it's allowed to fill input buffer only partially. Read/write callbacks should return number of bytes read/written, which is usually positive, but may be zero at the end of input data. Negative result means error and should be encoded using CELS_ERROR_* constant. Finally, callback should return CELS_ERROR_NOT_IMPLEMENTED for all unsupported service codes.

Also note that some codecs may run multiple threads and run the callback you passed from multiple threads simultaneously. It's guaranteed that reads will be serialized (i.e. next read starts after return from previous one, with full memory barrier between two threads involved) as well as writes. But reads+writes as well as other callbacks may be performed simultaneously, so you may need to protect your data from simultaneous access.


### Passing userdata to the callback

All CELS functions accepting callbacks also accept userdata parameter (usually shortened to `ud` in my code), which value is then passed to the callback as first argument. This allows to pass local data from caller to callback. The following example passes local FILES structure from `main` to the callback:

```C
#include <stdio.h>  // for fread/fwrite/printf
#include "CELS.h"

struct {FILE* infile, *outfile;} FILES;

CelsResult __cdecl ReadWrite (void* self, int service, void* inbuf, CelsNum insize, void* outbuf, CelsNum outsize, void* ud, CelsCallback0* cb)
{
    FILES *files = (FILES*) self;
    switch(service)
    {
        case CELS_READ:   return fread ( inbuf, 1,  insize, files->infile);
        case CELS_WRITE:  return fwrite(outbuf, 1, outsize, files->outfile);
        default:          return CELS_ERROR_NOT_IMPLEMENTED;
    }
}

int main (int argc, char **argv)
{
    if (argc!=3)  {printf ("Usage: compress infile outfile\n"); return 1;}
    CelsLoad();

    FILES files;
    FILES.infile  = fopen(argv[1], "r");
    FILES.outfile = fopen(argv[2], "w");

    CelsResult result = CelsCompress("test", &files, ReadWrite);
    if (result < CELS_OK)  {printf("%s\n", CelsErrorMessage(result)); return 1;}
    return 0;
}
```

### Memory buffer compression

If data should be compressed/decompressed from one memory buffer to another, use CelsCompressMem() and CelsDecompressMem() functions:

```C
#include <stdio.h>  // for printf
#include "CELS.h"

int main (int argc, char **argv)
{
    CelsLoad();

    char original[] = "text to compress", compressed[1000], decompressed[1000];

    CelsResult compressed_size = CelsCompressMem("test", original, sizeof(original), compressed, sizeof(compressed), 0, 0);
    if (compressed_size < CELS_OK)  {printf("Compression error: %s\n", CelsErrorMessage(compressed_size)); return 1;}

    CelsResult decompressed_size = CelsDecompressMem("test", compressed, compressed_size, decompressed, sizeof(decompressed), 0, 0);
    if (decompressed_size < CELS_OK)  {printf("Decompression error: %s\n", CelsErrorMessage(decompressed_size)); return 1;}

    if (decompressed_size != sizeof(original)  ||  memcmp(decompressed, original, sizeof(original))) {
        printf("Codec failed: data mismatch!!!\n");
        return 1;
    }
    return 0;
}
```

In this simplified example, we just allocated 1000 bytes for each output buffer, without strict guarantees that operation will not fail due to too small buffer. Production-quality code can use the following methods to ensure correct operation:

1. Check return code for CELS_ERROR_OUTBLOCK_TOO_SMALL and increase output buffer size, repeating the operation again until it succeeds (or returns other error code).

2. For decompression operation, original data size may be stored among the compressed data.

3. For compression operation, use reasonable assumption of maximum output size, f.e. 1.25*InputSize+20000

4. For compression operation, the service `CelsGetMaxCompressedSize(method,InputSize)` may compute maximum possible output size. Note, however, that a codec may not support this service at all. Moreover, some codecs (f.e. precomp) can unboundly inflate data - these services will return maximum CelsResult value which is 2^63-1. The value returned by `CelsGetMaxCompressedSize` covers all possible compression operations - from buffer to buffer, from stream to stream and so on.

The following example shows methods 1, 3 and 4:

```C
#include <stdio.h>  // for printf
#include "CELS.h"

int main (int argc, char **argv)
{
    CelsLoad();

    char inbuf[] = "text to compress", *outbuf = 0;
    const int insize = sizeof(inbuf);

    CelsResult outsize = CelsGetMaxCompressedSize("test",insize);
    if (outsize == CELS_ERROR_NOT_IMPLEMENTED)  outsize = insize+(insize/4)+20000;
    if (outsize < CELS_OK)  {printf("GetMaxCompressedSize error: %s\n", CelsErrorMessage(outsize)); return 1;}

    CelsResult compressed_size;
    do {
        outbuf = realloc(outbuf, outsize);
        if (! outbuf)  {printf("Cannot allocate %.0lf bytes\n", double(outsize)); return 1;}
        compressed_size = CelsCompressMem("test", inbuf, insize, outbuf, outsize, 0, 0);
        outsize *= 2;
    } while (compressed_size==CELS_ERROR_OUTBLOCK_TOO_SMALL);

    if (compressed_size < CELS_OK)  {printf("Compression error: %s\n", CelsErrorMessage(compressed_size)); return 1;}
    return 0;
}
```

### Mixed-mode compression

CelsCompressMem() and CelsDecompressMem() functions also accept the userdata/callback pair as their last arguments. This serves two needs - first, codec may use the callback to pass CELS_PROGRESS information, which is especially useful when compressing large buffers (see example in section WIP). Also, codec may invoke other, non-standard callbacks that application may support.

Moreover, CelsCompressMem()/CelsDecompressMem() may be called with inbuf==NULL and/or outbuf==NULL in which case codec should perform corresponding input/output via the callback. Note that CelsCompress()/CelsDecompress() are equivalent to CelsCompressMem()/CelsDecompressMem() with both buffers set to NULL, while later are flexible functions that support any combination of buffer/callback on input and output.

The following example compresses data from memory buffer to stdout:

```C
#include <stdio.h>  // for printf
#include "CELS.h"

CelsResult __cdecl OnlyWrite (void* self, int service, void* inbuf, CelsNum insize, void* outbuf, CelsNum outsize, void* ud, CelsCallback0* cb)
{
    switch(service)
    {
        case CELS_WRITE:  return fwrite(outbuf, 1, outsize, stdout);
        default:          return CELS_ERROR_NOT_IMPLEMENTED;
    }
}

int main (int argc, char **argv)
{
    CelsLoad();

    char original[] = "text to compress";

    CelsResult compressed_size = CelsCompressMem("test", original, sizeof(original), 0,0, NULL, OnlyWrite);
    if (compressed_size < CELS_OK)  {printf("Compression error: %s\n", CelsErrorMessage(compressed_size)); return 1;}
    return 0;
}
```

### Formatting a method string

The following functions returns modified method string:
- CelsCanonize() returns canonical method representation, usually with fixed argument order, fixed name for aliased parameters (such as "m" and "mem" in my ppmd), canonical representation of integers and memory sizes, "macro" parameters replaced with their substitution and so on. Overall, if canonical representations of two methods are the same, then methods are equal, and if canonical representations are different - methods have some semantic differences
- CelsDisplay() returns method string prepared for display, with sensitive information like encryption keys removed
- CelsPurify() returns method string prepared for storing in archive, with sensitive information and compression-specific parameters removed

Modified method string is saved to buffer provided as the second parameter. The buffer should be CELS_MAX_METHOD_STRING_SIZE bytes long. You can use the same buffer for input and output method strings, it will remain unchanged if error code is returned.

```C
#include <stdio.h>  // for printf
#include "CELS.h"

int main (int argc, char **argv)
{
    CelsLoad();

    // Buffer for modified compression method string
    char method[CELS_MAX_METHOD_STRING_SIZE];

    // Canonize the method string
    CelsResult errcode = CelsCanonize("test", method);
    if (errcode < CELS_OK) {
        printf("Canonizing method failed: %s\n", CelsErrorMessage(mem));
    } else {
        printf("Canonical method representation: %s\n", method);
    }

    // Prepare the method string for displaying
    errcode = CelsDisplay("test", method);

    // Prepare the method string for storing in an archive
    errcode = CelsPurify("test", method);

    return 0;
}
```

### Generic method parameters

The hallmark feature of CELS API is support of method parameters generic for all compression methods. This includes parameters like compression/decompression memory, CPU load, dictionary size and so on. This allows application to manipulate compression method in a generic way, querying and modifying its resource usage, or tailoring method to specific usecase, without the need to deal specifically with options of each codec, and even without knowing beforehand which codecs will be used with the application.

#### Querying method parameters

The `CelsGetXXX(method)` functions return the value of parameter `XXX` for the `method`. Be prepared that these requests may return CELS_ERROR_NOT_IMPLEMENTED.

```C
#include <stdio.h>  // for printf
#include "CELS.h"

int main (int argc, char **argv)
{
    CelsLoad();

    CelsResult mem = CelsGetCompressionMem("test");
    if (mem < CELS_OK) {
        printf("Compression memory request failed: %s\n", CelsErrorMessage(mem));
    } else {
        printf("Compression memory: %lld bytes\n", mem);
    }

    // Other calls should be checked for errors in the same way...
    mem       = CelsGetDecompressionMem("test");
    mem       = CelsGetMinCompressionMem("test");
    mem       = CelsGetMinDecompressionMem("test");
    size      = CelsGetMinimalInputSize("test");
    dict      = CelsGetDictionary("test");
    blocksize = CelsGetBlocksize("test");
    cpu_load  = CelsGetCompressionCpuLoad("test");
    cpu_load  = CelsGetDecompressionCpuLoad("test");

    return 0;
}
```

#### Modification of method parameters

You can also modify compression methods with `CelsSet*` operations to change these parameters, f.e. reduce memory usage on low-end computers or select number of compression threads. Codec may set the requested parameter to a lower value than requested, but not to a higher one. Modified compression method is stored as string in the output buffer provided as the last function parameter. The buffer should be CELS_MAX_METHOD_STRING_SIZE bytes long, can be the same as input buffer, and will remain unchanged if error code is returned. Then you can use new method string to perform compression/decompression operations.

There are also `CelsLimit*` operations that limit the corresponding parameter, i.e. it can be decreased but not increased. When a parameter wasn't changed, they return a canonical representation of the input method.

```C
#include <stdio.h>  // for printf
#include "CELS.h"

int main (int argc, char **argv)
{
    CelsLoad();

    // Buffer for modified compression method string
    char method[CELS_MAX_METHOD_STRING_SIZE];

    // Change memory required for compression
    CelsResult errcode = CelsSetCompressionMem("test", 1<<20, method);

    // If operation failed, copy the original method string
    if (errcode < CELS_OK)  strcpy (method, "test");

    // Change number of compression threads
    errcode = CelsSetCompressionCpuLoad(method, 4*100, method);
    // If operation failed, method[] retains its old contents

    // Other operations:
    errcode = CelsSetBlocksize          (method, 1<<20, method);
    errcode = CelsSetDictionary         (method, 1<<20, method);
    errcode = CelsSetDecompressionMem   (method, 1<<20, method);
    errcode = CelsSetMinCompressionMem  (method, 1<<20, method);
    errcode = CelsSetMinDecompressionMem(method, 1<<20, method);
    errcode = CelsSetMinimalInputSize   (method, 1<<20, method);
    errcode = CelsSetDecompressionCpuLoad(method, 4*100, method);

    // Each "set parameter" operation has the "limit parameter" pair:
    errcode = CelsLimitCompressionMem(method, 1<<20, method);
    errcode = CelsLimitDecompressionMem(method, 1<<20, method);
    // ... and so on

    // Now use modified method for compression:
    char original[] = "text to compress", compressed[1000];
    CelsResult compressed_size = CelsCompressMem(method, original, sizeof(original), compressed, sizeof(compressed), 0, 0);

    return 0;
}
```

Note that if you have used the modified method string in compression operation, you should perform decompression with the same method string - there are no guarantees of compatibility between original and modified method. Operations that you can perform on method used for compression, prior to using it for decompression, are limited to CelsSetCelsSetDecompressionCpuLoad() and CelsSetDecompressionMem().


#### Full list of supported parameters

The list of supported parameters continues to grow, driven by the needs of the FreeArc compression suite. ATM, the API defines the following parameters:

- CompressionMem: amount of memory (in bytes) used for streaming compression by the `method`
- DecompressionMem: memory used for streaming decompression
- MinCompressionMem: minimum memory that may be used for streaming compression, based on the string provided by `CelsPurify` (which may omit some compression parameters, not important for performing the decompression)
- MinDecompressionMem: minimum memory that may be required for streaming decompression of data compressed by the `method`
- MinimalInputSize: minimal input size the `method` is optimized for, so for smaller input sizes method can be reduced without losing the compression ratio
- Dictionary: dictionary size (for LZ and similar compressors)
- Blocksize: block size (for compressors that split data into independent blocks, like BWT does)
- CompressionCpuLoad: percents of CPU load during compression, where value of 100 = 1 hardware thread
- DecompressionCpuLoad: percents of CPU load during decompression

FreeArc employs operations, that query and modify generic method parameters, at three stages: compression, archive information, and decompression.

At compression, `CelsLimitCompressionMem` used to fit algorithm into memory available. Similarly, `CelsLimitMinDecompressionMem` called to ensure that compression method will produce data that can be decompressed on computers with given memory. For example, it may reduce "lzma:1g" to "lzma:800m" to ensure that decompression is possible when 800 MB of RAM available.

Usually we can predict input size (f.e. as sum of file sizes in the solid block), so we use `CelsLimitMinimalInputSize` to reduce algorithm, optimizing it for smaller input size. F.e., if we have 5 MB of input data, the "lzma:1g" will be reduced to "lzma:5m". OTOH, if algorithm is block-wise, i.e. splits input data into independently compressed blocks of fixed size, which is indicated by non-zero value of `CelsGetBlocksize`, FreeArc will split files into solid blocks of this size in order to speed up decompression of individual files.

`CelsSetCompressionCpuLoad` employed to modify method to use all cores available, f.e. on CPU with 4 cores/8 threads the optimal value is 800. And finally, user can directly set up dictionary size of algorithm by using option `-md`.

Once all these modifications were applied, the modified compression method is used for compression, while its `CelsDisplay()` version is displayed, among with CelsGetCompressionMem(), CelsGetDecompressionMem() and CelsGetMinDecompressionMem() results. The last two shows, correspondingly, memory required for fastest decompression on the current computer (in particular, running as much threads as hardware supports) and minimum memory that may be used for stripped-down decompression (in particular, running only one thread if this reduces memory usage).

Decompression method string, returned by the `CelsPurify()`, is saved to an archive. Archive information command uses this string to display minimum memory that may be used to produce these compressed data (returned by `CelsGetMinCompressionMem`), and minimum/optimal memory required for these data decompression (again, CelsGetDecompressionMem() and CelsGetMinDecompressionMem()).

On decompression stage, we can use only modifications that don't break compatibility with compressed data. Currently, they are limited to the two operations: `CelsSetDecompressionMem` modifies memory required for decompression (usually by reducing number of threads or switching to alternative slower algorithm), and `CelsSetDecompressionCpuLoad` directly changes number of decompression threads. Once modifications are done, we can use modified method string to start decompression and call `CelsGetDecompressionMem`/`CelsGetDecompressionCpuLoad` to query resulting method parameters.


### Low-level access to parsed method

All previous examples represented compression methods as strings. Internally, CELS parses such string into binary structure, performs the requested operation and unparses binary structure to the output string when required (i.e. for unparsing services and for services setting method parameters). Performing parsing and possibly unparsing for each operation may unnecessarily slowdown an application, so there is a way to perform parsing only once, execute all required operations directly on the parsed method and finally perform unparsing if necessary:

```C
#include <stdio.h>  // for printf
#include "CELS.h"

char original[] = "text to compress";
char compressed[1000];

int main (int argc, char **argv)
{
    CelsLoad();

    char method[CELS_MAX_PARSED_METHOD_SIZE];
    CelsResult result = CelsParse("test", method);
    if (result < CELS_OK)  {printf("Parsing failed: %s\n", CelsErrorMessage(result)); return 1;}

    // On success, CelsParse() returns size of binary record stored in the method.
    // If you need to move these data elsewhere, it's enough to alloc and copy only that many bytes:
    void *saved_method = malloc(result);
    memcpy(saved_method, method, result);
    // But note that parsed method may contain pointers to memory it allocated, so after copying
    // we should drop one of these instances without calling CelsFree():
    free(saved_method);

    // The parsed method may be used with any services like the string one:
    CelsResult csize_or_errcode = CelsCompressMem(method, original, sizeof(original), compressed, sizeof(compressed), 0,0);
    CelsResult cmem_or_errcode = CelsGetCompressionMem(method);

    // The only difference is that "set parameter" services modify the parsed structure directly,
    // so they don't store modified method string to the buffer you provided:
    errcode = CelsSetCompressionMem(method, 256<<20, 0);

    // In order to retrieve new string with modified method, you need to perform unparsing explicitly:
    char method_str[CELS_MAX_METHOD_STRING_SIZE];
    errcode = CelsCanonize(method, method_str);

    // In the same way, you may retrieve method string for storing for decompression:
    errcode = CelsPurify(method, method_str);

    // Once you have finished using the parsed method, you should request codec
    // to free any memory it may allocated:
    errcode = CelsFree(method);

    return 0;
}
```

Since services may modify the parsed method, avoid simultaneous use of the same parsed structure in multiple threads. Instead, parse the same string again into the new structure. Don't make copies of the parsed structure, since it may include pointers to allocated memory. Instead, convert the parsed method back to string with CelsCanonize() and parse the string into another buffer.


### Caching

Some codecs are so fast that allocation/freeing memory on each operation can slowdown them. Also, when a lot of encoding operations are performed, multiple memory reallocations may fragment memory up to the point when application should be stopped. In order to deal with such cases, CELS provide a simple API that allows application to ask codec to keep memory between operations. In order to use this API, you should work with parsed method, since codec stores pointers to allocated memory inside the parsed structure:

```C
#include <stdio.h>  // for printf
#include "CELS.h"

char original[] = "text to compress";
char compressed[1000];

int main (int argc, char **argv)
{
    CelsLoad();

    char method[CELS_MAX_PARSED_METHOD_SIZE];
    CelsResult size_or_errcode = CelsParse("test", method);

    // Tell codec to keep allocated memory between (de)compression operations:
    CelsResult errcode = CelsSetCaching(method, 1);

    // Ask codec whether caching is enabled:
    CelsResult caching_or_errcode = CelsGetCaching(method);

    // Perform multiple (de)compression operations:
    for (int i=0; i<10; i++) {
        CelsResult csize_or_errcode = CelsCompressMem(method, original, sizeof(original), compressed, sizeof(compressed), 0,0);
    }

    // Disable caching and free any memory it allocated:
    errcode = CelsSetCaching(method, 0);

    // CelsFree() also frees any memory allocated by caching:
    errcode = CelsFree(method);

    return 0;
}
```

Caching is enabled/disabled for each parsed instance separately, so if you need to work with cached and non-cached operations simultaneously, use separate parsed instances (or just pass method strings to operations that shouldn't be cached).

A codec may not support caching, so you may need to ignore CELS_ERROR_NOT_IMPLEMENTED result from CelsSetCaching(), and convert it to 0 (meaning "caching is disabled") for CelsGetCaching().


### Loading and registering codecs

The framework provides a few global services:
- CelsRegister() registers a codec
- CelsLoad() loads codecs from cels*.dll
- CelsUnload() deregisters all codecs and frees all DLLs

These services are also available through the Cels() call:
- Cels(0, CELS_REGISTER, method,0, 0,0, ud,cb) is equivalent to CelsRegister(method,ud,cb)
- Cels(0, CELS_LOAD, 0,0, 0,0, 0,0) is equivalent to CelsLoad()
- Cels(0, CELS_UNLOAD, 0,0, 0,0, 0,0) is equivalent to CelsUnload()

This serves two purposes - first, it may simplify binding CELS to other languages - you don't need to bind any function but Cels(). Second, it allows codecs loaded from DLLs to use full spectrum of CELS features available to application itself. More on that topic in the section WIP.

to do: CelsLoad() dll names & error checking, CelsUnload()


### Providing smooth progress indicator

Simple codecs compresses and writes all the data they have read, prior to reading next portion of data. In order to display correct progress indicator (i.e. speed and compression ratio) for such codecs it's enough to wait for CELS_READ callback and update the progress indicator with current stats PRIOR TO performing the read operation.

More complex codecs may postpone writing already compressed data, in which case they are facilitated to use CELS_PROGRESS callback to inform the application how much bytes they are already processed and how much bytes they are produced from this input. On each invocation, number of input bytes, processed since the last call, is passed as insize, and number of output bytes, produced since the last call, as outsize. It's recommended that application displays progress indicator based on data from this callback since the first time it was invoked during the current (de)compression operation. It's expected that operations supporting this callback, invoke it with zero parameters before any read/write calls.

The following example demonstrates technique of switching progress indicator from displaying progress of CELS_READ/CELS_WRITE calls to information provided by CELS_PROGRESS once it invoked first time. Note that any of these calls may occur pretty often, so it's highly recommended to limit display update to once per second or so. Also note that production-quality applications should correctly handle situations when different OS threads, created by the codec, simultaneously call the callback. Unlike CELS_READ/CELS_WRITE callbacks, CELS_PROGRESS is allowed to be called by multiple threads simultaneously.

```C
#include <stdio.h>  // for fread/fwrite/printf
#include "CELS.h"

// Total bytes read and written
double total_in=0, total_out=0;

// Enabled after first invocation of CELS_PROGRESS callback
bool progress_callback = false;

void update_indicator()
{
    static double last_time = 0;
    double cur_time = GetTime();   // OS-specific function that should return nuber of seconds since the application started
    if (cur_time - last_time < 0.1)  return;  // avoid updating progress indicator more than 10 times per second
    last_time = cur_time;

    double speed = (total_in/cur_time)/1048576;
    fprintf(stderr, "\rCompressed %.0lf bytes to %.0lf bytes, speed is %.3lf MiB/sec", total_in, total_out, speed);
}

CelsResult __cdecl ReadWrite (void* self, int service, void* inbuf, CelsNum insize, void* outbuf, CelsNum outsize, void* ud, CelsCallback0* cb)
{
    switch(service)
    {
        case CELS_READ:
        {
            // Update progress indicator,
            // using information derived from read/write calls,
            // prior to performing the read request
            if (!progress_callback)  update_indicator();

            size_t in = fread(inbuf, 1, insize, stdin);

            // Update totals with information from the read operation
            if (!progress_callback)  total_in += in;

            return in;
        }
        case CELS_WRITE:
        {
            fwrite(outbuf, 1, outsize, stdout);

            // Update totals with information from the write operation
            if (!progress_callback)  total_out += outsize;

            return insize;
        }
        case CELS_PROGRESS:
        {
            if (!progress_callback) {
                // The first call to the progress callback
                total_in = total_out = 0;
                progress_callback = true;
            }

            // Update totals with information provided by the callback
            total_in  += insize;
            total_out += outsize;

            // Update progress indicator,
            // using only information provided by the progress callback
            update_indicator();

            return CELS_OK;
        }
        default:  return CELS_ERROR_NOT_IMPLEMENTED;
    }
}

int main (int argc, char **argv)
{
    CelsLoad();
    CelsResult result = CelsCompress("test", NULL, ReadWrite);
    if (result < CELS_OK)  {printf("%s\n", CelsErrorMessage(result)); return 1;}
    return 0;
}
```

### Buffer-sharing API

Codecs may implement compress/decompress operations using the new "buffer-sharing" API. Later, the framework will implement shell functions allowing to coexist applications and codecs using different APIs (i.e. traditional read/write and new buffer-borrowing). But now you need to implement this API yourself in order to work with such codecs. Moreover, application callbacks can implement both APIs, ensuring compatibility with both old and new codecs (as well as codec can switch to old API if callback returns CELS_ERROR_NOT_IMPLEMENTED for the new API calls, thus providing compatibility with both old and new apps).

The API consists of four services that callback should implement:
- CELS_RECEIVE_FILLED_INBUF - receive next filled input buffer from the input queue: bufsize returned as result, bufptr stored in *inbuf
- CELS_SEND_EMPTY_INBUF - send empty input buffer (inbuf,insize) to the input queue
- CELS_RECEIVE_EMPTY_OUTBUF - receive next empty output buffer from the output queue: bufsize returned as result, bufptr stored in *outbuf
- CELS_SEND_FILLED_OUTBUF - send filled output buffer (outbuf,outsize) to the output queue

Note that all services may be invoked in parallel. It's only guaranteed that CELS_RECEIVE_FILLED_INBUF calls will be serialized, as well as CELS_SEND_FILLED_OUTBUF (since they should follow the data order).

More details are available at:
- [implementation](https://encode.ru/threads/2718-Standard-compression-library-API?p=51928&viewfull=1#post51928)



## Codec development

Our example codec simply copies input data to the output intact.


<a name="minimal-example-streaming-compression2"/>

### Minimal example: streaming compression

Minimal complete example (provided in easy_codec.cpp):

```C
#include "CELS.h"

CelsResult __cdecl CelsMain (void* self, int service, void* inbuf, CelsNum insize, void* outbuf, CelsNum outsize, void* ud, CelsCallback* cb)
{
    switch (service)
    {
    case CELS_COMPRESS:
    case CELS_DECOMPRESS:
        {
            if (inbuf || outbuf)  return CELS_ERROR_NOT_IMPLEMENTED;
            if (!cb)              return CELS_ERROR_GENERAL;

            char buf[4096];
            while (CelsResult len = CelsRead (cb,ud, buf,4096))
            {
                if (len < CELS_OK)  return len;  // Return errcode on error
                CelsResult result = CelsWrite (cb,ud, buf,len);
                if (result != len)  return result<CELS_OK? result : CELS_ERROR_WRITE;
            }
            return CELS_OK;
        }

    default:
        return CELS_ERROR_NOT_IMPLEMENTED;
    }
}
```

For minimal functionality, codec only need to support CELS_COMPRESS/CELS_DECOMPRESS services with inbuf==outbuf==0. For any unsupported services/parameters it should return CELS_ERROR_NOT_IMPLEMENTED.

Implementation of these services should compress/decompress data, reading input with CELS_READ callback and writing output with CELS_WRITE callback. CelsRead and CelsWrite are small helper functions performing these callbacks.


### Registering codec

There are two simple ways to register a codec: if it statically linked to an application, then we should call `CelsRegister()`:

```C
// Declared in the CELS.h
CelsResult CelsRegister (const char* name, void* ud, CelsFunction* CelsMain);

// Usage example
CelsRegister ("test", NULL, CelsMain);
```

The first parameter of CelsRegister is codec name exposed to an application. The last parameter (cb) is a codec function, and the previous parameter (ud) will be passed as first parameter (self) for this function. You may register multiple codecs with the same CelsMain function and use `self` to choose between them. Of course, when you call the `CelsRegister()` directly, you may choose any name for a codec function (as opposite to dynamic library case described below when you should export exactly the `CelsMain` function).

As shown in the `easy_codec.cpp` example, you may include CelsRegister call directly in the codec sources by using its value to "initialize" a global variable:

```C
static CelsResult dummy = CelsRegister ("test", NULL, CelsMain);
```

Second way to register a codec in an application is to compile it into dynamic library (.dll, .so, .dynlib depending on the OS) exposing the `CelsMain` function. Call to `CelsLoad()` scans the application executable directory and loads all dynamic libraries with filenames `cels-*.dll` and either `cels32-*.dll` or `cels64-*.dll` depending on bitness of the executable (or `.so` or `.dynlib` on other OSes). If dynamic library exports the `CelsMain` function, the framework registers it as a codec named after the dynamic library filename. F.e. codec loaded from file `cels64-MyCodec.dll` will be registered with `CelsRegister ("mycodec", dll_handle, CelsMain)`.

So, if you know that application calls the `CelsLoad()`, you may compile a codec into `cels-CodecName.dll` exporting the `CelsMain` function and drop the DLL into the application executable directory.

`CelsLoad()` also scans `cls-*.dll/cls32-*.dll/cls64-*.dll` files looking for the same `CelsMain()`. This allows you to ship a single dynamic library that exports both `ClsMain()` and `CelsMain()` making it compatible with both old applications using CLS and new ones.


### Memory buffer compression and mixed-mode compression

In many cases, applications need to compress/decompress data from a memory buffer to a memory buffer. While the CELS framework provides the `CelsCompressMem` and `CelsDecompressMem` functions implementing this service even for codecs that support only streaming compression, implementing these services directly in codec is more efficient. It's implemented by the same CELS_COMPRESS/CELS_DECOMPRESS services with inbuf!=0 and outbuf!=0. Moreover, they may be called in the mixed mode, where only inbuf or outbuf is specified and data on opposite side are should be handled with the callback. It's rarely required, but you may support it too if you wish:

```C
#include "CELS.h"

CelsResult __cdecl CelsMain (void* self, int service, void* inbuf, CelsNum insize, void* outbuf, CelsNum outsize, void* ud, CelsCallback* cb)
{
    switch (service)
    {
    case CELS_COMPRESS:
    case CELS_DECOMPRESS:
        {
            // Memory buffer compression: from inbuf to outbuf
            if (inbuf && outbuf)
            {
                if (insize > outsize)  return CELS_ERROR_OUTBLOCK_TOO_SMALL;
                memcpy (outbuf, inbuf, insize);
                return insize;
            }

            // All remaining cases are require callback
            if (!cb)  return CELS_ERROR_GENERAL;

            // Mixed mode: from inbuf to CelsWrite()
            if (inbuf)
            {
                CelsResult result = CelsWrite (cb,ud, inbuf,insize);
                if (result != insize)  return result<CELS_OK? result : CELS_ERROR_WRITE;
            }

            // Another mixed mode: from CelsRead() to outbuf. We choose to not implemented that.
            if (outbuf)  return CELS_ERROR_NOT_IMPLEMENTED;

            // Streaming compression: from CelsRead() to CelsWrite()
            char buf[4096];
            while (CelsResult len = CelsRead (cb,ud, buf,4096))
            {
                if (len < CELS_OK)  return len;  // Return errcode on error
                CelsResult result = CelsWrite (cb,ud, buf,len);
                if (result != len)  return result<CELS_OK? result : CELS_ERROR_WRITE;
            }
            return CELS_OK;
        }

    default:
        return CELS_ERROR_NOT_IMPLEMENTED;
    }
}
```

<a name="providing-smooth-progress-indicator2"/>

### Providing smooth progress indicator

While (dec)compression goes, FreeArc shows the progress indicator including information how much bytes were already (de)compressed, their (de)compressed size and (de)compression speed. In order to improve smoothness and accuracy of the progress indicator, codec may periodically call the `CelsProgress` procedure. I recommend to do it once per each 64-256 KB processed, but at least once per 1 ms. It will not slowdown the operation, since overhead of callback invocation by itself is very small, and this call, unlike I/O calls, doesn't suppose any OS interaction. Application should accumulate multiple progress messages and update the real display once per 0.1-1 second.

Take into account that compression filters, while very fast by itself, are usually combined with much slower main compression algorithms and delay between successive `CelsProgress` calls will be defined by the overall time required to process data by all algorithms. It's important to note that progress calls are also used by FreeArc to determine current compression ratio for algorithm chain, so it's important that all algorithms report their current compression ratio (i.e. insize and outsize) at pretty close rate (i.e. those 64-256 KB).

Progress is reported by calling `CelsProgress(cb,ud,insize,outsize)` where insize is amount of input bytes processed and outsize is the amount of output bytes produced SINCE the last CelsProgress call. This includes bytes that cannot be written yet. If operation will invoke the progress callback, it's recommended to call `CelsProgress(cb,ud,0,0)` right at the start of operation to let an application know beforehand. Like CelsRead and CelsWrite, CelsProgress is just a little helper function invoking `cb` with CELS_PROGRESS constant.

In the following example we report progress while performing buffer compression:

```C
#include "CELS.h"

CelsResult __cdecl CelsMain (void* self, int service, void* inbuf, CelsNum insize, void* outbuf, CelsNum outsize, void* ud, CelsCallback* cb)
{
    switch (service)
    {
    case CELS_COMPRESS:
    case CELS_DECOMPRESS:
        {
            // Memory buffer compression: from inbuf to outbuf
            if (inbuf && outbuf)
            {
                if (insize > outsize)  return CELS_ERROR_OUTBLOCK_TOO_SMALL;

                CelsProgress(cb,ud, 0,0);
                for (CelsNum pos=0; pos<insize; )
                {
                    CelsNum bytes = std::min(insize-pos, 256<<10);
                    memcpy (outbuf+pos, inbuf+pos, bytes);
                    CelsProgress(cb,ud, bytes,bytes);
                    pos += bytes;
                }
                return CELS_OK;
            }
            return CELS_ERROR_NOT_IMPLEMENTED;
        }

    default:
        return CELS_ERROR_NOT_IMPLEMENTED;
    }
}
```

### Getting method parameters

FreeArc requests from codecs information about their facilities - how much memory they are using, how much CPU load they create and so on. This information is then reported to a user and used to optimize (de)compression operation for particular hardware and specific data, f.e. by reducing memory usage on RAM shortage or setting number of threads.

This defines a bunch of services that codec can implement to improve user experience. You can find the full list of `CELS_GET_*` constants defining these services in `CELS.h` and their meaning is described in section WIP. Here is a quick example providing some of the services:

```C
#include "CELS.h"

CelsResult __cdecl CelsMain (void* self, int service, void* inbuf, CelsNum insize, void* outbuf, CelsNum outsize, void* ud, CelsCallback* cb)
{
    const int BUFSIZE = 4096;

    switch (service)
    {
    case CELS_GET_COMPRESSION_MEMORY:
    case CELS_GET_DECOMPRESSION_MEMORY:
        return BUFSIZE;

    case CELS_GET_COMPRESSION_CPU_LOAD:
    case CELS_GET_DECOMPRESSION_CPU_LOAD:
        return 100;

    case CELS_GET_MAX_COMPRESSED_SIZE:
        return insize;

    case CELS_COMPRESS:
    case CELS_DECOMPRESS:
        {
            if (inbuf || outbuf)  return CELS_ERROR_NOT_IMPLEMENTED;
            if (!cb)              return CELS_ERROR_GENERAL;

            char buf[BUFSIZE];
            while (CelsResult len = CelsRead (cb,ud, buf,BUFSIZE))
            {
                if (len < CELS_OK)  return len;  // Return errcode on error
                CelsResult result = CelsWrite (cb,ud, buf,len);
                if (result != len)  return result<CELS_OK? result : CELS_ERROR_WRITE;
            }
            return CELS_OK;
        }

    default:
        return CELS_ERROR_NOT_IMPLEMENTED;
    }
}
```

### Parsing a method string

Compression method may have parameters, in which case it should provide parsing service converting them from text into binary representation, and unparsing service performing the opposite. The parsing service has code CELS_PARSE and receives list of input parameter strings in the inbuf and buffer to store parsed binary structure in the (outbuf,outsize). The outsize is usually CELS_MAX_PARSED_METHOD_SIZE bytes minus a few dozen bytes that the CELS framework reserves for its own data, so try to limit your parsed method structure to ~900 bytes. If your need more storage - allocate it from a heap and release in the CELS_FREE service (this technique demoed in section WIP).

The FreeArc standard is to delimit parameters by the colon, and CELS_PARSE service receives the method string that is already split into list of parameters by this character. F.e. method string `"lzma:d1m:fb12"` will be passed as `{"lzma", "d1m", "fb12", NULL}` list. I plan to add later a sophisticated API simplifying the parameter parsing, but just now all you can do is to borrow some helper functions from FreeArc sources.

Parsing service should return size of the binary structure it created in the outbuf. The framework or an application will use
this size when moving the parsed structure elsewhere. The size may be even zero. Of course, negative return values, as usual, means `CELS_ERROR_*` codes.

```C
#include "CELS.h"

structure CopyCodec {
    int bufsize;
};

CelsResult __cdecl CelsMain (void* self, int service, void* inbuf, CelsNum insize, void* outbuf, CelsNum outsize, void* ud, CelsCallback* cb)
{
    switch (service)
    {
    case CELS_PARSE:
        {
            if (outsize < sizeof(CopyCodec))  return CELS_ERROR_GENERAL;

            CopyCodec* codec = (CopyCodec*) outbuf;
            codec->bufsize = 4096;  // set up default codec parameters

            char** param = (char**)inbuf;

            // Skip param[0] since it contains the method name
            while (*++param)
            {
                if (**param=='b')  {codec->bufsize = atoi(*param+1); continue;}
                else return CELS_ERROR_INVALID_COMPRESSOR;
            }

            return sizeof(CopyCodec);
        }

    case CELS_COMPRESS:
    case CELS_DECOMPRESS:
        ...;

    default:
        return CELS_ERROR_NOT_IMPLEMENTED;
    }
}
```

Note that the `param[0]` always points to the method name, but in simple cases we don't need to check it - the CELS framework ensures that `param[0]` matches the string registered as the codec name. There are only two cases when we need to check it:

- When the same `CelsMain` function was registered with multiple codec names. F.e. we may prefer to implement similar methods like `lzma/lzma2` or `aes-128/aes-256` with the same `CelsMain` that checks the `param[0]` and stores appropriate information in the parsed method structure.

- When codec was registered with wildcard name, f.e. `aes*` or just `*`. Like the previous case, we need to check method name correctness and store appropriate information in the parsed method structure.


### Unparsing a method structure

The CELS_UNPARSE service should build a method string in the `(outbuf,outsize)` buffer from a parsed method structure pointed by the `self` parameter. Usually `outsize==CELS_MAX_METHOD_STRING_SIZE` and codecs are expected to fit resulting string (plus a zero byte) into this space. Nevertheless, `outsize` should be explicitly checked and error code returned if buffer is too small.

The `insize` parameter specifies variant of string to build:
- CELS_UNPARSE_FULL requests to build string containing all method options as stored in the parsed structure
- CELS_UNPARSE_DISPLAY requests to build method string prepared for display, with sensitive information like encryption keys removed
- CELS_UNPARSE_PURE requests to build method string prepared for storing in archive, with sensitive information and, optionally, compression-specific parameters removed

For most codecs, output string doesn't depend on the `insize`.

```C
#include "CELS.h"

structure CopyCodec {
    int bufsize;
};

CelsResult __cdecl CelsMain (void* self, int service, void* inbuf, CelsNum insize, void* outbuf, CelsNum outsize, void* ud, CelsCallback* cb)
{
    switch (service)
    {
    case CELS_PARSE:
        ...;

    case CELS_UNPARSE:
    {
        if (outsize < 100)  return CELS_ERROR_GENERAL;

        CopyCodec* codec = (CopyCodec*) self;
        sprintf(outbuf, "test:b%d", codec->bufsize);
        return CELS_OK;
    }

    default:
        return CELS_ERROR_NOT_IMPLEMENTED;
    }
}
```

### Default implementation of (un)parsing services

If codec doesn't support the CELS_PARSE service AND was registered with a non-wildcard name, the CELS framework provides the default implementation that ensures that no method options are supplied. If codec ALSO doesn't support the CELS_UNPARSE service, the CELS framework provides the default implementation that just copies the registered method name to the outbuf. This allows to not implement CELS_PARSE/CELS_UNPARSE services in simple codecs that don't have any options, as we have done in first sections of this tutorial. The code equivalent to default implementations:

```C
    case CELS_PARSE:
        {
            char** param = (char**)inbuf;
            if (param[1])  return CELS_ERROR_INVALID_COMPRESSOR;
            return 0;  // size of parsed method structure
        }

    case CELS_UNPARSE:
        {
            if (outsize < strlen(METHOD_NAME)+1)  return CELS_ERROR_GENERAL;
            strcpy(outbuf, METHOD_NAME);
            return CELS_OK;
        }
```

### Using the parsed method structure

All instance services (see section WIP) receive pointer to the parsed method structure in the `self` parameter of `CelsMain`. This allows codecs to use data stored in the structure to change their behavior. The following example shows how our model codec can use the parsed bufsize parameter to modify size of its memory buffer:

```C
#include "CELS.h"

structure CopyCodec {
    int bufsize;
};

CelsResult __cdecl CelsMain (void* self, int service, void* inbuf, CelsNum insize, void* outbuf, CelsNum outsize, void* ud, CelsCallback* cb)
{
    switch (service)
    {
    case CELS_PARSE: ...;
    case CELS_UNPARSE: ...;

    case CELS_COMPRESS:
    case CELS_DECOMPRESS:
        {
            if (inbuf || outbuf)  return CELS_ERROR_NOT_IMPLEMENTED;
            if (!cb)              return CELS_ERROR_GENERAL;

            CopyCodec* codec = (CopyCodec*) self;
            char* buf = malloc (codec->bufsize);
            if (!buf)  return CELS_ERROR_NOT_ENOUGH_MEMORY;

            while (CelsResult len = CelsRead (cb,ud, buf,codec->bufsize))
            {
                if (len < CELS_OK)  {free(buf);  return len;}  // Return errcode on error
                CelsResult result = CelsWrite (cb,ud, buf,len);
                if (result != len)  {free(buf);  return result<CELS_OK? result : CELS_ERROR_WRITE;}
            }
            free(buf);
            return CELS_OK;
        }

    default:
        return CELS_ERROR_NOT_IMPLEMENTED;
    }
}
```

### Setting method parameters

Once we have parsing/unparsing services and structure to store codec instance options, we can provide services to change method parameters, i.e. modify its memory usage, numbers of threads and so on. This is implemented by providing `CELS_SET_*` services modifying structure pointed by the `self`. New parameter value is supplied in the `insize`, and extra data may be passed in the `inbuf`. Of course, `CELS_GET_*` also should use the `self` to return correct information about the particular codec instance:

```C
#include "CELS.h"

structure CopyCodec {
    int bufsize;
};

CelsResult __cdecl CelsMain (void* self, int service, void* inbuf, CelsNum insize, void* outbuf, CelsNum outsize, void* ud, CelsCallback* cb)
{
    CopyCodec* codec = (CopyCodec*) self;  // valid only for codec instance services

    switch (service)
    {
    case CELS_GET_COMPRESSION_MEMORY:
    case CELS_GET_DECOMPRESSION_MEMORY:
        return codec->bufsize;

    case CELS_SET_COMPRESSION_MEMORY:
    case CELS_SET_DECOMPRESSION_MEMORY:
        codec->bufsize = insize;
        return CELS_OK;

    case CELS_PARSE: ...;
    case CELS_UNPARSE: ...;
    case CELS_COMPRESS: ...;
    case CELS_DECOMPRESS: ...;

    default:
        return CELS_ERROR_NOT_IMPLEMENTED;
    }
}
```

### Meaning of method parameters

to do:

<a name="caching2"/>

### Caching

Application may request codec to enable caching in order to avoid spending time on memory alloc/free operations and initialization as well as reduce memory fragmentation. Request to enable/disable caching is `CelsMain(instance,CELS_SET_CACHING,0,on_off,0,0,ud,cb)` where `on_off=1/0` should enable/disable caching, and request to check whether caching is currently enabled is `on_off=CelsMain(instance,CELS_GET_CACHING,0,0,0,0,ud,cb)`, where `instance` is a pointer to parsed method structure. Of course, codec may not support these services, returning usual CELS_ERROR_NOT_IMPLEMENTED on these requests.

Once caching is enabled, codec is expected to keep memory allocated in compression/decompression operations and reuse it in subsequent operations if possible. On the "disable caching" request, codec should free all previously allocated caching memory. It also should be freed on the CELS_FREE request (see section WIP for details about this service).

Note that in order to keep pointers to cached resources, you need a parsed method structure, so (with the current CELS implementation) you obliged to implement CELS_PARSE and CELS_UNPARSE services. The following example shows codec that has no options, but supports caching:

```C
#include "CELS.h"

structure CopyCodec {
    bool caching_enabled;
    void* buf;
};

CelsResult __cdecl CelsMain (void* self, int service, void* inbuf, CelsNum insize, void* outbuf, CelsNum outsize, void* ud, CelsCallback* cb)
{
    const int BUFSIZE = 4096;
    CopyCodec* codec = (CopyCodec*) self;  // valid only for codec instance services

    switch (service)
    {
    case CELS_PARSE:
        // Simple parser that ensures that method string doesn't specify any options,
        // and initializes the instance caching infrastructure
        {
            if (outsize < sizeof(CopyCodec))  return CELS_ERROR_GENERAL;

            char** param = (char**)inbuf;
            if (param[1])  return CELS_ERROR_INVALID_COMPRESSOR;

            CopyCodec* codec = (CopyCodec*) outbuf;
            codec->caching_enabled = false;
            codec->buf = NULL;

            return sizeof(CopyCodec);
        }

    case CELS_UNPARSE:
        // Exactly the same as the default unparser
        {
            if (outsize < strlen(METHOD_NAME)+1)  return CELS_ERROR_GENERAL;
            strcpy(outbuf, METHOD_NAME);
            return CELS_OK;
        }


    case CELS_SET_CACHING:
        // Enable or disable caching.
        // If caching was disabled, free any cache memory.
        {
            codec->caching_enabled = (insize!=0);
            if (! codec->caching_enabled) {
                free(codec->buf);
                codec->buf = NULL;
            }
            return CELS_OK;
        }

    case CELS_GET_CACHING:
        return codec->caching_enabled? 1:0;

    case CELS_FREE:
        // Free all memory allocated by the instance, including any cache memory.
        free(codec->buf);
        codec->buf = NULL;
        return CELS_OK;


    case CELS_COMPRESS:
    case CELS_DECOMPRESS:
        // Compression code that reuses cached buffer if available,
        // and keeps allocated buffer if caching enabled
        {
            if (inbuf || outbuf)  return CELS_ERROR_NOT_IMPLEMENTED;
            if (!cb)              return CELS_ERROR_GENERAL;

            // Try to reuse buffer cached in the instance object,
            // and allocate new buffer if there is no one
            char* buf = codec->buf;
            if (!buf)  buf = malloc(BUFSIZE);
            if (!buf)  return CELS_ERROR_NOT_ENOUGH_MEMORY;

            CelsResult len_or_errcode;

            while (len_or_errcode = CelsRead (cb,ud, buf,BUFSIZE))
            {
                if (len_or_errcode < CELS_OK)  goto finished;  // Return errcode on error
                CelsResult result = CelsWrite (cb,ud, buf,len);
                if (result != len_or_errcode) {
                    len_or_errcode = (result<CELS_OK? result : CELS_ERROR_WRITE);
                    goto finished;
                }
            }

            // Keep allocated buffer in the instance object if caching enabled,
            // free it otherwise
            if (codec->caching_enabled) {
                codec->buf = buf;
            } else {
                free(buf);
            }
            return len_or_errcode;
        }

    default:
        return CELS_ERROR_NOT_IMPLEMENTED;
}
```

### Registering codecs: the full API

Codecs loaded from dynamic libraries (dll/so/dynlib) may provide services of three types - module-level, codec-level and instance-level, while codecs registered by `CelsRegister()` may provide only codec-level and instance-level services. The following sections describes only services invoked by the CELS framework. All other services are essentially convention between a codec and an application.

to do: diagram


#### Module-level services

Module-level services should be implemented by the `CelsMain` function exported by the DLL and receive as the first parameter `self` an OS-specific handle of the DLL.

There are two module-level services employed by the CELS framework - CELS_LOAD_MODULE and CELS_UNLOAD_MODULE. They allow to grab and release necessary OS resources on the module level, and perform more flexible codec registration.

Once DLL is loaded, `CelsLoad()` starts with executing `CelsMain(dll,CELS_LOAD_MODULE,0,0,0,0,0,Cels)` where `dll` is an OS-specific handle of the dynamic library, and `Cels` is a pointer to the main CELS function. If the call returns non-negative value, the module registration considered successful and DLL handle is added to the DLL list. If return value is negative other than CELS_ERROR_NOT_IMPLEMENTED, the module registration considered failed and DLL is released.

If return value is CELS_ERROR_NOT_IMPLEMENTED, the DLL considered as not supporting module-level registration and automatic codec registration performed instead - it performs `CelsRegister(module_name,dll,CelsMain)` where `module_name` is lowercased dll name without `cels*-` prefix and file extension, f.e. 'test' for 'cels64-TesT.dll'. The `dll` parameter is the DLL handle - it will be passed as the first parameter `self` to invocations of codec-level services for this codec. And again, DLL handle is added to the DLL list if `CelsRegister` call returns non-negative value or CELS_ERROR_NOT_IMPLEMENTED, otherwise DLL handle will be released immediately.

`CelsUnload()` loops through the DLL list and executes `CelsMain(dll,CELS_UNLOAD_MODULE,0,0,0,0,0,Cels)` before releasing the DLL handle.

Note that if CELS_LOAD_MODULE service succeeds, the CELS framework doesn't register codecs himself, expecting that it was already done by your code. CELS_LOAD_MODULE cannot call its own dll-local copy of the `CelsRegister()` since it will register codec in DLL-local codec list that isn't used by application `Cels()`. Instead, it should call the passed `Cels` callback (which is the pointer to application `Cels()`) as `Cels(self,CELS_REGISTER,method_name,0,0,0,ud,CelsMain)` which is equivalent to `CelsRegister(method_name,ud,CelsMain)`. Moreover, the passed `Cels` pointer may be saved and used by the codec to call any CELS services at the application level, i.e. using all codecs registered by the application. In particular, it may be used to implement 4x4-like codecs.

Explicit calls to `CelsRegister` (and equivalent calls to Cels(CELS_REGISTER)) allow DLL (or application code) to do things impossible for automatic registration - register methods with stable names independent of the DLL filename, register multiple codecs in the same DLL and register codecs with wildcard names such as `"aes*"`. The codec function passed to registration isn't necessarily the same CelsMain - f.e. you may want to register function LzmaCodec for method "lzma" and function BcjCodec for method "bcj":

```C
#include "CELS.h"

CelsResult __cdecl CelsMain (void* self, int service, void* inbuf, CelsNum insize, void* outbuf, CelsNum outsize, void* ud, CelsCallback* cb)
{
    switch (service)
    {
    case CELS_LOAD_MODULE:
        cb(ud,CELS_REGISTER,"lzma",0,0,0,0,LzmaCodec);
        cb(ud,CELS_REGISTER,"bcj",0,0,0,0,BcjCodec);
        return CELS_OK;

    default:
        return CELS_ERROR_NOT_IMPLEMENTED;
    }
}
```

#### Codec-level services

Codec-level services should be implemented by the codec function registered with `CelsRegister()`. They receive as the first parameter `self` the `ud` parameter passed to the `CelsRegister` call.

There are three codec-level services employed by the CELS framework - CELS_LOAD_CODEC, CELS_UNLOAD_CODEC and CELS_PARSE.

When `CelsRegister()` registers a codec, it tries to invoke CELS_LOAD_CODEC service of the codec function: `CelsMain(self,CELS_LOAD_CODEC,0,0,0,0,0,Cels)`. This gives the codec opportunity to grab OS resources, perform calls to application `Cels()` or store this function pointer for later usage. If CELS_LOAD_CODEC handler returns negative value other than CELS_ERROR_NOT_IMPLEMENTED, codec isn't registered. The handler return value is returned as result of entire `CelsRegister` call (but CELS_ERROR_NOT_IMPLEMENTED value translated to CELS_OK), so you can check it if you have called `CelsRegister` manually. If `CelsRegister` was called automatically (i.e. by DLL loader when CelsMain doesn't implement the CELS_LOAD_MODULE service), negative result of `CelsRegister` considered as failure and DLL handle is immediately released.

`CelsUnload()` loops through the list of registered codecs and executes `CelsMain(self,CELS_UNLOAD_CODEC,0,0,0,0,0,Cels)` on each codec where `CelsMain` and `self` are codec registration parameters. In the current implementation `CelsUnload()` "unloads" all codecs prior to "unloading" DLLs and releasing their handles.

CELS_PARSE service called to convert string method options (pointed by the `inbuf`) into binary method structure placed into the buffer `(oubuf,outsize)` called codec instance. Most CELS services are executed on codec instances.


#### Instance-level services

Instance-level services also should be implemented by the codec function registered with `CelsRegister()`. They receive as the first parameter `self` pointer to the binary structure filled by CELS_PARSE service of this codec.

There are three instance-level services employed by the CELS framework - CELS_INITIALIZE, CELS_FREE and CELS_UNPARSE.

CELS_INITIALIZE/CELS_FREE services are essentially instance-level "load/unload" services that may be used to grab/release OS resources. They also receive pointer to application `Cels()` as their last parameter `cb`. CELS_INITIALIZE is called after successful CELS_PARSE and is always the first service performed by the new-born codec instance, while CELS_FREE is called prior to releasing an instance and is always the last service performed by a codec instance.

CELS_UNPARSE service called to convert codec instance to a method string.


### The Cels() algorithm

`Cels()` can perform global, module-level, codec-level and instance-level services on method strings and parsed method structures. The algorithm is the following:

- if global service is requested, `Cels()` performs it directly (see section WIP)
- if the `self` argument isn't parsed method structure (the CELS framework ensures that these structures are started with zero byte), then it's treated as method string which parsed into temporary method structure
- the parsed method structure (either passed as `self` or temporary) holds pointer to `CelsMain` of the codec. If instance-level service is requested, it's passed to this `CelsMain` with pointer to codec instance passed as the `self`
- remaining services are passed into `CelsMain` too, but global codec `self` (that was passed into appropriate `CelsRegister`) is passed as the first argument. Note that this may be a wrong behavior for module-level services
- once service is executed, if it is a "set parameter" service and if original `self` was a method string, the modified parsed method structure is unparsed into buffer `(outbuf,outsize)`. Note that in this case the "set parameter" service itself receives zeros as its outbuf and outsize arguments


### Rules for choosing codes for new services
### Buffer-sharing API

More details are available at:
- [implementation](https://encode.ru/threads/2718-Standard-compression-library-API?p=51928&viewfull=1#post51928)
