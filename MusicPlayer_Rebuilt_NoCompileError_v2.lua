-- Roblox Exploit MP3 Player GUI - Final with Cooldown Fix + Auto Translate
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local HttpService = game:GetService("HttpService")
local CoreGui = game:GetService("CoreGui")
local StarterGui = game:GetService("StarterGui")
local SoundService = game:GetService("SoundService")

local player = Players.LocalPlayer
local mouse = player:GetMouse()

-- ========== FOLDER STRUCTURE ==========
local MUSIC_FOLDER = "MusicPlayerData"
local CACHE_FOLDER = MUSIC_FOLDER .. "/Cache"
local IMAGES_FOLDER = MUSIC_FOLDER .. "/Images"
pcall(function() if makefolder then makefolder(MUSIC_FOLDER) end end)
pcall(function() if makefolder then makefolder(CACHE_FOLDER) end end)
pcall(function() if makefolder then makefolder(IMAGES_FOLDER) end end)

local HISTORY_FILE = MUSIC_FOLDER .. "/mp3_history.json"
local CACHE_FILE = MUSIC_FOLDER .. "/mp3_cache.json"
local SETTINGS_FILE = MUSIC_FOLDER .. "/mp3_settings.json"
local KEY_FILE = MUSIC_FOLDER .. "/mp3_key.txt"
local IMAGE_CACHE_FILE = MUSIC_FOLDER .. "/image_cache.json"
local PLAYLIST_DATA_FILE = MUSIC_FOLDER .. "/user_playlist.json"
local STATS_FILE = MUSIC_FOLDER .. "/music_stats.json"

-- ========== ERROR NOTIFICATION ==========
local function showNotification(title, text, duration)
    pcall(function() StarterGui:SetCore("SendNotification", {Title = title, Text = text, Duration = duration or 5}) end)
    print("[MusicPlayer] " .. title .. ": " .. text)
end

-- ========== STOP OLD MUSIC & CLEANUP ==========
pcall(function() local oldGui = CoreGui:FindFirstChild("MusicPlayerGUI"); if oldGui then oldGui:Destroy() end end)
pcall(function() local oldMini = CoreGui:FindFirstChild("MusicPlayerMiniGUI"); if oldMini then oldMini:Destroy() end end)
pcall(function() local oldExtra = CoreGui:FindFirstChild("MusicPlayerExtraMini"); if oldExtra then oldExtra:Destroy() end end)
pcall(function() local oldHide = CoreGui:FindFirstChild("MusicPlayerHideBtn"); if oldHide then oldHide:Destroy() end end)
pcall(function() local oldShow = CoreGui:FindFirstChild("MusicPlayerShowGui"); if oldShow then oldShow:Destroy() end end)
pcall(function() for _, obj in pairs(workspace:GetDescendants()) do if obj:IsA("Sound") and obj.Name == "MusicPlayerSound" then obj:Stop(); obj:Destroy() end end end)

local S = {autoTranslateEnabled=false, translationCache={}, userLanguage="en", translatableElements={}}

-- ========== AUTO TRANSLATE SYSTEM ==========

local function detectUserLanguage()
    local locale = "en"
    pcall(function()
        local localizationService = game:GetService("LocalizationService")
        if localizationService and localizationService.RobloxLocaleId then
            local fullLocale = localizationService.RobloxLocaleId:lower()
            locale = fullLocale:match("^(%w+)") or "en"
        end
    end)
    return locale
end

local function translateText(text, targetLang)
    if not text or text == "" then return text end
    if targetLang == "en" then return text end
    
    local cacheKey = text .. "|" .. targetLang
    if S.translationCache[cacheKey] then
        return S.translationCache[cacheKey]
    end
    
    local translated = text
    pcall(function()
        local url = "https://translate.googleapis.com/translate_a/single?client=gtx&sl=auto&tl=" .. targetLang .. "&dt=t&q=" .. HttpService:UrlEncode(text)
        local response = game:HttpGet(url)
        local decoded = HttpService:JSONDecode(response)
        if decoded and decoded[1] and decoded[1][1] and decoded[1][1][1] then
            translated = decoded[1][1][1]
            S.translationCache[cacheKey] = translated
        end
    end)
    
    return translated
end

local function registerForTranslation(guiElement, originalText)
    if not guiElement or not originalText then return end
    table.insert(S.translatableElements, {
        element = guiElement,
        original = originalText,
    })
end

local function updateTranslatableText(guiElement, newText)
    if not guiElement or not newText then return end
    local found = false
    for _, item in ipairs(S.translatableElements) do
        if item.element == guiElement then
            item.original = newText
            found = true
            break
        end
    end
    if not found then
        registerForTranslation(guiElement, newText)
    end
    if S.autoTranslateEnabled then
        guiElement.Text = translateText(newText, S.userLanguage)
    else
        guiElement.Text = newText
    end
end

local function applyTranslations()
    for _, item in ipairs(S.translatableElements) do
        if item.element and item.element.Parent then
            if S.autoTranslateEnabled then
                local translated = translateText(item.original, S.userLanguage)
                item.element.Text = translated
            else
                item.element.Text = item.original
            end
        end
    end
end

-- ========== SHARED STATE ==========
-- GUI references are also stored in S to keep the executor's top-level local count low.
-- Fields are created on demand by the GUI builder.
-- ========== IMAGE CACHE ==========
local function loadImageCache() local s, r = pcall(function() if readfile and isfile and isfile(IMAGE_CACHE_FILE) then return HttpService:JSONDecode(readfile(IMAGE_CACHE_FILE)) end end); return s and r or {} end
local function saveImageCache() pcall(function() if writefile then writefile(IMAGE_CACHE_FILE, HttpService:JSONEncode(S.imageCache)) end end) end

