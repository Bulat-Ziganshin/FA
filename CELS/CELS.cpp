#include <stdio.h>  // only for debugging
#include <string.h>
#include <stdlib.h>
#include "CELS.h"


// Auxiliary functions =============================================================================

// Extend the array by 1 element and return address of the new array element
static void* ExtendArray (void** array, int element_size, int* i, int* size)
{
    if (*i >= *size) {
        int new_size = *size * 2 + 32;
        void* new_array = realloc(*array, new_size*element_size);
        if (new_array==NULL)  return NULL;
        *array = new_array;
        *size = new_size;
    }
    *i += 1;
    return (char*)*array + (*i-1) * element_size;
}

// Compute hash of the string
static unsigned StringHash (const char* str)
{
    unsigned hash = 314159265;
    do {
        hash = (hash + *str) * 1234567891;
        hash += hash>>17;
    } while (*str++);
    return hash;
}

// Разбить строку str на подстроки, разделённые символом splitter.
// Результат - в строке str splitter заменяется на '\0'
//   и массив result заполняется ссылками на выделенные в str подстроки + NULL (аналогично argv)
// Возвращает число найденных подстрок
static int SplitStr (char *str, char splitter, char **result_base, int result_size)
{
    char **result      = result_base;
    char **result_last = result_base+result_size-1;
    *result++ = str;
    while (*str && result < result_last)
    {
        while (*str && *str!=splitter) str++;
        if (*str) {
            *str++ = '\0';
            *result++ = str;
        }
    }
    *result = NULL;
    return result-result_base;
}

#ifdef _WIN32
#include <windows.h>
CelsResult DllUnload (void* dll)
{
    FreeLibrary ((HMODULE)dll);
    return CELS_OK;
}
#else
CelsResult DllUnload (void* dll)
{
    return CELS_ERROR_NOT_IMPLEMENTED;
}
#endif


// ****************************************************************************************************************************
// Method registering/parsing *************************************************************************************************
// ****************************************************************************************************************************

typedef struct {
    const char *name;  void* self;  CelsFunction* CelsMain;  unsigned hash;
} RegCodec;
static RegCodec* RegisteredCodecs = NULL;
static int NumRegisteredCodecs = 0;
static int MaxRegisteredCodecs = 0;

CelsResult CelsRegister (const char* name, void* ud, CelsFunction* CelsMain)
{
    // Add new record to the list of registered codecs
    RegCodec* codec = (RegCodec*)  ExtendArray ((void**)&RegisteredCodecs, sizeof(RegCodec), &NumRegisteredCodecs, &MaxRegisteredCodecs);
    if (codec==NULL)  return CELS_ERROR_NOT_ENOUGH_MEMORY;

    // Fill the record
    if (*name=='\0')  name = "*";
    const char* wildcard = strchr(name,'*');  // points to a first char after fixed part of wildcard name
    codec->name     = name;
    codec->self     = ud;
    codec->CelsMain = CelsMain;
    codec->hash     = wildcard? wildcard-name : StringHash(name);   // wildcard: size of fixed part, otherwise: hash of the method name

    // Initialize the codec
    CelsResult result = codec->CelsMain (codec->self, CELS_LOAD_CODEC,0, NULL,0, NULL,0, NULL,(CelsCallback*)Cels);
    if (result == CELS_ERROR_NOT_IMPLEMENTED)   result = CELS_OK;
    if (result < CELS_OK)                       --NumRegisteredCodecs;
    return result;
}

// Internal structure placed before parsed compression method
typedef struct
{
    char zero;  // first byte of structure should be 0 in order to distinguish between parsed method structure and unparsed method string
    CelsFunction* CodecMain;
    void*         CodecSelf;
    CelsFunction* CelsMain;
    const char*   CodecName;
} CELS_CODEC_INSTANCE;

const int CELS_HEADER = sizeof(CELS_CODEC_INSTANCE);

