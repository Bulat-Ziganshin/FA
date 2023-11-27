#include "ProtoBufDecoder.cpp"
#include "Example.pb.cpp"

int main()
{
    try {
        Filter filter;
        ProtoBufDecoder pb("data");
        filter.ProtoBufDecode(pb);
        printf("Decoding succeed!\n");
    } catch (const std::exception& e) {
        printf("Internal error: %s\n", e.what());
    }
    return 0;
}
