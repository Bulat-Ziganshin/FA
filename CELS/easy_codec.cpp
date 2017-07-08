// Simple codec template may be used for parameter-less codec loaded from dynamic library (dll/so/dynlib)
#include <stdio.h>  // only for debugging
#include "CELS.h"

CelsResult __cdecl CelsMain (void* self, int service, CelsNum subservice, void* inbuf, CelsNum insize, void* outbuf, CelsNum outsize, void* ud, CelsCallback* cb)
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
                int result = CelsWrite (cb,ud, buf,len);
                if (result != len)  return result<CELS_OK? result : CELS_ERROR_WRITE;
            }
            return CELS_OK;
        }

    default:
        return CELS_ERROR_NOT_IMPLEMENTED;
    }
}

#ifdef CELS_REGISTER_CODECS
static CelsResult dummy = CelsRegister ("test", NULL, CelsMain);
#endif
