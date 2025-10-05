-- =====================================================================================================================
--                                                          Header
-- =====================================================================================================================

script_authors('Sand')
script_description('Mining assistant TG: @Mister_Sand')
script_version("1.2")

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
local keysSuccess,      keys        = CheckLibrary('vkeys')

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

local COLORS = {
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
        },
        -- Черный список домов, которые нужно скрыть
        blackListHouses = {},
        maxBankAmount = 19999999 - 10000,
        -- Закрывать ли на ESC
        closeOnESC = true,
        -- Скрывать текст полученной крипты
        hideMessagesCollect = true,
    },
    deley = {
        timeoutDialog = 10,
        waitInterval = 10,
        timeoutShelf = 10,
        -- Ждать перед отправкой ответа на диалог
        waitRun = 0,
    },
    style = {
        -- масштаб интерфейса
        scaleUI = 1.0,
        -- Цвет в тексте
        colorChat = '8cbf91',
        -- Цвет текста
        colorMessage = 0xFF8cbf91,
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

local inputBlackHouse = new.int()

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
    -- Ожидаме заливки видяхи
    waitFill = false,
    -- Ожидаем пополнения дома
    waitDep = false,
    -- Количество, которое снимаем крипты
    takeCount = 0,
    -- Прогресс домов
    progressHouses = 0,
    -- Список домов в очереди
    queueHouses = {},
    -- Прогресс полок
    progressShelves = 0,
    -- Список полок в очереди
    queueShelves = {},
    -- Прогресс домов банка
    progressHousesBank = 0,
    -- Список домов банка в очереди
    queueHousesBank = {},
    -- Идентификатор текущего дома (номер) и валюта текущего take
    currentHouseId = nil,
    takeCurrency = nil,
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
    -- пополнить банк
    dep = false,
}

local haveLiquid = {
    btc = 0,
    supper_btc = 0,
    asc = 0,
}

-- Статистика по сбору
local collectStats = {
    total = { BTC = 0, ASC = 0 },
    house = {}  -- [house_number] = { BTC = 0, ASC = 0 }
}

-- Доступные полки
local shelves = {}

local houses = {}

local housesBanks = {}

local lastIDDialog = 0

local lastOpenHouse = 1

-- --------------------------------------------------------
--                           Class
-- --------------------------------------------------------

-- Утилиты для работы с диалогами в Interacting
local DialogUtils = {}

-- Класс для обработки домов
local HouseProcessor = {}

-- Класс для обработки полок
local ShelfProcessor = {}

-- =====================================================================================================================
--                                                          MAIN
-- =====================================================================================================================

imgui.OnInitialize(function()
    if ISMONETLOADER and settings.style.scaleUI ~= 1.0 then
        MONET_DPI_SCALE = settings.style.scaleUI
    elseif ISMONETLOADER then
        settings.style.scaleUI = MONET_DPI_SCALE
    end

    if not ISMONETLOADER then
        SetScaleUI()
    end

    SetStyle(ISMONETLOADER)

    if ISMONETLOADER then
        fa.Init(14*MONET_DPI_SCALE)
    else
        fa.Init(14)
    end
end)

function main()
    while not isSampAvailable() do wait(0) end

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

    AddChatMessage('Скрипт загружен. Команда активации: {'..settings.style.colorChat..'}/mmt{FFFFFF}.')

    processInteractingThread = lua_thread.create_suspended(ProcessInteracting)
end

-- =====================================================================================================================
--                                                          SAMP EVENTS
-- =====================================================================================================================

-- --------------------------------------------------------
--                           onServerMessage
-- --------------------------------------------------------

function sampev.onServerMessage(color, text)
    if stateCrypto.work then
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

        if text:find("Вы успешно пополнили счёт дома за электроэнергию на ") and color == 1941201407 then
            stateCrypto.waitDep = false
        end

        if text:find("В этом доме нет подвала с вентиляцией или он еще не достроен") and color == -1104335361 then
            DeactivateProcessesInteracting()
            AddChatMessage("Вы можете добавить данный дом в чёрный список, чтобы его скрыть", TYPECHATMESSAGES.SECONDARY)
        end

        if text:find("У Вас недостаточно денежных средств!") and color == -1104335361 then
            DeactivateProcessesInteracting()
        end

        if  text:find("осталось на счету видеокарты:") or (
                text:find("Вам был добавлен предмет") and (
                    text:find(":item1811:", nil, true) or
                    text:find(":item5996:", nil, true)
                )
            ) and
            color == -65281 and
            settings.main.hideMessagesCollect then
            return false
        end
    end
end

-- --------------------------------------------------------
--                           onShowDialog
-- --------------------------------------------------------

