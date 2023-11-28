const char* USAGE =
"Generator of C++ decoder from compiled ProtoBuf schema\n"
"  Usage: generator file.pbs\n";

#include <string>
#include <cctype>
#include <iostream>
#include <fstream>
#include <iterator>

#include "ProtoBufDecoder.cpp"
#include "descriptor.pb.cpp"


int main(int argc, char** argv)
{
    if (argc != 2) {
        printf(USAGE);
        return 1;
    }

    std::ifstream ifs(argv[1], std::ios::binary);
    std::string str(std::istreambuf_iterator<char>{ifs}, {});

    try {
        printf("=== Filesize = %d\n", str.size());
        ProtoBufDecoder pb(str);

        FileDescriptorSet proto;
        proto.ProtoBufDecode(pb);
        printf("=== Decoding succeed!\n");

        auto file = proto.file[0];
        std::cout << file.name << "\n";

        for (auto message_type: file.message_type)
        {
            std::cout << message_type.name << "\n";

            for (auto field: message_type.field)
            {
                std::cout << "  " << field.name
                    << (field.has_default_value? " = " + std::string(field.default_value) : "")
                    << "\n";
            }
        }
    } catch (const std::exception& e) {
        printf("Internal error: %s\n", e.what());
    }

    return 0;
}
