-- =====================================================================================================================
--                                                          Header
-- =====================================================================================================================

script_authors('Sand')
script_description('Mining assistant TG: @Mister_Sand')
script_version("0.1")

-- =====================================================================================================================
--                                                          Import
-- =====================================================================================================================

-- Проверяем библиотеку
local function CheckLibrary(libName)
    local success, lib = pcall(require, libName)
    if not success then
        print("Библиотека " .. libName .. " не найдена!")
    end
    return success, lib
end

local imguiSuccess,     imgui       = CheckLibrary('mimgui')
local encodingSuccess,  encoding    = CheckLibrary('encoding')
local sampevSuccess,    sampev      = CheckLibrary('lib.samp.events')
local jsonSuccess,      json        = CheckLibrary('cjson')
local lfsSuccess,       lfs         = CheckLibrary('lfs')
local faSuccess,        fa          = CheckLibrary('fAwesome6_solid')

encoding.default = 'CP1251'
local u8 = encoding.UTF8

if not imguiSuccess     or not encodingSuccess  or not sampevSuccess or
   not jsonSuccess      or not faSuccess then
    print("Некоторые библиотеки не были загружены. Пожалуйста, установите недостающие библиотеки.")
end

-- =====================================================================================================================
--                                                          GLOBAL VARIABLES
-- =====================================================================================================================

-- --------------------------------------------------------
--                           Constants
-- --------------------------------------------------------

ISMONETLOADER = true
SEPORATORPATCH = "/"
if MONET_DPI_SCALE == nil then MONET_DPI_SCALE = 1.0 ISMONETLOADER = false SEPORATORPATCH = "\\" end

local folderConfig = 'config'..SEPORATORPATCH -- Folder config
local PATCHCONFIG = folderConfig..'MMT CFGs'..SEPORATORPATCH  -- Main folder cfgs

local colors = {
    WHITE = "FFFFFF",
    RED = "FF3333",
    YELLOW = "FFE133",
    GREEN = "33FF33",
}

-- Типы сообщений скрипта
local TYPECHATMESSAGES = {
    SECONDARY = 2,
    WARNING = 6,
    CRITICAL = 8,
    DEBUG = 10
}

-- --------------------------------------------------------
--                           Settings
-- --------------------------------------------------------

-- Заводские настройки скрипта
local defaultSettings = {
    main = {
        -- Заменять диалог майнинга на окно скрипат
        replaceDialog = true,
        -- Заливать с числа. Если залито 49.9 - то будем заливать, если 50.1 - то уже не заливаем
        fillFrom = 50.0,
        -- Типы сообщений в чат игры
        typeChatMessage = {
            messages = true,
            debug = false,
        }
    },
    style = {
        -- масштаб интерфейса
        scaleUI = 1.0,
        -- Цвет в тексте
        colorChat = 'BFA68C',
        -- Цвет текста
        colorMessage = 0xFFBFA68C,
        -- Размер скроллбара
        scrollbarSizeStyle = 10,
        -- Стартовый размер основного окна скрипта
        sizeWindow = { x = 600, y = 400 },
        -- Цыета интерфейса
        mainColor   = { r = 0.25, g = 0.45, b = 0.28, a = 1.00},
        textColor   = { r = 0.80, g = 0.85, b = 0.80, a = 1.00},
        bgColor     = { r = 0.10, g = 0.15, b = 0.14, a = 0.98},
        accentColor = { r = 0.27, g = 0.25, b = 0.45, a = 1.00},
    }
}

-- Настрокйи скрипта
local settings = defaultSettings

-- --------------------------------------------------------
--                           Imgui
-- --------------------------------------------------------

-- Разрешение экрана пользователя
local sizeScreanX, sizeScreanY = getScreenResolution()

local new = imgui.new

local imguiWindows = {
    -- Основное окно скрипта
    main = new.bool(false),
}
-- Текущая позиция основного окна
local posMainFraim = { x = 0, y = 0}

-- Активный раздел в скрипте
local activeTabScript = "main"

local imguiInit = false

-- --------------------------------------------------------
--                           State
-- --------------------------------------------------------

local processInteractingThread

local idDialogs = {
    selectVideoCard = 0,
    selectVideoCardItemFlash = 0,
    selectHouse = 0,
}

local stateCrypto = {
    -- Запущен ли процесс взаимодействия
    work = false,
    -- Прогресс домов
    progressHouses = 0,
    -- Список дотов в очереди
    queueHouses = {},
    -- Прогресс полок
    progressShelves = 0,
    -- Список полок в очереди
    queueShelves = {},
}

local processes = {
    -- собираем
    take = false,
    -- заливаем
    fill = false,
    -- включаем
    on = false,
    -- выключаем
    off = false,
}

local haveLiquid = {
    btc = 0,
    supper_btc = 0,
    asc = 0,
}

-- Доступные полки
local shelves = {}

local houses = {}

local lastIDDialog = 0


-- =====================================================================================================================
--                                                          MAIN
-- =====================================================================================================================

imgui.OnInitialize(function()
    fa.Init()

    imguiInit = true
end)

function main()
    while not isSampAvailable() do wait(0) end

    LoadSettings()

    if ISMONETLOADER and settings.style.scaleUI ~= 1.0 then
        MONET_DPI_SCALE = settings.style.scaleUI
    elseif ISMONETLOADER then
        settings.style.scaleUI = MONET_DPI_SCALE
    end

    while not imguiInit do wait(10) end

    if not ISMONETLOADER then
        SetScaleUI()
    end

    SetStyle()

    AddChatMessage('Скрипт загружен. Команда активации: {'..settings.style.colorChat..'}/mmt{FFFFFF}.')

    sampRegisterChatCommand("mmt", function ()
        SwitchMainWindow()
    end)
    sampRegisterChatCommand("mmtr", function ()
        thisScript():reload()
    end)
    sampRegisterChatCommand("mmtsr", function ()
        settings.style.scaleUI = 1.0
        SaveSettings()
        thisScript():reload()
    end)

    processInteractingThread = lua_thread.create_suspended(ProcessInteracting)
