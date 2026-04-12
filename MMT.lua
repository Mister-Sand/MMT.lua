-- =====================================================================================================================
--                                                          Header
-- =====================================================================================================================

script_authors('Sand')
script_name('MMT | Mining Tool')
script_description('Mining assistant TG: @Mister_Sand')
script_version("1.8")

-- =====================================================================================================================
--                                                          Import
-- =====================================================================================================================

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
local keysSuccess,      vkeys       = CheckLibrary('vkeys')
local ffiSuccess,       ffi         = CheckLibrary('ffi')
local notifySuccess,    notify      = pcall(require, 'session_notifications')

encoding.default = 'CP1251'
local u8 = encoding.UTF8

if not imguiSuccess     or not encodingSuccess  or not sampevSuccess or
   not jsonSuccess      or not faSuccess then
    print("Некоторые библиотеки не были загружены. Пожалуйста, установите недостающие библиотеки.")
end

local VK_RETURN = (keysSuccess and vkeys.VK_RETURN) or 0x0D
local VK_UP     = (keysSuccess and vkeys.VK_UP)     or 0x26
local VK_DOWN   = (keysSuccess and vkeys.VK_DOWN)   or 0x28

local REQUIRED_NOTIFY_VERSION = '1.0'
local NOTIFY_MANAGER_REPO_URL = 'https://github.com/Mister-Sand/session_notifications'
local NOTIFY_MANAGER_RAW_URL = 'https://raw.githubusercontent.com/Mister-Sand/session_notifications/main/NotificationManager.lua'
local NOTIFY_LIBRARY_RAW_URL = 'https://raw.githubusercontent.com/Mister-Sand/session_notifications/main/lib/session_notifications.lua'

-- =====================================================================================================================
--                                                          GLOBAL VARIABLES
-- =====================================================================================================================

-- --------------------------------------------------------
--                           Constants
-- --------------------------------------------------------

ISMONETLOADER = true
SEPORATORPATCH = "/"
if MONET_DPI_SCALE == nil then MONET_DPI_SCALE = 1.0 ISMONETLOADER = false SEPORATORPATCH = "\\" end

local folderConfig = 'config'..SEPORATORPATCH
local PATCHCONFIG = folderConfig..'MMT CFGs'..SEPORATORPATCH

-- === Логи / статистика заточки видеокарт ===
local IMPROVE_LOGS_DIR   = PATCHCONFIG .. 'logs' .. SEPORATORPATCH     -- папка для текстовых логов
local IMPROVE_STATS_FILE = PATCHCONFIG .. 'ImproveStats.json'          -- файл со сводной статистикой
local COLLECT_STATS_FILE = PATCHCONFIG .. 'CollectStats.json'          -- лог сбора криптовалюты по датам / домам


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

-- Доходность видеокарт по уровням в час
local GPU_HOURLY_BY_LEVEL = {
    [1]=0.050325, [2]=0.100650, [3]=0.150975, [4]=0.201300, [5]=0.503250,
    [6]=0.631349, [7]=0.736575, [8]=0.876874, [9]=1.052250, [10]=1.227625,
}

-- Сколько часов видеокарта отработает за полный цикл при 100% охлаждения
local GPU_CYCLE_HOURS = 224

