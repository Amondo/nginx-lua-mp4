local config = require('config')
local log = require('log')
local utils = require('utils')

log('luamp started')

-- Set missing config options to the defaults
config.setDefaults({
    minimumTranscodedVideoSize = 1024,
    serveOriginalOnTranscodeFailure = true,
    ffmpegPreset = ''
})

-- Get URL params
local mediaType = ngx.var.luamp_media_type
local prefix = utils.cleanupPath(ngx.var.luamp_prefix)
local flags = ngx.var.luamp_flags
local postfix = utils.cleanupPath(ngx.var.luamp_postfix)
local mediaId = utils.cleanupPath(ngx.var.luamp_media_id)
local mediaExtension = ngx.var.luamp_media_extension
local filename = mediaId .. '.' .. mediaExtension

log('MediaType: ' .. mediaType)
log('Prefix: ' .. prefix)
log('Postfix: ' .. postfix)
log('Flags: ' .. flags)
log('MediaId: ' .. mediaId)
log('MediaExtension: ' .. mediaExtension)

-- Initialize flag-related variables
local flagValues = {}
local flagOrdered = {}
local enabledFlags = {
    crop = true,
    background = true,
    dpr = true,
    -- format = true,
    height = true,
    width = true,
    x = true,
    y = true,
}

-- Parse flags into a table
for flag, value in string.gmatch(flags, '(%w+)' .. config.flagValueDelimiter .. '([^' .. config.flagsDelimiter .. '\\/]+)' .. config.flagsDelimiter .. '*') do
    -- Check if the flag is enabled
    if value ~= nil and enabledFlags[config.flagMap[flag]] ~= nil then
        -- Preprocess the flag and value if necessary
        if config.flagPreprocessHook ~= nil then
            flag, value = config.flagPreprocessHook(flag, value)
        end
        log(config.flagMap[flag] .. ' ' .. value)
        -- Add the flag to the ordered list
        table.insert(flagOrdered, config.flagMap[flag])
        -- Check if it is an allowed text flag or cast to a number
        if config.flagValueMap[value] ~= nil then
            flagValues[config.flagMap[flag]] = config.flagValueMap[value] -- Add allowed text flag
        else
            flagValues[config.flagMap[flag]] = tonumber(value)            -- Cast to number
        end
    end
end

-- Sort flags so path will be the same for `w_1280,h_960` and `h_960,w_1280`
table.sort(flagOrdered)

-- Coalesce flag values
local function coalesceFlag(option)
    if flagValues[option] ~= nil then
        return option .. '_' .. flagValues[option]
    else
        return ''
    end
end

-- Generate the options path
local options = {}
local optionsPath = ''

for _, option in ipairs(flagOrdered) do
    table.insert(options, coalesceFlag(option))
end

optionsPath = table.concat(options, '/')
if optionsPath ~= '' then
    optionsPath = optionsPath .. '/'
end

-- check if we already have cached version of a file
local originalFilepath = config.mediaBaseFilepath .. (prefix or '') .. (postfix or '')
local cachedFilepath = originalFilepath .. (optionsPath or '')
log('checking for cached transcoded version at: ' .. cachedFilepath .. filename)
local cachedFile = io.open(cachedFilepath .. filename, 'r')