end

-- =====================================================================================================================
--                                                          SAMP EVENTS
-- =====================================================================================================================

-- --------------------------------------------------------
--                           onServerMessage
-- --------------------------------------------------------

function sampev.onServerMessage(color, text)
    if text:find("Вы залили") and text:find("охлаждающей жидкости в видеокарту") and color == 1941201407 then
        local nowFillLiquid = text:match("восстановлено до ([%d%.]+)%%")

        if nowFillLiquid then
            stateCrypto.queueShelves[stateCrypto.progressShelves].fill = tonumber(nowFillLiquid)
            stateCrypto.waitFill = false
        end
    end

    if text:find("Чтобы запустить видеокарту в работу, необходимо вывести всю прибыль этой видеокарты") and color == -1104335361 then
        DeactivateProcessesInteracting()
    end

    if text:find("Эта функция недоступна через флешку") and color == -1104335361 then
        DeactivateProcessesInteracting()
    end
end

-- --------------------------------------------------------
--                           onShowDialog
-- --------------------------------------------------------

function sampev.onShowDialog(dialogId, style, title, button1, button2, text)
    lastIDDialog = dialogId

    if stateCrypto.work and processes.take and title:find("Вывод прибыли видеокарты")then
        local continue = stateCrypto.queueShelves[stateCrypto.progressShelves].count - math.floor(stateCrypto.queueShelves[stateCrypto.progressShelves].count)
        stateCrypto.queueShelves[stateCrypto.progressShelves].count = continue
        sampSendDialogResponse(dialogId, 1, 0, "")
        return not settings.main.replaceDialog
    end

    if stateCrypto.work and title:find("Стойка") and title:find("Полка") then
        local actions = ParseShelfVideoCardData(text)

        for index, value in ipairs(actions) do
            -- AddChatMessage(value.action.." - "..value.samp_line.." - "..value.count)

            if processes.take then
                if  value.count > 0 and (value.action == "take_btc" or value.action == "take_asc") then
                    sampSendDialogResponse(dialogId, 1, value.samp_line, "")
                elseif math.floor(stateCrypto.queueShelves[stateCrypto.progressShelves].count) == 0 then
                    stateCrypto.progressShelves = stateCrypto.progressShelves +1
                    sampSendDialogResponse(dialogId, 0, 0, "")
                    return not settings.main.replaceDialog
                end
            end

            if processes.fill and value.action == "fill" then
                if stateCrypto.queueShelves[stateCrypto.progressShelves].fill > settings.main.fillFrom then
                    stateCrypto.progressShelves = stateCrypto.progressShelves +1
                    sampSendDialogResponse(dialogId, 0, 0, "")
                    return not settings.main.replaceDialog
                end
                sampSendDialogResponse(dialogId, 1, value.samp_line, "")
                return not settings.main.replaceDialog
            end

            if processes.on and value.action == "on" then
                sampSendDialogResponse(dialogId, 1, value.samp_line, "")
                return not settings.main.replaceDialog
            elseif processes.on and value.action == "off" then
                stateCrypto.queueShelves[stateCrypto.progressShelves].work = true
                stateCrypto.progressShelves = stateCrypto.progressShelves +1
                sampSendDialogResponse(dialogId, 0, 0, "")
                return not settings.main.replaceDialog
            end

            if processes.off and value.action == "off" then
                sampSendDialogResponse(dialogId, 1, value.samp_line, "")
                return not settings.main.replaceDialog
            elseif processes.off and value.action == "on" then
                stateCrypto.queueShelves[stateCrypto.progressShelves].work = false
                stateCrypto.progressShelves = stateCrypto.progressShelves +1
                sampSendDialogResponse(dialogId, 0, 0, "")
                return not settings.main.replaceDialog
            end
        end
        return not settings.main.replaceDialog
    end

    if stateCrypto.work and processes.fill and not stateCrypto.waitFill and title:find("Выберите тип жидкости") then
        local actions = ParseLiquidData(text)

        for index, value in ipairs(actions) do
            -- AddChatMessage(value.action.." - "..value.samp_line.." - "..value.count)
            if value.action == "btc" and value.count > 0 then
                haveLiquid.btc = value.count
                stateCrypto.waitFill = true
                sampSendDialogResponse(dialogId, 1, value.samp_line, "")
                return not settings.main.replaceDialog
            elseif value.action == "supper_btc" and value.count > 0 then
                haveLiquid.supper_btc = value.count
                stateCrypto.waitFill = true
                sampSendDialogResponse(dialogId, 1, value.samp_line, "")
                return not settings.main.replaceDialog
            elseif value.action == "asc" and value.count > 0 then
                haveLiquid.asc = value.count
                stateCrypto.waitFill = true
                sampSendDialogResponse(dialogId, 1, value.samp_line, "")
                return not settings.main.replaceDialog
            else
                haveLiquid.btc = 0
                haveLiquid.supper_btc = 0
                haveLiquid.asc = 0
                
                processes.fill = false
                AddChatMessage("Нет жидкости для видеокарты "..value.action, TYPECHATMESSAGES.CRITICAL)
            end
        end
    end


    if title:find("Выберите видеокарту") then
        if title:find("дом") then
            idDialogs.selectVideoCardItemFlash = dialogId
        end
        idDialogs.selectVideoCard = dialogId
        imguiWindows.main[0] = true

        shelves = ParseShelfData(text)

        if settings.main.replaceDialog then
            return false
        end
    end

    if title:find("Выбор дома") and text:find("циклов") then
        idDialogs.selectHouse = dialogId

        imguiWindows.main[0] = true

        houses = ParseHouseData(text)

        if settings.main.replaceDialog then
            return false
        end
    end