-- Цена попытки улучшения уровня видеокарты (с N на N+1)
local GPU_IMPROVE_PRICE_BY_LEVEL = {
    [1] = 8000000,
    [2] = 6000000,
    [3] = 5000000,
    [4] = 4000000,
    [5] = 3000000,
    [6] = 2000000,
    [7] = 1000000,
    [8] = 700000,
    [9] = 500000,
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
            debug    = false,
        },
        -- Черный список домов, которые нужно скрыть
        blackListHouses = {},
        maxBankAmount = 59999999 - 10000,
        -- Пополнять банк до целевой суммы (если выключено - до максимума диалога)
        bankFillToTarget = false,
        bankTargetAmount = 10000000,
        -- Закрывать ли на ESC
        closeOnESC = true,
        -- Перемещаться стрелками
        arrowsMove = true,
        -- Скрывать текст полученной крипты
        hideMessagesCollect = true,
        -- автозаливка
        autoFillEnabled = false,
        -- автоматически включать видеокарты после сбора
        autoEnableCards = false,
        -- Панель статуса
        showStatusPanel = false,
        -- Напоминание, если давно не было сбора крипты (в минутах, 0 = выкл)
        collectNotifyMinutes = 0,
        -- Отображение доходности (что показывать в списке полок)
        income = {
            showPerHour             = true,  -- "/ч"
            showPer24h              = true,  -- "/24ч"
            showPerCycle            = true,  -- "/цикл"
            showTillThresholdHours  = true,  -- "до доливки" (часы и прибыль)
            showTillThresholdProfit = true,  -- "до доливки" (часы и прибыль)
            houseBonuses            = {},
            onlineHours             = 0,
        },
    },
    improve = {
        -- true: улучшать все карты; false: только выбранную
        menuAll = true,
        -- 1 = Обычные, 2 = Arizona
        typeCards = 1,
        -- 1 = Классический инвентарь (текущая рабочая логика), 2 = Новый стиль (заготовка под CEF)
        inventoryMode = 1,
        -- 1 = Последовательное (сначала низкий уровень), 2 = Поочередное (как на экране)
        mode = 1,
        -- Целевой уровень (не улучшать если уже >= этого уровня)
        maxLevel = 2,
        -- Проверять наличие смазки при старте заточки (через /stats)
        checkOilsOnStart = true,
    },
    deley = {
        timeoutDialog = 10,
        waitInterval = 10,
        timeoutShelf = 10,
        -- Ждать перед отправкой ответа на диалог
        waitRun = 0,
        -- Пуза после получения результата
        improve_waitResult = 500,
        -- Пуза перед нажатием на видеокарту в инвентаре
        improve_waitTryClick = 500,
        -- Интервал автоповтора нажатия USE на шаге подтверждения
        improve_retryUseDelay = 1200,
        -- Таймаут ожидания сообщения о старте улучшения
        improve_waitStartTimeout = 8,
        -- Таймаут ожидания итогового результата улучшения
        improve_waitResultTimeout = 20,
    },
    style = {
        -- Скрол пальцем
        swipeScroll = ISMONETLOADER,
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
local windowPos = nil

-- Активный раздел в скрипте
local activeTabScript = "main"

local inputBlackHouse = new.int()
local inputIncomeHouse = new.int()
local ui_bank = { buf = new.char[32]("") }

-- Состояния для элеметов в ui
local ui_state = {
    -- Состояние свайпа списка
    swipe = { active = false, DRAG_THRESHOLD = 6 },
    -- Состояние перетаскивания окна
    drag = {
        active = false,
        mx = 0, my = 0,       -- координаты мыши в момент начала перетаскивания
        wx = 0, wy = 0,       -- позиция окна в момент начала перетаскивания
    }
}

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
    activeHouseID = "-1"
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
local collectLogStore = { days = {}, meta = {} }
local collectReminder = {
    lastNotifiedCollectAt = 0,
    notifyPending = false,
    retryAfterAt = 0,
    lastTickAt = 0,
    managerEnsurePending = false,
    managerDownloadPending = false,
    managerStatusMessage = "",
}
local collectReminderAction = nil

-- Доступные полки
local shelves = {}

local houses = {}
-- Дома с информацией о полках
--[id_house <string>] = { work_vc = <int> количество рабочих видеокарт, max_collect = <int> макс крипты в доме, min_liquid = <number> минимально охлаждайки в доме}
local housesData = {}

local housesBanks = {}

local lastIDDialog = 0

local lastOpenHouse = 1
local lastOpenShelves = 1

-- --------------------------------------------------------
--                           Improve
-- --------------------------------------------------------
local improve = {
    isOn = false,
    step = 0,              -- 0=выкл, 1=выбор карты, 2=жду "USE", 3=подтверждаю, 4=жду результат

    -- Кэш видеокарт на ТЕКУЩЕЙ странице инвентаря
    videoCards   = {},     -- { { td = <id>, level = <int>, storageUpgrade = <bool> } ... }
    select       = 0,      -- индекс выбранной карты (когда menuAll=false)
    lastScan     = 0,      -- оставить на будущее, сейчас не используем
    currentIndex = 0,      -- индекс карты, которую сейчас точим

    -- Состояние инвентаря видеокарт (страницы)
    inv = {
        pageTD     = 0,    -- id первой кнопки страниц
        activePage = 1,    -- номер текущей страницы (для информации)
        needScan   = false -- нужно перечитать видеокарты на этой странице
    },

    oils = { -- инвентарь смазок
        arizona = 0,
        classic = 0,
        lastAt = '-',
        busy = false,
    },
    needCheckOils   = false,   -- флаг: после старта надо проверить инвентарь
    waitOils        = false,   -- ждём завершения сканирования /stats
    consumedThisTry = false,   -- на текущую попытку уже списали смазки
    waitStart       = false,   -- ждём сообщения "Вы начали процесс улучшения..."
    waitStartAt     = 0,
    waitResultAt    = 0,
    lastUseAt       = 0,

    -- ID текстдравов кнопки "USE"/"Использовать"
    useTextId  = 0,  -- TD с текстом
    useClickId = 0,  -- кликабельный TD (id+1)

    -- Режим вида улучшения:
    -- false  = улучшение производительности
    -- true   = увеличение объёма хранения криптовалюты
    useStorageUpgrade = false,

    -- Логи и статистика заточки
    logs = {
        items      = {},   -- { { ts="дата-время", type="INFO", text="...", step=1 } ... }
        max        = 300,  -- макс. количество записей
        autoScroll = true, -- автопрокрутка вниз в UI
    },
    stats = {
        sessionId  = 0,
        active     = false,
        startedAt  = 0,
        finishedAt = 0,
        attempts   = 0,
        success    = 0,
        fail       = 0,
        oilsUsed   = 0,
        spent      = 0,
        byLevel    = {},
        lastReason = "",
    },
    cef = {
        stubNotified = false,
        lastPacketId = 0,
        lastPacket = '',
        cards = {},
        probing = false,
        probeDone = false,
        probed = false,
        pendingSlot = nil,
        pendingIndex = 0,
        needInventoryRefresh = true,
        waitInventory = false,
        probeAbort = false,
        probeAbortReason = '',
        probeProgress = 0,
        probeTotal = 0,
    },
}

local improveSteps = {
    [0]='Улучшение выключено',
    [1]='Выбираю видеокарту',
    [2]='Использую видеокарту',
    [3]='Подтверждаю крафт',
    [4]='Ожидаю крафт'
}

local function MI_Say(msg)
    AddChatMessage("Улучшение: "..tostring(msg), TYPECHATMESSAGES.SECONDARY)
end

local function Improve_IsNewStyleMode()
    return tonumber(settings.improve.inventoryMode or 1) == 2
end

local function Improve_IsClassicMode()
    return not Improve_IsNewStyleMode()
end

local function Improve_GetInventoryModeName()
    return Improve_IsNewStyleMode() and "Новый стиль" or "Классический инвентарь"
end

local function Improve_SendCef(payload)
    if not payload or payload == '' then return false end
    local bs = raknetNewBitStream()
    if not bs then return false end
    raknetBitStreamWriteInt8(bs, 220)
    raknetBitStreamWriteInt8(bs, 18)
    raknetBitStreamWriteInt16(bs, #payload)
    raknetBitStreamWriteString(bs, payload)
    raknetBitStreamWriteInt32(bs, 0)
    raknetSendBitStream(bs)
    raknetDeleteBitStream(bs)
    return true
end

local function Improve_SendCefMobile(iface, sub, reqid, payload)
    iface = tonumber(iface or 0) or 0
    sub = tonumber(sub or 0) or 0
    reqid = tonumber(reqid or -1) or -1
    payload = payload ~= nil and tostring(payload) or ''

    local bs = raknetNewBitStream()
    if not bs then return false end

    raknetBitStreamWriteInt8(bs, 220)
    raknetBitStreamWriteInt8(bs, 0x3F)
    raknetBitStreamWriteInt8(bs, iface)
    raknetBitStreamWriteInt32(bs, reqid)
    raknetBitStreamWriteInt32(bs, sub)

    if payload ~= '' then
        raknetBitStreamWriteInt16(bs, #payload)
        raknetBitStreamWriteString(bs, payload)
    else
        raknetBitStreamWriteInt16(bs, 0)
    end

    raknetSendBitStream(bs)
    raknetDeleteBitStream(bs)
    return true
end

local function Improve_SendCefClickOnSlot(slot, action, clickType)
    slot = tonumber(slot or 0) or 0
    action = tonumber(action or 1) or 1
    clickType = tonumber(clickType or 1) or 1
    if slot <= 0 then return false end

    local packet = string.format('clickOnButton|{"type": %d,"slot": %d, "action": %d}', clickType, slot, action)
    improve.cef.lastPacketId = 220
    improve.cef.lastPacket = packet
    return Improve_SendCef(packet)
end

local flashCollect = {
    active = false,
    inventoryOpened = false,
    waitHouseDialog = false,
    houseDialogReady = false,
    failed = false,
    error = "",
    statsBusy = false,
    lastStatsAt = "-",
    slot = 0,
    count = 0,
    name = "",
}

local function FlashCollect_ResetFlags()
    flashCollect.active = false
    flashCollect.inventoryOpened = false
    flashCollect.waitHouseDialog = false
    flashCollect.houseDialogReady = false
    flashCollect.failed = false
    flashCollect.error = ""
    flashCollect.statsBusy = false
end

local function FlashCollect_ResetItem()
    flashCollect.slot = 0
    flashCollect.count = 0
    flashCollect.name = ""
end

local function FlashCollect_Cancel()
    local wasPreparing = flashCollect.active
    local wasCollecting = stateCrypto.work and processes.take

    if wasPreparing then
        FlashCollect_ResetFlags()
    end

    if wasCollecting then
        DeactivateProcessesInteracting()
    end

    if wasPreparing or wasCollecting then
        AddChatMessage("Сбор через флешку: отменен", TYPECHATMESSAGES.WARNING)
        return true
    end

    return false
end

local function FlashCollect_IsFlashItem(name)
    local lowerName = tostring(name or "")
    return lowerName:find("Флешка майнера", 1, true) ~= nil
end

local function FlashCollect_RegisterItem(name, count, slot)
    slot = tonumber(slot or 0) or 0
    count = tonumber(count or 0) or 0
    if slot <= 0 or count <= 0 then return end
    if not FlashCollect_IsFlashItem(name) then return end

    flashCollect.slot = slot
    flashCollect.count = count
    flashCollect.name = tostring(name or "")
end

local function FlashCollect_ParseStatsInventoryPage(text)
    for line in (text or ''):gmatch("[^\r\n]+") do
        local indexSlot, name, count = line:match("%[([^%]]+)%]%s(.-)%s%{.-}%[([^%]]+)%sшт%]")
        local slotNum = tonumber(indexSlot)
        count = tonumber(count)
        if indexSlot and name and count then
            FlashCollect_RegisterItem(name, count, slotNum)
        end
    end
end

local function FlashCollect_Fail(reason, chatType)
    flashCollect.failed = true
    flashCollect.error = tostring(reason or "")
    flashCollect.active = false
    flashCollect.waitHouseDialog = false
    flashCollect.houseDialogReady = false
    flashCollect.inventoryOpened = false
    flashCollect.statsBusy = false
    AddChatMessage(reason or "Сбор через флешку: ошибка", chatType or TYPECHATMESSAGES.CRITICAL)
end

local function StartCollectViaFlash()
    if stateCrypto.work then
        AddChatMessage("Сбор через флешку: процесс уже запущен", TYPECHATMESSAGES.WARNING)
        return false
    end

    if improve.isOn or improve.oils.busy or flashCollect.statsBusy then
        AddChatMessage("Сбор через флешку: дождитесь завершения другого процесса", TYPECHATMESSAGES.WARNING)
        return false
    end

    if flashCollect.active then
        AddChatMessage("Сбор через флешку: запуск уже выполняется", TYPECHATMESSAGES.WARNING)
        return false
    end

    lua_thread.create(function()
        FlashCollect_ResetFlags()
        FlashCollect_ResetItem()
        flashCollect.active = true
        flashCollect.waitHouseDialog = true
        flashCollect.houseDialogReady = false

        AddChatMessage("Сбор через флешку: отправляю /flashminer", TYPECHATMESSAGES.DEBUG)
        sampSendChat('/flashminer')

        local dialogTimeout = os.clock() + 8
        while flashCollect.active and not flashCollect.houseDialogReady and not flashCollect.failed and os.clock() < dialogTimeout do
            wait(25)
        end

        if not flashCollect.active then
            return
        end

        if flashCollect.failed then
            return
        end

        if not flashCollect.houseDialogReady or #houses == 0 then
            FlashCollect_Fail("Сбор через флешку: список домов не открылся", TYPECHATMESSAGES.CRITICAL)
            return
        end

        FlashCollect_ResetFlags()
        AddChatMessage("Сбор через флешку: запускаю сбор со всех домов", TYPECHATMESSAGES.DEBUG)
        wait(100)
        StartProcessInteracting("take")
    end)

    return true
end
local function Improve_ResetCefInventory()
    improve.cef.cards = {}
    improve.cef.probing = false
    improve.cef.probeDone = false
    improve.cef.probed = false
    improve.cef.pendingSlot = nil
    improve.cef.pendingIndex = 0
    improve.cef.probeAbort = false
    improve.cef.probeAbortReason = ''
    improve.cef.probeProgress = 0
    improve.cef.probeTotal = 0
end

local function Improve_GetCardNameNorm(name)
    local s = tostring(name or '')
    s = s:gsub('^%s+', ''):gsub('%s+$', '')
    s = s:gsub('%s+%(%+1%)', '(+1)')
    return s
end

local function Improve_ParseCardMetaFromName(name)
    local n = Improve_GetCardNameNorm(name)
    if n == 'Видеокарта' then return 1, false end
    if n == 'Видеокарта(+1)' then return 1, true end
    if n == 'Arizona Video Card' then return 2, false end
    if n == 'Arizona Video Card(+1)' then return 2, true end
    return nil, false
end

local function Improve_AddCefCardSlot(slot, itemName, hasStorageUpgrade, cardType)
    slot = tonumber(slot or 0) or 0
    if slot <= 0 then return end

    local parsedType, parsedStorage = Improve_ParseCardMetaFromName(itemName)
    local ctype = tonumber(cardType or parsedType or 0) or 0
    local storage = (hasStorageUpgrade == true) or parsedStorage
    if ctype ~= 1 and ctype ~= 2 then return end

    for _, c in ipairs(improve.cef.cards) do
        if c.slot == slot then
            c.name = tostring(itemName or c.name or '')
            c.cardType = ctype
            c.storageUpgrade = storage or (c.storageUpgrade == true)
            return
        end
    end

    table.insert(improve.cef.cards, {
        slot = slot,
        name = tostring(itemName or ''),
        cardType = ctype,
        level = 0,
        storageUpgrade = storage,
    })
end

local function Improve_MoveMaxLevelCardsToEnd(cards)
    if type(cards) ~= "table" or #cards <= 1 then return cards end

    local activeCards = {}
    local maxLevelCards = {}

    for _, card in ipairs(cards) do
        if tonumber(card.level or 0) >= 10 then
            table.insert(maxLevelCards, card)
        else
            table.insert(activeCards, card)
        end
    end

    if #maxLevelCards == 0 or #activeCards == 0 then
        return cards
    end

    for _, card in ipairs(maxLevelCards) do
        table.insert(activeCards, card)
    end

    return activeCards
end

local function Improve_SyncVideoCardsFromCef()
    local cards = {}
    local selectedType = tonumber(settings.improve.typeCards or 1) or 1

    for _, c in ipairs(improve.cef.cards or {}) do
        if tonumber(c.cardType or 0) == selectedType then
            table.insert(cards, {
                td = 0,
                slot = c.slot,
                cardType = tonumber(c.cardType or 0) or 0,
                level = tonumber(c.level or 0) or 0,
                storageUpgrade = c.storageUpgrade == true,
            })
        end
    end

    if settings.improve.mode == 1 and settings.improve.menuAll then
        table.sort(cards, function(a, b)
            return (a.level or 0) < (b.level or 0)
        end)
    end

    cards = Improve_MoveMaxLevelCardsToEnd(cards)
    improve.videoCards = cards
end
local function Improve_ParseCardLevelFromDialog(text)
    local dialogText = tostring(text or '')

    local currentLvl = dialogText:match('Сейчас%s+уровень%s+производительности%s+видеокарты:%s*(%d+)%s*из%s*10')
    if currentLvl then
        return math.maxEx(0, tonumber(currentLvl) or 0)
    end

    for line in dialogText:gmatch('[^\r\n]+') do
        if line:find('Улучшить производительность видео-карты', 1, true) then
            local maxLvl = tonumber(line:match('до%s+(%d+)%s+уровн'))
            if maxLvl then
                return math.maxEx(0, maxLvl - 1)
            end
        end
    end

    return nil
end

local function Improve_RunNewStyleProbeLoop(allowWhenStopped)
    improve.cef.probing = true
    improve.cef.probeDone = false
    improve.cef.probed = false
    improve.cef.probeAbort = false
    improve.cef.probeAbortReason = ''
    improve.cef.probeProgress = 0

    local selectedType = tonumber(settings.improve.typeCards or 1) or 1
    local probeCards = {}
    for _, c in ipairs(improve.cef.cards or {}) do
        if tonumber(c.cardType or 0) == selectedType then
            table.insert(probeCards, c)
        end
    end

    if #probeCards == 0 then
        improve.cef.probeAbort = true
        improve.cef.probeAbortReason = 'в инвентаре нет карт выбранного типа'
    end

    improve.cef.probeTotal = #probeCards
    Improve_LogAdd('INFO', string.format('Новый стиль: начинаю проверку %d слотов видеокарт.', #probeCards))

    for idx, card in ipairs(probeCards) do
        if ((not improve.isOn) and (not allowWhenStopped)) or (not Improve_IsNewStyleMode()) then
            break
        end
        if improve.cef.probeAbort then
            break
        end

        improve.cef.pendingIndex = idx
        improve.cef.pendingSlot = card.slot
        improve.cef.probeDone = false

        Improve_SendCefClickOnSlot(card.slot, 1, 1)

        local timeoutAt = os.clock() + (settings.deley.timeoutDialog or 10)
        while (improve.isOn or allowWhenStopped)
            and Improve_IsNewStyleMode()
            and not improve.cef.probeDone
            and not improve.cef.probeAbort
            and os.clock() < timeoutAt do
            wait(25)
        end

        if improve.cef.probeAbort then
            break
        end

        if not improve.cef.probeDone then
            improve.cef.probeProgress = math.maxEx(0, idx - 1)
            improve.cef.probeAbort = true
            improve.cef.probeAbortReason = string.format('таймаут ожидания диалога (slot %d)', card.slot)
            break
        end

        improve.cef.probeProgress = idx
        wait(settings.deley.improve_waitTryClick or 300)
    end

    local aborted = improve.cef.probeAbort == true
    local abortReason = improve.cef.probeAbortReason or ''

    improve.cef.probing = false
    improve.cef.pendingSlot = nil
    improve.cef.pendingIndex = 0
    improve.cef.probeDone = false

    Improve_SyncVideoCardsFromCef()

    if aborted then
        improve.cef.probed = false
        Improve_LogAdd('WARN', 'Новый стиль: проверка уровней остановлена: ' .. abortReason)
        MI_Say('Проверка уровней остановлена: ' .. abortReason)
        if improve.isOn and not allowWhenStopped then
            Improve_Stop('Новый стиль: ' .. abortReason)
        end
    else
        improve.cef.probed = true
        improve.cef.probeProgress = improve.cef.probeTotal or #improve.videoCards
        Improve_LogAdd('INFO', string.format('Новый стиль: проверка завершена, карт в списке %d.', #improve.videoCards))
    end
end
local function Improve_StartNewStyleProbe(allowWhenStopped)
    if improve.cef.probing then return end

    Improve_SyncVideoCardsFromCef()
    if #improve.videoCards == 0 then
        improve.cef.probed = true
        return
    end

    Improve_RunNewStyleProbeLoop(allowWhenStopped)
end


local function Improve_ManualCheckCardLevels()
    if not Improve_IsNewStyleMode() then
        MI_Say('Проверка уровней доступна только в режиме ' .. Improve_GetInventoryModeName())
        return
    end

    if improve.oils.busy then
        MI_Say('Дождитесь завершения обновления инвентаря.')
        return
    end

    if improve.cef.probing then
        MI_Say('Проверка уровней уже выполняется.')
        return
    end

    lua_thread.create(function()
        Improve_RefreshOils(false)
        if not Improve_IsNewStyleMode() then return end

        if #improve.cef.cards == 0 then
            MI_Say('Видеокарты в инвентаре не найдены.')
            return
        end

        Improve_SyncVideoCardsFromCef()
        improve.cef.probed = false
        Improve_StartNewStyleProbe(true)
    end)
end

function Improve_HandleNewStyleChooseDialog(dialogId, title, text)
    if not Improve_IsNewStyleMode() then return false end

    local dialogTitle = tostring(title or '')
    local dialogText = tostring(text or '')
    local isChooseDialog = dialogTitle:find('{BFBBBA}Выберите вид улучшения для видеокарты', 1, true) ~= nil
    local isUpgradeDialog = dialogTitle:find('{BFBBBA}Улучшение видеокарты', 1, true) ~= nil

    if not isChooseDialog and not (improve.cef.probing and isUpgradeDialog) then
        return false
    end

    if improve.cef.probing and improve.cef.pendingSlot then
        local card = nil
        for _, c in ipairs(improve.cef.cards or {}) do
            if tonumber(c.slot or 0) == tonumber(improve.cef.pendingSlot or 0) then
                card = c
                break
            end
        end

        if card then
            local lvl = Improve_ParseCardLevelFromDialog(dialogText)
            if lvl ~= nil then
                card.level = lvl
            end

            if dialogText:find('Увеличить объем хранения криптовалюты на видео-карте', 1, true) then
                card.storageUpgrade = false
            elseif isChooseDialog then
                card.storageUpgrade = true
            end
        end

        improve.cef.probeDone = true
        sampSendDialogResponse(dialogId, 0, 0, '')
        return true
    end

    if not isChooseDialog then
        return false
    end

    if not (improve.isOn and improve.step == 3) then
        return false
    end

    local perfIndex = nil
    local storageIndex = nil
    local currentIndex = -1

    for line in dialogText:gmatch('[^\r\n]+') do
        currentIndex = currentIndex + 1
        if line:find('Улучшить производительность видео-карты', 1, true) then
            perfIndex = currentIndex
        end
        if line:find('Увеличить объем хранения криптовалюты на видео-карте', 1, true) then
            storageIndex = currentIndex
        end
    end

    local listToClick = 0
    if improve.useStorageUpgrade and storageIndex ~= nil then
        listToClick = storageIndex
    elseif perfIndex ~= nil then
        listToClick = perfIndex
    end

    sampSendDialogResponse(dialogId, 1, listToClick, '')
    return true
end
function Improve_HandleNewStyleConfirmDialog(dialogId, title)
    if not Improve_IsNewStyleMode() then return false end
    if not (improve.isOn and improve.step == 3) then return false end
    if not title:find('{BFBBBA}Улучшение видеокарты') then return false end

    if not improve.useStorageUpgrade then
        if not Improve_HasRequiredOils(2) then
            MI_Say('Недостаточно смазки (нужно 2). Отключаюсь.')
            Improve_LogAdd('WARN', 'Новый стиль: недостаточно смазки. Сессия остановлена.')
            Improve_Stop('Недостаточно смазки в новом стиле')
            return true
        end

        if not improve.consumedThisTry then
            Improve_ConsumeOils(2)
            improve.consumedThisTry = true
        end
    end

    sampSendDialogResponse(dialogId, 1, 0, '')
    improve.waitStart = true
    improve.waitStartAt = os.clock()
    return true
end

local function Improve_TickNewStyle()
    if improve.step ~= 1 then return end

    if (not improve.useStorageUpgrade) and (not Improve_HasRequiredOils(2)) then
        MI_Say('Смазка закончилась. Отключаюсь.')
        Improve_LogAdd('WARN', 'Новый стиль: смазка закончилась. Сессия остановлена.')
        Improve_Stop('Закончилась смазка в процессе (новый стиль)')
        return
    end

    if improve.cef.needInventoryRefresh then
        if not improve.oils.busy then
            Improve_RefreshOils(true)
            improve.cef.needInventoryRefresh = false
            improve.cef.waitInventory = true
            Improve_LogAdd('INFO', 'Новый стиль: обновляю инвентарь перед началом заточки.')
        end
        return
    end

    if improve.cef.waitInventory then
        if improve.oils.busy then return end
        improve.cef.waitInventory = false

        Improve_SyncVideoCardsFromCef()
        if #improve.videoCards == 0 then
            MI_Say('Новый стиль: видеокарты в инвентаре не найдены.')
            Improve_Stop('Новый стиль: не найдены слоты видеокарт')
            return
        end

        improve.cef.probed = false
        Improve_StartNewStyleProbe()
        return
    end

    if improve.cef.probing then return end

    if not improve.cef.probed then
        Improve_StartNewStyleProbe()
        return
    end

    local targetLevel = settings.improve.maxLevel or 2
    local candidate, idxCandidate

    if settings.improve.menuAll then
        for idx, v in ipairs(improve.videoCards) do
            if improve.useStorageUpgrade then
                if not v.storageUpgrade then
                    candidate = v
                    idxCandidate = idx
                    break
                end
            else
                if (v.level or 0) < targetLevel then
                    candidate = v
                    idxCandidate = idx
                    break
                end
            end
        end
    else
        if improve.select == 0 then
            MI_Say('Выбери видеокарту внизу списка.')
            Improve_Stop('Новый стиль: не выбрана видеокарта')
            return
        end
        local v = improve.videoCards[improve.select]
        if v and ((improve.useStorageUpgrade and not v.storageUpgrade) or ((not improve.useStorageUpgrade) and ((v.level or 0) < targetLevel))) then
            candidate = v
            idxCandidate = improve.select
        end
    end

    if not candidate then
        if improve.useStorageUpgrade then
            Improve_Stop('Новый стиль: все видеокарты уже улучшены по хранилищу')
        else
            Improve_Stop('Новый стиль: все видеокарты достигли целевого уровня')
        end
        return
    end

    local slot = tonumber(candidate.slot or 0) or 0
    if slot <= 0 then
        Improve_LogAdd('ERROR', 'Новый стиль: у выбранной видеокарты отсутствует slot.')
        Improve_Stop('Новый стиль: некорректный slot у видеокарты')
        return
    end

    improve.currentIndex = idxCandidate
    improve.consumedThisTry = false
    Improve_SendCefClickOnSlot(slot, 1, 1)
    improve.lastUseAt = os.clock()
    improve.step = 3
end

-- --------------------------------------------------------
--                           TD
-- --------------------------------------------------------

-- Кэш всех TD
local TD = {cache = {}}

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
        settings.style.sizeWindow = defaultSettings.style.sizeWindow
        SaveSettings()
        thisScript():reload()
    end)
    sampRegisterChatCommand("mmtflash", function ()
        StartCollectViaFlash()
    end)

    if notifySuccess and type(notify) == 'table' and type(notify.register_action) == 'function' then
        collectReminderAction = notify.register_action(u8("Запустить сбор"), function()
            StartCollectViaFlash()
        end)
    end

    -- Фоновый поток заточки
    lua_thread.create(function()
        while true do
            wait(10)

            if notifySuccess and type(notify) == 'table' and type(notify.process_actions) == 'function' then
                notify.process_actions()
            end

            -- автообновление инвентаря при старте заточки (если включено)
            if improve.isOn and improve.needCheckOils then
                improve.needCheckOils = false

                if settings.improve.checkOilsOnStart or Improve_IsNewStyleMode() then
                    Improve_RefreshOils(true)  -- асинхронно (/stats + парсинг)
                    improve.waitOils = true
                    if settings.improve.checkOilsOnStart then
                        MI_Say("Проверяю наличие смазки.")
                    else
                        MI_Say("Новый стиль: обновляю инвентарь перед стартом.")
                    end
                else
                    -- проверка отключена - сразу переходим к первому шагу
                    improve.step = 1
                end
            end

            -- ждём завершения сканирования /stats и принимаем решение
            if improve.isOn and improve.waitOils and not improve.oils.busy then
                improve.waitOils = false
                local count, name = Improve_GetOilCountByType()
                if settings.improve.checkOilsOnStart and (not improve.useStorageUpgrade) and count < 2 then
                    MI_Say(("Смазки нет (%s). Нужно минимум 2 - остановлено."):format(name))
                    Improve_LogAdd("WARN", string.format(
                        "Проверка смазки перед стартом: смазки нет (%s). Сессия не запущена.",
                        name
                    ))
                    Improve_Stop("Недостаточно смазки при старте")
                else
                    Improve_LogAdd("INFO", string.format(
                        "Проверка инвентаря перед стартом завершена (%s: %d шт.).",
                        name, count
                    ))
                    improve.step = 1
                end
            end

            -- Сканим видеокарты только по запросу (когда страница изменилась / открылась)
            if ((imguiWindows.main[0] and activeTabScript == "improve") or improve.isOn)
                and improve.inv.needScan then
                Improve_ScanVideoCards()
                improve.inv.needScan = false
            end

            Improve_Tick()
            Collect_ReminderTick()
        end
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

local function HandleFlashCollectServerMessage(text)
    if flashCollect.active and text:find("Эта функция недоступна через флешку", 1, true) then
        FlashCollect_Fail("Сбор через флешку: сервер отклонил использование флешки", TYPECHATMESSAGES.CRITICAL)
    end
end

local function HandleStateCryptoServerMessage(color, text)
    if not stateCrypto.work then
        return nil
    end

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

    if processes.take and (
            text:find("осталось на счету видеокарты:") or (
                text:find("Вам был добавлен предмет") and (
                    text:find(":item1811:", nil, true) or
                    text:find(":item5996:", nil, true) or
                    text:find("Bitcoin (BTC)", nil, true)
                )
            )
        ) and color == -65281 and settings.main.hideMessagesCollect then
        return false
    end

    return nil
end

local function Improve_HandleWaitStartServerMessage(text)
    if not (improve.isOn and improve.waitStart) then
        return
    end

    local startPattern
    local logMessage

    if improve.useStorageUpgrade then
        startPattern = 'Вы начали процесс улучшения увеличения объема хранение видеокарты'
        logMessage = 'Сервер подтвердил начало процесса улучшения хранилища видеокарты.'
    else
        startPattern = 'Вы начали процесс улучшения производительности видеокарты'
        logMessage = 'Сервер подтвердил начало процесса улучшения уровня видеокарты.'
    end

    if text:find(startPattern) then
        improve.waitStart = false
        improve.waitStartAt = 0
        improve.waitResultAt = os.clock()
        improve.step = 4
        Improve_LogAdd("INFO", logMessage)
        Improve_AttemptStart()
    end
end

local function Improve_HandleUseRetryServerMessage(text)
    if not (improve.isOn and improve.step == 3) then
        return
    end

    if text:find('Подождите немного') then
        Improve_LogAdd("WARN", "Сервер ответил \"Подождите немного.\" - повторяем нажатие кнопки \"Использовать\".")
        lua_thread.create(function ()
            wait(1000)
            if improve.isOn and improve.step == 3 then
                Improve_ClickUse()
            end
        end)
    end
end

local function Improve_HandleStorageUpgradeServerMessage(text)
    if not (improve.isOn and improve.step == 3 and improve.useStorageUpgrade) then
        return
    end

    if text:find('[Ошибка] {ffffff}У вас нет увеличителя пропускной способности', nil, true) then
        MI_Say("У вас нет увеличителя пропускной способности!")
        Improve_LogAdd("ERROR", "Получено сообщение об отсутствии увеличителя пропускной способности. Сессия остановлена.")
        Improve_Stop("Нет увеличителя пропускной способности")
    end

    if text:find('[Ошибка] {ffffff}На выбранной видео-карте уже увеличен объём хранение криптовалюты', nil, true) then
        MI_Say("Видеокарта уже улучшена, переходим к следующей")
        Improve_LogAdd("ERROR", "Получено сообщение о уже увеличен объём хранение криптовалюты")

        lua_thread.create(function ()
            wait(settings.deley.improve_waitResult or 600)
            local card = improve.videoCards[improve.currentIndex]
            if card then
                card.storageUpgrade = true
            end
            improve.step = 1
            improve.consumedThisTry = false
        end)
    end
end

local function Improve_HandleResultServerMessage(text)
    if not (improve.isOn and improve.step == 4) then
        return
    end

    local isFail
    local isSuccess

    if improve.useStorageUpgrade then
        isFail = text:find('^%[Информация%] {ffffff}При улучшении выбранной видеокарты вы допустили техническую ошибку, попробуйте еще раз%.$')
        isSuccess = text:find('^%[Информация%] {ffffff}Вы успешно увеличили объем хранения криптовалюты')
    else
        isFail = text:find('^%[Информация%] {ffffff}При улучшении выбранной видеокарты вы допустили техническую ошибку, попробуйте еще раз%.$')
        isSuccess = text:find('^%[Информация%] {ffffff}Вы успешно улучшили выбранную')
    end

    if isFail or isSuccess then
        Improve_OnResult(isSuccess == true, text)

        lua_thread.create(function ()
            wait(settings.deley.improve_waitResult or 600)
            improve.waitResultAt = 0
            improve.lastUseAt = 0
            improve.step = 1
            improve.consumedThisTry = false
        end)
    end
end

local function Improve_HandleProbeServerMessage(text)
    if improve.cef.probing and text:find('Чтобы установить видеокарту, вы должны находиться в подвале возле одной из специальных стоек') then
        improve.cef.probeAbort = true
        improve.cef.probeAbortReason = 'нужно находиться в подвале возле стойки'
        improve.cef.probeDone = true
    end
end

local function Improve_HandleInvalidPlaceServerMessage(text)
    if improve.isOn and text:find('Чтобы установить видеокарту, вы должны находиться в подвале возле одной из специальных стоек') then
        MI_Say("Недопустимое место заточки!")
        Improve_LogAdd("ERROR", "Получено сообщение о неверном месте заточки. Сессия остановлена.")
        Improve_Stop("Неподходящее место заточки")
    end
end

function sampev.onServerMessage(color, text)
    HandleFlashCollectServerMessage(text)

    local handled = HandleStateCryptoServerMessage(color, text)
    if handled ~= nil then
        return handled
    end

    Improve_HandleWaitStartServerMessage(text)
    Improve_HandleUseRetryServerMessage(text)
    Improve_HandleStorageUpgradeServerMessage(text)
    Improve_HandleResultServerMessage(text)
    Improve_HandleProbeServerMessage(text)
    Improve_HandleInvalidPlaceServerMessage(text)
end


-- --------------------------------------------------------
--                           onShowDialog
-- --------------------------------------------------------

local function DialogReturnVisibility()
    return not settings.main.replaceDialog
end

local function HandleBankDepositDialog(dialogId, title, text)
    local dialogTitle = tostring(title or "")
    local dialogText = tostring(text or "")
    local isBankTitle = dialogTitle:find("Баланс домашнего сч", 1, true) ~= nil
    local hasCurrentState = dialogText:find("Текущее состояние сч", 1, true) ~= nil
    local hasCanTopup = dialogText:find("Можно пополнить сч", 1, true) ~= nil

    if not (stateCrypto.work and processes.dep and (isBankTitle or (hasCurrentState and hasCanTopup))) then
        return nil
    end

    local function parseSmileMoneyValue(valueText)
        local raw = tostring(valueText or "")
        local numbers = {}

        for amount in raw:gmatch("%d[%d%.]*") do
            table.insert(numbers, tonumber((amount:gsub("%.", ""))) or 0)
        end

        if #numbers == 0 then
            return 0
        end

        if #numbers >= 2 and numbers[1] < 1000 then
            return numbers[1] * 1000000 + numbers[2]
        end

        if raw:find("KK", 1, true) and numbers[1] < 1000 then
            return numbers[1] * 1000000
        end

        return numbers[1]
    end

    local canLine = text:match("Можно пополнить счёт ещё на:%s*(.-)[\r\n]") or text:match("Можно пополнить счет еще на:%s*(.-)[\r\n]") or ""
    local can = parseSmileMoneyValue(canLine)

    local cur = tonumber(stateCrypto.queueHousesBank[stateCrypto.progressHousesBank].bankNow) or 0
    local target = (settings.main.bankFillToTarget and settings.main.bankTargetAmount) or nil

    local dep
    if target and target > 0 then
        if cur >= target then
            DialogUtils.waitAndSendDialogResponse(dialogId, 0, 0, "")
            return DialogReturnVisibility()
        end
        dep = target - cur
    else
        dep = can
    end

    local PER_OP_LIMIT = 10000000
    dep = math.minEx(dep, math.maxEx(0, can - 1))
    dep = math.minEx(dep, PER_OP_LIMIT)
    if dep <= 0 then
        DialogUtils.waitAndSendDialogResponse(dialogId, 0, 0, "")
        return DialogReturnVisibility()
    end

    DialogUtils.waitAndSendDialogResponse(dialogId, 1, 0, tostring(dep))
    stateCrypto.queueHousesBank[stateCrypto.progressHousesBank].bankNow = cur + dep
    return DialogReturnVisibility()
end
local function HandleTakeProfitDialog(dialogId, title)
    if not (stateCrypto.work and processes.take and title:find("Вывод прибыли видеокарты")) then
        return nil
    end

    local queueShelf = stateCrypto.queueShelves[stateCrypto.progressShelves]
    if queueShelf then
        queueShelf.count = (queueShelf.count or 0) - (stateCrypto.takeCount or 0)
    end

    if stateCrypto.takeCount and stateCrypto.takeCount > 0 and stateCrypto.takeCurrency then
        local cur = stateCrypto.takeCurrency
        local hid = stateCrypto.currentHouseId or 0

        collectStats.total[cur] = (collectStats.total[cur] or 0) + stateCrypto.takeCount
        collectStats.house[hid] = collectStats.house[hid] or { BTC = 0, ASC = 0 }
        collectStats.house[hid][cur] = (collectStats.house[hid][cur] or 0) + stateCrypto.takeCount

        AddCollectLogEntry(hid, cur, stateCrypto.takeCount)
    end

    DialogUtils.waitAndSendDialogResponse(dialogId, 1, 0, "")
    stateCrypto.takeCount = 0
    stateCrypto.takeCurrency = nil
    return DialogReturnVisibility()
end

local function HandleShelfDialog(dialogId, title, text)
    if not (stateCrypto.work and title:find("Стойка") and title:find("Полка")) then
        return nil
    end

    local actions = ParseShelfVideoCardData(text)
    local queueShelf = stateCrypto.queueShelves[stateCrypto.progressShelves]
    local onAction = nil

    for _, value in ipairs(actions) do
        if value.action == "on" and not onAction then
            onAction = value
        end

        if processes.take then
            if value.count > 0 and (value.action == "take_btc" or value.action == "take_asc") then
                stateCrypto.takeCount = value.count
                stateCrypto.takeCurrency = (value.action == "take_btc") and "BTC" or "ASC"
                DialogUtils.waitAndSendDialogResponse(dialogId, 1, value.samp_line, "")
                return DialogReturnVisibility()
            end
        end

        if processes.fill and value.action == "fill" then
            if queueShelf and (queueShelf.fill or 0) > settings.main.fillFrom then
                if settings.main.autoEnableCards and not queueShelf.work and (queueShelf.fill or 0) > 0 and onAction then
                    queueShelf.work = true
                    DialogUtils.waitAndSendDialogResponse(dialogId, 1, onAction.samp_line, "")
                    return DialogReturnVisibility()
                end

                stateCrypto.progressShelves = stateCrypto.progressShelves + 1
                DialogUtils.waitAndSendDialogResponse(dialogId, 0, 0, "")
                return DialogReturnVisibility()
            end
            DialogUtils.waitAndSendDialogResponse(dialogId, 1, value.samp_line, "")
            return DialogReturnVisibility()
        end

        if processes.on and value.action == "on" then
            DialogUtils.waitAndSendDialogResponse(dialogId, 1, value.samp_line, "")
            return DialogReturnVisibility()
        elseif processes.on and value.action == "off" then
            if queueShelf then
                queueShelf.work = true
            end
            stateCrypto.progressShelves = stateCrypto.progressShelves + 1
            DialogUtils.waitAndSendDialogResponse(dialogId, 0, 0, "")
            return DialogReturnVisibility()
        end

        if processes.off and value.action == "off" then
            DialogUtils.waitAndSendDialogResponse(dialogId, 1, value.samp_line, "")
            return DialogReturnVisibility()
        elseif processes.off and value.action == "on" then
            if queueShelf then
                queueShelf.work = false
            end
            stateCrypto.progressShelves = stateCrypto.progressShelves + 1
            DialogUtils.waitAndSendDialogResponse(dialogId, 0, 0, "")
            return DialogReturnVisibility()
        end
    end

    if processes.take and queueShelf and math.floor(queueShelf.count or 0) <= 0 then
        if settings.main.autoEnableCards and not queueShelf.work and (queueShelf.fill or 0) > 0 and onAction then
            queueShelf.work = true
            DialogUtils.waitAndSendDialogResponse(dialogId, 1, onAction.samp_line, "")
            return DialogReturnVisibility()
        end

        stateCrypto.progressShelves = stateCrypto.progressShelves + 1
        DialogUtils.waitAndSendDialogResponse(dialogId, 0, 0, "")
        return DialogReturnVisibility()
    end

    return DialogReturnVisibility()
end

local function HandleLiquidChoiceDialog(dialogId, title, text)
    if not (stateCrypto.work and processes.fill and not stateCrypto.waitFill and title:find("Выберите тип жидкости")) then
        return nil
    end

    local actions = ParseLiquidData(text)
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

    local cur = stateCrypto.queueShelves[stateCrypto.progressShelves]
    local card = cur and cur.card_type or nil

    if (not card or card == "BTC") and (text:find("ASIC") or text:find("Достать ASIC")) then
        card = "ASIC"
    end

    local choice = nil
    if card == "ASC" then
        if counts.asc > 0 then choice = "asc" end
    else
        if counts.btc > 0 then
            choice = "btc"
        elseif counts.supper_btc > 0 then
            choice = "supper_btc"
        elseif not card and counts.asc > 0 then
            choice = "asc"
        end
    end

    if choice then
        stateCrypto.waitFill = true
        DialogUtils.waitAndSendDialogResponse(dialogId, 1, lines[choice], "")
        return DialogReturnVisibility()
    end

    processes.fill = false
    local reason = (card == "ASC") and "нет охлаждайки ASC" or "нет охлаждайки BTC/super"
    AddChatMessage("Охлаждение: " .. reason .. " для текущей карты", TYPECHATMESSAGES.CRITICAL)
    return nil
end

local function HandleVideoCardSelectionDialog(dialogId, title, text)
    if not title:find("Выберите видеокарту") then
        return nil
    end

    if title:find("дом") then
        stateCrypto.activeHouseID = title:match("дом №(%d+)") or "-1"
        idDialogs.selectVideoCardItemFlash = dialogId
    end
    idDialogs.selectVideoCard = dialogId
    imguiWindows.main[0] = true

    local openedViaFlash = (dialogId == idDialogs.selectVideoCardItemFlash)
    if openedViaFlash then
        housesBanks = {}
    else
        houses = {}
        housesBanks = {}
    end
    shelves = ParseShelfData(text)

    if settings.main.autoFillEnabled and not stateCrypto.work and not openedViaFlash then
        local needFill = false
        for _, s in ipairs(shelves) do
            if (s.percentage or 0) <= (settings.main.fillFrom or 50.0) then
                needFill = true
                break
            end
        end

        if needFill then
            lua_thread.create(function()
                wait(50)
                StartProcessInteracting("fill")
            end)
        end
    end

    return DialogReturnVisibility()
end

local function HandleHouseSelectionDialog(dialogId, title, text)
    if not title:find("Выбор дома") then
        return nil
    end

    shelves = {}
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
    if flashCollect.waitHouseDialog and #houses > 0 then
        flashCollect.houseDialogReady = true
        flashCollect.waitHouseDialog = false
    end

    imguiWindows.main[0] = true
    return DialogReturnVisibility()
end

local function HandleImproveClassicChooseDialog(dialogId, title, text)
    if not (Improve_IsClassicMode() and improve.isOn and improve.step == 3 and title:find("{BFBBBA}Выберите вид улучшения для видеокарты")) then
        return nil
    end

    local perfIndex = nil
    local storageIndex = nil
    local currentIndex = -1

    for line in (text or ""):gmatch("[^\r\n]+") do
        currentIndex = currentIndex + 1

        if line:find("Улучшить производительность видео-карты", nil, true) then
            perfIndex = currentIndex
        end

        if line:find("Увеличить объем хранения криптовалюты на видео-карте", nil, true) then
            storageIndex = currentIndex
        end
    end

    local listToClick = 0
    if improve.useStorageUpgrade and storageIndex ~= nil then
        listToClick = storageIndex
    elseif perfIndex ~= nil then
        listToClick = perfIndex
    end

    sampSendDialogResponse(dialogId, 1, listToClick, "")
    return DialogReturnVisibility()
end

local function HandleImproveClassicConfirmDialog(dialogId, title)
    if not (Improve_IsClassicMode() and improve.isOn and improve.step == 3 and title:find("{BFBBBA}Улучшение видеокарты")) then
        return nil
    end

    if not improve.useStorageUpgrade then
        if not Improve_HasRequiredOils(2) then
            MI_Say("Недостаточно смазки (нужно 2). Отключаюсь.")
            improve.isOn = false
            improve.step = 0
            return DialogReturnVisibility()
        end

        if not improve.consumedThisTry then
            Improve_ConsumeOils(2)
            improve.consumedThisTry = true
        end
    end

    sampSendDialogResponse(dialogId, 1, 0, "")
    improve.waitStart = true
    improve.waitStartAt = os.clock()
    return DialogReturnVisibility()
end

local function HandleStatsInventoryDialog(dialogId, title, text)
    if not (improve.oils.busy or flashCollect.statsBusy) then
        return nil
    end

    if title:find('Основная статистика') then
        sampSendDialogResponse(dialogId, 1, 0, '')
        return false
    end

    if not title:find('ID:') then
        return nil
    end

    if improve.oils.busy then
        Improve_ParseInventoryDialogPage(text or '')
    end
    if flashCollect.statsBusy then
        FlashCollect_ParseStatsInventoryPage(text or '')
    end

    if (text or ''):find('Следующая%sстраница') then
        sampSendDialogResponse(dialogId, 1, 0, '')
        return false
    end

    if improve.oils.busy then
        improve.oils.busy = false
        improve.oils.lastAt = os.date('%H:%M')
    end
    if flashCollect.statsBusy then
        flashCollect.statsBusy = false
        flashCollect.lastStatsAt = os.date('%H:%M')
    end
    sampSendDialogResponse(dialogId, 0, 0, '')
    return false
end

function sampev.onShowDialog(dialogId, style, title, button1, button2, text)

    lastIDDialog = dialogId

    local handled = HandleBankDepositDialog(dialogId, title, text)
    if handled ~= nil then
        return handled
    end

    handled = HandleTakeProfitDialog(dialogId, title)
    if handled ~= nil then
        return handled
    end

    handled = HandleShelfDialog(dialogId, title, text)
    if handled ~= nil then
        return handled
    end

    handled = HandleLiquidChoiceDialog(dialogId, title, text)
    if handled ~= nil then
        return handled
    end

    handled = HandleVideoCardSelectionDialog(dialogId, title, text)
    if handled ~= nil then
        return handled
    end

    handled = HandleHouseSelectionDialog(dialogId, title, text)
    if handled ~= nil then
        return handled
    end

    if Improve_HandleNewStyleChooseDialog(dialogId, title, text) then
        return DialogReturnVisibility()
    end

    if Improve_HandleNewStyleConfirmDialog(dialogId, title) then
        return DialogReturnVisibility()
    end

    handled = HandleImproveClassicChooseDialog(dialogId, title, text)
    if handled ~= nil then
        return handled
    end

    handled = HandleImproveClassicConfirmDialog(dialogId, title)
    if handled ~= nil then
        return handled
    end

    handled = HandleStatsInventoryDialog(dialogId, title, text)
    if handled ~= nil then
        return handled
    end

    -- if not stateCrypto.work then
    --     imguiWindows.main[0] = false
    -- end
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

function sampev.onReceiveRpc(id, bs)
    if not flashCollect.active then
        return
    end

    if id ~= 220 then
        return
    end

    raknetBitStreamIgnoreBits(bs, 8)
    if raknetBitStreamReadInt8(bs) ~= 17 then
        raknetBitStreamResetReadPointer(bs)
        return
    end

    raknetBitStreamIgnoreBits(bs, 32)
    local length = raknetBitStreamReadInt16(bs)
    local encoded = raknetBitStreamReadInt8(bs)
    local str = (encoded ~= 0)
        and raknetBitStreamDecodeString(bs, length + encoded)
        or raknetBitStreamReadString(bs, length)

    if flashCollect.active and str and str:find('event.inventory.playerInventory', 1, true) then
        flashCollect.inventoryOpened = true
    end

    raknetBitStreamResetReadPointer(bs)
end

function IsArrowNavigationAvailable()
    if activeTabScript ~= "main" then
        return false
    end
    if #housesBanks > 0 then
        return true
    end
    if #houses > 0 then
        return true
    end
    return #shelves > 0
end
function onWindowMessage(msg, wparam, lparam)
    if not keysSuccess then return end

    local isMainWindowActive = imguiWindows.main[0]
    local isPauseInactive    = not isPauseMenuActive()

    if (msg == 0x0100 or msg == 0x0101)
       and isMainWindowActive and isPauseInactive
       and settings.main.arrowsMove
       and IsArrowNavigationAvailable()
    then
        local io = imgui.GetIO()
        local wantkbd = io and io.WantCaptureKeyboard
        if not wantkbd and (
            wparam == vkeys.VK_UP or
            wparam == vkeys.VK_DOWN
        ) then
            consumeWindowMessage(true, false)
            return
        end
    end

    -- =========================================================================
    local isEscapePressed   = (wparam == vkeys.VK_ESCAPE)
    local shouldCloseOnEsc  = settings.main.closeOnESC

    if (msg == 0x100 or msg == 0x101) and isEscapePressed and isMainWindowActive and isPauseInactive and shouldCloseOnEsc then
        consumeWindowMessage(true, false)
        if msg == 0x101 then
            SwitchMainWindow()
            DeactivateProcessesInteracting()
            sampSendDialogResponse(lastIDDialog, 0, 0, "")
            shelves = {}
            houses = {}
            housesBanks = {}
        end
    end
end

function sampev.onShowTextDraw(id, data)
    if ISMONETLOADER then
        TD.cache[id] = data
    end

    -- Кнопки переключения страниц инвентаря видеокарт
    if data.text == "LD_BEAT:chit"
        and data.position.x > 320 and data.position.y > 240
        and ((imguiWindows.main[0] and activeTabScript == "improve") or improve.isOn) then

        -- первый раз запоминаем id первой кнопки страницы
        if improve.inv.pageTD == 0 then
            improve.inv.pageTD   = id
            improve.inv.activePage = 1
            Improve_MarkNeedScan()
        else
            -- если обновился именно первый TD страницы - считаем, что страницу перелистнули
            if id == improve.inv.pageTD then
                improve.inv.activePage = (improve.inv.activePage or 1)
                Improve_MarkNeedScan()
            end
        end
    end

    -- Появление кнопки USE сигналит о готовности подтверждения крафта
    if (data.text == 'USE' or Translationtextdraw(data.text) == 'ИСПОЛЬЗОВАТЬ') and improve.step == 2 then
        -- Переходим на шаг 3 - ожидание клика по "Использовать"
        improve.step = 3

        -- Сохраняем ID текстдравов, чтобы можно было нажимать ещё раз
        improve.useClickId = id + 1   -- кликабельный TD
        improve.useTextId  = id       -- TD с текстом "USE"

        -- Первая автоматическая попытка нажать
        Improve_ClickUse()
    end
end

function sampev.onHideTextDraw(id)
    if ISMONETLOADER then TD.cache[id] = nil end

    -- Если скрылась кнопка страниц - сбрасываем состояние инвентаря
    if improve.inv and id == improve.inv.pageTD then
        improve.inv.pageTD     = 0
        improve.inv.activePage = 1
        improve.inv.needScan   = false
        improve.videoCards     = {}
        improve.currentIndex   = 0
    end
end

function sampev.onTextDrawSetString(id, text)
    if ISMONETLOADER and TD.cache[id] then TD.cache[id].text = text end
end

function sampev.onTextDrawSetPreviewModel(id, modelId, rx, ry, rz, zoom)
    if ISMONETLOADER then 
        local t = TD.cache[id] or {}
        t.modelId  = modelId
        TD.cache[id] = t
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

-- level            : уровень видеокарты (целое)
-- cool_percent_opt : (опц.) остаток охлаждения в процентах [0..100]
-- min_percent_opt  : (опц.) порог доливки, если задан - "время" до доливки,
--                    иначе - до полного нуля
-- Возвращает:
--   per_hour, per_24h, per_cycle, hours_to_show, income_to_end
-- где:
--   hours_to_show  - время до доливки (если выше порога) ИЛИ до конца работы (если порог уже пройден)
--   income_to_end  - прибыль до полного окончания охлаждайки (всегда до нуля)
local function CalcGpuIncome(level, cool_percent_opt, min_percent_opt, bonus_percent_opt)
    level = tonumber(level) or 1
    local per_hour  = GPU_HOURLY_BY_LEVEL[level] or 0
    local bonus_percent = tonumber(bonus_percent_opt) or 0
    if bonus_percent < 0 then
        bonus_percent = 0
    end
    per_hour = per_hour * (1 + bonus_percent / 100)
    local per_24h   = per_hour * 24
    local per_cycle = per_hour * GPU_CYCLE_HOURS

    local hours_to_show  = 0
    local income_to_end  = 0

    if cool_percent_opt ~= nil then
        -- нормализуем проценты
        local p = tonumber(cool_percent_opt) or 0
        if p < 0 then p = 0 elseif p > 100 then p = 100 end

        -- Всегда считаем "до нуля"
        local hours_until_zero = (p / 100) * GPU_CYCLE_HOURS
        income_to_end = per_hour * hours_until_zero

        -- Логика показа "времени":
        -- если выше порога - показываем до доливки,
        -- если на/ниже порога - показываем до конца работы (до нуля)
        local threshold = tonumber(min_percent_opt)
        if threshold ~= nil then
            if threshold < 0 then threshold = 0 elseif threshold > 100 then threshold = 100 end
            if p > threshold then
                hours_to_show = ((p - threshold) / 100) * GPU_CYCLE_HOURS
            else
                hours_to_show = hours_until_zero
            end
        else
            -- порога нет - просто до конца работы
            hours_to_show = hours_until_zero
        end
    end

    return per_hour, per_24h, per_cycle, hours_to_show, income_to_end
end

local function GetIncomeSettings()
    settings.main.income = settings.main.income or {}
    settings.main.income.houseBonuses = settings.main.income.houseBonuses or {}
    settings.main.income.onlineHours = math.minEx(24, math.maxEx(0, math.floor(tonumber(settings.main.income.onlineHours) or 0)))
    return settings.main.income
end

local function NormalizeIncomeHouseBonusConfig(config)
    config = (type(config) == "table") and config or {}
    config.creativitySet = config.creativitySet == true
    config.customPercent = math.maxEx(0, tonumber(config.customPercent) or 0)
    config.onlineHours = nil
    return config
end

local function GetIncomeHouseBonusConfig(houseId)
    local numericHouseId = tonumber(houseId)
    if not numericHouseId or numericHouseId <= 0 then
        return nil, nil
    end

    local houseKey = tostring(math.floor(numericHouseId))
    local houseBonuses = GetIncomeSettings().houseBonuses
    local config = houseBonuses[houseKey]
    if type(config) ~= "table" then
        return nil, houseKey
    end

    config = NormalizeIncomeHouseBonusConfig(config)
    houseBonuses[houseKey] = config
    return config, houseKey
end

local function CalcHouseIncomeBonusPercent(houseId)
    local onlineHours = GetIncomeSettings().onlineHours or 0
    local bonusPercent = 20 * (onlineHours / 24)

    local config = GetIncomeHouseBonusConfig(houseId)
    if not config then
        return bonusPercent
    end

    bonusPercent = bonusPercent + (tonumber(config.customPercent) or 0)
    if config.creativitySet then
        bonusPercent = bonusPercent + 20
    end

    return bonusPercent
end

local function GetSortedIncomeHouseBonusKeys()
    local keys = {}
    for houseKey in pairs(GetIncomeSettings().houseBonuses) do
        table.insert(keys, tostring(houseKey))
    end

    table.sort(keys, function(a, b)
        return (tonumber(a) or 0) < (tonumber(b) or 0)
    end)

    return keys
end

-- ---- Утилиты для очистки кэша при перезапуске заточки/перезаходе ----
function TD.Reset()
    for k in pairs(TD.cache) do TD.cache[k] = nil end
end

-- ---- Простые обёртки, которые ты будешь звать из логики заточки ----
function TD_IsExists(id)
    if not ISMONETLOADER then
        local ok, res = pcall(sampTextdrawIsExists, id)
        if ok then return res end
    end
    local t = TD.cache[id]
    return t ~= nil
end

function TD_GetString(id)
    if not ISMONETLOADER then
        local ok, res = pcall(sampTextdrawGetString, id)
        if ok then return res end
    end
    local t = TD.cache[id]
    return t and t.text or nil
end

-- Возвращает (modelId, rx, ry, rz, zoom, vehColor)
function TD_GetModelInfo(id)
    if not ISMONETLOADER then
        local ok, a,b,c,d,e,f = pcall(sampTextdrawGetModelRotationZoomVehColor, id)
        if ok then return a,b,c,d,e,f end
    end
    local t = TD.cache[id] or {}
    return t.modelId or 0, 0.0, 0.0, 0.0, 1.0, 0
end

-- Возвращает (letterColor, boxColor) - во многих скриптах boxColor используют как outline
function TD_GetOutlineColor(id)
    if not ISMONETLOADER then
        local ok, a,b = pcall(sampTextdrawGetOutlineColor, id)
        if ok then return a,b end
    end
    local t = TD.cache[id] or {}
    return t.letterColor or -1, t.boxColor or -1
end

function TD_GetBackgroundColor(id)
    -- Мобайл: из кэша (если есть)
    if TD and TD.cache and TD.cache[id] then
        return TD.cache[id].backgroundColor
    end
    return nil
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
                count = (shelf.profit_primary or shelf.profit or 0) + (shelf.profit2 or 0),
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
    local function NeedTopupForBank(now)
        local nowNum = tonumber(now) or 0
        if settings.main.bankFillToTarget and (settings.main.bankTargetAmount or 0) > 0 then
            return nowNum < (settings.main.bankTargetAmount or 0)
        else
            -- старое поведение: до тех пор, пока <= порог maxBankAmount
            return nowNum <= settings.main.maxBankAmount
        end
    end

    local filtered = {}
    for _, house in ipairs(housesBanks) do
        if NeedTopupForBank(house.bankNow) then
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

        local function NeedTopupForBankValue(now)
            local nowNum = tonumber(now) or 0
            if settings.main.bankFillToTarget and (settings.main.bankTargetAmount or 0) > 0 then
                return nowNum < (settings.main.bankTargetAmount or 0)
            else
                return nowNum <= settings.main.maxBankAmount
            end
        end

        -- Повторяем пополнение, пока не достигнем цели/максимума.
        while NeedTopupForBankValue(houseData.bankNow) do
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
            wait(50)

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

        if processes.take and stateCrypto.currentHouseId and collectStats.house[stateCrypto.currentHouseId] then
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

    collectStats = { total = { BTC = 0, ASC = 0 }, house = {} }
    stateCrypto.currentHouseId = nil

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

    -- Итоги по всем домам (если больше одного дома или просто удобно видеть общий итог)
    if ( (collectStats.total.BTC > 0) or (collectStats.total.ASC > 0) ) and processes.take then
        AddChatMessage(string.format(
            "Итого за сессию: %s BTC и %s ASC",
            collectStats.total.BTC or 0, collectStats.total.ASC or 0
        ), TYPECHATMESSAGES.SUCCESS)
    end

    DeactivateProcessesInteracting()
    AddChatMessage("Обработка завершена успешно", TYPECHATMESSAGES.SUCCESS)
end

function CheckProcessInteracting()
    return processes.take or processes.fill or processes.on or processes.off or processes.dep
end

function DeactivateProcessesInteracting()
    stateCrypto.work = false
    stateCrypto.waitFill = false
    stateCrypto.waitDep = false
    stateCrypto.takeCount = 0
    stateCrypto.takeCurrency = nil
    stateCrypto.currentHouseId = nil
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
--                           Improve
-- --------------------------------------------------------

-- ===== ЛОГИ ЗАТОЧКИ / СТАТИСТИКА =====

-- запись одной строки в файл лога за текущий день: logs/YYYY-MM-DD.log
function Improve_WriteLogLine(line)
    if not IMPROVE_LOGS_DIR or not line or line == "" then return end

    local filename = os.date('%Y-%m-%d') .. ".log"
    local fullPath = IMPROVE_LOGS_DIR .. filename

    local folderPath = fullPath:match("^(.*[/\\])")
    if folderPath then
        pcall(EnsureDirectoryExists, folderPath)
    end

    local ok, fh = pcall(io.open, fullPath, "a")
    if ok and fh then
        fh:write(line, "\n")
        fh:close()
    end
end

-- загрузка/инициализация общей статистики из JSON
function Improve_GetStatsStore()
    if not IMPROVE_STATS_FILE then return nil end

    if not improve.statsStore then
        local ok, data = pcall(LoadJSON, IMPROVE_STATS_FILE)
        if not ok or type(data) ~= 'table' then
            data = {}
        end
        data.days = data.days or {}
        data.total = data.total or {
            sessions  = 0,
            attempts  = 0,
            success   = 0,
            fail      = 0,
            oilsUsed  = 0,
            spent     = 0,
            byLevel   = {},
            time      = 0,
        }
        improve.statsStore = data
    end

    return improve.statsStore
end

-- сохранение статистики в JSON
function Improve_SaveStatsStore()
    if not IMPROVE_STATS_FILE or not improve.statsStore then return end
    pcall(SaveJSON, IMPROVE_STATS_FILE, improve.statsStore)
end

-- внутренняя функция добавления записи в лог
local function Improve_GetLevelStatsTemplate()
    local t = {}
    for lvl = 1, 9 do
        t[lvl] = {
            attempts = 0,
            success = 0,
            fail = 0,
            spent = 0,
        }
    end
    return t
end

local function Improve_EnsureLevelStats(statsObj)
    if type(statsObj) ~= 'table' then return end
    if type(statsObj.byLevel) ~= 'table' then
        statsObj.byLevel = Improve_GetLevelStatsTemplate()
    end
    for lvl = 1, 9 do
        local row = statsObj.byLevel[lvl]
        if type(row) ~= 'table' then
            statsObj.byLevel[lvl] = { attempts = 0, success = 0, fail = 0, spent = 0 }
        else
            row.attempts = tonumber(row.attempts or 0) or 0
            row.success  = tonumber(row.success  or 0) or 0
            row.fail     = tonumber(row.fail     or 0) or 0
            row.spent    = tonumber(row.spent    or 0) or 0
        end
    end
end

local function Improve_GetPriceByFromLevel(level)
    return tonumber(GPU_IMPROVE_PRICE_BY_LEVEL[tonumber(level or 0) or 0]) or 0
end

function Improve_LogAdd(evType, text)
    if not improve.logs then
        improve.logs = { items = {}, max = 300, autoScroll = true }
    end

    local ts    = os.date('%d.%m.%Y %H:%M:%S')
    local ttype = evType or "INFO"
    local msg   = text or ""

    local line = string.format("[%s] [%s] %s", ts, ttype, msg)

    -- в память (для UI)
    table.insert(improve.logs.items, {
        ts   = ts,
        type = ttype,
        text = msg,
        step = improve.step,
    })

    local maxCount = improve.logs.max or 300
    while #improve.logs.items > maxCount do
        table.remove(improve.logs.items, 1)
    end

    -- опционально в консоль, если включён debug
    if settings.main.typeChatMessage and settings.main.typeChatMessage.debug then
        print("[IMPROVE] " .. line)
    end

    -- в файл по дате
    Improve_WriteLogLine(line)
end

-- старт сессии заточки
function Improve_SessionStart()
    Improve_GetStatsStore()

    local s = improve.stats or {}
    s.sessionId  = (s.sessionId or 0) + 1
    s.active     = true
    s.startedAt  = os.time()
    s.finishedAt = 0
    s.attempts   = 0
    s.success    = 0
    s.fail       = 0
    s.oilsUsed   = 0
    s.spent      = 0
    s.byLevel    = Improve_GetLevelStatsTemplate()
    s.lastAttempt = nil
    s.lastReason = ""
    improve.stats = s

    local modeName  = (settings.improve.mode == 1) and "Последовательное" or "Поочередное"
    local cardsName = (settings.improve.typeCards == 2) and "Arizona" or "Обычные"
    local maxLevel  = settings.improve.maxLevel or 2
    local checkOils = settings.improve.checkOilsOnStart and "Да" or "Нет"
    local invMode   = Improve_GetInventoryModeName()

    Improve_LogAdd("INFO", string.format(
        "Старт сессии #%d. Карты: %s, режим: %s, инвентарь: %s, целевой уровень: %d, проверять смазку: %s.",
        s.sessionId, cardsName, modeName, invMode, maxLevel, checkOils
    ))
end

-- завершение сессии заточки + обновление суточной и общей статистики
function Improve_SessionStop(reason)
    local s = improve.stats
    if not s or not s.active then return end

    s.active     = false
    s.finishedAt = os.time()
    s.lastReason = reason or s.lastReason or "не указано"

    local duration = 0
    if s.startedAt and s.startedAt > 0 then
        duration = math.max(0, s.finishedAt - s.startedAt)
    end

    -- Обновляем статистику по дням и общую
    local store = Improve_GetStatsStore()
    if store then
        Improve_EnsureLevelStats(store.total)
    end
    if store then
        local dayKey
        if s.startedAt and s.startedAt > 0 then
            dayKey = os.date('%Y-%m-%d', s.startedAt)
        else
            dayKey = os.date('%Y-%m-%d')
        end

        store.days = store.days or {}
        local day = store.days[dayKey] or {
            sessions  = 0,
            attempts  = 0,
            success   = 0,
            fail      = 0,
            oilsUsed  = 0,
            spent     = 0,
            byLevel   = {},
            time      = 0,
        }
        Improve_EnsureLevelStats(day)

        day.sessions  = (day.sessions  or 0) + 1
        day.attempts  = (day.attempts  or 0) + (s.attempts or 0)
        day.success   = (day.success   or 0) + (s.success  or 0)
        day.fail      = (day.fail      or 0) + (s.fail     or 0)
        day.oilsUsed  = (day.oilsUsed  or 0) + (s.oilsUsed or 0)
        day.spent     = (day.spent     or 0) + (s.spent or 0)
        day.time      = (day.time      or 0) + duration
        Improve_EnsureLevelStats(s)
        for lvl = 1, 9 do
            local src = s.byLevel[lvl] or {}
            local dst = day.byLevel[lvl] or { attempts = 0, success = 0, fail = 0, spent = 0 }
            dst.attempts = (dst.attempts or 0) + (src.attempts or 0)
            dst.success  = (dst.success  or 0) + (src.success  or 0)
            dst.fail     = (dst.fail     or 0) + (src.fail     or 0)
            dst.spent    = (dst.spent    or 0) + (src.spent    or 0)
            day.byLevel[lvl] = dst
        end

        store.days[dayKey] = day

        local total = store.total or {
            sessions  = 0,
            attempts  = 0,
            success   = 0,
            fail      = 0,
            oilsUsed  = 0,
            spent     = 0,
            byLevel   = {},
            time      = 0,
        }
        Improve_EnsureLevelStats(total)

        total.sessions  = (total.sessions  or 0) + 1
        total.attempts  = (total.attempts  or 0) + (s.attempts or 0)
        total.success   = (total.success   or 0) + (s.success  or 0)
        total.fail      = (total.fail      or 0) + (s.fail     or 0)
        total.oilsUsed  = (total.oilsUsed  or 0) + (s.oilsUsed or 0)
        total.spent     = (total.spent     or 0) + (s.spent or 0)
        total.time      = (total.time      or 0) + duration
        for lvl = 1, 9 do
            local src = s.byLevel[lvl] or {}
            local dst = total.byLevel[lvl] or { attempts = 0, success = 0, fail = 0, spent = 0 }
            dst.attempts = (dst.attempts or 0) + (src.attempts or 0)
            dst.success  = (dst.success  or 0) + (src.success  or 0)
            dst.fail     = (dst.fail     or 0) + (src.fail     or 0)
            dst.spent    = (dst.spent    or 0) + (src.spent    or 0)
            total.byLevel[lvl] = dst
        end

        store.total = total

        Improve_SaveStatsStore()
    end

    Improve_LogAdd("INFO", string.format(
        "Окончание сессии #%d (%s). Попыток: %d, успешных: %d, неудачных: %d, смазки потрачено: %d, денег потрачено: $%d, длительность: %d сек.",
        s.sessionId or 0,
        s.lastReason,
        s.attempts or 0,
        s.success  or 0,
        s.fail     or 0,
        s.oilsUsed or 0,
        s.spent    or 0,
        duration
    ))
end

function Improve_Stop(reason)
    -- сначала аккуратно закрываем сессию
    Improve_SessionStop(reason or "остановлено вручную")

    -- потом чистим флаги автомата
    improve.isOn          = false
    improve.step          = 0
    improve.needCheckOils = false
    improve.waitOils      = false
    improve.waitStart     = false
    improve.waitStartAt   = 0
    improve.waitResultAt  = 0
    improve.lastUseAt     = 0
    improve.consumedThisTry = false
    improve.currentIndex  = 0
    improve.useTextId     = 0
    improve.useClickId    = 0
    improve.cef.stubNotified = false
    improve.cef.needInventoryRefresh = true
    improve.cef.waitInventory = false
    improve.cef.probing = false
    improve.cef.probed = false
    improve.cef.pendingSlot = nil
    improve.cef.pendingIndex = 0
    improve.cef.probeAbort = false
    improve.cef.probeAbortReason = ''
    improve.cef.probeProgress = 0
    improve.cef.probeTotal = 0
end

function Improve_AttemptStart()
    local s = improve.stats
    if not (s and s.active) then return end

    s.attempts = (s.attempts or 0) + 1

    local idx            = improve.currentIndex or 0
    local card           = improve.videoCards[idx]
    local level          = card and card.level or 0
    local storageUpgrade = card and card.storageUpgrade or false
    local fromLevel      = tonumber(level or 0) or 0
    local toLevel        = fromLevel + 1
    local price          = 0

    s.lastAttempt = {
        isStorage = improve.useStorageUpgrade == true,
        fromLevel = fromLevel,
        toLevel = toLevel,
    }

    if not improve.useStorageUpgrade and fromLevel >= 1 and fromLevel <= 9 then
        Improve_EnsureLevelStats(s)
        price = Improve_GetPriceByFromLevel(fromLevel)
        s.spent = (s.spent or 0) + price
        local row = s.byLevel[fromLevel] or { attempts = 0, success = 0, fail = 0, spent = 0 }
        row.attempts = (row.attempts or 0) + 1
        row.spent = (row.spent or 0) + price
        s.byLevel[fromLevel] = row
        s.lastAttempt.spent = price
    end

    Improve_LogAdd("INFO", string.format(
        "Попытка #%d: карта #%d, уровень %d, улучшение хранилища: %s, стоимость: $%d.",
        s.attempts, idx, level, storageUpgrade and "есть" or "нет", price
    ))
end

-- ===== БАЗОВАЯ ЛОГИКА =====

function Improve_GetOilCountByType()
    local isAZ = (settings.improve.typeCards == 2)
    local count = isAZ and (improve.oils.arizona or 0) or (improve.oils.classic or 0)
    local name  = isAZ and "Смазка для разгона Arizona Video Card" or "Смазка для разгона видеокарты"
    return count, name
end

function Improve_HasRequiredOils(n)
    -- Для улучшения хранилища смазка не требуется
    if improve.useStorageUpgrade then
        return true
    end

    -- Если выключена галка "проверять смазки перед стартом",
    -- НЕ блокируем заточку по локальному счётчику смазок
    if not settings.improve.checkOilsOnStart then
        return true
    end

    local count = (settings.improve.typeCards == 2)
        and (improve.oils.arizona or 0)
        or  (improve.oils.classic or 0)

    return count >= (n or 2)
end

function Improve_ConsumeOils(n)
    n = n or 2
    if settings.improve.typeCards == 2 then
        improve.oils.arizona = math.maxEx(0, (improve.oils.arizona or 0) - n)
    else
        improve.oils.classic = math.maxEx(0, (improve.oils.classic or 0) - n)
    end

    if improve.stats and improve.stats.active then
        improve.stats.oilsUsed = (improve.stats.oilsUsed or 0) + n
    end

    Improve_LogAdd("INFO", string.format(
        "Списано %d смазки. Остаток: Arizona=%d, Обычная=%d.",
        n, improve.oils.arizona or 0, improve.oils.classic or 0
    ))
end

function Improve_ResetOilCounters()
    improve.oils.arizona, improve.oils.classic = 0, 0
end

function Improve_ParseInventoryDialogPage(text)
    for line in (text or ''):gmatch("[^\r\n]+") do
        local indexSlot, name, count = line:match("%[([^%]]+)%]%s(.-)%s%{.-}%[([^%]]+)%sшт%]")
        local slotNum = tonumber(indexSlot)
        count = tonumber(count)
        if indexSlot and name and count then
            if name == "Смазка для разгона Arizona Video Card" then
                improve.oils.arizona = improve.oils.arizona + count
            elseif name == "Смазка для разгона видеокарты" then
                improve.oils.classic = improve.oils.classic + count
            end

            if slotNum and count > 0 then
                local cardType, cardStorage = Improve_ParseCardMetaFromName(name)
                if cardType ~= nil then
                    Improve_AddCefCardSlot(slotNum, name, cardStorage, cardType)
                end
            end
        end
    end
end

-- Запуск обновления
function Improve_RefreshOils(async)
    if improve.oils.busy then return end
    Improve_ResetOilCounters()
    Improve_ResetCefInventory()
    improve.oils.busy = true
    Improve_LogAdd("INFO", "Запрос /stats для обновления инвентаря смазок и видеокарт.")
    sampSendChat('/stats')

    local function logResult()
        Improve_LogAdd("INFO", string.format(
            "Инвентарь обновлён: Arizona=%d, Обычная=%d, видеокарты=%d.",
            improve.oils.arizona or 0,
            improve.oils.classic or 0,
            #(improve.cef.cards or {})
        ))

        -- После ручного обновления сразу показываем найденные слоты видеокарт в UI.
        if Improve_IsNewStyleMode() then
            Improve_SyncVideoCardsFromCef()
            improve.cef.probed = false
        end
    end

    if async then
        lua_thread.create(function()
            while improve.oils.busy do wait(10) end
            logResult()
        end)
    else
        while improve.oils.busy do wait(10) end
        logResult()
        return true
    end
end

-- Пометить, что нужно перечитать видеокарты на текущей странице
function Improve_MarkNeedScan()
    if not improve.inv then return end
    improve.inv.needScan = true
    improve.currentIndex = 0
end

-- Поиск доступных видеокарт на экране (однократный скан)
function Improve_ScanVideoCards()
    local cards = {}
    local page  = improve.inv and improve.inv.activePage or 1

    -- сканируем все текстдроу и собираем только рамки видеокарт
    for i = 0, 4096 do
        if TD_IsExists(i) then
            local pass = false

            -- Фильтр рамки TD по типу карт
            if ISMONETLOADER then
                local bg = TD_GetBackgroundColor(i)
                local wantBG = (settings.improve.typeCards == 2) and -16718603 or -13421773
                pass = (tostring(bg) == tostring(wantBG))
            else
                local _, outline = sampTextdrawGetOutlineColor(i)
                local wantOutline = (settings.improve.typeCards == 1) and 4281545523 or 4294304768
                pass = (tostring(outline) == tostring(wantOutline))
            end

            if pass then
                -- Рамка видеокарты
                if TD_GetString(i) == 'LD_SPAC:white' and TD_GetModelInfo(i) == 962 then
                    local s1 = TD_GetString(i + 1)
                    if s1 and TD_GetModelInfo(i + 1) == 0 then
                        local lvlStr = s1:match("(%-?%d+)%s*[lL][vV][lL]")

                        local lvl = tonumber(lvlStr or "") or 0

                        table.insert(cards, {
                            td             = i,
                            level          = lvl,
                            storageUpgrade = false,
                        })
                    end
                end
            end
        end
    end

    -- Сортировка для режима "Последовательное" (низкие уровни вперёд)
    if settings.improve.mode == 1 and settings.improve.menuAll then
        table.sort(cards, function(a, b)
            return (a.level or 0) < (b.level or 0)
        end)
    end

    cards = Improve_MoveMaxLevelCardsToEnd(cards)
    improve.videoCards = cards

    if #cards == 0 then
        Improve_LogAdd("WARN", string.format(
            "Сканирование страницы инвентаря #%d: видеокарты не найдены.",
            page
        ))
    else
        Improve_LogAdd("INFO", string.format(
            "Сканирование страницы инвентаря #%d: найдено карт: %d.",
            page, #cards
        ))
    end
end

function Improve_TryClick(td_id)
    lua_thread.create(function() wait(settings.deley.improve_waitTryClick or 500) sampSendClickTextdraw(td_id) end)
end

-- Нажать кнопку USE
function Improve_ClickUse()
    if improve.useClickId == 0 or improve.useTextId == 0 then return end

    lua_thread.create(function ()
        local tries    = 0
        local maxTries = 5
        local delayMs  = 300

        while improve.isOn and improve.step == 3 and tries < maxTries do
            tries = tries + 1

            sampSendClickTextdraw(improve.useClickId)
            improve.lastUseAt = os.clock()
            wait(delayMs)

            -- Проверяем, все ли еще висит "USE"/"Использовать"
            local curText = TD_GetString(improve.useTextId)
            local stillUSE = curText and (curText == 'USE' or Translationtextdraw(curText) == 'ИСПОЛЬЗОВАТЬ')

            -- Если кнопка пропала/изменилась - выходим
            if not stillUSE then
                break
            end
        end
    end)
end

-- Результат заточки (успех/ошибка) - обновляем уровень в кэше
function Improve_OnResult(success, serverMsg)
    if not improve.currentIndex or improve.currentIndex <= 0 then return end

    local card = improve.videoCards[improve.currentIndex]
    if not card then return end

    if improve.useStorageUpgrade then

        if success then
            card.storageUpgrade = success
        end

        local s = improve.stats
        if s and s.active then
            if success then
                s.success = (s.success or 0) + 1
            else
                s.fail    = (s.fail or 0) + 1
            end
        end

        local attemptNo = s and s.attempts or 0
        if success then
            Improve_LogAdd("SUCCESS", string.format(
                "Попытка #%d: УСПЕХ. Карта #%d, улучшенное хранилище.",
                attemptNo, improve.currentIndex or 0
            ))
        else
            Improve_LogAdd("WARN", string.format(
                "Попытка #%d: ОШИБКА. Карта #%d, улучшенное хранилище (без изменений).",
                attemptNo, improve.currentIndex or 0
            ))
        end
    else
        local oldLvl = card.level or 0
        local newLvl = oldLvl

        if success then
            -- Пытаемся вытащить фактический уровень из сообщения:
            local parsedLvl

            if serverMsg then
                local lvlText = serverMsg:match("до%s+(%d+)%s+уровн")
                if lvlText then
                    parsedLvl = tonumber(lvlText)
                end
            end

            newLvl = parsedLvl or (oldLvl + 1)
            if newLvl > 10 then newLvl = 10 end
            card.level = newLvl
        end

        local s = improve.stats
        if s and s.active then
            if success then
                s.success = (s.success or 0) + 1
            else
                s.fail    = (s.fail or 0) + 1
            end

            local fromLevel = s.lastAttempt and tonumber(s.lastAttempt.fromLevel or 0) or 0
            if fromLevel >= 1 and fromLevel <= 9 then
                Improve_EnsureLevelStats(s)
                local row = s.byLevel[fromLevel] or { attempts = 0, success = 0, fail = 0, spent = 0 }
                if success then
                    row.success = (row.success or 0) + 1
                else
                    row.fail = (row.fail or 0) + 1
                end
                s.byLevel[fromLevel] = row
            end
            s.lastAttempt = nil
        end

        local attemptNo = s and s.attempts or 0
        if success then
            Improve_LogAdd("SUCCESS", string.format(
                "Попытка #%d: УСПЕХ. Карта #%d, уровень %d -> %d.",
                attemptNo, improve.currentIndex or 0, oldLvl, newLvl
            ))
        else
            Improve_LogAdd("WARN", string.format(
                "Попытка #%d: ОШИБКА. Карта #%d, уровень %d (без изменений).",
                attemptNo, improve.currentIndex or 0, oldLvl
            ))
        end

        -- Для режима "Последовательное" пересортируем по уровню
        if settings.improve.menuAll and settings.improve.mode == 1 then
            table.sort(improve.videoCards, function(a, b)
                return (a.level or 0) < (b.level or 0)
            end)
        end
        improve.videoCards = Improve_MoveMaxLevelCardsToEnd(improve.videoCards)
    end
end

local function Improve_MarkAttemptTimedOut()
    local s = improve.stats
    if not (s and s.active) then return end

    s.fail = (s.fail or 0) + 1

    local fromLevel = s.lastAttempt and tonumber(s.lastAttempt.fromLevel or 0) or 0
    if fromLevel >= 1 and fromLevel <= 9 then
        Improve_EnsureLevelStats(s)
        local row = s.byLevel[fromLevel] or { attempts = 0, success = 0, fail = 0, spent = 0 }
        row.fail = (row.fail or 0) + 1
        s.byLevel[fromLevel] = row
    end

    s.lastAttempt = nil
end

local function Improve_TickWaitWatchdogs()
    if not improve.isOn then return end

    local now = os.clock()

    if improve.step == 3 then
        local retryMs = tonumber(settings.deley.improve_retryUseDelay or 1200) or 1200
        if retryMs < 200 then retryMs = 200 end

        if not improve.waitStart then
            if (improve.lastUseAt or 0) <= 0 then
                improve.lastUseAt = now
            elseif (now - improve.lastUseAt) * 1000 >= retryMs then
                if Improve_IsNewStyleMode() then
                    local idx = tonumber(improve.currentIndex or 0) or 0
                    local card = improve.videoCards[idx]
                    local slot = card and tonumber(card.slot or 0) or 0
                    if slot > 0 then
                        Improve_SendCefClickOnSlot(slot, 1, 1)
                        improve.lastUseAt = now
                    else
                        improve.step = 1
                        improve.consumedThisTry = false
                        improve.lastUseAt = 0
                    end
                else
                    Improve_ClickUse()
                end
            end
        else
            local waitStartTimeout = tonumber(settings.deley.improve_waitStartTimeout or 8) or 8
            if waitStartTimeout < 1 then waitStartTimeout = 1 end
            local startedAt = tonumber(improve.waitStartAt or 0) or 0
            if startedAt > 0 and (now - startedAt) >= waitStartTimeout then
                Improve_LogAdd("WARN", string.format(
                    "Таймаут ожидания старта улучшения (%d сек). Возвращаюсь к выбору карты.",
                    waitStartTimeout
                ))
                improve.waitStart = false
                improve.waitStartAt = 0
                improve.step = 1
                improve.consumedThisTry = false
            end
        end
    elseif improve.step == 4 then
        local waitResultTimeout = tonumber(settings.deley.improve_waitResultTimeout or 20) or 20
        if waitResultTimeout < 1 then waitResultTimeout = 1 end
        local startedAt = tonumber(improve.waitResultAt or 0) or 0
        if startedAt > 0 and (now - startedAt) >= waitResultTimeout then
            Improve_LogAdd("WARN", string.format(
                "Таймаут ожидания результата улучшения (%d сек). Фиксирую попытку как неудачную и продолжаю.",
                waitResultTimeout
            ))
            Improve_MarkAttemptTimedOut()
            improve.waitResultAt = 0
            improve.step = 1
            improve.consumedThisTry = false
        end
    end
end

-- Шаговая машина состояний
function Improve_Tick()
    if not improve.isOn then return end

    Improve_TickWaitWatchdogs()
    if improve.waitOils then return end -- Ждем смазки

    if Improve_IsNewStyleMode() then
        Improve_TickNewStyle()
        return
    end

    if improve.step == 1 then
        local targetLevel = settings.improve.maxLevel or 2

        if not Improve_HasRequiredOils(2) and not improve.useStorageUpgrade then
            MI_Say("Смазка закончилась. Отключаюсь.")
            Improve_LogAdd("WARN", "Смазка закончилась. Сессия заточки будет остановлена.")
            Improve_Stop("Закончилась смазка в процессе")
            return
        end
        improve.consumedThisTry = false

        -- если в кэше нет карт, смысла продолжать нет
        if #improve.videoCards == 0 then
            MI_Say("На текущей странице инвентаря видеокарт не найдено.")
            Improve_LogAdd("WARN", "На текущей странице инвентаря видеокарт не найдено. Сессия остановлена.")
            Improve_Stop("Нет видеокарт на странице")
            return
        end

        if settings.improve.menuAll then
            -- Работаем по всем картам
            local candidate, idxCandidate
            for idx, v in ipairs(improve.videoCards) do
                if improve.useStorageUpgrade then
                    if not v.storageUpgrade then
                        candidate    = v
                        idxCandidate = idx
                        break
                    end
                else
                    if v.level < targetLevel then
                        candidate    = v
                        idxCandidate = idx
                        break
                    end
                end
            end

            if candidate then
                improve.currentIndex = idxCandidate
                if improve.useStorageUpgrade then
                    Improve_LogAdd("INFO", string.format(
                        "Выбрана карта #%d для улучшения хранилища.",
                        idxCandidate
                    ))
                else
                    Improve_LogAdd("INFO", string.format(
                        "Выбрана карта #%d для заточки (уровень %d, целевой уровень %d).",
                        idxCandidate, candidate.level or 0, targetLevel
                    ))
                end
                Improve_TryClick(candidate.td)
                improve.step = 2
            else
                local page = improve.inv and improve.inv.activePage or 1
                MI_Say("Подходящих видеокарт не найдено. Отключаюсь.")
                if improve.useStorageUpgrade then
                    Improve_LogAdd("INFO", string.format(
                        "Подходящих видеокарт для улучшения хранилища на странице #%d не найдено.",
                        page
                    ))
                    Improve_Stop("Все видеокарты уже расширены по хранилищу")
                else
                    Improve_LogAdd("INFO", string.format(
                        "Подходящих видеокарт для улучшения до уровня %d на странице #%d не найдено.",
                        targetLevel, page
                    ))
                    Improve_Stop("Все видеокарты уже достигли целевого уровня")
                end
            end
        else
            -- Режим одной выбранной карты
            if improve.select == 0 then
                MI_Say("Выбери видеокарту внизу списка.")
                Improve_LogAdd("WARN", "Не выбрана видеокарта для заточки в режиме одиночной карты.")
                Improve_Stop("Не выбрана видеокарта")
                return
            end

            local v = improve.videoCards[improve.select]
            if not v then return end
            if (improve.useStorageUpgrade and not v.storageUpgrade) or ((not improve.useStorageUpgrade) and v.level < targetLevel) then
                if improve.useStorageUpgrade then
                    Improve_LogAdd("INFO", string.format(
                        "Выбрана видеокарта #%d для улучшения хранилища.",
                        improve.select
                    ))
                else
                    Improve_LogAdd("INFO", string.format(
                        "Выбрана видеокарта #%d для заточки (уровень %d -> целевой %d).",
                        improve.select, v.level or 0, targetLevel
                    ))
                end
                improve.currentIndex = improve.select
                Improve_TryClick(v.td)
                improve.step = 2
            else
                if improve.useStorageUpgrade then
                    MI_Say("Выбранная видеокарта уже имеет улучшение хранилища.")
                    Improve_LogAdd("INFO", string.format(
                        "Выбранная видеокарта уже имеет улучшение хранилища. Сессия остановлена."
                    ))
                    Improve_Stop("Выбранная видеокарта уже имеет улучшение хранилища.")
                else
                    MI_Say("Выбранная видеокарта уже достигла целевого уровня.")
                    Improve_LogAdd("INFO", string.format(
                        "Выбранная видеокарта уже достигла целевого уровня (%d). Сессия остановлена.",
                        targetLevel
                    ))
                    Improve_Stop("Выбранная видеокарта уже достигла целевого уровня")
                end
            end
        end
    end
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

if ISMONETLOADER and settings.style.scaleUI ~= 1.0 then
    MONET_DPI_SCALE = settings.style.scaleUI
elseif ISMONETLOADER then
    settings.style.scaleUI = MONET_DPI_SCALE
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

function LoadCollectLogStore()
    local data = LoadJSON(COLLECT_STATS_FILE)
    if type(data) ~= "table" then
        data = {}
    end
    data.days = data.days or {}
    data.meta = data.meta or {}
    if type(data.meta.lastCollect) ~= "table" then
        data.meta.lastCollect = nil
    end
    collectLogStore = data
end

function SaveCollectLogStore()
    collectLogStore.days = collectLogStore.days or {}
    collectLogStore.meta = collectLogStore.meta or {}
    return SaveJSON(COLLECT_STATS_FILE, collectLogStore)
end

local function Collect_NormalizeCryptoAmount(amount)
    amount = tonumber(amount) or 0
    return math.floor(amount * 1000 + 0.5) / 1000
end

function Collect_GetLastCollectInfo()
    local meta = collectLogStore.meta or {}
    local info = meta.lastCollect
    if type(info) ~= "table" then return nil end

    local timestamp = tonumber(info.timestamp or 0) or 0
    if timestamp <= 0 then return nil end

    info.timestamp = timestamp
    info.amount = Collect_NormalizeCryptoAmount(info.amount)
    info.houseId = tostring(info.houseId or "0")
    info.currency = tostring(info.currency or "BTC")
    return info
end

function Collect_UpdateLastCollectInfo(houseId, currency, amount)
    collectLogStore.meta = collectLogStore.meta or {}
    collectLogStore.meta.lastCollect = {
        timestamp = os.time(),
        houseId = tostring(houseId or 0),
        currency = tostring(currency or "BTC"),
        amount = Collect_NormalizeCryptoAmount(amount),
    }
    collectReminder.lastNotifiedCollectAt = 0
    collectReminder.retryAfterAt = 0
end

function Collect_GetReminderThresholdSeconds()
    local minutes = tonumber(settings.main and settings.main.collectNotifyMinutes or 0) or 0
    if minutes <= 0 then
        return 0
    end
    return math.floor(minutes * 60)
end

function Collect_FormatDuration(seconds)
    seconds = math.max(0, math.floor(tonumber(seconds) or 0))
    local days = math.floor(seconds / 86400)
    seconds = seconds % 86400
    local hours = math.floor(seconds / 3600)
    seconds = seconds % 3600
    local minutes = math.floor(seconds / 60)
    local secs = seconds % 60

    if days > 0 then
        return string.format("%d д. %02d:%02d:%02d", days, hours, minutes, secs)
    end
    if hours > 0 then
        return string.format("%02d:%02d:%02d", hours, minutes, secs)
    end
    return string.format("%02d:%02d", minutes, secs)
end

function Collect_FormatLastCollectText(info)
    if type(info) ~= "table" then
        return "ещё не зафиксирован"
    end

    local timestamp = tonumber(info.timestamp or 0) or 0
    if timestamp <= 0 then
        return "ещё не зафиксирован"
    end

    return os.date('%d.%m.%Y %H:%M:%S', timestamp)
end

function Collect_GetNotifySystemState()
    local state = {
        available = false,
        ready = false,
        installed = false,
        running = false,
        compatible = false,
        canInstall = false,
        message = "Система уведомлений недоступна.",
    }

    if not notifySuccess or type(notify) ~= 'table' then
        state.message = "Библиотека session_notifications не установлена."
        return state
    end

    state.available = true
    state.canInstall = type(notify.ensure_manager) == 'function'

    if type(notify.status) == 'function' then
        local ok, status = pcall(notify.status, REQUIRED_NOTIFY_VERSION)
        if ok and type(status) == 'table' then
            state.installed = not not status.installed
            state.running = not not status.running
            state.compatible = not not status.compatible
            state.ready = state.installed and state.running and state.compatible and type(notify.send) == 'function'

            if not state.installed then
                state.message = "Система уведомлений не установлена."
            elseif not state.running then
                state.message = "Менеджер уведомлений найден, но не запущен."
            elseif not state.compatible then
                state.message = "Менеджер уведомлений требует обновления."
            else
                state.message = "Система уведомлений готова."
            end

            return state
        end
    end

    state.ready = type(notify.send) == 'function'
    state.installed = state.ready
    state.running = state.ready
    state.compatible = state.ready
    state.message = state.ready and "Система уведомлений готова." or "Система уведомлений недоступна."
    return state
end

function Collect_GetNotifyInstallButtonText(state)
    if type(state) ~= 'table' then
        return "Открыть страницу установки"
    end
    if not state.available then
        return "Открыть страницу установки"
    end
    if not state.installed then
        return "Установить менеджер уведомлений"
    end
    if not state.running then
        return "Запустить менеджер уведомлений"
    end
    if not state.compatible then
        return "Обновить менеджер уведомлений"
    end
    return "Подготовить менеджер уведомлений"
end

function Collect_DownloadNotificationSystem()
    if collectReminder.managerDownloadPending or collectReminder.managerEnsurePending then
        return false
    end

    collectReminder.managerDownloadPending = true
    collectReminder.managerStatusMessage = "Скачиваю менеджер уведомлений и библиотеку..."

    lua_thread.create(function()
        local function fail(message, debugInfo)
            collectReminder.managerDownloadPending = false
            collectReminder.managerStatusMessage = message
            AddChatMessage(message, TYPECHATMESSAGES.WARNING)
            if debugInfo and debugInfo ~= "" then
                AddChatMessage('Уведомления: ' .. tostring(debugInfo), TYPECHATMESSAGES.DEBUG)
            end
        end

        local okRequests, requests = pcall(require, 'requests')
        if not okRequests or type(requests) ~= 'table' or type(requests.get) ~= 'function' then
            fail("Не удалось скачать систему уведомлений.", okRequests and 'requests.get недоступен' or requests)
            return
        end

        local function download_text(url)
            local ok, response = pcall(function()
                return requests.get(url, {
                    headers = {
                        ['Accept-Encoding'] = 'identity',
                        ['Connection'] = 'close'
                    },
                    timeout = 20
                })
            end)

            if not ok or type(response) ~= 'table' then
                return nil, tostring(response or 'ошибка requests')
            end
            if not tonumber(response.status_code) or response.status_code < 200 or response.status_code >= 300 then
                return nil, 'HTTP ' .. tostring(response.status_code or 'unknown')
            end
            return tostring(response.text or ''), nil
        end

        local managerText, managerErr = download_text(NOTIFY_MANAGER_RAW_URL)
        if not managerText or managerText == '' then
            fail("Не удалось скачать менеджер уведомлений.", managerErr)
            return
        end

        local libraryText, libraryErr = download_text(NOTIFY_LIBRARY_RAW_URL)
        if not libraryText or libraryText == '' then
            fail("Не удалось скачать библиотеку уведомлений.", libraryErr)
            return
        end

        local managerPath = getWorkingDirectory() .. SEPORATORPATCH .. 'NotificationManager.lua'
        local libraryPath = getWorkingDirectory() .. SEPORATORPATCH .. 'lib' .. SEPORATORPATCH .. 'session_notifications.lua'

        local okSaveManager, saveManagerErr = pcall(function()
            local file = assert(io.open(managerPath, 'w'))
            file:write(managerText)
            file:close()
        end)
        if not okSaveManager then
            fail("Не удалось сохранить менеджер уведомлений.", saveManagerErr)
            return
        end

        local okSaveLibrary, saveLibraryErr = pcall(function()
            EnsureDirectoryExists(getWorkingDirectory() .. SEPORATORPATCH .. 'lib')
            local file = assert(io.open(libraryPath, 'w'))
            file:write(libraryText)
            file:close()
        end)
        if not okSaveLibrary then
            fail("Не удалось сохранить библиотеку уведомлений.", saveLibraryErr)
            return
        end

        collectReminder.managerDownloadPending = false
        collectReminder.managerStatusMessage = "Система уведомлений скачана. Перезагружаю скрипт..."
        AddChatMessage("Менеджер уведомлений и библиотека скачаны. Перезагружаю скрипт", TYPECHATMESSAGES.SUCCESS)

        wait(300)
        thisScript():reload()
    end)

    return true
end

function Collect_EnsureNotificationManager()
    if collectReminder.managerEnsurePending or collectReminder.managerDownloadPending then
        return false
    end

    local state = Collect_GetNotifySystemState()
    if not state.available or type(notify) ~= 'table' or type(notify.ensure_manager) ~= 'function' then
        collectReminder.managerStatusMessage = "Открыта страница установки менеджера уведомлений."
        OpenUrl(NOTIFY_MANAGER_REPO_URL)
        AddChatMessage("Открыта страница установки менеджера уведомлений", TYPECHATMESSAGES.SECONDARY)
        return true
    end

    collectReminder.managerEnsurePending = true
    collectReminder.managerStatusMessage = "Подготавливаю менеджер уведомлений..."

    notify.ensure_manager({ required_version = REQUIRED_NOTIFY_VERSION }, function(success, info)
        collectReminder.managerEnsurePending = false
        if success then
            collectReminder.managerStatusMessage = "Менеджер уведомлений готов к работе."
            AddChatMessage("Менеджер уведомлений готов к работе", TYPECHATMESSAGES.SUCCESS)
            return
        end

        collectReminder.managerStatusMessage = "Не удалось подготовить менеджер уведомлений. Перезапустите игру или перезагрузите все скрипты."
        AddChatMessage("Не удалось подготовить менеджер уведомлений. Перезапустите игру или перезагрузите все скрипты.", TYPECHATMESSAGES.WARNING)
        AddChatMessage(
            'Менеджер уведомлений: ' .. tostring(info and info.message or 'неизвестная ошибка'),
            TYPECHATMESSAGES.DEBUG
        )
    end)

    return true
end

function Collect_SendReminderNotification(info, elapsedSeconds)
    if not (notifySuccess and type(notify) == 'table' and type(notify.send) == 'function') then
        collectReminder.retryAfterAt = os.time() + 300
        AddChatMessage("Напоминание о сборе: система session_notifications недоступна", TYPECHATMESSAGES.DEBUG)
        return false
    end

    collectReminder.notifyPending = true
    local lastCollectAt = tonumber(info.timestamp or 0) or 0
    local lastCollectText = Collect_FormatLastCollectText(info)
    local overdueText = Collect_FormatDuration(elapsedSeconds)

    notify.send(REQUIRED_NOTIFY_VERSION, {
        script_id = 'MMT',
        title = u8("Давно не было сбора крипты"),
        text = u8("С последнего сбора прошло " .. overdueText .. "."),
        description = u8("Последний сбор: " .. lastCollectText),
        sticky = true,
        theme = 'emerald',
        action = collectReminderAction
    }, function(success, notifyInfo)
        collectReminder.notifyPending = false
        if success then
            collectReminder.lastNotifiedCollectAt = lastCollectAt
            collectReminder.retryAfterAt = 0
            return
        end

        collectReminder.retryAfterAt = os.time() + 60
        AddChatMessage(
            'Напоминание о сборе не отправлено: ' .. tostring(notifyInfo and notifyInfo.message or 'неизвестная ошибка'),
            TYPECHATMESSAGES.DEBUG
        )
    end)

    return true
end

function Collect_ReminderTick()
    local nowClock = os.clock()
    if (nowClock - (collectReminder.lastTickAt or 0)) < 1 then
        return
    end
    collectReminder.lastTickAt = nowClock

    if collectReminder.notifyPending then
        return
    end

    local nowTime = os.time()
    if nowTime < (collectReminder.retryAfterAt or 0) then
        return
    end

    local thresholdSeconds = Collect_GetReminderThresholdSeconds()
    if thresholdSeconds <= 0 then
        return
    end

    if flashCollect.active or (stateCrypto.work and processes.take) then
        return
    end

    local info = Collect_GetLastCollectInfo()
    if not info then
        return
    end

    if collectReminder.lastNotifiedCollectAt == info.timestamp then
        return
    end

    local elapsedSeconds = nowTime - info.timestamp
    if elapsedSeconds < thresholdSeconds then
        return
    end

    Collect_SendReminderNotification(info, elapsedSeconds)
end

function AddCollectLogEntry(houseId, currency, amount)
    houseId = tostring(houseId or 0)
    currency = tostring(currency or "BTC")
    amount = Collect_NormalizeCryptoAmount(amount)
    if amount <= 0 then return end

    local dateKey = os.date('%Y-%m-%d')
    local timeKey = os.date('%H:%M:%S')

    collectLogStore.days[dateKey] = collectLogStore.days[dateKey] or {
        total = { BTC = 0, ASC = 0 },
        houses = {}
    }

    local dayData = collectLogStore.days[dateKey]
    dayData.total[currency] = (dayData.total[currency] or 0) + amount
    dayData.houses[houseId] = dayData.houses[houseId] or {
        total = { BTC = 0, ASC = 0 },
        items = {}
    }

    local houseData = dayData.houses[houseId]
    houseData.total[currency] = (houseData.total[currency] or 0) + amount
    table.insert(houseData.items, {
        time = timeKey,
        currency = currency,
        amount = amount,
    })

    Collect_UpdateLastCollectInfo(houseId, currency, amount)
    SaveCollectLogStore()
end

LoadCollectLogStore()

-- --------------------------------------------------------
--                           Parsers
-- --------------------------------------------------------

function ParseHouseData(text)
    houses = {}

    local results = {}

    local function trim(value)
        local result = tostring(value or ""):gsub("^%s+", "")
        result = result:gsub("%s+$", "")
        return result
    end

    local function parseEnergyValue(valueText)
        local raw = trim(valueText)
        local numbers = {}

        for amount in raw:gmatch("%d[%d%.]*") do
            table.insert(numbers, tonumber((amount:gsub("%.", ""))) or 0)
        end

        if #numbers == 0 then
            return nil, nil
        end

        if #numbers >= 2 and numbers[1] < 1000 then
            return tostring(numbers[1] * 1000000 + numbers[2]), "$"
        end

        if raw:find("KK", 1, true) and numbers[1] < 1000 then
            return tostring(numbers[1] * 1000000), "$"
        end

        return tostring(numbers[1]), "$"
    end

    local function splitTabs(line)
        local parts = {}
        for part in tostring(line or ""):gmatch("[^\t]+") do
            table.insert(parts, trim(part))
        end
        return parts
    end

    local lineIndex = 0
    for line in text:gmatch("[^\r\n]+") do
        lineIndex = lineIndex + 1
        local cols = splitTabs(line)

        if #cols >= 4 and cols[1]:find("%[") then
            local firstCol = cols[1]
            local city = trim(cols[#cols - 2] or "")
            local tax = tonumber((tostring(cols[#cols - 1] or ""):match("(%d+)%D*$")))
            local energyCol = trim(cols[#cols] or "")
            local houseNum = firstCol:match("(%d+)%s*$")
            local cycles = tonumber((energyCol:match("(%d+)") or ""))
            local energyBlock = energyCol:match("%((.-)%)")

            if houseNum and city ~= "" and cycles and energyBlock then
                local bankNowRaw, bankMaxRaw = energyBlock:match("^(.-)%s*/%s*(.-)$")
                local bankNow, currency = parseEnergyValue(bankNowRaw or "")
                local bankMax = select(1, parseEnergyValue(bankMaxRaw or ""))

                if bankNow and bankMax and not CheckHouseInBlackList(houseNum) then
                    table.insert(results, {
                        samp_line = lineIndex - 2,
                        house_number = tonumber(houseNum),
                        city = city,
                        tax = tax or 0,
                        cycles = cycles,
                        currency = currency,
                        bankNow = bankNow,
                        bankMax = bankMax,
                        raw_line = line
                    })
                end
            end
        end
    end

    return results
end
function ParseHouseBankData(text)
    housesBanks = {}

    local results = {}

    local function trim(value)
        local result = tostring(value or ""):gsub("^%s+", "")
        result = result:gsub("%s+$", "")
        return result
    end

    local function parseBankValue(valueText)
        local raw = trim(valueText)
        local numbers = {}

        for amount in raw:gmatch("%d[%d%.]*") do
            table.insert(numbers, tonumber((amount:gsub("%.", ""))) or 0)
        end

        if #numbers == 0 then
            return nil
        end

        if #numbers >= 2 and numbers[1] < 1000 then
            return tostring(numbers[1] * 1000000 + numbers[2])
        end

        if raw:find("KK", 1, true) and numbers[1] < 1000 then
            return tostring(numbers[1] * 1000000)
        end

        return tostring(numbers[1])
    end

    local function splitTabs(line)
        local parts = {}
        for part in tostring(line or ""):gmatch("[^\t]+") do
            table.insert(parts, trim(part))
        end
        return parts
    end

    local lineIndex = 0
    for line in text:gmatch("[^\r\n]+") do
        lineIndex = lineIndex + 1
        local cols = splitTabs(line)

        if #cols >= 3 and cols[1]:find("%[") then
            local firstCol = cols[1]
            local city = trim(cols[#cols - 1] or "")
            local bankNow = parseBankValue(cols[#cols] or "")
            local houseNum = firstCol:match("(%d+)%s*$")

            if houseNum and city ~= "" and bankNow and not CheckHouseInBlackList(houseNum) then
                table.insert(results, {
                    samp_line = lineIndex - 2,
                    house_number = tonumber(houseNum),
                    city = city,
                    bankNow = bankNow,
                    raw_line = line
                })
            end
        end
    end

    return results
end
function ParseShelfData(text)
    shelves = {}
    housesData[stateCrypto.activeHouseID] = { work_vc = 0, max_collect = 0, min_liquid = 0}
    local house_data = housesData[tostring(stateCrypto.activeHouseID)]

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
            local p1 = tonumber(profit1) or 0
            local p2 = tonumber(profit2) or 0
            local maxProfit = math.max(p1, p2)

            table.insert(results, {
                shelf_number = tonumber(shelfNum),
                samp_line = lineIndex - 2,
                status = status:gsub("^%s+", ""):gsub("%s+$", ""),
                color_code = colorCode,
                profit = maxProfit,
                profit_primary = p1,
                currency = (p1 >= p2) and currency1 or currency2,
                profit2 = p2,
                currency2 = currency2,
                level = tonumber(level),
                percentage = tonumber(percentage),
                card_type = "ASIC",
                raw_line = line
            })
            found = true

            -- Заполнение данными о доме
            house_data = {
                work_vc = house_data.work_vc + ((status:find("Работает") and 1) or 0),
                max_collect = maxProfit > house_data.max_collect and maxProfit or house_data.max_collect,
                min_liquid = house_data.min_liquid == 0 and tonumber(percentage) or (tonumber(percentage) < house_data.min_liquid and tonumber(percentage) or house_data.min_liquid),
            }
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
                    profit_primary = tonumber(profit),
                    currency = currency,
                    level = tonumber(level),
                    percentage = tonumber(percentage),
                    card_type = (currency == "ASC") and "ASC" or "BTC",
                    raw_line = line
                })

                -- Заполнение данными о доме
                house_data = {
                    work_vc = house_data.work_vc + ((status:find("Работает") and 1) or 0),
                    max_collect = tonumber(profit) > house_data.max_collect and tonumber(profit) or house_data.max_collect,
                    min_liquid = house_data.min_liquid == 0 and tonumber(percentage) or (tonumber(percentage) < house_data.min_liquid and tonumber(percentage) or house_data.min_liquid),
                }
            end
        end
    end
    housesData[stateCrypto.activeHouseID] = house_data
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
                local _countInt = math.floor(tonumber(countCrypto) or 0)
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

-- Буфер для строк
local function buf_set(buf, str)
    str = tostring(str or "")
    local n = math.minEx(#str, ffi.sizeof(buf) - 1)
    ffi.copy(buf, str, n)
    buf[n] = 0
end

-- Формат «10,000,000»
local function format_commas(n)
    n = math.floor(tonumber(n) or 0)
    local s = tostring(math.abs(n))
    s = s:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
    if n < 0 then s = '-' .. s end
    return s
end

local function digits_to_int(s)
    if not s or s == "" then return 0 end
    local neg = s:match("^%-") ~= nil
    local digits = s:gsub("%D", "")
    local n = tonumber(digits) or 0
    return neg and -n or n
end

local function clamp_bank_target(v)
    return math.maxEx(10000, math.minEx(59999999 - 10000, v))
end

function imgui.GetMiddleButtonX(count)
    local width = imgui.GetWindowContentRegionWidth()
    local space = imgui.GetStyle().ItemSpacing.x
    return (count == 1) and width or (width / count - ((space * (count - 1)) / count))
end

-- =====================================================================================================================
--                                                          UTLITES
-- =====================================================================================================================

-- Получить текущее время в формате %H:%M:%S
function GetTimeNow()
    return os.date('%H:%M:%S')
end

function OpenUrl(url)
    if MONET_VERSION then
        local gta = ffi.load('GTASA')
        ffi.cdef[[
            void _Z12AND_OpenLinkPKc(const char* link);
        ]]
    	gta._Z12AND_OpenLinkPKc(url)
	else
		os.execute("explorer " .. url)
	end
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

-- Округление до n знаков (по умолчанию 2)
function Round(x, n)
    n = n or 2
    local m = 10^n
    return math.floor((x or 0) * m + 0.5) / m
end

function ImGuiKeyPressed(keyConst)
    local ok, pressed = pcall(function() return imgui.IsKeyPressed(keyConst, false) end)
    return ok and pressed
end

function IsEnterPressed()
    -- пробуем ImGui Enter
    if ImGuiKeyPressed(imgui.Key.Enter) then return true end
    -- системная клавиша Enter
    if isKeyJustPressed then
        local ok, pressed = pcall(isKeyJustPressed, VK_RETURN)
        if ok and pressed then return true end
    end
    return false
end

-- current  - текущий индекс (1..max)
-- max      - количество элементов
-- onEnter  - при нажатии Enter на текущем элементе
function HandleListNavigation(current, max, onEnter)
    if max <= 0 or not settings.main.arrowsMove or not IsArrowNavigationAvailable() then return current end

    if imgui.IsWindowFocused(imgui.FocusedFlags.RootAndChildWindows)
       and not imgui.IsAnyItemActive() then

        local newIndex = current

        -- Вверх: ImGui или фолбэк через VK_UP
        if ImGuiKeyPressed(imgui.Key.UpArrow) or (isKeyJustPressed and isKeyJustPressed(VK_UP)) then
            newIndex = (current > 1) and (current - 1) or max
        end

        -- Вниз: ImGui или фолбэк через VK_DOWN
        if ImGuiKeyPressed(imgui.Key.DownArrow) or (isKeyJustPressed and isKeyJustPressed(VK_DOWN)) then
            newIndex = (current < max) and (current + 1) or 1
        end

        current = newIndex

        -- Enter (без KeypadEnter)
        if IsEnterPressed() and onEnter then
            onEnter(current)
        end
    end

    return current
end

function math.maxEx(a, b)
    return a > b and a or b
end

function math.minEx(a, b)
    return a < b and a or b
end


function Translationtextdraw(text) -- https://pawn-wiki.ru/index.php?/topic/24249-ispolzuem-russkie-simvoli-v-teksdravah/
	text = string.gsub(text, "a", "а")  text = string.gsub(text, "A", "А")  text = string.gsub(text, "—", "б")  text = string.gsub(text, "Ђ", "Б")  text = string.gsub(text, "ў", "в")  text = string.gsub(text, "‹", "В")  text = string.gsub(text, "™", "г")  text = string.gsub(text, "‚", "Г")  text = string.gsub(text, "љ", "д")  text = string.gsub(text, "ѓ", "Д")  text = string.gsub(text, "e", "е")	text = string.gsub(text, "E", "Е")	text = string.gsub(text, "e", "ё")	text = string.gsub(text, "E", "Ё")	text = string.gsub(text, "›", "ж")	text = string.gsub(text, "„", "Ж")	text = string.gsub(text, "џ", "з")	text = string.gsub(text, "€", "З")	text = string.gsub(text, "њ", "и")
	text = string.gsub(text, "…", "И")	text = string.gsub(text, "ќ", "й")	text = string.gsub(text, "…", "И")	text = string.gsub(text, "k", "к")	text = string.gsub(text, "K", "К")	text = string.gsub(text, "ћ", "л")	text = string.gsub(text, "‡", "Л")	text = string.gsub(text, "Ї", "м")	text = string.gsub(text, "M", "М")	text = string.gsub(text, "®", "н")	text = string.gsub(text, "H", "Н")	text = string.gsub(text, "o", "о")	text = string.gsub(text, "O", "О")	text = string.gsub(text, "Ј", "п")	text = string.gsub(text, "Њ", "П")	text = string.gsub(text, "p", "р")
	text = string.gsub(text, "P", "Р")	text = string.gsub(text, "c", "с")	text = string.gsub(text, "C", "С")	text = string.gsub(text, "¦", "т")	text = string.gsub(text, "Џ", "Т")	text = string.gsub(text, "y", "у")	text = string.gsub(text, "Y", "У")	text = string.gsub(text, "?", "ф")	text = string.gsub(text, "Ѓ", "Ф")	text = string.gsub(text, "x", "х")	text = string.gsub(text, "X", "Х")	text = string.gsub(text, "*", "ц")	text = string.gsub(text, "‰", "Ц")	text = string.gsub(text, "¤", "ч")	text = string.gsub(text, "Ќ", "Ч")	text = string.gsub(text, "Ґ", "ш")
	text = string.gsub(text, "Ћ", "Ш")	text = string.gsub(text, "Ў", "щ")	text = string.gsub(text, "Љ", "Щ")	text = string.gsub(text, "©", "ь")	text = string.gsub(text, "’", "Ь")	text = string.gsub(text, "ђ", "ъ'")	text = string.gsub(text, "§", "Ъ")	text = string.gsub(text, "Ё", "ы")	text = string.gsub(text, "‘", "Ы")	text = string.gsub(text, "Є", "э")	text = string.gsub(text, "“", "Э")	text = string.gsub(text, "«", "ю")	text = string.gsub(text, "”", "Ю")	text = string.gsub(text, "¬", "я")	text = string.gsub(text, "•", "Я")
    return text
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

    -- если мы уже когда-то двигали окно - задаём позицию на этот кадр
    if windowPos then
        imgui.SetNextWindowPos(windowPos, imgui.Cond_Always)
    end

    imgui.SetNextWindowSize(imgui.ImVec2(settings.style.sizeWindow.x, settings.style.sizeWindow.y), imgui.Cond.Appearing)

    imgui.Begin(u8("Main Window"), imguiWindows.main, imgui.WindowFlags.NoCollapse + imgui.WindowFlags.NoTitleBar + (settings.style.swipeScroll and imgui.WindowFlags.NoMove or 0))

        imgui.MoveOnTitleBar()

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
            shelves = {}
            houses = {}
            housesBanks = {}
        end

        imgui.Separator()

        local _widthButtons = (imgui.GetWindowWidth() - ScaleUI(36)) / 4
        if imgui.ButtonClickable(activeTabScript ~= "main", u8"Основное", imgui.ImVec2(_widthButtons, 0)) then
            activeTabScript = "main"
        end
        imgui.SameLine()
        if imgui.ButtonClickable(activeTabScript ~= "logs", u8"Логи", imgui.ImVec2(_widthButtons, 0)) then
            activeTabScript = "logs"
            LoadCollectLogStore()
        end
        imgui.SameLine()
        if imgui.ButtonClickable(activeTabScript ~= "improve", u8"Улучшить", imgui.ImVec2(_widthButtons, 0)) then
            activeTabScript = "improve"
        end
        imgui.SameLine()
        if imgui.ButtonClickable(activeTabScript ~= "settings", u8"Настройки", imgui.ImVec2(-1, 0)) then
            activeTabScript = "settings"
        end

        imgui.Separator()

        if activeTabScript == "main" then
            DrawMainMenu()
        elseif activeTabScript == "logs" then
            DrawCollectLogs()
        elseif activeTabScript == "improve" then
            DrawImproveSharp()
        elseif activeTabScript == "settings" then
            DrawSettings()
        end
    imgui.End()
end)

-- =====================================================================================================================
--                                                          DRAWS
-- =====================================================================================================================

function DrawMainMenu()
    local canCancelFlashCollect = flashCollect.active or (stateCrypto.work and processes.take)
    if canCancelFlashCollect then
        if imgui.Button(fa.CIRCLE_XMARK .. u8"\tОтменить сбор", imgui.ImVec2(-1, 0)) then
            FlashCollect_Cancel()
        end
        imgui.Separator()
    end

    local lastCollectInfo = Collect_GetLastCollectInfo()
    if lastCollectInfo then
        imgui.Text(u8("Последний сбор: " .. Collect_FormatLastCollectText(lastCollectInfo)))
    else
        imgui.TextDisabled(u8"Последний сбор: ещё не зафиксирован.")
    end

    imgui.SameLine()

    local thresholdSeconds = Collect_GetReminderThresholdSeconds()
    if thresholdSeconds > 0 then
        if lastCollectInfo then
            local elapsedSeconds = math.max(0, os.time() - (lastCollectInfo.timestamp or 0))
            local remainSeconds = thresholdSeconds - elapsedSeconds
            if remainSeconds > 0 then
                imgui.Text(u8("Напоминание через: " .. Collect_FormatDuration(remainSeconds)))
            elseif collectReminder.lastNotifiedCollectAt == (lastCollectInfo.timestamp or 0) then
                imgui.Text(u8("Напоминание: уведомление уже отправлено"))
            else
                imgui.Text(u8("Напоминание: время ожидания истекло"))
            end
        else
            imgui.TextDisabled(u8"Напоминание: таймер начнется после первого сбора.")
        end
    else
        imgui.TextDisabled(u8"Напоминание о долгом отсутствии сбора выключено.")
    end
    imgui.Separator()
    if #housesBanks > 0 then
        DrawHousesBank()
    elseif #houses > 0 then
        DrawHouses()
    else
        if #shelves == 0 then
            local canStartFlashCollect = (not stateCrypto.work) and (not flashCollect.active) and (not flashCollect.statsBusy) and (not improve.isOn) and (not improve.oils.busy)
            if imgui.ButtonClickable(canStartFlashCollect, u8"Открыть флешку и собрать", imgui.ImVec2(-1, 0)) then
                StartCollectViaFlash()
            end
            if flashCollect.active then
                imgui.Text(u8"Сбор через флешку: ожидание списка домов...")
            elseif (flashCollect.slot or 0) > 0 and settings.main.showStatusPanel then
                imgui.Text(string.format("Сбор через флешку: слот %d, количество %d", flashCollect.slot or 0, flashCollect.count or 0))
            end
            imgui.Separator()
            imgui.Text(u8(string.format("Охлаждаек в инвентаре: BTC - %s | Supper BTC - %s | ASC - %s", haveLiquid.btc, haveLiquid.supper_btc, haveLiquid.asc)))
            imgui.Separator()
        end
        DrawShelves()
    end
end

local function CollectLogCompareDesc(a, b)
    return tostring(a or '') > tostring(b or '')
end

local function CollectLogSortedKeys(map)
    local keys = {}
    for key in pairs(map or {}) do
        table.insert(keys, key)
    end
    table.sort(keys, CollectLogCompareDesc)
    return keys
end

local function FormatCryptoAmount(value)
    return tostring(math.floor(tonumber(value) or 0))
end

function DrawCollectLogs()
    LoadCollectLogStore()

    local days = collectLogStore.days or {}
    local dayKeys = CollectLogSortedKeys(days)

    imgui.Text(u8(string.format('Дней с логами: %d', #dayKeys)))
    imgui.SameLine()
    if imgui.RightButton(u8'Обновить', imgui.ImVec2(ScaleUI(110), 0)) then
        LoadCollectLogStore()
        days = collectLogStore.days or {}
        dayKeys = CollectLogSortedKeys(days)
    end

    imgui.Separator()
    imgui.BeginChild('collect_logs_list', imgui.ImVec2(-1, -1), true)
    imgui.ScrollMouse()

    if #dayKeys == 0 then
        imgui.TextDisabled(u8'Логи сбора пока пустые.')
        imgui.EndChild()
        return
    end

    for _, dayKey in ipairs(dayKeys) do
        local dayData = days[dayKey] or {}
        local dayTotal = dayData.total or {}
        local dayLabel = string.format('%s | BTC: %s | ASC: %s', dayKey, FormatCryptoAmount(dayTotal.BTC), FormatCryptoAmount(dayTotal.ASC))

        if imgui.TreeNodeStr(u8(dayLabel .. '##collect_day_' .. tostring(dayKey))) then
            local houseKeys = CollectLogSortedKeys(dayData.houses or {})

            if #houseKeys == 0 then
                imgui.TextDisabled(u8'Нет данных по домам.')
            else
                for _, houseId in ipairs(houseKeys) do
                    local houseData = dayData.houses[houseId] or {}
                    local houseTotal = houseData.total or {}
                    local houseLabel = string.format('Дом №%s | BTC: %s | ASC: %s', tostring(houseId), FormatCryptoAmount(houseTotal.BTC), FormatCryptoAmount(houseTotal.ASC))

                    if imgui.TreeNodeStr(u8(houseLabel .. '##collect_house_' .. tostring(dayKey) .. '_' .. tostring(houseId))) then
                        local items = houseData.items or {}
                        if #items == 0 then
                            imgui.TextDisabled(u8'Нет детальных записей.')
                        else
                            for _, item in ipairs(items) do
                                local line = string.format('%s | %s | %s', tostring(item.time or '--:--:--'), tostring(item.currency or '-'), FormatCryptoAmount(item.amount))
                                imgui.BulletText(u8(line))
                            end
                        end
                        imgui.TreePop()
                    end
                end
            end

            imgui.TreePop()
        end
    end
    imgui.EndChild()
end
function DrawImproveSharp()
    if imgui.BeginTabBar("ImproveTabs") then

        if imgui.BeginTabItem(u8"Процесс") then
            DrawImproveProcessTab()
            imgui.EndTabItem()
        end

        if imgui.BeginTabItem(u8"Настройки") then
            DrawImproveSettingsTab()
            imgui.EndTabItem()
        end

        if imgui.BeginTabItem(u8"Логи") then
            DrawImproveLogsTab()
            imgui.EndTabItem()
        end

        imgui.EndTabBar()
    end
end

function DrawImproveProcessTab()
    imgui.Columns(3, nil, false)
        imgui.Text(u8("Материалы для улучшения:"))
    imgui.NextColumn()
        imgui.Text(u8("BTC вид-карты:"))
        imgui.SameLine()
        imgui.TextColored(imgui.ImVec4(0.8,0.9,1,1), u8(tostring(improve.oils.classic)))
    imgui.NextColumn()
        imgui.Text(u8("Arizona вид-карты:"))
        imgui.SameLine()
        imgui.TextColored(imgui.ImVec4(0.8,0.9,1,1), u8(tostring(improve.oils.arizona)))
    imgui.Columns(1)
    imgui.Spacing()

    if imgui.Button(u8(improve.oils.busy and "Сканирую…" or "Обновить инвентарь"), imgui.ImVec2(-1, ScaleUI(26))) then
        Improve_RefreshOils(true)
    end

    if Improve_IsNewStyleMode() then
        if imgui.Button(u8(improve.cef.probing and "Проверяю уровни…" or "Проверить уровень видеокарт"), imgui.ImVec2(-1, ScaleUI(26))) then
            Improve_ManualCheckCardLevels()
        end

    if Improve_IsNewStyleMode() then
        local pTotal = tonumber(improve.cef.probeTotal or 0) or 0
        local pDone  = tonumber(improve.cef.probeProgress or 0) or 0
        if pDone < 0 then pDone = 0 end
        if pTotal > 0 and pDone > pTotal then pDone = pTotal end

        local status = "Проверка уровней: не запускалась"
        if improve.cef.probing then
            status = string.format("Проверка уровней: %d/%d", math.maxEx(0, improve.cef.pendingIndex or 0), math.maxEx(1, pTotal))
        elseif (improve.cef.probeAbortReason or "") ~= "" then
            status = "Проверка уровней: остановлена - " .. tostring(improve.cef.probeAbortReason)
        elseif improve.cef.probed and pTotal > 0 then
            status = string.format("Проверка уровней: завершена (%d/%d)", pDone, pTotal)
        end

        imgui.TextDisabled(u8(status))

        local frac = 0.0
        if pTotal > 0 then
            frac = math.maxEx(0.0, math.minEx(1.0, pDone / pTotal))
        end
        imgui.ProgressBar(frac, imgui.ImVec2(-1, ScaleUI(16)))
    end
    end

    imgui.Separator()

    imgui.CenterText(u8("Этап: " .. (improveSteps[improve.step] or "?")))

    -- Краткая текущая статистика сессии
    local s = improve.stats
    if s and (s.sessionId or 0) > 0 then
        local status = s.active and "идёт" or "завершена"
        imgui.Text(u8(string.format(
            "Сессия #%d (%s). Попыток: %d, успехов: %d, ошибок: %d, смазки: %d",
            s.sessionId or 0,
            status,
            s.attempts or 0,
            s.success or 0,
            s.fail or 0,
            s.oilsUsed or 0
        )))
    else
        imgui.TextDisabled(u8"Сессия заточки ещё не запускалась.")
    end

    if imgui.Button(u8(improve.isOn and "Выключить" or "Включить"), imgui.ImVec2(-1, ScaleUI(30))) then
        if improve.isOn then
            -- стоп заточки
            Improve_Stop("Остановлено вручную через UI")
            MI_Say("Заточка остановлена вручную.")
        else
            -- старт заточки
            improve.isOn            = true
            improve.consumedThisTry = false
            improve.waitStartAt = 0
            improve.waitResultAt = 0
            improve.lastUseAt = 0
            improve.cef.needInventoryRefresh = false
            improve.cef.waitInventory = false
            improve.cef.probed = false
            improve.cef.probing = false
            improve.cef.stubNotified = false

            if settings.improve.checkOilsOnStart or Improve_IsNewStyleMode() then
                -- сначала проверяем смазку
                improve.step          = 0
                improve.needCheckOils = true
                improve.waitOils      = false
            else
                -- сразу начинаем с первого шага без проверки
                improve.step          = 1
                improve.needCheckOils = false
                improve.waitOils      = false
            end

            Improve_MarkNeedScan()
            Improve_SessionStart()
            MI_Say("Заточка видеокарт запущена.")
        end
    end

    imgui.TextDisabled(u8("Режим инвентаря: " .. Improve_GetInventoryModeName()))

    -- Кнопка выбора режима улучшения: производительность / хранилище крипты
    local modeLabel = improve.useStorageUpgrade
        and "Режим улучшения: ХРАНИЛИЩЕ криптовалюты"
        or  "Режим улучшения: ПРОИЗВОДИТЕЛЬНОСТЬ"

    if imgui.Button(u8(modeLabel), imgui.ImVec2(-1, ScaleUI(24))) then
        improve.useStorageUpgrade = not improve.useStorageUpgrade
        if improve.useStorageUpgrade then
            MI_Say("Теперь в диалоге будет выбираться улучшение объёма хранения криптовалюты")
        else
            MI_Say("Теперь в диалоге будет выбираться улучшение производительности видеокарты")
        end
    end

    imgui.Spacing()


    imgui.BeginChild("improve_bottom_proc", imgui.ImVec2(-1, -1), true)
        imgui.ScrollMouse()
        imgui.CenterText(u8("Найденные видеокарты:"))

        for i, v in ipairs(improve.videoCards) do
            local btnW  = imgui.GetMiddleButtonX(4)
            local storageMark = (v.storageUpgrade == true) and u8" [ХР+]" or ""
            local label = (Improve_IsNewStyleMode() and v.slot)
                and string.format("%d LVL%s [slot %d]##%d", v.level, storageMark, v.slot, i)
                or string.format("%d LVL%s##%d", v.level, storageMark, i)
            local canClick = (improve.useStorageUpgrade and not v.storageUpgrade) or ((not improve.useStorageUpgrade) and (v.level < (settings.improve.maxLevel or 2)))
            if imgui.ButtonClickable(canClick, label, imgui.ImVec2(btnW, 0)) then
                if not settings.improve.menuAll then
                    improve.select = i
                    MI_Say("Выбрана видеокарта #" .. i .. " (ур. " .. v.level .. ")")
                end
            end
            if i % 4 ~= 0 and i ~= #improve.videoCards then imgui.SameLine() end
        end
    imgui.EndChild()
end

function DrawImproveSettingsTab()
    imgui.CenterText(u8("Режим работы:"))
    if imgui.Button(u8(settings.improve.menuAll and "Улучшение всех видеокарт" or "Улучшение определенной видеокарты"), imgui.ImVec2(-1, ScaleUI(30))) then
        settings.improve.menuAll = not settings.improve.menuAll
        SaveSettings()
        if settings.improve.menuAll then improve.select = 0 end
    end

    imgui.Separator()

    imgui.CenterText(u8("Вид улучшаемых видеокарт:"))
    local w = (imgui.GetWindowWidth() - ScaleUI(6)) / 2
    if imgui.ButtonClickable(settings.improve.typeCards ~= 1, u8("Обычные"), imgui.ImVec2(w, 0)) then
        settings.improve.typeCards = 1; SaveSettings(); Improve_SyncVideoCardsFromCef(); improve.select = 0
    end
    imgui.SameLine()
    if imgui.ButtonClickable(settings.improve.typeCards ~= 2, "Arizona", imgui.ImVec2(-1, 0)) then
        settings.improve.typeCards = 2; SaveSettings(); Improve_SyncVideoCardsFromCef(); improve.select = 0
    end

    imgui.Separator()

    imgui.CenterText(u8("Режим инвентаря:"))
    if imgui.ButtonClickable((settings.improve.inventoryMode or 1) ~= 1, u8("Классический инвентарь"), imgui.ImVec2(w, 0)) then
        settings.improve.inventoryMode = 1; SaveSettings()
    end
    imgui.SameLine()
    if imgui.ButtonClickable((settings.improve.inventoryMode or 1) ~= 2, u8("Новый стиль"), imgui.ImVec2(-1, 0)) then
        settings.improve.inventoryMode = 2; SaveSettings()
    end
    imgui.TextDisabled(u8"Новый стиль работает через CEF-пакеты, Классический на textdraw")

    imgui.Separator()

    imgui.CenterText(u8("Вид улучшения:"))
    if imgui.ButtonClickable(settings.improve.mode ~= 1, u8("Последовательное"), imgui.ImVec2(w, 0)) then
        settings.improve.mode = 1; SaveSettings()
    end
    imgui.SameLine()
    if imgui.ButtonClickable(settings.improve.mode ~= 2, u8("Поочередное"), imgui.ImVec2(-1, 0)) then
        settings.improve.mode = 2; SaveSettings()
    end
    imgui.TextDisabled(u8"Последовательное (сначала низкий уровень) | Поочередное (как на экране)")

    imgui.Separator()

    imgui.CenterText(u8("Уровень улучшения видеокарт:"))
    imgui.PushItemWidth(-1)
    local _maxLevel = imgui.new.int(settings.improve.maxLevel or 2)
    if imgui.SliderInt("##maximumValueLevel", _maxLevel, 2, 10, u8("%d ур.")) then
        settings.improve.maxLevel = _maxLevel[0]; SaveSettings()
    end
    imgui.PopItemWidth()

    imgui.Separator()

    -- проверять ли смазку при старте заточки
    local _checkOils = imgui.new.bool(settings.improve.checkOilsOnStart)
    if imgui.Checkbox(u8"Проверять смазку при старте заточки", _checkOils) then
        settings.improve.checkOilsOnStart = not settings.improve.checkOilsOnStart
        SaveSettings()
    end
    imgui.TextDisabled(u8"Если выключено, заточка стартует без принудительной проверки")
end

function DrawImproveLogsTab()
    local store = Improve_GetStatsStore()
    local todayKey = os.date('%Y-%m-%d')

    local today = store and store.days and store.days[todayKey] or {
        sessions  = 0,
        attempts  = 0,
        success   = 0,
        fail      = 0,
        oilsUsed  = 0,
        spent     = 0,
        byLevel   = {},
        time      = 0,
    }
    Improve_EnsureLevelStats(today)

    local total = store and store.total or {
        sessions  = 0,
        attempts  = 0,
        success   = 0,
        fail      = 0,
        oilsUsed  = 0,
        spent     = 0,
        byLevel   = {},
        time      = 0,
    }
    Improve_EnsureLevelStats(total)

    local s = improve.stats

    if imgui.BeginTabBar("ImproveLogsSegments") then
        if imgui.BeginTabItem(u8"Сводка") then
            imgui.Columns(2, nil, false)
                imgui.Text(u8(string.format("Сегодня (%s):", todayKey)))
                imgui.Text(u8(string.format("  Сессий:   %d", today.sessions or 0)))
                imgui.Text(u8(string.format("  Попыток:  %d (успехов: %d, ошибок: %d)", today.attempts or 0, today.success or 0, today.fail or 0)))
                imgui.Text(u8(string.format("  Смазки:   %d", today.oilsUsed or 0)))
                imgui.Text(u8(string.format("  Потрачено: $%d", today.spent or 0)))
                imgui.Text(u8(string.format("  Время:    %d сек.", today.time or 0)))
            imgui.NextColumn()
                imgui.Text(u8("За всё время:"))
                imgui.Text(u8(string.format("  Сессий:   %d", total.sessions or 0)))
                imgui.Text(u8(string.format("  Попыток:  %d (успехов: %d, ошибок: %d)", total.attempts or 0, total.success or 0, total.fail or 0)))
                imgui.Text(u8(string.format("  Смазки:   %d", total.oilsUsed or 0)))
                imgui.Text(u8(string.format("  Потрачено: $%d", total.spent or 0)))
                imgui.Text(u8(string.format("  Время:    %d сек.", total.time or 0)))
            imgui.Columns(1)

            imgui.Separator()
            imgui.Text(u8("По уровням (с N на N+1):"))
            imgui.Columns(2, nil, false)
                imgui.Text(u8("Сегодня"))
                for lvl = 1, 9 do
                    local row = today.byLevel[lvl] or {}
                    local attempts = row.attempts or 0
                    local success = row.success or 0
                    local chance = (attempts > 0) and (success * 100.0 / attempts) or 0
                    imgui.Text(u8(string.format(
                        "  %d->%d: попыток %d, шанс %.1f%%, потрачено $%d",
                        lvl, lvl + 1, attempts, chance, row.spent or 0
                    )))
                end
            imgui.NextColumn()
                imgui.Text(u8("За всё время"))
                for lvl = 1, 9 do
                    local row = total.byLevel[lvl] or {}
                    local attempts = row.attempts or 0
                    local success = row.success or 0
                    local chance = (attempts > 0) and (success * 100.0 / attempts) or 0
                    imgui.Text(u8(string.format(
                        "  %d->%d: попыток %d, шанс %.1f%%, потрачено $%d",
                        lvl, lvl + 1, attempts, chance, row.spent or 0
                    )))
                end
            imgui.Columns(1)
            imgui.EndTabItem()
        end

        if imgui.BeginTabItem(u8"Сессия") then
            if s and (s.sessionId or 0) > 0 then
                local startedStr  = (s.startedAt  and s.startedAt  > 0) and os.date('%d.%m.%Y %H:%M:%S', s.startedAt)  or "-"
                local finishedStr = (s.finishedAt and s.finishedAt > 0) and os.date('%d.%m.%Y %H:%M:%S', s.finishedAt) or (s.active and "идёт…" or "-")

                imgui.Text(u8(string.format("Последняя сессия #%d:", s.sessionId)))
                imgui.Text(u8("  Старт:      " .. startedStr))
                imgui.Text(u8("  Завершение: " .. finishedStr))
                imgui.Text(u8(string.format("  Попыток:    %d (успехов: %d, ошибок: %d)", s.attempts or 0, s.success or 0, s.fail or 0)))
                imgui.Text(u8(string.format("  Смазки потрачено: %d", s.oilsUsed or 0)))
                imgui.Text(u8(string.format("  Денег потрачено:  $%d", s.spent or 0)))
                if s.lastReason and s.lastReason ~= "" then
                    imgui.Text(u8("  Причина завершения: " .. s.lastReason))
                end
            else
                imgui.TextDisabled(u8"Сессий заточки ещё не было.")
            end
            imgui.EndTabItem()
        end

        if imgui.BeginTabItem(u8"Лента") then
            if imgui.Button(u8"Очистить лог", imgui.ImVec2(ScaleUI(120), 0)) then
                improve.logs.items = {}
            end
            imgui.SameLine()
            local autoScrollPtr = imgui.new.bool(improve.logs.autoScroll ~= false)
            if imgui.Checkbox(u8"Автопрокрутка вниз", autoScrollPtr) then
                improve.logs.autoScroll = autoScrollPtr[0]
            end

            imgui.Separator()
            imgui.BeginChild("improve_logs_scroll", imgui.ImVec2(-1, -1), true)
                imgui.ScrollMouse()
                for i, entry in ipairs(improve.logs.items or {}) do
                    local line = string.format("[%s] [%s] %s", entry.ts or "?", entry.type or "INFO", entry.text or "")
                    local etype = entry.type or "INFO"
                    if etype == "ERROR" or etype == "WARN" then
                        imgui.TextColored(imgui.ImVec4(1, 0.4, 0.4, 1), u8(line))
                    elseif etype == "SUCCESS" then
                        imgui.TextColored(imgui.ImVec4(0.6, 1.0, 0.6, 1), u8(line))
                    else
                        imgui.Text(u8(line))
                    end
                end

                if improve.logs.autoScroll ~= false then
                    imgui.SetScrollHereY(1.0)
                end
            imgui.EndChild()
            imgui.EndTabItem()
        end

        if imgui.BeginTabItem(u8"Сервис") then
            imgui.TextWrapped(u8"Сброс удаляет накопленную статистику по дням и за всё время.")
            if imgui.Button(u8"Сбросить статистику", imgui.ImVec2(ScaleUI(180), 0)) then
                improve.statsStore = {
                    days = {},
                    total = {
                        sessions  = 0,
                        attempts  = 0,
                        success   = 0,
                        fail      = 0,
                        oilsUsed  = 0,
                        spent     = 0,
                        byLevel   = {},
                        time      = 0,
                    }
                }
                Improve_EnsureLevelStats(improve.statsStore.total)
                Improve_SaveStatsStore()
            end
            imgui.EndTabItem()
        end

        imgui.EndTabBar()
    end
end


function DrawSettings()
    -- Верхняя панель статуса (если включена)
    if settings.main.showStatusPanel then
        imgui.BeginChild("status_panel", imgui.ImVec2(-1, 60), true)
        imgui.Text(u8(string.format("Работаю: %s | Заливаю: %s | Собираю: %s | Вкл/выкл: %s", 
            stateCrypto.work, processes.fill, processes.take, (processes.on or processes.off))))

        if stateCrypto.work then
            imgui.Spacing()
            if imgui.Button(u8"Отменить процесс", imgui.ImVec2(-1, 0)) then
                DeactivateProcessesInteracting()
            end
        end
        imgui.EndChild()

        imgui.Spacing()
    end

    -- Основная область с табами
    imgui.BeginChild("settings_tabs", imgui.ImVec2(-1, -1))

    if imgui.BeginTabBar("SettingsTabs") then

        -- ТАБ 1: Основное
        if imgui.BeginTabItem(u8"Основное") then
            imgui.BeginChild("tab_main", imgui.ImVec2(-1, -1))
            imgui.ScrollMouse()
            imgui.Spacing()

            if imgui.Checkbox(u8"Заменять окно диалога на окно скрипта", new.bool(settings.main.replaceDialog)) then
                settings.main.replaceDialog = not settings.main.replaceDialog 
                SaveSettings()
            end

            if imgui.Checkbox(u8"Закрывать скрипт на ESC", new.bool(settings.main.closeOnESC)) then
                settings.main.closeOnESC = not settings.main.closeOnESC 
                SaveSettings()
            end

            if imgui.Checkbox(u8"Перемещаться стрелочками в списке", new.bool(settings.main.arrowsMove)) then
                settings.main.arrowsMove = not settings.main.arrowsMove 
                SaveSettings()
            end

            if imgui.Checkbox(u8"Скрыть текст получения крипты в чате", new.bool(settings.main.hideMessagesCollect)) then
                settings.main.hideMessagesCollect = not settings.main.hideMessagesCollect 
                SaveSettings()
            end

            if imgui.Checkbox(u8"Отображать панель статуса (дебаг информация)", new.bool(settings.main.showStatusPanel)) then
                settings.main.showStatusPanel = not settings.main.showStatusPanel 
                SaveSettings()
            end
            imgui.TextDisabled(u8"Отображать информацию о работающих процессах вверху окна")

            if imgui.Checkbox(u8"Проверять смазку при старте заточки", new.bool(settings.improve.checkOilsOnStart)) then
                settings.improve.checkOilsOnStart = not settings.improve.checkOilsOnStart
                SaveSettings()
            end
            imgui.TextDisabled(u8"Если выключено, заточка стартует без принудительной проверки")

            imgui.Text(u8"Напомнить, если не было сбора:")
            imgui.PushItemWidth(ScaleUI(120))
            local collectNotifyMinutesPtr = imgui.new.int(tonumber(settings.main.collectNotifyMinutes) or 0)
            if imgui.InputInt("##collectNotifyMinutes", collectNotifyMinutesPtr, 0, 0) then
                settings.main.collectNotifyMinutes = math.maxEx(0, collectNotifyMinutesPtr[0])
                SaveSettings()
            end
            imgui.PopItemWidth()
            imgui.SameLine()
            imgui.TextDisabled(u8"мин (0 = выкл)")

            local notifyState = Collect_GetNotifySystemState()
            if not notifyState.ready then
                imgui.TextDisabled(u8(notifyState.message))
                if collectReminder.managerEnsurePending then
                    imgui.TextDisabled(u8"Подготовка менеджера уведомлений...")
                else
                    if imgui.Button(u8(Collect_GetNotifyInstallButtonText(notifyState)), imgui.ImVec2(-1, 0)) then
                        Collect_EnsureNotificationManager()
                    end
                    if not notifyState.available then
                        if collectReminder.managerDownloadPending then
                            imgui.TextDisabled(u8"Скачивание менеджера уведомлений и библиотеки...")
                        elseif imgui.Button(u8"Скачать менеджер и библиотеку", imgui.ImVec2(-1, 0)) then
                            Collect_DownloadNotificationSystem()
                        end
                    end
                end
                imgui.TextDisabled(u8("GitHub: " .. NOTIFY_MANAGER_REPO_URL))
                if collectReminder.managerStatusMessage ~= "" then
                    imgui.TextDisabled(u8(collectReminder.managerStatusMessage))
                end
            end

            imgui.Spacing()
            imgui.Separator()
            imgui.Spacing()

            imgui.Text(u8(string.format("Заливать при %.0f%%%% или ниже:", settings.main.fillFrom)))
            imgui.PushItemWidth(-1)
            local _fillFrom = new.float(settings.main.fillFrom)
            if imgui.SliderFloat("##fillFrom", _fillFrom, 0, 99, "%.0f%%") then
                settings.main.fillFrom = Round(_fillFrom[0], 2)
                SaveSettings()
            end
            imgui.PopItemWidth()

            imgui.EndChild()
            imgui.EndTabItem()
        end

        -- ТАБ 2: Доходность
        if imgui.BeginTabItem(u8"Доходность") then
            imgui.BeginChild("tab_income", imgui.ImVec2(-1, -1))
            imgui.ScrollMouse()
            imgui.Spacing()

            local inc = GetIncomeSettings()

            imgui.TextWrapped(u8"Выберите, какие показатели доходности отображать:")
            imgui.Spacing()
            imgui.Separator()
            imgui.Spacing()

            if imgui.Checkbox(u8"Показывать доход за час", imgui.new.bool(inc.showPerHour)) then
                inc.showPerHour = not inc.showPerHour
                SaveSettings()
            end
            imgui.SameLine()
            imgui.TextDisabled(u8"(/час)")

            if imgui.Checkbox(u8"Показывать доход за 24 часа", imgui.new.bool(inc.showPer24h)) then
                inc.showPer24h = not inc.showPer24h
                SaveSettings()
            end
            imgui.SameLine()
            imgui.TextDisabled(u8"(/24ч)")

            if imgui.Checkbox(u8"Показывать доход за цикл", imgui.new.bool(inc.showPerCycle)) then
                inc.showPerCycle = not inc.showPerCycle
                SaveSettings()
            end
            imgui.SameLine()
            imgui.TextDisabled(u8"(/цикл)")

            imgui.Spacing()
            imgui.Separator()
            imgui.Spacing()

            if imgui.Checkbox(u8"Показывать текущую прибыль", imgui.new.bool(inc.showTillThresholdProfit)) then
                inc.showTillThresholdProfit = not inc.showTillThresholdProfit
                SaveSettings()
            end

            if imgui.Checkbox(u8"Показывать время до доливки", imgui.new.bool(inc.showTillThresholdHours)) then
                inc.showTillThresholdHours = not inc.showTillThresholdHours
                SaveSettings()
            end

            imgui.Spacing()
            imgui.Separator()
            imgui.Spacing()

            imgui.TextWrapped(u8"Бонусы доходности по домам:")
            imgui.Spacing()
            imgui.Text(u8"Время в онлайне:")
            imgui.PushItemWidth(ScaleUI(120))
            local incomeOnlineHoursPtr = imgui.new.int(tonumber(inc.onlineHours) or 0)
            if imgui.InputInt("##income_online_hours_global", incomeOnlineHoursPtr, 0, 0) then
                inc.onlineHours = math.minEx(24, math.maxEx(0, incomeOnlineHoursPtr[0]))
                SaveSettings()
            end
            imgui.PopItemWidth()
            imgui.SameLine()
            imgui.TextDisabled(u8"ч (0-24)")
            imgui.TextDisabled(u8"Бонус от Время в онлайне применяется ко всем домам, даже если дома нет в списке ниже")
            imgui.Spacing()

            imgui.Text(u8"Номер дома:")
            imgui.PushItemWidth(ScaleUI(140))
            imgui.InputInt("##incomeHouseNumber", inputIncomeHouse, 0, 0)
            imgui.PopItemWidth()
            imgui.SameLine()

            if imgui.Button(u8"Добавить дом", imgui.ImVec2(ScaleUI(160), 0)) then
                local houseNumber = math.maxEx(0, inputIncomeHouse[0])
                if houseNumber >= 0 then
                    local houseKey = tostring(houseNumber)
                    if type(inc.houseBonuses[houseKey]) ~= "table" then
                        inc.houseBonuses[houseKey] = {
                            creativitySet = false,
                            customPercent = 0,
                        }
                        SaveSettings()
                    end
                    inputIncomeHouse[0] = 0
                end
            end
            imgui.TextDisabled(u8"Набор творчества даёт +20%% для дома")

            imgui.Spacing()

            local houseKeys = GetSortedIncomeHouseBonusKeys()
            if #houseKeys == 0 then
                imgui.TextDisabled(u8"Список домов пуст. Добавьте дом выше.")
            else
                imgui.BeginChild("income_house_bonus_list", imgui.ImVec2(-1, ScaleUI(220)), true)
                imgui.ScrollMouse()

                local removedHouse = false
                for _, houseKey in ipairs(houseKeys) do
                    local houseConfig = NormalizeIncomeHouseBonusConfig(inc.houseBonuses[houseKey])
                    inc.houseBonuses[houseKey] = houseConfig
                    local totalBonus = CalcHouseIncomeBonusPercent(houseKey)

                    imgui.Separator()
                    imgui.Text(u8(string.format("Дом №%s | Итоговый бонус: +%.2f%%", houseKey, totalBonus)))

                    imgui.SameLine()
                    if imgui.RightButton(u8("Удалить##income_remove_" .. houseKey), imgui.ImVec2(ScaleUI(120), 0)) then
                        inc.houseBonuses[houseKey] = nil
                        SaveSettings()
                        removedHouse = true
                        break
                    end

                    local creativityPtr = imgui.new.bool(houseConfig.creativitySet == true)
                    if imgui.Checkbox(u8("Набор творчества##income_creativity_" .. houseKey), creativityPtr) then
                        houseConfig.creativitySet = creativityPtr[0]
                        SaveSettings()
                    end

                    imgui.SameLine()
                    imgui.Text("\t|\t")
                    imgui.SameLine()

                    imgui.Text(u8"Свой процент:")
                    imgui.SameLine()
                    imgui.PushItemWidth(ScaleUI(120))
                    local customPercentPtr = imgui.new.int(tonumber(houseConfig.customPercent) or 0)
                    if imgui.InputInt("##income_custom_percent_" .. houseKey, customPercentPtr, 0, 0) then
                        houseConfig.customPercent = math.maxEx(0, customPercentPtr[0])
                        SaveSettings()
                    end
                    imgui.PopItemWidth()
                    imgui.SameLine()
                    imgui.TextDisabled(u8"%%")

                    imgui.Spacing()
                end

                if not removedHouse and #houseKeys > 0 then
                    imgui.Separator()
                end
                imgui.EndChild()
            end

            imgui.EndChild()
            imgui.EndTabItem()
        end
        -- ТАБ 3: Банк
        if imgui.BeginTabItem(u8"Банк") then
            imgui.BeginChild("tab_bank", imgui.ImVec2(-1, -1))
            imgui.ScrollMouse()
            imgui.Spacing()

            imgui.TextWrapped(u8"Настройки автоматического пополнения банка:")
            imgui.Spacing()
            imgui.Separator()
            imgui.Spacing()

            local _bankFillToTarget = imgui.new.bool(settings.main.bankFillToTarget)
            if imgui.Checkbox(u8"Пополнять до заданной суммы", _bankFillToTarget) then
                settings.main.bankFillToTarget = not settings.main.bankFillToTarget
                SaveSettings()
            end
            imgui.TextDisabled(u8"Если выключено - пополнение до максимума")

            imgui.Spacing()
            imgui.Spacing()

            imgui.Text(u8"Целевая сумма для пополнения:")
            imgui.PushItemWidth(-1)

            if ui_bank.buf[0] == 0 then
                buf_set(ui_bank.buf, format_commas(settings.main.bankTargetAmount or 10000000))
            end

            local pressed = imgui.InputText("##bankTargetAmount", ui_bank.buf, 32,
                imgui.InputTextFlags.AutoSelectAll + imgui.InputTextFlags.EnterReturnsTrue)
            if pressed then
                local s = ffi.string(ui_bank.buf)
                local v = clamp_bank_target(digits_to_int(s))
                if v ~= (settings.main.bankTargetAmount or 0) then
                    settings.main.bankTargetAmount = v
                    SaveSettings()
                end
                buf_set(ui_bank.buf, format_commas(settings.main.bankTargetAmount))
            end
            if imgui.IsItemDeactivatedAfterEdit() then
                buf_set(ui_bank.buf, format_commas(settings.main.bankTargetAmount))
            end
            imgui.PopItemWidth()
            imgui.TextDisabled(u8"Нажмите Enter для сохранения")

            imgui.EndChild()
            imgui.EndTabItem()
        end

        -- ТАБ 4: Задержки
        if imgui.BeginTabItem(u8"Задержки") then
            imgui.BeginChild("tab_delays", imgui.ImVec2(-1, -1))
            imgui.ScrollMouse()

            imgui.Spacing()

            imgui.TextWrapped(u8"Настройка временных интервалов для стабильной работы скрипта:")
            imgui.Spacing()
            imgui.Separator()
            imgui.Spacing()

            imgui.PushItemWidth(-1)

            imgui.CenterText(u8"Для работы с полками")

            imgui.Spacing()

            imgui.Text(u8"Ожидание ответа диалога:")
            local _timeoutDialog = new.int(settings.deley.timeoutDialog)
            if imgui.SliderInt("##timeoutDialog", _timeoutDialog, 1, 30, u8"%d сек") then
                settings.deley.timeoutDialog = _timeoutDialog[0]
                SaveSettings()
            end
            imgui.TextDisabled(u8"Максимальное время ожидания открытия диалога")

            imgui.Spacing()

            imgui.Text(u8"Интервал проверки:")
            local _waitInterval = new.int(settings.deley.waitInterval)
            if imgui.SliderInt("##waitInterval", _waitInterval, 1, 100, u8"%d мс") then
                settings.deley.waitInterval = _waitInterval[0]
                SaveSettings()
            end
            imgui.TextDisabled(u8"Частота проверки состояния (миллисекунды)")

            imgui.Spacing()

            imgui.Text(u8"Ожидание ответа от полок:")
            local _timeoutShelf = new.int(settings.deley.timeoutShelf)
            if imgui.SliderInt("##timeoutShelf", _timeoutShelf, 1, 30, u8"%d сек") then
                settings.deley.timeoutShelf = _timeoutShelf[0]
                SaveSettings()
            end
            imgui.TextDisabled(u8"Максимальное время ожидания ответа от полок")

            imgui.Spacing()

            imgui.Text(u8"Задержка перед ответом на диалог:")
            local _waitRun = new.int(settings.deley.waitRun)
            if imgui.SliderInt("##waitRun", _waitRun, 1, 100, u8"%d мс") then
                settings.deley.waitRun = _waitRun[0]
                SaveSettings()
            end
            imgui.TextDisabled(u8"Пауза перед отправкой ответа в диалог")

            imgui.Spacing()
            imgui.Separator()
            imgui.Spacing()

            imgui.CenterText(u8"Для улучшения видеокарт")

            imgui.Spacing()

            imgui.Text(u8"Задержка после получения результата улучшения:")
            local _improve_waitResult = new.int(settings.deley.improve_waitResult)
            if imgui.SliderInt("##improve_waitResult", _improve_waitResult, 10, 1000, u8"%d мс") then
                settings.deley.improve_waitResult = _improve_waitResult[0]
                SaveSettings()
            end
            imgui.TextDisabled(u8"Пауза после получения результата улучшения")

            imgui.Text(u8"Ожидание перед нажатием на видеокарту:")
            local _improve_waitTryClick = new.int(settings.deley.improve_waitTryClick)
            if imgui.SliderInt("##improve_waitTryClick", _improve_waitTryClick, 10, 1000, u8"%d мс") then
                settings.deley.improve_waitTryClick = _improve_waitTryClick[0]
                SaveSettings()
            end
            imgui.TextDisabled(u8"Пауза перед тем, как нажать на видеокарту")

            imgui.Text(u8"Интервал автоповтора USE:")
            local _improve_retryUseDelay = new.int(settings.deley.improve_retryUseDelay or 1200)
            if imgui.SliderInt("##improve_retryUseDelay", _improve_retryUseDelay, 200, 5000, u8"%d мс") then
                settings.deley.improve_retryUseDelay = _improve_retryUseDelay[0]
                SaveSettings()
            end
            imgui.TextDisabled(u8"Если USE долго не срабатывает, скрипт нажмёт снова")

            imgui.Text(u8"Таймаут ожидания старта улучшения:")
            local _improve_waitStartTimeout = new.int(settings.deley.improve_waitStartTimeout or 8)
            if imgui.SliderInt("##improve_waitStartTimeout", _improve_waitStartTimeout, 2, 30, u8"%d сек") then
                settings.deley.improve_waitStartTimeout = _improve_waitStartTimeout[0]
                SaveSettings()
            end
            imgui.TextDisabled(u8"Если старт не подтверждён сервером, попытка перезапускается")

            imgui.Text(u8"Таймаут ожидания результата улучшения:")
            local _improve_waitResultTimeout = new.int(settings.deley.improve_waitResultTimeout or 20)
            if imgui.SliderInt("##improve_waitResultTimeout", _improve_waitResultTimeout, 3, 60, u8"%d сек") then
                settings.deley.improve_waitResultTimeout = _improve_waitResultTimeout[0]
                SaveSettings()
            end
            imgui.TextDisabled(u8"Если нет результата, попытка считается ошибкой и цикл продолжается")

            imgui.PopItemWidth()

            imgui.EndChild()
            imgui.EndTabItem()
        end

        -- ТАБ 5: Черный список
        if imgui.BeginTabItem(u8"Черный список") then
            imgui.BeginChild("tab_blacklist", imgui.ImVec2(-1, -1))
            imgui.Spacing()

            imgui.TextWrapped(u8"Добавьте номера домов, которые нужно исключить из обработки:")
            imgui.Spacing()
            imgui.Separator()
            imgui.Spacing()

            imgui.Text(u8"Номер дома:")
            imgui.PushItemWidth(200)
            imgui.InputInt("##numberHouse", inputBlackHouse, 0, 0)
            imgui.PopItemWidth()
            imgui.SameLine()
            if imgui.Button(u8"Добавить в список", imgui.ImVec2(ScaleUI(150), 0)) then
                if inputBlackHouse[0] >= 0 then
                    table.insert(settings.main.blackListHouses, inputBlackHouse[0])
                    SaveSettings()
                    inputBlackHouse[0] = 0
                end
            end

            imgui.Spacing()
            imgui.Separator()
            imgui.Spacing()

            if #settings.main.blackListHouses > 0 then
                imgui.Text(u8(string.format("Домов в черном списке: %d", #settings.main.blackListHouses)))
                imgui.Spacing()
                imgui.BeginChild("blacklist_scroll", imgui.ImVec2(-1, -1), true)
                imgui.ScrollMouse()
                for index, blackHouse in ipairs(settings.main.blackListHouses) do
                    if imgui.Button(u8"Удалить##"..index, imgui.ImVec2(ScaleUI(80), 0)) then
                        table.remove(settings.main.blackListHouses, index)
                        SaveSettings()
                    end
                    imgui.SameLine()
                    imgui.Text(u8(string.format("Дом №%d", blackHouse)))
                    if index < #settings.main.blackListHouses then
                        imgui.Spacing()
                    end
                end
                imgui.EndChild()
            else
                imgui.TextDisabled(u8"Список пуст. Добавьте первый дом.")
            end

            imgui.EndChild()
            imgui.EndTabItem()
        end

        -- ТАБ 6: Интерфейс
        if imgui.BeginTabItem(u8"Интерфейс") then
            imgui.BeginChild("tab_interface", imgui.ImVec2(-1, -1))
            imgui.ScrollMouse()
            imgui.Spacing()

            if imgui.Checkbox(u8"Скролл пальцем", imgui.new.bool(settings.style.swipeScroll)) then
                settings.style.swipeScroll = not settings.style.swipeScroll
                SaveSettings()
            end
            imgui.TextDisabled(u8"Если включено - списки можно прокручивать свайпом (требуется перезагрузка скрипта).\nНо перемещение окна только за заголовок скрипта")

            imgui.Spacing()

            imgui.PushItemWidth(-1)

            imgui.Text(u8"Размер полосы прокрутки:")
            local _scrollbarSizeStyle = new.int(settings.style.scrollbarSizeStyle)
            if imgui.SliderInt("##scrollbarSize", _scrollbarSizeStyle, 10, 50, "%d px") then
                settings.style.scrollbarSizeStyle = _scrollbarSizeStyle[0] 
                SaveSettings()
                SetStyle()
            end

            imgui.Spacing()

            imgui.Text(u8"Масштаб интерфейса (DPI):")
            local _MONET_DPI_SCALE = new.float(settings.style.scaleUI)
            if imgui.SliderFloat("##scaleUI", _MONET_DPI_SCALE, 0.5, 3.0, "%.2f") then
                settings.style.scaleUI = _MONET_DPI_SCALE[0]
                SaveSettings()
            end
            imgui.TextDisabled(u8"Рекомендуемые значения: 1.0 - 2.0")

            imgui.PopItemWidth()

            imgui.Spacing()
            imgui.Separator()
            imgui.Spacing()

            if imgui.Button(u8"Перезапустить скрипт", imgui.ImVec2(-1, ScaleUI(40))) then
                thisScript():reload()
            end

            imgui.Spacing()
            imgui.TextWrapped(u8"Для применения изменения масштаба необходимо перезапустить скрипт.")
            imgui.Spacing()
            imgui.Text(u8"Полезные команды:")
            imgui.BulletText(u8"/mmtr - перезапустить скрипт")
            imgui.BulletText(u8"/mmtsr - сбросить масштаб к значению по умолчанию")

            imgui.EndChild()
            imgui.EndTabItem()
        end

        -- ТАБ 7: Автор
        if imgui.BeginTabItem(u8"Автор") then
            imgui.BeginChild("tab_author", imgui.ImVec2(-1, -1))
            imgui.ScrollMouse()
            imgui.Spacing()

            imgui.Text(u8"Канал разработчика в ТГ: ") imgui.SameLine()
            if imgui.ClickableText("MR.Sand | ARZ MCR & Mobile") then
                OpenUrl("https://t.me/arz_mcr")
            end

            imgui.Text(u8"ТГ разработчика: ") imgui.SameLine()
            if imgui.ClickableText("@Mister_Sand") then
                OpenUrl("https://t.me/Mister_Sand")
            end
            imgui.Spacing()
            imgui.Text(u8"Помощь монеткой разработчику: ") imgui.SameLine()
            if imgui.ClickableText("Boosty") then
                OpenUrl("https://boosty.to/sand-mcr")
            end
            imgui.Text(u8"Тема на Blast.hk: ") imgui.SameLine()
            if imgui.ClickableText("MMT | Mining Tool") then
                OpenUrl("https://www.blast.hk/threads/242059/")
            end

            imgui.Spacing()
            imgui.Separator()
            imgui.Spacing()

            imgui.TextWrapped(u8"Вы можете предлагать свои идеи для улучшения скрипта на Blast.hk или прямо в личные сообщения мне в ТГ")

            imgui.Spacing()
            imgui.Separator()

            imgui.EndChild()
            imgui.EndTabItem()
        end

        -- ТАБ 8: Техническая информация (только если есть данные)
        if #stateCrypto.queueShelves > 0 then
            if imgui.BeginTabItem(u8"Тех. состояние") then
                imgui.BeginChild("tab_techstate", imgui.ImVec2(-1, -1))
                imgui.Spacing()

                imgui.Text(u8(string.format("Количество активных полок: %d", #stateCrypto.queueShelves)))
                imgui.Spacing()
                imgui.Separator()
                imgui.Spacing()

                imgui.BeginChild("tech_state_scroll", imgui.ImVec2(-1, -1), true)
                imgui.ScrollMouse()

                imgui.Columns(4, "tech_columns", true)
                imgui.SetColumnWidth(0, 100)
                imgui.SetColumnWidth(1, 100)
                imgui.SetColumnWidth(2, 100)
                imgui.SetColumnWidth(3, 150)

                imgui.Text(u8"Строка")
                imgui.NextColumn()
                imgui.Text(u8"Заливка")
                imgui.NextColumn()
                imgui.Text(u8"Крипты")
                imgui.NextColumn()
                imgui.Text(u8"Состояние")
                imgui.NextColumn()
                imgui.Separator()

                -- Данные
                for index, value in ipairs(stateCrypto.queueShelves) do
                    imgui.Text(u8(tostring(value.samp_line)))
                    imgui.NextColumn()
                    imgui.Text(u8(tostring(value.fill)))
                    imgui.NextColumn()
                    imgui.Text(u8(tostring(value.count)))
                    imgui.NextColumn()
                    imgui.Text(u8(tostring(value.work)))
                    imgui.NextColumn()
                    if index < #stateCrypto.queueShelves then
                        imgui.Separator()
                    end
                end

                imgui.Columns(1)
                imgui.EndChild()

                imgui.EndChild()
                imgui.EndTabItem()
            end
        end

        imgui.EndTabBar()
    end

    imgui.EndChild()
end

function DrawHousesBank()
    if stateCrypto.work then
        imgui.ProgressBar(stateCrypto.progressHousesBank/#stateCrypto.queueHousesBank,imgui.ImVec2(-1,0), u8"Дом "..stateCrypto.progressHousesBank.."/"..#stateCrypto.queueHousesBank)
    end

    local btnTitle = settings.main.bankFillToTarget and u8"Заполнить до цели" or u8"Заполнить до MAX"
    if imgui.ButtonClickable(not stateCrypto.work, btnTitle, imgui.ImVec2(-1, 0)) then
        StartProcessInteracting("dep")
    end

    imgui.BeginChild("list", imgui.ImVec2(-1, -1))
    imgui.ScrollMouse()
    lastOpenHouse = HandleListNavigation(
        (lastOpenHouse > 0 and lastOpenHouse or 1),
        #housesBanks,
        function(idx)
            local house = housesBanks[idx]
            if house then
                sampSendDialogResponse(idDialogs.selectHouse, 1, house.samp_line, "")
                housesBanks = {}
                SwitchMainWindow()
            end
        end
    )
    for i, house in ipairs(housesBanks) do
        local _bank_now_str = tostring(house.bankNow or ""):gsub("[^%d]", "")
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

        if imgui.SelectableEx(i, house_text, lastOpenHouse == i, imgui.SelectableFlags.SpanAllColumns) and IsClick() then
            lastOpenHouse = i
            sampSendDialogResponse(idDialogs.selectHouse, 1, house.samp_line, "")
            housesBanks = {}
            SwitchMainWindow()
        end

        -- небольшой отступ между домами
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
        local bank_now = tonumber((tostring(house.bankNow or ""):gsub("[^%d]", ""))) or 0
        if bank_now < 5000000 then
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
    if imgui.ButtonClickable(not stateCrypto.work, fa.PLAY .. u8"\tВключить все видеокарты", imgui.ImVec2(-1, 0)) then
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
    imgui.ScrollMouse()
    lastOpenHouse = HandleListNavigation(
         math.maxEx(1, math.minEx(lastOpenHouse, #houses)),
        #houses,
        function(idx)
            local house = houses[idx]
            if house then
                sampSendDialogResponse(idDialogs.selectHouse, 1, house.samp_line, "")
                houses = {}
            end
        end
    )
    for i, house in ipairs(houses) do
        -- Определяем цвета для циклов и банка
        local cycles_color = house.cycles < 100 and COLORS.RED or COLORS.WHITE -- красный если < 100, белый если >= 100

        local _bank_now_str = tostring(house.bankNow or ""):gsub("[^%d]", "")
        local bank_now = tonumber(_bank_now_str) or 0
        local bank_color = COLORS.WHITE

        if bank_now < 5000000 then
            bank_color = COLORS.RED
        elseif bank_now < 10000000 then
            bank_color = COLORS.YELLOW
        end

        local house_data = housesData[tostring(house.house_number)]
        local house_data_str = house_data and string.format("Раб. вид-карт: %s  Мкс. крипты: {%s}%d{%s}  Мин. охлада: {%s}%d{%s}",
            house_data.work_vc,
            house_data.max_collect > 8 and COLORS.RED or house_data.max_collect > 1 and COLORS.GREEN or COLORS.WHITE,
            tonumber(house_data.max_collect),
            COLORS.WHITE,
            house_data.min_liquid == 0 and COLORS.RED or house_data.min_liquid < settings.main.fillFrom and COLORS.YELLOW or COLORS.WHITE,
            house_data.min_liquid,
            COLORS.WHITE
        ) or "-"
        -- Формируем текст для строки
        local house_text = string.format("№%s  {%s}%s  Налог: %s  {%s}Циклов: {%s}%s  {%s}Банк: {%s}%s%s",
            house.house_number,
            COLORS.WHITE,
            house_data_str,
            house.tax,
            COLORS.WHITE,
            cycles_color,
            GetCommaValue(house.cycles),
            COLORS.WHITE,
            bank_color,
            GetCommaValue(house.bankNow or 0),
            house.currency
        )

        if imgui.SelectableEx(i, house_text, lastOpenHouse == i, imgui.SelectableFlags.SpanAllColumns) and IsClick() then
            lastOpenHouse = i
            sampSendDialogResponse(idDialogs.selectHouse, 1, house.samp_line, "")
            houses = {}
        end

        -- небольшой отступ между домами
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

    local totalWidth = (imgui.GetWindowWidth() - ScaleUI(30))
    local half    = totalWidth / 2
    local quarter = (totalWidth / 4) - (imgui.GetStyle().ItemSpacing.x / 2)

    if imgui.ButtonClickable(not stateCrypto.work, fa.HAND_HOLDING_DOLLAR .. u8"\tСобрать", imgui.ImVec2(half, 0)) then
        StartProcessInteracting("take")
    end
    imgui.SameLine()
    if imgui.ButtonClickable(not stateCrypto.work, fa.FILL_DRIP .. u8"\tЗалить", imgui.ImVec2(quarter, 0)) then
        StartProcessInteracting("fill")
    end

    imgui.SameLine()

    local autoIcon  = settings.main.autoFillEnabled and fa.TOGGLE_ON or fa.TOGGLE_OFF
    local autoTitle = settings.main.autoFillEnabled and u8"Автозаливка: вкл" or u8"Автозаливка: выкл"
    if imgui.Button(autoIcon .. "\t" .. autoTitle, imgui.ImVec2(-1, 0)) then
        settings.main.autoFillEnabled = not settings.main.autoFillEnabled
        SaveSettings()
        AddChatMessage("Автозаливка: " .. (settings.main.autoFillEnabled and "включена" or "выключена"), TYPECHATMESSAGES.SECONDARY)
    end

    local toggleEnableIcon  = settings.main.autoEnableCards and fa.TOGGLE_ON or fa.TOGGLE_OFF
    local toggleEnableTitle = settings.main.autoEnableCards and u8"Автовкл: вкл" or u8"Автовкл: выкл"

    if imgui.ButtonClickable(not stateCrypto.work, fa.PLAY .. u8"\tВключить карты", imgui.ImVec2(quarter, 0)) then
        StartProcessInteracting("on")
    end
    imgui.SameLine()
    if imgui.Button(toggleEnableIcon .. "\t" .. toggleEnableTitle, imgui.ImVec2(quarter, 0)) then
        settings.main.autoEnableCards = not settings.main.autoEnableCards
        SaveSettings()
        AddChatMessage("Автовключение карт после сбора: " .. (settings.main.autoEnableCards and "включено" or "выключено"), TYPECHATMESSAGES.SECONDARY)
    end
    imgui.SameLine()
    if imgui.ButtonClickable(not stateCrypto.work, fa.PAUSE .. u8"\tОтключить карты", imgui.ImVec2(-1, 0)) then
        StartProcessInteracting("off")
    end
    if stateCrypto.work then
        imgui.ProgressBar(stateCrypto.progressShelves/#stateCrypto.queueShelves,imgui.ImVec2(-1,0), stateCrypto.progressShelves.."/"..#stateCrypto.queueShelves)
    end

    local currentHouseNumber = tonumber(stateCrypto.activeHouseID)
    local currentHouseBonusPercent = CalcHouseIncomeBonusPercent(currentHouseNumber)
    local inc = GetIncomeSettings()
    if currentHouseNumber and currentHouseNumber > 0 then
        imgui.Text(u8(string.format("Дом №%d | Бонус доходности: +%.2f%%", currentHouseNumber, currentHouseBonusPercent)))
    end

    imgui.Separator()

    imgui.BeginChild("list", imgui.ImVec2(-1, -1))
    imgui.ScrollMouse()
    lastOpenShelves = HandleListNavigation(
         math.maxEx(1, math.minEx(lastOpenShelves, #shelves)),
        #shelves,
        function(idx)
            local shelf = shelves[idx]
            if shelf then
                sampSendDialogResponse(lastIDDialog, 1, shelf.samp_line, "")
                imguiWindows.main[0] = false
            end
        end
    )
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

        -- Расчёт ожидаемой выработки по уровню + остаток до доливки
        local per_h, per_24h, per_cycle, hours_left, income_left =
            CalcGpuIncome(shelf.level, shelf.percentage, settings.main.fillFrom, currentHouseBonusPercent)

        -- Собираем суффикс по настройкам
        local parts = {}

        if inc.showPerHour  then table.insert(parts, string.format("%.2f/ч",   per_h))     end
        if inc.showPer24h   then table.insert(parts, string.format("%.2f/24ч", per_24h))   end
        if inc.showPerCycle then table.insert(parts, string.format("%.2f/цикл", per_cycle)) end

        local income_suffix = ""
        if #parts > 0 then
            income_suffix = " | Доход: " .. table.concat(parts, " | ")
        end

        -- Доп. блок "до доливки": часы и прибыль, если есть запас > 0
        if inc.showTillThresholdHours then -- and hours_left > 0
            local hh = math.floor(hours_left)
            local mm = math.floor((hours_left - hh) * 60 + 0.5)
            income_suffix = income_suffix .. string.format(" | До %s: %dч:%02dм",
                shelf.percentage > settings.main.fillFrom and "доливки" or "заливки", hh, mm)
        end
        if inc.showTillThresholdProfit then -- and hours_left > 0
            income_suffix = income_suffix .. string.format(" | Принесет: %.2f %s", income_left, shelf.currency)
        end

        -- Итоговая строка
        local _text = ""
        if shelf.profit2 then
            _text = string.format(
                "№%d Ур.%d {%s}%s {%s}%.6f %s | %.6f %s {%s}%.1f%%%s",
                shelf.shelf_number,
                shelf.level,
                gpu_color, shelf.status,
                profit_color, shelf.profit, shelf.currency, shelf.profit2, shelf.currency2,
                cooling_color, shelf.percentage,
                income_suffix
            )
        else
            _text = string.format(
                "№%d Ур.%d {%s}%s {%s}%.6f %s {%s}%.1f%%%s",
                shelf.shelf_number,
                shelf.level,
                gpu_color, shelf.status,
                profit_color, shelf.profit, shelf.currency,
                cooling_color, shelf.percentage,
                income_suffix
            )
        end

        if imgui.SelectableEx(i, _text, lastOpenShelves == i, imgui.SelectableFlags.SpanAllColumns) and IsClick() then
            lastOpenShelves = i
            sampSendDialogResponse(lastIDDialog, 1, shelf.samp_line, "")
            imguiWindows.main[0] = false
        end
    end
    imgui.EndChild()
end

-- --------------------------------------------------------
--                           Extension
-- --------------------------------------------------------

function IsClick()
    return not ui_state.swipe.is_gesture
end

function imgui.MoveOnTitleBar()
    if not settings.style.swipeScroll then return end

    local io = imgui.GetIO()
    local win_pos = imgui.GetWindowPos()
    local win_sz  = imgui.GetWindowSize()

    local grab_height = ScaleUI(28)
    local grab_offset = 6

    -- Новый ЛКМ-клик -> сбрасываем информацию о свайпе
    if io.MouseClicked[0] then
        ui_state.swipe.is_gesture = false
    end

    -- Если во время зажатой ЛКМ мышь ушла дальше порога - это свайп
    if io.MouseDown[0] then
        local drag_vec = io.MouseDragMaxDistanceAbs[0]
        if drag_vec.x > ui_state.swipe.DRAG_THRESHOLD or drag_vec.y > ui_state.swipe.DRAG_THRESHOLD then
            ui_state.swipe.is_gesture = true
        end
    end

    local mouse_over_grab =
        imgui.IsWindowHovered() and
        io.MousePos.x >= win_pos.x and
        io.MousePos.x <= win_pos.x + win_sz.x and
        io.MousePos.y >= win_pos.y + grab_offset and
        io.MousePos.y <= win_pos.y + grab_offset + grab_height

    if mouse_over_grab and io.MouseClicked[0] then
        ui_state.drag.active = true
        ui_state.drag.mx, ui_state.drag.my = io.MousePos.x, io.MousePos.y

        -- стартовая позиция окна - либо текущая, либо последняя сохранённая
        ui_state.drag.wx = windowPos and windowPos.x or win_pos.x
        ui_state.drag.wy = windowPos and windowPos.y or win_pos.y
    end

    if ui_state.drag.active then
        if not io.MouseDown[0] then
            ui_state.drag.active = false
        else
            local dx = io.MousePos.x - ui_state.drag.mx
            local dy = io.MousePos.y - ui_state.drag.my

            -- обновляем желаемую позицию окна; применится в следующем кадре через SetNextWindowPos
            windowPos = imgui.ImVec2(ui_state.drag.wx + dx, ui_state.drag.wy + dy)
        end
    end
end

function imgui.ScrollMouse()
    if not settings.style.swipeScroll then return end

    local io = imgui.GetIO()
    -- Ховер именно по дочернему окну
    local hovered = imgui.IsWindowHovered()

    -- Нажали ЛКМ над списком - начинаем свайп
    if hovered and io.MouseClicked[0] then
        ui_state.swipe.active = true
    end

    -- Отпустили ЛКМ - заканчиваем свайп
    if not io.MouseDown[0] then
        ui_state.swipe.active = false
    end

    -- Если свайп активен - крутим скролл по delta мыши
    if ui_state.swipe.active then
        local current = imgui.GetScrollY()
        local maxy    = imgui.GetScrollMaxY()

        local newY = current - io.MouseDelta.y

        -- Кламп по диапазону скролла
        if newY < 0 then newY = 0 end
        if newY > maxy then newY = maxy end

        imgui.SetScrollY(newY)
    end
end

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
    local _clearLabel = label:gsub("##.*$", "")
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

function imgui.SelectableEx(id, label, selected, flags, imVecSize)
    if imgui.Selectable("##"..id.."-"..label, selected, flags, imVecSize) then
        return true
    end
    imgui.SameLine()
    imgui.SetCursorPosX(imgui.GetCursorPosX() + imgui.GetStyle().ItemInnerSpacing.x)
    imgui.TextColoredRGB(label)
end

function imgui.ClickableText(text, url)
    -- Цвет ссылки
    local linkColor = imgui.ImVec4(0.4, 0.7, 1.0, 1.0)
    local hoverColor = imgui.ImVec4(0.6, 0.85, 1.0, 1.0)

    local isHovered = false

    -- Определяем цвет в зависимости от состояния
    imgui.PushStyleColor(imgui.Col.Text, linkColor)

    -- Добавляем иконку ссылки перед текстом
    imgui.Text(text)

    isHovered = imgui.IsItemHovered()

    if isHovered then
        imgui.SetMouseCursor(imgui.MouseCursor.Hand)

        -- Подчёркивание
        local min = imgui.GetItemRectMin()
        local max = imgui.GetItemRectMax()
        imgui.GetWindowDrawList():AddLine(
            imgui.ImVec2(min.x, max.y),
            imgui.ImVec2(max.x, max.y),
            imgui.GetColorU32Vec4(hoverColor),
            1.0
        )

        imgui.PopStyleColor(1)

        -- Всплывающая подсказка с URL
        if url then
            imgui.SetTooltip(u8"Нажмите, чтобы открыть:\n" .. url)
        else
            imgui.SetTooltip(u8"Нажмите для перехода")
        end
    else
        imgui.PopStyleColor(1)
    end

    if imgui.IsItemClicked() then
        return true
    end
    return false
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
    if imgui.IsInitialized() then
        imgui.SwitchContext()
    end
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

    colors[clr.Tab]                    = colors[clr.WindowBg]
    colors[clr.TabHovered]             = colors[clr.ButtonHovered]
    colors[clr.TabActive]              = colors[clr.FrameBg]
end
