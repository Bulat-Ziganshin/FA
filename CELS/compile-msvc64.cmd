@call "C:\Program Files (x86)\Microsoft Visual Studio 12.0\VC\vcvarsall.bat" x86_amd64
cl -O2 /EHsc simple_host.cpp simple_codec.cpp -o simple_host_with_simple_codec.exe
link -DLL -DEF:cls-test.def -out:cls-test.dll simple_codec.obj
