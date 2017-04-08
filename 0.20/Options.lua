--[[ **********************************************************************************************************************************
*** User-defined commands *************************************************************************************************************
*************************************************************************************************************************************]]

-- Example of raw command definition:
--  "fa debug" starts Lua built-in debugging REPL
--  "fa debug lua-code..." executes Lua code. Note that OS cmdline parsing may get into your way!
onRawCmdline ('debug', function (argv)
    if argv[1]=='debug' then
        if #argv > 1 then
            load(table.concat(argv,' ',2)) ()
        else
            debug.debug()
        end
        return true  -- command was executed, further processing not required
    end
end)

-- Example of raw command definition:
--  "fa run" executes script from stdin
--  "fa run script [arguments...]" executes the Lua script, passing arguments in the global table arg
onRawCmdline ('run', function (argv)
    if argv[1]=='run' then
        if #argv == 1 then
            dofile()
        else
            arg = {}
            for i,a in ipairs(argv) do
                arg[i-2] = argv[i]
            end
            dofile(arg[0])
        end
        return true  -- command was executed, further processing not required
    end
end)

-- Example of normal command definition: "fa create-locked ..." is equivalent to "fa create --lock ..."
onCmdline ('create-locked', function()
    if command.cmd=='create-locked' then
        command.cmd = 'create'
        command.lock_archive = true
        return false  -- command was preprocessed and should be executed in the usual way
    end
end)


--[[ **********************************************************************************************************************************
*** File-filtering options ************************************************************************************************************
*************************************************************************************************************************************]]
AddOptions{
    {'min_size', '-smBYTES --min-size=BYTES --SizeMore=BYTES', 'process only files larger than BYTES',
                    OPTION_BYTES,  post_processing = function(min_size) AddFileFilter('size>='..min_size) end},
    {'max_size', '-slBYTES --max-size=BYTES --SizeLess=BYTES', 'process only files smaller than BYTES',
                    OPTION_BYTES,  post_processing = function(max_size) AddFileFilter('size<='..max_size) end},
    {'select_archive_bit', '-ao --select-archive-bit --SelectArchiveBit', "select only files with Archive bit set",
                    OPTION_BOOL,   post_processing = function() AddFileFilter('btest(attr,0x20)') end},
}

AddOption{'filter', '-fEXPR --filter=EXPR', 'filter files by Lua expression employing vars name, type, size, time and attr',
OPTION_LIST,
post_processing = function(filters)
    for _,filter in ipairs(filters) do
        if not string.match (' '..filter..' ', '[^%w_]return[^%w_]') then
            AddFileFilter(filter)
        else
            onFileFilter('FilterOption', 'function (name, type, size, time, attr); '..filter..'; end')
        end
    end
end}

AddOption{'select_by_attributes', '-e[+]MASK', "include/exclude files based on file attributes (MASK is a number or [SHARD]+)",
-- Parsing function
function(param,name)
    local subname = 'exclude'
    optvalue[name] = optvalue[name] or {}
    if param:sub(1,1)=='+' then
        param = param:sub(2)
        subname = 'include'
    end
    param = param:lower()
    if param:match('^0[0-7]+$') then
        param = tonumber (sub(param,2), 8)          -- manual decoding for octal numbers
    elseif param:match('^%d+$') or param:match('^0x%x+$') then
        param = tonumber(param)                     -- automatic decoding for decimal/hexadecimal numbers
    elseif isWindows and param:match('^[dshar]+$') then
        param = (param:match('d') and 0x10 or 0)    -- directory, to do: not really supported yet
              + (param:match('a') and 0x20 or 0)    -- archive
              + (param:match('s') and 0x04 or 0)    -- system
              + (param:match('h') and 0x02 or 0)    -- hidden
              + (param:match('r') and 0x01 or 0)    -- read only
    else
        return 'Invalid option format, should be [+]number'..(isWindows and ' or [+][SHARD]+' or '')
    end
    optvalue[name][subname] = param
end,
post_processing = function(name)
    local option = optvalue[name] or {}
    if option.include  then AddFileFilter(    'btest(attr,'..option.include..')')  end
    if option.exclude  then AddFileFilter('not btest(attr,'..option.exclude..')')  end
end}


--[[ **********************************************************************************************************************************
*** Filename-based file-filtering options *********************************************************************************************
*************************************************************************************************************************************]]

-- Process list, replacing '@listfile' items with lines read from the listfile
function subst_listfiles(filespecs)
    local result = {}
    for _,filespec in ipairs(filespecs) do
        if filespec:sub(1,1)=='@' then
            local listfile_data = File.read_text(filespec:sub(2))
            for line in stringx.splitlines(listfile_data):iter() do
                line = line:gsub(' *//.*$','')
                if line > '' then
                    table.insert (result, line)
                end
            end
        else
            table.insert (result, filespec)
        end
    end
    return result
