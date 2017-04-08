-- "Archive directory:..." is never displayed if directory is smaller than this size:
optvalue.ui_min_displayed_arcdir_size = 1e4

--[[ **********************************************************************************************************************************
*** Cmdline options controlling the UI ************************************************************************************************
*************************************************************************************************************************************]]
DISPLAY_ALL        = "haocmftdnwk"                      -- enabled by "-di" without parameters
DISPLAY_DEFAULT    = DISPLAY_ALL:remove_chars("ocmd")   -- enabled by default - TYPES not interesting for most of users are disabled
DISPLAY_EVERYTHING = DISPLAY_ALL.."el$#%"               -- full list of supported modes, including extra TYPES for profiling and unusual formatting

-- Check that display mode represented by the char `mode` is enabled
function display_mode(mode)
    return mode:one_of(optvalue.display or DISPLAY_DEFAULT)   -- use default settings while option isn't processed yet
end

-- Initialize optvalue.display depending on command.cmd
function init_display_mode()
    local DISPLAY_DEFAULT_BYCMD = is_barelist_command() and "w"                                 -- bare filelist
                                  or is_list_command()  and DISPLAY_DEFAULT:remove_chars("k")   -- don't print "All OK"
                                  or                        DISPLAY_DEFAULT
    optvalue.display = optvalue.display or DISPLAY_DEFAULT_BYCMD
end

function modify_display_mode(param)
    init_display_mode()
    local function set(value)  optvalue.display = value end
    local function add(value)  optvalue.display = optvalue.display..value end
    local function sub(value)  optvalue.display = optvalue.display:remove_chars(value) end

    local cmd,rest = param:match('(.)(.*)')
        if param==""    then set(DISPLAY_ALL)
    elseif param=="--"  then set(nil); init_display_mode()
    elseif cmd=='+'     then add(rest)
    elseif cmd=='-'     then sub(rest)
    elseif cmd=='='     then set(rest)
    else                     set(param)
    end
end

AddOption{'display', '-diTYPES --display=TYPES',
'select TYPES of information displayed ("'..DISPLAY_DEFAULT..'" by default, "'..DISPLAY_EVERYTHING..'" supported)',
modify_display_mode,
post_processing = function(name)
    init_display_mode()
    if display_mode('%')  then TestMalloc() end
    SetCompressionLibDebugMode (display_mode('$') and 1 or 0)
end}

AddOptions {
    {"no_warnings", "--no-warnings  --nowarnings",  "don't print warning messages to console, equivalent to '-di-w'",  function() modify_display_mode("-w") end},
    {"profiler",    "--profiler",                   "print internal profiling stats, equivalent to '-di+$'",           function() modify_display_mode("+$") end},
    {"logfile",     "--logfile=FILENAME",           "log file (empty filename to disable)",     OPTION_STRING},
    {"answer_yes",  "-y  --answer-yes --yes",       "answer Yes to all queries",                OPTION_BOOL},
}

AddOption {"overwrite",  "-oMODE --overwrite=MODE",  "existing files overwrite MODE (+/-/p)",
default_value = 'p',
function (param)
    if param:match('^[-+pP]$') then
        optvalue.overwrite = param:lower()
    else
        return "overwrite mode (-o) should be one of: '+', '-', 'p'"
    end
end}


--[[ **********************************************************************************************************************************
*** Main UI steps *********************************************************************************************************************
*************************************************************************************************************************************]]
-- Init fields that may be used by error/warning processing, since it may precede any on*Start event handlers
ui = ui or {warnings=0, errors=0, last_output_len=0}

onCommandStart ('UI', function()
    local cmdname = path.splitext(path.basename(command.argv0))
    WriteLog ("\n")  -- add empty line to delimit from loglines of previous runs
    WriteLog (string.format("[%s]  %s>%s %s\n", os.date('%a %b %d %X %Y'), Dir.GetCurrent(), cmdname, clear_sensitive_option_info(command.argv)))
end)