end

-- --------------------------------------------------------
--                           onSendDialogResponse
-- --------------------------------------------------------

-- Срабатывание на отправку диалога
function sampev.onSendDialogResponse(id, btn, list, input)

    if id == idDialogs.selectHouse then
        imguiWindows.main[0] = false
        houses = {}
    end

    if id == idDialogs.selectVideoCard then
        imguiWindows.main[0] = false
    end

end

-- =====================================================================================================================
--                                                          FUNCTIONS
-- =====================================================================================================================

function StartProcessInteracting(action)
    if stateCrypto.work then AddChatMessage("Процесс уже запущен", TYPECHATMESSAGES.WARNING) end
    DeactivateProcessesInteracting()

    if action == "fill" then
        processes.fill = true
    elseif action == "take" then
        processes.take = true
    elseif action == "on" then
        processes.on = true
    elseif action == "off" then
        processes.off = true
    else
        AddChatMessage("Нет действий", TYPECHATMESSAGES.CRITICAL)
        return false
    end

    stateCrypto.work = true

    if #houses > 0 then
        stateCrypto.progressHouses = 1

        for index, house in ipairs(houses) do
            table.insert(stateCrypto.queueHouses, {
                samp_line = house.samp_line,
            })
        end
    end

    stateCrypto.progressShelves = 1
    for index, shelf in ipairs(shelves) do
        if
            (shelf.status == "Работает" and processes.off) or
            (shelf.status ~= "Работает" and processes.on and shelf.percentage > 0) or
            (shelf.profit >= 1.0 and processes.take) or
            (shelf.percentage <= settings.main.fillFrom and processes.fill)
        then
            table.insert(stateCrypto.queueShelves, {
                samp_line = shelf.samp_line,
                fill = shelf.percentage,
                work = shelf.status == "Работает",
                count = shelf.profit
            })
        end
    end

    if #stateCrypto.queueShelves == 0 then
        AddChatMessage("Отсутствуют полки для работы", TYPECHATMESSAGES.WARNING)
    end

    if processInteractingThread:status() == "suspended"
        or processInteractingThread:status() == "dead"
    then
        processInteractingThread:run()
    else
        processInteractingThread:terminate()
    end
end

function ProcessInteracting()
    for index, value in ipairs(stateCrypto.queueShelves) do
        while lastIDDialog ~= idDialogs.selectVideoCardItemFlash and lastIDDialog ~= idDialogs.selectVideoCard do
            wait(100)
            if not CheckProcessInteracting() then
                DeactivateProcessesInteracting()
                return
            end
        end
        sampSendDialogResponse(lastIDDialog, 1, value.samp_line, "")
        local _oldProgressShelves = stateCrypto.progressShelves
        while _oldProgressShelves == stateCrypto.progressShelves do
            wait(100)
            if not CheckProcessInteracting() then
                DeactivateProcessesInteracting()
                return
            end
        end
    end

    DeactivateProcessesInteracting()
end

function CheckProcessInteracting()
    return processes.take or processes.fill or processes.on or processes.off
end

function DeactivateProcessesInteracting()
    stateCrypto.work = false
    stateCrypto.waitFill = false
    stateCrypto.progressHouses = 0
    stateCrypto.queueHouses = {}
    stateCrypto.progressShelves = 0
    stateCrypto.queueShelves = {}
    processes.on = false
    processes.off = false
    processes.take = false
    processes.fill = false
end

-- --------------------------------------------------------
--                           Load
-- --------------------------------------------------------

function LoadJSON(filePatch)
    local _file = io.open(filePatch, "rb")

    if _file then
        local _content = _file:read("*a")
        _file:close()

        if _content and _content:match("%S") then
            return json.decode(_content)
        end
    end

    return {}
end

function LoadSettings()
    local _settings = LoadJSON(PATCHCONFIG..'Settings.json')
    if not _settings then
        _settings = {}
    end
    -- сливаем настройки с дефолтными
    MergeSettings(_settings, defaultSettings)
    settings = _settings
    return _settings
end

function MergeSettings(dest, source)
    for key, value in pairs(source) do
        if type(value) == "table" then
            if not dest[key] then
                dest[key] = {}
            end
            MergeSettings(dest[key], value)
        else
            if dest[key] == nil then
                dest[key] = value
            end
        end
    end
end

-- --------------------------------------------------------
--                           Save
-- --------------------------------------------------------

function SaveJSON(filePatch, data)
    local folderPath = string.match(filePatch, "^(.*[/\\])")
    if folderPath then
        EnsureDirectoryExists(folderPath)
    end

    local _file = io.open(filePatch, "w")
    if _file then
        _file:write(json.encode(data))
        _file:close()
        return true
    else
        return false
    end
end

function SaveSettings()
    local success = SaveJSON(PATCHCONFIG .. 'Settings.json', settings)
    if not success then
        print("Ошибка: Не удалось сохранить настройки!")
    end
end

-- --------------------------------------------------------
--                           Parsers
-- --------------------------------------------------------

