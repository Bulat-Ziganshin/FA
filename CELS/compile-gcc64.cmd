@path C:\Base\Compiler\MinGW-4.9.2\mingw64\bin;%path%
gcc -m64 -O3 -DCELS_REGISTER_CODECS CELS.cpp simple_host.cpp easy_codec.cpp -o simple_host_with_easy_codec64.exe
gcc -m64 -c -O3 easy_codec.cpp
dllwrap -m64 --driver-name c++ easy_codec.o -def cels-test.def -s -o cels64-test.dll
@del *.o
