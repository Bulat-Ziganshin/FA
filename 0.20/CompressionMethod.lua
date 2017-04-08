--[[ **********************************************************************************************************************************
*** Handling full method definition like "1x/$wav=tta/$bmp=grzip" *********************************************************************
*************************************************************************************************************************************]]
-- Split string with full method definition into a list of {group,method} pairs
function split_full_method(method, location)
    method = method:split('/')
    local m = { {'', method[1] or ''} }             -- first segment is a default compression method, so it doesn't carry a group name
    for i = 2, #method do
        local group,algo = method[i]:split2('=')    -- other segments should be of form "$group=method"
        if not algo then
            assert (i==2, "No '=' in subgroup '"..method[i].."' in "..location)
            -- The only exception is second segment, since "tor/ppmd/..." is treated as "exe+tor / $obj=tor / $text = ppmd / ...."
            m = { {'','exe+'..method[1]},  {'$obj',method[1]},  {'$text',method[2]} }
        else
            if group:sub(1,1) ~= '$'  then group = '$'..group end  -- add '$' to group name if necessary
            table.insert (m, {group,algo})
        end
    end
    return m
end

-- Join list of {group,method} pairs into string describing a full method
function join_full_method(method)
    local m = {method[1][2]}            -- first element is a default compression method, so it doesn't need a group name
    for i = 2, #method do
        if method[i][2] > '' then       -- '1$wav=' means "remove $wav group", so these files will be compressed by default compression method
            table.insert (m, method[i][1]..'='..method[i][2])
        end
    end
    return table.concat(m,'/')
end

-- Remove groups whose compression method is defined as empty string
function remove_empty_groups (method)
    local m = {method[1]}
    for i = 2, #method do
        if method[i][2] > '' then
            table.insert (m, method[i])
        end
    end
    return m
end

-- Leave only last group from multiple groups with same name
function remove_dup_groups (method)
    local m = { method[1] }
    for i = 2, #method do
        local group = method[i][1]
        if group == '$default'  then
            m[1][2] = method[i][2]
        else
            -- Remove previous group with the same name
            local index = tablex.find_if (m,  function(item)  return item[1]==group  end)
            if index then table.remove(m,index) end
            table.insert (m, method[i])
        end
    end
    return m
end


--[[ **********************************************************************************************************************************
*** 'Set compression method (-m)' option implementation *******************************************************************************
*************************************************************************************************************************************]]

-- Select submethod from "x|y|z|..." according to num_cpus, including recursive applications of form "...(x|y|z|..)..."
function select_by_cpus (method, num_cpus)
    method = method:gsub('%b()', function(found)
                return select_by_cpus (found:sub(2,-2), num_cpus)
             end)
    local x = stringx.split(method,'|')
    -- Find last non-empty value, if value for num_cpus is empty or absent
    for i = num_cpus, 1, -1 do
        if (x[i] or '') ~= '' then return x[i] end
    end
    return ''
end

-- Add preprocessed line to the intermediate array
local function Add (arr, src, dst, location)
    table.insert (arr,  {src, split_full_method(dst,location)})
end

-- Add preprocessed line to the substitution maps
local function FinishAdd (line)
    local src,dst = line[1], line[2]
    main_methods[src] = dst
    local method,group = src:match('(.*)($.*)')
    if group then                                 -- if method name is like "1x$wav" or just "$wav"
        local a  =  extra_methods[method] or {}   --   extra_methods['1x'] += {'$wav',method}
        table.insert (a,  {group, dst[1][2]})
        extra_methods[method] = a
    end
end

function SetupCompressionMethods (config, config_file, num_cpus)
    if num_cpus then
        local high_priority, low_priority = {},{}
        for orig in stringx.lines(config) do
            local s = orig:gsub('%s',''):gsub(';.*','')   -- remove spaces and comments
            if s > '' then                                -- skip empty/comment lines
                local location = "line '"..orig.."' from "..config_file
                local src,dst = s:split2('=')
                assert(dst, "No '=' in "..location)
                src = select_by_cpus (src, num_cpus)
                dst = select_by_cpus (dst, num_cpus)
                if src:match('#') then      -- if left part contains '#', replace it with 9 lines mapping '#' to 1..9
                    for i=1,9 do
                        Add (low_priority, src:gsub('#',i), dst:gsub('#',i), location)
                    end
                else
                    Add (high_priority, src, dst, location)
                end
            end
        end
        -- Add each pair to mapping so that high-priority mappings override low-priority ones
        tablex.foreach (low_priority,  FinishAdd)
        tablex.foreach (high_priority, FinishAdd)
    else
        -- Save all method definitions to array since we can't process them before num_cpus is known
        method_definitions:append {config, config_file}
    end
end
method_definitions = List.new()

