# nginx-lua-mp4

nginx-lua-mp4 (or simply _luamp_) is a LUA module for [OpenResty](https://openresty.org/en/) or nginx with [ngx_http_lua_module](https://github.com/openresty/lua-nginx-module) that allows on-the-fly video transcoding using [ffmpeg](https://ffmpeg.org/) controlled by parameters passed in the URL.

To put it simply, if you have a 1920x1080 video file
`https://example.com/vids/cat.mp4`, you can request URL `https://example.com/vids/w_640/cat.mp4` and you will get a 640x360 of the same video. You can crop/scale, keep aspect ratio or discard it, add padding around video (need a dynamic blurred padding? We got you covered).

## Features

https://user-images.githubusercontent.com/3368441/161866581-ee1c745c-f119-430c-810c-f13a820a6c4b.mp4

✅ — ready, 🚧 — WIP

- General:
  - ✅ Can (optionally) download original videos from the upstream, if missing from the local file system
  - ✅ Configurable transcoding flags in URL, can be dropped in place of existing system without front end rewrite
  - ✅ Configurable logging for debug/setup
  - ✅ [DPR (device pixel ratio) support](https://developer.mozilla.org/en-US/docs/Web/API/Window/devicePixelRatio)
  - ✅ Pass data back to nginx location after transcoding, so you can customize post-process or call more LUA modules
  - 🚧 Serve original on failed transcoding
- Transcoding:
  - ✅ Scale/Resize
  - Padding:
    - ✅ Black box padding
    - ✅ Blurred background padding
    - ✅ Upscale protection
    - 🚧 Colored box padding
  - ✅ Keep original aspect ratio
  - ✅ mp4 support (output)
  - 🚧 webm support (output)
## Requirements

- OpenResty or nginx with ngx_http_lua_module enabled
- [ffmpeg 5](https://launchpad.net/~savoury1/+archive/ubuntu/ffmpeg5) installed
- [time](https://en.wikipedia.org/wiki/Time_(Unix)) utility if you have `config.logTime` enabled

## Installation

#### 1. Clone the repo 

#### 2. nginx config changes

Add to the `http` section of the nginx config:

```
http {
    ...
    
    lua_package_path "/absolute/path/to/nginx-lua-mp4/?.lua;;";
    
    ...
```

And here's minimal viable config for 4 locations you need to set up. These locations are described in the sections below:
```
# video location
location ~ ^/(?<luamp_flags>([^\/]+)\/|)(?<luamp_filename>[^\/]+\.mp4)$ {
    # these two are required to be set regardless
    set $luamp_original_video "";
    set $luamp_transcoded_video "";
    
    # these are needed to be set if you did not use them in regex matching location
    set $luamp_prefix "";
    set $luamp_postfix "";

    #pass to transcoder location
    try_files $uri @luamp_process;
}

# process/transcode location
location @luamp_process {
    content_by_lua_file "/absolute/path/to/nginx-lua-mp4/nginx-lua-mp4.lua";
}

# cache location
location =/luamp-cache {
    internal;
    root /;
    index off;
    
    set_unescape_uri $luamp_transcoded_video $arg_luamp_cached_video_path;
    
    try_files $luamp_transcoded_video =404;
}

# upstream location
location =/luamp-upstream {
    internal;
    rewrite ^(.+)$ $luamp_original_video break;
    proxy_pass https://old-cdn.example.com;
}

```

#### 2.1. Video location
This location used as an entry point and to set initial variables. This is usually a location with a `.mp4` at the end.

There are two variables you need to `set`/initialise: `$luamp_original_video` and `$luamp_transcoded_video`.

There are four variables that may be used as a named capture group in location regex: `luamp_prefix`, `luamp_flags`, `luamp_postfix`, `luamp_filename`.

For example:

```
https://example.com/asset/video/width_1980,height_1080,crop_padding/2019/12/new_year_boardgames_party.mp4
luamp_prefix:   asset/video/
luamp_flags:    width_1980,height_1080,crop_padding
luamp_postfix:  2019/12/
luamp_filename: new_year_boardgames_party.mp4
```

If you do not need prefix and postfix, you can omit them from the regexp, but do make sure you `set` them to an empty string in the location. Here's the minimal viable example for simpler URLs with no prefix/postfix:

```
location ~ ^/(?<luamp_flags>([^\/]+)\/|)(?<luamp_filename>[^\/]+\.mp4)$ {
    # these two are required to be set regardless
    set $luamp_original_video "";
    set $luamp_transcoded_video "";
    
    # these are needed to be set if you did not use them in regex matching location
    set $luamp_prefix "";
    set $luamp_postfix "";

    #pass to transcoder location
    try_files $uri @luamp_process;
}

```

#### 2.2. Process location

Process location is pretty simple, it just passes execution to the LUA part of luamp module:

```
location @luamp_process {
    content_by_lua_file "/absolute/path/to/nginx-lua-mp4/nginx-lua-mp4.lua";
}
```

#### 2.3. Cache location

Cache location is where previously transcoded videos are served from:

```
location =/luamp-cache {
    internal;
    root /;
    index off;
    
    set_unescape_uri $luamp_transcoded_video $arg_luamp_cached_video_path;
    
    try_files $luamp_transcoded_video =404;
}
```

#### 2.4. Upstream location

Upstream location is used when you have no original video files stored on your local file system (perhaps, those are stored on your old CDN, or elsewhere).
If `luamp` finds no original file to transcode, it will attempt to download it from the upstream specified:
```
location =/luamp-upstream {
    internal;
    rewrite ^(.+)$ $luamp_original_video break;
    proxy_pass https://old-cdn.example.com;
}
```

`$luamp_original_video` is set within `config.getOriginalsUpstreamPath` function that can be configured in `luamp` config.lua. You can apply whatever logic you may need there to dynamically generate path for the upstream.

#### 3. nginx-lua-mp4 config

Go to the directory you downloaded `luamp` to:

```
$ cd /absolute/path/to/nginx-lua-mp4/
```

Create a config file by copying the example config:

```
$ cp config.lua.example config.lua
```

Open it with a text editor of your choice and change the variables you feel like changing.

```
$ nano config.lua
```

#### 3.1. `config.ffmpeg`

Path to the `ffmpeg` executable. Can be figured out by using `which` command in the terminal:

```
$ which ffmpeg
/usr/local/bin/ffmpeg
```

#### 3.2. `config.mediaBaseFilepath`

Where videos (both originals and transcoded ones) should be stored. Usually, a directory where assets are stored. Should be readable/writable for nginx. 

#### 3.3. `config.downloadOriginals`

When set to `true`, `luamp` will attempt to download missing original videos from the upstream. Set it to `false` if you have original videos provided by other means to this directory:
```
config.mediaBaseFilepath/$prefix/$postfix/$filename
```

#### 3.4. `config.getOriginalsUpstreamPath`

Function that is used to generate a URL for upstream. `prefix`, `postfix` and `filename` are provided to the function and you can also use [LUA ngx API](https://openresty-reference.readthedocs.io/en/latest/Lua_Nginx_API/).

#### 3.5. `config.flagsDelimiter`

Character that is used to separate different flags in URL, e.g. commas in `/w_1280,h_960,c_pad/`.
 
#### 3.6. `config.flagValueDelimiter`

Character that is used to separate flag name from the value, e.g. underscores in `/w_1280,h_960,c_pad/`.

#### 3.7. `config.flagMap`

Use this table to customize how flags are called in your URLs. Defaults are one letter flags like `w` for `width`, but you can customise these by editing left side of `flagMap` table:

One letter flags (except for DPR) if you want to use flags like `w_200,h_180,c_pad`:

```
    ['c'] = 'crop', 
    ['b'] = 'background',
    ['dpr'] = 'dpr',
    ['h'] = 'height',
    ['w'] = 'width',
```

Full flags if you want to use flags like `width_200,height_180,crop_pad`:

```
    ['crop'] = 'crop', 
    ['background'] = 'background',
    ['dpr'] = 'dpr',
    ['height'] = 'height',
    ['width'] = 'width',
```

#### 3.8. `config.flagValueMap`

Similar to `config.flagMap` above, but for non-number flag *values* rather than flag names.

Default flag values, e.g. `c_pad` or `c_lpad`, also `b_blurred`:

```
config.flagValueMap = {
    ['pad'] = 'padding',
    ['lpad'] = 'limited_padding',
    ['blurred'] = 'blur',
}
```

Full flag values, e.g. `c_padding` or `c_limited-padding`:
```
config.flagValueMap = {
    ['pading'] = 'padding',
    ['limited-padding'] = 'limited_padding',
    ['blurred'] = 'blur',
}
```

#### 3.9. `config.logEnabled = true`

Whether to log whole `luamp` process. Useful for initial setup and for debug.

#### 3.10. `config.logLevel = ngx.ERR`

Log level, available values: `ngx.STDERR`, `ngx.EMERG`, `ngx.ALERT`, `ngx.CRIT`, `ngx.ERR`, `ngx.WARN`, `ngx.NOTICE`, `ngx.INFO`, `ngx.DEBUG`.

#### 3.11. `config.logFfmpegOutput`

Whether to log `ffmpeg` output. Note that `ffmpeg` outputs to `stderr`, and if `logFfmpegOutput` is enabled, it will log to nginx's `error.log`. 

#### 3.12. `config.ffmpegDevNull`

Where to redirect `ffmpeg` output if `config.logFfmpegOutput` is set to false.

For *nix (default value):
```
config.ffmpegDevNull = '2> /dev/null' -- nix
```

For win:
```
config.ffmpegDevNull = '2>NUL' -- win
```

#### 3.13. `config.logTime`

Whether to prepend `ffmpeg` command with `time` utility, if you wish to log time spent in transcoding.

#### 3.14. `config.maxHeight` and `config.maxWidth`

Limit the output video's maximum height or width. If the resulting height or width is exceeding the limit (for example, after a high DPR calculation), it will be capped at the `config.maxHeight` and `config.maxWidth`.

## Flags

### `b` — Background

Available values:
 - `blurred` — when padding is enabled (with `c_pad` or `c_lpad`), the padding box will contain an upscaled blurred video.

### `c` — Crop

Available values:
 - `pad` — when resizing a video, aspect ratio will be preserved and padding box will be added to keep the aspect ratio. 
 - `lpad` — same as `pad` but original video will **not** be scaled up.

### `dpr` Device Pixel Ratio

Available values: float or integer number.

### `h` Height

Available values: integer number.

### `w` Width

Available values: integer number.