if cachedFile == nil then
    log('no cached file')
    -- create cached version

    -- check if we have original file to transcode
    log('checking for original version at: ' .. originalFilepath .. filename)
    local originalFileCheck = io.open(originalFilepath .. filename)

    -- check if we have original
    if not originalFileCheck then
        log('no original')
        if config.downloadOriginals then
            -- download original, if upstream download is enabled
            log('downloading original from ' .. config.getOriginalsUpstreamPath(prefix, postfix, filename))
            -- clear body
            ngx.req.discard_body()
            log('fetching')
            -- fetch
            local originalReq = ngx.location.capture('/luamp-upstream',
                { vars = { luamp_original_file = config.getOriginalsUpstreamPath(prefix, postfix, filename) } })
            log('upstream status: ' .. originalReq.status)
            if originalReq.status == ngx.HTTP_OK and originalReq.body:len() > 0 then
                log('downloaded original, saving')
                os.execute('mkdir -p ' .. originalFilepath)
                local originalFile = io.open(originalFilepath .. filename, 'w')
                originalFile:write(originalReq.body)
                originalFile:close()
                log('saved to ' .. originalFilepath .. filename)
            else
                ngx.exit(ngx.HTTP_NOT_FOUND)
            end
        else
            ngx.exit(ngx.HTTP_NOT_FOUND)
        end
    else
        log('original is present on local FS')
        originalFileCheck:close()
    end

    -- process DPR
    if (flagValues['dpr'] ~= nil) then
        log('before DPR calculation, w: ' ..
            (flagValues['width'] or 'nil') ..
            ', h: ' ..
            (flagValues['height'] or 'nil') ..
            ', x: ' .. (flagValues['x'] or 'nil') .. ', y: ' .. (flagValues['y'] or 'nil'))
        -- width and height
        if flagValues['height'] ~= nil then
            flagValues['height'] = math.ceil(flagValues['height'] * flagValues['dpr'])
        end
        if flagValues['width'] ~= nil then
            flagValues['width'] = math.ceil(flagValues['width'] * flagValues['dpr'])
        end

        -- x and y
        if flagValues['x'] ~= nil and flagValues['x'] >= 1 then
            flagValues['x'] = flagValues['x'] * flagValues['dpr']
        end
        if flagValues['y'] ~= nil and flagValues['y'] >= 1 then
            flagValues['y'] = flagValues['y'] * flagValues['dpr']
        end
        log('after DPR calculation, w: ' ..
            (flagValues['width'] or 'nil') ..
            ', h: ' ..
            (flagValues['height'] or 'nil') ..
            ', x: ' .. (flagValues['x'] or 'nil') .. ', y: ' .. (flagValues['y'] or 'nil'))
    end

    if config.maxVideoHeight ~= nil and flagValues['height'] ~= nil then
        if flagValues['height'] > config.maxVideoHeight then
            log('resulting height exceeds configured limit, capping it at ' .. config.maxVideoHeight)
            flagValues['height'] = config.maxVideoHeight
        end
    end

    if config.maxVideoWidth ~= nil and flagValues['width'] ~= nil then
        if flagValues['width'] > config.maxVideoWidth then
            log('resulting width exceeds configured limit, capping it at ' .. config.maxVideoWidth)
            flagValues['width'] = config.maxVideoWidth
        end
    end

    -- calculate absolute x/y for values in (0, 1) range
    if flagValues['x'] ~= nil and flagValues['x'] > 0 and flagValues['x'] < 1 then
        flagValues['x'] = flagValues['x'] * flagValues['width']
        log('absolute x: ' .. flagValues['x'])
    end
    if flagValues['y'] ~= nil and flagValues['y'] > 0 and flagValues['y'] < 1 then
        flagValues['y'] = flagValues['y'] * flagValues['height']
        log('absolute y: ' .. flagValues['y'])
    end

    local preset = ''
    -- setting x264 preset
    if (config['ffmpegPreset'] ~= '') then
        log('x264 preset: ' .. config['ffmpegPreset'])
        preset = ' -preset ' .. config['ffmpegPreset'] .. ' '
    end

    log('transcoding to ' .. cachedFilepath .. filename)

    -- create cached transcoded file
    os.execute('mkdir -p ' .. cachedFilepath)

    -- create command
    local command

    if (flagValues['background'] ~= nil and flagValues['background'] == 'blur' and flagValues['crop'] ~= nil and flagValues['crop'] == 'limited_padding' and flagValues['width'] ~= nil and flagValues['height'] ~= nil) then
        -- scale + padded (no upscale) + blurred bg
        command = config.ffmpeg ..
            ' -i ' ..
            originalFilepath ..
            filename ..
            ' -filter_complex "split [first][second];[first]hue=b=-1,boxblur=20, scale=max(' ..
            flagValues['width'] ..
            '\\,iw*(max(' ..
            flagValues['width'] ..
            '/iw\\,' ..
            flagValues['height'] ..
            '/ih))):max(' ..
            flagValues['height'] ..
            '\\,ih*(max(' ..
            flagValues['width'] ..
            '/iw\\,' ..
            flagValues['height'] ..
            '/ih))):force_original_aspect_ratio=increase:force_divisible_by=2, crop=' ..
            flagValues['width'] ..
            ':' ..
            flagValues['height'] ..
            ', setsar=1[background];[second]scale=min(' ..
            flagValues['width'] ..
            '\\,iw):min(' ..
            flagValues['height'] ..
            '\\,ih):force_original_aspect_ratio=decrease:force_divisible_by=2,setsar=1[foreground];[background][foreground]overlay=y=' ..
            (flagValues['y'] or '(H-h)/2') ..
            ':x=' .. (flagValues['x'] or '(W-w)/2') .. '" -c:a copy ' .. preset .. cachedFilepath .. filename
    elseif (flagValues['background'] ~= nil and flagValues['background'] == 'blur' and flagValues['crop'] ~= nil and flagValues['crop'] == 'padding' and flagValues['width'] ~= nil and flagValues['height'] ~= nil) then
        -- scale + padded (with upscale) + blurred bg
        command = config.ffmpeg ..
            ' -i ' ..
            originalFilepath ..
            filename ..
            ' -filter_complex "split [first][second];[first]hue=b=-1,boxblur=20, scale=max(' ..
            flagValues['width'] ..
            '\\,iw*(max(' ..
            flagValues['width'] ..
            '/iw\\,' ..
            flagValues['height'] ..
            '/ih))):max(' ..
            flagValues['height'] ..
            '\\,ih*(max(' ..
            flagValues['width'] ..
            '/iw\\,' ..
            flagValues['height'] ..
            '/ih))):force_original_aspect_ratio=increase:force_divisible_by=2, crop=' ..
            flagValues['width'] ..
            ':' ..
            flagValues['height'] ..
            ', setsar=1[background];[second]scale=min(' ..
            flagValues['width'] ..
            '\\,iw*(min(' ..
            flagValues['width'] ..
            '/iw\\,' ..
            flagValues['height'] ..
            '/ih))):min(' ..
            flagValues['height'] ..
            '\\,ih*(min(' ..
            flagValues['width'] ..
            '/iw\\,' ..
            flagValues['height'] ..
            '/ih))):force_original_aspect_ratio=increase:force_divisible_by=2,setsar=1[foreground];[background][foreground]overlay=y=' ..
            (flagValues['y'] or '(H-h)/2') ..
            ':x=' .. (flagValues['x'] or '(W-w)/2') .. '" -c:a copy ' .. preset .. cachedFilepath .. filename
    elseif (flagValues['crop'] ~= nil and flagValues['crop'] == 'limited_padding' and flagValues['width'] ~= nil and flagValues['height'] ~= nil) then
        -- scale (no upscale) with padding (blackbox)
        command = config.ffmpeg ..
            ' -i ' ..
            originalFilepath ..
            filename ..
            ' -filter_complex "scale=min(' ..
            flagValues['width'] ..
            '\\,iw):min(' ..
            flagValues['height'] ..
            '\\,ih):force_original_aspect_ratio=decrease:force_divisible_by=2,setsar=1,pad=' ..
            flagValues['width'] ..
            ':' ..
            flagValues['height'] ..
            ':y=' ..
            (flagValues['y'] or '-1') ..
            ':x=' .. (flagValues['x'] or '-1') .. ':color=black" -c:a copy ' .. preset .. cachedFilepath .. filename
    elseif (flagValues['crop'] ~= nil and flagValues['crop'] == 'padding' and flagValues['width'] ~= nil and flagValues['height'] ~= nil) then
        -- scale (with upscale) with padding (blackbox)
        command = config.ffmpeg ..
            ' -i ' ..
            originalFilepath ..
            filename ..
            ' -filter_complex "scale=min(' ..
            flagValues['width'] ..
            '\\,iw*(min(' ..
            flagValues['width'] ..
            '/iw\\,' ..
            flagValues['height'] ..
            '/ih))):min(' ..
            flagValues['height'] ..
            '\\,ih*(min(' ..
            flagValues['width'] ..
            '/iw\\,' ..
            flagValues['height'] ..
            '/ih))):force_original_aspect_ratio=increase:force_divisible_by=2,setsar=1,pad=' ..
            flagValues['width'] ..
            ':' ..
            flagValues['height'] ..
            ':y=' ..
            (flagValues['y'] or '-1') ..
            ':x=' .. (flagValues['x'] or '-1') .. ':color=black" -c:a copy ' .. preset .. cachedFilepath .. filename
    elseif (flagValues['width'] ~= nil and flagValues['height'] ~= nil) then
        -- simple scale (no aspect ratio)
        command = config.ffmpeg ..
            ' -i ' ..
            originalFilepath ..
            filename ..
            ' -filter_complex "scale=' ..
            flagValues['width'] ..
            ':' ..
            flagValues['height'] ..
            ':force_divisible_by=2:force_original_aspect_ratio=disable,setsar=1" -c:a copy ' ..
            preset .. cachedFilepath .. filename
    elseif (flagValues['height'] ~= nil) then
        -- simple one-side scale (h)
        command = config.ffmpeg ..
            ' -i ' ..
            originalFilepath ..
            filename ..
            ' -filter_complex "scale=-1:' ..
            flagValues['height'] ..
            ':force_divisible_by=2:force_original_aspect_ratio=decrease,setsar=1" -c:a copy ' ..
            preset .. cachedFilepath .. filename
    elseif (flagValues['width'] ~= nil) then
        -- simple one-side scale (w)
        command = config.ffmpeg ..
            ' -i ' ..
            originalFilepath ..
            filename ..
            ' -filter_complex "scale=' ..
            flagValues['width'] ..
            ':-1:force_divisible_by=2:force_original_aspect_ratio=decrease,setsar=1" -c:a copy ' ..
            preset .. cachedFilepath .. filename
    end

    local executeSuccess

    if command ~= nil then
        if config.logFfmpegOutput == false then
            command = command .. ' ' .. config.ffmpegDevNull
        end
        if config.logTime then
            command = 'time ' .. command
        end
        log('ffmpeg command: ' .. command)
        executeSuccess = os.execute(command)
    end

    if executeSuccess == nil then
        log('transcode failed')

        if config.serveOriginalOnTranscodeFailure == true then
            log('serving original from: ' .. originalFilepath .. filename)
            ngx.exec('/luamp-cache', { luamp_cached_file_path = originalFilepath .. filename })
        end
    else
        -- check if transcoded file is > minimumTranscodedVideoSize
        -- we do this inside the transcoding `if` block to not mess with other threads
        local transcodedFile = io.open(cachedFilepath .. filename, 'rb')
        local transcodedFileSize = transcodedFile:seek('end')
        transcodedFile:close()

        if transcodedFileSize > config.minimumTranscodedVideoSize then
            log('transcoded version is good, serving it')
            -- serve it
            ngx.exec('/luamp-cache', { luamp_cached_file_path = cachedFilepath .. filename })
        else
            log('transcoded version is corrupt')
            -- delete corrupt one
            os.remove(cachedFilepath .. filename)

            -- serve original
            if config.serveOriginalOnTranscodeFailure == true then
                log('serving original')
                ngx.exec('/luamp-cache', { luamp_cached_file_path = originalFilepath .. filename })
            end
        end
    end
else
    log('found previously transcoded version, serving it')
    cachedFile:close()
end

ngx.exec('/luamp-cache', { luamp_cached_file_path = cachedFilepath .. filename })