function sampev.onShowDialog(dialogId, style, title, button1, button2, text)
    lastIDDialog = dialogId

    if stateCrypto.work and processes.dep and title:find("{73B461}Баланс домашнего счёта") then
        local _dep = text:match("Можно пополнить счёт ещё на:%s*{%w+}%$([%d%.,]+)")
        if _dep then
            _dep = _dep:gsub(",", ""):gsub("%.", "")
        end

        _dep = tonumber(_dep)-1 > 10000000 and 10000000 or tonumber(_dep)-1
        DialogUtils.waitAndSendDialogResponse(dialogId, 1, 0, tostring(_dep))
        stateCrypto.queueHousesBank[stateCrypto.progressHousesBank].bankNow = stateCrypto.queueHousesBank[stateCrypto.progressHousesBank].bankNow + _dep
        return not settings.main.replaceDialog
    end

    if stateCrypto.work and processes.take and title:find("Вывод прибыли видеокарты") then
        local continue = stateCrypto.queueShelves[stateCrypto.progressShelves].count - stateCrypto.takeCount
        stateCrypto.queueShelves[stateCrypto.progressShelves].count = continue
        if stateCrypto.takeCount and stateCrypto.takeCount > 0 and stateCrypto.takeCurrency then
            local cur = stateCrypto.takeCurrency
            -- итого по всем домам
            collectStats.total[cur] = (collectStats.total[cur] or 0) + stateCrypto.takeCount
            -- итого по текущему дому (если он известен)
            local hid = stateCrypto.currentHouseId or 0
            collectStats.house[hid] = collectStats.house[hid] or { BTC = 0, ASC = 0 }
            collectStats.house[hid][cur] = (collectStats.house[hid][cur] or 0) + stateCrypto.takeCount
        end
        DialogUtils.waitAndSendDialogResponse(dialogId, 1, 0, "")
        stateCrypto.takeCount = 0
        stateCrypto.takeCurrency = nil
        return not settings.main.replaceDialog
    end

    if stateCrypto.work and title:find("Стойка") and title:find("Полка") then
        local actions = ParseShelfVideoCardData(text)

        for index, value in ipairs(actions) do
            -- AddChatMessage(value.action.." - "..value.samp_line.." - "..value.count)

            if processes.take then
                if  value.count > 0 and (value.action == "take_btc" or value.action == "take_asc") then
                    stateCrypto.takeCount = value.count
                    stateCrypto.takeCurrency = (value.action == "take_btc") and "BTC" or "ASC"
                    DialogUtils.waitAndSendDialogResponse(dialogId, 1, value.samp_line, "")
                    return not settings.main.replaceDialog
                elseif math.floor(stateCrypto.queueShelves[stateCrypto.progressShelves].count) <= 0 then
                    stateCrypto.progressShelves = stateCrypto.progressShelves +1
                    DialogUtils.waitAndSendDialogResponse(dialogId, 0, 0, "")
                    return not settings.main.replaceDialog
                end
            end

            if processes.fill and value.action == "fill" then
                if stateCrypto.queueShelves[stateCrypto.progressShelves].fill > settings.main.fillFrom then
                    stateCrypto.progressShelves = stateCrypto.progressShelves +1
                    DialogUtils.waitAndSendDialogResponse(dialogId, 0, 0, "")
                    return not settings.main.replaceDialog
                end
                DialogUtils.waitAndSendDialogResponse(dialogId, 1, value.samp_line, "")
                return not settings.main.replaceDialog
            end

            if processes.on and value.action == "on" then
                DialogUtils.waitAndSendDialogResponse(dialogId, 1, value.samp_line, "")
                return not settings.main.replaceDialog
            elseif processes.on and value.action == "off" then
                stateCrypto.queueShelves[stateCrypto.progressShelves].work = true
                stateCrypto.progressShelves = stateCrypto.progressShelves +1
                DialogUtils.waitAndSendDialogResponse(dialogId, 0, 0, "")
                return not settings.main.replaceDialog
            end

            if processes.off and value.action == "off" then
                DialogUtils.waitAndSendDialogResponse(dialogId, 1, value.samp_line, "")
                return not settings.main.replaceDialog
            elseif processes.off and value.action == "on" then
                stateCrypto.queueShelves[stateCrypto.progressShelves].work = false
                stateCrypto.progressShelves = stateCrypto.progressShelves +1
                DialogUtils.waitAndSendDialogResponse(dialogId, 0, 0, "")
                return not settings.main.replaceDialog
            end
        end
        return not settings.main.replaceDialog
    end

    if stateCrypto.work and processes.fill and not stateCrypto.waitFill and title:find("Выберите тип жидкости") then
        local actions = ParseLiquidData(text)

        -- Соберём наличие
        local counts = { btc = 0, supper_btc = 0, asc = 0 }
        local lines  = { btc = nil, supper_btc = nil, asc = nil }

        for _, v in ipairs(actions) do
            if v.action == "btc"         then counts.btc        = v.count or 0; lines.btc        = v.samp_line end
            if v.action == "supper_btc"  then counts.supper_btc = v.count or 0; lines.supper_btc = v.samp_line end
            if v.action == "asc"         then counts.asc        = v.count or 0; lines.asc        = v.samp_line end
        end

        haveLiquid.btc        = counts.btc
        haveLiquid.supper_btc = counts.supper_btc
        haveLiquid.asc        = counts.asc

        -- Тип карты из текущей очереди полок:
        local cur = stateCrypto.queueShelves[stateCrypto.progressShelves]
        local card = cur and cur.card_type or nil  -- "ASIC" | "BTC" | "ASC" | nil

        -- Фолбэк: если в самом диалоге есть фраза про ASIC — подстрахуемся
        if (not card or card == "BTC") and (text:find("ASIC") or text:find("Достать ASIC")) then
            card = "ASIC"
        end

        -- Выбор по типу карты
        local choice = nil
        if card == "ASC" then
            if counts.asc > 0 then choice = "asc" end
        else
            -- BTC или ASIC (или тип не определён) — не льём ASC для BTC/ASIC
            if counts.btc > 0 then
                choice = "btc"
            elseif counts.supper_btc > 0 then
                choice = "supper_btc"
            elseif not card and counts.asc > 0 then
                -- Тип не распознан: разрешим asc как крайний случай
                choice = "asc"
            end
        end

        if choice then
            stateCrypto.waitFill = true
            DialogUtils.waitAndSendDialogResponse(dialogId, 1, lines[choice], "")
            return not settings.main.replaceDialog
        else
            processes.fill = false
            local reason = (card == "ASC") and "нет охлаждайки ASC" or "нет охлаждайки BTC/super"
            AddChatMessage("Охлаждение: " .. reason .. " для текущей карты", TYPECHATMESSAGES.CRITICAL)
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

    if title:find("Выбор дома") then
        houses = {}
        housesBanks ={}

        if text:find("Энергия") then
            houses = ParseHouseData(text)
        elseif text:find("Баланс") then
            housesBanks = ParseHouseBankData(text)
        else
            return true
        end

        idDialogs.selectHouse = dialogId

        imguiWindows.main[0] = true

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
        housesBanks ={}
    end

    if id == idDialogs.selectVideoCard then
        imguiWindows.main[0] = false
    end

