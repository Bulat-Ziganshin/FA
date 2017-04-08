-- My little debug aid
do local original = ParseCommandLine
function ParseCommandLine(...)
    local successful, result_or_errmsg = xpcall (original, debug.traceback, ...)
    if not successful  then error(result_or_errmsg)
    else return result_or_errmsg end
end end