function ParseHouseData(text)
    houses = {}

    local results = {}
    local lines = {}

    -- Разбиваем текст на строки
    for line in text:gmatch("[^\r\n]+") do
        table.insert(lines, line)
    end

    -- Паттерн для извлечения данных о полке с налогом
    local patternWithTax = "Дом №(%d+)%s*([^%d]+)%s*{%w+}([%d]+)%s*([%d]+)%s*циклов%s*%(%$([%d,]+) / %$([%d%.,]+)%)"

    -- Паттерн для извлечения данных о полке без налога
    local patternWithoutTax = "Дом №(%d+)%s*([^%d]+)%s*([%d]+)%s*циклов%s*%(%$([%d,]+) / %$([%d%.,]+)%)"

    for lineIndex, line in ipairs(lines) do
        local found = false

        -- Сначала пробуем паттерн с налогом
        for houseNum, city, tax, cycles, bankNow, bankMax in string.gmatch(line, patternWithTax) do
            table.insert(results, {
                samp_line = lineIndex - 2,
                house_number = tonumber(houseNum),
                city = city:gsub("^%s+", ""):gsub("%s+$", ""),
                tax = tonumber(tax),
                cycles = tonumber(cycles),
                bankNow = bankNow:gsub(",", ""),
                bankMax = bankMax:gsub(",", ""),
                raw_line = line
            })
            found = true
        end

        -- Если не найдено совпадений с налогом, пробуем паттерн без налога
        if not found then
            for houseNum, city, cycles, bankNow, bankMax in string.gmatch(line, patternWithoutTax) do
                table.insert(results, {
                    samp_line = lineIndex - 2,
                    house_number = tonumber(houseNum),
                    city = city:gsub("^%s+", ""):gsub("%s+$", ""),
                    tax = nil,
                    cycles = tonumber(cycles),
                    bankNow = bankNow:gsub(",", ""),
                    bankMax = bankMax:gsub(",", ""),
                    raw_line = line
                })
            end
        end
    end

    return results
end

function ParseShelfData(text)
    shelves = {}

    local results = {}
    local lines = {}

    for line in text:gmatch("[^\r\n]+") do
        table.insert(lines, line)
    end

    -- Паттерн для извлечения данных о полке
    local pattern = "Полка №(%d+)%s*|%s*{(%w+)}([^%d]+)([%d%.]+)%s+(%w+)%s+(%d+)%s+уровень%s+([%d%.]+)"

    for lineIndex, line in ipairs(lines) do
        for shelfNum, colorCode, status, profit, currency, level, percentage in string.gmatch(line, pattern) do
            table.insert(results, {
                shelf_number = tonumber(shelfNum),
                samp_line = lineIndex - 2,
                status = status:gsub("^%s+", ""):gsub("%s+$", ""),
                color_code = colorCode,
                profit = tonumber(profit),
                currency = currency,
                level = tonumber(level),
                percentage = tonumber(percentage),
                raw_line = line
            })
        end
    end

    return results
end

function ParseShelfVideoCardData(text)
    local results = {}
    local lines = {}

    for line in text:gmatch("[^\r\n]+") do
        table.insert(lines, line)
    end

    local patterns = {
        {pater = "Запустить видеокарту", action = "on"},
        {pater = "Остановить видеокарту", action = "off"},
        {pater = "Забрать прибыль %(([%d%.]+) BTC%)", action = "take_btc"},
        {pater = "Забрать прибыль %(([%d%.]+) ASC%)", action = "take_asc"},
        {pater = "Залить охлаждающую жидкость", action = "fill"},
        {pater = "Достать видеокарту", action = "take_video_card"},
    }

    -- Проходим по каждой строке и ищем полки
    for lineIndex, line in ipairs(lines) do
        for _, pattern in ipairs(patterns) do
            for countCrypto in string.gmatch(line, pattern.pater) do
                local _countInt = tonumber(countCrypto:match("%d+%.")) or 0
                table.insert(results, {
                    action = pattern.action,
                    count = _countInt,
                    samp_line = lineIndex - 1
                })
            end
        end
    end

    return results
end

function ParseLiquidData(text)
    local results = {}
    local lines = {}

    for line in text:gmatch("[^\r\n]+") do
        table.insert(lines, line)
    end

    local patterns = {
        {pater = "Охлаждающая жидкость для видеокарты%s+{%w+}%[ ([%d]+) %]", action = "btc"},
        {pater = "Супер охлаждающая жидкость для видеокарты%s+{%w+}%[ ([%d]+) %]", action = "supper_btc"},
        {pater = "Охлаждающая жидкость для Arizona Video Card%s+{%w+}%[ ([%d]+) %]", action = "asc"},
    }

    -- Проходим по каждой строке и ищем полки
    for lineIndex, line in ipairs(lines) do
        for _, pattern in ipairs(patterns) do
            for countLiquid in string.gmatch(line, pattern.pater) do
                table.insert(results, {
                    action = pattern.action,
                    count = tonumber(countLiquid),
                    samp_line = lineIndex - 2
                })
            end
        end
    end

    return results
end

-- --------------------------------------------------------
--                           Message
-- --------------------------------------------------------

function AddChatMessage(message, type)
    local _scriptName = "MMT"
    local _pref = "[ ".._scriptName.." ]"
    if type then
        if type == TYPECHATMESSAGES.SECONDARY then _pref = "[ :paperclip: ".._scriptName.." ]" end
        if type == TYPECHATMESSAGES.WARNING then _pref = "[ :warning: ".._scriptName.." ]" end
        if type == TYPECHATMESSAGES.CRITICAL then _pref = "[ :sos: ".._scriptName.." ]" end

        if type == TYPECHATMESSAGES.DEBUG then _pref = "[ :symbols: ".._scriptName.." ]"
            if not settings.main.typeChatMessage.debug then return end end
    end

    if settings.main.typeChatMessage.messages then
        sampAddChatMessage(_pref..': {FFFFFF}'..tostring(message), settings.style.colorMessage)
    end
    if settings.main.typeChatMessage.debug then
        print("["..GetTimeNow().."]: "..message)
    end