onArchiveStart ('UI', function()
    ui.GlobalTime0 = GetGlobalTime()
    ui.CpuTime0    = GetCpuTime()
    ui.KernelTime0 = GetKernelTime()
    ui.found_stats = nil  -- drop saved value at the archive start

    local function lower1(str)
        return str:sub(1,1):lower() .. str:sub(2)
    end

    -- Stupid code that combines enabled parts of output both for logfile and display
    local x1 = FA_VERSION_STR
    local x2 = string.format ("%sing archive %s", (is_add_command() and "Creat" or uiCmdName()), command.arcname)
    local x3 = ""
    if optvalue.additional_options and #optvalue.additional_options > 0 then
        x3 = string.format ("Using additional options: %s", clear_sensitive_option_info(optvalue.additional_options))
    end
    WriteLog (string.format ("%s %s%s\n", x1, lower1(x2), (x3>"" and " "..lower1(x3) or "")))

    local x = ""
    if display_mode('h')            then x = x1 end
    if display_mode('a')            then x = (x=="" and x2  or x..' '..lower1(x2)) end
    if display_mode('o') and x3>""  then x = (x=="" and x3  or x..' '..lower1(x3)) end
    if x>"" then uiPrint(x..'\n') end
end)

-- Almost the same as onArchiveDone+onArchiveStart
onSubCommandStart ('UI', function()
    ui.GlobalTime0 = GetGlobalTime()
    ui.CpuTime0    = GetCpuTime()
    ui.KernelTime0 = GetKernelTime()
end)

onCommandDone ('UI', function()
    uiPrint('')  -- get rid of transient message
    if ui.warnings > 0 then
        uiPrintFmtAndLog('n', "There were %d warning(s)\n", ui.warnings)
    elseif ui.errors == 0 then
        uiPrintAndLog('k', "All OK\n")
    end
    ui.warnings, ui.errors = 0,0
    if display_mode('e') then uiPrint("\n") end
end)

-- Transient messages should be overwritten with later messages
function uiTransientMessage(msg)
    EnvSetConsoleTitle(msg)
    uiPrintTransientMessage(msg)
end


--[[ **********************************************************************************************************************************
*** Printings stats before and after compression/extraction ***************************************************************************
*************************************************************************************************************************************]]