-- ========== IMAGE DOWNLOAD ==========
local function downloadImage(url, songIndex)
    if not url or url == "" then return "" end; url = string.gsub(url, "^%s+", ""); url = string.gsub(url, "%s+$", "")
    if S.imageCache[url] then local cachedFile = S.imageCache[url].file; if isfile and isfile(cachedFile) then return S.imageCache[url].asset else S.imageCache[url] = nil end end
    local urlHash = 0; for i = 1, #url do urlHash = (urlHash * 31 + string.byte(url, i)) % 10000000 end
    local ext = ".jpeg"; if string.find(string.lower(url), ".png") then ext = ".png" elseif string.find(string.lower(url), ".jpg") then ext = ".jpg" elseif string.find(string.lower(url), ".webp") then ext = ".webp" elseif string.find(string.lower(url), ".gif") then ext = ".gif" end
    local fn = IMAGES_FOLDER .. "/img_" .. urlHash .. ext
    if isfile and isfile(fn) then local as, a = pcall(function() return getcustomasset(fn) end); if as and a and a ~= "" then S.imageCache[url] = {file = fn, asset = a}; saveImageCache(); return a end end
    local success = pcall(function() local d = game:HttpGet(url); if d and #d > 100 then writefile(fn, d) end end)
    if success and isfile and isfile(fn) then local as, a = pcall(function() return getcustomasset(fn) end); if as and a and a ~= "" then S.imageCache[url] = {file = fn, asset = a}; saveImageCache(); return a end end
    return url
end

-- ========== ALL THEMES (11 S.themes) ==========
S.themes = {
    Default = {mainBg=Color3.fromRGB(40,40,40),titleBg=Color3.fromRGB(30,30,30),outlineColor=Color3.fromRGB(80,80,80),inputBg=Color3.fromRGB(60,60,60),playColor=Color3.fromRGB(70,180,70),pauseColor=Color3.fromRGB(255,180,50),stopColor=Color3.fromRGB(200,70,70),historyColor=Color3.fromRGB(100,100,200),muteColor=Color3.fromRGB(180,80,80),muteOnColor=Color3.fromRGB(80,180,80),searchColor=Color3.fromRGB(100,150,255),infoColor=Color3.fromRGB(100,180,255),settingColor=Color3.fromRGB(150,150,150),timeSlider=Color3.fromRGB(100,180,255),speedBtnColor=Color3.fromRGB(100,100,180),textColor=Color3.fromRGB(255,255,255),labelColor=Color3.fromRGB(255,255,255),miniBtnColor=Color3.fromRGB(80,80,80),tabActive=Color3.fromRGB(100,150,255),tabInactive=Color3.fromRGB(60,60,70),scrollBarColor=Color3.fromRGB(130,130,140),loopRed=Color3.fromRGB(200,70,70),loopGreen=Color3.fromRGB(70,180,70),loopOrange=Color3.fromRGB(255,150,50),loopOff=Color3.fromRGB(130,130,130),loopOn=Color3.fromRGB(70,180,70)},
    ["Dark Blue"] = {mainBg=Color3.fromRGB(15,25,45),titleBg=Color3.fromRGB(10,18,35),outlineColor=Color3.fromRGB(40,80,140),inputBg=Color3.fromRGB(25,40,65),playColor=Color3.fromRGB(50,140,200),pauseColor=Color3.fromRGB(200,150,40),stopColor=Color3.fromRGB(180,60,60),historyColor=Color3.fromRGB(60,80,160),muteColor=Color3.fromRGB(160,70,70),muteOnColor=Color3.fromRGB(60,160,80),searchColor=Color3.fromRGB(70,120,220),infoColor=Color3.fromRGB(70,140,220),settingColor=Color3.fromRGB(80,100,150),timeSlider=Color3.fromRGB(70,150,230),speedBtnColor=Color3.fromRGB(60,80,150),textColor=Color3.fromRGB(220,230,255),labelColor=Color3.fromRGB(200,215,245),miniBtnColor=Color3.fromRGB(50,50,70),tabActive=Color3.fromRGB(70,120,220),tabInactive=Color3.fromRGB(30,40,60),scrollBarColor=Color3.fromRGB(80,80,100),loopRed=Color3.fromRGB(180,60,60),loopGreen=Color3.fromRGB(60,160,80),loopOrange=Color3.fromRGB(200,150,40),loopOff=Color3.fromRGB(130,130,130),loopOn=Color3.fromRGB(60,160,80)},
    Light = {mainBg=Color3.fromRGB(235,235,240),titleBg=Color3.fromRGB(220,220,225),outlineColor=Color3.fromRGB(180,180,190),inputBg=Color3.fromRGB(210,210,215),playColor=Color3.fromRGB(80,200,80),pauseColor=Color3.fromRGB(255,170,40),stopColor=Color3.fromRGB(220,80,80),historyColor=Color3.fromRGB(130,130,220),muteColor=Color3.fromRGB(200,100,100),muteOnColor=Color3.fromRGB(100,200,100),searchColor=Color3.fromRGB(120,170,255),infoColor=Color3.fromRGB(120,190,255),settingColor=Color3.fromRGB(170,170,180),timeSlider=Color3.fromRGB(120,190,255),speedBtnColor=Color3.fromRGB(130,130,200),textColor=Color3.fromRGB(30,30,35),labelColor=Color3.fromRGB(40,40,45),miniBtnColor=Color3.fromRGB(200,200,210),tabActive=Color3.fromRGB(120,170,255),tabInactive=Color3.fromRGB(190,190,200),scrollBarColor=Color3.fromRGB(160,160,170),loopRed=Color3.fromRGB(220,80,80),loopGreen=Color3.fromRGB(80,200,80),loopOrange=Color3.fromRGB(255,170,40),loopOff=Color3.fromRGB(180,180,180),loopOn=Color3.fromRGB(80,200,80)},
    ["Neon Light"] = {mainBg=Color3.fromRGB(20,20,20),titleBg=Color3.fromRGB(10,10,10),outlineColor=Color3.fromRGB(0,255,128),inputBg=Color3.fromRGB(35,35,35),playColor=Color3.fromRGB(0,255,100),pauseColor=Color3.fromRGB(255,180,0),stopColor=Color3.fromRGB(255,50,100),historyColor=Color3.fromRGB(128,0,255),muteColor=Color3.fromRGB(255,60,60),muteOnColor=Color3.fromRGB(0,255,60),searchColor=Color3.fromRGB(255,0,255),infoColor=Color3.fromRGB(0,255,255),settingColor=Color3.fromRGB(180,180,180),timeSlider=Color3.fromRGB(0,255,200),speedBtnColor=Color3.fromRGB(200,100,255),textColor=Color3.fromRGB(255,255,255),labelColor=Color3.fromRGB(200,255,220),miniBtnColor=Color3.fromRGB(50,50,50),tabActive=Color3.fromRGB(255,0,255),tabInactive=Color3.fromRGB(50,50,60),scrollBarColor=Color3.fromRGB(100,100,100),loopRed=Color3.fromRGB(255,50,100),loopGreen=Color3.fromRGB(0,255,100),loopOrange=Color3.fromRGB(255,180,0),loopOff=Color3.fromRGB(130,130,130),loopOn=Color3.fromRGB(0,255,100)},
    ["Dark Light"] = {mainBg=Color3.fromRGB(50,50,55),titleBg=Color3.fromRGB(40,40,45),outlineColor=Color3.fromRGB(100,100,110),inputBg=Color3.fromRGB(70,70,75),playColor=Color3.fromRGB(90,190,90),pauseColor=Color3.fromRGB(240,170,50),stopColor=Color3.fromRGB(210,80,80),historyColor=Color3.fromRGB(120,120,210),muteColor=Color3.fromRGB(190,90,90),muteOnColor=Color3.fromRGB(90,190,90),searchColor=Color3.fromRGB(110,160,255),infoColor=Color3.fromRGB(110,190,255),settingColor=Color3.fromRGB(160,160,170),timeSlider=Color3.fromRGB(110,190,255),speedBtnColor=Color3.fromRGB(120,120,190),textColor=Color3.fromRGB(240,240,245),labelColor=Color3.fromRGB(220,220,230),miniBtnColor=Color3.fromRGB(70,70,80),tabActive=Color3.fromRGB(110,160,255),tabInactive=Color3.fromRGB(60,60,70),scrollBarColor=Color3.fromRGB(100,100,110),loopRed=Color3.fromRGB(210,80,80),loopGreen=Color3.fromRGB(90,190,90),loopOrange=Color3.fromRGB(240,170,50),loopOff=Color3.fromRGB(150,150,150),loopOn=Color3.fromRGB(90,190,90)},
    Bright = {mainBg=Color3.fromRGB(255,255,255),titleBg=Color3.fromRGB(240,240,245),outlineColor=Color3.fromRGB(200,200,210),inputBg=Color3.fromRGB(230,230,235),playColor=Color3.fromRGB(60,200,60),pauseColor=Color3.fromRGB(255,160,30),stopColor=Color3.fromRGB(255,60,60),historyColor=Color3.fromRGB(100,100,255),muteColor=Color3.fromRGB(255,80,80),muteOnColor=Color3.fromRGB(80,255,80),searchColor=Color3.fromRGB(100,150,255),infoColor=Color3.fromRGB(100,200,255),settingColor=Color3.fromRGB(180,180,190),timeSlider=Color3.fromRGB(100,180,255),speedBtnColor=Color3.fromRGB(120,120,220),textColor=Color3.fromRGB(20,20,25),labelColor=Color3.fromRGB(30,30,35),miniBtnColor=Color3.fromRGB(220,220,230),tabActive=Color3.fromRGB(100,150,255),tabInactive=Color3.fromRGB(220,220,230),scrollBarColor=Color3.fromRGB(180,180,190),loopRed=Color3.fromRGB(255,60,60),loopGreen=Color3.fromRGB(60,200,60),loopOrange=Color3.fromRGB(255,160,30),loopOff=Color3.fromRGB(200,200,200),loopOn=Color3.fromRGB(60,200,60)},
    Blue = {mainBg=Color3.fromRGB(20,40,80),titleBg=Color3.fromRGB(15,30,60),outlineColor=Color3.fromRGB(50,100,180),inputBg=Color3.fromRGB(30,55,100),playColor=Color3.fromRGB(50,160,220),pauseColor=Color3.fromRGB(220,160,40),stopColor=Color3.fromRGB(200,70,70),historyColor=Color3.fromRGB(80,100,200),muteColor=Color3.fromRGB(180,80,80),muteOnColor=Color3.fromRGB(80,200,100),searchColor=Color3.fromRGB(80,140,240),infoColor=Color3.fromRGB(80,160,240),settingColor=Color3.fromRGB(100,120,180),timeSlider=Color3.fromRGB(80,170,250),speedBtnColor=Color3.fromRGB(80,100,180),textColor=Color3.fromRGB(230,240,255),labelColor=Color3.fromRGB(210,225,250),miniBtnColor=Color3.fromRGB(40,50,80),tabActive=Color3.fromRGB(80,140,240),tabInactive=Color3.fromRGB(25,45,70),scrollBarColor=Color3.fromRGB(60,70,100),loopRed=Color3.fromRGB(200,70,70),loopGreen=Color3.fromRGB(80,200,100),loopOrange=Color3.fromRGB(220,160,40),loopOff=Color3.fromRGB(130,130,130),loopOn=Color3.fromRGB(80,200,100)},
    Purple = {mainBg=Color3.fromRGB(40,20,60),titleBg=Color3.fromRGB(30,15,45),outlineColor=Color3.fromRGB(120,60,180),inputBg=Color3.fromRGB(55,30,80),playColor=Color3.fromRGB(130,80,220),pauseColor=Color3.fromRGB(220,150,50),stopColor=Color3.fromRGB(200,60,100),historyColor=Color3.fromRGB(100,80,200),muteColor=Color3.fromRGB(180,70,100),muteOnColor=Color3.fromRGB(80,180,100),searchColor=Color3.fromRGB(150,100,255),infoColor=Color3.fromRGB(140,100,255),settingColor=Color3.fromRGB(150,120,180),timeSlider=Color3.fromRGB(150,100,255),speedBtnColor=Color3.fromRGB(120,80,200),textColor=Color3.fromRGB(240,230,255),labelColor=Color3.fromRGB(230,215,255),miniBtnColor=Color3.fromRGB(60,40,90),tabActive=Color3.fromRGB(150,100,255),tabInactive=Color3.fromRGB(50,35,70),scrollBarColor=Color3.fromRGB(100,70,140),loopRed=Color3.fromRGB(200,60,100),loopGreen=Color3.fromRGB(80,200,100),loopOrange=Color3.fromRGB(255,150,50),loopOff=Color3.fromRGB(130,130,130),loopOn=Color3.fromRGB(80,200,100)},
    Red = {mainBg=Color3.fromRGB(60,20,20),titleBg=Color3.fromRGB(45,15,15),outlineColor=Color3.fromRGB(180,40,40),inputBg=Color3.fromRGB(75,25,25),playColor=Color3.fromRGB(220,50,50),pauseColor=Color3.fromRGB(255,150,40),stopColor=Color3.fromRGB(180,40,40),historyColor=Color3.fromRGB(200,60,60),muteColor=Color3.fromRGB(200,60,60),muteOnColor=Color3.fromRGB(60,200,60),searchColor=Color3.fromRGB(255,60,60),infoColor=Color3.fromRGB(255,80,80),settingColor=Color3.fromRGB(180,120,120),timeSlider=Color3.fromRGB(255,60,60),speedBtnColor=Color3.fromRGB(200,60,60),textColor=Color3.fromRGB(255,230,230),labelColor=Color3.fromRGB(255,215,215),miniBtnColor=Color3.fromRGB(80,30,30),tabActive=Color3.fromRGB(255,60,60),tabInactive=Color3.fromRGB(70,30,30),scrollBarColor=Color3.fromRGB(140,50,50),loopRed=Color3.fromRGB(255,30,30),loopGreen=Color3.fromRGB(60,200,60),loopOrange=Color3.fromRGB(255,150,40),loopOff=Color3.fromRGB(150,150,150),loopOn=Color3.fromRGB(60,200,60)},
    Green = {mainBg=Color3.fromRGB(20,50,30),titleBg=Color3.fromRGB(15,38,22),outlineColor=Color3.fromRGB(40,160,60),inputBg=Color3.fromRGB(25,65,38),playColor=Color3.fromRGB(50,200,70),pauseColor=Color3.fromRGB(220,160,40),stopColor=Color3.fromRGB(200,60,60),historyColor=Color3.fromRGB(60,160,80),muteColor=Color3.fromRGB(180,60,60),muteOnColor=Color3.fromRGB(60,200,60),searchColor=Color3.fromRGB(60,220,80),infoColor=Color3.fromRGB(60,220,80),settingColor=Color3.fromRGB(100,160,120),timeSlider=Color3.fromRGB(60,220,80),speedBtnColor=Color3.fromRGB(60,180,80),textColor=Color3.fromRGB(220,255,230),labelColor=Color3.fromRGB(210,255,220),miniBtnColor=Color3.fromRGB(30,70,40),tabActive=Color3.fromRGB(60,220,80),tabInactive=Color3.fromRGB(25,60,35),scrollBarColor=Color3.fromRGB(50,130,65),loopRed=Color3.fromRGB(200,50,50),loopGreen=Color3.fromRGB(50,220,60),loopOrange=Color3.fromRGB(240,160,40),loopOff=Color3.fromRGB(130,130,130),loopOn=Color3.fromRGB(50,220,60)},
    Midnight = {mainBg=Color3.fromRGB(10,12,25),titleBg=Color3.fromRGB(8,10,20),outlineColor=Color3.fromRGB(30,60,120),inputBg=Color3.fromRGB(15,20,40),playColor=Color3.fromRGB(30,120,200),pauseColor=Color3.fromRGB(180,130,30),stopColor=Color3.fromRGB(160,40,60),historyColor=Color3.fromRGB(40,70,180),muteColor=Color3.fromRGB(150,50,60),muteOnColor=Color3.fromRGB(40,160,70),searchColor=Color3.fromRGB(50,100,220),infoColor=Color3.fromRGB(50,120,220),settingColor=Color3.fromRGB(60,80,150),timeSlider=Color3.fromRGB(50,140,230),speedBtnColor=Color3.fromRGB(40,70,170),textColor=Color3.fromRGB(200,215,250),labelColor=Color3.fromRGB(190,210,245),miniBtnColor=Color3.fromRGB(20,25,50),tabActive=Color3.fromRGB(50,100,220),tabInactive=Color3.fromRGB(15,25,50),scrollBarColor=Color3.fromRGB(40,50,90),loopRed=Color3.fromRGB(180,40,60),loopGreen=Color3.fromRGB(40,170,70),loopOrange=Color3.fromRGB(200,140,40),loopOff=Color3.fromRGB(130,130,130),loopOn=Color3.fromRGB(40,170,70)},
autoTranslateEnabled=false, translationCache={}, userLanguage="en", translatableElements={},
    currentSound=nil, isLooping=true, currentVolume=1.0, currentSpeed=1.0, isMinimized=false,
    downloadHistory={}, isPlaying=false, isPaused=false, pausedTimePosition=0,
    isDraggingTimeSlider=false, isDraggingMiniTimeSlider=false, isDraggingExtraSlider=false, isDraggingDataInterval=false,
    currentTheme="Default", currentSongName="", saveThemeEnabled=false, rememberKeyEnabled=false,
    miniPlayMode=false, extraMiniPlayMode=false, isGameMuted=false, timeSliderBlue=true,
    secretKey="", isKeyCorrect=false, playlistSongs={}, currentSearchTab="Search", currentPlaylistIndex=0,
    musicCache={}, imageCache={}, isSearchOpen=false, isInfoOpen=false, isSettingsOpen=false, isHistoryOpen=false,
    userPlaylist={}, playlistLoopEnabled=false, playlistCheckConnection=nil, loopState=1, mainLoopOn=true,
    currentSoundEffect="Default", playingTabOpen=false, gameSoundsMuted={}, hideButton=nil, showButton=nil,
    keybindEnabled=false, keybindConnection=nil, hiddenGuis={}, rainbowAnimation=nil,
    soundEffectPresets={}, themes={}, rainbowColorList={}, musicStats={}, dataRefreshInterval=15
}

-- ========== SETTINGS ==========
local function loadSettings()
    local s, r = pcall(function() if readfile and isfile and isfile(SETTINGS_FILE) then return HttpService:JSONDecode(readfile(SETTINGS_FILE)) end end)
    if s and r then
        if r.theme then S.currentTheme=r.theme end
        if r.saveThemeEnabled~=nil then S.saveThemeEnabled=r.saveThemeEnabled end
        if r.rememberKeyEnabled~=nil then S.rememberKeyEnabled=r.rememberKeyEnabled end
        if r.timeSliderBlue~=nil then S.timeSliderBlue=r.timeSliderBlue end
        if r.keybindEnabled~=nil then S.keybindEnabled=r.keybindEnabled end
        if r.autoTranslateEnabled~=nil then S.autoTranslateEnabled=r.autoTranslateEnabled end
    end
    local rk, rv = pcall(function() if readfile and isfile and isfile(KEY_FILE) then return HttpService:JSONDecode(readfile(KEY_FILE)) end end)
    if rk and rv then if rv.rememberKeyEnabled~=nil then S.rememberKeyEnabled=rv.rememberKeyEnabled end; if rv.isKeyCorrect then S.isKeyCorrect=true; pcall(function() loadPlaylist() end) end end
    local up, upv = pcall(function() if readfile and isfile and isfile(PLAYLIST_DATA_FILE) then return HttpService:JSONDecode(readfile(PLAYLIST_DATA_FILE)) end end)
    if up and upv then S.userPlaylist=upv end
end
local function saveSettings()
    pcall(function()
        if writefile then
            writefile(SETTINGS_FILE, HttpService:JSONEncode({
                theme=S.currentTheme,
                saveThemeEnabled=S.saveThemeEnabled,
                rememberKeyEnabled=S.rememberKeyEnabled,
                timeSliderBlue=S.timeSliderBlue,
                keybindEnabled=S.keybindEnabled,
                autoTranslateEnabled=S.autoTranslateEnabled
            }))
        end
    end)
end

local function saveKeyState() pcall(function() if writefile then writefile(KEY_FILE, HttpService:JSONEncode({rememberKeyEnabled=S.rememberKeyEnabled,isKeyCorrect=S.isKeyCorrect})) end end) end
local function deleteKeyFile() pcall(function() if isfile and isfile(KEY_FILE) then delfile(KEY_FILE) end end) end
local function saveUserPlaylist() pcall(function() if writefile then writefile(PLAYLIST_DATA_FILE, HttpService:JSONEncode(S.userPlaylist)) end end) end

-- ========== CLEAN SONG NAME ==========
local function cleanSongName(fn) if not fn then return "Unknown" end; fn=string.gsub(fn,"%.mp3$",""); fn=string.gsub(fn,"%.MP3$",""); fn=string.gsub(fn,"%%20"," "); return fn end

-- ========== UPDATE SLIDER COLORS ==========
local function updateSliderColors()
    local sliderColor = S.timeSliderBlue and Color3.fromRGB(100,180,255) or Color3.fromRGB(255,80,80)
    if S.TimeSlider then S.TimeSlider.BackgroundColor3=sliderColor end
    if S.MiniTimeSlider then S.MiniTimeSlider.BackgroundColor3=sliderColor end
    if S.ExtraTimeSlider then S.ExtraTimeSlider.BackgroundColor3=sliderColor end
end
local function updateSliderColorToggle() if not S.SliderColorToggle then return end; if S.timeSliderBlue then S.SliderColorToggle.BackgroundColor3=Color3.fromRGB(80,180,255); S.SliderColorToggle.Text="BLUE" else S.SliderColorToggle.BackgroundColor3=Color3.fromRGB(255,80,80); S.SliderColorToggle.Text="RED" end end

-- ========== LOOP TOGGLE DISPLAY ==========
local function updateLoopToggleDisplay()
    if not S.LoopToggle then return end
    local t=S.themes[S.currentTheme] or S.themes["Default"]
    if S.mainLoopOn then
        S.LoopToggle.BackgroundColor3=t.loopOn or Color3.fromRGB(70,180,70)
        updateTranslatableText(S.LoopToggle, "🔁 LOOP: ON")
    else
        S.LoopToggle.BackgroundColor3=t.loopOff or Color3.fromRGB(130,130,130)
        updateTranslatableText(S.LoopToggle, "🔁 LOOP: OFF")
    end
end
local function updateExtraLoopButton()
    if not S.ExtraLoopImageButton then return end
    if S.loopState==0 then S.ExtraLoopImageButton.Image="rbxassetid://72571947341676"
    elseif S.loopState==1 then S.ExtraLoopImageButton.Image="rbxassetid://133261841375114"
    elseif S.loopState==2 then S.ExtraLoopImageButton.Image="rbxassetid://70388482182322" end
end

-- ========== APPLY THEME ==========
local function applyTheme(tn)
    local t=S.themes[tn] or S.themes["Default"]; S.currentTheme=tn
    if not S.MainFrame then return end
    S.MainFrame.BackgroundColor3=t.mainBg; S.OutlineFrame.BackgroundColor3=t.mainBg; S.TitleBar.BackgroundColor3=t.titleBg; S.UIStroke.Color=t.outlineColor; S.ContentFrame.BackgroundTransparency=1
    if S.UrlContainer then S.UrlContainer.BackgroundColor3=t.inputBg end
    if S.PlayButton then S.PlayButton.BackgroundColor3=t.playColor end; if S.PauseButton then S.PauseButton.BackgroundColor3=t.pauseColor end
    if S.StopButton then S.StopButton.BackgroundColor3=t.stopColor end; if S.HistoryButton then S.HistoryButton.BackgroundColor3=t.historyColor end
    if S.MuteToggle then S.MuteToggle.BackgroundColor3=S.isGameMuted and t.muteOnColor or t.muteColor end
    if S.LoopToggle then updateLoopToggleDisplay() end
    if S.SearchButton then S.SearchButton.BackgroundColor3=t.searchColor end; if S.InfoButton then S.InfoButton.BackgroundColor3=t.infoColor end
    if S.SettingsButton then S.SettingsButton.BackgroundColor3=t.settingColor end; updateSliderColors()
    if S.TimeSliderBg then S.TimeSliderBg.BackgroundColor3=t.inputBg end
    if S.VolumeTextBox then S.VolumeTextBox.BackgroundColor3=Color3.fromRGB(60,60,70); S.VolumeTextBox.TextColor3=t.textColor end
    if S.StatusLabel then S.StatusLabel.TextColor3=t.textColor end; if S.TitleText then S.TitleText.TextColor3=t.textColor end
    if S.UrlTextBox then S.UrlTextBox.TextColor3=t.textColor end; if S.SecretKeyTextBox then S.SecretKeyTextBox.TextColor3=t.textColor end
    if S.SecretKeyContainer then S.SecretKeyContainer.BackgroundColor3=t.inputBg end
    if S.SettingsScrollFrame then S.SettingsScrollFrame.ScrollBarImageColor3=t.scrollBarColor end
    if S.SearchPanelStroke then S.SearchPanelStroke.Color=t.searchColor end; if S.InfoPanelStroke then S.InfoPanelStroke.Color=t.infoColor end
    if S.SearchTabBtn and S.PlaylistTabBtn then S.SearchTabBtn.BackgroundColor3=S.currentSearchTab=="Search" and t.tabActive or t.tabInactive; S.PlaylistTabBtn.BackgroundColor3=S.currentSearchTab=="Playlist" and t.tabActive or t.tabInactive end
    if S.MiniFrame then S.MiniFrame.BackgroundColor3=t.mainBg; S.MiniOutlineFrame.BackgroundColor3=t.mainBg; S.MiniUIStroke.Color=t.outlineColor end
    if S.VolumeLabel then S.VolumeLabel.TextColor3=t.labelColor end; if S.SpeedLabel then S.SpeedLabel.TextColor3=t.labelColor end
    if S.SpeedDownButton then S.SpeedDownButton.BackgroundColor3=t.speedBtnColor end; if S.SpeedUpButton then S.SpeedUpButton.BackgroundColor3=t.speedBtnColor end
    if S.saveThemeEnabled then saveSettings() end
end

-- ========== FORMAT TIME ==========
local function formatTime(s) if s<0 then s=0 end; return string.format("%d:%02d",math.floor(s/60),math.floor(s%60)) end
S.rainbowColorList={Color3.fromRGB(255,50,50),Color3.fromRGB(255,150,50),Color3.fromRGB(255,255,50),Color3.fromRGB(50,255,50),Color3.fromRGB(50,150,255),Color3.fromRGB(150,50,255),Color3.fromRGB(255,50,255)}

-- ========== OLD-STYLE SMOOTH RAINBOW ANIMATION ==========
local function startRainbowAnimation()
    if S.rainbowAnimation then return end
    S.rainbowAnimation = true
    local ci = 1
    spawn(function()
        while S.rainbowAnimation and S.TimeLabel and S.TimeLabel.Parent do
            if S.currentSongName ~= "" then
                local c = S.rainbowColorList[ci]
                TweenService:Create(S.TimeLabel, TweenInfo.new(0.5), {TextColor3 = c}):Play()
                if S.MiniSongLabel and S.MiniSongLabel.Text ~= "" then
                    TweenService:Create(S.MiniSongLabel, TweenInfo.new(0.5), {TextColor3 = c}):Play()
                end
                ci = ci + 1
                if ci > #S.rainbowColorList then ci = 1 end
            end
            wait(0.5)
        end
        S.rainbowAnimation = nil
    end)
end

local function stopRainbowAnimation()
    S.rainbowAnimation = nil
    wait(0.1)
end

-- ========== SOUND FUNCTIONS ==========
local function updateSpeedDisplay()
    if S.SpeedTextBox then S.SpeedTextBox.Text=string.format("%.2f",S.currentSpeed).."x" end
    if S.SpeedLabel then S.SpeedLabel.Text="Speed: "..string.format("%.2f",S.currentSpeed).."x" end
end

local function cleanAllEffects()
    if S.currentSound then
        pcall(function() for _, v in pairs({S.currentSound:FindFirstChild("EqualizerSoundEffect"), S.currentSound:FindFirstChild("ReverbSoundEffect"), S.currentSound:FindFirstChild("EchoSoundEffect")}) do if v then v:Destroy() end end end)
    end
end

local function applySoundEffect(effectName)
    S.currentSoundEffect=effectName
    local effect=nil
    for _, e in ipairs(S.soundEffectPresets) do if e.name==effectName then effect=e; break end end
    if not effect then return end
    cleanAllEffects()
    if effectName=="Default" then if S.currentSound then S.currentSound.PlaybackSpeed=S.currentSpeed end; updateSpeedDisplay(); return end
    if S.currentSound then
        S.currentSound.PlaybackSpeed=S.currentSpeed*effect.speed
        if effect.bass~=1 or effect.treble~=1 then pcall(function() local eq=Instance.new("EqualizerSoundEffect"); eq.Parent=S.currentSound; eq.LowGain=math.clamp((effect.bass-1)*15,-20,20); eq.MidGain=math.clamp(((effect.bass+effect.treble)/2-1)*8,-12,12); eq.HighGain=math.clamp((effect.treble-1)*15,-20,20) end) end
        if effect.reverb>0.01 then pcall(function() local reverb=Instance.new("ReverbSoundEffect"); reverb.Parent=S.currentSound; reverb.DryLevel=math.clamp(1-effect.reverb,0.2,1); reverb.WetLevel=math.clamp(effect.reverb,0,1); reverb.DecayTime=effect.reverb*5 end) end
        if effect.echo>0.01 then pcall(function() local echo=Instance.new("EchoSoundEffect"); echo.Parent=S.currentSound; echo.DryLevel=math.clamp(1-effect.echo,0.3,1); echo.WetLevel=math.clamp(effect.echo,0,0.8); echo.Delay=effect.echo*0.5; echo.Feedback=effect.echo*0.7 end) end
    end
    updateSpeedDisplay()
end

local function updateSoundEffectList()
    if not S.soundEffectScrollFrame then return end
    for _, c in pairs(S.soundEffectScrollFrame:GetChildren()) do if c.Name=="EffectItem" then c:Destroy() end end
    local th=0
    for _, effect in ipairs(S.soundEffectPresets) do
        local item=Instance.new("Frame"); item.Name="EffectItem"; item.Size=UDim2.new(1,-5,0,35); item.Position=UDim2.new(0,2,0,th)
        item.BackgroundColor3=Color3.fromRGB(45,45,55); item.BorderSizePixel=0; item.Parent=S.soundEffectScrollFrame; Instance.new("UICorner",item).CornerRadius=UDim.new(0,6)
        local nameLabel=Instance.new("TextLabel"); nameLabel.Size=UDim2.new(0,140,1,0); nameLabel.Position=UDim2.new(0,8,0,0)
        nameLabel.BackgroundTransparency=1; nameLabel.Text=effect.name; nameLabel.TextColor3=Color3.fromRGB(255,255,255)
        nameLabel.Font=Enum.Font.GothamBold; nameLabel.TextSize=11; nameLabel.TextXAlignment=Enum.TextXAlignment.Left; nameLabel.Parent=item
        local descText=""
        if effect.name=="Default" then descText="Original"
        elseif effect.name=="Idk" then descText="maybe it's working sometimes"
        elseif effect.bass>1.5 then descText="Heavy bass"
        elseif effect.treble>2 then descText="High pitch"
        elseif effect.speed>1.2 then descText="Sped up"
        elseif effect.speed<0.85 then descText="Slowed"
        elseif effect.reverb>0.5 then descText="Reverb"
        elseif effect.echo>0.5 then descText="Echo"
        else descText="Custom" end
        local descLabel=Instance.new("TextLabel"); descLabel.Size=UDim2.new(0,180,0,18); descLabel.Position=UDim2.new(0,8,0,18)
        descLabel.BackgroundTransparency=1; descLabel.Text=descText; descLabel.TextColor3=Color3.fromRGB(150,150,170)
        descLabel.Font=Enum.Font.Gotham; descLabel.TextSize=9; descLabel.TextXAlignment=Enum.TextXAlignment.Left; descLabel.Parent=item
        local useBtn=Instance.new("TextButton"); useBtn.Size=UDim2.new(0,55,0,22); useBtn.Position=UDim2.new(1,-60,0,6)
        useBtn.BorderSizePixel=0; useBtn.Font=Enum.Font.GothamBold; useBtn.TextSize=10; useBtn.TextColor3=Color3.fromRGB(255,255,255); useBtn.Parent=item; Instance.new("UICorner",useBtn).CornerRadius=UDim.new(0,4)
        if S.currentSoundEffect==effect.name then useBtn.BackgroundColor3=Color3.fromRGB(100,180,100); useBtn.Text="USING" else useBtn.BackgroundColor3=Color3.fromRGB(80,130,200); useBtn.Text="Use" end
        local en=effect.name
        useBtn.MouseButton1Click:Connect(function() applySoundEffect(en); updateSoundEffectList() end)
        th=th+38
    end
    S.soundEffectScrollFrame.CanvasSize=UDim2.new(0,0,0,th+5)
end

local function updateTimeDisplay()
    if not S.currentSound then
        if S.TimeLabel then S.TimeLabel.Text="0:00 / 0:00"; S.TimeLabel.TextColor3=Color3.fromRGB(200,200,200) end
        if S.TimeSlider then S.TimeSlider.Size=UDim2.new(0,0,1,0) end; if S.MiniTimeLabel then S.MiniTimeLabel.Text="0:00 / 0:00" end
        if S.MiniTimeSlider then S.MiniTimeSlider.Size=UDim2.new(0,0,1,0) end; if S.ExtraTimeLabel then S.ExtraTimeLabel.Text="0:00 / 0:00" end
        if S.ExtraTimeSlider then S.ExtraTimeSlider.Size=UDim2.new(0,0,1,0) end
        if S.MiniPauseImageButton then S.MiniPauseImageButton.Image="rbxassetid://80704722265943" end
        if S.ExtraPauseImageButton then S.ExtraPauseImageButton.Image="rbxassetid://80704722265943" end
        return
    end
    local tp=S.currentSound.TimePosition; local tl=S.currentSound.TimeLength
    if tp~=tp then tp=0 end; if tl~=tl or tl<=0 then tl=1 end
    local timeText=formatTime(tp).." / "..formatTime(tl)
    if S.TimeLabel then S.TimeLabel.Text=S.currentSongName~="" and (timeText.."   "..S.currentSongName) or timeText end
    local frac=math.clamp(tp/tl,0,1)
    if S.TimeSlider then S.TimeSlider.Size=UDim2.new(frac,0,1,0) end; if S.MiniTimeLabel then S.MiniTimeLabel.Text=timeText end
    if S.MiniTimeSlider then S.MiniTimeSlider.Size=UDim2.new(frac,0,1,0) end
    if S.MiniSongLabel and S.currentSongName~="" then S.MiniSongLabel.Text=S.currentSongName end
    
    local songEnded=(not S.isPlaying and not S.isPaused and not S.isLooping and not S.playlistLoopEnabled)
    if S.MiniPauseImageButton then 
        if songEnded then S.MiniPauseImageButton.Image="rbxassetid://110560238983134"
        else S.MiniPauseImageButton.Image=S.isPaused and "rbxassetid://110560238983134" or "rbxassetid://80704722265943" end
    end
    if S.ExtraTimeLabel then S.ExtraTimeLabel.Text=timeText end; if S.ExtraTimeSlider then S.ExtraTimeSlider.Size=UDim2.new(frac,0,1,0) end
    if S.ExtraPauseImageButton then 
        if songEnded then S.ExtraPauseImageButton.Image="rbxassetid://110560238983134"
        else S.ExtraPauseImageButton.Image=S.isPaused and "rbxassetid://110560238983134" or "rbxassetid://80704722265943" end
    end
    if songEnded and S.currentSound then updateTranslatableText(S.PauseButton, "▶ RESUME") end
end

-- ========== SIMPLE AUTO SCROLL ==========
local function startAutoScroll(label)
    if not label then return end; local oldContainer=label:FindFirstChild("ScrollContainer"); if oldContainer then oldContainer:Destroy() end
    local songName=label.Text; if songName=="" then return end
    label.Text=""; label.TextTruncate=Enum.TextTruncate.None; label.ClipsDescendants=true
    local scrollContainer=Instance.new("Frame"); scrollContainer.Name="ScrollContainer"; scrollContainer.Size=UDim2.new(1,0,1,0); scrollContainer.Position=UDim2.new(0,0,0,0)
    scrollContainer.BackgroundTransparency=1; scrollContainer.ClipsDescendants=true; scrollContainer.Parent=label
    local innerText=Instance.new("TextLabel"); innerText.Name="InnerText"; innerText.BackgroundTransparency=1
    innerText.TextColor3=Color3.fromRGB(255,255,255); innerText.Font=Enum.Font.GothamBold; innerText.TextSize=11
    innerText.TextXAlignment=Enum.TextXAlignment.Left; innerText.TextYAlignment=Enum.TextYAlignment.Center; innerText.Parent=scrollContainer
    innerText.Text=songName; innerText.Size=UDim2.new(0,innerText.TextBounds.X+10,1,0); wait(0.1); innerText.Size=UDim2.new(0,innerText.TextBounds.X+10,1,0)
    spawn(function()
        while scrollContainer and scrollContainer.Parent do
            local textWidth=innerText.TextBounds.X; local containerWidth=scrollContainer.AbsoluteSize.X
            if textWidth>containerWidth and containerWidth>10 then
                innerText.Size=UDim2.new(0,textWidth+40,1,0); innerText.Position=UDim2.new(0,containerWidth,0,0); wait(0.8)
                if not scrollContainer.Parent then break end
                local endX=-textWidth-20; local distance=containerWidth-endX; local duration=distance/40
                local tween=TweenService:Create(innerText,TweenInfo.new(duration,Enum.EasingStyle.Linear,Enum.EasingDirection.Out),{Position=UDim2.new(0,endX,0,0)})
                tween:Play(); wait(duration+0.3)
            else innerText.Size=UDim2.new(1,-10,1,0); innerText.Position=UDim2.new(0,5,0,0); innerText.TextXAlignment=Enum.TextXAlignment.Center; wait(2) end
        end
    end)
end

-- ========== CORE FUNCTIONS ==========
local function loadCache() local s,r=pcall(function() if readfile and isfile and isfile(CACHE_FILE) then return HttpService:JSONDecode(readfile(CACHE_FILE)) end end); return s and r or {} end
local function saveCache() pcall(function() if writefile then writefile(CACHE_FILE,HttpService:JSONEncode(S.musicCache)) end end) end
local function loadHistory() local s,r=pcall(function() if readfile and isfile and isfile(HISTORY_FILE) then return HttpService:JSONDecode(readfile(HISTORY_FILE)) end end); return s and r or {} end
local function saveHistory() pcall(function() if writefile then writefile(HISTORY_FILE,HttpService:JSONEncode(S.downloadHistory)) end end) end
local function addToHistory(url,fn)
    for i,e in ipairs(S.downloadHistory) do if e.url==url then table.remove(S.downloadHistory,i); break end end
    table.insert(S.downloadHistory,1,{url=url,fileName=fn,timestamp=os.time(),date=os.date("%Y-%m-%d %H:%M:%S")})
    if #S.downloadHistory>50 then for i=51,#S.downloadHistory do S.downloadHistory[i]=nil end end; saveHistory()
end
local function removeFromHistory(idx) if S.downloadHistory[idx] then table.remove(S.downloadHistory,idx); saveHistory(); return true end; return false end

local function stopMusic() 
    if S.playlistCheckConnection then pcall(function() S.playlistCheckConnection:Disconnect() end); S.playlistCheckConnection=nil end
    if S.currentSound then pcall(function() S.currentSound:Stop(); S.currentSound:Destroy() end); S.currentSound=nil end
    S.isPlaying=false; S.isPaused=false; S.pausedTimePosition=0; S.currentSongName=""; S.currentPlaylistIndex=0
    stopRainbowAnimation()
    updateTranslatableText(S.PauseButton, "⏸ PAUSE")
    updateTranslatableText(S.PlayButton, "▶ PLAY")
    if S.playingSongLabel then S.playingSongLabel.Text='Now Playing: <font color="#888888">Nothing</font>' end
    updateTimeDisplay() 
end

local function updateVolume(v)
    S.currentVolume=math.clamp(v,0,100)
    if S.VolumeTextBox then S.VolumeTextBox.Text=string.format("%.2f",S.currentVolume) end
    if S.VolumeLabel then S.VolumeLabel.Text="Volume: "..string.format("%.2f",S.currentVolume) end
    if S.currentSound then S.currentSound.Volume=S.currentVolume end
end
local function updateVolumeDisplayOnly()
    if S.VolumeTextBox then S.VolumeTextBox.Text=string.format("%.2f",S.currentVolume) end
    if S.VolumeLabel then S.VolumeLabel.Text="Volume: "..string.format("%.2f",S.currentVolume) end
    if S.currentSound then S.currentSound.Volume=S.currentVolume end
end
local function updateSpeed(s) 
    S.currentSpeed=math.clamp(s,0,100); updateSpeedDisplay()
    if S.currentSound then S.currentSound.PlaybackSpeed=S.currentSpeed end
end

local function togglePause()
    if not S.currentSound then return end
    if S.isPaused then 
        S.currentSound.TimePosition=S.pausedTimePosition; S.currentSound:Resume(); S.isPaused=false; S.isPlaying=true
        updateTranslatableText(S.PauseButton, "⏸ PAUSE")
        updateTranslatableText(S.PlayButton, "▶ PLAY")
    elseif S.isPlaying then
        S.pausedTimePosition=S.currentSound.TimePosition; S.currentSound:Pause(); S.isPaused=true; S.isPlaying=false
        updateTranslatableText(S.PauseButton, "▶ RESUME")
        updateTranslatableText(S.PlayButton, "▶ PLAY")
    else
        S.currentSound.TimePosition=0; S.currentSound:Play(); S.isPlaying=true; S.isPaused=false
        updateTranslatableText(S.PauseButton, "⏸ PAUSE")
        updateTranslatableText(S.PlayButton, "▶ PLAY")
    end
    updateTimeDisplay()
end

local function setupPlaylistLoop()
    if not S.playlistLoopEnabled then if S.playlistCheckConnection then pcall(function() S.playlistCheckConnection:Disconnect() end); S.playlistCheckConnection=nil end end
end


-- ========== COMPLETED PLAY STATS ==========
local function loadMusicStats()
    local ok, data = pcall(function()
        if readfile and isfile and isfile(STATS_FILE) then
            return HttpService:JSONDecode(readfile(STATS_FILE))
        end
    end)
    if ok and type(data)=="table" then
        S.musicStats=data
    else
        S.musicStats={}; S.dataRefreshInterval=15
    end
end

local function saveMusicStats()
    pcall(function()
        if writefile then
            writefile(STATS_FILE, HttpService:JSONEncode(S.musicStats or {}))
        end
    end)
end

local function recordCompletedPlay(url, fileName)
    local key=tostring(url or fileName or "Unknown")
    local old=S.musicStats[key]
    if type(old)~="table" then
        old={name=cleanSongName(fileName), url=url or "", count=0}
        S.musicStats[key]=old
    end
    old.name=cleanSongName(fileName) or old.name or "Unknown"
    old.url=url or old.url or ""
    old.count=(tonumber(old.count) or 0)+1
    old.lastPlayed=os.time()
    saveMusicStats()
end

local function getTopMusicStats(limit)
    local list={}
    for _,entry in pairs(S.musicStats or {}) do
        if type(entry)=="table" and (tonumber(entry.count) or 0)>0 then
            table.insert(list, entry)
        end
    end
    table.sort(list,function(a,b)
        return (tonumber(a.count) or 0)>(tonumber(b.count) or 0)
    end)
    local result={}
    for i=1,math.min(limit or 3,#list) do
        result[i]=list[i]
    end
    return result
end

local function updateDataPanel()
    if not S.InfoDataFrame then return end

    for _,child in pairs(S.InfoDataFrame:GetChildren()) do
        if child.Name=="DataSongItem" then child:Destroy() end
    end

    local top=getTopMusicStats(3)
    if #top==0 then
        if S.DataEmptyLabel then
            S.DataEmptyLabel.Visible=true
            S.DataEmptyLabel.Text="No completed songs yet.\nA play is counted only when the song reaches Ended."
        end
    else
        if S.DataEmptyLabel then S.DataEmptyLabel.Visible=false end
        for i,entry in ipairs(top) do
            local item=Instance.new("Frame")
            item.Name="DataSongItem"
            item.Size=UDim2.new(1,-20,0,58)
            item.Position=UDim2.new(0,10,0,10+(i-1)*64)
            item.BackgroundColor3=Color3.fromRGB(50,55,62)
            item.BorderSizePixel=0
            item.Parent=S.InfoDataFrame
            Instance.new("UICorner",item).CornerRadius=UDim.new(0,7)

            local rank=Instance.new("TextLabel")
            rank.Size=UDim2.new(0,32,1,0)
            rank.Position=UDim2.new(0,5,0,0)
            rank.BackgroundTransparency=1
            rank.Text="#"..i
            rank.TextColor3=Color3.fromRGB(255,190,80)
            rank.Font=Enum.Font.GothamBold
            rank.TextSize=16
            rank.Parent=item

            local name=Instance.new("TextLabel")
            name.Size=UDim2.new(1,-125,0,25)
            name.Position=UDim2.new(0,42,0,6)
            name.BackgroundTransparency=1
            name.Text=entry.name or "Unknown"
            name.TextColor3=Color3.fromRGB(255,255,255)
            name.TextXAlignment=Enum.TextXAlignment.Left
            name.Font=Enum.Font.GothamBold
            name.TextSize=12
            name.TextTruncate=Enum.TextTruncate.AtEnd
            name.Parent=item

            local plays=Instance.new("TextLabel")
            plays.Size=UDim2.new(0,75,0,22)
            plays.Position=UDim2.new(1,-82,0,18)
            plays.BackgroundTransparency=1
            plays.Text=tostring(entry.count or 0).." plays"
            plays.TextColor3=Color3.fromRGB(120,220,255)
            plays.Font=Enum.Font.GothamBold
            plays.TextSize=11
            plays.TextXAlignment=Enum.TextXAlignment.Right
            plays.Parent=item
        end
    end

    if S.DataLastUpdatedLabel then
        S.DataLastUpdatedLabel.Text="Updated: "..os.date("%H:%M:%S")
    end
end

local function setDataRefreshInterval(seconds)
    S.dataRefreshInterval=math.clamp(math.floor(seconds+0.5),5,60)
    if S.DataIntervalLabel then
        S.DataIntervalLabel.Text="Auto refresh: "..S.dataRefreshInterval.."s"
    end
    if S.DataIntervalFill then
        local frac=(S.dataRefreshInterval-5)/55
        S.DataIntervalFill.Size=UDim2.new(frac,0,1,0)
    end
end

local function playMusicFromUrl(url, fn, playlistIdx)
    local newIndex=playlistIdx or 0
    if S.currentSound then pcall(function() S.currentSound:Stop(); S.currentSound:Destroy() end); S.currentSound=nil end
    if S.playlistCheckConnection then pcall(function() S.playlistCheckConnection:Disconnect() end); S.playlistCheckConnection=nil end
    S.isPlaying=false; S.isPaused=false; S.pausedTimePosition=0
    S.currentSongName=cleanSongName(fn); S.currentPlaylistIndex=newIndex
    
    updateTranslatableText(S.StatusLabel, "⏬ Loading...")
    if S.StatusLabel then S.StatusLabel.TextColor3=Color3.fromRGB(255,200,100) end
    if S.MiniSongLabel then S.MiniSongLabel.Text=S.currentSongName end
    updateTranslatableText(S.PauseButton, "⏸ PAUSE")
    updateTranslatableText(S.PlayButton, "▶ PLAY")
    if S.playingSongLabel and S.playingTabOpen then S.playingSongLabel.Text='Now Playing: <font color="#ff9944">'..S.currentSongName..'</font>' end
    
    if S.TimeLabel and S.currentSongName~="" then stopRainbowAnimation(); startRainbowAnimation() end
    
    if S.ExtraSongLabel then pcall(function() local oldContainer=S.ExtraSongLabel:FindFirstChild("ScrollContainer"); if oldContainer then oldContainer:Destroy() end; S.ExtraSongLabel.Text=S.currentSongName; startAutoScroll(S.ExtraSongLabel) end) end
    if S.ExtraMiniImage and S.currentPlaylistIndex>0 and S.playlistSongs[S.currentPlaylistIndex] then local img=S.playlistSongs[S.currentPlaylistIndex].imageAsset; S.ExtraMiniImage.Image=(img and img~="") and img or "" elseif S.ExtraMiniImage then S.ExtraMiniImage.Image="" end
    
    local function createAndPlaySound(soundId)
        local sound=Instance.new("Sound"); S.currentSound=sound; sound.Name="MusicPlayerSound"; sound.SoundId=soundId
        sound.Volume=S.currentVolume; sound.Looped=S.isLooping; sound.PlaybackSpeed=S.currentSpeed
        sound.Parent=workspace

        sound.Ended:Connect(function()
            if S.currentSound~=sound then return end
            recordCompletedPlay(url,fn)
            if S.playlistLoopEnabled and #S.playlistSongs>0 then
                local ni=S.currentPlaylistIndex+1; if ni>#S.playlistSongs then ni=1 end
                local song=S.playlistSongs[ni]
                if song then pcall(function() playMusicFromUrl(song.url,song.fileName,ni) end) end
            elseif S.currentSound and not S.currentSound.Looped then
                S.isPlaying=false; S.isPaused=false
                updateTranslatableText(S.PauseButton, "▶ RESUME")
                if S.MiniPauseImageButton then S.MiniPauseImageButton.Image="rbxassetid://110560238983134" end
                if S.ExtraPauseImageButton then S.ExtraPauseImageButton.Image="rbxassetid://110560238983134" end
            end
        end)
        
        sound:Play(); S.isPlaying=true; S.isPaused=false; S.pausedTimePosition=0
        if S.currentSoundEffect~="Default" then applySoundEffect(S.currentSoundEffect) end
        if S.StatusLabel then S.StatusLabel.Text="🎵 "..S.currentSongName; S.StatusLabel.TextColor3=Color3.fromRGB(100,255,100) end
        addToHistory(url,fn); updateTimeDisplay(); return true
    end
    
    if S.musicCache[url] and S.musicCache[url].fileName then
        local cf=S.musicCache[url].fileName
        if isfile and isfile(cf) then return createAndPlaySound(getcustomasset(cf)) else S.musicCache[url]=nil; saveCache() end
    end
    
    local success,result=pcall(function() local d=game:HttpGet(url); local ts=os.time(); local cfn=CACHE_FOLDER.."/cache_"..ts..".mp3"; writefile(cfn,d); S.musicCache[url]={fileName=cfn,timestamp=ts}; saveCache(); return getcustomasset(cfn) end)
    if success and result then return createAndPlaySound(result)
    else showNotification("Error","❌ Failed to load music!",3); S.currentSongName=""; stopMusic(); return false end
end

local function applyLoopState()
    if S.mainLoopOn then S.isLooping=true; S.playlistLoopEnabled=false; if S.currentSound then S.currentSound.Looped=true end
    else S.isLooping=false; S.playlistLoopEnabled=false; if S.currentSound then S.currentSound.Looped=false end end
    setupPlaylistLoop(); updateLoopToggleDisplay(); updateExtraLoopButton()
end
local function applyExtraLoopState()
    if S.loopState==0 then S.isLooping=false; S.playlistLoopEnabled=false; if S.currentSound then S.currentSound.Looped=false end
    elseif S.loopState==1 then S.isLooping=true; S.playlistLoopEnabled=false; if S.currentSound then S.currentSound.Looped=true end
    elseif S.loopState==2 then S.isLooping=false; S.playlistLoopEnabled=true; if S.currentSound then S.currentSound.Looped=false end end
    setupPlaylistLoop(); updateLoopToggleDisplay(); updateExtraLoopButton()
end

-- ========== PLAYLIST ==========
function loadPlaylist()
    S.playlistSongs={}
    local s,data=pcall(function() return game:HttpGet("https://raw.githubusercontent.com/Bro-broa3/PrimeMusic/refs/heads/main/Playlist") end)
    if s and data then
        local index=1
        for line in string.gmatch(data,"[^\r\n]+") do
            line=string.gsub(line,"^%s+",""); line=string.gsub(line,"%s+$","")
            if line~="" then
                local commaPos=string.find(line," , "); local url,imageUrl="",""
                if commaPos then url=string.sub(line,1,commaPos-1); imageUrl=string.sub(line,commaPos+3)
                else commaPos=string.find(line,","); if commaPos then url=string.sub(line,1,commaPos-1); imageUrl=string.sub(line,commaPos+1) else url=line end end
                url=string.gsub(url,"^%s+",""); url=string.gsub(url,"%s+$",""); imageUrl=string.gsub(imageUrl,"^%s+",""); imageUrl=string.gsub(imageUrl,"%s+$","")
                if url~="" and string.find(url,".mp3") then
                    local fn="audio.mp3"; local pts=string.split(url,"/"); if #pts>0 and string.find(pts[#pts],".mp3") then fn=string.gsub(string.gsub(pts[#pts],"%%20"," "),"%%25","%%") end
                    local imageAsset=""; if imageUrl~="" then imageAsset=downloadImage(imageUrl,index) end
                    table.insert(S.playlistSongs,{url=url,fileName=fn,imageUrl=imageUrl,imageAsset=imageAsset,isDefault=true}); index=index+1
                end
            end
        end
    end
    for _,song in ipairs(S.userPlaylist) do table.insert(S.playlistSongs,song) end
end

function checkSecretKey(input)
    local s,fetchedKey=pcall(function() return game:HttpGet("https://raw.githubusercontent.com/Bro-broa3/PrimeMusic/refs/heads/main/Key") end)
    if s and fetchedKey then fetchedKey=string.gsub(fetchedKey,"^%s+",""); fetchedKey=string.gsub(fetchedKey,"%s+$",""); S.secretKey=fetchedKey end
    if input==S.secretKey then S.isKeyCorrect=true; S.SecretKeyTextBox.Text=""; updateExtraMiniToggle(); if S.rememberKeyEnabled then saveKeyState() end; loadPlaylist(); showNotification("GitHub MP3 Player","✅ Key correct!",3); if S.isSearchOpen and S.currentSearchTab=="Playlist" then updatePlaylistDisplay() end; return true
    else S.SecretKeyTextBox.Text=""; showNotification("GitHub MP3 Player","❌ Wrong key!",3); return false end
end

function updatePlaylistDisplay()
    if not S.PlaylistScrollFrame then return end
    for _,c in pairs(S.PlaylistScrollFrame:GetChildren()) do if c.Name=="PlaylistItem" or c.Name=="AddMusicButton" or c.Name=="AddMusicPanel" then c:Destroy() end end
    if not S.isKeyCorrect then if S.PlaylistNoResultsLabel then S.PlaylistNoResultsLabel.Visible=true; S.PlaylistNoResultsLabel.Text="Enter secret key!" end; S.PlaylistScrollFrame.CanvasSize=UDim2.new(0,0,0,0); return end
    if #S.playlistSongs==0 then if S.PlaylistNoResultsLabel then S.PlaylistNoResultsLabel.Visible=true; S.PlaylistNoResultsLabel.Text="Loading..." end; S.PlaylistScrollFrame.CanvasSize=UDim2.new(0,0,0,0); return end
    S.PlaylistNoResultsLabel.Visible=false; local th=0
    for idx,song in ipairs(S.playlistSongs) do
        local itemHeight=55; local hasImage=song.imageAsset~=""
        local item=Instance.new("Frame"); item.Name="PlaylistItem"; item.Size=UDim2.new(1,-10,0,itemHeight); item.Position=UDim2.new(0,5,0,th)
        item.BackgroundColor3=Color3.fromRGB(50,50,60); item.BorderSizePixel=0; item.Parent=S.PlaylistScrollFrame; Instance.new("UICorner",item).CornerRadius=UDim.new(0,4)
        if hasImage then local img=Instance.new("ImageLabel"); img.Size=UDim2.new(0,42,0,42); img.Position=UDim2.new(0,5,0,6); img.BackgroundTransparency=1; img.Image=song.imageAsset; img.ScaleType=Enum.ScaleType.Crop; img.Parent=item; Instance.new("UICorner",img).CornerRadius=UDim.new(0,4) end
        local nameStartX=hasImage and 52 or 5
        local scrollFrame=Instance.new("Frame"); scrollFrame.Size=UDim2.new(1,-nameStartX-120,0,35); scrollFrame.Position=UDim2.new(0,nameStartX,0,5); scrollFrame.BackgroundTransparency=1; scrollFrame.ClipsDescendants=true; scrollFrame.Parent=item
        local lb=Instance.new("TextLabel"); lb.Size=UDim2.new(0,0,1,0); lb.Position=UDim2.new(0,0,0,0); lb.BackgroundTransparency=1; lb.Text=cleanSongName(song.fileName); lb.TextColor3=Color3.fromRGB(255,255,255); lb.Font=Enum.Font.GothamBold; lb.TextSize=12; lb.TextTruncate=Enum.TextTruncate.None; lb.TextXAlignment=Enum.TextXAlignment.Left; lb.Parent=scrollFrame
        local pb=Instance.new("TextButton"); pb.Size=UDim2.new(0,50,0,25); pb.Position=UDim2.new(1,-110,0,5); pb.BackgroundColor3=Color3.fromRGB(70,150,70); pb.BorderSizePixel=0; pb.Text="PLAY"; pb.TextColor3=Color3.fromRGB(255,255,255); pb.Font=Enum.Font.GothamBold; pb.TextSize=10; pb.Parent=item; Instance.new("UICorner",pb).CornerRadius=UDim.new(0,4)
        local delBtn=Instance.new("TextButton"); delBtn.Size=UDim2.new(0,50,0,25); delBtn.Position=UDim2.new(1,-55,0,5); delBtn.BackgroundColor3=Color3.fromRGB(200,70,70); delBtn.BorderSizePixel=0; delBtn.Text="DEL"; delBtn.TextColor3=Color3.fromRGB(255,255,255); delBtn.Font=Enum.Font.GothamBold; delBtn.TextSize=10; delBtn.Parent=item; Instance.new("UICorner",delBtn).CornerRadius=UDim.new(0,4)
        spawn(function() while scrollFrame and scrollFrame.Parent do local textWidth=lb.TextBounds.X; local containerWidth=scrollFrame.AbsoluteSize.X; if textWidth>containerWidth and containerWidth>10 then lb.Size=UDim2.new(0,textWidth+40,1,0); lb.Position=UDim2.new(0,0,0,0); wait(1); local tween=TweenService:Create(lb,TweenInfo.new(textWidth/40,Enum.EasingStyle.Linear),{Position=UDim2.new(0,-textWidth+containerWidth-20,0,0)}); tween:Play(); wait(textWidth/40+0.3) else lb.Size=UDim2.new(1,0,1,0); lb.Position=UDim2.new(0,0,0,0); wait(2) end; if not scrollFrame.Parent then break end end end)
        local si=idx; local su,sf=song.url,song.fileName
        pb.MouseButton1Click:Connect(function() if S.isSearchOpen then toggleSearchPanel() end; playMusicFromUrl(su,sf,si) end)
        if not song.isDefault then delBtn.MouseButton1Click:Connect(function() for i,us in ipairs(S.userPlaylist) do if us.url==su then table.remove(S.userPlaylist,i); break end end; saveUserPlaylist(); loadPlaylist(); updatePlaylistDisplay(); showNotification("Playlist","✅ Removed!",2) end)
        else delBtn.BackgroundColor3=Color3.fromRGB(100,100,100); delBtn.Text="🔒"; delBtn.MouseButton1Click:Connect(function() showNotification("Playlist","❌ Cannot delete!",2) end) end
        th=th+itemHeight+4
    end
    local addBtn=Instance.new("TextButton"); addBtn.Name="AddMusicButton"; addBtn.Size=UDim2.new(1,-10,0,35); addBtn.Position=UDim2.new(0,5,0,th+10)
    addBtn.BackgroundColor3=Color3.fromRGB(100,180,100); addBtn.BorderSizePixel=0; addBtn.Text="➕ Add your music to playlist"; addBtn.TextColor3=Color3.fromRGB(255,255,255); addBtn.Font=Enum.Font.GothamBold; addBtn.TextSize=12; addBtn.Parent=S.PlaylistScrollFrame; Instance.new("UICorner",addBtn).CornerRadius=UDim.new(0,6)
    local btnTh=th+10+35+10
    
    local addPanel=Instance.new("Frame"); addPanel.Name="AddMusicPanel"; addPanel.Size=UDim2.new(1,-10,0,140); addPanel.Position=UDim2.new(0,5,0,btnTh)
    addPanel.BackgroundColor3=Color3.fromRGB(45,45,55); addPanel.BorderSizePixel=0; addPanel.Visible=false; addPanel.Parent=S.PlaylistScrollFrame; Instance.new("UICorner",addPanel).CornerRadius=UDim.new(0,6)
    local mp3Label=Instance.new("TextLabel"); mp3Label.Size=UDim2.new(1,-10,0,18); mp3Label.Position=UDim2.new(0,5,0,5); mp3Label.BackgroundTransparency=1; mp3Label.Text="GitHub MP3 URL:"; mp3Label.TextColor3=Color3.fromRGB(255,255,255); mp3Label.TextXAlignment=Enum.TextXAlignment.Left; mp3Label.Font=Enum.Font.Gotham; mp3Label.TextSize=11; mp3Label.Parent=addPanel
    local mp3Container=Instance.new("Frame"); mp3Container.Size=UDim2.new(1,-10,0,28); mp3Container.Position=UDim2.new(0,5,0,26); mp3Container.BackgroundColor3=Color3.fromRGB(60,60,70); mp3Container.BorderSizePixel=0; mp3Container.ClipsDescendants=true; mp3Container.Parent=addPanel; Instance.new("UICorner",mp3Container).CornerRadius=UDim.new(0,4)
    local mp3ScrollFrame=Instance.new("ScrollingFrame"); mp3ScrollFrame.Size=UDim2.new(1,0,1,0); mp3ScrollFrame.BackgroundTransparency=1; mp3ScrollFrame.BorderSizePixel=0; mp3ScrollFrame.ScrollBarThickness=5; mp3ScrollFrame.CanvasSize=UDim2.new(0,0,0,0); mp3ScrollFrame.ElasticBehavior=Enum.ElasticBehavior.Never; mp3ScrollFrame.ScrollingDirection=Enum.ScrollingDirection.X; mp3ScrollFrame.Parent=mp3Container
    local mp3TextBox=Instance.new("TextBox"); mp3TextBox.Size=UDim2.new(1,0,1,0); mp3TextBox.Position=UDim2.new(0,5,0,0); mp3TextBox.BackgroundTransparency=1; mp3TextBox.Text=""; mp3TextBox.PlaceholderText="https://raw.githubusercontent.com/.../audio.mp3"; mp3TextBox.PlaceholderColor3=Color3.fromRGB(150,150,160); mp3TextBox.TextColor3=Color3.fromRGB(255,255,255); mp3TextBox.Font=Enum.Font.Gotham; mp3TextBox.TextSize=10; mp3TextBox.ClearTextOnFocus=false; mp3TextBox.TextXAlignment=Enum.TextXAlignment.Left; mp3TextBox.TextWrapped=false; mp3TextBox.Parent=mp3ScrollFrame
    local imgLabel=Instance.new("TextLabel"); imgLabel.Size=UDim2.new(1,-10,0,18); imgLabel.Position=UDim2.new(0,5,0,60); imgLabel.BackgroundTransparency=1; imgLabel.Text="Raw Image Link (optional):"; imgLabel.TextColor3=Color3.fromRGB(255,255,255); imgLabel.TextXAlignment=Enum.TextXAlignment.Left; imgLabel.Font=Enum.Font.Gotham; imgLabel.TextSize=11; imgLabel.Parent=addPanel
    local imgContainer=Instance.new("Frame"); imgContainer.Size=UDim2.new(1,-10,0,28); imgContainer.Position=UDim2.new(0,5,0,81); imgContainer.BackgroundColor3=Color3.fromRGB(60,60,70); imgContainer.BorderSizePixel=0; imgContainer.ClipsDescendants=true; imgContainer.Parent=addPanel; Instance.new("UICorner",imgContainer).CornerRadius=UDim.new(0,4)
    local imgScrollFrame=Instance.new("ScrollingFrame"); imgScrollFrame.Size=UDim2.new(1,0,1,0); imgScrollFrame.BackgroundTransparency=1; imgScrollFrame.BorderSizePixel=0; imgScrollFrame.ScrollBarThickness=5; imgScrollFrame.CanvasSize=UDim2.new(0,0,0,0); imgScrollFrame.ElasticBehavior=Enum.ElasticBehavior.Never; imgScrollFrame.ScrollingDirection=Enum.ScrollingDirection.X; imgScrollFrame.Parent=imgContainer
    local imgTextBox=Instance.new("TextBox"); imgTextBox.Size=UDim2.new(1,0,1,0); imgTextBox.Position=UDim2.new(0,5,0,0); imgTextBox.BackgroundTransparency=1; imgTextBox.Text=""; imgTextBox.PlaceholderText="https://raw.githubusercontent.com/.../image.png"; imgTextBox.PlaceholderColor3=Color3.fromRGB(150,150,160); imgTextBox.TextColor3=Color3.fromRGB(255,255,255); imgTextBox.Font=Enum.Font.Gotham; imgTextBox.TextSize=10; imgTextBox.ClearTextOnFocus=false; imgTextBox.TextXAlignment=Enum.TextXAlignment.Left; imgTextBox.TextWrapped=false; imgTextBox.Parent=imgScrollFrame
    
    local addConfirmBtn=Instance.new("TextButton"); addConfirmBtn.Size=UDim2.new(1,-10,0,25); addConfirmBtn.Position=UDim2.new(0,5,0,115); addConfirmBtn.BackgroundColor3=Color3.fromRGB(70,150,70); addConfirmBtn.BorderSizePixel=0; addConfirmBtn.Text="Add"; addConfirmBtn.TextColor3=Color3.fromRGB(255,255,255); addConfirmBtn.Font=Enum.Font.GothamBold; addConfirmBtn.TextSize=12; addConfirmBtn.Parent=addPanel; Instance.new("UICorner",addConfirmBtn).CornerRadius=UDim.new(0,4)
    
    addBtn.MouseButton1Click:Connect(function() addPanel.Visible=not addPanel.Visible; if addPanel.Visible then S.PlaylistScrollFrame.CanvasSize=UDim2.new(0,0,0,btnTh+145) else S.PlaylistScrollFrame.CanvasSize=UDim2.new(0,0,0,btnTh) end end)
    addConfirmBtn.MouseButton1Click:Connect(function()
        local mp3Url=mp3TextBox.Text; local imgUrl=imgTextBox.Text
        if mp3Url=="" then showNotification("Error","❌ Please enter an MP3 URL!",2); return end
        if not string.find(string.lower(mp3Url),".mp3") then showNotification("Error","❌ URL must end with .mp3!",2); return end
        local fn="audio.mp3"; local pts=string.split(mp3Url,"/"); if #pts>0 and string.find(pts[#pts],".mp3") then fn=string.gsub(string.gsub(pts[#pts],"%%20"," "),"%%25","%%") end
        local imageAsset=""; if imgUrl~="" then imageAsset=downloadImage(imgUrl,#S.userPlaylist+1) end
        table.insert(S.userPlaylist,{url=mp3Url,fileName=fn,imageUrl=imgUrl,imageAsset=imageAsset,isDefault=false}); saveUserPlaylist(); loadPlaylist(); updatePlaylistDisplay(); mp3TextBox.Text=""; imgTextBox.Text=""; showNotification("Playlist","✅ Added!",2)
    end)
    S.PlaylistScrollFrame.CanvasSize=UDim2.new(0,0,0,btnTh+10)
end

-- ========== TOGGLE FUNCTIONS ==========
local function updateSaveThemeToggle() if not S.SaveThemeToggle then return end; S.SaveThemeToggle.BackgroundColor3=S.saveThemeEnabled and Color3.fromRGB(80,180,80) or Color3.fromRGB(180,80,80); S.SaveThemeToggle.Text=S.saveThemeEnabled and "ON" or "OFF" end
local function updateRememberKeyToggle() if not S.RememberKeyToggle then return end; S.RememberKeyToggle.BackgroundColor3=S.rememberKeyEnabled and Color3.fromRGB(80,180,80) or Color3.fromRGB(180,80,80); S.RememberKeyToggle.Text=S.rememberKeyEnabled and "ON" or "OFF" end
local function updateMiniPlayToggle() if not S.MiniPlayToggle then return end; S.MiniPlayToggle.BackgroundColor3=S.miniPlayMode and Color3.fromRGB(80,180,80) or Color3.fromRGB(180,80,80); S.MiniPlayToggle.Text=S.miniPlayMode and "ON" or "OFF" end
local function updateExtraMiniToggle() if not S.ExtraMiniToggle then return end; if not S.isKeyCorrect then S.ExtraMiniToggle.BackgroundColor3=Color3.fromRGB(180,80,80); S.ExtraMiniToggle.Text="LOCKED"; return end; S.ExtraMiniToggle.BackgroundColor3=S.extraMiniPlayMode and Color3.fromRGB(80,180,80) or Color3.fromRGB(180,80,80); S.ExtraMiniToggle.Text=S.extraMiniPlayMode and "ON" or "OFF" end
local function updateKeybindToggle() if not S.KeybindToggle then return end; S.KeybindToggle.BackgroundColor3=S.keybindEnabled and Color3.fromRGB(80,180,80) or Color3.fromRGB(180,80,80); S.KeybindToggle.Text=S.keybindEnabled and "ON" or "OFF" end
local function updateAutoTranslateToggle() if not S.AutoTranslateToggle then return end; S.AutoTranslateToggle.BackgroundColor3=S.autoTranslateEnabled and Color3.fromRGB(80,180,80) or Color3.fromRGB(180,80,80); S.AutoTranslateToggle.Text=S.autoTranslateEnabled and "ON" or "OFF" end

local function toggleAutoTranslate()
    S.autoTranslateEnabled = not S.autoTranslateEnabled
    applyTranslations()
    saveSettings()
    updateAutoTranslateToggle()
end

-- ========== HIDE/SHOW SYSTEM ==========
local function hideAllGuis()
    S.hiddenGuis={}
    if S.ScreenGui and S.ScreenGui.Enabled then S.ScreenGui.Enabled=false; table.insert(S.hiddenGuis,S.ScreenGui) end
    if S.MiniScreenGui and S.MiniScreenGui.Enabled then S.MiniScreenGui.Enabled=false; table.insert(S.hiddenGuis,S.MiniScreenGui) end
    if S.ExtraMiniScreenGui and S.ExtraMiniScreenGui.Enabled then S.ExtraMiniScreenGui.Enabled=false; table.insert(S.hiddenGuis,S.ExtraMiniScreenGui) end
    if S.hideButton then S.hideButton.Visible=false end
    if S.showButton then S.showButton.Visible=true end
end

local function showAllGuis()
    for _, gui in pairs(S.hiddenGuis) do pcall(function() gui.Enabled=true end) end
    S.hiddenGuis={}
    if S.hideButton then S.hideButton.Visible=true end
    if S.showButton then S.showButton.Visible=false end
end

local function createHideShowButtons()
    if S.ContentFrame then
        if S.hideButton then S.hideButton:Destroy() end
        S.hideButton=Instance.new("TextButton"); S.hideButton.Name="MusicPlayerHideBtn"; S.hideButton.Size=UDim2.new(0,50,0,25)
        S.hideButton.Position=UDim2.new(0,5,1,-30); S.hideButton.BackgroundColor3=Color3.fromRGB(60,60,70)
        S.hideButton.BorderSizePixel=0; S.hideButton.Text="👁 Hide"; S.hideButton.TextColor3=Color3.fromRGB(255,255,255)
        S.hideButton.Font=Enum.Font.GothamBold; S.hideButton.TextSize=11; S.hideButton.Parent=S.ContentFrame; S.hideButton.Visible=true; S.hideButton.ZIndex=5
        Instance.new("UICorner",S.hideButton).CornerRadius=UDim.new(0,5)
        S.hideButton.MouseButton1Click:Connect(hideAllGuis)
        registerForTranslation(S.hideButton, "👁 Hide")
    end
    
    if S.showButton then if S.showButton.Parent then S.showButton.Parent:Destroy() end end
    local showScreenGui=Instance.new("ScreenGui"); showScreenGui.Name="MusicPlayerShowGui"; showScreenGui.ResetOnSpawn=false; showScreenGui.ZIndexBehavior=Enum.ZIndexBehavior.Sibling; showScreenGui.Parent=CoreGui
    
    S.showButton=Instance.new("TextButton"); S.showButton.Name="MusicPlayerShowBtn"; S.showButton.Size=UDim2.new(0,80,0,40)
    S.showButton.Position=UDim2.new(0.5,-40,0.85,0); S.showButton.BackgroundColor3=Color3.fromRGB(70,180,70)
    S.showButton.BorderSizePixel=0; S.showButton.Text="🎵 SHOW"; S.showButton.TextColor3=Color3.fromRGB(255,255,255)
    S.showButton.Font=Enum.Font.GothamBold; S.showButton.TextSize=16; S.showButton.Parent=showScreenGui
    S.showButton.Visible=false; S.showButton.ZIndex=999; S.showButton.Active=true; S.showButton.Draggable=true
    Instance.new("UICorner",S.showButton).CornerRadius=UDim.new(0,10)
    Instance.new("UIStroke",S.showButton).Thickness=2
    S.showButton.UIStroke.Color=Color3.fromRGB(255,255,255); showStroke.Transparency=0.5
    S.showButton.MouseButton1Click:Connect(showAllGuis)
    registerForTranslation(S.showButton, "🎵 SHOW")
end

-- ========== EXTRA MINI GUI (WITH COOLDOWN ON PREV/NEXT) ==========
local function createExtraMiniGUI()
    if S.ExtraMiniScreenGui then S.ExtraMiniScreenGui:Destroy() end
    S.ExtraMiniScreenGui=Instance.new("ScreenGui"); S.ExtraMiniScreenGui.Name="MusicPlayerExtraMini"; S.ExtraMiniScreenGui.ResetOnSpawn=false; S.ExtraMiniScreenGui.ZIndexBehavior=Enum.ZIndexBehavior.Sibling; S.ExtraMiniScreenGui.Parent=CoreGui; S.ExtraMiniScreenGui.Enabled=false
    S.ExtraMiniFrame=Instance.new("Frame"); S.ExtraMiniFrame.Size=UDim2.new(0,220,0,280); S.ExtraMiniFrame.Position=UDim2.new(0.5,-110,0.35,-140); S.ExtraMiniFrame.BackgroundColor3=Color3.fromRGB(20,20,20); S.ExtraMiniFrame.BackgroundTransparency=0.5; S.ExtraMiniFrame.BorderSizePixel=0; S.ExtraMiniFrame.Active=true; S.ExtraMiniFrame.Draggable=true; S.ExtraMiniFrame.Parent=S.ExtraMiniScreenGui; Instance.new("UICorner",S.ExtraMiniFrame).CornerRadius=UDim.new(0,15)
    local ecb=Instance.new("TextButton"); ecb.Size=UDim2.new(0,25,0,25); ecb.Position=UDim2.new(1,-28,0,3); ecb.BackgroundColor3=Color3.fromRGB(20,20,20); ecb.BackgroundTransparency=1; ecb.BorderSizePixel=0; ecb.Text="X"; ecb.TextColor3=Color3.fromRGB(255,255,255); ecb.Font=Enum.Font.GothamBold; ecb.TextSize=14; ecb.Parent=S.ExtraMiniFrame; Instance.new("UICorner",ecb).CornerRadius=UDim.new(1,0)
    ecb.MouseButton1Click:Connect(function() S.extraMiniPlayMode=false; if S.ExtraMiniScreenGui then S.ExtraMiniScreenGui.Enabled=false end; if S.ScreenGui then S.ScreenGui.Enabled=true end; updateExtraMiniToggle() end)
    S.ExtraLoopImageButton=Instance.new("ImageButton"); S.ExtraLoopImageButton.Size=UDim2.new(0,25,0,25); S.ExtraLoopImageButton.Position=UDim2.new(0,3,0,3); S.ExtraLoopImageButton.BackgroundTransparency=1; S.ExtraLoopImageButton.BorderSizePixel=0; S.ExtraLoopImageButton.Parent=S.ExtraMiniFrame; Instance.new("UICorner",S.ExtraLoopImageButton).CornerRadius=UDim.new(1,0); updateExtraLoopButton()
    S.ExtraLoopImageButton.MouseButton1Click:Connect(function() S.loopState=S.loopState+1; if S.loopState>2 then S.loopState=0 end; S.mainLoopOn=(S.loopState~=0); applyExtraLoopState() end)
    S.ExtraSongLabel=Instance.new("TextLabel"); S.ExtraSongLabel.Size=UDim2.new(1,-60,0,22); S.ExtraSongLabel.Position=UDim2.new(0,30,0,5); S.ExtraSongLabel.BackgroundTransparency=1; S.ExtraSongLabel.Text=""; S.ExtraSongLabel.TextColor3=Color3.fromRGB(255,255,255); S.ExtraSongLabel.Font=Enum.Font.GothamBold; S.ExtraSongLabel.TextSize=11; S.ExtraSongLabel.Parent=S.ExtraMiniFrame; S.ExtraSongLabel.ClipsDescendants=true
    S.ExtraMiniImage=Instance.new("ImageLabel"); S.ExtraMiniImage.Size=UDim2.new(1,-20,0,140); S.ExtraMiniImage.Position=UDim2.new(0,10,0,32); S.ExtraMiniImage.BackgroundTransparency=1; S.ExtraMiniImage.Image=""; S.ExtraMiniImage.ScaleType=Enum.ScaleType.Crop; S.ExtraMiniImage.Parent=S.ExtraMiniFrame; Instance.new("UICorner",S.ExtraMiniImage).CornerRadius=UDim.new(0,8)
    local esb=Instance.new("Frame"); esb.Size=UDim2.new(1,-20,0,6); esb.Position=UDim2.new(0,10,0,178); esb.BackgroundColor3=Color3.fromRGB(60,60,60); esb.BorderSizePixel=0; esb.Active=true; esb.Parent=S.ExtraMiniFrame; Instance.new("UICorner",esb).CornerRadius=UDim.new(0,3)
    S.ExtraTimeSlider=Instance.new("Frame"); S.ExtraTimeSlider.Size=UDim2.new(0,0,1,0); S.ExtraTimeSlider.BackgroundColor3=S.timeSliderBlue and Color3.fromRGB(100,180,255) or Color3.fromRGB(255,80,80); S.ExtraTimeSlider.BorderSizePixel=0; S.ExtraTimeSlider.Parent=esb; Instance.new("UICorner",S.ExtraTimeSlider).CornerRadius=UDim.new(0,3)
    S.ExtraTimeLabel=Instance.new("TextLabel"); S.ExtraTimeLabel.Size=UDim2.new(1,-20,0,15); S.ExtraTimeLabel.Position=UDim2.new(0,10,0,188); S.ExtraTimeLabel.BackgroundTransparency=1; S.ExtraTimeLabel.Text="0:00 / 0:00"; S.ExtraTimeLabel.TextColor3=Color3.fromRGB(200,200,200); S.ExtraTimeLabel.Font=Enum.Font.Gotham; S.ExtraTimeLabel.TextSize=10; S.ExtraTimeLabel.TextXAlignment=Enum.TextXAlignment.Center; S.ExtraTimeLabel.Parent=S.ExtraMiniFrame
    local esca=Instance.new("ImageButton"); esca.Size=UDim2.new(1,0,1,0); esca.BackgroundTransparency=1; esca.Image="rbxassetid://0"; esca.ImageTransparency=1; esca.BorderSizePixel=0; esca.ZIndex=5; esca.Parent=esb
    esca.MouseButton1Down:Connect(function() S.isDraggingExtraSlider=true; if S.currentSound and S.currentSound.TimeLength>0 then local mx=mouse.X-esb.AbsolutePosition.X; local frac=math.clamp(mx/esb.AbsoluteSize.X,0,1); S.currentSound.TimePosition=frac*S.currentSound.TimeLength; if S.isPaused then S.pausedTimePosition=S.currentSound.TimePosition end; updateTimeDisplay() end end)
    local ecf=Instance.new("Frame"); ecf.Size=UDim2.new(1,-20,0,30); ecf.Position=UDim2.new(0,10,0,210); ecf.BackgroundTransparency=1; ecf.Parent=S.ExtraMiniFrame
    local btnSize=30; local totalBtns=5; local totalWidth=btnSize*totalBtns+5*(totalBtns-1); local startX=(200-totalWidth)/2
    local function meb(img,px) local btn=Instance.new("ImageButton"); btn.Size=UDim2.new(0,btnSize,0,btnSize); btn.Position=UDim2.new(0,px,0,0); btn.BackgroundTransparency=1; btn.BorderSizePixel=0; btn.Image=img; btn.Parent=ecf; Instance.new("UICorner",btn).CornerRadius=UDim.new(1,0); return btn end
    
    -- COOLDOWN: Previous button (0.25s)
    local extraLastCooldown = false
    local lastBtn=meb("rbxassetid://88757150664292",startX)
    lastBtn.MouseButton1Click:Connect(function()
        if extraLastCooldown then return end
        extraLastCooldown = true
        spawn(function() wait(0.25); extraLastCooldown = false end)
        if #S.playlistSongs>0 then local ni=S.currentPlaylistIndex-1; if ni<1 then ni=#S.playlistSongs end; local song=S.playlistSongs[ni]; if song then playMusicFromUrl(song.url,song.fileName,ni) end end
    end)
    
    local rewindBtn=meb("rbxassetid://122950454234379",startX+btnSize+5); rewindBtn.MouseButton1Click:Connect(function() if not S.currentSound then return end; local nt=math.max(S.currentSound.TimePosition-10,0); S.currentSound.TimePosition=nt; if S.isPaused then S.pausedTimePosition=nt end; updateTimeDisplay() end)
    S.ExtraPauseImageButton=meb("rbxassetid://80704722265943",startX+btnSize*2+10); S.ExtraPauseImageButton.MouseButton1Click:Connect(function() if not S.currentSound then return end; togglePause() end)
    local forwardBtn=meb("rbxassetid://102857578902137",startX+btnSize*3+15); forwardBtn.MouseButton1Click:Connect(function() if not S.currentSound then return end; local nt=math.min(S.currentSound.TimePosition+10,S.currentSound.TimeLength); S.currentSound.TimePosition=nt; if S.isPaused then S.pausedTimePosition=nt end; updateTimeDisplay() end)
    
    -- COOLDOWN: Next button (0.25s)
    local extraNextCooldown = false
    local nextBtn=meb("rbxassetid://82401540450034",startX+btnSize*4+20)
    nextBtn.MouseButton1Click:Connect(function()
        if extraNextCooldown then return end
        extraNextCooldown = true
        spawn(function() wait(0.25); extraNextCooldown = false end)
        if #S.playlistSongs>0 then local ni=S.currentPlaylistIndex+1; if ni>#S.playlistSongs then ni=1 end; local song=S.playlistSongs[ni]; if song then playMusicFromUrl(song.url,song.fileName,ni) end end
    end)
end

local function toggleExtraMiniMode()
    if not S.isKeyCorrect then if S.ExtraMiniToggle then S.ExtraMiniToggle.BackgroundColor3=Color3.fromRGB(180,80,80); S.ExtraMiniToggle.Text="LOCKED" end; showNotification("GitHub MP3 Player","Unlock playlist first!",2); wait(1); updateExtraMiniToggle(); return end
    S.extraMiniPlayMode=not S.extraMiniPlayMode; updateExtraMiniToggle()
    if S.extraMiniPlayMode then createExtraMiniGUI(); if S.currentPlaylistIndex>0 and S.playlistSongs[S.currentPlaylistIndex] then local img=S.playlistSongs[S.currentPlaylistIndex].imageAsset; if img and img~="" and S.ExtraMiniImage then S.ExtraMiniImage.Image=img end end; if S.currentSongName~="" and S.ExtraSongLabel then S.ExtraSongLabel.Text=S.currentSongName; startAutoScroll(S.ExtraSongLabel) end; if S.ExtraMiniScreenGui then S.ExtraMiniScreenGui.Enabled=true end; if S.ScreenGui then S.ScreenGui.Enabled=false end; if S.MiniScreenGui then S.MiniScreenGui.Enabled=false end
    else if S.ExtraMiniScreenGui then S.ExtraMiniScreenGui.Enabled=false end; if S.ScreenGui then S.ScreenGui.Enabled=true end; if S.MiniScreenGui then S.MiniScreenGui.Enabled=S.miniPlayMode end end
end

-- ========== TOGGLE PANELS ==========
function toggleSettingsPanel()
    if not S.SettingsPanel then return end
    if S.isSettingsOpen then TweenService:Create(S.SettingsPanel,TweenInfo.new(0.3,Enum.EasingStyle.Back,Enum.EasingDirection.In),{Position=UDim2.new(0,0,0,-290)}):Play(); wait(0.3); S.SettingsPanel.Visible=false; S.isSettingsOpen=false
    else if S.isSearchOpen then toggleSearchPanel() end; if S.isInfoOpen then toggleInfoPanel() end; if S.isHistoryOpen then toggleHistoryPanel() end; S.SettingsPanel.Visible=true; S.isSettingsOpen=true; TweenService:Create(S.SettingsPanel,TweenInfo.new(0.3,Enum.EasingStyle.Back,Enum.EasingDirection.Out),{Position=UDim2.new(0,0,0,-290)}):Play() end
end
function toggleInfoPanel() if not S.InfoPanel then return end; if S.isInfoOpen then TweenService:Create(S.InfoPanel,TweenInfo.new(0.3,Enum.EasingStyle.Back,Enum.EasingDirection.In),{Position=UDim2.new(0,-290,0,0)}):Play(); wait(0.3); S.InfoPanel.Visible=false; S.isInfoOpen=false else if S.isSearchOpen then toggleSearchPanel() end; if S.isHistoryOpen then toggleHistoryPanel() end; S.InfoPanel.Visible=true; S.isInfoOpen=true; TweenService:Create(S.InfoPanel,TweenInfo.new(0.3,Enum.EasingStyle.Back,Enum.EasingDirection.Out),{Position=UDim2.new(0,-290,0,0)}):Play() end end
function toggleSearchPanel() if not S.SearchPanel then return end; if S.isHistoryOpen then toggleHistoryPanel() end; S.isSearchOpen=not S.isSearchOpen; if S.isSearchOpen then S.SearchPanel.Visible=true; TweenService:Create(S.SearchPanel,TweenInfo.new(0.3,Enum.EasingStyle.Back,Enum.EasingDirection.Out),{Position=UDim2.new(1,10,0,0)}):Play(); S.SearchTextBox.Text=""; for _,c in pairs(S.SearchScrollFrame:GetChildren()) do if c.Name=="SearchResultItem" then c:Destroy() end end; S.SearchNoResultsLabel.Visible=true; S.SearchNoResultsLabel.Text="Enter a search term or URL" else TweenService:Create(S.SearchPanel,TweenInfo.new(0.3,Enum.EasingStyle.Back,Enum.EasingDirection.In),{Position=UDim2.new(1,310,0,0)}):Play(); wait(0.3); S.SearchPanel.Visible=false end end
function toggleHistoryPanel() if not S.HistoryPanel then return end; S.isHistoryOpen=not S.isHistoryOpen; if S.isHistoryOpen then S.HistoryPanel.Visible=true; TweenService:Create(S.HistoryPanel,TweenInfo.new(0.3,Enum.EasingStyle.Back,Enum.EasingDirection.Out),{Position=UDim2.new(0,0,0,0)}):Play(); updateTranslatableText(S.HistoryButton, "← HISTORY"); updateHistoryList() else TweenService:Create(S.HistoryPanel,TweenInfo.new(0.3,Enum.EasingStyle.Back,Enum.EasingDirection.In),{Position=UDim2.new(1,0,0,0)}):Play(); updateTranslatableText(S.HistoryButton, "→ HISTORY"); wait(0.3); S.HistoryPanel.Visible=false end end
function updateHistoryList() if not S.HistoryScrollFrame then return end; for _,c in pairs(S.HistoryScrollFrame:GetChildren()) do if c.Name=="HistoryItem" then c:Destroy() end end; S.NoHistoryLabel.Visible=#S.downloadHistory==0; if #S.downloadHistory==0 then S.HistoryScrollFrame.CanvasSize=UDim2.new(0,0,0,0); return end; local ih,spc,th=45,5,0; for i,e in ipairs(S.downloadHistory) do local ce,ci={url=e.url,fileName=e.fileName,date=e.date},i; local it=Instance.new("Frame"); it.Name="HistoryItem"; it.Size=UDim2.new(1,-10,0,ih); it.Position=UDim2.new(0,5,0,th); it.BackgroundColor3=i%2==0 and Color3.fromRGB(55,55,55) or Color3.fromRGB(50,50,50); it.BorderSizePixel=0; it.Parent=S.HistoryScrollFrame; Instance.new("UICorner",it).CornerRadius=UDim.new(0,4); local fl=Instance.new("TextLabel"); fl.Size=UDim2.new(0.6,-5,0,20); fl.Position=UDim2.new(0,5,0,5); fl.BackgroundTransparency=1; fl.Text=ce.fileName or "Unknown"; fl.TextColor3=Color3.fromRGB(255,255,255); fl.Font=Enum.Font.Gotham; fl.TextSize=11; fl.TextTruncate=Enum.TextTruncate.AtEnd; fl.Parent=it; local dl=Instance.new("TextLabel"); dl.Size=UDim2.new(0.6,-5,0,15); dl.Position=UDim2.new(0,5,0,25); dl.BackgroundTransparency=1; dl.Text=ce.date or "Unknown"; dl.TextColor3=Color3.fromRGB(180,180,180); dl.Font=Enum.Font.Gotham; dl.TextSize=9; dl.Parent=it; local pb=Instance.new("TextButton"); pb.Size=UDim2.new(0.15,-5,0,25); pb.Position=UDim2.new(0.6,5,0,10); pb.BackgroundColor3=Color3.fromRGB(70,150,70); pb.BorderSizePixel=0; pb.Text="▶"; pb.TextColor3=Color3.fromRGB(255,255,255); pb.Font=Enum.Font.GothamBold; pb.TextSize=12; pb.Parent=it; Instance.new("UICorner",pb).CornerRadius=UDim.new(0,4); local db=Instance.new("TextButton"); db.Size=UDim2.new(0.15,-5,0,25); db.Position=UDim2.new(0.8,10,0,10); db.BackgroundColor3=Color3.fromRGB(200,80,80); db.BorderSizePixel=0; db.Text="🗑️"; db.TextColor3=Color3.fromRGB(255,255,255); db.Font=Enum.Font.Gotham; db.TextSize=12; db.Parent=it; Instance.new("UICorner",db).CornerRadius=UDim.new(0,4); pb.MouseButton1Click:Connect(function() if ce and ce.url then if S.isHistoryOpen then toggleHistoryPanel() end; playMusicFromUrl(ce.url,ce.fileName or "audio.mp3") end end); db.MouseButton1Click:Connect(function() if removeFromHistory(ci) then updateHistoryList() end end); th=th+ih+spc end; S.HistoryScrollFrame.CanvasSize=UDim2.new(0,0,0,th) end

-- ========== SLIDER DRAGGING ==========
UserInputService.InputChanged:Connect(function(input) if input.UserInputType==Enum.UserInputType.MouseMovement then if S.isDraggingDataInterval and S.DataIntervalSlider and S.DataIntervalSlider.AbsoluteSize.X>0 then local mx=mouse.X-S.DataIntervalSlider.AbsolutePosition.X; local frac=math.clamp(mx/S.DataIntervalSlider.AbsoluteSize.X,0,1); setDataRefreshInterval(5+frac*55) elseif S.isDraggingTimeSlider and S.currentSound and S.currentSound.TimeLength>0 then local mx=mouse.X-S.TimeSliderBg.AbsolutePosition.X; local frac=math.clamp(mx/S.TimeSliderBg.AbsoluteSize.X,0,1); S.currentSound.TimePosition=frac*S.currentSound.TimeLength; if S.isPaused then S.pausedTimePosition=S.currentSound.TimePosition end; updateTimeDisplay() elseif S.isDraggingMiniTimeSlider and S.currentSound and S.currentSound.TimeLength>0 then local mx=mouse.X-S.MiniTimeSliderBg.AbsolutePosition.X; local frac=math.clamp(mx/S.MiniTimeSliderBg.AbsoluteSize.X,0,1); S.currentSound.TimePosition=frac*S.currentSound.TimeLength; if S.isPaused then S.pausedTimePosition=S.currentSound.TimePosition end; updateTimeDisplay() elseif S.isDraggingExtraSlider and S.currentSound and S.currentSound.TimeLength>0 and S.ExtraTimeSlider and S.ExtraTimeSlider.Parent then local mx=mouse.X-S.ExtraTimeSlider.Parent.AbsolutePosition.X; local frac=math.clamp(mx/S.ExtraTimeSlider.Parent.AbsoluteSize.X,0,1); S.currentSound.TimePosition=frac*S.currentSound.TimeLength; if S.isPaused then S.pausedTimePosition=S.currentSound.TimePosition end; updateTimeDisplay() end end end)
UserInputService.InputEnded:Connect(function(input) if input.UserInputType==Enum.UserInputType.MouseButton1 then S.isDraggingTimeSlider=false; S.isDraggingMiniTimeSlider=false; S.isDraggingExtraSlider=false; S.isDraggingDataInterval=false end end)

-- ========== KEYBIND SYSTEM ==========
local function setupKeybind()
    if S.keybindConnection then pcall(function() S.keybindConnection:Disconnect() end); S.keybindConnection=nil end
    if not S.keybindEnabled then return end
    S.keybindConnection=UserInputService.InputBegan:Connect(function(input,gp) 
        if gp then return end
        if input.KeyCode==Enum.KeyCode.H then
            if #S.hiddenGuis>0 or (S.showButton and S.showButton.Visible) then showAllGuis() else hideAllGuis() end
        elseif input.KeyCode==Enum.KeyCode.P then
            if S.currentSound then togglePause() end
        elseif input.KeyCode==Enum.KeyCode.S then
            stopMusic(); updateTranslatableText(S.StatusLabel, "⏹ Music Stopped"); updateTimeDisplay()
        elseif input.KeyCode==Enum.KeyCode.M then
            local t=S.themes[S.currentTheme] or S.themes["Default"]
            if S.isGameMuted then
                S.isGameMuted=false; updateTranslatableText(S.MuteToggle, "🔇 MUTE GAME"); S.MuteToggle.BackgroundColor3=t.muteColor or Color3.fromRGB(180,80,80)
                for sound,vol in pairs(S.gameSoundsMuted) do pcall(function() if sound and sound.Parent then sound.Volume=vol end end) end
                S.gameSoundsMuted={}; pcall(function() SoundService.Volume=1 end)
            else
                S.isGameMuted=true; updateTranslatableText(S.MuteToggle, "🔊 UNMUTE"); S.MuteToggle.BackgroundColor3=t.muteOnColor or Color3.fromRGB(80,180,80)
                S.gameSoundsMuted={}
                pcall(function() for _,v in pairs(workspace:GetDescendants()) do if v:IsA("Sound") and v~=S.currentSound then S.gameSoundsMuted[v]=v.Volume; v.Volume=0 end end end)
                pcall(function() SoundService.Volume=0 end)
            end
        elseif input.KeyCode==Enum.KeyCode.L then
            S.mainLoopOn=not S.mainLoopOn; applyLoopState()
        end
    end)
    print("[MusicPlayer] Keybinds: H=Hide/Show, P=Play/Pause, S=Stop, M=Mute Game, L=Loop")
end

-- ========== TEXTBOX ANIMATION ==========
local function animateTextboxPlaceholder(textbox, texts)
    if not textbox then return end
    local ti=1
    spawn(function()
        while textbox and textbox.Parent do
            local ft=texts[ti]; local ct=""
            for i=1,#ft do if not textbox or not textbox.Parent then return end; ct=ct..string.sub(ft,i,i); textbox.PlaceholderText=ct.."_"; wait(0.15) end
            if not textbox or not textbox.Parent then return end; textbox.PlaceholderText=ft.."_"; wait(0.3)
            for b=1,3 do if not textbox or not textbox.Parent then return end; textbox.PlaceholderText=ft; wait(0.2); if not textbox or not textbox.Parent then return end; textbox.PlaceholderText=ft.."_"; wait(0.2) end
            wait(1.5); if not textbox or not textbox.Parent then return end; textbox.PlaceholderText=""; wait(0.5)
            ti=ti+1; if ti>#texts then ti=1 end
        end
    end)
end

-- ========== CREATE MAIN GUI ==========
local function createMainGUI()
    print("[MusicPlayer] Creating main GUI...")
    S.ScreenGui=Instance.new("ScreenGui"); S.ScreenGui.Name="MusicPlayerGUI"; S.ScreenGui.ResetOnSpawn=false; S.ScreenGui.ZIndexBehavior=Enum.ZIndexBehavior.Sibling; S.ScreenGui.Parent=CoreGui; S.ScreenGui.Enabled=true
    S.MainFrame=Instance.new("Frame"); S.MainFrame.Size=UDim2.new(0,400,0,345); S.MainFrame.Position=UDim2.new(0.5,-200,0.5,-172); S.MainFrame.BackgroundColor3=Color3.fromRGB(40,40,40); S.MainFrame.BorderSizePixel=0; S.MainFrame.Active=true; S.MainFrame.Draggable=true; S.MainFrame.Parent=S.ScreenGui; Instance.new("UICorner",S.MainFrame).CornerRadius=UDim.new(0,10)
    S.OutlineFrame=Instance.new("Frame"); S.OutlineFrame.Size=UDim2.new(1,6,1,6); S.OutlineFrame.Position=UDim2.new(0,-3,0,-3); S.OutlineFrame.BackgroundColor3=Color3.fromRGB(40,40,40); S.OutlineFrame.BorderSizePixel=0; S.OutlineFrame.ZIndex=0; S.OutlineFrame.Parent=S.MainFrame; Instance.new("UICorner",S.OutlineFrame).CornerRadius=UDim.new(0,12)
    S.UIStroke=Instance.new("UIStroke"); S.UIStroke.Thickness=3; S.UIStroke.Color=Color3.fromRGB(80,80,80); S.UIStroke.Parent=S.OutlineFrame
    spawn(function() local cl={Color3.fromRGB(255,50,50),Color3.fromRGB(255,150,50),Color3.fromRGB(255,255,50),Color3.fromRGB(50,255,50),Color3.fromRGB(50,150,255),Color3.fromRGB(150,50,255),Color3.fromRGB(255,50,255)}; local i=1; while S.UIStroke and S.UIStroke.Parent do TweenService:Create(S.UIStroke,TweenInfo.new(2),{Color=cl[i]}):Play(); i=i+1; if i>#cl then i=1 end; wait(2) end end)
    
    S.TitleBar=Instance.new("Frame"); S.TitleBar.Size=UDim2.new(1,0,0,35); S.TitleBar.BackgroundColor3=Color3.fromRGB(30,30,30); S.TitleBar.BorderSizePixel=0; S.TitleBar.Parent=S.MainFrame; Instance.new("UICorner",S.TitleBar).CornerRadius=UDim.new(0,10)
    S.TitleText=Instance.new("TextLabel"); S.TitleText.Size=UDim2.new(0,200,1,0); S.TitleText.Position=UDim2.new(0,15,0,0); S.TitleText.BackgroundTransparency=1; S.TitleText.Text="GitHub MP3 Player"; S.TitleText.TextColor3=Color3.fromRGB(255,255,255); S.TitleText.TextXAlignment=Enum.TextXAlignment.Left; S.TitleText.Font=Enum.Font.GothamBold; S.TitleText.TextSize=16; S.TitleText.Parent=S.TitleBar
    
    local function mkBtn(tx,px,cl,pr) local b=Instance.new("TextButton"); b.Size=UDim2.new(0,35,0,35); b.Position=UDim2.new(1,px,0,0); b.BackgroundColor3=cl; b.BorderSizePixel=0; b.Text=tx; b.TextColor3=Color3.fromRGB(255,255,255); b.Font=Enum.Font.GothamBold; b.TextSize=18; b.Parent=pr; Instance.new("UICorner",b).CornerRadius=UDim.new(0,8); return b end
    S.InfoButton=mkBtn("ℹ",-200,Color3.fromRGB(100,180,255),S.TitleBar); S.SettingsButton=mkBtn("⚙",-160,Color3.fromRGB(150,150,150),S.TitleBar); S.SearchButton=mkBtn("🔍",-120,Color3.fromRGB(100,150,255),S.TitleBar); local MinimizeButton=mkBtn("-",-80,Color3.fromRGB(255,180,60),S.TitleBar)
    local CloseButton=Instance.new("TextButton"); CloseButton.Size=UDim2.new(0,40,0,35); CloseButton.Position=UDim2.new(1,-40,0,0); CloseButton.BackgroundColor3=Color3.fromRGB(255,60,60); CloseButton.BorderSizePixel=0; CloseButton.Text="X"; CloseButton.TextColor3=Color3.fromRGB(255,255,255); CloseButton.Font=Enum.Font.GothamBold; CloseButton.TextSize=14; CloseButton.Parent=S.TitleBar; Instance.new("UICorner",CloseButton).CornerRadius=UDim.new(0,8)
    
    -- Settings Panel
    S.SettingsPanel=Instance.new("Frame"); S.SettingsPanel.Size=UDim2.new(1,0,0,280); S.SettingsPanel.Position=UDim2.new(0,0,0,-290); S.SettingsPanel.BackgroundColor3=Color3.fromRGB(35,35,42); S.SettingsPanel.BorderSizePixel=0; S.SettingsPanel.Visible=false; S.SettingsPanel.Parent=S.MainFrame; S.SettingsPanel.ZIndex=10; Instance.new("UICorner",S.SettingsPanel).CornerRadius=UDim.new(0,8); S.SettingsPanelUIStroke=Instance.new("UIStroke",S.SettingsPanel).Thickness=3.5; S.SettingsPanelUIStroke.Color=Color3.fromRGB(150,150,160); S.SettingsPanelUIStroke.Transparency=0.5
    local settingsTabBtn=Instance.new("TextButton"); settingsTabBtn.Size=UDim2.new(0.48,0,0,28); settingsTabBtn.Position=UDim2.new(0,3,0,1); settingsTabBtn.BackgroundColor3=Color3.fromRGB(100,150,255); settingsTabBtn.BorderSizePixel=0; settingsTabBtn.Text="⚙ Settings"; settingsTabBtn.TextColor3=Color3.fromRGB(255,255,255); settingsTabBtn.Font=Enum.Font.GothamBold; settingsTabBtn.TextSize=11; settingsTabBtn.Parent=S.SettingsPanel; settingsTabBtn.ZIndex=11; Instance.new("UICorner",settingsTabBtn).CornerRadius=UDim.new(0,5)
    local playingTabBtn=Instance.new("TextButton"); playingTabBtn.Size=UDim2.new(0.48,0,0,28); playingTabBtn.Position=UDim2.new(0.52,0,0,1); playingTabBtn.BackgroundColor3=Color3.fromRGB(60,60,70); playingTabBtn.BorderSizePixel=0; playingTabBtn.Text="🎵 Playing"; playingTabBtn.TextColor3=Color3.fromRGB(255,255,255); playingTabBtn.Font=Enum.Font.GothamBold; playingTabBtn.TextSize=11; playingTabBtn.Parent=S.SettingsPanel; playingTabBtn.ZIndex=11; Instance.new("UICorner",playingTabBtn).CornerRadius=UDim.new(0,5)
    
    S.SettingsScrollFrame=Instance.new("ScrollingFrame"); S.SettingsScrollFrame.Size=UDim2.new(1,-5,1,-35); S.SettingsScrollFrame.Position=UDim2.new(0,0,0,33); S.SettingsScrollFrame.BackgroundTransparency=1; S.SettingsScrollFrame.BorderSizePixel=0; S.SettingsScrollFrame.ScrollBarThickness=5; S.SettingsScrollFrame.CanvasSize=UDim2.new(0,0,0,300); S.SettingsScrollFrame.Parent=S.SettingsPanel
    
    local yPos=5; local tl=Instance.new("TextLabel"); tl.Size=UDim2.new(0,120,0,25); tl.Position=UDim2.new(0,15,0,yPos); tl.BackgroundTransparency=1; tl.Text="Theme:"; tl.TextColor3=Color3.fromRGB(220,220,230); tl.TextXAlignment=Enum.TextXAlignment.Left; tl.Font=Enum.Font.GothamBold; tl.TextSize=13; tl.Parent=S.SettingsScrollFrame; yPos=yPos+30
    local td=Instance.new("TextButton"); td.Size=UDim2.new(1,-30,0,30); td.Position=UDim2.new(0,15,0,yPos); td.BackgroundColor3=Color3.fromRGB(60,60,70); td.BorderSizePixel=0; td.Text=S.currentTheme.." ▼"; td.TextColor3=Color3.fromRGB(255,255,255); td.Font=Enum.Font.GothamBold; td.TextSize=13; td.Parent=S.SettingsScrollFrame; Instance.new("UICorner",td).CornerRadius=UDim.new(0,6); yPos=yPos+35
    local tml=Instance.new("ScrollingFrame"); tml.Size=UDim2.new(1,-30,0,55); tml.Position=UDim2.new(0,15,0,yPos); tml.BackgroundColor3=Color3.fromRGB(50,50,58); tml.BorderSizePixel=0; tml.ScrollBarThickness=6; tml.CanvasSize=UDim2.new(0,0,0,0); tml.Visible=false; tml.Parent=S.SettingsScrollFrame; Instance.new("UICorner",tml).CornerRadius=UDim.new(0,5)
    local allThemes={"Default","Dark Blue","Light","Neon Light","Dark Light","Bright","Blue","Purple","Red","Green","Midnight"}
    for i,n in ipairs(allThemes) do local b=Instance.new("TextButton"); b.Size=UDim2.new(1,-10,0,28); b.Position=UDim2.new(0,5,0,(i-1)*30+3); b.BackgroundColor3=Color3.fromRGB(55,55,63); b.BorderSizePixel=0; b.Text=n; b.TextColor3=Color3.fromRGB(255,255,255); b.Font=Enum.Font.Gotham; b.TextSize=12; b.Parent=tml; Instance.new("UICorner",b).CornerRadius=UDim.new(0,4); b.MouseButton1Click:Connect(function() applyTheme(n); td.Text=n.." ▼"; tml.Visible=false end) end
    tml.CanvasSize=UDim2.new(0,0,0,#allThemes*30+6); td.MouseButton1Click:Connect(function() tml.Visible=not tml.Visible end); yPos=yPos+5
    
    local SaveThemeLabel=Instance.new("TextLabel"); SaveThemeLabel.Size=UDim2.new(0,200,0,25); SaveThemeLabel.Position=UDim2.new(0,15,0,yPos+55); SaveThemeLabel.BackgroundTransparency=1; SaveThemeLabel.Text="Save Theme:"; SaveThemeLabel.TextColor3=Color3.fromRGB(220,220,230); SaveThemeLabel.TextXAlignment=Enum.TextXAlignment.Left; SaveThemeLabel.Font=Enum.Font.GothamBold; SaveThemeLabel.TextSize=13; SaveThemeLabel.Parent=S.SettingsScrollFrame
    S.SaveThemeToggle=Instance.new("TextButton"); S.SaveThemeToggle.Size=UDim2.new(0,60,0,28); S.SaveThemeToggle.Position=UDim2.new(0,220,0,yPos+55); S.SaveThemeToggle.BorderSizePixel=0; S.SaveThemeToggle.Font=Enum.Font.GothamBold; S.SaveThemeToggle.TextSize=12; S.SaveThemeToggle.TextColor3=Color3.fromRGB(255,255,255); S.SaveThemeToggle.Parent=S.SettingsScrollFrame; Instance.new("UICorner",S.SaveThemeToggle).CornerRadius=UDim.new(0,6)
    S.SaveThemeToggle.MouseButton1Click:Connect(function() S.saveThemeEnabled=not S.saveThemeEnabled; updateSaveThemeToggle(); if S.saveThemeEnabled then saveSettings() else pcall(function() if isfile and isfile(SETTINGS_FILE) then delfile(SETTINGS_FILE) end end) end end)
    local RememberKeyLabel=Instance.new("TextLabel"); RememberKeyLabel.Size=UDim2.new(0,200,0,25); RememberKeyLabel.Position=UDim2.new(0,15,0,yPos+90); RememberKeyLabel.BackgroundTransparency=1; RememberKeyLabel.Text="Remember Key:"; RememberKeyLabel.TextColor3=Color3.fromRGB(220,220,230); RememberKeyLabel.TextXAlignment=Enum.TextXAlignment.Left; RememberKeyLabel.Font=Enum.Font.GothamBold; RememberKeyLabel.TextSize=13; RememberKeyLabel.Parent=S.SettingsScrollFrame
    S.RememberKeyToggle=Instance.new("TextButton"); S.RememberKeyToggle.Size=UDim2.new(0,60,0,28); S.RememberKeyToggle.Position=UDim2.new(0,220,0,yPos+90); S.RememberKeyToggle.BorderSizePixel=0; S.RememberKeyToggle.Font=Enum.Font.GothamBold; S.RememberKeyToggle.TextSize=12; S.RememberKeyToggle.TextColor3=Color3.fromRGB(255,255,255); S.RememberKeyToggle.Parent=S.SettingsScrollFrame; Instance.new("UICorner",S.RememberKeyToggle).CornerRadius=UDim.new(0,6)
    S.RememberKeyToggle.MouseButton1Click:Connect(function() S.rememberKeyEnabled=not S.rememberKeyEnabled; updateRememberKeyToggle(); if S.rememberKeyEnabled then if S.isKeyCorrect then saveKeyState() end else deleteKeyFile() end end)
    local SliderColorLabel=Instance.new("TextLabel"); SliderColorLabel.Size=UDim2.new(0,200,0,25); SliderColorLabel.Position=UDim2.new(0,15,0,yPos+125); SliderColorLabel.BackgroundTransparency=1; SliderColorLabel.Text="Slider Color:"; SliderColorLabel.TextColor3=Color3.fromRGB(220,220,230); SliderColorLabel.TextXAlignment=Enum.TextXAlignment.Left; SliderColorLabel.Font=Enum.Font.GothamBold; SliderColorLabel.TextSize=13; SliderColorLabel.Parent=S.SettingsScrollFrame
    S.SliderColorToggle=Instance.new("TextButton"); S.SliderColorToggle.Size=UDim2.new(0,60,0,28); S.SliderColorToggle.Position=UDim2.new(0,220,0,yPos+125); S.SliderColorToggle.BorderSizePixel=0; S.SliderColorToggle.Font=Enum.Font.GothamBold; S.SliderColorToggle.TextSize=12; S.SliderColorToggle.TextColor3=Color3.fromRGB(255,255,255); S.SliderColorToggle.Parent=S.SettingsScrollFrame; Instance.new("UICorner",S.SliderColorToggle).CornerRadius=UDim.new(0,6)
    S.SliderColorToggle.MouseButton1Click:Connect(function() S.timeSliderBlue=not S.timeSliderBlue; updateSliderColors(); updateSliderColorToggle(); if S.saveThemeEnabled then saveSettings() end end)
    local MiniPlayLabel=Instance.new("TextLabel"); MiniPlayLabel.Size=UDim2.new(0,200,0,25); MiniPlayLabel.Position=UDim2.new(0,15,0,yPos+160); MiniPlayLabel.BackgroundTransparency=1; MiniPlayLabel.Text="Mini Play Mode:"; MiniPlayLabel.TextColor3=Color3.fromRGB(220,220,230); MiniPlayLabel.TextXAlignment=Enum.TextXAlignment.Left; MiniPlayLabel.Font=Enum.Font.GothamBold; MiniPlayLabel.TextSize=13; MiniPlayLabel.Parent=S.SettingsScrollFrame
    S.MiniPlayToggle=Instance.new("TextButton"); S.MiniPlayToggle.Size=UDim2.new(0,60,0,28); S.MiniPlayToggle.Position=UDim2.new(0,220,0,yPos+160); S.MiniPlayToggle.BorderSizePixel=0; S.MiniPlayToggle.Font=Enum.Font.GothamBold; S.MiniPlayToggle.TextSize=12; S.MiniPlayToggle.TextColor3=Color3.fromRGB(255,255,255); S.MiniPlayToggle.Parent=S.SettingsScrollFrame; Instance.new("UICorner",S.MiniPlayToggle).CornerRadius=UDim.new(0,6)
    local ExtraMiniLabel=Instance.new("TextLabel"); ExtraMiniLabel.Size=UDim2.new(0,200,0,25); ExtraMiniLabel.Position=UDim2.new(0,15,0,yPos+195); ExtraMiniLabel.BackgroundTransparency=1; ExtraMiniLabel.Text="Extra Mini Mode:"; ExtraMiniLabel.TextColor3=Color3.fromRGB(220,220,230); ExtraMiniLabel.TextXAlignment=Enum.TextXAlignment.Left; ExtraMiniLabel.Font=Enum.Font.GothamBold; ExtraMiniLabel.TextSize=13; ExtraMiniLabel.Parent=S.SettingsScrollFrame
    S.ExtraMiniToggle=Instance.new("TextButton"); S.ExtraMiniToggle.Size=UDim2.new(0,60,0,28); S.ExtraMiniToggle.Position=UDim2.new(0,220,0,yPos+195); S.ExtraMiniToggle.BorderSizePixel=0; S.ExtraMiniToggle.Font=Enum.Font.GothamBold; S.ExtraMiniToggle.TextSize=12; S.ExtraMiniToggle.TextColor3=Color3.fromRGB(255,255,255); S.ExtraMiniToggle.Parent=S.SettingsScrollFrame; Instance.new("UICorner",S.ExtraMiniToggle).CornerRadius=UDim.new(0,6)
    S.ExtraMiniToggle.MouseButton1Click:Connect(function() toggleExtraMiniMode() end)
    local KeybindLabel=Instance.new("TextLabel"); KeybindLabel.Size=UDim2.new(0,200,0,25); KeybindLabel.Position=UDim2.new(0,15,0,yPos+230); KeybindLabel.BackgroundTransparency=1; KeybindLabel.Text="Keybinds:"; KeybindLabel.TextColor3=Color3.fromRGB(220,220,230); KeybindLabel.TextXAlignment=Enum.TextXAlignment.Left; KeybindLabel.Font=Enum.Font.GothamBold; KeybindLabel.TextSize=13; KeybindLabel.Parent=S.SettingsScrollFrame
    S.KeybindToggle=Instance.new("TextButton"); S.KeybindToggle.Size=UDim2.new(0,60,0,28); S.KeybindToggle.Position=UDim2.new(0,220,0,yPos+230); S.KeybindToggle.BorderSizePixel=0; S.KeybindToggle.Font=Enum.Font.GothamBold; S.KeybindToggle.TextSize=12; S.KeybindToggle.TextColor3=Color3.fromRGB(255,255,255); S.KeybindToggle.Parent=S.SettingsScrollFrame; Instance.new("UICorner",S.KeybindToggle).CornerRadius=UDim.new(0,6)
    S.KeybindToggle.MouseButton1Click:Connect(function() S.keybindEnabled=not S.keybindEnabled; updateKeybindToggle(); saveSettings(); setupKeybind() end)
    
    -- Auto Translate Toggle
    local AutoTranslateLabel=Instance.new("TextLabel"); AutoTranslateLabel.Size=UDim2.new(0,200,0,25); AutoTranslateLabel.Position=UDim2.new(0,15,0,yPos+265); AutoTranslateLabel.BackgroundTransparency=1; AutoTranslateLabel.Text="Auto Translate:"; AutoTranslateLabel.TextColor3=Color3.fromRGB(220,220,230); AutoTranslateLabel.TextXAlignment=Enum.TextXAlignment.Left; AutoTranslateLabel.Font=Enum.Font.GothamBold; AutoTranslateLabel.TextSize=13; AutoTranslateLabel.Parent=S.SettingsScrollFrame
    S.AutoTranslateToggle=Instance.new("TextButton"); S.AutoTranslateToggle.Size=UDim2.new(0,60,0,28); S.AutoTranslateToggle.Position=UDim2.new(0,220,0,yPos+265); S.AutoTranslateToggle.BorderSizePixel=0; S.AutoTranslateToggle.Font=Enum.Font.GothamBold; S.AutoTranslateToggle.TextSize=12; S.AutoTranslateToggle.TextColor3=Color3.fromRGB(255,255,255); S.AutoTranslateToggle.Parent=S.SettingsScrollFrame; Instance.new("UICorner",S.AutoTranslateToggle).CornerRadius=UDim.new(0,6)
    S.AutoTranslateToggle.MouseButton1Click:Connect(function() toggleAutoTranslate() end)
    
    S.SettingsScrollFrame.CanvasSize=UDim2.new(0,0,0,yPos+300)
    
    -- Sound Effects Tab
    S.playingPanel=Instance.new("Frame"); S.playingPanel.Size=UDim2.new(1,0,1,-35); S.playingPanel.Position=UDim2.new(0,0,0,33); S.playingPanel.BackgroundColor3=Color3.fromRGB(35,35,42); S.playingPanel.BorderSizePixel=0; S.playingPanel.Visible=false; S.playingPanel.Parent=S.SettingsPanel; S.playingPanel.ZIndex=11
    S.playingSongLabel=Instance.new("TextLabel"); S.playingSongLabel.Size=UDim2.new(1,-20,0,25); S.playingSongLabel.Position=UDim2.new(0,10,0,5); S.playingSongLabel.BackgroundTransparency=1; S.playingSongLabel.Text='Now Playing: <font color="#888888">Nothing</font>'; S.playingSongLabel.TextColor3=Color3.fromRGB(200,200,220); S.playingSongLabel.Font=Enum.Font.GothamBold; S.playingSongLabel.TextSize=12; S.playingSongLabel.TextTruncate=Enum.TextTruncate.AtEnd; S.playingSongLabel.TextXAlignment=Enum.TextXAlignment.Left; S.playingSongLabel.RichText=true; S.playingSongLabel.Parent=S.playingPanel
    S.soundEffectScrollFrame=Instance.new("ScrollingFrame"); S.soundEffectScrollFrame.Size=UDim2.new(1,-10,1,-40); S.soundEffectScrollFrame.Position=UDim2.new(0,5,0,35); S.soundEffectScrollFrame.BackgroundTransparency=1; S.soundEffectScrollFrame.BorderSizePixel=0; S.soundEffectScrollFrame.ScrollBarThickness=6; S.soundEffectScrollFrame.CanvasSize=UDim2.new(0,0,0,0); S.soundEffectScrollFrame.Parent=S.playingPanel
    settingsTabBtn.MouseButton1Click:Connect(function() S.playingTabOpen=false; S.SettingsScrollFrame.Visible=true; S.playingPanel.Visible=false; settingsTabBtn.BackgroundColor3=Color3.fromRGB(100,150,255); playingTabBtn.BackgroundColor3=Color3.fromRGB(60,60,70) end)
    playingTabBtn.MouseButton1Click:Connect(function() S.playingTabOpen=true; S.SettingsScrollFrame.Visible=false; S.playingPanel.Visible=true; playingTabBtn.BackgroundColor3=Color3.fromRGB(100,150,255); settingsTabBtn.BackgroundColor3=Color3.fromRGB(60,60,70); if S.playingSongLabel then S.playingSongLabel.Text=S.currentSongName~="" and 'Now Playing: <font color="#ff9944">'..S.currentSongName..'</font>' or 'Now Playing: <font color="#888888">Nothing</font>' end; updateSoundEffectList() end)
    
    -- Info Panel: HOW TO USE + DATA
    S.InfoPanel=Instance.new("Frame"); S.InfoPanel.Size=UDim2.new(0,280,1,0); S.InfoPanel.Position=UDim2.new(0,-290,0,0); S.InfoPanel.BackgroundColor3=Color3.fromRGB(30,35,40); S.InfoPanel.BorderSizePixel=0; S.InfoPanel.Visible=false; S.InfoPanel.Parent=S.MainFrame; S.InfoPanel.ZIndex=10; Instance.new("UICorner",S.InfoPanel).CornerRadius=UDim.new(0,8)
    S.InfoPanelStroke=Instance.new("UIStroke",S.InfoPanel); S.InfoPanelStroke.Thickness=3.5; S.InfoPanelStroke.Color=Color3.fromRGB(150,150,160); S.InfoPanelStroke.Transparency=0.5

    local infoTabs=Instance.new("Frame"); infoTabs.Size=UDim2.new(1,0,0,32); infoTabs.BackgroundColor3=Color3.fromRGB(40,45,50); infoTabs.BorderSizePixel=0; infoTabs.Parent=S.InfoPanel; infoTabs.ZIndex=11
    S.InfoHowTab=Instance.new("TextButton"); S.InfoHowTab.Size=UDim2.new(0.5,-2,1,0); S.InfoHowTab.Position=UDim2.new(0,0,0,0); S.InfoHowTab.BackgroundColor3=Color3.fromRGB(100,150,255); S.InfoHowTab.BorderSizePixel=0; S.InfoHowTab.Text="📖 HOW TO USE"; S.InfoHowTab.TextColor3=Color3.fromRGB(255,255,255); S.InfoHowTab.Font=Enum.Font.GothamBold; S.InfoHowTab.TextSize=11; S.InfoHowTab.Parent=infoTabs; S.InfoHowTab.ZIndex=12; Instance.new("UICorner",S.InfoHowTab).CornerRadius=UDim.new(0,6)
    S.InfoDataTab=Instance.new("TextButton"); S.InfoDataTab.Size=UDim2.new(0.5,-2,1,0); S.InfoDataTab.Position=UDim2.new(0.5,2,0,0); S.InfoDataTab.BackgroundColor3=Color3.fromRGB(60,65,72); S.InfoDataTab.BorderSizePixel=0; S.InfoDataTab.Text="📊 DATA"; S.InfoDataTab.TextColor3=Color3.fromRGB(255,255,255); S.InfoDataTab.Font=Enum.Font.GothamBold; S.InfoDataTab.TextSize=11; S.InfoDataTab.Parent=infoTabs; S.InfoDataTab.ZIndex=12; Instance.new("UICorner",S.InfoDataTab).CornerRadius=UDim.new(0,6)

    S.InfoHowFrame=Instance.new("ScrollingFrame"); S.InfoHowFrame.Size=UDim2.new(1,-20,1,-42); S.InfoHowFrame.Position=UDim2.new(0,10,0,38); S.InfoHowFrame.BackgroundColor3=Color3.fromRGB(35,40,45); S.InfoHowFrame.BorderSizePixel=0; S.InfoHowFrame.ScrollBarThickness=8; S.InfoHowFrame.CanvasSize=UDim2.new(0,0,0,0); S.InfoHowFrame.Parent=S.InfoPanel; Instance.new("UICorner",S.InfoHowFrame).CornerRadius=UDim.new(0,6)

    local howText=Instance.new("TextLabel"); howText.Size=UDim2.new(1,-20,0,650); howText.Position=UDim2.new(0,10,0,10); howText.BackgroundTransparency=1
    howText.Text=[[<b>STEPS TO PLAY MUSIC:</b>
<font color="#ff4444">1. UPLOAD</font> <font color="#ffffff">a music from</font> <font color="#ff4444">GitHub</font>
<font color="#ff4444">2. RAW</font> <font color="#ffffff">the uploaded music link</font>
<font color="#ff4444">3. PASTE</font> <font color="#ffffff">the raw GitHub link</font>

<b>PLAYLIST:</b>
<font color="#ffffff">Enter the secret key in the</font>
<font color="#f1c40f">key textbox</font> <font color="#ffffff">to unlock!</font>

<b>EXTRA MINI MODE:</b>
<font color="#ffffff">Compact player with image!</font>

<b>LOOP MODES (Extra Mini):</b>
<font color="#ff4444">RED = No Loop</font>
<font color="#44ff44">GREEN = Single Loop</font>
<font color="#ff9944">ORANGE = Playlist Auto-Next</font>

<b>SOUND EFFECTS:</b> Settings > Playing tab

<b>KEYBINDS (PC):</b>
<font color="#ff9944">H</font> - Hide/Show all GUIs
<font color="#ff9944">P</font> - Play/Pause music
<font color="#ff9944">S</font> - Stop music
<font color="#ff9944">M</font> - Mute/Unmute game sounds
<font color="#ff9944">L</font> - Toggle loop ON/OFF

<b>MOBILE:</b> Use Hide button on player
Green Show button to restore

<font color="#9b59b6">DISCORD LINK:</font>
<font color="#3498db">https://discord.gg/hTEvZ3nkZd</font>]]
    howText.TextColor3=Color3.fromRGB(200,220,240); howText.TextXAlignment=Enum.TextXAlignment.Left; howText.TextYAlignment=Enum.TextYAlignment.Top; howText.Font=Enum.Font.Gotham; howText.TextSize=13; howText.TextWrapped=true; howText.RichText=true; howText.Parent=S.InfoHowFrame
    howText:GetPropertyChangedSignal("TextBounds"):Connect(function() S.InfoHowFrame.CanvasSize=UDim2.new(0,0,0,howText.TextBounds.Y+20) end)

    S.InfoDataFrame=Instance.new("Frame"); S.InfoDataFrame.Size=UDim2.new(1,-20,1,-42); S.InfoDataFrame.Position=UDim2.new(0,10,0,38); S.InfoDataFrame.BackgroundColor3=Color3.fromRGB(35,40,45); S.InfoDataFrame.BorderSizePixel=0; S.InfoDataFrame.Visible=false; S.InfoDataFrame.Parent=S.InfoPanel; Instance.new("UICorner",S.InfoDataFrame).CornerRadius=UDim.new(0,6)

    local dataTitle=Instance.new("TextLabel"); dataTitle.Size=UDim2.new(1,-20,0,25); dataTitle.Position=UDim2.new(0,10,0,8); dataTitle.BackgroundTransparency=1; dataTitle.Text="TOP 3 COMPLETED PLAYS"; dataTitle.TextColor3=Color3.fromRGB(255,255,255); dataTitle.Font=Enum.Font.GothamBold; dataTitle.TextSize=12; dataTitle.TextXAlignment=Enum.TextXAlignment.Left; dataTitle.Parent=S.InfoDataFrame

    S.DataEmptyLabel=Instance.new("TextLabel"); S.DataEmptyLabel.Size=UDim2.new(1,-20,0,70); S.DataEmptyLabel.Position=UDim2.new(0,10,0,45); S.DataEmptyLabel.BackgroundTransparency=1; S.DataEmptyLabel.Text="No completed songs yet.\nA play is counted only when the song reaches Ended."; S.DataEmptyLabel.TextColor3=Color3.fromRGB(160,170,180); S.DataEmptyLabel.Font=Enum.Font.Gotham; S.DataEmptyLabel.TextSize=11; S.DataEmptyLabel.TextWrapped=true; S.DataEmptyLabel.Parent=S.InfoDataFrame

    S.DataLastUpdatedLabel=Instance.new("TextLabel"); S.DataLastUpdatedLabel.Size=UDim2.new(1,-20,0,18); S.DataLastUpdatedLabel.Position=UDim2.new(0,10,1,-70); S.DataLastUpdatedLabel.BackgroundTransparency=1; S.DataLastUpdatedLabel.Text="Updated: --:--:--"; S.DataLastUpdatedLabel.TextColor3=Color3.fromRGB(140,150,160); S.DataLastUpdatedLabel.Font=Enum.Font.Gotham; S.DataLastUpdatedLabel.TextSize=9; S.DataLastUpdatedLabel.TextXAlignment=Enum.TextXAlignment.Left; S.DataLastUpdatedLabel.Parent=S.InfoDataFrame

    S.DataRefreshButton=Instance.new("TextButton"); S.DataRefreshButton.Size=UDim2.new(0,78,0,27); S.DataRefreshButton.Position=UDim2.new(1,-88,1,-76); S.DataRefreshButton.BackgroundColor3=Color3.fromRGB(80,140,210); S.DataRefreshButton.BorderSizePixel=0; S.DataRefreshButton.Text="↻ REFRESH"; S.DataRefreshButton.TextColor3=Color3.fromRGB(255,255,255); S.DataRefreshButton.Font=Enum.Font.GothamBold; S.DataRefreshButton.TextSize=9; S.DataRefreshButton.Parent=S.InfoDataFrame; Instance.new("UICorner",S.DataRefreshButton).CornerRadius=UDim.new(0,5)

    local intervalTitle=Instance.new("TextLabel"); intervalTitle.Size=UDim2.new(1,-20,0,18); intervalTitle.Position=UDim2.new(0,10,1,-43); intervalTitle.BackgroundTransparency=1; intervalTitle.Text="Auto refresh interval"; intervalTitle.TextColor3=Color3.fromRGB(190,200,210); intervalTitle.Font=Enum.Font.Gotham; intervalTitle.TextSize=9; intervalTitle.TextXAlignment=Enum.TextXAlignment.Left; intervalTitle.Parent=S.InfoDataFrame

    S.DataIntervalSlider=Instance.new("Frame"); S.DataIntervalSlider.Size=UDim2.new(1,-110,0,8); S.DataIntervalSlider.Position=UDim2.new(0,10,1,-22); S.DataIntervalSlider.BackgroundColor3=Color3.fromRGB(65,70,78); S.DataIntervalSlider.BorderSizePixel=0; S.DataIntervalSlider.Active=true; S.DataIntervalSlider.Parent=S.InfoDataFrame; Instance.new("UICorner",S.DataIntervalSlider).CornerRadius=UDim.new(0,4)
    S.DataIntervalFill=Instance.new("Frame"); S.DataIntervalFill.Size=UDim2.new(0.18,0,1,0); S.DataIntervalFill.BackgroundColor3=Color3.fromRGB(100,180,255); S.DataIntervalFill.BorderSizePixel=0; S.DataIntervalFill.Parent=S.DataIntervalSlider; Instance.new("UICorner",S.DataIntervalFill).CornerRadius=UDim.new(0,4)
    local intervalButton=Instance.new("TextButton"); intervalButton.Size=UDim2.new(1,0,1,0); intervalButton.BackgroundTransparency=1; intervalButton.Text=""; intervalButton.Parent=S.DataIntervalSlider
    S.DataIntervalLabel=Instance.new("TextLabel"); S.DataIntervalLabel.Size=UDim2.new(0,82,0,18); S.DataIntervalLabel.Position=UDim2.new(1,-88,1,-27); S.DataIntervalLabel.BackgroundTransparency=1; S.DataIntervalLabel.Text="Auto refresh: 15s"; S.DataIntervalLabel.TextColor3=Color3.fromRGB(120,220,255); S.DataIntervalLabel.Font=Enum.Font.GothamBold; S.DataIntervalLabel.TextSize=9; S.DataIntervalLabel.TextXAlignment=Enum.TextXAlignment.Right; S.DataIntervalLabel.Parent=S.InfoDataFrame

    intervalButton.MouseButton1Down:Connect(function()
        S.isDraggingDataInterval=true
        local mx=mouse.X-S.DataIntervalSlider.AbsolutePosition.X
        local frac=math.clamp(mx/S.DataIntervalSlider.AbsoluteSize.X,0,1)
        setDataRefreshInterval(5+frac*55)
    end)

    S.InfoHowTab.MouseButton1Click:Connect(function()
        S.InfoHowFrame.Visible=true; S.InfoDataFrame.Visible=false
        S.InfoHowTab.BackgroundColor3=Color3.fromRGB(100,150,255); S.InfoDataTab.BackgroundColor3=Color3.fromRGB(60,65,72)
    end)

    S.InfoDataTab.MouseButton1Click:Connect(function()
        S.InfoHowFrame.Visible=false; S.InfoDataFrame.Visible=true
        S.InfoHowTab.BackgroundColor3=Color3.fromRGB(60,65,72); S.InfoDataTab.BackgroundColor3=Color3.fromRGB(100,150,255)
        updateDataPanel()
    end)

    S.DataRefreshButton.MouseButton1Click:Connect(function()
        updateDataPanel()
    end)

    S.ContentFrame=Instance.new("Frame"); S.ContentFrame.Size=UDim2.new(1,-20,1,-55); S.ContentFrame.Position=UDim2.new(0,10,0,45); S.ContentFrame.BackgroundTransparency=1; S.ContentFrame.Parent=S.MainFrame
    local ul=Instance.new("TextLabel"); ul.Size=UDim2.new(1,0,0,18); ul.BackgroundTransparency=1; ul.Text="GitHub MP3 URL:"; ul.TextColor3=Color3.fromRGB(255,255,255); ul.TextXAlignment=Enum.TextXAlignment.Left; ul.Font=Enum.Font.Gotham; ul.TextSize=12; ul.Parent=S.ContentFrame
    S.UrlContainer=Instance.new("Frame"); S.UrlContainer.Size=UDim2.new(1,0,0,32); S.UrlContainer.Position=UDim2.new(0,0,0,22); S.UrlContainer.BackgroundColor3=Color3.fromRGB(60,60,60); S.UrlContainer.BorderSizePixel=0; S.UrlContainer.ClipsDescendants=true; S.UrlContainer.Parent=S.ContentFrame; Instance.new("UICorner",S.UrlContainer).CornerRadius=UDim.new(0,6)
    local usf=Instance.new("ScrollingFrame"); usf.Size=UDim2.new(1,0,1,0); usf.BackgroundTransparency=1; usf.BorderSizePixel=0; usf.ScrollBarThickness=8; usf.VerticalScrollBarInset=Enum.ScrollBarInset.None; usf.HorizontalScrollBarInset=Enum.ScrollBarInset.Always; usf.CanvasSize=UDim2.new(0,0,0,0); usf.ElasticBehavior=Enum.ElasticBehavior.Never; usf.ScrollingDirection=Enum.ScrollingDirection.X; usf.Parent=S.UrlContainer
    S.UrlTextBox=Instance.new("TextBox"); S.UrlTextBox.Size=UDim2.new(1,0,1,0); S.UrlTextBox.Position=UDim2.new(0,5,0,0); S.UrlTextBox.BackgroundTransparency=1; S.UrlTextBox.Text=""; S.UrlTextBox.PlaceholderText="https://github.com/.../audio.mp3"; S.UrlTextBox.TextColor3=Color3.fromRGB(255,255,255); S.UrlTextBox.Font=Enum.Font.Gotham; S.UrlTextBox.TextSize=12; S.UrlTextBox.ClearTextOnFocus=false; S.UrlTextBox.TextXAlignment=Enum.TextXAlignment.Left; S.UrlTextBox.TextWrapped=false; S.UrlTextBox.Parent=usf
    
    local cb=Instance.new("Frame"); cb.Size=UDim2.new(1,0,0,35); cb.Position=UDim2.new(0,0,0,60); cb.BackgroundTransparency=1; cb.Parent=S.ContentFrame
    S.PlayButton=Instance.new("TextButton"); S.PlayButton.Size=UDim2.new(0.31,0,1,0); S.PlayButton.BackgroundColor3=Color3.fromRGB(70,180,70); S.PlayButton.BorderSizePixel=0; S.PlayButton.Text="▶ PLAY"; S.PlayButton.TextColor3=Color3.fromRGB(255,255,255); S.PlayButton.Font=Enum.Font.GothamBold; S.PlayButton.TextSize=13; S.PlayButton.Parent=cb; Instance.new("UICorner",S.PlayButton).CornerRadius=UDim.new(0,6)
    S.PauseButton=Instance.new("TextButton"); S.PauseButton.Size=UDim2.new(0.31,0,1,0); S.PauseButton.Position=UDim2.new(0.345,0,0,0); S.PauseButton.BackgroundColor3=Color3.fromRGB(255,180,50); S.PauseButton.BorderSizePixel=0; S.PauseButton.Text="⏸ PAUSE"; S.PauseButton.TextColor3=Color3.fromRGB(255,255,255); S.PauseButton.Font=Enum.Font.GothamBold; S.PauseButton.TextSize=13; S.PauseButton.Parent=cb; Instance.new("UICorner",S.PauseButton).CornerRadius=UDim.new(0,6)
    S.StopButton=Instance.new("TextButton"); S.StopButton.Size=UDim2.new(0.31,0,1,0); S.StopButton.Position=UDim2.new(0.69,0,0,0); S.StopButton.BackgroundColor3=Color3.fromRGB(200,70,70); S.StopButton.BorderSizePixel=0; S.StopButton.Text="⏹ STOP"; S.StopButton.TextColor3=Color3.fromRGB(255,255,255); S.StopButton.Font=Enum.Font.GothamBold; S.StopButton.TextSize=13; S.StopButton.Parent=cb; Instance.new("UICorner",S.StopButton).CornerRadius=UDim.new(0,6)
    
    local tf=Instance.new("Frame"); tf.Size=UDim2.new(1,0,0,35); tf.Position=UDim2.new(0,0,0,100); tf.BackgroundTransparency=1; tf.Parent=S.ContentFrame
    S.TimeLabel=Instance.new("TextLabel"); S.TimeLabel.Size=UDim2.new(1,-5,0,15); S.TimeLabel.Position=UDim2.new(0,0,0,0); S.TimeLabel.BackgroundTransparency=1; S.TimeLabel.Text="0:00 / 0:00"; S.TimeLabel.TextColor3=Color3.fromRGB(200,200,200); S.TimeLabel.TextXAlignment=Enum.TextXAlignment.Left; S.TimeLabel.Font=Enum.Font.Gotham; S.TimeLabel.TextSize=11; S.TimeLabel.TextTruncate=Enum.TextTruncate.AtEnd; S.TimeLabel.Parent=tf
    S.TimeSliderBg=Instance.new("Frame"); S.TimeSliderBg.Size=UDim2.new(1,0,0,8); S.TimeSliderBg.Position=UDim2.new(0,0,0,18); S.TimeSliderBg.BackgroundColor3=Color3.fromRGB(60,60,60); S.TimeSliderBg.BorderSizePixel=0; S.TimeSliderBg.Active=true; S.TimeSliderBg.Parent=tf; Instance.new("UICorner",S.TimeSliderBg).CornerRadius=UDim.new(0,4)
    S.TimeSlider=Instance.new("Frame"); S.TimeSlider.Size=UDim2.new(0,0,1,0); S.TimeSlider.BackgroundColor3=Color3.fromRGB(100,180,255); S.TimeSlider.BorderSizePixel=0; S.TimeSlider.Parent=S.TimeSliderBg; Instance.new("UICorner",S.TimeSlider).CornerRadius=UDim.new(0,4)
    local tsca=Instance.new("ImageButton"); tsca.Size=UDim2.new(1,0,1,0); tsca.BackgroundTransparency=1; tsca.Image="rbxassetid://0"; tsca.ImageTransparency=1; tsca.BorderSizePixel=0; tsca.ZIndex=5; tsca.Parent=S.TimeSliderBg
    tsca.MouseButton1Down:Connect(function() S.isDraggingTimeSlider=true; if S.currentSound and S.currentSound.TimeLength>0 then local mx=mouse.X-S.TimeSliderBg.AbsolutePosition.X; local frac=math.clamp(mx/S.TimeSliderBg.AbsoluteSize.X,0,1); S.currentSound.TimePosition=frac*S.currentSound.TimeLength; if S.isPaused then S.pausedTimePosition=S.currentSound.TimePosition end; updateTimeDisplay() end end)
    
    S.HistoryButton=Instance.new("TextButton"); S.HistoryButton.Size=UDim2.new(1,0,0,25); S.HistoryButton.Position=UDim2.new(0,0,0,140); S.HistoryButton.BackgroundColor3=Color3.fromRGB(100,100,200); S.HistoryButton.BorderSizePixel=0; S.HistoryButton.Text="→ HISTORY"; S.HistoryButton.TextColor3=Color3.fromRGB(255,255,255); S.HistoryButton.Font=Enum.Font.GothamBold; S.HistoryButton.TextSize=12; S.HistoryButton.Parent=S.ContentFrame; Instance.new("UICorner",S.HistoryButton).CornerRadius=UDim.new(0,6)
    
    local tgf=Instance.new("Frame"); tgf.Size=UDim2.new(1,0,0,28); tgf.Position=UDim2.new(0,0,0,170); tgf.BackgroundTransparency=1; tgf.Parent=S.ContentFrame; local bw,sp=0.32,0.02
    S.MuteToggle=Instance.new("TextButton"); S.MuteToggle.Size=UDim2.new(bw,0,0,28); S.MuteToggle.Position=UDim2.new(0,0,0,0); S.MuteToggle.BackgroundColor3=Color3.fromRGB(180,80,80); S.MuteToggle.BorderSizePixel=0; S.MuteToggle.Text="🔇 MUTE GAME"; S.MuteToggle.TextColor3=Color3.fromRGB(255,255,255); S.MuteToggle.Font=Enum.Font.Gotham; S.MuteToggle.TextSize=10; S.MuteToggle.Parent=tgf; Instance.new("UICorner",S.MuteToggle).CornerRadius=UDim.new(0,6)
    
    S.SecretKeyContainer=Instance.new("Frame"); S.SecretKeyContainer.Size=UDim2.new(bw,0,0,28); S.SecretKeyContainer.Position=UDim2.new(bw+sp,0,0,0); S.SecretKeyContainer.BackgroundColor3=Color3.fromRGB(60,60,70); S.SecretKeyContainer.BorderSizePixel=0; S.SecretKeyContainer.ClipsDescendants=true; S.SecretKeyContainer.Parent=tgf; Instance.new("UICorner",S.SecretKeyContainer).CornerRadius=UDim.new(0,6)
    local sksf=Instance.new("ScrollingFrame"); sksf.Size=UDim2.new(1,0,1,0); sksf.BackgroundTransparency=1; sksf.BorderSizePixel=0; sksf.ScrollBarThickness=5; sksf.VerticalScrollBarInset=Enum.ScrollBarInset.None; sksf.HorizontalScrollBarInset=Enum.ScrollBarInset.Always; sksf.CanvasSize=UDim2.new(0,0,0,0); sksf.ElasticBehavior=Enum.ElasticBehavior.Never; sksf.ScrollingDirection=Enum.ScrollingDirection.X; sksf.Parent=S.SecretKeyContainer
    S.SecretKeyTextBox=Instance.new("TextBox"); S.SecretKeyTextBox.Size=UDim2.new(1,0,1,0); S.SecretKeyTextBox.Position=UDim2.new(0,3,0,0); S.SecretKeyTextBox.BackgroundTransparency=1; S.SecretKeyTextBox.Text=""; S.SecretKeyTextBox.PlaceholderText=""; S.SecretKeyTextBox.PlaceholderColor3=Color3.fromRGB(150,150,160); S.SecretKeyTextBox.TextColor3=Color3.fromRGB(255,255,255); S.SecretKeyTextBox.Font=Enum.Font.Gotham; S.SecretKeyTextBox.TextSize=9; S.SecretKeyTextBox.ClearTextOnFocus=false; S.SecretKeyTextBox.TextXAlignment=Enum.TextXAlignment.Left; S.SecretKeyTextBox.TextWrapped=false; S.SecretKeyTextBox.Parent=sksf
    S.SecretKeyTextBox.FocusLost:Connect(function(ep) if ep and S.SecretKeyTextBox.Text~="" then checkSecretKey(S.SecretKeyTextBox.Text) end end)
    
    S.LoopToggle=Instance.new("TextButton"); S.LoopToggle.Size=UDim2.new(bw,0,0,28); S.LoopToggle.Position=UDim2.new(bw*2+sp*2,0,0,0); S.LoopToggle.BackgroundColor3=Color3.fromRGB(70,180,70); S.LoopToggle.BorderSizePixel=0; S.LoopToggle.Text="🔁 LOOP: ON"; S.LoopToggle.TextColor3=Color3.fromRGB(255,255,255); S.LoopToggle.Font=Enum.Font.Gotham; S.LoopToggle.TextSize=11; S.LoopToggle.Parent=tgf; Instance.new("UICorner",S.LoopToggle).CornerRadius=UDim.new(0,6)
    
    local vf=Instance.new("Frame"); vf.Size=UDim2.new(1,0,0,35); vf.Position=UDim2.new(0,0,0,205); vf.BackgroundTransparency=1; vf.Parent=S.ContentFrame
    S.VolumeLabel=Instance.new("TextLabel"); S.VolumeLabel.Size=UDim2.new(0,80,0,18); S.VolumeLabel.BackgroundTransparency=1; S.VolumeLabel.Text="Volume: 1.00"; S.VolumeLabel.TextColor3=Color3.fromRGB(255,255,255); S.VolumeLabel.TextXAlignment=Enum.TextXAlignment.Left; S.VolumeLabel.Font=Enum.Font.Gotham; S.VolumeLabel.TextSize=12; S.VolumeLabel.Parent=vf
    S.VolumeTextBox=Instance.new("TextBox"); S.VolumeTextBox.Size=UDim2.new(1,-130,0,22); S.VolumeTextBox.Position=UDim2.new(0,85,0,6); S.VolumeTextBox.BackgroundColor3=Color3.fromRGB(60,60,70); S.VolumeTextBox.BorderSizePixel=0; S.VolumeTextBox.Text="1.00"; S.VolumeTextBox.TextColor3=Color3.fromRGB(255,255,255); S.VolumeTextBox.Font=Enum.Font.GothamBold; S.VolumeTextBox.TextSize=12; S.VolumeTextBox.TextXAlignment=Enum.TextXAlignment.Center; S.VolumeTextBox.PlaceholderText="0-100"; S.VolumeTextBox.PlaceholderColor3=Color3.fromRGB(150,150,150); S.VolumeTextBox.Parent=vf; Instance.new("UICorner",S.VolumeTextBox).CornerRadius=UDim.new(0,5)
    S.VolumeDownButton=Instance.new("TextButton"); S.VolumeDownButton.Size=UDim2.new(0,20,0,22); S.VolumeDownButton.Position=UDim2.new(1,-40,0,6); S.VolumeDownButton.BackgroundColor3=Color3.fromRGB(100,100,180); S.VolumeDownButton.BorderSizePixel=0; S.VolumeDownButton.Text="<"; S.VolumeDownButton.TextColor3=Color3.fromRGB(255,255,255); S.VolumeDownButton.Font=Enum.Font.GothamBold; S.VolumeDownButton.TextSize=14; S.VolumeDownButton.AutoButtonColor=true; S.VolumeDownButton.Parent=vf; Instance.new("UICorner",S.VolumeDownButton).CornerRadius=UDim.new(0,5)
    S.VolumeUpButton=Instance.new("TextButton"); S.VolumeUpButton.Size=UDim2.new(0,20,0,22); S.VolumeUpButton.Position=UDim2.new(1,-15,0,6); S.VolumeUpButton.BackgroundColor3=Color3.fromRGB(100,100,180); S.VolumeUpButton.BorderSizePixel=0; S.VolumeUpButton.Text=">"; S.VolumeUpButton.TextColor3=Color3.fromRGB(255,255,255); S.VolumeUpButton.Font=Enum.Font.GothamBold; S.VolumeUpButton.TextSize=14; S.VolumeUpButton.AutoButtonColor=true; S.VolumeUpButton.Parent=vf; Instance.new("UICorner",S.VolumeUpButton).CornerRadius=UDim.new(0,5)
    
    local sf=Instance.new("Frame"); sf.Size=UDim2.new(1,0,0,35); sf.Position=UDim2.new(0,0,0,245); sf.BackgroundTransparency=1; sf.Parent=S.ContentFrame
    S.SpeedLabel=Instance.new("TextLabel"); S.SpeedLabel.Size=UDim2.new(0,80,0,18); S.SpeedLabel.BackgroundTransparency=1; S.SpeedLabel.Text="Speed: 1.00x"; S.SpeedLabel.TextColor3=Color3.fromRGB(255,255,255); S.SpeedLabel.TextXAlignment=Enum.TextXAlignment.Left; S.SpeedLabel.Font=Enum.Font.Gotham; S.SpeedLabel.TextSize=12; S.SpeedLabel.Parent=sf
    S.SpeedTextBox=Instance.new("TextBox"); S.SpeedTextBox.Size=UDim2.new(1,-130,0,22); S.SpeedTextBox.Position=UDim2.new(0,85,0,6); S.SpeedTextBox.BackgroundColor3=Color3.fromRGB(60,60,70); S.SpeedTextBox.BorderSizePixel=0; S.SpeedTextBox.Text="1.00x"; S.SpeedTextBox.TextColor3=Color3.fromRGB(255,255,255); S.SpeedTextBox.Font=Enum.Font.GothamBold; S.SpeedTextBox.TextSize=12; S.SpeedTextBox.TextXAlignment=Enum.TextXAlignment.Center; S.SpeedTextBox.PlaceholderText="0-100"; S.SpeedTextBox.PlaceholderColor3=Color3.fromRGB(150,150,150); S.SpeedTextBox.Parent=sf; Instance.new("UICorner",S.SpeedTextBox).CornerRadius=UDim.new(0,5)
    S.SpeedDownButton=Instance.new("TextButton"); S.SpeedDownButton.Size=UDim2.new(0,20,0,22); S.SpeedDownButton.Position=UDim2.new(1,-40,0,6); S.SpeedDownButton.BackgroundColor3=Color3.fromRGB(100,100,180); S.SpeedDownButton.BorderSizePixel=0; S.SpeedDownButton.Text="<"; S.SpeedDownButton.TextColor3=Color3.fromRGB(255,255,255); S.SpeedDownButton.Font=Enum.Font.GothamBold; S.SpeedDownButton.TextSize=14; S.SpeedDownButton.AutoButtonColor=true; S.SpeedDownButton.Parent=sf; Instance.new("UICorner",S.SpeedDownButton).CornerRadius=UDim.new(0,5)
    S.SpeedUpButton=Instance.new("TextButton"); S.SpeedUpButton.Size=UDim2.new(0,20,0,22); S.SpeedUpButton.Position=UDim2.new(1,-15,0,6); S.SpeedUpButton.BackgroundColor3=Color3.fromRGB(100,100,180); S.SpeedUpButton.BorderSizePixel=0; S.SpeedUpButton.Text=">"; S.SpeedUpButton.TextColor3=Color3.fromRGB(255,255,255); S.SpeedUpButton.Font=Enum.Font.GothamBold; S.SpeedUpButton.TextSize=14; S.SpeedUpButton.AutoButtonColor=true; S.SpeedUpButton.Parent=sf; Instance.new("UICorner",S.SpeedUpButton).CornerRadius=UDim.new(0,5)
    
    S.StatusLabel=Instance.new("TextLabel"); S.StatusLabel.Size=UDim2.new(1,0,0,18); S.StatusLabel.Position=UDim2.new(0,0,1,-22); S.StatusLabel.BackgroundTransparency=1; S.StatusLabel.Text="Ready to play music"; S.StatusLabel.TextColor3=Color3.fromRGB(200,200,200); S.StatusLabel.TextXAlignment=Enum.TextXAlignment.Center; S.StatusLabel.Font=Enum.Font.Gotham; S.StatusLabel.TextSize=11; S.StatusLabel.Parent=S.ContentFrame
    
    -- History Panel
    S.HistoryPanel=Instance.new("Frame"); S.HistoryPanel.Size=UDim2.new(1,0,1,0); S.HistoryPanel.Position=UDim2.new(1,0,0,0); S.HistoryPanel.BackgroundColor3=Color3.fromRGB(35,35,35); S.HistoryPanel.BorderSizePixel=0; S.HistoryPanel.Visible=false; S.HistoryPanel.Parent=S.ContentFrame; Instance.new("UICorner",S.HistoryPanel).CornerRadius=UDim.new(0,8)
    local htitle=Instance.new("TextLabel"); htitle.Size=UDim2.new(1,0,0,30); htitle.BackgroundColor3=Color3.fromRGB(50,50,50); htitle.BorderSizePixel=0; htitle.Text="DOWNLOAD HISTORY"; htitle.TextColor3=Color3.fromRGB(255,255,255); htitle.Font=Enum.Font.GothamBold; htitle.TextSize=14; htitle.Parent=S.HistoryPanel; Instance.new("UICorner",htitle).CornerRadius=UDim.new(0,8)
    S.BackButton=Instance.new("TextButton"); S.BackButton.Size=UDim2.new(0,80,0,25); S.BackButton.Position=UDim2.new(0,10,0,35); S.BackButton.BackgroundColor3=Color3.fromRGB(80,130,200); S.BackButton.BorderSizePixel=0; S.BackButton.Text="← BACK"; S.BackButton.TextColor3=Color3.fromRGB(255,255,255); S.BackButton.Font=Enum.Font.GothamBold; S.BackButton.TextSize=12; S.BackButton.Parent=S.HistoryPanel; Instance.new("UICorner",S.BackButton).CornerRadius=UDim.new(0,6); S.BackButton.MouseButton1Click:Connect(function() toggleHistoryPanel() end)
    S.HistoryScrollFrame=Instance.new("ScrollingFrame"); S.HistoryScrollFrame.Size=UDim2.new(1,-20,1,-70); S.HistoryScrollFrame.Position=UDim2.new(0,10,0,70); S.HistoryScrollFrame.BackgroundColor3=Color3.fromRGB(45,45,45); S.HistoryScrollFrame.BorderSizePixel=0; S.HistoryScrollFrame.ScrollBarThickness=8; S.HistoryScrollFrame.CanvasSize=UDim2.new(0,0,0,0); S.HistoryScrollFrame.Parent=S.HistoryPanel; Instance.new("UICorner",S.HistoryScrollFrame).CornerRadius=UDim.new(0,6)
    S.NoHistoryLabel=Instance.new("TextLabel"); S.NoHistoryLabel.Size=UDim2.new(1,0,0,50); S.NoHistoryLabel.Position=UDim2.new(0,0,0.5,-25); S.NoHistoryLabel.BackgroundTransparency=1; S.NoHistoryLabel.Text="No download history yet"; S.NoHistoryLabel.TextColor3=Color3.fromRGB(150,150,150); S.NoHistoryLabel.Font=Enum.Font.Gotham; S.NoHistoryLabel.TextSize=12; S.NoHistoryLabel.TextWrapped=true; S.NoHistoryLabel.Visible=true; S.NoHistoryLabel.Parent=S.HistoryScrollFrame
    
    -- Search Panel
    S.SearchPanel=Instance.new("Frame"); S.SearchPanel.Size=UDim2.new(0,300,1,0); S.SearchPanel.Position=UDim2.new(1,10,0,0); S.SearchPanel.BackgroundColor3=Color3.fromRGB(35,35,45); S.SearchPanel.BorderSizePixel=0; S.SearchPanel.Visible=false; S.SearchPanel.Parent=S.MainFrame; S.SearchPanel.ZIndex=10; Instance.new("UICorner",S.SearchPanel).CornerRadius=UDim.new(0,8)
    S.SearchPanelStroke=Instance.new("UIStroke",S.SearchPanel); S.SearchPanelStroke.Thickness=3.5; S.SearchPanelStroke.Color=Color3.fromRGB(150,150,160); S.SearchPanelStroke.Transparency=0.5
    local tbf=Instance.new("Frame"); tbf.Size=UDim2.new(1,0,0,30); tbf.BackgroundTransparency=1; tbf.Parent=S.SearchPanel
    S.SearchTabBtn=Instance.new("TextButton"); S.SearchTabBtn.Size=UDim2.new(0.48,0,1,0); S.SearchTabBtn.BackgroundColor3=Color3.fromRGB(100,150,255); S.SearchTabBtn.BorderSizePixel=0; S.SearchTabBtn.Text="🔍 Search"; S.SearchTabBtn.TextColor3=Color3.fromRGB(255,255,255); S.SearchTabBtn.Font=Enum.Font.GothamBold; S.SearchTabBtn.TextSize=12; S.SearchTabBtn.Parent=tbf; Instance.new("UICorner",S.SearchTabBtn).CornerRadius=UDim.new(0,6)
    S.PlaylistTabBtn=Instance.new("TextButton"); S.PlaylistTabBtn.Size=UDim2.new(0.48,0,1,0); S.PlaylistTabBtn.Position=UDim2.new(0.52,0,0,0); S.PlaylistTabBtn.BackgroundColor3=Color3.fromRGB(60,60,70); S.PlaylistTabBtn.BorderSizePixel=0; S.PlaylistTabBtn.Text="📋 Playlist"; S.PlaylistTabBtn.TextColor3=Color3.fromRGB(255,255,255); S.PlaylistTabBtn.Font=Enum.Font.GothamBold; S.PlaylistTabBtn.TextSize=12; S.PlaylistTabBtn.Parent=tbf; Instance.new("UICorner",S.PlaylistTabBtn).CornerRadius=UDim.new(0,6)
    local scf=Instance.new("Frame"); scf.Size=UDim2.new(1,0,1,-35); scf.Position=UDim2.new(0,0,0,35); scf.BackgroundTransparency=1; scf.Visible=true; scf.Parent=S.SearchPanel
    local sif=Instance.new("Frame"); sif.Size=UDim2.new(1,-20,0,40); sif.Position=UDim2.new(0,10,0,0); sif.BackgroundColor3=Color3.fromRGB(60,60,70); sif.BorderSizePixel=0; sif.ClipsDescendants=true; sif.Parent=scf; Instance.new("UICorner",sif).CornerRadius=UDim.new(0,6)
    local ssf2=Instance.new("ScrollingFrame"); ssf2.Size=UDim2.new(1,-40,1,0); ssf2.BackgroundTransparency=1; ssf2.BorderSizePixel=0; ssf2.ScrollBarThickness=6; ssf2.VerticalScrollBarInset=Enum.ScrollBarInset.None; ssf2.HorizontalScrollBarInset=Enum.ScrollBarInset.Always; ssf2.CanvasSize=UDim2.new(0,0,0,0); ssf2.ElasticBehavior=Enum.ElasticBehavior.Never; ssf2.ScrollingDirection=Enum.ScrollingDirection.X; ssf2.Parent=sif
    S.SearchTextBox=Instance.new("TextBox"); S.SearchTextBox.Size=UDim2.new(1,0,1,0); S.SearchTextBox.Position=UDim2.new(0,5,0,0); S.SearchTextBox.BackgroundTransparency=1; S.SearchTextBox.Text=""; S.SearchTextBox.PlaceholderText=""; S.SearchTextBox.PlaceholderColor3=Color3.fromRGB(180,180,180); S.SearchTextBox.TextColor3=Color3.fromRGB(255,255,255); S.SearchTextBox.Font=Enum.Font.Gotham; S.SearchTextBox.TextSize=12; S.SearchTextBox.ClearTextOnFocus=false; S.SearchTextBox.TextXAlignment=Enum.TextXAlignment.Left; S.SearchTextBox.TextWrapped=false; S.SearchTextBox.Parent=ssf2
    local spb=Instance.new("TextButton"); spb.Size=UDim2.new(0,30,0,30); spb.Position=UDim2.new(1,-35,0,5); spb.BackgroundColor3=Color3.fromRGB(100,150,255); spb.BorderSizePixel=0; spb.Text="🔍"; spb.TextColor3=Color3.fromRGB(255,255,255); spb.Font=Enum.Font.GothamBold; spb.TextSize=14; spb.Parent=sif; Instance.new("UICorner",spb).CornerRadius=UDim.new(0,4)
    local si=Instance.new("TextLabel"); si.Size=UDim2.new(1,-20,0,25); si.Position=UDim2.new(0,10,0,45); si.BackgroundTransparency=1; si.Text="Enter song name or full GitHub raw URL"; si.TextColor3=Color3.fromRGB(200,200,220); si.TextXAlignment=Enum.TextXAlignment.Left; si.TextWrapped=true; si.Font=Enum.Font.Gotham; si.TextSize=10; si.Parent=scf
    S.SearchScrollFrame=Instance.new("ScrollingFrame"); S.SearchScrollFrame.Size=UDim2.new(1,-20,1,-80); S.SearchScrollFrame.Position=UDim2.new(0,10,0,75); S.SearchScrollFrame.BackgroundColor3=Color3.fromRGB(45,45,55); S.SearchScrollFrame.BorderSizePixel=0; S.SearchScrollFrame.ScrollBarThickness=8; S.SearchScrollFrame.CanvasSize=UDim2.new(0,0,0,0); S.SearchScrollFrame.Parent=scf; Instance.new("UICorner",S.SearchScrollFrame).CornerRadius=UDim.new(0,6)
    S.SearchNoResultsLabel=Instance.new("TextLabel"); S.SearchNoResultsLabel.Size=UDim2.new(1,0,0,50); S.SearchNoResultsLabel.Position=UDim2.new(0,0,0.5,-25); S.SearchNoResultsLabel.BackgroundTransparency=1; S.SearchNoResultsLabel.Text="Enter a search term or URL"; S.SearchNoResultsLabel.TextColor3=Color3.fromRGB(150,150,160); S.SearchNoResultsLabel.Font=Enum.Font.Gotham; S.SearchNoResultsLabel.TextSize=12; S.SearchNoResultsLabel.TextWrapped=true; S.SearchNoResultsLabel.Visible=true; S.SearchNoResultsLabel.Parent=S.SearchScrollFrame
    local pcf=Instance.new("Frame"); pcf.Size=UDim2.new(1,0,1,-35); pcf.Position=UDim2.new(0,0,0,35); pcf.BackgroundTransparency=1; pcf.Visible=false; pcf.Parent=S.SearchPanel
    S.PlaylistScrollFrame=Instance.new("ScrollingFrame"); S.PlaylistScrollFrame.Size=UDim2.new(1,-20,1,-10); S.PlaylistScrollFrame.Position=UDim2.new(0,10,0,5); S.PlaylistScrollFrame.BackgroundColor3=Color3.fromRGB(45,45,55); S.PlaylistScrollFrame.BorderSizePixel=0; S.PlaylistScrollFrame.ScrollBarThickness=8; S.PlaylistScrollFrame.CanvasSize=UDim2.new(0,0,0,0); S.PlaylistScrollFrame.Parent=pcf; Instance.new("UICorner",S.PlaylistScrollFrame).CornerRadius=UDim.new(0,6)
    S.PlaylistNoResultsLabel=Instance.new("TextLabel"); S.PlaylistNoResultsLabel.Size=UDim2.new(1,0,0,50); S.PlaylistNoResultsLabel.Position=UDim2.new(0,0,0.5,-25); S.PlaylistNoResultsLabel.BackgroundTransparency=1; S.PlaylistNoResultsLabel.Text="Enter secret key!"; S.PlaylistNoResultsLabel.TextColor3=Color3.fromRGB(150,150,160); S.PlaylistNoResultsLabel.Font=Enum.Font.Gotham; S.PlaylistNoResultsLabel.TextSize=12; S.PlaylistNoResultsLabel.TextWrapped=true; S.PlaylistNoResultsLabel.Visible=true; S.PlaylistNoResultsLabel.Parent=S.PlaylistScrollFrame
    S.SearchTabBtn.MouseButton1Click:Connect(function() S.currentSearchTab="Search"; scf.Visible=true; pcf.Visible=false; local t=S.themes[S.currentTheme] or S.themes["Default"]; S.SearchTabBtn.BackgroundColor3=t.tabActive; S.PlaylistTabBtn.BackgroundColor3=t.tabInactive end)
    S.PlaylistTabBtn.MouseButton1Click:Connect(function() S.currentSearchTab="Playlist"; scf.Visible=false; pcf.Visible=true; local t=S.themes[S.currentTheme] or S.themes["Default"]; S.PlaylistTabBtn.BackgroundColor3=t.tabActive; S.SearchTabBtn.BackgroundColor3=t.tabInactive; updatePlaylistDisplay() end)
    
    -- Mini GUI
    S.MiniScreenGui=Instance.new("ScreenGui"); S.MiniScreenGui.Name="MusicPlayerMiniGUI"; S.MiniScreenGui.ResetOnSpawn=false; S.MiniScreenGui.ZIndexBehavior=Enum.ZIndexBehavior.Sibling; S.MiniScreenGui.Parent=CoreGui; S.MiniScreenGui.Enabled=false
    S.MiniFrame=Instance.new("Frame"); S.MiniFrame.Size=UDim2.new(0,360,0,120); S.MiniFrame.Position=UDim2.new(0.5,-180,0.1,0); S.MiniFrame.BackgroundColor3=Color3.fromRGB(40,40,40); S.MiniFrame.BorderSizePixel=0; S.MiniFrame.Active=true; S.MiniFrame.Draggable=true; S.MiniFrame.Parent=S.MiniScreenGui; Instance.new("UICorner",S.MiniFrame).CornerRadius=UDim.new(0,15)
    S.MiniOutlineFrame=Instance.new("Frame"); S.MiniOutlineFrame.Size=UDim2.new(1,6,1,6); S.MiniOutlineFrame.Position=UDim2.new(0,-3,0,-3); S.MiniOutlineFrame.BackgroundColor3=Color3.fromRGB(40,40,40); S.MiniOutlineFrame.BorderSizePixel=0; S.MiniOutlineFrame.ZIndex=0; S.MiniOutlineFrame.Parent=S.MiniFrame; Instance.new("UICorner",S.MiniOutlineFrame).CornerRadius=UDim.new(0,16)
    S.MiniUIStroke=Instance.new("UIStroke"); S.MiniUIStroke.Thickness=3; S.MiniUIStroke.Color=Color3.fromRGB(80,80,80); S.MiniUIStroke.Parent=S.MiniOutlineFrame
    spawn(function() local cl={Color3.fromRGB(255,50,50),Color3.fromRGB(255,150,50),Color3.fromRGB(255,255,50),Color3.fromRGB(50,255,50),Color3.fromRGB(50,150,255),Color3.fromRGB(150,50,255),Color3.fromRGB(255,50,255)}; local i=1; while S.MiniUIStroke and S.MiniUIStroke.Parent do TweenService:Create(S.MiniUIStroke,TweenInfo.new(2),{Color=cl[i]}):Play(); i=i+1; if i>#cl then i=1 end; wait(2) end end)
    S.MiniSongLabel=Instance.new("TextLabel"); S.MiniSongLabel.Size=UDim2.new(1,-60,0,25); S.MiniSongLabel.Position=UDim2.new(0,15,0,8); S.MiniSongLabel.BackgroundTransparency=1; S.MiniSongLabel.Text=""; S.MiniSongLabel.TextColor3=Color3.fromRGB(255,255,255); S.MiniSongLabel.TextXAlignment=Enum.TextXAlignment.Left; S.MiniSongLabel.Font=Enum.Font.GothamBold; S.MiniSongLabel.TextSize=14; S.MiniSongLabel.TextTruncate=Enum.TextTruncate.AtEnd; S.MiniSongLabel.Parent=S.MiniFrame
    S.MiniTimeLabel=Instance.new("TextLabel"); S.MiniTimeLabel.Size=UDim2.new(1,-60,0,18); S.MiniTimeLabel.Position=UDim2.new(0,15,0,35); S.MiniTimeLabel.BackgroundTransparency=1; S.MiniTimeLabel.Text="0:00 / 0:00"; S.MiniTimeLabel.TextColor3=Color3.fromRGB(200,200,200); S.MiniTimeLabel.TextXAlignment=Enum.TextXAlignment.Left; S.MiniTimeLabel.Font=Enum.Font.Gotham; S.MiniTimeLabel.TextSize=11; S.MiniTimeLabel.Parent=S.MiniFrame
    S.MiniTimeSliderBg=Instance.new("Frame"); S.MiniTimeSliderBg.Size=UDim2.new(1,-60,0,10); S.MiniTimeSliderBg.Position=UDim2.new(0,15,0,58); S.MiniTimeSliderBg.BackgroundColor3=Color3.fromRGB(60,60,60); S.MiniTimeSliderBg.BorderSizePixel=0; S.MiniTimeSliderBg.Active=true; S.MiniTimeSliderBg.Parent=S.MiniFrame; Instance.new("UICorner",S.MiniTimeSliderBg).CornerRadius=UDim.new(0,5)
    S.MiniTimeSlider=Instance.new("Frame"); S.MiniTimeSlider.Size=UDim2.new(0,0,1,0); S.MiniTimeSlider.BackgroundColor3=Color3.fromRGB(100,180,255); S.MiniTimeSlider.BorderSizePixel=0; S.MiniTimeSlider.Parent=S.MiniTimeSliderBg; Instance.new("UICorner",S.MiniTimeSlider).CornerRadius=UDim.new(0,5)
    local mtsca=Instance.new("ImageButton"); mtsca.Size=UDim2.new(1,0,1,0); mtsca.BackgroundTransparency=1; mtsca.Image="rbxassetid://0"; mtsca.ImageTransparency=1; mtsca.BorderSizePixel=0; mtsca.ZIndex=5; mtsca.Parent=S.MiniTimeSliderBg
    mtsca.MouseButton1Down:Connect(function() S.isDraggingMiniTimeSlider=true; if S.currentSound and S.currentSound.TimeLength>0 then local mx=mouse.X-S.MiniTimeSliderBg.AbsolutePosition.X; local frac=math.clamp(mx/S.MiniTimeSliderBg.AbsoluteSize.X,0,1); S.currentSound.TimePosition=frac*S.currentSound.TimeLength; if S.isPaused then S.pausedTimePosition=S.currentSound.TimePosition end; updateTimeDisplay() end end)
    local mbf=Instance.new("Frame"); mbf.Size=UDim2.new(0,160,0,35); mbf.Position=UDim2.new(0,15,0,75); mbf.BackgroundTransparency=1; mbf.Parent=S.MiniFrame
    S.MiniRewindImageButton=Instance.new("ImageButton"); S.MiniRewindImageButton.Size=UDim2.new(0,35,0,35); S.MiniRewindImageButton.Position=UDim2.new(0,0,0,0); S.MiniRewindImageButton.BackgroundTransparency=1; S.MiniRewindImageButton.BorderSizePixel=0; S.MiniRewindImageButton.Image="rbxassetid://122950454234379"; S.MiniRewindImageButton.Parent=mbf; Instance.new("UICorner",S.MiniRewindImageButton).CornerRadius=UDim.new(1,0)
    S.MiniPauseImageButton=Instance.new("ImageButton"); S.MiniPauseImageButton.Size=UDim2.new(0,35,0,35); S.MiniPauseImageButton.Position=UDim2.new(0,50,0,0); S.MiniPauseImageButton.BackgroundTransparency=1; S.MiniPauseImageButton.BorderSizePixel=0; S.MiniPauseImageButton.Image="rbxassetid://80704722265943"; S.MiniPauseImageButton.Parent=mbf; Instance.new("UICorner",S.MiniPauseImageButton).CornerRadius=UDim.new(1,0)
    S.MiniForwardImageButton=Instance.new("ImageButton"); S.MiniForwardImageButton.Size=UDim2.new(0,35,0,35); S.MiniForwardImageButton.Position=UDim2.new(0,100,0,0); S.MiniForwardImageButton.BackgroundTransparency=1; S.MiniForwardImageButton.BorderSizePixel=0; S.MiniForwardImageButton.Image="rbxassetid://102857578902137"; S.MiniForwardImageButton.Parent=mbf; Instance.new("UICorner",S.MiniForwardImageButton).CornerRadius=UDim.new(1,0)
    S.MiniShowButton=Instance.new("TextButton"); S.MiniShowButton.Size=UDim2.new(0,35,0,35); S.MiniShowButton.Position=UDim2.new(1,-42,0,8); S.MiniShowButton.BackgroundColor3=Color3.fromRGB(80,80,80); S.MiniShowButton.BorderSizePixel=0; S.MiniShowButton.Text="📂"; S.MiniShowButton.TextColor3=Color3.fromRGB(255,255,255); S.MiniShowButton.Font=Enum.Font.GothamBold; S.MiniShowButton.TextSize=18; S.MiniShowButton.Parent=S.MiniFrame; Instance.new("UICorner",S.MiniShowButton).CornerRadius=UDim.new(0,8)
    
    -- ========== REGISTER ELEMENTS FOR TRANSLATION ==========
    registerForTranslation(ul, "GitHub MP3 URL:")
    registerForTranslation(S.PlayButton, "▶ PLAY")
    registerForTranslation(S.PauseButton, "⏸ PAUSE")
    registerForTranslation(S.StopButton, "⏹ STOP")
    registerForTranslation(S.HistoryButton, "→ HISTORY")
    registerForTranslation(S.MuteToggle, "🔇 MUTE GAME")
    registerForTranslation(S.VolumeLabel, "Volume: 1.00")
    registerForTranslation(S.SpeedLabel, "Speed: 1.00x")
    registerForTranslation(S.StatusLabel, "Ready to play music")
    registerForTranslation(settingsTabBtn, "⚙ Settings")
    registerForTranslation(playingTabBtn, "🎵 Playing")
    registerForTranslation(SaveThemeLabel, "Save Theme:")
    registerForTranslation(RememberKeyLabel, "Remember Key:")
    registerForTranslation(SliderColorLabel, "Slider Color:")
    registerForTranslation(MiniPlayLabel, "Mini Play Mode:")
    registerForTranslation(ExtraMiniLabel, "Extra Mini Mode:")
    registerForTranslation(KeybindLabel, "Keybinds:")
    registerForTranslation(AutoTranslateLabel, "Auto Translate:")
    registerForTranslation(S.InfoHowTab, "📖 HOW TO USE")
    registerForTranslation(S.SearchTabBtn, "🔍 Search")
    registerForTranslation(S.PlaylistTabBtn, "📋 Playlist")
    registerForTranslation(S.BackButton, "← BACK")
    registerForTranslation(si, "Enter song name or full GitHub raw URL")
    registerForTranslation(S.NoHistoryLabel, "No download history yet")
    registerForTranslation(S.LoopToggle, "🔁 LOOP: ON")
    
    local function applySpeedFromTextBox() local t=string.gsub(string.gsub(S.SpeedTextBox.Text,"x",""),"X",""); local s=tonumber(t); if s then updateSpeed(math.clamp(s,0,100)) else S.SpeedTextBox.Text=string.format("%.2f",S.currentSpeed).."x" end end
    local function applyVolumeFromText() if not S.VolumeTextBox then return end; local t=string.gsub(S.VolumeTextBox.Text,"%s",""); local v=tonumber(t); if v then local clampedV=math.clamp(v,0,100); S.currentVolume=clampedV; if S.currentSound then S.currentSound.Volume=S.currentVolume end; S.VolumeLabel.Text="Volume: "..string.format("%.2f",S.currentVolume); S.VolumeTextBox.Text=string.format("%.2f",S.currentVolume) else S.VolumeTextBox.Text=string.format("%.2f",S.currentVolume) end end
    local function toggleMiniPlayMode() S.miniPlayMode=not S.miniPlayMode; updateMiniPlayToggle(); if S.miniPlayMode then if S.extraMiniPlayMode then toggleExtraMiniMode() end; if S.ScreenGui then S.ScreenGui.Enabled=false end; if S.MiniScreenGui then S.MiniScreenGui.Enabled=true end else if S.ScreenGui then S.ScreenGui.Enabled=true end; if S.MiniScreenGui then S.MiniScreenGui.Enabled=false end end end
    
    local function searchMusic(st)
        if not S.SearchScrollFrame then return end
        for _,c in pairs(S.SearchScrollFrame:GetChildren()) do if c.Name=="SearchResultItem" then c:Destroy() end end
        if st=="" then if S.SearchNoResultsLabel then S.SearchNoResultsLabel.Visible=true; S.SearchNoResultsLabel.Text="Enter a search term or URL" end; S.SearchScrollFrame.CanvasSize=UDim2.new(0,0,0,0); return end
        S.SearchNoResultsLabel.Visible=false; local isFU=string.find(st,"http") and string.find(st,".mp3")
        if isFU then local s,r=pcall(function() return game:HttpGet(st) end)
            if s and r and #r>0 then local fn="audio.mp3"; local pts=string.split(st,"/"); if #pts>0 and string.find(pts[#pts],".mp3") then fn=string.gsub(string.gsub(pts[#pts],"%%20"," "),"%%25","%%") end
                local it=Instance.new("Frame"); it.Name="SearchResultItem"; it.Size=UDim2.new(1,-10,0,50); it.Position=UDim2.new(0,5,0,0); it.BackgroundColor3=Color3.fromRGB(50,50,60); it.BorderSizePixel=0; it.Parent=S.SearchScrollFrame; Instance.new("UICorner",it).CornerRadius=UDim.new(0,4)
                local lb=Instance.new("TextLabel"); lb.Size=UDim2.new(1,-70,0,20); lb.Position=UDim2.new(0,5,0,5); lb.BackgroundTransparency=1; lb.Text=fn; lb.TextColor3=Color3.fromRGB(255,255,255); lb.Font=Enum.Font.GothamBold; lb.TextSize=12; lb.Parent=it
                local pb=Instance.new("TextButton"); pb.Size=UDim2.new(0,60,0,30); pb.Position=UDim2.new(1,-65,0,10); pb.BackgroundColor3=Color3.fromRGB(70,150,70); pb.BorderSizePixel=0; pb.Text="PLAY"; pb.TextColor3=Color3.fromRGB(255,255,255); pb.Font=Enum.Font.GothamBold; pb.TextSize=10; pb.Parent=it; Instance.new("UICorner",pb).CornerRadius=UDim.new(0,4)
                pb.MouseButton1Click:Connect(function() if S.isSearchOpen then toggleSearchPanel() end; playMusicFromUrl(st,fn) end); S.SearchScrollFrame.CanvasSize=UDim2.new(0,0,0,60)
            else S.SearchNoResultsLabel.Visible=true; S.SearchNoResultsLabel.Text="❌ URL not found"; S.SearchScrollFrame.CanvasSize=UDim2.new(0,0,0,0) end
        else local fd={}; pcall(function() local bu="https://github.com/Bro-broa3/PrimeMusic/raw/main/"; local tr={string.gsub(st," ","%%20")..".mp3",string.gsub(string.lower(st)," ","%%20")..".mp3",string.gsub(st," ","")..".mp3",string.gsub(string.lower(st)," ","_")..".mp3",string.gsub(string.lower(st)," ","-")..".mp3",string.lower(string.gsub(st," ",""))..".mp3"}; for _,fn in ipairs(tr) do pcall(function() local rp=game:HttpGet(bu..fn); if rp and #rp>1000 then table.insert(fd,{url=bu..fn,fileName=string.gsub(fn,"%%20"," ")}) end end) end end)
            if #fd>0 then local th=0; for _,rs in ipairs(fd) do local it=Instance.new("Frame"); it.Name="SearchResultItem"; it.Size=UDim2.new(1,-10,0,50); it.Position=UDim2.new(0,5,0,th); it.BackgroundColor3=Color3.fromRGB(50,50,60); it.BorderSizePixel=0; it.Parent=S.SearchScrollFrame; Instance.new("UICorner",it).CornerRadius=UDim.new(0,4)
                local lb=Instance.new("TextLabel"); lb.Size=UDim2.new(1,-70,0,20); lb.Position=UDim2.new(0,5,0,5); lb.BackgroundTransparency=1; lb.Text=rs.fileName; lb.TextColor3=Color3.fromRGB(255,255,255); lb.Font=Enum.Font.GothamBold; lb.TextSize=12; lb.Parent=it
                local pb=Instance.new("TextButton"); pb.Size=UDim2.new(0,60,0,30); pb.Position=UDim2.new(1,-65,0,10); pb.BackgroundColor3=Color3.fromRGB(70,150,70); pb.BorderSizePixel=0; pb.Text="PLAY"; pb.TextColor3=Color3.fromRGB(255,255,255); pb.Font=Enum.Font.GothamBold; pb.TextSize=10; pb.Parent=it; Instance.new("UICorner",pb).CornerRadius=UDim.new(0,4)
                local ru,rf=rs.url,rs.fileName; pb.MouseButton1Click:Connect(function() if S.isSearchOpen then toggleSearchPanel() end; playMusicFromUrl(ru,rf) end); th=th+55 end
                S.SearchScrollFrame.CanvasSize=UDim2.new(0,0,0,th)
            else S.SearchNoResultsLabel.Visible=true; S.SearchNoResultsLabel.Text="❌ No results found"; S.SearchScrollFrame.CanvasSize=UDim2.new(0,0,0,0) end
        end
    end
    
    -- Connect events
    S.LoopToggle.MouseButton1Click:Connect(function() S.mainLoopOn=not S.mainLoopOn; applyLoopState() end)
    S.SpeedTextBox.FocusLost:Connect(function(ep) applySpeedFromTextBox() end)
    S.SpeedUpButton.MouseButton1Click:Connect(function() updateSpeed(math.min(S.currentSpeed+0.25,100)) end)
    S.SpeedDownButton.MouseButton1Click:Connect(function() updateSpeed(math.max(S.currentSpeed-0.25,0)) end)
    S.VolumeTextBox.FocusLost:Connect(function(ep) applyVolumeFromText() end)
    S.VolumeUpButton.MouseButton1Click:Connect(function() updateVolume(math.min(S.currentVolume+0.5,100)) end)
    S.VolumeDownButton.MouseButton1Click:Connect(function() updateVolume(math.max(S.currentVolume-0.5,0)) end)
    CloseButton.MouseButton1Click:Connect(function() if S.playlistCheckConnection then pcall(function() S.playlistCheckConnection:Disconnect() end); S.playlistCheckConnection=nil end; stopMusic(); S.ScreenGui:Destroy(); if S.MiniScreenGui then S.MiniScreenGui:Destroy() end; if S.ExtraMiniScreenGui then S.ExtraMiniScreenGui:Destroy() end; if S.hideButton then S.hideButton:Destroy() end; if S.showButton then if S.showButton.Parent then S.showButton.Parent:Destroy() end end end)
    MinimizeButton.MouseButton1Click:Connect(function() if S.isMinimized then S.MainFrame.Size=UDim2.new(0,400,0,345); S.ContentFrame.Visible=true; S.OutlineFrame.Visible=true; S.isMinimized=false else S.MainFrame.Size=UDim2.new(0,400,0,35); S.ContentFrame.Visible=false; S.OutlineFrame.Visible=false; S.isMinimized=true end end)
    S.SettingsButton.MouseButton1Click:Connect(function() toggleSettingsPanel() end)
    S.InfoButton.MouseButton1Click:Connect(function() toggleInfoPanel() end)
    S.SearchButton.MouseButton1Click:Connect(function() toggleSearchPanel() end)
    spb.MouseButton1Click:Connect(function() searchMusic(S.SearchTextBox.Text) end)
    S.SearchTextBox.FocusLost:Connect(function(ep) if ep then searchMusic(S.SearchTextBox.Text) end end)
    S.HistoryButton.MouseButton1Click:Connect(function() toggleHistoryPanel() end)
    
    S.MuteToggle.MouseButton1Click:Connect(function() 
        local t=S.themes[S.currentTheme] or S.themes["Default"]
        if S.isGameMuted then
            S.isGameMuted=false; updateTranslatableText(S.MuteToggle, "🔇 MUTE GAME"); S.MuteToggle.BackgroundColor3=t.muteColor or Color3.fromRGB(180,80,80)
            for sound,vol in pairs(S.gameSoundsMuted) do pcall(function() if sound and sound.Parent then sound.Volume=vol end end) end
            S.gameSoundsMuted={}; pcall(function() SoundService.Volume=1 end)
        else
            S.isGameMuted=true; updateTranslatableText(S.MuteToggle, "🔊 UNMUTE"); S.MuteToggle.BackgroundColor3=t.muteOnColor or Color3.fromRGB(80,180,80)
            S.gameSoundsMuted={}
            pcall(function() for _,v in pairs(workspace:GetDescendants()) do if v:IsA("Sound") and v~=S.currentSound then S.gameSoundsMuted[v]=v.Volume; v.Volume=0 end end end)
            pcall(function() SoundService.Volume=0 end)
        end
    end)
    
    S.PlayButton.MouseButton1Click:Connect(function() local url=S.UrlTextBox.Text; if url=="" then updateTranslatableText(S.StatusLabel, "❌ Error: Please enter URL"); return end; if string.sub(string.lower(url),-4)~=".mp3" then updateTranslatableText(S.StatusLabel, "❌ Error: URL must end with .mp3"); return end; local fn="audio.mp3"; local pts=string.split(url,"/"); if #pts>0 and string.find(pts[#pts],".mp3") then fn=string.gsub(string.gsub(pts[#pts],"%%20"," "),"%%25","%%") end; playMusicFromUrl(url,fn) end)
    S.PauseButton.MouseButton1Click:Connect(function() if not S.currentSound then return end; togglePause() end)
    S.StopButton.MouseButton1Click:Connect(function() stopMusic(); updateTranslatableText(S.StatusLabel, "⏹ Music Stopped"); updateTimeDisplay() end)
    S.MiniPlayToggle.MouseButton1Click:Connect(toggleMiniPlayMode)
    S.MiniShowButton.MouseButton1Click:Connect(function() toggleMiniPlayMode() end)
    S.MiniRewindImageButton.MouseButton1Click:Connect(function() if not S.currentSound then return end; local nt=math.max(S.currentSound.TimePosition-10,0); S.currentSound.TimePosition=nt; if S.isPaused then S.pausedTimePosition=nt end; updateTimeDisplay() end)
    S.MiniPauseImageButton.MouseButton1Click:Connect(function() if not S.currentSound then return end; togglePause() end)
    S.MiniForwardImageButton.MouseButton1Click:Connect(function() if not S.currentSound then return end; local nt=math.min(S.currentSound.TimePosition+10,S.currentSound.TimeLength); S.currentSound.TimePosition=nt; if S.isPaused then S.pausedTimePosition=nt end; updateTimeDisplay() end)
    
    createHideShowButtons()
    spawn(function() animateTextboxPlaceholder(S.SearchTextBox, {"search by name or paste URL","type a song name to find...","paste GitHub raw URL here...","find your favorite music...","enter URL ending with .mp3..."}) end)
    spawn(function() animateTextboxPlaceholder(S.SecretKeyTextBox, {"enter a secret key","unlock the playlist...","type the key to access..."}) end)
    
    -- Apply initial translation state
    applyTranslations()
    updateAutoTranslateToggle()
    
    print("[MusicPlayer] Main GUI created!")
end

-- ========== INIT ==========
print("[MusicPlayer] Starting...")

local function runInitStep(name, fn)
    local ok, err=xpcall(fn,function(e)
        return tostring(e).."\n"..debug.traceback()
    end)
    if ok then
        print("[MusicPlayer] "..name.." OK")
    else
        warn("[MusicPlayer] "..name.." FAILED")
        warn(err)
        print("[MusicPlayer] "..name.." FAILED: "..tostring(err))
    end
    return ok
end

runInitStep("load settings/data",function()
    loadSettings()
    S.imageCache=loadImageCache()
    S.musicCache=loadCache()
    S.downloadHistory=loadHistory()
    S.userLanguage=detectUserLanguage()
    loadMusicStats()
end)

local guiOK=runInitStep("create main GUI",function()
    createMainGUI()
end)

if guiOK then
    runInitStep("create extra GUI/setup",function()
        createExtraMiniGUI()
        applyLoopState()
        updateExtraLoopButton()
        updateExtraMiniToggle()
        applyTheme(S.currentTheme)
        updateSaveThemeToggle()
        updateRememberKeyToggle()
        updateMiniPlayToggle()
        updateKeybindToggle()
        setupKeybind()
        updateSliderColors()
        updateSliderColorToggle()
        updateVolumeDisplayOnly()
        updateSpeed(S.currentSpeed)
        updateTimeDisplay()
        updateDataPanel()

        if S.isKeyCorrect then
            loadPlaylist()
        end
    end)

    task.spawn(function()
        while task.wait(0.05) do
            if S.currentSound then
                pcall(updateTimeDisplay)
            end
        end
    end)

    task.spawn(function()
        while task.wait(1) do
            if S.InfoDataFrame and S.InfoDataFrame.Visible then
                updateDataPanel()
            end
        end
    end)

    task.spawn(function()
        while task.wait(S.dataRefreshInterval or 15) do
            if S.InfoDataFrame and S.InfoDataFrame.Visible then
                updateDataPanel()
            end
        end
    end)

    print("[MusicPlayer] Ready!")
    showNotification("GitHub MP3 Player","✅ GUI Loaded!",3)
else
    warn("[MusicPlayer] GUI creation failed. The script stopped before creating the player.")
end

player.CharacterAdded:Connect(function(char)
    if S.currentSound and S.isPlaying then
        S.currentSound.Parent=workspace
        if not S.currentSound.IsPlaying then
            S.currentSound:Play()
        end
    end
end)

Players.PlayerRemoving:Connect(function(lp)
    if lp~=player then return end
    if S.playlistCheckConnection then
        pcall(function() S.playlistCheckConnection:Disconnect() end)
        S.playlistCheckConnection=nil
    end
    pcall(stopMusic)
    pcall(function() if S.ScreenGui then S.ScreenGui:Destroy() end end)
    pcall(function() if S.MiniScreenGui then S.MiniScreenGui:Destroy() end end)
    pcall(function() if S.ExtraMiniScreenGui then S.ExtraMiniScreenGui:Destroy() end end)
    pcall(function() if S.hideButton then S.hideButton:Destroy() end end)
    pcall(function() if S.showButton and S.showButton.Parent then S.showButton.Parent:Destroy() end end)
end)