// Execute operation on parsed codec instance.
// Only this function and CelsParseSplitted() deals with instance internals.
static CelsResult CallCels (void* method, int service, CelsNum subservice, void* inbuf, CelsNum insize, void* outbuf, CelsNum outsize, void* ud, CelsCallback* cb)
{
    CELS_CODEC_INSTANCE* instance = (CELS_CODEC_INSTANCE*) method;
    if (IS_CELS_INSTANCE_SERVICE(service)) {
        // Run requested service on the instance
        CelsNum result = instance->CelsMain (instance+1, service,subservice, inbuf,insize, outbuf,outsize, ud,cb);
        if (result==CELS_ERROR_NOT_IMPLEMENTED && service==CELS_UNPARSE && instance->CodecName) {
            // Codec lacks PARSE/UNPARSE functionality
            if (strlen(instance->CodecName) >= outsize)
                return CELS_ERROR_GENERAL;
            strcpy ((char*)outbuf, instance->CodecName);
            return CELS_OK;
        }
        return result;
    } else {
        // Run requested service on the codec that created this instance
        return instance->CodecMain (instance->CodecSelf, service,subservice, inbuf,insize, outbuf,outsize, ud,cb);
    }
}

// Parse method already splitted into separate parameters and save parsed method into (method,method_size) buffer.\
// Only this function creates new codec instances.
CelsResult CelsParseSplitted (char const* const* parameters, void* method, CelsNum method_size, void* ud, CelsCallback* cb)
{
    const char* name = parameters[0];
    unsigned hash = StringHash(name);
    unsigned len = strlen(name);
    CelsResult errcode_or_size = CELS_ERROR_GENERAL;
    RegCodec* codec;

    for (codec = RegisteredCodecs+NumRegisteredCodecs;  codec-- > RegisteredCodecs; )
    {
        // Try only registered codecs with matching name (including wildcards like "aes*")
        int exact_name_match  =  codec->hash==hash && !strcmp(codec->name, name);   // check for exact name match
        if (exact_name_match ||  codec->hash<=len && !strncmp(codec->name, name, codec->hash)
                                 &&  strlen(codec->name) < codec->hash  &&  codec->name[codec->hash]=='*')
        {
            CELS_CODEC_INSTANCE* instance = (CELS_CODEC_INSTANCE*) method;
            *(char*)instance    = 0;
            instance->CodecMain = codec->CelsMain;
            instance->CodecSelf = codec->self;
            instance->CelsMain  = codec->CelsMain;
            instance->CodecName = NULL;

            errcode_or_size = codec->CelsMain (codec->self, CELS_PARSE,0, (void*)parameters,0,
                                               instance+1, method_size-CELS_HEADER, ud,cb);

            if (errcode_or_size == CELS_ERROR_NOT_IMPLEMENTED  &&  parameters[1] == NULL  &&  exact_name_match) {
                // Parsing isn't implemented that means method w/o parameters
                instance->CodecName = codec->name;   // will be used for CELS_UNPARSE if it's not supported too
                errcode_or_size = 0;
            }

            if (errcode_or_size >= 0) {
                // Allow instance to initialize itself
                CelsResult result = CallCels (method, CELS_INITIALIZE,0, NULL,0, NULL,0, NULL,(CelsCallback*)Cels);
                if (result < CELS_OK  &&  result != CELS_ERROR_NOT_IMPLEMENTED)
                    return result;

                // Successful parsing - errcode_or_size contains size of parsed record
                return CELS_HEADER + errcode_or_size;
            }
        }
    }
    return errcode_or_size;   // last error code returned by CELS_PARSE
}

// Parse method_str and save parsed method into (method,method_size) buffer
CelsResult CelsParseStr (const char* method_str, void* method, CelsNum method_size, void* ud, CelsCallback* cb)
{
    // Make modifiable copy of method_str
    char method_copy[CELS_MAX_METHOD_STRING_SIZE];  int i;
    for (i=0;  i<CELS_MAX_METHOD_STRING_SIZE-1 && method_str[i]!=0;  i++)
        method_copy[i] = method_str[i];
    method_copy[i] = 0;

    // Split method_str into parameters delimited by ':'
    char *parameters[CELS_MAX_METHOD_PARAMETERS];
    SplitStr (method_copy, CELS_METHOD_PARAMETERS_DELIMITER, parameters, CELS_MAX_METHOD_PARAMETERS);

    return CelsParseSplitted ((const char**) parameters, method,method_size, ud,cb);
}