end

-- --------------------------------------------------------
--                           onWindowMessage
-- --------------------------------------------------------

function onWindowMessage(msg, wparam, lparam)
    if not keysSuccess then return end
    local isEscapePressed = (wparam == keys.VK_ESCAPE)
    local shouldCloseOnEsc = settings.main.closeOnESC
    local isMainWindowActive = imguiWindows.main[0]
    local isPauseInactive = not isPauseMenuActive()

    if (msg == 0x100 or msg == 0x101) and isEscapePressed and isMainWindowActive and isPauseInactive and shouldCloseOnEsc then
        consumeWindowMessage(true, false)
        if msg == 0x101 then
            SwitchMainWindow()
            DeactivateProcessesInteracting()
            sampSendDialogResponse(lastIDDialog, 0, 0, "")
            houses = {}
        end
    end
end

-- =====================================================================================================================
--                                                          FUNCTIONS
-- =====================================================================================================================

function CheckHouseInBlackList(number)
    for index, value in ipairs(settings.main.blackListHouses) do
        if tonumber(number) == value then return true end
    end
    return false
end

-- --------------------------------------------------------
--                           Dialog Utils
-- --------------------------------------------------------

function DialogUtils.waitForDialog(expectedDialogId, timeoutSeconds)
    local timeout = os.clock() + (timeoutSeconds or settings.deley.timeoutDialog)

    while lastIDDialog ~= expectedDialogId do
        wait(settings.deley.waitInterval)

        if os.clock() > timeout then
            return false, "Timeout waiting for dialog " .. tostring(expectedDialogId)
        end

        if not CheckProcessInteracting() then
            return false, "Process was interrupted"
        end
    end

    return true
end

function DialogUtils.waitForAnyDialog(expectedDialogIds, timeoutSeconds)
    local timeout = os.clock() + (timeoutSeconds or settings.deley.timeoutDialog)

    while true do
        for _, dialogId in ipairs(expectedDialogIds) do
            if lastIDDialog == dialogId then
                return true, dialogId
            end
        end

        wait(settings.deley.waitInterval)

        if os.clock() > timeout then
            local dialogNames = table.concat(expectedDialogIds, ", ")
            return false, "Timeout waiting for any dialog: " .. dialogNames
        end

        if not CheckProcessInteracting() then
            return false, "Process was interrupted"
        end
    end
end

function DialogUtils.sendResponseAndWait(dialogId, button, listitem, input, waitCondition)
    sampSendDialogResponse(dialogId, button, listitem, input or "")

    if waitCondition then
        local timeout = os.clock() + settings.deley.timeoutDialog
        while not waitCondition() do
            wait(settings.deley.waitInterval)
            if os.clock() > timeout then
                return false, "Timeout waiting for condition"
            end
            if not CheckProcessInteracting() then
                return false, "Process was interrupted"
            end
        end
    end

    return true
end

-- Запускает поток, в котором ждем время на ответ и отвечаем
function DialogUtils.waitAndSendDialogResponse(dialogId, button, listitem, input, waitRun)
    lua_thread.create(function ()
        waitRun = waitRun or settings.deley.waitRun

        local timeout = os.clock() + waitRun/1000
        while os.clock() < timeout do
            wait(settings.deley.waitInterval)
        -- AddChatMessage(os.clock().." - "..timeout)

        end

        sampSendDialogResponse(dialogId, button, listitem, input or "")
    end)
end

-- --------------------------------------------------------
--                           Shelf Processor
-- --------------------------------------------------------

function ShelfProcessor.filterShelves()
    local filtered = {}

    for _, shelf in ipairs(shelves) do
        local shouldProcess = (
            (shelf.status == "Работает" and processes.off) or
            (shelf.status ~= "Работает" and processes.on and shelf.percentage > 0) or
            (shelf.profit >= 1.0 and processes.take) or
            (shelf.percentage <= settings.main.fillFrom and processes.fill)
        )

        if shouldProcess then
            table.insert(filtered, {
                samp_line = shelf.samp_line,
                fill = shelf.percentage,
                work = shelf.status == "Работает",
                count = shelf.profit + (shelf.profit2 or 0),
                card_type = shelf.card_type
            })
        end
    end

    return filtered
end

function ShelfProcessor.process()
    stateCrypto.progressShelves = 1
    stateCrypto.queueShelves = ShelfProcessor.filterShelves()

    if #stateCrypto.queueShelves == 0 then
        AddChatMessage("Отсутствуют полки для работы", TYPECHATMESSAGES.WARNING)
        return true
    end

    for index, shelfData in ipairs(stateCrypto.queueShelves) do
        local success, dialogId = DialogUtils.waitForAnyDialog({
            idDialogs.selectVideoCardItemFlash,
            idDialogs.selectVideoCard
        })

        if not success then
            AddChatMessage("Ошибка ожидания диалога полок: " .. dialogId, TYPECHATMESSAGES.CRITICAL)
            return false
        end

        local oldProgress = stateCrypto.progressShelves
        local progressUpdated = function()
            return stateCrypto.progressShelves ~= oldProgress
        end

        success, error = DialogUtils.sendResponseAndWait(
            lastIDDialog, 1, shelfData.samp_line, "", progressUpdated
        )

        if not success then
            AddChatMessage("Ошибка обработки полки: " .. error, TYPECHATMESSAGES.CRITICAL)
            return false
        end
    end

    return true
