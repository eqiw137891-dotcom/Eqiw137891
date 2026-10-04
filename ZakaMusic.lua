--[[=========================================================================
    ZakaMusic v1.3   |   网易云风格 · Roblox 执行器音乐播放器
    -------------------------------------------------------------------------
    功能:
      · 启动动画 (Logo 呼吸 + 进度条 + 界面淡入)
      · 账号登录 (token + userid 直填, 凭据本地保存, 下次自动登录)
      · 同步 VIP 状态 + 收藏歌单
      · 搜索增强: 搜索历史(本地保存) / 热门搜索 / 分页加载更多
      · 播放 / 上一首 / 下一首 / 进度拖动
      · 歌词字幕, 可开关, 自动滚动高亮
      · 音量条调节
      · 面板拖动 + 右下角拖拽缩放 + Ctrl+滚轮缩放
    用法:
      丢进执行器执行. 首次使用点顶栏头像填 token + userid.
      需要执行器支持 writefile + getcustomasset 才能播放外部 mp3
      (Solara / Wave / Xeno / Swift / Delta 等较新版本都支持)
    注:
      酷狗官方短信接口 (/v2/sendcode、/v2/login) 已下线, 手机验证码这条路
      拿不到码了, 所以登录改为 token + userid 直填, 不再走短信.
===========================================================================]]

