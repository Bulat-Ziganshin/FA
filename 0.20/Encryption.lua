DEFAULT_ENCRYPTION_METHOD = "aes"  -- default setting of '--encryption' option

--[[ **********************************************************************************************************************************
*** Handling of encryption algorithms *************************************************************************************************
*************************************************************************************************************************************]]
EncryptionGet = CompressionGet
EncryptionIs = CompressionIs

-- Check whether it's an encryption method
function is_encryptor (compressor)
    return CompressionIs (compressor, "encryption?")
end

-- Map each encryptor in the `method` through `filter_f`, removing empty strings from result.
-- Nil returned from `filter_f` keeps the encryptor intact.
function map_encryptors (method, filter_f, ...)
    local function f (encryptor, ...)
        if is_encryptor(encryptor)  then return filter_f (encryptor, ...) end
    end
    return map_compressors (method, f, ...)
end

-- Derive encryption key and checkCode from password+salt
function derive_key (encryptor, password, salt, checkCodeSize)
    local numIterations = EncryptionGet (encryptor, "numIterations")
    local keySize = EncryptionGet (encryptor, "keySize")
    local result = Pbkdf2Hmac (password, salt, numIterations, keySize+checkCodeSize)
    return result:sub(1,keySize), result:sub(keySize+1)
end

-- Generate salt/key/checkCode for the new encryption algo
function generate_encryption (encryptor, password)
    local salt = GenerateRandomBytes (EncryptionGet (encryptor, "keySize"))
    local checkCodeSize = 2  -- it's always 2 bytes
    local key, checkCode = derive_key (encryptor, password, salt, checkCodeSize)
    return encryptor..":f:s"..encode16(salt)..":k"..encode16(key)..":c"..encode16(checkCode)   -- to do: ":f" require FreeArc > "0.666" for decompression
end

-- Add IV to the new instance of encryption algo
function prepare_encryption (encryptor)
    local initVector = GenerateRandomBytes (EncryptionGet (encryptor, "ivSize"))
    return encryptor..":i"..encode16(initVector)
end

-- Remove key from encryption algo prior to displaying or storing in the archive directory
function remove_encryption_key (encryptor)
    return remove_param(encryptor,"k")
end