// ****************************************************************************************************************************
// DLL loading/unloading ******************************************************************************************************
// ****************************************************************************************************************************

typedef struct {
    void*             dll;          // dynamic library
    char*             method_name;  // memory allocated for the library
    CelsFunction*     CelsMain;     // CelsMain() function loaded from the library
} RegModule;
static RegModule* RegisteredModules = NULL;
static int NumRegisteredModules = 0;
static int MaxRegisteredModules = 0;

CelsResult CelsRegisterModule (void* dll, const char* method_name, CelsFunction* CelsMain)
{
    RegModule* module = (RegModule*)  ExtendArray ((void**)&RegisteredModules, sizeof(RegModule), &NumRegisteredModules, &MaxRegisteredModules);
    if (module==NULL) {
        if (dll)  DllUnload(dll);
        return CELS_ERROR_NOT_ENOUGH_MEMORY;
    }
    module->dll         = dll;
    module->method_name = NULL;
    module->CelsMain    = CelsMain;

    CelsResult result = CelsMain (dll, CELS_LOAD_MODULE,0, NULL,0, NULL,0, NULL,(CelsCallback*)Cels);

    if (result == CELS_ERROR_NOT_IMPLEMENTED)
    {
        module->method_name = (char*) malloc(strlen(method_name)+1);
        if (module->method_name==NULL)  {result = CELS_ERROR_NOT_ENOUGH_MEMORY;  goto failed;}
        strcpy (module->method_name, method_name);
        result = CelsRegister (module->method_name, dll,CelsMain);
    }

    if (result >= CELS_OK)  return result;

failed:
    CelsMain (dll, CELS_UNLOAD_MODULE,0, NULL,0, NULL,0, NULL,(CelsCallback*)Cels);
    if (dll)  DllUnload(dll);
    --NumRegisteredModules;
    return result;
}

#ifdef _WIN32
#include <windows.h>
#include <string.h>

// Converts UTF-16 string to UTF-8
static char *UTF16toUTF8 (const wchar_t *utf16, char *_utf8)
{
  char *utf8 = _utf8;
  do {
    unsigned c = utf16[0];
    if (0xd800<=c && c<=0xdbff && 0xdc00<=utf16[1] && utf16[1]<=0xdfff)
      c = (c - 0xd800)*0x400 + (unsigned)(*++utf16 - 0xdc00) + 0x10000;

    // Now c represents full 32-bit Unicode char
         if (c<=0x7F)   *utf8++ = c;
    else if (c<=0x07FF) *utf8++ = 0xC0|(c>> 6)&0x1F,  *utf8++ = 0x80|(c>> 0)&0x3F;
    else if (c<=0xFFFF) *utf8++ = 0xE0|(c>>12)&0x0F,  *utf8++ = 0x80|(c>> 6)&0x3F,  *utf8++ = 0x80|(c>> 0)&0x3F;
    else                *utf8++ = 0xF0|(c>>18)&0x0F,  *utf8++ = 0x80|(c>>12)&0x3F,  *utf8++ = 0x80|(c>> 6)&0x3F,  *utf8++ = 0x80|(c>> 0)&0x3F;

  } while (*utf16++);
  return _utf8;
}

// Add CELS-enabled compressors from DLLs matching the wildcard
static void RegisterCelsDlls (const wchar_t *dll_wildcard, wchar_t *path, wchar_t *basename)
{
    // Replace basename part with "celsXX-*.dll"
    wcscpy (basename, dll_wildcard);

    // Find all celsXX-*.dll from program's directory
    WIN32_FIND_DATAW FindData;
    HANDLE ff = FindFirstFileW(path, &FindData);
    BOOL found;
    for (found = (ff!=INVALID_HANDLE_VALUE);  found;  found = FindNextFileW(ff, &FindData))
    {
        // Put full DLL filename into `path`
        wcscpy (basename, FindData.cFileName);

        // If DLL contains CelsMain() - register included codecs
        HMODULE dll = LoadLibraryW(path);
        CelsFunction *CelsMain = (CelsFunction*) GetProcAddress (dll, "CelsMain");
        if (CelsMain)
        {
            // Register new CELS method in the global list of compression methods
            char method_buf[MAX_PATH], *method_name;
            UTF16toUTF8 (basename, method_buf);

            // "cels-TeSt.dll" will be registered as "test" compression method
            method_name = strchr(method_buf,'-')+1;   // skip "cels-" prefix
            strrchr(method_name,'.')[0] = '\0';       // remove ".dll" suffix
            strlwr(method_name);

            // Register included codecs
            CelsRegisterModule (dll, method_name, CelsMain);
        }
    }
    FindClose(ff);
}

