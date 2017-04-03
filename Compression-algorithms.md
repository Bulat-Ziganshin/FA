### MM
MM algo detects and preprocesses "multimedia" data  i.e. raw (uncompressed) audio and bitmap data, such as WAV and BMP file formats. It can apply only one method to entire solid block, so this method probably should be used with solid compression disabled. Parameters:
- d# - detection speed mode (1 - fastest, 9 - most accurate)
- s  - skip WAV header detection
- f  - floating-point data format
- c# - channels count
- w# - word size, in bits (8/16)
- o# - offset of MM data in file (=header size)
- r# - reorder data. -r1 - reorder bytes, -r2 - reorder words (unfinished!)
- c\*w - use c channels w bits each (example: 3*8)
- o+c\*w - use c channels w bits each starting from offset o

### ZSTD
FA incorporates ZSTD 1.1, and shipped fa.ini replaces Tornado with ZSTD in -m1/m2 modes.

Example of compression method with all parameters specified: `zstd:19:d4m:c1m:h4m:l16:b4:t64:s7`.

Description of all parameters:
- :19  = compression level (profile), 1..22 : larger == more compression
- :d4m = dictionary size in bytes, AKA largest match distance : larger == more compression, more memory needed during compression and decompression
- :c1m = fully searched segment : larger == more compression, slower, more memory (useless for fast strategy)
- :h4m = hash size in bytes : larger == faster and more compression, more memory needed during compression
- :l16 = chain length, AKA number of searches : larger == more compression, slower
- :b4  = minimum match length : larger == faster decompression, sometimes less compression
- :t64 = target length AKA fast bytes - acceptable match size (only for optimal parser AKA btopt strategy) : larger == more compression, slower
- :s7  = parsing strategy: fast=1, dfast=2, greedy=3, lazy=4, lazy2=5, btlazy2=6, btopt=7

By default, compression level parameter is set to 1, and other parameters are set to 0, that means "use default values as specified in the [table](https://github.com/facebook/zstd/blob/v1.1.0/lib/compress/zstd_compress.c#L3044)".