end

-- Build an expression that matches 'name' variable to provided filespec
function match_name_filter_expr (filespec, reverse)
    if is_wildcard(filespec) then
        return (reverse and 'not ' or '') .. string.format('string_match(name,%q)', wildcard2pattern(filespec))
    else
        return 'name' .. (reverse and '~=' or '==') .. string.format('%q', filespec)
    end
end

AddOption{'include', '-nFILESPECS --include=FILESPECS', 'include only files matching FILESPECS',
OPTION_LIST,
post_processing = function(filespecs)
    local filters  =  tablex.imap (match_name_filter_expr, subst_listfiles(filespecs))
    AddFileFilter ('('..table.concat(filters,') or (')..')')
end}

AddOption{'exclude', '-xFILESPECS --exclude=FILESPECS', 'exclude FILESPECS from operation',
OPTION_LIST,
post_processing = function(filespecs)
    for _,filespec in ipairs(subst_listfiles(filespecs)) do
        AddFileFilter (match_name_filter_expr (filespec, true))
    end
end}


--[[ **********************************************************************************************************************************
*** Time-based file-filtering options *************************************************************************************************
*************************************************************************************************************************************]]

-- Add file filter based on `cmp` and time saved into optvalue[name]
function post_process_TIME(cmp)
    return function(name)
        if optvalue[name] then
            AddFileFilter('time'..cmp..optvalue[name])
        end
    end
end

