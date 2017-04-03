This is the Lua startup code as included in FA 0.11. You can print actual version of this code by executing `fa --print-config`.

```lua
--[[ **********************************************************************************************************************************
*** Utility functions *****************************************************************************************************************
*************************************************************************************************************************************]]

kb,mb,gb,tb,pb = 1024, 1024^2, 1024^3, 1024^4, 1024^5

function wildcard2pattern(wildcard)
    return '^' .. wildcard:gsub('%p','%%%0'):gsub('%%%*','.*'):gsub('%%%?','.') .. '$'
end

function start_with(str,...)
    for _, substr in ipairs{...} do
        if str:sub(1,#substr) == substr then
            return str:sub(1+#substr)
        end
    end
end
string.start_with = start_with

function in_list(str,list,delim)
    delim = delim or ','
    return string.find (delim..list..delim, delim..str..delim, 1, true)
end
string.in_list = in_list

function table.map(xs,f)
    local result = {}
    for _,x in ipairs(xs) do
      table.insert (result, f(x))
    end
    return result
end

function split(str,sep)
    local t = {}
    for word in str:gmatch('([^'..sep..']+)') do
        table.insert(t,word)
    end
    return t
end
string.split = split


--[[ **********************************************************************************************************************************
*** Handling compression method strings ***********************************************************************************************
*************************************************************************************************************************************]]
function split_method(method)
    return split(method,'+')
end

function join_method(compressors)
     return table.concat(compressors,'+')
end

function split_compressor(compressor)
    return split(compressor,':')
end

function join_compressor(params)
     return table.concat(params,':')
end

function get_compressor_name(compressor)
    return split_compressor(compressor)[1]
end

for name in string.gmatch('GetCompressionMem GetMinCompressionMem GetDecompressionMem GetMinDecompressionMem GetDictionary GetBlockSize GetAlgoMem GetMaxCompressedSize', '%S+') do
    _G[name] = function(method,param) return CompressionService(method, name, param or 0) end
end
for name in string.gmatch('SetDictionary SetBlockSize SetCompressionMem SetDecompressionMem SetMinDecompressionMem', '%S+') do
    _G[name] = function(method,param) return CompressionModify(method,name,param) end
end

STORING              = "storing"
FAKE_COMPRESSION     = "fake"
CRC_ONLY_COMPRESSION = "crc"


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
        local removed_group = predicate_f
        predicate_f = function(method,group) return group==removed_group end
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


-- Map each compressor in the `method` through `filter_f`, removing empty strings from result.
-- Nil returned from `filter_f` keeps the compressor intact.
function map_compressors (method, filter_f, ...)
    local cm = {}
    for old_compressor in string.gmatch(method, '[^+]+') do
        local name = get_compressor_name (old_compressor)
        local new_compressor = filter_f (name, old_compressor, ...)
        if new_compressor ~= '' then
            table.insert(cm, new_compressor or old_compressor)
        end
    end
    return join_method(cm)
end

-- Remove from `method` compressors satisfying `predicate_f`.
-- Alternatively, `predicate_f` may be just a string with name of compressor to remove.
function remove_compressors (method, predicate_f, ...)
    if type(predicate_f)=='string' then
        local removed_name = predicate_f
        predicate_f = function(name) return name==removed_name end
    end
    local function filter_f (name, compressor, ...)
        return (predicate_f(name,compressor,...) and '' or compressor)
    end
    return map_compressors (method, filter_f, ...)
end


--[[ **********************************************************************************************************************************
*** Event handling machinery **********************************************************************************************************
*************************************************************************************************************************************]]
for cmd in string.gmatch('ProgramStart ProgramDone CommandStart CommandDone ArchiveStart ArchiveDone Error Warning Option PostOption FileFilter', '%S+') do
    local tabname = 'on'..cmd..'Handlers'

    local function addEventHandler(handler)
        if type(handler)=='string' then
            handler,errmsg = load('local string_match, start_with, bnot, bor, bxor, band, btest = string.match, start_with, bit32.bnot, bit32.bor, bit32.bxor, bit32.band, bit32.btest; return ('..handler..')')
            if handler   then handler = handler()   else print(errmsg) end
        end
        table.insert (_G[tabname], handler)
    end

    local function runEventHandlers(...)
        for _,handler in ipairs(_G[tabname]) do
            result = handler(...)
            if result then return result end
        end
    end

    _G[tabname] = _G[tabname] or {}
    _G['on'..cmd] = addEventHandler
    _G[cmd] = runEventHandlers
end

function PostOption(...)
    for _,handler in ipairs(onPostOptionHandlers) do
        result = handler(...)
        if result then return result end
    end
    if #ExprFileFilters > 0 then
        onFileFilter ('function (name, type, size, time, attr); return ('..table.concat(ExprFileFilters,') and (')..'); end')
    end
end
function AddFileFilter(filter)
    table.insert (ExprFileFilters, filter)
end
ExprFileFilters = ExprFileFilters or {}

function FileFilter(...)
    for _,handler in ipairs(onFileFilterHandlers) do
        result = handler(...)
        if not result then return result end
    end
    return true
end

function noFileFilters()
    return #onFileFilterHandlers==0
end


--[[ **********************************************************************************************************************************
*** Option parsing machinery **********************************************************************************************************
*************************************************************************************************************************************]]
optvalue = optvalue or {}

function parse_num(str)
    str = str:gsub("[',]", '')
    return tonumber(str)
end

function parse_mem(str,spec)
    spec = spec or 'b'
    if str:sub(-1) == 'b' then
        str = str:sub(1,-2)
        spec = 'b'
    end
    local last_char = str:sub(-1)
    if string.find(MEM_SUFFIXES,last_char,1,true) then
        str = str:sub(1,-2)
        spec = last_char
    end
    local n = parse_num(str)
    if n then
        if spec=='^' then
            n = 2^n
        else
            local pos = string.find(MEM_SUFFIXES,spec,1,true)
            if pos  then n = n*(1024^pos) end
        end
    end
    return n
end
MEM_SUFFIXES = 'kmgtpezy^'

function try_parse_num(name,str)
    local n = parse_num(str)
    if n then
        optvalue[name] = n
    else
        return 'cannot parse "'..str..'" as number'
    end
end

function try_parse_mem(name,str,spec)
    local size = parse_mem(str,spec)
    if size then
        optvalue[name] = size
    else
        return 'cannot parse "'..str..'" as size'
    end
end

function try_parse_bool(name,str)
    if str=='' then
        optvalue[name] = true
    else
        return 'extra text "'..str..'" in the option that doesn\'t take any parameters'
    end
end

OPTION_BYTES     = 'b'
OPTION_KILOBYTES = 'k'
OPTION_MEGABYTES = 'm'
OPTION_GIGABYTES = 'g'
OPTION_TERABYTES = 't'
OPTION_PETABYTES = 'p'
OPTION_POWER     = '^'
OPTION_NUMBER    = '%'
OPTION_STRING    = '$'
OPTION_LIST      = '*'
OPTION_BOOL      = '?'

function AddOption(...)
    local option = {...}
    if type(option[2]) ~= "number" then
        table.insert(option,2,0)
    end
    local name, priority, texts, help, parser, post_parser = table.unpack(option)
    if type(parser) == "string" then
        local spec = parser
        if string.find (MEM_SUFFIXES..'b', spec, 1, true)  then  parser = function(param);  return try_parse_mem(name,param,spec);  end
        elseif spec==OPTION_NUMBER                         then  parser = function(param);  return try_parse_num(name,param);       end
        elseif spec==OPTION_STRING                         then  parser = function(param);  optvalue[name] = param;                 end
        elseif spec==OPTION_LIST                           then  parser = function(param);  optvalue[name] = optvalue[name] or {};  table.insert(optvalue[name], param);  end
        elseif spec==OPTION_BOOL                           then  parser = function(param);  return try_parse_bool(name,param);      end
        else print ('Invalid option type: "'..spec..'"')
        end
        if post_parser then
            local orig_post_parser = post_parser
            post_parser = function();  if optvalue[name]  then return orig_post_parser(optvalue[name]) end end
        end
    end
    ModifyOption(name, priority, texts, help, parser, post_parser)
end

function AddOptions(options)
    for _,option in ipairs(options) do
        AddOption(table.unpack(option))
    end
end

function RemoveOption(name)
    ModifyOption(name, 0, '', '')
end
```