end

-- --------------------------------------------------------
--                           House Processor
-- --------------------------------------------------------

function HouseProcessor.filterBankHouses()
    local filtered = {}

    for _, house in ipairs(housesBanks) do
        if tonumber(house.bankNow) <= settings.main.maxBankAmount then
            table.insert(filtered, {
                samp_line = house.samp_line,
                bankNow = house.bankNow
            })
        end
    end

    return filtered
end

function HouseProcessor.processBankHouses()
    stateCrypto.progressHousesBank = 1
    stateCrypto.queueHousesBank = HouseProcessor.filterBankHouses()

    if #stateCrypto.queueHousesBank == 0 then
        return true
    end

    for index, houseData in ipairs(stateCrypto.queueHousesBank) do
        local success, error = DialogUtils.waitForDialog(idDialogs.selectHouse)
        if not success then
            AddChatMessage("Ошибка ожидания диалога дома: " .. error, TYPECHATMESSAGES.CRITICAL)
            return false
        end

        sampSendDialogResponse(lastIDDialog, 1, houseData.samp_line, "")
        lastOpenHouse = index
        stateCrypto.waitDep = true

        -- Ждем завершения операции депозита
        local timeout = os.clock() + settings.deley.timeoutDialog
        while stateCrypto.waitDep do
            wait(settings.deley.waitInterval)
            if os.clock() > timeout then
                AddChatMessage("Timeout при ожидании депозита", TYPECHATMESSAGES.CRITICAL)
                return false
            end
            if not CheckProcessInteracting() then
                return false
            end
        end

        -- Дополнительная проверка и повторная операция если нужно
        if tonumber(houseData.bankNow) <= settings.main.maxBankAmount then
            sampSendDialogResponse(lastIDDialog, 1, houseData.samp_line, "")
            stateCrypto.waitDep = true

            timeout = os.clock() + settings.deley.timeoutDialog
            while stateCrypto.waitDep do
                wait(settings.deley.waitInterval)
                if os.clock() > timeout then
                    AddChatMessage("Timeout при повторном депозите", TYPECHATMESSAGES.CRITICAL)
                    return false
                end
                if not CheckProcessInteracting() then
                    return false
                end
            end
        end

        stateCrypto.progressHousesBank = stateCrypto.progressHousesBank + 1
    end

    return true
end

function HouseProcessor.processRegularHouses()
    stateCrypto.progressHouses = 1
    stateCrypto.queueHouses = {}

    for _, house in ipairs(houses) do
        table.insert(stateCrypto.queueHouses, {
            samp_line = house.samp_line,
        })
    end

    for index, houseData in ipairs(stateCrypto.queueHouses) do
        local success, error = DialogUtils.waitForDialog(idDialogs.selectHouse)
        if not success then
            AddChatMessage("DeactivateProcessesInteracting - " .. error, TYPECHATMESSAGES.CRITICAL)
            return false
        end

        -- Очищаем данные полок для нового дома
        shelves = {}
        stateCrypto.queueShelves = {}

        sampSendDialogResponse(lastIDDialog, 1, houseData.samp_line, "")
        lastOpenHouse = index
        stateCrypto.currentHouseId = houses[index] and houses[index].house_number or nil
        if stateCrypto.currentHouseId and not collectStats.house[stateCrypto.currentHouseId] then
            collectStats.house[stateCrypto.currentHouseId] = { BTC = 0, ASC = 0 }
        end

        -- Ждем загрузки полок с таймаутом
        local timeout = os.clock() + settings.deley.timeoutShelf
        local shelvesLoaded = false

        while not shelvesLoaded do
            wait(10)

            if #shelves > 0 then
                shelvesLoaded = true
            elseif os.clock() > timeout then
                AddChatMessage("Не смог получить полки для дома " .. index, TYPECHATMESSAGES.WARNING)
                break
            end

            if not CheckProcessInteracting() then
                return false
            end
        end

        if shelvesLoaded then
            local shelfSuccess = ShelfProcessor.process()
            if not shelfSuccess then
                return false
            end
        end

        -- Закрываем диалог дома
        while lastIDDialog ~= idDialogs.selectHouse do
            sampSendDialogResponse(lastIDDialog, 0, 0, "")
            wait(settings.deley.waitInterval)

            if not CheckProcessInteracting() then
                return false
            end
        end

        stateCrypto.progressHouses = stateCrypto.progressHouses + 1

        if stateCrypto.currentHouseId and collectStats.house[stateCrypto.currentHouseId] then
            local s = collectStats.house[stateCrypto.currentHouseId]
            AddChatMessage(string.format(
                "Дом №%s: собрано %s BTC и %s ASC",
                tostring(stateCrypto.currentHouseId), s.BTC or 0, s.ASC or 0
            ), TYPECHATMESSAGES.SECONDARY)
        end
        stateCrypto.currentHouseId = nil
    end

    return true
end

function StartProcessInteracting(action)
    if stateCrypto.work then AddChatMessage("Процесс уже запущен", TYPECHATMESSAGES.WARNING) end
    DeactivateProcessesInteracting()

    if action == "fill" then
        processes.fill = true
    elseif action == "take" then
        processes.take = true
        collectStats = { total = { BTC = 0, ASC = 0 }, house = {} }
        stateCrypto.currentHouseId = nil
    elseif action == "on" then
        processes.on = true
    elseif action == "off" then
        processes.off = true
    elseif action == "dep" then
        processes.dep = true
    else
        AddChatMessage("Нет действий", TYPECHATMESSAGES.CRITICAL)
        return false
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
    -- Инициализация
    stateCrypto.work = true

    local success = true

    -- Обрабатываем дома с банками
    if #housesBanks > 0 then
        success = HouseProcessor.processBankHouses()
        if not success then
            DeactivateProcessesInteracting()
            return
        end
    end

    -- Обрабатываем обычные дома или полки напрямую
    if #houses > 0 then
        success = HouseProcessor.processRegularHouses()
    else
        success = ShelfProcessor.process()
    end

    if not success then
        DeactivateProcessesInteracting()
        return
    end

    DeactivateProcessesInteracting()
    AddChatMessage("Обработка завершена успешно", TYPECHATMESSAGES.SUCCESS)

    -- Итоги по всем домам (если больше одного дома или просто удобно видеть общий итог)
    if (collectStats.total.BTC > 0) or (collectStats.total.ASC > 0) then
        AddChatMessage(string.format(
            "Итого за сессию: %s BTC и %s ASC",
            collectStats.total.BTC or 0, collectStats.total.ASC or 0
        ), TYPECHATMESSAGES.SUCCESS)
    end
