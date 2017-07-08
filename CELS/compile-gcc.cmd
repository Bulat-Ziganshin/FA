@path C:\Base\Compiler\MinGW\bin;%path%
gcc -O3 CELS.cpp simple_host.cpp -o simple_host.exe
gcc -O3 -DCELS_REGISTER_CODECS CELS.cpp simple_host.cpp easy_codec.cpp -o simple_host_with_easy_codec.exe
gcc -c -O3 easy_codec.cpp
dllwrap --driver-name c++ easy_codec.o -def cels-test.def -s -o cels-test.dll
@del *.o
