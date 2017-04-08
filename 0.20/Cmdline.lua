--[[ **********************************************************************************************************************************
*** Configuration files processing ****************************************************************************************************
*************************************************************************************************************************************]]

-- Convert plain string (config file contents) into the structure convenient to process config data
function PreprocessConfigFile(config_data_str, config_location)
    -- Config is a list of sections, which are lists of lines
    local config_data = List.new()
    local cur_section = List.new()      -- first section, that may be empty, collects all lines prior to first section heading

    -- Split config lines into sections
    for cur_line in stringx.splitlines(config_data_str):iter() do
        -- Line matching '[...]' starts new section
        if cur_line:match('^%[.*%]$') then
            config_data:append(cur_section)     -- flush the section contents
            cur_section = List.new()            -- and start a new one
        end
        cur_section:append(cur_line)
    end
    config_data:append(cur_section)             -- flush the section contents

    return {data=config_data, file=config_location}
end

-- Process with `process_f` each `config` section with name matching `heading_pattern` regex
function EnumSections(config, heading_pattern, process_f)
    heading_pattern  =  '^%['..heading_pattern:lower()..'%]$'
    for cur_section in config.data:iter() do
        local section_heading  =  cur_section[1] or ''
        if section_heading:lower():match(heading_pattern) then   -- Section heading with name matching the `heading_pattern`
            process_f(cur_section, 'Section '..section_heading..' of '..config.file)
        end
    end
end

-- Read config files (including built-in config) and process all their sections
function ParseConfigFiles()
    local config_files = List.new{ PreprocessConfigFile (builtin_config_file, 'builtin config') }

    -- Load fa-*.ini config files from the executable directory
    for filename in path.dir(exedir()) do
        if dir.fnmatch (filename, 'fa-*.ini') then
            local config_file = path.join (exedir(), filename)
            config_files:append (PreprocessConfigFile (File.read_text(config_file), config_file))
        end
    end

    local config_data = File.read_text_config(optvalue.config_file)
    if config_data  then config_files:append (PreprocessConfigFile (config_data, optvalue.config_file)) end

    -- Parse compression method aliases
    for config in config_files:iter() do
        EnumSections (config, 'Compression methods', function(cur_section, cur_location)
            SetupCompressionMethods (cur_section:remove(1):join('\n'), cur_location)
        end)
    end

    -- Populate external compressors table
    ClearExternalCompressorsTable()
    for config in config_files:iter() do
        EnumSections (config, 'External compressor:.*', function(cur_section, cur_location)
            local section_data = cur_section:join('\n')
            if AddExternalCompressor(section_data) ~= 1 then
                error('Error in '..config.file..' section:\n'..section_data..'\n')  -- to do: make a warning
            end
        end)
    end

    -- Run fa-*.lua scripts from the executable directory
    for filename in path.dir(exedir()) do
        if dir.fnmatch (filename, 'fa-*.lua') then
            dofile (path.join (exedir(), filename))
        end
    end

    -- Run [Lua code*] sections from config files
    for config in config_files:iter() do
        EnumSections (config, 'Lua code.*', function(cur_section, cur_location)
            local successful, errmsg = xpcall (assert (load (cur_section:remove(1):join('\n'), cur_location)), debug.traceback)
            if not successful  then error(cur_location..': '..errmsg) end
        end)
    end

    -- First line of each config file contains default program options
    for config in config_files:iter() do
        for cur_line in config.data[1]:iter() do
            if not (cur_line:match('^%s*;') or cur_line:match('^%s*$')) then  -- skip empty/comment lines
                ParseOptions (words(cur_line), 'First line of '..config.file)
                break
            end
        end
    end

    -- Extract default options for the current command from the [Default options] section
    for config in config_files:iter() do
        EnumSections (config, 'Default options', function(cur_section, cur_location)
            for cur_line in cur_section:remove(1):iter() do
                if not (cur_line:match('^%s*;') or cur_line:match('^%s*$')) then  -- skip empty/comment lines
                    local cfg_commands, cfg_options  =  cur_line:split2('=')
                    assert(cfg_options, cur_location..": no '=' in line '"..cur_line.."'")
                    if command.cmd:in_list(cfg_commands, ' ') then
                        ParseOptions (words(cfg_options), cur_location)
                    end
                end
            end
        end)
    end
end


--[[ **********************************************************************************************************************************
*** Program help **********************************************************************************************************
*************************************************************************************************************************************]]
FA_VERSION = {major=0, minor=20, date=os.time{year=2017,month=4,day=4}}
FA_VERSION.str = FA_VERSION.major .. '.' .. FA_VERSION.minor
FA_VERSION_STR = string.format ("FreeArc'Next-x%d v%s (%s)", (WORD_SIZE==32 and 86 or WORD_SIZE), FA_VERSION.str, os.date('%b %d %Y',FA_VERSION.date))
first_help_line = FA_VERSION_STR.." by Bulat.Ziganshin@gmail.com (http://freearc.org)"