-- Derive key and verify checkCode prior to decryption
function prepare_decryption (encryptor, password)
    local salt = decode16(get_param(encryptor,"s"))
    local checkCode = decode16(get_param(encryptor,"c"))
    local key, derivedCheckCode = derive_key (encryptor, password, salt, #checkCode)
    return  encryptor..":k"..encode16(key),  checkCode==derivedCheckCode
end


--[[ **********************************************************************************************************************************
*** Encryption options ****************************************************************************************************************
*************************************************************************************************************************************]]
AddOption{'encryption',       '-aeALGORITHM   --encryption=ALGORITHM',                                    'encryption ALGORITHM (aes, blowfish, serpent, twofish, aes+serpent...)', OPTION_STRING}
AddOption{'password',         '-p[PASSWORD]   --password=PASSWORD',                                       'encrypt/decrypt compressed data using PASSWORD', OPTION_STRING}
AddOption{'keyfile',          '-kfKEYFILE     --keyfile=KEYFILE',                                         'encrypt/decrypt using KEYFILE (with or without password)', OPTION_STRING}
AddOption{'old_password',     '-opPASSWORD    --old-password=PASSWORD     --OldPassword=PASSWORD',        'old PASSWORD used only for decryption', OPTION_LIST}
AddOption{'old_keyfile',      '-okfKEYFILE    --old-keyfile=KEYFILE       --OldKeyfile=KEYFILE',          'old KEYFILE used only for decryption', OPTION_LIST}
AddOption{'headers_password', '-hp[PASSWORD]  --headers-password=PASSWORD --HeadersPassword=PASSWORD',    'encrypt/decrypt archive headers and data using PASSWORD', OPTION_STRING}

-- All encryption options are handled here
onPostOption ('Encryption', LOWEST_PRIORITY, function ()
    optvalue.old_password = optvalue.old_password or {}
    optvalue.old_keyfile_data = {}
    for _,keyfile in ipairs(optvalue.old_keyfile or {}) do
        table.insert (optvalue.old_keyfile_data, File.read_binary(keyfile))
    end

    -- Data encryption enabled if any of -p/-hp/-kf is present
    if optvalue.password or optvalue.headers_password or optvalue.keyfile then
        -- -pPWD1 -hpPWD2: pwd1 used for data, pwd2 used for headers
        -- -pPWD -hp / -hpPWD: pwd used for both data and headers
        -- -pPWD: pwd used for data, headers remain unencrypted
        -- -p / -hp / -p -hp: ask user for password(s) - not yet implemented
        optvalue.password     = optvalue.password or ''
        optvalue.password     = optvalue.password~='' and optvalue.password or optvalue.headers_password
        optvalue.keyfile_data = optvalue.keyfile and File.read_binary(optvalue.keyfile) or ''

        assert (optvalue.password~='' or optvalue.keyfile, "No password nor keyfile")
        if optvalue.password~='' then table.insert (optvalue.old_password,     optvalue.password)     end
        if optvalue.keyfile      then table.insert (optvalue.old_keyfile_data, optvalue.keyfile_data) end

        optvalue.encryption          = optvalue.encryption or DEFAULT_ENCRYPTION_METHOD
        optvalue.encryption_password = optvalue.password..optvalue.keyfile_data
        optvalue.encryption_with_key = map_encryptors (optvalue.encryption, generate_encryption, optvalue.encryption_password)

        -- Add encryption to data block compression operation
        onCompressDataBlockMethod ('Encryption', function(method)
            return method.."+"..map_encryptors (optvalue.encryption_with_key, prepare_encryption)
        end)

        -- Headers encryption enabled only when -hp is present
        if optvalue.headers_password then
            if optvalue.headers_password~='' and optvalue.headers_password~=optvalue.password then
                table.insert (optvalue.old_password, optvalue.headers_password)
            end
            optvalue.headers_password            = optvalue.headers_password~='' and optvalue.headers_password or optvalue.password
            optvalue.headers_encryption_password = optvalue.headers_password..optvalue.keyfile_data
            optvalue.headers_encryption_with_key = map_encryptors (optvalue.encryption, generate_encryption, optvalue.headers_encryption_password)

            -- Add encryption to archive header compression operation
            onCompressHeaderBlockMethod ('Encryption', function(method)
                return method.."+"..map_encryptors (optvalue.headers_encryption_with_key, prepare_encryption)
            end)
        end
    end
end)

-- Remove encryption keys from method for displaying purposes
onDisplayMethod ('Encryption', function(method)
    return map_encryptors (method, remove_encryption_key)
end)

-- Called for each solid block going to Decompress()
onExtractBlockMethod ('Encryption', function(method)
    -- to do: cache successful salt+checkCode -> key mappings, move successful passwords/keyfiles to the top of list
    return map_encryptors (method, function(encryptor)
            for _,password in ipairs (optvalue.old_password) do
                local new_encryptor, verified = prepare_decryption (encryptor, password)
                if verified then return new_encryptor end
            end
            for _,keyfile in ipairs (optvalue.old_keyfile_data) do
                local new_encryptor, verified = prepare_decryption (encryptor, keyfile)
                if verified then return new_encryptor end
            end
            for _,password in ipairs (optvalue.old_password) do
                for _,keyfile in ipairs (optvalue.old_keyfile_data) do
                    local new_encryptor, verified = prepare_decryption (encryptor, password..keyfile)
                    if verified then return new_encryptor end
                end
            end
            error ("No password/keyfile pair succeed at decryption of "..encryptor)
        end)
end)