local Players      = game:GetService("Players")
local HttpService  = game:GetService("HttpService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local UIS          = game:GetService("UserInputService")
local RunService   = game:GetService("RunService")
local LP           = Players.LocalPlayer

--============================== 0. 配置 ==============================--
local CFG = {
    cacheDir  = "ZakaMusic",
    histFile  = "ZakaMusic/history.txt",    -- 搜索历史
    userFile  = "ZakaMusic/account.txt",    -- 登录凭据
    splash    = true,       -- 启动动画
    quality   = "128",      -- 128 / 320
    showLyric = true,
    volume    = 0.65,
    token     = "",
    userid    = "",
    nickname  = "未登录",
    isVip     = false,
    theme = {
        bg     = Color3.fromRGB(24, 24, 28),
        panel  = Color3.fromRGB(32, 32, 38),
        card   = Color3.fromRGB(41, 41, 48),
        accent = Color3.fromRGB(194, 12, 12),
        text   = Color3.fromRGB(234, 234, 236),
        sub    = Color3.fromRGB(140, 140, 150),
        line   = Color3.fromRGB(56, 56, 64),
    },
}
CFG.mid  = (HttpService:GenerateGUID(false):gsub("%-", ""))
CFG.dfid = "-"

local T = CFG.theme

--============================ 1. 基础工具 ============================--
local function new(cls, props, parent)
    local o = Instance.new(cls)
    if props then
        for k, v in pairs(props) do
            o[k] = v
        end
    end
    if parent then o.Parent = parent end
    return o
end

local function corner(o, r)
    return new("UICorner", { CornerRadius = UDim.new(0, r or 8) }, o)
end

local function stroke(o, col, th)
    return new("UIStroke", {
        Color = col or T.line,
        Thickness = th or 1,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
    }, o)
end

local function pad(o, l, r, t, b)
    return new("UIPadding", {
        PaddingLeft   = UDim.new(0, l or 0),
        PaddingRight  = UDim.new(0, r or 0),
        PaddingTop    = UDim.new(0, t or 0),
        PaddingBottom = UDim.new(0, b or 0),
    }, o)
end

--============================ 2. 编码工具 ============================--
-- MD5 (纯 Lua, 走 bit32)
local function md5(input)
    local band, bor, bxor, bnot = bit32.band, bit32.bor, bit32.bxor, bit32.bnot
    local lshift, rshift = bit32.lshift, bit32.rshift

    local K = {}
    for i = 1, 64 do
        K[i] = math.floor(math.abs(math.sin(i)) * 4294967296)
    end
    local S = {
        7,12,17,22, 7,12,17,22, 7,12,17,22, 7,12,17,22,
        5, 9,14,20, 5, 9,14,20, 5, 9,14,20, 5, 9,14,20,
        4,11,16,23, 4,11,16,23, 4,11,16,23, 4,11,16,23,
        6,10,15,21, 6,10,15,21, 6,10,15,21, 6,10,15,21,
    }

    local msg = {}
    for i = 1, #input do msg[i] = input:byte(i) end
    local bitlen = #input * 8
    msg[#msg + 1] = 0x80
    while (#msg % 64) ~= 56 do msg[#msg + 1] = 0 end
    local lo = bitlen % 4294967296
    local hi = math.floor(bitlen / 4294967296)
    for i = 0, 3 do msg[#msg + 1] = band(rshift(lo, i * 8), 0xff) end
    for i = 0, 3 do msg[#msg + 1] = band(rshift(hi, i * 8), 0xff) end

    local function rot(x, c)
        return band(bor(lshift(x, c), rshift(x, 32 - c)), 0xffffffff)
    end

    local a0, b0, c0, d0 = 0x67452301, 0xefcdab89, 0x98badcfe, 0x10325476

    for chunk = 0, (#msg / 64) - 1 do
        local M = {}
        for j = 0, 15 do
            local o = chunk * 64 + j * 4
            M[j] = msg[o + 1] + msg[o + 2] * 256 + msg[o + 3] * 65536 + msg[o + 4] * 16777216
        end
        local A, B, C, D = a0, b0, c0, d0
        for i = 0, 63 do
            local f, g
            if i < 16 then
                f = bor(band(B, C), band(bnot(B), D)); g = i
            elseif i < 32 then
                f = bor(band(D, B), band(bnot(D), C)); g = (5 * i + 1) % 16
            elseif i < 48 then
                f = bxor(B, bxor(C, D)); g = (3 * i + 5) % 16
            else
                f = bxor(C, bor(B, bnot(D))); g = (7 * i) % 16
            end
            f = band(f + A + K[i + 1] + M[g], 0xffffffff)
            A = D
            D = C
            C = B
            B = band(B + rot(f, S[i + 1]), 0xffffffff)
        end
        a0 = band(a0 + A, 0xffffffff)
        b0 = band(b0 + B, 0xffffffff)
        c0 = band(c0 + C, 0xffffffff)
        d0 = band(d0 + D, 0xffffffff)
    end

    local out = {}
    local function push(n)
        out[#out + 1] = string.format("%02x", band(n, 0xff))
        out[#out + 1] = string.format("%02x", band(rshift(n, 8), 0xff))
        out[#out + 1] = string.format("%02x", band(rshift(n, 16), 0xff))
        out[#out + 1] = string.format("%02x", band(rshift(n, 24), 0xff))
    end
    push(a0); push(b0); push(c0); push(d0)
    return table.concat(out)
end

local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local function b64decode(data)
    if type(data) ~= "string" then return "" end
    data = data:gsub("[^" .. B64 .. "=]", "")
    local bits = data:gsub(".", function(x)
        if x == "=" then return "" end
        local r, f = "", (B64:find(x, 1, true) - 1)
        for i = 6, 1, -1 do
            r = r .. ((f % 2 ^ i - f % 2 ^ (i - 1) > 0) and "1" or "0")
        end
        return r
    end)
    return (bits:gsub("%d%d%d?%d?%d?%d?%d?%d?", function(x)
        if #x ~= 8 then return "" end
        local c = 0
        for i = 1, 8 do
            if x:sub(i, i) == "1" then c = c + 2 ^ (8 - i) end
        end
        return string.char(c)
    end))
end

--============================ 3. 执行器适配 ===========================--
local writefileFn  = writefile or write_file
local readfileFn   = readfile or read_file
local isfileFn     = isfile or is_file
local makefolderFn = makefolder or make_folder
local getcustomassetFn = getcustomasset or getsynasset

local function httpFn()
    return (syn and syn.request) or (http and http.request) or http_request
        or (fluxus and fluxus.request) or (request)
end

local function httpGet(url, headers)
    local fn = httpFn()
    if not fn then return nil, "当前执行器不支持 HTTP 请求" end
    local ok, res = pcall(fn, { Url = url, Method = "GET", Headers = headers or {} })
    if not ok or not res then return nil, "请求失败" end
    return res
end

local function httpPost(url, body, headers)
    local fn = httpFn()
    if not fn then return nil, "当前执行器不支持 HTTP 请求" end
    local ok, res = pcall(fn, { Url = url, Method = "POST", Body = body, Headers = headers or {} })
    if not ok or not res then return nil, "请求失败" end
    return res
end

local function jsonDecode(str)
    if not str or str == "" then return nil end
    local ok, res = pcall(function() return HttpService:JSONDecode(str) end)
    if ok then return res end
    return nil
end

if makefolderFn then pcall(makefolderFn, CFG.cacheDir) end

--============================ 4. 酷狗 API ============================--
local Salt = "NVPh5oo715z5DIWAeQlhMDsWXXQV4hwt"

local function signParams(p)
    local ks = {}
    for k in pairs(p) do ks[#ks + 1] = k end
    table.sort(ks)
    local s = {}
    for _, k in ipairs(ks) do s[#s + 1] = k .. "=" .. tostring(p[k]) end
    return md5(Salt .. table.concat(s, "&") .. Salt)
end

local function buildQuery(p)
    local ks = {}
    for k in pairs(p) do ks[#ks + 1] = k end
    table.sort(ks)
    local s = {}
    for _, k in ipairs(ks) do
        s[#s + 1] = k .. "=" .. HttpService:UrlEncode(tostring(p[k]))
    end
    return table.concat(s, "&")
end

local function apiHeaders()
    return {
        ["User-Agent"] = "Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 Chrome/120 Mobile Safari/537.36",
        ["Cookie"] = string.format("kg_mid=%s; kg_dfid=%s; token=%s; userid=%s;",
            CFG.mid, CFG.dfid, CFG.token, CFG.userid),
        ["Referer"] = "https://www.kugou.com/",
    }
end

local API = {}

local ENDPOINTS = {
    search   = "https://songsearch.kugou.com/song_search_v2",
    playData = "https://wwwapi.kugou.com/yy/index.php",
    lyric    = "https://krcs.kugou.com/search",
    lyricDl  = "https://lyrics.kugou.com/download",
    playlist = "https://gateway.kugou.com/v2/get_user_songlist",
    vipInfo  = "https://kugouvip.kugou.com/v1/get_union_vip",
    sendSms  = "https://login-user.kugou.com/v2/sendcode",
    loginSms = "https://login-user.kugou.com/v2/login",
}

-- 搜索歌曲
function API.search(kw, page)
    local p = {
        keyword = kw,
        page = page or 1,
        pagesize = 20,
        userid = (CFG.userid ~= "" and CFG.userid) or -1,
        clientver = 2000,
        platform = "WebFilter",
        iscorrection = 1,
        privilege_filter = 0,
        filter = 10,
        appid = 1014,
        mid = CFG.mid,
    }
    p.signature = signParams(p)
    local res = httpGet(ENDPOINTS.search .. "?" .. buildQuery(p), apiHeaders())
    local j = res and jsonDecode(res.Body)
    local out = {}
    local lists = j and j.data and (j.data.lists or j.data.info)
    if lists then
        for _, it in ipairs(lists) do
            local singer = it.SingerName
            if type(singer) == "table" then
                local nm = {}
                for _, s in ipairs(singer) do nm[#nm + 1] = s.name or tostring(s) end
                singer = table.concat(nm, "、")
            end
            if type(singer) ~= "string" then singer = it.SingerName or "未知歌手" end
            local name = tostring(it.SongName or it.FileName or "未知歌曲"):gsub("<[^>]->", "")
            if it.FileHash and it.FileHash ~= "" then
                out[#out + 1] = {
                    hash    = it.FileHash,
                    name    = name,
                    singer  = tostring(singer):gsub("<[^>]->", ""),
                    albumId = tostring(it.AlbumID or ""),
                    audioId = tostring(it.EMixSongID or it.Audioid or ""),
                    duration= tonumber(it.Duration) or 0,
                    vip     = (tonumber(it.Privilege) or 0) == 10,
                }
            end
        end
    end
    return out
end

-- 取播放地址 + 歌词 + 封面
function API.playData(track)
    local p = {
        r = "play/getdata",
        hash = track.hash,
        album_id = track.albumId,
        dfid = CFG.dfid,
        mid = CFG.mid,
        platid = 4,
        appid = 1014,
        _ = tostring(math.floor(os.time() * 1000)),
    }
    local res = httpGet(ENDPOINTS.playData .. "?" .. buildQuery(p), apiHeaders())
    local j = res and jsonDecode(res.Body)
    local d = j and j.data
    if not d then return nil end
    track.url    = d.play_url or d.play_backup_url
    track.cover  = d.img
    track.lyric  = d.lyrics
    track.duration = tonumber(d.timelength) or track.duration * 1000 or 0
    track.hash   = d.hash or track.hash
    return track
end

-- 拉字幕
function API.lyric(track)
    if track.lyric and track.lyric ~= "" then
        local raw = track.lyric
        local dec = b64decode(raw)
        if dec ~= "" and dec:find("%[") then return dec end
        return raw
    end
    local p = {
        ver = 1, man = "yes", client = "mobi",
        keyword = "", hash = track.hash,
        duration = tostring(math.floor((track.duration or 0))),
        album_audio_id = track.audioId,
    }
    local res = httpGet(ENDPOINTS.lyric .. "?" .. buildQuery(p), apiHeaders())
    local j = res and jsonDecode(res.Body)
    local cand = j and j.candidates and j.candidates[1]
    if not cand then return nil end
    local q = { ver = 1, client = "pc", id = cand.id, accesskey = cand.accesskey, fmt = "lrc", charset = "utf8" }
    local res2 = httpGet(ENDPOINTS.lyricDl .. "?" .. buildQuery(q), apiHeaders())
    local j2 = res2 and jsonDecode(res2.Body)
    if j2 and j2.content then
        return b64decode(j2.content)
    end
    return nil
end

-- 收藏歌单
function API.favorites()
    if CFG.token == "" or CFG.userid == "" then return {} end
    local p = {
        userid = CFG.userid, token = CFG.token,
        page = 1, pagesize = 100, type = 0,
        clientver = 12329, appid = 1014, mid = CFG.mid,
    }
    p.signature = signParams(p)
    local res = httpGet(ENDPOINTS.playlist .. "?" .. buildQuery(p), apiHeaders())
    local j = res and jsonDecode(res.Body)
    local out = {}
    local src = (j and j.data and (j.data.info or j.data.lists)) or {}
    for _, it in ipairs(src) do
        local hash = it.hash or it.FileHash
        if hash then
            out[#out + 1] = {
                hash = hash,
                name = it.name or it.filename or "未知歌曲",
                singer = it.singername or it.SingerName or "",
                albumId = tostring(it.album_id or it.AlbumID or ""),
                audioId = tostring(it.audio_id or it.EMixSongID or ""),
                duration = tonumber(it.timelen or it.Duration) or 0,
                vip = (tonumber(it.privilege) or tonumber(it.Privilege) or 0) == 10,
                fav = true,
            }
        end
    end
    return out
end

-- VIP 状态
function API.vipInfo()
    if CFG.token == "" then return false end
    local p = { userid = CFG.userid, token = CFG.token, clientver = 12329, appid = 1014, mid = CFG.mid }
    p.signature = signParams(p)
    local res = httpGet(ENDPOINTS.vipInfo .. "?" .. buildQuery(p), apiHeaders())
    local j = res and jsonDecode(res.Body)
    if not j or not j.data then return false end
    local d = j.data
    local t = tonumber(d.vip_type or d.vipType or 0) or 0
    return t > 0
end

-- 短信验证码
-- 说明: 酷狗官方 /v2/sendcode 与 /v2/login 两个短信接口已下线(整条路径直接 404),
-- 现在短信下发走 App 私有通道 + 滑块风控, 网页/脚本这条路拿不到验证码。
-- 因此这里不再发请求, 直接返回真实原因, 避免白等。
function API.sendSms(phone, ccode)
    return false, "酷狗短信通道已下线,请用 token + userid 登录"
end

-- 验证码登录
function API.loginSms(phone, code, ccode)
    local p = {
        mobile = phone, code = code, ccode = ccode or "86",
        clientver = 12329, appid = 1014, mid = CFG.mid,
    }
    p.signature = signParams(p)
    local res = httpPost(ENDPOINTS.loginSms, buildQuery(p),
        { ["Content-Type"] = "application/x-www-form-urlencoded" })
    local j = res and jsonDecode(res.Body)
    local d = j and j.data
    if d and d.token then
        CFG.token  = tostring(d.token)
        CFG.userid = tostring(d.userid or d.user_id or "")
        CFG.nickname = tostring(d.nickname or d.username or ("酷狗用户" .. CFG.userid))
        return true, "登录成功"
    end
    return false, (j and (j.error_msg or j.msg)) or "登录失败"
end

--============================ 5. 播放引擎 ============================--
local UI = {}   -- 前向声明: 播放引擎里要用到 UI 回调
local Player = {
    sound = nil,
    list = {},
    index = 0,
    cache = {},
}

Player.sound = new("Sound", {
    Name = "ZakaMusicPlayer",
    Volume = CFG.volume,
    Looped = false,
    Parent = SoundService,
})

local function toAsset(path)
    if getcustomassetFn then
        local ok, res = pcall(getcustomassetFn, path)
        if ok and res then return res end
    end
    return nil
end

local function download(track)
    if CFG.cacheDir and track.hash then
        local p = CFG.cacheDir .. "/" .. tostring(track.hash) .. ".mp3"
        if Player.cache[p] then return Player.cache[p] end
        if isfileFn and readfileFn then
            local ok, exists = pcall(isfileFn, p)
            if ok and exists then
                local a = toAsset(p)
                if a then Player.cache[p] = a; return a end
            end
        end
        local res = httpGet(track.url, apiHeaders())
        if res and res.Body and #res.Body > 4096 then
            if writefileFn then
                local okw = pcall(writefileFn, p, res.Body)
                if okw then
                    local a = toAsset(p)
                    if a then Player.cache[p] = a; return a end
                end
            end
        end
    end
    return nil
end

function Player.load(track)
    Player.sound:Stop()
    local a = download(track)
    if not a then
        return false, "无法缓存音频(执行器不支持 writefile/getcustomasset)"
    end
    Player.sound.SoundId = a
    Player.sound.Volume = CFG.volume
    Player.sound:Play()
    Player.currentTrack = track
    return true
end

function Player.playIndex(i)
    local list = Player.list
    if #list == 0 then return end
    if i < 1 then i = #list end
    if i > #list then i = 1 end
    Player.index = i
    local track = list[i]
    UI.setNow(track, true)
    UI.setLyricText("加载中...")

    task.spawn(function()
        local ok, err = API.playData(track)
        if not ok or (not track.url or track.url == "") then
            UI.setLyricText("这首歌取不到播放地址(可能需要 VIP 或版权限制)")
            return
        end
        local ok2, err2 = Player.load(track)
        if not ok2 then
            UI.setLyricText(err2)
            return
        end
        UI.setNow(track, false)
        local lrc = API.lyric(track)
        UI.setLrc(lrc)
        if track.cover and track.cover ~= "" then
            UI.setCover(track.cover)
        end
    end)
end

function Player.next()
    Player.playIndex(Player.index + 1)
end

function Player.prev()
    Player.playIndex(Player.index - 1)
end

function Player.toggle()
    if Player.sound.IsPlaying then
        Player.sound:Pause()
    else
        if Player.sound.SoundId ~= "" and Player.sound.TimePosition > 0 then
            Player.sound:Resume()
        elseif #Player.list > 0 then
            Player.playIndex(Player.index == 0 and 1 or Player.index)
        end
    end
    UI.refreshPlayBtn()
end

Player.sound.Ended:Connect(function()
    Player.next()
end)

--============================ 6. UI ============================--
local function guiParent()
    if gethui then
        local ok, h = pcall(gethui)
        if ok and h then return h end
    end
    if get_hidden_gui then
        local ok, h = pcall(get_hidden_gui)
        if ok and h then return h end
    end
    return LP:WaitForChild("PlayerGui")
end

local gui = new("ScreenGui", {
    Name = "ZakaMusic_" .. tostring(math.random(100000, 999999)),
    ResetOnSpawn = false,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
    IgnoreGuiInset = true,
}, guiParent())

UI = UI or {}

-- 主面板
local Main = new("Frame", {
    Name = "Main",
    Size = UDim2.fromOffset(460, 356),
    Position = UDim2.new(0, 60, 0, 90),
    BackgroundColor3 = T.bg,
    BorderSizePixel = 0,
    Active = true,
    Draggable = false,
}, gui)
corner(Main, 14)
stroke(Main, T.line, 1)

local scale = new("UIScale", { Scale = 1 }, Main)

-- 顶栏
local Top = new("Frame", {
    Size = UDim2.new(1, 0, 0, 66),
    BackgroundColor3 = T.panel,
    BorderSizePixel = 0,
}, Main)
corner(Top, 14)
new("Frame", {
    Size = UDim2.new(1, 0, 0, 20),
    Position = UDim2.new(0, 0, 1, -20),
    BackgroundColor3 = T.panel,
    BorderSizePixel = 0,
}, Top)

local Cover = new("ImageLabel", {
    Size = UDim2.fromOffset(46, 46),
    Position = UDim2.fromOffset(12, 10),
    BackgroundColor3 = T.card,
    BorderSizePixel = 0,
    Image = "",
    ScaleType = Enum.ScaleType.Crop,
}, Top)
corner(Cover, 8)

local SongTitle = new("TextLabel", {
    Size = UDim2.new(1, -230, 0, 20),
    Position = UDim2.fromOffset(70, 13),
    BackgroundTransparency = 1,
    Font = Enum.Font.GothamBold,
    TextSize = 15,
    TextColor3 = T.text,
    TextXAlignment = Enum.TextXAlignment.Left,
    TextTruncate = Enum.TextTruncate.AtEnd,
    Text = "ZakaMusic",
}, Top)

local SongSub = new("TextLabel", {
    Size = UDim2.new(1, -230, 0, 16),
    Position = UDim2.fromOffset(70, 35),
    BackgroundTransparency = 1,
    Font = Enum.Font.Gotham,
    TextSize = 12,
    TextColor3 = T.sub,
    TextXAlignment = Enum.TextXAlignment.Left,
    TextTruncate = Enum.TextTruncate.AtEnd,
    Text = "网易云风格 · 支持歌词/音量/缩放",
}, Top)

local Avatar = new("TextButton", {
    Size = UDim2.fromOffset(64, 26),
    Position = UDim2.new(1, -76, 0, 20),
    BackgroundColor3 = T.accent,
    BorderSizePixel = 0,
    Font = Enum.Font.GothamBold,
    TextSize = 12,
    TextColor3 = Color3.new(1, 1, 1),
    Text = "登录",
    AutoButtonColor = true,
}, Top)
corner(Avatar, 13)

local CloseBtn = new("TextButton", {
    Size = UDim2.fromOffset(22, 22),
    Position = UDim2.new(1, -30, 0, 4),
    BackgroundTransparency = 1,
    Font = Enum.Font.GothamBold,
    TextSize = 15,
    TextColor3 = T.sub,
    Text = "x",
}, Top)

-- 歌单/歌词分区
local BodyY = 66 + 8

local LyricBox = new("Frame", {
    Size = UDim2.new(1, -24, 1, -190),
    Position = UDim2.fromOffset(12, BodyY),
    BackgroundColor3 = T.panel,
    BorderSizePixel = 0,
    ClipsDescendants = true,
}, Main)
corner(LyricBox, 10)

local LrcScroll = new("ScrollingFrame", {
    Size = UDim2.new(1, -16, 1, -16),
    Position = UDim2.fromOffset(8, 8),
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    ScrollBarThickness = 3,
    ScrollBarImageColor3 = T.line,
    CanvasSize = UDim2.new(0, 0, 0, 0),
    AutomaticCanvasSize = Enum.AutomaticSize.Y,
    ScrollingDirection = Enum.ScrollingDirection.Y,
}, LyricBox)

local LrcLayout = new("UIListLayout", {
    Padding = UDim.new(0, 6),
    HorizontalAlignment = Enum.HorizontalAlignment.Center,
    SortOrder = Enum.SortOrder.LayoutOrder,
}, LrcScroll)

new("UIPadding", { PaddingTop = UDim.new(0, 20), PaddingBottom = UDim.new(0, 20) }, LrcScroll)

local LrcTexts = {}

function UI.setLyricText(txt)
    for _, c in ipairs(LrcScroll:GetChildren()) do
        if c:IsA("TextLabel") then c:Destroy() end
    end
    LrcTexts = {}
    local l = new("TextLabel", {
        Size = UDim2.new(1, 0, 0, 22),
        BackgroundTransparency = 1,
        Font = Enum.Font.Gotham,
        TextSize = 14,
        TextColor3 = T.sub,
        TextWrapped = true,
        Text = txt,
    }, LrcScroll)
    new("UITextSizeConstraint", { MaxTextSize = 14 }, l)
end

-- 歌单区
local ListBox = new("Frame", {
    Size = UDim2.new(1, -24, 1, -190),
    Position = UDim2.fromOffset(12, BodyY),
    BackgroundColor3 = T.panel,
    BorderSizePixel = 0,
    Visible = false,
    ClipsDescendants = true,
}, Main)
corner(ListBox, 10)

local ListScroll = new("ScrollingFrame", {
    Size = UDim2.new(1, -12, 1, -12),
    Position = UDim2.fromOffset(6, 6),
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    ScrollBarThickness = 3,
    ScrollBarImageColor3 = T.line,
    CanvasSize = UDim2.new(0, 0, 0, 0),
    AutomaticCanvasSize = Enum.AutomaticSize.Y,
}, ListBox)

new("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, ListScroll)

local function listRow(track, i)
    local row = new("TextButton", {
        Size = UDim2.new(1, 0, 0, 30),
        BackgroundColor3 = T.card,
        BackgroundTransparency = 0.35,
        BorderSizePixel = 0,
        LayoutOrder = i,
        Font = Enum.Font.Gotham,
        TextSize = 12,
        TextColor3 = T.text,
        TextXAlignment = Enum.TextXAlignment.Left,
        Text = string.format("  %s - %s%s", track.name, track.singer, track.vip and "  [VIP]" or ""),
        TextTruncate = Enum.TextTruncate.AtEnd,
    }, ListScroll)
    corner(row, 6)
    row.MouseButton1Click:Connect(function()
        local found = false
        for idx, t in ipairs(Player.list) do
            if t == track then found = true; Player.playIndex(idx); break end
        end
        if not found then
            Player.list[#Player.list + 1] = track
            Player.playIndex(#Player.list)
        end
        UI.showList(false)
    end)
    return row
end

function UI.fillList(tracks)
    for _, c in ipairs(ListScroll:GetChildren()) do
        if c:IsA("TextButton") then c:Destroy() end
    end
    for i, t in ipairs(tracks) do
        listRow(t, i)
    end
end

-- 歌单底部的「加载更多」
function UI.addMoreRow(on)
    for _, c in ipairs(ListScroll:GetChildren()) do
        if c:IsA("TextButton") and c.Name == "MoreRow" then c:Destroy() end
    end
    if not on then return end
    local b = new("TextButton", {
        Name = "MoreRow",
        Size = UDim2.new(1, 0, 0, 28),
        BackgroundColor3 = T.card,
        BackgroundTransparency = 0.6,
        BorderSizePixel = 0,
        LayoutOrder = 999999,
        Font = Enum.Font.GothamBold,
        TextSize = 11,
        TextColor3 = T.sub,
        Text = "↓  加载更多",
    }, ListScroll)
    corner(b, 6)
    b.MouseButton1Click:Connect(function()
        b.Text = "加载中…"
        if UI.onMore then UI.onMore() end
    end)
end

function UI.showList(on)
    ListBox.Visible = on
    LyricBox.Visible = not on
end

-- 底部
local Bottom = new("Frame", {
    Size = UDim2.new(1, -24, 0, 100),
    Position = UDim2.new(0, 12, 1, -108),
    BackgroundColor3 = T.panel,
    BorderSizePixel = 0,
}, Main)
corner(Bottom, 10)

local ProgressBg = new("Frame", {
    Size = UDim2.new(1, -24, 0, 4),
    Position = UDim2.fromOffset(12, 16),
    BackgroundColor3 = T.line,
    BorderSizePixel = 0,
}, Bottom)
corner(ProgressBg, 2)

local ProgressFill = new("Frame", {
    Size = UDim2.new(0, 0, 1, 0),
    BackgroundColor3 = T.accent,
    BorderSizePixel = 0,
}, ProgressBg)
corner(ProgressFill, 2)

local ProgressDot = new("Frame", {
    Size = UDim2.fromOffset(10, 10),
    AnchorPoint = Vector2.new(0.5, 0.5),
    Position = UDim2.new(0, 0, 0.5, 0),
    BackgroundColor3 = Color3.new(1, 1, 1),
    BorderSizePixel = 0,
}, ProgressBg)
corner(ProgressDot, 5)

local CurTime = new("TextLabel", {
    Size = UDim2.fromOffset(40, 14),
    Position = UDim2.fromOffset(12, 26),
    BackgroundTransparency = 1,
    Font = Enum.Font.Gotham,
    TextSize = 11,
    TextColor3 = T.sub,
    Text = "00:00",
}, Bottom)

local TotTime = new("TextLabel", {
    Size = UDim2.fromOffset(40, 14),
    Position = UDim2.new(1, -52, 0, 26),
    BackgroundTransparency = 1,
    Font = Enum.Font.Gotham,
    TextSize = 11,
    TextColor3 = T.sub,
    Text = "00:00",
    TextXAlignment = Enum.TextXAlignment.Right,
}, Bottom)

local function ctrlBtn(txt, x, w, color)
    local b = new("TextButton", {
        Size = UDim2.fromOffset(w or 34, 28),
        Position = UDim2.new(0.5, x, 0, 46),
        AnchorPoint = Vector2.new(0.5, 0),
        BackgroundColor3 = color or T.card,
        BorderSizePixel = 0,
        Font = Enum.Font.GothamBold,
        TextSize = 13,
        TextColor3 = T.text,
        Text = txt,
    }, Bottom)
    corner(b, 14)
    return b
end

local PrevBtn  = ctrlBtn("<<", -78, 38)
local PlayBtn  = ctrlBtn("播放", 0, 62, T.accent)
local NextBtn  = ctrlBtn(">>", 78, 38)
local ListBtn  = ctrlBtn("歌单", -132, 46)
local LrcBtn   = ctrlBtn("歌词", 132, 46)

PlayBtn.TextColor3 = Color3.new(1, 1, 1)

function UI.refreshPlayBtn()
    PlayBtn.Text = Player.sound.IsPlaying and "暂停" or "播放"
end

-- 音量条
local VolBg = new("Frame", {
    Size = UDim2.fromOffset(80, 4),
    Position = UDim2.new(1, -100, 0, 82),
    BackgroundColor3 = T.line,
    BorderSizePixel = 0,
}, Bottom)
corner(VolBg, 2)

local VolFill = new("Frame", {
    Size = UDim2.new(CFG.volume, 0, 1, 0),
    BackgroundColor3 = T.text,
    BorderSizePixel = 0,
}, VolBg)
corner(VolFill, 2)

local VolLabel = new("TextLabel", {
    Size = UDim2.fromOffset(30, 14),
    Position = UDim2.new(1, -34, 0, 76),
    BackgroundTransparency = 1,
    Font = Enum.Font.Gotham,
    TextSize = 10,
    TextColor3 = T.sub,
    Text = math.floor(CFG.volume * 100) .. "%",
}, Bottom)

local VolIcon = new("TextLabel", {
    Size = UDim2.fromOffset(50, 14),
    Position = UDim2.new(1, -110, 0, 76),
    BackgroundTransparency = 1,
    Font = Enum.Font.Gotham,
    TextSize = 10,
    TextColor3 = T.sub,
    Text = "音量",
    TextXAlignment = Enum.TextXAlignment.Left,
}, Bottom)

-- 搜索框
local SearchBox = new("TextBox", {
    Size = UDim2.fromOffset(190, 22),
    Position = UDim2.new(0, 12, 0, 74),
    BackgroundColor3 = T.card,
    BorderSizePixel = 0,
    Font = Enum.Font.Gotham,
    TextSize = 11,
    TextColor3 = T.text,
    PlaceholderText = "搜歌 + 回车",
    PlaceholderColor3 = T.sub,
    Text = "",
    ClearTextOnFocus = false,
}, Bottom)
corner(SearchBox, 11)
pad(SearchBox, 8, 8, 0, 0)

-- ---------- 搜索历史 / 热门 面板 ----------
local HOT = {
    "周杰伦", "林俊杰", "薛之谦", "邓紫棋", "陈奕迅", "毛不易",
    "夜曲", "起风了", "孤勇者", "晴天", "纯音乐", "轻音乐",
}

local Suggest = new("ScrollingFrame", {
    Name = "Suggest",
    Size = UDim2.fromOffset(240, 120),
    Position = UDim2.new(0, 24, 1, -40),
    AnchorPoint = Vector2.new(0, 1),
    BackgroundColor3 = T.panel,
    BorderSizePixel = 0,
    Visible = false,
    ClipsDescendants = true,
    ScrollBarThickness = 3,
    ScrollBarImageColor3 = T.line,
    CanvasSize = UDim2.new(0, 0, 0, 0),
    AutomaticCanvasSize = Enum.AutomaticSize.Y,
    ScrollingDirection = Enum.ScrollingDirection.Y,
    ZIndex = 15,
}, Main)
corner(Suggest, 10)
stroke(Suggest, T.line)
new("UIPadding", {
    PaddingTop = UDim.new(0, 6), PaddingBottom = UDim.new(0, 6),
    PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6),
}, Suggest)
local SuggestLayout = new("UIListLayout", { Padding = UDim.new(0, 3), SortOrder = Enum.SortOrder.LayoutOrder }, Suggest)

local Hist = {}

local function loadHist()
    Hist = {}
    if not (readfileFn and isfileFn) then return end
    local ok, exists = pcall(isfileFn, CFG.histFile)
    if not ok or not exists then return end
    local ok2, data = pcall(readfileFn, CFG.histFile)
    if not ok2 or type(data) ~= "string" then return end
    for line in data:gmatch("[^\r\n]+") do
        local w = line:match("^%s*(.-)%s*$")
        if w ~= "" and #w <= 30 and #Hist < 8 then Hist[#Hist + 1] = w end
    end
end

local function pushHist(kw)
    for i = #Hist, 1, -1 do
        if Hist[i] == kw then table.remove(Hist, i) end
    end
    table.insert(Hist, 1, kw)
    while #Hist > 8 do table.remove(Hist) end
    if writefileFn then pcall(writefileFn, CFG.histFile, table.concat(Hist, "\n")) end
end

function UI.suggestHeader(txt, order, onClick, hint)
    local maker = onClick and "TextButton" or "TextLabel"
    local h = new(maker, {
        Size = UDim2.new(1, 0, 0, 18),
        BackgroundTransparency = 1,
        LayoutOrder = order,
        Font = Enum.Font.GothamBold,
        TextSize = 10,
        TextColor3 = T.sub,
        TextXAlignment = Enum.TextXAlignment.Left,
        Text = "  " .. txt .. (hint and ("      " .. hint) or ""),
    }, Suggest)
    if onClick then h.MouseButton1Click:Connect(onClick) end
    return h
end

function UI.suggestRow(txt, order, icon, onClick)
    local b = new("TextButton", {
        Size = UDim2.new(1, 0, 0, 24),
        BackgroundColor3 = T.card,
        BackgroundTransparency = 0.45,
        BorderSizePixel = 0,
        LayoutOrder = order,
        AutoButtonColor = true,
        Font = Enum.Font.Gotham,
        TextSize = 11,
        TextColor3 = T.text,
        TextXAlignment = Enum.TextXAlignment.Left,
        Text = "  " .. (icon and (icon .. "  ") or "") .. txt,
        TextTruncate = Enum.TextTruncate.AtEnd,
    }, Suggest)
    corner(b, 6)
    b.MouseButton1Click:Connect(onClick)
    return b
end

function UI.hideSuggest()
    Suggest.Visible = false
end

function UI.refreshSuggest()
    for _, c in ipairs(Suggest:GetChildren()) do
        if c:IsA("TextButton") or c:IsA("TextLabel") then c:Destroy() end
    end
    local o = 0
    if #Hist > 0 then
        o = o + 1
        UI.suggestHeader("搜索历史", o, function()
            Hist = {}
            if writefileFn then pcall(writefileFn, CFG.histFile, "") end
            UI.refreshSuggest()
        end, "点此清空")
        for i, w in ipairs(Hist) do
            if i > 5 then break end
            o = o + 1
            UI.suggestRow(w, o, "·", function()
                SearchBox.Text = w
                UI.runSearch(w, 1, false)
            end)
        end
    end
    o = o + 1
    UI.suggestHeader("热门搜索", o, nil, nil)
    for i, w in ipairs(HOT) do
        if i > 6 then break end
        o = o + 1
        UI.suggestRow(w, o, "★", function()
            SearchBox.Text = w
            UI.runSearch(w, 1, false)
        end)
    end
    Suggest.Visible = true
    task.spawn(function()
        task.wait(0.05)
        local h = math.min(SuggestLayout.AbsoluteContentSize.Y + 12, 250)
        Suggest.Size = UDim2.fromOffset(240, math.max(h, 40))
        Suggest.CanvasPosition = Vector2.new(0, 0)
    end)
end

loadHist()

-- 右下角缩放手柄
local Resizer = new("TextButton", {
    Size = UDim2.fromOffset(18, 18),
    Position = UDim2.new(1, -18, 1, -18),
    BackgroundTransparency = 1,
    Text = "",
}, Main)
new("Frame", {
    Size = UDim2.fromOffset(10, 2),
    Position = UDim2.new(1, -13, 1, -9),
    BackgroundColor3 = T.sub,
    BorderSizePixel = 0,
    Rotation = -45,
}, Resizer)
new("Frame", {
    Size = UDim2.fromOffset(6, 2),
    Position = UDim2.new(1, -10, 1, -14),
    BackgroundColor3 = T.sub,
    BorderSizePixel = 0,
    Rotation = -45,
}, Resizer)

--============================ 6.5 启动动画 ===========================--
do
    Main.Visible = false

    local Splash = new("Frame", {
        Name = "Splash",
        Size = UDim2.new(1, 0, 1, 0),
        BackgroundColor3 = Color3.fromRGB(11, 11, 14),
        BorderSizePixel = 0,
        ZIndex = 50,
    }, gui)

    -- 中间的圆形 Logo
    local LogoWrap = new("Frame", {
        Size = UDim2.fromOffset(74, 74),
        Position = UDim2.new(0.5, -37, 0.5, -118),
        BackgroundColor3 = T.accent,
        BorderSizePixel = 0,
        ZIndex = 51,
    }, Splash)
    corner(LogoWrap, 24)
    local LogoScale = new("UIScale", { Scale = 1 }, LogoWrap)
    new("TextLabel", {
        Size = UDim2.new(1, 0, 1, 0),
        BackgroundTransparency = 1,
        Font = Enum.Font.GothamBold,
        TextSize = 34,
        TextColor3 = Color3.new(1, 1, 1),
        Text = "♪",
        ZIndex = 52,
    }, LogoWrap)

    local function stab(txt, x, y, w, h, size, col, bold)
        return new("TextLabel", {
            Size = UDim2.fromOffset(w, h),
            Position = UDim2.new(0.5, x, 0.5, y),
            BackgroundTransparency = 1,
            Font = bold and Enum.Font.GothamBold or Enum.Font.Gotham,
            TextSize = size,
            TextColor3 = col,
            Text = txt,
            TextXAlignment = Enum.TextXAlignment.Center,
            ZIndex = 51,
        }, Splash)
    end

    stab("ZakaMusic", -140, -28, 280, 32, 26, T.text, true)
    stab("网易云风格 · 酷狗曲库 · 歌词 / 音量 / 缩放", -170, 6, 340, 16, 11, T.sub)
    stab("v1.3", 116, 62, 60, 14, 9, T.sub)

    -- 进度条
    local Track = new("Frame", {
        Size = UDim2.fromOffset(220, 4),
        Position = UDim2.new(0.5, -110, 0.5, 40),
        BackgroundColor3 = T.line,
        BorderSizePixel = 0,
        ZIndex = 51,
    }, Splash)
    corner(Track, 2)
    local Fill = new("Frame", {
        Size = UDim2.new(0, 0, 1, 0),
        BackgroundColor3 = T.accent,
        BorderSizePixel = 0,
        ZIndex = 52,
    }, Track)
    corner(Fill, 2)

    local Status = stab("正在启动…", -150, 56, 300, 16, 10, T.sub)

    -- Logo 呼吸
    task.spawn(function()
        while LogoWrap.Parent do
            TweenService:Create(LogoScale, TweenInfo.new(0.8, Enum.EasingStyle.Sine), { Scale = 1.14 }):Play()
            task.wait(0.85)
            if not LogoWrap.Parent then break end
            TweenService:Create(LogoScale, TweenInfo.new(0.8, Enum.EasingStyle.Sine), { Scale = 1 }):Play()
            task.wait(0.85)
        end
    end)

    local function fadeOutAll(root, dur)
        local info = TweenInfo.new(dur or 0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
        local all = { root }
        for _, d in ipairs(root:GetDescendants()) do all[#all + 1] = d end
        for _, d in ipairs(all) do
            for _, p in ipairs({ "BackgroundTransparency", "TextTransparency", "ImageTransparency" }) do
                local ok, cur = pcall(function() return d[p] end)
                if ok and type(cur) == "number" and cur < 1 then
                    pcall(function()
                        TweenService:Create(d, info, { [p] = 1 }):Play()
                    end)
                end
            end
        end
    end

    local function revealMain()
        Main.Visible = true
        scale.Scale = 0.94
        Main.Position = UDim2.new(0, 60, 0, 104)
        TweenService:Create(scale, TweenInfo.new(0.34, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
            { Scale = 1 }):Play()
        TweenService:Create(Main, TweenInfo.new(0.34, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
            { Position = UDim2.new(0, 60, 0, 90) }):Play()
    end

    if CFG.splash == false then
        Splash:Destroy()
        Main.Visible = true
    else
        task.spawn(function()
            task.wait(0.35)
            Status.Text = "正在初始化运行环境…"
            TweenService:Create(Fill, TweenInfo.new(0.7, Enum.EasingStyle.Quad), { Size = UDim2.new(0.45, 0, 1, 0) }):Play()
            task.wait(0.75)
            Status.Text = "正在连接酷狗曲库…"
            TweenService:Create(Fill, TweenInfo.new(0.7, Enum.EasingStyle.Quad), { Size = UDim2.new(0.82, 0, 1, 0) }):Play()
            task.wait(0.75)
            Status.Text = "正在装配界面组件…"
            TweenService:Create(Fill, TweenInfo.new(0.55, Enum.EasingStyle.Quad), { Size = UDim2.new(1, 0, 1, 0) }):Play()
            task.wait(0.6)
            Status.Text = "就绪 ✓"
            task.wait(0.25)
            fadeOutAll(Splash, 0.35)
            revealMain()
            task.wait(0.4)
            Splash:Destroy()
        end)
    end
end

--============================ 7. 交互逻辑 ============================--
-- 拖动
do
    local dragging, dragStart, startPos
    Top.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPos = Main.Position
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then dragging = false end
            end)
        end
    end)
    UIS.InputChanged:Connect(function(input)
        if not dragging then return end
        if input.UserInputType == Enum.UserInputType.MouseMovement
            or input.UserInputType == Enum.UserInputType.Touch then
            local d = input.Position - dragStart
            Main.Position = UDim2.new(
                startPos.X.Scale, startPos.X.Offset + d.X,
                startPos.Y.Scale, startPos.Y.Offset + d.Y)
        end
    end)
end

-- 缩放 (右下角拖拽)
do
    local resizing, startSize, startPos
    Resizer.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            resizing = true
            startSize = Main.AbsoluteSize
            startPos = input.Position
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then resizing = false end
            end)
        end
    end)
    UIS.InputChanged:Connect(function(input)
        if not resizing then return end
        local d = input.Position - startPos
        local w = math.clamp(startSize.X + d.X, 320, 900)
        local h = math.clamp(startSize.Y + d.Y, 260, 700)
        Main.Size = UDim2.fromOffset(w, h)
    end)
end

-- Ctrl + 滚轮缩放
UIS.InputChanged:Connect(function(input)
    if input.UserInputType ~= Enum.UserInputType.MouseWheel then return end
    if not UIS:IsKeyDown(Enum.KeyCode.LeftControl) and not UIS:IsKeyDown(Enum.KeyCode.RightControl) then return end
    scale.Scale = math.clamp(scale.Scale + input.Position.Z * 0.05, 0.6, 2)
end)

-- 进度条点击/拖动
do
    local seeking = false
    local function seek(input)
        local rel = (input.Position.X - ProgressBg.AbsolutePosition.X) / ProgressBg.AbsoluteSize.X
        rel = math.clamp(rel, 0, 1)
        ProgressFill.Size = UDim2.new(rel, 0, 1, 0)
        ProgressDot.Position = UDim2.new(rel, 0, 0.5, 0)
        local dur = Player.sound.TimeLength
        if dur and dur > 0 then
            Player.sound.TimePosition = dur * rel
        end
    end
    ProgressBg.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            seeking = true
            seek(input)
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then seeking = false end
            end)
        end
    end)
    UIS.InputChanged:Connect(function(input)
        if seeking and (input.UserInputType == Enum.UserInputType.MouseMovement
            or input.UserInputType == Enum.UserInputType.Touch) then
            seek(input)
        end
    end)
end

-- 音量拖动
do
    local volDrag = false
    local function setVol(input)
        local rel = (input.Position.X - VolBg.AbsolutePosition.X) / VolBg.AbsoluteSize.X
        rel = math.clamp(rel, 0, 1)
        CFG.volume = rel
        VolFill.Size = UDim2.new(rel, 0, 1, 0)
        VolLabel.Text = math.floor(rel * 100) .. "%"
        Player.sound.Volume = rel
    end
    VolBg.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            volDrag = true
            setVol(input)
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then volDrag = false end
            end)
        end
    end)
    UIS.InputChanged:Connect(function(input)
        if volDrag and (input.UserInputType == Enum.UserInputType.MouseMovement
            or input.UserInputType == Enum.UserInputType.Touch) then
            setVol(input)
        end
    end)
end

-- 歌词开关
LrcBtn.MouseButton1Click:Connect(function()
    CFG.showLyric = not CFG.showLyric
    LrcScroll.Visible = CFG.showLyric
    LrcBtn.Text = CFG.showLyric and "歌词" or "无字幕"
    LrcBtn.BackgroundColor3 = CFG.showLyric and T.card or T.accent
end)

-- 歌单开关
ListBtn.MouseButton1Click:Connect(function()
    UI.showList(not ListBox.Visible)
end)

-- 播放控制
PlayBtn.MouseButton1Click:Connect(function() Player.toggle() end)
NextBtn.MouseButton1Click:Connect(function() Player.next() end)
PrevBtn.MouseButton1Click:Connect(function() Player.prev() end)

CloseBtn.MouseButton1Click:Connect(function()
    gui:Destroy()
end)

-- 搜索
local search = { kw = "", page = 0, hasMore = false }

function UI.renderList(res, append)
    if append then
        for _, t in ipairs(res) do
            Player.list[#Player.list + 1] = t
            listRow(t, #Player.list)
        end
    else
        Player.list = res
        Player.index = 0
        UI.fillList(res)
    end
    UI.addMoreRow(search.hasMore)
end

function UI.onMore()
    UI.runSearch(search.kw, search.page + 1, true)
end

function UI.runSearch(kw, page, append)
    kw = (kw or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if kw == "" then return end
    search.kw, search.page = kw, page or 1
    UI.hideSuggest()
    SearchBox.Text = kw
    if not append then
        UI.setLyricText("搜索中…   「" .. kw .. "」")
        UI.showList(true)
    end
    task.spawn(function()
        local res = API.search(kw, search.page)
        if #res == 0 then
            if append then
                search.hasMore = false
                UI.addMoreRow(false)
                UI.setLyricText("没有更多了")
            else
                UI.setLyricText("没搜到, 换个关键词试试")
                UI.showList(false)
            end
            return
        end
        search.hasMore = (#res >= 20)
        UI.renderList(res, append)
        pushHist(kw)
        UI.setLyricText(string.format("「%s」 %d 首 · 点歌单里的歌直接播放", kw, #Player.list))
    end)
end

SearchBox.Focused:Connect(function()
    UI.refreshSuggest()
end)

SearchBox.FocusLost:Connect(function(enter)
    task.delay(0.2, function() UI.hideSuggest() end)
    if not enter then return end
    local kw = SearchBox.Text
    if kw == "" then return end
    UI.runSearch(kw, 1, false)
end)

-- 登录面板
do
    local Login = new("Frame", {
        Size = UDim2.fromOffset(320, 216),
        Position = UDim2.new(0.5, -160, 0.5, -108),
        BackgroundColor3 = T.panel,
        BorderSizePixel = 0,
        Visible = false,
        ZIndex = 20,
    }, Main)
    corner(Login, 12)
    stroke(Login, T.line)

    local function label(txt, y, h, size, col, bold, wrap)
        return new("TextLabel", {
            Size = UDim2.new(1, -24, 0, h),
            Position = UDim2.fromOffset(12, y),
            BackgroundTransparency = 1,
            Font = bold and Enum.Font.GothamBold or Enum.Font.Gotham,
            TextSize = size,
            TextColor3 = col,
            TextXAlignment = Enum.TextXAlignment.Left,
            TextWrapped = wrap and true or false,
            Text = txt,
        }, Login)
    end

    local function field(ph, y)
        local t = new("TextBox", {
            Size = UDim2.new(1, -24, 0, 30),
            Position = UDim2.fromOffset(12, y),
            BackgroundColor3 = T.card,
            BorderSizePixel = 0,
            Font = Enum.Font.Gotham,
            TextSize = 12,
            TextColor3 = T.text,
            PlaceholderText = ph,
            PlaceholderColor3 = T.sub,
            Text = "",
            ClearTextOnFocus = false,
        }, Login)
        corner(t, 8)
        pad(t, 10, 10, 0, 0)
        return t
    end

    label("登录酷狗音乐", 12, 20, 14, T.text, true)
    label("短信验证码通道已停用,请用下面的 token + userid 登录", 34, 16, 10, T.accent)

    local TokenBox  = field("token", 56)
    local UserIdBox = field("userid", 90)

    label("获取方式:电脑浏览器登录 kugou.com  →  按 F12  →  Application  →  Cookies,把 token 和 userid 两项值复制过来",
        124, 30, 9, T.sub, false, true)

    local DoLogin = new("TextButton", {
        Size = UDim2.fromOffset(96, 30),
        Position = UDim2.fromOffset(12, 158),
        BackgroundColor3 = T.accent,
        BorderSizePixel = 0,
        Font = Enum.Font.GothamBold,
        TextSize = 12,
        TextColor3 = Color3.new(1, 1, 1),
        Text = "登录",
    }, Login)
    corner(DoLogin, 8)

    local Logout = new("TextButton", {
        Size = UDim2.fromOffset(96, 30),
        Position = UDim2.new(1, -108, 0, 158),
        BackgroundColor3 = T.card,
        BorderSizePixel = 0,
        Font = Enum.Font.GothamBold,
        TextSize = 12,
        TextColor3 = T.text,
        Text = "退出登录",
    }, Login)
    corner(Logout, 8)

    local Tip = label("", 192, 18, 10, T.sub)

    -- 让面板内容盖住其它控件
    for _, c in ipairs(Login:GetDescendants()) do
        if c:IsA("GuiObject") then c.ZIndex = 21 end
    end

    local function saveAccount()
        if not writefileFn then return end
        pcall(writefileFn, CFG.userFile,
            (CFG.token or "") .. "\n" .. (CFG.userid or "") .. "\n" .. (CFG.nickname or ""))
    end

    local function applyHeader()
        Avatar.Text = CFG.isVip and "VIP" or "已登录"
        Avatar.BackgroundColor3 = T.card
        SongSub.Text = (CFG.nickname or "酷狗用户") .. (CFG.isVip and " · VIP" or " · 普通用户")
    end

    local function finishLogin()
        applyHeader()
        UI.setLyricText("登录成功, 正在同步收藏…")
        task.spawn(function()
            local favs = API.favorites()
            if #favs > 0 then
                Player.list = favs
                UI.fillList(favs)
                UI.addMoreRow(false)
                UI.showList(true)
            end
            UI.setLyricText(string.format("已同步 %d 首收藏", #favs))
        end)
    end

    DoLogin.MouseButton1Click:Connect(function()
        local tk  = (TokenBox.Text or ""):gsub("%s", "")
        local uid = (UserIdBox.Text or ""):gsub("%s", "")
        if tk == "" or uid == "" then Tip.Text = "token 和 userid 两项都要填"; return end
        Tip.Text = "校验中…"
        task.spawn(function()
            CFG.token, CFG.userid = tk, uid
            CFG.nickname = "酷狗用户" .. uid
            CFG.isVip = API.vipInfo()
            saveAccount()
            Tip.Text = CFG.isVip and "登录成功 (VIP 已生效)" or "已登录 (普通账号)"
            task.wait(0.5)
            Login.Visible = false
            finishLogin()
        end)
    end)

    Logout.MouseButton1Click:Connect(function()
        CFG.token, CFG.userid = "", ""
        CFG.nickname, CFG.isVip = "未登录", false
        if writefileFn then pcall(writefileFn, CFG.userFile, "\n\n未登录") end
        TokenBox.Text, UserIdBox.Text = "", ""
        Avatar.Text = "登录"
        Avatar.BackgroundColor3 = T.accent
        SongSub.Text = "网易云风格 · 支持歌词/音量/缩放"
        Tip.Text = "已清除本地保存的凭据"
    end)

    Avatar.MouseButton1Click:Connect(function()
        Login.Visible = not Login.Visible
    end)

    -- 启动时自动读取上次保存的凭据
    task.spawn(function()
        if not (readfileFn and isfileFn) then return end
        local ok, ex = pcall(isfileFn, CFG.userFile)
        if not ok or not ex then return end
        local ok2, data = pcall(readfileFn, CFG.userFile)
        if not ok2 or type(data) ~= "string" then return end
        local lines = {}
        for l in data:gmatch("[^\r\n]*") do lines[#lines + 1] = l end
        local tk  = (lines[1] or ""):gsub("%s", "")
        local uid = (lines[2] or ""):gsub("%s", "")
        if tk == "" or uid == "" then return end
        CFG.token, CFG.userid = tk, uid
        CFG.nickname = "酷狗用户" .. uid
        TokenBox.Text, UserIdBox.Text = tk, uid
        CFG.isVip = API.vipInfo()
        applyHeader()
        local favs = API.favorites()
        if #favs > 0 then
            Player.list = favs
            UI.fillList(favs)
            UI.addMoreRow(false)
            UI.showList(true)
            UI.setLyricText(string.format("已自动登录 · 同步 %d 首收藏", #favs))
        else
            UI.setLyricText("已自动登录 · 搜歌框输入关键词回车 或 点搜索框看历史/热门")
        end
    end)
end

--============================ 8. UI 更新循环 ============================--
function UI.setNow(track, loading)
    SongTitle.Text = track.name
    SongSub.Text = string.format("%s%s%s",
        track.singer ~= "" and track.singer or "未知歌手",
        track.vip and "  [VIP]" or "",
        loading and "   加载中..." or "")
end

function UI.setCover(url)
    local ok, fn = pcall(function() return httpFn() end)
    if not ok or not fn then return end
    task.spawn(function()
        local res = httpGet(url, apiHeaders())
        if not res or not res.Body or #res.Body < 512 then return end
        if not writefileFn or not getcustomassetFn then return end
        local p = CFG.cacheDir .. "/cover.jpg"
        local okw = pcall(writefileFn, p, res.Body)
        if not okw then return end
        local a = toAsset(p)
        if a then
            pcall(function() Cover.Image = a end)
        end
    end)
end

function UI.setLrc(text)
    for _, c in ipairs(LrcScroll:GetChildren()) do
        if c:IsA("TextLabel") then c:Destroy() end
    end
    LrcTexts = {}
    Player.lrcTimes = {}
    Player.lrcIndex = 0
    if not text or text == "" then
        UI.setLyricText("暂无歌词")
        return
    end
    local lines = {}
    for line in text:gmatch("[^\r\n]+") do
        local times = {}
        local bodyParts = {}
        local rest = line
        for mm, ss, ms in rest:gmatch("%[(%d+):(%d+)[%.%:](%d+)%]") do
            times[#times + 1] = tonumber(mm) * 60 + tonumber(ss) + tonumber(ms) / (10 ^ #ms)
        end
        if #times == 0 then
            for mm, ss in rest:gmatch("%[(%d+):(%d+)%]") do
                times[#times + 1] = tonumber(mm) * 60 + tonumber(ss)
            end
        end
        local body = rest:gsub("%[%d+:%d+%.%d+%]", "")
        local body2 = body:gsub("%[[^%]]*%]", "")
        body2 = body2:gsub("%s+$", "")
        if #times > 0 and body2 ~= "" then
            for _, t in ipairs(times) do
                lines[#lines + 1] = { t = t, s = body2 }
            end
        end
    end
    table.sort(lines, function(a, b) return a.t < b.t end)
    if #lines == 0 then
        UI.setLyricText("暂无歌词")
        return
    end
    for i, l in ipairs(lines) do
        local lb = new("TextLabel", {
            Size = UDim2.new(1, 0, 0, 22),
            BackgroundTransparency = 1,
            Font = Enum.Font.Gotham,
            TextSize = 14,
            TextColor3 = T.sub,
            TextWrapped = true,
            LayoutOrder = i,
            Text = l.s,
        }, LrcScroll)
        new("UITextSizeConstraint", { MaxTextSize = 15 }, lb)
        LrcTexts[i] = lb
        Player.lrcTimes[i] = l.t
    end
end

local function fmtTime(s)
    s = math.max(0, math.floor(s or 0))
    return string.format("%02d:%02d", math.floor(s / 60), s % 60)
end

RunService.Heartbeat:Connect(function()
    local snd = Player.sound
    local dur = snd.TimeLength
    if dur and dur > 0 then
        local rel = math.clamp(snd.TimePosition / dur, 0, 1)
        ProgressFill.Size = UDim2.new(rel, 0, 1, 0)
        ProgressDot.Position = UDim2.new(rel, 0, 0.5, 0)
        CurTime.Text = fmtTime(snd.TimePosition)
        TotTime.Text = fmtTime(dur)
        UI.refreshPlayBtn()
    end

    -- 歌词滚动
    if CFG.showLyric and Player.lrcTimes and #Player.lrcTimes > 0 then
        local pos = snd.TimePosition
        local idx = 0
        for i = 1, #Player.lrcTimes do
            if pos >= Player.lrcTimes[i] then idx = i else break end
        end
        if idx ~= Player.lrcIndex and idx > 0 then
            Player.lrcIndex = idx
            for i, lb in pairs(LrcTexts) do
                if i == idx then
                    lb.TextColor3 = Color3.new(1, 1, 1)
                    lb.Font = Enum.Font.GothamBold
                else
                    lb.TextColor3 = T.sub
                    lb.Font = Enum.Font.Gotham
                end
            end
            local target = LrcTexts[idx]
            if target then
                local y = target.AbsolutePosition.Y - LrcScroll.AbsolutePosition.Y + LrcScroll.CanvasPosition.Y
                TweenService:Create(LrcScroll, TweenInfo.new(0.25), {
                    CanvasPosition = Vector3.new(0, math.max(0, y - LrcScroll.AbsoluteSize.Y / 2 + 12), 0),
                }):Play()
            end
        end
    end
end)

--============================ 9. 启动 ============================--
pcall(function() UIS.MouseIconEnabled = true end)
UI.setLyricText("ZakaMusic 已启动  ·  点搜索框看历史/热门,或直接输关键词回车  ·  右上角头像绑定账号")
UI.refreshPlayBtn()

print("[ZakaMusic] loaded. UI Scale:", scale.Scale)
