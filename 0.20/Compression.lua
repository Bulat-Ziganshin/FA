--[[ **********************************************************************************************************************************
*** Handling compression method strings ***********************************************************************************************
*************************************************************************************************************************************]]
DEFAULT_COMPRESSION_METHOD = '4'
NO_COMPRESSION       = 'storing'
FAKE_COMPRESSION     = 'fake'
CRC_ONLY_COMPRESSION = 'crc'
BUFFERING_COMPRESSOR = 'tempfile'

function split_method(method)
    return split(method,'+')
end

function join_method(compressors)
     return table.concat(compressors,'+')
end

function is_multi_method(method)
    return method:find('+', 1, true)
end

function last_compressor(method)
    return method:gsub('.*%+', '')
end

function split_compressor(compressor)
    return split(compressor,':')
end

function join_compressor(params)
     return table.concat(params,':')
end

function split_compressor_name(compressor)
    return compressor:match('([^:]*)(.*)')  -- return name and :params
end

function join_compressor_name (name, params)
     return name..params
end

function get_compressor_name(compressor)
    return compressor:match('([^:]*)')
end

-- Return value of specified parameter from compression/encryption algo
function get_param (method, param)
    return method:match(":"..param.."([^:]+)")
end

-- Remove specified parameter from compression/encryption algo
function remove_param (method, param)
    return (method:gsub(":"..param.."[^:]+",""))
end

function canonize_compressor (compressor, ...)
    local success, result = pcall(CanonizeCompressor, compressor, ...)
    if success then return result
    else error('Invalid compression method: '..compressor)
    end
end

function canonize_method (method, ...)
    return join_method (tablex.map (canonize_compressor, split_method (method), ...))
end

function CompressionGet (method, name, param)
    return CompressionService(method, name, param or 0)
end

-- Check boolean property of compression method, returning FALSE if it's not implemented
function CompressionIs (method, name, param)
    return (CompressionService(method, name, param or 0) > 0)
end

for name in string.gmatch('GetMinCompressionMem GetAlgoMem GetMaxCompressedSize', '%S+') do
    _G[name] = function(method,param)  return CompressionService(method, name, param or 0) end
end
for name in string.gmatch('Dictionary BlockSize CompressionMem DecompressionMem MinDecompressionMem', '%S+') do
    local get_f, set_f, limit_f  =  'Get'..name, 'Set'..name, 'Limit'..name
    _G[get_f]   = function(method,param)  return CompressionService(method, get_f,   param or 0) end
    _G[set_f]   = function(method,param)  return CompressionModify (method, set_f,   param) end
    _G[limit_f] = function(method,param)  return CompressionModify (method, limit_f, param) end
end

-- Various max/sum summaries of all compressors in the method
function GetMaxOfDictionary         (method)   return List(split_method(method)):map(GetDictionary)         :reduce(max)  end
function GetSumOfDecompressionMem   (method)   return List(split_method(method)):map(GetDecompressionMem)   :reduce('+')  end
function GetSumOfCompressionMem     (method)   return List(split_method(method)):map(GetCompressionMem)     :reduce('+')  end
function GetSumOfMinDecompressionMem(method)   return List(split_method(method)):map(GetMinDecompressionMem):reduce('+')  end

-- Limit dictionaries of compressors in the method, stopping do that once we encountered the first compressor
-- that can inflate the data (such as precomp). There are no such algorithms among internal compressors,
-- but we suspect all external ones :)
function MethodLimitDictionary (method, dict)
    if dict and dict>0 then
        local cm = split_method(method)
        for i,compressor in ipairs(cm) do
            cm[i] = LimitDictionary (compressor, roundMemUp(dict))
            dict = dict*1.01 + 512   -- take into account that each compressor may slightly inflate the data
            if CompressionIs (compressor, "external?")  then break end
        end
        return join_method(cm)
    else
        return method
    end
end


--[[ **********************************************************************************************************************************
*** Handling compression groups *******************************************************************************************************
*************************************************************************************************************************************]]
-- Pass each compression group through filter_f(compression_method, group_name).
-- The first returned value, if not nil, assigned back to the compression method.
-- The second returned value, if not nil, assigned back to the group name.
-- Finally, groups having empty compression method are completely removed.
function MapCompressionGroups (filter_f, ...)
    local cmethods, cgroups = command.compression_methods, command.compression_groups
    cgroups[1] = '$default'

    -- Filter method/group through filter_f, removing groups whose compression method became empty
    local m,g = {},{}
    for i in ipairs(cgroups) do
        local method, group  = filter_f (cmethods[i], cgroups[i], ...)
        if method ~= '' then
            table.insert (m, method or cmethods[i])
            table.insert (g, group  or cgroups[i])
        end
    end

    g[1] = ''
    command.compression_methods, command.compression_groups = m, g
end