// Add CELS-enabled compressors from celsXX-*.dll (also from clsXX-*.dll in order to allow distribution of CLS+CELS-enabled DLLs)
CelsResult CelsLoad()
{
    // Get program's executable/unarc.dll filename (or, more exactly, filename of module containing the CelsLoad function)
    MEMORY_BASIC_INFORMATION mbi;
    VirtualQuery ((void*)CelsLoad, &mbi, sizeof(MEMORY_BASIC_INFORMATION));

    wchar_t path[MAX_PATH];
    GetModuleFileNameW ((HMODULE) mbi.AllocationBase, path, MAX_PATH);

    // Replace basename part with "celsXX-*.dll"
    wchar_t *basename = wcsrchr (path, L'\\') + 1;
    RegisterCelsDlls (L"cls-*.dll",        path, basename);
    RegisterCelsDlls (L"cels-*.dll",       path, basename);
    if (sizeof(void*) == 8) {
        RegisterCelsDlls (L"cls64-*.dll",  path, basename);
        RegisterCelsDlls (L"cels64-*.dll", path, basename);
    } else {
        RegisterCelsDlls (L"cls32-*.dll",  path, basename);
        RegisterCelsDlls (L"cels32-*.dll", path, basename);
    }

    return CELS_OK;
}

#else

CelsResult CelsLoad()
{
    return CELS_ERROR_NOT_IMPLEMENTED;   // Non-Windows platforms aren't yet supported
}

#endif  // _WIN32

void CelsUnload()
{
    // Unload codecs
    while (NumRegisteredCodecs > 0) {
        RegCodec *codec  =  & RegisteredCodecs[--NumRegisteredCodecs];
        codec->CelsMain (codec->self, CELS_UNLOAD_CODEC,0, NULL,0, NULL,0, NULL,(CelsCallback*)Cels);
    }
    free(RegisteredCodecs);
    RegisteredCodecs = NULL;
    MaxRegisteredCodecs = 0;

    // Unload modules
    while (NumRegisteredModules > 0) {
        RegModule* module = & RegisteredModules[--NumRegisteredModules];
        if (module->CelsMain)       module->CelsMain (module->dll, CELS_UNLOAD_MODULE,0, NULL,0, NULL,0, NULL,(CelsCallback*)Cels);
        if (module->method_name)    free (module->method_name);
        if (module->dll)            DllUnload (module->dll);
    }
    free(RegisteredModules);
    RegisteredModules = NULL;
    MaxRegisteredModules = 0;
}


// ****************************************************************************************************************************
// Providing actual services **************************************************************************************************
// ****************************************************************************************************************************