end

-- --------------------------------------------------------
--                           Imgui
-- --------------------------------------------------------

function SwitchMainWindow()
    imguiWindows.main[0] = not imguiWindows.main[0]
end

function ScaleUI(num)
    return ISMONETLOADER and num*MONET_DPI_SCALE or num*imgui.GetIO().FontGlobalScale
end

-- Устанавливаем масштаб UI
function SetScaleUI()
    local _scale = settings.style.scaleUI
    imgui.GetIO().FontGlobalScale = 1.0*_scale  -- Увеличит UI
    imgui.GetStyle().ScrollbarSize = settings.style.scrollbarSizeStyle  -- Установить размер скроллбара
    imgui.GetIO().DisplayFramebufferScale = imgui.ImVec2(1.0*_scale, 1.0*_scale)  -- Увеличение для HD экранов
end

-- =====================================================================================================================
--                                                          UTLITES
-- =====================================================================================================================

-- Получить текущее время в формате %H:%M:%S
function GetTimeNow()
    return os.date('%H:%M:%S')
end

function OpenUrl(url)
    os.execute("explorer " .. url)
end

function EnsureDirectoryExists(path)
    local currentPath = ""
    for folder in string.gmatch(path, "[^/\\]+") do
        currentPath = currentPath .. folder .. "/"
        if not lfs.attributes(currentPath, "mode") then
            lfs.mkdir(currentPath)
        end
    end
end

function GetCommaValue(n)
	local left,num,right = string.match(n,'^([^%d]*%d)(%d*)(.-)$')
	return left..(num:reverse():gsub('(%d%d%d)','%1,'):reverse())..right
end

-- =====================================================================================================================
--                                                          INGUI FRAMES
-- =====================================================================================================================

local mainFrame = imgui.OnFrame( function() return imguiWindows.main[0] end, function(player)
    if settings.main.replaceDialog then
        imgui.SetNextWindowPos(imgui.ImVec2(sizeScreanX/ 2, sizeScreanY / 2), imgui.Cond.Appearing, imgui.ImVec2(0.5, 0.5))
    else
        imgui.SetNextWindowPos(imgui.ImVec2(sizeScreanX, sizeScreanY / 2), imgui.Cond.Appearing, imgui.ImVec2(1, 0.5))
    end
    imgui.SetNextWindowSize(imgui.ImVec2(settings.style.sizeWindow.x, settings.style.sizeWindow.y), imgui.Cond.Appearing)

    imgui.Begin(u8("Main Window"), imguiWindows.main, imgui.WindowFlags.NoCollapse + imgui.WindowFlags.NoTitleBar)

        if settings.style.sizeWindow.x ~= imgui.GetWindowSize().x or settings.style.sizeWindow.y ~= imgui.GetWindowSize().y then
            settings.style.sizeWindow.x = imgui.GetWindowSize().x
            settings.style.sizeWindow.y = imgui.GetWindowSize().y
            SaveSettings()
        end

        if imgui.Button("Boosty") then
            OpenUrl("https://boosty.to/sand-mcr")
        end

        imgui.SameLine()

        imgui.CenterText("[MMT] Mining Tool @Mister_Sand")

        imgui.SameLine()

        if imgui.RightButton("\t"..fa.CIRCLE_XMARK.."\t") then
            SwitchMainWindow()
            DeactivateProcessesInteracting()
            sampSendDialogResponse(lastIDDialog, 0, 0, "")
            houses = {}
        end

        imgui.Separator()

        local _widthButtons = (imgui.GetWindowWidth() - ScaleUI(30)) / 2
        if imgui.ButtonClickable(activeTabScript ~= "main", u8"Основное", imgui.ImVec2(_widthButtons, 0)) then
            activeTabScript = "main"
        end
        imgui.SameLine()
        if imgui.ButtonClickable(activeTabScript ~= "settings", u8"Настройки", imgui.ImVec2(-1, 0)) then
            activeTabScript = "settings"
        end

        imgui.Separator()

        if activeTabScript == "main" then
            DrawMainMenu()
        elseif activeTabScript == "settings" then
            DrawSettings()
        end


        posMainFraim = imgui.GetWindowPos()
    imgui.End()
end)

-- =====================================================================================================================
--                                                          DRAWS
-- =====================================================================================================================

function DrawMainMenu()
    imgui.Text(u8(string.format("Охлада: BTC - %s | supper BTC - %s | ASC - %s", haveLiquid.btc, haveLiquid.supper_btc, haveLiquid.asc)))
    imgui.Separator()

    if #houses > 0 then
        DrawHouses()
    else
        DrawShelves()
    end
end

function DrawSettings()
    imgui.Text(u8(string.format("Работа - %s | Заливать - %s | Собирать - %s", stateCrypto.work, processes.fill, processes.take)))
    if stateCrypto.work then
        if imgui.Button(u8"Отменить процесс") then
            DeactivateProcessesInteracting()
        end
    end

    local _fillFrom = new.float(settings.main.fillFrom)
    if imgui.SliderFloat(u8("Заливать, когда "..settings.main.fillFrom.." процентов или ниже"), _fillFrom, 0, 100) then
        settings.main.fillFrom = _fillFrom[0] SaveSettings()
    end

    if imgui.Checkbox(u8"Заменять окно диалога на окно скрипта", new.bool(settings.main.replaceDialog)) then
        settings.main.replaceDialog = not settings.main.replaceDialog SaveSettings()
    end

    local _scrollbarSizeStyle = new.int(settings.style.scrollbarSizeStyle)
    if imgui.SliderInt(u8("Размер скроллбара"), _scrollbarSizeStyle, 10, 50) then
        settings.style.scrollbarSizeStyle = _scrollbarSizeStyle[0] SaveSettings()
        SetStyle()
    end

    local _MONET_DPI_SCALE = new.float(settings.style.scaleUI)
    if imgui.SliderFloat(u8("DPI"), _MONET_DPI_SCALE, 0, 5) then
        settings.style.scaleUI = _MONET_DPI_SCALE[0] SaveSettings()
    end
    if imgui.Button(u8"Перезапустите") then
        thisScript():reload()
    end
    imgui.SameLine()
    imgui.Text(u8("скрипт, чтобы применить /mcrmr"))

    for index, value in ipairs(stateCrypto.queueShelves) do
        imgui.Separator()
        imgui.Text(u8(string.format("Строка - %s | Заливка - %s | Крипты - %s | Состояние - %s", value.samp_line, value.fill, value.count, value.work)))
    end