-- Remove compression groups satisfying `predicate_f`.
-- Alternatively, `predicate_f` may be just a string with name of group to remove.
function RemoveCompressionGroups (predicate_f, ...)
    if type(predicate_f)=='string' then
        local group_to_remove = predicate_f
        predicate_f = function(method,group) return group==group_to_remove end
    end
    local function filter_f (method, group, ...)
        return (predicate_f(method,group,...) and '' or nil)
    end
    MapCompressionGroups (filter_f, ...)
end

-- Add new compression group
function AddCompressionGroup (method, group)
    RemoveCompressionGroups(group)
    local g,m = command.compression_groups, command.compression_methods
    table.insert (g, group)
    table.insert (m, method)
    command.compression_groups, command.compression_methods = g, m
end


-- Map last compressor in the `method` through `filter_f`, removing it completely if result is empty string.
-- Nil returned from `filter_f` keeps the compressor intact.
function map_last_compressor (method, filter_f, ...)
    local cm = split_method(method)
    cm[#cm] = filter_f(cm[#cm],...) or cm[#cm]
    return join_method(cm)
end

-- Map each compressor in the `method` through `filter_f`, removing empty strings from result.
-- Nil returned from `filter_f` keeps the compressor intact.
function map_compressors (method, filter_f, ...)
    local cm = {}
    for old_compressor in string.gmatch(method, '[^+]+') do
        local new_compressor = filter_f (old_compressor, ...)
        if new_compressor ~= '' then
            table.insert(cm, new_compressor or old_compressor)
        end
    end
    return join_method(cm)
end

-- Remove from `method` compressors satisfying `predicate_f`.
-- Alternatively, `predicate_f` may be just a string with the name of compressor to remove.
function remove_compressors (method, predicate_f, ...)
    if type(predicate_f)=='string' then
        local compressor_to_remove = predicate_f
        predicate_f = function(compressor)  return get_compressor_name(compressor) == compressor_to_remove end
    end
    local function filter_f(compressor,...)
        return (predicate_f(compressor,...) and '' or compressor)
    end
    return map_compressors (method, filter_f, ...)
end


--[[ **********************************************************************************************************************************
*** 'Method change (-mc)' option implementation ***************************************************************************************
*************************************************************************************************************************************]]

AddOption{'method_change', '-mcDIRECTIVE', 'modify compressor: [$group1,$group2][:]-$group,-algo,+algo,algo1/algo2',
-- Parsing function
function(param)
    local action

    --mcd-: replace rar-compatible abbreviated directives with longer explicit ones
    local rarAbbrevs = {d="-delta", e="-exe", l="-lzp", r="-rep", z="-dict", a="-$wav", c="-$bmp", t="-$text"}
    param = rarAbbrevs[param:match('^(%a)%-$')] or param

    -- Split param into list of groups and operation to perform on these groups
    local groups,operation = param:match('^:?($.-)([:+-].+)$')
    if not groups then
        groups = ''
        operation = param
    end

    --mc:lzma/lzma:max:512mb
    local old_compressor,new_compressor = operation:match('^:?(.+)/([^$].*)$')
    if old_compressor   then action = function(env) env.replace_compressor(groups,old_compressor,DecodeMethod(new_compressor)) end  else
    --mc+precomp+xtor
    local new_compressor = operation:match('^:?%+(.+)$') or operation:match('^:?(.+)%+$')
    if new_compressor   then action = function(env) env.add_compressor(groups,DecodeMethod(new_compressor)) end  else
    --mc-$wav,$bmp
    local old_groups = operation:match('^:?%-($.+)$') or operation:match('^:?($.+)%-$')
    if old_groups and (groups=='')  then action = function(env) env.remove_groups(old_groups) end  else
    --mc-rep,lzp
    local old_compressor = operation:match('^:?%-(.+)$') or operation:match('^:?(.+)%-$')
    if old_compressor   then action = function(env) env.remove_compressor(groups,old_compressor) end  else
    --unrecognized
    return 'Bad option format'
    end end end end

    optvalue.method_change = optvalue.method_change or {}
    table.insert (optvalue.method_change, action)
end,

post_processing = function()
    local cgroups, cmethods = command.compression_groups, command.compression_methods
    cgroups[1] = '$default'

    -- Filter cmethods[i] through f if cgroup[i] is in the `groups` list or the list is empty
    local function filter_methods (groups, f)
        for i,group in ipairs(cgroups) do
            if groups==""  or  group:in_list(groups) then
                cmethods[i] = f(cmethods[i],group)
            end
        end
    end

    -- Filter through the f each compressor in the `groups`
    local function filter_compressors (groups, f)
        filter_methods (groups, function (method)
            local cm = {}
            for old_compressor in string.gmatch(method, "[^+]+") do
                local name = string.match (old_compressor..':', '^([^:]*):')
                local new_compressor = f(name,old_compressor)
                if new_compressor ~= "" then
                    table.insert(cm, new_compressor or old_compressor)
                end
            end
            return table.concat(cm,'+')
        end)
    end

    local env = {}
    function env.add_compressor(groups,compressor)
        filter_methods (groups, function(method)  return compressor..'+'..method; end)
    end
    function env.replace_compressor(groups,old_names,new_compressor)
        filter_compressors (groups, function(name)  if name:in_list(old_names) then return new_compressor end end)
    end
    function env.remove_compressor(groups,names)
        --mc-grzip removes groups like $bmp=mm+grzip where "grzip" is the last compressor in the chain
        filter_methods (groups, function(method,group)
            local compressors = split_method(method)
            if #compressors>0  and  group~='$default' then
                local last_compressor_name = get_compressor_name(compressors[#compressors])
                if last_compressor_name:in_list(names) then
                    compressors = {}
                end
            end
            return join_method(compressors)
        end)
        --mc-grzip also removes grzip from middle of compression chain
        filter_compressors (groups, function(name)  if name:in_list(names) then return "" end end)
    end
    function env.remove_groups(groups)
        filter_methods (groups, function() return "" end)
    end

    -- Modify the compressor by executing code built at the parsing stage
    for _,directive in ipairs(optvalue.method_change or {}) do
        directive(env)
    end

    -- Remove groups whose compression method became empty
    local g,m = {},{}
    cgroups[1] = ''
    for i,method in ipairs(cmethods) do
        if method > "" then
            table.insert (g, cgroups[i])
            table.insert (m, cmethods[i])
        end
    end
    command.compression_groups, command.compression_methods = g,m
end}


--[[ **********************************************************************************************************************************
*** Limit memory usage: -lc/-ld options ***********************************************************************************************
*************************************************************************************************************************************]]
MAX_RAM_USAGE = parse_phys_mem('75%')   -- by default, we limit memory usage to this value to ensure no disk trashing
MAX_FUTURE_DECOMPRESSION_MEM = parse_phys_mem('1600mb')    -- DECOMPRESSION memory limit applied for COMPRESSION operations to ensure that compressed data can be later extracted on 32-bit computers

function mem_limit_parser(param,name)
        if param=='-'  then  optvalue[name] = 0     -- no limit
    elseif param=='--' then  optvalue[name] = nil   -- back to default value
    else                     return try_parse_phys_mem(name,param,'m') end   -- parse as percents of RAM or fixed memory size
end

AddOption{'limit_cmem', '-lcN --LimitCompMem=N', 'limit memory usage for compression to N mbytes (or N% of RAM)',
mem_limit_parser}

AddOption{'limit_dmem', '-ldN --LimitDecompMem=N', 'limit memory usage for decompression to N mbytes (or N% of RAM)',
mem_limit_parser,
post_processing = function(name)
    if optvalue[name] ~= 0 then   -- -ld-/-ld0 means "skip corresponding checks entirely"
        onExtractBlockMethod ('LimitMemory', LOWEST_PRIORITY, LimitMemoryOnExtraction)
    end
end}


-- Apply memory constraints on the extraction stage
function LimitMemoryOnExtraction(method)
    -- In addition to -ld own value (by default 75% of RAM):
    -- 1) limit memory usage for "SparseDecompression?" methods to GetTotalMemoryToAlloc (i.e. total memory available for program)
    -- 2) limit memory usage for other methods to GetMaxBlockToAlloc (i.e. size of largest contiguous memory block available)
    local limit = optvalue.limit_dmem or MAX_RAM_USAGE

    -- If decompression mem is less than the limit, try to alloc that memory block instead of calculating TotalMemory/MaxBlock.
    -- If the allocation was successful, skip the full check.
    local dmem = GetSumOfDecompressionMem(method)
    if dmem < limit then
        if TryToAlloc(dmem) then
            return nil
        end
    end

    local maxmem   = min (limit, GetTotalMemoryToAlloc()-30*mb)  -- reserve 30 MB for the program itself :)
    local maxblock = min (limit, GetMaxBlockToAlloc())

    -- On decompression, algorithms are started (and thus allocate RAM) in reversed order,
    -- so in rep+lzma, REP allocates after LZMA and thus can utilize remaining sparse memory areas.
    -- This means that we should scan algorithms in reversed order to correctly check their accumulated memreqs
    local new_method,total_dmem = {},0
    for _,compressor in ipairs(table.reverse(split_method(method))) do
        if CompressionIs (compressor, "MemoryBarrierDecompression?") then
            total_dmem = 0
        else
            -- For sparse decompression algorithms (such as REP) we need to check only total memory amount,
            -- while for other algorithms we ensure that all decompressors together can fit into the largest contiguous memory block available
            local limit_dmem = CompressionIs(compressor,"SparseDecompression?") and maxmem or maxblock
            local dmem       = GetDecompressionMem(compressor)

            -- Limit the compressor if it needs too much memory (by reducing number of threads so we don't lose compatibility with those compressed data)
            if dmem > limit_dmem then
                compressor = LimitDecompressionMem(compressor, limit_dmem)
                dmem       = GetDecompressionMem(compressor)
            end

            -- If total memreqs of methods after last barrier exceeds limit_dmem,
            -- then add one more "tempfile" occurence prior to the current compressor
            if total_dmem>0 and dmem>0 and total_dmem+dmem>limit_dmem then
                table.insert (new_method, BUFFERING_COMPRESSOR)
                total_dmem = 0
            end
            total_dmem = total_dmem + dmem
        end
        table.insert (new_method, compressor)
    end

    return join_method (table.reverse (new_method))
end

-- Apply memory constraints on the compression stage
onCompressBlockMethod ('LimitMemory', LOWEST_PRIORITY, function(method, is_header, blocksize)
    -- First, reduce blocksize/dictionary if block contains less data.
    -- This may reduce memory usage so that it will start to fit into -lc/ld constraints
    if blocksize==0  then blocksize=1 end
    method = MethodLimitDictionary (method, blocksize)

    -- Maximum memory allowed for compression and later decompression
    local limit_cmem  =  optvalue.limit_cmem or MAX_RAM_USAGE
    local limit_dmem  =  optvalue.limit_dmem or MAX_FUTURE_DECOMPRESSION_MEM

    -- Limit memory usage to GetMaxBlockToAlloc (i.e. size of largest contiguous memory block available)
    -- in addition to -lc own value (by default 75% of RAM), unless -lc- is given
    if limit_cmem > 0 then
        -- If compression mem is less than the limit, try to alloc that memory block instead of calculating MaxBlock.
        -- If the allocation was successful, disable the limit_cmem check, so only limit_dmem check remains.
        local cmem = GetSumOfCompressionMem(method)
        if cmem < limit_cmem then
            if TryToAlloc(cmem) then
                limit_cmem = 0
                goto cmem_is_enough  -- skip slow GetMaxBlockToAlloc() call
            end
        end
        limit_cmem  =  min (limit_cmem, GetMaxBlockToAlloc())
        ::cmem_is_enough::
    end

    -- Value of 0 (-lc-/-ld-) means "skip corresponding checks entirely"
    if limit_cmem==0 and limit_dmem==0  then return method end

    local new_method,total_cmem = {},0
    for _,compressor in ipairs(split_method(method)) do
        -- Limit dmem first to ensure that total_cmem will sum up final method settings
        if limit_dmem > 0 then
            compressor = LimitMinDecompressionMem(compressor, limit_dmem)
        end
        if limit_cmem > 0 then
            if CompressionIs (compressor, "MemoryBarrierCompression?") then
                total_cmem = 0
            else
                -- Reduce compressor if it needs too much memory for compression or decompression
                compressor = LimitCompressionMem (compressor, limit_cmem)
                local cmem = GetCompressionMem(compressor)

                -- If total memreqs of methods after last barrier exceeds limit_cmem,
                -- then add one more "tempfile" occurence prior to the current compressor
                if total_cmem>0 and cmem>0 and limit_cmem>0 and total_cmem+cmem>limit_cmem then
                    table.insert (new_method, BUFFERING_COMPRESSOR)
                    total_cmem = 0
                end
                total_cmem = total_cmem + cmem
            end
        end
        table.insert (new_method, compressor)
    end

    return join_method(new_method)
end)


--[[ **********************************************************************************************************************************
*** Remaining compression options *****************************************************************************************************
*************************************************************************************************************************************]]

AddOption{'dictionary', '-mdN --dictionary=N', 'set compression dictionary to N mbytes',
OPTION_MEGABYTES,
post_priority = LOW_PRIORITY,
post_processing = function(dictionary)
    MapCompressionGroups (function (method)
        return map_last_compressor (method, SetDictionary, dictionary)
    end)
end}

AddOption{'crc_only', '--crc-only --crconly', "save/check CRC, but don't store data",
OPTION_BOOL,
post_processing = function()
    command.compression_groups  = {""}
    command.compression_methods = {CRC_ONLY_COMPRESSION}
end}

-- In most cases, we don't want to use REP method when deduplication enabled
onPostOption ('RemoveREPonDeduplication', LOWEST_PRIORITY, function ()   -- when option parsing is done:
    if command.deduplication_mode then                         --   if -dup is enabled
        MapCompressionGroups (function (method)                --     go through each compression group, making changes to its compression method
            method = remove_compressors (method, "rep")        --       remove "rep" compressors from the compression method
            return (method=='' and NO_COMPRESSION or method)   --       if "rep" was the only compressor in the method, replace entire method with "storing"
        end)
    end
end)
