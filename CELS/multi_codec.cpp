#include <stdio.h>  // only for debugging
#include "CELS.h"

CelsResult __cdecl CelsMain (void* self, int service, CelsNum subservice, void* inbuf, CelsNum insize, void* outbuf, CelsNum outsize, void* ud, CelsCallback* cb)
{
    switch (service)
    {
    case CELS_PARSE:
        {
            return 0;
        }

    case CELS_COMPRESS:
    case CELS_DECOMPRESS:
        {
            char buf[4096];
            while (CelsResult len = CelsRead (cb,ud, buf,4096))
            {
                if (len<0)  return len;  // Return errcode on error
                int result = CelsWrite (cb,ud, buf,len);
                if (result != len)  return result<0? result : CELS_ERROR_WRITE;
            }
            return CELS_OK;
        }

    default:
        return CELS_ERROR_NOT_IMPLEMENTED;
    }
}

// Register CELS compressor from DLL
CelsResult __cdecl CelsInit (int service, void* ud, CelsInitCallback* cb)
{
    if (service==CELS_LOAD_MODULE) {
        cb (ud, CELS_REGISTER, NULL, NULL, "test", CelsMain, NULL /*self*/, 0);
    }
    else return CELS_NOT_IMPLEMENTED;
}

#ifdef CELS_REGISTER_CODECS
static CelsResult dummy = CelsInit (CELS_LOAD, NULL, CelsInitCB);
#endif
