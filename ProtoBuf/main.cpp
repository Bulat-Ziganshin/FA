#include "ProtoBufDecoder.cpp"
#include "Example.pb.cpp"

void main()
{
    try {
        ProtoBufDecoder pb(buf,size);
        filter.ProtoBufDecode(pb);
    } catch (const std::exception& e) {
        abort("Internal error: " + e.what());
    }
}