-- Substitute method name for single compressor
local function DecodeCompressor (compressor)
    local name, params = split_compressor_name(compressor)
    local subst = main_methods[name]
    -- if there is a substitution, we use only its main part
    return (subst and join_compressor_name (DecodeMethod(subst[1][2]), params)
                  or  compressor)
end

-- Substitute for all compressors in the chain and canonize results
function DecodeMethod (method)
    return canonize_method (join_method (tablex.map (DecodeCompressor, split_method (method))), false)
end


-- Recursively substitute main method in full method definition
local function DecodeMainMethod (full_method)
    local method = full_method[1][2]
    -- Auxiliary group definitions (like 1x$wav=mm) have lower priority than explicit groups, thus inserted at position 2
    tablex.insertvalues (full_method, 2, (extra_methods[method] or {}))
    -- Replace first element with main method defintion
    local main = main_methods[method]
    if main then
        table.remove (full_method, 1)
        tablex.insertvalues (full_method, 1, DecodeMainMethod(main))  -- recursively process first element of the main defintion
    end
    return full_method
end

-- Add permanent group definitions like "$wav=method" before any other groups since they have lowest priority
local function AddPermanentGroups (full_method)
    return tablex.insertvalues (full_method, 2, (extra_methods[''] or {}))
end

-- Substitute full method definition including groups as provided in cmdline
function DecodeFullMethod (method, location)
    method = remove_dup_groups (AddPermanentGroups (DecodeMainMethod (split_full_method (method, location))))
    for _,m in ipairs(method) do
        m[2] = DecodeMethod (m[2])
    end
    return remove_empty_groups(method)
end


AddOption{'method', '-mMETHOD --method=METHOD', 'set compression method',
function (param)  -- Parsing function
    param = param:gsub('%s',''):gsub('^=', '', 1)
    if param:sub(1,1) == '$' then
        optvalue.method:append (param)
    else
        optvalue.method[1] = param
    end
end,

post_priority = HIGHEST_PRIORITY,  -- it should be handled before any options modifying the compression method
post_processing = function()
    main_methods = {}
    extra_methods = {}
    local num_cpus = command.deduplication_mode and 1 or command.num_threads
    for x in method_definitions:iter() do
        SetupCompressionMethods (x[1], x[2], num_cpus)
    end

    local x = DecodeFullMethod (optvalue.method:concat('/'), 'option -m')
    local C = require 'pl.comprehension' . new()
    command.compression_groups  = C'x[1] for x'(x)
    command.compression_methods = C'x[2] for x'(x)
end}
optvalue.method = List.new {DEFAULT_COMPRESSION_METHOD}


AddOption{"dirmethod", "-dmMETHOD  --dirmethod=METHOD", "compression method for archive directory",
OPTION_STRING,
post_priority = HIGH_PRIORITY,
post_processing = function(method)
    local is_multi = is_multi_method(method)
    method = DecodeFullMethod (method, 'option -dm')
    method = method[1][2]   -- Extract compression method of main group
    -- Extract last compressor from the chain for options like -dm9;
    -- keep full method only if source method string was multi-method like -dm=delta+lzma
    command.directory_compressor  =  is_multi and method or last_compressor(method)
end}