end

function DrawHouses()
    imgui.BeginChild("list", imgui.ImVec2(-1, -1))
    for i, house in ipairs(houses) do
        -- Определяем цвета для циклов и банка
        local cycles_color = house.cycles < 100 and colors.RED or colors.WHITE -- красный если < 100, белый если >= 100

        local _bank_now_str = house.bankNow:gsub("[^%d]", "")
        local bank_now = tonumber(_bank_now_str) or 0
        local bank_color = colors.WHITE

        if bank_now < 5000000 then
            bank_color = colors.RED
        elseif bank_now < 10000000 then
            bank_color = colors.YELLOW
        end

        if imgui.Button(u8("Открыть##")..i) then
            sampSendDialogResponse(idDialogs.selectHouse, 1, house.samp_line, "")
            houses = {}
        end
        imgui.SameLine()

        -- Заголовок дома
        imgui.Text(u8(string.format("Дом №%s (%s) - Налог: %s", 
            house.house_number, house.city, house.tax)))

        -- Строка с циклами и банком в одной строке
        imgui.SameLine(0, 0)
        imgui.TextColoredRGB(string.format("  {%s}Циклов:{%s} %s",
            colors.WHITE, cycles_color, GetCommaValue(house.cycles)))

        imgui.SameLine()
        imgui.TextColoredRGB(string.format("  {%s}Банк:{%s} %s/%s$",
            colors.WHITE, bank_color, GetCommaValue(house.bankNow), GetCommaValue(house.bankMax)))

        -- Добавляем небольшой отступ между домами
        if i < #houses then
            imgui.Spacing()
        end
    end
    imgui.EndChild()
end

function DrawShelves()
    -- Подсчет статистики полок
    local total_shelves = #shelves
    local working_shelves = 0
    local not_working_shelves = 0
    local low_liauid = 0

    for _, shelf in ipairs(shelves) do
        if shelf.status:find("Работает") then
            working_shelves = working_shelves + 1
        else
            not_working_shelves = not_working_shelves + 1
        end

        if shelf.percentage <= settings.main.fillFrom then
            low_liauid = low_liauid + 1
        end
    end

    -- Отображение статистики
    imgui.Text(u8(string.format("Найдено полок: %d", total_shelves)))
    imgui.SameLine()
    imgui.TextColoredRGB(string.format("  Работают:{%s} %d",
        working_shelves > 0 and colors.GREEN or colors.RED,
        working_shelves))
    imgui.SameLine()
    imgui.TextColoredRGB(string.format("  Не работают:{%s} %d", colors.RED, not_working_shelves))
    imgui.TextColoredRGB(string.format("Нет или мало охлаждайки:{%s} %d", colors.YELLOW, low_liauid))

    imgui.Spacing()

    if stateCrypto.work then
        imgui.ProgressBar(stateCrypto.progressShelves/#stateCrypto.queueShelves,imgui.ImVec2(-1,0), stateCrypto.progressShelves.."/"..#stateCrypto.queueShelves)
    end

    -- Первая строка кнопок: Собрать и Залить
    local button_width = (imgui.GetWindowWidth() - ScaleUI(30)) / 2 -- ширина для 2 кнопок в ряд

    if imgui.Button(fa.HAND_HOLDING_DOLLAR .. u8" Собрать всё", imgui.ImVec2(button_width, 0)) then
        StartProcessInteracting("take")
    end
    imgui.SameLine()
    if imgui.Button(fa.FILL_DRIP .. u8" Залить всё", imgui.ImVec2(-1, 0)) then
        StartProcessInteracting("fill")
    end

    -- Вторая строка кнопок: Включить и Отключить
    if imgui.Button(fa.TOGGLE_ON .. u8" Включить всё", imgui.ImVec2(button_width, 0)) then
        StartProcessInteracting("on")
    end
    imgui.SameLine()
    if imgui.Button(fa.TOGGLE_OFF .. u8" Отключить всё", imgui.ImVec2(-1, 0)) then
        StartProcessInteracting("off")
    end

    imgui.Separator()

    imgui.BeginChild("list", imgui.ImVec2(-1, -1))
    for i, shelf in ipairs(shelves) do
        local shelf_in_rack = math.floor(i / 4) + 1

        -- Показываем заголовок стойки только для первой полки в стойке
        if shelf.shelf_number == 1 and #shelves > 4 then
            if i > 1 then imgui.Spacing() end
            imgui.Text(u8(string.format("=== Стойка №%d ===", shelf_in_rack)))
        end

        local cooling_color = colors.WHITE
        if shelf.percentage == 0 then
            cooling_color = colors.RED
        elseif shelf.percentage < 50 then
            cooling_color = colors.YELLOW
        end

        local profit_color = shelf.profit > 1 and colors.GREEN or colors.WHITE -- зеленый если > 1, белый если <= 1

        local gpu_color = colors.RED
        if shelf.status:find("Работает") then
            gpu_color = colors.GREEN
        end

        if imgui.Button(u8(string.format("Открыть##%d", i))) then
            sampSendDialogResponse(lastIDDialog, 1, shelf.samp_line, "")
            imguiWindows.main[0] = false
        end
        imgui.SameLine()

        imgui.TextColoredRGB(string.format("Полка №%d Ур.%d {%s}%s {%s}%.6f %s {%s}%.1f%%",
            shelf.shelf_number,
            shelf.level,
            gpu_color, shelf.status,
            profit_color, shelf.profit, shelf.currency,
            cooling_color, shelf.percentage))
    end
    imgui.EndChild()
end

-- --------------------------------------------------------
--                           Extension
-- --------------------------------------------------------

function imgui.ButtonClickable(clickable, ...)
    if clickable then
        return imgui.Button(...)
    else
        local rcol = (imgui.GetStyle().Colors[imgui.Col.Button])
		local r, g, b, a = rcol.x, rcol.y, rcol.z, rcol.w
        imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(r, g, b, a/2) )
        imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(r, g, b, a/2))
        imgui.PushStyleColor(imgui.Col.ButtonActive, imgui.ImVec4(r, g, b, a/2))
        imgui.PushStyleColor(imgui.Col.Text, imgui.GetStyle().Colors[imgui.Col.TextDisabled])
            imgui.Button(...)
        imgui.PopStyleColor()
        imgui.PopStyleColor()
        imgui.PopStyleColor()
        imgui.PopStyleColor()
    end