onCompressionStart ('UI', function()
    local cmethods, cgroups, ui_method  =  command.compression_methods, command.compression_groups, ""
    ui.origsize, ui.compsize, ui.allocated, ui.min_dmem = 0,0,0,0
    if command.no_data  then return end  -- no data will be compressed at all

    -- Display compression method
    for i,group in ipairs(cgroups) do
        local method = cmethods[i]
        if ui_method > ""  then ui_method = ui_method..", " end
        if group     > ""  then ui_method = ui_method..group.." => " end
        ui_method = ui_method..method
    end
    uiPrintFmtAndLog('c', "Compress with %s\n", ui_method)

    -- Display memory usage
    cmethods = List(cmethods)
    local  cmem = cmethods:map(GetSumOfCompressionMem)     :reduce(max)
    ui.min_dmem = cmethods:map(GetSumOfMinDecompressionMem):reduce(max)
    local  dmem = cmethods:map(GetSumOfDecompressionMem)   :reduce(max)

    local prefetch_str = ""
    if command.prefetch_threads > 0 then
        prefetch_str = string.format(".  Prefetch %s using %d thread%s",
            showMem(command.prefetch_cache),
            command.prefetch_threads,
            (command.prefetch_threads~=1 and "s" or ""))
    end

    if archive.deduplication_mode then
        local num_buffers = command.num_threads+command.num_buffers+1
        uiPrintFmtAndLog('m', "Using %d threads * %dmb + %d * %s I/O buffers = total %dmb,  %s..%s.. chunks%s\n",
            command.num_threads, cmem//mb,
            num_buffers, showMem(command.buffer_size),
            (command.num_threads*cmem + num_buffers*command.buffer_size)//mb,
            showMem(command.min_chunk), showMem(command.chunk_size), prefetch_str)
    else
        local dmem_str = string.format (ui.min_dmem==dmem and "%d" or "%d..%d", ui.min_dmem//mb, dmem//mb)
        uiPrintFmtAndLog('m', "Compression memory %dmb + %d*%s read-ahead buffers, decompression memory %s MiB%s\n",
            cmem//mb, command.num_buffers, showMem(command.buffer_size), dmem_str, prefetch_str)
    end
end)

onCompressionDone ('UI', function (stat, decompression_memory)
    local compsize_str, shasize_str, ram_str = "", "", ""
    local origsize = stat.footer_origsize + stat.dir_origsize + stat.dedup_origsize
    local compsize = stat.footer_compsize + stat.dir_compsize + stat.dedup_compsize

    if compsize+stat.sha_size < optvalue.ui_min_displayed_arcdir_size  then return end

    if origsize ~= compsize  then compsize_str = string.format (" -> %s", show3(compsize)) end
    if stat.sha_size > 0     then shasize_str  = string.format (", SHA hashes: %s bytes", show3(stat.sha_size)) end

    if archive.deduplication_mode then
        ram_str = string.format(".  Decompression memory: %s + N*%s = %s..%s MiB",
            show3(roundUp(decompression_memory,mb)/mb),
            show3(roundUp(ui.min_dmem,mb)/mb),
            show3(roundUp(decompression_memory+ui.min_dmem,mb)/mb),
            show3(roundUp(decompression_memory+command.num_threads*ui.min_dmem,mb)/mb))
    end

    uiPrintFmtAndLog('d', "Archive directory: %s%s bytes%s%s\n", show3(origsize), compsize_str, shasize_str, ram_str)
end)

onExtractionStart ('UI', function (stats)
    -- Don't print this line if stats are the same as were printed in the Found line
    if ui.found_stats ~= string.format('%d %d %d', stats.bytes, stats.dirs, stats.files) then
        uiPrintFmtAndLog("", "%s %s bytes in %s folders and %s files\n",
            uiCmdName()..'ing', show3(stats.bytes), show3(stats.dirs), show3(stats.files))
    end
end)


--[[ **********************************************************************************************************************************
*** Progress indicator ****************************************************************************************************************
*************************************************************************************************************************************]]

-- Update the progress indicator with new operation state. Called asynchronously from C++ every command.ui_progress_interval seconds
function uiProgress(state)
    for k,v in pairs(state) do
        ui[k] = v
    end

    if not ui.StageStart_GlobalTime then
        ui.StageStart_GlobalTime = GetGlobalTime() - ui.GlobalTime0
        ui.last_output_len = 0
    end

    uiUpdateProgressIndicator()

    if ui.final then
        ui.StageStart_GlobalTime = nil
        uiFlushProgressIndicator()
    end
end

-- Make a pause in the progress indicator to display other information
function uiFlushProgressIndicator()
    if ui.last_output_len > 0  then uiPrint("\n") end
    ui.last_output_len = 0
end

-- Clear progress indicator on the current line, preparing it to display some other information
function uiClearProgressIndicator()
    if ui.last_output_len > 0  then uiPrint('\r'..string.rep(' ',ui.last_output_len)..'\r') end
    ui.last_output_len = 0
end

-- Output to console current state of the progress indicator
function uiUpdateProgressIndicator()
    local outputs, output, console_title = {}  -- displayed in the current console line and console title, correspondingly
    local GlobalTime = GetGlobalTime() - ui.GlobalTime0
    local CpuTime    = GetCpuTime()    - ui.CpuTime0
    local KernelTime = GetKernelTime() - ui.KernelTime0
    local stage = ui.stage
    local final = ui.final
    local time_digits = (final and 2 or 0)

    if stage=='SCAN_DISK' then
        console_title = string.format("%s%s bytes in %s folders and %s files",
                            final and 'Found ' or 'Scanning: ',
                            show3(ui.totalsize), show3(ui.dirs), show3(ui.files))
        if display_mode('l') then
            output = string.format("%s  (RAM %s MiB, I/O %.3f sec, cpu %.3f sec, real %.3f sec)",
                                console_title, show3(roundUp(ui.allocated,mb)/mb), KernelTime, CpuTime, GlobalTime)
        elseif GlobalTime > 1 then
            output = string.format("%s (%."..time_digits.."f sec)", console_title, GlobalTime)
        else
            output = console_title
        end

        if final then
            -- Store totals so we can avoid pinting them again on -t
            ui.found_stats = string.format('%d %d %d', ui.totalsize, ui.dirs, ui.files)
        end

    elseif stage=='COMPRESS' or stage=='EXTRACT' then
        local COMPRESSION = (stage=='COMPRESS')
        local origsize    = ui.origsize
        local compsize    = ui.compsize
        local totalsize   = ui.totalsize
        local allocated   = ui.allocated
        local ram         = ui.ram
        local max_ram     = ui.max_ram

        local percents     = totalsize>0 and math.floor(origsize/totalsize*100.0) or 100
        local remain       = origsize >0 and math.ceil((totalsize-origsize)/origsize * (GlobalTime - ui.StageStart_GlobalTime)) or 0
        local percent_str  = final and uiCmdName()..'ed: '  or  string.format("%d%%: ", percents)
        local remains_hour = string.format("%02d:", remain // 3600)
        local remains_time = string.format("%s%02d:%02d", (remain>=3600 and remains_hour or ""), (remain//60) % 60, remain % 60)
        local remains      = string.format(".  ETA %s", remains_time)

        local dedupsize_str, ram_str = "",""
        if archive.deduplication_mode then
            dedupsize_str = string.format("%s -> ", show3(ui.dedupsize))
            if COMPRESSION then
                ram_str = string.format("RAM %s MiB.  ", show3(roundUp(allocated,mb)/mb))
            else
                ram_str = string.format("RAM %s / %s MiB.  ", show3(roundUp(ram,mb)/mb),  show3(roundUp(max_ram,mb)/mb))
            end
        end

        local leftsize    = COMPRESSION and origsize or compsize
        local rightsize   = COMPRESSION and compsize or origsize
        local CpuSpeed    = CpuTime   >0 and (origsize/CpuTime)/mb    or 0
        local GlobalSpeed = GlobalTime>0 and (origsize/GlobalTime)/mb or 0
        local CpuLoad     = string.format("%.0f%%", GlobalTime>0 and (CpuTime/GlobalTime)*100.0 or 0)
        local ratio       = string.format("%.2f%%", origsize>0 and compsize/origsize*100.0 or 0)
        local ETA         = (final or remain<0) and "" or remains
        local function digits(x)  return x<0.999 and 3  or x<9.99 and 2  or x<99.9 and 1  or  0  end
        local CpuSpeedStr    = string.format("%."..digits(CpuSpeed)   .."f", CpuSpeed)
        local GlobalSpeedStr = string.format("%."..digits(GlobalSpeed).."f", GlobalSpeed)

        if display_mode('l') then
            output = string.format("%s%s -> %s%s: %s.  %sI/O %.3f sec, cpu %s MiB/s (%.3f sec), real %s MiB/s (%.3f sec) = %s%s",
                             percent_str, show3(leftsize), dedupsize_str, show3(rightsize), ratio,
                             ram_str, KernelTime, CpuSpeedStr, CpuTime, GlobalSpeedStr, GlobalTime, CpuLoad, ETA)

        elseif final and (display_mode('f') or display_mode('t')) then
            if display_mode('f') then
                -- Compressed: 21,000 -> 6,290 bytes. Ratio 29.95%
                table.insert (outputs, string.format("%s%s -> %s bytes. Ratio %s",
                                                     percent_str, show3(leftsize), show3(rightsize), ratio))
            end
            if display_mode('t') then
                -- Compression time: cpu 0.00 sec/real 0.06 sec = 0%. Speed 0.35 mB/s
                table.insert (outputs, string.format("%s time: cpu %.2f sec/real %.2f sec = %s. Speed %s MiB/s",
                                                     uiOperationName(), CpuTime, GlobalTime, CpuLoad, GlobalSpeedStr))
            end
            output = table.remove (outputs, 1)

        else
            -- 12%: 51 -> 12 MiB: 23.19%.  26.2 MiB/s = 99% (2 sec).  ETA 00:15
            output = string.format("%s%s -> %s%s: %s.  %s MiB/s = %s (%."..time_digits.."f sec)%s",
                             percent_str,
                             show3(final and leftsize or leftsize//1048576),
                             show3(final and rightsize or rightsize//1048576),
                             final and "" or " MiB", ratio,
                             GlobalSpeedStr, CpuLoad, GlobalTime, ETA)
        end

        console_title = string.format("%d%% %s | %s %s", percents, remains_time, uiCmdName(), command.arcname)
        Taskbar_SetProgressValue (origsize, totalsize)
    else
        return  -- other stages don't display the progress indicator
    end

    EnvSetConsoleTitle (console_title)
    if final  then WriteLog(output.."\n") end

    -- Append to the output as much spaces as required to clean up remainder of previous longer line
    local output_len = output:len()
    if output_len < ui.last_output_len then
        local extra = ui.last_output_len-output_len
        output = output..string.rep(' ',extra)..string.rep('\b',extra)
    end
    ui.last_output_len = output_len
    uiPrint ("\r"..output)

    -- Display and log the remaining lines
    for _,line in ipairs(outputs) do
        uiFlushProgressIndicator()
        uiPrintAndLog("", line.."\n")
    end
end


--[[ **********************************************************************************************************************************
*** Requests to the user **************************************************************************************************************
*************************************************************************************************************************************]]
-- List of answers allowed to the file overwrite question
ANSWER_YES  = 'y'   -- overwrite current file
ANSWER_ALL  = 'a'   -- overwrite all files
ANSWER_NO   = 'n'   -- skip current file
ANSWER_SKIP = 's'   -- skip all files
ANSWER_QUIT = 'q'   -- quit program

-- Ask user if necessary and return one of the allowed answers
function uiAskOverwrite (outname)
    local commented_answers = "(Y)es / (N)o / (A)lways / (S)kip all / (Q)uit"
    local valid_answers = table.concat (
              { ""
              , "  Valid answers are:"
              , "    y - yes"
              , "    n - no"
              , "    a - always, answer yes to all remaining queries"
              , "    s - skip, answer no to all remaining queries"
              , "    q - quit program"
              , ""
              , ""}, "\n")

    if optvalue.answer_yes or optvalue.overwrite=='+' then
        return ANSWER_ALL
    end
    if optvalue.overwrite=='-' then
        return ANSWER_SKIP
    end

    uiFlushProgressIndicator()

    while true do
        local question = string.format("Overwrite file %s", outname)
        uiPrint("  "..question.."?\n  "..commented_answers.."? ")
        local answer = io.read()
        if not answer then   -- EOF of stdin (probably redirected to file)
            return ANSWER_SKIP
        end
        answer = answer:lower()
        if answer:match("^[yansq]$") then
            return answer
        end
        uiPrint(valid_answers)
    end
end


--[[ **********************************************************************************************************************************
*** Errors, warnings and profiling ****************************************************************************************************
*************************************************************************************************************************************]]

-- Format/translate message and fire the Warning event
function uiWarning (warning, ...)
    local tab = {
            FAILED_FILE_OPEN = 'can\'t open file "%s"',
            FAILED_DIR_OPEN  = 'can\'t open directory "%s"',
            FAILED_STAT      = 'can\'t get information about file/directory "%s"',
            NOT_FOUND        = 'file/directory "%s" not found',
            CANT_CREATE_FILE = 'can\'t create file "%s"',
            BAD_CRC          = 'file "%s" failed CRC check. File is broken.',
            BAD_OPTION_TYPE  = 'Invalid option type: "%s"',
        }
    assert (tab[warning], 'Unknown warning type "'..warning..'"')
    RunEvent.Warning (string.format(tab[warning],...))
end

-- Format/translate message and fire the Error event
function uiError (message, ...)
    RunEvent.Error (string.format(message,...))
end

-- Display and log the warning message
onWarning('UI', function(message)
    if display_mode('w') then uiClearProgressIndicator() end  -- reuse progress indicator line for the warning message
    uiPrintFmtAndLog('w', "WARNING: %s\n", message)
    ui.warnings = ui.warnings+1
end)

-- Save error message to logfile. The message isn't printed to console here since the host c++ program does it itself,
-- to ensure that message will be shown even if Lua state is seriously broken.
onError('UI', function(message)
    uiFlushProgressIndicator()  -- ensure that the next printed string will start from column 1
    uiPrint('')  -- get rid of transient message
    WriteLog ("  ERROR! "..message.."\n")
    ui.errors = ui.errors+1
end)

-- Display how much time was spent since the last call to this routine
function uiProfiler (label)
    local GlobalTime, CpuTime, KernelTime  =  GetGlobalTime(), GetCpuTime(), GetKernelTime()

    local message
    if not label then
        message = "\n"   -- on the first call, skip to next line just for the case when current line shows the progress indicator
    else
        message = string.format("%s  %.3f %.3f  %.3f %.3f  %.3f %.3f\n", label,
            GlobalTime-ui.profiler.LastGlobalTime, GlobalTime-ui.profiler.GlobalTime0,
            KernelTime-ui.profiler.LastKernelTime, KernelTime-ui.profiler.KernelTime0,
            CpuTime   -ui.profiler.LastCpuTime,    CpuTime   -ui.profiler.CpuTime0)
    end

    if display_mode('#')  then WriteLog(message) end
    if display_mode('$')  then uiPrint(message) end

    -- Save base for the next measurement
    ui.profiler = ui.profiler or {}
    ui.profiler.LastGlobalTime = GlobalTime;  ui.profiler.LastKernelTime = KernelTime;  ui.profiler.LastCpuTime = CpuTime
    if not label  then ui.profiler.GlobalTime0 = GlobalTime;  ui.profiler.KernelTime0 = KernelTime;  ui.profiler.CpuTime0 = CpuTime end
end


--[[ **********************************************************************************************************************************
*** Console I/O and logging ***********************************************************************************************************
*************************************************************************************************************************************]]

function uiPrintFmtAndLog (mode, ...)
    uiPrintAndLog (mode, string.format(...))
end

function uiPrintFmt (...)
    uiPrint(string.format(...))
end

function uiPrintAndLog (mode, str)
    WriteLog (str)
    if display_mode(mode) then
        uiPrint(str)
    end
end

function uiPrint (str)
    uiPrintTransientMessage(str)
    ui.last_transient_msg_len = nil
end

function uiPrintTransientMessage (str)
    local old_len = ui.last_transient_msg_len
    local new_len = str:len()
    ui.last_transient_msg_len = new_len

    if old_len==nil  then
        uiPrintInternal(str)
    else
        -- Append to the str as much spaces as required to clean up remainder of previous longer line
        if new_len < old_len then
            local extra_spaces = old_len - new_len
            str = str .. string.rep(' ',extra_spaces) .. string.rep('\b',extra_spaces)
        end
        uiPrintInternal ("\r"..str)
    end
end


if GetConsoleScreenBufferInfo and GetConsoleScreenBufferInfo() then
    function uiPrintInternal (str)  WriteConsole(str) end
else
    -- Alternative way to print strings. stderr can be redirected, but default console CP is non-Unicode
    function uiPrintInternal (str)  io.stderr:write(str) end
end


-- Save message to log, if it was specified by the --logfile option
function WriteLog(message)
    if optvalue.logfile and optvalue.logfile~="" then
        if not ui.logfile then
            ui.logfile = assert (File.open (optvalue.logfile, "a"))
            ui.logfile:setvbuf('no')
        end
        local pid_str = GetPID()..': '
        ui.logfile:write (message:match("^[\n]*$") and message or pid_str..message)
    end
end

-- Close the logfile at the end of command execution
onCommandDone ('Log', LOW_PRIORITY, function()
    if ui.logfile then
        ui.logfile:close()
        ui.logfile = nil
    end
end)


--[[ **********************************************************************************************************************************
*** Auxiliary functions ***********************************************************************************************************
*************************************************************************************************************************************]]

-- Remove from the option_list sensitive information, such as passwords, and concat the result
function clear_sensitive_option_info(option_list)
    local function clear_option(option)
        for _, head in ipairs{'-p', '-op', '-hp'} do
            if option:sub(1,#head) == head then
                local remainder = option:sub(#head+1)
                local hide = (remainder~="" and remainder~="-" and remainder~="?")
                return hide and head.."???" or option
            end
        end
        return option
    end
    return tablex.imap(clear_option, option_list):concat(' ')
end

-- Textual description of currently executed subcommand
function uiCmdName()
    return is_add_command()     and "Compress"
        or is_list_command()    and "List"
        or is_test_command()    and "Test"
        or is_extract_command() and "Extract"
                                or  "Process"
end

function uiOperationName()
    return is_add_command()     and "Compression"
        or is_list_command()    and "Listing"
        or is_test_command()    and "Testing"
        or is_extract_command() and "Extraction"
                                or  "Processing"
end
