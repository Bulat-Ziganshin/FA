#include <stdio.h>
#include "CELS.h"

CelsResult __cdecl ReadWrite (void* self, int service, CelsNum subservice, void* inbuf, CelsNum insize, void* outbuf, CelsNum outsize, void* ud, CelsCallback0* cb)
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