// Execute global service;
// or execute service on parsed method;
// or parse string method, execute service and optionally unparse (only for SET_PARAM services) modified method to (outbuf,outsize)
CelsResult Cels (const void* method_str, int service, CelsNum subservice, void* inbuf, CelsNum insize, void* outbuf, CelsNum outsize, void* ud, CelsCallback* cb)
{
    // First, serve global services
    if (service==CELS_REGISTER) {
        return CelsRegister ((const char*)inbuf, ud,(CelsFunction*)cb);  // Register codec with name:=inbuf, CelsMain:=cb(ud...)
    }
    else if (service==CELS_LOAD) {
        return CelsLoad();
    }
    else if (service==CELS_UNLOAD) {
        CelsUnload();
        return CELS_OK;
    }

    // Then, try to process it as parsed method
    CELS_CODEC_INSTANCE* instance = (CELS_CODEC_INSTANCE*) method_str;
    if (*(char*)instance == 0)   return CallCels (instance, service,subservice, inbuf,insize, outbuf,outsize, ud,cb);

    // And finally, parse method string, execute the service on the parsed method and unparse it back if necessary
    char method[CELS_MAX_PARSED_METHOD_SIZE];
    CelsResult errcode_or_size = CelsParseStr ((const char*) method_str,
                                               service==CELS_PARSE? outbuf : method,
                                               service==CELS_PARSE? outsize : sizeof(method),
                                               ud, cb);

    if (errcode_or_size < CELS_OK) {
        return errcode_or_size;  // error code
    }
    else if (service==CELS_PARSE)  {
        // Return size of parsed method structure (the structure itself was stored to the outbuf)
        return errcode_or_size;
    }
    else {
        int set_param  =  IS_CELS_SET_INSTANCE_PARAM_SERVICE(service);

        // Run requested service on the parsed method
        CelsResult result = CallCels (method, service,subservice,
                                      inbuf, insize,
                                      set_param? NULL : outbuf,
                                      set_param?    0 : outsize,
                                      ud, cb);

        // Unparse for "set parameter" services
        if (result >= CELS_OK  &&  outbuf && outsize > 0  &&  set_param) {
            CelsResult errcode = CallCels (method, CELS_UNPARSE,CELS_UNPARSE_FULL, NULL,0, outbuf,outsize, ud,cb);
            if (errcode < CELS_OK)   result = errcode;
        }

        // Free any memory allocated by the parsed method. Returned error code is silently ignored.
        CallCels (method, CELS_FREE,0, NULL,0, NULL,0, NULL,(CelsCallback*)Cels);
        return result;
    }
}

// English description for error code
const char* CelsErrorMessage (CelsResult errcode)
{
    if (errcode == CELS_OK)                             return "ALL RIGHT";
    if (errcode == CELS_ERROR_GENERAL)                  return "Some error when (de)compressing";
    if (errcode == CELS_ERROR_INVALID_COMPRESSOR)       return "Invalid compression method or parameters";
    if (errcode == CELS_ERROR_ONLY_DECOMPRESS)          return "Program was compiled with CELS_DECOMPRESS_ONLY, so don't try to use compression functions";
    if (errcode == CELS_ERROR_OUTBLOCK_TOO_SMALL)       return "Output block size in (de)compressMem is not enough for all output data";
    if (errcode == CELS_ERROR_NOT_ENOUGH_MEMORY)        return "Can't allocate memory needed for (de)compression";
    if (errcode == CELS_ERROR_READ)                     return "Error when reading data";
    if (errcode == CELS_ERROR_BAD_COMPRESSED_DATA)      return "Data can't be decompressed";
    if (errcode == CELS_ERROR_NOT_IMPLEMENTED)          return "Requested feature isn't supported";
    if (errcode == CELS_ERROR_NO_MORE_DATA_REQUIRED)    return "Required part of data was already decompressed";
    if (errcode == CELS_ERROR_OPERATION_TERMINATED)     return "Operation terminated by user";
    if (errcode == CELS_ERROR_WRITE)                    return "Error when writing data";
    if (errcode == CELS_ERROR_BAD_CRC)                  return "File failed CRC check";
    if (errcode == CELS_ERROR_BAD_PASSWORD)             return "Password/keyfile failed checkcode test";
    if (errcode == CELS_ERROR_BAD_HEADERS)              return "Archive headers are corrupted";
    if (errcode == CELS_ERROR_INTERNAL)                 return "It should never happen: implementation error. Please report this bug to developers!";
    else                                                return "Unknown error";
}


// ****************************************************************************************************************************
// Extensions (these functions aren't required for CELS functioning and use only official API,                                *
//   so it's a sort of 3rd-party code, shipped with the library)                                                              *
// ****************************************************************************************************************************

// ****************************************************************************************************************************
// (De)compress data from memory buffer (input) to another memory buffer (output).                                            *
// When inbuf and/or outbuf is NULL, read/write data via CELS_READ/CELS_WRITE callbacks.                                      *
// ****************************************************************************************************************************

