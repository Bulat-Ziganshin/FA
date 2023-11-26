#include "ProtoBufDecoder.cpp"
#include "Example.pb.cpp"

void main()
{
    ProtoBufDecoder pb(buf,size);
    filter.ProtoBufDecode(pb);
    if(pb.error)
        abort("Internal error: " + pb.error_message());
}