-- Parse argument of -ta/-tb option and save computed absolute time into optvalue[name]
function parse_TIME(param,name)
    param = param:gsub('[%p%s]','')   -- remove delimiters
    -- Remaining chars should be only digits and include only full fields, at least the year
    if not (param:match('^%d%d%d+$') and (#param%2)==0) then
        return 'Bad option format, should be: YYYY[MM[DD[HH[MM[SS]]]]] plus any delimiters'
    end
    param = param .. ('20000101000000'):sub(#param+1)   -- add values for omitted fields
    local time = {year=param:sub(1,4),  month=param:sub(5,6), day=param:sub(7,8),
                  hour=param:sub(9,10), min=param:sub(11,12), sec=param:sub(13,14)}
    optvalue[name] = os.time(time)
end

AddOption{'time_after',  '-taTIME --time-after=TIME  --TimeAfter=TIME',  'select files modified after specified TIME (format: YYYYMMDDHHMMSS)',
          parse_TIME,  post_processing = post_process_TIME('>=')}
AddOption{'time_before', '-tbTIME --time-before=TIME --TimeBefore=TIME', 'select files modified before specified TIME (format: YYYYMMDDHHMMSS)',
          parse_TIME,  post_processing = post_process_TIME('<')}


-- Parse argument of -tn/-to option and save computed absolute time into optvalue[name]
function parse_TIME_OFFFSET(param,name)
    local errmsg = 'Bad option format, should be: [<ndays>d][<nhours>h][<nminutes>m][<nseconds>s]'
    if not param:match('^%d.*%D$') then  -- entire option contents should start with digit and end with non-digit
        return errmsg
    end

    local time, visited  =  os.date('*t', START_TIME), {}
    for value,suffix in param:gmatch('(%d+)(%D+)') do
        -- Translate suffix into the name of corresponding os.time() field
        local field = ({d='day', h='hour', m='min', s='sec'})[suffix]
        if field  and  (not visited[suffix]) then
            time[field] = time[field] - value
            visited[suffix] = true
        else
            return errmsg
        end
    end
    optvalue[name] = os.time(time)
end

AddOption{'time_newer', '-tnPERIOD --time-newer=PERIOD --TimeNewer=PERIOD', 'select files newer than specified time PERIOD (format: #d#h#m#s)',
          parse_TIME_OFFFSET,  post_processing = post_process_TIME('>=')}
AddOption{'time_older', '-toPERIOD --time-older=PERIOD --TimeOlder=PERIOD', 'select files older than specified time PERIOD (format: #d#h#m#s)',
          parse_TIME_OFFFSET,  post_processing = post_process_TIME('<')}


--[[ **********************************************************************************************************************************
*** Remaining options *****************************************************************************************************************
*************************************************************************************************************************************]]
DEFAULT_AUTOGENERATE_FORMAT = '%Y%m%d%H%M%S'
DEFAULT_SFX_MODULE = 'freearc.sfx'

AddOption{'autogenerate', '-ag[FORMAT] --autogenerate=[FORMAT]', 'append to archive name string generated by strftime(FORMAT||"'..DEFAULT_AUTOGENERATE_FORMAT..'")',
OPTION_STRING,
post_processing = function(format)
    if format~='-' and format~='--' then
        if format==''  then format = DEFAULT_AUTOGENERATE_FORMAT end
        local timestr = os.date(format, START_TIME)
        local arcname, arcext = path.splitext(command.arcname)
        command.arcname = arcname .. timestr .. arcext
    end
end}

AddOption{'noarcext', '--no-arc-ext --noarcext', "don't add default extension to archive name",
function(param,name)
    optvalue[name] = true
end,
post_processing = function(name)
    if not optvalue[name]  and  path.extension(command.arcname)=='' then
        command.arcname = command.arcname .. '.' .. FREEARC_ARCHIVE_EXTENSION
    end
end}

AddOption{'large_page_mode', '-slpMODE', 'set large page mode (TRY(default), FORCE(+), DISABLE(-), MALLOC)',
OPTION_STRING,
post_processing = function(mode)
    if mode==''  then mode = 'TRY' end
    if mode=='-' then mode = 'DISABLE' end
    if mode=='+' then mode = 'FORCE' end
    SetLargePageMode(mode)
end}

AddOption{'prefetch', '--prefetch[PARAMS]', 'prefetching to the OS file cache (:1g:8 means read 1GB ahead using 8 threads)',
OPTION_STRING,
post_processing = function(params)
    if params==''   then params = '2g:8' end
    if params=='-'  then params = '0' end
    for word in params:gmatch('([^:=/,;]+)') do
        local n = parse_num(word)
        if n then
            command.prefetch_threads = n
        else
            local size = parse_phys_mem(word,'m')
            if size then
                command.prefetch_cache = size
            else
                return 'cannot parse "'..word..'" as number of threads or cache size'
            end
        end
    end
end}

AddOption{'archive_comment_file', '-zFILE --arccmt=FILE', 'read archive comment from FILE or stdin',
function(param,name)
    optvalue[name] = param
    command.archive_comment = '\0'   -- the last of -z/--archive-comment options will take effect
end,
post_processing = function(name)
    local file = optvalue[name]
    if command.archive_comment~='\0'  then return end   -- Go out if --archive-comment was used in command line later than -z
    command.archive_comment  =  file=='-' and ''                        --  -z- clears the comment
                             or file==''  and io.read('*all')           --  -z reads comment from stdin
                             or               File.read_binary(file)    --  -zFILE reads comment from FILE
end}

AddOption{"sfx", "-sfx[MODULE]", "add sfx MODULE (\""..DEFAULT_SFX_MODULE.."\" by default)",
OPTION_STRING,
post_processing = function(sfx)
    if sfx~='-' and sfx~='--' then
        if sfx==''  then sfx = DEFAULT_SFX_MODULE end
        command.sfxdata  =  assert(File.read_binary_config(sfx), 'SFX module \"'..sfx..'\" not found')
    end
end}

DEFAULT_GROUP_FILE = 'arc.groups'
AddOption{"group_file",  "--groups=FILE",  'name of groups file ('..DEFAULT_GROUP_FILE..' by default)',
default_value = '--',
function(param,name)
    optvalue[name] = param
end,
post_processing = function(name)
    local filename = optvalue[name]
    if filename=='--' then                  -- "--groups=--" may be used to restore default option value
        filename = DEFAULT_GROUP_FILE
    end
    if filename~='-' and filename~='' then  -- "--groups=-" or  "--groups=" may be used to disable group file sorting
        local data = File.read_text_config(filename)
        if data or optvalue[name]~='--' then
            command.group_data  =  assert(data, 'Groups file \"'..filename..'\" not found')
        end
    end
end}

AddOption{"workdir",  "-wDIRECTORY --workdir=DIRECTORY",  "DIRECTORY for temporary files, created by external compressors",
OPTION_STRING,
post_processing = function(workdir)
    if workdir:sub(1,1)=='%' then
        workdir = assert (os.getenv(workdir:sub(2)), 'Environment variable \"'..workdir:sub(2)..'\", used to specify workdir, isn\'t defined')
    end
    if workdir~="" then
        SetTempDir(workdir)
    end
end}

AddCppOption{"sort_order", "-dsORDER --sort=ORDER", "sort files in the order defined by chars 'gerpnsd-' ('DEFAULT_VALUE' by default)",
default_value="gerpn",
function(param,name)
    local valid_chars = 'gepnsdt'
    -- Reversed sorting order is represented by capital letters internally, but as 'letter-' in the cmdline
    param = param:gsub('(['..valid_chars..'])[-]', string.upper)
    -- Valid sorting order chars include valid_chars, their capital equivalents, and 'r'
    if not param:match('^[r'..valid_chars..valid_chars:upper()..']*$') then return "invalid sort order" end
    optvalue[name] = param
end}

AddOption{"expand_paths3", "-ep3", "keep drive/rootchar in filenames, useful for multi-disk backups",
function()
    command.expand_paths = 3
end}

AddOptions{
    {"config_env", "-envVAR", "read default options from environment VAR (default: DEFAULT_VALUE)",
        OPTION_STRING, for_preparsing=true, default_value='FA_CFG'},
    {"config_file", "-cfgFILE --config=FILE", "use configuration FILE (default: DEFAULT_VALUE)",
        OPTION_STRING, for_preparsing=true, default_value='fa.ini'},
    {"help", "-h --help", "display help on the commands and options", OPTION_BOOL},
    {"print_config", "--print-config", "display built-in definitions of compression methods", OPTION_BOOL},
    {"remark", "-rem... --rem...", "remark (ignored commentary)", function() end},
}


--[[ **********************************************************************************************************************************
*** C++ options *****************************************************************************************************************
*************************************************************************************************************************************]]
function ParseSolidOption(param)
    -- Since C++ function cannot return nil, it returns empty string as the success indicator
    local errmsg = CppParseSolidOption(param)
    if errmsg ~= ''  then return errmsg end
end

AddCppOptions{
    {"deduplication_mode", "-dup        --deduplication",                "global deduplication a-la ZPAQ"},
    {"archive_comment",    "            --archive-comment=COMMENT",      "input archive COMMENT in cmdline"},
    {"recursive",          "-r          --recursive",                    "recursively find files to add (to do: or archives to list/extract)"},
    {"test",               "-t          --test",                         "test archive after operation"},
    {"lock_archive",       "-k          --lock",                         "lock archive from further updates"},
    {"keep_broken",        "-kb         --keep-broken    --keepbroken",  "keep extracted files that failed the CRC check"},
    {"dirs",               "            --dirs",                         "add empty dirs to archive"},
    {"no_dirs",            "-ed         --no-dirs        --nodirs",      "don't add empty dirs to archive"},
    {"no_read",            "            --no-read        --noread",      "only build list of files to compress"},
    {"no_write",           "            --no-write       --nowrite",     "don't create archive file"},
    {"no_crc",             "            --no-crc         --nocrc",       "don't compute/check CRC"},
    {"no_data",            "            --no-data        --nodata",      "don't write compressed data to the archive"},
    {"no_dir",             "            --no-dir         --nodir",       "don't write archive directory"},
    {"no_attrs",           "-ai         --no-attrs",                     "don't save/restore file attributes"},
    {"restore_compressed_attribute",   "-oc",                            "restore NTFS Compressed file attribute"},
    {"no_check",           "            --no-check       --nocheck",     "don't check SHA-256 hashes of extracted data"},
    {"save_sha_hashes",    "            --save-sha-hashes",              "store in the archive SHA-256 hashes of the chunks"},
    {"global_queueing",    "            --queue",                        "queue operations across multiple FreeArc copies"},
    {"shutdown_mode",      "-ioff       --shutdown",                     "shutdown computer when operation is completed"},
    {"diskpath",           "-dpDIR      --diskpath=DIR",                 "base DIR on disk"},
    {"cache_size",         "            --cache=BYTES",                  "size of read-ahead cache", OPTION_MEGABYTES},
    {"io_threads",         "-miNUM      --io-threads=NUM",               "I/O threads"},
    {"num_threads",        "-mtNUM      --threads=NUM    -tNUM  --MultiThreaded=THREADS",  "number of (de)compression threads (default: DEFAULT_VALUE)"},
    {"buffer_size",        "-mbBYTES    --bufsize=BYTES  -bBYTES",       "buffer size", OPTION_MEGABYTES},
    {"chunk_size",         "-cBYTES     --chunk=BYTES",                  "average chunk size (default: DEFAULT_VALUE)", OPTION_BYTES},
    {"min_chunk",          "            --min-chunk=BYTES",              "minimum chunk size (default: DEFAULT_VALUE)", OPTION_BYTES},
    {"ratio",              "            --ratio=PERCENTS",               "automatically store blocks with order-0 entropy >PERCENTS% (DEFAULT_VALUE by default)"},
    {"solid",              "-sGROUPING  --solid=GROUPING",               "group files into solid blocks", ParseSolidOption},
}