end

function CheckProcessInteracting()
    return processes.take or processes.fill or processes.on or processes.off or processes.dep
end

function DeactivateProcessesInteracting()
    stateCrypto.work = false
    stateCrypto.waitFill = false
    stateCrypto.takeCount = 0
    stateCrypto.progressHouses = 0
    stateCrypto.queueHouses = {}
    stateCrypto.progressShelves = 0
    stateCrypto.queueShelves = {}
    stateCrypto.progressHousesBank = 0
    stateCrypto.queueHousesBank = {}
    processes.on = false
    processes.off = false
    processes.take = false
    processes.fill = false
    processes.dep = false
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

LoadSettings()

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

    -- Паттерн для извлечения данных о доме с налогом (поддержка разных валют)
    local patternWithTax = "Дом №(%d+)%s*([^%d]+)%s*{%w+}([%d]+)%s*([%d]+)%s*циклов%s*%(([VC]*%$)([%d,]+) / [VC]*%$([%d%.,]+)%)"

    -- Паттерн для извлечения данных о доме без налога (поддержка разных валют)
    local patternWithoutTax = "Дом №(%d+)%s*([^%d]+)%s*([%d]+)%s*циклов%s*%(([VC]*%$)([%d,]+) / [VC]*%$([%d%.,]+)%)"

    for lineIndex, line in ipairs(lines) do
        local found = false

        -- Сначала пробуем паттерн с налогом
        for houseNum, city, tax, cycles, currency, bankNow, bankMax in string.gmatch(line, patternWithTax) do
            if CheckHouseInBlackList(houseNum) then break end

            table.insert(results, {
                samp_line = lineIndex - 2,
                house_number = tonumber(houseNum),
                city = city:gsub("^%s+", ""):gsub("%s+$", ""),
                tax = tonumber(tax),
                cycles = tonumber(cycles),
                currency = currency,
                bankNow = bankNow:gsub(",", ""),
                bankMax = bankMax:gsub(",", ""),
                raw_line = line
            })
            found = true
        end

        -- Если не найдено совпадений с налогом, пробуем паттерн без налога
        if not found then
            for houseNum, city, cycles, currency, bankNow, bankMax in string.gmatch(line, patternWithoutTax) do
                if CheckHouseInBlackList(houseNum) then break end

                table.insert(results, {
                    samp_line = lineIndex - 2,
                    house_number = tonumber(houseNum),
                    city = city:gsub("^%s+", ""):gsub("%s+$", ""),
                    tax = nil,
                    cycles = tonumber(cycles),
                    currency = currency,
                    bankNow = bankNow:gsub(",", ""),
                    bankMax = bankMax:gsub(",", ""),
                    raw_line = line
                })
            end
        end
    end

    return results
end

function ParseHouseBankData(text)
    housesBanks = {}

    local results = {}
    local lines = {}

    -- Разбиваем текст на строки
    for line in text:gmatch("[^\r\n]+") do
        table.insert(lines, line)
    end

    local pattern = "Дом №(%d+)%s*([^%d]+)%s*%$([%d%.,]+)"

    for lineIndex, line in ipairs(lines) do
        for houseNum, city, bankNow in string.gmatch(line, pattern) do
            if CheckHouseInBlackList(houseNum) then break end

            table.insert(results, {
                samp_line = lineIndex - 2,
                house_number = tonumber(houseNum),
                city = city:gsub("^%s+", ""):gsub("%s+$", ""),
                bankNow = bankNow:gsub(",", ""),
                raw_line = line
            })
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

    -- Паттерн для полки с одной валютой
    local patternSingle = "Полка №(%d+)%s*|%s*{(%w+)}([^%d]+)([%d%.]+)%s+(%w+)%s+(%d+)%s+уровень%s+([%d%.]+)"

    -- Паттерн для полки с двумя валютами
    local patternDouble = "Полка №(%d+)%s*|%s*{(%w+)}([^%d]+)([%d%.]+)%s+(%w+)%s*|%s*([%d%.]+)%s+(%w+)%s+(%d+)%s+уровень%s+([%d%.]+)"

    for lineIndex, line in ipairs(lines) do
        local found = false

        -- Сначала пробуем паттерн с двумя валютами
        for shelfNum, colorCode, status, profit1, currency1, profit2, currency2, level, percentage in string.gmatch(line, patternDouble) do
            table.insert(results, {
                shelf_number = tonumber(shelfNum),
                samp_line = lineIndex - 2,
                status = status:gsub("^%s+", ""):gsub("%s+$", ""),
                color_code = colorCode,
                profit = tonumber(profit1),
                currency = currency1,
                profit2 = tonumber(profit2),
                currency2 = currency2,
                level = tonumber(level),
                percentage = tonumber(percentage),
                card_type = "ASIC",
                raw_line = line
            })
            found = true
        end

        -- Если не найдено, пробуем паттерн с одной валютой
        if not found then
            for shelfNum, colorCode, status, profit, currency, level, percentage in string.gmatch(line, patternSingle) do
                table.insert(results, {
                    shelf_number = tonumber(shelfNum),
                    samp_line = lineIndex - 2,
                    status = status:gsub("^%s+", ""):gsub("%s+$", ""),
                    color_code = colorCode,
                    profit = tonumber(profit),
                    currency = currency,
                    level = tonumber(level),
                    percentage = tonumber(percentage),
                    card_type = (currency == "ASC") and "ASC" or "BTC",
                    raw_line = line
                })
            end
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
        if type == TYPECHATMESSAGES.SUCCESS then _pref = "[ :true: ".._scriptName.." ]" end
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

        imgui.CenterText("[MMT] Mining Tool v"..thisScript().version.." | TG: @Mister_Sand")

        imgui.SameLine()

        local _icon = lastIDDialog == idDialogs.selectVideoCardItemFlash and fa.REPLY or fa.CIRCLE_XMARK
        if imgui.RightButton("\t".._icon.."\t") then
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
    if #housesBanks > 0 then
        DrawHousesBank()
    elseif #houses > 0 then
        DrawHouses()
    else
        imgui.Text(u8(string.format("Охлада: BTC - %s | supper BTC - %s | ASC - %s", haveLiquid.btc, haveLiquid.supper_btc, haveLiquid.asc)))
        imgui.Separator()
        DrawShelves()
    end
