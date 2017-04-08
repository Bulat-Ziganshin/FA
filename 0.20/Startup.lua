require 'pl'; utils.on_error('error');  isWindows = path.is_windows
FREEARC_ARCHIVE_EXTENSION = 'arc'
RAM_SIZE = GetPhysicalMemory()
NUM_CPUS = GetCpuThreads()
WORD_SIZE = string.packsize("T")*8

--[[ **********************************************************************************************************************************
*** Utility functions *****************************************************************************************************************
*************************************************************************************************************************************]]

kb,mb,gb,tb,pb = 1024, 1024^2, 1024^3, 1024^4, 1024^5

function min(a,b)   if a<b  then return a  else return b end end
function max(a,b)   if a>b  then return a  else return b end end

-- Round first number *down* to divisible by a second one
function roundDown(a,b)
    if b>1 then
        return a - a%b
    else
        return a
    end
end

-- Round first number *up* to divisible by a second one
function roundUp(a,b)
    if a~=0 and b>1 then
        return roundDown(a-1,b)+b
    else
        return a
    end
end

-- Round up the memory size in order to make it easily readable
function roundMemUp(mem)
    return roundUp(mem, mem>900*kb and mb or kb)
end

-- Returns a string describing the memory amount
function showMem(mem, skip_b)
  local b = (skip_b and '' or 'b')
      if mem   ==0  then return '0'..b
  elseif mem%pb==0  then return string.format('%d',mem//pb)..'p'..b
  elseif mem%tb==0  then return string.format('%d',mem//tb)..'t'..b
  elseif mem%gb==0  then return string.format('%d',mem//gb)..'g'..b
  elseif mem%mb==0  then return string.format('%d',mem//mb)..'m'..b
  elseif mem%kb==0  then return string.format('%d',mem//kb)..'k'..b
  else                   return string.format('%d',mem//1)..b end
end

-- Convert integer number into string divided by ',': "1,234,567"
function show3(num)
    local s = string.format('%d',num)
    return s:reverse():gsub('%d%d%d','%0,'):reverse():gsub('^,','')
end


-- Check that filespec is a wildcard, i.e. contains *? characters
function is_wildcard(filespec)
    return filespec:match('[*?]')
end

-- Convert wildcard containing *? characters into Lua regex pattern
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

function one_of(char,list)
    return string.find (list, char, 1, true)
end
string.one_of = one_of

-- Remove from the `str` any chars presented in the `list`
function remove_chars(str,list)
    return str:gsub('.', function(old) return old:one_of(list) and '' end)
end
string.remove_chars = remove_chars

function in_list(str,list,delim)
    delim = delim or ','
    return string.find (delim..list..delim, delim..str..delim, 1, true)
end
string.in_list = in_list

function table.append(t1,t2)
    local result = {table.unpack(t1)}
    for i = 1,#t2 do
        table.insert(result, t2[i])
    end
    return result
end

function table.reverse(xs)
    local result = {}
    for i=#xs,1,-1 do
        table.insert (result, xs[i])
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

words = stringx.split
string.words = words

function split2 (str, delim)
    local pos = str:find(delim, 1, true)
    if pos then return str:sub(1,pos-1), str:sub(pos+#delim)
           else return str
    end
end
string.split2 = split2

-- Move to front list elements on which predicate_f returns true
function List:partition_bool(predicate_f)
    local x = self:partition(predicate_f)
    return (x[true] or List.new()) :extend(x[false] or {})
end

-- Base-16 string encoder/decoder
function encode16(str)
    return (string.gsub (str, ".",
        function (c) return string.format ("%02x", string.byte(c)) end))
end
function decode16(str)  -- to do: raise exception on errors
    return (string.gsub (str, "%x%x",
        function (s) return string.char(tonumber(s,16)) end))
end


--[[ **********************************************************************************************************************************
*** File operations *******************************************************************************************************************
*************************************************************************************************************************************]]

-- Windows: Unicode/UNC/LongName-aware operations. Unix: just usual operations.
-- In both cases, filenames are UTF8-encoded.
File = {exists=FileExists, open=FileOpen or io.open, GetSize=GetFileSize, GetTime=GetFileTime, GetAttr=GetFileAttr, SetAttr=SetFileAttr, SetTime=SetFileTime, delete=DeleteFile, rename=RenameFile}
Dir  = {exists=DirExists, GetCurrent=GetCurrentDir or path.currentdir, create=CreateDir, createRecursively=CreateDirRecursively, delete=DeleteDir}

-- Directory of the program executable file
function exedir()
    return path.dirname(ExecutableFilename())
end

-- Look for file in configuration directories, returning nil when not found
function File.search_config(filename)
    if not filename:match('[:/\\]') then            -- to do: has_path()
        filename = path.join(exedir(),filename)     -- to do: search in OS-recommended dirs
    end
    if File.exists(filename) then
        return filename
    end
end

local function read_file(mode)
    return function(filename)
        local file = assert(File.open(filename,mode))
        local data = file:read('*all')
        file:close()
        return data
    end
end
File.read_binary = read_file("rb")
File.read_text   = read_file("r")

-- Return contents of config file or nil + error message
local function read_config_file (filename, read_f)
    local fullname = File.search_config(filename)
    if fullname then
        return read_f(fullname)
    else
        return nil, 'Configuration file \"'..filename..'\" not found'
    end
end
function File.read_text_config(filename)    return read_config_file (filename, File.read_text)   end
function File.read_binary_config(filename)  return read_config_file (filename, File.read_binary) end


--[[ **********************************************************************************************************************************
*** Event handling machinery **********************************************************************************************************
*************************************************************************************************************************************]]
HIGHEST_PRIORITY = 1e6                  -- executed first
HIGH_PRIORITY    = 1e3
NORMAL_PRIORITY  = 0
LOW_PRIORITY     = -HIGH_PRIORITY
LOWEST_PRIORITY  = -HIGHEST_PRIORITY    -- executed last

EventHandlers = EventHandlers or {}
AddHandler    = AddHandler    or {}
RemoveHandler = RemoveHandler or {}
RunEvent      = RunEvent      or {}

-- Resort handlers by priority if new handlers were added since the last sort
function SortEventHandlers(event)
    if not EventHandlers[event].already_sorted then
        EventHandlers[event].already_sorted = true
        table.sort (EventHandlers[event], function (a,b) return (a.priority > b.priority) end)  -- put handlers with higher priority first
    end
end

-- Declare event with provided name
function DeclareEvent(event)
    -- Adds one more event handler with optional label and priority
    local function addEventHandler (label, priority, handler)
        -- Handle reduced amount of options: only handler
        if not priority then
            label, priority, handler = '', NORMAL_PRIORITY, label
        end
        -- Only priority and handler
        if not handler and type(label)=='number' then
            label, priority, handler = '', label, priority
        end
        -- Only label and handler
        if not handler then
            label, priority, handler = label, NORMAL_PRIORITY, priority
        end

        -- Convert textual handler representation into code
        if type(handler)=='string' then
            if label=='' then label = handler end
            handler = [[
                local string_match, start_with = string.match, start_with
                local bnot, bor, bxor, band, btest = bit32.bnot, bit32.bor, bit32.bxor, bit32.band, bit32.btest
                return ( ]] .. handler .. ')'
            handler = assert(load(handler,label)) ()
        end

        -- Save event handler to the table
        table.insert (EventHandlers[event], {label=label, priority=priority, handler=handler})
        EventHandlers[event].already_sorted = false
    end

    -- Remove event handlers with label `name`
    local function removeEventHandler(name)
        EventHandlers[event] = tablex.filter (EventHandlers[event], function(v)
            return v.label~=name
        end)
    end

    -- Execute all handlers for the event in the priority order
    local function runEventHandlers(...)
        SortEventHandlers(event)
        -- Execute all handlers in descending priority order until any handler returned not nil/false
        for _,obj in ipairs(EventHandlers[event]) do
            local result = obj.handler(...)
            if result then return result end
        end
    end

    EventHandlers[event]  =  EventHandlers[event] or {}
    AddHandler[event], _G['on'..event]  =  addEventHandler, addEventHandler
    RemoveHandler[event] = removeEventHandler
    RunEvent[event] = runEventHandlers
    _G[event] = function(...)  return RunEvent[event](...) end  -- to do: remove
end

function DeclareEvents(EventNames)
    for event in string.gmatch(EventNames, '%S+') do
        DeclareEvent(event)
    end
end

-- Events that are called from C++ code, except for Warning/Error those messages are translated/formatted by the UI module
DeclareEvents[[ProgramStart ProgramDone
               CommandStart CommandDone
               ArchiveStart ArchiveDone
               SubCommandStart SubCommandDone
               CompressionStart CompressionDone
               ExtractionStart ExtractionDone
               Warning Error]]


-- Custom processing for events modifying the compression method
function ProcessEventByChainingHandlers(event, super_event, is_header)
    if not EventHandlers[event]  then DeclareEvent(event) end
    RunEvent[event] = function(method, ...)
        SortEventHandlers(event)
        for _,obj in ipairs(EventHandlers[event]) do
            method  =  obj.handler(method, ...) or method
        end
        if super_event then
            method = RunEvent[super_event](method, is_header, ...)
        end
        return method
    end
end

ProcessEventByChainingHandlers('DisplayMethod')
ProcessEventByChainingHandlers('CompressBlockMethod')
ProcessEventByChainingHandlers('CompressDataBlockMethod'  , 'CompressBlockMethod', false)
ProcessEventByChainingHandlers('CompressHeaderBlockMethod', 'CompressBlockMethod', true)
ProcessEventByChainingHandlers('ExtractBlockMethod')
ProcessEventByChainingHandlers('ExtractDataBlockMethod'   , 'ExtractBlockMethod', false)
ProcessEventByChainingHandlers('ExtractHeaderBlockMethod' , 'ExtractBlockMethod', true)
