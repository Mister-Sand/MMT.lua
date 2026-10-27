-- =====================================================================================================================
--                                                          Header
-- =====================================================================================================================

script_authors('Sand')
script_name('MMT | Mining Tool')
script_description('Mining assistant TG: @Mister_Sand')
script_version("2.5")

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
   not jsonSuccess      or not lfsSuccess       or not faSuccess     or
   not ffiSuccess then
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

-- На ПК относительный путь считается от папки игры, а не от moonloader, поэтому
-- раньше данные лежали в <папка игры>\config\MMT CFGs. Теперь, как у остальных
-- скриптов, - в moonloader\config\MMT CFGs (перенос: Storage.MigrateLegacyConfig).
local folderConfig = 'config'..SEPORATORPATCH
if not ISMONETLOADER then
    folderConfig = getWorkingDirectory()..SEPORATORPATCH..folderConfig
end
local PATCHCONFIG = folderConfig..'MMT CFGs'..SEPORATORPATCH

-- === Логи / статистика заточки видеокарт ===
local IMPROVE_LOGS_DIR   = PATCHCONFIG .. 'logs' .. SEPORATORPATCH     -- папка для текстовых логов
local IMPROVE_STATS_FILE = PATCHCONFIG .. 'ImproveStats.json'          -- файл со сводной статистикой
local COLLECT_STATS_FILE = PATCHCONFIG .. 'CollectStats.json'          -- лог сбора криптовалюты по датам / домам


local GREENHOUSE_STATS_FILE = PATCHCONFIG .. 'GreenhouseStats.json'   -- лог сбора с теплиц по датам
local MINER_STATS_FILE = PATCHCONFIG .. 'MinerStats.json'             -- лог сбора с майнера по датам
local CARD_LEVELS_FILE = PATCHCONFIG .. 'CardLevels.json'             -- запомненные уровни видеокарт по слотам

local COLORS = {
    WHITE = "FFFFFF",
    RED = "FF3333",
    YELLOW = "FFE133",
    GREEN = "33FF33",
}

-- Типы сообщений скрипта
local TYPECHATMESSAGES = {
    SUCCESS = 1,
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

function math.maxEx(a, b)
    return a > b and a or b
end

function math.minEx(a, b)
    return a < b and a or b
end

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
        -- С какой накопленной крипты подсвечивать дом красным (хранилище скоро переполнится)
        maxCollectAlert = 11.0,
        -- Типы сообщений в чат игры
        typeChatMessage = {
            messages = true,
            debug    = false,
        },
        -- Черный список домов, которые нужно скрыть
        blackListHouses = {},
        maxBankAmount = 60000000,
        -- Пополнять банк до целевой суммы (если выключено - до максимума диалога)
        bankFillToTarget = false,
        bankTargetAmount = 30000000,
        -- Закрывать ли на ESC
        closeOnESC = true,
        -- Перемещаться стрелками
        arrowsMove = true,
        -- Скрывать текст полученной крипты
        hideMessagesCollect = true,
    -- Общая сводка в чат по завершению сбора (уровни видеокарт, суммы, время)
    showCollectSummary = true,
    -- Прятать окно скрипта на время сбора, запущенного командой /mmtflash
    hideWindowOnFlashCmd = false,
        -- автозаливка
        autoFillEnabled = false,
        -- автоматически включать видеокарты после сбора
        autoEnableCards = false,
        -- Панель статуса
        showStatusPanel = false,
        -- Напоминание, если давно не было сбора крипты (в минутах, 0 = выкл)
        collectNotifyMinutes = 0,
        collectLogsView = "list",
        collectLogsPeriod = 7,
        collectLogMaxItemsPerHouseDay = 300,
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
    farmer = {
        -- Обновлять содержимое склада при открытии меню фермера
        refreshOnOpen = true,
        -- Автосбор ресурсов при открытии меню фермера
        autoTake = false,
        -- Автопополнение воды при открытии меню фермера
        autoFill = false,
        -- Заливать воду фермеру не выше этого уровня (максимум - Farmer.WATER_MAX)
        fillTarget = 400,
        -- Пауза перед ответом на диалог (мс)
        actionDelay = 150,
        -- Таймаут ожидания диалога (сек)
        timeout = 10,
        -- Интервал опроса ожидания (мс)
        waitInterval = 10,
        -- Удержание клавиши Alt при повторном открытии меню (мс)
        altHoldTime = 100,
        -- Пауза после забора ресурса перед нажатием Alt (мс)
        afterTakeDelay = 400,
        -- Хранить логи теплиц за N дней (0 = без ограничения)
        logMaxDays = 60,
        -- Период отображения логов теплиц (дней, 0 = всё время)
        logsPeriod = 7,
        -- Вид логов теплиц: "table" | "graph"
        logsView = "table",
        -- Напомнить в Telegram, если не было сбора с теплиц (в минутах, 0 = выкл)
        notifyMinutes = 0,
    },
    miner = {
        -- Обновлять содержимое склада при открытии меню майнера
        refreshOnOpen = true,
        -- Автосбор тёмной материи при открытии меню майнера
        autoTake = false,
        -- Автозарядка майнера при открытии меню
        autoFill = false,
        -- Заряжать майнера не выше этого уровня (максимум - Miner.CHARGE_MAX)
        fillTarget = 10,
        -- Пауза перед ответом на диалог (мс)
        actionDelay = 150,
        -- Таймаут ожидания диалога (сек)
        timeout = 10,
        -- Интервал опроса ожидания (мс)
        waitInterval = 10,
        -- Удержание клавиши Alt при повторном открытии меню (мс)
        altHoldTime = 100,
        -- Пауза после забора ресурса перед нажатием Alt (мс)
        afterTakeDelay = 400,
        -- Хранить логи майнера за N дней (0 = без ограничения)
        logMaxDays = 60,
        -- Период отображения логов майнера (дней, 0 = всё время)
        logsPeriod = 7,
        -- Вид логов майнера: "table" | "graph"
        logsView = "table",
        -- Напомнить в Telegram, если не было сбора с майнера (в минутах, 0 = выкл)
        notifyMinutes = 0,
    },
    mirage = {
        -- Забирать монеты сразу при открытии сарая миража
        autoTake = false,
        -- Не открывать окно скрипта, когда монеты забирает автосбор
        hideOnAutoTake = false,
        -- В каком радиусе показывать сараи в списке "Сараи рядом", метров
        nearRadius = 50,
        -- Напомнить в Telegram, если сарай давно не собирали (в минутах, 0 = выкл)
        notifyMinutes = 0,
        -- Хранить логи сарая за N дней (0 = без ограничения)
        logMaxDays = 60,
        -- Период отображения логов (дней, 0 = всё время)
        logsPeriod = 7,
        -- Вид логов: "table" | "graph"
        logsView = "table",
    },
    notifications = {
        -- Версия формата: до 2 была одна общая галочка Telegram
        version = 2,
        -- Через какого бота: 1 = свой бот, 2 = MCR Notification
        methodBot = 1,
        -- Свой бот: токен и ID чата
        botToken = "",
        chatId = "",
        -- ID пользователя в боте MCR Notification
        mcrChatId = "",
        -- Ключ MCR (пусто = взять из MCR ПК или MLoader)
        mcrKey = "",
        -- Напоминания в Telegram по событиям
        tg = {
            crypto = false,
            greenhouse = false,
            miner = false,
            mirage = false,
        },
        -- Напоминания в игре (менеджер уведомлений, без него - сообщение в чат)
        game = {
            crypto = true,
            greenhouse = true,
            miner = true,
            mirage = true,
        },
        -- [вид] = время сбора, о котором уже напомнили (повторно не шлём)
        sent = {},
    },
    cloud = {
        -- Отправлять сборы крипты, теплиц и майнера на сервер MCR (нужен ключ MCR)
        sendCollects = true,
        -- Какой лог показывать в разделе "Логи": "local" | "cloud"
        logsSource = "local",
        -- Период облачного лога, дней
        period = 7,
    },
    improve = {
        -- true: улучшать все карты; false: только выбранную
        menuAll = true,
        -- 1 = Обычные, 2 = Arizona
        typeCards = 1,
        -- Новый стиль CEF - основной режим инвентаря
        inventoryMode = 2,
        -- 1 = Последовательное (сначала низкий уровень), 2 = Поочередное (как на экране)
        mode = 1,
        -- Целевой уровень (не улучшать если уже >= этого уровня)
        maxLevel = 2,
        -- Проверять наличие смазки при старте заточки (через /stats)
        checkOilsOnStart = true,
        -- Сколько часов считать запомненный уровень видеокарты актуальным (0 = бессрочно)
        levelCacheHours = 0,
        -- Сколько повторов делать, если слот не ответил при проверке уровня
        probeRetries = 2,
        -- Не переоткрывать /invent между картами: при проверке уровней и при заточке
        fastProbe = true,
        -- Брать уровни карт из пакетов инвентаря, а не из диалога по каждой карте
        packetLevels = true,
    },
    deley = {
        timeoutDialog = 10,
        waitInterval = 10,
        timeoutShelf = 10,
        -- Ждать перед отправкой ответа на диалог
        waitRun = 0,
        -- Повторов, если сервер не ответил на открытие полки
        shelfRetries = 2,
        -- Повторов дома, который не отработал целиком
        houseRetries = 1,
        -- Пуза после получения результата
        improve_waitResult = 500,
        -- Пуза перед нажатием на видеокарту в инвентаре
        improve_waitTryClick = 500,
        -- Пауза после /invent, пока инвентарь открывается
        improve_waitInventory = 1500,
        -- Интервал автоповтора CEF-клика на шаге подтверждения
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
        -- Цвета интерфейса
        mainColor   = { r = 0.25, g = 0.45, b = 0.28, a = 1.00},
        textColor   = { r = 0.80, g = 0.85, b = 0.80, a = 1.00},
        bgColor     = { r = 0.10, g = 0.15, b = 0.14, a = 0.98},
        accentColor = { r = 0.27, g = 0.25, b = 0.45, a = 1.00},
        -- Цвет префикса скрипта в чате
        chatColor   = { r = 0.55, g = 0.75, b = 0.57, a = 1.00},
        -- Смысловые цвета текста в окне
        okColor     = { r = 0.20, g = 1.00, b = 0.20, a = 1.00},
        warnColor   = { r = 1.00, g = 0.8824, b = 0.20, a = 1.00},
        badColor    = { r = 1.00, g = 0.20, b = 0.20, a = 1.00},
        -- Полосы заполнения: свободно / наполовину / почти полная
        barFreeColor = { r = 0.34, g = 0.56, b = 0.40, a = 0.85},
        barHalfColor = { r = 0.70, g = 0.60, b = 0.32, a = 0.85},
        barFullColor = { r = 0.68, g = 0.36, b = 0.34, a = 0.85},
        -- Столбики графиков в логах: обычный / выбранный / подложка
        graphBarColor    = { r = 0.34, g = 0.70, b = 0.42, a = 1.00},
        graphActiveColor = { r = 0.78, g = 0.68, b = 0.32, a = 1.00},
        graphBgColor     = { r = 0.16, g = 0.20, b = 0.18, a = 1.00},
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

-- Активный раздел (режим) верхнего переключателя
local activeMode = "cards"  -- "cards" | "farmer" | "miner" | "mirage"
local MODE_ORDER = { "cards", "farmer", "miner", "mirage" }
local MODE_LABELS = { cards = "Видеокарты", farmer = "Фермер", miner = "Майнер", mirage = "Сарай миража" }

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
    },
    collectLogs = {
        selectedDay = nil,
    },
    farmerLogs = {
        selectedDay = nil,
    },
    minerLogs = {
        selectedDay = nil,
    },
    mirageLogs = {
        selectedDay = nil,
    },
    -- цвет меняли в этом кадре, сохранить настройки когда отпустят элемент
    colorsDirty = false,
}

-- --------------------------------------------------------
--                           State
-- --------------------------------------------------------

local processInteractingThread

local idDialogs = {
    selectVideoCard = 0,
    selectVideoCardItemFlash = 0,
    selectHouse = 0,
    mobileImproveStatus = 24680,
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
    -- Счётчик всех показанных диалогов и номер последнего списка полок.
    -- По ним видно, открыт ли список сейчас и прислал ли сервер его заново
    dialogSerial = 0,
    shelfListSerial = 0,
    -- Сколько полок пропущено из-за зависших диалогов
    shelvesSkipped = 0,
    -- Список полок в очереди
    queueShelves = {},
    -- Прогресс домов банка
    progressHousesBank = 0,
    -- Список домов банка в очереди
    queueHousesBank = {},
    -- Идентификатор текущего дома (номер) и валюта текущего take
    currentHouseId = nil,
    takeCurrency = nil,
    fillLiquidType = nil,
    fillLiquidLabel = nil,
    fillLiquidBefore = 0,
    fillLiquidAfter = 0,
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
local collectLogSave = { dirty = false, lastAt = 0, minInterval = 2 }
local collectReminder = {
    lastTickAt = 0,
    game = {},               -- [событие] = { notifiedAt, retryAt, pending } - напоминания в игре
    managerEnsurePending = false,
    managerDownloadPending = false,
    managerStatusMessage = "",
}
local collectReminderAction = nil

-- Доступные полки
-- --------------------------------------------------------
--                           Farmer (теплицы)
-- --------------------------------------------------------

-- Состояние работы с фермером/теплицами
local farmer = {
    active = false,
    mode = nil,                -- "take" | "fill" | "both"
    dialogSeq = 0,             -- счётчик пришедших диалогов фермера
    menuOpen = false,          -- открыто ли (скрытое) меню фермера на сервере
    last = { kind = nil, id = nil, style = nil },
    menu = { id = nil, status = "", storeNow = 0, storeMax = 0, wareLine = nil },
    ware = { id = nil, items = {}, putLine = nil, waterLine = nil, waterNow = 0, waterMax = 0 },
    input = {},
    collected = {},            -- [имя] = количество (за текущую сессию)
    waterSpent = 0,
    invLiquid = 0,             -- жидкость (вода) в инвентаре игрока
    statusText = "",
    logs = {},
}

-- Лог сбора с теплиц (в одну кучу за день)
local greenhouseLog = { days = {}, dirty = false, lastSaveAt = 0 }

-- --------------------------------------------------------
--                           Miner (майнер)
-- --------------------------------------------------------

-- Состояние работы с майнером
local miner = {
    active = false,
    mode = nil,                -- "take" | "fill" | "both" | "check"
    dialogSeq = 0,             -- счётчик пришедших диалогов майнера
    menuOpen = false,          -- открыто ли (скрытое) меню майнера на сервере
    last = { kind = nil, id = nil, style = nil },
    menu = { id = nil, status = "", storeNow = 0, storeMax = 0, wareLine = nil, statusLine = nil },
    ware = { id = nil, items = {}, putLine = nil, chargeName = nil, chargeLine = nil, chargeInWare = 0 },
    input = {},
    skipLines = {},            -- строки склада, которые забирать не нужно (номер строки -> true)
    collected = {},            -- [имя] = количество (за текущую сессию)
    chargeSpent = 0,           -- сколько зарядки залито за сессию
    chargeNow = 0,             -- зарядка у майнера (из диалога "Положить на склад")
    chargeMax = 0,
    invCharge = 0,             -- зарядка майнера в инвентаре игрока
    statusText = "",
    logs = {},
}

-- Лог сбора с майнера (в одну кучу за день)
local minerLog = { days = {}, dirty = false, lastSaveAt = 0 }

-- Сарай миража: состояние, лог и функции модуля
local Mirage = {
    st = {
        open = false,              -- окно сарая сейчас открыто на сервере
        dialogId = nil,
        dialogStyle = nil,
        dialogAt = 0,
        house = nil,
        now = 0,                   -- монет в сарае
        max = 10,
        cost = 0,                  -- цена сбора
        pending = nil,             -- забор отправлен, ждём подтверждения
        sheds = {},                -- [дом или id надписи] = { id, house, coins, x, y, z, at }
        shedKeys = {},             -- [id 3D-текста] = ключ сарая в sheds
        sessionCoins = 0,
        sessionSpent = 0,
        sessionCollects = 0,
        statusText = "",
        logs = {},
    },
    log = { days = {}, dirty = false, lastSaveAt = 0, lastCollectAt = 0 },
}

-- Доступные полки
local shelves = {}

local houses = {}
-- Дома с информацией о полках
--[id_house <string>] = { work_vc = <int> количество рабочих видеокарт, max_collect = <int> макс крипты в доме, min_liquid = <number> минимально охлаждайки в доме}
local housesData = {}

local housesBanks = {}

local Storage = {}
local Collect = {}
local Parser = {}
local Draw = {}
local Interacting = {}
local Chat = {}
local UI = {}
local Util = {}
local Farmer = {}
local Miner = {}
local Greenhouse = {}
function Util.EnsureDirectoryExists(path)
    local currentPath = ""
    for folder in string.gmatch(path, "[^/\\]+") do
        currentPath = currentPath .. folder .. "/"
        if not lfs.attributes(currentPath, "mode") then
            lfs.mkdir(currentPath)
        end
    end
end

local lastIDDialog = 0

local lastOpenHouse = 1
local lastOpenShelves = 1

-- --------------------------------------------------------
--                           Improve
-- --------------------------------------------------------
local Improve = {}
Improve.STEP = {
    STOPPED = 0,
    SELECT_CARD = 1, -- выбрать подходящую карту и кликнуть CEF-слот
    CONFIRM = 3,     -- обработать диалоги выбора/подтверждения улучшения
    WAIT_RESULT = 4, -- дождаться результата от сервера
}

local improve = {
    isOn = false,
    step = Improve.STEP.STOPPED,

    -- Кэш видеокарт из CEF-инвентаря
    videoCards   = {},     -- { { slot = <int>, level = <int>, storageUpgrade = <bool> } ... }
    select       = 0,      -- индекс выбранной карты (когда menuAll=false)
    selectSlot   = nil,    -- слот выбранной карты: индекс меняется при пересборке списка
    lastResult   = nil,    -- последний результат заточки для экрана «Процесс»
    currentIndex = 0,      -- индекс карты, которую сейчас точим

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

    -- Режим вида улучшения:
    -- false  = улучшение производительности
    -- true   = увеличение объёма хранения криптовалюты
    useStorageUpgrade = false,

    -- Логи и статистика заточки
    logs = {
        items      = {},   -- { { ts="дата-время", type="INFO", text="...", step=Improve.STEP.SELECT_CARD } ... }
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
        inventoryFresh = false,   -- инвентарь уже открыт, можно кликать без /invent
        inventoryOpen = false,    -- мы открывали инвентарь и ещё не закрывали его
        inventoryBlockedUntil = 0,-- сервер попросил подождать перед следующим /invent
        upgradeFast = false,      -- текущий клик заточки ушёл без /invent
        pktSnapshot = false,      -- весь инвентарь пришёл пакетом (при входе в игру)
        listDirty = false,        -- список карт изменился по пакетам, пересобрать videoCards
        lastClickSlot = nil,      -- слот последнего клика в инвентаре
        lastClickAt = 0,
        upgradeFastFails = 0,     -- сколько раз подряд такой клик не открыл окно
        unknownCount = 0,         -- сколько карт выбранного типа остались без уровня
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
        watchdogMark = '',      -- слепок прогресса проверки для сторожа
        watchdogAt = 0,
        pktLevels = {},         -- уровни карт из пакетов инвентаря: [слот] = { level, cardType, at }
        pktInvAt = 0,           -- когда в последний раз приходил инвентарь пакетом
    },
}

Improve.stepNames = {
    [Improve.STEP.STOPPED] = 'Улучшение выключено',
    [Improve.STEP.SELECT_CARD] = 'Выбор карты и CEF-слота',
    [Improve.STEP.CONFIRM] = 'Подтверждение улучшения',
    [Improve.STEP.WAIT_RESULT] = 'Ожидание результата'
}

function Improve.Say(msg)
    Chat.Add("Улучшение: "..tostring(msg), TYPECHATMESSAGES.SECONDARY)
end

local mobileImproveDialog = {
    lastShowAt = 0,
    suppressUntil = 0,
    closing = false,
    lastText = '',
    wasActive = false,
    -- true, пока скрипт сам открывает/закрывает диалоги: исчезновение статуса
    -- в этот момент не считается нажатием "Остановить"
    scriptBusy = false,
}

-- Запомненные уровни видеокарт: { slots = { ["<slot>"] = { name, level, cardType, storage, at } } }
local cardLevels = { slots = {}, dirty = false, lastSaveAt = 0 }

function Improve.IsMobileStatusDialogActive()
    if type(sampIsDialogActive) ~= 'function' or type(sampGetCurrentDialogId) ~= 'function' then
        return false
    end

    local okActive, active = pcall(sampIsDialogActive)
    if not okActive or not active then return false end

    local okId, currentId = pcall(sampGetCurrentDialogId)
    return okId and tonumber(currentId) == idDialogs.mobileImproveStatus
end

function Improve.CloseMobileStatusDialog(suppressMs)
    if not ISMONETLOADER then return end

    mobileImproveDialog.suppressUntil = os.clock() + ((tonumber(suppressMs or 0) or 0) / 1000)
    if not Improve.IsMobileStatusDialogActive() then return end
    if type(sampCloseCurrentDialogWithButton) ~= 'function' then return end

    mobileImproveDialog.closing = true
    pcall(sampCloseCurrentDialogWithButton, 1)
end

-- Статус-диалог обновляется только пока идёт заточка или проверка уровней.
-- Когда всё закончилось, закрыть его больше некому - делаем это сами.
-- Повтор не чаще раза в 3 секунды: CloseMobileStatusDialog двигает suppressUntil.
function Improve.FinishProbeUI()
    if not ISMONETLOADER then return end
    if improve.isOn or improve.cef.probing then return end
    if not Improve.IsMobileStatusDialogActive() then return end
    if os.clock() < (mobileImproveDialog.suppressUntil or 0) then return end

    mobileImproveDialog.wasActive = false
    Improve.CloseMobileStatusDialog(3000)
end

-- Инвентарь закрывается кликом по несуществующему текстдраву:
-- отдельного CEF-пакета на закрытие у iface 52 нет.
function Improve.CloseInventory()
    if type(sampSendClickTextdraw) ~= 'function' then return end
    pcall(sampSendClickTextdraw, 65535)
    improve.cef.inventoryFresh = false
    improve.cef.inventoryOpen = false
    -- сразу после закрытия сервер не даёт открыть инвентарь снова
    improve.cef.inventoryBlockedUntil = os.clock() + 1.2
end

-- Сервер отвечает "Нельзя так быстро открывать инвентарь": ждём, пока он снова разрешит
function Improve.WaitInventoryCooldown()
    local guard = os.clock() + 6
    while os.clock() < (improve.cef.inventoryBlockedUntil or 0) do
        if os.clock() > guard then break end
        wait(100)
    end
end

-- =====================================================================================================================
--                        Уровни видеокарт из пакетов инвентаря
-- =====================================================================================================================
-- При входе в игру и при каждом открытии инвентаря сервер присылает весь инвентарь
-- набором пакетов, а дальше шлёт точечные обновления слотов. У видеокарты там уже есть
-- уровень: unic_id = уровень, text = "N lvl", plus_btc/plus_asc = доход в час.
-- Значит уровень можно взять из пакета и не открывать диалог по каждой карте.
local CEF_CARD_ITEMS = { [1810] = 1, [5995] = 2 }

function Improve.UsePacketLevels()
    if type(settings) ~= 'table' or type(settings.improve) ~= 'table' then return false end
    return settings.improve.packetLevels ~= false
end

-- Уровень карты из данных слота: unic_id, потом подпись "N lvl", потом доход в час
function Improve.LevelFromSlotData(itemData)
    local _level = tonumber(itemData.unic_id)

    if not _level and type(itemData.text) == 'string' then
        _level = tonumber(itemData.text:match('^%s*(%d+)%s*lvl%s*$'))
    end

    if not _level then
        local _income = tonumber(itemData.plus_btc) or tonumber(itemData.plus_asc)
        if _income then
            for _lvl, _hourly in pairs(GPU_HOURLY_BY_LEVEL) do
                if math.abs(_hourly - _income) < 0.0005 then
                    _level = _lvl
                    break
                end
            end
        end
    end

    if not _level or _level < 1 or _level > 10 then return nil end
    return _level
end

-- Уровень слота, который пришёл пакетом; nil, если такого слота не видели
function Improve.PacketLevelForSlot(slot, cardType)
    local _entry = improve.cef.pktLevels[tonumber(slot) or 0]
    if type(_entry) ~= 'table' then return nil end
    if cardType ~= nil and (tonumber(_entry.cardType) or 0) ~= (tonumber(cardType) or 0) then
        return nil
    end
    return tonumber(_entry.level)
end

function Improve.ForgetPacketLevels()
    improve.cef.pktLevels = {}
    improve.cef.pktInvAt = 0
end

-- Запомнить уровень из пакета и сразу обновить карточку в списке
function Improve.ApplyPacketCardSlot(slot, itemId, itemData)
    local _cardType = CEF_CARD_ITEMS[itemId]
    if not _cardType then return false end

    local _level = Improve.LevelFromSlotData(itemData)
    if not _level then return false end

    improve.cef.pktLevels[slot] = { level = _level, cardType = _cardType, at = os.time() }

    for _, c in ipairs(improve.cef.cards or {}) do
        if (tonumber(c.slot) or 0) == slot and (tonumber(c.cardType) or 0) == _cardType then
            if (not c.levelKnown) or (tonumber(c.level) or 0) ~= _level then
                Improve.LogAdd('INFO', string.format('Пакет инвентаря: слот %d - уровень %d.', slot, _level))
            end
            c.level = _level
            c.levelKnown = true
            c.levelGuessed = false
            c.probeFailed = false
            Improve.CardCacheSet(c.slot, c.name, _level, _cardType, c.storageUpgrade)
            return true
        end
    end

    -- карты ещё нет в списке (переложили из хранилища, список не обновлялся),
    -- но кэш всё равно переписываем: у всех карт одно имя, и по нему не понять,
    -- что в слоте лежит уже другая карта. Иначе после перезапуска всплывёт старый уровень
    local _cached = cardLevels.slots[tostring(slot)]
    local _name, _storage = (_cardType == 2) and 'Arizona Video Card' or 'Видеокарта', false
    if type(_cached) == 'table' and (tonumber(_cached.cardType) or 0) == _cardType then
        _name, _storage = _cached.name or _name, _cached.storage == true
    end
    Improve.CardCacheSet(slot, _name, _level, _cardType, _storage)

    -- инвентарь известен целиком (пришёл при входе) или список уже собран через /stats:
    -- новая карта сразу попадает в список, /stats для этого не нужен
    if improve.cef.pktSnapshot or #(improve.cef.cards or {}) > 0 then
        Improve.AddCefCardSlot(slot, _name, _storage, _cardType)
        improve.cef.listDirty = true
    end

    return true
end

-- В слоте теперь не видеокарта: запомненный уровень больше ни о чём не говорит,
-- а сама карта ушла из инвентаря или переехала в другой слот
function Improve.ForgetPacketSlot(slot)
    improve.cef.pktLevels[slot] = nil
    if cardLevels.slots[tostring(slot)] ~= nil then
        Improve.CardCacheForget(slot)
    end

    local _cards = improve.cef.cards or {}
    for i = #_cards, 1, -1 do
        if (tonumber(_cards[i].slot) or 0) == slot then
            table.remove(_cards, i)
            improve.cef.listDirty = true
        end
    end
end

-- Список карт на экране пересобираем, когда это ничему не мешает:
-- посреди заточки или проверки индексы карт должны оставаться прежними
function Improve.FlushCardListDirty()
    if not improve.cef.listDirty or improve.cef.probing or improve.oils.busy then return end
    if improve.isOn and improve.step ~= Improve.STEP.SELECT_CARD then return end
    improve.cef.listDirty = false
    Improve.SyncVideoCardsFromCef()
end

-- Последний слот, по которому кликнули в инвентаре: к нему относится окно
-- улучшения или «Информация о предмете», которое придёт следом
function Improve.NoteClickSlot(slot)
    slot = tonumber(slot)
    if not slot or slot < 0 then return end
    improve.cef.lastClickSlot = slot
    improve.cef.lastClickAt = os.clock()
end

-- Исходящий CEF-пакет: ПК шлёт тип 18 строкой, мобильный клиент - 0x3F с iface
function Improve.CaptureSentClick(id, bs)
    if id ~= 220 or not bs then return end

    pcall(raknetBitStreamResetReadPointer, bs)
    local _ok, _payload, _mobile = pcall(function()
        raknetBitStreamIgnoreBits(bs, 8)
        local _type = raknetBitStreamReadInt8(bs)
        if _type == 18 then
            local _len = raknetBitStreamReadInt16(bs)
            if not _len or _len <= 0 or _len > 4096 then return nil end
            if not Util.BitStreamHasBytes(bs, 4, _len) then return nil end
            return raknetBitStreamReadString(bs, _len), false
        end
        if _type == 0x3F then
            local _iface = raknetBitStreamReadInt8(bs)
            raknetBitStreamIgnoreBits(bs, 64)
            local _len = raknetBitStreamReadInt16(bs)
            if _iface ~= 52 or not _len or _len <= 0 or _len > 4096 then return nil end
            if not Util.BitStreamHasBytes(bs, 13, _len) then return nil end
            return raknetBitStreamReadString(bs, _len), true
        end
        return nil
    end)
    pcall(raknetBitStreamResetReadPointer, bs)
    if not _ok or type(_payload) ~= 'string' then return end

    if not _mobile then
        if _payload:sub(1, 14) ~= 'clickOnButton|' and _payload:sub(1, 18) ~= 'rightClickOnBlock|' then return end
    elseif _payload:find('"from"', 1, true) then
        return
    end

    local _slot = _payload:match('"slot":%s*(%d+)')
    local _itemType = tonumber(_payload:match('"type":%s*(%d+)') or 1)
    if _slot and _itemType == 1 then
        Improve.NoteClickSlot(_slot)
    end
end

-- Тип карты в слоте по тому, что о нём уже известно
function Improve.KnownCardTypeForSlot(slot)
    for _, c in ipairs(improve.cef.cards or {}) do
        if (tonumber(c.slot) or 0) == slot then return tonumber(c.cardType) end
    end
    local _pkt = improve.cef.pktLevels[slot]
    if type(_pkt) == 'table' then return tonumber(_pkt.cardType) end
    local _cached = cardLevels.slots[tostring(slot)]
    if type(_cached) == 'table' then return tonumber(_cached.cardType) end
    return nil
end

-- Уровень карты из окна, которое игрок открыл сам: выбор вида улучшения
-- ("до N уровня" = сейчас N-1) или «Информация о предмете» ("Уровень производительности: N из 10")
function Improve.CaptureCardDialog(title, text)
    if improve.cef.probing then return end

    local _slot = tonumber(improve.cef.lastClickSlot)
    if not _slot or (os.clock() - (improve.cef.lastClickAt or 0)) > 5 then return end

    local _title = Farmer.stripColors(tostring(title or ''))
    local _text = Farmer.stripColors(tostring(text or ''))
    local _level, _storage, _cardType

    if _title:find('Выберите вид улучшения для видеокарты', 1, true) then
        _level = Improve.ParseCardLevelFromDialog(_text)
        _storage = not _text:find('Увеличить объем хранения криптовалюты на видео-карте', 1, true)
        _cardType = Improve.KnownCardTypeForSlot(_slot)
    elseif _title:find('Информация о предмете', 1, true) then
        local _item = _text:match('Предмет:%s*([^\r\n]+)') or ''
        if _item:find('Arizona Video Card', 1, true) then
            _cardType = 2
        elseif _item:find('Видеокарта', 1, true) then
            _cardType = 1
        end
        _level = tonumber(_text:match('Уровень производительности:%s*(%d+)%s*из%s*10'))
    else
        return
    end

    if not _level or not _cardType or _level < 1 or _level > 10 then return end
    improve.cef.lastClickSlot = nil

    improve.cef.pktLevels[_slot] = { level = _level, cardType = _cardType, at = os.time() }

    for _, c in ipairs(improve.cef.cards or {}) do
        if (tonumber(c.slot) or 0) == _slot and (tonumber(c.cardType) or 0) == _cardType then
            if (not c.levelKnown) or (tonumber(c.level) or 0) ~= _level then
                Improve.LogAdd('INFO', string.format('Окно видеокарты: слот %d - уровень %d.', _slot, _level))
            end
            Improve.UpdateCefCardLevel(_slot, _level, _storage)
            c.levelGuessed = false
            improve.cef.listDirty = true
            return
        end
    end

    local _cached = cardLevels.slots[tostring(_slot)]
    local _name = (_cardType == 2) and 'Arizona Video Card' or 'Видеокарта'
    if _storage == nil then _storage = false end
    if type(_cached) == 'table' and (tonumber(_cached.cardType) or 0) == _cardType then
        _name = _cached.name or _name
        if _storage == false then _storage = _cached.storage == true end
    end
    Improve.CardCacheSet(_slot, _name, _level, _cardType, _storage)
end

-- Разбор страницы инвентаря: {"action":0|2,"data":{"type":1,"items":[...]}}
function Improve.ApplyPacketInventoryPage(page)
    if type(page) ~= 'table' then return end

    local _body = (type(page.data) == 'table') and page.data or page
    if type(_body.items) ~= 'table' then return end
    if (tonumber(_body.type) or 1) ~= 1 then return end

    local _action = tonumber(page.action) or tonumber(_body.action)
    if _action ~= nil and _action ~= 0 and _action ~= 2 then return end

    -- action 0 по основному инвентарю приходит при входе в игру: весь инвентарь
    -- кусками по диапазонам слотов, пустые слоты - без поля item
    if _action == 0 then improve.cef.pktSnapshot = true end

    for _, itemData in ipairs(_body.items) do
        if type(itemData) == 'table' then
            local _slot = tonumber(itemData.slot)
            local _item = tonumber(itemData.item)
            if _slot and _item then
                if not CEF_CARD_ITEMS[_item] then
                    Improve.ForgetPacketSlot(_slot)
                else
                    Improve.ApplyPacketCardSlot(_slot, _item, itemData)
                end
            elseif _slot and itemData.item == nil then
                -- слот опустел
                Improve.ForgetPacketSlot(_slot)
            end
        end
    end

    improve.cef.pktInvAt = os.clock()
end

-- Чтение CEF-пакета: ПК шлёт тип 17, мобильный клиент - тип 84 с iface/sub
function Improve.ReadCefPacket(id, bs)
    if id ~= 220 or not bs then return nil end

    pcall(raknetBitStreamResetReadPointer, bs)

    local _ok, _iface, _sub, _payload = pcall(function()
        raknetBitStreamIgnoreBits(bs, 8)
        local _type = raknetBitStreamReadInt8(bs)

        if _type == 17 then
            raknetBitStreamIgnoreBits(bs, 32)
            local _len = raknetBitStreamReadInt16(bs)
            local _encoded = raknetBitStreamReadInt8(bs)
            if not _len or _len < 0 or _encoded == nil then return nil end
            if _encoded ~= 0 then
                -- сжатая строка короче _len, поэтому проверяем только, что данные есть
                if not Util.BitStreamHasBytes(bs, 9, 1) then return nil end
                return nil, nil, raknetBitStreamDecodeString(bs, _len + _encoded)
            end
            if not Util.BitStreamHasBytes(bs, 9, _len) then return nil end
            return nil, nil, raknetBitStreamReadString(bs, _len)
        end

        if _type == 84 then
            local _ifaceId = raknetBitStreamReadInt8(bs)
            local _subId = raknetBitStreamReadInt8(bs)
            local _len = raknetBitStreamReadInt16(bs)
            local _encoded = raknetBitStreamReadInt8(bs)
            if not _len or _len < 0 or _encoded == nil then return nil end
            if _encoded ~= 0 then
                if not Util.BitStreamHasBytes(bs, 7, 1) then return nil end
                return _ifaceId, _subId, raknetBitStreamDecodeString(bs, _len + 1)
            end
            if not Util.BitStreamHasBytes(bs, 7, _len) then return nil end
            return _ifaceId, _subId, raknetBitStreamReadString(bs, _len)
        end

        return nil
    end)

    pcall(raknetBitStreamResetReadPointer, bs)

    if not _ok or type(_payload) ~= 'string' or _payload == '' then return nil end
    return _iface, _sub, _payload
end

-- Ловим пакеты инвентаря игрока и достаём из них уровни видеокарт
function Improve.CaptureInventoryPacket(id, bs)
    if not Improve.UsePacketLevels() then return end

    local _iface, _sub, _payload = Improve.ReadCefPacket(id, bs)
    if not _payload then return end

    -- на мобильном инвентарь приходит по iface 52: sub 0 - весь, sub 2 - обновление
    if _iface ~= nil and (_iface ~= 52 or (_sub ~= 0 and _sub ~= 2)) then return end

    -- дешёвый фильтр: лавка (13 и 28) и прочие интерфейсы нам не нужны
    if not _payload:find('"items"', 1, true) then return end
    if _payload:find('"type":13', 1, true) or _payload:find('"type":28', 1, true) then return end

    local _text = _payload:gsub('%z', '')
    local _first = _text:sub(1, 1)
    if _first ~= '{' and _first ~= '[' then
        _text = _text:match('(%b[])') or _text:match('(%b{})') or ''
    end
    if _text == '' then return end

    local _okJson, _data = pcall(json.decode, _text)
    if not _okJson or type(_data) ~= 'table' then return end

    if type(_data.data) == 'table' or type(_data.items) == 'table' then
        Improve.ApplyPacketInventoryPage(_data)
        return
    end

    for _, page in ipairs(_data) do
        Improve.ApplyPacketInventoryPage(page)
    end
end

addEventHandler('onReceivePacket', function(id, bs)
    pcall(Improve.CaptureInventoryPacket, id, bs)
end)

addEventHandler('onSendPacket', function(id, bs)
    pcall(Improve.CaptureSentClick, id, bs)
end)

-- Попросить сервер прислать инвентарь целиком: один такой запрос заменяет
-- поштучную проверку карт. Вызывать только из потока - внутри есть wait
function Improve.RequestInventoryDump(timeoutSec)
    if not Improve.UsePacketLevels() then return false end

    local _mark = improve.cef.pktInvAt or 0

    -- на мобильном открытый диалог статуса мешает открыть инвентарь
    if ISMONETLOADER then
        Improve.CloseMobileStatusDialog(((tonumber(timeoutSec) or 5) * 1000) + 1000)
    end

    if improve.cef.inventoryOpen then
        Improve.CloseInventory()
    end
    Improve.WaitInventoryCooldown()
    improve.cef.inventoryOpen = true

    if ISMONETLOADER then
        Improve.SendCefMobile(52, 0, 4294967295, '""')
    else
        sampSendChat('/invent')
    end

    local _deadline = os.clock() + (tonumber(timeoutSec) or 5)
    local _got = false
    while os.clock() < _deadline do
        wait(50)
        if (improve.cef.pktInvAt or 0) > _mark then
            _got = true
            break
        end
    end

    -- дамп приходит несколькими пакетами подряд, даём дойти остальным страницам
    if _got then wait(400) end

    Improve.CloseInventory()
    return _got
end

-- Завершение проверки уровней: убираем за собой статус и инвентарь.
-- Только когда заточка не идёт - в автоматическом цикле инвентарь ещё нужен.
function Improve.FinishProbe()
    if improve.isOn or improve.cef.probing then return end
    Improve.FinishProbeUI()
    Improve.CloseInventory()
end

-- Проверка уровней крутится в отдельном потоке. Если он оборвётся, probing
-- останется true навсегда: статус будет висеть, а закрыть его будет некому.
-- Поэтому следим за прогрессом и при полном застое сбрасываем состояние.
function Improve.ProbeWatchdogTick()
    if not improve.cef.probing then
        improve.cef.watchdogMark = ''
        return
    end

    local mark = string.format('%s|%s|%s|%s',
        tostring(improve.cef.pendingIndex or 0),
        tostring(improve.cef.pendingSlot or '-'),
        tostring(improve.cef.probeProgress or 0),
        tostring(improve.cef.probeDone))

    local now = os.clock()
    if mark ~= improve.cef.watchdogMark then
        improve.cef.watchdogMark = mark
        improve.cef.watchdogAt = now
        return
    end

    -- запас: полный цикл попыток по одной карте плюс 30 секунд
    local timeoutDialog = tonumber(settings.deley.timeoutDialog) or 10
    local retries = math.maxEx(0, tonumber(settings.improve.probeRetries) or 2)
    local limit = math.maxEx(60, timeoutDialog * (retries + 1) + 30)
    if (now - (improve.cef.watchdogAt or 0)) < limit then return end

    improve.cef.watchdogMark = ''
    -- probeAbort будит поток проверки, если он всё же жив: он выйдет сам
    improve.cef.probeAbort = true
    improve.cef.probeAbortReason = 'проверка зависла'
    improve.cef.probeDone = true
    improve.cef.probing = false
    improve.cef.pendingSlot = nil
    improve.cef.pendingIndex = 0
    mobileImproveDialog.scriptBusy = false

    Improve.LogAdd('WARN', string.format('Проверка уровней зависла (%d сек без прогресса) - состояние сброшено.', math.floor(limit)))
    Improve.Say('Проверка уровней зависла - состояние сброшено.')
    Improve.FinishProbe()
end

function Improve.GetMobileStatusText()
    local lines = {}
    -- ручная проверка уровней идёт при выключенной заточке (improve.isOn = false),
    -- поэтому её состояние показываем отдельно, иначе статус врёт про 'остановлено'
    local probingOnly = improve.cef.probing and not improve.isOn
    local stepName = probingOnly and 'Проверка уровней видеокарт'
        or (Improve.stepNames[improve.step] or '?')
    local statusName = improve.isOn and 'работает'
        or (probingOnly and 'проверка уровней' or 'остановлено')
    table.insert(lines, string.format('Статус: %s', statusName))
    table.insert(lines, string.format('Этап: %s', stepName))

    if improve.waitOils or improve.oils.busy then
        table.insert(lines, 'Инвентарь: обновляется')
    else
        local count, name = Improve.GetOilCountByType()
        table.insert(lines, string.format('Смазка: %d шт. (%s)', count or 0, name or '-'))
    end

    if improve.cef.probing then
        local done = math.maxEx(0, tonumber(improve.cef.pendingIndex or 0) or 0)
        local total = math.maxEx(1, tonumber(improve.cef.probeTotal or 0) or 0)
        table.insert(lines, string.format('Проверка уровней: %d/%d', done, total))
        if improve.cef.pendingSlot then
            table.insert(lines, string.format('Проверяется слот: %s', tostring(improve.cef.pendingSlot)))
        end
    elseif improve.cef.probed and (tonumber(improve.cef.probeTotal or 0) or 0) > 0 then
        table.insert(lines, string.format('Проверка уровней: завершена (%d/%d)', improve.cef.probeProgress or 0, improve.cef.probeTotal or 0))
    elseif (improve.cef.probeAbortReason or '') ~= '' then
        table.insert(lines, 'Проверка уровней: остановлена - ' .. tostring(improve.cef.probeAbortReason))
    end

    local idx = tonumber(improve.currentIndex or 0) or 0
    local card = improve.videoCards[idx]
    if card then
        table.insert(lines, string.format('Текущая карта: #%d, слот %d, уровень %d', idx, tonumber(card.slot or 0) or 0, tonumber(card.level or 0) or 0))
    end

    local s = improve.stats
    if s and (s.sessionId or 0) > 0 then
        table.insert(lines, string.format('Сессия #%d: попыток %d, успехов %d, ошибок %d', s.sessionId or 0, s.attempts or 0, s.success or 0, s.fail or 0))
        table.insert(lines, string.format('Потрачено смазки: %d, денег: $%d', s.oilsUsed or 0, s.spent or 0))
    end

    table.insert(lines, '')
    table.insert(lines, 'Статус обновляется автоматически.')
    table.insert(lines, 'Кнопка - остановить процесс.')
    return table.concat(lines, '\n')
end

function Improve.ShowMobileStatusDialog(force)
    if not ISMONETLOADER then return end
    if not (improve.isOn or improve.cef.probing) then return end
    if improve.step == Improve.STEP.CONFIRM or improve.oils.busy then return end
    if os.clock() < (mobileImproveDialog.suppressUntil or 0) then return end
    if type(sampShowDialog) ~= 'function' then return end

    local currentIsStatus = Improve.IsMobileStatusDialogActive()
    if type(sampIsDialogActive) == 'function' and type(sampGetCurrentDialogId) == 'function' then
        local okActive, active = pcall(sampIsDialogActive)
        if okActive and active and not currentIsStatus then return end
    end

    local now = os.clock()
    local minUpdateDelay = improve.cef.probing and 0.25 or 1.0
    if not force and currentIsStatus and (now - (mobileImproveDialog.lastShowAt or 0)) < minUpdateDelay then return end

    local text = Improve.GetMobileStatusText()
    if not force and currentIsStatus and text == mobileImproveDialog.lastText then return end

    mobileImproveDialog.lastText = text
    mobileImproveDialog.lastShowAt = now
    sampShowDialog(idDialogs.mobileImproveStatus, '{33CCFF}MMT | Заточка видеокарт', text, 'Остановить', '', 0)
    mobileImproveDialog.wasActive = true
end

function Improve.StopFromMobileStatus()
    if improve.cef.probing and not improve.isOn then
        improve.cef.probeAbort = true
        improve.cef.probeAbortReason = 'остановлено через мобильный статус'
        improve.cef.probeDone = true
    elseif improve.isOn then
        Improve.Stop('Остановлено через мобильный статус')
    end
    mobileImproveDialog.suppressUntil = os.clock() + 3600
    mobileImproveDialog.wasActive = false
end

function Improve.MobileStatusTick()
    if not ISMONETLOADER then return end

    if not (improve.isOn or improve.cef.probing) then
        mobileImproveDialog.wasActive = false
        Improve.FinishProbeUI()
        return
    end

    local active = Improve.IsMobileStatusDialogActive()
    if mobileImproveDialog.wasActive and not active then
        mobileImproveDialog.wasActive = false
        if mobileImproveDialog.closing then
            mobileImproveDialog.closing = false
            return
        end
        -- Пока скрипт сам работает с диалогами (проверка уровней, открытие карты),
        -- пропавший статус - это наш же диалог, а не нажатие игрока
        if mobileImproveDialog.scriptBusy or improve.cef.probing then
            return
        end
        if os.clock() < (mobileImproveDialog.suppressUntil or 0) then
            return
        end
        Improve.StopFromMobileStatus()
        return
    end

    if active then
        mobileImproveDialog.wasActive = true
    end

    Improve.ShowMobileStatusDialog(false)
end

function Improve.HandleMobileStatusDialogResponse(btn)
    if not ISMONETLOADER then return false end

    if mobileImproveDialog.closing then
        mobileImproveDialog.closing = false
        mobileImproveDialog.wasActive = false
        return false
    end

    Improve.StopFromMobileStatus()
    return false
end

function Improve.IsNewStyleMode()
    return true
end


function Improve.GetInventoryModeName()
    return "Новый стиль"
end

function Improve.SendCef(payload)
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

function Improve.SendCefMobile(iface, sub, reqid, payload)
    iface = tonumber(iface or 0) or 0
    sub = tonumber(sub or 0) or 0
    reqid = tonumber(reqid or -1) or -1
    if reqid > 2147483647 then reqid = reqid - 4294967296 end
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

function Improve.SendCefClickOnSlot(slot, action, clickType)
    slot = tonumber(slot or 0) or 0
    action = tonumber(action or 1) or 1
    clickType = tonumber(clickType or 1) or 1
    if slot <= 0 then return false end

    Improve.NoteClickSlot(slot)
    local packet = string.format('clickOnButton|{"type": %d,"slot": %d, "action": %d}', clickType, slot, action)
    improve.cef.lastPacketId = 220
    improve.cef.lastPacket = packet
    return Improve.SendCef(packet)
end

-- skipInvent = инвентарь уже открыт, хватит одного CEF-клика
function Improve.OpenCardDialog(slot, action, clickType, skipInvent)
    slot = tonumber(slot or 0) or 0
    if slot <= 0 then return false end

    local inventWait = tonumber(settings.deley.improve_waitInventory) or 1500

    if ISMONETLOADER then
        -- подавление должно перекрывать ожидание инвентаря, иначе MobileStatusTick
        -- примет наш же закрытый диалог за нажатие "Остановить"
        Improve.CloseMobileStatusDialog(improve.cef.probing and (inventWait + 1000) or 3000)
    end

    if skipInvent then
        wait(200)
    else
        -- /invent переключает инвентарь: открытый он закроет, и клик уйдёт в пустоту.
        -- Закрываем сами только то, что открывали, иначе сервер отвечает
        -- "Нельзя так быстро открывать инвентарь" и команда пропадает впустую
        if improve.cef.inventoryOpen then
            Improve.CloseInventory()
        end
        Improve.WaitInventoryCooldown()
        improve.cef.inventoryOpen = true
        sampSendChat('/invent')
        wait(inventWait)
    end

    if ISMONETLOADER then
        Improve.NoteClickSlot(slot)
        local payload = string.format('{"action":1,"id":0,"slot":%d,"type":1}', slot)
        improve.cef.lastPacketId = 220
        improve.cef.lastPacket = payload
        return Improve.SendCefMobile(52, 3, 4294967295, payload)
    end

    return Improve.SendCefClickOnSlot(slot, action, clickType)
end

local FlashCollect = {}
local flashCollect = {
    active = false,
    inventoryOpened = false,
    waitHouseDialog = false,
    houseDialogReady = false,
    failed = false,
    error = "",
    statsBusy = false,
    lastStatsAt = "-",
    hideWindow = false,
    slot = 0,
    count = 0,
    name = "",
}

function FlashCollect.ResetFlags()
    flashCollect.active = false
    flashCollect.inventoryOpened = false
    flashCollect.waitHouseDialog = false
    flashCollect.houseDialogReady = false
    flashCollect.failed = false
    flashCollect.error = ""
    flashCollect.statsBusy = false
end

function FlashCollect.ResetItem()
    flashCollect.slot = 0
    flashCollect.count = 0
    flashCollect.name = ""
end

function FlashCollect.Cancel()
    local wasPreparing = flashCollect.active
    local wasCollecting = stateCrypto.work and processes.take

    if wasPreparing then
        FlashCollect.ResetFlags()
    end

    if wasCollecting then
        Interacting.Deactivate()
    end

    if wasPreparing or wasCollecting then
        Chat.Add("Сбор через флешку: отменен", TYPECHATMESSAGES.WARNING)
        return true
    end

    return false
end

-- Окно скрипта прячем только на время сбора, запущенного командой /mmtflash:
-- если сбор уже закончился, флаг ни на что не влияет
function FlashCollect.ApplyWindowVisibility()
    if flashCollect.hideWindow and (flashCollect.active or (stateCrypto.work and processes.take)) then
        imguiWindows.main[0] = false
        return
    end
    imguiWindows.main[0] = true
end

function FlashCollect.IsFlashItem(name)
    local lowerName = tostring(name or "")
    return lowerName:find("Флешка майнера", 1, true) ~= nil
end

function FlashCollect.RegisterItem(name, count, slot)
    slot = tonumber(slot or 0) or 0
    count = tonumber(count or 0) or 0
    if slot <= 0 or count <= 0 then return end
    if not FlashCollect.IsFlashItem(name) then return end

    flashCollect.slot = slot
    flashCollect.count = count
    flashCollect.name = tostring(name or "")
end

function FlashCollect.ParseStatsInventoryPage(text)
    for line in (text or ''):gmatch("[^\r\n]+") do
        local indexSlot, name, count = line:match("%[([^%]]+)%]%s*(.-)%s*%[(%d+)%s*шт%]")
        local slotNum = tonumber(indexSlot)
        count = tonumber(count)
        if name then name = name:gsub("{%x+}", ""):gsub("%s+$", "") end
        if indexSlot and name and count then
            FlashCollect.RegisterItem(name, count, slotNum)
        end
    end
end

function FlashCollect.Fail(reason, chatType)
    flashCollect.failed = true
    flashCollect.error = tostring(reason or "")
    flashCollect.active = false
    flashCollect.waitHouseDialog = false
    flashCollect.houseDialogReady = false
    flashCollect.inventoryOpened = false
    flashCollect.statsBusy = false
    Chat.Add(reason or "Сбор через флешку: ошибка", chatType or TYPECHATMESSAGES.CRITICAL)
end

function FlashCollect.Start(hideWindow, fromCommand)
    if stateCrypto.work then
        Chat.Add("Сбор через флешку: процесс уже запущен", TYPECHATMESSAGES.WARNING)
        return false
    end

    if improve.isOn or improve.oils.busy or flashCollect.statsBusy then
        Chat.Add("Сбор через флешку: дождитесь завершения другого процесса", TYPECHATMESSAGES.WARNING)
        return false
    end

    if flashCollect.active then
        Chat.Add("Сбор через флешку: запуск уже выполняется", TYPECHATMESSAGES.WARNING)
        return false
    end

    flashCollect.hideWindow = hideWindow == true
    flashCollect.fromCommand = fromCommand == true

    flashCollect.thread = RunThreadFresh(flashCollect.thread, FlashCollect.Process)

    return true
end

-- Тело сбора через флешку вынесено в отдельную функцию: поток создаётся заранее
-- приостановленным (см. main), потому что lua_thread.create изнутри уже работающего
-- потока роняет moonloader ("cannot resume non-suspended coroutine")
function FlashCollect.Process()
    FlashCollect.ResetFlags()
    FlashCollect.ResetItem()
    flashCollect.active = true
    flashCollect.waitHouseDialog = true
    flashCollect.houseDialogReady = false

    Chat.Add("Сбор через флешку: отправляю /flashminer", TYPECHATMESSAGES.DEBUG)
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
        FlashCollect.Fail("Сбор через флешку: список домов не открылся", TYPECHATMESSAGES.CRITICAL)
        return
    end

    FlashCollect.ResetFlags()
    Chat.Add("Сбор через флешку: запускаю сбор со всех домов", TYPECHATMESSAGES.DEBUG)
    wait(100)
    Interacting.Start("take", "flash")
end
-- ===== Кэш уровней видеокарт =====

-- Запись из кэша для слота, если в нём тот же предмет и запись не протухла
function Improve.CardCacheGet(slot, name)
    local entry = cardLevels.slots[tostring(tonumber(slot) or 0)]
    if type(entry) ~= 'table' then return nil end
    if Improve.GetCardNameNorm(entry.name) ~= Improve.GetCardNameNorm(name) then return nil end

    local hours = tonumber(settings.improve.levelCacheHours) or 0
    if hours > 0 and (os.time() - (tonumber(entry.at) or 0)) > hours * 3600 then
        return nil
    end
    return entry
end

function Improve.CardCacheSet(slot, name, level, cardType, storage)
    slot = tonumber(slot or 0) or 0
    if slot <= 0 then return end
    cardLevels.slots[tostring(slot)] = {
        name = Improve.GetCardNameNorm(name),
        level = math.maxEx(0, math.minEx(10, tonumber(level) or 0)),
        cardType = tonumber(cardType or 0) or 0,
        storage = storage == true,
        at = os.time(),
    }
    Storage.RequestSaveCardLevels(false)
end

function Improve.CardCacheForget(slot)
    cardLevels.slots[tostring(tonumber(slot) or 0)] = nil
    Storage.RequestSaveCardLevels(false)
end

-- Очистка кэша: целиком или только по одному типу карт
function Improve.CardCacheClear(cardType)
    cardType = tonumber(cardType or 0) or 0
    if cardType == 0 then
        cardLevels.slots = {}
    else
        for key, entry in pairs(cardLevels.slots) do
            if type(entry) == 'table' and (tonumber(entry.cardType or 0) or 0) == cardType then
                cardLevels.slots[key] = nil
            end
        end
    end
    Storage.RequestSaveCardLevels(true)
end

-- Актуальный уровень пишем и в список CEF, и в кэш на диске
function Improve.UpdateCefCardLevel(slot, level, storage)
    slot = tonumber(slot or 0) or 0
    if slot <= 0 then return end
    for _, c in ipairs(improve.cef.cards or {}) do
        if tonumber(c.slot or 0) == slot then
            if level ~= nil then
                c.level = level
                c.levelKnown = true
                c.probeFailed = false
            end
            if storage ~= nil then c.storageUpgrade = storage end
            Improve.CardCacheSet(c.slot, c.name, c.level, c.cardType, c.storageUpgrade)
            return
        end
    end
end

-- Сколько карт выбранного типа с известным/неизвестным уровнем
function Improve.CountKnownLevels()
    local selectedType = tonumber(settings.improve.typeCards or 1) or 1
    local known, unknown = 0, 0
    for _, c in ipairs(improve.cef.cards or {}) do
        if tonumber(c.cardType or 0) == selectedType then
            if c.levelKnown then known = known + 1 else unknown = unknown + 1 end
        end
    end
    return known, unknown
end

function Improve.ResetCefInventory()
    improve.cef.cards = {}
    improve.cef.inventoryFresh = false
    improve.cef.inventoryOpen = false
    improve.cef.inventoryBlockedUntil = 0
    improve.cef.unknownCount = 0
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

function Improve.GetCardNameNorm(name)
    local s = tostring(name or '')
    s = s:gsub('^%s+', ''):gsub('%s+$', '')
    s = s:gsub('%s+%(%+1%)', '(+1)')
    return s
end

function Improve.ParseCardMetaFromName(name)
    local n = Improve.GetCardNameNorm(name)
    if n == 'Видеокарта' then return 1, false end
    if n == 'Видеокарта(+1)' then return 1, true end
    if n == 'Arizona Video Card' then return 2, false end
    if n == 'Arizona Video Card(+1)' then return 2, true end
    return nil, false
end

function Improve.AddCefCardSlot(slot, itemName, hasStorageUpgrade, cardType)
    slot = tonumber(slot or 0) or 0
    if slot <= 0 then return end

    local parsedType, parsedStorage = Improve.ParseCardMetaFromName(itemName)
    local ctype = tonumber(cardType or parsedType or 0) or 0
    local storage = (hasStorageUpgrade == true) or parsedStorage
    if ctype ~= 1 and ctype ~= 2 then return end

    local nameNorm = Improve.GetCardNameNorm(itemName)

    for _, c in ipairs(improve.cef.cards) do
        if c.slot == slot then
            -- в слоте сменился предмет - прежний уровень больше не про него
            if Improve.GetCardNameNorm(c.name) ~= nameNorm then
                c.level = 0
                c.levelKnown = false
                c.probeFailed = false
                c.storageUpgrade = false
                Improve.CardCacheForget(slot)
            end
            c.name = tostring(itemName or c.name or '')
            c.cardType = ctype
            c.storageUpgrade = storage or (c.storageUpgrade == true)

            local _pktLevel = Improve.PacketLevelForSlot(slot, ctype)
            if _pktLevel then
                c.level = _pktLevel
                c.levelKnown = true
                c.levelGuessed = false
                c.probeFailed = false
                Improve.CardCacheSet(slot, c.name, _pktLevel, ctype, c.storageUpgrade)
            end
            return
        end
    end

    -- уровень берём из кэша, если он про этот же предмет и ещё не протух
    -- пакет инвентаря знает уровень точно, кеш - только по памяти прошлых проверок
    local level, known = 0, false
    local pktLevel = Improve.PacketLevelForSlot(slot, ctype)
    local cached = Improve.CardCacheGet(slot, itemName)
    if cached and cached.storage == true then storage = true end

    if pktLevel then
        level = pktLevel
        known = true
        Improve.CardCacheSet(slot, itemName, pktLevel, ctype, storage)
    elseif cached and (tonumber(cached.cardType or 0) or 0) == ctype then
        level = tonumber(cached.level) or 0
        known = true
    end

    table.insert(improve.cef.cards, {
        slot = slot,
        name = tostring(itemName or ''),
        cardType = ctype,
        level = level,
        levelKnown = known,
        levelGuessed = false,
        probeFailed = false,
        storageUpgrade = storage,
    })
end

function Improve.MoveMaxLevelCardsToEnd(cards)
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

function Improve.SyncVideoCardsFromCef()
    local cards = {}
    local selectedType = tonumber(settings.improve.typeCards or 1) or 1

    for _, c in ipairs(improve.cef.cards or {}) do
        -- карты, которые не удалось проверить, в работу не берём:
        -- их реальный уровень неизвестен, попытки улучшения были бы вслепую
        if tonumber(c.cardType or 0) == selectedType and not (c.probeFailed and not c.levelKnown) then
            table.insert(cards, {
                slot = c.slot,
                name = c.name,
                cardType = tonumber(c.cardType or 0) or 0,
                level = tonumber(c.level or 0) or 0,
                levelKnown = c.levelKnown == true,
                storageUpgrade = c.storageUpgrade == true,
            })
        end
    end

    if settings.improve.mode == 1 and settings.improve.menuAll then
        table.sort(cards, function(a, b)
            return (a.level or 0) < (b.level or 0)
        end)
    end

    cards = Improve.MoveMaxLevelCardsToEnd(cards)
    improve.videoCards = cards
end
function Improve.ParseCardLevelFromDialog(text)
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

-- Проверка уровней видеокарт.
-- Замеряются только карты с неизвестным уровнем, известные берутся из кэша;
-- при обрыве прогресс сохраняется и следующий запуск добирает остаток.
function Improve.RunNewStyleProbeLoop(allowWhenStopped, rescanAll)
    improve.cef.probing = true
    improve.cef.probeDone = false
    improve.cef.probed = false
    improve.cef.probeAbort = false
    improve.cef.probeAbortReason = ''
    improve.cef.inventoryFresh = false

    local selectedType = tonumber(settings.improve.typeCards or 1) or 1

    -- Уровни приходят в пакете инвентаря. Если с запуска скрипта такого пакета
    -- ещё не было, просим инвентарь один раз - это дешевле, чем диалог по каждой карте
    if Improve.UsePacketLevels() then
        -- уровни из пакетов точные, их не забываем даже при полном пересканировании:
        -- сбрасывается только кэш на диске

        if (improve.cef.pktInvAt or 0) == 0 then
            local _hasUnknown = false
            for _, c in ipairs(improve.cef.cards or {}) do
                if tonumber(c.cardType or 0) == selectedType and (rescanAll or not c.levelKnown) then
                    _hasUnknown = true
                    break
                end
            end

            if _hasUnknown then
                Improve.LogAdd('INFO', 'Оценка карт: запрашиваем инвентарь, уровни должны прийти пакетом.')
                if not Improve.RequestInventoryDump(6) then
                    Improve.LogAdd('WARN', 'Оценка карт: инвентарь пакетом не пришёл, проверяем карты по старинке.')
                end
            end
        end
    end

    local typeCards, probeCards, knownCount = {}, {}, 0
    for _, c in ipairs(improve.cef.cards or {}) do
        if tonumber(c.cardType or 0) == selectedType then
            if rescanAll then
                c.levelKnown = false
                c.probeFailed = false
                c.levelGuessed = false

                local _pktLevel = Improve.PacketLevelForSlot(c.slot, c.cardType)
                if _pktLevel then
                    c.level = _pktLevel
                    c.levelKnown = true
                end
            end
            table.insert(typeCards, c)
            if c.levelKnown then
                knownCount = knownCount + 1
            elseif not c.probeFailed then
                table.insert(probeCards, c)
            end
        end
    end

    improve.cef.probeTotal = #typeCards
    improve.cef.probeProgress = knownCount

    -- нечего проверять
    if #typeCards == 0 then
        improve.cef.probing = false
        improve.cef.probeAbort = true
        improve.cef.probeAbortReason = 'в инвентаре нет карт выбранного типа'
        Improve.SyncVideoCardsFromCef()
        Improve.LogAdd('WARN', 'Новый стиль: в инвентаре нет карт выбранного типа.')
        if improve.isOn and not allowWhenStopped then
            Improve.Stop('Новый стиль: в инвентаре нет карт выбранного типа')
        end
        Improve.FinishProbe()
        return
    end

    -- всё уже известно из кэша
    if #probeCards == 0 then
        improve.cef.probing = false
        improve.cef.probed = true
        improve.cef.unknownCount = 0
        Improve.SyncVideoCardsFromCef()
        Improve.LogAdd('INFO', string.format('Новый стиль: уровни всех %d карт уже известны, проверка не нужна.', #typeCards))
        if allowWhenStopped then
            Improve.Say(string.format('Уровни всех %d карт уже известны.', #typeCards))
        end
        Improve.FinishProbe()
        return
    end

    Improve.LogAdd('INFO', string.format('Новый стиль: проверяю %d карт из %d (остальные уже известны).', #probeCards, #typeCards))
    Improve.ShowMobileStatusDialog(true)

    local timeoutDialog = tonumber(settings.deley.timeoutDialog) or 10
    local maxRetries = math.maxEx(0, tonumber(settings.improve.probeRetries) or 2)
    local fastProbe = settings.improve.fastProbe ~= false
    local fastFails, failStreak, stopped = 0, 0, false

    for idx, card in ipairs(probeCards) do
        if ((not improve.isOn) and (not allowWhenStopped)) or improve.cef.probeAbort then
            stopped = true
            break
        end

        improve.cef.pendingIndex = knownCount + idx
        improve.cef.pendingSlot = card.slot
        Improve.ShowMobileStatusDialog(true)

        local measured = false
        for attempt = 1, maxRetries + 1 do
            if ((not improve.isOn) and (not allowWhenStopped)) or improve.cef.probeAbort then
                stopped = true
                break
            end

            -- первая попытка может обойтись без /invent, если инвентарь уже открыт
            local useFast = fastProbe and improve.cef.inventoryFresh and attempt == 1
            local stepTimeout = useFast and math.minEx(4, timeoutDialog) or timeoutDialog

            improve.cef.probeDone = false
            mobileImproveDialog.scriptBusy = true
            Improve.OpenCardDialog(card.slot, 1, 1, useFast)

            local timeoutAt = os.clock() + stepTimeout
            while (improve.isOn or allowWhenStopped)
                and not improve.cef.probeDone
                and not improve.cef.probeAbort
                and os.clock() < timeoutAt do
                wait(25)
            end
            mobileImproveDialog.scriptBusy = false

            -- HandleProbeServerMessage ставит probeDone вместе с probeAbort,
            -- чтобы разбудить ожидание: это не замер, а аварийный выход
            if improve.cef.probeDone and not improve.cef.probeAbort then
                measured = true
                break
            end
            if improve.cef.probeAbort then
                stopped = true
                break
            end

            improve.cef.inventoryFresh = false
            if useFast then
                fastFails = fastFails + 1
                if fastFails >= 2 then
                    fastProbe = false
                    Improve.LogAdd('INFO', 'Новый стиль: быстрая проверка не срабатывает, переоткрываю инвентарь для каждой карты.')
                end
            elseif attempt <= maxRetries then
                Improve.LogAdd('WARN', string.format('Новый стиль: слот %d не ответил, повтор %d из %d.', card.slot, attempt, maxRetries))
                wait(500)
            end
        end

        if stopped or improve.cef.probeAbort then
            stopped = true
            break
        end

        if measured then
            failStreak = 0
            card.levelKnown = true
            card.probeFailed = false
            improve.cef.inventoryFresh = true
            improve.cef.probeProgress = knownCount + idx
            -- уровень, который не удалось прочитать из диалога, запоминать нельзя
            if not card.levelGuessed then
                Improve.CardCacheSet(card.slot, card.name, card.level, card.cardType, card.storageUpgrade)
            end
        else
            -- одна неотвечающая карта не должна рушить весь проход
            failStreak = failStreak + 1
            card.levelKnown = false
            card.probeFailed = true
            Improve.LogAdd('WARN', string.format('Новый стиль: слот %d проверить не удалось, пропускаю.', card.slot))
            if failStreak >= 3 then
                improve.cef.probeAbort = true
                improve.cef.probeAbortReason = 'подряд не открылось окно у 3 карт (стойте у стола, закройте инвентарь, MMT должен быть запущен один раз)'
                break
            end
        end

        Improve.ShowMobileStatusDialog(true)
        wait(settings.deley.improve_waitTryClick or 300)
    end

    local aborted = improve.cef.probeAbort == true
    local abortReason = improve.cef.probeAbortReason or ''

    improve.cef.probing = false
    improve.cef.pendingSlot = nil
    improve.cef.pendingIndex = 0
    improve.cef.probeDone = false
    mobileImproveDialog.scriptBusy = false

    local known, unknown = Improve.CountKnownLevels()
    improve.cef.probeProgress = known
    improve.cef.unknownCount = unknown
    improve.cef.probeTotal = known + unknown

    Improve.SyncVideoCardsFromCef()
    Storage.RequestSaveCardLevels(true)

    if aborted or stopped then
        improve.cef.probed = false
        local reason = (abortReason ~= '') and abortReason or 'остановлено'
        Improve.LogAdd('WARN', string.format('Новый стиль: проверка прервана (%s). Известно уровней %d из %d, при следующем запуске доберу остальные.', reason, known, known + unknown))
        Improve.Say(string.format('Проверка прервана: %s. Известно %d/%d, прогресс сохранён.', reason, known, known + unknown))
        if improve.isOn and not allowWhenStopped then
            Improve.Stop('Новый стиль: ' .. reason)
        end
    else
        improve.cef.probed = true
        if unknown > 0 then
            Improve.LogAdd('WARN', string.format('Новый стиль: проверка завершена, %d карт проверить не удалось - в работу они не пойдут.', unknown))
        else
            Improve.LogAdd('INFO', string.format('Новый стиль: проверка завершена, уровни известны у всех %d карт.', known))
        end
        if allowWhenStopped then
            Improve.Say(string.format('Проверка уровней завершена: известно %d из %d.', known, known + unknown))
        end
    end

    Improve.FinishProbe()
end

function Improve.StartNewStyleProbe(allowWhenStopped, rescanAll)
    if improve.cef.probing then return end

    if #(improve.cef.cards or {}) == 0 then
        Improve.SyncVideoCardsFromCef()
        improve.cef.probed = true
        return
    end

    Improve.RunNewStyleProbeLoop(allowWhenStopped, rescanAll)
end

-- rescanAll = забыть запомненные уровни и промерить всё заново
function Improve.ManualCheckCardLevels(rescanAll)
    if improve.oils.busy then
        Improve.Say('Дождитесь завершения обновления инвентаря.')
        return
    end

    if improve.cef.probing then
        Improve.Say('Проверка уровней уже выполняется.')
        return
    end

    lua_thread.create(function()
        if rescanAll then
            Improve.CardCacheClear(tonumber(settings.improve.typeCards or 1) or 1)
        end

        Improve.RefreshOils(false)

        if #(improve.cef.cards or {}) == 0 then
            Improve.Say('Видеокарты в инвентаре не найдены.')
            return
        end

        Improve.SyncVideoCardsFromCef()
        improve.cef.probed = false
        Improve.StartNewStyleProbe(true, rescanAll)
    end)
end

function Improve.HandleNewStyleChooseDialog(dialogId, title, text)
    if not Improve.IsNewStyleMode() then return false end

    local dialogTitle = Farmer.stripColors(tostring(title or ''))
    local dialogText = tostring(text or '')
    local isChooseDialog = dialogTitle:find('Выберите вид улучшения для видеокарты', 1, true) ~= nil
    local isUpgradeDialog = dialogTitle:find('Улучшение видеокарты', 1, true) ~= nil

    if not isChooseDialog and not (improve.cef.probing and isUpgradeDialog) then
        -- чужой диалог во время проверки - пишем заголовок, чтобы было видно, что пришло вместо карты
        if improve.cef.probing and improve.cef.pendingSlot then
            Improve.LogAdd('WARN', string.format('Новый стиль: вместо окна карты (слот %s) пришёл диалог "%s".', tostring(improve.cef.pendingSlot), dialogTitle))
        end
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
            local lvl = Improve.ParseCardLevelFromDialog(dialogText)
            if lvl ~= nil then
                card.level = lvl
                card.levelGuessed = false
            else
                card.level = 10
                card.levelGuessed = true
                Improve.LogAdd('WARN', string.format('Новый стиль: не удалось определить уровень карты в slot %s, считаю 10 LVL (в память не пишу).', tostring(card.slot or improve.cef.pendingSlot or '?')))
            end

            if dialogText:find('Увеличить объем хранения криптовалюты на видео-карте', 1, true) then
                card.storageUpgrade = false
            elseif isChooseDialog then
                card.storageUpgrade = true
            end
        end

        improve.cef.probeDone = true
        sampSendDialogResponse(dialogId, 0, 0, '')
        lua_thread.create(function()
            wait(200)
            Improve.ShowMobileStatusDialog(true)
        end)
        return true
    end

    if not isChooseDialog then
        return false
    end

    if not (improve.isOn and improve.step == Improve.STEP.CONFIRM) then
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
function Improve.HandleNewStyleConfirmDialog(dialogId, title)
    if not Improve.IsNewStyleMode() then return false end
    if not (improve.isOn and improve.step == Improve.STEP.CONFIRM) then return false end
    if not title:find('{BFBBBA}Улучшение видеокарты') then return false end

    if not improve.useStorageUpgrade then
        if not Improve.HasRequiredOils(2) then
            Improve.Say('Недостаточно смазки (нужно 2). Отключаюсь.')
            Improve.LogAdd('WARN', 'Новый стиль: недостаточно смазки. Сессия остановлена.')
            Improve.Stop('Недостаточно смазки в новом стиле')
            return true
        end

        if not improve.consumedThisTry then
            Improve.ConsumeOils(2)
            improve.consumedThisTry = true
        end
    end

    if improve.cef.upgradeFast then
        improve.cef.upgradeFast = false
        improve.cef.upgradeFastFails = 0
    end

    sampSendDialogResponse(dialogId, 1, 0, '')
    improve.waitStart = true
    improve.waitStartAt = os.clock()
    return true
end

function Improve.TickNewStyle()
    if improve.step ~= Improve.STEP.SELECT_CARD then return end

    if (not improve.useStorageUpgrade) and (not Improve.HasRequiredOils(2)) then
        Improve.Say('Смазка закончилась. Отключаюсь.')
        Improve.LogAdd('WARN', 'Новый стиль: смазка закончилась. Сессия остановлена.')
        Improve.Stop('Закончилась смазка в процессе (новый стиль)')
        return
    end

    if improve.cef.needInventoryRefresh then
        if not improve.oils.busy then
            Improve.RefreshOils(true)
            improve.cef.needInventoryRefresh = false
            improve.cef.waitInventory = true
            Improve.LogAdd('INFO', 'Новый стиль: обновляю инвентарь перед началом заточки.')
        end
        return
    end

    if improve.cef.waitInventory then
        if improve.oils.busy then return end
        improve.cef.waitInventory = false

        Improve.SyncVideoCardsFromCef()
        if #improve.videoCards == 0 then
            Improve.Say('Новый стиль: видеокарты в инвентаре не найдены.')
            Improve.Stop('Новый стиль: не найдены слоты видеокарт')
            return
        end

        improve.cef.probed = false
        Improve.StartNewStyleProbe()
        return
    end

    if improve.cef.probing then return end

    if not improve.cef.probed then
        Improve.StartNewStyleProbe()
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
        if improve.selectSlot then
            improve.select = 0
            for idx, v in ipairs(improve.videoCards) do
                if v.slot == improve.selectSlot then
                    improve.select = idx
                    break
                end
            end
        end
        if improve.select == 0 then
            Improve.Say('Выбери видеокарту внизу списка.')
            Improve.Stop('Новый стиль: не выбрана видеокарта')
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
            Improve.Stop('Новый стиль: все видеокарты уже улучшены по хранилищу')
        else
            Improve.Stop('Новый стиль: все видеокарты достигли целевого уровня')
        end
        return
    end

    local slot = tonumber(candidate.slot or 0) or 0
    if slot <= 0 then
        Improve.LogAdd('ERROR', 'Новый стиль: у выбранной видеокарты отсутствует slot.')
        Improve.Stop('Новый стиль: некорректный slot у видеокарты')
        return
    end

    improve.currentIndex = idxCandidate
    improve.consumedThisTry = false

    -- после заточки инвентарь остаётся открытым: кликаем по карте сразу, без /invent.
    -- Если окно не открылось, автоповтор в TickWaitWatchdogs переоткроет инвентарь
    local useFast = settings.improve.fastProbe ~= false
        and improve.cef.inventoryOpen
        and (improve.cef.upgradeFastFails or 0) < 2
    improve.cef.upgradeFast = useFast
    Improve.OpenCardDialog(slot, 1, 1, useFast)
    improve.lastUseAt = os.clock()
    improve.step = Improve.STEP.CONFIRM
end

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
        UI.SetScale()
    end

    UI.SetStyle(ISMONETLOADER)

    if ISMONETLOADER then
        fa.Init(14*MONET_DPI_SCALE)
    else
        fa.Init(14)
    end
end)

function main()
    -- Версия в консоли: она попадает в лог NeoMLoader и в отчёты о крашах
    print("[MMT] Версия скрипта: " .. tostring(thisScript().version))

    while not isSampAvailable() do wait(0) end

    -- цвет префикса в чате и смысловые цвета берём из настроек до первого сообщения
    UI.RefreshSemanticColors()

    -- два экземпляра MMT шлют /invent одновременно: инвентарь открывается
    -- и тут же закрывается, проверка уровней видеокарт не срабатывает
    local okList, scriptList = pcall(script.list)
    if okList and type(scriptList) == 'table' then
        local me = thisScript()
        for _, s in ipairs(scriptList) do
            if s.id ~= me.id and s.name == me.name then
                Chat.Add(string.format('MMT запущен дважды (%s). Оставьте один файл, иначе проверка уровней видеокарт не сработает.', tostring(s.filename)), TYPECHATMESSAGES.WARNING)
            end
        end
    end

    sampRegisterChatCommand("mmt", function ()
        UI.SwitchMainWindow()
    end)
    sampRegisterChatCommand("mmtr", function ()
        thisScript():reload()
    end)
    sampRegisterChatCommand("mmtsr", function ()
        settings.style.scaleUI = 1.0
        -- копия: окно пишет свой размер прямо в settings.style.sizeWindow
        settings.style.sizeWindow = { x = defaultSettings.style.sizeWindow.x, y = defaultSettings.style.sizeWindow.y }
        Storage.SaveSettings()
        thisScript():reload()
    end)
    sampRegisterChatCommand("mmtflash", function ()
        if settings.main.hideWindowOnFlashCmd then
            imguiWindows.main[0] = false
        end
        FlashCollect.Start(settings.main.hideWindowOnFlashCmd, true)
    end)
    sampRegisterChatCommand("mmtfarm", function ()
        activeMode = "farmer"
        if activeTabScript == "improve" then activeTabScript = "main" end
        imguiWindows.main[0] = true
    end)

    if notifySuccess and type(notify) == 'table' and type(notify.register_action) == 'function' then
        collectReminderAction = notify.register_action(u8("Запустить сбор"), function()
            -- колбэк вызывается изнутри notify.process_actions: поток отсюда не запускаем
            flashCollect.notifyStart = true
        end)
    end

    -- Фоновый поток заточки
    lua_thread.create(function()
        while true do
            wait(10)

            if notifySuccess and type(notify) == 'table' and type(notify.process_actions) == 'function' then
                -- ошибка внутри библиотеки не должна убивать весь фоновый поток
                local okActions, errActions = pcall(notify.process_actions)
                if not okActions then
                    print("[MMT] notify.process_actions: " .. tostring(errActions))
                end
            end

            -- запуск сбора по кнопке уведомления: только вне process_actions
            if flashCollect.notifyStart then
                flashCollect.notifyStart = false
                FlashCollect.Start()
            end

            -- автообновление инвентаря при старте заточки (если включено)
            if improve.isOn and improve.needCheckOils then
                improve.needCheckOils = false

                if settings.improve.checkOilsOnStart or Improve.IsNewStyleMode() then
                    Improve.RefreshOils(true)  -- асинхронно (/stats + парсинг)
                    improve.waitOils = true
                    if settings.improve.checkOilsOnStart then
                        Improve.Say("Проверяю наличие смазки.")
                    else
                        Improve.Say("Новый стиль: обновляю инвентарь перед стартом.")
                    end
                else
                    -- проверка отключена - сразу переходим к выбору карты
                    improve.step = Improve.STEP.SELECT_CARD
                end
            end

            -- ждём завершения сканирования /stats и принимаем решение
            if improve.isOn and improve.waitOils and not improve.oils.busy then
                improve.waitOils = false
                local count, name = Improve.GetOilCountByType()
                if settings.improve.checkOilsOnStart and (not improve.useStorageUpgrade) and count < 2 then
                    Improve.Say(("Смазки нет (%s). Нужно минимум 2 - остановлено."):format(name))
                    Improve.LogAdd("WARN", string.format(
                        "Проверка смазки перед стартом: смазки нет (%s). Сессия не запущена.",
                        name
                    ))
                    Improve.Stop("Недостаточно смазки при старте")
                else
                    Improve.LogAdd("INFO", string.format(
                        "Проверка инвентаря перед стартом завершена (%s: %d шт.).",
                        name, count
                    ))
                    improve.step = Improve.STEP.SELECT_CARD
                end
            end


            Improve.Tick()
            Improve.FlushCardListDirty()
            Improve.ProbeWatchdogTick()
            Improve.MobileStatusTick()
            Collect.ReminderTick()
            Collect.TgTick()
            Collect.SyncTick()
            Mirage.Tick()
            Storage.FlushResourceLogs()
        end
    end)

    Chat.Add('Скрипт загружен. Команда активации: {'..settings.style.colorChat..'}/mmt{FFFFFF}.')

    -- предупреждения о повреждённых файлах, найденных при загрузке
    Storage.FlushBrokenFilesNotice()

    processInteractingThread = lua_thread.create_suspended(Interacting.Process)
    farmer.thread = lua_thread.create_suspended(Farmer.Process)
    miner.thread = lua_thread.create_suspended(Miner.Process)
    flashCollect.thread = lua_thread.create_suspended(FlashCollect.Process)
    improve.oilsThread = lua_thread.create_suspended(Improve.OilsWaitProcess)
end

-- =====================================================================================================================
--                                                          SAMP EVENTS
-- =====================================================================================================================

-- --------------------------------------------------------
--                           onServerMessage
-- --------------------------------------------------------

local function HandleFlashCollectServerMessage(text)
    if flashCollect.active and text:find("Эта функция недоступна через флешку", 1, true) then
        FlashCollect.Fail("Сбор через флешку: сервер отклонил использование флешки", TYPECHATMESSAGES.CRITICAL)
    end
end

local function HandleStateCryptoServerMessage(color, text)
    if not stateCrypto.work then
        return nil
    end

    if text:find("Вы залили") and text:find("охлаждающей жидкости в видеокарту") and color == 1941201407 then
        local nowFillLiquid = text:match("восстановлено до ([%d%.]+)%%")

        if nowFillLiquid then
            Collect.SyncOnLiquid(stateCrypto.fillLiquidType)
            stateCrypto.queueShelves[stateCrypto.progressShelves].fill = tonumber(nowFillLiquid)
            stateCrypto.waitFill = false
            stateCrypto.fillLiquidType = nil
            stateCrypto.fillLiquidLabel = nil
            stateCrypto.fillLiquidBefore = 0
            stateCrypto.fillLiquidAfter = 0
        end
    end

    if text:find("Чтобы запустить видеокарту в работу, необходимо вывести всю прибыль этой видеокарты") and color == -1104335361 then
        Interacting.Deactivate("сначала нужно вывести прибыль видеокарты")
    end

    if text:find("Эта функция недоступна через флешку") and color == -1104335361 then
        Interacting.Deactivate("функция недоступна через флешку")
    end

    if text:find("Вы успешно пополнили счёт дома за электроэнергию на ") and color == 1941201407 then
        Collect.SyncOnDeposit(stateCrypto.pendingDeposit)
        stateCrypto.pendingDeposit = 0
        stateCrypto.waitDep = false
    end

    if text:find("В этом доме нет подвала с вентиляцией или он еще не достроен") and color == -1104335361 then
        Interacting.Deactivate("в доме нет подвала с вентиляцией")
        Chat.Add("Вы можете добавить данный дом в чёрный список, чтобы его скрыть", TYPECHATMESSAGES.SECONDARY)
    end

    if text:find("У Вас недостаточно денежных средств!") and color == -1104335361 then
        Interacting.Deactivate("недостаточно денег")
    end

    -- Фактический вывод прибыли: сервер присылает точную сумму, которую реально выдал.
    -- "Вы вывели {ffffff}9 BTC{ffff00}, осталось на счету видеокарты: {ffffff}0.043804 BTC{ffff00}."
    if processes.take and text:find("осталось на счету видеокарты:") then
        local clean = text:gsub("{%x%x%x%x%x%x}", "")
        local rawAmount, currency = clean:match("Вы вывели%s*([%d%.]+)%s*(%u+)")
        local amount = tonumber(rawAmount) or 0

        if amount > 0 and (currency == "BTC" or currency == "ASC") then
            local hid = stateCrypto.currentHouseId or 0
            local queueShelf = stateCrypto.queueShelves[stateCrypto.progressShelves]

            collectStats.total[currency] = (collectStats.total[currency] or 0) + amount
            collectStats.house[hid] = collectStats.house[hid] or { BTC = 0, ASC = 0 }
            collectStats.house[hid][currency] = (collectStats.house[hid][currency] or 0) + amount

            Collect.AddLogEntry(hid, currency, amount)
            Collect.SummaryTake(queueShelf, currency, amount)
            Collect.SyncOnTake(currency, amount)

            Chat.Add(string.format("Сбор DEBUG: сервер выдал %s %s (дом %s)",
                tostring(amount), tostring(currency), tostring(hid)), TYPECHATMESSAGES.DEBUG)
        end
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

    -- Новый вариант выдачи битка: ":u1f7e8: В инвентарь добавлен предмет: :item1811:." (color -1)
    if processes.take and settings.main.hideMessagesCollect
        and text:find("инвентарь добавлен предмет", 1, true)
        and (
            text:find(":item1811:", 1, true) or
            text:find(":item5996:", 1, true) or
            text:find("Bitcoin (BTC)", 1, true)
        )
    then
        return false
    end

    return nil
end

function Improve.HandleWaitStartServerMessage(text)
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
        improve.step = Improve.STEP.WAIT_RESULT
        Improve.LogAdd("INFO", logMessage)
        Improve.AttemptStart()
    end
end

function Improve.HandleUseRetryServerMessage(text)
    if not (improve.isOn and improve.step == Improve.STEP.CONFIRM) then
        return
    end

    if text:find('Подождите немного') then
        Improve.LogAdd("WARN", "Сервер ответил \"Подождите немного.\" - повторяем CEF-клик по текущему слоту.")
        improve.cef.upgradeFast = false
        lua_thread.create(function ()
            wait(1000)
            if improve.isOn and improve.step == Improve.STEP.CONFIRM then
                local idx = tonumber(improve.currentIndex or 0) or 0
                local card = improve.videoCards[idx]
                local slot = card and tonumber(card.slot or 0) or 0
                if slot > 0 then
                    Improve.OpenCardDialog(slot, 1, 1)
                    improve.lastUseAt = os.clock()
                end
            end
        end)
    end
end

function Improve.HandleStorageUpgradeServerMessage(text)
    if not (improve.isOn and improve.step == Improve.STEP.CONFIRM and improve.useStorageUpgrade) then
        return
    end

    if text:find('[Ошибка] {ffffff}У вас нет увеличителя пропускной способности', nil, true) then
        Improve.Say("У вас нет увеличителя пропускной способности!")
        Improve.LogAdd("ERROR", "Получено сообщение об отсутствии увеличителя пропускной способности. Сессия остановлена.")
        Improve.Stop("Нет увеличителя пропускной способности")
    end

    if text:find('[Ошибка] {ffffff}На выбранной видео-карте уже увеличен объём хранение криптовалюты', nil, true) then
        Improve.Say("Видеокарта уже улучшена, переходим к следующей")
        Improve.LogAdd("ERROR", "Получено сообщение о уже увеличен объём хранение криптовалюты")

        lua_thread.create(function ()
            wait(settings.deley.improve_waitResult or 600)
            local card = improve.videoCards[improve.currentIndex]
            if card then
                card.storageUpgrade = true
            end
            improve.step = Improve.STEP.SELECT_CARD
            improve.consumedThisTry = false
        end)
    end
end

function Improve.HandleResultServerMessage(text)
    if not (improve.isOn and improve.step == Improve.STEP.WAIT_RESULT) then
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
        Improve.OnResult(isSuccess ~= nil and isSuccess ~= false, text)

        lua_thread.create(function ()
            wait(settings.deley.improve_waitResult or 600)
            improve.waitResultAt = 0
            improve.lastUseAt = 0
            improve.step = Improve.STEP.SELECT_CARD
            improve.consumedThisTry = false
        end)
    end
end

function Improve.HandleProbeServerMessage(text)
    -- "Нельзя так быстро открывать инвентарь, подождите еще 1 сек." - команда не сработала
    local blockSeconds = text:match('Нельзя так быстро открывать инвентарь, подождите еще (%d+)')
    if blockSeconds then
        improve.cef.inventoryOpen = false
        improve.cef.inventoryFresh = false
        improve.cef.inventoryBlockedUntil = os.clock() + (tonumber(blockSeconds) or 1) + 0.5
    end

    if improve.cef.probing and text:find('Чтобы установить видеокарту, вы должны находиться в подвале возле одной из специальных стоек') then
        improve.cef.probeAbort = true
        improve.cef.probeAbortReason = 'нужно находиться в подвале возле стойки'
        improve.cef.probeDone = true
    end
end

function Improve.HandleInvalidPlaceServerMessage(text)
    if improve.isOn and text:find('Чтобы установить видеокарту, вы должны находиться в подвале возле одной из специальных стоек') then
        Improve.Say("Недопустимое место заточки!")
        Improve.LogAdd("ERROR", "Получено сообщение о неверном месте заточки. Сессия остановлена.")
        Improve.Stop("Неподходящее место заточки")
    end
end

function sampev.onServerMessage(color, text)
    HandleFlashCollectServerMessage(text)
    Mirage.HandleServerMessage(text)

    local handled = HandleStateCryptoServerMessage(color, text)
    if handled ~= nil then
        return handled
    end

    Improve.HandleWaitStartServerMessage(text)
    Improve.HandleUseRetryServerMessage(text)
    Improve.HandleStorageUpgradeServerMessage(text)
    Improve.HandleResultServerMessage(text)
    Improve.HandleProbeServerMessage(text)
    Improve.HandleInvalidPlaceServerMessage(text)
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
    local maxBank = tonumber(settings.main.maxBankAmount or 60000000) or 60000000
    local effectiveTarget = (target and target > 0) and math.minEx(target, math.maxEx(0, maxBank - 1)) or math.maxEx(0, maxBank - 1)

    if cur >= effectiveTarget then
        stateCrypto.waitDep = false
        DialogUtils.waitAndSendDialogResponse(dialogId, 0, 0, "")
        return DialogReturnVisibility()
    end

    local dep = effectiveTarget - cur
    local MIN_OP_LIMIT = 10000
    local MAX_OP_LIMIT = 10000000
    dep = math.minEx(dep, math.maxEx(0, can - 1))
    dep = math.minEx(dep, MAX_OP_LIMIT)
    if dep < MIN_OP_LIMIT then
        stateCrypto.queueHousesBank[stateCrypto.progressHousesBank].bankNow = effectiveTarget
        stateCrypto.waitDep = false
        DialogUtils.waitAndSendDialogResponse(dialogId, 0, 0, "")
        return DialogReturnVisibility()
    end

    DialogUtils.waitAndSendDialogResponse(dialogId, 1, 0, tostring(dep))
    stateCrypto.pendingDeposit = dep
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

    -- Сумму не считаем здесь: подпись кнопки - не факт выплаты.
    -- Статистику считаем по сообщению "Вы вывели N BTC/ASC" в HandleStateCryptoServerMessage.

    DialogUtils.waitAndSendDialogResponse(dialogId, 1, 0, "")
    stateCrypto.takeCount = 0
    stateCrypto.takeCurrency = nil
    stateCrypto.fillLiquidType = nil
    stateCrypto.fillLiquidLabel = nil
    stateCrypto.fillLiquidBefore = 0
    stateCrypto.fillLiquidAfter = 0
    return DialogReturnVisibility()
end

local function HandleShelfDialog(dialogId, title, text)
    if not (stateCrypto.work and title:find("Стойка") and title:find("Полка")) then
        return nil
    end

    local actions = Parser.ShelfVideoCardData(text)
    local queueShelf = stateCrypto.queueShelves[stateCrypto.progressShelves]
    local onAction = nil
    local hasCollectableTakeAction = false
    local actionDebug = {}

    for _, value in ipairs(actions) do
        table.insert(actionDebug, string.format("%s(count=%s,line=%s)",
            tostring(value.action), tostring(value.count or 0), tostring(value.samp_line or "?")))
    end
    Chat.Add(string.format("Сбор DEBUG: диалог %s, take=%s, действий=[%s]",
        tostring(dialogId), tostring(processes.take), table.concat(actionDebug, ", ")), TYPECHATMESSAGES.DEBUG)

    -- У ASC-карты сервер иногда показывает фейковую кнопку BTC вместе с ASC.
    -- Пропускаем такой BTC только если тип ASC уже определён в очереди полок.
    local hasBtcTake, hasAscTake, isVideoCard = false, false, false
    for _, value in ipairs(actions) do
        if value.action == "take_btc" then hasBtcTake = true end
        if value.action == "take_asc" then hasAscTake = true end
        if value.action == "take_video_card" then isVideoCard = true end
    end
    local isAsicShelf = text:find("ASIC") ~= nil
    local shelfCardType = queueShelf and queueShelf.card_type or nil
    local skipStuckBtc = hasBtcTake and hasAscTake and shelfCardType == "ASC"
    Chat.Add(string.format("Сбор DEBUG: BTC=%s, ASC=%s, video=%s, ASIC=%s, тип=%s, skipBTC=%s",
        tostring(hasBtcTake), tostring(hasAscTake), tostring(isVideoCard),
        tostring(isAsicShelf), tostring(shelfCardType or "?"), tostring(skipStuckBtc)), TYPECHATMESSAGES.DEBUG)

    for _, value in ipairs(actions) do
        if value.action == "on" and not onAction then
            onAction = value
        end

        if processes.take then
            if value.count > 0 and (value.action == "take_btc" or value.action == "take_asc")
                and not (skipStuckBtc and value.action == "take_btc") then
                hasCollectableTakeAction = true
                stateCrypto.takeCount = value.count
                stateCrypto.takeCurrency = (value.action == "take_btc") and "BTC" or "ASC"
                Chat.Add(string.format("Сбор DEBUG: отправляю действие %s, сумма=%s, строка=%s",
                    tostring(value.action), tostring(value.count), tostring(value.samp_line)), TYPECHATMESSAGES.DEBUG)
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

    if processes.take and queueShelf and not hasCollectableTakeAction then
        Chat.Add("Сбор DEBUG: подходящее действие забора не найдено, закрываю диалог", TYPECHATMESSAGES.DEBUG)
        if settings.main.autoEnableCards and not queueShelf.work and (queueShelf.fill or 0) > 0 and onAction then
            queueShelf.work = true
            Collect.SummaryCardEnabled()
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

    local actions = Parser.LiquidData(text)
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

    local labels = { btc = 'обычной охлаждайки BTC', supper_btc = 'супер охлаждайки BTC', asc = 'охлаждайки ASC' }
    local choice = nil
    if card == "ASC" then
        if counts.asc > 0 then choice = "asc" end
    else
        if counts.btc > 0 then
            choice = "btc"
        elseif counts.supper_btc > 0 then
            choice = "supper_btc"
        elseif (not card or card == "ASIC") and counts.asc > 0 then
            -- АСИК тоже принимает охлаждайку ASC
            choice = "asc"
        end
    end

    if choice then
        stateCrypto.waitFill = true
        stateCrypto.fillLiquidType = choice
        stateCrypto.fillLiquidLabel = labels[choice] or 'охлаждайки'
        stateCrypto.fillLiquidBefore = counts[choice] or 0
        stateCrypto.fillLiquidAfter = math.maxEx(0, (counts[choice] or 0) - 1)
        haveLiquid[choice] = stateCrypto.fillLiquidAfter
        DialogUtils.waitAndSendDialogResponse(dialogId, 1, lines[choice], "")
        return DialogReturnVisibility()
    end

    processes.fill = false
    local reason = "нет охлаждайки BTC/super"
    if card == "ASC" then
        reason = "нет охлаждайки ASC"
    elseif not card or card == "ASIC" then
        reason = "нет охлаждайки BTC/super/ASC"
    end
    -- останавливаем весь процесс и не даём автозаливке тут же запустить его снова
    stateCrypto.stopReason = reason
    stateCrypto.autoFillNoLiquid = true
    Chat.Add("Охлаждение: " .. reason .. " для текущей карты. Заливка остановлена", TYPECHATMESSAGES.CRITICAL)
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
    -- номер дома в заголовке есть не всегда: в подвале его нет
    stateCrypto.shelfListHouse = title:match("дом №(%d+)")
    -- запоминаем, каким по счёту диалогом пришёл список: по этому номеру
    -- процесс сбора понимает, что вернулся к списку, а не завис на карточке
    stateCrypto.shelfListSerial = stateCrypto.dialogSerial or 0
    FlashCollect.ApplyWindowVisibility()
    -- не фермерский диалог - возвращаемся в раздел видеокарт
    if not farmer.active then
        activeMode = "cards"
    end

    local openedViaFlash = (dialogId == idDialogs.selectVideoCardItemFlash)
    if openedViaFlash then
        housesBanks = {}
    else
        houses = {}
        housesBanks = {}
    end
    shelves = Parser.ShelfData(text)

    if settings.main.autoFillEnabled and not stateCrypto.work and not openedViaFlash
        and not stateCrypto.autoFillNoLiquid then
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
                Interacting.Start("fill")
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
        houses = Parser.HouseData(text)
    elseif text:find("Баланс") then
        housesBanks = Parser.HouseBankData(text)
    else
        return true
    end

    idDialogs.selectHouse = dialogId
    if flashCollect.waitHouseDialog and #houses > 0 then
        flashCollect.houseDialogReady = true
        flashCollect.waitHouseDialog = false
    end

    FlashCollect.ApplyWindowVisibility()
    -- не фермерский диалог - возвращаемся в раздел видеокарт
    if not farmer.active then
        activeMode = "cards"
    end
    return DialogReturnVisibility()
end

local function HandleStatsInventoryDialog(dialogId, style, title, text)
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

    local _page = text or ''
    if _page == statsLastPageText then
        if improve.oils.busy then improve.oils.busy = false; improve.oils.lastAt = os.date('%H:%M') end
        if flashCollect.statsBusy then flashCollect.statsBusy = false; flashCollect.lastStatsAt = os.date('%H:%M') end
        statsLastPageText = nil
        sampSendDialogResponse(dialogId, 0, 0, '')
        return false
    end
    statsLastPageText = _page

    if improve.oils.busy then
        Improve.ParseInventoryDialogPage(text or '')
    end
    if flashCollect.statsBusy then
        FlashCollect.ParseStatsInventoryPage(text or '')
    end

    if (text or ''):find('Следующая%sстраница') then
        local _hoff = (style == 5) and 1 or 0
        local _nextIdx = 0
        local _ln = 0
        for _line in (text or ''):gmatch('[^\r\n]+') do
            if _line:find('Следующая%sстраница') and (_ln - _hoff) >= 0 then _nextIdx = _ln - _hoff end
            _ln = _ln + 1
        end
        sampSendDialogResponse(dialogId, 1, _nextIdx, '')
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
    statsLastPageText = nil
    sampSendDialogResponse(dialogId, 0, 0, '')
    return false
end

function sampev.onShowDialog(dialogId, style, title, button1, button2, text)

    lastIDDialog = dialogId
    stateCrypto.dialogSerial = (stateCrypto.dialogSerial or 0) + 1

    pcall(Improve.CaptureCardDialog, title, text)

    local minerHandled = Miner.HandleDialog(dialogId, style, title, text)
    if minerHandled ~= nil then
        return minerHandled
    end

    local farmerHandled = Farmer.HandleDialog(dialogId, style, title, text)
    if farmerHandled ~= nil then
        return farmerHandled
    end

    local mirageHandled = Mirage.HandleDialog(dialogId, style, title, text)
    if mirageHandled ~= nil then
        return mirageHandled
    end

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

    if Improve.HandleNewStyleChooseDialog(dialogId, title, text) then
        return DialogReturnVisibility()
    end

    if Improve.HandleNewStyleConfirmDialog(dialogId, title) then
        return DialogReturnVisibility()
    end

    handled = HandleStatsInventoryDialog(dialogId, style, title, text)
    if handled ~= nil then
        return handled
    end

    -- if not stateCrypto.work then
    --     imguiWindows.main[0] = false
    -- end
end

function onDialogResponse(dialogId, button, listboxId, input)
    if tonumber(dialogId or -1) == idDialogs.mobileImproveStatus then
        return Improve.HandleMobileStatusDialogResponse(button)
    end
    if ISMONETLOADER and mobileImproveDialog.wasActive and not mobileImproveDialog.closing
        and not (mobileImproveDialog.scriptBusy or improve.cef.probing)
        and os.clock() >= (mobileImproveDialog.suppressUntil or 0) then
        return Improve.HandleMobileStatusDialogResponse(button)
    end
end
function sampev.onDialogResponse(dialogId, button, listboxId, input)
    if tonumber(dialogId or -1) == idDialogs.mobileImproveStatus then
        return Improve.HandleMobileStatusDialogResponse(button)
    end
    if ISMONETLOADER and mobileImproveDialog.wasActive and not mobileImproveDialog.closing
        and not (mobileImproveDialog.scriptBusy or improve.cef.probing)
        and os.clock() >= (mobileImproveDialog.suppressUntil or 0) then
        return Improve.HandleMobileStatusDialogResponse(button)
    end
end
-- --------------------------------------------------------
--                           onSendDialogResponse
-- --------------------------------------------------------

-- Срабатывание на отправку диалога
function sampev.onSendDialogResponse(id, btn, list, input)
    Mirage.OnDialogResponse(id, btn)

    if id == idDialogs.mobileImproveStatus then
        return Improve.HandleMobileStatusDialogResponse(btn)
    end

    if id == idDialogs.selectHouse then
        imguiWindows.main[0] = false
        houses = {}
        housesBanks ={}
    end

    if id == idDialogs.selectVideoCard then
        imguiWindows.main[0] = false
    end

end

-- 3D-текст над сараем миража: номер дома и монеты на складе
function sampev.onCreate3DText(id, color, position, distance, testLOS, attachedPlayerId, attachedVehicleId, text)
    Mirage.On3DText(id, position, text)
end

function sampev.onRemove3DText(id)
    Mirage.Remove3DText(id)
end

-- --------------------------------------------------------
--                           onWindowMessage
-- --------------------------------------------------------

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
    if ISMONETLOADER and (msg == 0x0101 or msg == 0x101) and wparam == VK_RETURN and Improve.IsMobileStatusDialogActive() then
        consumeWindowMessage(true, false)
        Improve.StopFromMobileStatus()
        return
    end

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
            UI.SwitchMainWindow()
            Interacting.Deactivate()
            Farmer.Cancel()
            Miner.Cancel()
            sampSendDialogResponse(lastIDDialog, 0, 0, "")
            shelves = {}
            houses = {}
            housesBanks = {}
        end
    end
end

-- =====================================================================================================================
--                                                          FUNCTIONS
-- =====================================================================================================================

-- hex "RRGGBB" -> imgui.ImVec4
function HexToVec4(hex, alpha)
    local r = tonumber(hex:sub(1, 2), 16) / 255
    local g = tonumber(hex:sub(3, 4), 16) / 255
    local b = tonumber(hex:sub(5, 6), 16) / 255
    return imgui.ImVec4(r, g, b, alpha or 1.0)
end

-- изменить яркость: factor > 1 — светлее, < 1 — темнее
function Shade(vec, factor, alpha)
    return imgui.ImVec4(
        math.min(vec.x * factor, 1.0),
        math.min(vec.y * factor, 1.0),
        math.min(vec.z * factor, 1.0),
        alpha or vec.w
    )
end

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
    if not numericHouseId or numericHouseId < 0 then
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
        bonusPercent = bonusPercent + 30
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

-- --------------------------------------------------------
--                           Dialog Utils
-- --------------------------------------------------------

function DialogUtils.waitForDialog(expectedDialogId, timeoutSeconds)
    local timeout = os.clock() + (timeoutSeconds or settings.deley.timeoutDialog)

    while lastIDDialog ~= expectedDialogId do
        wait(settings.deley.waitInterval)

        if os.clock() > timeout then
            return false, string.format("диалог %s не пришёл за %d сек.",
                tostring(expectedDialogId), math.floor(timeoutSeconds or settings.deley.timeoutDialog))
        end

        if not Interacting.IsActive() then
            return false, "процесс остановлен"
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
            return false, string.format("ни один из диалогов (%s) не пришёл за %d сек.",
                dialogNames, math.floor(timeoutSeconds or settings.deley.timeoutDialog))
        end

        if not Interacting.IsActive() then
            return false, "процесс остановлен"
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
                return false, string.format("сервер не ответил за %d сек.",
                    math.floor(settings.deley.timeoutDialog))
            end
            if not Interacting.IsActive() then
                return false, "процесс остановлен"
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
                card_type = shelf.card_type,
                level = tonumber(shelf.level) or 0,
                shelf_number = shelf.shelf_number
            })
        end
    end

    return filtered
end

--- Сколько раз перезаходить на полку, если сервер не ответил
function ShelfProcessor.MaxRetries()
    return math.minEx(5, math.maxEx(0, tonumber(settings.deley.shelfRetries) or 2))
end

--- Список полок сейчас на экране (последним пришёл именно он)
function ShelfProcessor.IsShelfListOpen()
    local listSerial = stateCrypto.shelfListSerial or 0
    return listSerial > 0 and listSerial == (stateCrypto.dialogSerial or 0)
end

--- Возврат к списку полок: закрываем всё, что сервер оставил открытым, пока он не
--- пришлёт список заново. Заодно обновляются данные полок дома, поэтому повторная
--- попытка идёт уже по свежему состоянию, а не по устаревшему.
--- @return boolean recovered Список полок снова на экране
function ShelfProcessor.BackToShelfList()
    if ShelfProcessor.IsShelfListOpen() then return true end

    local startSerial = stateCrypto.shelfListSerial or 0
    local deadline = os.clock() + settings.deley.timeoutDialog

    while (stateCrypto.shelfListSerial or 0) <= startSerial do
        if not Interacting.IsActive() then return false end
        if os.clock() > deadline then return false end

        sampSendDialogResponse(lastIDDialog, 0, 0, "")
        wait(300)
    end

    return true
end

--- Одна полка: открыть, дождаться результата, при зависании вернуться к списку и повторить.
--- @return string outcome "done" | "skipped" | "lost" | "cancelled"
function ShelfProcessor.RunShelf(shelfData, index)
    local attempts = ShelfProcessor.MaxRetries() + 1

    for attempt = 1, attempts do
        local listReady, listError = DialogUtils.waitForAnyDialog({
            idDialogs.selectVideoCardItemFlash,
            idDialogs.selectVideoCard
        })

        if not listReady then
            if not Interacting.IsActive() then return "cancelled" end

            Chat.Add(string.format("Полка %d: %s", index, tostring(listError)), TYPECHATMESSAGES.WARNING)
            if not ShelfProcessor.BackToShelfList() then return "lost" end
        else
            local startProgress = stateCrypto.progressShelves
            local shelfDone = function()
                return stateCrypto.progressShelves ~= startProgress
            end

            local ok, sendError = DialogUtils.sendResponseAndWait(
                lastIDDialog, 1, shelfData.samp_line, "", shelfDone
            )

            if ok then return "done" end
            if not Interacting.IsActive() then return "cancelled" end

            Chat.Add(string.format("Полка %d: %s Возвращаюсь и пробую снова (%d из %d)",
                index, tostring(sendError), attempt, attempts), TYPECHATMESSAGES.WARNING)

            -- карточка видеокарты осталась открытой: закрываем её и берём свежий список
            if not ShelfProcessor.BackToShelfList() then return "lost" end
        end
    end

    return "skipped"
end

--- @return string outcome "done" | "lost" | "cancelled"
function ShelfProcessor.process()
    stateCrypto.progressShelves = 1
    stateCrypto.queueShelves = ShelfProcessor.filterShelves()
    stateCrypto.shelvesSkipped = 0

    if #stateCrypto.queueShelves == 0 then
        Chat.Add("Отсутствуют полки для работы", TYPECHATMESSAGES.WARNING)
        return "done"
    end

    for index, shelfData in ipairs(stateCrypto.queueShelves) do
        -- пропущенные полки двигают прогресс сами, иначе обработчики диалогов
        -- будут смотреть не на ту позицию очереди, что и цикл
        if (stateCrypto.progressShelves or 0) < index then
            stateCrypto.progressShelves = index
        end

        Collect.SyncOnVisit()
        Collect.SummaryVisit(shelfData)

        local outcome = ShelfProcessor.RunShelf(shelfData, index)

        if outcome == "cancelled" then
            return "cancelled"
        elseif outcome == "lost" then
            Chat.Add(string.format("Полка %d: не удалось вернуться к списку полок", index),
                TYPECHATMESSAGES.WARNING)
            return "lost"
        elseif outcome == "skipped" then
            stateCrypto.shelvesSkipped = (stateCrypto.shelvesSkipped or 0) + 1
            stateCrypto.progressShelves = index + 1
            Chat.Add(string.format("Полка %d пропущена: сервер так и не ответил", index),
                TYPECHATMESSAGES.WARNING)
        end
    end

    if (stateCrypto.shelvesSkipped or 0) > 0 then
        Chat.Add(string.format("Пропущено полок из-за зависших диалогов: %d", stateCrypto.shelvesSkipped),
            TYPECHATMESSAGES.WARNING)
    end

    return "done"
end

-- --------------------------------------------------------
--                           House Processor
-- --------------------------------------------------------

function HouseProcessor.filterBankHouses()
    local function NeedTopupForBank(now)
        local nowNum = tonumber(now) or 0
        if settings.main.bankFillToTarget and (settings.main.bankTargetAmount or 0) > 0 then
            local target = settings.main.bankTargetAmount or 0
            local maxBank = tonumber(settings.main.maxBankAmount or 60000000) or 60000000
            return nowNum < math.minEx(target, math.maxEx(0, maxBank - 1))
        else
            -- сервер принимает пополнение только ниже полного лимита банка
            local maxBank = tonumber(settings.main.maxBankAmount or 60000000) or 60000000
            return nowNum < math.maxEx(0, maxBank - 1)
        end
    end

    local filtered = {}
    for _, house in ipairs(housesBanks) do
        if NeedTopupForBank(house.bankNow) then
            table.insert(filtered, {
                samp_line = house.samp_line,
                house_number = house.house_number,
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

    local function WaitForBankHouseDialog()
        local timeout = os.clock() + settings.deley.timeoutDialog
        while true do
            if lastIDDialog == idDialogs.selectHouse and #housesBanks > 0 then
                return true, nil
            end

            wait(settings.deley.waitInterval)
            if os.clock() > timeout then
                return false, "Timeout waiting for current bank house dialog"
            end
            if not Interacting.IsActive() then
                return false, "процесс остановлен"
            end
        end
    end

    for index, houseData in ipairs(stateCrypto.queueHousesBank) do
        local success, error = WaitForBankHouseDialog()
        if not success then
            Chat.Add("Ошибка ожидания диалога дома: " .. error, TYPECHATMESSAGES.CRITICAL)
            return false
        end
        Collect.SyncBankBegin(houseData)

        sampSendDialogResponse(lastIDDialog, 1, houseData.samp_line, "")
        lastOpenHouse = index
        stateCrypto.waitDep = true

        -- Ждем завершения операции депозита
        local timeout = os.clock() + settings.deley.timeoutDialog
        while stateCrypto.waitDep do
            wait(settings.deley.waitInterval)
            if os.clock() > timeout then
                Chat.Add("Timeout при ожидании депозита", TYPECHATMESSAGES.CRITICAL)
                return false
            end
            if not Interacting.IsActive() then
                return false
            end
        end

        local function NeedTopupForBankValue(now)
            local nowNum = tonumber(now) or 0
            if settings.main.bankFillToTarget and (settings.main.bankTargetAmount or 0) > 0 then
                local target = settings.main.bankTargetAmount or 0
                local maxBank = tonumber(settings.main.maxBankAmount or 60000000) or 60000000
                return nowNum < math.minEx(target, math.maxEx(0, maxBank - 1))
            else
                local maxBank = tonumber(settings.main.maxBankAmount or 60000000) or 60000000
                return nowNum < math.maxEx(0, maxBank - 1)
            end
        end

        -- Повторяем пополнение, пока не достигнем цели/максимума.
        while NeedTopupForBankValue(houseData.bankNow) do
            if lastIDDialog ~= idDialogs.selectHouse then
                timeout = os.clock() + settings.deley.timeoutDialog
                while NeedTopupForBankValue(houseData.bankNow) and lastIDDialog ~= idDialogs.selectHouse do
                    wait(settings.deley.waitInterval)
                    if os.clock() > timeout then
                        Chat.Add("Timeout при ожидании повторного диалога депозита", TYPECHATMESSAGES.CRITICAL)
                        return false
                    end
                    if not Interacting.IsActive() then
                        return false
                    end
                end
                if not NeedTopupForBankValue(houseData.bankNow) then
                    break
                end
            end

            success, error = WaitForBankHouseDialog()
            if not success then
                Chat.Add("Ошибка ожидания списка домов для повторного депозита: " .. error, TYPECHATMESSAGES.CRITICAL)
                return false
            end

            sampSendDialogResponse(lastIDDialog, 1, houseData.samp_line, "")
            stateCrypto.waitDep = true

            timeout = os.clock() + settings.deley.timeoutDialog
            while stateCrypto.waitDep do
                wait(settings.deley.waitInterval)
                if os.clock() > timeout then
                    Chat.Add("Timeout при повторном депозите", TYPECHATMESSAGES.CRITICAL)
                    return false
                end
                if not Interacting.IsActive() then
                    return false
                end
            end
        end

        Collect.SyncBankEnd("complete")
        stateCrypto.progressHousesBank = stateCrypto.progressHousesBank + 1
    end

    return true
end

--- Сколько раз перезаходить в дом, который не отработал целиком
function HouseProcessor.MaxRetries()
    return math.minEx(3, math.maxEx(0, tonumber(settings.deley.houseRetries) or 1))
end

--- Возврат к списку домов: закрываем всё, что осталось открытым.
--- Раньше этот цикл был без таймаута и слал ответы каждые 10 мс - если сервер
--- список так и не присылал, сбор вис намертво.
--- @return boolean recovered Список домов снова на экране
function HouseProcessor.BackToHouseList()
    local deadline = os.clock() + settings.deley.timeoutDialog

    while lastIDDialog ~= idDialogs.selectHouse do
        if not Interacting.IsActive() then return false end
        if os.clock() > deadline then return false end

        sampSendDialogResponse(lastIDDialog, 0, 0, "")
        wait(300)
    end

    return true
end

--- Один дом: открыть, дождаться полок, обойти их.
--- @return string outcome "done" | "retry" | "cancelled"
function HouseProcessor.RunHouse(houseData, index)
    local listReady, listError = DialogUtils.waitForDialog(idDialogs.selectHouse)
    if not listReady then
        if not Interacting.IsActive() then return "cancelled" end
        Chat.Add("Список домов: " .. tostring(listError), TYPECHATMESSAGES.WARNING)
        return "retry"
    end

    -- Очищаем данные полок для нового дома
    shelves = {}
    stateCrypto.queueShelves = {}

    sampSendDialogResponse(lastIDDialog, 1, houseData.samp_line, "")
    lastOpenHouse = index
    stateCrypto.currentHouseId = houses[index] and houses[index].house_number or nil
    Collect.SyncBeginHouse(stateCrypto.currentHouseId, index)
    if stateCrypto.currentHouseId and not collectStats.house[stateCrypto.currentHouseId] then
        collectStats.house[stateCrypto.currentHouseId] = { BTC = 0, ASC = 0 }
    end

    -- Ждем загрузки полок с таймаутом
    local timeout = os.clock() + settings.deley.timeoutShelf
    while #shelves == 0 do
        wait(50)

        if not Interacting.IsActive() then return "cancelled" end

        if os.clock() > timeout then
            Chat.Add("Не смог получить полки для дома " .. index, TYPECHATMESSAGES.WARNING)
            return "retry"
        end
    end

    local outcome = ShelfProcessor.process()
    if outcome == "cancelled" then return "cancelled" end
    if outcome == "lost" then return "retry" end

    return "done"
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
        local attempts = HouseProcessor.MaxRetries() + 1
        local houseDone = false

        for attempt = 1, attempts do
            local outcome = HouseProcessor.RunHouse(houseData, index)

            if outcome == "cancelled" then return false end
            if outcome == "done" then
                houseDone = true
                break
            end

            -- дом не отработал: возвращаемся к списку домов и заходим заново
            if not HouseProcessor.BackToHouseList() then
                Chat.Add("Не удалось вернуться к списку домов, сбор остановлен", TYPECHATMESSAGES.CRITICAL)
                stateCrypto.stopReason = "не удалось вернуться к списку домов"
                return false
            end

            if attempt < attempts then
                Chat.Add(string.format("Дом %d: перепроверяю (попытка %d из %d)",
                    index, attempt + 1, attempts), TYPECHATMESSAGES.WARNING)
            else
                Chat.Add(string.format("Дом %d пропущен после %d попыток, иду к следующему",
                    index, attempts), TYPECHATMESSAGES.WARNING)
            end
        end

        -- Закрываем диалог дома
        if not HouseProcessor.BackToHouseList() then
            Chat.Add("Не удалось вернуться к списку домов, сбор остановлен", TYPECHATMESSAGES.CRITICAL)
            stateCrypto.stopReason = "не удалось вернуться к списку домов"
            return false
        end

        if houseDone then
            Collect.SyncEndHouse("complete")
        else
            Collect.SyncEndHouse("interrupted", "дом пропущен после повторов")
        end

        stateCrypto.progressHouses = stateCrypto.progressHouses + 1

        if processes.take and stateCrypto.currentHouseId and collectStats.house[stateCrypto.currentHouseId] then
            local s = collectStats.house[stateCrypto.currentHouseId]
            Chat.Add(string.format(
                "Дом №%s: собрано %s BTC и %s ASC",
                tostring(stateCrypto.currentHouseId), s.BTC or 0, s.ASC or 0
            ), TYPECHATMESSAGES.SECONDARY)
        end
        stateCrypto.currentHouseId = nil
    end

    return true
end

function Interacting.Start(action, source)
    if stateCrypto.work then Chat.Add("Процесс уже запущен", TYPECHATMESSAGES.WARNING) end
    Interacting.Deactivate()

    collectStats = { total = { BTC = 0, ASC = 0 }, house = {}, summary = Collect.NewSummary(source) }
    stateCrypto.currentHouseId = nil
    Collect.SyncStartSession()

    if action == "fill" then
        processes.fill = true
        stateCrypto.autoFillNoLiquid = false
    elseif action == "take" then
        processes.take = true
        collectStats = { total = { BTC = 0, ASC = 0 }, house = {}, summary = Collect.NewSummary(source) }
        stateCrypto.currentHouseId = nil
    elseif action == "on" then
        processes.on = true
    elseif action == "off" then
        processes.off = true
    elseif action == "dep" then
        processes.dep = true
    else
        Chat.Add("Нет действий", TYPECHATMESSAGES.CRITICAL)
        return false
    end

    -- Занят ли поток, проверяем по running/yielded: на NeoMLoader status() отработавшего
    -- потока может вернуть "suspended"
    local _status = processInteractingThread and processInteractingThread:status() or nil
    if _status == "running" or _status == "yielded" then
        processInteractingThread:terminate()
    else
        processInteractingThread = RunThreadFresh(processInteractingThread, Interacting.Process)
    end
end

function Interacting.Process()
    -- Инициализация
    stateCrypto.work = true

    local success = true

    -- Обрабатываем дома с банками
    if #housesBanks > 0 then
        success = HouseProcessor.processBankHouses()
        if not success then
            Interacting.Deactivate()
            return
        end
    end

    -- Обрабатываем обычные дома или полки напрямую
    if #houses > 0 then
        success = HouseProcessor.processRegularHouses()
    else
        Collect.SyncBeginHouse(stateCrypto.shelfListHouse, "shelves")
        local outcome = ShelfProcessor.process()
        success = outcome ~= "cancelled"
        if outcome == "done" then
            Collect.SyncEndHouse("complete")
        elseif success then
            Collect.SyncEndHouse("interrupted", "не удалось вернуться к списку полок")
        end
    end

    if not success then
        Interacting.Deactivate(stateCrypto.stopReason)
        return
    end

    -- Итоги по всем домам (если больше одного дома или просто удобно видеть общий итог)
    if ( (collectStats.total.BTC > 0) or (collectStats.total.ASC > 0) ) and processes.take then
        Chat.Add(string.format(
            "Итого за сессию: %s BTC и %s ASC",
            collectStats.total.BTC or 0, collectStats.total.ASC or 0
        ), TYPECHATMESSAGES.SUCCESS)
    end

    if processes.take then
        Collect.PrintSummary()
    end

    Interacting.Deactivate()
    Chat.Add("Обработка завершена успешно", TYPECHATMESSAGES.SUCCESS)
end

function Interacting.IsActive()
    return processes.take or processes.fill or processes.on or processes.off or processes.dep
end

function Interacting.Deactivate(reason)
    Collect.SyncEndHouse("interrupted", reason or stateCrypto.stopReason or "остановлено")
    Collect.SyncBankEnd("interrupted", reason or stateCrypto.stopReason or "остановлено")
    stateCrypto.pendingDeposit = 0
    stateCrypto.stopReason = nil
    Storage.FlushCollectLogStore()
    stateCrypto.work = false
    stateCrypto.waitFill = false
    stateCrypto.waitDep = false
    stateCrypto.takeCount = 0
    stateCrypto.takeCurrency = nil
    stateCrypto.fillLiquidType = nil
    stateCrypto.fillLiquidLabel = nil
    stateCrypto.fillLiquidBefore = 0
    stateCrypto.fillLiquidAfter = 0
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
function Improve.WriteLogLine(line)
    if not IMPROVE_LOGS_DIR or not line or line == "" then return end

    local filename = os.date('%Y-%m-%d') .. ".log"
    local fullPath = IMPROVE_LOGS_DIR .. filename

    local folderPath = fullPath:match("^(.*[/\\])")
    if folderPath then
        pcall(Util.EnsureDirectoryExists, folderPath)
    end

    local ok, fh = pcall(io.open, fullPath, "a")
    if ok and fh then
        fh:write(line, "\n")
        fh:close()
    end
end

-- загрузка/инициализация общей статистики из JSON
function Improve.GetStatsStore()
    if not IMPROVE_STATS_FILE then return nil end

    if not improve.statsStore then
        local ok, data = pcall(Storage.LoadJSON, IMPROVE_STATS_FILE)
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
function Improve.SaveStatsStore()
    if not IMPROVE_STATS_FILE or not improve.statsStore then return end
    pcall(Storage.SaveJSON, IMPROVE_STATS_FILE, improve.statsStore)
end

-- внутренняя функция добавления записи в лог
function Improve.GetLevelStatsTemplate()
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

function Improve.EnsureLevelStats(statsObj)
    if type(statsObj) ~= 'table' then return end
    if type(statsObj.byLevel) ~= 'table' then
        statsObj.byLevel = Improve.GetLevelStatsTemplate()
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

function Improve.GetPriceByFromLevel(level)
    return tonumber(GPU_IMPROVE_PRICE_BY_LEVEL[tonumber(level or 0) or 0]) or 0
end

function Improve.LogAdd(evType, text)
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
    Improve.WriteLogLine(line)
end

-- старт сессии заточки
function Improve.SessionStart()
    Improve.GetStatsStore()

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
    s.byLevel    = Improve.GetLevelStatsTemplate()
    s.lastAttempt = nil
    s.lastReason = ""
    improve.stats = s

    local modeName  = (settings.improve.mode == 1) and "Последовательное" or "Поочередное"
    local cardsName = (settings.improve.typeCards == 2) and "Arizona" or "Обычные"
    local maxLevel  = settings.improve.maxLevel or 2
    local checkOils = settings.improve.checkOilsOnStart and "Да" or "Нет"
    local invMode   = Improve.GetInventoryModeName()

    Improve.LogAdd("INFO", string.format(
        "Старт сессии #%d. Карты: %s, режим: %s, инвентарь: %s, целевой уровень: %d, проверять смазку: %s.",
        s.sessionId, cardsName, modeName, invMode, maxLevel, checkOils
    ))
end

-- завершение сессии заточки + обновление суточной и общей статистики
function Improve.SessionStop(reason)
    local s = improve.stats
    if not s or not s.active then return end

    s.active     = false
    s.finishedAt = os.time()
    s.lastReason = reason or s.lastReason or "не указано"

    local duration = 0
    if s.startedAt and s.startedAt > 0 then
        duration = math.maxEx(0, s.finishedAt - s.startedAt)
    end

    -- Обновляем статистику по дням и общую
    local store = Improve.GetStatsStore()
    if store then
        Improve.EnsureLevelStats(store.total)
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
        Improve.EnsureLevelStats(day)

        day.sessions  = (day.sessions  or 0) + 1
        day.attempts  = (day.attempts  or 0) + (s.attempts or 0)
        day.success   = (day.success   or 0) + (s.success  or 0)
        day.fail      = (day.fail      or 0) + (s.fail     or 0)
        day.oilsUsed  = (day.oilsUsed  or 0) + (s.oilsUsed or 0)
        day.spent     = (day.spent     or 0) + (s.spent or 0)
        day.time      = (day.time      or 0) + duration
        Improve.EnsureLevelStats(s)
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
        Improve.EnsureLevelStats(total)

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

        Improve.SaveStatsStore()
    end

    Improve.LogAdd("INFO", string.format(
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

function Improve.Stop(reason)
    Improve.CloseMobileStatusDialog(3600000)

    -- сначала аккуратно закрываем сессию
    Improve.SessionStop(reason or "остановлено вручную")

    -- потом чистим флаги автомата
    improve.isOn          = false
    improve.step          = Improve.STEP.STOPPED
    improve.needCheckOils = false
    improve.waitOils      = false
    improve.waitStart     = false
    improve.waitStartAt   = 0
    improve.waitResultAt  = 0
    improve.lastUseAt     = 0
    improve.consumedThisTry = false
    improve.currentIndex  = 0
    improve.cef.stubNotified = false
    improve.cef.needInventoryRefresh = true
    improve.cef.waitInventory = false
    improve.cef.probing = false
    improve.cef.probed = false
    improve.cef.upgradeFast = false
    improve.cef.upgradeFastFails = 0
    improve.cef.pendingSlot = nil
    improve.cef.pendingIndex = 0
    improve.cef.probeAbort = false
    improve.cef.probeAbortReason = ''
    improve.cef.probeProgress = 0
    improve.cef.probeTotal = 0
end

function Improve.AttemptStart()
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
        Improve.EnsureLevelStats(s)
        price = Improve.GetPriceByFromLevel(fromLevel)
        s.spent = (s.spent or 0) + price
        local row = s.byLevel[fromLevel] or { attempts = 0, success = 0, fail = 0, spent = 0 }
        row.attempts = (row.attempts or 0) + 1
        row.spent = (row.spent or 0) + price
        s.byLevel[fromLevel] = row
        s.lastAttempt.spent = price
    end

    Improve.LogAdd("INFO", string.format(
        "Попытка #%d: карта #%d, уровень %d, улучшение хранилища: %s, стоимость: $%d.",
        s.attempts, idx, level, storageUpgrade and "есть" or "нет", price
    ))
end

-- ===== БАЗОВАЯ ЛОГИКА =====

function Improve.GetOilCountByType()
    local isAZ = (settings.improve.typeCards == 2)
    local count = isAZ and (improve.oils.arizona or 0) or (improve.oils.classic or 0)
    local name  = isAZ and "Смазка для разгона Arizona Video Card" or "Смазка для разгона видеокарты"
    return count, name
end

function Improve.HasRequiredOils(n)
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

function Improve.ConsumeOils(n)
    n = n or 2
    if settings.improve.typeCards == 2 then
        improve.oils.arizona = math.maxEx(0, (improve.oils.arizona or 0) - n)
    else
        improve.oils.classic = math.maxEx(0, (improve.oils.classic or 0) - n)
    end

    if improve.stats and improve.stats.active then
        improve.stats.oilsUsed = (improve.stats.oilsUsed or 0) + n
    end

    Improve.LogAdd("INFO", string.format(
        "Списано %d смазки. Остаток: Arizona=%d, Обычная=%d.",
        n, improve.oils.arizona or 0, improve.oils.classic or 0
    ))
end

function Improve.ResetOilCounters()
    improve.oils.arizona, improve.oils.classic = 0, 0
end

function Improve.ParseInventoryDialogPage(text)
    for line in (text or ''):gmatch("[^\r\n]+") do
        local indexSlot, name, count = line:match("%[([^%]]+)%]%s*(.-)%s*%[(%d+)%s*шт%]")
        local slotNum = tonumber(indexSlot)
        count = tonumber(count)
        if name then name = name:gsub("{%x+}", ""):gsub("%s+$", "") end
        if indexSlot and name and count then
            if name == "Смазка для разгона Arizona Video Card" then
                improve.oils.arizona = improve.oils.arizona + count
            elseif name == "Смазка для разгона видеокарты" then
                improve.oils.classic = improve.oils.classic + count
            end

            if slotNum and count > 0 then
                local cardType, cardStorage = Improve.ParseCardMetaFromName(name)
                if cardType ~= nil then
                    Improve.AddCefCardSlot(slotNum, name, cardStorage, cardType)
                end
            end
        end
    end
end

-- Запуск обновления
function Improve.RefreshOils(async)
    if improve.oils.busy then return end
    Improve.ResetOilCounters()
    Improve.ResetCefInventory()
    improve.oils.busy = true
    Improve.LogAdd("INFO", "Запрос /stats для обновления инвентаря смазок и видеокарт.")
    sampSendChat('/stats')

    if async then
        -- ждать /stats уходим в отдельный поток; он создан заранее приостановленным,
        -- потому что RefreshOils зовут в том числе из фонового потока
        improve.oilsThread = RunThreadFresh(improve.oilsThread, Improve.OilsWaitProcess)
    else
        Improve.OilsWaitProcess()
        return true
    end
end

-- Ждём окончания разбора /stats и пишем результат в лог
function Improve.OilsWaitProcess()
    while improve.oils.busy do wait(10) end
    Improve.LogOilsResult()
end

-- Итог обновления инвентаря смазок и видеокарт
function Improve.LogOilsResult()
    Improve.LogAdd("INFO", string.format(
        "Инвентарь обновлён: Arizona=%d, Обычная=%d, видеокарты=%d.",
        improve.oils.arizona or 0,
        improve.oils.classic or 0,
        #(improve.cef.cards or {})
    ))

    -- После ручного обновления сразу показываем найденные слоты видеокарт в UI.
    if Improve.IsNewStyleMode() then
        Improve.SyncVideoCardsFromCef()
        improve.cef.probed = false
    end
end

-- Результат заточки (успех/ошибка) - обновляем уровень в кэше
function Improve.OnResult(success, serverMsg)
    if not improve.currentIndex or improve.currentIndex <= 0 then return end

    local card = improve.videoCards[improve.currentIndex]
    if not card then return end

    local _resFrom = tonumber(card.level) or 0
    improve.lastResult = {
        ok = success == true, slot = card.slot, from = _resFrom, to = _resFrom,
        storage = improve.useStorageUpgrade == true, at = os.time(),
    }

    if improve.useStorageUpgrade then

        if success then
            card.storageUpgrade = success
            Improve.UpdateCefCardLevel(card.slot, nil, true)
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
            Improve.LogAdd("SUCCESS", string.format(
                "Попытка #%d: УСПЕХ. Карта #%d, улучшенное хранилище.",
                attemptNo, improve.currentIndex or 0
            ))
        else
            Improve.LogAdd("WARN", string.format(
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
                local lvlText = serverMsg:match("до%s+(%d+)%D+уров") or serverMsg:match("до%s+(%d+)%s+уровн")
                if lvlText then
                    parsedLvl = tonumber(lvlText)
                end
            end

            newLvl = parsedLvl or (oldLvl + 1)
            if newLvl > 10 then newLvl = 10 end
            card.level = newLvl
            card.levelKnown = true
            Improve.UpdateCefCardLevel(card.slot, newLvl, nil)
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
                Improve.EnsureLevelStats(s)
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
            Improve.LogAdd("SUCCESS", string.format(
                "Попытка #%d: УСПЕХ. Карта #%d, уровень %d -> %d.",
                attemptNo, improve.currentIndex or 0, oldLvl, newLvl
            ))
        else
            Improve.LogAdd("WARN", string.format(
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
        improve.videoCards = Improve.MoveMaxLevelCardsToEnd(improve.videoCards)
        improve.lastResult.to = tonumber(card.level) or _resFrom
    end
end

function Improve.MarkAttemptTimedOut()
    local _card = improve.videoCards[tonumber(improve.currentIndex or 0) or 0]
    improve.lastResult = { timeout = true, slot = _card and _card.slot or 0, at = os.time() }

    local s = improve.stats
    if not (s and s.active) then return end

    s.fail = (s.fail or 0) + 1

    local fromLevel = s.lastAttempt and tonumber(s.lastAttempt.fromLevel or 0) or 0
    if fromLevel >= 1 and fromLevel <= 9 then
        Improve.EnsureLevelStats(s)
        local row = s.byLevel[fromLevel] or { attempts = 0, success = 0, fail = 0, spent = 0 }
        row.fail = (row.fail or 0) + 1
        s.byLevel[fromLevel] = row
    end

    s.lastAttempt = nil
end

function Improve.TickWaitWatchdogs()
    if not improve.isOn then return end

    local now = os.clock()

    if improve.step == Improve.STEP.CONFIRM then
        local retryMs = tonumber(settings.deley.improve_retryUseDelay or 1200) or 1200
        if retryMs < 200 then retryMs = 200 end

        if not improve.waitStart then
            if (improve.lastUseAt or 0) <= 0 then
                improve.lastUseAt = now
            elseif (now - improve.lastUseAt) * 1000 >= retryMs then
                if improve.cef.upgradeFast then
                    improve.cef.upgradeFast = false
                    improve.cef.upgradeFastFails = (improve.cef.upgradeFastFails or 0) + 1
                    if improve.cef.upgradeFastFails >= 2 then
                        Improve.LogAdd('INFO', 'Новый стиль: клик без /invent не срабатывает, переоткрываю инвентарь перед каждой картой.')
                    end
                end
                local idx = tonumber(improve.currentIndex or 0) or 0
                local card = improve.videoCards[idx]
                local slot = card and tonumber(card.slot or 0) or 0
                if slot > 0 then
                    Improve.OpenCardDialog(slot, 1, 1)
                    improve.lastUseAt = now
                else
                    improve.step = Improve.STEP.SELECT_CARD
                    improve.consumedThisTry = false
                    improve.lastUseAt = 0
                end
            end
        else
            local waitStartTimeout = tonumber(settings.deley.improve_waitStartTimeout or 8) or 8
            if waitStartTimeout < 1 then waitStartTimeout = 1 end
            local startedAt = tonumber(improve.waitStartAt or 0) or 0
            if startedAt > 0 and (now - startedAt) >= waitStartTimeout then
                Improve.LogAdd("WARN", string.format(
                    "Таймаут ожидания старта улучшения (%d сек). Возвращаюсь к выбору карты.",
                    waitStartTimeout
                ))
                improve.waitStart = false
                improve.waitStartAt = 0
                improve.step = Improve.STEP.SELECT_CARD
                improve.consumedThisTry = false
            end
        end
    elseif improve.step == Improve.STEP.WAIT_RESULT then
        local waitResultTimeout = tonumber(settings.deley.improve_waitResultTimeout or 20) or 20
        if waitResultTimeout < 1 then waitResultTimeout = 1 end
        local startedAt = tonumber(improve.waitResultAt or 0) or 0
        if startedAt > 0 and (now - startedAt) >= waitResultTimeout then
            Improve.LogAdd("WARN", string.format(
                "Таймаут ожидания результата улучшения (%d сек). Фиксирую попытку как неудачную и продолжаю.",
                waitResultTimeout
            ))
            Improve.MarkAttemptTimedOut()
            improve.waitResultAt = 0
            improve.step = Improve.STEP.SELECT_CARD
            improve.consumedThisTry = false
        end
    end
end

-- Шаговая машина состояний
function Improve.Tick()
    if not improve.isOn then return end

    Improve.TickWaitWatchdogs()
    if improve.waitOils then return end -- Ждем смазки

    Improve.TickNewStyle()
end


-- --------------------------------------------------------
--                           Load
-- --------------------------------------------------------

-- Сообщения о повреждённых файлах копятся до старта main(): Chat.Add работает
-- только после загрузки настроек, а Settings.json читается самым первым
Storage.brokenFilesNotice = {}

function Storage.NoticeBrokenFile(message)
    print("[MMT] "..tostring(message))
    table.insert(Storage.brokenFilesNotice, tostring(message))
end

--- Выводит накопленные предупреждения в чат. Вызывается из main()
function Storage.FlushBrokenFilesNotice()
    if #Storage.brokenFilesNotice == 0 then return end

    for _, message in ipairs(Storage.brokenFilesNotice) do
        Chat.Add(message, TYPECHATMESSAGES.WARNING)
    end
    Storage.brokenFilesNotice = {}
end

--- Убирает нечитаемый файл в сторону, чтобы скрипт стартовал с чистого листа,
--- а сам файл остался для разбора
function Storage.QuarantineBrokenFile(filePatch, reason)
    local _broken = filePatch..".broken"
    os.remove(_broken)

    if not os.rename(filePatch, _broken) then
        os.remove(filePatch)
        _broken = nil
    end

    Storage.NoticeBrokenFile(string.format("Файл %s повреждён (%s).%s",
        filePatch, tostring(reason),
        _broken and (" Копия для разбора: ".._broken) or " Файл удалён."))
end

--- Читает и разбирает JSON.
--- @return table|nil data Данные файла
--- @return string|nil reason Причина, если файл есть, но не читается.
---         nil в обоих значениях - файла просто нет или он пустой, это не ошибка
function Storage.ReadJSONFile(filePatch)
    local _file = io.open(filePatch, "rb")
    if not _file then return nil, nil end

    local _content = _file:read("*a")
    _file:close()

    if not _content or not _content:match("%S") then return nil, nil end

    -- блокнот и подобные редакторы дописывают BOM, cjson на нём падает
    if _content:sub(1, 3) == "\239\187\191" then
        _content = _content:sub(4)
        if not _content:match("%S") then return nil, nil end
    end

    local _ok, _data = pcall(json.decode, _content)

    if not _ok then
        -- из "MMT.lua:4040: текст ошибки" оставляем только текст
        local _reason = tostring(_data)
        _reason = _reason:gsub("^.-:%d+:%s*", "")
        return nil, _reason
    end

    if type(_data) ~= "table" then return nil, "внутри не объект JSON" end

    return _data, nil
end

--- Битый файл не должен ронять весь скрипт. Обычно он получается, когда игра падает
--- во время записи: размер файла Windows уже увеличила, а данные сбросить не успела,
--- и внутри остаются нули - cjson отвечает на них
--- "JSON parser does not support UTF-16 or UTF-32" и бросает ошибку наружу.
function Storage.LoadJSON(filePatch)
    local _data, _reason = Storage.ReadJSONFile(filePatch)
    if _data then return _data end
    if not _reason then return {} end

    Storage.QuarantineBrokenFile(filePatch, _reason)

    -- рядом лежит предыдущее удачное сохранение - шанс не потерять логи
    local _backup = Storage.ReadJSONFile(filePatch..".bak")
    if _backup then
        Storage.NoticeBrokenFile(string.format("Данные восстановлены из %s.bak", filePatch))
        return _backup
    end

    return {}
end

function Storage.LoadSettings()
    local _settings = Storage.LoadJSON(PATCHCONFIG..'Settings.json')
    if not _settings then
        _settings = {}
    end
    -- до версии 2 Telegram включался одной общей галочкой и списком config
    local oldNotify = type(_settings.notifications) == 'table' and _settings.notifications.version == nil
        and _settings.notifications or nil
    local oldEnabled = oldNotify and oldNotify.enabled == true
    local oldConfig = oldNotify and type(oldNotify.config) == 'table' and oldNotify.config or nil

    -- сливаем настройки с дефолтными
    Storage.MergeSettings(_settings, defaultSettings)

    if oldNotify then
        for kind in pairs(_settings.notifications.tg) do
            _settings.notifications.tg[kind] = oldEnabled and (oldConfig == nil or oldConfig[kind] ~= false)
        end
        _settings.notifications.enabled = nil
        _settings.notifications.config = nil
    end
    if tonumber(_settings.main.maxBankAmount or 0) < 60000000 then
        _settings.main.maxBankAmount = 60000000
    end
    settings = _settings
    return _settings
end

function Storage.MergeSettings(dest, source)
    for key, value in pairs(source) do
        if type(value) == "table" then
            if not dest[key] then
                dest[key] = {}
            end
            Storage.MergeSettings(dest[key], value)
        else
            if dest[key] == nil then
                dest[key] = value
            end
        end
    end
end

--- Копирует файл побайтно: запасной путь, если os.rename не сработал
function Storage.CopyFile(src, dst)
    local input = io.open(src, "rb")
    if not input then return false end
    local data = input:read("*a")
    input:close()

    local output = io.open(dst, "wb")
    if not output then return false end
    output:write(data or "")
    output:close()
    return true
end

--- Переносит данные MMT на ПК из старой папки (<папка игры>\config\MMT CFGs)
--- в moonloader\config\MMT CFGs. Файл, который уже есть на новом месте, не трогаем.
function Storage.MigrateLegacyConfig()
    if ISMONETLOADER or type(getGameDirectory) ~= 'function' then return end

    local oldDir = getGameDirectory()..SEPORATORPATCH..'config'..SEPORATORPATCH..'MMT CFGs'
    local newDir = folderConfig..'MMT CFGs'
    if oldDir:lower() == newDir:lower() or lfs.attributes(oldDir, "mode") ~= "directory" then return end

    local moved, failed = 0, 0
    local function moveDir(from, to)
        Util.EnsureDirectoryExists(to)

        -- сначала собираем имена: переименование во время обхода lfs.dir пропускает файлы
        local names = {}
        for name in lfs.dir(from) do
            if name ~= "." and name ~= ".." then
                names[#names + 1] = name
            end
        end

        for _, name in ipairs(names) do
            local src, dst = from..SEPORATORPATCH..name, to..SEPORATORPATCH..name
            local mode = lfs.attributes(src, "mode")
            if mode == "directory" then
                moveDir(src, dst)
            elseif mode == "file" and not lfs.attributes(dst, "mode") then
                if os.rename(src, dst) or (Storage.CopyFile(src, dst) and os.remove(src)) then
                    moved = moved + 1
                else
                    failed = failed + 1
                end
            end
        end

        -- папка удалится, только если опустела
        lfs.rmdir(from)
    end

    local ok, err = pcall(moveDir, oldDir, newDir)
    if not ok then
        Storage.NoticeBrokenFile("Не удалось перенести данные из "..oldDir..": "..tostring(err))
    elseif moved > 0 or failed > 0 then
        Storage.NoticeBrokenFile(string.format("Данные перенесены в %s (файлов: %d%s).",
            newDir, moved, failed > 0 and (", не перенесено: "..failed..", они остались в "..oldDir) or ""))
    end
end

Storage.MigrateLegacyConfig()
Storage.LoadSettings()

if ISMONETLOADER and settings.style.scaleUI ~= 1.0 then
    MONET_DPI_SCALE = settings.style.scaleUI
elseif ISMONETLOADER then
    settings.style.scaleUI = MONET_DPI_SCALE
end

-- Окно на мобилке по умолчанию такого же размера, как у MCR Mobile. Старый дефолт
-- 600x400 без учёта масштаба на телефоне выходил крошечным - его тоже заменяем.
if ISMONETLOADER then
    defaultSettings.style.sizeWindow = { x = 700 * MONET_DPI_SCALE, y = 400 * MONET_DPI_SCALE }
    local size = settings.style.sizeWindow
    if type(size) ~= 'table' or (tonumber(size.x) == 600 and tonumber(size.y) == 400) then
        settings.style.sizeWindow = { x = defaultSettings.style.sizeWindow.x, y = defaultSettings.style.sizeWindow.y }
    end
end

-- --------------------------------------------------------
--                           Save
-- --------------------------------------------------------

--- Пишет JSON через временный файл и подменяет им основной. Прямая запись в основной
--- файл оставляла после падения игры обрезанный или забитый нулями JSON, из-за чего
--- скрипт потом не стартовал. Предыдущее сохранение остаётся рядом как .bak.
function Storage.SaveJSON(filePatch, data)
    local folderPath = string.match(filePatch, "^(.*[/\\])")
    if folderPath then
        Util.EnsureDirectoryExists(folderPath)
    end

    -- кодируем до открытия файла: ошибка кодирования не должна обнулять то,
    -- что уже лежит на диске
    local _ok, _encoded = pcall(json.encode, data)
    if not _ok or type(_encoded) ~= "string" then
        print("[MMT] Не удалось закодировать "..filePatch..": "..tostring(_encoded))
        return false
    end

    local _tempPatch = filePatch..".tmp"
    local _file = io.open(_tempPatch, "wb")
    if not _file then return false end

    local _written = pcall(_file.write, _file, _encoded)
    _file:close()

    if not _written then
        os.remove(_tempPatch)
        return false
    end

    -- прошлую версию не удаляем, а отводим в .bak: если игра упадёт между
    -- переименованиями, данные останутся хотя бы в одном из двух файлов
    local _backupPatch = filePatch..".bak"
    os.remove(_backupPatch)
    os.rename(filePatch, _backupPatch)

    if not os.rename(_tempPatch, filePatch) then
        -- подменить не вышло: возвращаем прошлую версию на место
        os.rename(_backupPatch, filePatch)
        os.remove(_tempPatch)
        print("[MMT] Не удалось заменить "..filePatch.." новой версией")
        return false
    end

    return true
end

function Storage.SaveSettings()
    local success = Storage.SaveJSON(PATCHCONFIG .. 'Settings.json', settings)
    if not success then
        print("Ошибка: Не удалось сохранить настройки!")
    end
end

function Storage.LoadCollectLogStore()
    local data = Storage.LoadJSON(COLLECT_STATS_FILE)
    if type(data) ~= "table" then
        collectLogStore = {
            days = {},
            meta = {}
        }
        return
    end

    data.days = type(data.days) == "table" and data.days or {}
    data.meta = type(data.meta) == "table" and data.meta or {}

    if type(data.meta.lastCollect) ~= "table" then
        data.meta.lastCollect = nil
    end

    collectLogStore = data

    if Collect.TrimLogStoreDetails() then
        Storage.SaveCollectLogStore()
    end
end

function Storage.SaveCollectLogStore()
    collectLogStore.days = collectLogStore.days or {}
    collectLogStore.meta = collectLogStore.meta or {}
    local success = Storage.SaveJSON(COLLECT_STATS_FILE, collectLogStore)
    if success then
        collectLogSave.dirty = false
        collectLogSave.lastAt = os.clock()
    end
    return success
end

function Storage.RequestSaveCollectLogStore(force)
    collectLogSave.dirty = true
    local now = os.clock()
    if force or (now - (collectLogSave.lastAt or 0)) >= (collectLogSave.minInterval or 2) then
        return Storage.SaveCollectLogStore()
    end
    return false
end

function Storage.FlushCollectLogStore()
    if collectLogSave.dirty then
        return Storage.SaveCollectLogStore()
    end
    return true
end

-- Логи теплиц и майнера пишутся с троттлингом в 2 секунды: если запись попала в паузу,
-- она оставалась только в памяти до конца процесса. Досохраняем её фоном
function Storage.FlushResourceLogs()
    local now = os.clock()
    if greenhouseLog.dirty and (now - (greenhouseLog.lastSaveAt or 0)) >= 5 then
        Storage.SaveGreenhouseLog()
    end
    if minerLog.dirty and (now - (minerLog.lastSaveAt or 0)) >= 5 then
        Storage.SaveMinerLog()
    end
end

function Collect.GetMaxLogItemsPerHouseDay()
    local value = tonumber(settings.main and settings.main.collectLogMaxItemsPerHouseDay or 300) or 300
    return math.maxEx(0, math.floor(value))
end

function Collect.TrimHouseLogItems(houseData, maxItems)
    if type(houseData) ~= 'table' or type(houseData.items) ~= 'table' then
        return false
    end

    local items = houseData.items
    maxItems = tonumber(maxItems) or 0
    if maxItems <= 0 then
        local removed = #items
        if removed <= 0 then return false end
        houseData.items = {}
        houseData.itemsTrimmed = (tonumber(houseData.itemsTrimmed) or 0) + removed
        return true
    end

    local count = #items
    if count <= maxItems then
        return false
    end

    local removed = count - maxItems
    local trimmedItems = {}
    local startIndex = removed + 1
    for i = startIndex, count do
        table.insert(trimmedItems, items[i])
    end
    houseData.items = trimmedItems
    houseData.itemsTrimmed = (tonumber(houseData.itemsTrimmed) or 0) + removed
    return true
end

function Collect.TrimLogStoreDetails()
    local maxItems = Collect.GetMaxLogItemsPerHouseDay()
    local changed = false
    for _, dayData in pairs(collectLogStore.days or {}) do
        for _, houseData in pairs((dayData and dayData.houses) or {}) do
            if Collect.TrimHouseLogItems(houseData, maxItems) then
                changed = true
            end
        end
    end
    return changed
end

function Collect.NormalizeCryptoAmount(amount)
    amount = tonumber(amount) or 0
    return math.floor(amount * 1000 + 0.5) / 1000
end

function Collect.GetLastCollectInfo()
    local meta = collectLogStore.meta or {}
    local info = meta.lastCollect
    if type(info) ~= "table" then return nil end

    local timestamp = tonumber(info.timestamp or 0) or 0
    if timestamp <= 0 then return nil end

    info.timestamp = timestamp
    info.amount = Collect.NormalizeCryptoAmount(info.amount)
    info.houseId = tostring(info.houseId or "0")
    info.currency = tostring(info.currency or "BTC")
    return info
end

function Collect.UpdateLastCollectInfo(houseId, currency, amount)
    collectLogStore.meta = collectLogStore.meta or {}
    collectLogStore.meta.lastCollect = {
        timestamp = os.time(),
        houseId = tostring(houseId or 0),
        currency = tostring(currency or "BTC"),
        amount = Collect.NormalizeCryptoAmount(amount),
    }
    Collect.GameState('crypto').retryAt = 0
end

function Collect.GetReminderThresholdSeconds()
    local minutes = tonumber(settings.main and settings.main.collectNotifyMinutes or 0) or 0
    if minutes <= 0 then
        return 0
    end
    return math.floor(minutes * 60)
end

function Collect.FormatDuration(seconds)
    seconds = math.maxEx(0, math.floor(tonumber(seconds) or 0))
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

function Collect.FormatLastCollectText(info)
    if type(info) ~= "table" then
        return "ещё не зафиксирован"
    end

    local timestamp = tonumber(info.timestamp or 0) or 0
    if timestamp <= 0 then
        return "ещё не зафиксирован"
    end

    return os.date('%d.%m.%Y %H:%M:%S', timestamp)
end

function Collect.GetNotifySystemState()
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

function Collect.GetNotifyInstallButtonText(state)
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

function Collect.DownloadNotificationSystem()
    if collectReminder.managerDownloadPending or collectReminder.managerEnsurePending then
        return false
    end

    collectReminder.managerDownloadPending = true
    collectReminder.managerStatusMessage = "Скачиваю менеджер уведомлений и библиотеку..."

    lua_thread.create(function()
        local function fail(message, debugInfo)
            collectReminder.managerDownloadPending = false
            collectReminder.managerStatusMessage = message
            Chat.Add(message, TYPECHATMESSAGES.WARNING)
            if debugInfo and debugInfo ~= "" then
                Chat.Add('Уведомления: ' .. tostring(debugInfo), TYPECHATMESSAGES.DEBUG)
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
            Util.EnsureDirectoryExists(getWorkingDirectory() .. SEPORATORPATCH .. 'lib')
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
        Chat.Add("Менеджер уведомлений и библиотека скачаны. Перезагружаю скрипт", TYPECHATMESSAGES.SUCCESS)

        wait(300)
        thisScript():reload()
    end)

    return true
end

function Collect.EnsureNotificationManager()
    if collectReminder.managerEnsurePending or collectReminder.managerDownloadPending then
        return false
    end

    local state = Collect.GetNotifySystemState()
    if not state.available or type(notify) ~= 'table' or type(notify.ensure_manager) ~= 'function' then
        collectReminder.managerStatusMessage = "Открыта страница установки менеджера уведомлений."
        Util.OpenUrl(NOTIFY_MANAGER_REPO_URL)
        Chat.Add("Открыта страница установки менеджера уведомлений", TYPECHATMESSAGES.SECONDARY)
        return true
    end

    collectReminder.managerEnsurePending = true
    collectReminder.managerStatusMessage = "Подготавливаю менеджер уведомлений..."

    notify.ensure_manager({ required_version = REQUIRED_NOTIFY_VERSION }, function(success, info)
        collectReminder.managerEnsurePending = false
        if success then
            collectReminder.managerStatusMessage = "Менеджер уведомлений готов к работе."
            Chat.Add("Менеджер уведомлений готов к работе", TYPECHATMESSAGES.SUCCESS)
            return
        end

        collectReminder.managerStatusMessage = "Не удалось подготовить менеджер уведомлений. Перезапустите игру или перезагрузите все скрипты."
        Chat.Add("Не удалось подготовить менеджер уведомлений. Перезапустите игру или перезагрузите все скрипты.", TYPECHATMESSAGES.WARNING)
        Chat.Add(
            'Менеджер уведомлений: ' .. tostring(info and info.message or 'неизвестная ошибка'),
            TYPECHATMESSAGES.DEBUG
        )
    end)

    return true
end

-- Состояние напоминаний в игре по событиям
function Collect.GameState(kind)
    collectReminder.game = collectReminder.game or {}
    local st = collectReminder.game[kind]
    if not st then
        st = { notifiedAt = 0, retryAt = 0, pending = false }
        collectReminder.game[kind] = st
    end
    return st
end

Collect.GAME_TITLES = {
    crypto = 'Пора собирать крипту',
    greenhouse = 'Пора собирать теплицы',
    miner = 'Пора собирать майнера',
    mirage = 'Пора собирать сарай миража',
}

-- Напоминание в игре: всплывающее окно менеджера уведомлений, без него - сообщение в чат
function Collect.SendReminderNotification(kind, lastAt, elapsedSeconds)
    local st = Collect.GameState(kind)
    local title = Collect.GAME_TITLES[kind] or 'Пора собирать'
    local text = 'С последнего сбора прошло ' .. Collect.FormatDuration(elapsedSeconds) .. '.'
    local description = 'Последний сбор: ' .. os.date('%d.%m.%Y %H:%M:%S', lastAt)

    local function toChat()
        st.notifiedAt = lastAt
        Chat.Add(title .. '. ' .. text .. ' ' .. description, TYPECHATMESSAGES.WARNING)
    end

    if not (notifySuccess and type(notify) == 'table' and type(notify.send) == 'function') then
        toChat()
        return
    end

    st.pending = true
    notify.send(REQUIRED_NOTIFY_VERSION, {
        script_id = 'MMT',
        title = u8(title),
        text = u8(text),
        description = u8(description),
        sticky = true,
        theme = 'emerald',
        -- кнопка "Запустить сбор" есть только у крипты
        action = (kind == 'crypto') and collectReminderAction or nil,
    }, function(success, notifyInfo)
        st.pending = false
        if success then
            st.notifiedAt = lastAt
            st.retryAt = 0
            return
        end
        -- менеджер уведомлений не принял - напоминание всё равно не теряем
        toChat()
        Chat.Add('Менеджер уведомлений: ' .. tostring(notifyInfo and notifyInfo.message or 'неизвестная ошибка'),
            TYPECHATMESSAGES.DEBUG)
    end)
end

function Collect.ReminderTick()
    local nowClock = os.clock()
    if (nowClock - (collectReminder.lastTickAt or 0)) < 1 then
        return
    end
    collectReminder.lastTickAt = nowClock

    local now = os.time()
    for _, kind in ipairs(Collect.TG_KINDS) do
        local id = kind.id
        if settings.notifications.game[id] then
            local st = Collect.GameState(id)
            local lastAt, minutes = Collect.TgReminderSource(id)
            if not st.pending and now >= st.retryAt and minutes > 0 and lastAt > 0
                and st.notifiedAt ~= lastAt
                and (now - lastAt) >= minutes * 60
                and not Collect.TgKindBusy(id)
            then
                Collect.SendReminderNotification(id, lastAt, now - lastAt)
            end
        end
    end
end

-- ===== Уведомления в Telegram =====
-- Два способа, как в MCR ПК: свой бот (api.telegram.org) или бот MCR Notification
-- (API MCR, нужен ключ MCR). Запросы уходят из отдельного effil-потока, чтобы игра
-- не подвисала; ответы забирает фоновый цикл через Collect.TgTick().

collectReminder.tg = {
    worker = nil,
    reqCh = nil,
    resCh = nil,
    initError = nil,
    pending = 0,
    tickAt = -1000,
    retryAt = {},              -- [вид] = os.time(), раньше которого не повторяем
    keyCache = nil,
    keySource = '',
    keyCheckedAt = -1000,
    keyEdit = false,
    buf = {},
    lastResult = '',
}

Collect.TG_KINDS = {
    { id = 'crypto',     label = 'Пора собирать крипту',       short = 'Крипта' },
    { id = 'greenhouse', label = 'Пора собирать теплицы',      short = 'Теплицы' },
    { id = 'miner',      label = 'Пора собирать майнера',      short = 'Майнер' },
    { id = 'mirage',     label = 'Пора собирать сарай миража', short = 'Сарай миража' },
}

-- Где лежит интервал напоминания для события
Collect.REMINDER_MINUTES = {
    crypto = { 'main', 'collectNotifyMinutes' },
    greenhouse = { 'farmer', 'notifyMinutes' },
    miner = { 'miner', 'notifyMinutes' },
    mirage = { 'mirage', 'notifyMinutes' },
}

Collect.TG_MCR_URLS = {
    'https://api.arz-mcr.ru/v1/bot/notifications',
    'https://api.arz-mcr.top/v1/bot/notifications',
}

function Collect.TgTrim(s)
    local r = tostring(s or ''):gsub('^%s+', '')
    r = r:gsub('%s+$', '')
    return r
end

function Collect.TgReadFile(path)
    local ok, fh = pcall(io.open, path, 'rb')
    if not ok or not fh then return nil end
    local data = fh:read('*a')
    fh:close()
    return data
end

-- Ключ MCR: свой из настроек MMT, иначе из MCR ПК, иначе из MLoader
function Collect.TgGetKey()
    local tg = collectReminder.tg
    local own = Collect.TgTrim(settings.notifications.mcrKey)
    if own ~= '' then
        return own, 'MMT'
    end

    if (os.clock() - tg.keyCheckedAt) < 30 and tg.keyCache ~= nil then
        return tg.keyCache, tg.keySource
    end
    tg.keyCheckedAt = os.clock()
    tg.keyCache, tg.keySource = '', ''

    local base = getWorkingDirectory() .. SEPORATORPATCH
    local mcrKey = Collect.TgTrim(Collect.TgReadFile(base .. 'MCR' .. SEPORATORPATCH .. 'config' .. SEPORATORPATCH .. 'UserKey-DontShare.key'))
    if #mcrKey >= 16 then
        tg.keyCache, tg.keySource = mcrKey, 'MCR ПК'
        return tg.keyCache, tg.keySource
    end

    local ini = Collect.TgReadFile(base .. 'config' .. SEPORATORPATCH .. 'mloader.ini') or ''
    local loaderKey = ''
    for line in ini:gmatch('[^\r\n]+') do
        local v = line:match('^%s*key%s*=%s*(.-)%s*$')
        if v then
            local unquoted = v:gsub('^"(.*)"$', '%1')
            loaderKey = Collect.TgTrim(unquoted)
            break
        end
    end
    if #loaderKey >= 16 then
        tg.keyCache, tg.keySource = loaderKey, 'MLoader'
    end
    return tg.keyCache, tg.keySource
end

-- Ключ целиком не показываем: только первые и последние два символа
function Collect.TgMaskKey(key)
    key = tostring(key or '')
    if #key <= 4 then return string.rep('*', #key) end
    return key:sub(1, 2) .. string.rep('*', #key - 4) .. key:sub(-2)
end

-- Почему отправка сейчас невозможна (nil - всё заполнено)
function Collect.TgConfigProblem()
    local cfg = settings.notifications
    if tonumber(cfg.methodBot) == 2 then
        if Collect.TgTrim(cfg.mcrChatId) == '' then return 'не указан ваш ID для бота MCR Notification' end
        if Collect.TgGetKey() == '' then return 'не найден ключ MCR' end
        return nil
    end
    if Collect.TgTrim(cfg.botToken) == '' then return 'не указан токен своего бота' end
    if Collect.TgTrim(cfg.chatId) == '' then return 'не указан ID чата' end
    return nil
end

function Collect.TgInitWorker()
    local tg = collectReminder.tg
    if tg.worker then return true end
    if tg.initError then return false end

    local ok, err = pcall(function()
        local effil = require('effil')
        tg.reqCh = effil.channel()
        tg.resCh = effil.channel()
        tg.worker = effil.thread(function(reqCh, resCh)
            local requests = require('requests')
            while true do
                local id, method, url, body, isJson = reqCh:pop()
                if id == nil then return end
                local headers = { ['User-Agent'] = 'mmt' }
                if isJson then
                    headers['Content-Type'] = 'application/json'
                    headers['Content-Length'] = tostring(#body)
                end
                local okReq, res = pcall(requests.request, method, url, {
                    headers = headers,
                    data = (body ~= '') and body or nil,
                    timeout = 15,
                })
                if okReq and type(res) == 'table' then
                    resCh:push(id, tonumber(res.status_code) or 0, tostring(res.text or ''))
                else
                    resCh:push(id, 0, tostring(res))
                end
            end
        end)(tg.reqCh, tg.resCh)
    end)

    if not ok then
        tg.worker = nil
        tg.initError = tostring(err)
        Chat.Add('Telegram: не удалось запустить отправку (' .. tg.initError .. ')', TYPECHATMESSAGES.WARNING)
        return false
    end
    return true
end

-- Отправить текст. kind - вид уведомления ('test' для тестового сообщения)
function Collect.TgSend(text, kind)
    local problem = Collect.TgConfigProblem()
    if problem then
        return false, problem
    end
    if not Collect.TgInitWorker() then
        return false, 'нет библиотеки effil/requests'
    end

    local cfg = settings.notifications
    local plain = tostring(text or ''):gsub('{%x%x%x%x%x%x}', '')
    local clean = u8(plain)

    local task = { kind = kind or 'test', text = clean, urlIndex = 1 }
    if tonumber(cfg.methodBot) == 2 then
        local key = Collect.TgGetKey()
        task.isJson = true
        task.body = json.encode({
            telegram_id = Collect.TgTrim(cfg.mcrChatId),
            key_user = key,
            message = clean,
        })
    else
        local encoded = clean:gsub('([^%w%-_%.~])', function(c)
            return string.format('%%%02X', string.byte(c))
        end)
        task.url = string.format('https://api.telegram.org/bot%s/sendMessage?chat_id=%s&text=%s',
            Collect.TgTrim(cfg.botToken), Collect.TgTrim(cfg.chatId), encoded)
    end

    Collect.TgPush(task)
    return true
end

function Collect.TgPush(task)
    local tg = collectReminder.tg
    tg.tasks = tg.tasks or {}
    tg.seq = (tg.seq or 0) + 1
    tg.tasks[tg.seq] = task
    tg.pending = tg.pending + 1
    local url = task.url or (task.urls or Collect.TG_MCR_URLS)[task.urlIndex]
    tg.reqCh:push(tg.seq, 'POST', url, task.body or '', task.isJson == true)
end

function Collect.TgHandleResult(id, status, text)
    local tg = collectReminder.tg
    local task = tg.tasks and tg.tasks[id]
    if not task then return end
    tg.tasks[id] = nil
    tg.pending = math.maxEx(0, tg.pending - 1)

    -- сеть или сервер MCR недоступны - пробуем зеркало
    local urls = task.urls or Collect.TG_MCR_URLS
    if task.isJson and (status == 0 or status >= 500) and task.urlIndex < #urls then
        task.urlIndex = task.urlIndex + 1
        Collect.TgPush(task)
        return
    end

    -- запросы облачного лога разбирают ответ сами
    if task.onDone then
        local ok, err = pcall(task.onDone, status, text)
        if not ok then
            print('[MMT] обработка ответа сервера: ' .. tostring(err))
        end
        return
    end

    if status >= 200 and status < 300 then
        tg.lastResult = os.date('%H:%M:%S') .. ' - сообщение отправлено'
        return
    end

    local raw = tostring(text or ''):sub(1, 150)
    local okDecode, detail = pcall(u8.decode, u8, raw)
    if not okDecode then detail = raw end
    local reason = (status == 0) and ('нет связи: ' .. detail) or string.format('ошибка %d: %s', status, detail)
    tg.lastResult = os.date('%H:%M:%S') .. ' - не отправлено, ' .. reason

    if task.kind ~= 'test' then
        -- напоминание не дошло: разрешаем повторить его позже
        settings.notifications.sent[task.kind] = nil
        -- ошибка настроек (4xx) сама не пройдёт - не шумим каждые 5 минут
        tg.retryAt[task.kind] = os.time() + ((status >= 400 and status < 500) and 1800 or 300)
        Chat.Add('Telegram: уведомление не отправлено (' .. reason .. ')', TYPECHATMESSAGES.WARNING)
    end
end

-- Время последнего сбора и порог напоминания (в минутах) для вида уведомления
function Collect.TgReminderSource(kind)
    if kind == 'crypto' then
        local info = Collect.GetLastCollectInfo()
        return info and info.timestamp or 0, tonumber(settings.main.collectNotifyMinutes) or 0
    elseif kind == 'greenhouse' then
        return tonumber(greenhouseLog.lastCollectAt) or 0, tonumber(settings.farmer.notifyMinutes) or 0
    elseif kind == 'miner' then
        return tonumber(minerLog.lastCollectAt) or 0, tonumber(settings.miner.notifyMinutes) or 0
    elseif kind == 'mirage' then
        return tonumber(Mirage.log.lastCollectAt) or 0, tonumber(settings.mirage.notifyMinutes) or 0
    end
    return 0, 0
end

-- Сбор этого вида идёт прямо сейчас - напоминать не о чем
function Collect.TgKindBusy(kind)
    if kind == 'crypto' then
        return flashCollect.active or (stateCrypto.work and processes.take)
    elseif kind == 'greenhouse' then
        return farmer.active
    elseif kind == 'miner' then
        return miner.active
    elseif kind == 'mirage' then
        return Mirage.st.pending ~= nil
    end
    return false
end

function Collect.TgNickname()
    local ok, res, id = pcall(sampGetPlayerIdByCharHandle, PLAYER_PED)
    if not (ok and res) then return '' end
    local okNick, nick = pcall(sampGetPlayerNickname, id)
    return (okNick and nick) and tostring(nick) or ''
end

function Collect.TgReminderText(kind, lastAt, elapsed)
    local head = '[MMT]'
    local passed = Collect.FormatDuration(elapsed)
    local lastText = os.date('%d.%m.%Y %H:%M', lastAt)
    if kind == 'crypto' then
        return string.format('%s\nПора собирать крипту: с последнего сбора прошло %s.\nПоследний сбор: %s', head, passed, lastText)
    elseif kind == 'greenhouse' then
        return string.format('%s\nПора собирать теплицы: с последнего сбора прошло %s.\nПоследний сбор: %s', head, passed, lastText)
    elseif kind == 'mirage' then
        return string.format('%s\nПора собирать сарай миража: с последнего сбора прошло %s.\nПоследний сбор: %s', head, passed, lastText)
    end
    return string.format('%s\nПора собирать майнера: с последнего сбора прошло %s.\nПоследний сбор: %s', head, passed, lastText)
end

-- Состояние таймера для окна настроек
function Collect.TgReminderStatus(kind)
    local cfg = settings.notifications
    if not (cfg.game[kind] or cfg.tg[kind]) then return 'выключено' end
    local lastAt, minutes = Collect.TgReminderSource(kind)
    if minutes <= 0 then return 'интервал 0 - выключено' end
    if lastAt <= 0 then return 'после первого сбора' end
    local remain = minutes * 60 - (os.time() - lastAt)
    if remain > 0 then return 'через ' .. Collect.FormatDuration(remain) end
    local sentGame = cfg.game[kind] and Collect.GameState(kind).notifiedAt == lastAt
    local sentTg = cfg.tg[kind] and tonumber(cfg.sent[kind]) == lastAt
    if sentGame or sentTg then return 'отправлено' end
    return 'время истекло'
end

-- Вызывается из фонового цикла
function Collect.TgTick()
    local tg = collectReminder.tg
    if tg.resCh then
        local id, status, text = tg.resCh:pop(0)
        while id ~= nil do
            Collect.TgHandleResult(id, tonumber(status) or 0, text)
            id, status, text = tg.resCh:pop(0)
        end
    end

    local nowClock = os.clock()
    if (nowClock - tg.tickAt) < 5 then return end
    tg.tickAt = nowClock

    local cfg = settings.notifications
    local anyOn = false
    for _, kind in ipairs(Collect.TG_KINDS) do
        if cfg.tg[kind.id] then anyOn = true end
    end
    if not anyOn or tg.initError or Collect.TgConfigProblem() then return end

    local now = os.time()
    for _, kind in ipairs(Collect.TG_KINDS) do
        local id = kind.id
        local lastAt, minutes = Collect.TgReminderSource(id)
        if cfg.tg[id] and minutes > 0 and lastAt > 0
            and tonumber(cfg.sent[id]) ~= lastAt
            and (now - lastAt) >= minutes * 60
            and now >= (tg.retryAt[id] or 0)
            and not Collect.TgKindBusy(id)
        then
            cfg.sent[id] = lastAt
            Storage.SaveSettings()
            Collect.TgSend(Collect.TgReminderText(id, lastAt, now - lastAt), id)
        end
    end
end

-- Поток отправки живёт вне скрипта: при выгрузке MMT его нужно погасить,
-- иначе после каждого /mmtr остаётся лишний поток
function Collect.TgShutdown()
    local tg = collectReminder.tg
    if tg.worker then
        pcall(function() tg.worker:cancel(0) end)
        tg.worker = nil
    end
end

function onScriptTerminate(scr)
    if scr == thisScript() then
        Collect.TgShutdown()
    end
end

-- ===== Облачный лог сборов (API MCR /v1/mmt/collect) =====
-- Каждый сбор (один дом с криптой, теплица, майнер) - отдельное событие. События
-- сначала ложатся в очередь на диске и уходят по одному через поток отправки Telegram.
-- Повтор идёт с тем же event_id, поэтому сервер не посчитает сбор дважды.

collectReminder.sync = {
    queue = nil,               -- загружается при первом обращении
    inflight = false,
    pausedUntil = 0,
    failCount = 0,
    lastOkAt = 0,
    lastError = '',
    tickAt = -1000,
    seq = 0,
    unit = nil,                -- дом с криптой, который сейчас собирается
    sessionId = nil,
    itemIds = {},              -- кэш: название -> id (false - не найден)
    catalogs = nil,
    summary = { data = nil, key = '', autoKey = '', loading = false, error = '', at = 0 },
}

Collect.SYNC_URLS = {
    'https://api.arz-mcr.ru/v1/mmt/collect',
    'https://api.arz-mcr.top/v1/mmt/collect',
}
Collect.SUMMARY_URLS = {
    'https://api.arz-mcr.ru/v1/mmt/collect/summary',
    'https://api.arz-mcr.top/v1/mmt/collect/summary',
}
Collect.SYNC_QUEUE_FILE = PATCHCONFIG .. 'CollectSyncQueue.json'
Collect.SYNC_QUEUE_MAX = 1000
-- cjson кодирует пустую таблицу как объект, а серверу нужен массив
Collect.SYNC_EMPTY_ARRAY = '__MMT_EMPTY_ARRAY__'

-- Ресурсы теплиц и майнера: склад показывает только названия (ё заменена на е)
Collect.SYNC_ITEM_IDS = {
    ['Лен'] = 595,
    ['Хлопок'] = 594,
    ['Укроп'] = 510,
    ['Кусок редкой ткани'] = 1692,
    ['Темная материя'] = 7281,
}

function Collect.SyncEnabled()
    return settings.cloud.sendCollects == true
end

function Collect.SyncQueue()
    local sync = collectReminder.sync
    if not sync.queue then
        local data = Storage.LoadJSON(Collect.SYNC_QUEUE_FILE)
        sync.queue = (type(data) == 'table' and type(data.events) == 'table') and data.events or {}
    end
    return sync.queue
end

function Collect.SyncSaveQueue()
    Storage.SaveJSON(Collect.SYNC_QUEUE_FILE, { events = Collect.SyncQueue() })
end

function Collect.SyncNewId(tag)
    local sync = collectReminder.sync
    sync.seq = sync.seq + 1
    return string.format('%d-%s-%d-%04x', os.time(), tostring(tag), sync.seq, math.random(0, 65535))
end

function Collect.SyncAccount()
    local nick = Collect.TgNickname()
    local server = ''
    if type(sampGetCurrentServerAddress) == 'function' then
        local ok, ip, port = pcall(sampGetCurrentServerAddress)
        if ok and ip then
            server = tostring(ip) .. ':' .. tostring(port or 0)
        end
    end
    return { nick = (nick ~= '') and nick or 'unknown', server_ip = (server ~= '') and server or 'unknown' }
end

-- Общие поля события. key_user подставляется при отправке, в очереди ключ не хранится
function Collect.SyncBase(kind, status, reason, startedAt)
    local version = tostring(thisScript().version or '')
    return {
        event_id = Collect.SyncNewId(kind),
        session_id = collectReminder.sync.sessionId or Collect.SyncNewId('s'),
        type = kind,
        status = status,
        stop_reason = reason and u8(tostring(reason)) or json.null,
        started_at = tonumber(startedAt) or os.time(),
        finished_at = os.time(),
        account = Collect.SyncAccount(),
        client = { name = 'mmt', version = (version ~= '') and version or '0', platform = ISMONETLOADER and 'mobile' or 'pc' },
    }
end

function Collect.SyncEnqueue(event)
    local queue = Collect.SyncQueue()
    table.insert(queue, event)
    while #queue > Collect.SYNC_QUEUE_MAX do
        table.remove(queue, 1)
    end
    Collect.SyncSaveQueue()
end

-- ----- Крипта: один дом = одно событие -----

-- Новый запуск сбора или заливки
function Collect.SyncStartSession()
    local sync = collectReminder.sync
    sync.unit = nil
    sync.sessionId = Collect.SyncNewId('s')
end

-- houseId = nil - подвал или дом не определён; unitKey различает дома в одном проходе
function Collect.SyncBeginHouse(houseId, unitKey)
    local sync = collectReminder.sync
    if not (processes.take or processes.fill) then return end
    if sync.unit and sync.unit.key == unitKey then return end
    Collect.SyncEndHouse('complete')

    local summary = collectStats.summary
    local source = (summary and summary.source == 'flash') and 'flash' or 'manual'
    if source == 'flash' and flashCollect.fromCommand then
        source = 'command'
    end

    sync.unit = {
        key = unitKey,
        houseId = houseId,
        startedAt = os.time(),
        source = source,
        BTC = 0,
        ASC = 0,
        visited = 0,
        collected = 0,
        cardsEnabled = 0,
        lastShelf = nil,
        liquid = { btc = 0, super_btc = 0, asc = 0 },
    }
end

function Collect.SyncEndHouse(status, reason)
    local sync = collectReminder.sync
    local unit = sync.unit
    if not unit then return end
    sync.unit = nil
    if not Collect.SyncEnabled() then return end

    local liquidTotal = unit.liquid.btc + unit.liquid.super_btc + unit.liquid.asc
    if unit.BTC <= 0 and unit.ASC <= 0 and liquidTotal <= 0 then return end

    local event = Collect.SyncBase('crypto', status or 'complete', reason, unit.startedAt)
    event.source = unit.source
    event.house_id = (unit.houseId ~= nil and tostring(unit.houseId) ~= '' and tostring(unit.houseId) ~= '0')
        and tostring(unit.houseId) or json.null
    event.collected = {
        BTC = Collect.NormalizeCryptoAmount(unit.BTC),
        ASC = Collect.NormalizeCryptoAmount(unit.ASC),
    }
    event.shelves = { visited = unit.visited, collected = unit.collected, cards_enabled = unit.cardsEnabled }
    if liquidTotal > 0 then
        event.liquid_used = unit.liquid
    end
    Collect.SyncEnqueue(event)
end

function Collect.SyncOnVisit()
    local unit = collectReminder.sync.unit
    if unit then unit.visited = unit.visited + 1 end
end

function Collect.SyncOnTake(currency, amount)
    local unit = collectReminder.sync.unit
    if not unit or (currency ~= 'BTC' and currency ~= 'ASC') then return end
    unit[currency] = unit[currency] + (tonumber(amount) or 0)
    -- с одной полки может прийти и BTC, и ASC - полку считаем один раз
    local shelfKey = tostring(stateCrypto.progressShelves)
    if unit.lastShelf ~= shelfKey then
        unit.lastShelf = shelfKey
        unit.collected = unit.collected + 1
    end
end

function Collect.SyncOnCardEnabled()
    local unit = collectReminder.sync.unit
    if unit then unit.cardsEnabled = unit.cardsEnabled + 1 end
end

-- liquidType - выбор из диалога жидкости: btc | supper_btc | asc
function Collect.SyncOnLiquid(liquidType)
    local unit = collectReminder.sync.unit
    if not unit then return end
    local field = (liquidType == 'supper_btc') and 'super_btc' or liquidType
    if unit.liquid[field] then
        unit.liquid[field] = unit.liquid[field] + 1
    end
end

-- ----- Пополнение банка домов: один дом = одно событие -----

function Collect.SyncBankBegin(houseData)
    local sync = collectReminder.sync
    Collect.SyncBankEnd('complete')
    sync.bank = {
        houseId = houseData and houseData.house_number,
        startedAt = os.time(),
        before = tonumber(houseData and houseData.bankNow) or 0,
        deposited = 0,
        operations = 0,
    }
end

-- Сервер подтвердил пополнение на сумму, которую ввёл скрипт
function Collect.SyncOnDeposit(amount)
    local bank = collectReminder.sync.bank
    amount = math.floor(tonumber(amount) or 0)
    if not bank or amount <= 0 then return end
    bank.deposited = bank.deposited + amount
    bank.operations = bank.operations + 1
end

function Collect.SyncBankEnd(status, reason)
    local sync = collectReminder.sync
    local bank = sync.bank
    if not bank then return end
    sync.bank = nil
    if not Collect.SyncEnabled() or bank.deposited <= 0 then return end

    local event = Collect.SyncBase('bank', status or 'complete', reason, bank.startedAt)
    event.house_id = bank.houseId and tostring(bank.houseId) or json.null
    event.deposited = bank.deposited
    event.operations = bank.operations
    event.bank_before = bank.before
    event.bank_after = bank.before + bank.deposited
    Collect.SyncEnqueue(event)
end

-- ----- Теплицы и майнер -----

function Collect.SyncNormName(name)
    local s = tostring(name or '')
    s = s:gsub('\184', '\229')
    s = s:gsub('\168', '\197')
    return s
end

-- id из каталога MCR: ПК - UTF-8, мобилка - CP1251
function Collect.SyncCatalogId(name)
    local sync = collectReminder.sync
    if not sync.catalogs then
        local base = getWorkingDirectory() .. SEPORATORPATCH
        sync.catalogs = {
            { raw = Collect.TgReadFile(base .. 'MCR' .. SEPORATORPATCH .. 'data' .. SEPORATORPATCH .. 'ItemCatalog.json'), utf8 = true },
            { raw = Collect.TgReadFile(base .. 'config' .. SEPORATORPATCH .. 'MCRM CFGs' .. SEPORATORPATCH .. 'AllItemsID.json'), utf8 = false },
        }
    end
    for _, catalog in ipairs(sync.catalogs) do
        if catalog.raw then
            local needle = catalog.utf8 and u8(name) or name
            local pos = catalog.raw:find('":"' .. needle .. '"', 1, true)
            if pos then
                local id = catalog.raw:sub(math.maxEx(1, pos - 12), pos):match('"(%d+)"$')
                if id then return tonumber(id) end
            end
        end
    end
    return nil
end

function Collect.SyncItemId(name)
    local sync = collectReminder.sync
    local norm = Collect.SyncNormName(name)
    local cached = sync.itemIds[norm]
    if cached ~= nil then return cached or nil end

    local id = Collect.SYNC_ITEM_IDS[norm] or Collect.SyncCatalogId(name)
    if not id and norm ~= name then
        id = Collect.SyncCatalogId(norm)
    end
    sync.itemIds[norm] = id or false
    return id
end

function Collect.SyncItems(collected)
    local items = {}
    for name, amount in pairs(collected or {}) do
        amount = math.floor(tonumber(amount) or 0)
        if amount > 0 then
            local id = Collect.SyncItemId(name)
            table.insert(items, { item_id = id or json.null, name = u8(tostring(name)), amount = amount })
        end
    end
    return items
end

-- kind = 'greenhouse' | 'miner'. Одно событие на запуск: повторный вызов ничего не шлёт
function Collect.SyncResource(kind, status, reason)
    local st = (kind == 'greenhouse') and farmer or miner
    if not st.syncPending then return end
    st.syncPending = false
    if not Collect.SyncEnabled() then return end

    local items = Collect.SyncItems(st.collected)
    local added = (kind == 'greenhouse') and (tonumber(farmer.waterSpent) or 0) or (tonumber(miner.chargeSpent) or 0)
    if #items == 0 and added <= 0 then return end

    local event = Collect.SyncBase(kind, status, reason, st.syncStartedAt)
    event.items = (#items > 0) and items or Collect.SYNC_EMPTY_ARRAY
    local menu = st.menu or {}
    event.store_after = { now = tonumber(menu.storeNow) or 0, max = tonumber(menu.storeMax) or 0 }
    if kind == 'greenhouse' then
        event.water_added = added
        event.water_after = { now = tonumber(farmer.wareWaterNow) or 0, max = tonumber(farmer.wareWaterMax) or 0 }
    else
        event.charge_added = added
        event.charge_after = { now = tonumber(miner.chargeNow) or 0, max = tonumber(miner.chargeMax) or 0 }
    end
    -- у каждого сбора теплицы/майнера своя сессия
    event.session_id = Collect.SyncNewId('s')
    Collect.SyncEnqueue(event)
end

function Collect.SyncResourceStart(kind)
    local st = (kind == 'greenhouse') and farmer or miner
    st.syncPending = true
    st.syncStartedAt = os.time()
end

-- ----- Отправка -----

function Collect.SyncOnResult(event, status, text)
    local sync = collectReminder.sync
    sync.inflight = false
    local queue = Collect.SyncQueue()
    local now = os.time()

    local function dropEvent()
        for i, e in ipairs(queue) do
            if e.event_id == event.event_id then
                table.remove(queue, i)
                break
            end
        end
        Collect.SyncSaveQueue()
    end

    if status >= 200 and status < 300 then
        dropEvent()
        sync.failCount = 0
        sync.lastOkAt = now
        sync.lastError = ''
        return
    end

    if status == 403 then
        sync.pausedUntil = now + 1800
        sync.lastError = 'ключ не найден или выключен'
        Chat.Add('Облачный лог: ' .. sync.lastError .. '. Повторю через 30 минут.', TYPECHATMESSAGES.WARNING)
    elseif status == 422 then
        -- сервер такой сбор не примет никогда - повторять бессмысленно
        dropEvent()
        sync.lastError = 'сервер отклонил сбор (ошибка данных)'
        local raw = tostring(text or ''):sub(1, 200)
        local okDecode, detail = pcall(u8.decode, u8, raw)
        Chat.Add('Облачный лог: сбор отклонён: ' .. tostring(okDecode and detail or raw), TYPECHATMESSAGES.DEBUG)
    elseif status == 429 then
        sync.pausedUntil = now + 60
        sync.lastError = 'слишком много запросов'
    else
        sync.failCount = sync.failCount + 1
        local delays = { 60, 300, 900 }
        sync.pausedUntil = now + delays[math.minEx(sync.failCount, #delays)]
        sync.lastError = (status == 0) and 'нет связи с сервером' or ('ошибка сервера ' .. status)
    end
end

-- Вызывается из фонового цикла
function Collect.SyncTick()
    local sync = collectReminder.sync
    if sync.inflight then return end

    local nowClock = os.clock()
    if (nowClock - sync.tickAt) < 1 then return end
    sync.tickAt = nowClock

    if not Collect.SyncEnabled() or os.time() < sync.pausedUntil then return end
    local queue = Collect.SyncQueue()
    if #queue == 0 then return end

    local key = Collect.TgGetKey()
    if key == '' then
        sync.lastError = 'не найден ключ MCR'
        return
    end
    if not Collect.TgInitWorker() then
        sync.lastError = 'нет библиотеки effil/requests'
        return
    end

    local event = queue[1]
    event.key_user = key
    local okEncode, encoded = pcall(json.encode, event)
    event.key_user = nil
    if not okEncode then
        table.remove(queue, 1)
        Collect.SyncSaveQueue()
        return
    end
    local body = encoded:gsub('"' .. Collect.SYNC_EMPTY_ARRAY .. '"', '[]')

    sync.inflight = true
    Collect.TgPush({
        kind = 'sync',
        urls = Collect.SYNC_URLS,
        urlIndex = 1,
        body = body,
        isJson = true,
        onDone = function(status, text)
            Collect.SyncOnResult(event, status, text)
        end,
    })
end

-- ----- Итоги из облака -----

function Collect.JsonValue(v)
    if v == json.null then return nil end
    return v
end

-- Поля-идентификаторы при слиянии не складываются
Collect.CLOUD_ID_FIELDS = { house_id = true, item_id = true, id = true, number = true }

-- Сложить две секции итогов: числа суммируются, списки домов и предметов
-- сливаются по house_id / item_id / name, остальное берётся из первой
function Collect.CloudSum(a, b)
    a, b = Collect.JsonValue(a), Collect.JsonValue(b)
    if a == nil then return b end
    if b == nil then return a end
    if type(a) == 'number' and type(b) == 'number' then return a + b end
    if type(a) ~= 'table' or type(b) ~= 'table' then return a end

    if #a > 0 or #b > 0 then
        local out, index = {}, {}
        for _, list in ipairs({ a, b }) do
            for _, row in ipairs(list) do
                local key = type(row) == 'table' and tostring(Collect.JsonValue(row.house_id)
                    or Collect.JsonValue(row.item_id) or Collect.JsonValue(row.name) or '') or ''
                if index[key] then
                    out[index[key]] = Collect.CloudSum(out[index[key]], row)
                else
                    table.insert(out, row)
                    index[key] = #out
                end
            end
        end
        return out
    end

    local out = {}
    for k, v in pairs(a) do out[k] = v end
    for k, v in pairs(b) do
        if Collect.CLOUD_ID_FIELDS[k] then
            if Collect.JsonValue(out[k]) == nil then out[k] = v end
        else
            out[k] = Collect.CloudSum(out[k], v)
        end
    end
    return out
end

-- У сервера бывает несколько адресов (IP, домен), а бэкенд различает аккаунты по
-- нику и адресу - один персонаж приходит несколькими строками. Сливаем их по нику
-- и серверу из справочника (id, иначе название, иначе адрес).
function Collect.CloudMergeAccounts(accounts)
    local out, index = {}, {}
    for _, acc in ipairs(Collect.JsonValue(accounts) or {}) do
        local server = Collect.JsonValue(acc.server) or {}
        local serverKey = Collect.JsonValue(server.id) or Collect.JsonValue(server.title) or Collect.JsonValue(server.ip) or '?'
        local key = tostring(Collect.JsonValue(acc.nick) or '?') .. '|' .. tostring(serverKey)
        local pos = index[key]
        if pos then
            local merged = out[pos]
            for field, value in pairs(acc) do
                if field ~= 'nick' and field ~= 'server' then
                    merged[field] = Collect.CloudSum(merged[field], value)
                end
            end
        else
            local copy = {}
            for field, value in pairs(acc) do copy[field] = value end
            table.insert(out, copy)
            index[key] = #out
        end
    end
    return out
end

function Collect.CloudFetchSummary(periodDays)
    local st = collectReminder.sync.summary
    if st.loading then return end

    local key = Collect.TgGetKey()
    if key == '' then
        st.error = 'не найден ключ MCR - укажите его в настройках (вкладка "Основное")'
        return
    end
    if not Collect.TgInitWorker() then
        st.error = 'нет библиотеки effil/requests'
        return
    end

    periodDays = math.maxEx(1, math.minEx(93, tonumber(periodDays) or 7))
    local now = os.time()
    local body = json.encode({
        key_user = key,
        date_from = os.date('%Y-%m-%d', now - (periodDays - 1) * 86400),
        date_to = os.date('%Y-%m-%d', now),
    })

    local reqKey = tostring(periodDays)
    st.loading = true
    st.error = ''
    Collect.TgPush({
        kind = 'summary',
        urls = Collect.SUMMARY_URLS,
        urlIndex = 1,
        body = body,
        isJson = true,
        onDone = function(status, text)
            st.loading = false
            st.key = reqKey
            if status == 200 then
                local ok, data = pcall(json.decode, text)
                if ok and type(data) == 'table' and data.ok then
                    for _, day in ipairs(Collect.JsonValue(data.days) or {}) do
                        day.accounts = Collect.CloudMergeAccounts(day.accounts)
                    end
                    st.data = data
                    st.at = os.time()
                    return
                end
                st.error = 'сервер прислал непонятный ответ'
            elseif status == 403 then
                st.error = 'ключ не найден или выключен'
            elseif status == 422 then
                st.error = 'сервер не принял период'
            elseif status == 429 then
                st.error = 'слишком часто, попробуйте через минуту'
            elseif status == 0 then
                st.error = 'нет связи с сервером'
            else
                st.error = 'ошибка сервера ' .. tostring(status)
            end
        end,
    })
end

-- Старые логи без lastCollectAt: берём последний день, в котором что-то собрано
function Collect.LastCollectFromDays(days)
    local best = 0
    for _, d in pairs(days or {}) do
        if type(d) == 'table' and type(d.collected) == 'table' and next(d.collected) ~= nil then
            best = math.maxEx(best, tonumber(d.updatedAt) or 0)
        end
    end
    return best
end

-- ===== Расширенная сводка сбора =====

-- Читаемые названия оборудования на полке
Collect.CARD_TYPE_LABELS = {
    BTC = "Видеокарты",
    ASIC = "ASIC-фермы",
    ASC = "Arizona Video Card",
}

function Collect.NewSummary(source)
    return {
        source = source or "manual",
        startedAt = os.time(),
        finishedAt = 0,
        houses = {},
        houseCount = 0,
        shelvesVisited = 0,
        shelvesCollected = 0,
        cardsEnabled = 0,
        byLevel = {},
        byType = {},
        typeOrder = {},
        lastCollectedKey = nil,
        maxTake = { count = 0, currency = nil, level = 0, house = nil },
    }
end

-- Ячейка статистики по уровню видеокарты (0 = уровень не распознан)
function Collect.LevelBucket(summary, level)
    level = math.maxEx(0, math.floor(tonumber(level) or 0))
    local bucket = summary.byLevel[level]
    if not bucket then
        bucket = { visited = 0, collected = 0, BTC = 0, ASC = 0 }
        summary.byLevel[level] = bucket
    end
    return bucket
end

-- Ячейка статистики по типу оборудования
function Collect.TypeBucket(summary, cardType)
    cardType = tostring(cardType or "BTC")
    local bucket = summary.byType[cardType]
    if not bucket then
        bucket = { visited = 0, collected = 0, BTC = 0, ASC = 0 }
        summary.byType[cardType] = bucket
        table.insert(summary.typeOrder, cardType)
    end
    return bucket
end

-- Полка, которую скрипт взял в обработку
function Collect.SummaryVisit(shelfData)
    local summary = collectStats.summary
    if not (summary and processes.take and type(shelfData) == 'table') then return end

    local level = tonumber(shelfData.level) or 0
    summary.shelvesVisited = summary.shelvesVisited + 1

    local lvlBucket = Collect.LevelBucket(summary, level)
    lvlBucket.visited = lvlBucket.visited + 1

    local typeBucket = Collect.TypeBucket(summary, shelfData.card_type)
    typeBucket.visited = typeBucket.visited + 1

    local hid = stateCrypto.currentHouseId
    if hid ~= nil and not summary.houses[tostring(hid)] then
        summary.houses[tostring(hid)] = true
        summary.houseCount = summary.houseCount + 1
    end
end

-- Фактическая выплата с полки (с одной полки может прийти и BTC, и ASC)
function Collect.SummaryTake(shelfData, currency, amount)
    local summary = collectStats.summary
    if not summary then return end

    amount = tonumber(amount) or 0
    if amount <= 0 or (currency ~= "BTC" and currency ~= "ASC") then return end

    local level = (type(shelfData) == 'table') and shelfData.level or 0
    local cardType = (type(shelfData) == 'table') and shelfData.card_type or nil
    local lvlBucket = Collect.LevelBucket(summary, level)
    local typeBucket = Collect.TypeBucket(summary, cardType)

    lvlBucket[currency] = (lvlBucket[currency] or 0) + amount
    typeBucket[currency] = (typeBucket[currency] or 0) + amount

    local key = tostring(stateCrypto.currentHouseId) .. "#" .. tostring(stateCrypto.progressShelves)
    if summary.lastCollectedKey ~= key then
        summary.lastCollectedKey = key
        summary.shelvesCollected = summary.shelvesCollected + 1
        lvlBucket.collected = lvlBucket.collected + 1
        typeBucket.collected = typeBucket.collected + 1
    end

    if amount > (summary.maxTake.count or 0) then
        summary.maxTake = {
            count = amount,
            currency = currency,
            level = tonumber(level) or 0,
            house = stateCrypto.currentHouseId,
        }
    end
end

-- Скрипт сам включил простаивавшую видеокарту
function Collect.SummaryCardEnabled()
    Collect.SyncOnCardEnabled()
    local summary = collectStats.summary
    if summary and processes.take then
        summary.cardsEnabled = summary.cardsEnabled + 1
    end
end

-- Длинные перечисления бьём на строки, чтобы чат не резал текст
function Collect.PrintChunks(prefix, parts, perLine, chatType)
    local buffer = {}
    for _, part in ipairs(parts) do
        table.insert(buffer, part)
        if #buffer >= perLine then
            Chat.Add(prefix .. table.concat(buffer, "; "), chatType)
            buffer = {}
            prefix = string.rep(" ", 0)
        end
    end
    if #buffer > 0 then
        Chat.Add(prefix .. table.concat(buffer, "; "), chatType)
    end
end

function Collect.PrintSummary()
    local summary = collectStats.summary
    if not summary then return end
    if not settings.main.showCollectSummary then return end
    if summary.shelvesVisited <= 0 then return end

    summary.finishedAt = os.time()

    local btc = Collect.NormalizeCryptoAmount(collectStats.total.BTC or 0)
    local asc = Collect.NormalizeCryptoAmount(collectStats.total.ASC or 0)
    local duration = Collect.FormatDuration(summary.finishedAt - summary.startedAt)
    local sourceLabel = (summary.source == "flash") and "флешка" or "ручной запуск"

    Chat.Add(string.format(
        "Сводка сбора (%s): домов %d, видеокарт %d, время %s",
        sourceLabel, summary.houseCount, summary.shelvesVisited, duration
    ), TYPECHATMESSAGES.SUCCESS)

    Chat.Add(string.format(
        "Собрано: %s BTC и %s ASC | с выплатой %d из %d полок",
        tostring(btc), tostring(asc), summary.shelvesCollected, summary.shelvesVisited
    ), TYPECHATMESSAGES.SECONDARY)

    -- Уровни видеокарт: сколько обработано и сколько с них снято
    local levels = {}
    for level in pairs(summary.byLevel) do table.insert(levels, level) end
    table.sort(levels, function(a, b) return a > b end)

    local levelParts = {}
    for _, level in ipairs(levels) do
        local bucket = summary.byLevel[level]
        local gains = {}
        if (bucket.BTC or 0) > 0 then
            table.insert(gains, Collect.NormalizeCryptoAmount(bucket.BTC) .. " BTC")
        end
        if (bucket.ASC or 0) > 0 then
            table.insert(gains, Collect.NormalizeCryptoAmount(bucket.ASC) .. " ASC")
        end
        table.insert(levelParts, string.format(
            "%s - %d шт%s",
            (level > 0) and (level .. " ур.") or "ур. ?",
            bucket.visited,
            (#gains > 0) and (" (" .. table.concat(gains, ", ") .. ")") or ""
        ))
    end
    if #levelParts > 0 then
        Collect.PrintChunks("Уровни видеокарт: ", levelParts, 3, TYPECHATMESSAGES.SECONDARY)
    end

    -- Типы оборудования
    local typeParts = {}
    for _, cardType in ipairs(summary.typeOrder) do
        local bucket = summary.byType[cardType]
        table.insert(typeParts, string.format(
            "%s - %d шт",
            Collect.CARD_TYPE_LABELS[cardType] or cardType,
            bucket.visited
        ))
    end
    if #typeParts > 1 then
        Collect.PrintChunks("Типы: ", typeParts, 3, TYPECHATMESSAGES.SECONDARY)
    end

    -- Дома, по убыванию собранного
    local houseIds = {}
    for houseId in pairs(collectStats.house or {}) do table.insert(houseIds, houseId) end
    table.sort(houseIds, function(a, b)
        local sa = collectStats.house[a] or {}
        local sb = collectStats.house[b] or {}
        return ((sa.BTC or 0) + (sa.ASC or 0)) > ((sb.BTC or 0) + (sb.ASC or 0))
    end)
    local houseParts = {}
    for _, houseId in ipairs(houseIds) do
        local st = collectStats.house[houseId]
        if (st.BTC or 0) > 0 or (st.ASC or 0) > 0 then
            local gains = {}
            if (st.BTC or 0) > 0 then table.insert(gains, Collect.NormalizeCryptoAmount(st.BTC) .. " BTC") end
            if (st.ASC or 0) > 0 then table.insert(gains, Collect.NormalizeCryptoAmount(st.ASC) .. " ASC") end
            table.insert(houseParts, string.format("дом %s: %s", tostring(houseId), table.concat(gains, " + ")))
        end
    end
    if #houseParts > 0 then
        Collect.PrintChunks("По домам: ", houseParts, 3, TYPECHATMESSAGES.SECONDARY)
    end

    local extra = {}
    local skipped = summary.shelvesVisited - summary.shelvesCollected
    if skipped > 0 then
        table.insert(extra, string.format("без выплаты: %d", skipped))
    end
    if summary.cardsEnabled > 0 then
        table.insert(extra, string.format("включено видеокарт: %d", summary.cardsEnabled))
    end
    if (summary.maxTake.count or 0) > 0 then
        table.insert(extra, string.format(
            "лучшая полка: %s %s%s",
            tostring(Collect.NormalizeCryptoAmount(summary.maxTake.count)),
            tostring(summary.maxTake.currency or ""),
            ((summary.maxTake.level or 0) > 0) and (" / " .. summary.maxTake.level .. " ур.") or ""
        ))
    end
    if #extra > 0 then
        Collect.PrintChunks("Детали: ", extra, 2, TYPECHATMESSAGES.SECONDARY)
    end
end

function Collect.AddLogEntry(houseId, currency, amount)
    houseId = tostring(houseId or 0)
    currency = tostring(currency or "BTC")
    amount = Collect.NormalizeCryptoAmount(amount)
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
    Collect.TrimHouseLogItems(houseData, Collect.GetMaxLogItemsPerHouseDay())

    Collect.UpdateLastCollectInfo(houseId, currency, amount)
    Storage.RequestSaveCollectLogStore(false)
end

Storage.LoadCollectLogStore()


-- --------------------------------------------------------
--                           Parsers
-- --------------------------------------------------------

-- =====================================================================================================================
--                                                          FARMER / GREENHOUSE
-- =====================================================================================================================

-- Приведение cp1251-строки к нижнему регистру (латиница + кириллица)
function Farmer.lower(s)
    s = tostring(s or "")
    local out = {}
    for i = 1, #s do
        local b = s:byte(i)
        if b >= 65 and b <= 90 then
            b = b + 32
        elseif b >= 0xC0 and b <= 0xDF then
            b = b + 0x20
        elseif b == 0xA8 then
            b = 0xB8
        end
        out[i] = string.char(b)
    end
    return table.concat(out)
end

function Farmer.num(s)
    return tonumber((tostring(s or ""):gsub("%D", ""))) or 0
end

-- Убираем цветовые коды {RRGGBB}/{RRGGBBAA} из текста диалога
function Farmer.stripColors(s)
    s = tostring(s or "")
    s = s:gsub("{%x%x%x%x%x%x%x%x}", "")
    s = s:gsub("{%x%x%x%x%x%x}", "")
    return s
end

function Farmer.cleanName(name)
    local n = Farmer.stripColors(name):gsub("^%s*%[.-%]%s*", "")
    n = n:gsub("^%s+", ""):gsub("%s+$", "")
    return n
end

-- Индекс listitem для строки текста диалога (учитываем шапку у style 5)
function Farmer.ListItem(idx, style)
    local base = idx - 1
    if tonumber(style) == 5 then
        base = base - 1
    end
    if base < 0 then base = 0 end
    return base
end

-- Сколько всего влезает воды в фермера
Farmer.WATER_MAX = 400

-- Разбор диалога "Меню фермера"
function Farmer.ParseMenu(text, style)
    local m = { id = nil, status = "", storeNow = 0, storeMax = 0, wareLine = nil, statusLine = nil }
    text = Farmer.stripColors(text)
    local idx = 0
    for line in tostring(text or ""):gmatch("[^\r\n]+") do
        idx = idx + 1
        local low = Farmer.lower(line)
        if low:find("склад фермера") then
            m.wareLine = Farmer.ListItem(idx, style)
            local a, b = line:match("(%d[%d%s]*)%s*/%s*(%d[%d%s]*)")
            if a then
                m.storeNow = Farmer.num(a)
                m.storeMax = Farmer.num(b)
            end
        elseif low:find("статус") then
            m.statusLine = Farmer.ListItem(idx, style)
            local v = line:match(".*%[%s*(.-)%s*%]")
            if v then m.status = v end
        end
    end
    return m
end

-- Разбор диалога "Склад фермера"
function Farmer.ParseWare(text, style)
    local w = { id = nil, items = {}, putLine = nil, waterLine = nil, waterNow = 0, waterMax = 0 }
    text = Farmer.stripColors(text)
    local idx = 0
    for line in tostring(text or ""):gmatch("[^\r\n]+") do
        idx = idx + 1
        local low = Farmer.lower(line)
        local li = Farmer.ListItem(idx, style)
        if low:find("положить") then
            w.putLine = li
        else
            local cols = {}
            for part in line:gmatch("[^\t]+") do
                table.insert(cols, (part:gsub("^%s+", ""):gsub("%s+$", "")))
            end
            if #cols >= 2 then
                local name = cols[1]
                local count = Farmer.num(cols[#cols])
                local isWater = low:find("вода") or low:find("грядок")
                if isWater then
                    w.waterLine = li
                    w.waterNow = count
                    w.waterName = Farmer.cleanName(name)
                elseif name ~= "" and (count > 0 or low:find("ед")) then
                    table.insert(w.items, {
                        line = li,
                        name = Farmer.cleanName(name),
                        count = count,
                    })
                end
            end
        end
    end
    return w
end

function Farmer.ParseTakeInput(text)
    text = Farmer.stripColors(text)
    local name = text:match("аименование:%s*(.-)%s*[\r\n]") or ""
    local maxc = text:match("оличество:%s*(%d[%d%s]*)")
    return { name = Farmer.cleanName(name), max = Farmer.num(maxc) }
end

function Farmer.ParsePutInput(text)
    text = Farmer.stripColors(text)
    local name = text:match("аименование:%s*(.-)%s*[\r\n]") or ""
    local have = Farmer.num(text:match("ас:%s*(%d[%d%s]*)"))
    local fn, fm = text:match("ермера:%s*(%d[%d%s]*)%s*/%s*(%d[%d%s]*)")
    return {
        name = Farmer.cleanName(name),
        have = have,
        farmNow = Farmer.num(fn),
        farmMax = Farmer.num(fm),
    }
end

function Farmer.NextTakeable()
    for _, it in ipairs((farmer.ware and farmer.ware.items) or {}) do
        if (it.count or 0) > 0 then
            return it
        end
    end
    return nil
end

-- Диспетчер диалогов фермера. Возвращает nil (не наш диалог) / true / false (видимость)
function Farmer.HandleDialog(dialogId, style, title, text)
    local low = Farmer.lower(Farmer.stripColors(title or ""))

    if low:find("меню фермера") then
        local menu = Farmer.ParseMenu(text, style)
        menu.id = dialogId
        farmer.menu = menu
        farmer.menuOpen = true
        farmer.last = { kind = "menu", id = dialogId, style = style }
        farmer.dialogSeq = farmer.dialogSeq + 1
        imguiWindows.main[0] = true
        activeMode = "farmer"
        if activeTabScript == "improve" then activeTabScript = "main" end
        if not farmer.active then
            local mode = nil
            if settings.farmer.autoTake and settings.farmer.autoFill then
                mode = "both"
            elseif settings.farmer.autoTake then
                mode = "take"
            elseif settings.farmer.autoFill then
                mode = "fill"
            elseif settings.farmer.refreshOnOpen then
                -- автодействий нет: хотя бы подтянем свежее содержимое склада
                mode = "check"
            end
            if mode then
                lua_thread.create(function()
                    wait(50)
                    Farmer.Start(mode)
                end)
            end
        end
        if settings.main.replaceDialog then return false end
        return true
    end

    if low:find("положить на склад") then
        if not farmer.active then return nil end
        local inp = Farmer.ParsePutInput(text)
        inp.kind = "put"
        inp.id = dialogId
        farmer.input = inp
        farmer.invLiquid = tonumber(inp.have) or 0
        farmer.wareWaterNow = tonumber(inp.farmNow) or 0
        farmer.wareWaterMax = tonumber(inp.farmMax) or 0
        farmer.last = { kind = "putInput", id = dialogId, style = style }
        farmer.dialogSeq = farmer.dialogSeq + 1
        return false
    end

    if low:find("забрать") then
        if not farmer.active then return nil end
        local inp = Farmer.ParseTakeInput(text)
        inp.kind = "take"
        inp.id = dialogId
        farmer.input = inp
        farmer.last = { kind = "takeInput", id = dialogId, style = style }
        farmer.dialogSeq = farmer.dialogSeq + 1
        return false
    end

    if low:find("склад фермера") then
        if not farmer.active then return nil end
        local ware = Farmer.ParseWare(text, style)
        ware.id = dialogId
        farmer.ware = ware
        farmer.wareAt = os.time()
        -- склад показывает актуальный остаток воды: он важнее значения
        -- из окна пополнения, которое могло устареть
        if ware.waterNow ~= nil then
            farmer.wareWaterNow = tonumber(ware.waterNow) or 0
        end
        farmer.last = { kind = "ware", id = dialogId, style = style }
        farmer.dialogSeq = farmer.dialogSeq + 1
        return false
    end

    return nil
end

-- --------------------------------------------------------
--                    Farmer: логика процесса
-- --------------------------------------------------------

-- Запись в журнал действий. debugOnly = только в консоль (техническая отладка)
function Farmer.Log(msg, debugOnly)
    local text = tostring(msg)
    if settings.main.typeChatMessage and settings.main.typeChatMessage.debug then
        print(string.format("[FARM] [%s] %s", os.date('%H:%M:%S'), text))
    end
    if debugOnly then return end
    table.insert(farmer.logs, { time = os.date('%H:%M:%S'), text = text })
    while #farmer.logs > 200 do
        table.remove(farmer.logs, 1)
    end
end

function Farmer.AddCollected(name, amount)
    name = (name ~= nil and name ~= "") and name or "Ресурс"
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return end
    farmer.collected[name] = (tonumber(farmer.collected[name]) or 0) + amount
    Greenhouse.AddCollected(name, amount)
    Farmer.Log(string.format("Забрал %s - %d шт.", name, amount))
end

function Farmer.AddWater(amount)
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return end
    farmer.waterSpent = (farmer.waterSpent or 0) + amount
    Greenhouse.AddWater(amount)
    Farmer.Log(string.format("Полил грядки - %d воды", amount))
end

function Farmer.Respond(id, btn, list, input)
    local d = tonumber(settings.farmer.actionDelay) or 0
    if d > 0 then wait(d) end
    sampSendDialogResponse(id, btn, list or 0, input or "")
end

-- Ждём появления следующего диалога фермера (по счётчику dialogSeq)
function Farmer.WaitAdvance(startSeq)
    local interval = tonumber(settings.farmer.waitInterval) or 10
    local timeout = os.clock() + (tonumber(settings.farmer.timeout) or 10)
    while farmer.active do
        if farmer.dialogSeq ~= startSeq then
            return farmer.last.kind
        end
        wait(interval)
        if os.clock() > timeout then
            return nil
        end
    end
    return nil
end

-- Закрывает всё, что осталось открытым. Отвечаем именно тому диалогу, который пришёл последним:
-- на Cancel сервер часто возвращает предыдущее окно, а ответ по устаревшему id он игнорирует,
-- и тогда на экране висит "мёртвый" диалог, который уже ничего не открывает
function Farmer.CloseChain(limit)
    limit = tonumber(limit) or 4
    local interval = tonumber(settings.farmer.waitInterval) or 10
    for _ = 1, limit do
        local id = farmer.last and farmer.last.id
        if id == nil then break end
        local seq = farmer.dialogSeq
        Farmer.Respond(id, 0, 0, "")
        local deadline = os.clock() + 0.35
        while os.clock() < deadline and farmer.dialogSeq == seq do
            wait(interval)
        end
        -- сервер ничего не прислал в ответ - значит закрылось всё
        if farmer.dialogSeq == seq then break end
    end
    farmer.last = { kind = nil, id = nil, style = nil }
    if farmer.menu then farmer.menu.id = nil end
    if farmer.ware then farmer.ware.id = nil end
    farmer.menuOpen = false
end

function Farmer.OpenWarehouse()
    if not (farmer.menu and farmer.menu.id and farmer.menu.wareLine ~= nil) then
        return false
    end
    local seq = farmer.dialogSeq
    Farmer.Respond(farmer.menu.id, 1, farmer.menu.wareLine, "")
    return Farmer.WaitAdvance(seq) == "ware"
end

-- Нажатие Alt (заново открывает меню фермера после закрытия диалога)
function Farmer.PressAlt()
    if type(setVirtualKeyDown) ~= "function" then
        Farmer.Log("Не получилось нажать Alt: функция недоступна")
        return false
    end
    local hold = tonumber(settings.farmer.altHoldTime) or 100
    pcall(setVirtualKeyDown, 0x12, true)
    wait(hold)
    pcall(setVirtualKeyDown, 0x12, false)
    return true
end

-- Заново открыть меню фермера через Alt и дождаться его
function Farmer.ReopenMenuViaAlt()
    local delay = tonumber(settings.farmer.afterTakeDelay) or 400
    if delay > 0 then wait(delay) end
    local seq = farmer.dialogSeq
    if not Farmer.PressAlt() then return false end
    if Farmer.WaitAdvance(seq) == "menu" then
        return true
    end
    Farmer.Log("Меню фермера не открылось - похоже, вы отошли")
    return false
end

-- Гарантируем, что открыт диалог "Склад фермера" (при необходимости жмём Alt)
function Farmer.EnsureWare()
    if farmer.last.kind == "ware" and farmer.ware and farmer.ware.id then
        return true
    end
    if farmer.last.kind ~= "menu" or not (farmer.menu and farmer.menu.id) then
        if not Farmer.ReopenMenuViaAlt() then return false end
    end
    return Farmer.OpenWarehouse()
end

-- Убедиться, что меню фермера открыто. Если нет - жмём Alt; при неудаче сообщаем, что игрок далеко
function Farmer.EnsureMenu()
    if farmer.last.kind == "menu" and farmer.menu and farmer.menu.id then
        return true
    end
    if Farmer.ReopenMenuViaAlt() then
        return true
    end
    farmer.statusText = "Вы далеко от фермера"
    Chat.Add("Ферма: вы далеко от фермера", TYPECHATMESSAGES.WARNING)
    return false
end

function Farmer.DoTake()
    farmer.statusText = "Забираю ресурсы..."
    local guard = 0
    while farmer.active and guard < 30 do
        guard = guard + 1
        if not Farmer.EnsureWare() then break end
        local item = Farmer.NextTakeable()
        if not item then break end
        local seq = farmer.dialogSeq
        Farmer.Respond(farmer.ware.id, 1, item.line, "")
        local kind = Farmer.WaitAdvance(seq)
        Farmer.Log("Клик '" .. tostring(item.name) .. "' -> " .. tostring(kind), true)
        if kind ~= "takeInput" then break end
        local amount = tonumber(farmer.input.max) or 0
        local nm = (farmer.input.name ~= nil and farmer.input.name ~= "") and farmer.input.name or item.name
        Farmer.Log("Количество к забору: " .. tostring(amount), true)
        if amount > 0 then
            Farmer.Respond(farmer.input.id, 1, 0, tostring(amount))
            Farmer.AddCollected(nm, amount)
            -- диалог закрывается полностью; следующий проход откроет меню через Alt
        else
            Farmer.Log(string.format("Пропустил %s: сервер не показал количество", tostring(nm)))
            Farmer.Respond(farmer.input.id, 0, 0, "")
            break
        end
    end
end

function Farmer.DoFill()
    if not Farmer.EnsureWare() then return end
    if farmer.ware.putLine == nil then
        Farmer.Log("На складе нет пункта пополнения воды")
        return
    end
    farmer.statusText = "Пополняю воду..."
    local seq = farmer.dialogSeq
    Farmer.Respond(farmer.ware.id, 1, farmer.ware.putLine, "")
    if Farmer.WaitAdvance(seq) ~= "putInput" then
        -- окно осталось у игрока: если он зальёт руками, скрипт этого не увидит и в лог не запишет
        Farmer.Log("Окно пополнения воды не открылось - вода не залита и не посчитана")
        return
    end
    -- заливаем не выше заданного в настройках уровня (по умолчанию - полный бак)
    local farmMax = tonumber(farmer.input.farmMax) or 0
    local cap = tonumber(settings.farmer.fillTarget) or Farmer.WATER_MAX
    -- ползунок на максимуме = без ограничения: заливаем столько, сколько принимает фермер
    local target = (cap >= Farmer.WATER_MAX) and farmMax or math.minEx(cap, farmMax)
    local missing = math.maxEx(0, target - (tonumber(farmer.input.farmNow) or 0))
    local amount = math.minEx(missing, tonumber(farmer.input.have) or 0)
    Farmer.Log(string.format("Окно пополнения: у вас %d, у фермера %d/%d, зальём %d",
        tonumber(farmer.input.have) or 0, tonumber(farmer.input.farmNow) or 0, farmMax, amount), true)
    if amount > 0 then
        Farmer.Respond(farmer.input.id, 1, 0, tostring(amount))
        Farmer.AddWater(amount)
        farmer.invLiquid = math.maxEx(0, (tonumber(farmer.invLiquid) or 0) - amount)
        farmer.wareWaterNow = math.minEx(tonumber(farmer.wareWaterMax) or 0, (tonumber(farmer.wareWaterNow) or 0) + amount)
    else
        Farmer.Respond(farmer.input.id, 0, 0, "")
        if missing > 0 then
            Farmer.Log("У вас с собой нет воды")
        elseif target < farmMax then
            Farmer.Log(string.format("Вода у фермера уже на заданном уровне (%d из %d)", target, farmMax))
        else
            Farmer.Log("Вода у фермера уже залита доверху")
        end
    end
end

function Farmer.Finish(reason)
    -- Свежие "У вас: N" и запас воды сервер показывает только в окне пополнения:
    -- заглядываем туда, пока склад ещё открыт
    if farmer.last.kind == "ware" and farmer.ware and farmer.ware.id and farmer.ware.putLine ~= nil then
        farmer.statusText = "Обновляю запас воды..."
        Farmer.PeekWater()
    end
    Farmer.CloseChain()
    -- Переоткрываем меню через Alt, чтобы подтянуть свежие данные (склад/статус) после сбора/заливки
    farmer.statusText = "Обновляю данные..."
    Farmer.ReopenMenuViaAlt()
    Farmer.CloseChain()
    Storage.RequestSaveGreenhouseLog(true)
    farmer.active = false
    farmer.statusText = tostring(reason or "Готово")
    Collect.SyncResource("greenhouse", "complete")

    local parts = {}
    for name, amt in pairs(farmer.collected) do
        table.insert(parts, string.format("%s x%d", name, amt))
    end
    local summary = (#parts > 0) and table.concat(parts, ", ") or "ничего"
    Chat.Add(string.format("Теплицы: собрано (%s); воды залито: %d", summary, farmer.waterSpent or 0), TYPECHATMESSAGES.SUCCESS)
    Farmer.Log(tostring(reason or "Готово"))
end

-- Запас воды у фермера и остаток воды у игрока сервер показывает только в окне пополнения:
-- открываем его и считываем "Имеется у Вас: N" и "Имеется у фермера: N / M".
-- Окно остаётся открытым - закрывает его вызывающий через Farmer.CloseChain()
function Farmer.PeekWater()
    if not (farmer.ware and farmer.ware.id and farmer.ware.putLine ~= nil) then
        return false
    end
    local seq = farmer.dialogSeq
    Farmer.Respond(farmer.ware.id, 1, farmer.ware.putLine, "")
    return Farmer.WaitAdvance(seq) == "putInput"
end

-- Открыть склад фермы, обновить данные о содержимом и закрыть диалоги
function Farmer.CheckWare()
    if not Farmer.EnsureMenu() then
        farmer.active = false
        return
    end
    farmer.statusText = "Проверяю склад фермы..."
    Farmer.Log("Смотрю, что лежит на складе")
    local ok = Farmer.EnsureWare()

    -- содержимое склада уже разобрано, дальше читаем воду из окна пополнения
    if ok then
        farmer.statusText = "Проверяю запас воды..."
        if not Farmer.PeekWater() then
            Farmer.Log("Запас воды прочитать не удалось", true)
        end
    end

    Farmer.CloseChain()
    farmer.active = false
    farmer.statusText = ok and "Склад фермы обновлён" or "Не удалось открыть склад фермы"
end

-- Переключить статус фермера (собирает / не собирает).
-- Меню на сервере к этому моменту обычно уже закрыто, поэтому открываем его заново через Alt
function Farmer.ToggleStatus()
    if not Farmer.EnsureMenu() then
        farmer.active = false
        return
    end
    if farmer.menu.statusLine == nil then
        Farmer.Log("В меню фермера нет строки статуса")
        Farmer.CloseChain()
        farmer.active = false
        farmer.statusText = "Статус переключить не удалось"
        return
    end

    farmer.statusText = "Переключаю статус..."
    local seq = farmer.dialogSeq
    Farmer.Respond(farmer.menu.id, 1, farmer.menu.statusLine, "")
    -- сервер возвращает меню с новым статусом - его и разберём
    Farmer.WaitAdvance(seq)
    Farmer.CloseChain()
    farmer.active = false
    local st = (farmer.menu.status ~= nil and farmer.menu.status ~= "") and farmer.menu.status or "?"
    farmer.statusText = "Статус: " .. tostring(st)
    Farmer.Log("Статус фермера: " .. tostring(st))
end

function Farmer.Process()
    farmer.active = true
    if farmer.mode == "check" then
        Farmer.CheckWare()
        return
    end
    if farmer.mode == "status" then
        Farmer.ToggleStatus()
        return
    end
    if not Farmer.EnsureMenu() then
        farmer.active = false
        return
    end
    Collect.SyncResourceStart("greenhouse")
    farmer.collected = {}
    farmer.waterSpent = 0
    farmer.logs = {}
    local doTake = (farmer.mode == "take" or farmer.mode == "both")
    local doFill = (farmer.mode == "fill" or farmer.mode == "both")
    farmer.statusText = "Открываю склад..."
    Farmer.Log((doTake and doFill) and "Забираю урожай и пополняю воду"
        or (doTake and "Забираю урожай")
        or "Пополняю воду")

    if doTake then Farmer.DoTake() end
    if not farmer.active then
        Collect.SyncResource("greenhouse", "interrupted", "остановлено")
        return
    end
    if doFill then Farmer.DoFill() end
    if not farmer.active then
        Collect.SyncResource("greenhouse", "interrupted", "остановлено")
        return
    end

    Farmer.Finish("Готово")
end

function Farmer.Start(mode)
    if farmer.active then
        Chat.Add("Ферма: процесс уже запущен", TYPECHATMESSAGES.WARNING)
        return
    end
    farmer.mode = mode
    farmer.thread = RunThreadFresh(farmer.thread, Farmer.Process)
end

function Farmer.Cancel()
    if not farmer.active then return end
    farmer.active = false
    if farmer.ware and farmer.ware.id then sampSendDialogResponse(farmer.ware.id, 0, 0, "") end
    if farmer.menu and farmer.menu.id then sampSendDialogResponse(farmer.menu.id, 0, 0, "") end
    farmer.menuOpen = false
    if farmer.menu then farmer.menu.id = nil end
    farmer.statusText = "Отменено"
    Collect.SyncResource("greenhouse", "interrupted", "отменено игроком")
    Storage.RequestSaveGreenhouseLog(true)
    Farmer.Log("Вы отменили процесс")
    Chat.Add("Ферма: процесс отменён", TYPECHATMESSAGES.SECONDARY)
end

-- --------------------------------------------------------
--                    Greenhouse: логи теплиц
-- --------------------------------------------------------

function Greenhouse.Day(dateKey)
    dateKey = dateKey or os.date('%Y-%m-%d')
    greenhouseLog.days[dateKey] = greenhouseLog.days[dateKey] or { collected = {}, water = 0, updatedAt = os.time() }
    local d = greenhouseLog.days[dateKey]
    d.collected = d.collected or {}
    d.water = tonumber(d.water) or 0
    return d
end

function Greenhouse.AddCollected(name, amount)
    name = tostring(name or "Ресурс")
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return end
    local d = Greenhouse.Day()
    d.collected[name] = (tonumber(d.collected[name]) or 0) + amount
    d.updatedAt = os.time()
    greenhouseLog.lastCollectAt = d.updatedAt
    Storage.RequestSaveGreenhouseLog(false)
end

function Greenhouse.AddWater(amount)
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return end
    local d = Greenhouse.Day()
    d.water = (tonumber(d.water) or 0) + amount
    d.updatedAt = os.time()
    Storage.RequestSaveGreenhouseLog(false)
end

function Greenhouse.TrimOldDays()
    local keep = tonumber(settings.farmer and settings.farmer.logMaxDays) or 0
    if keep <= 0 then return end
    local fromKey = os.date('%Y-%m-%d', os.time() - (keep - 1) * 86400)
    for k in pairs(greenhouseLog.days) do
        if tostring(k) < fromKey then
            greenhouseLog.days[k] = nil
        end
    end
end

function Greenhouse.SortedDayKeys()
    local keys = {}
    for k in pairs(greenhouseLog.days) do
        table.insert(keys, k)
    end
    table.sort(keys, function(a, b) return tostring(a) > tostring(b) end)
    return keys
end


-- Хранилище логов теплиц
function Storage.LoadGreenhouseLog()
    local ok, data = pcall(Storage.LoadJSON, GREENHOUSE_STATS_FILE)
    if not ok or type(data) ~= "table" then data = {} end
    greenhouseLog.days = (type(data.days) == "table") and data.days or {}
    greenhouseLog.lastCollectAt = tonumber(data.lastCollectAt) or Collect.LastCollectFromDays(greenhouseLog.days)
    Greenhouse.TrimOldDays()
end

function Storage.SaveGreenhouseLog()
    local ok, res = pcall(Storage.SaveJSON, GREENHOUSE_STATS_FILE, { days = greenhouseLog.days, lastCollectAt = greenhouseLog.lastCollectAt })
    if ok and res then
        greenhouseLog.dirty = false
        greenhouseLog.lastSaveAt = os.clock()
        return true
    end
    return false
end

function Storage.RequestSaveGreenhouseLog(force)
    greenhouseLog.dirty = true
    local now = os.clock()
    if force or (now - (greenhouseLog.lastSaveAt or 0)) >= 2 then
        return Storage.SaveGreenhouseLog()
    end
    return false
end

Storage.LoadGreenhouseLog()

-- =====================================================================================================================
--                                                          MINER
-- =====================================================================================================================

-- --------------------------------------------------------
--                    Miner: разбор диалогов
-- --------------------------------------------------------

-- Сколько всего влезает зарядки в майнера
Miner.CHARGE_MAX = 10

-- Разбор диалога "Меню майнера"
function Miner.ParseMenu(text, style)
    local m = { id = nil, status = "", storeNow = 0, storeMax = 0, wareLine = nil, statusLine = nil }
    text = Farmer.stripColors(text)
    local idx = 0
    for line in tostring(text or ""):gmatch("[^\r\n]+") do
        idx = idx + 1
        local low = Farmer.lower(line)
        if low:find("убрать майнера") then
            -- строку "Убрать майнера" скрипт не трогает никогда
        elseif low:find("склад майнера") then
            m.wareLine = Farmer.ListItem(idx, style)
            local a, b = line:match("(%d[%d%s]*)%s*/%s*(%d[%d%s]*)")
            if a then
                m.storeNow = Farmer.num(a)
                m.storeMax = Farmer.num(b)
            end
        elseif low:find("статус") then
            m.statusLine = Farmer.ListItem(idx, style)
            local v = line:match(".*%[%s*(.-)%s*%]")
            if v then m.status = v end
        end
    end
    return m
end

-- Строка склада с зарядкой майнера: её забирать нельзя, иначе вынем заряд из самого майнера
function Miner.IsCharge(name)
    return Farmer.lower(Farmer.stripColors(name)):find("заряд") ~= nil
end

-- Разбор диалога "Склад майнера"
function Miner.ParseWare(text, style)
    local w = { id = nil, items = {}, putLine = nil, chargeName = nil, chargeLine = nil, chargeInWare = 0 }
    text = Farmer.stripColors(text)
    local idx = 0
    for line in tostring(text or ""):gmatch("[^\r\n]+") do
        idx = idx + 1
        local low = Farmer.lower(line)
        local li = Farmer.ListItem(idx, style)
        if low:find("положить") then
            w.putLine = li
            local nm = line:match("'(.-)'") or line:match('"(.-)"')
            if nm then w.chargeName = Farmer.cleanName(nm) end
        else
            local cols = {}
            for part in line:gmatch("[^\t]+") do
                table.insert(cols, (part:gsub("^%s+", ""):gsub("%s+$", "")))
            end
            if #cols >= 2 then
                local name = cols[1]
                local count = Farmer.num(cols[#cols])
                if Miner.IsCharge(name) then
                    -- зарядка майнера: запоминаем строку, но в список забираемого не кладём
                    w.chargeLine = li
                    w.chargeInWare = count
                    if w.chargeName == nil or w.chargeName == "" then
                        w.chargeName = Farmer.cleanName(name)
                    end
                elseif name ~= "" and (count > 0 or low:find("ед")) then
                    table.insert(w.items, {
                        line = li,
                        name = Farmer.cleanName(name),
                        count = count,
                    })
                end
            end
        end
    end
    return w
end

-- Разбор диалога "Положить на склад майнера"
function Miner.ParsePutInput(text)
    text = Farmer.stripColors(text)
    local name = text:match("аименование:%s*(.-)%s*[\r\n]") or ""
    local have = Farmer.num(text:match("ас:%s*(%d[%d%s]*)"))
    local mn, mm = text:match("айнера:%s*(%d[%d%s]*)%s*/%s*(%d[%d%s]*)")
    return {
        name = Farmer.cleanName(name),
        have = have,
        minerNow = Farmer.num(mn),
        minerMax = Farmer.num(mm),
    }
end

function Miner.NextTakeable()
    for _, it in ipairs((miner.ware and miner.ware.items) or {}) do
        if (it.count or 0) > 0 and not (it.line ~= nil and miner.skipLines[it.line]) then
            return it
        end
    end
    return nil
end

-- Диспетчер диалогов майнера. Возвращает nil (не наш диалог) / true / false (видимость)
function Miner.HandleDialog(dialogId, style, title, text)
    local low = Farmer.lower(Farmer.stripColors(title or ""))

    if low:find("меню майнера") then
        local menu = Miner.ParseMenu(text, style)
        menu.id = dialogId
        miner.menu = menu
        miner.menuOpen = true
        miner.last = { kind = "menu", id = dialogId, style = style }
        miner.dialogSeq = miner.dialogSeq + 1
        imguiWindows.main[0] = true
        activeMode = "miner"
        if activeTabScript == "improve" then activeTabScript = "main" end
        if not miner.active then
            local mode = nil
            if settings.miner.autoTake and settings.miner.autoFill then
                mode = "both"
            elseif settings.miner.autoTake then
                mode = "take"
            elseif settings.miner.autoFill then
                mode = "fill"
            elseif settings.miner.refreshOnOpen then
                -- автодействий нет: хотя бы подтянем свежее содержимое склада
                mode = "check"
            end
            if mode then
                lua_thread.create(function()
                    wait(50)
                    Miner.Start(mode)
                end)
            end
        end
        if settings.main.replaceDialog then return false end
        return true
    end

    -- Заголовки "Положить на склад" / "Забрать" совпадают с фермерскими,
    -- поэтому перехватываем их только когда работает именно майнер.
    -- Проверяем их раньше склада: "Положить на склад майнера" тоже содержит "склад майнера"
    if low:find("положить на склад") then
        if not miner.active then return nil end
        local inp = Miner.ParsePutInput(text)
        inp.kind = "put"
        inp.id = dialogId
        miner.input = inp
        miner.invCharge = tonumber(inp.have) or 0
        miner.chargeNow = tonumber(inp.minerNow) or 0
        miner.chargeMax = tonumber(inp.minerMax) or 0
        miner.last = { kind = "putInput", id = dialogId, style = style }
        miner.dialogSeq = miner.dialogSeq + 1
        return false
    end

    if low:find("забрать") then
        if not miner.active then return nil end
        local inp = Farmer.ParseTakeInput(text)
        inp.kind = "take"
        inp.id = dialogId
        miner.input = inp
        miner.last = { kind = "takeInput", id = dialogId, style = style }
        miner.dialogSeq = miner.dialogSeq + 1
        return false
    end

    if low:find("склад майнера") then
        if not miner.active then return nil end
        local ware = Miner.ParseWare(text, style)
        ware.id = dialogId
        miner.ware = ware
        miner.wareAt = os.time()
        miner.last = { kind = "ware", id = dialogId, style = style }
        miner.dialogSeq = miner.dialogSeq + 1
        return false
    end

    return nil
end

-- --------------------------------------------------------
--                    Miner: логика процесса
-- --------------------------------------------------------

-- Запись в журнал действий. debugOnly = только в консоль (техническая отладка)
function Miner.Log(msg, debugOnly)
    local text = tostring(msg)
    if settings.main.typeChatMessage and settings.main.typeChatMessage.debug then
        print(string.format("[MINER] [%s] %s", os.date('%H:%M:%S'), text))
    end
    if debugOnly then return end
    table.insert(miner.logs, { time = os.date('%H:%M:%S'), text = text })
    while #miner.logs > 200 do
        table.remove(miner.logs, 1)
    end
end

function Miner.AddCollected(name, amount)
    name = (name ~= nil and name ~= "") and name or "Тёмная материя"
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return end
    miner.collected[name] = (tonumber(miner.collected[name]) or 0) + amount
    Miner.LogCollected(name, amount)
    Miner.Log(string.format("Забрал %s - %d шт.", name, amount))
end

function Miner.AddCharge(amount)
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return end
    miner.chargeSpent = (miner.chargeSpent or 0) + amount
    Miner.LogCharge(amount)
    Miner.Log(string.format("Зарядил майнера - %d ед.", amount))
end

function Miner.Respond(id, btn, list, input)
    local d = tonumber(settings.miner.actionDelay) or 0
    if d > 0 then wait(d) end
    sampSendDialogResponse(id, btn, list or 0, input or "")
end

-- Ждём появления следующего диалога майнера (по счётчику dialogSeq)
function Miner.WaitAdvance(startSeq)
    local interval = tonumber(settings.miner.waitInterval) or 10
    local timeout = os.clock() + (tonumber(settings.miner.timeout) or 10)
    while miner.active do
        if miner.dialogSeq ~= startSeq then
            return miner.last.kind
        end
        wait(interval)
        if os.clock() > timeout then
            return nil
        end
    end
    return nil
end

-- Закрывает всё, что осталось открытым. Отвечаем именно тому диалогу, который пришёл последним:
-- на Cancel сервер часто возвращает предыдущее окно, а ответ по устаревшему id он игнорирует,
-- и тогда на экране висит "мёртвый" диалог, который уже ничего не открывает
function Miner.CloseChain(limit)
    limit = tonumber(limit) or 4
    local interval = tonumber(settings.miner.waitInterval) or 10
    for _ = 1, limit do
        local id = miner.last and miner.last.id
        if id == nil then break end
        local seq = miner.dialogSeq
        Miner.Respond(id, 0, 0, "")
        local deadline = os.clock() + 0.35
        while os.clock() < deadline and miner.dialogSeq == seq do
            wait(interval)
        end
        -- сервер ничего не прислал в ответ - значит закрылось всё
        if miner.dialogSeq == seq then break end
    end
    miner.last = { kind = nil, id = nil, style = nil }
    if miner.menu then miner.menu.id = nil end
    if miner.ware then miner.ware.id = nil end
    miner.menuOpen = false
end

function Miner.OpenWarehouse()
    if not (miner.menu and miner.menu.id and miner.menu.wareLine ~= nil) then
        return false
    end
    local seq = miner.dialogSeq
    Miner.Respond(miner.menu.id, 1, miner.menu.wareLine, "")
    return Miner.WaitAdvance(seq) == "ware"
end

-- Нажатие Alt (заново открывает меню майнера после закрытия диалога)
function Miner.PressAlt()
    if type(setVirtualKeyDown) ~= "function" then
        Miner.Log("Не получилось нажать Alt: функция недоступна")
        return false
    end
    local hold = tonumber(settings.miner.altHoldTime) or 100
    pcall(setVirtualKeyDown, 0x12, true)
    wait(hold)
    pcall(setVirtualKeyDown, 0x12, false)
    return true
end

-- Заново открыть меню майнера через Alt и дождаться его
function Miner.ReopenMenuViaAlt()
    local delay = tonumber(settings.miner.afterTakeDelay) or 400
    if delay > 0 then wait(delay) end
    local seq = miner.dialogSeq
    if not Miner.PressAlt() then return false end
    if Miner.WaitAdvance(seq) == "menu" then
        return true
    end
    Miner.Log("Меню майнера не открылось - похоже, вы отошли")
    return false
end

-- Гарантируем, что открыт диалог "Склад майнера" (при необходимости жмём Alt)
function Miner.EnsureWare()
    if miner.last.kind == "ware" and miner.ware and miner.ware.id then
        return true
    end
    if miner.last.kind ~= "menu" or not (miner.menu and miner.menu.id) then
        if not Miner.ReopenMenuViaAlt() then return false end
    end
    return Miner.OpenWarehouse()
end

-- Убедиться, что меню майнера открыто. Если нет - жмём Alt; при неудаче сообщаем, что игрок далеко
function Miner.EnsureMenu()
    if miner.last.kind == "menu" and miner.menu and miner.menu.id then
        return true
    end
    if Miner.ReopenMenuViaAlt() then
        return true
    end
    miner.statusText = "Вы далеко от майнера"
    Chat.Add("Майнер: вы далеко от майнера", TYPECHATMESSAGES.WARNING)
    return false
end

function Miner.DoTake()
    miner.statusText = "Забираю ресурсы..."
    local guard = 0
    while miner.active and guard < 30 do
        guard = guard + 1
        if not Miner.EnsureWare() then break end
        local item = Miner.NextTakeable()
        if not item then break end
        local seq = miner.dialogSeq
        Miner.Respond(miner.ware.id, 1, item.line, "")
        local kind = Miner.WaitAdvance(seq)
        Miner.Log("Клик '" .. tostring(item.name) .. "' -> " .. tostring(kind), true)
        if kind ~= "takeInput" then break end
        local amount = tonumber(miner.input.max) or 0
        local nm = (miner.input.name ~= nil and miner.input.name ~= "") and miner.input.name or item.name
        Miner.Log("Количество к забору: " .. tostring(amount), true)
        if Miner.IsCharge(nm) then
            -- на складе строка могла называться иначе, чем в окне забора - отменяем и больше её не трогаем
            Miner.Respond(miner.input.id, 0, 0, "")
            if item.line ~= nil then miner.skipLines[item.line] = true end
            Miner.Log(string.format("Пропустил %s: зарядку майнера не забираем", tostring(nm)))
        elseif amount > 0 then
            Miner.Respond(miner.input.id, 1, 0, tostring(amount))
            Miner.AddCollected(nm, amount)
            -- диалог закрывается полностью; следующий проход откроет меню через Alt
        else
            Miner.Log(string.format("Пропустил %s: сервер не показал количество", tostring(nm)))
            Miner.Respond(miner.input.id, 0, 0, "")
            break
        end
    end
end

function Miner.DoFill()
    if not Miner.EnsureWare() then return end
    if miner.ware.putLine == nil then
        Miner.Log("На складе нет пункта зарядки майнера")
        return
    end
    miner.statusText = "Заряжаю майнера..."
    local seq = miner.dialogSeq
    Miner.Respond(miner.ware.id, 1, miner.ware.putLine, "")
    if Miner.WaitAdvance(seq) ~= "putInput" then
        -- окно осталось у игрока: если он зарядит руками, скрипт этого не увидит и в лог не запишет
        Miner.Log("Окно зарядки не открылось - зарядка не залита и не посчитана")
        return
    end
    -- заряжаем не выше заданного в настройках уровня (по умолчанию - полный заряд)
    local minerMax = tonumber(miner.input.minerMax) or 0
    local cap = tonumber(settings.miner.fillTarget) or Miner.CHARGE_MAX
    -- ползунок на максимуме = без ограничения: заряжаем столько, сколько принимает майнер
    local target = (cap >= Miner.CHARGE_MAX) and minerMax or math.minEx(cap, minerMax)
    local missing = math.maxEx(0, target - (tonumber(miner.input.minerNow) or 0))
    local amount = math.minEx(missing, tonumber(miner.input.have) or 0)
    Miner.Log(string.format("Окно зарядки: у вас %d, у майнера %d/%d, зальём %d",
        tonumber(miner.input.have) or 0, tonumber(miner.input.minerNow) or 0, minerMax, amount), true)
    if amount > 0 then
        Miner.Respond(miner.input.id, 1, 0, tostring(amount))
        Miner.AddCharge(amount)
        miner.invCharge = math.maxEx(0, (tonumber(miner.invCharge) or 0) - amount)
        miner.chargeNow = math.minEx(tonumber(miner.chargeMax) or 0, (tonumber(miner.chargeNow) or 0) + amount)
    else
        Miner.Respond(miner.input.id, 0, 0, "")
        if missing > 0 then
            Miner.Log("У вас с собой нет зарядки")
        elseif target < minerMax then
            Miner.Log(string.format("Майнер уже заряжен до заданного уровня (%d из %d)", target, minerMax))
        else
            Miner.Log("Майнер уже заряжен полностью")
        end
    end
end

function Miner.Finish(reason)
    -- Свежие "У вас: N" и заряд майнера сервер показывает только в окне пополнения:
    -- заглядываем туда, пока склад ещё открыт
    if miner.last.kind == "ware" and miner.ware and miner.ware.id and miner.ware.putLine ~= nil then
        miner.statusText = "Обновляю заряд..."
        Miner.PeekCharge()
    end
    Miner.CloseChain()
    -- Переоткрываем меню через Alt, чтобы подтянуть свежие данные (склад/статус) после сбора/зарядки
    miner.statusText = "Обновляю данные..."
    Miner.ReopenMenuViaAlt()
    Miner.CloseChain()
    Storage.RequestSaveMinerLog(true)
    miner.active = false
    miner.statusText = tostring(reason or "Готово")
    Collect.SyncResource("miner", "complete")

    local parts = {}
    for name, amt in pairs(miner.collected) do
        table.insert(parts, string.format("%s x%d", name, amt))
    end
    local summary = (#parts > 0) and table.concat(parts, ", ") or "ничего"
    Chat.Add(string.format("Майнер: собрано (%s); зарядки залито: %d", summary, miner.chargeSpent or 0), TYPECHATMESSAGES.SUCCESS)
    Miner.Log(tostring(reason or "Готово"))
end

-- Заряд майнера и остаток зарядки у игрока сервер показывает только в окне пополнения:
-- открываем его и считываем "Имеется у Вас: N" и "Имеется у майнера: N / M".
-- Окно остаётся открытым - закрывает его вызывающий через Miner.CloseChain()
function Miner.PeekCharge()
    if not (miner.ware and miner.ware.id and miner.ware.putLine ~= nil) then
        return false
    end
    local seq = miner.dialogSeq
    Miner.Respond(miner.ware.id, 1, miner.ware.putLine, "")
    return Miner.WaitAdvance(seq) == "putInput"
end

function Miner.CheckWare()
    if not Miner.EnsureMenu() then
        miner.active = false
        return
    end
    miner.statusText = "Проверяю склад майнера..."
    Miner.Log("Смотрю, что лежит на складе майнера")
    local ok = Miner.EnsureWare()

    -- содержимое склада уже разобрано, дальше читаем заряд из окна пополнения
    if ok then
        miner.statusText = "Проверяю заряд майнера..."
        if not Miner.PeekCharge() then
            Miner.Log("Заряд майнера прочитать не удалось", true)
        end
    end

    Miner.CloseChain()
    miner.active = false
    miner.statusText = ok and "Склад майнера обновлён" or "Не удалось открыть склад майнера"
end

-- Переключить статус майнера (собирает / не собирает).
-- Меню на сервере к этому моменту обычно уже закрыто, поэтому открываем его заново через Alt
function Miner.ToggleStatus()
    if not Miner.EnsureMenu() then
        miner.active = false
        return
    end
    if miner.menu.statusLine == nil then
        Miner.Log("В меню майнера нет строки статуса")
        Miner.CloseChain()
        miner.active = false
        miner.statusText = "Статус переключить не удалось"
        return
    end

    miner.statusText = "Переключаю статус..."
    local seq = miner.dialogSeq
    Miner.Respond(miner.menu.id, 1, miner.menu.statusLine, "")
    -- сервер возвращает меню с новым статусом - его и разберём
    Miner.WaitAdvance(seq)
    Miner.CloseChain()
    miner.active = false
    local st = (miner.menu.status ~= nil and miner.menu.status ~= "") and miner.menu.status or "?"
    miner.statusText = "Статус: " .. tostring(st)
    Miner.Log("Статус майнера: " .. tostring(st))
end

function Miner.Process()
    miner.active = true
    if miner.mode == "check" then
        Miner.CheckWare()
        return
    end
    if miner.mode == "status" then
        Miner.ToggleStatus()
        return
    end
    if not Miner.EnsureMenu() then
        miner.active = false
        return
    end
    Collect.SyncResourceStart("miner")
    miner.collected = {}
    miner.chargeSpent = 0
    miner.skipLines = {}
    miner.logs = {}
    local doTake = (miner.mode == "take" or miner.mode == "both")
    local doFill = (miner.mode == "fill" or miner.mode == "both")
    miner.statusText = "Открываю склад..."
    Miner.Log((doTake and doFill) and "Забираю материю и заряжаю майнера"
        or (doTake and "Забираю тёмную материю")
        or "Заряжаю майнера")

    if doTake then Miner.DoTake() end
    if not miner.active then
        Collect.SyncResource("miner", "interrupted", "остановлено")
        return
    end
    if doFill then Miner.DoFill() end
    if not miner.active then
        Collect.SyncResource("miner", "interrupted", "остановлено")
        return
    end

    Miner.Finish("Готово")
end

function Miner.Start(mode)
    if miner.active then
        Chat.Add("Майнер: процесс уже запущен", TYPECHATMESSAGES.WARNING)
        return
    end
    miner.mode = mode
    miner.thread = RunThreadFresh(miner.thread, Miner.Process)
end

function Miner.Cancel()
    if not miner.active then return end
    miner.active = false
    if miner.ware and miner.ware.id then sampSendDialogResponse(miner.ware.id, 0, 0, "") end
    if miner.menu and miner.menu.id then sampSendDialogResponse(miner.menu.id, 0, 0, "") end
    miner.menuOpen = false
    if miner.menu then miner.menu.id = nil end
    miner.statusText = "Отменено"
    Collect.SyncResource("miner", "interrupted", "отменено игроком")
    Storage.RequestSaveMinerLog(true)
    Miner.Log("Вы отменили процесс")
    Chat.Add("Майнер: процесс отменён", TYPECHATMESSAGES.SECONDARY)
end

-- --------------------------------------------------------
--                    Miner: логи сбора
-- --------------------------------------------------------

function Miner.Day(dateKey)
    dateKey = dateKey or os.date('%Y-%m-%d')
    minerLog.days[dateKey] = minerLog.days[dateKey] or { collected = {}, charge = 0, updatedAt = os.time() }
    local d = minerLog.days[dateKey]
    d.collected = d.collected or {}
    d.charge = tonumber(d.charge) or 0
    return d
end

function Miner.LogCollected(name, amount)
    name = tostring(name or "Ресурс")
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return end
    local d = Miner.Day()
    d.collected[name] = (tonumber(d.collected[name]) or 0) + amount
    d.updatedAt = os.time()
    minerLog.lastCollectAt = d.updatedAt
    Storage.RequestSaveMinerLog(false)
end

function Miner.LogCharge(amount)
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return end
    local d = Miner.Day()
    d.charge = (tonumber(d.charge) or 0) + amount
    d.updatedAt = os.time()
    Storage.RequestSaveMinerLog(false)
end

function Miner.TrimOldDays()
    local keep = tonumber(settings.miner and settings.miner.logMaxDays) or 0
    if keep <= 0 then return end
    local fromKey = os.date('%Y-%m-%d', os.time() - (keep - 1) * 86400)
    for k in pairs(minerLog.days) do
        if tostring(k) < fromKey then
            minerLog.days[k] = nil
        end
    end
end

-- Хранилище логов майнера
function Storage.LoadMinerLog()
    local ok, data = pcall(Storage.LoadJSON, MINER_STATS_FILE)
    if not ok or type(data) ~= "table" then data = {} end
    minerLog.days = (type(data.days) == "table") and data.days or {}
    minerLog.lastCollectAt = tonumber(data.lastCollectAt) or Collect.LastCollectFromDays(minerLog.days)
    Miner.TrimOldDays()
end

function Storage.SaveMinerLog()
    local ok, res = pcall(Storage.SaveJSON, MINER_STATS_FILE, { days = minerLog.days, lastCollectAt = minerLog.lastCollectAt })
    if ok and res then
        minerLog.dirty = false
        minerLog.lastSaveAt = os.clock()
        return true
    end
    return false
end

function Storage.RequestSaveMinerLog(force)
    minerLog.dirty = true
    local now = os.clock()
    if force or (now - (minerLog.lastSaveAt or 0)) >= 2 then
        return Storage.SaveMinerLog()
    end
    return false
end

Storage.LoadMinerLog()

-- =====================================================================================================================
--                                                          MIRAGE (сарай миража)
-- =====================================================================================================================
-- Сарай копит монеты миража (до 10). Номер дома и остаток на складе видны в 3D-тексте
-- над сараем, по Alt открывается диалог с накоплением и ценой. Забор - кнопка "Выбрать".
-- Сбор засчитывается только после подтверждения: 3D-текст сарая показал меньше монет
-- или сервер написал про монеты миража.

Mirage.FILE = PATCHCONFIG .. 'MirageStats.json'
Mirage.ITEM_ID = 8094
Mirage.ITEM_NAME = 'Монета Миража'
-- Каждый сбор стоит фиксированную сумму: потрачено = число сборов * цена
Mirage.COLLECT_COST = 200000
Mirage.CONFIRM_TIMEOUT = 8
-- на каком расстоянии от надписи считать, что игрок стоит у этого сарая
Mirage.SHED_RADIUS = 15

function Mirage.Clean(s)
    return Farmer.stripColors(tostring(s or ''))
end

-- "200.000" / "$ 200 000" -> 200000
function Mirage.Money(s)
    local digits = tostring(s or ''):gsub('[^%d]', '')
    return tonumber(digits) or 0
end

function Mirage.Log(msg)
    local st = Mirage.st
    table.insert(st.logs, { time = os.date('%H:%M:%S'), text = tostring(msg) })
    while #st.logs > 200 do
        table.remove(st.logs, 1)
    end
end

-- ----- 3D-текст над сараем -----

function Mirage.On3DText(id, position, text)
    local low = Farmer.lower(Mirage.Clean(text))
    if not low:find('сарай миража', 1, true) then return end

    local house = low:match('дому%s*№%s*(%d+)')
    local coins = tonumber(low:match('на складе:%s*(%d+)'))
    local pos = type(position) == 'table' and position or {}
    -- ключ - номер дома: при входе в дом и выходе сервер пересоздаёт надписи
    -- с новыми id, а старые не удаляет, и сараи в списке задваивались
    local key = house and ('house' .. house) or ('label' .. tostring(id))
    Mirage.st.shedKeys[id] = key
    Mirage.st.sheds[key] = {
        id = id,
        house = house,
        coins = coins,
        x = tonumber(pos.x) or 0,
        y = tonumber(pos.y) or 0,
        z = tonumber(pos.z) or 0,
        at = os.time(),
    }

    -- сервер пересоздал надпись после оплаты: монет на складе стало меньше
    local pending = Mirage.st.pending
    if pending and coins and pending.house and house == pending.house and coins < pending.before then
        Mirage.Confirm()
    end
end

function Mirage.Remove3DText(id)
    local st = Mirage.st
    local key = st.shedKeys[id]
    st.shedKeys[id] = nil
    -- надпись могли уже пересоздать с другим id - такую запись не трогаем
    if key and st.sheds[key] and st.sheds[key].id == id then
        st.sheds[key] = nil
    end
end

-- Расстояние от игрока до сарая, метров (nil - координаты игрока неизвестны)
function Mirage.Distance(shed)
    local ok, x, y, z = pcall(getCharCoordinates, PLAYER_PED)
    if not ok or not x then return nil end
    return math.sqrt((shed.x - x) ^ 2 + (shed.y - y) ^ 2 + (shed.z - z) ^ 2)
end

-- Сараи в радиусе из настроек, от ближнего к дальнему
function Mirage.NearbySheds()
    local radius = tonumber(settings.mirage.nearRadius) or 50
    local rows = {}
    for _, shed in pairs(Mirage.st.sheds) do
        local dist = Mirage.Distance(shed)
        if dist and dist <= radius then
            table.insert(rows, { shed = shed, dist = dist })
        end
    end
    table.sort(rows, function(a, b) return a.dist < b.dist end)
    return rows
end

-- Сарай, возле которого стоит игрок (по 3D-тексту)
function Mirage.NearestShed()
    local ok, x, y, z = pcall(getCharCoordinates, PLAYER_PED)
    if not ok or not x then return nil end
    local best, bestDist = nil, nil
    for _, shed in pairs(Mirage.st.sheds) do
        local d = (shed.x - x) ^ 2 + (shed.y - y) ^ 2 + (shed.z - z) ^ 2
        if not bestDist or d < bestDist then
            best, bestDist = shed, d
        end
    end
    if best and bestDist <= Mirage.SHED_RADIUS ^ 2 then
        return best
    end
    return nil
end

-- ----- Диалог сарая -----

function Mirage.HandleDialog(dialogId, style, title, text)
    local low = Farmer.lower(Mirage.Clean(title))
    if not low:find('сарай миража', 1, true) then return nil end

    local st = Mirage.st
    local body = Farmer.lower(Mirage.Clean(text))
    local now, max = body:match('накопилось:%s*(%d+)%s*/%s*(%d+)')

    -- после оплаты сервер может спросить подтверждение: если забор начал скрипт, соглашаемся
    if not now and st.pending then
        Mirage.Log('Сервер попросил подтвердить оплату')
        if st.pending.auto then
            sampSendDialogResponse(dialogId, 1, 0, '')
            return false
        end
        return true
    end

    st.dialogId = dialogId
    st.dialogStyle = style
    st.open = true
    st.now = tonumber(now) or 0
    st.max = tonumber(max) or 10
    st.cost = 0
    for line in body:gmatch('[^\r\n]+') do
        if line:find('стоимость', 1, true) then
            st.cost = Mirage.Money(line)
        end
    end
    if st.cost == 0 then
        st.cost = Mirage.COLLECT_COST
    end
    st.dialogAt = os.time()
    local shed = Mirage.NearestShed()
    st.house = shed and shed.house or nil

    Mirage.Log(string.format('Открыт сарай%s: %d/%d монет',
        st.house and (' дома №' .. st.house) or '', st.now, st.max))

    local autoTake = settings.mirage.autoTake and st.now > 0
    if not (autoTake and settings.mirage.hideOnAutoTake) then
        imguiWindows.main[0] = true
        activeMode = 'mirage'
        if activeTabScript == 'improve' then activeTabScript = 'main' end
    end

    if autoTake then
        Mirage.Take(true)
        return false
    end
    if settings.main.replaceDialog then return false end
    return true
end

-- Игрок сам нажал "Выбрать" в окне сарая
function Mirage.OnDialogResponse(dialogId, button)
    local st = Mirage.st
    if not st.open or dialogId ~= st.dialogId then return end
    st.open = false
    if button == 1 and st.now > 0 and not st.pending then
        Mirage.BeginPending(false)
    end
end

function Mirage.BeginPending(auto)
    local st = Mirage.st
    st.pending = {
        auto = auto == true,
        house = st.house,
        before = st.now,
        coins = st.now,
        cost = st.cost,
        at = os.clock(),
        startedAt = os.time(),
    }
    st.statusText = 'Забираю монеты...'
end

function Mirage.Take(auto)
    local st = Mirage.st
    if not (st.open and st.dialogId) then return false end
    if st.now <= 0 then
        st.statusText = 'Монет в сарае пока нет'
        return false
    end
    Mirage.BeginPending(auto ~= false)
    st.open = false
    sampSendDialogResponse(st.dialogId, 1, 0, '')
    return true
end

-- Закрыть окно сарая, ничего не забирая
function Mirage.Close()
    local st = Mirage.st
    if st.open and st.dialogId then
        sampSendDialogResponse(st.dialogId, 0, 0, '')
    end
    st.open = false
end

-- ----- Подтверждение -----

function Mirage.HandleServerMessage(text)
    local st = Mirage.st
    if not st.pending then return end
    local low = Farmer.lower(Mirage.Clean(text))

    if low:find('недостаточно', 1, true) then
        st.pending = nil
        st.statusText = 'Не хватает денег на сбор'
        Mirage.Log('Сервер: недостаточно денег - монеты не забраны')
        return
    end

    if text:find(':item' .. Mirage.ITEM_ID .. ':', 1, true)
        or (low:find('мираж', 1, true) and low:find('монет', 1, true))
    then
        Mirage.Confirm()
    end
end

function Mirage.Confirm()
    local st = Mirage.st
    local pending = st.pending
    if not pending then return end
    st.pending = nil

    local coins = pending.coins
    st.now = 0
    st.sessionCoins = (st.sessionCoins or 0) + coins
    st.sessionCollects = (st.sessionCollects or 0) + 1
    st.sessionSpent = st.sessionCollects * Mirage.COLLECT_COST
    Mirage.AddLog(coins)

    st.statusText = string.format('Забрано монет: %d', coins)
    Mirage.Log(string.format('Забрал %d монет, заплатил $%d', coins, Mirage.COLLECT_COST))
    Chat.Add(string.format('Сарай миража: забрано монет: %d%s', coins,
        pending.house and (' (дом №' .. pending.house .. ')') or ''), TYPECHATMESSAGES.SUCCESS)

    Collect.SyncMirage(pending, coins)
end

-- Вызывается из фонового цикла
function Mirage.Tick()
    local st = Mirage.st
    local pending = st.pending
    if pending and (os.clock() - pending.at) > Mirage.CONFIRM_TIMEOUT then
        st.pending = nil
        st.statusText = 'Сервер не подтвердил сбор'
        Mirage.Log('Подтверждения от сервера не было - сбор не записан')
    end

    local log = Mirage.log
    if log.dirty and (os.clock() - (log.lastSaveAt or 0)) >= 5 then
        Storage.SaveMirageLog()
    end
end

-- ----- Лог по дням -----

function Mirage.Day(dateKey)
    dateKey = dateKey or os.date('%Y-%m-%d')
    Mirage.log.days[dateKey] = Mirage.log.days[dateKey] or { collected = {}, spent = 0, updatedAt = os.time() }
    local d = Mirage.log.days[dateKey]
    d.collected = d.collected or {}
    d.spent = tonumber(d.spent) or 0
    return d
end

function Mirage.AddLog(coins)
    local d = Mirage.Day()
    d.collected[Mirage.ITEM_NAME] = (tonumber(d.collected[Mirage.ITEM_NAME]) or 0) + coins
    -- потрачено считаем от числа сборов: каждый сбор - фиксированная плата
    d.collects = (tonumber(d.collects) or 0) + 1
    d.spent = d.collects * Mirage.COLLECT_COST
    d.updatedAt = os.time()
    Mirage.log.lastCollectAt = d.updatedAt
    Mirage.log.dirty = true
    Storage.SaveMirageLog()
end

function Mirage.TrimOldDays()
    local keep = tonumber(settings.mirage and settings.mirage.logMaxDays) or 0
    if keep <= 0 then return end
    local fromKey = os.date('%Y-%m-%d', os.time() - (keep - 1) * 86400)
    for k in pairs(Mirage.log.days) do
        if tostring(k) < fromKey then
            Mirage.log.days[k] = nil
        end
    end
end

function Storage.LoadMirageLog()
    local ok, data = pcall(Storage.LoadJSON, Mirage.FILE)
    if not ok or type(data) ~= 'table' then data = {} end
    Mirage.log.days = (type(data.days) == 'table') and data.days or {}
    Mirage.log.lastCollectAt = tonumber(data.lastCollectAt) or Collect.LastCollectFromDays(Mirage.log.days)
    Mirage.TrimOldDays()
end

function Storage.SaveMirageLog()
    local ok, res = pcall(Storage.SaveJSON, Mirage.FILE, { days = Mirage.log.days, lastCollectAt = Mirage.log.lastCollectAt })
    if ok and res then
        Mirage.log.dirty = false
        Mirage.log.lastSaveAt = os.clock()
        return true
    end
    return false
end

Storage.LoadMirageLog()

-- ----- Облачный лог -----

function Collect.SyncMirage(pending, coins)
    if not Collect.SyncEnabled() then return end
    local event = Collect.SyncBase('mirage', 'complete', nil, pending.startedAt)
    event.session_id = Collect.SyncNewId('s')
    event.house_id = pending.house and tostring(pending.house) or json.null
    event.items = { { item_id = Mirage.ITEM_ID, name = u8(Mirage.ITEM_NAME), amount = coins } }
    event.spent = Mirage.COLLECT_COST
    event.store_after = { now = 0, max = tonumber(Mirage.st.max) or 10 }
    Collect.SyncEnqueue(event)
end

-- Хранилище запомненных уровней видеокарт
function Storage.LoadCardLevels()
    local ok, data = pcall(Storage.LoadJSON, CARD_LEVELS_FILE)
    if not ok or type(data) ~= "table" then data = {} end
    cardLevels.slots = (type(data.slots) == "table") and data.slots or {}
end

function Storage.SaveCardLevels()
    local ok, res = pcall(Storage.SaveJSON, CARD_LEVELS_FILE, { slots = cardLevels.slots })
    if ok and res then
        cardLevels.dirty = false
        cardLevels.lastSaveAt = os.clock()
        return true
    end
    return false
end

function Storage.RequestSaveCardLevels(force)
    cardLevels.dirty = true
    local now = os.clock()
    if force or (now - (cardLevels.lastSaveAt or 0)) >= 2 then
        return Storage.SaveCardLevels()
    end
    return false
end

Storage.LoadCardLevels()


function Parser.HouseData(text)
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
function Parser.HouseBankData(text)
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
function Parser.ShelfData(text)
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
            local maxProfit = math.maxEx(p1, p2)

            table.insert(results, {
                shelf_number = tonumber(shelfNum),
                samp_line = lineIndex - 2,
                status = status:gsub("^%s+", ""):gsub("%s+$", ""),
                color_code = colorCode,
                profit = maxProfit,
                profit_primary = p1,
                currency = currency1,
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

function Parser.ShelfVideoCardData(text)
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

function Parser.LiquidData(text)
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

function Chat.Add(message, type)
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
        print("["..Util.GetTimeNow().."]: "..message)
    end
end

-- --------------------------------------------------------
--                           Imgui
-- --------------------------------------------------------

function UI.SwitchMainWindow()
    imguiWindows.main[0] = not imguiWindows.main[0]
end

function UI.Scale(num)
    return ISMONETLOADER and num*MONET_DPI_SCALE or num*imgui.GetIO().FontGlobalScale
end

-- Устанавливаем масштаб UI
function UI.SetScale()
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
    return math.maxEx(10000, math.minEx(60000000, v))
end

function imgui.GetMiddleButtonX(count)
    local width = imgui.GetWindowContentRegionWidth()
    local space = imgui.GetStyle().ItemSpacing.x
    return (count == 1) and width or (width / count - ((space * (count - 1)) / count))
end

-- =====================================================================================================================
--                                                          UTLITES
-- =====================================================================================================================

-- NeoMLoader: скрипты лежат в .../neomloader
IS_NEOMLOADER = string.find(string.lower(tostring(getWorkingDirectory() or "")), "neomloader", 1, true) ~= nil

--- Запустить поток процесса. Проверку "поток занят" делает вызывающий код.
--- NeoMLoader: повторный run() уже запускавшегося потока роняет игру (SIGSEGV в LuaThread::run),
--- status() после terminate() или завершения может вернуть "suspended" - поэтому всегда новый поток.
--- MoonLoader/MonetLoader: перезапускаем прежний поток, созданный заранее в main. Новый поток,
--- созданный внутри работающего потока, падает в lua51.dll, когда тот поток завершается
--- (/mmtflash: поток флешки запускает сбор последней строкой и сразу заканчивается)
---@param thread table|nil Прежний поток lua_thread
---@param entryPoint function Функция потока
---@return table thread Запущенный поток - его нужно сохранить вместо прежнего
function RunThreadFresh(thread, entryPoint)
    if not IS_NEOMLOADER and thread
        and (thread:status() == "suspended" or thread:status() == "dead")
    then
        thread:run()
        return thread
    end
    if not IS_NEOMLOADER then
        return lua_thread.create(entryPoint)
    end
    thread = lua_thread.create_suspended(entryPoint)
    thread:run()
    return thread
end

--- Хватит ли в пакете байт на строку: offset - сколько байт уже прочитано от начала пакета
--- (с его id), len - длина строки. На NeoMLoader чтение за концом пакета роняет игру нативно,
--- pcall от этого не спасает. Если размер пакета узнать нельзя, читаем как раньше
function Util.BitStreamHasBytes(bs, offset, len)
    local _ok, _size = pcall(raknetBitStreamGetNumberOfBytesUsed, bs)
    _size = _ok and tonumber(_size) or 0
    if _size <= 0 then return true end
    return offset + len <= _size
end

-- Получить текущее время в формате %H:%M:%S
function Util.GetTimeNow()
    return os.date('%H:%M:%S')
end

function Util.OpenUrl(url)
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

-- ===== Общие помощники логов сбора (теплицы / майнер) =====

-- Ключи дней по убыванию даты
function Util.LogsSortedDayKeys(days)
    local keys = {}
    for key in pairs(days or {}) do
        table.insert(keys, key)
    end
    table.sort(keys, function(a, b) return tostring(a) > tostring(b) end)
    return keys
end

-- Отбор дней за последние N суток (0 = без ограничения)
function Util.LogsFilterDayKeys(dayKeys, periodDays)
    periodDays = tonumber(periodDays) or 0
    if periodDays <= 0 then
        return dayKeys
    end

    local fromKey = os.date('%Y-%m-%d', os.time() - (math.maxEx(1, periodDays) - 1) * 86400)
    local keys = {}
    for _, dayKey in ipairs(dayKeys or {}) do
        if tostring(dayKey) >= fromKey then
            table.insert(keys, dayKey)
        end
    end
    return keys
end

-- Сумма всех собранных предметов за день
function Util.LogsDayTotal(dayData)
    local sum = 0
    for _, value in pairs((dayData or {}).collected or {}) do
        sum = sum + (tonumber(value) or 0)
    end
    return sum
end

-- Набор колонок (имён предметов) по выбранным дням + суммы по каждому предмету
function Util.LogsBuildColumns(days, dayKeys)
    local totals, names = {}, {}
    for _, dayKey in ipairs(dayKeys or {}) do
        local dayData = (days or {})[dayKey] or {}
        for name, value in pairs(dayData.collected or {}) do
            value = tonumber(value) or 0
            if value > 0 then
                if totals[name] == nil then
                    totals[name] = 0
                    table.insert(names, name)
                end
                totals[name] = totals[name] + value
            end
        end
    end
    table.sort(names, function(a, b)
        if totals[a] ~= totals[b] then return totals[a] > totals[b] end
        return tostring(a) < tostring(b)
    end)
    return names, totals
end

function Util.GetCommaValue(n)
	local left,num,right = string.match(n,'^([^%d]*%d)(%d*)(.-)$')
	return left..(num:reverse():gsub('(%d%d%d)','%1,'):reverse())..right
end

-- Округление до n знаков (по умолчанию 2)
function Util.Round(x, n)
    n = n or 2
    local m = 10^n
    return math.floor((x or 0) * m + 0.5) / m
end

function UI.ImGuiKeyPressed(keyConst)
    local ok, pressed = pcall(function() return imgui.IsKeyPressed(keyConst, false) end)
    return ok and pressed
end

function UI.IsEnterPressed()
    -- пробуем ImGui Enter
    if UI.ImGuiKeyPressed(imgui.Key.Enter) then return true end
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
function UI.HandleListNavigation(current, max, onEnter)
    if max <= 0 or not settings.main.arrowsMove or not IsArrowNavigationAvailable() then return current end

    if imgui.IsWindowFocused(imgui.FocusedFlags.RootAndChildWindows)
       and not imgui.IsAnyItemActive() then

        local newIndex = current

        -- Вверх: ImGui или фолбэк через VK_UP
        if UI.ImGuiKeyPressed(imgui.Key.UpArrow) or (isKeyJustPressed and isKeyJustPressed(VK_UP)) then
            newIndex = (current > 1) and (current - 1) or max
        end

        -- Вниз: ImGui или фолбэк через VK_DOWN
        if UI.ImGuiKeyPressed(imgui.Key.DownArrow) or (isKeyJustPressed and isKeyJustPressed(VK_DOWN)) then
            newIndex = (current < max) and (current + 1) or 1
        end

        current = newIndex

        -- Enter (без KeypadEnter)
        if UI.IsEnterPressed() and onEnter then
            onEnter(current)
        end
    end

    return current
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
            Storage.SaveSettings()
        end

        if imgui.Button(u8("Раздел: " .. (MODE_LABELS[activeMode] or "?"))) then
            local idx = 1
            for i, m in ipairs(MODE_ORDER) do if m == activeMode then idx = i end end
            activeMode = MODE_ORDER[(idx % #MODE_ORDER) + 1]
            if activeMode ~= "cards" and activeTabScript == "improve" then
                activeTabScript = "main"
            end
        end
        imgui.SameLine()

        if imgui.Button("Boosty") then
            Util.OpenUrl("https://boosty.to/sand-mcr")
        end

        imgui.SameLine()

        imgui.CenterText("[MMT] Mining Tool v"..thisScript().version.." | TG: @Mister_Sand")

        imgui.SameLine()

        local _icon = lastIDDialog == idDialogs.selectVideoCardItemFlash and fa.REPLY or fa.CIRCLE_XMARK
        if imgui.RightButton("\t".._icon.."\t") then
            UI.SwitchMainWindow()
            Interacting.Deactivate()
            Farmer.Cancel()
            Miner.Cancel()
            sampSendDialogResponse(lastIDDialog, 0, 0, "")
            shelves = {}
            houses = {}
            housesBanks = {}
        end

        imgui.Separator()

        local _tabCount = (activeMode == "cards") and 4 or 3
        local _widthButtons = (imgui.GetWindowWidth() - UI.Scale(36)) / _tabCount
        if imgui.ButtonClickable(activeTabScript ~= "main", u8"Основное", imgui.ImVec2(_widthButtons, 0)) then
            activeTabScript = "main"
        end
        imgui.SameLine()
        if imgui.ButtonClickable(activeTabScript ~= "logs", u8"Логи", imgui.ImVec2(_widthButtons, 0)) then
            activeTabScript = "logs"
            if activeMode == "cards" then Storage.LoadCollectLogStore() end
        end
        imgui.SameLine()
        if activeMode == "cards" then
            if imgui.ButtonClickable(activeTabScript ~= "improve", u8"Улучшить", imgui.ImVec2(_widthButtons, 0)) then
                activeTabScript = "improve"
            end
            imgui.SameLine()
        end
        if imgui.ButtonClickable(activeTabScript ~= "settings", u8"Настройки", imgui.ImVec2(-1, 0)) then
            activeTabScript = "settings"
        end

        imgui.Separator()

        if activeTabScript == "main" then
            if activeMode == "farmer" then
                imgui.BeginChild("farmer_main_area", imgui.ImVec2(-1, -1))
                imgui.ScrollMouse()
                Draw.FarmerMain()
                imgui.EndChild()
            elseif activeMode == "miner" then
                imgui.BeginChild("miner_main_area", imgui.ImVec2(-1, -1))
                imgui.ScrollMouse()
                Draw.MinerMain()
                imgui.EndChild()
            elseif activeMode == "mirage" then
                imgui.BeginChild("mirage_main_area", imgui.ImVec2(-1, -1))
                imgui.ScrollMouse()
                Draw.MirageMain()
                imgui.EndChild()
            else
                Draw.MainMenu()
            end
        elseif activeTabScript == "logs" then
            if Draw.LogsSourceSwitch() then
                local cloudKinds = { farmer = "greenhouse", miner = "miner", mirage = "mirage" }
                Draw.CloudLogs(cloudKinds[activeMode] or "crypto")
            elseif activeMode == "farmer" then
                Draw.FarmerLogs()
            elseif activeMode == "miner" then
                Draw.MinerLogs()
            elseif activeMode == "mirage" then
                Draw.MirageLogs()
            else
                Draw.CollectLogs()
            end
        elseif activeTabScript == "improve" then
            if activeMode == "cards" then Draw.ImproveSharp() end
        elseif activeTabScript == "settings" then
            Draw.Settings()
        end
    imgui.End()
end)


-- =====================================================================================================================
--                                                          DRAWS
-- =====================================================================================================================

-- =====================================================================================================================
--                                                          FARMER UI
-- =====================================================================================================================

-- =====================================================================================================================
--                                            Общие блоки UI (фермер / майнер)
-- =====================================================================================================================

-- Цвет заполнения по настройкам: свободно / наполовину / почти полная
function Draw.FillColor(now, max)
    local pct = ((tonumber(max) or 0) > 0) and (now / max * 100) or 0
    if pct >= 90 then return UI.Vec4('barFullColor') end
    if pct >= 50 then return UI.Vec4('barHalfColor') end
    return UI.Vec4('barFreeColor')
end

-- Палитра столбиков графика в логах
function Draw.GraphColors()
    return imgui.GetColorU32Vec4(UI.Vec4('graphBgColor')),
           imgui.GetColorU32Vec4(UI.Vec4('graphBarColor')),
           imgui.GetColorU32Vec4(UI.Vec4('graphActiveColor')),
           imgui.GetColorU32Vec4(UI.Vec4('textColor'))
end

-- Подпись слева, полоса заполнения "N / M" справа - в одну строку
function Draw.FillBar(label, labelWidth, now, max, color)
    now, max = tonumber(now) or 0, tonumber(max) or 0
    local frac = (max > 0) and math.minEx(1.0, now / max) or 0
    local startX = imgui.GetCursorPosX()
    imgui.Text(u8(tostring(label)))
    imgui.SameLine()
    imgui.SetCursorPosX(startX + labelWidth)
    imgui.PushStyleColor(imgui.Col.PlotHistogram, color or Draw.FillColor(now, max))
    imgui.ProgressBar(frac, imgui.ImVec2(-1, imgui.GetTextLineHeight()), u8(string.format("%d / %d", now, max)))
    imgui.PopStyleColor()
end

-- Строка склада: название слева, количество справа (чётные строки подсвечены)
function Draw.WareRow(index, name, count, hexColor)
    local value = Util.GetCommaValue(math.floor(tonumber(count) or 0))
    local startX = imgui.GetCursorPosX()
    local width = imgui.GetWindowContentRegionWidth()
    local pos = imgui.GetCursorScreenPos()

    if (index % 2) == 0 then
        local h = imgui.GetTextLineHeightWithSpacing()
        imgui.GetWindowDrawList():AddRectFilled(
            imgui.ImVec2(pos.x - UI.Scale(3), pos.y - UI.Scale(1)),
            imgui.ImVec2(pos.x + width + UI.Scale(3), pos.y + h - UI.Scale(2)),
            imgui.GetColorU32Vec4(imgui.ImVec4(1.0, 1.0, 1.0, 0.04)))
    end

    local col = hexColor and HexToVec4(hexColor) or nil
    local gap = UI.Scale(6)
    local valueW = imgui.CalcTextSize(value).x
    local avail = math.maxEx(UI.Scale(20), width - valueW - gap * 2)

    -- Длинные названия (например, "Вода для полива грядок") режем, чтобы не сталкиваться с числом
    local label = tostring(name)
    local labelU = u8(label)
    local labelW = imgui.CalcTextSize(labelU).x
    local truncated = labelW > avail
    if truncated then
        while #label > 1 and imgui.CalcTextSize(u8(label .. "...")).x > avail do
            label = label:sub(1, #label - 1)
        end
        labelU = u8(label .. "...")
        labelW = imgui.CalcTextSize(labelU).x
    end

    if col then imgui.TextColored(col, labelU) else imgui.Text(labelU) end
    if truncated and imgui.IsItemHovered() then imgui.SetTooltip(u8(tostring(name))) end

    -- Соединяем название и количество тонкой линией, чтобы глаз не терял строку
    local leaderFrom = pos.x + labelW + gap
    local leaderTo = pos.x + width - valueW - gap
    if leaderTo - leaderFrom > UI.Scale(8) then
        local y = pos.y + imgui.GetTextLineHeight() * 0.65
        imgui.GetWindowDrawList():AddLine(
            imgui.ImVec2(leaderFrom, y), imgui.ImVec2(leaderTo, y),
            imgui.GetColorU32Vec4(imgui.ImVec4(1.0, 1.0, 1.0, 0.14)), UI.Scale(1))
    end

    imgui.SameLine()
    imgui.SetCursorPosX(startX + width - valueW)
    if col then imgui.TextColored(col, value) else imgui.Text(value) end
end

-- Заголовок блока склада с отметкой, когда данные были получены
function Draw.WareTitle(wareAt)
    wareAt = tonumber(wareAt) or 0
    if wareAt <= 0 then
        return "Содержимое склада"
    end
    return string.format("Содержимое склада (на %s)", os.date('%H:%M:%S', wareAt))
end

-- Заголовок списка по центру + разделитель
-- Строка настройки цвета: свотч + название, изменение применяется сразу
function Draw.ColorEditRow(label, key, withAlpha)
    local color = settings.style[key]
    if type(color) ~= 'table' then return end

    local buf = new.float[4]({ color.r or 0, color.g or 0, color.b or 0, color.a or 1.0 })
    local changed
    if withAlpha then
        changed = imgui.ColorEdit4(u8(label) .. "##style_" .. key, buf,
            imgui.ColorEditFlags.AlphaBar + imgui.ColorEditFlags.AlphaPreview)
    else
        changed = imgui.ColorEdit3(u8(label) .. "##style_" .. key, buf)
    end

    if changed then
        color.r, color.g, color.b = buf[0], buf[1], buf[2]
        if withAlpha then color.a = buf[3] end
        UI.ApplyColors()
        ui_state.colorsDirty = true
    end
end

function Draw.SectionTitle(text)
    local label = u8(tostring(text))
    local startX = imgui.GetCursorPosX()
    imgui.SetCursorPosX(startX + math.maxEx(0, (imgui.GetWindowContentRegionWidth() - imgui.CalcTextSize(label).x) / 2))
    imgui.Text(label)
    imgui.Separator()
end

-- Список "имя -> количество" с устойчивым порядком (по убыванию количества)
function Draw.AmountList(map, emptyText, hexColor)
    local names = {}
    for name, value in pairs(map or {}) do
        if (tonumber(value) or 0) > 0 then table.insert(names, name) end
    end
    if #names == 0 then
        imgui.TextDisabled(u8(emptyText))
        return
    end
    table.sort(names, function(a, b)
        local va, vb = tonumber(map[a]) or 0, tonumber(map[b]) or 0
        if va ~= vb then return va > vb end
        return tostring(a) < tostring(b)
    end)
    for i, name in ipairs(names) do
        Draw.WareRow(i, name, map[name], hexColor)
    end
end

-- Журнал действий под сворачиваемым заголовком
function Draw.Journal(id, logs)
    logs = logs or {}
    if #logs == 0 then return end
    imgui.Spacing()
    if imgui.CollapsingHeader(u8(string.format("Журнал действий (%d)", #logs)) .. "##" .. id .. "_journal") then
        -- занимаем всю оставшуюся высоту, но не меньше 100 px
        local height = math.maxEx(UI.Scale(100), imgui.GetContentRegionAvail().y)
        imgui.BeginChild(id .. "_journal_body", imgui.ImVec2(-1, height), true)
        imgui.ScrollMouse()
        for _, entry in ipairs(logs) do
            if type(entry) == "table" then
                imgui.TextDisabled(u8(tostring(entry.time or "")))
                imgui.SameLine()
                imgui.Text(u8(tostring(entry.text or "")))
            else
                imgui.Text(u8(tostring(entry)))
            end
        end
        imgui.EndChild()
    end
end

function Draw.FarmerMain()
    local st = (farmer.menu.status ~= nil and farmer.menu.status ~= "") and farmer.menu.status or "-"
    -- Статус-кнопка: зелёная если фермер собирает, жёлтая если нет
    local collecting = tostring(st):find("Собирает") ~= nil

    -- меню на сервере скрипт закрывает за собой, поэтому по клику открываем его заново через Alt
    local canToggle = not farmer.active and (farmer.menu and farmer.menu.statusLine) ~= nil
    if collecting then
        if imgui.ButtonClickable(canToggle, u8("Статус: " .. tostring(st))) then
            Farmer.Start("status")
        end
    else
        local stCol = HexToVec4(COLORS.YELLOW)

        imgui.PushStyleColor(imgui.Col.Button,        stCol)
        imgui.PushStyleColor(imgui.Col.ButtonHovered, Shade(stCol, 0.9))
        imgui.PushStyleColor(imgui.Col.ButtonActive,  Shade(stCol, 0.80))
        imgui.PushStyleColor(imgui.Col.Text,          imgui.ImVec4(0.10, 0.10, 0.10, 1.0))

        if imgui.ButtonClickable(canToggle, u8("Статус: " .. tostring(st))) then
            Farmer.Start("status")
        end

        imgui.PopStyleColor(4)
    end
    
    imgui.SameLine()
    imgui.Text(u8(string.format("Воды с собой: %d", farmer.invLiquid or 0)))

    -- Заполненность склада фермы и запаса воды
    local labelW = math.maxEx(imgui.CalcTextSize(u8"Склад фермы").x, imgui.CalcTextSize(u8"Вода у фермера").x) + UI.Scale(10)
    local storeNow, storeMax = farmer.menu.storeNow or 0, farmer.menu.storeMax or 0
    Draw.FillBar("Склад фермы", labelW, storeNow, storeMax)

    -- Запас воды известен после открытия окна пополнения; пустой бак = красный
    local waterMax = tonumber(farmer.wareWaterMax) or 0
    if waterMax > 0 then
        local waterNow = farmer.wareWaterNow or 0
        Draw.FillBar("Вода у фермера", labelW, waterNow, waterMax, Draw.FillColor(waterMax - waterNow, waterMax))
    end
    imgui.Separator()

    local spacing = imgui.GetStyle().ItemSpacing.x
    local third = (imgui.GetWindowContentRegionWidth() - spacing * 2) / 3

    if imgui.ButtonClickable(not farmer.active, fa.HAND_HOLDING_DOLLAR .. u8"\tЗабрать", imgui.ImVec2(third, 0)) then
        Farmer.Start("take")
    end
    imgui.SameLine()
    if imgui.ButtonClickable(not farmer.active, fa.FILL_DRIP .. u8"\tЗаполнить", imgui.ImVec2(third, 0)) then
        Farmer.Start("fill")
    end
    imgui.SameLine()
    if imgui.AccentButtonClickable(not farmer.active, fa.PLAY .. u8"\tСделать всё", imgui.ImVec2(-1, 0)) then
        Farmer.Start("both")
    end

    local halfW = (imgui.GetWindowContentRegionWidth() - spacing) / 2
    local takeIcon = settings.farmer.autoTake and fa.TOGGLE_ON or fa.TOGGLE_OFF
    if imgui.Button(takeIcon .. "\t" .. (settings.farmer.autoTake and u8"Автосбор: вкл" or u8"Автосбор: выкл"), imgui.ImVec2(halfW, 0)) then
        settings.farmer.autoTake = not settings.farmer.autoTake
        Storage.SaveSettings()
    end
    imgui.SameLine()
    local fillIcon = settings.farmer.autoFill and fa.TOGGLE_ON or fa.TOGGLE_OFF
    if imgui.Button(fillIcon .. "\t" .. (settings.farmer.autoFill and u8"Автопополнение: вкл" or u8"Автопополнение: выкл"), imgui.ImVec2(-1, 0)) then
        settings.farmer.autoFill = not settings.farmer.autoFill
        Storage.SaveSettings()
    end

    local checkIcon = settings.farmer.refreshOnOpen and fa.TOGGLE_ON or fa.TOGGLE_OFF
    if imgui.Button(checkIcon .. "\t" .. (settings.farmer.refreshOnOpen and u8"Проверка склада при открытии меню: вкл" or u8"Проверка склада при открытии меню: выкл") .. "##farmer_refresh_on_open", imgui.ImVec2(halfW, 0)) then
        settings.farmer.refreshOnOpen = not settings.farmer.refreshOnOpen
        Storage.SaveSettings()
    end
    imgui.SameLine()
    if imgui.ButtonClickable(not farmer.active, fa.WAREHOUSE .. u8"	Проверить склад фермы", imgui.ImVec2(-1, 0)) then
        Farmer.Start("check")
    end

    imgui.Separator()

    if farmer.active then
        imgui.TextColoredRGB(string.format("{%s}Идёт процесс: {%s}%s", COLORS.YELLOW, COLORS.WHITE, tostring(farmer.statusText or "")))
        if imgui.Button(fa.CIRCLE_XMARK .. u8"\tОтменить", imgui.ImVec2(-1, 0)) then
            Farmer.Cancel()
        end
    elseif farmer.statusText ~= "" then
        imgui.TextDisabled(u8(tostring(farmer.statusText)))
    end

    Draw.SectionTitle("Собрано за сессию")
    Draw.AmountList(farmer.collected, "Пока ничего не собрано")
    if (farmer.waterSpent or 0) > 0 then
        imgui.TextColoredRGB(string.format("{%s}Воды залито: %d", COLORS.YELLOW, farmer.waterSpent))
    end

    imgui.Spacing()
    Draw.SectionTitle(Draw.WareTitle(farmer.wareAt))
    local ware = farmer.ware or {}
    local wareItems = ware.items or {}
    if #wareItems > 0 or (ware.waterNow or 0) > 0 then
        local row = 0
        for _, it in ipairs(wareItems) do
            row = row + 1
            Draw.WareRow(row, it.name, it.count)
        end
        if (ware.waterNow or 0) > 0 then
            row = row + 1
            Draw.WareRow(row, ware.waterName or "Вода для личных грядок", ware.waterNow, COLORS.YELLOW)
        end
    else
        imgui.TextDisabled(u8"Пока неизвестно - нажмите \"Проверить склад фермы\"")
    end

    Draw.Journal("farmer", farmer.logs)
end

-- ---------------------------------------------------------------------------
-- Обобщённый экран логов сбора. Используется разделами "Фермер" и "Майнер".
-- cfg = {
--   id         - префикс для imgui-идентификаторов,
--   days       - таблица дней { [YYYY-MM-DD] = { collected = {}, <extraKey> = n } },
--   state      - таблица ui_state с полем selectedDay,
--   opts       - таблица настроек с полями logsPeriod / logsView,
--   extraKey   - имя поля с расходником (water / charge),
--   extraLabel - заголовок колонки расходника,
--   emptyText  - текст при отсутствии логов,
--   refresh    - функция перезагрузки логов, возвращает свежую таблицу дней,
-- }
-- ---------------------------------------------------------------------------

-- Таблица: строки - дни, колонки - предметы (+ расходник и общий итог)
function Draw.ResourceLogsTable(cfg, dayKeys, names, totals)
    imgui.BeginChild(cfg.id .. "_logs_table", imgui.ImVec2(-1, -1), true, imgui.WindowFlags.HorizontalScrollbar)
    imgui.ScrollMouse()

    if #dayKeys == 0 then
        imgui.TextDisabled(u8(cfg.emptyText))
        imgui.EndChild()
        return
    end

    -- Шапка: Дата | <предметы...> | <расходник> | Всего
    local headers = { u8"Дата" }
    for _, name in ipairs(names) do
        table.insert(headers, u8(tostring(name)))
    end
    table.insert(headers, u8(cfg.extraLabel))
    table.insert(headers, u8"Всего")

    -- Строки по дням
    local rows, sumExtra, sumAll = {}, 0, 0
    for _, dayKey in ipairs(dayKeys) do
        local dayData = cfg.days[dayKey] or {}
        local collected = dayData.collected or {}
        local cells, dayTotal = { tostring(dayKey) }, 0
        for _, name in ipairs(names) do
            local value = tonumber(collected[name]) or 0
            dayTotal = dayTotal + value
            table.insert(cells, (value > 0) and Util.GetCommaValue(value) or "-")
        end
        local extra = tonumber(dayData[cfg.extraKey]) or 0
        sumExtra = sumExtra + extra
        sumAll = sumAll + dayTotal
        table.insert(cells, (extra > 0) and Util.GetCommaValue(extra) or "-")
        table.insert(cells, Util.GetCommaValue(dayTotal))
        table.insert(rows, cells)
    end

    -- Итоговая строка
    local footer = { u8"Итого" }
    for _, name in ipairs(names) do
        table.insert(footer, Util.GetCommaValue(tonumber(totals[name]) or 0))
    end
    table.insert(footer, Util.GetCommaValue(sumExtra))
    table.insert(footer, Util.GetCommaValue(sumAll))

    -- Ширина колонок по самому широкому содержимому
    local pad = UI.Scale(18)
    local widths = {}
    for i, text in ipairs(headers) do
        widths[i] = imgui.CalcTextSize(text).x + pad
    end
    local function fitRow(cells)
        for i, text in ipairs(cells) do
            local w = imgui.CalcTextSize(text).x + pad
            if w > (widths[i] or 0) then widths[i] = w end
        end
    end
    for _, cells in ipairs(rows) do fitRow(cells) end
    fitRow(footer)

    local baseX = imgui.GetCursorPosX()

    -- Если содержимое уже доступной ширины - растягиваем колонки на всё окно
    local avail = imgui.GetWindowContentRegionWidth() - UI.Scale(4)
    local contentW = 0
    for _, w in ipairs(widths) do contentW = contentW + w end
    if contentW > 0 and avail > contentW then
        local scale = avail / contentW
        for i, w in ipairs(widths) do widths[i] = w * scale end
    end

    local offsets, totalW = {}, 0
    for i, w in ipairs(widths) do
        offsets[i] = baseX + totalW
        totalW = totalW + w
    end

    local drawList = imgui.GetWindowDrawList()
    local rowH = imgui.GetTextLineHeightWithSpacing()
    local colStripe = imgui.GetColorU32Vec4(imgui.ImVec4(1.00, 1.00, 1.00, 0.04))
    local colHeader = HexToVec4(COLORS.GREEN)
    local colTotal = HexToVec4(COLORS.YELLOW)

    local function drawRow(cells, color, stripe)
        if stripe then
            local pos = imgui.GetCursorScreenPos()
            drawList:AddRectFilled(imgui.ImVec2(pos.x - UI.Scale(3), pos.y - UI.Scale(1)), imgui.ImVec2(pos.x + totalW, pos.y + rowH - UI.Scale(2)), colStripe)
        end
        for i, text in ipairs(cells) do
            if i > 1 then imgui.SameLine() end
            imgui.SetCursorPosX(offsets[i])
            if color then
                imgui.TextColored(color, text)
            else
                imgui.Text(text)
            end
        end
    end

    drawRow(headers, colHeader, false)
    imgui.Separator()
    for i, cells in ipairs(rows) do
        drawRow(cells, nil, (i % 2) == 0)
    end
    imgui.Separator()
    drawRow(footer, colTotal, false)

    imgui.EndChild()
end

-- График: столбцы по дням + разбивка выбранного дня по предметам
function Draw.ResourceLogsGraph(cfg, dayKeys, names)
    if #dayKeys == 0 then
        imgui.BeginChild(cfg.id .. "_logs_graph_empty", imgui.ImVec2(-1, -1), true)
        imgui.TextDisabled(u8(cfg.emptyText))
        imgui.EndChild()
        return
    end

    cfg.state.selectedDay = cfg.state.selectedDay or dayKeys[1]
    local selectedInFilter = false
    for _, dayKey in ipairs(dayKeys) do
        if dayKey == cfg.state.selectedDay then
            selectedInFilter = true
            break
        end
    end
    if not selectedInFilter or not cfg.days[cfg.state.selectedDay] then
        cfg.state.selectedDay = dayKeys[1]
    end

    imgui.BeginChild(cfg.id .. "_logs_graph", imgui.ImVec2(-1, -1), true)
    imgui.ScrollMouse()
    imgui.Text(u8"Собрано за день")
    imgui.SameLine()
    imgui.TextDisabled(u8"Кликните по столбцу, чтобы увидеть предметы.")
    imgui.Spacing()

    local graphW = math.maxEx(UI.Scale(160), imgui.GetWindowContentRegionWidth())
    local maxVisible = math.maxEx(1, math.floor(graphW / UI.Scale(46)))
    local graphKeys = {}
    for i = math.minEx(#dayKeys, maxVisible), 1, -1 do
        table.insert(graphKeys, dayKeys[i])
    end

    local maxTotal = 1
    for _, dayKey in ipairs(graphKeys) do
        maxTotal = math.maxEx(maxTotal, Util.LogsDayTotal(cfg.days[dayKey]))
    end

    local gap = UI.Scale(5)
    local barW = math.maxEx(UI.Scale(28), (graphW - gap * (#graphKeys - 1)) / math.maxEx(1, #graphKeys))
    local graphH = UI.Scale(150)
    local drawList = imgui.GetWindowDrawList()
    local colBg, colBar, colBarActive, colText = Draw.GraphColors()

    for i, dayKey in ipairs(graphKeys) do
        if i > 1 then imgui.SameLine(nil, gap) end
        local dayData = cfg.days[dayKey] or {}
        local totalValue = Util.LogsDayTotal(dayData)
        local pos = imgui.GetCursorScreenPos()
        if imgui.InvisibleButton("##" .. cfg.id .. "_graph_bar_" .. tostring(dayKey), imgui.ImVec2(barW, graphH)) then
            cfg.state.selectedDay = dayKey
        end
        local filledH = math.maxEx(UI.Scale(3), (graphH - UI.Scale(28)) * (totalValue / maxTotal))
        local x1, y1 = pos.x, pos.y
        local x2, y2 = pos.x + barW, pos.y + graphH
        drawList:AddRectFilled(imgui.ImVec2(x1, y1), imgui.ImVec2(x2, y2), colBg, UI.Scale(4), 15)
        local barColor = (cfg.state.selectedDay == dayKey) and colBarActive or colBar
        drawList:AddRectFilled(imgui.ImVec2(x1 + UI.Scale(4), y2 - filledH - UI.Scale(20)), imgui.ImVec2(x2 - UI.Scale(4), y2 - UI.Scale(20)), barColor, UI.Scale(3), 15)
        drawList:AddText(imgui.ImVec2(x1 + UI.Scale(4), y2 - UI.Scale(17)), colText, tostring(dayKey):sub(6))
        if imgui.IsItemHovered() then
            local tip = string.format("%s\nВсего собрано: %s\n%s: %s", tostring(dayKey), Util.GetCommaValue(totalValue), cfg.extraLabel, Util.GetCommaValue(tonumber(dayData[cfg.extraKey]) or 0))
            for _, name in ipairs(names) do
                local value = tonumber((dayData.collected or {})[name]) or 0
                if value > 0 then
                    tip = tip .. string.format("\n%s: %s", tostring(name), Util.GetCommaValue(value))
                end
            end
            imgui.SetTooltip(u8(tip))
        end
    end

    imgui.Spacing()
    imgui.Separator()

    local selectedDay = cfg.state.selectedDay
    local dayData = cfg.days[selectedDay] or {}
    local dayTotal = Util.LogsDayTotal(dayData)
    imgui.TextColoredRGB(string.format("{%s}Выбран день: {%s}%s", COLORS.GREEN, COLORS.WHITE, tostring(selectedDay)))
    imgui.Text(u8(string.format("Всего собрано: %s | %s: %s", Util.GetCommaValue(dayTotal), cfg.extraLabel, Util.GetCommaValue(tonumber(dayData[cfg.extraKey]) or 0))))
    imgui.Separator()

    local shown = false
    for _, name in ipairs(names) do
        local value = tonumber((dayData.collected or {})[name]) or 0
        if value > 0 then
            shown = true
            local percent = (dayTotal > 0) and (value / dayTotal * 100) or 0
            imgui.BulletText(u8(string.format("%s: %s (%.1f%%)", tostring(name), Util.GetCommaValue(value), percent)))
        end
    end
    if not shown then
        imgui.TextDisabled(u8"Нет собранных ресурсов за этот день.")
    end

    imgui.EndChild()
end

-- Шапка экрана логов: обновление, период, переключатель вида
function Draw.ResourceLogs(cfg)
    local allDayKeys = Util.LogsSortedDayKeys(cfg.days)
    local periodDays = tonumber(cfg.opts.logsPeriod or 7) or 7
    local dayKeys = Util.LogsFilterDayKeys(allDayKeys, periodDays)

    if imgui.Button(u8"Обновить" .. "##" .. cfg.id .. "_logs_refresh") then
        cfg.days = cfg.refresh() or cfg.days
        allDayKeys = Util.LogsSortedDayKeys(cfg.days)
        dayKeys = Util.LogsFilterDayKeys(allDayKeys, periodDays)
    end
    imgui.SameLine()
    imgui.Text(u8(string.format("Дней с логами: %d/%d", #dayKeys, #allDayKeys)))

    local periodOptions = {
        { days = 3, label = "3 дня" },
        { days = 7, label = "7 дней" },
        { days = 14, label = "14 дней" },
        { days = 30, label = "30 дней" },
        { days = 0, label = "Всё время" },
    }
    local periodW = (imgui.GetWindowContentRegionWidth() - imgui.GetStyle().ItemSpacing.x * (#periodOptions - 1)) / #periodOptions
    for i, option in ipairs(periodOptions) do
        if i > 1 then imgui.SameLine() end
        local label = u8(option.label) .. "##" .. cfg.id .. "_period_" .. tostring(option.days)
        if imgui.ButtonClickable(periodDays ~= option.days, label, imgui.ImVec2(i == #periodOptions and -1 or periodW, 0)) then
            cfg.opts.logsPeriod = option.days
            Storage.SaveSettings()
            periodDays = option.days
            dayKeys = Util.LogsFilterDayKeys(allDayKeys, periodDays)
        end
    end

    imgui.Separator()

    local w = (imgui.GetWindowContentRegionWidth() - imgui.GetStyle().ItemSpacing.x) / 2
    if imgui.ButtonClickable(cfg.opts.logsView ~= "table", u8"Таблица" .. "##" .. cfg.id .. "_view_table", imgui.ImVec2(w, 0)) then
        cfg.opts.logsView = "table"
        Storage.SaveSettings()
    end
    imgui.SameLine()
    if imgui.ButtonClickable(cfg.opts.logsView ~= "graph", u8"График" .. "##" .. cfg.id .. "_view_graph", imgui.ImVec2(-1, 0)) then
        cfg.opts.logsView = "graph"
        Storage.SaveSettings()
    end

    local names, totals = Util.LogsBuildColumns(cfg.days, dayKeys)
    if cfg.opts.logsView == "graph" then
        Draw.ResourceLogsGraph(cfg, dayKeys, names)
    else
        Draw.ResourceLogsTable(cfg, dayKeys, names, totals)
    end
end

function Draw.FarmerLogs()
    Draw.ResourceLogs({
        id = "gh",
        days = greenhouseLog.days or {},
        state = ui_state.farmerLogs,
        opts = settings.farmer,
        extraKey = "water",
        extraLabel = "Вода",
        emptyText = "Логи теплиц пока пустые.",
        refresh = function()
            Storage.SaveGreenhouseLog()
            Storage.LoadGreenhouseLog()
            return greenhouseLog.days or {}
        end,
    })
end

function Draw.MinerLogs()
    Draw.ResourceLogs({
        id = "miner",
        days = minerLog.days or {},
        state = ui_state.minerLogs,
        opts = settings.miner,
        extraKey = "charge",
        extraLabel = "Зарядка",
        emptyText = "Логи майнера пока пустые.",
        refresh = function()
            Storage.SaveMinerLog()
            Storage.LoadMinerLog()
            return minerLog.days or {}
        end,
    })
end

function Draw.FarmerSettings()
    imgui.Spacing()
    imgui.TextDisabled(u8"Замена диалога окном скрипта общая для всего скрипта - вкладка \"Основное\".")
    imgui.Spacing()
    if imgui.Checkbox(u8"Обновлять склад при открытии меню фермера", new.bool(settings.farmer.refreshOnOpen)) then
        settings.farmer.refreshOnOpen = not settings.farmer.refreshOnOpen
        Storage.SaveSettings()
    end
    imgui.TextDisabled(u8"Скрипт заглянет на склад и покажет актуальные остатки.\nЕсли включён автосбор или автопополнение, склад обновляется и без этого.")
    imgui.Spacing()
    if imgui.Checkbox(u8"Автосбор ресурсов при открытии меню фермера", new.bool(settings.farmer.autoTake)) then
        settings.farmer.autoTake = not settings.farmer.autoTake
        Storage.SaveSettings()
    end
    if imgui.Checkbox(u8"Автопополнение воды при открытии меню фермера", new.bool(settings.farmer.autoFill)) then
        settings.farmer.autoFill = not settings.farmer.autoFill
        Storage.SaveSettings()
    end

    imgui.Spacing()
    imgui.Text(u8"Заливать воду фермеру не выше:")
    imgui.PushItemWidth(-1)
    local _fillTarget = new.int(tonumber(settings.farmer.fillTarget) or Farmer.WATER_MAX)
    if imgui.SliderInt("##farmFillTarget", _fillTarget, 0, Farmer.WATER_MAX, u8"%d") then
        settings.farmer.fillTarget = math.maxEx(0, math.minEx(Farmer.WATER_MAX, _fillTarget[0]))
        Storage.SaveSettings()
    end
    imgui.PopItemWidth()
    imgui.TextDisabled(u8(string.format("Остальная вода остаётся с собой. По умолчанию %d - заполняется полностью.", Farmer.WATER_MAX)))

    imgui.Spacing()
    imgui.Separator()
    imgui.Spacing()

    imgui.Text(u8"Пауза перед ответом на диалог:")
    imgui.PushItemWidth(-1)
    local _delay = new.int(tonumber(settings.farmer.actionDelay) or 150)
    if imgui.SliderInt("##farmDelay", _delay, 0, 1000, u8"%d мс") then
        settings.farmer.actionDelay = math.maxEx(0, _delay[0])
        Storage.SaveSettings()
    end
    imgui.PopItemWidth()

    imgui.Text(u8"Таймаут ожидания диалога:")
    imgui.PushItemWidth(-1)
    local _timeout = new.int(tonumber(settings.farmer.timeout) or 10)
    if imgui.SliderInt("##farmTimeout", _timeout, 3, 30, u8"%d сек") then
        settings.farmer.timeout = math.maxEx(1, _timeout[0])
        Storage.SaveSettings()
    end
    imgui.PopItemWidth()

    imgui.Text(u8"Пауза после забора перед Alt:")
    imgui.PushItemWidth(-1)
    local _atd = new.int(tonumber(settings.farmer.afterTakeDelay) or 400)
    if imgui.SliderInt("##farmAfterTake", _atd, 0, 3000, u8"%d мс") then
        settings.farmer.afterTakeDelay = math.maxEx(0, _atd[0])
        Storage.SaveSettings()
    end
    imgui.PopItemWidth()

    imgui.Text(u8"Удержание клавиши Alt:")
    imgui.PushItemWidth(-1)
    local _alt = new.int(tonumber(settings.farmer.altHoldTime) or 100)
    if imgui.SliderInt("##farmAltHold", _alt, 20, 500, u8"%d мс") then
        settings.farmer.altHoldTime = math.maxEx(1, _alt[0])
        Storage.SaveSettings()
    end
    imgui.PopItemWidth()

    imgui.Text(u8"Хранить логи теплиц (дней, 0 = без ограничения):")
    imgui.PushItemWidth(UI.Scale(120))
    local _keep = new.int(tonumber(settings.farmer.logMaxDays) or 60)
    if imgui.InputInt("##farmKeep", _keep, 0, 0) then
        settings.farmer.logMaxDays = math.maxEx(0, _keep[0])
        Storage.SaveSettings()
    end
    imgui.PopItemWidth()
end

-- (окно теплиц перенесено в основное окно - см. переключатель раздела)

-- =====================================================================================================================
--                                                          MINER UI
-- =====================================================================================================================

function Draw.MinerMain()
    local st = (miner.menu.status ~= nil and miner.menu.status ~= "") and miner.menu.status or "-"
    -- Статус-кнопка: зелёная если майнер собирает, жёлтая если нет
    local collecting = tostring(st):find("обирает") ~= nil

    -- меню на сервере скрипт закрывает за собой, поэтому по клику открываем его заново через Alt
    local canToggle = not miner.active and (miner.menu and miner.menu.statusLine) ~= nil
    if collecting then
        if imgui.ButtonClickable(canToggle, u8("Статус: " .. tostring(st))) then
            Miner.Start("status")
        end
    else
        local stCol = HexToVec4(COLORS.YELLOW)

        imgui.PushStyleColor(imgui.Col.Button,        stCol)
        imgui.PushStyleColor(imgui.Col.ButtonHovered, Shade(stCol, 0.9))
        imgui.PushStyleColor(imgui.Col.ButtonActive,  Shade(stCol, 0.80))
        imgui.PushStyleColor(imgui.Col.Text,          imgui.ImVec4(0.10, 0.10, 0.10, 1.0))

        if imgui.ButtonClickable(canToggle, u8("Статус: " .. tostring(st))) then
            Miner.Start("status")
        end

        imgui.PopStyleColor(4)
    end

    imgui.SameLine()
    imgui.Text(u8(string.format("Зарядки с собой: %d", miner.invCharge or 0)))

    -- Заполненность склада майнера и его заряд
    local labelW = math.maxEx(imgui.CalcTextSize(u8"Склад майнера").x, imgui.CalcTextSize(u8"Заряд майнера").x) + UI.Scale(10)
    local storeNow, storeMax = miner.menu.storeNow or 0, miner.menu.storeMax or 0
    Draw.FillBar("Склад майнера", labelW, storeNow, storeMax)

    -- Заряд известен после открытия окна зарядки; разряженный майнер = красный
    local chargeMax = tonumber(miner.chargeMax) or 0
    if chargeMax > 0 then
        local chargeNow = miner.chargeNow or 0
        Draw.FillBar("Заряд майнера", labelW, chargeNow, chargeMax, Draw.FillColor(chargeMax - chargeNow, chargeMax))
    end
    imgui.Separator()

    local spacing = imgui.GetStyle().ItemSpacing.x
    local third = (imgui.GetWindowContentRegionWidth() - spacing * 2) / 3

    if imgui.ButtonClickable(not miner.active, fa.GEM .. u8"\tЗабрать", imgui.ImVec2(third, 0)) then
        Miner.Start("take")
    end
    imgui.SameLine()
    if imgui.ButtonClickable(not miner.active, fa.BOLT .. u8"\tЗарядить", imgui.ImVec2(third, 0)) then
        Miner.Start("fill")
    end
    imgui.SameLine()
    if imgui.AccentButtonClickable(not miner.active, fa.PLAY .. u8"\tСделать всё", imgui.ImVec2(-1, 0)) then
        Miner.Start("both")
    end

    local halfW = (imgui.GetWindowContentRegionWidth() - spacing) / 2
    local takeIcon = settings.miner.autoTake and fa.TOGGLE_ON or fa.TOGGLE_OFF
    if imgui.Button(takeIcon .. "\t" .. (settings.miner.autoTake and u8"Автосбор: вкл" or u8"Автосбор: выкл") .. "##miner_auto_take", imgui.ImVec2(halfW, 0)) then
        settings.miner.autoTake = not settings.miner.autoTake
        Storage.SaveSettings()
    end
    imgui.SameLine()
    local fillIcon = settings.miner.autoFill and fa.TOGGLE_ON or fa.TOGGLE_OFF
    if imgui.Button(fillIcon .. "\t" .. (settings.miner.autoFill and u8"Автозарядка: вкл" or u8"Автозарядка: выкл") .. "##miner_auto_fill", imgui.ImVec2(-1, 0)) then
        settings.miner.autoFill = not settings.miner.autoFill
        Storage.SaveSettings()
    end

    local checkIcon = settings.miner.refreshOnOpen and fa.TOGGLE_ON or fa.TOGGLE_OFF
    if imgui.Button(checkIcon .. "\t" .. (settings.miner.refreshOnOpen and u8"Проверка склада при открытии меню: вкл" or u8"Проверка склада при открытии меню: выкл") .. "##miner_refresh_on_open", imgui.ImVec2(halfW, 0)) then
        settings.miner.refreshOnOpen = not settings.miner.refreshOnOpen
        Storage.SaveSettings()
    end
    imgui.SameLine()
    if imgui.ButtonClickable(not miner.active, fa.WAREHOUSE .. u8"\tПроверить склад майнера", imgui.ImVec2(-1, 0)) then
        Miner.Start("check")
    end

    imgui.Separator()

    if miner.active then
        imgui.TextColoredRGB(string.format("{%s}Идёт процесс: {%s}%s", COLORS.YELLOW, COLORS.WHITE, tostring(miner.statusText or "")))
        if imgui.Button(fa.CIRCLE_XMARK .. u8"\tОтменить" .. "##miner_cancel", imgui.ImVec2(-1, 0)) then
            Miner.Cancel()
        end
    elseif miner.statusText ~= "" then
        imgui.TextDisabled(u8(tostring(miner.statusText)))
    end

    Draw.SectionTitle("Собрано за сессию")
    Draw.AmountList(miner.collected, "Пока ничего не собрано")
    if (miner.chargeSpent or 0) > 0 then
        imgui.TextColoredRGB(string.format("{%s}Зарядки залито: %d", COLORS.YELLOW, miner.chargeSpent))
    end

    imgui.Spacing()
    Draw.SectionTitle(Draw.WareTitle(miner.wareAt))
    local ware = miner.ware or {}
    local wareItems = ware.items or {}
    local hasCharge = ware.chargeLine ~= nil
    if #wareItems > 0 or hasCharge then
        for i, it in ipairs(wareItems) do
            Draw.WareRow(i, it.name, it.count)
        end
        -- зарядку скрипт не забирает, показываем её отдельной строкой
        if hasCharge then
            local chargeName = (ware.chargeName ~= nil and ware.chargeName ~= "") and ware.chargeName or "Зарядка"
            Draw.WareRow(#wareItems + 1, chargeName, ware.chargeInWare, COLORS.YELLOW)
        end
    else
        imgui.TextDisabled(u8"Пока неизвестно - нажмите \"Проверить склад майнера\"")
    end

    Draw.Journal("miner", miner.logs)
end

function Draw.MirageMain()
    local st = Mirage.st

    local title = st.house and ("Сарай миража дома №" .. st.house) or "Сарай миража"
    Draw.SectionTitle(title)

    if (st.dialogAt or 0) > 0 then
        local labelW = imgui.CalcTextSize(u8"Монет в сарае").x + UI.Scale(10)
        Draw.FillBar("Монет в сарае", labelW, st.now or 0, st.max or 10, Draw.FillColor(st.now or 0, st.max or 10))
        if (st.cost or 0) > 0 then
            imgui.Text(u8("Стоимость сбора: " .. Draw.CloudMoney(st.cost)))
        end
        imgui.TextDisabled(u8("Данные на " .. os.date('%H:%M:%S', st.dialogAt)))
    else
        imgui.TextDisabled(u8"Подойдите к сараю миража и нажмите Alt - окно сарая откроется здесь.")
    end
    imgui.Separator()

    local spacing = imgui.GetStyle().ItemSpacing.x
    local halfW = (imgui.GetWindowContentRegionWidth() - spacing) / 2
    local canTake = st.open and (st.now or 0) > 0 and not st.pending
    if imgui.AccentButtonClickable(canTake, fa.GEM .. u8"\tЗабрать монеты", imgui.ImVec2(halfW, 0)) then
        Mirage.Take(true)
    end
    imgui.SameLine()
    local autoIcon = settings.mirage.autoTake and fa.TOGGLE_ON or fa.TOGGLE_OFF
    if imgui.Button(autoIcon .. "\t" .. (settings.mirage.autoTake and u8"Автосбор: вкл" or u8"Автосбор: выкл") .. "##mirage_auto_take", imgui.ImVec2(-1, 0)) then
        settings.mirage.autoTake = not settings.mirage.autoTake
        Storage.SaveSettings()
    end
    imgui.TextDisabled(u8"Автосбор забирает монеты сразу при открытии сарая, если они есть.")
    if imgui.Checkbox(u8"Не открывать окно скрипта при автосборе", new.bool(settings.mirage.hideOnAutoTake)) then
        settings.mirage.hideOnAutoTake = not settings.mirage.hideOnAutoTake
        Storage.SaveSettings()
    end

    if st.open then
        if imgui.Button(fa.CIRCLE_XMARK .. u8"\tЗакрыть окно сарая##mirage_close", imgui.ImVec2(-1, 0)) then
            Mirage.Close()
        end
    end

    if st.pending then
        imgui.TextColoredRGB(string.format("{%s}Идёт процесс: {%s}%s", COLORS.YELLOW, COLORS.WHITE, tostring(st.statusText or "")))
    elseif (st.statusText or "") ~= "" then
        imgui.TextDisabled(u8(tostring(st.statusText)))
    end

    Draw.SectionTitle("Собрано за сессию")
    if (st.sessionCoins or 0) > 0 then
        imgui.Text(u8(string.format("Монет миража: %d, сборов: %d", st.sessionCoins, st.sessionCollects or 0)))
        imgui.Text(u8(string.format("Потрачено: %s", Draw.CloudMoney(st.sessionSpent or 0))))
    else
        imgui.TextDisabled(u8"Пока ничего не собрано")
    end

    -- сараи, чьи 3D-надписи видны рядом: сколько монет на складе
    Draw.SectionTitle("Сараи рядом")
    imgui.Text(u8"Радиус поиска:")
    imgui.SameLine()
    imgui.PushItemWidth(-1)
    local radius = new.int(tonumber(settings.mirage.nearRadius) or 50)
    if imgui.SliderInt("##mirage_near_radius", radius, 5, 300, u8"%d м") then
        settings.mirage.nearRadius = radius[0]
        Storage.SaveSettings()
    end
    imgui.PopItemWidth()

    local rows = Mirage.NearbySheds()
    if #rows == 0 then
        imgui.TextDisabled(u8"В этом радиусе сараев не видно.")
    end
    for i, row in ipairs(rows) do
        local shed = row.shed
        local name = shed.house and ("Дом №" .. shed.house) or "Дом не указан"
        Draw.WareRow(i, string.format("%s (%d м)", name, math.floor(row.dist + 0.5)), shed.coins or 0)
    end

    Draw.Journal("mirage", st.logs)
end

function Draw.MirageLogs()
    Draw.ResourceLogs({
        id = "mirage",
        days = Mirage.log.days or {},
        state = ui_state.mirageLogs,
        opts = settings.mirage,
        extraKey = "spent",
        extraLabel = "Потрачено $",
        emptyText = "Логи сарая миража пока пустые.",
        refresh = function()
            Storage.SaveMirageLog()
            Storage.LoadMirageLog()
            return Mirage.log.days or {}
        end,
    })
end

function Draw.MinerSettings()
    imgui.Spacing()
    imgui.TextDisabled(u8"Замена диалога окном скрипта общая для всего скрипта - вкладка \"Основное\".")
    imgui.Spacing()
    if imgui.Checkbox(u8"Обновлять склад при открытии меню майнера", new.bool(settings.miner.refreshOnOpen)) then
        settings.miner.refreshOnOpen = not settings.miner.refreshOnOpen
        Storage.SaveSettings()
    end
    imgui.TextDisabled(u8"Скрипт заглянет на склад и в окно зарядки и покажет актуальные остатки.\nЕсли включён автосбор или автозарядка, склад обновляется и без этого.")
    imgui.Spacing()
    if imgui.Checkbox(u8"Автосбор ресурсов при открытии меню майнера", new.bool(settings.miner.autoTake)) then
        settings.miner.autoTake = not settings.miner.autoTake
        Storage.SaveSettings()
    end
    if imgui.Checkbox(u8"Автозарядка при открытии меню майнера", new.bool(settings.miner.autoFill)) then
        settings.miner.autoFill = not settings.miner.autoFill
        Storage.SaveSettings()
    end

    imgui.Spacing()
    imgui.Text(u8"Заряжать майнера не выше:")
    imgui.PushItemWidth(-1)
    local _fillTarget = new.int(tonumber(settings.miner.fillTarget) or Miner.CHARGE_MAX)
    if imgui.SliderInt("##minerFillTarget", _fillTarget, 0, Miner.CHARGE_MAX, u8"%d") then
        settings.miner.fillTarget = math.maxEx(0, math.minEx(Miner.CHARGE_MAX, _fillTarget[0]))
        Storage.SaveSettings()
    end
    imgui.PopItemWidth()
    imgui.TextDisabled(u8(string.format("Остальная зарядка остаётся с собой. По умолчанию %d - майнер заряжается доверху.", Miner.CHARGE_MAX)))

    imgui.Spacing()
    imgui.Separator()
    imgui.Spacing()

    imgui.Text(u8"Пауза перед ответом на диалог:")
    imgui.PushItemWidth(-1)
    local _delay = new.int(tonumber(settings.miner.actionDelay) or 150)
    if imgui.SliderInt("##minerDelay", _delay, 0, 1000, u8"%d мс") then
        settings.miner.actionDelay = math.maxEx(0, _delay[0])
        Storage.SaveSettings()
    end
    imgui.PopItemWidth()

    imgui.Text(u8"Таймаут ожидания диалога:")
    imgui.PushItemWidth(-1)
    local _timeout = new.int(tonumber(settings.miner.timeout) or 10)
    if imgui.SliderInt("##minerTimeout", _timeout, 3, 30, u8"%d сек") then
        settings.miner.timeout = math.maxEx(1, _timeout[0])
        Storage.SaveSettings()
    end
    imgui.PopItemWidth()

    imgui.Text(u8"Пауза после забора перед Alt:")
    imgui.PushItemWidth(-1)
    local _atd = new.int(tonumber(settings.miner.afterTakeDelay) or 400)
    if imgui.SliderInt("##minerAfterTake", _atd, 0, 3000, u8"%d мс") then
        settings.miner.afterTakeDelay = math.maxEx(0, _atd[0])
        Storage.SaveSettings()
    end
    imgui.PopItemWidth()

    imgui.Text(u8"Удержание клавиши Alt:")
    imgui.PushItemWidth(-1)
    local _alt = new.int(tonumber(settings.miner.altHoldTime) or 100)
    if imgui.SliderInt("##minerAltHold", _alt, 20, 500, u8"%d мс") then
        settings.miner.altHoldTime = math.maxEx(1, _alt[0])
        Storage.SaveSettings()
    end
    imgui.PopItemWidth()

    imgui.Text(u8"Хранить логи майнера (дней, 0 = без ограничения):")
    imgui.PushItemWidth(UI.Scale(120))
    local _keep = new.int(tonumber(settings.miner.logMaxDays) or 60)
    if imgui.InputInt("##minerKeep", _keep, 0, 0) then
        settings.miner.logMaxDays = math.maxEx(0, _keep[0])
        Storage.SaveSettings()
    end
    imgui.PopItemWidth()
end


function Draw.MainMenu()
    local canCancelFlashCollect = flashCollect.active or (stateCrypto.work and processes.take)
    if canCancelFlashCollect then
        if imgui.Button(fa.CIRCLE_XMARK .. u8"\tОтменить сбор", imgui.ImVec2(-1, 0)) then
            FlashCollect.Cancel()
        end
        imgui.Separator()
    end

    local lastCollectInfo = Collect.GetLastCollectInfo()
    if lastCollectInfo then
        imgui.Text(u8("Последний сбор: " .. Collect.FormatLastCollectText(lastCollectInfo)))
    else
        imgui.TextDisabled(u8"Последний сбор: ещё не зафиксирован.")
    end

    imgui.SameLine()

    local thresholdSeconds = Collect.GetReminderThresholdSeconds()
    if thresholdSeconds > 0 then
        if lastCollectInfo then
            local elapsedSeconds = math.maxEx(0, os.time() - (lastCollectInfo.timestamp or 0))
            local remainSeconds = thresholdSeconds - elapsedSeconds
            if remainSeconds > 0 then
                imgui.Text(u8("Напоминание через: " .. Collect.FormatDuration(remainSeconds)))
            elseif Collect.GameState('crypto').notifiedAt == (lastCollectInfo.timestamp or 0) then
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
        Draw.HousesBank()
    elseif #houses > 0 then
        Draw.Houses()
    else
        if #shelves == 0 then
            local canStartFlashCollect = (not stateCrypto.work) and (not flashCollect.active) and (not flashCollect.statsBusy) and (not improve.isOn) and (not improve.oils.busy)
            if imgui.AccentButtonClickable(canStartFlashCollect, u8"Открыть флешку и собрать", imgui.ImVec2(-1, 0)) then
                FlashCollect.Start()
            end
            if flashCollect.active then
                imgui.Text(u8"Сбор через флешку: ожидание списка домов...")
            elseif (flashCollect.slot or 0) > 0 and settings.main.showStatusPanel then
                imgui.Text(string.format("Сбор через флешку: слот %d, количество %d", flashCollect.slot or 0, flashCollect.count or 0))
            end
            imgui.Separator()
        end
        Draw.Shelves()
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

local function CollectLogDayTotalValue(dayData)
    local total = (dayData and dayData.total) or {}
    return (tonumber(total.BTC) or 0) + (tonumber(total.ASC) or 0)
end

local function CollectLogFilterKeys(dayKeys, periodDays)
    periodDays = tonumber(periodDays) or 0
    if periodDays <= 0 then
        return dayKeys
    end

    local fromKey = os.date('%Y-%m-%d', os.time() - (math.maxEx(1, periodDays) - 1) * 86400)
    local keys = {}
    for _, dayKey in ipairs(dayKeys or {}) do
        if tostring(dayKey) >= fromKey then
            table.insert(keys, dayKey)
        end
    end
    return keys
end

local function CollectLogGraphKeys(dayKeys, width)
    width = math.maxEx(1, tonumber(width) or imgui.GetWindowContentRegionWidth())
    local maxVisible = math.maxEx(1, math.floor(width / UI.Scale(46)))
    local count = math.minEx(#dayKeys, maxVisible)
    local keys = {}
    for i = count, 1, -1 do
        table.insert(keys, dayKeys[i])
    end
    return keys
end

function Draw.CollectLogsList(days, dayKeys)
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
                        local trimmed = tonumber(houseData.itemsTrimmed or 0) or 0
                        if trimmed > 0 then
                            imgui.TextDisabled(u8(string.format('Скрыто старых записей: %d', trimmed)))
                        end
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

function Draw.CollectLogsGraph(days, dayKeys)
    if #dayKeys == 0 then
        imgui.BeginChild('collect_logs_graph_empty', imgui.ImVec2(-1, -1), true)
        imgui.TextDisabled(u8'Логи сбора пока пустые.')
        imgui.EndChild()
        return
    end

    ui_state.collectLogs.selectedDay = ui_state.collectLogs.selectedDay or dayKeys[1]
    local selectedInFilter = false
    for _, dayKey in ipairs(dayKeys) do
        if dayKey == ui_state.collectLogs.selectedDay then
            selectedInFilter = true
            break
        end
    end
    if not selectedInFilter or not days[ui_state.collectLogs.selectedDay] then
        ui_state.collectLogs.selectedDay = dayKeys[1]
    end

    imgui.BeginChild('collect_logs_graph', imgui.ImVec2(-1, -1), true)
    imgui.ScrollMouse()
    imgui.Text(u8'Прибыль за день')
    imgui.SameLine()
    imgui.TextDisabled(u8'Кликните по столбцу, чтобы увидеть дома.')
    imgui.Spacing()

    local graphW = math.maxEx(UI.Scale(160), imgui.GetWindowContentRegionWidth())
    local graphKeys = CollectLogGraphKeys(dayKeys, graphW)
    local maxTotal = 1
    for _, dayKey in ipairs(graphKeys) do
        maxTotal = math.maxEx(maxTotal, CollectLogDayTotalValue(days[dayKey]))
    end

    local gap = UI.Scale(5)
    local barW = math.maxEx(UI.Scale(28), (graphW - gap * (#graphKeys - 1)) / math.maxEx(1, #graphKeys))
    local graphH = UI.Scale(150)
    local drawList = imgui.GetWindowDrawList()
    local colBg, colBar, colBarActive, colText = Draw.GraphColors()

    for i, dayKey in ipairs(graphKeys) do
        if i > 1 then imgui.SameLine(nil, gap) end
        local totalValue = CollectLogDayTotalValue(days[dayKey])
        local pos = imgui.GetCursorScreenPos()
        if imgui.InvisibleButton('##collect_graph_bar_' .. tostring(dayKey), imgui.ImVec2(barW, graphH)) then
            ui_state.collectLogs.selectedDay = dayKey
        end
        local ratio = totalValue / maxTotal
        local filledH = math.maxEx(UI.Scale(3), (graphH - UI.Scale(28)) * ratio)
        local x1, y1 = pos.x, pos.y
        local x2, y2 = pos.x + barW, pos.y + graphH
        drawList:AddRectFilled(imgui.ImVec2(x1, y1), imgui.ImVec2(x2, y2), colBg, UI.Scale(4), 15)
        local barColor = (ui_state.collectLogs.selectedDay == dayKey) and colBarActive or colBar
        drawList:AddRectFilled(imgui.ImVec2(x1 + UI.Scale(4), y2 - filledH - UI.Scale(20)), imgui.ImVec2(x2 - UI.Scale(4), y2 - UI.Scale(20)), barColor, UI.Scale(3), 15)
        local label = tostring(dayKey):sub(6)
        drawList:AddText(imgui.ImVec2(x1 + UI.Scale(4), y2 - UI.Scale(17)), colText, label)
        if imgui.IsItemHovered() then
            local total = (days[dayKey] and days[dayKey].total) or {}
            imgui.SetTooltip(u8(string.format('%s\nВсего: BTC %s | ASC %s', dayKey, FormatCryptoAmount(total.BTC), FormatCryptoAmount(total.ASC))))
        end
    end

    imgui.Spacing()
    imgui.Separator()

    local selectedDay = ui_state.collectLogs.selectedDay
    local dayData = days[selectedDay] or {}
    local dayTotal = dayData.total or {}
    imgui.Text(u8(string.format('Выбран день: %s | BTC: %s | ASC: %s', tostring(selectedDay), FormatCryptoAmount(dayTotal.BTC), FormatCryptoAmount(dayTotal.ASC))))
    imgui.Text(u8'Доход по домам за выбранный день:')

    local houseKeys = CollectLogSortedKeys(dayData.houses or {})
    if #houseKeys == 0 then
        imgui.TextDisabled(u8'Нет данных по домам.')
    else
        for _, houseId in ipairs(houseKeys) do
            local houseData = dayData.houses[houseId] or {}
            local houseTotal = houseData.total or {}
            imgui.BulletText(u8(string.format('Дом №%s | BTC: %s | ASC: %s', tostring(houseId), FormatCryptoAmount(houseTotal.BTC), FormatCryptoAmount(houseTotal.ASC))))
        end
    end

    imgui.EndChild()
end

function Draw.CollectLogs()
    local days = collectLogStore.days or {}
    local allDayKeys = CollectLogSortedKeys(days)
    local periodDays = tonumber(settings.main.collectLogsPeriod or 7) or 7
    local dayKeys = CollectLogFilterKeys(allDayKeys, periodDays)

    if imgui.Button(u8'Обновить') then
        Storage.FlushCollectLogStore()
        Storage.LoadCollectLogStore()
        days = collectLogStore.days or {}
        allDayKeys = CollectLogSortedKeys(days)
        dayKeys = CollectLogFilterKeys(allDayKeys, periodDays)
    end
    imgui.SameLine()
    imgui.Text(u8(string.format('Дней с логами: %d/%d', #dayKeys, #allDayKeys)))

    local periodOptions = {
        { days = 3, label = '3 дня' },
        { days = 7, label = '7 дней' },
        { days = 14, label = '14 дней' },
        { days = 30, label = '30 дней' },
        { days = 0, label = 'Всё время' },
    }
    local periodW = (imgui.GetWindowContentRegionWidth() - imgui.GetStyle().ItemSpacing.x * (#periodOptions - 1)) / #periodOptions
    for i, option in ipairs(periodOptions) do
        if i > 1 then imgui.SameLine() end
        if imgui.ButtonClickable(periodDays ~= option.days, u8(option.label), imgui.ImVec2(i == #periodOptions and -1 or periodW, 0)) then
            settings.main.collectLogsPeriod = option.days
            Storage.SaveSettings()
            periodDays = option.days
            dayKeys = CollectLogFilterKeys(allDayKeys, periodDays)
        end
    end

    imgui.Separator()

    local w = (imgui.GetWindowContentRegionWidth() - imgui.GetStyle().ItemSpacing.x) / 2
    if imgui.ButtonClickable(settings.main.collectLogsView ~= 'list', u8'Список', imgui.ImVec2(w, 0)) then
        settings.main.collectLogsView = 'list'
        Storage.SaveSettings()
    end
    imgui.SameLine()
    if imgui.ButtonClickable(settings.main.collectLogsView ~= 'graph', u8'График', imgui.ImVec2(-1, 0)) then
        settings.main.collectLogsView = 'graph'
        Storage.SaveSettings()
    end

    if settings.main.collectLogsView == 'graph' then
        Draw.CollectLogsGraph(days, dayKeys)
    else
        Draw.CollectLogsList(days, dayKeys)
    end
end
function Draw.ImproveSharp()
    if imgui.BeginTabBar("ImproveTabs") then

        if imgui.BeginTabItem(u8"Процесс") then
            Draw.ImproveProcessTab()
            imgui.EndTabItem()
        end

        if imgui.BeginTabItem(u8"Настройки") then
            Draw.ImproveSettingsTab()
            imgui.EndTabItem()
        end

        if imgui.BeginTabItem(u8"Логи") then
            Draw.ImproveLogsTab()
            imgui.EndTabItem()
        end

        imgui.EndTabBar()
    end
end

-- =====================================================================================================================
--                        Вкладка «Процесс» заточки
-- =====================================================================================================================

-- Карта, которую скрипт точит прямо сейчас
function Improve.CurrentCard()
    if not improve.isOn then return nil end
    return improve.videoCards[tonumber(improve.currentIndex or 0) or 0]
end

-- Карте больше не нужна заточка в текущем режиме
function Improve.IsCardDone(v)
    if improve.useStorageUpgrade then return v.storageUpgrade == true end
    return (tonumber(v.level) or 0) >= (tonumber(settings.improve.maxLevel) or 2)
end

-- Выбранная карта (режим «одна карта»)
function Improve.SelectedCard()
    if not improve.selectSlot then return nil end
    for _, v in ipairs(improve.videoCards or {}) do
        if v.slot == improve.selectSlot then return v end
    end
    return nil
end

-- Какие карты пойдут в работу: первая из них и сколько всего
function Improve.PlanCards()
    if not settings.improve.menuAll then
        local v = Improve.SelectedCard()
        if v and not Improve.IsCardDone(v) then return v, 1 end
        return nil, 0
    end
    local first, todo = nil, 0
    for _, v in ipairs(improve.videoCards or {}) do
        if not Improve.IsCardDone(v) then
            todo = todo + 1
            first = first or v
        end
    end
    return first, todo
end

-- Что мешает запуску; nil - можно запускать
function Improve.GetStartBlocker()
    local cards = improve.videoCards or {}
    if #cards > 0 then
        if not settings.improve.menuAll then
            local v = Improve.SelectedCard()
            if not v then
                return 'Выберите карту в списке ниже или переключите "Какие карты" на "Все по очереди"'
            end
            if Improve.IsCardDone(v) then
                return improve.useStorageUpgrade and 'У выбранной карты хранилище уже улучшено'
                    or string.format('Выбранная карта уже на %d ур. - поднимите цель или выберите другую', v.level or 0)
            end
        else
            local _, todo = Improve.PlanCards()
            if todo == 0 then
                return improve.useStorageUpgrade and 'Хранилище уже улучшено у всех карт'
                    or string.format('Все карты уже на %d ур. или выше - поднимите цель', settings.improve.maxLevel or 2)
            end
        end
    end

    if settings.improve.checkOilsOnStart and not improve.useStorageUpgrade and improve.oils.lastAt ~= '-' then
        local count = Improve.GetOilCountByType()
        if count < 2 then return 'Нет смазки: на одну попытку нужно 2 шт.' end
    end
    return nil
end

function Improve.FormatDuration(sec)
    sec = math.maxEx(0, tonumber(sec) or 0)
    if sec < 60 then return string.format('%d с', sec) end
    if sec < 3600 then return string.format('%d мин %d с', math.floor(sec / 60), sec % 60) end
    return string.format('%d ч %d мин', math.floor(sec / 3600), math.floor((sec % 3600) / 60))
end

-- Что скрипт делает сейчас: текст, иконка, ключ цвета
function Improve.GetStatusLine()
    local probeText = string.format('Проверяю уровни карт: %d из %d',
        math.maxEx(0, improve.cef.pendingIndex or 0), math.maxEx(1, tonumber(improve.cef.probeTotal) or 1))

    if not improve.isOn then
        if improve.cef.probing then return probeText, fa.MAGNIFYING_GLASS, 'warnColor' end
        if improve.oils.busy then return 'Обновляю инвентарь через /stats…', fa.ARROWS_ROTATE, 'warnColor' end
        local s = improve.stats or {}
        if (s.sessionId or 0) > 0 and (s.lastReason or '') ~= '' then
            local reason = tostring(s.lastReason):gsub('^Новый стиль:%s*', '')
            return 'Остановлено: ' .. reason, fa.STOP, nil
        end
        return 'Заточка выключена', fa.STOP, nil
    end

    if improve.needCheckOils or improve.waitOils or improve.oils.busy or improve.cef.waitInventory then
        return 'Готовлю: проверяю смазку и инвентарь…', fa.ARROWS_ROTATE, 'warnColor'
    end
    if improve.cef.probing then return probeText, fa.MAGNIFYING_GLASS, 'warnColor' end

    local card = Improve.CurrentCard()
    if card and improve.step ~= Improve.STEP.SELECT_CARD then
        local what = improve.useStorageUpgrade
            and string.format('слот %d, хранилище', card.slot or 0)
            or string.format('слот %d, %d -> %d ур.', card.slot or 0, card.level or 0, (card.level or 0) + 1)
        if improve.step == Improve.STEP.WAIT_RESULT then
            local sec = math.floor(os.clock() - (tonumber(improve.waitResultAt) or os.clock()))
            return string.format('Карта точится (%s), жду результат: %d с', what, math.maxEx(0, sec)), fa.PLAY, 'okColor'
        end
        if improve.waitStart then
            return 'Подтверждаю улучшение (' .. what .. ')', fa.PLAY, 'okColor'
        end
        return 'Открываю окно улучшения (' .. what .. ')', fa.PLAY, 'okColor'
    end
    return 'Выбираю следующую карту…', fa.PLAY, 'okColor'
end

-- Запуск заточки кнопкой
function Improve.StartFromUI()
    if ISMONETLOADER then
        mobileImproveDialog.suppressUntil = 0
        mobileImproveDialog.lastShowAt = 0
        mobileImproveDialog.lastText = ''
        mobileImproveDialog.wasActive = false
    end
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

    if settings.improve.checkOilsOnStart or Improve.IsNewStyleMode() then
        -- сначала проверяем смазку
        improve.step          = Improve.STEP.STOPPED
        improve.needCheckOils = true
        improve.waitOils      = false
    else
        -- сразу начинаем с первого шага без проверки
        improve.step          = Improve.STEP.SELECT_CARD
        improve.needCheckOils = false
        improve.waitOils      = false
    end

    Improve.SessionStart()
    Improve.Say("Заточка видеокарт запущена.")
end

-- Кнопка в один ряд с другими: выбранный вариант подсвечен акцентом
function Draw.ImproveSegment(id, labels, current, locked)
    local spacing = imgui.GetStyle().ItemSpacing.x
    local w = (imgui.GetContentRegionAvail().x - spacing * (#labels - 1)) / #labels
    local picked
    for i, label in ipairs(labels) do
        if i > 1 then imgui.SameLine() end
        local text = u8(label) .. '##' .. id .. i
        local size = imgui.ImVec2(i == #labels and -1 or w, 0)
        if i == current then
            imgui.AccentButton(text, size)
        elseif imgui.ButtonClickable(not locked, text, size) and not locked then
            picked = i
        end
    end
    return picked
end

-- Подпись слева и элемент управления справа - на одной высоте
function Draw.ImproveRowLabel(text, labelW)
    imgui.AlignTextToFramePadding()
    imgui.Text(u8(text))
    imgui.SameLine(labelW)
end

-- Строка статуса и три главные цифры
function Draw.ImproveHeader()
    local text, icon, colorKey = Improve.GetStatusLine()
    local col = colorKey and UI.Vec4(colorKey) or imgui.GetStyle().Colors[imgui.Col.TextDisabled]
    imgui.TextColored(col, icon)
    imgui.SameLine()
    imgui.TextColored(colorKey and col or UI.Vec4('textColor'), u8(text))

    local first, todo = Improve.PlanCards()
    local cardsTotal = #(improve.videoCards or {})
    local oil = Improve.GetOilCountByType()

    imgui.Columns(3, 'improve_head', false)
        imgui.TextDisabled(u8'Видеокарты')
        if cardsTotal > 0 then
            imgui.Text(u8(string.format('%d шт., точить: %d', cardsTotal, todo)))
        else
            imgui.Text(u8'не найдены')
        end
    imgui.NextColumn()
        imgui.TextDisabled(u8'Смазка')
        if improve.useStorageUpgrade then
            imgui.Text(u8'не нужна для хранилища')
        elseif improve.oils.lastAt == '-' then
            imgui.Text(u8'ещё не проверена')
        else
            local col2 = oil >= 2 and UI.Vec4('textColor') or UI.Vec4('badColor')
            imgui.TextColored(col2, u8(string.format('%s шт. (на %d попыток)', Util.GetCommaValue(oil), math.floor(oil / 2))))
        end
    imgui.NextColumn()
        imgui.TextDisabled(u8'Цена попытки')
        local price = (first and not improve.useStorageUpgrade) and Improve.GetPriceByFromLevel(first.level) or 0
        if price > 0 then
            imgui.Text(u8(string.format('$%s (с %d ур.)', Util.GetCommaValue(price), first.level or 0)))
        else
            imgui.Text(u8'-')
        end
    imgui.Columns(1)
end

-- Что и как точить: меняется только пока заточка остановлена
function Draw.ImproveQuickSettings()
    local locked = improve.isOn
    local labelW = UI.Scale(120)

    Draw.ImproveRowLabel('Что улучшать:', labelW)
    local mode = Draw.ImproveSegment('imp_mode', { 'Производительность', 'Хранилище крипты' }, improve.useStorageUpgrade and 2 or 1, locked)
    if mode then
        improve.useStorageUpgrade = (mode == 2)
        Improve.SyncVideoCardsFromCef()
    end

    Draw.ImproveRowLabel('Какие карты:', labelW)
    local which = Draw.ImproveSegment('imp_which', { 'Все по очереди', 'Одну выбранную' }, settings.improve.menuAll and 1 or 2, locked)
    if which then
        settings.improve.menuAll = (which == 1)
        if settings.improve.menuAll then
            improve.select = 0
            improve.selectSlot = nil
        end
        Storage.SaveSettings()
    end

    if not improve.useStorageUpgrade then
        Draw.ImproveRowLabel('Точить до:', labelW)
        imgui.PushItemWidth(-1)
        local _maxLevel = imgui.new.int(settings.improve.maxLevel or 2)
        if imgui.SliderInt('##imp_quick_level', _maxLevel, 2, 10, u8('%d ур.')) then
            settings.improve.maxLevel = _maxLevel[0]
            Storage.SaveSettings()
        end
        imgui.PopItemWidth()
    end

    if locked then
        imgui.TextDisabled(u8'Режим и выбор карт меняются, когда заточка остановлена.')
    end
end

-- Большая кнопка запуска; если запускать нельзя - объясняем почему
function Draw.ImproveStartButton()
    local h = UI.Scale(32)
    if improve.isOn then
        local col = UI.Vec4('badColor')
        imgui.PushStyleColor(imgui.Col.Button, col)
        imgui.PushStyleColor(imgui.Col.ButtonHovered, Shade(col, 1.15))
        imgui.PushStyleColor(imgui.Col.ButtonActive, Shade(col, 0.85))
        local pressed = imgui.Button(fa.STOP .. u8'\tОстановить заточку', imgui.ImVec2(-1, h))
        imgui.PopStyleColor(3)
        if pressed then
            Improve.Stop("Остановлено вручную через UI")
            Improve.Say("Заточка остановлена вручную.")
        end
        return
    end

    local blocker = Improve.GetStartBlocker()
    if imgui.AccentButtonClickable(blocker == nil, fa.PLAY .. u8'\tНачать заточку', imgui.ImVec2(-1, h)) then
        Improve.StartFromUI()
    end

    if blocker then
        imgui.TextColored(UI.Vec4('warnColor'), fa.TRIANGLE_EXCLAMATION)
        imgui.SameLine()
        imgui.TextColored(UI.Vec4('warnColor'), u8(blocker))
        return
    end

    -- что произойдёт после нажатия
    local first, todo = Improve.PlanCards()
    local plan
    if #(improve.videoCards or {}) == 0 then
        plan = 'Скрипт обновит инвентарь через /stats, найдёт карты и начнёт заточку.'
    elseif improve.useStorageUpgrade then
        plan = string.format('Улучшит хранилище у %d карт, начиная со слота %d.', todo, first and first.slot or 0)
    elseif not settings.improve.menuAll then
        plan = string.format('Будет точить карту в слоте %d до %d ур.', first and first.slot or 0, settings.improve.maxLevel or 2)
    else
        plan = string.format('Будет точить %d карт до %d ур., %s.', todo, settings.improve.maxLevel or 2,
            settings.improve.mode == 1 and 'сначала самые слабые' or 'по порядку в списке')
    end
    imgui.TextDisabled(u8(plan .. ' Стойте у стола для улучшения видеокарт.'))
end

-- Итоги текущей или последней сессии и последний результат
function Draw.ImproveSession()
    local s = improve.stats
    if not s or (s.sessionId or 0) == 0 then
        imgui.TextDisabled(u8'Сессий заточки ещё не было.')
        return
    end

    local att = s.attempts or 0
    local rate = att > 0 and math.floor((s.success or 0) * 100 / att + 0.5) or 0
    local endAt = s.active and os.time() or (tonumber(s.finishedAt) or os.time())
    local dur = endAt - (tonumber(s.startedAt) or endAt)

    imgui.Text(u8(string.format('Сессия #%d - %s, %s', s.sessionId, s.active and 'идёт' or 'завершена', Improve.FormatDuration(dur))))
    imgui.TextColoredRGB(string.format(
        'Попыток: %d   {%s}Успехов: %d (%d%%%%){%s}   {%s}Неудач: %d{%s}   Смазки: %d   Потрачено: $%s',
        att, COLORS.GREEN, s.success or 0, rate, COLORS.WHITE, COLORS.RED, s.fail or 0, COLORS.WHITE,
        s.oilsUsed or 0, Util.GetCommaValue(math.floor(tonumber(s.spent) or 0))
    ))

    local r = improve.lastResult
    if r then
        local when = os.date('%H:%M:%S', r.at or os.time())
        local line
        if r.timeout then
            line = string.format('{%s}%s  слот %d: сервер не ответил, попытка засчитана как неудачная', COLORS.YELLOW, when, r.slot or 0)
        elseif r.storage then
            line = string.format('{%s}%s  слот %d: %s', r.ok and COLORS.GREEN or COLORS.RED, when, r.slot or 0,
                r.ok and 'хранилище улучшено' or 'хранилище не улучшилось')
        elseif r.ok then
            line = string.format('{%s}%s  слот %d: %d -> %d ур., успех', COLORS.GREEN, when, r.slot or 0, r.from or 0, r.to or 0)
        else
            line = string.format('{%s}%s  слот %d: неудача, остался %d ур.', COLORS.RED, when, r.slot or 0, r.from or 0)
        end
        imgui.TextColoredRGB('Последний результат: ' .. line)
    end
end

-- Кнопки инвентаря и прогресс проверки уровней
function Draw.ImproveCardTools()
    local busy = improve.isOn or improve.cef.probing or improve.oils.busy
    local third = imgui.GetMiddleButtonX(3)

    if imgui.ButtonClickable(not busy, fa.ARROWS_ROTATE .. u8(improve.oils.busy and '\tОбновляю…' or '\tОбновить инвентарь'), imgui.ImVec2(third, 0)) and not busy then
        Improve.RefreshOils(true)
    end
    imgui.SameLine()
    if imgui.ButtonClickable(not busy, fa.MAGNIFYING_GLASS .. u8'\tПроверить уровни', imgui.ImVec2(third, 0)) and not busy then
        Improve.ManualCheckCardLevels(false)
    end
    imgui.SameLine()
    if imgui.ButtonClickable(not busy, u8'Сканировать заново', imgui.ImVec2(-1, 0)) and not busy then
        Improve.ManualCheckCardLevels(true)
    end
    if imgui.IsItemHovered() then
        imgui.SetTooltip(u8'Забыть запомненные уровни и проверить все карты ещё раз')
    end

    local known, unknown = Improve.CountKnownLevels()
    local total = known + unknown
    if improve.cef.probing or unknown > 0 then
        local frac = (total > 0) and math.maxEx(0.0, math.minEx(1.0, known / total)) or 0.0
        local caption = improve.cef.probing
            and string.format('Проверяю: %d из %d', math.maxEx(0, improve.cef.pendingIndex or 0), math.maxEx(1, tonumber(improve.cef.probeTotal) or total))
            or string.format('Уровень неизвестен у %d карт из %d', unknown, total)
        imgui.ProgressBar(frac, imgui.ImVec2(-1, UI.Scale(16)), u8(caption))
    end
    if not improve.cef.probing and (improve.cef.probeAbortReason or '') ~= '' then
        imgui.TextColored(UI.Vec4('warnColor'), u8('Проверка прервана: ' .. tostring(improve.cef.probeAbortReason)))
    end
end

-- Одна плитка видеокарты
function Draw.ImproveCardTile(i, v, w, isCurrent, isSelected)
    local known = v.levelKnown ~= false
    local lvlText = known and string.format('%d ур.', v.level or 0) or '? ур.'
    if v.storageUpgrade then lvlText = lvlText .. '  ХР+' end
    local label = u8(string.format('%s\nслот %d', lvlText, v.slot or 0)) .. '##imp_card' .. i

    local col
    if isCurrent or isSelected then
        col = UI.Vec4('accentColor')
    elseif not known then
        col = UI.Vec4('warnColor', 0.45)
    elseif Improve.IsCardDone(v) then
        col = UI.Vec4('okColor', 0.30)
    end
    if col then
        imgui.PushStyleColor(imgui.Col.Button, col)
        imgui.PushStyleColor(imgui.Col.ButtonHovered, Shade(col, 1.15))
        imgui.PushStyleColor(imgui.Col.ButtonActive, Shade(col, 0.85))
    end
    local clicked = imgui.Button(label, imgui.ImVec2(w, UI.Scale(38)))
    if col then imgui.PopStyleColor(3) end

    if imgui.IsItemHovered() then
        local unit = (tonumber(v.cardType) or 1) == 2 and 'ASC' or 'BTC'
        local tip = string.format('Слот %d\nУровень: %s\nХранилище: %s', v.slot or 0,
            known and string.format('%d из 10', v.level or 0) or 'неизвестен',
            v.storageUpgrade and 'улучшено' or 'не улучшено')
        local hourly = known and GPU_HOURLY_BY_LEVEL[tonumber(v.level) or 0]
        if hourly then tip = tip .. string.format('\nДоход: %.6f %s в час', hourly, unit) end
        if isCurrent then
            tip = tip .. '\n\nСейчас точится'
        elseif not settings.improve.menuAll then
            tip = tip .. '\n\nНажмите, чтобы выбрать эту карту'
        else
            tip = tip .. '\n\nЧтобы точить только её, включите "Одну выбранную"'
        end
        imgui.SetTooltip(u8(tip))
    end
    return clicked
end

-- Список карт плитками: порядок = очередь заточки
function Draw.ImproveCardGrid()
    local cards = improve.videoCards or {}
    if #cards == 0 then
        imgui.TextDisabled(u8'Карты ещё не найдены. Нажмите "Обновить инвентарь" или просто начните заточку.')
        return
    end

    local legend = {
        { 'okColor', 'на цели' },
        { 'accentColor', 'точится / выбрана' },
        { 'warnColor', 'уровень неизвестен' },
    }
    for _, l in ipairs(legend) do
        imgui.TextColored(UI.Vec4(l[1]), fa.SQUARE)
        imgui.SameLine()
        imgui.TextDisabled(u8(l[2]))
        imgui.SameLine()
    end
    imgui.TextDisabled(u8(settings.improve.menuAll and '  Порядок = очередь заточки' or '  Нажмите на карту, чтобы выбрать'))

    local current = Improve.CurrentCard()
    imgui.BeginChild('improve_cards', imgui.ImVec2(-1, -1), true)
        imgui.ScrollMouse()
        local spacing = imgui.GetStyle().ItemSpacing.x
        local avail = imgui.GetContentRegionAvail().x
        local cols = math.maxEx(2, math.floor((avail + spacing) / (UI.Scale(110) + spacing)))
        local w = (avail - spacing * (cols - 1)) / cols

        for i, v in ipairs(cards) do
            local isCurrent = current ~= nil and current.slot == v.slot
            local isSelected = (not settings.improve.menuAll) and improve.selectSlot == v.slot
            if Draw.ImproveCardTile(i, v, w, isCurrent, isSelected)
                and not settings.improve.menuAll and not improve.isOn then
                improve.select = i
                improve.selectSlot = v.slot
            end
            if i % cols ~= 0 and i ~= #cards then imgui.SameLine() end
        end
    imgui.EndChild()
end

function Draw.ImproveProcessTab()
    Draw.ImproveHeader()
    imgui.Separator()
    Draw.ImproveQuickSettings()
    imgui.Spacing()
    Draw.ImproveStartButton()
    imgui.Separator()
    Draw.ImproveSession()
    imgui.Spacing()
    Draw.SectionTitle(settings.improve.typeCards == 2 and 'Видеокарты Arizona' or 'Видеокарты')
    Draw.ImproveCardTools()
    Draw.ImproveCardGrid()
end

-- Кнопка опасного действия: первое нажатие просит подтверждения, второе выполняет
function Draw.ConfirmButton(key, label, confirmLabel, size)
    improve.ui = improve.ui or {}
    local armedAt = tonumber(improve.ui[key]) or 0
    local armed = (os.clock() - armedAt) < 4
    if armed then
        local col = UI.Vec4('badColor')
        imgui.PushStyleColor(imgui.Col.Button, col)
        imgui.PushStyleColor(imgui.Col.ButtonHovered, Shade(col, 1.15))
        imgui.PushStyleColor(imgui.Col.ButtonActive, Shade(col, 0.85))
        local pressed = imgui.Button(u8(confirmLabel) .. '##' .. key, size)
        imgui.PopStyleColor(3)
        if pressed then improve.ui[key] = 0 end
        return pressed
    end
    if imgui.Button(u8(label) .. '##' .. key, size) then
        improve.ui[key] = os.clock()
    end
    return false
end

-- Слайдер с подписью сверху и пояснением снизу
function Draw.ImproveSlider(label, id, value, minV, maxV, fmt, hint)
    imgui.Text(u8(label))
    imgui.PushItemWidth(-1)
    local ptr = imgui.new.int(tonumber(value) or minV)
    local changed = imgui.SliderInt('##' .. id, ptr, minV, maxV, u8(fmt))
    imgui.PopItemWidth()
    if hint then imgui.TextDisabled(u8(hint)) end
    return changed and ptr[0] or nil
end

-- Задержки и таймауты заточки: общие для вкладки заточки и раздела «Задержки»
function Draw.ImproveDelaySettings()
    local d = settings.deley
    local v

    v = Draw.ImproveSlider('Пауза после результата улучшения:', 'improve_waitResult', d.improve_waitResult or 500, 10, 1000, '%d мс',
        'Сколько подождать после "успешно" или "ошибка", прежде чем браться за следующую карту')
    if v then d.improve_waitResult = v; Storage.SaveSettings() end

    v = Draw.ImproveSlider('Пауза перед нажатием на видеокарту:', 'improve_waitTryClick', d.improve_waitTryClick or 500, 10, 1000, '%d мс',
        'Пауза перед кликом по карте в инвентаре')
    if v then d.improve_waitTryClick = v; Storage.SaveSettings() end

    v = Draw.ImproveSlider('Пауза после /invent:', 'improve_waitInventory', d.improve_waitInventory or 1500, 300, 5000, '%d мс',
        'Сколько ждать, пока откроется инвентарь. Увеличьте, если окно улучшения не открывается')
    if v then d.improve_waitInventory = v; Storage.SaveSettings() end

    v = Draw.ImproveSlider('Повторный клик, если окно не открылось:', 'improve_retryUseDelay', d.improve_retryUseDelay or 1200, 200, 5000, '%d мс',
        'Если за это время окно улучшения не появилось, скрипт кликнет по карте снова')
    if v then d.improve_retryUseDelay = v; Storage.SaveSettings() end

    v = Draw.ImproveSlider('Ждать начала улучшения:', 'improve_waitStartTimeout', d.improve_waitStartTimeout or 8, 2, 30, '%d сек',
        'Если сервер не написал "Вы начали процесс улучшения", попытка начинается заново')
    if v then d.improve_waitStartTimeout = v; Storage.SaveSettings() end

    v = Draw.ImproveSlider('Ждать результата улучшения:', 'improve_waitResultTimeout', d.improve_waitResultTimeout or 20, 3, 60, '%d сек',
        'Если результата нет, попытка считается неудачной и заточка идёт дальше')
    if v then d.improve_waitResultTimeout = v; Storage.SaveSettings() end
end

-- Сколько слотов с запомненным уровнем
function Improve.CountCachedLevels()
    local n = 0
    for _ in pairs(cardLevels.slots or {}) do n = n + 1 end
    return n
end

function Draw.ImproveSettingsTab()
    local locked = improve.isOn
    local labelW = UI.Scale(130)

    imgui.BeginChild('improve_settings_scroll', imgui.ImVec2(-1, -1), false)
    imgui.ScrollMouse()

    -- ---------- Что точить ----------
    Draw.SectionTitle('Что точить')

    Draw.ImproveRowLabel('Тип карт:', labelW)
    local cardType = Draw.ImproveSegment('imp_set_type', { 'Обычные (BTC)', 'Arizona (ASC)' }, settings.improve.typeCards == 2 and 2 or 1, locked)
    if cardType then
        settings.improve.typeCards = cardType
        Storage.SaveSettings()
        Improve.SyncVideoCardsFromCef()
        improve.select = 0
        improve.selectSlot = nil
    end

    Draw.ImproveRowLabel('Какие карты:', labelW)
    local which = Draw.ImproveSegment('imp_set_which', { 'Все по очереди', 'Одну выбранную' }, settings.improve.menuAll and 1 or 2, locked)
    if which then
        settings.improve.menuAll = (which == 1)
        if settings.improve.menuAll then
            improve.select = 0
            improve.selectSlot = nil
        end
        Storage.SaveSettings()
    end

    if settings.improve.menuAll then
        Draw.ImproveRowLabel('Порядок:', labelW)
        local order = Draw.ImproveSegment('imp_set_order', { 'Сначала слабые', 'Как в инвентаре' }, settings.improve.mode == 2 and 2 or 1, locked)
        if order then
            settings.improve.mode = order
            Storage.SaveSettings()
            Improve.SyncVideoCardsFromCef()
        end
    end

    Draw.ImproveRowLabel('Точить до:', labelW)
    imgui.PushItemWidth(-1)
    local _maxLevel = imgui.new.int(settings.improve.maxLevel or 2)
    if imgui.SliderInt('##imp_set_level', _maxLevel, 2, 10, u8('%d ур.')) then
        settings.improve.maxLevel = _maxLevel[0]
        Storage.SaveSettings()
    end
    imgui.PopItemWidth()

    local summary
    if not settings.improve.menuAll then
        summary = string.format('Скрипт точит одну карту, которую вы выберете на вкладке "Процесс", до %d ур.', settings.improve.maxLevel or 2)
    elseif settings.improve.mode == 2 then
        summary = string.format('Скрипт точит все карты до %d ур. в том порядке, как они лежат в инвентаре.', settings.improve.maxLevel or 2)
    else
        summary = string.format('Скрипт точит все карты до %d ур., сначала самые слабые: так дешевле поднять общий доход.', settings.improve.maxLevel or 2)
    end
    imgui.TextDisabled(u8(summary .. ' Карты, которые уже на цели, пропускаются.'))
    if locked then
        imgui.TextColored(UI.Vec4('warnColor'), u8'Пока идёт заточка, тип карт, выбор и порядок не меняются.')
    end

    imgui.Spacing()

    -- ---------- Перед стартом ----------
    Draw.SectionTitle('Перед стартом')
    local _checkOils = imgui.new.bool(settings.improve.checkOilsOnStart)
    if imgui.Checkbox(u8'Проверять смазку при старте заточки', _checkOils) then
        settings.improve.checkOilsOnStart = not settings.improve.checkOilsOnStart
        Storage.SaveSettings()
    end
    imgui.TextDisabled(u8'Скрипт откроет /stats, посчитает смазку и не начнёт, если её меньше 2 шт.\nЕсли выключить, заточка стартует сразу, а счётчик смазки не останавливает её.')

    imgui.Spacing()

    -- ---------- Уровни видеокарт ----------
    Draw.SectionTitle('Уровни видеокарт')
    imgui.TextDisabled(u8(string.format(
        'Скрипт помнит уровни по слотам (сейчас: %d) и обновляет их по пакетам инвентаря,\nпо окну улучшения и по "Информации о предмете".',
        Improve.CountCachedLevels())))

    local _pktLevels = imgui.new.bool(settings.improve.packetLevels ~= false)
    if imgui.Checkbox(u8'Брать уровни из пакетов инвентаря', _pktLevels) then
        settings.improve.packetLevels = not (settings.improve.packetLevels ~= false)
        Storage.SaveSettings()
    end
    imgui.TextDisabled(u8'Уровни приходят от сервера при входе в игру и при каждом изменении карты.\nБез этой галочки каждую карту придётся открывать по одной.')

    local _fast = imgui.new.bool(settings.improve.fastProbe ~= false)
    if imgui.Checkbox(u8'Не переоткрывать инвентарь между картами', _fast) then
        settings.improve.fastProbe = not (settings.improve.fastProbe ~= false)
        Storage.SaveSettings()
    end
    imgui.TextDisabled(u8'Экономит 2-3 с на каждой карте при проверке и заточке.\nЕсли клик не сработал, инвентарь всё равно переоткроется.')

    Draw.ImproveRowLabel('Помнить уровень:', labelW)
    imgui.PushItemWidth(UI.Scale(90))
    local _ttl = imgui.new.int(tonumber(settings.improve.levelCacheHours) or 0)
    if imgui.InputInt('##levelCacheHours', _ttl, 0, 0) then
        settings.improve.levelCacheHours = math.maxEx(0, _ttl[0])
        Storage.SaveSettings()
    end
    imgui.PopItemWidth()
    imgui.SameLine()
    local ttl = tonumber(settings.improve.levelCacheHours) or 0
    imgui.TextDisabled(u8(ttl > 0 and string.format('ч. - потом карта проверяется заново', ttl) or 'ч. (0 = бессрочно)'))

    Draw.ImproveRowLabel('Повторов на карту:', labelW)
    imgui.PushItemWidth(-1)
    local _retries = imgui.new.int(tonumber(settings.improve.probeRetries) or 2)
    if imgui.SliderInt('##probeRetries', _retries, 0, 5, u8'%d') then
        settings.improve.probeRetries = math.maxEx(0, _retries[0])
        Storage.SaveSettings()
    end
    imgui.PopItemWidth()
    imgui.TextDisabled(u8'Сколько раз повторить, если карта не открылась при проверке уровня.')

    local canForget = not improve.cef.probing and not improve.isOn
    if canForget then
        if Draw.ConfirmButton('confirmForget', 'Забыть запомненные уровни', 'Точно забыть? Нажмите ещё раз', imgui.ImVec2(-1, UI.Scale(26))) then
            Improve.CardCacheClear(0)
            Improve.ForgetPacketLevels()
            for _, c in ipairs(improve.cef.cards or {}) do
                c.levelKnown = false
                c.probeFailed = false
                c.level = 0
            end
            improve.cef.probed = false
            Improve.SyncVideoCardsFromCef()
            Improve.Say('Запомненные уровни видеокарт очищены.')
        end
    else
        imgui.ButtonClickable(false, u8'Забыть запомненные уровни', imgui.ImVec2(-1, UI.Scale(26)))
    end

    imgui.Spacing()

    -- ---------- Тонкая настройка ----------
    if imgui.CollapsingHeader(u8'Задержки и таймауты') then
        imgui.TextDisabled(u8'Менять стоит, только если заточка спотыкается: окно не открывается\nили результат не успевает прийти. Те же настройки есть в "Настройки -> Задержки".')
        imgui.Spacing()
        Draw.ImproveDelaySettings()
    end

    imgui.EndChild()
end

-- ---------- Логи заточки ----------

function Improve.EmptyStats()
    return { sessions = 0, attempts = 0, success = 0, fail = 0, oilsUsed = 0, spent = 0, byLevel = {}, time = 0 }
end

-- Сумма статистики за последние N дней (0 = за всё время)
function Improve.StatsForPeriod(days)
    local store = Improve.GetStatsStore()
    if not store then
        local e = Improve.EmptyStats()
        Improve.EnsureLevelStats(e)
        return e
    end
    if days == 0 then
        local total = store.total or Improve.EmptyStats()
        Improve.EnsureLevelStats(total)
        return total
    end

    local sum = Improve.EmptyStats()
    Improve.EnsureLevelStats(sum)
    local fromKey = os.date('%Y-%m-%d', os.time() - (days - 1) * 86400)
    for key, day in pairs(store.days or {}) do
        if key >= fromKey and type(day) == 'table' then
            for _, f in ipairs({ 'sessions', 'attempts', 'success', 'fail', 'oilsUsed', 'spent', 'time' }) do
                sum[f] = sum[f] + (tonumber(day[f]) or 0)
            end
            for lvl = 1, 9 do
                local src = (day.byLevel or {})[lvl] or {}
                local dst = sum.byLevel[lvl]
                dst.attempts = (dst.attempts or 0) + (src.attempts or 0)
                dst.success  = (dst.success or 0) + (src.success or 0)
                dst.fail     = (dst.fail or 0) + (src.fail or 0)
                dst.spent    = (dst.spent or 0) + (src.spent or 0)
            end
        end
    end
    return sum
end

-- Шанс в процентах строкой (для текста imgui знак процента удвоен)
function Improve.ChanceText(success, attempts)
    if (attempts or 0) <= 0 then return '-' end
    return string.format('%.1f%%%%', success * 100.0 / attempts)
end

function Draw.ImproveLogsSummary()
    improve.ui = improve.ui or {}
    local periods = { { 'Сегодня', 1 }, { '7 дней', 7 }, { '30 дней', 30 }, { 'Всё время', 0 } }
    local cur = improve.ui.logsPeriod or 1
    local picked = Draw.ImproveSegment('imp_logs_period', { periods[1][1], periods[2][1], periods[3][1], periods[4][1] }, cur, false)
    if picked then improve.ui.logsPeriod = picked; cur = picked end

    local st = Improve.StatsForPeriod(periods[cur][2])
    local att, ok = st.attempts or 0, st.success or 0

    imgui.Spacing()
    imgui.Columns(4, 'imp_logs_tiles', false)
        imgui.TextDisabled(u8'Попыток')
        imgui.Text(u8(string.format('%d за %d сес.', att, st.sessions or 0)))
    imgui.NextColumn()
        imgui.TextDisabled(u8'Успехов')
        imgui.TextColored(UI.Vec4('okColor'), u8(string.format('%d (%s)', ok, Improve.ChanceText(ok, att))))
    imgui.NextColumn()
        imgui.TextDisabled(u8'Смазки / денег')
        imgui.Text(u8(string.format('%d / $%s', st.oilsUsed or 0, Util.GetCommaValue(math.floor(tonumber(st.spent) or 0)))))
    imgui.NextColumn()
        imgui.TextDisabled(u8'Время')
        imgui.Text(u8(Improve.FormatDuration(st.time or 0)))
    imgui.Columns(1)

    if ok > 0 and (st.spent or 0) > 0 then
        imgui.TextDisabled(u8(string.format('В среднем один поднятый уровень стоил $%s и %d смазки.',
            Util.GetCommaValue(math.floor(st.spent / ok)), math.floor((st.oilsUsed or 0) / ok + 0.5))))
    end

    imgui.Spacing()
    Draw.SectionTitle('По уровням')
    if att == 0 then
        imgui.TextDisabled(u8'За этот период попыток не было.')
        return
    end

    imgui.Columns(6, 'imp_logs_levels', false)
    for _, h in ipairs({ 'Переход', 'Попыток', 'Успехов', 'Шанс', 'Потрачено', 'Цена уровня' }) do
        imgui.TextDisabled(u8(h))
        imgui.NextColumn()
    end
    for lvl = 1, 9 do
        local row = st.byLevel[lvl] or {}
        local a, s = row.attempts or 0, row.success or 0
        if a > 0 then
            imgui.Text(u8(string.format('%d -> %d', lvl, lvl + 1))); imgui.NextColumn()
            imgui.Text(tostring(a)); imgui.NextColumn()
            imgui.Text(tostring(s)); imgui.NextColumn()
            local chance = s * 100.0 / a
            local col = chance >= 50 and UI.Vec4('okColor') or (chance >= 25 and UI.Vec4('warnColor') or UI.Vec4('badColor'))
            imgui.TextColored(col, Improve.ChanceText(s, a)); imgui.NextColumn()
            imgui.Text('$' .. Util.GetCommaValue(math.floor(tonumber(row.spent) or 0))); imgui.NextColumn()
            imgui.Text(s > 0 and ('$' .. Util.GetCommaValue(math.floor((row.spent or 0) / s))) or '-'); imgui.NextColumn()
        end
    end
    imgui.Columns(1)
    imgui.TextDisabled(u8'Цена уровня = сколько в среднем ушло денег на один успешный переход.')

    imgui.Spacing()
    if Draw.ConfirmButton('confirmResetStats', 'Сбросить всю статистику', 'Точно сбросить? Нажмите ещё раз', imgui.ImVec2(UI.Scale(240), 0)) then
        improve.statsStore = { days = {}, total = Improve.EmptyStats() }
        Improve.EnsureLevelStats(improve.statsStore.total)
        Improve.SaveStatsStore()
        Improve.Say('Статистика заточки сброшена.')
    end
end

function Draw.ImproveLogsDays()
    local store = Improve.GetStatsStore()
    local keys = {}
    for key, day in pairs(store and store.days or {}) do
        if type(day) == 'table' and (tonumber(day.attempts) or 0) > 0 then table.insert(keys, key) end
    end
    table.sort(keys, function(a, b) return a > b end)

    if #keys == 0 then
        imgui.TextDisabled(u8'Дней с заточкой пока нет.')
        return
    end

    imgui.BeginChild('imp_logs_days', imgui.ImVec2(-1, -1), true)
    imgui.ScrollMouse()
    imgui.Columns(7, 'imp_logs_days_cols', false)
    for _, h in ipairs({ 'Дата', 'Сессий', 'Попыток', 'Успехов', 'Смазки', 'Потрачено', 'Время' }) do
        imgui.TextDisabled(u8(h))
        imgui.NextColumn()
    end
    for _, key in ipairs(keys) do
        local d = store.days[key]
        local y, m, dd = key:match('^(%d+)-(%d+)-(%d+)$')
        imgui.Text(y and string.format('%s.%s.%s', dd, m, y) or key); imgui.NextColumn()
        imgui.Text(tostring(d.sessions or 0)); imgui.NextColumn()
        imgui.Text(tostring(d.attempts or 0)); imgui.NextColumn()
        imgui.TextColored(UI.Vec4('okColor'), string.format('%d (%s)', d.success or 0, Improve.ChanceText(d.success or 0, d.attempts or 0))); imgui.NextColumn()
        imgui.Text(tostring(d.oilsUsed or 0)); imgui.NextColumn()
        imgui.Text('$' .. Util.GetCommaValue(math.floor(tonumber(d.spent) or 0))); imgui.NextColumn()
        imgui.Text(u8(Improve.FormatDuration(d.time or 0))); imgui.NextColumn()
    end
    imgui.Columns(1)
    imgui.EndChild()
end

function Draw.ImproveLogsFeed()
    improve.ui = improve.ui or {}
    local filters = { 'Все', 'Успехи', 'Неудачи и ошибки', 'Служебные' }
    local picked = Draw.ImproveSegment('imp_logs_filter', filters, improve.ui.logsFilter or 1, false)
    if picked then improve.ui.logsFilter = picked end
    local filter = improve.ui.logsFilter or 1

    local autoScrollPtr = imgui.new.bool(improve.logs.autoScroll ~= false)
    if imgui.Checkbox(u8'Прокручивать к новым', autoScrollPtr) then
        improve.logs.autoScroll = autoScrollPtr[0]
    end
    imgui.SameLine()
    if imgui.RightButton(u8'Очистить ленту##imp_feed_clear') then
        improve.logs.items = {}
    end

    local colors = { SUCCESS = UI.Vec4('okColor'), WARN = UI.Vec4('warnColor'), ERROR = UI.Vec4('badColor') }

    imgui.BeginChild('improve_logs_scroll', imgui.ImVec2(-1, -1), true)
        imgui.ScrollMouse()
        local shown = 0
        for _, entry in ipairs(improve.logs.items or {}) do
            local etype = entry.type or 'INFO'
            local pass = filter == 1
                or (filter == 2 and etype == 'SUCCESS')
                or (filter == 3 and (etype == 'WARN' or etype == 'ERROR'))
                or (filter == 4 and etype == 'INFO')
            if pass then
                shown = shown + 1
                local ts = tostring(entry.ts or '')
                imgui.TextDisabled(ts:match('(%d+:%d+:%d+)$') or ts)
                if imgui.IsItemHovered() then imgui.SetTooltip(ts) end
                imgui.SameLine()
                local col = colors[etype]
                if col then
                    imgui.TextColored(col, u8(tostring(entry.text or '')))
                else
                    imgui.Text(u8(tostring(entry.text or '')))
                end
            end
        end
        if shown == 0 then
            imgui.TextDisabled(u8'Записей нет. Полный журнал по дням лежит в config/MMT CFGs/logs.')
        end

        if improve.logs.autoScroll ~= false then
            imgui.SetScrollHereY(1.0)
        end
    imgui.EndChild()
end

function Draw.ImproveLogsTab()
    if imgui.BeginTabBar('ImproveLogsSegments') then
        if imgui.BeginTabItem(u8'Статистика') then
            Draw.ImproveLogsSummary()
            imgui.EndTabItem()
        end
        if imgui.BeginTabItem(u8'По дням') then
            Draw.ImproveLogsDays()
            imgui.EndTabItem()
        end
        if imgui.BeginTabItem(u8'Лента') then
            Draw.ImproveLogsFeed()
            imgui.EndTabItem()
        end
        imgui.EndTabBar()
    end
end


-- Поле ввода настройки уведомлений. Буфер живёт между кадрами, иначе ввод сбрасывается
function Draw.TgInput(id, field, flags)
    local tg = collectReminder.tg
    local buf = tg.buf[field]
    if not buf then
        buf = new.char[256]()
        buf_set(buf, u8(tostring(settings.notifications[field] or '')))
        tg.buf[field] = buf
    end
    imgui.PushItemWidth(-1)
    if imgui.InputText(id, buf, 256, flags or 0) then
        settings.notifications[field] = Collect.TgTrim(u8:decode(ffi.string(buf)))
        Storage.SaveSettings()
    end
    imgui.PopItemWidth()
end

-- Таблица событий: галочки "В игре" и "Telegram", интервал и когда придёт напоминание
function Draw.ReminderTable()
    local cfg = settings.notifications
    Draw.SectionTitle("Напоминания о сборе")

    local x0 = imgui.GetCursorPosX()
    local colGame = x0 + UI.Scale(130)
    local colTg = colGame + UI.Scale(70)
    local colMin = colTg + UI.Scale(80)
    local colStatus = colMin + UI.Scale(80)

    imgui.TextDisabled(u8"Событие")
    imgui.SameLine(colGame)
    imgui.TextDisabled(u8"В игре")
    imgui.SameLine(colTg)
    imgui.TextDisabled(u8"Telegram")
    imgui.SameLine(colMin)
    imgui.TextDisabled(u8"Через, мин")
    imgui.SameLine(colStatus)
    imgui.TextDisabled(u8"Когда")

    for _, kind in ipairs(Collect.TG_KINDS) do
        local id = kind.id
        imgui.AlignTextToFramePadding()
        imgui.Text(u8(kind.short))

        imgui.SameLine(colGame)
        if imgui.Checkbox("##reminderGame" .. id, new.bool(cfg.game[id] == true)) then
            cfg.game[id] = not cfg.game[id]
            Storage.SaveSettings()
        end

        imgui.SameLine(colTg)
        if imgui.Checkbox("##reminderTg" .. id, new.bool(cfg.tg[id] == true)) then
            cfg.tg[id] = not cfg.tg[id]
            Storage.SaveSettings()
        end

        local where = Collect.REMINDER_MINUTES[id]
        imgui.SameLine(colMin)
        imgui.PushItemWidth(UI.Scale(70))
        local ptr = new.int(tonumber(settings[where[1]][where[2]]) or 0)
        if imgui.InputInt("##reminderMin" .. id, ptr, 0, 0) then
            settings[where[1]][where[2]] = math.maxEx(0, ptr[0])
            Storage.SaveSettings()
        end
        imgui.PopItemWidth()

        imgui.SameLine(colStatus)
        imgui.TextDisabled(u8(Collect.TgReminderStatus(id)))
    end

    imgui.TextDisabled(u8"Напоминание приходит через заданное число минут после последнего сбора, одно на каждый сбор.\n0 минут - напоминание выключено. Интервал крипты общий с вкладкой \"Видеокарты\".")

    local problem = Collect.TgConfigProblem()
    local anyTg = false
    for _, kind in ipairs(Collect.TG_KINDS) do
        if cfg.tg[kind.id] then anyTg = true end
    end
    if anyTg and problem then
        imgui.TextColored(UI.Vec4('warnColor'), u8("Telegram не настроен: " .. problem .. " (ниже)"))
    end
end

-- Состояние менеджера уведомлений: без него напоминания в игре приходят сообщением в чат
function Draw.NotifyManagerBlock()
    local notifyState = Collect.GetNotifySystemState()
    if not notifyState.ready then
        imgui.TextDisabled(u8(notifyState.message))
        if collectReminder.managerEnsurePending then
            imgui.TextDisabled(u8"Подготовка менеджера уведомлений...")
        else
            if imgui.Button(u8(Collect.GetNotifyInstallButtonText(notifyState)), imgui.ImVec2(-1, 0)) then
                Collect.EnsureNotificationManager()
            end
            if not notifyState.available then
                if collectReminder.managerDownloadPending then
                    imgui.TextDisabled(u8"Скачивание менеджера уведомлений и библиотеки...")
                elseif imgui.Button(u8"Скачать менеджер и библиотеку", imgui.ImVec2(-1, 0)) then
                    Collect.DownloadNotificationSystem()
                end
            end
        end
        imgui.TextDisabled(u8("GitHub: " .. NOTIFY_MANAGER_REPO_URL))
        if collectReminder.managerStatusMessage ~= "" then
            imgui.TextDisabled(u8(collectReminder.managerStatusMessage))
        end
    end
    if notifyState.ready then
        imgui.TextDisabled(u8"Менеджер уведомлений работает: напоминания появятся всплывающим окном.")
    else
        imgui.TextDisabled(u8"Пока менеджер не установлен, напоминания в игре приходят сообщением в чат.")
    end
end

function Draw.SettingsNotifications()
    local cfg = settings.notifications
    local tg = collectReminder.tg
    imgui.Spacing()

    Draw.ReminderTable()

    imgui.Spacing()
    Draw.SectionTitle("Telegram")
    imgui.Text(u8"Через какого бота:")
    local half = (imgui.GetContentRegionAvail().x - imgui.GetStyle().ItemSpacing.x) / 2
    local own = tonumber(cfg.methodBot) ~= 2
    if (own and imgui.AccentButton or imgui.Button)(u8"Свой бот", imgui.ImVec2(half, 0)) then
        cfg.methodBot = 1
        Storage.SaveSettings()
    end
    imgui.SameLine()
    if ((not own) and imgui.AccentButton or imgui.Button)(u8"Бот MCR Notification", imgui.ImVec2(-1, 0)) then
        cfg.methodBot = 2
        Storage.SaveSettings()
    end

    imgui.Spacing()
    if own then
        imgui.Text(u8"Токен бота:")
        Draw.TgInput("##tgToken", "botToken", imgui.InputTextFlags.Password)
        imgui.Text(u8"ID чата:")
        Draw.TgInput("##tgChatId", "chatId")
        imgui.TextDisabled(u8"Бота создайте в @BotFather, свой ID узнайте в @getmyid_bot и напишите своему боту /start.")
        if imgui.Button(u8"Инструкция по созданию бота", imgui.ImVec2(-1, 0)) then
            Util.OpenUrl("https://docs.arz-mcr.ru/create-tg-bot/")
        end
    else
        imgui.Text(u8"Ваш ID в боте MCR Notification:")
        Draw.TgInput("##tgMcrChatId", "mcrChatId")
        if imgui.Button(u8"Открыть @MCR_NotificationBot", imgui.ImVec2(-1, 0)) then
            Util.OpenUrl("https://t.me/MCR_NotificationBot")
        end
        imgui.TextDisabled(u8"В боте отправьте /start и следуйте инструкции - бот пришлёт ваш ID.")

        imgui.Spacing()
        Draw.McrKeyBlock()
    end

    local problem = Collect.TgConfigProblem()
    if problem then
        imgui.TextColored(UI.Vec4('badColor'), u8("Не заполнено: " .. problem))
    end

    if imgui.ButtonClickable(problem == nil, u8"Тестовое сообщение", imgui.ImVec2(-1, 0)) then
        local ok, err = Collect.TgSend("[MMT] Тестовое сообщение. Уведомления работают.", 'test')
        tg.lastResult = ok and (os.date('%H:%M:%S') .. " - отправляю...") or ("не отправлено: " .. tostring(err))
    end
    if tg.initError then
        imgui.TextColored(UI.Vec4('badColor'), u8("Отправка недоступна: " .. tg.initError))
    elseif tg.lastResult ~= '' then
        imgui.TextDisabled(u8(tg.lastResult))
    end

    imgui.Spacing()
    Draw.SectionTitle("Уведомления в игре")
    Draw.NotifyManagerBlock()
end

-- Ключ MCR: общий для бота MCR Notification и облачного лога
function Draw.McrKeyBlock()
    local cfg = settings.notifications
    local tg = collectReminder.tg
    local key, source = Collect.TgGetKey()
    if key ~= '' and not tg.keyEdit then
        imgui.Text(u8(string.format("Ключ MCR: %s (%s)", Collect.TgMaskKey(key), source)))
        if source == 'MMT' then
            if imgui.Button(u8"Очистить ключ##mcrKey", imgui.ImVec2(-1, 0)) then
                cfg.mcrKey = ''
                tg.keyCheckedAt = -1000
                Storage.SaveSettings()
            end
        elseif imgui.Button(u8"Указать другой ключ##mcrKey", imgui.ImVec2(-1, 0)) then
            tg.keyEdit = true
        end
        return
    end

    imgui.Text(u8"Ключ MCR:")
    imgui.TextDisabled(u8"Ключ не найден в MCR ПК и MLoader - введите его и нажмите Enter.")
    local buf = tg.buf.mcrKey
    if not buf then
        buf = new.char[64]()
        tg.buf.mcrKey = buf
    end
    imgui.PushItemWidth(-1)
    if imgui.InputText("##tgMcrKey", buf, 64, imgui.InputTextFlags.Password + imgui.InputTextFlags.EnterReturnsTrue) then
        cfg.mcrKey = Collect.TgTrim(ffi.string(buf))
        buf_set(buf, '')
        tg.keyEdit = false
        Storage.SaveSettings()
    end
    imgui.PopItemWidth()
    if tg.keyEdit and imgui.Button(u8"Отмена##mcrKey", imgui.ImVec2(-1, 0)) then
        buf_set(buf, '')
        tg.keyEdit = false
    end
end

-- Настройка отправки сборов в облако (вкладка "Основное")
function Draw.CloudSettings()
    local sync = collectReminder.sync
    Draw.SectionTitle("Облачный лог сборов")
    imgui.TextDisabled(u8"Сборы крипты, теплиц и майнера уходят на сервер MCR по ключу.\nЛог можно смотреть с другого устройства; в разделе \"Логи\" - кнопка \"Облако\".")

    if imgui.Checkbox(u8"Отправлять сборы на сервер", new.bool(settings.cloud.sendCollects)) then
        settings.cloud.sendCollects = not settings.cloud.sendCollects
        Storage.SaveSettings()
    end

    Draw.McrKeyBlock()

    local queued = #Collect.SyncQueue()
    local parts = { string.format("В очереди: %d", queued) }
    if sync.lastOkAt > 0 then
        table.insert(parts, "последняя отправка " .. os.date('%H:%M:%S', sync.lastOkAt))
    end
    imgui.TextDisabled(u8(table.concat(parts, ", ")))
    if sync.lastError ~= '' and queued > 0 then
        imgui.TextColored(UI.Vec4('warnColor'), u8("Не отправлено: " .. sync.lastError))
        if os.time() < sync.pausedUntil and imgui.Button(u8"Отправить сейчас##cloudRetry", imgui.ImVec2(-1, 0)) then
            sync.pausedUntil = 0
            sync.failCount = 0
        end
    end
end

-- Переключатель "Локальный / Облако" над логами
function Draw.LogsSourceSwitch()
    local w = (imgui.GetWindowContentRegionWidth() - imgui.GetStyle().ItemSpacing.x) / 2
    local isCloud = settings.cloud.logsSource == 'cloud'
    if imgui.ButtonClickable(isCloud, u8"Локальный лог##logsSrcLocal", imgui.ImVec2(w, 0)) then
        settings.cloud.logsSource = 'local'
        Storage.SaveSettings()
    end
    imgui.SameLine()
    if imgui.ButtonClickable(not isCloud, u8"Облако##logsSrcCloud", imgui.ImVec2(-1, 0)) then
        settings.cloud.logsSource = 'cloud'
        Storage.SaveSettings()
    end
    imgui.Separator()
    return settings.cloud.logsSource == 'cloud'
end

function Draw.CloudAmount(v)
    local n = tonumber(Collect.JsonValue(v)) or 0
    local s = string.format('%.3f', n)
    s = s:gsub('0+$', '')
    s = s:gsub('%.$', '')
    return s
end

-- Итог дня по выбранному виду сбора (сумма по всем аккаунтам)
function Draw.CloudDayLabel(day, kind)
    local collects, btc, asc, added, deposited = 0, 0, 0, 0, 0
    for _, acc in ipairs(day.accounts or {}) do
        local bank = (kind == 'crypto') and Collect.JsonValue(acc.bank) or nil
        if bank then
            deposited = deposited + (tonumber(Collect.JsonValue(bank.deposited)) or 0)
        end
        local sec = Collect.JsonValue(acc[kind])
        if sec then
            collects = collects + (tonumber(sec.collects) or 0)
            if kind == 'crypto' then
                local c = Collect.JsonValue(sec.collected) or {}
                btc = btc + (tonumber(Collect.JsonValue(c.BTC)) or 0)
                asc = asc + (tonumber(Collect.JsonValue(c.ASC)) or 0)
            else
                added = added + (tonumber(Collect.JsonValue(sec.water_added) or Collect.JsonValue(sec.charge_added) or Collect.JsonValue(sec.spent)) or 0)
            end
        end
    end
    if collects == 0 and deposited <= 0 then return nil end
    if kind == 'crypto' then
        local label = string.format('%s | BTC: %s | ASC: %s | сборов: %d', tostring(day.date), Draw.CloudAmount(btc), Draw.CloudAmount(asc), collects)
        if deposited > 0 then
            label = label .. ' | банк: ' .. Draw.CloudMoney(deposited)
        end
        return label
    end
    if kind == 'mirage' then
        return string.format('%s | сборов: %d | потрачено: %s', tostring(day.date), collects, Draw.CloudMoney(added))
    end
    local addedLabel = (kind == 'greenhouse') and 'воды' or 'зарядки'
    return string.format('%s | сборов: %d | %s залито: %d', tostring(day.date), collects, addedLabel, added)
end

function Draw.CloudCrypto(sec)
    local c = Collect.JsonValue(sec.collected) or {}
    imgui.Text(u8(string.format('BTC: %s | ASC: %s', Draw.CloudAmount(c.BTC), Draw.CloudAmount(c.ASC))))
    local sh = Collect.JsonValue(sec.shelves) or {}
    imgui.TextDisabled(u8(string.format('Полок: %d, с выплатой: %d, включено карт: %d',
        tonumber(sh.visited) or 0, tonumber(sh.collected) or 0, tonumber(sh.cards_enabled) or 0)))
    local l = Collect.JsonValue(sec.liquid_used) or {}
    local lb, ls, la = tonumber(l.btc) or 0, tonumber(l.super_btc) or 0, tonumber(l.asc) or 0
    if lb + ls + la > 0 then
        imgui.TextDisabled(u8(string.format('Охлаждайка: BTC %d, супер %d, ASC %d', lb, ls, la)))
    end
    for hi, house in ipairs(Collect.JsonValue(sec.houses) or {}) do
        local hc = Collect.JsonValue(house.collected) or {}
        local label = string.format('Дом №%s | BTC: %s | ASC: %s | сборов: %d',
            tostring(Collect.JsonValue(house.house_id) or '?'), Draw.CloudAmount(hc.BTC), Draw.CloudAmount(hc.ASC), tonumber(house.collects) or 0)
        local interrupted = tonumber(house.interrupted) or 0
        if interrupted > 0 then
            label = label .. string.format(' (прервано: %d)', interrupted)
        end
        imgui.BulletText(u8(label))
    end
end

function Draw.CloudMoney(v)
    local digits = tostring(math.floor(tonumber(Collect.JsonValue(v)) or 0))
    local grouped = digits:reverse():gsub('(%d%d%d)', '%1.')
    grouped = grouped:reverse():gsub('^%.', '')
    return '$' .. grouped
end

function Draw.CloudBank(bank)
    imgui.Text(u8(string.format('Пополнено банков: %s, операций: %d',
        Draw.CloudMoney(bank.deposited), tonumber(Collect.JsonValue(bank.operations)) or 0)))
    for _, house in ipairs(Collect.JsonValue(bank.houses) or {}) do
        imgui.BulletText(u8(string.format('Дом №%s | %s',
            tostring(Collect.JsonValue(house.house_id) or '?'), Draw.CloudMoney(house.deposited))))
    end
end

function Draw.CloudResource(sec, kind)
    if kind == 'mirage' then
        imgui.Text(u8('Потрачено: ' .. Draw.CloudMoney(sec.spent)))
    else
        local added = tonumber(Collect.JsonValue(sec.water_added) or Collect.JsonValue(sec.charge_added)) or 0
        imgui.Text(u8(string.format('%s залито: %d', (kind == 'greenhouse') and 'Воды' or 'Зарядки', added)))
    end
    local items = Collect.JsonValue(sec.items) or {}
    if #items == 0 then
        imgui.TextDisabled(u8'Ресурсы не собирались.')
    end
    for _, item in ipairs(items) do
        -- названия приходят в UTF-8, их отдаём imgui как есть
        imgui.BulletText('%s', tostring(Collect.JsonValue(item.name) or '?') .. u8(string.format(' - %d', tonumber(item.amount) or 0)))
    end
end

-- kind = 'crypto' | 'greenhouse' | 'miner'
function Draw.CloudLogs(kind)
    local st = collectReminder.sync.summary
    local period = tonumber(settings.cloud.period) or 7
    local periodKey = tostring(period)

    -- при первом открытии и смене периода подтягиваем данные сами (один раз, чтобы не долбить сервер)
    if not st.loading and st.key ~= periodKey and st.autoKey ~= periodKey then
        st.autoKey = periodKey
        Collect.CloudFetchSummary(period)
    end

    if imgui.ButtonClickable(not st.loading, u8"Обновить##cloudRefresh") then
        Collect.CloudFetchSummary(period)
    end
    imgui.SameLine()
    if st.loading then
        imgui.TextDisabled(u8"Загружаю...")
    elseif st.error ~= '' then
        imgui.TextColored(UI.Vec4('badColor'), u8(st.error))
    elseif st.at > 0 then
        imgui.TextDisabled(u8("Обновлено в " .. os.date('%H:%M:%S', st.at)))
    end

    local periodOptions = { 1, 3, 7, 14, 30, 93 }
    local periodW = (imgui.GetWindowContentRegionWidth() - imgui.GetStyle().ItemSpacing.x * (#periodOptions - 1)) / #periodOptions
    for i, days in ipairs(periodOptions) do
        if i > 1 then imgui.SameLine() end
        local label = (days == 1) and 'Сегодня' or (days .. ' дн.')
        if imgui.ButtonClickable(period ~= days, u8(label) .. "##cloudPeriod" .. days, imgui.ImVec2(i == #periodOptions and -1 or periodW, 0)) then
            settings.cloud.period = days
            Storage.SaveSettings()
        end
    end
    imgui.Separator()

    imgui.BeginChild('cloud_logs_' .. kind, imgui.ImVec2(-1, -1), true)
    imgui.ScrollMouse()
    local data = st.data
    if not data or st.key ~= periodKey then
        imgui.TextDisabled(u8(st.loading and "Загружаю лог из облака..." or "Нет данных. Нажмите \"Обновить\"."))
        imgui.EndChild()
        return
    end

    local shown = 0
    for di, day in ipairs(Collect.JsonValue(data.days) or {}) do
        local label = Draw.CloudDayLabel(day, kind)
        if label then
            shown = shown + 1
            if imgui.TreeNodeStr(u8(label) .. '##cloudDay' .. kind .. di) then
                for ai, acc in ipairs(day.accounts or {}) do
                    local sec = Collect.JsonValue(acc[kind])
                    local bank = (kind == 'crypto') and Collect.JsonValue(acc.bank) or nil
                    if sec or bank then
                        local server = Collect.JsonValue(acc.server) or {}
                        local serverName = Collect.JsonValue(server.title) or Collect.JsonValue(server.ip) or '?'
                        local head = tostring(Collect.JsonValue(acc.nick) or '?') .. ' | ' .. tostring(serverName)
                        if sec then
                            head = head .. u8(string.format(' | сборов: %d', tonumber(sec.collects) or 0))
                            local interrupted = tonumber(sec.interrupted) or 0
                            if interrupted > 0 then
                                head = head .. u8(string.format(' (прервано: %d)', interrupted))
                            end
                        end
                        if imgui.TreeNodeStr(head .. '##cloudAcc' .. kind .. di .. '_' .. ai) then
                            if sec and kind == 'crypto' then
                                Draw.CloudCrypto(sec)
                            elseif sec then
                                Draw.CloudResource(sec, kind)
                            end
                            if bank then
                                Draw.CloudBank(bank)
                            end
                            imgui.TreePop()
                        end
                    end
                end
                imgui.TreePop()
            end
        end
    end
    if shown == 0 then
        imgui.TextDisabled(u8"За этот период сборов в облаке нет.")
    end
    imgui.EndChild()
end

-- Настройки майнинга крипты: сбор, заливка, напоминание, заточка
function Draw.CryptoSettings()
    imgui.Spacing()
    if imgui.Checkbox(u8"Скрыть текст получения крипты в чате", new.bool(settings.main.hideMessagesCollect)) then
        settings.main.hideMessagesCollect = not settings.main.hideMessagesCollect 
        Storage.SaveSettings()
    end

    if imgui.Checkbox(u8"Общая сводка в чат после сбора", new.bool(settings.main.showCollectSummary)) then
        settings.main.showCollectSummary = not settings.main.showCollectSummary
        Storage.SaveSettings()
    end
    imgui.TextDisabled(u8"Уровни видеокарт, суммы по домам, время и детали сбора")

    if imgui.Checkbox(u8"Закрывать окно скрипта после /mmtflash", new.bool(settings.main.hideWindowOnFlashCmd)) then
        settings.main.hideWindowOnFlashCmd = not settings.main.hideWindowOnFlashCmd
        Storage.SaveSettings()
    end
    imgui.TextDisabled(u8"Окно не будет всплывать на диалогах дома и видеокарт во время такого сбора")

    if imgui.Checkbox(u8"Проверять смазку при старте заточки", new.bool(settings.improve.checkOilsOnStart)) then
        settings.improve.checkOilsOnStart = not settings.improve.checkOilsOnStart
        Storage.SaveSettings()
    end
    imgui.TextDisabled(u8"Если выключено, заточка стартует без принудительной проверки")

    imgui.Text(u8"Напомнить, если не было сбора:")
    imgui.PushItemWidth(UI.Scale(120))
    local collectNotifyMinutesPtr = imgui.new.int(tonumber(settings.main.collectNotifyMinutes) or 0)
    if imgui.InputInt("##collectNotifyMinutes", collectNotifyMinutesPtr, 0, 0) then
        settings.main.collectNotifyMinutes = math.maxEx(0, collectNotifyMinutesPtr[0])
        Storage.SaveSettings()
    end
    imgui.PopItemWidth()
    imgui.SameLine()
    imgui.TextDisabled(u8"мин (0 = выкл)")
    imgui.TextDisabled(u8"Куда присылать напоминания - в игру или в Telegram - вкладка \"Уведомления\".")

    imgui.Spacing()
    imgui.Separator()
    imgui.Spacing()

    imgui.Text(u8(string.format("Заливать при %.0f%%%% или ниже:", settings.main.fillFrom)))
    imgui.PushItemWidth(-1)
    local _fillFrom = new.float(settings.main.fillFrom)
    if imgui.SliderFloat("##fillFrom", _fillFrom, 0, 99, "%.0f%%") then
        settings.main.fillFrom = Util.Round(_fillFrom[0], 2)
        Storage.SaveSettings()
    end
    imgui.PopItemWidth()

    imgui.Text(u8(string.format("Подсвечивать дом красным от %.0f крипты:", settings.main.maxCollectAlert)))
    imgui.PushItemWidth(-1)
    local _maxCollectAlert = new.float(tonumber(settings.main.maxCollectAlert) or 11.0)
    if imgui.SliderFloat("##maxCollectAlert", _maxCollectAlert, 1, 30, "%.0f") then
        settings.main.maxCollectAlert = Util.Round(_maxCollectAlert[0], 2)
        Storage.SaveSettings()
    end
    imgui.PopItemWidth()
    imgui.TextDisabled(u8"Столбец \"Мкс. крипты\" в списке домов: выше порога - хранилище пора разгружать")
end

function Draw.Settings()
    -- Верхняя панель статуса (если включена)
    if settings.main.showStatusPanel then
        imgui.BeginChild("status_panel", imgui.ImVec2(-1, 60), true)
        imgui.Text(u8(string.format("Работаю: %s | Заливаю: %s | Собираю: %s | Вкл/выкл: %s", 
            stateCrypto.work, processes.fill, processes.take, (processes.on or processes.off))))

        if stateCrypto.work then
            imgui.Spacing()
            if imgui.Button(u8"Отменить процесс", imgui.ImVec2(-1, 0)) then
                Interacting.Deactivate()
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
                Storage.SaveSettings()
            end

            if imgui.Checkbox(u8"Закрывать скрипт на ESC", new.bool(settings.main.closeOnESC)) then
                settings.main.closeOnESC = not settings.main.closeOnESC 
                Storage.SaveSettings()
            end

            if imgui.Checkbox(u8"Перемещаться стрелочками в списке", new.bool(settings.main.arrowsMove)) then
                settings.main.arrowsMove = not settings.main.arrowsMove 
                Storage.SaveSettings()
            end

            if imgui.Checkbox(u8"Отображать панель статуса (дебаг информация)", new.bool(settings.main.showStatusPanel)) then
                settings.main.showStatusPanel = not settings.main.showStatusPanel 
                Storage.SaveSettings()
            end
            imgui.TextDisabled(u8"Отображать информацию о работающих процессах вверху окна")

            imgui.Spacing()
            Draw.CloudSettings()

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
                Storage.SaveSettings()
            end
            imgui.SameLine()
            imgui.TextDisabled(u8"(/час)")

            if imgui.Checkbox(u8"Показывать доход за 24 часа", imgui.new.bool(inc.showPer24h)) then
                inc.showPer24h = not inc.showPer24h
                Storage.SaveSettings()
            end
            imgui.SameLine()
            imgui.TextDisabled(u8"(/24ч)")

            if imgui.Checkbox(u8"Показывать доход за цикл", imgui.new.bool(inc.showPerCycle)) then
                inc.showPerCycle = not inc.showPerCycle
                Storage.SaveSettings()
            end
            imgui.SameLine()
            imgui.TextDisabled(u8"(/цикл)")

            imgui.Spacing()
            imgui.Separator()
            imgui.Spacing()

            if imgui.Checkbox(u8"Показывать текущую прибыль", imgui.new.bool(inc.showTillThresholdProfit)) then
                inc.showTillThresholdProfit = not inc.showTillThresholdProfit
                Storage.SaveSettings()
            end

            if imgui.Checkbox(u8"Показывать время до доливки", imgui.new.bool(inc.showTillThresholdHours)) then
                inc.showTillThresholdHours = not inc.showTillThresholdHours
                Storage.SaveSettings()
            end

            imgui.Spacing()
            imgui.Separator()
            imgui.Spacing()

            imgui.TextWrapped(u8"Бонусы доходности по домам:")
            imgui.Spacing()
            imgui.Text(u8"Время в онлайне:")
            imgui.PushItemWidth(UI.Scale(120))
            local incomeOnlineHoursPtr = imgui.new.int(tonumber(inc.onlineHours) or 0)
            if imgui.InputInt("##income_online_hours_global", incomeOnlineHoursPtr, 0, 0) then
                inc.onlineHours = math.minEx(24, math.maxEx(0, incomeOnlineHoursPtr[0]))
                Storage.SaveSettings()
            end
            imgui.PopItemWidth()
            imgui.SameLine()
            imgui.TextDisabled(u8"ч (0-24)")
            imgui.TextDisabled(u8"Бонус от Время в онлайне применяется ко всем домам, даже если дома нет в списке ниже")
            imgui.Spacing()

            imgui.Text(u8"Номер дома:")
            imgui.PushItemWidth(UI.Scale(140))
            imgui.InputInt("##incomeHouseNumber", inputIncomeHouse, 0, 0)
            imgui.PopItemWidth()
            imgui.SameLine()

            if imgui.Button(u8"Добавить дом", imgui.ImVec2(UI.Scale(160), 0)) then
                local houseNumber = math.maxEx(0, inputIncomeHouse[0])
                if houseNumber >= 0 then
                    local houseKey = tostring(houseNumber)
                    if type(inc.houseBonuses[houseKey]) ~= "table" then
                        inc.houseBonuses[houseKey] = {
                            creativitySet = false,
                            customPercent = 0,
                        }
                        Storage.SaveSettings()
                    end
                    inputIncomeHouse[0] = 0
                end
            end
            imgui.TextDisabled(u8"Набор архитектора даёт +30%% для дома")

            imgui.Spacing()

            local houseKeys = GetSortedIncomeHouseBonusKeys()
            if #houseKeys == 0 then
                imgui.TextDisabled(u8"Список домов пуст. Добавьте дом выше.")
            else
                imgui.BeginChild("income_house_bonus_list", imgui.ImVec2(-1, UI.Scale(220)), true)
                imgui.ScrollMouse()

                local removedHouse = false
                for _, houseKey in ipairs(houseKeys) do
                    local houseConfig = NormalizeIncomeHouseBonusConfig(inc.houseBonuses[houseKey])
                    inc.houseBonuses[houseKey] = houseConfig
                    local totalBonus = CalcHouseIncomeBonusPercent(houseKey)

                    imgui.Separator()
                    imgui.Text(u8(string.format("Дом №%s | Итоговый бонус: +%.2f%%", houseKey, totalBonus)))

                    imgui.SameLine()
                    if imgui.RightButton(u8("Удалить##income_remove_" .. houseKey), imgui.ImVec2(UI.Scale(120), 0)) then
                        inc.houseBonuses[houseKey] = nil
                        Storage.SaveSettings()
                        removedHouse = true
                        break
                    end

                    local creativityPtr = imgui.new.bool(houseConfig.creativitySet == true)
                    if imgui.Checkbox(u8("Набор архитектора##income_creativity_" .. houseKey), creativityPtr) then
                        houseConfig.creativitySet = creativityPtr[0]
                        Storage.SaveSettings()
                    end

                    imgui.SameLine()
                    imgui.Text("\t|\t")
                    imgui.SameLine()

                    imgui.Text(u8"Свой процент:")
                    imgui.SameLine()
                    imgui.PushItemWidth(UI.Scale(120))
                    local customPercentPtr = imgui.new.int(tonumber(houseConfig.customPercent) or 0)
                    if imgui.InputInt("##income_custom_percent_" .. houseKey, customPercentPtr, 0, 0) then
                        houseConfig.customPercent = math.maxEx(0, customPercentPtr[0])
                        Storage.SaveSettings()
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
                Storage.SaveSettings()
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
                    Storage.SaveSettings()
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
                Storage.SaveSettings()
            end
            imgui.TextDisabled(u8"Максимальное время ожидания открытия диалога")

            imgui.Spacing()

            imgui.Text(u8"Интервал проверки:")
            local _waitInterval = new.int(settings.deley.waitInterval)
            if imgui.SliderInt("##waitInterval", _waitInterval, 1, 100, u8"%d мс") then
                settings.deley.waitInterval = _waitInterval[0]
                Storage.SaveSettings()
            end
            imgui.TextDisabled(u8"Частота проверки состояния (миллисекунды)")

            imgui.Spacing()

            imgui.Text(u8"Ожидание ответа от полок:")
            local _timeoutShelf = new.int(settings.deley.timeoutShelf)
            if imgui.SliderInt("##timeoutShelf", _timeoutShelf, 1, 30, u8"%d сек") then
                settings.deley.timeoutShelf = _timeoutShelf[0]
                Storage.SaveSettings()
            end
            imgui.TextDisabled(u8"Максимальное время ожидания ответа от полок")

            imgui.Spacing()

            imgui.Text(u8"Задержка перед ответом на диалог:")
            local _waitRun = new.int(settings.deley.waitRun)
            if imgui.SliderInt("##waitRun", _waitRun, 1, 100, u8"%d мс") then
                settings.deley.waitRun = _waitRun[0]
                Storage.SaveSettings()
            end
            imgui.TextDisabled(u8"Пауза перед отправкой ответа в диалог")

            imgui.Spacing()

            imgui.Text(u8"Повторов при зависшей полке:")
            local _shelfRetries = new.int(tonumber(settings.deley.shelfRetries) or 2)
            if imgui.SliderInt("##shelfRetries", _shelfRetries, 0, 5, u8"%d") then
                settings.deley.shelfRetries = _shelfRetries[0]
                Storage.SaveSettings()
            end
            imgui.TextDisabled(u8"Если сервер не ответил на открытие полки, скрипт закроет\nкарточку видеокарты, вернётся к списку и попробует снова")

            imgui.Text(u8"Повторов при зависшем доме:")
            local _houseRetries = new.int(tonumber(settings.deley.houseRetries) or 1)
            if imgui.SliderInt("##houseRetries", _houseRetries, 0, 3, u8"%d") then
                settings.deley.houseRetries = _houseRetries[0]
                Storage.SaveSettings()
            end
            imgui.TextDisabled(u8"Сколько раз перезайти в дом, если он не отработал целиком.\nПосле этого дом пропускается, а сбор идёт дальше")

            imgui.Spacing()
            imgui.Separator()
            imgui.Spacing()

            imgui.CenterText(u8"Для улучшения видеокарт")

            imgui.Spacing()

            Draw.ImproveDelaySettings()

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
            if imgui.Button(u8"Добавить в список", imgui.ImVec2(UI.Scale(150), 0)) then
                if inputBlackHouse[0] >= 0 then
                    table.insert(settings.main.blackListHouses, inputBlackHouse[0])
                    Storage.SaveSettings()
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
                    if imgui.Button(u8"Удалить##"..index, imgui.ImVec2(UI.Scale(80), 0)) then
                        table.remove(settings.main.blackListHouses, index)
                        Storage.SaveSettings()
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

        -- ТАБ: Видеокарты (майнинг крипты)
        if imgui.BeginTabItem(u8"Видеокарты") then
            imgui.BeginChild("tab_crypto", imgui.ImVec2(-1, -1))
            imgui.ScrollMouse()
            Draw.CryptoSettings()
            imgui.EndChild()
            imgui.EndTabItem()
        end

        -- ТАБ: Теплицы (фермер)
        if imgui.BeginTabItem(u8"Теплицы") then
            imgui.BeginChild("tab_farmer", imgui.ImVec2(-1, -1))
            imgui.ScrollMouse()
            Draw.FarmerSettings()
            imgui.EndChild()
            imgui.EndTabItem()
        end

        -- ТАБ: Майнер
        if imgui.BeginTabItem(u8"Майнер") then
            imgui.BeginChild("tab_miner", imgui.ImVec2(-1, -1))
            imgui.ScrollMouse()
            Draw.MinerSettings()
            imgui.EndChild()
            imgui.EndTabItem()
        end

        -- ТАБ: Уведомления в Telegram
        if imgui.BeginTabItem(u8"Уведомления") then
            imgui.BeginChild("tab_notifications", imgui.ImVec2(-1, -1))
            imgui.ScrollMouse()
            Draw.SettingsNotifications()
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
                Storage.SaveSettings()
            end
            imgui.TextDisabled(u8"Если включено - списки можно прокручивать свайпом (требуется перезагрузка скрипта).\nНо перемещение окна только за заголовок скрипта")

            imgui.Spacing()

            imgui.PushItemWidth(-1)

            imgui.Text(u8"Размер полосы прокрутки:")
            local _scrollbarSizeStyle = new.int(settings.style.scrollbarSizeStyle)
            if imgui.SliderInt("##scrollbarSize", _scrollbarSizeStyle, 10, 50, "%d px") then
                settings.style.scrollbarSizeStyle = _scrollbarSizeStyle[0] 
                Storage.SaveSettings()
                imgui.GetStyle().ScrollbarSize = settings.style.scrollbarSizeStyle
            end

            imgui.Spacing()

            imgui.Text(u8"Масштаб интерфейса (DPI):")
            local _MONET_DPI_SCALE = new.float(settings.style.scaleUI)
            if imgui.SliderFloat("##scaleUI", _MONET_DPI_SCALE, 0.5, 3.0, "%.2f") then
                settings.style.scaleUI = _MONET_DPI_SCALE[0]
                Storage.SaveSettings()
            end
            imgui.TextDisabled(u8"Рекомендуемые значения: 1.0 - 2.0")

            imgui.PopItemWidth()

            imgui.Spacing()
            imgui.Separator()
            imgui.CenterText(u8"Цвета интерфейса")
            imgui.Spacing()

            -- Готовые темы
            local spacingX = imgui.GetStyle().ItemSpacing.x
            local presetW = (imgui.GetWindowContentRegionWidth() - spacingX * 2) / 3
            for i, preset in ipairs(UI.COLOR_PRESETS) do
                if (i % 3) ~= 1 then imgui.SameLine() end
                if imgui.Button(u8(preset.name) .. "##colorPreset" .. i, imgui.ImVec2((i % 3 == 0) and -1 or presetW, 0)) then
                    UI.ApplyPreset(i)
                end
            end

            imgui.Spacing()

            Draw.ColorEditRow("Основной цвет", "mainColor", true)
            Draw.ColorEditRow("Цвет текста", "textColor", false)
            Draw.ColorEditRow("Цвет фона", "bgColor", true)
            Draw.ColorEditRow("Акцент", "accentColor", false)
            Draw.ColorEditRow("Префикс скрипта в чате", "chatColor", false)

            imgui.Spacing()
            imgui.Text(u8"Смысловые цвета:")
            Draw.ColorEditRow("Успех / готово", "okColor", false)
            Draw.ColorEditRow("Предупреждение", "warnColor", false)
            Draw.ColorEditRow("Ошибка / опасность", "badColor", false)

            imgui.Spacing()
            imgui.Text(u8"Полосы заполнения:")
            Draw.ColorEditRow("Свободно", "barFreeColor", true)
            Draw.ColorEditRow("Заполнено наполовину", "barHalfColor", true)
            Draw.ColorEditRow("Почти полная", "barFullColor", true)

            imgui.Spacing()
            imgui.Text(u8"Графики в логах:")
            Draw.ColorEditRow("Столбик", "graphBarColor", false)
            Draw.ColorEditRow("Выбранный столбик", "graphActiveColor", false)
            Draw.ColorEditRow("Подложка столбика", "graphBgColor", false)

            imgui.Spacing()
            if imgui.Button(u8"Сбросить цвета к стандартным", imgui.ImVec2(-1, UI.Scale(26))) then
                UI.ResetColors()
                ui_state.colorsDirty = false
            end

            -- настройки пишем на диск только когда пользователь отпустил элемент
            if ui_state.colorsDirty and not imgui.IsAnyItemActive() then
                ui_state.colorsDirty = false
                Storage.SaveSettings()
            end

            imgui.Spacing()
            imgui.Separator()
            imgui.Spacing()

            if imgui.Button(u8"Перезапустить скрипт", imgui.ImVec2(-1, UI.Scale(40))) then
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
                Util.OpenUrl("https://t.me/arz_mcr")
            end

            imgui.Text(u8"ТГ разработчика: ") imgui.SameLine()
            if imgui.ClickableText("@Mister_Sand") then
                Util.OpenUrl("https://t.me/Mister_Sand")
            end
            imgui.Spacing()
            imgui.Text(u8"Помощь монеткой разработчику: ") imgui.SameLine()
            if imgui.ClickableText("Boosty") then
                Util.OpenUrl("https://boosty.to/sand-mcr")
            end
            imgui.Text(u8"Тема на Blast.hk: ") imgui.SameLine()
            if imgui.ClickableText("MMT | Mining Tool") then
                Util.OpenUrl("https://www.blast.hk/threads/242059/")
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

function Draw.HousesBank()
    if stateCrypto.work then
        imgui.ProgressBar(stateCrypto.progressHousesBank/#stateCrypto.queueHousesBank,imgui.ImVec2(-1,0), u8"Дом "..stateCrypto.progressHousesBank.."/"..#stateCrypto.queueHousesBank)
    end

    local btnTitle = settings.main.bankFillToTarget and u8"Заполнить до цели" or u8"Заполнить до максимума"
    if imgui.ButtonClickable(not stateCrypto.work, btnTitle, imgui.ImVec2(-1, 0)) then
        Interacting.Start("dep")
    end

    imgui.BeginChild("list", imgui.ImVec2(-1, -1))
    imgui.ScrollMouse()
    lastOpenHouse = UI.HandleListNavigation(
        (lastOpenHouse > 0 and lastOpenHouse or 1),
        #housesBanks,
        function(idx)
            local house = housesBanks[idx]
            if house then
                sampSendDialogResponse(idDialogs.selectHouse, 1, house.samp_line, "")
                housesBanks = {}
                UI.SwitchMainWindow()
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
            Util.GetCommaValue(house.bankNow)
        )

        if imgui.SelectableEx(i, house_text, lastOpenHouse == i, imgui.SelectableFlags.SpanAllColumns) and UI.IsClick() then
            lastOpenHouse = i
            sampSendDialogResponse(idDialogs.selectHouse, 1, house.samp_line, "")
            housesBanks = {}
            UI.SwitchMainWindow()
        end

        -- небольшой отступ между домами
        if i < #houses then
            imgui.Spacing()
        end
    end
    imgui.EndChild()
end

function Draw.Houses()
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

    local button_width = (imgui.GetWindowWidth() - UI.Scale(30)) / 2
    if imgui.ButtonClickable(not stateCrypto.work, fa.HAND_HOLDING_DOLLAR .. u8"\tСобрать всю прибыль", imgui.ImVec2(button_width, 0)) then
        Interacting.Start("take")
    end
    imgui.SameLine()
    if imgui.ButtonClickable(not stateCrypto.work, fa.PLAY .. u8"\tВключить все видеокарты", imgui.ImVec2(-1, 0)) then
        Interacting.Start("on")
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
    lastOpenHouse = UI.HandleListNavigation(
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
            house_data.max_collect > (tonumber(settings.main.maxCollectAlert) or 11) and COLORS.RED or house_data.max_collect > 1 and COLORS.GREEN or COLORS.WHITE,
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
            Util.GetCommaValue(house.cycles),
            COLORS.WHITE,
            bank_color,
            Util.GetCommaValue(house.bankNow or 0),
            house.currency
        )

        if imgui.SelectableEx(i, house_text, lastOpenHouse == i, imgui.SelectableFlags.SpanAllColumns) and UI.IsClick() then
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

function Draw.Shelves()
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
    imgui.Text(u8(string.format("Охлаждаек в инвентаре: BTC - %s | Supper BTC - %s | ASC - %s", haveLiquid.btc, haveLiquid.supper_btc, haveLiquid.asc)))

    imgui.Spacing()

    local totalWidth = (imgui.GetWindowWidth() - UI.Scale(30))
    local half    = totalWidth / 2
    local quarter = (totalWidth / 4) - (imgui.GetStyle().ItemSpacing.x / 2)

    if imgui.ButtonClickable(not stateCrypto.work, fa.HAND_HOLDING_DOLLAR .. u8"\tСобрать", imgui.ImVec2(half, 0)) then
        Interacting.Start("take")
    end
    imgui.SameLine()
    if imgui.ButtonClickable(not stateCrypto.work, fa.FILL_DRIP .. u8"\tЗалить", imgui.ImVec2(quarter, 0)) then
        Interacting.Start("fill")
    end

    imgui.SameLine()

    local autoIcon  = settings.main.autoFillEnabled and fa.TOGGLE_ON or fa.TOGGLE_OFF
    local autoTitle = settings.main.autoFillEnabled and u8"Автозаливка: вкл" or u8"Автозаливка: выкл"
    if imgui.Button(autoIcon .. "\t" .. autoTitle, imgui.ImVec2(-1, 0)) then
        settings.main.autoFillEnabled = not settings.main.autoFillEnabled
        Storage.SaveSettings()
        Chat.Add("Автозаливка: " .. (settings.main.autoFillEnabled and "включена" or "выключена"), TYPECHATMESSAGES.SECONDARY)
    end

    local toggleEnableIcon  = settings.main.autoEnableCards and fa.TOGGLE_ON or fa.TOGGLE_OFF
    local toggleEnableTitle = settings.main.autoEnableCards and u8"Автовкл: вкл" or u8"Автовкл: выкл"

    if imgui.ButtonClickable(not stateCrypto.work, fa.PLAY .. u8"\tВключить карты", imgui.ImVec2(quarter, 0)) then
        Interacting.Start("on")
    end
    imgui.SameLine()
    if imgui.Button(toggleEnableIcon .. "\t" .. toggleEnableTitle, imgui.ImVec2(quarter, 0)) then
        settings.main.autoEnableCards = not settings.main.autoEnableCards
        Storage.SaveSettings()
        Chat.Add("Автовключение карт после сбора: " .. (settings.main.autoEnableCards and "включено" or "выключено"), TYPECHATMESSAGES.SECONDARY)
    end
    imgui.SameLine()
    if imgui.ButtonClickable(not stateCrypto.work, fa.PAUSE .. u8"\tОтключить карты", imgui.ImVec2(-1, 0)) then
        Interacting.Start("off")
    end
    if stateCrypto.work then
        imgui.ProgressBar(stateCrypto.progressShelves/#stateCrypto.queueShelves,imgui.ImVec2(-1,0), stateCrypto.progressShelves.."/"..#stateCrypto.queueShelves)
    end

    local currentHouseNumber = tonumber(stateCrypto.activeHouseID)
    local currentHouseBonusPercent = CalcHouseIncomeBonusPercent(currentHouseNumber)
    local inc = GetIncomeSettings()
    if currentHouseNumber and currentHouseNumber >= 0 then
        imgui.Text(u8(string.format("Дом №%d | Бонус доходности: +%.2f%%", currentHouseNumber, currentHouseBonusPercent)))
    end

    imgui.Separator()

    imgui.BeginChild("list", imgui.ImVec2(-1, -1))
    imgui.ScrollMouse()
    lastOpenShelves = UI.HandleListNavigation(
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

        local profit_color = (shelf.profit or 0) >= 1 and COLORS.GREEN or COLORS.WHITE -- зеленый если можно собрать, белый если нельзя

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
                profit_color, shelf.profit_primary or shelf.profit, shelf.currency, shelf.profit2, shelf.currency2,
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

        if imgui.SelectableEx(i, _text, lastOpenShelves == i, imgui.SelectableFlags.SpanAllColumns) and UI.IsClick() then
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

function UI.IsClick()
    return not ui_state.swipe.is_gesture
end

function imgui.MoveOnTitleBar()
    if not settings.style.swipeScroll then return end

    local io = imgui.GetIO()
    local win_pos = imgui.GetWindowPos()
    local win_sz  = imgui.GetWindowSize()

    local grab_height = UI.Scale(28)
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

-- Кнопка акцентным цветом: для главных действий (запуск, обновление, сбор)
function imgui.AccentButton(label, size)
    local col = UI.Vec4('accentColor')
    -- на светлом акценте белый текст не читается - берём тёмный
    local lum = col.x * 0.299 + col.y * 0.587 + col.z * 0.114
    local darkText = lum > 0.6

    imgui.PushStyleColor(imgui.Col.Button, col)
    imgui.PushStyleColor(imgui.Col.ButtonHovered, Shade(col, 1.18))
    imgui.PushStyleColor(imgui.Col.ButtonActive, Shade(col, 0.85))
    if darkText then
        imgui.PushStyleColor(imgui.Col.Text, imgui.ImVec4(0.10, 0.10, 0.10, 1.0))
    end

    local pressed = imgui.Button(label, size)

    imgui.PopStyleColor(darkText and 4 or 3)
    return pressed
end

function imgui.AccentButtonClickable(clickable, label, size)
    if clickable then
        return imgui.AccentButton(label, size)
    end
    return imgui.ButtonClickable(false, label, size)
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
        imgui.PopStyleColor(4)
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

-- Цвет из настроек как ImVec4
function UI.Vec4(key, alphaOverride)
    local c = settings.style[key] or {}
    return imgui.ImVec4(c.r or 0, c.g or 0, c.b or 0, alphaOverride or c.a or 1.0)
end

-- Цвет { r, g, b } -> строка "RRGGBB" для чата и {цветовых} вставок
function UI.ColorToHex(color)
    local function byte(v)
        return math.floor(math.maxEx(0, math.minEx(1, tonumber(v) or 0)) * 255 + 0.5)
    end
    color = color or {}
    return string.format('%02X%02X%02X', byte(color.r), byte(color.g), byte(color.b))
end

-- Смысловые цвета текста и цвет префикса в чате
function UI.RefreshSemanticColors()
    local st = settings.style
    COLORS.WHITE  = UI.ColorToHex(st.textColor)
    COLORS.GREEN  = UI.ColorToHex(st.okColor)
    COLORS.YELLOW = UI.ColorToHex(st.warnColor)
    COLORS.RED    = UI.ColorToHex(st.badColor)

    local chatHex = UI.ColorToHex(st.chatColor)
    st.colorChat = chatHex
    st.colorMessage = tonumber('FF' .. chatHex, 16) or 0xFF8cbf91
end

-- Применение цветов к текущему стилю imgui (безопасно вызывать прямо в кадре)
function UI.ApplyStyleColors()
    local colors = imgui.GetStyle().Colors
    local clr = imgui.Col
    local ImVec4 = imgui.ImVec4

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

-- Цвета целиком: стиль окна + смысловые цвета текста + чат
function UI.ApplyColors()
    UI.ApplyStyleColors()
    UI.RefreshSemanticColors()
end

-- Полная установка стиля: отступы/скругления (зависят от платформы) + цвета
function UI.SetStyle(mobile)
    if mobile == nil then mobile = ISMONETLOADER end
    if mobile then
        MainStyleMobile()
    else
        MainStyle()
    end
    UI.ApplyColors()
end

-- Готовые темы
UI.COLOR_PRESETS = {
    { name = 'Зелёная',    main = { 0.25, 0.45, 0.28 }, bg = { 0.10, 0.15, 0.14 }, text = { 0.80, 0.85, 0.80 }, accent = { 0.27, 0.25, 0.45 }, chat = { 0.55, 0.75, 0.57 } },
    { name = 'Синяя',      main = { 0.20, 0.35, 0.55 }, bg = { 0.09, 0.12, 0.17 }, text = { 0.82, 0.86, 0.92 }, accent = { 0.30, 0.55, 0.80 }, chat = { 0.55, 0.72, 0.95 } },
    { name = 'Фиолетовая', main = { 0.35, 0.27, 0.52 }, bg = { 0.12, 0.10, 0.17 }, text = { 0.86, 0.83, 0.92 }, accent = { 0.55, 0.45, 0.80 }, chat = { 0.72, 0.62, 0.95 } },
    { name = 'Оранжевая',  main = { 0.50, 0.33, 0.16 }, bg = { 0.15, 0.12, 0.09 }, text = { 0.92, 0.87, 0.80 }, accent = { 0.85, 0.55, 0.25 }, chat = { 0.95, 0.72, 0.42 } },
    { name = 'Вишнёвая',   main = { 0.46, 0.20, 0.26 }, bg = { 0.15, 0.09, 0.11 }, text = { 0.92, 0.83, 0.85 }, accent = { 0.80, 0.35, 0.42 }, chat = { 0.95, 0.58, 0.62 } },
    { name = 'Графит',     main = { 0.27, 0.29, 0.32 }, bg = { 0.11, 0.12, 0.13 }, text = { 0.85, 0.86, 0.88 }, accent = { 0.45, 0.48, 0.52 }, chat = { 0.75, 0.78, 0.82 } },
}

function UI.ApplyPreset(index)
    local preset = UI.COLOR_PRESETS[tonumber(index) or 0]
    if not preset then return end

    local st = settings.style
    local function set(target, rgb, alpha)
        target.r, target.g, target.b = rgb[1], rgb[2], rgb[3]
        target.a = alpha or 1.00
    end

    set(st.mainColor, preset.main)
    set(st.bgColor, preset.bg, 0.98)
    set(st.textColor, preset.text)
    set(st.accentColor, preset.accent)
    set(st.chatColor, preset.chat)

    UI.ApplyColors()
    Storage.SaveSettings()
end

-- Сброс всех цветов к значениям по умолчанию
function UI.ResetColors()
    local st = settings.style
    for _, key in ipairs({ 'mainColor', 'textColor', 'bgColor', 'accentColor', 'chatColor',
                           'okColor', 'warnColor', 'badColor',
                           'barFreeColor', 'barHalfColor', 'barFullColor',
                           'graphBarColor', 'graphActiveColor', 'graphBgColor' }) do
        local src = defaultSettings.style[key]
        if src then
            st[key] = { r = src.r, g = src.g, b = src.b, a = src.a }
        end
    end
    UI.ApplyColors()
    Storage.SaveSettings()
end