// Internal structure keeping read/write buffer positions for in-memory (de)compression operations
typedef struct
{
    char    *readPtr;           // current read position in inbuf (or NULL for redirecting reads to the original callback)
    size_t   readLeft;          // remaining bytes in the inbuf
    char    *writePtr;          // current write position in outbuf (or NULL for redirecting writes to the original callback)
    size_t   writeLeft;         // remaining bytes in the outbuf
    void    *userdata;          // data passed to the original callback
    CelsCallback* callback;     // original callback to serve all other requests
} CelsMemBuf;

// Callback emulating CELS_READ/CELS_WRITE for in-memory (de)compression operations
static CelsResult __cdecl CelsReadWriteMem (void* self, int service, CelsNum subservice, void* inbuf, CelsNum insize, void* outbuf, CelsNum outsize, void* ud, CelsCallback0* cb)
{
    CelsMemBuf *membuf = (CelsMemBuf*)self;
    if (service==CELS_READ  &&  membuf->readPtr)
    {
        // Copy data from readPtr to inbuf and advance the read pointer
        size_t read_bytes = membuf->readLeft<insize ? membuf->readLeft : insize;
        memcpy (inbuf, membuf->readPtr, read_bytes);
        membuf->readPtr  += read_bytes;
        membuf->readLeft -= read_bytes;
        return read_bytes;
    }
    else if (service==CELS_WRITE  &&  membuf->writePtr)
    {
        // Copy data from outbuf to writePtr and advance the write pointer
        if (outsize > membuf->writeLeft)  return CELS_ERROR_OUTBLOCK_TOO_SMALL;
        memcpy (membuf->writePtr, outbuf, outsize);
        membuf->writePtr  += outsize;
        membuf->writeLeft -= outsize;
        return outsize;
    }
    else
    {
        // All unhandled requests are passed to the original callback
        return (membuf->callback? membuf->callback (membuf->userdata, service,subservice, inbuf,insize, outbuf,outsize, ud,cb)
                                : CELS_ERROR_NOT_IMPLEMENTED);
    }
}

// Compress buffer (inbuf,insize) into buffer (outbuf,outsize) and return compressed size or error_code<0.
// When inbuf and/or outbuf is NULL, read/write data via CELS_READ/CELS_WRITE callbacks.
CelsResult CelsCompressMem (const void* method, void* inbuf, CelsNum insize, void* outbuf, CelsNum outsize, void* ud, CelsCallback* cb)
{
    CelsResult result = Cels(method, CELS_COMPRESS,0, inbuf,insize, outbuf,outsize, ud,cb);
    if (result != CELS_ERROR_NOT_IMPLEMENTED) {
        return result;
    } else {
        CelsMemBuf membuf = {(char*)inbuf,(size_t)insize, (char*)outbuf,(size_t)outsize, ud,cb};
        result = CelsCompress (method, &membuf, CelsReadWriteMem);
        // Return error code or number of bytes written to the buffer
        return result<CELS_OK ? result : outsize-membuf.writeLeft;
    }
}

// Decompress buffer (inbuf,insize) into buffer (outbuf,outsize) and return decompressed size or error_code<0.
// When inbuf and/or outbuf is NULL, read/write data via CELS_READ/CELS_WRITE callbacks.
CelsResult CelsDecompressMem (const void* method, void* inbuf, CelsNum insize, void* outbuf, CelsNum outsize, void* ud, CelsCallback* cb)
{
    CelsResult result = Cels(method, CELS_DECOMPRESS,0, inbuf,insize, outbuf,outsize, ud,cb);
    if (result != CELS_ERROR_NOT_IMPLEMENTED) {
        return result;
    } else {
        CelsMemBuf membuf = {(char*)inbuf,(size_t)insize, (char*)outbuf,(size_t)outsize, ud,cb};
        result = CelsDecompress (method, &membuf, CelsReadWriteMem);
        // Return error code or number of bytes written to the buffer
        return result<CELS_OK ? result : outsize-membuf.writeLeft;
    }
}