function MiniHelp()
    print (first_help_line..'\nType "FA -h" for information about commands and options')
end

function Help()
    local help = [[
%s
Usage: fa COMMAND ARCHIVE [OPTION...] FILES/DIRS/@LISTFILES...

Commands:
  a[dd]|create  create archive from files/dirs
  l[ist]        list files in the archive
  lb|barelist   bare list of filenames in the archive
  lt|techlist   list solid blocks in the archive
  t[est]        check the archive integrity
  v[erblist]    verbosely list files in the archive
  x|extract     extract all files from the archive

Options:
%s

PLEASE DON'T USE THE PROGRAM IN PRODUCTION ENVIRONMENT SINCE IT'S STILL IN ALPHA STAGE
]]
    print (help:format (first_help_line, GetOptionsHelp(2,12,24)))
end


--[[ **********************************************************************************************************************************
*** Top-level function parsing config files & command line ****************************************************************************
*************************************************************************************************************************************]]
function is_add_command()       return command.cmd=='a'  or command.cmd=='add'  or  command.cmd=='create'  end
function is_test_command()      return command.cmd=='t'  or command.cmd=='test'      end
function is_extract_command()   return command.cmd=='x'  or command.cmd=='extract'   end
function is_list_command()      return is_filelist_command() or is_verblist_command() or is_barelist_command() or is_techlist_command() end
function is_filelist_command()  return command.cmd=='l'  or command.cmd=='list'      end
function is_verblist_command()  return command.cmd=='v'  or command.cmd=='verblist'  end
function is_barelist_command()  return command.cmd=='lb' or command.cmd=='barelist'  end
function is_techlist_command()  return command.cmd=='lt' or command.cmd=='techlist'  end
DeclareEvents[[RawCmdline Cmdline]]

function ParseCommandLine()
    START_TIME = os.time()      -- let's fix the command start time so that all options use the same value
    local argv = command.argv   -- array of strings representing the command line

    -- Replace @cmdfile, if it's a single argument, with cmdfile contents split into words
    if #argv==1 and argv[1]:match('^@') then
        local cmdfile = argv[1]:sub(2)
        argv = File.read_text(cmdfile):words()  -- to do: consider "any text" as the single word
    end

    -- Request user-defined command handlers to preprocess/execute the raw command
    local done = RunEvent.RawCmdline(argv)
    if done  then return true end  -- command successfuly executed, now please quit the program

    -- Preparsing - determine the command and values of -cfg/-env options
    local environment_options = ''
    InitializeOptions()
    PreparseOptions(argv)

    -- Second pass of preparsing - now with options from FA_CFG
    if optvalue.config_env=='-' or optvalue.config_file=='-' then
        optvalue.config_env = '-'
    else
        local env = os.getenv(optvalue.config_env)
        if env then
            environment_options = words(env)
            -- Preparse again in order to establish -cfg option using envvar+cmdline
            PreparseOptions(environment_options)
            PreparseOptions(argv)
        end
    end

    -- Parse config files, environment variable and cmdline
    optvalue.additional_options = {}
    ParseConfigFiles()
    ParseOptions (environment_options, "environment variable "..optvalue.config_env)
    ParseOptions (argv, "command line", --[[allow_filenames=]] true)

    -- Request user-defined command handlers to postprocess/execute the parsed command
    local done = RunEvent.Cmdline()
    if done  then return true end  -- command successfuly executed, now please quit the program

    -- Print help/config and quit if no command was given
    if command.cmd=='' then
        if optvalue.print_config then
            print(builtin_config_file)
        elseif optvalue.help then
            Help()
        else
            MiniHelp()
        end
        return true  -- signal to quit the program immediately
    end

    -- Check command.cmd/arcname/filenames[]
    assert (command.cmd     > '',  'No command')
    assert (command.arcname > '',  'No archive name')
    if is_add_command() and #command.filenames==0 then  -- to do: speed-optimize
        command.filenames = {'.'}   -- Add command compresses current dir by default
    end

    PostProcessOptions()

    -- Establish default option values
    if command.deduplication_mode then
        if command.buffer_size==0 then
            -- Default buffer_size = max dictionary of all compression methods
            MapCompressionGroups (function (method)
                command.buffer_size  =  max(command.buffer_size, GetMaxOfDictionary(method))
            end)
        else
            -- Limit all dictionaries to the buffer size, since no block can contain more data
            MapCompressionGroups (function (method)
                return MethodLimitDictionary(method, command.buffer_size)
            end)
        end
    end
    if command.buffer_size==0 then
        command.buffer_size = command.deduplication_mode and 16*mb or 1*mb
    end
    if command.io_threads < 0 then
        command.io_threads  = command.cache_size > 0  and  command.cache_size/command.buffer_size  or  1
    end
    if command.deduplication_mode then
        command.num_buffers = command.num_threads + command.io_threads
    else
        command.num_buffers = command.cache_size > 0  and  command.cache_size/command.buffer_size  or  command.num_threads
    end
end