end

function DrawSettings()
    imgui.Text(u8(string.format("Работаю - %s | Заливаю - %s | Собираю - %s | Вкл/выкл - %s", stateCrypto.work, processes.fill, processes.take, (processes.on or processes.off))))
    if stateCrypto.work then
        if imgui.Button(u8"Отменить процесс", imgui.ImVec2(-1, 0)) then
            DeactivateProcessesInteracting()
        end
    end
    imgui.Separator()

    imgui.BeginChild("settings", imgui.ImVec2(-1, -1))

    imgui.CenterText(u8"Основное")

    if imgui.Checkbox(u8"Заменять окно диалога на окно скрипта", new.bool(settings.main.replaceDialog)) then
        settings.main.replaceDialog = not settings.main.replaceDialog SaveSettings()
    end
    if imgui.Checkbox(u8"Закрывать скрипт на ESC", new.bool(settings.main.closeOnESC)) then
        settings.main.closeOnESC = not settings.main.closeOnESC SaveSettings()
    end
    if imgui.Checkbox(u8"Скрыть текст получения крипты в чате", new.bool(settings.main.hideMessagesCollect)) then
        settings.main.hideMessagesCollect = not settings.main.hideMessagesCollect SaveSettings()
    end
    imgui.Text(u8("Заливать, когда "..settings.main.fillFrom.." процентов или ниже:"))
    imgui.PushItemWidth(-1)
    local _fillFrom = new.float(settings.main.fillFrom)
    if imgui.SliderFloat("##Заливать, когда этот процент или ниже", _fillFrom, 0, 100) then
        settings.main.fillFrom = _fillFrom[0] SaveSettings()
    end
    imgui.PopItemWidth()

    imgui.Spacing()
    imgui.CenterText(u8"Задержки")

    imgui.PushItemWidth(imgui.GetWindowWidth()/2)

    -- todo Нужно доделать, поменять еще в диалогах макс закид
    -- local _maxBankAmount = new.int(settings.main.maxBankAmount)
    -- if imgui.SliderInt(u8("Заполнять до"), _maxBankAmount, 10000, 19999999-10000) then
    --     settings.main.maxBankAmount = _maxBankAmount[0] SaveSettings()
    -- end

    local _timeoutDialog = new.int(settings.deley.timeoutDialog)
    if imgui.SliderInt(u8("Ожидание ответа диалога (сек)"), _timeoutDialog, 1, 30) then
        settings.deley.timeoutDialog = _timeoutDialog[0] SaveSettings()
    end

    local _waitInterval = new.int(settings.deley.waitInterval)
    if imgui.SliderInt(u8("Интервал проверки (миллисекунды)"), _waitInterval, 1, 100) then
        settings.deley.waitInterval = _waitInterval[0] SaveSettings()
    end

    local _timeoutShelf = new.int(settings.deley.timeoutShelf)
    if imgui.SliderInt(u8("Ожидание ответа от полок (сек)"), _timeoutShelf, 1, 30) then
        settings.deley.timeoutShelf = _timeoutShelf[0] SaveSettings()
    end

    local _waitRun = new.int(settings.deley.waitRun)
    if imgui.SliderInt(u8("Ожидать перед ответом на диалог (миллисекунды)"), _waitRun, 1, 100) then
        settings.deley.waitRun = _waitRun[0] SaveSettings()
    end

    imgui.PopItemWidth()


    imgui.Spacing()
    imgui.CenterText(u8"Черный список домов")

    imgui.Text(u8"Номер дома, который нужно скрыть")
    if imgui.Button(u8"Добавить", imgui.ImVec2(imgui.GetWindowWidth()/4)) then
        table.insert(settings.main.blackListHouses, inputBlackHouse[0])
        SaveSettings()
    end
    imgui.SameLine()
    imgui.PushItemWidth(-1)
    imgui.InputInt("##numberHouse", inputBlackHouse, 0,0)
    imgui.PopItemWidth()

    for index, blackHouse in ipairs(settings.main.blackListHouses) do
        if imgui.Button("X##"..index) then
            table.remove(settings.main.blackListHouses, index)
            SaveSettings()
        end
        imgui.SameLine()
        imgui.Text(u8"Дом №"..blackHouse)
    end


    imgui.Spacing()
    imgui.CenterText(u8"Интерфейс")

    local _scrollbarSizeStyle = new.int(settings.style.scrollbarSizeStyle)
    if imgui.SliderInt(u8("Размер скроллбара"), _scrollbarSizeStyle, 10, 50) then
        settings.style.scrollbarSizeStyle = _scrollbarSizeStyle[0] SaveSettings()
        SetStyle()
    end

    local _MONET_DPI_SCALE = new.float(settings.style.scaleUI)
    if imgui.SliderFloat(u8("DPI (Масштаб скрипта)"), _MONET_DPI_SCALE, 0, 5) then
        settings.style.scaleUI = _MONET_DPI_SCALE[0] SaveSettings()
    end
    if imgui.Button(u8"Перезапустите") then
        thisScript():reload()
    end
    imgui.SameLine()
    imgui.Text(u8("скрипт, чтобы применить. Либо команда: /mmtr"))
    imgui.Text(u8("Сбросить масштаб, команда: /mmtsr"))


    if #stateCrypto.queueShelves > 0 then
        imgui.Spacing()
        imgui.CenterText(u8"Тех состояние")

        for index, value in ipairs(stateCrypto.queueShelves) do
            imgui.Separator()
            imgui.Text(u8(string.format("Строка - %s | Заливка - %s | Крипты - %s | Состояние - %s", value.samp_line, value.fill, value.count, value.work)))
        end
    end

    imgui.EndChild()
