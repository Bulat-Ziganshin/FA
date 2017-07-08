#include <stdio.h>  // only for debugging
#include "CELS.h"

// Structure representing parsed codec
struct MyCodec
{
    int level;
};

CelsResult __cdecl CelsMain (void* self, int service, CelsNum subservice, void* inbuf, CelsNum insize, void* outbuf, CelsNum outsize, void* ud, CelsCallback* cb)
{
    switch (service)
    {
    case CELS_PARSE:
        {
            MyCodec *codec = (MyCodec*)outbuf;
            codec->level = 5;
            return sizeof(MyCodec);
        }

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

            // Remaining services require callback
            if (!cb)  return CELS_ERROR_GENERAL;

            // Mixed mode: from inbuf to CelsWrite()
            if (inbuf)
            {
                int result = CelsWrite (cb,ud, inbuf,insize);
                if (result != insize)  return result<CELS_OK? result : CELS_ERROR_WRITE;
            }

            // Mixed mode: from CelsRead() to outbuf. We don't want to implement it.
            if (outbuf)  return CELS_ERROR_NOT_IMPLEMENTED;

            // Streaming compression: from CelsRead() to CelsWrite()
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