builtin_config_file = [[
;You can insert these lines into your FA.INI

[Compression methods]
;High-level method definitions
x  = 9            ;highest compression mode using only internal algorithms
ax = 9p           ;highest compression mode involving external compressors
0  = storing
1  = 1b
1x = 1
#  = #rep+#exe+#xb / $obj=#b / $text=#t
#x = #exe+#xb / $obj=#xb / $text=#xt

;Family of methods providing fast but memory-hungry decompression: -m1d, -m2d...
#d = #rep+#exe+#xb / $obj = #b / $text = #xt / $compressed = #$compressed / $wav = #x$wav / $bmp = #x$bmp

;Family of methods providing memory-efficient but slow decompression: -m1a, -m2a...
#a = #exe+#xb / $obj = #xb / $text = #t / $compressed = #x$compressed / $wav = #$wav / $bmp = #$bmp

;Text files compression with slow decompression
1t  = 1xt
2t  = grzip:m4:8m:32:h15                                             | ex2t
3t  = dict:p: 64m:85% + lzp: 64m: 24:h20        :92% + grzip:m3:8m:l | ex3t
4t  = dict:p: 64m:80% + lzp: 64m: 65:d1m:s16:h20:90% + ppmd:8:96m    | ex4t
5t  = dict:p: 64m:80% + lzp: 80m:105:d1m:s32:h22:92% + ppmd:12:192m  | ex5t
#t  = dict:p:128m:80% + lzp:160m:145:d1m:s32:h23:92% + ppmd:16:384m

;Binary files compression with slow and/or memory-expensive decompression
#b  = #rep + #bx
1rep  = rep: 512m:512:c512
2rep  = rep: 512m:256:c256
3rep  = rep: 512m
4rep  = rep: 512m
5rep  = rep: 512m
6rep  = rep: 512m
7rep  = rep: 512m
8rep  = rep:1024m
9rep  = rep:2040m

;Text files compression with fast decompression
1xt = 1binary
2xt = 2binary
3xt = dict:  64m:80% + 3binary:32m
4xt = dict:  64m:75% + 4binary:32m
#xt = dict: 128m:75% + #binary

;Binary files compression with fast decompression
1xb = 1binary
2xb = 2binary
#xb = delta + #binary

;Binary files compression with fast decompression
1binary = tor:3:8mb                   | ex1binary
2binary = tor:5                       | ex2binary
3binary = lzma: 96m:fast  :32:mc4     | ex3binary
4binary = lzma: 96m:normal:16:mc8   | | ex4binary
5binary = lzma: 96m:normal:128:mc32 | | ex5binary
6binary = lzma: 32m:max
7binary = lzma: 64m:max
8binary = lzma:128m:max
9binary = lzma:254m:max

;x86 executable preprocessing
1exe = exe
2exe = exe
3exe = exe
#exe = exe2

;Synonyms
bcj = exe
#bx = #xb
#tx = #xt
x#  = #x    ;accept options like -mx7 in order to mimic the 7-zip
copy = storing
exe2 = dispack
dispack = dispack070

;ZSTD shortcuts
z = zstd
xz = 4x4:zstd
ez = z|xz
rxz = 1rep+xz
rexz = 1rep+exe+xz


;Sound wave files are best compressed with TTA
wav     = tta      ;best compression
wavfast = tta:m1   ;faster compression and decompression
1$wav  = ;;; wavfast | bmpfastest
2$wav  = wavfast
#$wav  = wav
1x$wav = ;;; wavfast | bmpfastest
#x$wav = wavfast

;Bitmap graphic files are best compressed with GRZip
bmp        = mm    + grzip:m1:l2048:a  ;best compression
bmpfast    = mm    + grzip:m4:l:a      ;faster compression
bmpfastest = mm:d1 + 1binary:t0        ;fastest one
1$bmp  = ;;; bmpfastest
2$bmp  = bmpfastest | bmpfast
3$bmp  = bmpfast    | bmp
#$bmp  = bmp
1x$bmp = ;;; bmpfastest
2x$bmp = bmpfastest
#x$bmp = mm+#binary

;Quick & dirty compression for already compressed data
1$compressed   = storing | 1rep
2$compressed   = 2rep + 1binary
3$compressed   = 3rep + 1binary
4$compressed   = 4rep + etor:c3
#$compressed   =

1x$compressed  = storing | 1rep
2x$compressed  = 2rep:8m + 1binary
3x$compressed  = 3rep:8m + 1binary
4x$compressed  = etor:8m:c3
#x$compressed  =

;LZ4 support
xlz4   = 4x4:lz4
elz4   = (|x)lz4
lz4hc  = lz4:hc
xlz4hc = xlz4:hc
elz4hc = (|x)lz4hc


;Multi-threading compression modes
xtor  = 4x4:tor
xlzma = 4x4:lzma
xppmd = 4x4:b7mb:ppmd
etor  = (|x)tor
elzma = (|x)lzma
eppmd = (|x)ppmd

ex1 = ex1b / $wav=mm:d1+ex1b:t0 / $bmp=mm:d1+ex1b:t0 / $compressed = 1$compressed
ex# = #rep+#exe+ex#b / $obj=#rep+ex#b / $text=ex#t / $wav = #$wav / $bmp = #$bmp / $compressed = #$compressed
#ex = ex#

ex1b = ex1binary
ex2b = ex2binary
ex#b = delta + ex#binary

ex1binary = xtor:3:8mb
ex2binary = xtor:5
ex3binary = xlzma:96mb:fast  :32:mc4
ex4binary = xlzma:96mb:normal:16:mc8
ex5binary = xlzma:96mb:normal:128:mc32
ex6binary = 4x4:i0:lzma: 8mb:max
ex7binary = 4x4:i0:lzma:16mb:max
ex8binary = 4x4:i0:lzma:32mb:max
ex9binary = 4x4:i0:lzma:64mb:max

ex1t = ex1b
ex2t = grzip:m4
ex3t = grzip:m2
ex4t = grzip:m1   ;or dict:p:64m:80% + lzp:8m:45:d1m:s16:h15:92% + xppmd:6:48m
ex5t = dict:p: 64m:80% + lzp: 64m: 65:d1m:s32:h22:90% + xppmd:8:96m
ex6t = dict:p: 64m:80% + lzp: 80m:105:d1m:s32:h22:92% + xppmd:12:192m
ex#t = dict:p:128m:80% + lzp:160m:145:d1m:s32:h23:92% + xppmd:16:384m
]]