end

function DrawHousesBank()
    if stateCrypto.work then
        imgui.ProgressBar(stateCrypto.progressHousesBank/#stateCrypto.queueHousesBank,imgui.ImVec2(-1,0), u8"Дом "..stateCrypto.progressHousesBank.."/"..#stateCrypto.queueHousesBank)
    end

    if imgui.ButtonClickable(not stateCrypto.work, u8"Заполнить до MAX", imgui.ImVec2(-1, 0)) then
        StartProcessInteracting("dep")
    end

    imgui.BeginChild("list", imgui.ImVec2(-1, -1))
    for i, house in ipairs(housesBanks) do
        local _bank_now_str = house.bankNow:gsub("[^%d]", "")
        local bank_now = tonumber(_bank_now_str) or 0
        local bank_color = COLORS.WHITE

        if bank_now < 5000000 then
            bank_color = COLORS.RED
        elseif bank_now < 10000000 then
            bank_color = COLORS.YELLOW
        end

        -- Формируем текст для строки
        local house_text = string.format("Дом №%s (%s) - {%s}Банк: {%s}%s$",
            house.house_number,
            house.city,
            COLORS.WHITE,
            bank_color,
            GetCommaValue(house.bankNow)
        )

        if imgui.SelectableEx(house_text, lastOpenHouse == i, imgui.SelectableFlags.SpanAllColumns) then
            lastOpenHouse = i
            sampSendDialogResponse(idDialogs.selectHouse, 1, house.samp_line, "")
            housesBanks = {}
            SwitchMainWindow()
        end

        -- Добавляем небольшой отступ между домами
        if i < #houses then
            imgui.Spacing()
        end
    end
    imgui.EndChild()
end

function DrawHouses()
    local totalHouse = #houses
    local lowCycles = 0
    local lowBank = 0

    for i, house in ipairs(houses) do
        if house.cycles < 100 then
            lowCycles = lowCycles + 1
        end
        if tonumber(house.bankNow) < 5000000 then
            lowBank = lowBank + 1
        end
    end

    -- Отображение статистики
    imgui.Text(u8(string.format("Найдено домов: %d", totalHouse)))
    imgui.SameLine()
    imgui.TextColoredRGB(string.format("  Мало циклов:{%s} %d", COLORS.RED, lowCycles))
    imgui.SameLine()
    imgui.TextColoredRGB(string.format("  Мало денег:{%s} %d", COLORS.YELLOW, lowBank))

    imgui.Separator()

    local button_width = (imgui.GetWindowWidth() - ScaleUI(30)) / 2
    if imgui.ButtonClickable(not stateCrypto.work, fa.HAND_HOLDING_DOLLAR .. u8"\tСобрать всю прибыль", imgui.ImVec2(button_width, 0)) then
        StartProcessInteracting("take")
    end
    imgui.SameLine()
    if imgui.ButtonClickable(not stateCrypto.work, fa.TOGGLE_ON .. u8"\tВключить все видеокарты", imgui.ImVec2(-1, 0)) then
        StartProcessInteracting("on")
    end

    if stateCrypto.work then
        imgui.ProgressBar(stateCrypto.progressHouses/#stateCrypto.queueHouses,imgui.ImVec2(-1,0), u8"Дом "..stateCrypto.progressHouses.."/"..#stateCrypto.queueHouses)
    end
    if stateCrypto.work then
        imgui.ProgressBar(stateCrypto.progressShelves/#stateCrypto.queueShelves,imgui.ImVec2(-1,0), u8"Полка "..stateCrypto.progressShelves.."/"..#stateCrypto.queueShelves)
    end

    imgui.Separator()

    imgui.BeginChild("list", imgui.ImVec2(-1, -1))
    for i, house in ipairs(houses) do
        -- Определяем цвета для циклов и банка
        local cycles_color = house.cycles < 100 and COLORS.RED or COLORS.WHITE -- красный если < 100, белый если >= 100

        local _bank_now_str = house.bankNow:gsub("[^%d]", "")
        local bank_now = tonumber(_bank_now_str) or 0
        local bank_color = COLORS.WHITE

        if bank_now < 5000000 then
            bank_color = COLORS.RED
        elseif bank_now < 10000000 then
            bank_color = COLORS.YELLOW
        end

        -- Формируем текст для строки
        local house_text = string.format("Дом №%s (%s) - Налог: %s  {%s}Циклов: {%s}%s  {%s}Банк: {%s}%s{%s}/%s%s",
            house.house_number,
            house.city,
            house.tax,
            COLORS.WHITE,
            cycles_color,
            GetCommaValue(house.cycles),
            COLORS.WHITE,
            bank_color,
            GetCommaValue(house.bankNow),
            COLORS.WHITE,
            GetCommaValue(house.bankMax),
            house.currency
        )

        if imgui.SelectableEx(house_text, lastOpenHouse == i, imgui.SelectableFlags.SpanAllColumns) then
            lastOpenHouse = i
            sampSendDialogResponse(idDialogs.selectHouse, 1, house.samp_line, "")
            houses = {}
        end

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
        working_shelves > 0 and COLORS.GREEN or COLORS.RED,
        working_shelves))
    imgui.SameLine()
    imgui.TextColoredRGB(string.format("  Не работают:{%s} %d", COLORS.RED, not_working_shelves))
    imgui.TextColoredRGB(string.format("Нет или мало охлаждайки:{%s} %d", COLORS.YELLOW, low_liauid))

    imgui.Spacing()

    -- Первая строка кнопок: Собрать и Залить
    local button_width = (imgui.GetWindowWidth() - ScaleUI(30)) / 2

    if imgui.ButtonClickable(not stateCrypto.work, fa.HAND_HOLDING_DOLLAR .. u8"\tСобрать всё", imgui.ImVec2(button_width, 0)) then
        StartProcessInteracting("take")
    end
    imgui.SameLine()
    if imgui.ButtonClickable(not stateCrypto.work, fa.FILL_DRIP .. u8"\tЗалить всё", imgui.ImVec2(-1, 0)) then
        StartProcessInteracting("fill")
    end

    -- Вторая строка кнопок: Включить и Отключить
    if imgui.ButtonClickable(not stateCrypto.work, fa.TOGGLE_ON .. u8"\tВключить всё", imgui.ImVec2(button_width, 0)) then
        StartProcessInteracting("on")
    end
    imgui.SameLine()
    if imgui.ButtonClickable(not stateCrypto.work, fa.TOGGLE_OFF .. u8"\tОтключить всё", imgui.ImVec2(-1, 0)) then
        StartProcessInteracting("off")
    end

    if stateCrypto.work then
        imgui.ProgressBar(stateCrypto.progressShelves/#stateCrypto.queueShelves,imgui.ImVec2(-1,0), stateCrypto.progressShelves.."/"..#stateCrypto.queueShelves)
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

        local cooling_color = COLORS.WHITE
        if shelf.percentage == 0 then
            cooling_color = COLORS.RED
        elseif shelf.percentage <= settings.main.fillFrom then
            cooling_color = COLORS.YELLOW
        end

        local gpu_color = COLORS.RED
        if shelf.status:find("Работает") then
            gpu_color = COLORS.GREEN
        end

        local profit_color = shelf.profit > 1 and COLORS.GREEN or COLORS.WHITE -- зеленый если > 1, белый если <= 1

        if imgui.Button(u8(string.format("Открыть##%d", i))) then
            sampSendDialogResponse(lastIDDialog, 1, shelf.samp_line, "")
            imguiWindows.main[0] = false
        end
        imgui.SameLine()

        if shelf.profit2 then
            imgui.TextColoredRGB(string.format("Полка №%d Ур.%d {%s}%s {%s}%.6f %s | %.6f %s {%s}%.1f%%",
                shelf.shelf_number,
                shelf.level,
                gpu_color, shelf.status,
                profit_color, shelf.profit, shelf.currency, shelf.profit2, shelf.currency2,
                cooling_color, shelf.percentage))
        else
            imgui.TextColoredRGB(string.format("Полка №%d Ур.%d {%s}%s {%s}%.6f %s {%s}%.1f%%",
                shelf.shelf_number,
                shelf.level,
                gpu_color, shelf.status,
                profit_color, shelf.profit, shelf.currency,
                cooling_color, shelf.percentage))
        end
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

function imgui.SelectableEx(label, selected, flags, imVecSize)
    if imgui.Selectable("##"..label, selected, flags, imVecSize) then
        return true
    end
    imgui.SameLine()
    imgui.SetCursorPosX(imgui.GetCursorPosX() + imgui.GetStyle().ItemInnerSpacing.x)
    imgui.TextColoredRGB(label)
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

local function MainStyleMobile()
    settings.style.colorChat, settings.style.colorMessage = '8cbf91', 0xFF8cbf91

    local style = imgui.GetStyle()
    local colors = style.Colors
    local clr = imgui.Col
    local ImVec4 = imgui.ImVec4
    local ImVec2 = imgui.ImVec2
    style.WindowPadding = ImVec2(8, 8)
    style.WindowRounding = 10*MONET_DPI_SCALE
    style.ChildRounding = 8*MONET_DPI_SCALE
    style.FramePadding = ImVec2(6, 4)
    style.FrameRounding = 8*MONET_DPI_SCALE
    style.ItemSpacing = ImVec2(6*MONET_DPI_SCALE, 6*MONET_DPI_SCALE)
    style.ItemInnerSpacing = ImVec2(4, 4)
    style.IndentSpacing = 21
    style.ScrollbarSize = settings.style.scrollbarSizeStyle
    style.ScrollbarRounding = 13*MONET_DPI_SCALE
    style.GrabMinSize = 8
    style.GrabRounding = 1*MONET_DPI_SCALE
    style.WindowTitleAlign = ImVec2(0.5, 0.5)
    style.ButtonTextAlign = ImVec2(0.5, 0.5)
    return colors, clr, ImVec4
end

function SetStyle(mobile)
    local colors, clr, ImVec4
    if mobile then
        colors, clr, ImVec4 = MainStyleMobile()
    else
        colors, clr, ImVec4 = MainStyle()
    end

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