end

-- Функция для создания кнопки, выровненной по правому краю
function imgui.RightButton(label)
    local _clearLabel = label:gsub("##.-", "")
    imgui.SetItemRight(_clearLabel)

    if imgui.Button(label) then
        return true
    end
end

function imgui.SetItemRight(label)
    local window_size = imgui.GetWindowSize()

    local button_size = imgui.CalcTextSize(label)
    button_size.x = button_size.x + imgui.GetStyle().FramePadding.x * 2
    button_size.y = button_size.y + imgui.GetStyle().FramePadding.y * 2

    local _offsetScroll = imgui.GetScrollMaxY() > 0 and imgui.GetStyle().ScrollbarSize or 0
    local new_cursor_pos_x = window_size.x - button_size.x - imgui.GetStyle().WindowPadding.x - _offsetScroll
    imgui.SetCursorPosX(new_cursor_pos_x)
end

function imgui.CenterText(text, size)
	local _size = size or imgui.GetWindowWidth()
	imgui.SetCursorPosX((_size - imgui.CalcTextSize(tostring(text)).x) / 2)
	imgui.Text(tostring(text))
end

function imgui.TextColoredRGB(text)
    local style = imgui.GetStyle()
    local colors = style.Colors[imgui.Col.Text]
    local ImVec4 = imgui.ImVec4
    local explode_argb = function(argb)
        local a = bit.band(bit.rshift(argb, 24), 0xFF)
        local r = bit.band(bit.rshift(argb, 16), 0xFF)
        local g = bit.band(bit.rshift(argb, 8), 0xFF)
        local b = bit.band(argb, 0xFF)
        return a, r, g, b
    end
    local getcolor = function(color)
        if color:sub(1, 6):upper() == 'SSSSSS' then
            local r, g, b = colors.x, colors.y, colors.z
            local a = tonumber(color:sub(7, 8), 16) or colors.w * 255
            return ImVec4(r, g, b, a / 255)
        end
        local color = type(color) == 'string' and tonumber(color, 16) or color
        if type(color) ~= 'number' then return end
        local r, g, b, a = explode_argb(color)
        return imgui.ImVec4(r/255, g/255, b/255, a/255)
    end
    local render_text = function(text_)
        for w in text_:gmatch('[^\r\n]+') do
            local text, colors_, m = {}, {}, 1
            w = w:gsub('{(......)}', '{%1FF}')
            while w:find('{........}') do
                local n, k = w:find('{........}')
                local color = getcolor(w:sub(n + 1, k - 1))
                if color then
                    text[#text], text[#text + 1] = w:sub(m, n - 1), w:sub(k + 1, #w)
                    colors_[#colors_ + 1] = color
                    m = n
                end
                w = w:sub(1, n - 1) .. w:sub(k + 1, #w)
            end
            if text[0] then
                for i = 0, #text do
                    imgui.TextColored(colors_[i] or colors, u8(text[i]))
                    imgui.SameLine(nil, 0)
                end
                imgui.NewLine()
            else imgui.Text(u8(w)) end
        end
    end
    render_text(text)
end

-- --------------------------------------------------------
--                           Style
-- --------------------------------------------------------

local function MainStyle()
    settings.style.colorChat, settings.style.colorMessage = '8cbf91', 0xFF8cbf91

    local style = imgui.GetStyle()
    local colors = style.Colors
    local clr = imgui.Col
    local ImVec4 = imgui.ImVec4
    local ImVec2 = imgui.ImVec2
    style.WindowPadding = ImVec2(8, 8)
    style.WindowRounding = 10
    style.ChildRounding = 8
    style.FramePadding = ImVec2(6, 4)
    style.FrameRounding = 8
    style.ItemSpacing = ImVec2(6, 6)
    style.ItemInnerSpacing = ImVec2(4, 4)
    style.IndentSpacing = 21
    style.ScrollbarSize = settings.style.scrollbarSizeStyle
    style.ScrollbarRounding = 13
    style.GrabMinSize = 8
    style.GrabRounding = 1
    style.WindowTitleAlign = ImVec2(0.5, 0.5)
    style.ButtonTextAlign = ImVec2(0.5, 0.5)
    return colors, clr, ImVec4
end

function SetStyle()
    local colors, clr, ImVec4 = MainStyle()

    local mainColor = settings.style.mainColor
    local textColor = settings.style.textColor
    local bgColor = settings.style.bgColor

    colors[clr.Text] = ImVec4(textColor.r, textColor.g, textColor.b, textColor.a)
    colors[clr.TextDisabled] = ImVec4(textColor.r * 0.5, textColor.g * 0.5, textColor.b * 0.5, textColor.a)
    colors[clr.WindowBg] = ImVec4(bgColor.r, bgColor.g, bgColor.b, bgColor.a)
    colors[clr.PopupBg] = ImVec4(bgColor.r, bgColor.g, bgColor.b, bgColor.a)
    colors[clr.Border] = ImVec4(mainColor.r, mainColor.g, mainColor.b, 1)
    colors[clr.BorderShadow] = ImVec4(mainColor.r + 0.1, mainColor.g + 0.1, mainColor.b + 0.1, 0.1)
    colors[clr.FrameBg] = ImVec4(mainColor.r, mainColor.g, mainColor.b, mainColor.a)
    colors[clr.FrameBgHovered] = ImVec4(mainColor.r + 0.05, mainColor.g + 0.05, mainColor.b + 0.05, mainColor.a)
    colors[clr.FrameBgActive] = ImVec4(mainColor.r + 0.1, mainColor.g + 0.1, mainColor.b + 0.1, mainColor.a)
    colors[clr.Button] = ImVec4(mainColor.r, mainColor.g, mainColor.b, mainColor.a * 0.83)
    colors[clr.ButtonHovered] = ImVec4(mainColor.r * 0.8, mainColor.g * 0.8, mainColor.b * 0.8, mainColor.a * 0.83)
    colors[clr.ButtonActive] = ImVec4(mainColor.r + 0.05, mainColor.g + 0.05, mainColor.b + 0.05, mainColor.a * 0.83)
    colors[clr.Header] = ImVec4(mainColor.r, mainColor.g, mainColor.b, mainColor.a * 0.83)
    colors[clr.HeaderHovered] = ImVec4(mainColor.r * 0.8, mainColor.g * 0.8, mainColor.b * 0.8, mainColor.a * 0.83)
    colors[clr.HeaderActive] = ImVec4(mainColor.r + 0.05, mainColor.g + 0.05, mainColor.b + 0.05, mainColor.a * 0.83)
    colors[clr.Separator] = ImVec4(mainColor.r, mainColor.g, mainColor.b, 1)
    colors[clr.SeparatorHovered] = ImVec4(mainColor.r + 0.05, mainColor.g + 0.05, mainColor.b + 0.05, 1)
    colors[clr.SeparatorActive] = ImVec4(mainColor.r + 0.1, mainColor.g + 0.1, mainColor.b + 0.1, 1)
    colors[clr.ResizeGrip] = ImVec4(mainColor.r * 1.2, mainColor.g * 1.3, mainColor.b * 1.4, 1)
    colors[clr.ResizeGripHovered] = ImVec4(mainColor.r * 1.1, mainColor.g * 1.2, mainColor.b * 1.3, 1)
    colors[clr.ResizeGripActive] = ImVec4(mainColor.r * 1.3, mainColor.g * 1.4, mainColor.b * 1.5, 1)
    colors[clr.PlotLines] = ImVec4(mainColor.r * 0.8, mainColor.g * 0.9, mainColor.b, 1)
    colors[clr.PlotLinesHovered] = ImVec4(bgColor.r, bgColor.g, bgColor.b, bgColor.a)
    colors[clr.PlotHistogram] = ImVec4(mainColor.r + 0.1, mainColor.g + 0.1, mainColor.b + 0.1, 1)
    colors[clr.PlotHistogramHovered] = ImVec4(bgColor.r, bgColor.g, bgColor.b, bgColor.a)
    colors[clr.TextSelectedBg] = ImVec4(mainColor.r * 0.7, mainColor.g * 0.8, mainColor.b * 0.9, 1)
    colors[clr.ModalWindowDimBg] = ImVec4(0, 0, 0, 0.7)

    -- Продолжение с настройками для остальных элементов
    colors[clr.TitleBg] = ImVec4(bgColor.r, bgColor.g, bgColor.b, bgColor.a)
    colors[clr.TitleBgActive] = ImVec4(bgColor.r, bgColor.g, bgColor.b, bgColor.a)
    colors[clr.TitleBgCollapsed] = ImVec4(bgColor.r, bgColor.g, bgColor.b, bgColor.a)
    colors[clr.MenuBarBg] = ImVec4(bgColor.r, bgColor.g, bgColor.b, bgColor.a)
    colors[clr.ScrollbarBg] = ImVec4(bgColor.r, bgColor.g, bgColor.b, bgColor.a)
    colors[clr.ScrollbarGrab] = ImVec4(mainColor.r * 2, mainColor.g * 2, mainColor.b * 2, 1)
    colors[clr.ScrollbarGrabHovered] = ImVec4(mainColor.r * 2.4, mainColor.g * 2.4, mainColor.b * 2.4, 1)
    colors[clr.ScrollbarGrabActive] = ImVec4(mainColor.r * 2.2, mainColor.g * 2.2, mainColor.b * 2.2, 1)
    colors[clr.CheckMark] = ImVec4(mainColor.r * 1.2, mainColor.g * 1.4, mainColor.b * 1.6, 1)
    colors[clr.SliderGrab] = ImVec4(mainColor.r * 1.2, mainColor.g * 1.3, mainColor.b * 1.4, 1)
    colors[clr.SliderGrabActive] = ImVec4(mainColor.r, mainColor.g, mainColor.b, 1)
end