-- Patch34
-- Podcast HTML/DOCX Script Viewer
-- Read DOCX and Google Docs HTML scripts inside REAPER.
--
-- https://github.com/patch-34
--
-- @description Patch34: Podcast HTML/DOCX Script Viewer
-- @version 1.0.0
-- @author Aleksei Vorobev / Patch34
-- @about
--   Read podcast, voiceover, and post-production scripts inside REAPER.
--   Opens DOCX files and Google Docs HTML exports with supported formatting,
--   comments, clickable links, and search by individual occurrence.
--
--   Requires REAPER 7 or newer and ReaImGui 0.10 or newer.
--   See README.md / README_RU.md for installation, controls, and import limits.
--
--   First public release.
--   Support: https://boosty.to/patch34/donate

-- ══════════════════════════════════════════════════════════════
--  FONTS  (before first frame)
-- ══════════════════════════════════════════════════════════════

-- Check the API before any resources or project state are accessed.
do
  local compatible = type(reaper.ImGui_GetVersion) == "function"
  if compatible then
    local ok, imgui_version, imgui_number, version = pcall(reaper.ImGui_GetVersion)
    local major, minor = tostring(version or ""):match("^(%d+)%.(%d+)")
    major, minor = tonumber(major), tonumber(minor)
    compatible = ok and major ~= nil and (major > 0 or minor >= 10)
      and type(reaper.ImGui_CreateFont) == "function"
      and type(reaper.ImGui_Col_NavCursor) == "function"
      and type(reaper.ImGui_SetScrollFromPosY) == "function"
  end
  if not compatible then
    reaper.MB("This script requires ReaImGui 0.10 or newer.\nInstall or update ReaImGui through ReaPack.",
      "Podcast HTML/DOCX Script Viewer", 0)
    return
  end
end

local SCRIPT_NAME  = "Podcast HTML/DOCX Script Viewer"
PSV_SCRIPT_VERSION = "1.0.0"
local EXTSTATE_SEC = "PodcastScriptViewer"
local SUPPORT_URL  = "https://boosty.to/patch34/donate"

-- ══════════════════════════════════════════════════════════════
--  UI SETTINGS  (централизованный блок текущих UI-настроек)
-- ══════════════════════════════════════════════════════════════
-- ВАЖНО:
-- Это extraction-only блок.
-- Здесь собраны только уже существующие и реально используемые
-- UI-настройки/тюнинги текущей версии, без изменения поведения.
-- Следующие пассы смогут безопасно добавлять ручную визуальную
-- настройку именно сюда, не разыскивая inline-литералы по файлу.

-- Стартовый размер окна при первом открытии скрипта.
-- Landscape-default: компактнее по высоте и шире для чтения/пустого экрана.
local UI_INIT_WINDOW_W = 840
local UI_INIT_WINDOW_H = 560

-- Minimum resize size for the main script window.
-- Nonlocal by design to avoid increasing Lua main-chunk local pressure
-- and to keep the value easy to tune from the UI SETTINGS block.
UI_MIN_WINDOW_W = 840
UI_MIN_WINDOW_H = 560

-- Стартовая позиция окна, если ещё нет сохранённой геометрии для owner project.
-- Фиксированная безопасная позиция намеренно сдвинута правее и ниже,
-- без зависимости от monitor API, чтобы не вводить новую платформенную ветку.
local UI_INIT_WINDOW_X = 560
local UI_INIT_WINDOW_Y = 300

-- Базовый размер шрифта viewer-а по умолчанию.
local UI_FONT_SIZE_DEFAULT = 16

-- Минимально и максимально допустимый размер шрифта viewer-а.
local UI_FONT_SIZE_MIN = 10
local UI_FONT_SIZE_MAX = 40

-- Количество полностью скрытых startup-кадров,
-- пока окно проходит минимальную стартовую стабилизацию.
local UI_STARTUP_HIDE_FRAMES = 2

-- Количество defer-кадров перед первым созданием ImGui-контекста и первым ImGui_Begin.
-- Устраняет чёрную панель при старте, вызванную слишком ранним созданием
-- нативного ReaImGui-окна поверх arrange/track view REAPER.
local UI_STARTUP_DELAY_FRAMES = 0

-- Текущая ширина верхнего поля поиска.
local UI_SEARCH_FIELD_W = 220

-- Единый визуальный контракт верхнего search field.
-- Active и inactive состояния используют одну и ту же геометрию,
-- форму, border-policy и baseline; отличаться должен только fill color.
local UI_SEARCH_FIELD_H = 28 -- explicit top-row fit; 0 = использовать ImGui_GetFrameHeight() на текущем кадре
local UI_SEARCH_FIELD_ROUNDING = 3
local UI_SEARCH_FIELD_PAD_X = 8
local UI_SEARCH_BORDER_THICKNESS = 1.0

-- Фиксированный размер шрифта для верхней search UI-строки.
-- Он намеренно не зависит от document/body font size, чтобы поле поиска
-- не росло и не сжималось при настройке размера текста документа.
local UI_SEARCH_FONT_SIZE = 16

-- ══════════════════════════════════════════════════════════════
--  COMMENTS NAVIGATOR POPUP UI SETTINGS
-- ══════════════════════════════════════════════════════════════
-- Manual tuning block for the custom top-row Comments navigator popup/list.
-- ВАЖНО: эти настройки намеренно НЕ объявлены через local, потому что файл
-- находится около Lua main-chunk local-variable limit. Это presentation-only
-- слой для custom Comments navigator popup; он не меняет навигационную модель
-- и не относится к document comment-card UI_COMMENT_CARD_* settings.

-- Popup/window size. MIN_H prevents very small 1–2 item popups from becoming
-- visually cramped or getting false scrollbars when content fits. MAX_H still
-- caps long lists and keeps internal vertical scrolling.
UI_COMMENTS_NAV_POPUP_W = 300
UI_COMMENTS_NAV_POPUP_MAX_H = 350
UI_COMMENTS_NAV_POPUP_MIN_H = 96

-- Popup frame/border and opening position relative to the Comments trigger.
UI_COMMENTS_NAV_BORDER_THICKNESS = 1.0
UI_COMMENTS_NAV_POPUP_ROUNDING = 4.0
UI_COMMENTS_NAV_OPEN_OFFSET_X = 0
UI_COMMENTS_NAV_OPEN_OFFSET_Y = 4
UI_COMMENTS_NAV_OUTER_PAD = 4

-- Row/bubble geometry. These control only the navigator popup list rows.
UI_COMMENTS_NAV_ROW_MIN_H = 40
UI_COMMENTS_NAV_ROW_PAD_X = 8
UI_COMMENTS_NAV_ROW_PAD_Y = 5
UI_COMMENTS_NAV_ROW_LINE_GAP_Y = 1
UI_COMMENTS_NAV_ROW_GAP_Y = 1
UI_COMMENTS_NAV_ROW_ROUNDING = 6.0
UI_COMMENTS_NAV_ROW_BORDER_THICKNESS = 1.0

-- Vertical scrollbar reserve and local navigator scrollbar colors.
-- ScrollbarBg stays transparent, while the grab remains visible.
UI_COMMENTS_NAV_SCROLLBAR_RESERVED_W = 4
UI_COMMENTS_NAV_SCROLLBAR_BG_RGBA = {0, 0, 0, 0}
UI_COMMENTS_NAV_SCROLLBAR_GRAB_RGBA = {150, 150, 150, 120}
UI_COMMENTS_NAV_SCROLLBAR_GRAB_HOVER_RGBA = {150, 150, 150, 150}
UI_COMMENTS_NAV_SCROLLBAR_GRAB_ACTIVE_RGBA = {150, 150, 150, 180}

-- Independent Comments navigator font size. Controlled from View → Comments font.
UI_COMMENTS_NAV_FONT_SIZE_DEFAULT = 14
UI_COMMENTS_NAV_FONT_SIZE_MIN = 10
UI_COMMENTS_NAV_FONT_SIZE_MAX = 24
-- Legacy compatibility knob from the previous popup-scale pass. Kept inert:
-- navigator font size is now controlled by the independent View setting comments_nav_font_size.
UI_COMMENTS_NAV_FONT_SIZE_OFFSET = 0

-- Comments sidebar placeholder layout. Session-only visibility is controlled by
-- PSV_COMMENTS_SIDEBAR_OPEN below. These settings are intentionally separate
-- from the popup-specific UI_COMMENTS_NAV_POPUP_* settings because the sidebar
-- will become a right-side document-area panel, not a top-row popup.
UI_COMMENTS_SIDEBAR_W = 300
UI_COMMENTS_SIDEBAR_GAP = 0
UI_COMMENTS_SIDEBAR_MIN_BODY_W = 320

-- Unified Comments sidebar/list background. This is intentionally separate
-- from theme-dependent navigator popup colors. The sidebar background stays
-- lighter than the darker document comment-card overlay, while its rounding
-- matches the comment-card corner rounding.
UI_COMMENTS_SIDEBAR_BG_ENABLED = true
UI_COMMENTS_SIDEBAR_BG_RGBA = {205, 205, 205, 145}
UI_COMMENTS_SIDEBAR_BG_ROUNDING = 9.0

-- Visual separation between the grey sidebar/list background and the native
-- scrollbar lane. This does not move or restyle the scrollbar; it only keeps
-- the grey list background from being painted underneath the scrollbar lane.
UI_COMMENTS_SIDEBAR_SCROLLBAR_SEPARATION_ENABLED = true

-- Visual outer gaps around navigator row bubbles inside the Comments sidebar.
-- These do not move the sidebar child or change row internal text padding.
UI_COMMENTS_SIDEBAR_BUBBLE_GAP_L = 10
UI_COMMENTS_SIDEBAR_BUBBLE_GAP_R = 4

-- Tiny vertical gap before the first visible navigator row/card inside
-- the Comments sidebar list. Implemented via Dummy only in sidebar mode,
-- without moving the outer sidebar container or changing row/card padding.
UI_COMMENTS_SIDEBAR_LIST_TOP_GAP_Y = 2

-- Marker-aware Comments navigator row-click navigation.
-- The paragraph target is kept as a force-render/coarse stage, but the old
-- paragraph-level SetScrollHereY is suppressed for active navigator requests.
-- The matched marker either opens immediately when already inside this safe
-- viewport band or receives one minimal scroll-to-visible correction first.
-- Margins provide comfortable distance from body viewport edges after a
-- corrective navigator scroll.
UI_COMMENTS_NAV_MARKER_AWARE_SCROLL_ENABLED = true
UI_COMMENTS_NAV_MARKER_VISIBLE_MARGIN_TOP = 100
UI_COMMENTS_NAV_MARKER_VISIBLE_MARGIN_BOTTOM = 100
UI_COMMENTS_NAV_MARKER_SCROLL_MAX_ATTEMPTS = 3

-- ══════════════════════════════════════════════════════════════
--  TEMPORARY LOCAL PROFILER
-- ══════════════════════════════════════════════════════════════
-- TEMPORARY TESTING PROFILER
-- Safe to remove after release validation. Console-only, throttled,
-- session-local diagnostics for rough PSV frame/block cost checks.
PROFILER_ENABLED = false
PROFILER_REPORT_INTERVAL_SEC = 5.0
PROFILER_SPIKE_16_MS = 16.0
PROFILER_SPIKE_50_MS = 50.0
PROFILER_BLOCK_TIMERS_ENABLED = false
PROFILER_DOCUMENT_SUBBLOCKS_ENABLED = false
PROFILER_DOCUMENT_COUNTERS_ENABLED = false
PROFILER_MAX_SAMPLES_PER_WINDOW = 1200

-- Pages-only color separation for the custom Comments navigator popup.
-- Applied only when ui_theme == "paper" (user-facing Theme: Pages).
-- These settings affect only the top-row Comments navigator popup/list,
-- not document comment cards, document highlights, or global page colors.
UI_COMMENTS_NAV_PAGES_COLOR_OVERRIDE_ENABLED = true
UI_COMMENTS_NAV_PAGES_POPUP_BG_RGBA = {82, 102, 94, 255}
UI_COMMENTS_NAV_PAGES_ROW_BG_RGBA = {248, 248, 246, 255}
UI_COMMENTS_NAV_PAGES_ROW_HOVER_BG_RGBA = {238, 241, 237, 255}
UI_COMMENTS_NAV_PAGES_ROW_BORDER_RGBA = {122, 145, 136, 150}
UI_COMMENTS_NAV_REAPER_GREY_ROW_BORDER_RGBA = {104, 120, 114, 70}
UI_COMMENTS_NAV_PAGES_AUTHOR_TEXT_RGBA = {112, 112, 112, 255}
UI_COMMENTS_NAV_PAGES_PREVIEW_TEXT_RGBA = {28, 28, 28, 255}
UI_COMMENTS_NAV_PAGES_POPUP_BORDER_RGBA = {82, 102, 94, 190}

-- Top/menu row tuning.
-- ВАЖНО: эти настройки намеренно НЕ объявлены через local, потому что файл
-- находится около Lua main-chunk local-variable limit. Не переводить их в local.
-- UI_TOP_ROW_TARGET_H задаёт желаемую визуальную высоту объединённой строки меню/Search.
-- FRAME_PAD_Y и ITEM_SPACING_Y — первые безопасные настройки native menu-row height.
-- SEARCH_Y_OFFSET — маленький ручной вертикальный сдвиг Search field внутри строки.
UI_TOP_ROW_TARGET_H = 38
UI_TOP_ROW_FRAME_PAD_Y = 10
UI_TOP_ROW_ITEM_SPACING_Y = 4
UI_TOP_ROW_SEARCH_Y_OFFSET = 0

-- Horizontal gap between the custom Comments navigator trigger and the Search field.
-- Search is the stable right-side anchor; Comments is placed to the left of it
-- and must not push or recalculate Search via cursor flow.
UI_TOP_ROW_COMMENTS_GAP_TO_SEARCH = 8

-- Draw rounding for the custom Comments sidebar trigger highlight/background.
-- 0.0 keeps hover/open/active highlight rectangular with straight corners.
-- This does not affect File/View/Theme/Help, Search field, sidebar rows,
-- or document comment cards.
UI_TOP_ROW_COMMENTS_TRIGGER_ROUNDING = 0.0

-- Separator между native menu/Search row и body/page area.
-- Рисуется по нижней границе menu row: без верхнего зазора и без боковых inset-ов.
-- ВАЖНО: эти настройки намеренно НЕ объявлены через local, потому что файл
-- находится около Lua main-chunk local-variable limit. Не переводить их в local.
UI_TOP_ROW_SEPARATOR_ENABLED = true
UI_TOP_ROW_SEPARATOR_THICKNESS = 1.0
UI_TOP_ROW_SEPARATOR_RGBA = {150, 150, 150, 255}

-- Текущий резерв справа для стабильной wrap-границы текста,
-- чтобы перенос строк не упирался вплотную в правый край/скроллбар.
local UI_WRAP_RIGHT_RESERVE = 18

-- Консервативный запас вокруг видимой области body child для render-culling.
-- Чем больше значение, тем дальше от viewport происходит переключение
-- full-render ↔ Dummy(cached_para_h), поэтому при обычном скролле меньше
-- риск увидеть скачок от пограничного culling-перехода.
local UI_BODY_CULL_BUFFER_PX = 600

-- Allows cached-height offscreen paragraph culling to remain active when
-- visual page-flow is enabled. The skip path still requires a valid cached
-- paragraph height and never applies to force-rendered search/comment targets.
-- Nonlocal by design: this is a temporary optimization switch for quick rollback
-- if page-flow/culling regressions appear during profiling.
UI_BODY_PAGE_FLOW_CACHED_CULLING_ENABLED = true

-- ══════════════════════════════════════════════════════════════
--  PAGE LAYOUT SETTINGS
-- ══════════════════════════════════════════════════════════════
-- Визуальный слой страниц внутри body child.
-- ВАЖНО: эти значения намеренно НЕ объявлены через local, потому что файл
-- находится около Lua main-chunk local-variable limit. Это такой же editable
-- settings-паттерн, как у COMMENT CARD UI SETTINGS ниже.
--
-- Page layout не меняет text wrap, body margins, parser, search или comments.
-- Он только читает ImGui scroll/window metrics текущего ##body и рисует
-- background/pages через DrawList перед основным рендером текста.
PAGE_LAYOUT_ENABLED = true

-- Высота одной визуальной страницы и внешние зазоры page stack внутри body child.
-- PAGE_MARGIN_LEFT/PAGE_MARGIN_RIGHT — это визуальные внешние зазоры страницы
-- от краёв body child. Они НЕ являются text margins и НЕ меняют wrap текста.
-- PAGE_STACK_TOP_GAP — внешний зазор перед первой визуальной страницей.
-- PAGE_STACK_BOTTOM_GAP — внешний app/background-зазор после последней
-- визуальной страницы. Это НЕ PAGE_PAD_BOTTOM, НЕ PAGE_GAP_Y и НЕ PAGE_H:
-- он добавляется после фиксированного нижнего края последней страницы.
-- PAGE_PAD_TOP/PAGE_PAD_BOTTOM задают вертикальную область чтения внутри
-- визуальной страницы: render_paragraphs() реально двигает ImGui cursor так,
-- чтобы абзацы начинались внутри этой зоны и не попадали в gutter между страницами.
PAGE_H = 1056
PAGE_MARGIN_LEFT = 84
PAGE_MARGIN_RIGHT = 84
PAGE_GAP_Y = 43
PAGE_STACK_TOP_GAP = 50
PAGE_STACK_BOTTOM_GAP = 42
PAGE_PAD_TOP = 42
PAGE_PAD_BOTTOM = 80

-- Reserved extra horizontal padding inside the visual page sheet for the
-- readable text/content area. The user-facing View → Text margins value is
-- the canonical effective margin, so these stay at 0 by default to avoid a
-- hidden second margin layer. Nonlocal by design: this file is close to Lua
-- main-chunk local pressure, and these are manual page-layout tuning constants.
PAGE_CONTENT_PAD_LEFT = 0
PAGE_CONTENT_PAD_RIGHT = 0

-- Минимальное количество строк, которое должно помещаться в оставшейся
-- content-area текущей страницы, чтобы новый абзац мог стартовать здесь.
-- Если места меньше, абзац переносится на следующую страницу; если места
-- достаточно, continuation lines обрабатывает существующий line-level guard.
-- ВАЖНО: nonlocal по тому же PAGE_* settings-паттерну, без роста main-chunk locals.
PAGE_FLOW_MIN_START_LINES = 3

-- Визуальное скругление углов страницы.
-- Рекомендуемый ручной диапазон: 2–4.
-- Более высокие значения могут сделать страницу похожей на card/panel,
-- а не на простой лист документа.
PAGE_ROUNDING = 3

-- Двухслойная page shadow model: CSS-like box-shadow без настоящего blur.
-- Используются только два компонента: широкий лёгкий ambient shadow и более
-- узкий contact shadow. Значения alpha намеренно очень низкие, потому что
-- прозрачность накапливается через PAGE_SHADOW_N_STEPS прямоугольников.
-- BLUR_T/R/B/L задают независимое расширение по сторонам: низкий BLUR_T
-- сохраняет чистый верх страницы, высокий BLUR_B делает нижнюю тень читаемой,
-- уменьшение BLUR_L/R ослабляет side-column артефакты.
-- Рекомендуемые диапазоны:
--   PAGE_SHADOW_N_STEPS = 6–12
--   AMBIENT_DY = 2–8, AMBIENT_BLUR_T = 0–3,
--   AMBIENT_BLUR_R/L = 3–12, AMBIENT_BLUR_B = 8–24,
--   AMBIENT_ALPHA = 0.002–0.008
--   CONTACT_DY = 1–4, CONTACT_BLUR_T = 0–1,
--   CONTACT_BLUR_R/L = 1–5, CONTACT_BLUR_B = 3–10,
--   CONTACT_ALPHA = 0.003–0.012
PAGE_SHADOW_ENABLED = true
PAGE_SHADOW_N_STEPS = 10

PAGE_SHADOW_AMBIENT_DX = 0
PAGE_SHADOW_AMBIENT_DY = 2
PAGE_SHADOW_AMBIENT_BLUR_T = 11
PAGE_SHADOW_AMBIENT_BLUR_R = 11
PAGE_SHADOW_AMBIENT_BLUR_B = 11
PAGE_SHADOW_AMBIENT_BLUR_L = 11
PAGE_SHADOW_AMBIENT_ALPHA = 0.02
PAGE_SHADOW_AMBIENT_R = 0
PAGE_SHADOW_AMBIENT_G = 0
PAGE_SHADOW_AMBIENT_B = 0

PAGE_SHADOW_CONTACT_DX = 0
PAGE_SHADOW_CONTACT_DY = 0
PAGE_SHADOW_CONTACT_BLUR_T = 2
PAGE_SHADOW_CONTACT_BLUR_R = 2
PAGE_SHADOW_CONTACT_BLUR_B = 2
PAGE_SHADOW_CONTACT_BLUR_L = 2
PAGE_SHADOW_CONTACT_ALPHA = 0.02
PAGE_SHADOW_CONTACT_R = 0
PAGE_SHADOW_CONTACT_G = 0
PAGE_SHADOW_CONTACT_B = 0

PAGE_SHADOW_ROUNDING_EXTRA = 2

-- Ручной контроль видимой обводки страницы.
-- Reference может не требовать сильного отдельного outline: оставлено включённым
-- для ручной проверки, но PAGE_BORDER_ENABLED=false полностью убирает border,
-- PAGE_BORDER_ALPHA_MULT ослабляет его, PAGE_BORDER_INSET двигает линию внутрь
-- при возможном edge clipping, PAGE_BORDER_THICKNESS задаёт толщину линии.
-- Рекомендуемые диапазоны:
--   PAGE_BORDER_ALPHA_MULT = 0.0–1.0
--   PAGE_BORDER_INSET = 0.0–1.0
--   PAGE_BORDER_THICKNESS = 0.5–1.0
PAGE_BORDER_ENABLED = false
PAGE_BORDER_ALPHA_MULT = 1.0
PAGE_BORDER_INSET = 0.0
PAGE_BORDER_THICKNESS = 1.0

-- Активная визуальная тема страниц: classic / warm / dark.
-- Пока переключается ручной правкой значения; меню/ExtState оставлены на позже.
page_layout_theme = "classic"

-- Диагностический слой ручного wheel-scroll только для body child.
-- Нужен для A/B проверки: убираем неконтролируемые всплески wheel/trackpad
-- и задаём предсказуемый фиксированный шаг скролла для чтения.
local UI_BODY_MANUAL_WHEEL_SCROLL_ENABLED = true
local UI_BODY_WHEEL_STEP_MULT = 3
local UI_BODY_WHEEL_MAX_TICKS_PER_FRAME = 1

-- Inertial body scroll controller.
-- ВАЖНО: эти настройки намеренно НЕ объявлены через local, потому что файл
-- находится около Lua main-chunk local-variable limit. Body scroll остаётся
-- manual через ImGui_SetScrollY(), так как ##body использует NoScrollWithMouse.
UI_BODY_INERTIAL_SCROLL_ENABLED = true
UI_BODY_SCROLL_LINES_PER_WHEEL = 4.1
UI_BODY_SCROLL_IMMEDIATE_FRACTION = 0.15
UI_BODY_SCROLL_TOTAL_DISTANCE_MULT = 1.08
-- Legacy/reference setting: active inertial model derives gain from
-- TOTAL_DISTANCE_MULT + IMMEDIATE_FRACTION + DAMPING_PER_SECOND.
UI_BODY_SCROLL_VELOCITY_GAIN = 18.0
UI_BODY_SCROLL_MAX_VELOCITY = 3800.0
UI_BODY_SCROLL_DAMPING_PER_SECOND = 13.5
UI_BODY_SCROLL_CUTOFF_VELOCITY = 28.0
UI_BODY_SCROLL_DT_MAX = 0.05
UI_BODY_SCROLL_MAX_WHEEL_UNITS_PER_FRAME = 6.0
UI_BODY_SCROLL_INPUT_CURVE = 1.55

PSV_BODY_SCROLL_STATE = PSV_BODY_SCROLL_STATE or {
  velocity_y = 0.0,
  last_time = nil,
  body_scroll_apply_y = nil,
}

-- Стартовые поля текстового потока внутри page/content area.
-- ВАЖНО: это user-facing Text margins внутри визуальной страницы.
-- body_margin_left/body_margin_right инициализируются из этих defaults
-- при старте скрипта. Команда Reset → Margins возвращает поля именно
-- к этим значениям. Слайдер View → Text margins показывает абсолютное
-- paired-значение в px, а не extra-offset поверх скрытого default.
local UI_BODY_TEXT_MARGIN_LEFT_DEFAULT = 27
local UI_BODY_TEXT_MARGIN_RIGHT_DEFAULT = 27

-- Безопасные пределы ручной настройки text margins через View UI.
local UI_BODY_TEXT_MARGIN_MIN = 18
local UI_BODY_TEXT_MARGIN_MAX = 150

function clamp_body_text_margin(value, fallback)
  local min_v = math.max(0, tonumber(UI_BODY_TEXT_MARGIN_MIN) or 0)
  local max_v = tonumber(UI_BODY_TEXT_MARGIN_MAX) or min_v
  if max_v < min_v then max_v = min_v end

  local v = tonumber(value)
  if v == nil then
    v = tonumber(fallback) or tonumber(UI_BODY_TEXT_MARGIN_LEFT_DEFAULT) or min_v
  end

  if v < min_v then return min_v end
  if v > max_v then return max_v end
  return v
end

-- Фиксированный внутренний отступ первой строки абзаца.
-- Он намеренно не выводится в View UI: первый line indent остаётся
-- стабильным internal typography value на 18 px.
local UI_FIRST_LINE_INDENT_DEFAULT = 18

-- Дополнительный межстрочный интервал внутри абзаца.
-- Это локальная вертикальная прибавка между строками одного абзаца.
local UI_LINE_SPACING_DEFAULT = 2

-- Дополнительный интервал между абзацами.
-- Он применяется после завершения абзаца и не меняет межстрочную дистанцию.
local UI_PARAGRAPH_SPACING_DEFAULT = 12

-- Безопасные пределы ручной настройки типографики.
local UI_LINE_SPACING_MIN = 0
local UI_LINE_SPACING_MAX = 40
local UI_PARAGRAPH_SPACING_MIN = 0
local UI_PARAGRAPH_SPACING_MAX = 80

-- View settings controls geometry.
-- ВАЖНО: эти настройки намеренно НЕ объявлены через local, потому что файл
-- находится около Lua main-chunk local-variable limit. Это такой же editable
-- settings-паттерн, как у PAGE_* и UI_COMMENT_CARD_* settings ниже.
-- Значения совпадают с v1.3.56 и вынесены наверх для ручного тюнинга
-- и будущего movable View Settings window.
UI_VIEW_LABEL_W = 100
UI_VIEW_SLIDER_W = 140
UI_VIEW_VALUE_W = 42
UI_VIEW_VALUE_GAP = 4
UI_VIEW_ROW_H = 22
UI_VIEW_ROW_GAP = 3

-- View settings controls button geometry.
-- Reset-row ширина вычисляется из той же content width, что и rows:
-- label + slider + value gap + value. Поэтому нижняя строка не шире
-- и не уже основной полосы View controls.
UI_VIEW_BUTTON_H = 23
UI_VIEW_BUTTON_GAP = 5
UI_VIEW_CONTENT_W = UI_VIEW_LABEL_W + UI_VIEW_SLIDER_W + UI_VIEW_VALUE_GAP + UI_VIEW_VALUE_W
UI_VIEW_RESET_BUTTON_W = (UI_VIEW_CONTENT_W - 2 * UI_VIEW_BUTTON_GAP) / 3

-- View settings controls slider visuals.
UI_VIEW_SLIDER_KNOB_R = 6
UI_VIEW_SLIDER_TRACK_H = 3
UI_VIEW_SLIDER_CIRCLE_SEGMENTS = 24
UI_VIEW_SLIDER_KNOB_OUTLINE_NORMAL = 1.2
UI_VIEW_SLIDER_KNOB_OUTLINE_HOVER = 1.5

-- View settings controls button visuals / spacing.
UI_VIEW_BUTTON_ROUNDING = 7
UI_VIEW_SECTION_TOP_GAP = 5
UI_VIEW_SECTION_BOTTOM_GAP = 2
UI_VIEW_ROW_LABEL_Y_OFFSET = 2

-- Reset footer block spacing.
-- Компактные labels кнопок остаются короткими, а назначение блока
-- объясняется отдельной лёгкой Reset-меткой над ними.
-- Separator в Reset footer рисуется вручную, чтобы не наследовать
-- дополнительный cursor-flow gap от native ImGui_Separator().
UI_VIEW_RESET_SECTION_TOP_GAP = 7
UI_VIEW_RESET_LABEL_TO_LINE_GAP = 5
UI_VIEW_RESET_LINE_TO_BUTTON_GAP = 7
UI_VIEW_RESET_LINE_THICKNESS = 1.0

-- ══════════════════════════════════════════════════════════════
--  COMMENT CARD UI SETTINGS
-- ══════════════════════════════════════════════════════════════
-- Настройки экспериментальной native comment-card.
-- ВАЖНО: значения намеренно НЕ объявлены через local, потому что файл уже
-- находится около Lua main-chunk local-variable limit. Новые top-level locals
-- могут сломать компиляцию скрипта.
--
-- Карточка теперь компактная: без видимого заголовка "comment:".
-- Размеры рассчитываются от фактического текста, ссылок, separator-ов,
-- внешнего overlay padding и внутреннего padding text-child.
--
-- Важно различать два уровня padding:
-- OUTER_PAD_X/Y — внешний отступ overlay window, то есть толщина пустой зоны
-- вокруг внутреннего поля текста;
-- INNER_PAD_X/Y — реальный inset текста внутри scrollable child.
--
-- Цвета задаются как RGBA tuples: {R, G, B, A}, где четвёртое значение — alpha.
-- Alpha всегда находится в диапазоне 0–255: 0 = полностью прозрачно,
-- 255 = полностью непрозрачно. Меньшее значение даёт большую прозрачность.
-- UI_COMMENT_CARD_BG_ALPHA отдельно управляет прозрачностью основного видимого
-- фона карточки. Важно: несколько полупрозрачных слоёв, наложенных друг на
-- друга, визуально выглядят плотнее. Поэтому текущая реализация использует
-- один основной background layer: outer overlay window. Inner child по умолчанию
-- прозрачный и не добавляет второй semi-opaque слой поверх карточки.
-- Остальные цвета могут иметь собственный alpha в tuple.

-- Внешние отступы overlay window: узкая оболочка вокруг inner text child.
-- Это НЕ отступ текста. Текстовый inset задаётся через INNER_PAD_X/Y.
UI_COMMENT_CARD_OUTER_PAD_X = 3
UI_COMMENT_CARD_OUTER_PAD_Y = 3

-- Внутренние отступы text-child: реальный inset текста внутри поля комментария.
-- Эти значения применяются к BeginChild через ChildFlags_AlwaysUseWindowPadding.
UI_COMMENT_CARD_INNER_PAD_X = 8
UI_COMMENT_CARD_INNER_PAD_Y = 6

-- Ширина карточки: 0 в MIN_W означает content-driven minimum.
-- MAX_W остаётся верхним пределом для длинных комментариев.
UI_COMMENT_CARD_MIN_W = 0
UI_COMMENT_CARD_MAX_W = 330

-- Небольшой горизонтальный safety reserve между измеренной шириной текста
-- и фактической шириной TextWrapped/child content. Он нужен, чтобы очень
-- короткие комментарии не переносились из-за микроскопической разницы между
-- measurement и реальным рендером. Это НЕ padding и НЕ placement-настройка.
UI_COMMENT_CARD_TEXT_WIDTH_SAFETY_X = 1

-- Tiny vertical reserve for manual height measurement vs actual ImGui item layout.
-- It prevents false scrollbars on compact cards with metadata headers.
-- This is not padding and not a visual layout redesign.
UI_COMMENT_CARD_HEIGHT_SAFETY_Y = 4

-- Высота внутреннего text-child: 0 в MIN_H означает content-driven minimum.
-- Это важно для коротких однострочных комментариев: карточка не получает
-- искусственную минимальную высоту, если текст реально помещается в одну строку.
-- MAX_H ограничивает длинные комментарии и включает scrollbar при необходимости.
UI_COMMENT_CARD_INNER_CHILD_MIN_H = 0
UI_COMMENT_CARD_INNER_CHILD_MAX_H = 100

-- Вертикальные зазоры внутри карточки: ссылки, separator между comment blocks
-- и стандартный ItemSpacing. Header-зазора больше нет, потому что header удалён.
UI_COMMENT_CARD_ITEM_SPACING_X = 5.0
UI_COMMENT_CARD_ITEM_SPACING_Y = 5.0
UI_COMMENT_CARD_LINK_GAP_Y = UI_COMMENT_CARD_ITEM_SPACING_Y
UI_COMMENT_CARD_SEPARATOR_GAP_Y = UI_COMMENT_CARD_ITEM_SPACING_Y
UI_COMMENT_CARD_SEPARATOR_LINE_H = 1.0

-- Scrollbar text-child: actual size влияет на видимый scrollbar.
-- Reserved width применяется в measurement/wrap только после того, как расчёт
-- без scrollbar reserve доказал, что scroll действительно нужен. Так короткие
-- однострочные комментарии не получают ложную двухстрочную высоту.
UI_COMMENT_CARD_SCROLLBAR_SIZE = 12.0
UI_COMMENT_CARD_SCROLLBAR_RESERVED_W = UI_COMMENT_CARD_SCROLLBAR_SIZE + 2.0
UI_COMMENT_CARD_MANUAL_WHEEL_SCROLL_ENABLED = true
UI_COMMENT_CARD_WHEEL_STEP_MULT = 1
UI_COMMENT_CARD_WHEEL_MAX_TICKS_PER_FRAME = 1

-- Форма и обводка карточки. Border рисуется явно drawlist-обводкой.
-- По умолчанию border совпадает с телом карточки; THICKNESS можно поставить 0.
UI_COMMENT_CARD_CORNER_ROUNDING = 9.0
UI_COMMENT_CARD_BORDER_THICKNESS = 1.0

-- Legacy clamp margin setting сохранён для совместимости с tuning block.
-- В текущей anchored-follow модели карточка больше не зажимается в viewport:
-- она свободно едет за marker-ом и закрывается, когда полностью вышла за body.
UI_COMMENT_CARD_BODY_CLAMP_MARGIN = 0

-- Горизонтальное удержание anchored comment-card внутри видимого body/window.
-- Карточка может визуально залезать за белую страницу на общий фон, потому что
-- page margins НЕ используются как границы карточки. Но native overlay должен
-- оставаться внутри видимой области body/window по горизонтали.
-- Это НЕ page geometry, НЕ text padding и НЕ изменение размера карточки.
-- Верхняя/нижняя граница body остаётся строгой: vertical close policy сохранён.
UI_COMMENT_CARD_KEEP_INSIDE_BODY_X = true
UI_COMMENT_CARD_BODY_EDGE_MARGIN_X = 8

-- Горизонтальный резерв под вертикальный scrollbar основного body child.
-- Используется только в anchored comment-card keep-inside-body расчёте:
-- карточка не должна перекрывать правый scrollbar документа.
-- Это НЕ scrollbar самой карточки, НЕ page geometry и НЕ text padding.
UI_COMMENT_CARD_BODY_SCROLLBAR_RESERVED_W = 18

-- Смещение открытия относительно marker.
-- X остаётся обычным горизонтальным смещением от marker.
-- Y применяется к bottom-left якорю карточки: 0 прижимает нижний край
-- карточки к marker/top reference; положительные значения двигают карточку ниже,
-- отрицательные значения двигают карточку выше.
-- ABOVE_MARKER_GAP_Y сохранён для существующей clamp/fallback-логики.
UI_COMMENT_CARD_OPEN_OFFSET_X = 20
UI_COMMENT_CARD_OPEN_OFFSET_Y = 2
UI_COMMENT_CARD_ABOVE_MARKER_GAP_Y = 0

-- Общая прозрачность основного фона карточки: используется outer overlay window.
-- Значение должно быть в диапазоне 0–255; renderer дополнительно clamp-ит alpha
-- локально, чтобы случайное значение вне диапазона не ломало прозрачность.
UI_COMMENT_CARD_BG_ALPHA = 240

-- Диагностический console-output placement/candidate логики comment-card.
-- ВАЖНО: diagnostic-only; не должно менять placement, close policy или drag behavior.
PSV_COMMENT_CARD_DIAG_ENABLED = false

-- Visual-only DOCX comment range highlight.
-- Applied by the renderer only when a token carries token.comment_ids.
-- Nonlocal by design, following the existing PAGE_* / UI_COMMENT_CARD_*
-- settings pattern to avoid increasing Lua main-chunk local pressure.
UI_DOCX_COMMENT_RANGE_HIGHLIGHT_RGBA = {255, 221, 120, 82}

-- Temporary document-hover arbitration diagnostic. Disabled by default.
-- When manually enabled, render_paragraphs() prints only hover-kind changes
-- for document text hover zones: link / marker / DOCX range.
PSV_DOC_HOVER_DIAG_ENABLED = false

-- Temporary DOCX marker placement diagnostic. Disabled by default.
-- When manually enabled, the DOCX bridge prints suspicious marker/range
-- placement rows once during DOCX load/bridge, without changing refs/ranges/tokens.
PSV_DOCX_MARKER_PLACEMENT_DIAG_ENABLED = false

-- Temporary diagnostic-only DOCX paragraph/layout cross-export audit.
-- Console-only, bounded, used to compare Google Docs DOCX vs Word DOCX
-- paragraph XML/text/token geometry without changing import/render behavior.
PSV_DOCX_PARAGRAPH_FORMAT_DIAG_ENABLED = false
-- Temporary focused output mode: keep adapter ADAPTER_* diagnostics copyable
-- by suppressing noisy main-side BRIDGE / RENDER / RENDER_TOKEN console lines.
PSV_DOCX_PARAGRAPH_FORMAT_DIAG_ADAPTER_ONLY_OUTPUT = false
-- Temporary DOCX bridge/import normalization spike. When enabled, DOCX imports
-- conservatively drop only pure empty paragraphs before PSV paragraph creation.
PSV_DOCX_DROP_PURE_EMPTY_PARAGRAPHS = true

-- HTML import normalization. When enabled, HTML imports conservatively drop
-- pure empty <p> paragraphs so Google Docs HTML spacing matches the current
-- DOCX-style document flow more closely.
PSV_HTML_DROP_PURE_EMPTY_PARAGRAPHS = true
PSV_DOCX_PARAGRAPH_FORMAT_DIAG_MAX_ROWS = 80
PSV_DOCX_PARAGRAPH_FORMAT_DIAG_MATCH_TEXTS = {
  "bold",
  "italic",
  "underline",
  "strikethrough",
  "highlight",
  "habr.com"
}

-- Temporary DOCX comment ordering diagnostic. Disabled by default after the v3.0.121 diagnostic pass.
-- Console-only and bounded; does not change comment parsing, grouping, sorting,
-- range-click, marker click, or comment-card rendering behavior.
PSV_DOCX_COMMENT_ORDER_DIAG_ENABLED = false
PSV_DOCX_COMMENT_ORDER_DIAG_MAX_ROWS = 80

-- Temporary DOCX long-token layout diagnostic. Disabled by default after the v3.0.121 diagnostic pass.
-- Console-only, bounded and de-duplicated by file/paragraph/token/preview.
-- It identifies unbroken DOCX tokens that can overflow the readable text column.
PSV_DOCX_LONG_TOKEN_LAYOUT_DIAG_ENABLED = false
PSV_DOCX_LONG_TOKEN_LAYOUT_DIAG_MAX_ROWS = 60

-- Temporary DOCX direct-formatting token-boundary diagnostic.
-- Disabled by default after the temporary v3.0.134 diagnostic build.
-- Console-only and bounded; it must not change DOCX parsing, matching, splitting, spacing,
-- styling, rendering, comments, links, or layout behavior.
PSV_DOCX_RUN_BOUNDARY_DIAG_ENABLED = false
PSV_DOCX_RUN_BOUNDARY_DIAG_MAX_ROWS = 180
PSV_DOCX_RUN_BOUNDARY_DIAG_MATCH_TEXTS = {
  "форматирования",
  "bold",
  "italic",
  "underline"
}

-- Temporary renderer spacing / no_space_before visual-gap diagnostic.
-- Disabled by default after the temporary v3.0.137 diagnostic build.
-- Console-only and bounded; it must not change spacing, text positioning,
-- DOCX adapter output, HTML parsing, page-flow, comments, links, or layout behavior.
PSV_RENDER_SPACING_DIAG_ENABLED = false
PSV_RENDER_SPACING_DIAG_MAX_ROWS = 320
PSV_RENDER_SPACING_DIAG_MATCH_TEXTS = {
  "форматирования",
  "bold",
  "italic",
  "underline",
  "."
}
PSV_RENDER_SPACING_DIAG_BOOT_ONCE = true
PSV_RENDER_SPACING_DIAG_LOG_TARGET_TOKENS = true
PSV_RENDER_SPACING_DIAG_LOG_ADD_TOKEN = true
PSV_RENDER_SPACING_DIAG_LOG_LINE_TOKENS = true
PSV_RENDER_SPACING_DIAG_LOG_DRAW = true
PSV_RENDER_SPACING_DIAG_DRAW_RECTS = false

-- Corrected live-scroll layout/page-flow audit diagnostic. Disabled by default.
-- Console-only, bounded per file/epoch/scroll segment. It must not change
-- render, culling, page-flow, import, comments, links, placeholders, or cache
-- behavior. Enable manually by setting PSV_LAYOUT_AUDIT_ENABLED = true.
PSV_LAYOUT_AUDIT_ENABLED = false
PSV_LAYOUT_AUDIT_EPOCH = 1
PSV_LAYOUT_AUDIT_MAX_ROWS_PER_SEGMENT = 160
PSV_LAYOUT_AUDIT_SCROLL_SEGMENT_PX = 120
PSV_LAYOUT_AUDIT_MIN_SCROLL_DELTA_PX = 12
PSV_LAYOUT_AUDIT_VISIBLE_PAD_PX = 320
PSV_LAYOUT_AUDIT_PAGE_BOUNDARY_WINDOW_PX = 180
PSV_LAYOUT_AUDIT_LOG_SEGMENT_HEADER = true
PSV_LAYOUT_AUDIT_LOG_CULLING = true
PSV_LAYOUT_AUDIT_LOG_PAGE_JUMPS = true
PSV_LAYOUT_AUDIT_LOG_CACHE_UPDATES = true
PSV_LAYOUT_AUDIT_LOG_LINES_NEAR_PAGE_BOUNDARY = true
PSV_LAYOUT_AUDIT_LOG_VISIBLE_PARAGRAPHS = true

-- Custom native-like top-row menu family state.
-- Comments navigator is intentionally separate and is not part of this state.
PSV_TOP_ROW_CUSTOM_MENU_OPEN = PSV_TOP_ROW_CUSTOM_MENU_OPEN or nil

-- Session-only state for the future Comments sidebar.
-- Not persisted, not stored under paragraphs.comments, and intentionally kept
-- separate from PSV_TOP_ROW_CUSTOM_MENU_OPEN.
PSV_COMMENTS_SIDEBAR_OPEN = PSV_COMMENTS_SIDEBAR_OPEN or false
PSV_COMMENTS_SIDEBAR_LAST_BODY_W = PSV_COMMENTS_SIDEBAR_LAST_BODY_W or nil

-- Frame-local top-row Search geometry used by the Comments sidebar width pass.
-- This is not persisted and is refreshed whenever the Search field is rendered.
PSV_TOP_ROW_SEARCH_RECT_MIN_X = PSV_TOP_ROW_SEARCH_RECT_MIN_X or nil
PSV_TOP_ROW_SEARCH_RECT_MAX_X = PSV_TOP_ROW_SEARCH_RECT_MAX_X or nil

-- Цвета карточки как RGBA tuples: {R, G, B, A}.
-- OUTER_BG — единственный основной видимый translucent background layer.
-- INNER_BG по умолчанию прозрачный, чтобы не наслаивать второй alpha-слой
-- поверх outer background. FILL оставлен как ручная настройка body-color алиаса
-- для будущего тюнинга, но текущий renderer не рисует отдельный fill-layer.
-- BORDER по умолчанию совпадает с цветом карточки и слушает BORDER_THICKNESS.
UI_COMMENT_CARD_OUTER_BG_RGBA = {80, 80, 80, UI_COMMENT_CARD_BG_ALPHA}
UI_COMMENT_CARD_INNER_BG_RGBA = {80, 80, 80, 0}
UI_COMMENT_CARD_FILL_RGBA = UI_COMMENT_CARD_OUTER_BG_RGBA
UI_COMMENT_CARD_BORDER_RGBA = UI_COMMENT_CARD_OUTER_BG_RGBA
UI_COMMENT_CARD_TEXT_RGBA = {245, 245, 245, 255}
UI_COMMENT_CARD_LINK_RGBA = {198, 224, 255, 255}
UI_COMMENT_CARD_LINK_HOVER_RGBA = UI_COMMENT_CARD_LINK_RGBA
UI_COMMENT_CARD_SEPARATOR_RGBA = {245, 245, 245, 70}
UI_COMMENT_CARD_SCROLLBAR_BG_RGBA = {80, 80, 80, 0}
UI_COMMENT_CARD_SCROLLBAR_GRAB_RGBA = {160, 160, 160, 95}
UI_COMMENT_CARD_SCROLLBAR_GRAB_HOVER_RGBA = {175, 175, 175, 115}
UI_COMMENT_CARD_SCROLLBAR_GRAB_ACTIVE_RGBA = {190, 190, 190, 135}

-- ctx, search_filter and _fonts are nil/empty at module load time.
-- They are created once by ensure_imgui_resources(), which is called
-- after the startup delay and at the top of every loop() frame as a no-op guard.
local ctx           = nil
local search_filter = nil

local FONT_PX = {10,11,12,13,14,15,16,17,18,20,22,24,26,28,30,32,36,40,48}
local _fonts  = {}

local _imgui_resources_ready = false
local function ensure_imgui_resources()
  if _imgui_resources_ready then return end
  ctx = reaper.ImGui_CreateContext(SCRIPT_NAME)
  search_filter = reaper.ImGui_CreateTextFilter()
  reaper.ImGui_Attach(ctx, search_filter)
  _fonts.italic = _fonts.italic or {}
  _fonts.bold = _fonts.bold or {}
  _fonts.bold_italic = _fonts.bold_italic or {}
  for _, px in ipairs(FONT_PX) do
    local f = reaper.ImGui_CreateFont("sans-serif", 0)
    reaper.ImGui_Attach(ctx, f)
    _fonts[px] = f

    -- Source-backed ReaImGui font variant path:
    -- CreateFont(family, flags) creates the face, while PushFont(ctx, font, px)
    -- supplies the current size at render time. The regular face above uses
    -- FontFlags_None (0); pixel sizes are never passed as creation flags.
    local italic = reaper.ImGui_CreateFont("sans-serif", reaper.ImGui_FontFlags_Italic())
    reaper.ImGui_Attach(ctx, italic)
    _fonts.italic[px] = italic

    local bold = reaper.ImGui_CreateFont("sans-serif", reaper.ImGui_FontFlags_Bold())
    reaper.ImGui_Attach(ctx, bold)
    _fonts.bold[px] = bold

    local bold_italic = reaper.ImGui_CreateFont(
      "sans-serif",
      reaper.ImGui_FontFlags_Bold() | reaper.ImGui_FontFlags_Italic()
    )
    reaper.ImGui_Attach(ctx, bold_italic)
    _fonts.bold_italic[px] = bold_italic
  end
  _imgui_resources_ready = true
end

local function get_font(px, variant)
  px = math.max(UI_FONT_SIZE_MIN, math.min(48, math.floor(px + 0.5)))

  if variant == "italic" or variant == "bold" or variant == "bold_italic" then
    local variant_fonts = _fonts[variant]
    if not variant_fonts then return nil end
    if variant_fonts[px] then return variant_fonts[px] end
    for d = 1, 20 do
      if variant_fonts[px - d] then return variant_fonts[px - d] end
      if variant_fonts[px + d] then return variant_fonts[px + d] end
    end
    return variant_fonts[UI_FONT_SIZE_DEFAULT]
  end

  if _fonts[px] then return _fonts[px] end
  for d = 1, 20 do
    if _fonts[px - d] then return _fonts[px - d] end
    if _fonts[px + d] then return _fonts[px + d] end
  end
  return _fonts[UI_FONT_SIZE_DEFAULT]
end

-- ══════════════════════════════════════════════════════════════
--  COLOURS
-- ══════════════════════════════════════════════════════════════

-- ВАЖНО:
-- Эта версия уходит от самодельного "угадывания" packed-формата цвета.
-- Основной путь теперь канонический для ReaImGui:
--   ImGui_ColorConvertDouble4ToU32
--
-- Если в конкретной сборке/версии helper недоступен,
-- используется fallback ради совместимости.

local function rgba(r, g, b, a)
  a = a or 255

  if reaper.ImGui_ColorConvertDouble4ToU32 then
    return reaper.ImGui_ColorConvertDouble4ToU32(
      r / 255.0,
      g / 255.0,
      b / 255.0,
      a / 255.0
    )
  end

  -- Compatibility fallback.
  -- Оставлен только как запасной путь для старых сборок.
  return (a * 0x1000000) + (b * 0x10000) + (g * 0x100) + r
end

local function u32_to_rgba(col)
  if reaper.ImGui_ColorConvertU32ToDouble4 then
    local r, g, b, a = reaper.ImGui_ColorConvertU32ToDouble4(col)
    return math.floor(r * 255 + 0.5),
           math.floor(g * 255 + 0.5),
           math.floor(b * 255 + 0.5),
           math.floor(a * 255 + 0.5)
  end

  -- Compatibility fallback paired with the fallback pack path above.
  local r = col & 0xFF
  local g = (col >> 8) & 0xFF
  local b = (col >> 16) & 0xFF
  local a = (col >> 24) & 0xFF
  return r, g, b, a
end

local function luminance(col)
  local r, g, b = u32_to_rgba(col)
  return r * 0.2126 + g * 0.7152 + b * 0.0722
end

-- ══════════════════════════════════════════════════════════════
--  PAGE LAYOUT: THEMES AND DRAWLIST BACKGROUND LAYER
-- ══════════════════════════════════════════════════════════════
-- C_PAPER объявлен заранее, потому что render_page_layer(ctx) определён
-- раньше основного paper/chrome color block. Без forward declaration Lua
-- искал бы глобальный C_PAPER внутри render_page_layer(), и цвет фона
-- мог бы стать nil до последующей локальной инициализации.
local C_PAPER
-- Drawlist-only визуальная разбивка на страницы внутри ##body.
-- Модель намеренно повторяет page_layout_addon.lua: читаем только metrics
-- текущего body child и рисуем background/pages до render_paragraphs().
-- Core text layout, wrapping, margins, search и comments не меняются.
PAGE_THEMES = {
  -- Pages / Warm page-layer colors. Kept in the existing PAGE_THEMES table
  -- because render_page_layer(ctx) already consumes this color contract.
  -- The user-facing selector remains the existing Theme menu only.
  warm = {
    app_bg      = rgba(217, 215, 209),
    page_bg     = rgba(245, 244, 240),
    shadow_col  = rgba(80, 50, 20, 26),
    shadow_col2 = rgba(80, 50, 20, 46),
    shadow_col3 = rgba(80, 50, 20, 10),
    border_col  = rgba(208, 206, 201, 140),
    gutter_col  = rgba(217, 215, 209),
    pagenum_col = rgba(153, 153, 153),
  },
  classic = {
    app_bg      = rgba(217, 215, 209),
    page_bg     = rgba(245, 244, 240),
    shadow_col  = rgba(0, 0, 0, 31),
    shadow_col2 = rgba(0, 0, 0, 46),
    shadow_col3 = rgba(0, 0, 0, 10),
    border_col  = rgba(208, 206, 201, 140),
    gutter_col  = rgba(217, 215, 209),
    pagenum_col = rgba(153, 153, 153),
  },
  reaper_grey = {
    app_bg      = rgba(218, 218, 218),
    page_bg     = rgba(244, 244, 244),
    shadow_col  = rgba(0, 0, 0, 34),
    shadow_col2 = rgba(0, 0, 0, 20),
    shadow_col3 = rgba(0, 0, 0, 8),
    border_col  = rgba(104, 120, 114, 100),
    gutter_col  = rgba(218, 218, 218),
    pagenum_col = rgba(112, 112, 112),
  },
  google_docs_white = {
    app_bg      = rgba(241, 243, 244),
    page_bg     = rgba(255, 255, 255),
    shadow_col  = rgba(0, 0, 0, 28),
    shadow_col2 = rgba(0, 0, 0, 14),
    shadow_col3 = rgba(0, 0, 0, 6),
    border_col  = rgba(218, 220, 224, 120),
    gutter_col  = rgba(241, 243, 244),
    pagenum_col = rgba(95, 99, 104),
  },
  dark = {
    app_bg      = rgba(36, 35, 40),
    page_bg     = rgba(248, 244, 238),
    shadow_col  = rgba(0, 0, 0, 90),
    shadow_col2 = rgba(0, 0, 0, 50),
    shadow_col3 = rgba(0, 0, 0, 20),
    border_col  = rgba(180, 175, 165, 50),
    gutter_col  = rgba(52, 51, 58),
    pagenum_col = rgba(130, 125, 120),
  },
}

local function page_shadow_smoothstep(t)
  return t * t * (3 - 2 * t)
end

local function page_shadow_rgba_float(r, g, b, a)
  return rgba(
    math.floor((r or 0) * 255 + 0.5),
    math.floor((g or 0) * 255 + 0.5),
    math.floor((b or 0) * 255 + 0.5),
    math.floor((a or 0) * 255 + 0.5)
  )
end

local function draw_page_gradient_shadow(dl, px, py, pw, ph, rounding)
  if not PAGE_SHADOW_ENABLED then return end

  local steps = math.max(1, math.floor(tonumber(PAGE_SHADOW_N_STEPS) or 10))
  local layers = {
    {
      dx = PAGE_SHADOW_AMBIENT_DX,
      dy = PAGE_SHADOW_AMBIENT_DY,
      blur_t = PAGE_SHADOW_AMBIENT_BLUR_T,
      blur_r = PAGE_SHADOW_AMBIENT_BLUR_R,
      blur_b = PAGE_SHADOW_AMBIENT_BLUR_B,
      blur_l = PAGE_SHADOW_AMBIENT_BLUR_L,
      alpha = PAGE_SHADOW_AMBIENT_ALPHA,
      r = PAGE_SHADOW_AMBIENT_R,
      g = PAGE_SHADOW_AMBIENT_G,
      b = PAGE_SHADOW_AMBIENT_B,
    },
    {
      dx = PAGE_SHADOW_CONTACT_DX,
      dy = PAGE_SHADOW_CONTACT_DY,
      blur_t = PAGE_SHADOW_CONTACT_BLUR_T,
      blur_r = PAGE_SHADOW_CONTACT_BLUR_R,
      blur_b = PAGE_SHADOW_CONTACT_BLUR_B,
      blur_l = PAGE_SHADOW_CONTACT_BLUR_L,
      alpha = PAGE_SHADOW_CONTACT_ALPHA,
      r = PAGE_SHADOW_CONTACT_R,
      g = PAGE_SHADOW_CONTACT_G,
      b = PAGE_SHADOW_CONTACT_B,
    },
  }

  for _, L in ipairs(layers) do
    for step_i = 0, steps - 1 do
      local t_raw = (steps == 1) and 1 or (step_i / (steps - 1))
      local t_eased = page_shadow_smoothstep(t_raw)
      local f = 1 - t_raw
      local alpha = (tonumber(L.alpha) or 0) * t_eased

      if alpha > 0 then
        local col = page_shadow_rgba_float(
          tonumber(L.r) or 0,
          tonumber(L.g) or 0,
          tonumber(L.b) or 0,
          alpha
        )

        reaper.ImGui_DrawList_AddRectFilled(
          dl,
          px + (tonumber(L.dx) or 0) - (tonumber(L.blur_l) or 0) * f,
          py + (tonumber(L.dy) or 0) - (tonumber(L.blur_t) or 0) * f,
          px + pw + (tonumber(L.dx) or 0) + (tonumber(L.blur_r) or 0) * f,
          py + ph + (tonumber(L.dy) or 0) + (tonumber(L.blur_b) or 0) * f,
          col,
          rounding
        )
      end
    end
  end
end


function get_page_text_horizontal_geometry(ctx, cursor_cx, cursor_sx, margin_left, margin_right, indent_first_line)
  local body_window_sx = select(1, reaper.ImGui_GetWindowPos(ctx))
  local body_window_w = select(1, reaper.ImGui_GetWindowSize(ctx))
  body_window_sx = tonumber(body_window_sx) or 0
  body_window_w = math.max(1, tonumber(body_window_w) or 1)

  local page_left_sx = body_window_sx + (tonumber(PAGE_MARGIN_LEFT) or 0)
  local page_right_sx = body_window_sx + body_window_w - (tonumber(PAGE_MARGIN_RIGHT) or 0)
  if page_right_sx < page_left_sx + 100 then
    page_right_sx = page_left_sx + 100
  end
  local page_w = math.max(1, page_right_sx - page_left_sx)

  local user_left_margin = clamp_body_text_margin(
    margin_left,
    UI_BODY_TEXT_MARGIN_LEFT_DEFAULT
  )
  local user_right_margin = clamp_body_text_margin(
    margin_right,
    UI_BODY_TEXT_MARGIN_RIGHT_DEFAULT
  )

  local extra_pad_left = math.max(0, tonumber(PAGE_CONTENT_PAD_LEFT) or 0)
  local extra_pad_right = math.max(0, tonumber(PAGE_CONTENT_PAD_RIGHT) or 0)
  local content_left_sx = page_left_sx + user_left_margin + extra_pad_left
  local content_right_sx = page_right_sx - user_right_margin - extra_pad_right

  if content_left_sx < page_left_sx then content_left_sx = page_left_sx end
  if content_right_sx > page_right_sx then content_right_sx = page_right_sx end

  local wrap_reserve = math.max(0, tonumber(UI_WRAP_RIGHT_RESERVE) or 0)
  local min_wrap_w = 40
  local min_content_w = wrap_reserve + min_wrap_w
  if content_right_sx < content_left_sx + min_content_w then
    content_right_sx = math.min(page_right_sx, content_left_sx + min_content_w)
    if content_right_sx < content_left_sx + min_content_w then
      content_left_sx = math.max(page_left_sx, content_right_sx - min_content_w)
    end
  end

  local content_w = math.max(1, content_right_sx - content_left_sx)
  local first_indent = tonumber(indent_first_line) or 0
  local continuation_left_sx = content_left_sx
  local first_line_left_sx = content_left_sx + first_indent
  local wrap_right_sx = content_right_sx - wrap_reserve
  if wrap_right_sx < continuation_left_sx + min_wrap_w then
    wrap_right_sx = continuation_left_sx + min_wrap_w
  end

  local geom = {
    body_window_sx = body_window_sx,
    body_window_w = body_window_w,
    page_left_sx = page_left_sx,
    page_right_sx = page_right_sx,
    page_w = page_w,
    content_left_sx = content_left_sx,
    content_right_sx = content_right_sx,
    content_w = content_w,
    continuation_left_sx = continuation_left_sx,
    first_line_left_sx = first_line_left_sx,
    wrap_right_sx = wrap_right_sx,
    placeholder_center_left_sx = content_left_sx,
    placeholder_center_right_sx = content_right_sx,
  }

  if type(cursor_cx) == "number" and type(cursor_sx) == "number" then
    geom.content_left_cx = cursor_cx + (content_left_sx - cursor_sx)
    geom.continuation_left_cx = cursor_cx + (continuation_left_sx - cursor_sx)
    geom.first_line_left_cx = cursor_cx + (first_line_left_sx - cursor_sx)
  end

  return geom
end

function render_page_layer(ctx)
  if not PAGE_LAYOUT_ENABLED then return end

  local theme = PAGE_THEMES[page_layout_theme] or PAGE_THEMES.classic
  local dl = reaper.ImGui_GetWindowDrawList(ctx)
  local win_x, win_y = reaper.ImGui_GetWindowPos(ctx)
  local win_w, win_h = reaper.ImGui_GetWindowSize(ctx)
  local scroll_y = reaper.ImGui_GetScrollY(ctx)
  local scroll_max_y = reaper.ImGui_GetScrollMaxY(ctx)
  local content_h = math.max(win_h, scroll_max_y + win_h)
  local body_bg_col = C_PAPER or theme.page_bg or theme.app_bg

  -- 1) Фон всего видимого body child берётся из основной UI-темы.
  -- Page layer больше не владеет app/background цветом вокруг страниц:
  -- PAGE_THEMES сохраняет page sheet/shadow/border, а общий body background
  -- следует C_PAPER, как в более простой paper/chrome модели. Fallback ниже
  -- только защищает drawlist от nil-цвета, если theme init ещё не завершён.
  reaper.ImGui_DrawList_AddRectFilled(
    dl,
    win_x, win_y,
    win_x + win_w, win_y + win_h,
    body_bg_col
  )

  -- 2) Страницы используют тот же horizontal geometry contract, что и
  -- текстовая колонка: page sheet bounds берутся из shared helper, а content
  -- padding используется только render_paragraphs().
  local page_geom = get_page_text_horizontal_geometry(
    ctx,
    nil,
    nil,
    UI_BODY_TEXT_MARGIN_LEFT_DEFAULT,
    UI_BODY_TEXT_MARGIN_RIGHT_DEFAULT,
    0
  )

  local slot_h = PAGE_H + PAGE_GAP_Y
  local page_stack_top_gap = math.max(0, tonumber(PAGE_STACK_TOP_GAP) or 0)
  local page_stack_bottom_gap = math.max(0, tonumber(PAGE_STACK_BOTTOM_GAP) or 0)
  local drawable_h = math.max(0, content_h - page_stack_top_gap - page_stack_bottom_gap)
  local page_count = math.max(1, math.floor(drawable_h / slot_h) + 1)
  for i = 0, page_count - 1 do
    local doc_top = page_stack_top_gap + i * slot_h
    local doc_bottom = doc_top + PAGE_H
    local sx1 = page_geom.page_left_sx
    local sy1 = win_y + doc_top - scroll_y
    local sx2 = page_geom.page_right_sx
    local sy2 = win_y + doc_bottom - scroll_y

    -- Culling: рисуем только страницы, которые могут попасть в видимый body.
    if not (sy2 < win_y - 20 or sy1 > win_y + win_h + 20) then
      -- CSS-like page shadow approximation без настоящего blur.
      -- Сначала рисуется двухслойная gradient/smoothstep тень, затем лист
      -- перекрывает внутренние shadow-rects своим fill, как в box-shadow модели.
      draw_page_gradient_shadow(
        dl,
        sx1,
        sy1,
        sx2 - sx1,
        sy2 - sy1,
        PAGE_ROUNDING + PAGE_SHADOW_ROUNDING_EXTRA
      )

      reaper.ImGui_DrawList_AddRectFilled(
        dl,
        sx1, sy1,
        sx2, sy2,
        theme.page_bg,
        PAGE_ROUNDING
      )

      if PAGE_BORDER_ENABLED then
        local border_col = theme.border_col
        local border_alpha_mult = tonumber(PAGE_BORDER_ALPHA_MULT) or 1.0
        if border_alpha_mult < 0 then border_alpha_mult = 0 end
        if border_alpha_mult > 1 then border_alpha_mult = 1 end

        if border_alpha_mult < 1.0 then
          local br, bg, bb, ba = u32_to_rgba(theme.border_col)
          border_col = rgba(br, bg, bb, math.floor(ba * border_alpha_mult + 0.5))
        end

        local border_inset = tonumber(PAGE_BORDER_INSET) or 0
        if border_inset < 0 then border_inset = 0 end
        local border_thickness = tonumber(PAGE_BORDER_THICKNESS) or 1.0
        if border_thickness < 0.5 then border_thickness = 0.5 end

        reaper.ImGui_DrawList_AddRect(
          dl,
          sx1 + border_inset, sy1 + border_inset,
          sx2 - border_inset, sy2 - border_inset,
          border_col,
          PAGE_ROUNDING,
          reaper.ImGui_DrawFlags_None(),
          border_thickness
        )
      end

      -- Номер страницы — декоративный ориентир, не Google Docs pagination.
      if sy2 > win_y and sy2 < win_y + win_h + 30 then
        local page_num_str = tostring(i + 1)
        local num_font = get_font(11)
        reaper.ImGui_PushFont(ctx, num_font, 11)
        local num_w, num_h = reaper.ImGui_CalcTextSize(ctx, page_num_str)
        reaper.ImGui_DrawList_AddText(
          dl,
          sx2 - num_w - 18,
          sy2 - num_h - 14,
          theme.pagenum_col,
          page_num_str
        )
        reaper.ImGui_PopFont(ctx)
      end
    end
  end
end

-- ── Paper / chrome palette (migrated from podcast_viewer_v6.lua) ────────
-- Сохраняем текущий paper-style viewer contract:
-- документ остаётся тёплым бумажным по ощущению,
-- а расширяем только chrome/style слой вокруг него.

-- Paper (контентная зона документа)
C_PAPER              = rgba(248, 244, 236)  -- тёплый кремовый белый
local C_TEXT         = rgba(28,  24,  18)   -- тёплый почти-чёрный
local C_DIM          = rgba(130, 118, 100)  -- dim-текст, подсказки

-- Chrome (UI-оболочка)
local C_CHROME       = rgba(232, 228, 220)  -- общий фон UI-хрома
local C_CHROME_DEEP  = rgba(215, 210, 200)  -- более глубокий active-слой
local C_CHROME_TITLE = rgba(224, 220, 211)  -- неактивный title/chrome tone

-- Интерактивные состояния
local C_HEAD         = rgba(210, 204, 192)  -- hover/selected
local C_HEAD_H       = rgba(196, 189, 175)  -- pressed/active
local C_FRAME        = rgba(255, 255, 252)  -- фон поля ввода

-- Семантика UI-хрома
local C_LINE         = rgba(196, 190, 178)  -- separator/border
local C_MENU_BORDER  = C_LINE                 -- popup/window border, theme-overridable
local C_SCROLL       = rgba(192, 186, 174)  -- scrollbar grab
local C_SCROLL_H     = rgba(170, 163, 149)  -- scrollbar hover
local C_SCROLL_A     = rgba(148, 140, 126)  -- scrollbar active
local C_SCROLL_BG    = rgba(232, 228, 220)  -- scrollbar track

-- Локальные оттенки для поля поиска.
-- Они не меняют общий theme direction,
-- а только возвращают нормальную active-edit читаемость после theme migration.
local C_SEARCH_FRAME_H = rgba(250, 248, 242)
local C_SEARCH_FRAME_A = rgba(255, 252, 246)
local C_SEARCH_ACTIVE_BORDER = rgba(196, 189, 175)

-- Disabled search field colors for empty-document state.
-- These keep the same geometry as the active search field but read as inactive:
-- pale fill, faint border, and low-emphasis placeholder text.
local C_SEARCH_DISABLED_FRAME = rgba(240, 237, 229)
local C_SEARCH_DISABLED_BORDER = rgba(222, 216, 205)
local C_SEARCH_DISABLED_TEXT = rgba(176, 166, 148)
local C_SEARCH_FIELD_BORDER = C_SEARCH_DISABLED_BORDER

-- View settings controls colors.
-- Extraction-only: цвета совпадают с локальной палитрой v1.3.56
-- и вынесены сюда для ручного визуального тюнинга.
local C_VIEW_SLIDER_TRACK = rgba(214, 208, 196)
local C_VIEW_SLIDER_FILL = rgba(94, 124, 164)
local C_VIEW_SLIDER_KNOB_FILL = rgba(255, 255, 252)
local C_VIEW_SLIDER_KNOB_OUTLINE = rgba(94, 124, 164)

local C_VIEW_BUTTON_FILL = rgba(245, 242, 235)
local C_VIEW_BUTTON_HOVER = rgba(238, 234, 225)
local C_VIEW_BUTTON_ACTIVE = rgba(228, 222, 211)
local C_VIEW_BUTTON_BORDER = rgba(194, 187, 174)
local C_VIEW_BUTTON_TEXT = C_TEXT

-- Отдельная визуальная подсветка search-hit.
-- Она намеренно отличается от импортированной document highlight-подложки:
-- здесь используем не новую заливку, а тонкую заметную рамку.
local C_SEARCH_HIT = rgba(214, 154, 44, 255)

-- Мягкий разделитель между абзацами только в активном search mode.
-- Это локальный visual aid для быстрого сканирования найденных абзацев,
-- а не новый глобальный layout-стиль документа.
local C_SEARCH_SEPARATOR = rgba(218, 208, 190, 255)

-- ══════════════════════════════════════════════════════════════
--  UI THEME
-- ══════════════════════════════════════════════════════════════

-- Paper is the primary/default visual scheme.
-- Missing or invalid ExtState must always fall back to Paper, not REAPER Grey.
local UI_THEME_DEFAULT = "paper"
local ui_theme = UI_THEME_DEFAULT

-- Theme tables intentionally assign the existing C_* chrome variables.
-- Imported document token colors/highlights stay untouched: tok.fg/tok.bg are
-- still taken from the HTML parser, and the paper document area remains light.
local UI_THEMES = {
  paper = {
    label = "Pages",
    PAGE_THEME_KEY = "warm",

    C_PAPER = rgba(217, 215, 209),
    C_TEXT = rgba(28, 28, 28),
    C_DIM = rgba(153, 153, 153),

    C_CHROME = rgba(236, 234, 229),
    C_CHROME_DEEP = rgba(208, 206, 201),
    C_CHROME_TITLE = rgba(236, 234, 229),

    C_HEAD = rgba(225, 223, 218),
    C_HEAD_H = rgba(208, 206, 201),
    C_FRAME = rgba(245, 244, 240),

    C_LINE = rgba(208, 206, 201),
    C_MENU_BORDER = rgba(208, 206, 201),
    C_SCROLL = rgba(158, 155, 149),
    C_SCROLL_H = rgba(174, 172, 166),
    C_SCROLL_A = rgba(140, 137, 131),
    C_SCROLL_BG = rgba(217, 215, 209),

    C_SEARCH_FRAME_H = rgba(245, 244, 240),
    C_SEARCH_FRAME_A = rgba(250, 249, 245),
    C_SEARCH_ACTIVE_BORDER = rgba(208, 206, 201),
    C_SEARCH_DISABLED_FRAME = rgba(239, 237, 232),
    C_SEARCH_DISABLED_BORDER = rgba(208, 206, 201),
    C_SEARCH_DISABLED_TEXT = rgba(153, 153, 153),
    C_SEARCH_FIELD_BORDER = rgba(208, 206, 201),

    C_VIEW_SLIDER_TRACK = rgba(200, 198, 192),
    C_VIEW_SLIDER_FILL = rgba(74, 124, 199),
    C_VIEW_SLIDER_KNOB_FILL = rgba(245, 244, 240),
    C_VIEW_SLIDER_KNOB_OUTLINE = rgba(74, 124, 199),

    C_VIEW_BUTTON_FILL = rgba(245, 244, 240),
    C_VIEW_BUTTON_HOVER = rgba(236, 234, 229),
    C_VIEW_BUTTON_ACTIVE = rgba(225, 223, 218),
    C_VIEW_BUTTON_BORDER = rgba(208, 206, 201),

    C_SEARCH_HIT = rgba(74, 124, 199, 255),
    C_SEARCH_SEPARATOR = rgba(208, 206, 201, 255),
  },

  reaper_grey = {
    label = "REAPER Grey",
    PAGE_THEME_KEY = "reaper_grey",

    -- Light grey document/body surface for REAPER Grey.
    -- Imported Google Docs token colours/highlights remain unchanged.
    C_PAPER = rgba(239, 239, 239),
    C_TEXT = rgba(28, 24, 18),
    C_DIM = rgba(112, 112, 112),

    C_CHROME = rgba(218, 218, 218),
    C_CHROME_DEEP = rgba(92, 112, 104),
    C_CHROME_TITLE = rgba(112, 132, 122),

    C_HEAD = rgba(202, 206, 210),
    C_HEAD_H = rgba(188, 193, 198),
    C_FRAME = rgba(250, 250, 250),

    C_LINE = rgba(104, 120, 114),
    C_MENU_BORDER = rgba(104, 120, 114, 60),
    C_SCROLL = rgba(176, 176, 176),
    C_SCROLL_H = rgba(154, 154, 154),
    C_SCROLL_A = rgba(132, 132, 132),
    C_SCROLL_BG = rgba(239, 239, 239),

    C_SEARCH_FRAME_H = rgba(252, 252, 252),
    C_SEARCH_FRAME_A = rgba(255, 255, 255),
    C_SEARCH_ACTIVE_BORDER = rgba(174, 174, 174),
    C_SEARCH_DISABLED_FRAME = rgba(232, 232, 232),
    C_SEARCH_DISABLED_BORDER = rgba(198, 198, 198),
    C_SEARCH_DISABLED_TEXT = rgba(156, 156, 156),
    C_SEARCH_FIELD_BORDER = rgba(198, 198, 198),

    C_VIEW_SLIDER_TRACK = rgba(196, 196, 196),
    C_VIEW_SLIDER_FILL = rgba(86, 104, 124),
    C_VIEW_SLIDER_KNOB_FILL = rgba(252, 252, 252),
    C_VIEW_SLIDER_KNOB_OUTLINE = rgba(86, 104, 124),

    C_VIEW_BUTTON_FILL = rgba(238, 238, 238),
    C_VIEW_BUTTON_HOVER = rgba(226, 226, 226),
    C_VIEW_BUTTON_ACTIVE = rgba(214, 214, 214),
    C_VIEW_BUTTON_BORDER = rgba(174, 174, 174),

    -- Search hit overlays remain the same semantic document aid.
    C_SEARCH_HIT = rgba(214, 154, 44, 255),
    C_SEARCH_SEPARATOR = rgba(218, 208, 190, 255),
  },

  google_docs_white = {
    label = "Google Docs White",
    PAGE_THEME_KEY = "google_docs_white",

    -- White Google Docs-like document/body surface with cool, light Material-style chrome.
    -- Imported Google Docs token colours/highlights remain unchanged.
    C_PAPER = rgba(241, 243, 244),
    C_TEXT = rgba(32, 33, 36),
    C_DIM = rgba(95, 99, 104),

    C_CHROME = rgba(248, 250, 253),
    C_CHROME_DEEP = rgba(232, 240, 254),
    C_CHROME_TITLE = rgba(248, 250, 253),

    C_HEAD = rgba(232, 240, 254),
    C_HEAD_H = rgba(210, 227, 252),
    C_FRAME = rgba(255, 255, 255),

    C_LINE = rgba(218, 220, 224),
    C_MENU_BORDER = rgba(218, 220, 224),
    C_SCROLL = rgba(189, 193, 198),
    C_SCROLL_H = rgba(154, 160, 166),
    C_SCROLL_A = rgba(128, 134, 139),
    C_SCROLL_BG = rgba(241, 243, 244),

    C_SEARCH_FRAME_H = rgba(255, 255, 255),
    C_SEARCH_FRAME_A = rgba(255, 255, 255),
    C_SEARCH_ACTIVE_BORDER = rgba(26, 115, 232),
    C_SEARCH_DISABLED_FRAME = rgba(241, 243, 244),
    C_SEARCH_DISABLED_BORDER = rgba(218, 220, 224),
    C_SEARCH_DISABLED_TEXT = rgba(128, 134, 139),
    C_SEARCH_FIELD_BORDER = rgba(218, 220, 224),

    C_VIEW_SLIDER_TRACK = rgba(218, 220, 224),
    C_VIEW_SLIDER_FILL = rgba(26, 115, 232),
    C_VIEW_SLIDER_KNOB_FILL = rgba(255, 255, 255),
    C_VIEW_SLIDER_KNOB_OUTLINE = rgba(26, 115, 232),

    C_VIEW_BUTTON_FILL = rgba(255, 255, 255),
    C_VIEW_BUTTON_HOVER = rgba(241, 243, 244),
    C_VIEW_BUTTON_ACTIVE = rgba(232, 240, 254),
    C_VIEW_BUTTON_BORDER = rgba(218, 220, 224),

    -- Search hit overlays remain the same semantic document aid.
    C_SEARCH_HIT = rgba(214, 154, 44, 255),
    C_SEARCH_SEPARATOR = rgba(218, 208, 190, 255),
  },
}
local function normalize_ui_theme(theme_name)
  if theme_name and UI_THEMES[theme_name] then
    return theme_name
  end
  return UI_THEME_DEFAULT
end

local function apply_ui_theme(theme_name)
  theme_name = normalize_ui_theme(theme_name)
  local theme = UI_THEMES[theme_name]

  ui_theme = theme_name

  C_PAPER = theme.C_PAPER
  C_TEXT = theme.C_TEXT
  C_DIM = theme.C_DIM

  C_CHROME = theme.C_CHROME
  C_CHROME_DEEP = theme.C_CHROME_DEEP
  C_CHROME_TITLE = theme.C_CHROME_TITLE

  C_HEAD = theme.C_HEAD
  C_HEAD_H = theme.C_HEAD_H
  C_FRAME = theme.C_FRAME

  C_LINE = theme.C_LINE
  C_MENU_BORDER = theme.C_MENU_BORDER or theme.C_LINE
  C_SCROLL = theme.C_SCROLL
  C_SCROLL_H = theme.C_SCROLL_H
  C_SCROLL_A = theme.C_SCROLL_A
  C_SCROLL_BG = theme.C_SCROLL_BG

  C_SEARCH_FRAME_H = theme.C_SEARCH_FRAME_H
  C_SEARCH_FRAME_A = theme.C_SEARCH_FRAME_A
  C_SEARCH_ACTIVE_BORDER = theme.C_SEARCH_ACTIVE_BORDER
  C_SEARCH_DISABLED_FRAME = theme.C_SEARCH_DISABLED_FRAME
  C_SEARCH_DISABLED_BORDER = theme.C_SEARCH_DISABLED_BORDER
  C_SEARCH_DISABLED_TEXT = theme.C_SEARCH_DISABLED_TEXT
  C_SEARCH_FIELD_BORDER = theme.C_SEARCH_FIELD_BORDER

  C_VIEW_SLIDER_TRACK = theme.C_VIEW_SLIDER_TRACK
  C_VIEW_SLIDER_FILL = theme.C_VIEW_SLIDER_FILL
  C_VIEW_SLIDER_KNOB_FILL = theme.C_VIEW_SLIDER_KNOB_FILL
  C_VIEW_SLIDER_KNOB_OUTLINE = theme.C_VIEW_SLIDER_KNOB_OUTLINE

  C_VIEW_BUTTON_FILL = theme.C_VIEW_BUTTON_FILL
  C_VIEW_BUTTON_HOVER = theme.C_VIEW_BUTTON_HOVER
  C_VIEW_BUTTON_ACTIVE = theme.C_VIEW_BUTTON_ACTIVE
  C_VIEW_BUTTON_BORDER = theme.C_VIEW_BUTTON_BORDER
  C_VIEW_BUTTON_TEXT = C_TEXT

  C_SEARCH_HIT = theme.C_SEARCH_HIT
  C_SEARCH_SEPARATOR = theme.C_SEARCH_SEPARATOR

  -- Keep the visual page layer synchronized with the active user-facing Theme.
  -- This does not add a second selector; it only maps the existing Theme choice
  -- to the already-existing PAGE_THEMES color contract used by render_page_layer().
  if theme.PAGE_THEME_KEY and PAGE_THEMES and PAGE_THEMES[theme.PAGE_THEME_KEY] then
    page_layout_theme = theme.PAGE_THEME_KEY
  end
end

local function load_ui_theme()
  local saved = reaper.GetExtState(EXTSTATE_SEC, "ui_theme")
  apply_ui_theme(saved)
end

local function save_ui_theme()
  ui_theme = normalize_ui_theme(ui_theme)
  reaper.SetExtState(EXTSTATE_SEC, "ui_theme", ui_theme, true)
end

local function set_ui_theme(theme_name)
  apply_ui_theme(theme_name)
  save_ui_theme()
end

-- Session-only deferred theme switch. Interactive Theme menu clicks request
-- a change here and the next frame applies it before any style colors are
-- derived/pushed, preventing one mixed old/new theme frame.
PSV_PENDING_UI_THEME = PSV_PENDING_UI_THEME or nil

local function request_ui_theme_change(theme_name)
  theme_name = normalize_ui_theme(theme_name)
  if theme_name == ui_theme then
    PSV_PENDING_UI_THEME = nil
    return
  end
  PSV_PENDING_UI_THEME = theme_name
end

local function apply_pending_ui_theme_if_needed()
  if not PSV_PENDING_UI_THEME then return end
  local theme_name = normalize_ui_theme(PSV_PENDING_UI_THEME)
  PSV_PENDING_UI_THEME = nil
  set_ui_theme(theme_name)
end

-- Ensure missing/invalid theme state starts from Paper until persisted settings load.
apply_ui_theme(UI_THEME_DEFAULT)

-- ══════════════════════════════════════════════════════════════
--  STATE
-- ══════════════════════════════════════════════════════════════

local paragraphs         = {}
local file_path          = nil
local font_size          = UI_FONT_SIZE_DEFAULT
comments_nav_font_size   = comments_nav_font_size or UI_COMMENTS_NAV_FONT_SIZE_DEFAULT
local body_margin_left   = clamp_body_text_margin(UI_BODY_TEXT_MARGIN_LEFT_DEFAULT, UI_BODY_TEXT_MARGIN_LEFT_DEFAULT)
local body_margin_right  = clamp_body_text_margin(UI_BODY_TEXT_MARGIN_RIGHT_DEFAULT, UI_BODY_TEXT_MARGIN_RIGHT_DEFAULT)
local first_line_indent  = UI_FIRST_LINE_INDENT_DEFAULT
local line_spacing       = UI_LINE_SPACING_DEFAULT
local paragraph_spacing  = UI_PARAGRAPH_SPACING_DEFAULT
local win_open           = true
local last_proj_key      = nil
local owner_project_key  = nil
-- The pointer owns the live instance; path-based keys remain persistence-only.
local owner_project      = nil
local show_about_overlay = false

local STARTUP_HIDE_FRAMES = UI_STARTUP_HIDE_FRAMES
local startup_frames      = 0
local startup_refresh_done = false
local startup_boot_phase   = 0

local search_nav_index         = 0
local search_nav_scroll_target = nil
local search_nav_occurrence = nil
local search_input_buf         = ""
local search_input_active      = false
local escape_key_owner         = nil

-- Empty-state panel warmup.
-- After Clear/project restore/unsupported HTML, the first body-frame can expose
-- transient content geometry, so we skip only the centered panel for one frame
-- and still submit the body-sized Dummy item to keep child layout valid.
local empty_state_layout_warmup_frames = 0
local owner_mismatch_hidden_last_frame = false

local function request_empty_state_layout_warmup()
  empty_state_layout_warmup_frames = 1
end

-- ══════════════════════════════════════════════════════════════
--  TEMPORARY LOCAL PROFILER HELPERS
-- ══════════════════════════════════════════════════════════════
-- TEMPORARY TESTING PROFILER
-- Safe to remove after release validation. Search for PROFILER_ / psv_profiler_.
PSV_PROFILER = PSV_PROFILER or {
  window_start_time = nil,
  last_report_time = nil,
  frame_count = 0,
  frame_sum_ms = 0.0,
  frame_max_ms = 0.0,
  spike_16_count = 0,
  spike_50_count = 0,
  samples = {},
  prev_report_mem_kb = nil,
  blocks = {},
  doc_blocks = {},
  doc_counters = {},
  last_context_label = "init",
}

function psv_profiler_now()
  if not PROFILER_ENABLED then return nil end
  return reaper.time_precise()
end

function psv_profiler_reset_window(now)
  if not PROFILER_ENABLED then return end
  local p = PSV_PROFILER
  now = now or reaper.time_precise()
  p.window_start_time = now
  p.last_report_time = now
  p.frame_count = 0
  p.frame_sum_ms = 0.0
  p.frame_max_ms = 0.0
  p.spike_16_count = 0
  p.spike_50_count = 0
  p.samples = {}
  p.blocks = {}
  psv_profiler_doc_reset_window()
end

function psv_profiler_frame_begin(context_label)
  if not PROFILER_ENABLED then return nil end
  local now = reaper.time_precise()
  if type(PSV_PROFILER) ~= "table" then
    PSV_PROFILER = {}
  end
  if not PSV_PROFILER.window_start_time then
    psv_profiler_reset_window(now)
  end
  PSV_PROFILER.last_context_label = context_label or PSV_PROFILER.last_context_label or "loop"
  return now
end

function psv_profiler_block_begin(block_name)
  if not PROFILER_ENABLED or not PROFILER_BLOCK_TIMERS_ENABLED then return nil end
  if not block_name then return nil end
  return reaper.time_precise()
end

function psv_profiler_block_end(block_name, block_t0)
  if not PROFILER_ENABLED or not PROFILER_BLOCK_TIMERS_ENABLED then return end
  if not block_name or not block_t0 then return end
  local dt_ms = (reaper.time_precise() - block_t0) * 1000.0
  local blocks = PSV_PROFILER.blocks
  if type(blocks) ~= "table" then
    blocks = {}
    PSV_PROFILER.blocks = blocks
  end
  local b = blocks[block_name]
  if type(b) ~= "table" then
    b = {sum_ms = 0.0, count = 0, max_ms = 0.0}
    blocks[block_name] = b
  end
  b.sum_ms = (b.sum_ms or 0.0) + dt_ms
  b.count = (b.count or 0) + 1
  if dt_ms > (b.max_ms or 0.0) then b.max_ms = dt_ms end
end

function psv_profiler_doc_reset_window()
  if type(PSV_PROFILER) ~= "table" then return end
  PSV_PROFILER.doc_blocks = {}
  PSV_PROFILER.doc_counters = {}
end

function psv_profiler_doc_block_begin(name)
  if not PROFILER_ENABLED or not PROFILER_DOCUMENT_SUBBLOCKS_ENABLED then return nil end
  if not name then return nil end
  return reaper.time_precise()
end

function psv_profiler_doc_block_end(name, t0)
  if not PROFILER_ENABLED or not PROFILER_DOCUMENT_SUBBLOCKS_ENABLED then return end
  if not name or not t0 then return end
  local dt_ms = (reaper.time_precise() - t0) * 1000.0
  local blocks = PSV_PROFILER.doc_blocks
  if type(blocks) ~= "table" then
    blocks = {}
    PSV_PROFILER.doc_blocks = blocks
  end
  local b = blocks[name]
  if type(b) ~= "table" then
    b = {sum_ms = 0.0, count = 0, max_ms = 0.0}
    blocks[name] = b
  end
  b.sum_ms = (b.sum_ms or 0.0) + dt_ms
  b.count = (b.count or 0) + 1
  if dt_ms > (b.max_ms or 0.0) then b.max_ms = dt_ms end
end

function psv_profiler_doc_count(name, amount)
  if not PROFILER_ENABLED or not PROFILER_DOCUMENT_COUNTERS_ENABLED then return end
  if not name then return end
  local counters = PSV_PROFILER.doc_counters
  if type(counters) ~= "table" then
    counters = {}
    PSV_PROFILER.doc_counters = counters
  end
  counters[name] = (tonumber(counters[name]) or 0) + (tonumber(amount) or 1)
end

function psv_profiler_doc_emit_report_lines(lines)
  if not PROFILER_ENABLED then return end
  if type(lines) ~= "table" then return end

  local doc_block_names = {
    "doc_setup",
    "paragraph_loop",
    "culling_decision",
    "offscreen_skip_dummy",
    "visible_paragraph_render",
    "page_flow_layout",
    "text_measure",
    "styled_text_render",
    "comments_links_markers",
    "search_highlight",
  }

  if PROFILER_DOCUMENT_SUBBLOCKS_ENABLED then
    local doc_blocks = PSV_PROFILER.doc_blocks
    if type(doc_blocks) ~= "table" then doc_blocks = {} end

    lines[#lines + 1] = "document_subblocks_avg_ms:"
    for _, name in ipairs(doc_block_names) do
      local b = doc_blocks[name] or {}
      local count = tonumber(b.count) or 0
      local avg = count > 0 and ((tonumber(b.sum_ms) or 0.0) / count) or 0.0
      lines[#lines + 1] = "  " .. name .. ": " .. psv_profiler_format_ms(avg)
    end

    lines[#lines + 1] = "document_subblocks_max_ms:"
    for _, name in ipairs(doc_block_names) do
      local b = doc_blocks[name] or {}
      lines[#lines + 1] = "  " .. name .. ": " .. psv_profiler_format_ms(b.max_ms)
    end
  end

  if PROFILER_DOCUMENT_COUNTERS_ENABLED then
    local counters = PSV_PROFILER.doc_counters
    if type(counters) ~= "table" then counters = {} end
    local counter_names = {
      "paragraphs_total",
      "paragraphs_looped",
      "paragraphs_full_rendered",
      "paragraphs_skipped_dummy",
      "paragraphs_cache_height_hit",
      "paragraphs_cache_height_miss",
      "paragraphs_force_rendered",
      "paragraphs_pageflow_cached_skip_allowed",
      "paragraphs_pageflow_cached_skip_blocked",
      "visible_paragraphs",
      "tokens_seen",
      "tokens_rendered_visible",
      "calc_text_calls",
      "comment_marker_checks",
      "link_hitbox_checks",
    }

    lines[#lines + 1] = "document_counters:"
    for _, name in ipairs(counter_names) do
      lines[#lines + 1] = "  " .. name .. ": " .. tostring(math.floor((tonumber(counters[name]) or 0) + 0.5))
    end
    lines[#lines + 1] = "document_hint: high visible_paragraph_render/text_measure suggests visible render cost; high paragraphs_looped with low skipped_dummy may indicate ineffective culling."
  end
end

function psv_profiler_format_ms(v)
  v = tonumber(v) or 0
  return string.format("%.2f", v)
end

function psv_profiler_make_context_label()
  if not file_path or file_path == "" or #paragraphs == 0 then
    return "empty"
  end
  local label = "document"
  if PSV_COMMENTS_SIDEBAR_OPEN == true then
    label = label .. "+comments"
  end
  if search_filter and reaper.ImGui_TextFilter_IsActive(search_filter) then
    label = label .. "+search"
  end
  return label
end

function psv_profiler_emit_report(now)
  if not PROFILER_ENABLED then return end
  local p = PSV_PROFILER
  local window_start = tonumber(p.window_start_time) or now
  local window_sec = math.max(0.0001, now - window_start)
  local frames = tonumber(p.frame_count) or 0
  local avg_ms = frames > 0 and ((tonumber(p.frame_sum_ms) or 0.0) / frames) or 0.0
  local hz = frames / window_sec
  local duty_est = avg_ms * hz / 1000.0 * 100.0
  local p95_ms = 0.0
  local samples = p.samples
  if type(samples) == "table" and #samples > 0 then
    local sorted = {}
    for i = 1, #samples do sorted[i] = samples[i] end
    table.sort(sorted)
    local idx = math.ceil(#sorted * 0.95)
    if idx < 1 then idx = 1 end
    if idx > #sorted then idx = #sorted end
    p95_ms = tonumber(sorted[idx]) or 0.0
  end

  local mem_kb = collectgarbage("count")
  local prev_mem = tonumber(p.prev_report_mem_kb)
  local mem_delta = prev_mem and (mem_kb - prev_mem) or 0.0
  p.prev_report_mem_kb = mem_kb

  local status = "OK"
  if mem_delta > 2048 then
    status = "MEM_GROWTH"
  elseif avg_ms > 8.0 or duty_est > 35.0 then
    status = "HEAVY"
  elseif (tonumber(p.spike_16_count) or 0) > 0 or p95_ms > 16.0 then
    status = "SPIKES"
  end

  local lines = {}
  lines[#lines + 1] = "[PSV PROFILER]"
  lines[#lines + 1] = "version: v" .. tostring(PSV_SCRIPT_VERSION or "1.0.0")
  lines[#lines + 1] = string.format("window_sec: %.1f", window_sec)
  lines[#lines + 1] = string.format("frames: %d", frames)
  lines[#lines + 1] = string.format("hz: %.1f", hz)
  lines[#lines + 1] = "avg_ms: " .. psv_profiler_format_ms(avg_ms)
  lines[#lines + 1] = "p95_ms: " .. psv_profiler_format_ms(p95_ms)
  lines[#lines + 1] = "max_ms: " .. psv_profiler_format_ms(p.frame_max_ms)
  lines[#lines + 1] = string.format("duty_est: %.1f%%", duty_est)
  lines[#lines + 1] = string.format("spikes_gt_16ms: %d", tonumber(p.spike_16_count) or 0)
  lines[#lines + 1] = string.format("spikes_gt_50ms: %d", tonumber(p.spike_50_count) or 0)
  lines[#lines + 1] = string.format("lua_mem_kb: %.0f", mem_kb)
  lines[#lines + 1] = string.format("lua_mem_delta_kb: %+0.0f", mem_delta)
  lines[#lines + 1] = "context_last: " .. tostring(p.last_context_label or "unknown")
  lines[#lines + 1] = "status: " .. status

  if PROFILER_BLOCK_TIMERS_ENABLED and type(p.blocks) == "table" then
    local names = {"body_scroll", "page_layer", "document_render", "empty_render", "comments_sidebar", "comment_card"}
    lines[#lines + 1] = "blocks_avg_ms:"
    for _, name in ipairs(names) do
      local b = p.blocks[name] or {}
      local count = tonumber(b.count) or 0
      local avg = count > 0 and ((tonumber(b.sum_ms) or 0.0) / count) or 0.0
      lines[#lines + 1] = "  " .. name .. ": " .. psv_profiler_format_ms(avg)
    end
    lines[#lines + 1] = "blocks_max_ms:"
    for _, name in ipairs(names) do
      local b = p.blocks[name] or {}
      lines[#lines + 1] = "  " .. name .. ": " .. psv_profiler_format_ms(b.max_ms)
    end
  end

  psv_profiler_doc_emit_report_lines(lines)

  reaper.ShowConsoleMsg(table.concat(lines, "\n") .. "\n\n")
  psv_profiler_reset_window(now)
  PSV_PROFILER.prev_report_mem_kb = mem_kb
end

function psv_profiler_frame_end(frame_t0, context_label)
  if not PROFILER_ENABLED or not frame_t0 then return end
  local now = reaper.time_precise()
  local frame_ms = (now - frame_t0) * 1000.0
  local p = PSV_PROFILER
  if type(p) ~= "table" then return end
  if not p.window_start_time then
    psv_profiler_reset_window(now)
  end

  p.last_context_label = context_label or p.last_context_label or "loop"
  p.frame_count = (tonumber(p.frame_count) or 0) + 1
  p.frame_sum_ms = (tonumber(p.frame_sum_ms) or 0.0) + frame_ms
  if frame_ms > (tonumber(p.frame_max_ms) or 0.0) then p.frame_max_ms = frame_ms end
  if frame_ms > (tonumber(PROFILER_SPIKE_16_MS) or 16.0) then
    p.spike_16_count = (tonumber(p.spike_16_count) or 0) + 1
  end
  if frame_ms > (tonumber(PROFILER_SPIKE_50_MS) or 50.0) then
    p.spike_50_count = (tonumber(p.spike_50_count) or 0) + 1
  end

  if type(p.samples) ~= "table" then p.samples = {} end
  if #p.samples < (tonumber(PROFILER_MAX_SAMPLES_PER_WINDOW) or 1200) then
    p.samples[#p.samples + 1] = frame_ms
  end

  if now - (tonumber(p.window_start_time) or now) >= (tonumber(PROFILER_REPORT_INTERVAL_SEC) or 5.0) then
    psv_profiler_emit_report(now)
  end
end

-- Позиция скролла body child хранится отдельно для каждого REAPER project key.
-- Это session-only состояние: оно нужно только для переключения между проектами
-- внутри текущей сессии REAPER и не меняет существующий ExtState file persistence.
local project_body_scroll_y = {}
local current_body_scroll_y = nil
local pending_body_scroll_y = nil
local pending_body_scroll_restore_frames = 0

-- Геометрия окна хранится для launch/owner project, а не как shared/global state.
-- pending_window_geometry_apply ставится только при первом старте и сбрасывается
-- после первого реального visible-frame, чтобы не перетирать saved geometry
-- hidden startup-кадрами.
local current_window_x = UI_INIT_WINDOW_X
local current_window_y = UI_INIT_WINDOW_Y
local current_window_w = UI_INIT_WINDOW_W
local current_window_h = UI_INIT_WINDOW_H
local pending_window_geometry_apply = true

-- Консервативный render-culling cache для body renderer.
-- Храним только уже измеренные высоты абзацев при текущей layout-конфигурации,
-- чтобы на следующих кадрах можно было безопасно пропускать явно offscreen
-- абзацы через Dummy(), не трогая сам per-word renderer.
local body_render_cache = {
  doc_version = -1,
  layout_key = "",
  paragraph_heights = {},
  paragraph_start_y = {},
}

function reset_body_scroll_inertia()
  local st = PSV_BODY_SCROLL_STATE
  if type(st) ~= "table" then return end
  st.velocity_y = 0.0
  st.last_time = nil
  st.body_scroll_apply_y = nil
end

function update_body_inertial_scroll(ctx, wheel_y)
  local st = PSV_BODY_SCROLL_STATE
  if type(st) ~= "table" then return end

  local now = reaper.time_precise()
  local dt = 1.0 / 60.0
  if st.last_time ~= nil then
    dt = now - st.last_time
  end
  st.last_time = now

  if dt < 0 then
    dt = 0
  elseif dt > UI_BODY_SCROLL_DT_MAX then
    dt = UI_BODY_SCROLL_DT_MAX
  end

  local scroll_y = reaper.ImGui_GetScrollY(ctx)
  local scroll_max_y = reaper.ImGui_GetScrollMaxY(ctx)
  local target_y = scroll_y

  if UI_BODY_INERTIAL_SCROLL_ENABLED then
    local wheel_units = tonumber(wheel_y) or 0
    if wheel_units ~= 0 then
      local max_units = tonumber(UI_BODY_SCROLL_MAX_WHEEL_UNITS_PER_FRAME) or 4.0
      if max_units <= 0 then max_units = 4.0 end
      if wheel_units > max_units then
        wheel_units = max_units
      elseif wheel_units < -max_units then
        wheel_units = -max_units
      end

      local sign = wheel_units < 0 and -1 or 1
      local magnitude = math.abs(wheel_units)
      local curve = tonumber(UI_BODY_SCROLL_INPUT_CURVE) or 1.0
      if curve > 0 and curve ~= 1.0 and max_units > 0 then
        local normalized = magnitude / max_units
        if normalized > 1 then normalized = 1 end
        magnitude = (normalized ^ curve) * max_units
      end
      wheel_units = sign * magnitude

      local line_px = math.max(1.0, (tonumber(font_size) or UI_FONT_SIZE_DEFAULT) + (tonumber(line_spacing) or 0))
      local base_delta_px = line_px * (tonumber(UI_BODY_SCROLL_LINES_PER_WHEEL) or 4.5)
      local input_delta_px = -wheel_units * base_delta_px

      local immediate_fraction = tonumber(UI_BODY_SCROLL_IMMEDIATE_FRACTION) or 0.25
      if immediate_fraction < 0 then immediate_fraction = 0 end
      if immediate_fraction > 1 then immediate_fraction = 1 end
      target_y = target_y + input_delta_px * immediate_fraction

      local damping = tonumber(UI_BODY_SCROLL_DAMPING_PER_SECOND) or 10.0
      if damping < 0 then damping = 0 end
      local total_mult = tonumber(UI_BODY_SCROLL_TOTAL_DISTANCE_MULT) or 1.35
      if total_mult < immediate_fraction then total_mult = immediate_fraction end

      local velocity_gain = 0
      if (1 - immediate_fraction) > 0 and damping > 0 then
        velocity_gain = damping * (total_mult - immediate_fraction) / (1 - immediate_fraction)
      end
      st.velocity_y = (tonumber(st.velocity_y) or 0.0) + input_delta_px * (1 - immediate_fraction) * velocity_gain

      local max_velocity = tonumber(UI_BODY_SCROLL_MAX_VELOCITY) or 2800.0
      if st.velocity_y > max_velocity then
        st.velocity_y = max_velocity
      elseif st.velocity_y < -max_velocity then
        st.velocity_y = -max_velocity
      end
    end

    local velocity = tonumber(st.velocity_y) or 0.0
    if velocity ~= 0 and dt > 0 then
      target_y = target_y + velocity * dt

      local damping_per_second = tonumber(UI_BODY_SCROLL_DAMPING_PER_SECOND) or 10.0
      if damping_per_second > 0 then
        st.velocity_y = velocity * math.exp(-damping_per_second * dt)
      end

      local cutoff = tonumber(UI_BODY_SCROLL_CUTOFF_VELOCITY) or 10.0
      if math.abs(st.velocity_y) < cutoff then
        st.velocity_y = 0.0
      end
    end
  else
    local wheel_units = tonumber(wheel_y) or 0
    if wheel_units ~= 0 then
      local max_ticks = UI_BODY_WHEEL_MAX_TICKS_PER_FRAME
      if wheel_units > max_ticks then
        wheel_units = max_ticks
      elseif wheel_units < -max_ticks then
        wheel_units = -max_ticks
      end
      target_y = target_y - wheel_units * ((tonumber(font_size) or UI_FONT_SIZE_DEFAULT) * UI_BODY_WHEEL_STEP_MULT)
    end
    st.velocity_y = 0.0
  end

  if target_y < 0 then
    target_y = 0
    if (tonumber(st.velocity_y) or 0) < 0 then st.velocity_y = 0.0 end
  elseif target_y > scroll_max_y then
    target_y = scroll_max_y
    if (tonumber(st.velocity_y) or 0) > 0 then st.velocity_y = 0.0 end
  end

  if math.abs(target_y - scroll_y) > 0.01 then
    st.body_scroll_apply_y = target_y
  else
    st.body_scroll_apply_y = nil
  end
end

-- Кэш search-derived данных по текущему документу.
-- ВАЖНО:
-- Это локальный performance-layer.
-- Он не меняет видимое search behavior, а только убирает лишние
-- пересчеты одних и тех же строк/нормализаций каждый кадр.
local search_doc_cache_version = 0
local search_doc_cache = {
  cached_version = -1,
  paragraph_texts = {},
  paragraph_norm_texts = {},
  paragraph_token_spans = {},
  paragraph_normalization_segments = {},
}

-- Кэш search-derived данных по текущему query.
-- Пересобирается только когда:
-- 1) меняется нормализованный query
-- 2) меняется документ (через version)
local search_query_cache = {
  doc_version = -1,
  query = "",
  has_filter = false,
  match_indices = {},
  match_lookup = {},
  token_hit_lookup = {},
  occurrence_count = 0,
  occurrences = {},
}

-- PSV_NAV_DIAG_BEGIN core
-- Session-only bounded diagnostics. No file writes, timers, or navigation changes.
local search_diag = { limit=100, entries={}, next=1, count=0, sequence=0, frame=0, request=0 }
do
  local function read(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, first, second, third = pcall(fn, ...)
    if ok then return first, second, third end
    return nil
  end
  local function quote(value)
    local text = tostring(value)
    if #text > 256 then
      local stop = 256
      while stop > 0 and text:byte(stop + 1) and text:byte(stop + 1) >= 0x80 and text:byte(stop + 1) < 0xC0 do
        stop = stop - 1
      end
      text = text:sub(1, stop) .. "..."
    end
    return '"' .. text:gsub("\\", "\\\\"):gsub('"', '\\"')
      :gsub("\r", "\\r"):gsub("\n", "\\n"):gsub("\t", "\\t")
      :gsub("[%z\1-\8\11\12\14-\31]", function(char) return string.format("\\x%02X", char:byte()) end) .. '"'
  end
  search_diag.read = read
  function search_diag.record(event, fields)
    local now = read(reaper.time_precise) or os.clock()
    search_diag.started = search_diag.started or now
    search_diag.sequence = search_diag.sequence + 1
    local frame = ctx and read(reaper.ImGui_GetFrameCount, ctx) or search_diag.frame
    local parts = { string.format("%04d +%.3fs frame=%s %s", search_diag.sequence,
      now - search_diag.started, tostring(frame or search_diag.frame), event),
      "selected=" .. tostring(search_nav_index) .. "/" .. tostring(search_query_cache.occurrence_count or 0),
      "target_para=" .. tostring(search_nav_scroll_target), "doc=" .. tostring(search_doc_cache_version),
      "query=" .. quote(search_query_cache.query or "") }
    local keys = {}
    for key in pairs(fields or {}) do keys[#keys + 1] = key end
    table.sort(keys)
    for _, key in ipairs(keys) do
      local value = fields[key]
      parts[#parts + 1] = key .. "=" .. (type(value) == "string" and quote(value) or tostring(value))
    end
    search_diag.entries[search_diag.next] = table.concat(parts, " ")
    search_diag.next = (search_diag.next % search_diag.limit) + 1
    search_diag.count = math.min(search_diag.limit, search_diag.count + 1)
  end
  function search_diag.export()
    local _, _, imgui_version = read(reaper.ImGui_GetVersion)
    local filename = tostring(file_path or ""):match("([^/\\]+)$") or ""
    local lines = {
      "PSV SEARCH NAVIGATION DIAGNOSTICS",
      "version=" .. tostring(PSV_SCRIPT_VERSION) .. " diagnostic=true",
      "reaper=" .. quote(read(reaper.GetAppVersion) or "unknown") .. " reaimgui=" .. quote(imgui_version or "unknown")
        .. " os=" .. quote(read(reaper.GetOS) or "unknown"),
      "document=" .. quote(filename) .. " paragraphs=" .. tostring(#paragraphs),
      "retained=" .. tostring(search_diag.count) .. "/100 total_events=" .. tostring(search_diag.sequence),
      "query=" .. quote(search_query_cache.query or "") .. " selected=" .. tostring(search_nav_index)
        .. "/" .. tostring(search_query_cache.occurrence_count or 0),
      "--- oldest to newest ---",
    }
    local start = search_diag.count == search_diag.limit and search_diag.next or 1
    for offset = 0, search_diag.count - 1 do
      lines[#lines + 1] = search_diag.entries[((start + offset - 1) % search_diag.limit) + 1]
    end
    return table.concat(lines, "\n")
  end
  function search_diag.copy(context)
    if type(reaper.ImGui_SetClipboardText) ~= "function" then return false end
    return pcall(reaper.ImGui_SetClipboardText, context, search_diag.export())
  end
  function search_diag.selected(from, mods, shift)
    local occurrence = search_nav_occurrence or {}
    search_diag.pending_samples = 0
    search_diag.record("nav_selected", { from=from, direction=shift and "previous" or "next", mods=mods,
      paragraph=occurrence.paragraph_index, token=occurrence.token_index, token_byte=occurrence.token_byte,
      first_byte=occurrence.first_byte, last_byte=occurrence.last_byte })
  end
  function search_diag.request_scroll(context, mode, paragraph, token, first, last, line_y, ratio)
    if search_diag.watch then
      search_diag.record("scroll_superseded", { request=search_diag.watch.id, previous_selection=search_diag.watch.index })
    end
    search_diag.request = search_diag.request + 1
    search_diag.watch = { id=search_diag.request, index=search_nav_index, samples=0, line_y=line_y }
    local _, height = read(reaper.ImGui_GetWindowSize, context)
    search_diag.record("scroll_request", { request=search_diag.request, mode=mode, paragraph=paragraph, token=token,
      chunk_first=first, chunk_last=last, line_y=line_y, ratio=ratio,
      api_local_y=mode == "token" and line_y and (line_y - (read(reaper.ImGui_GetScrollY, context) or 0)) or nil,
      before_y=read(reaper.ImGui_GetScrollY, context), max_y=read(reaper.ImGui_GetScrollMaxY, context), viewport_h=height })
  end
  function search_diag.begin_body()
    local watch = search_diag.watch
    if watch then
      watch.actual_line_y = nil
      watch.actual_line_h = nil
    end
  end
  function search_diag.observe_target(paragraph, token, first, last, line_y, line_h)
    local watch = search_diag.watch
    if not watch or watch.index ~= search_nav_index then return end
    local occurrence = search_query_cache.occurrences[watch.index]
    if not occurrence or occurrence.paragraph_index ~= paragraph or occurrence.token_index ~= token then return end
    local byte = occurrence.token_byte or 1
    if byte < first or byte > last then return end
    watch.actual_line_y = line_y
    watch.actual_line_h = line_h
  end
  function search_diag.override(kind, y)
    if search_diag.watch or search_nav_scroll_target then
      search_diag.record("scroll_override", { kind=kind, y=y })
    end
  end
  function search_diag.observe_scroll(context)
    local watch = search_diag.watch
    if watch then
      local sample = watch.samples
      if sample <= 2 or sample == 5 then
        local y = read(reaper.ImGui_GetScrollY, context)
        local _, height = read(reaper.ImGui_GetWindowSize, context)
        search_diag.record("scroll_sample", { request=watch.id, requested_selection=watch.index, sample=sample,
          y=y, max_y=read(reaper.ImGui_GetScrollMaxY, context), viewport_h=height,
          target_observed=watch.actual_line_y ~= nil,
          line_y=watch.actual_line_y, line_h=watch.actual_line_h,
          line_in_view=watch.actual_line_y and y and watch.actual_line_y - y,
          target_visible=watch.actual_line_y and y and height
            and watch.actual_line_y >= y and watch.actual_line_y + (watch.actual_line_h or 0) <= y + height,
          requested_line_in_view=watch.line_y and y and watch.line_y - y,
          restore_frames=pending_body_scroll_restore_frames,
          inertia_y=PSV_BODY_SCROLL_STATE and PSV_BODY_SCROLL_STATE.body_scroll_apply_y })
      end
      watch.samples = sample + 1
      if watch.samples >= 6 then search_diag.watch = nil end
    end
    if search_nav_scroll_target then
      search_diag.pending_samples = (search_diag.pending_samples or 0) + 1
      if search_diag.pending_samples == 1 or search_diag.pending_samples == 3 or search_diag.pending_samples == 6 then
        search_diag.record("target_pending", { samples=search_diag.pending_samples,
          token=search_nav_occurrence and search_nav_occurrence.token_index,
          token_byte=search_nav_occurrence and search_nav_occurrence.token_byte })
      end
    end
  end
  search_diag.record("session_start")
end
-- PSV_NAV_DIAG_END core

local HEADING_SCALE = {h1=1.7, h2=1.45, h3=1.25, h4=1.1, h5=1.0, h6=1.0}

-- ══════════════════════════════════════════════════════════════
--  HTML ENTITY DECODER
-- ══════════════════════════════════════════════════════════════

local NAMED_ENT = {
  hellip="\xe2\x80\xa6", mdash="\xe2\x80\x94", ndash="\xe2\x80\x93",
  ldquo="\xe2\x80\x9c",  rdquo="\xe2\x80\x9d", lsquo="\xe2\x80\x98",
  rsquo="\xe2\x80\x99",  sbquo="\xe2\x80\x9a", bdquo="\xe2\x80\x9e",
  laquo="\xc2\xab",      raquo="\xc2\xbb",      lsaquo="\xe2\x80\xb9",
  rsaquo="\xe2\x80\xba", bull="\xe2\x80\xa2",   middot="\xc2\xb7",
  copy="\xc2\xa9",       reg="\xc2\xae",        trade="\xe2\x84\xa2",
  euro="\xe2\x82\xac",   pound="\xc2\xa3",
  ensp=" ", emsp="  ", thinsp=" ",
  eacute="\xc3\xa9", egrave="\xc3\xa8", ecirc="\xc3\xaa",
  aacute="\xc3\xa1", agrave="\xc3\xa0", acirc="\xc3\xa2",
  oacute="\xc3\xb3", ograve="\xc3\xb2", ocirc="\xc3\xb4",
  uacute="\xc3\xba", ugrave="\xc3\xb9", ucirc="\xc3\xbb",
  iacute="\xc3\xad", igrave="\xc3\xac", icirc="\xc3\xae",
  ccedil="\xc3\xa7", ntilde="\xc3\xb1", szlig="\xc3\x9f",
  Eacute="\xc3\x89", Agrave="\xc3\x80", Oacute="\xc3\x93",
  alpha="\xce\xb1", beta="\xce\xb2", gamma="\xce\xb3", pi="\xcf\x80",
}

local function decode_ent(s)
  s = s:gsub("&(%a+);", function(n)
    return NAMED_ENT[n] or NAMED_ENT[n:lower()] or ("&"..n..";")
  end)
  local function numeric_entity(n, base)
    local cp = tonumber(n, base)
    if cp and cp >= 0 and cp <= 0x10FFFF and not (cp >= 0xD800 and cp <= 0xDFFF) then
      return utf8.char(cp)
    end
    return utf8.char(0xFFFD)
  end
  s = s:gsub("&#(%d+);", function(n) return numeric_entity(n, 10) end)
  s = s:gsub("&#[xX](%x+);", function(n) return numeric_entity(n, 16) end)
  s = s:gsub("&amp;", "&"):gsub("&lt;", "<"):gsub("&gt;", ">")
  s = s:gsub("&quot;", '"'):gsub("&nbsp;", " ")
  return s
end

local function strip_tags(s) return (s:gsub("<[^>]+>", "")) end
local function trim(s)       return (s:gsub("^%s+",""):gsub("%s+$","")) end

-- ══════════════════════════════════════════════════════════════
--  CSS COLOUR PARSING
-- ══════════════════════════════════════════════════════════════

local function css_color(val)
  if not val then return nil end
  val = trim(val):lower()
  if val == "transparent" or val == "inherit" or val == "initial" then return nil end

  local r, g, b
  r, g, b = val:match("^#(%x%x)(%x%x)(%x%x)")
  if r then
    return rgba(tonumber(r,16), tonumber(g,16), tonumber(b,16))
  end

  r, g, b = val:match("^#(%x)(%x)(%x)$")
  if r then
    return rgba(tonumber(r,16)*17, tonumber(g,16)*17, tonumber(b,16)*17)
  end

  r, g, b = val:match("rgb%((%d+),%s*(%d+),%s*(%d+)%)")
  if r then
    return rgba(tonumber(r), tonumber(g), tonumber(b))
  end

  return nil
end

local function parse_inline_style(attr)
  if not attr then return nil, nil, nil, nil, nil end
  local props = {}
  for k, v in attr:gmatch("([%a%-]+)%s*:%s*([^;]+)") do
    props[trim(k):lower()] = trim(v)
  end

  local weight = (props["font-weight"] or ""):lower()
  local weight_num = tonumber(weight)
  local bold = (weight == "bold") or (weight_num ~= nil and weight_num >= 600)

  local style = (props["font-style"] or ""):lower()
  local italic = (style == "italic")

  local decoration = ((props["text-decoration"] or "") .. " " .. (props["text-decoration-line"] or "")):lower()
  local underline = decoration:match("%f[%a]underline%f[%A]") ~= nil

  return css_color(props["color"]),
         css_color(props["background-color"]),
         bold or nil,
         italic or nil,
         underline or nil
end

-- ──────────────────────────────────────────────────────────────
--  CSS STYLESHEET PARSER  — for Google Docs class-based colours
-- ──────────────────────────────────────────────────────────────
-- Google Docs exports styles as:  .c5 { color:#ff0000; ... }
-- We capture per-class fg and bg colours.

local function parse_stylesheet(html)
  local class_col = {}
  local style_block = html:match("<style[^>]*>(.-)</style>")
  if not style_block then return class_col end

  for cls, rules in style_block:gmatch("%.([%w_-]+)%s*{([^}]*)}") do
    local props = {}
    for k, v in rules:gmatch("([%a%-]+)%s*:%s*([^;]+)") do
      props[trim(k):lower()] = trim(v)
    end
    local fg = css_color(props["color"])
    local bg = css_color(props["background-color"])

    local weight = (props["font-weight"] or ""):lower()
    local weight_num = tonumber(weight)
    local bold = (weight == "bold") or (weight_num ~= nil and weight_num >= 600)

    local style = (props["font-style"] or ""):lower()
    local italic = (style == "italic")

    local decoration = ((props["text-decoration"] or "") .. " " .. (props["text-decoration-line"] or "")):lower()
    local underline = decoration:match("%f[%a]underline%f[%A]") ~= nil

    if fg or bg or bold or italic or underline then
      class_col[cls] = {
        fg=fg,
        bg=bg,
        bold=bold or nil,
        italic=italic or nil,
        underline=underline or nil,
      }
    end
  end
  return class_col
end

-- ══════════════════════════════════════════════════════════════
--  HTML PARSER
-- ══════════════════════════════════════════════════════════════

local function tokenize(text, fg, bg, href, bold, italic, underline, first_no_space_before)
  local out   = {}
  local first = true
  local mark_first_no_space_before = first_no_space_before == true
  for line in (text .. "\n"):gmatch("([^\n]*)\n") do
    if not first then out[#out+1] = {newline=true} end
    first = false
    for word in line:gmatch("%S+") do
      local tok = {
        text=word,
        fg=fg,
        bg=bg,
        href=href,
        bold=bold or nil,
        italic=italic or nil,
        underline=underline or nil,
      }
      if mark_first_no_space_before then
        tok.no_space_before = true
        mark_first_no_space_before = false
      end
      out[#out+1] = tok
    end
  end
  return out
end

local function parse_para(content, class_col)
  content = content:gsub("<br%s*/?>", "\n")
  local tokens = {}
  local comment_refs = {}
  local pos    = 1
  local current_href = nil
  local bold_depth = 0
  local italic_depth = 0
  local underline_depth = 0
  local previous_visible_ended_non_ws = false

  -- Internal markers are inserted by parse_document() before normal stable parsing.
  -- They let the existing span/class parser keep fg/bg semantics while adding
  -- optional href/bold/italic/underline token properties for text generated inside tags.
  local function append_text_segment(segment, fg, bg, span_bold, span_italic, span_underline)
    local scan_pos = 1

    local function append_plain_text(chunk)
      if not chunk or chunk == "" then return end
      local t = decode_ent(strip_tags(chunk))
      if t == "" then return end

      local begins_non_ws = t:match("^%S") ~= nil
      local first_no_space_before = previous_visible_ended_non_ws and begins_non_ws

      for _, tok in ipairs(tokenize(
        t,
        fg,
        bg,
        current_href,
        (bold_depth > 0) or span_bold,
        (italic_depth > 0) or span_italic,
        (underline_depth > 0) or span_underline,
        first_no_space_before
      )) do
        tokens[#tokens+1] = tok
      end

      if t:match("%S") then
        previous_visible_ended_non_ws = t:match("%S$") ~= nil
      else
        previous_visible_ended_non_ws = false
      end
    end

    while scan_pos <= #segment do
      local marker_s = segment:find("\31", scan_pos, true)
      if not marker_s then
        append_plain_text(segment:sub(scan_pos))
        break
      end

      append_plain_text(segment:sub(scan_pos, marker_s - 1))

      local marker_e = segment:find("\30", marker_s + 1, true)
      if not marker_e then
        -- Malformed internal marker: treat the rest as ordinary text.
        append_plain_text(segment:sub(marker_s))
        break
      end

      local marker = segment:sub(marker_s + 1, marker_e - 1)
      if marker:sub(1, 5) == "LINK:" then
        current_href = decode_ent(marker:sub(6))
      elseif marker == "/LINK" then
        current_href = nil
      elseif marker == "BOLD" then
        bold_depth = bold_depth + 1
      elseif marker == "/BOLD" then
        bold_depth = math.max(0, bold_depth - 1)
      elseif marker == "ITALIC" then
        italic_depth = italic_depth + 1
      elseif marker == "/ITALIC" then
        italic_depth = math.max(0, italic_depth - 1)
      elseif marker == "UNDERLINE" then
        underline_depth = underline_depth + 1
      elseif marker == "/UNDERLINE" then
        underline_depth = math.max(0, underline_depth - 1)
      elseif marker:sub(1, 12) == "COMMENT_REF:" then
        -- Google Docs comment refs are parser metadata only in this pass.
        -- They are not converted into visible tokens yet, so rendering stays unchanged.
        -- Treat the source anchor as a real marker boundary for no-space repair:
        -- do not glue visible text across a comment insertion point.
        previous_visible_ended_non_ws = false
        local ref_id, comment_id, label = marker:sub(13):match("^([^\29]*)\29([^\29]*)\29(.*)$")
        if ref_id and ref_id ~= "" and comment_id and comment_id ~= "" then
          comment_refs[#comment_refs + 1] = {
            ref_id=ref_id,
            comment_id=comment_id,
            label=decode_ent(label or ""),
            token_index_after=#tokens,
          }
        end
      else
        -- Unknown marker: keep it invisible and continue.
      end

      scan_pos = marker_e + 1
    end
  end

  while pos <= #content do
    local s, e = content:find("<span[^>]*>", pos)
    if not s then
      append_text_segment(content:sub(pos), nil, nil)
      break
    end

    if s > pos then
      append_text_segment(content:sub(pos, s-1), nil, nil)
    end

    local span_src = content:sub(s, e)

    -- 1) Inline style has priority for direct colour fields, and can also
    --    carry CSS-based bold/italic from Google Docs exports.
    local fg, bg, inline_bold, inline_italic, inline_underline = parse_inline_style(span_src:match('style="([^"]*)"'))
    local span_bold = inline_bold
    local span_italic = inline_italic
    local span_underline = inline_underline

    -- 2) Fallback/composition from Google Docs classes. Multi-class exports
    --    often split style across classes: one class can provide italic, another
    --    bold, another underline, another fg/bg. Compose all of them while preserving inline priority.
    if class_col then
      local cls_attr = span_src:match('class="([^"]*)"')
      if cls_attr then
        for cls in cls_attr:gmatch("%S+") do
          local c = class_col[cls]
          if c then
            fg = fg or c.fg
            bg = bg or c.bg
            span_bold = span_bold or c.bold
            span_italic = span_italic or c.italic
            span_underline = span_underline or c.underline
          end
        end
      end
    end

    local cs = e + 1
    local ce = content:find("</span>", cs, true)
    if not ce then break end

    append_text_segment(content:sub(cs, ce-1), fg, bg, span_bold, span_italic, span_underline)
    pos = ce + 7
  end

  return tokens, comment_refs
end

-- Document IR v1 contract note.
-- The current HTML parser produces an implicit internal document model.
-- This model is consumed directly by render_paragraphs().
-- It is also consumed by paragraph_search_text().
-- It is also consumed by PSV_COMMENT_CARD_RENDERER.
-- This existing shape is now referred to as Document IR v1.
-- Document IR v1 is a name for the current consumed shape only.
-- This block documents the current contract without changing it.
-- It does not introduce a new parser model.
-- It does not move existing data structures.
-- It does not rename the existing paragraphs table.
--
-- Paragraph block shape in Document IR v1:
--   tokens: array
--   is_heading: bool
--   tag: "p" or "h1"..."h6"
--   is_blank_paragraph: bool
--
-- Token shape in Document IR v1:
--   either a newline token with newline = true
--   or a text token with text plus optional styling/link fields
--   supported optional token fields are fg, bg, href, bold, italic, underline, strike
--
-- Comments sidecar shape in Document IR v1:
--   paragraphs.comments.by_id[id] stores comment records
--   each comment record contains id, ref_id, label, text
--   comment records may also contain raw_html and href_to_ref
--   paragraphs.comments.refs stores comment reference records
--   each reference record contains ref_id, comment_id, label
--   each reference record also contains token_index_after
--   each reference record also contains paragraph_index and paragraph_tag
--   each reference record also contains block_src
--   paragraphs.comments.order stores comment ids in document order
--
-- Runtime fields on paragraphs.comments are UI state.
-- Runtime fields are not parsed document data.
-- Import adapters must not produce these UI/runtime fields.
-- Known UI/runtime fields include active_id.
-- Known UI/runtime fields include active_x and active_y.
-- Known UI/runtime fields include active_group_key.
-- Known UI/runtime fields include active_group_comment_ids.
-- Known UI/runtime fields include active_marker_geometry_available.
-- Known UI/runtime fields include active_marker_visible.
-- Known UI/runtime fields include active_card_locked_candidate* fields.
-- Known UI/runtime fields include manual_card_position_enabled.
-- Known UI/runtime fields include manual_card_dragging.
-- Known UI/runtime fields include card_scroll_y.
-- Known UI/runtime fields include card_scroll_max_y.
-- Known UI/runtime fields include diag_console_* fields.
--
-- Future import adapters must produce Document IR v1.
-- A future DOCX adapter must produce the same Document IR v1 shape.
-- Future adapters must provide parsed document data only.
-- Future adapters must leave comment-card and UI runtime state to the UI layer.
-- The renderer consumes token.strike as a visual-only strikethrough flag.
-- DOCX adapters may set token.strike for direct w:strike/w:dstrike formatting.
--
local function parse_document(html)
  local class_col = parse_stylesheet(html)
  local comments = {by_id={}, refs={}, order={}}

  -- Local parser-only helpers for Google Docs exported comments.
  -- Kept inside parse_document() to avoid increasing main-chunk locals.
  local function read_anchor_attr(tag, name)
    local key
    if name == "href" then
      key = "[hH][rR][eE][fF]"
    elseif name == "id" then
      key = "[iI][dD]"
    else
      key = name
    end

    return tag:match(key .. '%s*=%s*"([^"]*)"')
        or tag:match(key .. "%s*=%s*'([^']*)'")
        or tag:match(key .. "%s*=%s*([^%s>]+)")
  end

  local function remember_comment_order(comment_id)
    if not comment_id or comment_id == "" then return end
    for _, existing_id in ipairs(comments.order) do
      if existing_id == comment_id then return end
    end
    comments.order[#comments.order + 1] = comment_id
  end

  local function make_comment_ref_marker(ref_id, comment_id, label)
    return "\31COMMENT_REF:"
      .. tostring(ref_id or "")
      .. "\29"
      .. tostring(comment_id or "")
      .. "\29"
      .. tostring(label or "")
      .. "\30"
  end

  -- Extract Google Docs comment-body containers before the generic anchor pass.
  -- Multi-paragraph comments are exported as a small block/container where only
  -- the first <p> carries id="cmntN"; continuation <p> blocks do not. Therefore
  -- suppress the whole detected comment container, not just the anchor paragraph.
  local function extract_comment_body_from_block(block_html)
    local comment_id = nil
    local ref_id = nil
    local label = nil

    local without_anchor = block_html:gsub("<[aA]%s+[^>]*>.-</[aA]>", function(anchor)
      local open_tag, inner = anchor:match("^(<[aA]%s+[^>]*>)(.-)</[aA]>$")
      if not open_tag then return anchor end

      local href = read_anchor_attr(open_tag, "href")
      local anchor_id = read_anchor_attr(open_tag, "id")
      local linked_ref_id = href and href:match("^#(cmnt_ref%d+)$")

      if anchor_id and anchor_id:match("^cmnt%d+$") and linked_ref_id then
        comment_id = anchor_id
        ref_id = linked_ref_id
        label = trim(decode_ent(strip_tags(inner or "")))
        return ""
      end

      return anchor
    end)

    if not comment_id then return false end

    local text_parts = {}
    for p_content in without_anchor:gmatch("<[pP][^>]*>(.-)</[pP]>") do
      local txt = trim(decode_ent(strip_tags(p_content)))
      if txt ~= "" then
        text_parts[#text_parts + 1] = txt
      end
    end

    if #text_parts == 0 then
      local txt = trim(decode_ent(strip_tags(without_anchor)))
      if txt ~= "" then
        text_parts[#text_parts + 1] = txt
      end
    end

    comments.by_id[comment_id] = {
      id=comment_id,
      ref_id=ref_id,
      href_to_ref="#" .. tostring(ref_id or ""),
      label=label or "",
      text=table.concat(text_parts, "\n\n"),
      raw_html=without_anchor,
    }
    remember_comment_order(comment_id)

    return true
  end

  -- Primary path: suppress the whole simple Google Docs comment-body <div>,
  -- including continuation paragraphs that do not contain id="cmntN".
  html = html:gsub("<[dD][iI][vV][^>]*>.-</[dD][iI][vV]>", function(div_block)
    if div_block:find('[iI][dD]%s*=%s*["\']cmnt%d+["\']')
       and div_block:find('[hH][rR][eE][fF]%s*=%s*["\']#cmnt_ref%d+["\']')
       and not div_block:find('[iI][dD]%s*=%s*["\']cmnt_ref%d+["\']')
       and not div_block:find("<[sS][uU][pP][^>]*>") then
      local p_count = 0
      for _ in div_block:gmatch("<[pP][^>]*>") do
        p_count = p_count + 1
      end

      if p_count > 0 and p_count <= 50 then
        if extract_comment_body_from_block(div_block) then
          return " "
        end
      end
    end

    return div_block
  end)

  -- Fallback path for older/simpler exports where the comment body is a single
  -- <p> without an enclosing comment-only container. Kept after the container
  -- pass so single-paragraph comments still work.
  html = html:gsub("<[pP][^>]*>.-</[pP]>", function(p_block)
    if p_block:find('[iI][dD]%s*=%s*["\']cmnt%d+["\']')
       and p_block:find('[hH][rR][eE][fF]%s*=%s*["\']#cmnt_ref%d+["\']') then
      if extract_comment_body_from_block(p_block) then
        return " "
      end
    end

    return p_block
  end)

  -- Preserve Google Docs body comment refs as invisible parser metadata.
  -- The later generic <sup> remover still strips non-comment superscripts.
  html = html:gsub("<[sS][uU][pP][^>]*>.-</[sS][uU][pP]>", function(sup_block)
    local ref_id = nil
    local comment_id = nil
    local label = nil

    sup_block:gsub("<[aA]%s+[^>]*>.-</[aA]>", function(anchor)
      if ref_id then return anchor end

      local open_tag, inner = anchor:match("^(<[aA]%s+[^>]*>)(.-)</[aA]>$")
      if not open_tag then return anchor end

      local href = read_anchor_attr(open_tag, "href")
      local anchor_id = read_anchor_attr(open_tag, "id")
      local linked_comment_id = href and href:match("^#(cmnt%d+)$")

      if anchor_id and anchor_id:match("^cmnt_ref%d+$") and linked_comment_id then
        ref_id = anchor_id
        comment_id = linked_comment_id
        label = trim(decode_ent(strip_tags(inner or "")))
      end

      return anchor
    end)

    if ref_id and comment_id then
      remember_comment_order(comment_id)
      return make_comment_ref_marker(ref_id, comment_id, label)
    end

    return sup_block
  end)

  -- Preserve visible imported link text and carry href through the stable
  -- span parser via internal markers. The markers are consumed in parse_para()
  -- and never become visible document text.
  html = html:gsub("<[aA]%s+[^>]*>.-</[aA]>", function(anchor)
    local open_tag, inner = anchor:match("^(<[aA]%s+[^>]*>)(.-)</[aA]>$")
    if not open_tag then return anchor end

    local href = open_tag:match('[hH][rR][eE][fF]%s*=%s*"([^"]*)"')
              or open_tag:match("[hH][rR][eE][fF]%s*=%s*'([^']*)'")
              or open_tag:match("[hH][rR][eE][fF]%s*=%s*([^%s>]+)")

    if href and href ~= "" then
      return "\31LINK:" .. href .. "\30" .. inner .. "\31/LINK\30"
    end

    return inner
  end)
  -- Preserve simple imported emphasis tags as internal markers.
  -- This remains intentionally narrow: no generic HTML renderer is introduced.
  html = html:gsub("<[bB]%f[%s>][^>]*>(.-)</[bB]>", "\31BOLD\30%1\31/BOLD\30")
  html = html:gsub("<[sS][tT][rR][oO][nN][gG]%f[%s>][^>]*>(.-)</[sS][tT][rR][oO][nN][gG]>", "\31BOLD\30%1\31/BOLD\30")
  html = html:gsub("<[iI]%f[%s>][^>]*>(.-)</[iI]>", "\31ITALIC\30%1\31/ITALIC\30")
  html = html:gsub("<[eE][mM]%f[%s>][^>]*>(.-)</[eE][mM]>", "\31ITALIC\30%1\31/ITALIC\30")
  html = html:gsub("<[uU]%f[%s>][^>]*>(.-)</[uU]>", "\31UNDERLINE\30%1\31/UNDERLINE\30")

  html = html:gsub("<sup[^>]*>.-</sup>", "")
  html = html:gsub("<sub[^>]*>.-</sub>", "")

  -- HTML unsupported-object placeholders are normal system paragraphs rendered
  -- by the existing centered grey placeholder path. The parser records their
  -- source offsets before stripping unsupported tags so source order is kept.
  local function html_system_placeholder_text(kind)
    if kind == "html_table" then
      return "Sorry, there's a table here.\nPodcast HTML/DOCX Script Viewer can't read it."
    elseif kind == "html_image" then
      return "Sorry, there's an image here.\nPodcast HTML/DOCX Script Viewer can't display it."
    end
    return ""
  end

  local function is_src_inside_ranges(src, ranges)
    if not src or not ranges then return false end
    for _, range in ipairs(ranges) do
      if src >= range.s and src <= range.e then return true end
    end
    return false
  end

  local function make_html_system_placeholder_tokens(text)
    local tokens = {}
    local normalized = tostring(text or "")
    normalized = normalized:gsub("\r\n", "\n"):gsub("\r", "\n")
    local start_pos = 1
    while true do
      local nl = normalized:find("\n", start_pos, true)
      local line
      if nl then
        line = normalized:sub(start_pos, nl - 1)
      else
        line = normalized:sub(start_pos)
      end
      if #tokens > 0 then tokens[#tokens + 1] = { newline = true } end
      tokens[#tokens + 1] = { text = line }
      if not nl then break end
      start_pos = nl + 1
    end
    if #tokens == 0 then tokens[1] = { text = normalized } end
    return tokens
  end

  local function append_html_system_placeholder(result, kind)
    local placeholder_text = html_system_placeholder_text(kind)
    local para_index = #result + 1
    result[para_index] = {
      tokens = make_html_system_placeholder_tokens(placeholder_text),
      is_heading = false,
      tag = "p",
      system_placeholder = true,
      system_placeholder_kind = kind,
      system_placeholder_text = placeholder_text,
    }
    return para_index
  end

  html = html:gsub("<script.->.-</script>", " ")
  html = html:gsub("<style.->.-</style>",   " ")
  html = html:gsub("<!%-%-.-%-%->",         " ")

  local table_ranges = {}
  for s, e in html:gmatch("()<[tT][aA][bB][lL][eE][^>]*>.-</[tT][aA][bB][lL][eE]>()") do
    table_ranges[#table_ranges + 1] = { s = s, e = e }
  end

  local html_image_placeholder_sources = {}
  for s in html:gmatch("()<[iI][mM][gG][^>]*>") do
    if not is_src_inside_ranges(s, table_ranges) then
      html_image_placeholder_sources[#html_image_placeholder_sources + 1] = s
    end
  end

  local blocks = {}

  for _, range in ipairs(table_ranges) do
    blocks[#blocks + 1] = { src = range.s, tag = "p", is_h = false, system_placeholder = true, system_placeholder_kind = "html_table" }
  end

  for _, s in ipairs(html_image_placeholder_sources) do
    blocks[#blocks + 1] = { src = s, tag = "p", is_h = false, system_placeholder = true, system_placeholder_kind = "html_image" }
  end

  local pos = 1
  while true do
    local s, e, content = html:find("<p[^>]*>(.-)</p>", pos)
    if not s then break end
    if not is_src_inside_ranges(s, table_ranges) then
      blocks[#blocks+1] = {src=s, content=content, tag="p",  is_h=false}
    end
    pos = e + 1
  end

  pos = 1
  while true do
    local s, e, n, content = html:find("<h([1-6])[^>]*>(.-)</h%1>", pos)
    if not s then break end
    if not is_src_inside_ranges(s, table_ranges) then
      blocks[#blocks+1] = {src=s, content=content, tag="h"..n, is_h=true}
    end
    pos = e + 1
  end

  table.sort(blocks, function(a, b) return a.src < b.src end)

  local result = {}
  result.comments = comments

  for _, blk in ipairs(blocks) do
    local tokens, para_comment_refs = nil, nil
    local para_index = nil

    if blk.system_placeholder == true then
      para_index = append_html_system_placeholder(result, blk.system_placeholder_kind)
      tokens = result[para_index].tokens
      para_comment_refs = nil
    else
      tokens, para_comment_refs = parse_para(blk.content, class_col)
      local has_txt = false
      for _, t in ipairs(tokens) do
        if type(t.text) == "string" and trim(t.text) ~= "" then has_txt = true; break end
      end

      if has_txt then
        para_index = #result + 1
        result[para_index] = {
          tokens=tokens,
          is_heading=blk.is_h,
          tag=blk.tag,
        }
      elseif blk.tag == "p" then
        local has_comment_refs = type(para_comment_refs) == "table" and #para_comment_refs > 0
        if PSV_HTML_DROP_PURE_EMPTY_PARAGRAPHS ~= true or has_comment_refs then
          -- Preserve empty <p> only when the normalization toggle is off or the
          -- paragraph carries meaningful comment-ref metadata.
          para_index = #result + 1
          result[para_index] = {
            tokens=tokens,
            is_heading=false,
            tag="p",
            is_blank_paragraph=true,
          }
        end
      end
    end

    if para_index and para_comment_refs then
      for _, ref in ipairs(para_comment_refs) do
        ref.paragraph_index = para_index
        ref.paragraph_tag = blk.tag
        ref.block_src = blk.src
        comments.refs[#comments.refs + 1] = ref
        remember_comment_order(ref.comment_id)

        comments.by_id[ref.comment_id] = comments.by_id[ref.comment_id] or {
          id=ref.comment_id,
          ref_id=ref.ref_id,
          label=ref.label or "",
          text="",
        }
        comments.by_id[ref.comment_id].ref_id = comments.by_id[ref.comment_id].ref_id or ref.ref_id
        comments.by_id[ref.comment_id].label = comments.by_id[ref.comment_id].label or ref.label or ""
      end
    end
  end
  return result
end

function psv_html_code_file_placeholder_text()
  return "Looks like a code file.\nWhat did you expect?"
end

function psv_make_html_code_file_placeholder_document(path)
  local result = {}
  result[1] = {
    tokens = {
      { text = "Looks like a code file." },
      { newline = true },
      { text = "What did you expect?" },
    },
    is_heading = false,
    tag = "p",
    system_placeholder = true,
    system_placeholder_kind = "html_code_file",
    system_placeholder_text = psv_html_code_file_placeholder_text(),
  }
  result.comments = { by_id = {}, refs = {}, order = {}, ranges = {} }
  result.import_info = {
    source_format = "html_code_file",
    original_file_path = path,
  }
  return result
end

function psv_is_likely_html_code_file(html, path)
  html = tostring(html or "")
  path = tostring(path or "")
  local lower_path = path:lower()
  if not (lower_path:match("%.html$") or lower_path:match("%.htm$")) then return false end
  if html == "" then return false end

  local lower = html:lower()

  -- Google Docs HTML exports and paragraph-heavy readable documents are the
  -- primary supported HTML input. Keep this detector conservative and require
  -- multiple source/web-app signals before using the placeholder path.
  if lower:find("docs%-internal%-guid") or lower:find("id=[\"']docs%-internal") then
    return false
  end

  local readable_scan = html
    :gsub("<script[^>]*>.-</script>", " ")
    :gsub("<style[^>]*>.-</style>", " ")
    :gsub("<!%-%-.-%-%->", " ")

  local paragraph_count = 0
  local heading_count = 0
  local meaningful_block_text_len = 0

  for content in readable_scan:gmatch("<[pP][^>]*>(.-)</[pP]>") do
    local txt = trim(decode_ent(strip_tags(content)))
    if txt ~= "" then
      paragraph_count = paragraph_count + 1
      meaningful_block_text_len = meaningful_block_text_len + #txt
    end
  end

  for _, content in readable_scan:gmatch("<[hH]([1-6])[^>]*>(.-)</[hH]%1>") do
    local txt = trim(decode_ent(strip_tags(content)))
    if txt ~= "" then
      heading_count = heading_count + 1
      meaningful_block_text_len = meaningful_block_text_len + #txt
    end
  end

  local all_visible_text = trim(decode_ent(strip_tags(readable_scan))):gsub("%s+", " ")
  local visible_len = #all_visible_text

  local function count_pattern(pattern)
    local n = 0
    for _ in lower:gmatch(pattern) do n = n + 1 end
    return n
  end

  local script_count = count_pattern("<script[%s>/]")
  local style_count = count_pattern("<style[%s>/]")
  local link_count = count_pattern("<link[%s>/]")
  local meta_count = count_pattern("<meta[%s>/]")
  local app_tag_count = 0
  for _, tag in ipairs({"nav", "header", "footer", "form", "input", "button", "select", "textarea", "canvas", "svg", "video", "audio", "iframe", "main", "section", "article"}) do
    app_tag_count = app_tag_count + count_pattern("<" .. tag .. "[%s>/]")
  end

  local script_style_len = 0
  for block in html:gmatch("<script[^>]*>.-</script>") do script_style_len = script_style_len + #block end
  for block in html:gmatch("<style[^>]*>.-</style>") do script_style_len = script_style_len + #block end

  local strong_score = 0
  if script_count >= 2 then strong_score = strong_score + 2 elseif script_count == 1 then strong_score = strong_score + 1 end
  if style_count >= 2 then strong_score = strong_score + 2 elseif style_count == 1 then strong_score = strong_score + 1 end
  if link_count >= 2 then strong_score = strong_score + 1 end
  if meta_count >= 4 then strong_score = strong_score + 1 end
  if app_tag_count >= 3 then strong_score = strong_score + 2 elseif app_tag_count >= 1 then strong_score = strong_score + 1 end
  if lower:find("<!doctype%s+html") and (script_count + style_count + link_count + meta_count) >= 5 then strong_score = strong_score + 1 end
  if script_style_len > 2000 and script_style_len > (visible_len * 2) then strong_score = strong_score + 2 end

  local doc_blocks = paragraph_count + heading_count
  local strong_document_signal = doc_blocks >= 4 and meaningful_block_text_len >= 300
  local weak_readable_signal = doc_blocks <= 1 or visible_len < 160 or meaningful_block_text_len < 120

  if strong_document_signal and strong_score < 7 then return false end
  return strong_score >= 4 and weak_readable_signal
end

-- ══════════════════════════════════════════════════════════════
--  SEARCH CACHE
-- ══════════════════════════════════════════════════════════════

-- Предобъявляем cache-helpers заранее, чтобы их можно было безопасно
-- вызывать из load/reset-логики ниже, а реальные реализации дать позже —
-- уже после объявления локальных search-normalization helpers.
local invalidate_search_cache
local ensure_search_document_cache
local ensure_search_query_cache

-- ══════════════════════════════════════════════════════════════
--  PER-PROJECT FILE STATE
-- ══════════════════════════════════════════════════════════════

local function get_project_key()
  local proj, path = reaper.EnumProjects(-1, "")
  if path and path ~= "" then
    return "path:" .. path
  end
  return "unsaved:" .. tostring(proj)
end

local function save_file_for_project()
  reaper.SetExtState(EXTSTATE_SEC, "file:" .. get_project_key(), file_path or "", true)
end

local function reset_loaded_state(save_project_state)
  paragraphs = {}
  file_path  = nil
  PSV_COMMENTS_SIDEBAR_OPEN = false
  invalidate_search_cache()
  reset_body_scroll_inertia()
  psv_layout_audit_reset(nil)
  request_empty_state_layout_warmup()
  if save_project_state then
    save_file_for_project()
  end
end

local function load_file_for_project()
  local saved = reaper.GetExtState(EXTSTATE_SEC, "file:" .. get_project_key())
  if saved and saved ~= "" then
    load_file(saved, {silent=true, clear_on_fail=true, skip_save=true, skip_recent=true})
  else
    reset_loaded_state(false)
  end
end

-- ══════════════════════════════════════════════════════════════
--  RECENT SCRIPTS  (global utility-level list)
-- ══════════════════════════════════════════════════════════════

local RECENT_SCRIPTS_MAX = 10

local function basename_for_menu(path)
  path = tostring(path or "")
  path = path:gsub("\\", "/")
  return path:match("([^/]+)$") or path
end

local function make_main_window_title()
  local visible_title = SCRIPT_NAME
  if file_path and file_path ~= "" then
    local filename = basename_for_menu(file_path)
    if filename and filename ~= "" then
      visible_title = SCRIPT_NAME .. " — " .. filename
    end
  end
  return visible_title .. "###" .. SCRIPT_NAME
end

local function load_recent_scripts()
  local list = {}
  local count = tonumber(reaper.GetExtState(EXTSTATE_SEC, "recent_count")) or 0
  if count < 0 then count = 0 end
  if count > RECENT_SCRIPTS_MAX then count = RECENT_SCRIPTS_MAX end

  for i = 1, count do
    local path = reaper.GetExtState(EXTSTATE_SEC, "recent_" .. tostring(i))
    if path and path ~= "" then
      list[#list + 1] = path
    end
  end

  -- Compatibility/safety: if recent_count is absent but numbered keys exist,
  -- still recover them without introducing any delimiter-based storage.
  if #list == 0 and count == 0 then
    for i = 1, RECENT_SCRIPTS_MAX do
      local path = reaper.GetExtState(EXTSTATE_SEC, "recent_" .. tostring(i))
      if path and path ~= "" then
        list[#list + 1] = path
      end
    end
  end

  return list
end

local function save_recent_scripts(list)
  local count = math.min(#list, RECENT_SCRIPTS_MAX)
  reaper.SetExtState(EXTSTATE_SEC, "recent_count", tostring(count), true)

  for i = 1, RECENT_SCRIPTS_MAX do
    local path = ""
    if i <= count then
      path = list[i] or ""
    end
    reaper.SetExtState(EXTSTATE_SEC, "recent_" .. tostring(i), path, true)
  end
end

local function add_recent_script(path)
  if not path or path == "" then return end

  local new_list = {path}
  local old_list = load_recent_scripts()

  for _, old_path in ipairs(old_list) do
    if old_path ~= path and #new_list < RECENT_SCRIPTS_MAX then
      new_list[#new_list + 1] = old_path
    end
  end

  save_recent_scripts(new_list)
end

local function clear_recent_scripts()
  save_recent_scripts({})
end

-- ══════════════════════════════════════════════════════════════
--  FILE I/O
-- ══════════════════════════════════════════════════════════════

-- DOCX import bridge namespace.
-- Intentionally nonlocal: this branch is close to Lua main-chunk local limits.
-- The adapter remains optional and is loaded only for .docx paths.
DOCX_IMPORT = DOCX_IMPORT or {}
DOCX_IMPORT.ADAPTER_FILENAME = "Podcast_Script_Viewer_docx_adapter_v0.5.lua"
DOCX_IMPORT.BRIDGE_VERSION = "0.3-main"
DOCX_IMPORT.PRINT_SUCCESS_TO_CONSOLE = false
DOCX_IMPORT.HIGHLIGHT_COLORS = {
  yellow={255,255,0}, green={0,255,0}, cyan={0,255,255}, magenta={255,0,255},
  blue={0,0,255}, red={255,0,0}, darkblue={0,0,128}, darkcyan={0,128,128},
  darkgreen={0,128,0}, darkmagenta={128,0,128}, darkred={128,0,0},
  darkyellow={128,128,0}, black={0,0,0}, lightgray={211,211,211},
  darkgray={128,128,128}, white={255,255,255},
}

function DOCX_IMPORT.msg(text)
  reaper.ShowConsoleMsg(tostring(text or "") .. "\n")
end

function DOCX_IMPORT.basename(path)
  path = tostring(path or "")
  local name = path:match("([^/\\]+)$")
  return name and name ~= "" and name or path
end

function DOCX_IMPORT.paragraph_format_diag_enabled()
  return PSV_DOCX_PARAGRAPH_FORMAT_DIAG_ENABLED == true
end

function DOCX_IMPORT.comment_order_diag_enabled()
  return PSV_DOCX_COMMENT_ORDER_DIAG_ENABLED == true
end

function DOCX_IMPORT.comment_order_diag_max_rows()
  local max_rows = tonumber(PSV_DOCX_COMMENT_ORDER_DIAG_MAX_ROWS) or 80
  if max_rows < 0 then max_rows = 0 end
  return math.floor(max_rows + 0.5)
end

function DOCX_IMPORT.long_token_layout_diag_enabled()
  return PSV_DOCX_LONG_TOKEN_LAYOUT_DIAG_ENABLED == true
end

function DOCX_IMPORT.long_token_layout_diag_max_rows()
  local max_rows = tonumber(PSV_DOCX_LONG_TOKEN_LAYOUT_DIAG_MAX_ROWS) or 60
  if max_rows < 0 then max_rows = 0 end
  return math.floor(max_rows + 0.5)
end

function DOCX_IMPORT.paragraph_format_diag_adapter_only_output()
  return PSV_DOCX_PARAGRAPH_FORMAT_DIAG_ADAPTER_ONLY_OUTPUT == true
end

function DOCX_IMPORT.paragraph_format_diag_max_rows()
  local max_rows = tonumber(PSV_DOCX_PARAGRAPH_FORMAT_DIAG_MAX_ROWS) or 80
  if max_rows < 0 then max_rows = 0 end
  return math.floor(max_rows + 0.5)
end

function DOCX_IMPORT.paragraph_format_diag_match_texts()
  if type(PSV_DOCX_PARAGRAPH_FORMAT_DIAG_MATCH_TEXTS) == "table" then
    return PSV_DOCX_PARAGRAPH_FORMAT_DIAG_MATCH_TEXTS
  end
  return { "bold", "italic", "underline", "strikethrough", "highlight", "habr.com" }
end

function DOCX_IMPORT.compute_adapter_lines_status(path, adapter, result_diagnostics, adapter_diag_lines)
  local status = {
    file = DOCX_IMPORT.basename(path),
    adapter = (adapter and adapter.VERSION) or (result_diagnostics and result_diagnostics.adapter_version) or nil,
    adapter_build = (adapter and adapter.BUILD) or (result_diagnostics and result_diagnostics.adapter_build) or nil,
    bridge = DOCX_IMPORT.BRIDGE_VERSION or nil,
    count = type(adapter_diag_lines) == "table" and #adapter_diag_lines or 0,
    has_summary = false,
    has_para = false,
    has_neighbor = false,
    has_run = false,
  }

  if type(adapter_diag_lines) == "table" then
    for _, line in ipairs(adapter_diag_lines) do
      local line_text = tostring(line or "")
      if line_text:find("ADAPTER_SUMMARY", 1, true) then status.has_summary = true end
      if line_text:find("ADAPTER_PARA", 1, true) then status.has_para = true end
      if line_text:find("ADAPTER_NEIGHBOR", 1, true) then status.has_neighbor = true end
      if line_text:find("ADAPTER_RUN", 1, true) then status.has_run = true end
    end
  end

  return status
end

function DOCX_IMPORT.format_adapter_lines_status(prefix, status)
  status = type(status) == "table" and status or {}
  return "[PSV DOCX PARAGRAPH FORMAT DIAG] " .. tostring(prefix or "ADAPTER_LINES_STATUS") ..
    " file=" .. tostring(status.file or nil) ..
    " adapter=" .. tostring(status.adapter or nil) ..
    " adapter_build=" .. tostring(status.adapter_build or nil) ..
    " bridge=" .. tostring(status.bridge or nil) ..
    " count=" .. tostring(status.count or 0) ..
    " has_summary=" .. tostring(status.has_summary == true) ..
    " has_para=" .. tostring(status.has_para == true) ..
    " has_neighbor=" .. tostring(status.has_neighbor == true) ..
    " has_run=" .. tostring(status.has_run == true)
end

function DOCX_IMPORT.print_pending_adapter_lines_tail_status()
  if not DOCX_IMPORT.paragraph_format_diag_enabled() then
    DOCX_IMPORT.PENDING_ADAPTER_LINES_TAIL_STATUS = nil
    return
  end

  local status = DOCX_IMPORT.PENDING_ADAPTER_LINES_TAIL_STATUS
  if type(status) ~= "table" then return end

  DOCX_IMPORT.PENDING_ADAPTER_LINES_TAIL_STATUS = nil
  DOCX_IMPORT.msg(DOCX_IMPORT.format_adapter_lines_status("ADAPTER_LINES_STATUS_TAIL", status))
end

function DOCX_IMPORT.diag_escape_text(text, max_chars)
  text = tostring(text or "")
  text = text:gsub("\\", "\\\\")
  text = text:gsub("\r", "\\r")
  text = text:gsub("\n", "\\n")
  text = text:gsub("\t", "\\t")
  max_chars = tonumber(max_chars) or 160
  if max_chars > 0 and #text > max_chars then
    return text:sub(1, max_chars) .. "..."
  end
  return text
end

function DOCX_IMPORT.diag_join_ids(ids)
  local parts = {}
  if type(ids) == "table" then
    for _, id in ipairs(ids) do
      parts[#parts + 1] = tostring(id)
    end
  end
  return "[" .. table.concat(parts, ",") .. "]"
end

function DOCX_IMPORT.comment_order_group_refs_for_diag(refs)
  local groups = {}
  local order = {}
  for _, ref in ipairs(type(refs) == "table" and refs or {}) do
    if type(ref) == "table" then
      local key = tostring(ref.paragraph_index or "nil") .. ":" .. tostring(ref.token_index_after or "nil")
      local group = groups[key]
      if not group then
        group = { key = key, paragraph_index = ref.paragraph_index, token_index_after = ref.token_index_after, ids = {}, refs = {} }
        groups[key] = group
        order[#order + 1] = group
      end
      if ref.comment_id ~= nil and tostring(ref.comment_id) ~= "" then
        group.ids[#group.ids + 1] = ref.comment_id
      end
      group.refs[#group.refs + 1] = ref
    end
  end
  return order
end

function DOCX_IMPORT.print_comment_order_load_diagnostics(path, adapter, result, bridged_paragraphs)
  if not DOCX_IMPORT.comment_order_diag_enabled() then return end

  local max_rows = DOCX_IMPORT.comment_order_diag_max_rows()
  local printed = 0
  local function can_print()
    if max_rows <= 0 then return false end
    if printed >= max_rows then return false end
    printed = printed + 1
    return true
  end

  local result_diagnostics = type(result) == "table" and type(result.diagnostics) == "table" and result.diagnostics or {}
  local detail = type(result_diagnostics.comment_order_detail) == "table" and result_diagnostics.comment_order_detail or {}
  local comments = type(bridged_paragraphs) == "table" and type(bridged_paragraphs.comments) == "table" and bridged_paragraphs.comments or {}
  local adapter_version = tostring((adapter and adapter.VERSION) or result_diagnostics.adapter_version or "")
  local adapter_build = tostring((adapter and adapter.BUILD) or result_diagnostics.adapter_build or "")
  local adapter_path = tostring(DOCX_IMPORT.adapter_path or "")

  if can_print() then
    DOCX_IMPORT.msg("[PSV DOCX COMMENT ORDER DIAG] LOAD file=" .. DOCX_IMPORT.basename(path) ..
      " version=" .. tostring(PSV_SCRIPT_VERSION or "") ..
      " adapter=" .. adapter_version ..
      " build=" .. adapter_build ..
      " adapter_path=" .. adapter_path ..
      " bridge=" .. tostring(DOCX_IMPORT.BRIDGE_VERSION or ""))
  end

  for _, row in ipairs(type(detail.parsed_order) == "table" and detail.parsed_order or {}) do
    if not can_print() then return end
    DOCX_IMPORT.msg("[PSV DOCX COMMENT ORDER DIAG] PARSED_ORDER #" .. tostring(row.index or "") ..
      " id=" .. tostring(row.comment_id or "") ..
      " author=" .. tostring(row.author or "") ..
      " date=" .. tostring(row.date or "") ..
      " text=\"" .. DOCX_IMPORT.diag_escape_text(row.text or "", 80) .. "\"")
  end

  for _, row in ipairs(type(detail.raw_refs) == "table" and detail.raw_refs or {}) do
    if not can_print() then return end
    DOCX_IMPORT.msg("[PSV DOCX COMMENT ORDER DIAG] RAW_REF #" .. tostring(row.index or "") ..
      " id=" .. tostring(row.comment_id or "") ..
      " p=" .. tostring(row.paragraph_index or "") ..
      " token_after=" .. tostring(row.token_index_after or "") ..
      " kind=" .. tostring(row.anchor_kind or ""))
  end

  for _, row in ipairs(type(detail.normalized_refs) == "table" and detail.normalized_refs or {}) do
    if not can_print() then return end
    DOCX_IMPORT.msg("[PSV DOCX COMMENT ORDER DIAG] NORMALIZED_REF #" .. tostring(row.index or "") ..
      " id=" .. tostring(row.comment_id or "") ..
      " p=" .. tostring(row.paragraph_index or "") ..
      " token_after=" .. tostring(row.token_index_after or "") ..
      " kind=" .. tostring(row.anchor_kind or "") ..
      " visible=" .. tostring(row.visible_marker == true))
  end

  for _, group in ipairs(type(detail.groups) == "table" and detail.groups or {}) do
    if not can_print() then return end
    DOCX_IMPORT.msg("[PSV DOCX COMMENT ORDER DIAG] ADAPTER_GROUP key=" .. tostring(group.key or "") ..
      " ids=" .. DOCX_IMPORT.diag_join_ids(group.ids or {}))
  end

  for i, id in ipairs(type(comments.order) == "table" and comments.order or {}) do
    if not can_print() then return end
    local comment = type(comments.by_id) == "table" and comments.by_id[id] or nil
    DOCX_IMPORT.msg("[PSV DOCX COMMENT ORDER DIAG] BRIDGED_ORDER #" .. tostring(i) ..
      " id=" .. tostring(id or "") ..
      " author=" .. tostring(comment and comment.author or "") ..
      " date=" .. tostring(comment and comment.date or "") ..
      " text=\"" .. DOCX_IMPORT.diag_escape_text(comment and comment.text or "", 80) .. "\"")
  end

  for i, ref in ipairs(type(comments.refs) == "table" and comments.refs or {}) do
    if not can_print() then return end
    DOCX_IMPORT.msg("[PSV DOCX COMMENT ORDER DIAG] BRIDGED_REF #" .. tostring(i) ..
      " id=" .. tostring(ref.comment_id or "") ..
      " p=" .. tostring(ref.paragraph_index or "") ..
      " token_after=" .. tostring(ref.token_index_after or "") ..
      " kind=" .. tostring(ref.anchor_kind or "") ..
      " visible=" .. tostring(ref.visible_marker == true))
  end

  for _, group in ipairs(DOCX_IMPORT.comment_order_group_refs_for_diag(comments.refs)) do
    if not can_print() then return end
    DOCX_IMPORT.msg("[PSV DOCX COMMENT ORDER DIAG] GROUP key=" .. tostring(group.key or "") ..
      " ids=" .. DOCX_IMPORT.diag_join_ids(group.ids or {}))
  end
end

function DOCX_IMPORT.print_comment_order_marker_click_diag(comments, group_key, para_index, token_index_after, refs, active_group_comment_ids, primary_ref, sx, sy)
  if not DOCX_IMPORT.comment_order_diag_enabled() then return end
  if not tostring(file_path or ""):lower():match("%.docx$") then return end
  if type(refs) ~= "table" or #refs <= 1 then return end

  local ref_ids = {}
  for _, ref in ipairs(refs) do
    if type(ref) == "table" and ref.comment_id ~= nil then
      ref_ids[#ref_ids + 1] = ref.comment_id
    end
  end

  DOCX_IMPORT.msg("[PSV DOCX COMMENT ORDER DIAG] MARKER_CLICK group=" .. tostring(group_key or "") ..
    " para=" .. tostring(para_index or "") ..
    " token_after=" .. tostring(token_index_after or "") ..
    " refs_count=" .. tostring(#refs) ..
    " refs=" .. DOCX_IMPORT.diag_join_ids(ref_ids) ..
    " active_group=" .. DOCX_IMPORT.diag_join_ids(active_group_comment_ids or {}) ..
    " primary=" .. tostring(primary_ref and primary_ref.comment_id or "") ..
    " marker_x=" .. tostring(math.floor((tonumber(sx) or 0) + 0.5)) ..
    " marker_y=" .. tostring(math.floor((tonumber(sy) or 0) + 0.5)) ..
    " grouped=" .. tostring(#refs > 1))
end

function DOCX_IMPORT.print_comment_order_card_blocks_diag(comments, active_id, active_group_comment_ids, comment_blocks)
  if not DOCX_IMPORT.comment_order_diag_enabled() then return end
  if not tostring(file_path or ""):lower():match("%.docx$") then return end
  if type(active_group_comment_ids) ~= "table" or #active_group_comment_ids <= 1 then return end
  if type(comments) ~= "table" then return end

  local block_ids = {}
  local block_parts = {}
  local max_rows = DOCX_IMPORT.comment_order_diag_max_rows()
  for i, block in ipairs(type(comment_blocks) == "table" and comment_blocks or {}) do
    if i > max_rows then break end
    local id = block and block.id or ""
    block_ids[#block_ids + 1] = id
    block_parts[#block_parts + 1] = "#" .. tostring(i) ..
      " id=" .. tostring(id or "") ..
      " author=" .. tostring(block and block.author or "") ..
      " date=" .. tostring(block and block.date or "") ..
      " text=\"" .. DOCX_IMPORT.diag_escape_text(block and block.text or "", 80) .. "\""
  end

  local key = tostring(comments.active_group_key or "") .. "|" .. DOCX_IMPORT.diag_join_ids(active_group_comment_ids) .. "|" .. DOCX_IMPORT.diag_join_ids(block_ids)
  if comments._comment_order_card_diag_key == key then return end
  comments._comment_order_card_diag_key = key

  DOCX_IMPORT.msg("[PSV DOCX COMMENT ORDER DIAG] CARD_BLOCKS active_id=" .. tostring(active_id or "") ..
    " active_group_key=" .. tostring(comments.active_group_key or "") ..
    " active_group=" .. DOCX_IMPORT.diag_join_ids(active_group_comment_ids) ..
    " blocks=" .. DOCX_IMPORT.diag_join_ids(block_ids))
  for _, part in ipairs(block_parts) do
    DOCX_IMPORT.msg("[PSV DOCX COMMENT ORDER DIAG] CARD_BLOCK " .. part)
  end
end

function DOCX_IMPORT.reset_long_token_layout_diag_state(path)
  DOCX_IMPORT.LONG_TOKEN_LAYOUT_DIAG_STATE = {
    file = tostring(path or ""),
    seen = {},
    count = 0,
  }
end

function DOCX_IMPORT.maybe_print_long_token_layout_diag(path, para_index, tok_index, tok, word, word_w, text_column_w, remaining_line_w, max_sx, para_sx, safe_href, line_width)
  if not DOCX_IMPORT.long_token_layout_diag_enabled() then return end
  local path_text = tostring(path or "")
  if not path_text:lower():match("%.docx$") then return end
  if type(tok) ~= "table" or tok.newline == true or type(tok.text) ~= "string" then return end

  word = tostring(word or "")
  if word == "" or word:find("%s") then return end

  word_w = tonumber(word_w) or 0
  text_column_w = math.max(1, tonumber(text_column_w) or 1)
  remaining_line_w = tonumber(remaining_line_w) or text_column_w
  line_width = tonumber(line_width) or 0

  if not (word_w > text_column_w or (word_w > remaining_line_w and line_width == 0)) then return end

  local state = DOCX_IMPORT.LONG_TOKEN_LAYOUT_DIAG_STATE
  if type(state) ~= "table" or state.file ~= path_text then
    DOCX_IMPORT.reset_long_token_layout_diag_state(path_text)
    state = DOCX_IMPORT.LONG_TOKEN_LAYOUT_DIAG_STATE
  end

  local max_rows = DOCX_IMPORT.long_token_layout_diag_max_rows()
  if max_rows <= 0 or state.count >= max_rows then return end

  local preview = DOCX_IMPORT.diag_escape_text(word, 100)
  local key = path_text .. "|" .. tostring(para_index or "") .. "|" .. tostring(tok_index or "") .. "|" .. preview
  if state.seen[key] then return end
  state.seen[key] = true
  state.count = state.count + 1

  DOCX_IMPORT.msg("[PSV DOCX LONG TOKEN DIAG] file=" .. DOCX_IMPORT.basename(path_text) ..
    " para=" .. tostring(para_index or "") ..
    " tok=" .. tostring(tok_index or "") ..
    " has_href=" .. tostring(tok.href ~= nil) ..
    " safe_href=" .. tostring(safe_href ~= nil) ..
    " len=" .. tostring(#word) ..
    " word_w=" .. tostring(math.floor(word_w + 0.5)) ..
    " column_w=" .. tostring(math.floor(text_column_w + 0.5)) ..
    " remaining_w=" .. tostring(math.floor(remaining_line_w + 0.5)) ..
    " max_sx=" .. tostring(math.floor((tonumber(max_sx) or 0) + 0.5)) ..
    " para_sx=" .. tostring(math.floor((tonumber(para_sx) or 0) + 0.5)) ..
    " preview=\"" .. preview .. "\"")
end


-- ══════════════════════════════════════════════════════════════
--  TEMPORARY RENDER SPACING / NO_SPACE_BEFORE DIAGNOSTIC
-- ══════════════════════════════════════════════════════════════
-- Diagnostic-only helper family for v3.0.138. It is intentionally bounded,
-- console-only, and fully gated by PSV_RENDER_SPACING_DIAG_ENABLED.
-- It must not participate in rendering decisions.

function psv_render_spacing_diag_enabled()
  return PSV_RENDER_SPACING_DIAG_ENABLED == true
end

function psv_render_spacing_diag_num(v)
  local n = tonumber(v)
  if n == nil then return "nil" end
  return tostring(math.floor(n * 100 + 0.5) / 100)
end

function psv_render_spacing_diag_bool(v)
  return v and "true" or "false"
end

function psv_render_spacing_diag_rows_max()
  return math.max(0, tonumber(PSV_RENDER_SPACING_DIAG_MAX_ROWS) or 320)
end

function psv_render_spacing_diag_reserved_rows()
  return 4
end

function psv_render_spacing_diag_state()
  PSV_RENDER_SPACING_DIAG_STATE = PSV_RENDER_SPACING_DIAG_STATE or {
    rows = 0,
    cap_reached = false,
    boot_done = false,
    doc_key = nil,
  }
  return PSV_RENDER_SPACING_DIAG_STATE
end

function psv_render_spacing_diag_msg(text, mandatory)
  if not psv_render_spacing_diag_enabled() then return false end
  if type(reaper) ~= "table" or type(reaper.ShowConsoleMsg) ~= "function" then return false end

  local state = psv_render_spacing_diag_state()
  local max_rows = psv_render_spacing_diag_rows_max()
  if max_rows <= 0 then
    state.cap_reached = true
    return false
  end

  local limit = max_rows
  if mandatory ~= true then
    limit = math.max(0, max_rows - psv_render_spacing_diag_reserved_rows())
  end

  if (tonumber(state.rows) or 0) >= limit then
    state.cap_reached = true
    return false
  end

  state.rows = (tonumber(state.rows) or 0) + 1
  reaper.ShowConsoleMsg("[PSV RENDER SPACING DIAG] " .. tostring(text or "") .. "\n")
  return true
end

function psv_render_spacing_diag_escape(text, max_len)
  text = tostring(text or "")
  text = text:gsub("\\", "\\\\"):gsub("\n", "\\n"):gsub("\r", "\\r"):gsub('"', '\\"')
  max_len = tonumber(max_len) or 80
  if #text > max_len then
    text = text:sub(1, max_len) .. "…"
  end
  return text
end

function psv_render_spacing_diag_match_texts_label()
  local match_texts = PSV_RENDER_SPACING_DIAG_MATCH_TEXTS
  if type(match_texts) ~= "table" then return "" end
  local parts = {}
  for _, needle in ipairs(match_texts) do
    if type(needle) == "string" and needle ~= "" then
      parts[#parts + 1] = needle
    end
  end
  return table.concat(parts, "|")
end

function psv_render_spacing_diag_matches_text(text)
  if type(text) ~= "string" or text == "" then return false end
  local match_texts = PSV_RENDER_SPACING_DIAG_MATCH_TEXTS
  if type(match_texts) ~= "table" then return false end
  for _, needle in ipairs(match_texts) do
    if type(needle) == "string" and needle ~= "" and text:find(needle, 1, true) then
      return true
    end
  end
  return false
end

function psv_render_spacing_diag_item_target(item)
  if type(item) ~= "table" then return false end
  if psv_render_spacing_diag_matches_text(tostring(item.word or item.text or "")) then return true end
  local tok = item.tok
  if type(tok) == "table" and psv_render_spacing_diag_matches_text(tostring(tok.text or "")) then return true end
  return false
end

function psv_render_spacing_diag_item_no_space(item)
  if type(item) ~= "table" then return false end
  if item.no_space_before == true then return true end
  if type(item.tok) == "table" and item.tok.no_space_before == true then return true end
  return false
end

function psv_render_spacing_diag_line_is_target(line_tokens)
  if type(line_tokens) ~= "table" then return false end
  for _, item in ipairs(line_tokens) do
    if psv_render_spacing_diag_item_target(item) or psv_render_spacing_diag_item_no_space(item) then
      return true
    end
  end
  return false
end

function psv_render_spacing_diag_pair_basic_relevant(prev_item, cur_item)
  return psv_render_spacing_diag_item_target(prev_item)
    or psv_render_spacing_diag_item_target(cur_item)
    or psv_render_spacing_diag_item_no_space(prev_item)
    or psv_render_spacing_diag_item_no_space(cur_item)
end

function psv_render_spacing_diag_font_label(tok)
  if type(tok) ~= "table" then return "regular" end
  if tok.bold and tok.italic then return "bold_italic" end
  if tok.bold then return "bold" end
  if tok.italic then return "italic" end
  return "regular"
end

function psv_render_spacing_diag_style_flags(tok)
  if type(tok) ~= "table" then return "" end
  return " bold=" .. psv_render_spacing_diag_bool(tok.bold) ..
    " italic=" .. psv_render_spacing_diag_bool(tok.italic) ..
    " underline=" .. psv_render_spacing_diag_bool(tok.underline) ..
    " strike=" .. psv_render_spacing_diag_bool(tok.strike)
end

function psv_render_spacing_diag_pair_relevant(prev_item, cur_item)
  if type(cur_item) ~= "table" or type(cur_item.tok) ~= "table" then return false end
  if cur_item.tok.no_space_before ~= true then return false end
  local cur_word = tostring(cur_item.word or "")
  local prev_word = type(prev_item) == "table" and tostring(prev_item.word or "") or ""
  if psv_render_spacing_diag_matches_text(cur_word) then return true end
  if psv_render_spacing_diag_matches_text(prev_word) then return true end
  if cur_word == "." and (prev_word == "bold" or prev_word == "italic" or prev_word == "underline") then return true end
  return false
end

function psv_render_spacing_diag_source(paras, path)
  local info = type(paras) == "table" and type(paras.import_info) == "table" and paras.import_info or nil
  local source = info and info.source_format or nil
  if source ~= nil and tostring(source) ~= "" then return tostring(source) end
  local lower = tostring(path or ""):lower()
  if lower:match("%.docx$") then return "docx" end
  if lower:match("%.html?$") then return "html" end
  return "unknown"
end

function psv_render_spacing_diag_para_flags(para)
  if type(psv_layout_audit_para_flags) == "function" then
    return psv_layout_audit_para_flags(para)
  end
  local flags = {}
  if type(para) == "table" then
    if para.tag then flags[#flags + 1] = tostring(para.tag) end
    if para.system_placeholder then flags[#flags + 1] = "system_placeholder" end
    if para.docx_unsupported then flags[#flags + 1] = "docx_unsupported" end
    if para.is_heading then flags[#flags + 1] = "heading" end
    if para.is_blank_paragraph then flags[#flags + 1] = "blank" end
  end
  return #flags > 0 and table.concat(flags, ",") or "none"
end

function psv_render_spacing_diag_boot()
  if not psv_render_spacing_diag_enabled() then return false end
  local state = psv_render_spacing_diag_state()
  if PSV_RENDER_SPACING_DIAG_BOOT_ONCE == true and state.boot_done == true then return false end
  state.boot_done = true
  return psv_render_spacing_diag_msg(
    "BOOT version=" .. tostring(PSV_SCRIPT_VERSION or "") ..
    " enabled=" .. psv_render_spacing_diag_bool(PSV_RENDER_SPACING_DIAG_ENABLED == true) ..
    " max_rows=" .. tostring(psv_render_spacing_diag_rows_max()) ..
    " match_texts=\"" .. psv_render_spacing_diag_escape(psv_render_spacing_diag_match_texts_label(), 240) .. "\"",
    true
  )
end

function psv_render_spacing_diag_begin_document(path, paras)
  if not psv_render_spacing_diag_enabled() then return false end
  psv_render_spacing_diag_boot()

  local state = psv_render_spacing_diag_state()
  local doc_key = tostring(path or "") .. "|" .. tostring(type(paras) == "table" and #paras or 0) .. "|" .. tostring(paras)
  if state.doc_key ~= doc_key then
    state.doc_key = doc_key
    state.rows = 0
    state.cap_reached = false
    state.summary_emitted = false
    state.no_targets_emitted = false
    state.paragraphs_scanned = 0
    state.target_paragraphs_seen = 0
    state.para_target_tokens_logged = 0
    state.add_token_targets_seen = 0
    state.target_lines_seen = 0
    state.draw_items_logged = 0
    state.seen_paras = {}
    state.seen_para_tokens = {}
    state.seen_add_tokens = {}
    state.seen_lines = {}
    state.seen_draw_items = {}
    state.seen_draw_pairs = {}
    state.seen_line_pairs = {}
    state.source = psv_render_spacing_diag_source(paras, path)
    state.file = (type(DOCX_IMPORT) == "table" and DOCX_IMPORT.basename and DOCX_IMPORT.basename(path or "")) or tostring(path or "")

    psv_render_spacing_diag_msg(
      "DOC_START file=" .. psv_render_spacing_diag_escape(state.file or "", 160) ..
      " source=" .. tostring(state.source or "unknown") ..
      " paragraphs=" .. tostring(type(paras) == "table" and #paras or 0),
      true
    )
  end
  return true
end

function psv_render_spacing_diag_scan_paragraph(path, paras, para_index, para)
  if not psv_render_spacing_diag_enabled() then return end
  if PSV_RENDER_SPACING_DIAG_LOG_TARGET_TOKENS ~= true then return end
  if type(para) ~= "table" or type(para.tokens) ~= "table" then return end

  local state = psv_render_spacing_diag_state()
  local para_key = tostring(para_index or "")
  state.seen_paras = state.seen_paras or {}
  if state.seen_paras[para_key] then return end
  state.seen_paras[para_key] = true
  state.paragraphs_scanned = (tonumber(state.paragraphs_scanned) or 0) + 1

  local target_indexes = {}
  for tok_index, tok in ipairs(para.tokens) do
    if type(tok) == "table" and psv_render_spacing_diag_matches_text(tostring(tok.text or "")) then
      target_indexes[#target_indexes + 1] = tok_index
    end
  end
  if #target_indexes == 0 then return end

  state.target_paragraphs_seen = (tonumber(state.target_paragraphs_seen) or 0) + 1
  psv_render_spacing_diag_msg(
    "PARA_TARGET p=" .. tostring(para_index or "") ..
    " token_count=" .. tostring(#para.tokens) ..
    " source=" .. tostring(psv_render_spacing_diag_source(paras, path)) ..
    " flags=" .. tostring(psv_render_spacing_diag_para_flags(para))
  )

  local printed = {}
  for _, target_index in ipairs(target_indexes) do
    for _, offset in ipairs({-1, 0, 1}) do
      local tok_index = target_index + offset
      local tok = para.tokens[tok_index]
      if tok and not printed[tok_index] then
        printed[tok_index] = true
        local role = offset == 0 and "target" or (offset < 0 and "prev" or "next")
        local msg_ok = psv_render_spacing_diag_msg(
          "PARA_TOKEN p=" .. tostring(para_index or "") ..
          " tok=" .. tostring(tok_index or "") ..
          " role=" .. role ..
          " text=\"" .. psv_render_spacing_diag_escape(tok.text or "", 100) .. "\"" ..
          " no_space=" .. psv_render_spacing_diag_bool(tok.no_space_before) ..
          " bold=" .. psv_render_spacing_diag_bool(tok.bold) ..
          " italic=" .. psv_render_spacing_diag_bool(tok.italic) ..
          " underline=" .. psv_render_spacing_diag_bool(tok.underline) ..
          " href=" .. psv_render_spacing_diag_bool(tok.href ~= nil) ..
          " fg=" .. psv_render_spacing_diag_bool(tok.fg ~= nil) ..
          " bg=" .. psv_render_spacing_diag_bool(tok.bg ~= nil) ..
          " comment_ids=" .. psv_render_spacing_diag_bool(type(tok.comment_ids) == "table" and #tok.comment_ids > 0)
        )
        if msg_ok and offset == 0 then
          state.para_target_tokens_logged = (tonumber(state.para_target_tokens_logged) or 0) + 1
        end
      end
    end
  end
end

function psv_render_spacing_diag_log_add_token(para_index, token_index, word, tok, line_tokens, sx, word_w, prev_item_before_no_space, prev_gap_before, line_w_before_no_space, entered_no_space_branch, removed_gap, line_w_after_no_space, wrap_triggered)
  if not psv_render_spacing_diag_enabled() then return end
  if PSV_RENDER_SPACING_DIAG_LOG_ADD_TOKEN ~= true then return end

  local target_like = psv_render_spacing_diag_matches_text(tostring(word or ""))
    or (type(tok) == "table" and psv_render_spacing_diag_matches_text(tostring(tok.text or "")))
  local no_space = type(tok) == "table" and tok.no_space_before == true
  if not target_like and not no_space then return end

  local state = psv_render_spacing_diag_state()
  local key = tostring(para_index or "") .. ":" .. tostring(token_index or "") .. ":" .. tostring(word or "") .. ":" .. tostring(#(line_tokens or {})) .. ":" .. tostring(wrap_triggered)
  state.seen_add_tokens = state.seen_add_tokens or {}
  if state.seen_add_tokens[key] then return end
  state.seen_add_tokens[key] = true

  local prev_item = (type(line_tokens) == "table" and #line_tokens > 0) and line_tokens[#line_tokens] or nil
  local prev_end = prev_item and ((tonumber(prev_item.sx) or 0) + (tonumber(prev_item.word_w) or 0)) or nil
  local model_gap = prev_end and ((tonumber(sx) or 0) - prev_end) or nil
  local tag = (target_like and not no_space) and "ADD_TOKEN_NO_NOSPACE" or "ADD_TOKEN"
  local msg_ok = psv_render_spacing_diag_msg(
    tag ..
    " p=" .. tostring(para_index or "") ..
    " tok=" .. tostring(token_index or "") ..
    " word=\"" .. psv_render_spacing_diag_escape(word, 100) .. "\"" ..
    " target=" .. psv_render_spacing_diag_bool(target_like) ..
    " no_space=" .. psv_render_spacing_diag_bool(no_space) ..
    " line_items_before=" .. tostring(type(line_tokens) == "table" and #line_tokens or 0) ..
    " prev=\"" .. psv_render_spacing_diag_escape(prev_item and prev_item.word or "", 80) .. "\"" ..
    " prev_before_no_space=\"" .. psv_render_spacing_diag_escape(prev_item_before_no_space and prev_item_before_no_space.word or "", 80) .. "\"" ..
    " prev_sx=" .. psv_render_spacing_diag_num(prev_item and prev_item.sx) ..
    " prev_word_w=" .. psv_render_spacing_diag_num(prev_item and prev_item.word_w) ..
    " prev_gap_before=" .. psv_render_spacing_diag_num(prev_gap_before) ..
    " line_w_before_no_space=" .. psv_render_spacing_diag_num(line_w_before_no_space) ..
    " entered_no_space_branch=" .. psv_render_spacing_diag_bool(entered_no_space_branch) ..
    " removed_gap=" .. psv_render_spacing_diag_num(removed_gap) ..
    " line_w_after_no_space=" .. psv_render_spacing_diag_num(line_w_after_no_space) ..
    " wrap_triggered=" .. psv_render_spacing_diag_bool(wrap_triggered) ..
    " current_sx=" .. psv_render_spacing_diag_num(sx) ..
    " prev_end=" .. psv_render_spacing_diag_num(prev_end) ..
    " model_gap=" .. psv_render_spacing_diag_num(model_gap) ..
    " word_w=" .. psv_render_spacing_diag_num(word_w) ..
    " font=" .. psv_render_spacing_diag_font_label(tok) ..
    " prev_font=" .. psv_render_spacing_diag_font_label(prev_item and prev_item.tok)
  )
  if msg_ok then
    state.add_token_targets_seen = (tonumber(state.add_token_targets_seen) or 0) + 1
  end
end

function psv_render_spacing_diag_log_line_snapshot(para_index, line_index, line_tokens, line_start_sx, line_width)
  if not psv_render_spacing_diag_enabled() then return false end
  if PSV_RENDER_SPACING_DIAG_LOG_LINE_TOKENS ~= true then return false end
  if not psv_render_spacing_diag_line_is_target(line_tokens) then return false end

  local state = psv_render_spacing_diag_state()
  local key = tostring(para_index or "") .. ":" .. tostring(line_index or "") .. ":" .. tostring(#line_tokens) .. ":" .. tostring(line_start_sx or "")
  state.seen_lines = state.seen_lines or {}
  if state.seen_lines[key] then return true end
  state.seen_lines[key] = true
  state.target_lines_seen = (tonumber(state.target_lines_seen) or 0) + 1

  psv_render_spacing_diag_msg(
    "LINE_SNAPSHOT p=" .. tostring(para_index or "") ..
    " line=" .. tostring(line_index or "") ..
    " token_count=" .. tostring(#line_tokens) ..
    " line_start_sx=" .. psv_render_spacing_diag_num(line_start_sx) ..
    " line_width=" .. psv_render_spacing_diag_num(line_width)
  )

  for i, item in ipairs(line_tokens) do
    psv_render_spacing_diag_msg(
      "LINE_ITEM p=" .. tostring(para_index or "") ..
      " line=" .. tostring(line_index or "") ..
      " i=" .. tostring(i) ..
      " word=\"" .. psv_render_spacing_diag_escape(item.word, 100) .. "\"" ..
      " no_space=" .. psv_render_spacing_diag_bool(item.tok and item.tok.no_space_before) ..
      " sx=" .. psv_render_spacing_diag_num(item.sx) ..
      " word_w=" .. psv_render_spacing_diag_num(item.word_w) ..
      " gap_after=" .. psv_render_spacing_diag_num(item.gap_after) ..
      " font=" .. psv_render_spacing_diag_font_label(item.tok) ..
      psv_render_spacing_diag_style_flags(item.tok)
    )
  end
  return true
end

function psv_render_spacing_diag_log_line_pair(para_index, line_index, prev, cur, prev_i, cur_i, line_start_sx, line_width)
  if not psv_render_spacing_diag_enabled() then return end
  if PSV_RENDER_SPACING_DIAG_LOG_LINE_TOKENS ~= true then return end
  if not psv_render_spacing_diag_pair_basic_relevant(prev, cur) then return end

  local state = psv_render_spacing_diag_state()
  local key = tostring(para_index or "") .. ":" .. tostring(line_index or "") .. ":" .. tostring(prev_i or "") .. ":" .. tostring(cur_i or "") .. ":" .. tostring(prev and prev.word or "") .. ":" .. tostring(cur and cur.word or "")
  state.seen_line_pairs = state.seen_line_pairs or {}
  if state.seen_line_pairs[key] then return end
  state.seen_line_pairs[key] = true

  local prev_end = (tonumber(prev and prev.sx) or 0) + (tonumber(prev and prev.word_w) or 0)
  local model_gap = (tonumber(cur and cur.sx) or 0) - prev_end
  psv_render_spacing_diag_msg(
    "LINE_PAIR p=" .. tostring(para_index or "") ..
    " line=" .. tostring(line_index or "") ..
    " prev_i=" .. tostring(prev_i or "") ..
    " cur_i=" .. tostring(cur_i or "") ..
    " prev=\"" .. psv_render_spacing_diag_escape(prev and prev.word or "", 80) .. "\"" ..
    " cur=\"" .. psv_render_spacing_diag_escape(cur and cur.word or "", 80) .. "\"" ..
    " cur_no_space=" .. psv_render_spacing_diag_bool(cur and cur.tok and cur.tok.no_space_before) ..
    " prev_end=" .. psv_render_spacing_diag_num(prev_end) ..
    " cur_sx=" .. psv_render_spacing_diag_num(cur and cur.sx) ..
    " model_gap=" .. psv_render_spacing_diag_num(model_gap) ..
    " prev_gap_after=" .. psv_render_spacing_diag_num(prev and prev.gap_after) ..
    " line_start_sx=" .. psv_render_spacing_diag_num(line_start_sx) ..
    " line_width=" .. psv_render_spacing_diag_num(line_width) ..
    " prev_font=" .. psv_render_spacing_diag_font_label(prev and prev.tok) ..
    " cur_font=" .. psv_render_spacing_diag_font_label(cur and cur.tok)
  )
end

function psv_render_spacing_diag_log_draw_item(para_index, line_index, draw_i, item, cursor_before_sx, cursor_before_sy, rect_min_x, rect_max_x)
  if not psv_render_spacing_diag_enabled() then return end
  if PSV_RENDER_SPACING_DIAG_LOG_DRAW ~= true then return end
  local state = psv_render_spacing_diag_state()
  local key = tostring(para_index or "") .. ":" .. tostring(line_index or "") .. ":" .. tostring(draw_i or "") .. ":" .. tostring(item and item.word or "")
  state.seen_draw_items = state.seen_draw_items or {}
  if state.seen_draw_items[key] then return end
  state.seen_draw_items[key] = true

  local msg_ok = psv_render_spacing_diag_msg(
    "DRAW_ITEM p=" .. tostring(para_index or "") ..
    " line=" .. tostring(line_index or "") ..
    " i=" .. tostring(draw_i) ..
    " word=\"" .. psv_render_spacing_diag_escape(item and item.word or "", 100) .. "\"" ..
    " no_space=" .. psv_render_spacing_diag_bool(item and item.tok and item.tok.no_space_before) ..
    " model_sx=" .. psv_render_spacing_diag_num(item and item.sx) ..
    " cursor_before_sx=" .. psv_render_spacing_diag_num(cursor_before_sx) ..
    " rect_min_x=" .. psv_render_spacing_diag_num(rect_min_x) ..
    " rect_max_x=" .. psv_render_spacing_diag_num(rect_max_x) ..
    " rect_w=" .. psv_render_spacing_diag_num((tonumber(rect_max_x) or 0) - (tonumber(rect_min_x) or 0)) ..
    " word_w=" .. psv_render_spacing_diag_num(item and item.word_w) ..
    " gap_after=" .. psv_render_spacing_diag_num(item and item.gap_after) ..
    " font=" .. psv_render_spacing_diag_font_label(item and item.tok) ..
    psv_render_spacing_diag_style_flags(item and item.tok)
  )
  if msg_ok then
    state.draw_items_logged = (tonumber(state.draw_items_logged) or 0) + 1
  end
end

function psv_render_spacing_diag_log_draw_pair(para_index, line_index, prev, cur, prev_rect, cur_rect)
  if not psv_render_spacing_diag_enabled() then return end
  if PSV_RENDER_SPACING_DIAG_LOG_DRAW ~= true then return end
  if type(prev_rect) ~= "table" or type(cur_rect) ~= "table" then return end

  local state = psv_render_spacing_diag_state()
  local key = tostring(para_index or "") .. ":" .. tostring(line_index or "") .. ":" .. tostring(prev and prev.word or "") .. ":" .. tostring(cur and cur.word or "") .. ":" .. tostring(prev_rect.max_x or "") .. ":" .. tostring(cur_rect.min_x or "")
  state.seen_draw_pairs = state.seen_draw_pairs or {}
  if state.seen_draw_pairs[key] then return end
  state.seen_draw_pairs[key] = true

  local model_prev_end = (tonumber(prev and prev.sx) or 0) + (tonumber(prev and prev.word_w) or 0)
  local model_gap = (tonumber(cur and cur.sx) or 0) - model_prev_end
  local actual_rect_gap = (tonumber(cur_rect.min_x) or 0) - (tonumber(prev_rect.max_x) or 0)
  psv_render_spacing_diag_msg(
    "DRAW_PAIR p=" .. tostring(para_index or "") ..
    " line=" .. tostring(line_index or "") ..
    " prev=\"" .. psv_render_spacing_diag_escape(prev and prev.word or "", 80) .. "\"" ..
    " cur=\"" .. psv_render_spacing_diag_escape(cur and cur.word or "", 80) .. "\"" ..
    " model_gap=" .. psv_render_spacing_diag_num(model_gap) ..
    " actual_rect_gap=" .. psv_render_spacing_diag_num(actual_rect_gap) ..
    " prev_rect_max=" .. psv_render_spacing_diag_num(prev_rect.max_x) ..
    " cur_rect_min=" .. psv_render_spacing_diag_num(cur_rect.min_x) ..
    " prev_font=" .. psv_render_spacing_diag_font_label(prev and prev.tok) ..
    " cur_font=" .. psv_render_spacing_diag_font_label(cur and cur.tok)
  )
end

function psv_render_spacing_diag_finish_document()
  if not psv_render_spacing_diag_enabled() then return end
  local state = psv_render_spacing_diag_state()
  if state.summary_emitted == true then return end
  state.summary_emitted = true

  if (tonumber(state.target_paragraphs_seen) or 0) == 0 then
    psv_render_spacing_diag_msg(
      "NO_TARGETS_FOUND paragraphs_scanned=" .. tostring(tonumber(state.paragraphs_scanned) or 0) ..
      " reason=no target text matched paragraph token stream",
      true
    )
  end

  psv_render_spacing_diag_msg(
    "SUMMARY paragraphs_scanned=" .. tostring(tonumber(state.paragraphs_scanned) or 0) ..
    " target_paragraphs=" .. tostring(tonumber(state.target_paragraphs_seen) or 0) ..
    " para_tokens=" .. tostring(tonumber(state.para_target_tokens_logged) or 0) ..
    " add_tokens=" .. tostring(tonumber(state.add_token_targets_seen) or 0) ..
    " target_lines=" .. tostring(tonumber(state.target_lines_seen) or 0) ..
    " draw_items=" .. tostring(tonumber(state.draw_items_logged) or 0) ..
    " rows=" .. tostring(tonumber(state.rows) or 0) ..
    " cap=" .. psv_render_spacing_diag_bool(state.cap_reached == true),
    true
  )
end

psv_render_spacing_diag_boot()


-- ══════════════════════════════════════════════════════════════
--  TEMPORARY LIVE-SCROLL LAYOUT AUDIT DIAGNOSTIC
-- ══════════════════════════════════════════════════════════════
-- Diagnostic-only helper family for v3.0.138. It is intentionally runtime-only,
-- bounded per scroll segment, and fully gated by PSV_LAYOUT_AUDIT_ENABLED.
-- It must not participate in layout decisions.

function psv_layout_audit_enabled()
  return PSV_LAYOUT_AUDIT_ENABLED == true
end

function psv_layout_audit_num(v)
  local n = tonumber(v)
  if n == nil then return "nil" end
  return tostring(math.floor(n * 10 + 0.5) / 10)
end

function psv_layout_audit_bool(v)
  return v and "true" or "false"
end

function psv_layout_audit_reset(path)
  PSV_LAYOUT_AUDIT_STATE = {
    file = tostring(path or ""),
    epoch = tonumber(PSV_LAYOUT_AUDIT_EPOCH) or 1,
    segment_id = nil,
    rows_in_segment = 0,
    seen = {},
    counters = {},
    frame = 0,
    last_scroll_y = nil,
    last_viewport_doc_top = nil,
    last_viewport_doc_bottom = nil,
  }
end

function psv_layout_audit_state(path)
  local path_text = tostring(path or "")
  local epoch = tonumber(PSV_LAYOUT_AUDIT_EPOCH) or 1
  if type(PSV_LAYOUT_AUDIT_STATE) ~= "table"
     or PSV_LAYOUT_AUDIT_STATE.file ~= path_text
     or PSV_LAYOUT_AUDIT_STATE.epoch ~= epoch then
    psv_layout_audit_reset(path_text)
  end
  return PSV_LAYOUT_AUDIT_STATE
end

function psv_layout_audit_rows_max()
  local n = tonumber(PSV_LAYOUT_AUDIT_MAX_ROWS_PER_SEGMENT) or 160
  if n < 0 then n = 0 end
  return math.floor(n + 0.5)
end

function psv_layout_audit_msg(path, text, dedupe_key)
  if not psv_layout_audit_enabled() then return false end
  if type(reaper) ~= "table" or type(reaper.ShowConsoleMsg) ~= "function" then return false end
  local state = psv_layout_audit_state(path)
  local max_rows = psv_layout_audit_rows_max()
  if max_rows <= 0 or (tonumber(state.rows_in_segment) or 0) >= max_rows then return false end

  if dedupe_key ~= nil then
    local key = tostring(dedupe_key)
    if state.seen and state.seen[key] then return false end
    state.seen = state.seen or {}
    state.seen[key] = true
  end

  state.rows_in_segment = (tonumber(state.rows_in_segment) or 0) + 1
  reaper.ShowConsoleMsg("[PSV LAYOUT AUDIT] " .. tostring(text or "") .. "\n")
  return true
end

function psv_layout_audit_source_format(paras, path)
  local info = type(paras) == "table" and type(paras.import_info) == "table" and paras.import_info or nil
  local source = info and info.source_format or nil
  if source ~= nil and tostring(source) ~= "" then return tostring(source) end
  local lower = tostring(path or ""):lower()
  if lower:match("%.docx$") then return "docx" end
  if lower:match("%.html?$") then return "html" end
  return "unknown"
end

function psv_layout_audit_para_flags(para)
  local flags = {}
  if type(para) == "table" then
    if para.tag then flags[#flags + 1] = tostring(para.tag) end
    if para.system_placeholder then flags[#flags + 1] = "system_placeholder" end
    if para.docx_unsupported then flags[#flags + 1] = "docx_unsupported" end
    if para.is_heading then flags[#flags + 1] = "heading" end
    if para.is_blank_paragraph then flags[#flags + 1] = "blank" end
  end
  return #flags > 0 and table.concat(flags, ",") or "none"
end

function psv_layout_audit_page_state(y, params)
  params = type(params) == "table" and params or {}
  local top_gap = tonumber(params.top_gap) or 0
  local slot_h = math.max(1, tonumber(params.slot_h) or 1)
  local page_h = math.max(1, tonumber(params.page_h) or 1)
  local pad_top = math.max(0, tonumber(params.pad_top) or 0)
  local pad_bottom = math.max(0, tonumber(params.pad_bottom) or 0)
  local yy = tonumber(y) or 0
  local rel = yy - top_gap
  local page_index = math.floor(rel / slot_h)
  if page_index < 0 then page_index = 0 end
  local page_top = top_gap + page_index * slot_h
  local content_top = page_top + pad_top
  local content_bottom = page_top + page_h - pad_bottom
  local next_content_top = top_gap + (page_index + 1) * slot_h + pad_top
  return {
    page = page_index,
    phase_y = yy - page_top,
    content_top = content_top,
    content_bottom = content_bottom,
    dist_to_content_top = yy - content_top,
    dist_to_content_bottom = content_bottom - yy,
    dist_to_next_content_top = next_content_top - yy,
  }
end

function psv_layout_audit_is_visible_or_near(path, y1, y2)
  if not psv_layout_audit_enabled() then return false end
  local state = psv_layout_audit_state(path)
  local top = tonumber(state.last_viewport_doc_top)
  local bottom = tonumber(state.last_viewport_doc_bottom)
  if top == nil or bottom == nil then return true end
  local pad = math.max(0, tonumber(PSV_LAYOUT_AUDIT_VISIBLE_PAD_PX) or 320)
  local a = tonumber(y1) or 0
  local b = tonumber(y2) or a
  if b < a then a, b = b, a end
  return b >= (top - pad) and a <= (bottom + pad)
end

function psv_layout_audit_is_near_page_boundary(y, params)
  local ps = psv_layout_audit_page_state(y, params)
  local threshold = math.max(0, tonumber(PSV_LAYOUT_AUDIT_PAGE_BOUNDARY_WINDOW_PX) or 180)
  return math.abs(tonumber(ps.dist_to_content_bottom) or 999999) <= threshold
    or math.abs(tonumber(ps.dist_to_content_top) or 999999) <= threshold
    or math.abs(tonumber(ps.dist_to_next_content_top) or 999999) <= threshold
end

function psv_layout_audit_relevant(path, y1, y2, params)
  if psv_layout_audit_is_visible_or_near(path, y1, y2) then return true end
  return psv_layout_audit_is_near_page_boundary(y1, params)
    or psv_layout_audit_is_near_page_boundary(y2 or y1, params)
end

function psv_layout_audit_counter(path, name, amount)
  if not psv_layout_audit_enabled() then return end
  local state = psv_layout_audit_state(path)
  state.counters = state.counters or {}
  state.counters[name] = (tonumber(state.counters[name]) or 0) + (amount or 1)
end

function psv_layout_audit_begin_segment(ctx, paras, path, horizontal_geom, params)
  if not psv_layout_audit_enabled() then return nil end
  params = type(params) == "table" and params or {}
  local state = psv_layout_audit_state(path)
  local scroll_y = 0
  if type(reaper.ImGui_GetScrollY) == "function" then
    scroll_y = tonumber(reaper.ImGui_GetScrollY(ctx)) or 0
  end
  local viewport_h = tonumber(params.viewport_h) or 0
  local segment_px = tonumber(PSV_LAYOUT_AUDIT_SCROLL_SEGMENT_PX) or 120
  if segment_px < 1 then segment_px = 120 end
  local segment_id = math.floor(scroll_y / segment_px)

  if state.segment_id ~= segment_id then
    state.segment_id = segment_id
    state.rows_in_segment = 0
    state.seen = {}
    state.counters = {}
    state.segment_summary_printed = false
  end

  state.frame = (tonumber(state.frame) or 0) + 1
  state.last_scroll_y = scroll_y
  state.last_viewport_doc_top = scroll_y
  state.last_viewport_doc_bottom = scroll_y + viewport_h

  if PSV_LAYOUT_AUDIT_LOG_SEGMENT_HEADER == true then
    local source = psv_layout_audit_source_format(paras, path)
    psv_layout_audit_msg(path,
      "SEGMENT file=" .. DOCX_IMPORT.basename(path or "") ..
      " version=" .. tostring(PSV_SCRIPT_VERSION or "") ..
      " epoch=" .. tostring(tonumber(PSV_LAYOUT_AUDIT_EPOCH) or 1) ..
      " segment=" .. tostring(segment_id) ..
      " scroll_y=" .. psv_layout_audit_num(scroll_y) ..
      " viewport_doc=" .. psv_layout_audit_num(state.last_viewport_doc_top) .. ".." .. psv_layout_audit_num(state.last_viewport_doc_bottom) ..
      " source=" .. source ..
      " page_flow=" .. psv_layout_audit_bool(params.page_flow_enabled) ..
      " cached_culling_under_page_flow=" .. psv_layout_audit_bool(params.page_flow_cached_culling_allowed) ..
      " page_h=" .. psv_layout_audit_num(params.page_h) ..
      " page_gap=" .. psv_layout_audit_num(params.page_gap_y) ..
      " pad_top=" .. psv_layout_audit_num(params.page_pad_top) ..
      " pad_bottom=" .. psv_layout_audit_num(params.page_pad_bottom) ..
      " stack_top_gap=" .. psv_layout_audit_num(params.page_stack_top_gap) ..
      " min_start_lines=" .. psv_layout_audit_num(PAGE_FLOW_MIN_START_LINES) ..
      " content_w=" .. psv_layout_audit_num(horizontal_geom and horizontal_geom.content_w) ..
      " wrap_right=" .. psv_layout_audit_num(horizontal_geom and horizontal_geom.wrap_right_sx),
      "SEGMENT:" .. tostring(segment_id))
  end
  return state
end

function psv_layout_audit_para_start(path, para_index, para, start_cy, start_sy, cached_h, force_render, force_reason, page_flow_enabled, cached_culling_allowed, page_params)
  if not psv_layout_audit_enabled() or PSV_LAYOUT_AUDIT_LOG_VISIBLE_PARAGRAPHS ~= true then return end
  local cached_num = tonumber(cached_h) or 0
  local est_end = (tonumber(start_cy) or 0) + math.max(cached_num, 1)
  if not psv_layout_audit_relevant(path, start_cy, est_end, page_params) then return end
  local ps = psv_layout_audit_page_state(start_cy, page_params)
  psv_layout_audit_msg(path,
    "PARA_START i=" .. tostring(para_index) ..
    " page=" .. tostring(ps.page) ..
    " phase_y=" .. psv_layout_audit_num(ps.phase_y) ..
    " y=" .. psv_layout_audit_num(start_cy) ..
    " sy=" .. psv_layout_audit_num(start_sy) ..
    " flags=" .. psv_layout_audit_para_flags(para) ..
    " cached_h=" .. psv_layout_audit_num(cached_h) ..
    " force=" .. psv_layout_audit_bool(force_render) ..
    " force_reason=" .. tostring(force_reason or "") ..
    " page_flow=" .. psv_layout_audit_bool(page_flow_enabled) ..
    " cached_culling_allowed=" .. psv_layout_audit_bool(cached_culling_allowed),
    "PARA_START:" .. tostring(para_index) .. ":" .. psv_layout_audit_num(start_cy))
end

function psv_layout_audit_culling_decision(path, para_index, decision, data, page_params)
  if not psv_layout_audit_enabled() or PSV_LAYOUT_AUDIT_LOG_CULLING ~= true then return end
  data = type(data) == "table" and data or {}
  local start_y = tonumber(data.para_start_cy) or 0
  local est_end_y = tonumber(data.para_end_cy_est) or (start_y + math.max(tonumber(data.cached_h) or 1, 1))
  if decision ~= "cached_dummy_skip" and not data.force_render and not psv_layout_audit_relevant(path, start_y, est_end_y, page_params) then return end
  psv_layout_audit_counter(path, decision or "culling_decision", 1)
  psv_layout_audit_msg(path,
    "CULLING para=" .. tostring(para_index) ..
    " decision=" .. tostring(decision or "") ..
    " offscreen=" .. psv_layout_audit_bool(data.offscreen) ..
    " intersects_padded=" .. psv_layout_audit_bool(psv_layout_audit_is_visible_or_near(path, start_y, est_end_y)) ..
    " cached=" .. psv_layout_audit_bool(data.cached) ..
    " cached_h=" .. psv_layout_audit_num(data.cached_h) ..
    " force=" .. psv_layout_audit_bool(data.force_render) ..
    " page_flow=" .. psv_layout_audit_bool(data.page_flow_enabled) ..
    " page_flow_cached_allowed=" .. psv_layout_audit_bool(data.page_flow_cached_culling_allowed) ..
    " para_start_y=" .. psv_layout_audit_num(start_y) ..
    " para_end_y_est=" .. psv_layout_audit_num(est_end_y) ..
    " para_start_sy=" .. psv_layout_audit_num(data.para_start_sy) ..
    " para_end_sy_est=" .. psv_layout_audit_num(data.para_end_sy_est),
    "CULL:" .. tostring(para_index) .. ":" .. tostring(decision) .. ":" .. psv_layout_audit_num(start_y))
end

function psv_layout_audit_page_jump(path, kind, para_index, line_index, from_y, to_y, dummy_h, from_page, to_page, reason, page_params)
  if not psv_layout_audit_enabled() or PSV_LAYOUT_AUDIT_LOG_PAGE_JUMPS ~= true then return end
  local visible_near = psv_layout_audit_relevant(path, from_y, to_y, page_params)
  if not visible_near then return end
  psv_layout_audit_counter(path, "page_jumps", 1)
  if tostring(kind or ""):find("line", 1, true) then
    psv_layout_audit_counter(path, "line_jumps", 1)
  end
  psv_layout_audit_msg(path,
    "PAGE_JUMP kind=" .. tostring(kind or "") ..
    " para=" .. tostring(para_index or "") ..
    " line=" .. tostring(line_index or "") ..
    " from_page=" .. tostring(from_page or "") ..
    " to_page=" .. tostring(to_page or "") ..
    " from_y=" .. psv_layout_audit_num(from_y) ..
    " to_y=" .. psv_layout_audit_num(to_y) ..
    " dummy_h=" .. psv_layout_audit_num(dummy_h) ..
    " visible_near=" .. psv_layout_audit_bool(visible_near) ..
    " reason=" .. tostring(reason or ""),
    "JUMP:" .. tostring(kind) .. ":" .. tostring(para_index) .. ":" .. tostring(line_index) .. ":" .. psv_layout_audit_num(from_y) .. ":" .. psv_layout_audit_num(to_y))
end

function psv_layout_audit_line_near_page_boundary(path, para_index, line_index, line_y, line_h, line_tokens, line_width, page_params)
  if not psv_layout_audit_enabled() or PSV_LAYOUT_AUDIT_LOG_LINES_NEAR_PAGE_BOUNDARY ~= true then return end
  local ps = psv_layout_audit_page_state(line_y, page_params)
  local threshold = tonumber(PSV_LAYOUT_AUDIT_PAGE_BOUNDARY_WINDOW_PX) or 180
  local bottom_dist = ps.content_bottom - ((tonumber(line_y) or 0) + (tonumber(line_h) or 0))
  local top_dist = (tonumber(line_y) or 0) - ps.content_top
  if math.abs(bottom_dist) > threshold and math.abs(top_dist) > threshold then return end
  if not psv_layout_audit_is_visible_or_near(path, line_y, (tonumber(line_y) or 0) + (tonumber(line_h) or 0)) then return end
  psv_layout_audit_msg(path,
    "LINE_BOUNDARY para=" .. tostring(para_index) ..
    " line=" .. tostring(line_index or "") ..
    " page=" .. tostring(ps.page) ..
    " line_y=" .. psv_layout_audit_num(line_y) ..
    " line_h=" .. psv_layout_audit_num(line_h) ..
    " dist_bottom=" .. psv_layout_audit_num(bottom_dist) ..
    " dist_top=" .. psv_layout_audit_num(top_dist) ..
    " tokens=" .. tostring(type(line_tokens) == "table" and #line_tokens or 0) ..
    " line_w=" .. psv_layout_audit_num(line_width),
    "LINE:" .. tostring(para_index) .. ":" .. tostring(line_index) .. ":" .. psv_layout_audit_num(line_y))
end

function psv_layout_audit_cache_update(path, para_index, old_h, new_h, start_y, line_jumps, start_pushes, page_params)
  if not psv_layout_audit_enabled() or PSV_LAYOUT_AUDIT_LOG_CACHE_UPDATES ~= true then return end
  local old_n = tonumber(old_h)
  local new_n = tonumber(new_h) or 0
  local delta = old_n and math.abs(old_n - new_n) or new_n
  local relevant = delta >= 2
    or (tonumber(line_jumps) or 0) > 0
    or (tonumber(start_pushes) or 0) > 0
    or psv_layout_audit_relevant(path, start_y, (tonumber(start_y) or 0) + new_n, page_params)
  if not relevant then return end
  local ps = psv_layout_audit_page_state(start_y, page_params)
  psv_layout_audit_counter(path, "cache_updates", 1)
  psv_layout_audit_msg(path,
    "CACHE_UPDATE i=" .. tostring(para_index) ..
    " old=" .. psv_layout_audit_num(old_h) ..
    " new=" .. psv_layout_audit_num(new_h) ..
    " delta=" .. psv_layout_audit_num(delta) ..
    " start_page=" .. tostring(ps.page) ..
    " start_phase=" .. psv_layout_audit_num(ps.phase_y) ..
    " line_jumps=" .. tostring(line_jumps or 0) ..
    " start_pushes=" .. tostring(start_pushes or 0),
    "CACHE:" .. tostring(para_index) .. ":" .. psv_layout_audit_num(start_y) .. ":" .. psv_layout_audit_num(new_h))
end

function psv_layout_audit_count_line_side_effects(path, line_tokens)
  if not psv_layout_audit_enabled() or type(line_tokens) ~= "table" then return end
  for _, item in ipairs(line_tokens) do
    if type(item) == "table" then
      if item.safe_href then psv_layout_audit_counter(path, "link_hitboxes", 1) end
      if item.comment_range_group_key then psv_layout_audit_counter(path, "comment_range_hitboxes", 1) end
      if item.is_comment_marker then psv_layout_audit_counter(path, "marker_anchors", 1) end
      if item.search_hit then psv_layout_audit_counter(path, "search_hits", 1) end
    end
  end
end

function psv_layout_audit_count_placeholder(path)
  if not psv_layout_audit_enabled() then return end
  psv_layout_audit_counter(path, "system_placeholders", 1)
end

function psv_layout_audit_segment_summary(path)
  if not psv_layout_audit_enabled() then return end
  local state = psv_layout_audit_state(path)
  if state.segment_summary_printed then return end
  state.segment_summary_printed = true
  local c = state.counters or {}
  psv_layout_audit_msg(path,
    "SEGMENT_SUMMARY segment=" .. tostring(state.segment_id or "") ..
    " full_render=" .. tostring(c.full_render or 0) ..
    " cached_skip=" .. tostring(c.cached_dummy_skip or 0) ..
    " page_jumps=" .. tostring(c.page_jumps or 0) ..
    " line_jumps=" .. tostring(c.line_jumps or 0) ..
    " cache_updates=" .. tostring(c.cache_updates or 0) ..
    " link_hitboxes=" .. tostring(c.link_hitboxes or 0) ..
    " comment_range_hitboxes=" .. tostring(c.comment_range_hitboxes or 0) ..
    " marker_anchors=" .. tostring(c.marker_anchors or 0) ..
    " search_hits=" .. tostring(c.search_hits or 0) ..
    " system_placeholders=" .. tostring(c.system_placeholders or 0),
    "SUMMARY:" .. tostring(state.segment_id or ""))
end

function DOCX_IMPORT.block_text_for_diag(block)
  local parts = {}
  for _, token in ipairs(block and block.tokens or {}) do
    if type(token) == "table" then
      if token.newline then
        parts[#parts + 1] = "\n"
      elseif token.text ~= nil then
        if #parts > 0 and parts[#parts] ~= "\n" then
          parts[#parts + 1] = " "
        end
        parts[#parts + 1] = tostring(token.text)
      end
    end
  end
  return table.concat(parts)
end

function DOCX_IMPORT.match_paragraph_format_diag_text(text)
  if not DOCX_IMPORT.paragraph_format_diag_enabled() then return nil end
  local lower = tostring(text or ""):lower()
  for _, key in ipairs(DOCX_IMPORT.paragraph_format_diag_match_texts()) do
    key = tostring(key or "")
    if key ~= "" and lower:find(key:lower(), 1, true) then
      return key
    end
  end
  return nil
end

function DOCX_IMPORT.diag_token_flags(token)
  local flags = {}
  if token.bold then flags[#flags + 1] = "b" end
  if token.italic then flags[#flags + 1] = "i" end
  if token.underline then flags[#flags + 1] = "u" end
  if token.strike then flags[#flags + 1] = "s" end
  if token.fg ~= nil then flags[#flags + 1] = "fg" end
  if token.bg ~= nil then flags[#flags + 1] = "bg" end
  if token.href ~= nil then flags[#flags + 1] = "href" end
  if token.comment_ids ~= nil then flags[#flags + 1] = "comments=" .. tostring(#(token.comment_ids or {})) end
  return #flags > 0 and table.concat(flags, ",") or "none"
end

function DOCX_IMPORT.drop_pure_empty_paragraphs_enabled()
  return PSV_DOCX_DROP_PURE_EMPTY_PARAGRAPHS == true
end

function DOCX_IMPORT.collect_referenced_docx_paragraph_indices(comments)
  local referenced = {}

  local function mark(index)
    local n = tonumber(index)
    if n ~= nil then referenced[n] = true end
  end

  comments = type(comments) == "table" and comments or {}

  for _, ref in ipairs(type(comments.refs) == "table" and comments.refs or {}) do
    if type(ref) == "table" then
      mark(ref.paragraph_index)
    end
  end

  for _, range in ipairs(type(comments.ranges) == "table" and comments.ranges or {}) do
    if type(range) == "table" then
      mark(range.start_paragraph_index)
      mark(range.end_paragraph_index)
      mark(range.reference_paragraph_index)
    end
  end

  return referenced
end

function DOCX_IMPORT.value_has_meaningful_payload(value)
  if value == nil or value == false then return false end
  if type(value) == "table" then return next(value) ~= nil end
  if type(value) == "string" then return value ~= "" end
  return true
end

function DOCX_IMPORT.token_has_meaningful_nonempty_payload(token)
  if type(token) ~= "table" then return token ~= nil end

  if token.newline == true then return true end

  if token.text ~= nil then
    local visible = tostring(token.text):gsub("[%s%c]", "")
    if visible ~= "" then return true end
  end

  local preserve_fields = {
    "comment_ids", "comment_id", "comments", "refs", "ranges", "anchors", "anchor_kind",
    "href", "hyperlink", "hyperlinks",
    "table", "tables", "drawing", "drawings", "image", "images",
    "object", "objects", "placeholder", "placeholders",
  }

  for _, field in ipairs(preserve_fields) do
    if DOCX_IMPORT.value_has_meaningful_payload(token[field]) then return true end
  end

  if token.bold ~= nil or token.italic ~= nil or token.underline ~= nil or token.strike ~= nil or
      token.fg ~= nil or token.bg ~= nil or token.bg_source ~= nil then
    return true
  end

  return false
end

function DOCX_IMPORT.block_has_meaningful_docx_payload(block)
  if type(block) ~= "table" then return false end

  local preserve_fields = {
    "comment_ids", "comment_id", "comments", "refs", "ranges", "anchors", "anchor_kind",
    "href", "hyperlink", "hyperlinks",
    "table", "tables", "drawing", "drawings", "image", "images",
    "object", "objects", "placeholder", "placeholders",
  }

  for _, field in ipairs(preserve_fields) do
    if DOCX_IMPORT.value_has_meaningful_payload(block[field]) then return true end
  end

  return false
end

function DOCX_IMPORT.should_drop_pure_empty_paragraph(block, source_block_index, bridged_block, referenced_source_paragraph_indices)
  if not DOCX_IMPORT.drop_pure_empty_paragraphs_enabled() then return false end
  if type(block) ~= "table" then return false end
  if block.is_blank_paragraph ~= true then return false end
  if block.is_heading == true then return false end
  if type(referenced_source_paragraph_indices) == "table" and referenced_source_paragraph_indices[source_block_index] then return false end
  if DOCX_IMPORT.block_has_meaningful_docx_payload(block) then return false end

  for _, token in ipairs(type(block.tokens) == "table" and block.tokens or {}) do
    if DOCX_IMPORT.token_has_meaningful_nonempty_payload(token) then return false end
  end

  for _, token in ipairs(type(bridged_block) == "table" and type(bridged_block.tokens) == "table" and bridged_block.tokens or {}) do
    if DOCX_IMPORT.token_has_meaningful_nonempty_payload(token) then return false end
  end

  return true
end

function DOCX_IMPORT.remap_docx_paragraph_index(source_to_bridged_index, value)
  local n = tonumber(value)
  if n ~= nil and type(source_to_bridged_index) == "table" and source_to_bridged_index[n] ~= nil then
    return source_to_bridged_index[n]
  end
  return value
end

function DOCX_IMPORT.copy_docx_range_with_remapped_paragraphs(range, source_to_bridged_index)
  if type(range) ~= "table" then return range end

  local out = {}
  for k, v in pairs(range) do
    out[k] = v
  end

  out.start_paragraph_index = DOCX_IMPORT.remap_docx_paragraph_index(source_to_bridged_index, range.start_paragraph_index)
  out.end_paragraph_index = DOCX_IMPORT.remap_docx_paragraph_index(source_to_bridged_index, range.end_paragraph_index)
  out.reference_paragraph_index = DOCX_IMPORT.remap_docx_paragraph_index(source_to_bridged_index, range.reference_paragraph_index)

  return out
end

function DOCX_IMPORT.print_empty_paragraph_normalization_status(path, bridge_diagnostics)
  if not DOCX_IMPORT.paragraph_format_diag_enabled() then return end

  bridge_diagnostics = type(bridge_diagnostics) == "table" and bridge_diagnostics or {}
  local enabled = DOCX_IMPORT.drop_pure_empty_paragraphs_enabled()
  local skipped = enabled and tonumber(bridge_diagnostics.dropped_pure_empty_paragraph_count or 0) or 0

  DOCX_IMPORT.msg("[PSV DOCX PARAGRAPH FORMAT DIAG] EMPTY_PARAGRAPH_NORMALIZATION file=" .. DOCX_IMPORT.basename(path) ..
    " enabled=" .. tostring(enabled == true) ..
    " skipped=" .. tostring(skipped or 0))
end

function DOCX_IMPORT.script_dir()
  local _, script_path = reaper.get_action_context()
  script_path = tostring(script_path or "")
  if script_path:sub(1, 1) == "@" then script_path = script_path:sub(2) end
  local dir = script_path:match("^(.*[\\/])")
  if dir and dir ~= "" then return dir end
  return ""
end

function DOCX_IMPORT.create_embedded_adapter()
-- Embedded DOCX adapter module, version 0.5.
-- Self-contained document parsing; no ReaImGui or main viewer state.

local DOCX_ADAPTER = {}
DOCX_ADAPTER.VERSION = "0.5"
DOCX_ADAPTER.BUILD = "psv-3.0.139-partial-run-split"

local DOCX_RUN_BOUNDARY_DIAG_STATE = { path = nil, rows = 0 }

local function rb_diag_enabled()
  return PSV_DOCX_RUN_BOUNDARY_DIAG_ENABLED == true
end

local function rb_diag_max_rows()
  return math.max(0, tonumber(PSV_DOCX_RUN_BOUNDARY_DIAG_MAX_ROWS) or 180)
end

local function rb_diag_reset(path)
  path = tostring(path or "")
  if DOCX_RUN_BOUNDARY_DIAG_STATE.path ~= path then
    DOCX_RUN_BOUNDARY_DIAG_STATE.path = path
    DOCX_RUN_BOUNDARY_DIAG_STATE.rows = 0
  end
end

local function rb_diag_bool(v)
  return tostring(v == true)
end

local function rb_diag_basename(path)
  local s = tostring(path or "")
  return s:match("([^/\\]+)$") or s
end

local function rb_utf8_next_pos(s, pos)
  local b = s and s:byte(pos) or nil
  if not b then return nil end
  if b < 0x80 then return pos + 1 end
  if b < 0xE0 then return math.min(#s + 1, pos + 2) end
  if b < 0xF0 then return math.min(#s + 1, pos + 3) end
  return math.min(#s + 1, pos + 4)
end

local function rb_truncate_chars(s, max_chars)
  s = tostring(s or "")
  max_chars = tonumber(max_chars) or 0
  if max_chars <= 0 then return s end
  local pos = 1
  local count = 0
  local last_good = 1
  while pos <= #s and count < max_chars do
    local next_pos = rb_utf8_next_pos(s, pos)
    if not next_pos or next_pos <= pos then break end
    count = count + 1
    last_good = next_pos
    pos = next_pos
  end
  if pos <= #s then
    return s:sub(1, math.max(0, last_good - 1)) .. "…"
  end
  return s
end

local function rb_diag_preview(text, max_chars)
  local s = rb_truncate_chars(tostring(text or ""), max_chars or 120)
  s = s:gsub("\\", "\\\\")
       :gsub("\r", "\\r")
       :gsub("\n", "\\n")
       :gsub("\t", "\\t")
  return s
end

local function rb_diag_msg(line)
  if not rb_diag_enabled() then return end
  local max_rows = rb_diag_max_rows()
  if DOCX_RUN_BOUNDARY_DIAG_STATE.rows >= max_rows then return end
  DOCX_RUN_BOUNDARY_DIAG_STATE.rows = DOCX_RUN_BOUNDARY_DIAG_STATE.rows + 1
  if reaper and reaper.ShowConsoleMsg then
    reaper.ShowConsoleMsg("[PSV DOCX RUN BOUNDARY DIAG] " .. tostring(line or "") .. "\n")
  end
end

local function rb_diag_match_text(text)
  if not rb_diag_enabled() then return nil end
  local s = tostring(text or "")
  local match_texts = PSV_DOCX_RUN_BOUNDARY_DIAG_MATCH_TEXTS
  if type(match_texts) ~= "table" then
    match_texts = { "форматирования", "bold", "italic", "underline" }
  end
  for _, needle in ipairs(match_texts) do
    needle = tostring(needle or "")
    if needle ~= "" and s:find(needle, 1, true) then
      return needle
    end
  end
  return nil
end

local function rb_diag_run_is_target(run)
  return rb_diag_match_text(run and run.text or "") ~= nil
end

local function rb_diag_text_starts_ws(text)
  return tostring(text or ""):match("^%s") ~= nil
end

local function rb_diag_text_ends_ws(text)
  return tostring(text or ""):match("%s$") ~= nil
end

local function rb_diag_style_flags_from_run(run)
  local style = run and run.style or {}
  return " bold=" .. rb_diag_bool(style.bold == true) ..
         " italic=" .. rb_diag_bool(style.italic == true) ..
         " underline=" .. rb_diag_bool(style.underline == true) ..
         " strike=" .. rb_diag_bool(style.strike == true) ..
         " color=" .. rb_diag_bool(style.color ~= nil) ..
         " bg=" .. rb_diag_bool(style.shading ~= nil or style.highlight ~= nil) ..
         " href=" .. rb_diag_bool(run and run.href ~= nil)
end

local function rb_diag_token_flags(tok)
  tok = tok or {}
  return " no_space_before=" .. rb_diag_bool(tok.no_space_before == true) ..
         " bold=" .. rb_diag_bool(tok.bold == true) ..
         " italic=" .. rb_diag_bool(tok.italic == true) ..
         " underline=" .. rb_diag_bool(tok.underline == true) ..
         " strike=" .. rb_diag_bool(tok.strike == true) ..
         " fg=" .. rb_diag_bool(tok.fg ~= nil) ..
         " bg=" .. rb_diag_bool(tok.bg ~= nil) ..
         " href=" .. rb_diag_bool(tok.href ~= nil) ..
         " comment_ids=" .. rb_diag_bool(type(tok.comment_ids) == "table" and #tok.comment_ids > 0)
end

local function rb_diag_token_snapshot(tokens, start_index, count)
  local parts = {}
  tokens = tokens or {}
  start_index = math.max(1, tonumber(start_index) or 1)
  count = math.max(1, tonumber(count) or 6)
  for i = start_index, math.min(#tokens, start_index + count - 1) do
    local tok = tokens[i] or {}
    parts[#parts + 1] = "#" .. tostring(i) .. ":\"" .. rb_diag_preview(tok.newline and "\\n" or (tok.text or ""), 40) .. "\"" .. rb_diag_token_flags(tok)
  end
  return table.concat(parts, " | ")
end

local function rb_diag_raw_run(path, run)
  local text = tostring(run and run.text or "")
  rb_diag_msg("RAW_RUN file=" .. rb_diag_basename(path) ..
    " p=" .. tostring(run and run.paragraph_index or nil) ..
    " run=" .. tostring(run and run.run_index or nil) ..
    " text=\"" .. rb_diag_preview(text, 160) .. "\"" ..
    " byte_len=" .. tostring(#text) ..
    rb_diag_style_flags_from_run(run) ..
    " starts_ws=" .. rb_diag_bool(rb_diag_text_starts_ws(text)) ..
    " ends_ws=" .. rb_diag_bool(rb_diag_text_ends_ws(text)))
end

local function rb_diag_split(path, ctx, token_index, original, prefix_text, matched, remainder)
  if not (ctx and ctx.target) then return end
  rb_diag_msg("SPLIT file=" .. rb_diag_basename(path) ..
    " p=" .. tostring(ctx.paragraph_index) ..
    " run=" .. tostring(ctx.run_index) ..
    " event=" .. tostring(ctx.event_index) ..
    " token=" .. tostring(token_index) ..
    " original=\"" .. rb_diag_preview(original and original.text or "", 160) .. "\"" ..
    " prefix=\"" .. rb_diag_preview(prefix_text or "", 120) .. "\"" ..
    " matched=\"" .. rb_diag_preview(matched and matched.text or "", 120) .. "\"" ..
    " matched_no_space=" .. rb_diag_bool(matched and matched.no_space_before == true) ..
    " remainder=\"" .. rb_diag_preview(remainder and remainder.text or "", 120) .. "\"" ..
    " remainder_no_space=" .. rb_diag_bool(remainder and remainder.no_space_before == true) ..
    " matched_comment_ids=" .. rb_diag_bool(matched and type(matched.comment_ids) == "table" and #matched.comment_ids > 0) ..
    " remainder_comment_ids=" .. rb_diag_bool(remainder and type(remainder.comment_ids) == "table" and #remainder.comment_ids > 0))
end

local function rb_diag_final_tokens(path, paragraph_index, block)
  if not rb_diag_enabled() then return end
  local tokens = block and block.tokens or {}
  local should_print = false
  for _, tok in ipairs(tokens) do
    if tok and tok.text and rb_diag_match_text(tok.text) then
      should_print = true
      break
    end
  end
  if not should_print then return end
  for i, tok in ipairs(tokens) do
    rb_diag_msg("FINAL_TOKEN file=" .. rb_diag_basename(path) ..
      " p=" .. tostring(paragraph_index) ..
      " i=" .. tostring(i) ..
      " text=\"" .. rb_diag_preview(tok and tok.newline and "\\n" or (tok and tok.text or ""), 120) .. "\"" ..
      rb_diag_token_flags(tok))
  end
end

local function read_file_binary(path)
  local f, err = io.open(path, "rb")
  if not f then return nil, err end
  local data = f:read("*all")
  f:close()
  return data
end

local function u16le(s, p)
  local b1, b2 = s:byte(p, p + 1)
  if not b1 or not b2 then return nil end
  return b1 + b2 * 256
end

local function u32le(s, p)
  local b1, b2, b3, b4 = s:byte(p, p + 3)
  if not b1 or not b2 or not b3 or not b4 then return nil end
  return b1 + b2 * 256 + b3 * 65536 + b4 * 16777216
end

local function find_eocd(data)
  -- End Of Central Directory can be followed by up to 65535 bytes of comment.
  local sig = "PK\005\006"
  local size = #data
  local start_pos = math.max(1, size - 65535 - 22 + 1)
  for p = size - 3, start_pos, -1 do
    if data:sub(p, p + 3) == sig then
      return p
    end
  end
  return nil
end

-- ══════════════════════════════════════════════════════════════
--  Minimal ZIP reader
-- ══════════════════════════════════════════════════════════════

local function parse_zip_central_directory(data)
  local eocd = find_eocd(data)
  if not eocd then
    return nil, "EOCD signature not found"
  end

  local total_entries = u16le(data, eocd + 10)
  local cd_size = u32le(data, eocd + 12)
  local cd_offset = u32le(data, eocd + 16)
  if not total_entries or not cd_size or not cd_offset then
    return nil, "EOCD is truncated"
  end

  local cd_pos = cd_offset + 1
  local entries = {}
  local by_name = {}

  for _ = 1, total_entries do
    if data:sub(cd_pos, cd_pos + 3) ~= "PK\001\002" then
      return nil, "Central directory entry signature mismatch"
    end

    local flags = u16le(data, cd_pos + 8)
    local method = u16le(data, cd_pos + 10)
    local compressed_size = u32le(data, cd_pos + 20)
    local uncompressed_size = u32le(data, cd_pos + 24)
    local name_len = u16le(data, cd_pos + 28)
    local extra_len = u16le(data, cd_pos + 30)
    local comment_len = u16le(data, cd_pos + 32)
    local local_header_offset = u32le(data, cd_pos + 42)

    if not flags or not method or not compressed_size or not uncompressed_size or
       not name_len or not extra_len or not comment_len or not local_header_offset then
      return nil, "Central directory entry is truncated"
    end

    local name_start = cd_pos + 46
    local name = data:sub(name_start, name_start + name_len - 1)

    local entry = {
      name = name,
      flags = flags,
      method = method,
      compressed_size = compressed_size,
      uncompressed_size = uncompressed_size,
      local_header_offset = local_header_offset,
    }

    entries[#entries + 1] = entry
    by_name[name] = entry

    cd_pos = name_start + name_len + extra_len + comment_len
  end

  return {
    eocd_offset = eocd - 1,
    central_directory_offset = cd_offset,
    central_directory_size = cd_size,
    total_entries = total_entries,
    entries = entries,
    by_name = by_name,
  }
end

local function get_local_file_data_slice(data, entry)
  if entry.compressed_size == 0xFFFFFFFF or entry.uncompressed_size == 0xFFFFFFFF then
    return nil, "Zip64 entry sizes are not supported in this spike"
  end
  if (entry.flags & 1) ~= 0 then
    return nil, "Encrypted ZIP entries are not supported"
  end

  local p = entry.local_header_offset + 1
  if data:sub(p, p + 3) ~= "PK\003\004" then
    return nil, "Local file header signature mismatch"
  end

  local name_len = u16le(data, p + 26)
  local extra_len = u16le(data, p + 28)
  if not name_len or not extra_len then
    return nil, "Local file header is truncated"
  end

  local data_start = p + 30 + name_len + extra_len
  local data_end = data_start + entry.compressed_size - 1
  if data_end > #data then
    return nil, "Compressed data range exceeds file size"
  end

  return data:sub(data_start, data_end)
end

-- ══════════════════════════════════════════════════════════════
--  Raw DEFLATE inflater, small feasibility implementation
-- ══════════════════════════════════════════════════════════════

local LEN_BASE = {
  3, 4, 5, 6, 7, 8, 9, 10,
  11, 13, 15, 17, 19, 23, 27, 31,
  35, 43, 51, 59, 67, 83, 99, 115,
  131, 163, 195, 227, 258
}

local LEN_EXTRA = {
  0, 0, 0, 0, 0, 0, 0, 0,
  1, 1, 1, 1, 2, 2, 2, 2,
  3, 3, 3, 3, 4, 4, 4, 4,
  5, 5, 5, 5, 0
}

local DIST_BASE = {
  1, 2, 3, 4, 5, 7, 9, 13,
  17, 25, 33, 49, 65, 97, 129, 193,
  257, 385, 513, 769, 1025, 1537, 2049, 3073,
  4097, 6145, 8193, 12289, 16385, 24577
}

local DIST_EXTRA = {
  0, 0, 0, 0, 1, 1, 2, 2,
  3, 3, 4, 4, 5, 5, 6, 6,
  7, 7, 8, 8, 9, 9, 10, 10,
  11, 11, 12, 12, 13, 13
}

local function bit_reader_new(data)
  return {
    data = data,
    pos = 1,
    bitbuf = 0,
    bitcnt = 0,
  }
end

local function bit_reader_read_bits(br, n)
  if n == 0 then return 0 end
  while br.bitcnt < n do
    local b = br.data:byte(br.pos)
    if not b then error("Unexpected end of compressed data") end
    br.bitbuf = br.bitbuf | (b << br.bitcnt)
    br.bitcnt = br.bitcnt + 8
    br.pos = br.pos + 1
  end

  local mask = (1 << n) - 1
  local v = br.bitbuf & mask
  br.bitbuf = br.bitbuf >> n
  br.bitcnt = br.bitcnt - n
  return v
end

local function bit_reader_align_byte(br)
  br.bitbuf = 0
  br.bitcnt = 0
end

local function reverse_bits(code, len)
  local out = 0
  for _ = 1, len do
    out = (out << 1) | (code & 1)
    code = code >> 1
  end
  return out
end

local function build_huffman(lengths)
  local max_bits = 0
  for _, l in ipairs(lengths) do
    if l and l > max_bits then max_bits = l end
  end

  local tables = {}
  for i = 1, max_bits do tables[i] = {} end

  if max_bits == 0 then
    return { tables = tables, max_bits = 0, empty = true }
  end

  local bl_count = {}
  for i = 0, max_bits do bl_count[i] = 0 end
  for _, l in ipairs(lengths) do
    if l and l > 0 then bl_count[l] = bl_count[l] + 1 end
  end

  local next_code = {}
  local code = 0
  bl_count[0] = 0
  for bits = 1, max_bits do
    code = (code + (bl_count[bits - 1] or 0)) << 1
    next_code[bits] = code
  end

  for i, len in ipairs(lengths) do
    if len and len > 0 then
      local symbol = i - 1
      local c = next_code[len]
      next_code[len] = c + 1
      local rev = reverse_bits(c, len)
      tables[len][rev] = symbol
    end
  end

  return { tables = tables, max_bits = max_bits, empty = false }
end

local function decode_symbol(br, huff)
  if not huff or huff.empty then
    error("Attempted to decode using an empty Huffman tree")
  end

  local code = 0
  for len = 1, huff.max_bits do
    code = code | (bit_reader_read_bits(br, 1) << (len - 1))
    local table_for_len = huff.tables[len]
    local sym = table_for_len and table_for_len[code]
    if sym ~= nil then return sym end
  end

  error("Invalid Huffman code")
end

local fixed_lit_huff = nil
local fixed_dist_huff = nil

local function get_fixed_huffmans()
  if fixed_lit_huff and fixed_dist_huff then
    return fixed_lit_huff, fixed_dist_huff
  end

  local lit_lengths = {}
  for sym = 0, 287 do
    if sym <= 143 then
      lit_lengths[sym + 1] = 8
    elseif sym <= 255 then
      lit_lengths[sym + 1] = 9
    elseif sym <= 279 then
      lit_lengths[sym + 1] = 7
    else
      lit_lengths[sym + 1] = 8
    end
  end

  local dist_lengths = {}
  for sym = 0, 31 do
    dist_lengths[sym + 1] = 5
  end

  fixed_lit_huff = build_huffman(lit_lengths)
  fixed_dist_huff = build_huffman(dist_lengths)
  return fixed_lit_huff, fixed_dist_huff
end

local function read_dynamic_huffmans(br)
  local hlit = bit_reader_read_bits(br, 5) + 257
  local hdist = bit_reader_read_bits(br, 5) + 1
  local hclen = bit_reader_read_bits(br, 4) + 4
  local order = {16,17,18,0,8,7,9,6,10,5,11,4,12,3,13,2,14,1,15}

  local code_len_lengths = {}
  for i = 1, 19 do code_len_lengths[i] = 0 end
  for i = 1, hclen do
    local symbol = order[i]
    code_len_lengths[symbol + 1] = bit_reader_read_bits(br, 3)
  end

  local code_len_huff = build_huffman(code_len_lengths)
  local all_lengths = {}
  local total = hlit + hdist

  while #all_lengths < total do
    local sym = decode_symbol(br, code_len_huff)
    if sym <= 15 then
      all_lengths[#all_lengths + 1] = sym
    elseif sym == 16 then
      if #all_lengths == 0 then error("Invalid repeat code 16 at start of dynamic lengths") end
      local repeat_count = bit_reader_read_bits(br, 2) + 3
      local previous = all_lengths[#all_lengths]
      for _ = 1, repeat_count do
        all_lengths[#all_lengths + 1] = previous
      end
    elseif sym == 17 then
      local repeat_count = bit_reader_read_bits(br, 3) + 3
      for _ = 1, repeat_count do
        all_lengths[#all_lengths + 1] = 0
      end
    elseif sym == 18 then
      local repeat_count = bit_reader_read_bits(br, 7) + 11
      for _ = 1, repeat_count do
        all_lengths[#all_lengths + 1] = 0
      end
    else
      error("Invalid dynamic code-length symbol")
    end
  end

  local lit_lengths = {}
  local dist_lengths = {}
  for i = 1, hlit do
    lit_lengths[i] = all_lengths[i] or 0
  end
  for i = 1, hdist do
    dist_lengths[i] = all_lengths[hlit + i] or 0
  end

  return build_huffman(lit_lengths), build_huffman(dist_lengths)
end

local function inflate_raw_deflate(compressed)
  local br = bit_reader_new(compressed)
  local out = {}
  local out_len = 0
  local final_block = false

  local function append_byte(b)
    out_len = out_len + 1
    out[out_len] = string.char(b)
  end

  local function append_string_bytes(s)
    for i = 1, #s do
      out_len = out_len + 1
      out[out_len] = s:sub(i, i)
    end
  end

  while not final_block do
    final_block = bit_reader_read_bits(br, 1) == 1
    local block_type = bit_reader_read_bits(br, 2)

    if block_type == 0 then
      bit_reader_align_byte(br)
      local p = br.pos
      local len = u16le(br.data, p)
      local nlen = u16le(br.data, p + 2)
      if not len or not nlen then error("Stored DEFLATE block header is truncated") end
      if ((len + nlen) & 0xFFFF) ~= 0xFFFF then
        error("Stored DEFLATE block LEN/NLEN check failed")
      end
      br.pos = p + 4
      local block = br.data:sub(br.pos, br.pos + len - 1)
      if #block ~= len then error("Stored DEFLATE block data is truncated") end
      append_string_bytes(block)
      br.pos = br.pos + len

    elseif block_type == 1 or block_type == 2 then
      local lit_huff, dist_huff
      if block_type == 1 then
        lit_huff, dist_huff = get_fixed_huffmans()
      else
        lit_huff, dist_huff = read_dynamic_huffmans(br)
      end

      while true do
        local sym = decode_symbol(br, lit_huff)
        if sym < 256 then
          append_byte(sym)
        elseif sym == 256 then
          break
        elseif sym >= 257 and sym <= 285 then
          local len_index = sym - 257 + 1
          local length = LEN_BASE[len_index]
          local extra_bits = LEN_EXTRA[len_index]
          if not length or not extra_bits then error("Invalid length code") end
          if extra_bits > 0 then
            length = length + bit_reader_read_bits(br, extra_bits)
          end

          local dist_sym = decode_symbol(br, dist_huff)
          local distance = DIST_BASE[dist_sym + 1]
          local dist_extra = DIST_EXTRA[dist_sym + 1]
          if not distance or not dist_extra then error("Invalid distance code") end
          if dist_extra > 0 then
            distance = distance + bit_reader_read_bits(br, dist_extra)
          end
          if distance > out_len then
            error("Invalid DEFLATE distance beyond output buffer")
          end

          for _ = 1, length do
            local c = out[out_len - distance + 1]
            if not c then error("Invalid DEFLATE back-reference") end
            out_len = out_len + 1
            out[out_len] = c
          end
        else
          error("Invalid literal/length code")
        end
      end

    else
      error("Reserved DEFLATE block type encountered")
    end
  end

  return table.concat(out)
end

local function extract_entry(data, entry)
  local compressed, err = get_local_file_data_slice(data, entry)
  if not compressed then return nil, err end

  if entry.method == 0 then
    return compressed, nil, "stored"
  elseif entry.method == 8 then
    local ok, inflated_or_err = pcall(inflate_raw_deflate, compressed)
    if ok then
      return inflated_or_err, nil, "deflated"
    end
    return nil, inflated_or_err, "deflated"
  end

  return nil, "Unsupported ZIP compression method: " .. tostring(entry.method), tostring(entry.method)
end

-- ══════════════════════════════════════════════════════════════
--  Minimal DOCX paragraph structure inspection
-- ══════════════════════════════════════════════════════════════

local XML_ENTITIES = {
  amp = "&",
  lt = "<",
  gt = ">",
  quot = '"',
  apos = "'",
}

local function utf8_from_codepoint(cp)
  if not cp then return "" end
  if cp < 0x80 then
    return string.char(cp)
  elseif cp < 0x800 then
    return string.char(0xC0 | (cp >> 6), 0x80 | (cp & 0x3F))
  elseif cp < 0x10000 then
    return string.char(0xE0 | (cp >> 12), 0x80 | ((cp >> 6) & 0x3F), 0x80 | (cp & 0x3F))
  elseif cp < 0x110000 then
    return string.char(0xF0 | (cp >> 18), 0x80 | ((cp >> 12) & 0x3F), 0x80 | ((cp >> 6) & 0x3F), 0x80 | (cp & 0x3F))
  end
  return ""
end

local function decode_xml_entities(s)
  s = s:gsub("&#x(%x+);", function(hex)
    return utf8_from_codepoint(tonumber(hex, 16))
  end)
  s = s:gsub("&#(%d+);", function(dec)
    return utf8_from_codepoint(tonumber(dec, 10))
  end)
  s = s:gsub("&([%a_][%w_%-%.]*);", function(name)
    return XML_ENTITIES[name] or ("&" .. name .. ";")
  end)
  return s
end

local function utf8_next_len(first_byte)
  if not first_byte then return nil end
  if first_byte < 0x80 then return 1 end
  if first_byte >= 0xC2 and first_byte <= 0xDF then return 2 end
  if first_byte >= 0xE0 and first_byte <= 0xEF then return 3 end
  if first_byte >= 0xF0 and first_byte <= 0xF4 then return 4 end
  return nil
end

local function utf8_is_valid(s)
  s = s or ""
  local i = 1
  local n = #s

  while i <= n do
    local b1 = s:byte(i)
    local len = utf8_next_len(b1)
    if not len or i + len - 1 > n then return false end

    if len == 2 then
      local b2 = s:byte(i + 1)
      if not b2 or b2 < 0x80 or b2 > 0xBF then return false end
    elseif len == 3 then
      local b2, b3 = s:byte(i + 1), s:byte(i + 2)
      if not b2 or not b3 then return false end
      if b2 < 0x80 or b2 > 0xBF or b3 < 0x80 or b3 > 0xBF then return false end
      if b1 == 0xE0 and b2 < 0xA0 then return false end
      if b1 == 0xED and b2 > 0x9F then return false end
    elseif len == 4 then
      local b2, b3, b4 = s:byte(i + 1), s:byte(i + 2), s:byte(i + 3)
      if not b2 or not b3 or not b4 then return false end
      if b2 < 0x80 or b2 > 0xBF or b3 < 0x80 or b3 > 0xBF or b4 < 0x80 or b4 > 0xBF then return false end
      if b1 == 0xF0 and b2 < 0x90 then return false end
      if b1 == 0xF4 and b2 > 0x8F then return false end
    end

    i = i + len
  end

  return true
end

local function utf8_char_count_until(s, max_chars)
  local i = 1
  local n = #s
  local chars = 0

  while i <= n and chars < max_chars do
    local len = utf8_next_len(s:byte(i))
    if not len or i + len - 1 > n then break end

    for j = 1, len - 1 do
      local b = s:byte(i + j)
      if not b or b < 0x80 or b > 0xBF then
        return i - 1, chars, false
      end
    end

    i = i + len
    chars = chars + 1
  end

  return i - 1, chars, i <= n
end

local function utf8_truncate(s, max_chars)
  s = s or ""
  max_chars = max_chars or 220

  local byte_end, _, had_more = utf8_char_count_until(s, max_chars)
  if byte_end < #s then
    return s:sub(1, byte_end), true
  end

  return s, had_more
end

local function utf8_codepoint_to_string(cp)
  return utf8_from_codepoint(cp)
end

local function utf8_to_codepoints(s)
  local cps = {}
  local i = 1
  local n = #s

  while i <= n do
    local b1 = s:byte(i)
    local len = utf8_next_len(b1)
    if not len or i + len - 1 > n then return nil end

    local cp = nil
    if len == 1 then
      cp = b1
    elseif len == 2 then
      local b2 = s:byte(i + 1)
      if not b2 or b2 < 0x80 or b2 > 0xBF then return nil end
      cp = ((b1 & 0x1F) << 6) | (b2 & 0x3F)
    elseif len == 3 then
      local b2, b3 = s:byte(i + 1), s:byte(i + 2)
      if not b2 or not b3 or b2 < 0x80 or b2 > 0xBF or b3 < 0x80 or b3 > 0xBF then return nil end
      if b1 == 0xE0 and b2 < 0xA0 then return nil end
      if b1 == 0xED and b2 > 0x9F then return nil end
      cp = ((b1 & 0x0F) << 12) | ((b2 & 0x3F) << 6) | (b3 & 0x3F)
    elseif len == 4 then
      local b2, b3, b4 = s:byte(i + 1), s:byte(i + 2), s:byte(i + 3)
      if not b2 or not b3 or not b4 then return nil end
      if b2 < 0x80 or b2 > 0xBF or b3 < 0x80 or b3 > 0xBF or b4 < 0x80 or b4 > 0xBF then return nil end
      if b1 == 0xF0 and b2 < 0x90 then return nil end
      if b1 == 0xF4 and b2 > 0x8F then return nil end
      cp = ((b1 & 0x07) << 18) | ((b2 & 0x3F) << 12) | ((b3 & 0x3F) << 6) | (b4 & 0x3F)
    end

    cps[#cps + 1] = cp
    i = i + len
  end

  return cps
end

local function has_mojibake_marker(s)
  s = s or ""
  return s:find("Ð", 1, true) ~= nil or s:find("Ñ", 1, true) ~= nil
end

local function repair_latin1_mojibake_if_safe(s)
  if not has_mojibake_marker(s) then return s, false end

  local cps = utf8_to_codepoints(s)
  if not cps then return s, false end

  local bytes = {}
  local changed = false
  for _, cp in ipairs(cps) do
    if cp <= 0xFF then
      bytes[#bytes + 1] = string.char(cp)
      if cp >= 0x80 then changed = true end
    else
      bytes[#bytes + 1] = utf8_codepoint_to_string(cp)
    end
  end

  if not changed then return s, false end

  local repaired = table.concat(bytes)
  if not utf8_is_valid(repaired) then return s, false end
  if has_mojibake_marker(repaired) then return s, false end

  return repaired, true
end

local function normalize_preview_line(s, max_chars)
  max_chars = max_chars or 220
  s = s or ""
  s = s:gsub("\r\n", "\n"):gsub("\r", "\n")
  s = s:gsub("\t", "    ")
  s = s:gsub("\n", "\\n")
  s = s:gsub("%s%s+", " ")
  s = s:gsub("^%s+", ""):gsub("%s+$", "")

  local valid_before = utf8_is_valid(s)
  local repaired = false
  if valid_before then
    s, repaired = repair_latin1_mojibake_if_safe(s)
  end

  local truncated_text, truncated = utf8_truncate(s, max_chars)
  if truncated then
    truncated_text = truncated_text .. "..."
  end

  return truncated_text, {
    utf8_valid = utf8_is_valid(truncated_text:gsub("%.%.%.$", "")),
    truncated = truncated,
    mojibake_marker = has_mojibake_marker(truncated_text),
    mojibake_repaired = repaired,
  }
end

local function find_w_text_open_tag(s, pos)
  pos = pos or 1

  while true do
    local open_start = s:find("<w:t", pos, true)
    if not open_start then return nil end

    local next_char = s:sub(open_start + 4, open_start + 4)
    if next_char == ">" or next_char:match("%s") then
      local open_end = s:find(">", open_start, true)
      if not open_end then return nil end
      return open_start, open_end
    end

    pos = open_start + 4
  end
end

local function extract_text_from_paragraph_xml(paragraph_xml)
  local out = {}
  local pos = 1

  while pos <= #paragraph_xml do
    local best_pos = nil
    local best_kind = nil

    local t_pos = find_w_text_open_tag(paragraph_xml, pos)
    if t_pos and (not best_pos or t_pos < best_pos) then
      best_pos = t_pos
      best_kind = "text"
    end

    local tab_pos = paragraph_xml:find("<w:tab[^>]*/>", pos)
    if tab_pos and (not best_pos or tab_pos < best_pos) then
      best_pos = tab_pos
      best_kind = "tab"
    end

    local br_pos = paragraph_xml:find("<w:br[^>]*/>", pos)
    if br_pos and (not best_pos or br_pos < best_pos) then
      best_pos = br_pos
      best_kind = "break"
    end

    local cr_pos = paragraph_xml:find("<w:cr[^>]*/>", pos)
    if cr_pos and (not best_pos or cr_pos < best_pos) then
      best_pos = cr_pos
      best_kind = "break"
    end

    if not best_pos then break end

    if best_kind == "text" then
      local open_start, open_end = find_w_text_open_tag(paragraph_xml, best_pos)
      local close_start, close_end = paragraph_xml:find("</w:t>", open_end + 1, true)
      if not open_start or not open_end or not close_start or not close_end then
        break
      end

      local raw_text = paragraph_xml:sub(open_end + 1, close_start - 1)
      out[#out + 1] = decode_xml_entities(raw_text)
      pos = close_end + 1

    elseif best_kind == "tab" then
      local _, tag_end = paragraph_xml:find("<w:tab[^>]*/>", best_pos)
      out[#out + 1] = "\t"
      pos = tag_end + 1

    elseif best_kind == "break" then
      local _, br_end = paragraph_xml:find("<w:br[^>]*/>", best_pos)
      local _, cr_end = paragraph_xml:find("<w:cr[^>]*/>", best_pos)
      local tag_end = nil

      if br_end and cr_end then
        tag_end = math.min(br_end, cr_end)
      else
        tag_end = br_end or cr_end
      end

      out[#out + 1] = "\n"
      pos = (tag_end or best_pos) + 1

    else
      break
    end
  end

  return table.concat(out)
end

local function find_docx_open_tag(s, tag_name, pos)
  s = tostring(s or "")
  pos = pos or 1
  local needle = "<" .. tag_name

  while true do
    local open_start = s:find(needle, pos, true)
    if not open_start then return nil end

    local next_char = s:sub(open_start + #needle, open_start + #needle)
    if next_char == ">" or next_char == "/" or next_char:match("%s") then
      local open_end = s:find(">", open_start, true)
      if not open_end then return nil end
      return open_start, open_end
    end

    pos = open_start + #needle
  end
end

local function find_docx_block_body(s, tag_name, pos)
  s = tostring(s or "")
  local open_start, open_end = find_docx_open_tag(s, tag_name, pos or 1)
  if not open_start or not open_end then return nil, nil, nil end

  local open_tag = s:sub(open_start, open_end)
  if open_tag:match("/%s*>") then
    return "", open_tag, open_end + 1
  end

  local close_tag = "</" .. tag_name .. ">"
  local close_start, close_end = s:find(close_tag, open_end + 1, true)
  if not close_start or not close_end then
    return "", open_tag, open_end + 1
  end

  return s:sub(open_end + 1, close_start - 1), open_tag, close_end + 1
end

local function docx_text_visible_key(text)
  local visible = tostring(text or ""):gsub("\r\n", "\n"):gsub("\r", "\n")
  return visible:gsub("[%s%c]", "")
end

local function make_docx_text_paragraph(paragraph_xml)
  local text = extract_text_from_paragraph_xml(paragraph_xml)
  local visible = docx_text_visible_key(text)
  return {
    text = text,
    xml = paragraph_xml,
    is_empty = visible == "",
    byte_len = #text,
  }
end

local function make_docx_unsupported_placeholder_paragraph(kind, placeholder_text)
  return {
    text = placeholder_text,
    xml = "",
    is_empty = false,
    byte_len = #placeholder_text,
    docx_unsupported = true,
    docx_unsupported_kind = kind,
    docx_unsupported_placeholder = placeholder_text,
  }
end

local function docx_unsupported_placeholder_text(kind)
  if kind == "table" then
    return "Sorry, there's a table here.\nPodcast HTML/DOCX Script Viewer can't read it."
  elseif kind == "image" then
    return "Sorry, there's an image here.\nPodcast HTML/DOCX Script Viewer can't display it."
  end
  return "Sorry, there's unsupported DOCX content here.\nPodcast HTML/DOCX Script Viewer can't read it."
end

local function append_docx_unsupported_placeholder(paragraphs, counters, kind)
  kind = kind or "unknown"
  counters = counters or {}
  if kind == "table" then
    counters.table_count = (counters.table_count or 0) + 1
  elseif kind == "image" then
    counters.image_count = (counters.image_count or 0) + 1
  else
    counters.unknown_count = (counters.unknown_count or 0) + 1
  end
  paragraphs[#paragraphs + 1] = make_docx_unsupported_placeholder_paragraph(kind, docx_unsupported_placeholder_text(kind))
end

local function docx_paragraph_contains_visual_object(paragraph_xml)
  paragraph_xml = tostring(paragraph_xml or "")
  return paragraph_xml:find("<w:drawing", 1, true) ~= nil or
         paragraph_xml:find("<w:pict", 1, true) ~= nil or
         paragraph_xml:find("<w:object", 1, true) ~= nil
end

local function append_docx_paragraph_or_placeholder(paragraphs, counters, paragraph_xml)
  local paragraph = make_docx_text_paragraph(paragraph_xml)
  if docx_paragraph_contains_visual_object(paragraph_xml) then
    if paragraph.is_empty then
      append_docx_unsupported_placeholder(paragraphs, counters, "image")
      return
    end
    counters.mixed_inline_image_left_unchanged_count = (counters.mixed_inline_image_left_unchanged_count or 0) + 1
  end
  paragraphs[#paragraphs + 1] = paragraph
end

local function find_docx_body_xml(document_xml)
  local body_start, body_open_end = find_docx_open_tag(document_xml or "", "w:body", 1)
  if not body_start or not body_open_end then return nil end
  local body_close_start = (document_xml or ""):find("</w:body>", body_open_end + 1, true)
  if not body_close_start then return nil end
  return (document_xml or ""):sub(body_open_end + 1, body_close_start - 1)
end

local function find_next_docx_body_child(body_xml, pos)
  body_xml = tostring(body_xml or "")
  pos = pos or 1
  while pos <= #body_xml do
    local open_start, _, tag_local = body_xml:find("<w:([%w_]+)", pos)
    if not open_start or not tag_local then return nil end
    local after = body_xml:sub(open_start + 3 + #tag_local, open_start + 3 + #tag_local)
    if after == "" or after == ">" or after == "/" or after:match("%s") then
      local open_end = body_xml:find(">", open_start, true)
      if not open_end then return nil end
      return open_start, open_end, "w:" .. tag_local
    end
    pos = open_start + 3
  end
  return nil
end

local function docx_block_end_pos(xml, tag_name, open_start, open_end)
  local open_tag = xml:sub(open_start or open_end or 1, open_end or open_start or 1)
  if open_tag:match("/%s*>") then return (open_end or 1) + 1 end
  local close_tag = "</" .. tag_name .. ">"
  local close_start, close_end = xml:find(close_tag, (open_end or 1) + 1, true)
  if close_end then return close_end + 1 end
  return (open_end or 1) + 1
end

local function docx_is_harmless_body_child(tag_name)
  return tag_name == "w:sectPr" or
         tag_name == "w:bookmarkStart" or
         tag_name == "w:bookmarkEnd" or
         tag_name == "w:proofErr" or
         tag_name == "w:permStart" or
         tag_name == "w:permEnd"
end

local function docx_is_meaningful_unsupported_body_child(tag_name)
  return tag_name == "w:altChunk" or
         tag_name == "w:sdt" or
         tag_name == "w:customXml" or
         tag_name == "w:object" or
         tag_name == "w:drawing" or
         tag_name == "w:pict" or
         tag_name == "w:oMath" or
         tag_name == "w:oMathPara"
end

local function extract_docx_paragraphs(document_xml)
  local paragraphs = {}
  local counters = {
    table_count = 0,
    image_count = 0,
    unknown_count = 0,
    mixed_inline_image_left_unchanged_count = 0,
  }

  local body_xml = find_docx_body_xml(document_xml)
  if not body_xml then
    for paragraph_xml in tostring(document_xml or ""):gmatch("<w:p[^>]*>(.-)</w:p>") do
      append_docx_paragraph_or_placeholder(paragraphs, counters, paragraph_xml)
    end
    paragraphs.unsupported_placeholders = counters
    return paragraphs
  end

  local pos = 1
  while pos <= #body_xml do
    local child_start, child_open_end, tag_name = find_next_docx_body_child(body_xml, pos)
    if not child_start or not child_open_end or not tag_name then break end

    if tag_name == "w:p" then
      local body, _, next_pos = find_docx_block_body(body_xml, "w:p", child_start)
      append_docx_paragraph_or_placeholder(paragraphs, counters, body or "")
      pos = next_pos or (child_open_end + 1)

    elseif tag_name == "w:tbl" then
      append_docx_unsupported_placeholder(paragraphs, counters, "table")
      pos = docx_block_end_pos(body_xml, "w:tbl", child_start, child_open_end)

    elseif docx_is_harmless_body_child(tag_name) then
      pos = docx_block_end_pos(body_xml, tag_name, child_start, child_open_end)

    elseif docx_is_meaningful_unsupported_body_child(tag_name) then
      append_docx_unsupported_placeholder(paragraphs, counters, "unknown")
      pos = docx_block_end_pos(body_xml, tag_name, child_start, child_open_end)

    else
      -- Unknown direct body child: skip conservatively to avoid placeholder spam for metadata-like nodes.
      pos = docx_block_end_pos(body_xml, tag_name, child_start, child_open_end)
    end
  end

  paragraphs.unsupported_placeholders = counters
  return paragraphs
end

local function summarize_paragraphs(paragraphs)
  local empty_count = 0
  local longest_len = 0

  for _, paragraph in ipairs(paragraphs or {}) do
    if paragraph.is_empty then empty_count = empty_count + 1 end
    if paragraph.byte_len > longest_len then longest_len = paragraph.byte_len end
  end

  return {
    count = #(paragraphs or {}),
    empty_count = empty_count,
    longest_len = longest_len,
  }
end

-- ══════════════════════════════════════════════════════════════
--  Minimal IR-like diagnostic conversion
-- ══════════════════════════════════════════════════════════════

local function split_lines_preserve_empty(s)
  local lines = {}
  s = s or ""
  s = s:gsub("\r\n", "\n"):gsub("\r", "\n")

  local pos = 1
  while true do
    local nl = s:find("\n", pos, true)
    if nl then
      lines[#lines + 1] = s:sub(pos, nl - 1)
      pos = nl + 1
    else
      lines[#lines + 1] = s:sub(pos)
      break
    end
  end

  return lines
end

local function append_word_tokens_from_line(tokens, line)
  for word in tostring(line or ""):gmatch("%S+") do
    tokens[#tokens + 1] = { text = word }
  end
end

local function convert_paragraphs_to_ir_like_doc(paragraphs)
  local doc = {
    blocks = {},
    comments = {
      by_id = {},
      refs = {},
      order = {},
    },
  }

  for _, paragraph in ipairs(paragraphs or {}) do
    local block = {
      tokens = {},
      is_heading = false,
      tag = "p",
      is_blank_paragraph = paragraph.is_empty and true or false,
    }

    if paragraph.docx_unsupported then
      block.docx_unsupported = true
      block.docx_unsupported_kind = paragraph.docx_unsupported_kind
      block.docx_unsupported_placeholder = paragraph.docx_unsupported_placeholder
    end

    local lines = split_lines_preserve_empty(paragraph.text or "")
    for line_i, line in ipairs(lines) do
      append_word_tokens_from_line(block.tokens, line)
      if line_i < #lines then
        block.tokens[#block.tokens + 1] = { newline = true }
      end
    end

    if paragraph.docx_unsupported then
      for _, token in ipairs(block.tokens or {}) do
        if token.text ~= nil then
          token.docx_unsupported_placeholder = true
          token.docx_unsupported_kind = paragraph.docx_unsupported_kind
        end
      end
    end

    doc.blocks[#doc.blocks + 1] = block
  end

  return doc
end

local function table_is_empty(t)
  return type(t) == "table" and next(t) == nil
end

local function summarize_ir_like_doc(doc)
  local summary = {
    block_count = 0,
    total_token_count = 0,
    text_token_count = 0,
    newline_token_count = 0,
    blank_block_count = 0,
    max_tokens_in_one_block = 0,
    comments_by_id_empty = false,
    comments_refs_empty = false,
    comments_order_empty = false,
  }

  if not doc then return summary end

  summary.block_count = #(doc.blocks or {})
  for _, block in ipairs(doc.blocks or {}) do
    local token_count = #(block.tokens or {})
    if token_count > summary.max_tokens_in_one_block then
      summary.max_tokens_in_one_block = token_count
    end
    if block.is_blank_paragraph then
      summary.blank_block_count = summary.blank_block_count + 1
    end
    for _, token in ipairs(block.tokens or {}) do
      summary.total_token_count = summary.total_token_count + 1
      if token.newline then
        summary.newline_token_count = summary.newline_token_count + 1
      elseif token.text ~= nil then
        summary.text_token_count = summary.text_token_count + 1
      end
    end
  end

  local comments = doc.comments or {}
  summary.comments_by_id_empty = table_is_empty(comments.by_id)
  summary.comments_refs_empty = table_is_empty(comments.refs)
  summary.comments_order_empty = table_is_empty(comments.order)

  return summary
end

local function ir_like_block_preview(block, max_chars)
  if not block then return "", { utf8_valid = true, truncated = false, mojibake_marker = false, mojibake_repaired = false } end

  local parts = {}
  for _, token in ipairs(block.tokens or {}) do
    if token.newline then
      parts[#parts + 1] = "\n"
    elseif token.text ~= nil then
      if #parts > 0 and parts[#parts] ~= "\n" then
        parts[#parts + 1] = " "
      end
      parts[#parts + 1] = tostring(token.text)
    end
  end

  return normalize_preview_line(table.concat(parts), max_chars or 180)
end


-- ══════════════════════════════════════════════════════════════
--  Minimal DOCX comments diagnostic extraction
-- ══════════════════════════════════════════════════════════════

local function find_xml_open_tag(s, tag_name, pos)
  pos = pos or 1
  local needle = "<" .. tag_name

  while true do
    local open_start = s:find(needle, pos, true)
    if not open_start then return nil end

    local next_char = s:sub(open_start + #needle, open_start + #needle)
    if next_char == ">" or next_char == "/" or next_char:match("%s") then
      local open_end = s:find(">", open_start, true)
      if not open_end then return nil end
      return open_start, open_end
    end

    pos = open_start + #needle
  end
end

local function xml_attr(tag, attr_name)
  if not tag or not attr_name then return nil end
  local value = tag:match(attr_name .. '%s*=%s*"([^"]*)"')
  if value == nil then
    value = tag:match(attr_name .. "%s*=%s*'([^']*)'")
  end
  if value ~= nil then
    return decode_xml_entities(value)
  end
  return nil
end

local function extract_comment_body_text(comment_body_xml)
  local parts = {}

  for paragraph_xml in tostring(comment_body_xml or ""):gmatch("<w:p[^>]*>(.-)</w:p>") do
    parts[#parts + 1] = extract_text_from_paragraph_xml(paragraph_xml)
  end

  if #parts == 0 then
    return extract_text_from_paragraph_xml(comment_body_xml or "")
  end

  return table.concat(parts, "\n")
end

local function parse_docx_comments(comments_xml)
  local parsed = {
    by_id = {},
    order = {},
  }

  if not comments_xml or comments_xml == "" then
    return parsed
  end

  local pos = 1
  while pos <= #comments_xml do
    local open_start, open_end = find_xml_open_tag(comments_xml, "w:comment", pos)
    if not open_start or not open_end then break end

    local close_start, close_end = comments_xml:find("</w:comment>", open_end + 1, true)
    if not close_start or not close_end then break end

    local open_tag = comments_xml:sub(open_start, open_end)
    local body_xml = comments_xml:sub(open_end + 1, close_start - 1)
    local id = xml_attr(open_tag, "w:id")

    if id and id ~= "" then
      local comment = {
        id = id,
        text = extract_comment_body_text(body_xml),
      }

      local author = xml_attr(open_tag, "w:author")
      local date = xml_attr(open_tag, "w:date")
      if author and author ~= "" then comment.author = author end
      if date and date ~= "" then comment.date = date end

      if not parsed.by_id[id] then
        parsed.order[#parsed.order + 1] = id
      end
      parsed.by_id[id] = comment
    end

    pos = close_end + 1
  end

  return parsed
end

local function count_ir_like_tokens_in_text(text)
  local tokens = {}
  local lines = split_lines_preserve_empty(text or "")

  for line_i, line in ipairs(lines) do
    append_word_tokens_from_line(tokens, line)
    if line_i < #lines then
      tokens[#tokens + 1] = { newline = true }
    end
  end

  return #tokens
end

local function token_index_after_xml_prefix(paragraph_xml, tag_start)
  if not paragraph_xml or not tag_start or tag_start <= 1 then return 0 end
  local prefix_xml = paragraph_xml:sub(1, tag_start - 1)
  local prefix_text = extract_text_from_paragraph_xml(prefix_xml)
  return count_ir_like_tokens_in_text(prefix_text)
end

local function extract_docx_comment_refs(paragraphs)
  local refs = {}
  local anchor_tags = {
    { tag = "w:commentRangeStart", kind = "range_start" },
    { tag = "w:commentRangeEnd", kind = "range_end" },
    { tag = "w:commentReference", kind = "reference" },
  }

  for paragraph_index, paragraph in ipairs(paragraphs or {}) do
    local paragraph_xml = paragraph.xml or ""
    local pos = 1

    while pos <= #paragraph_xml do
      local best_start = nil
      local best_end = nil
      local best_kind = nil

      for _, candidate in ipairs(anchor_tags) do
        local tag_start, tag_end = find_xml_open_tag(paragraph_xml, candidate.tag, pos)
        if tag_start and (not best_start or tag_start < best_start) then
          best_start = tag_start
          best_end = tag_end
          best_kind = candidate.kind
        end
      end

      if not best_start or not best_end then break end

      local tag_xml = paragraph_xml:sub(best_start, best_end)
      local comment_id = xml_attr(tag_xml, "w:id")
      if comment_id and comment_id ~= "" then
        refs[#refs + 1] = {
          comment_id = comment_id,
          paragraph_index = paragraph_index,
          token_index_after = token_index_after_xml_prefix(paragraph_xml, best_start),
          anchor_kind = best_kind,
        }
      end

      pos = best_end + 1
    end
  end

  return refs
end

local function attach_comments_to_ir_like_doc(doc, parsed_comments, refs)
  if not doc then return end

  parsed_comments = parsed_comments or { by_id = {}, order = {} }
  doc.comments = {
    by_id = {},
    refs = {},
    order = {},
  }

  for _, id in ipairs(parsed_comments.order or {}) do
    local comment = parsed_comments.by_id and parsed_comments.by_id[id]
    if comment then
      doc.comments.order[#doc.comments.order + 1] = id
      doc.comments.by_id[id] = {
        id = comment.id,
        text = comment.text,
        author = comment.author,
        date = comment.date,
      }
    end
  end

  for _, ref in ipairs(refs or {}) do
    doc.comments.refs[#doc.comments.refs + 1] = {
      comment_id = ref.comment_id,
      paragraph_index = ref.paragraph_index,
      token_index_after = ref.token_index_after,
      anchor_kind = ref.anchor_kind,
    }
  end
end

local function summarize_docx_comments(parsed_comments)
  local summary = {
    count = 0,
    non_empty_text_count = 0,
  }

  parsed_comments = parsed_comments or { by_id = {}, order = {} }
  summary.count = #(parsed_comments.order or {})

  for _, id in ipairs(parsed_comments.order or {}) do
    local comment = parsed_comments.by_id and parsed_comments.by_id[id]
    if comment then
      local visible = tostring(comment.text or ""):gsub("\r\n", "\n"):gsub("\r", "\n")
      visible = visible:gsub("[%s%c]", "")
      if visible ~= "" then
        summary.non_empty_text_count = summary.non_empty_text_count + 1
      end
    end
  end

  return summary
end

local function summarize_docx_comment_refs(refs, by_id)
  local summary = {
    total_count = 0,
    range_start_count = 0,
    range_end_count = 0,
    reference_count = 0,
    mapped_to_paragraph_count = 0,
    matching_by_id_count = 0,
    without_matching_comment_count = 0,
  }

  by_id = by_id or {}
  summary.total_count = #(refs or {})

  for _, ref in ipairs(refs or {}) do
    if ref.anchor_kind == "range_start" then
      summary.range_start_count = summary.range_start_count + 1
    elseif ref.anchor_kind == "range_end" then
      summary.range_end_count = summary.range_end_count + 1
    elseif ref.anchor_kind == "reference" then
      summary.reference_count = summary.reference_count + 1
    end

    if ref.paragraph_index ~= nil then
      summary.mapped_to_paragraph_count = summary.mapped_to_paragraph_count + 1
    end

    if ref.comment_id and by_id[ref.comment_id] then
      summary.matching_by_id_count = summary.matching_by_id_count + 1
    else
      summary.without_matching_comment_count = summary.without_matching_comment_count + 1
    end
  end

  return summary
end


-- ══════════════════════════════════════════════════════════════
--  Normalized DOCX comments sidecar
-- ══════════════════════════════════════════════════════════════

local function clone_ref_position(ref)
  if not ref then return nil end
  return {
    paragraph_index = ref.paragraph_index,
    token_index_after = ref.token_index_after,
    anchor_kind = ref.anchor_kind,
  }
end

local function ref_position_sort_value(ref)
  local paragraph_index = tonumber(ref and ref.paragraph_index) or 1000000000
  local token_index_after = tonumber(ref and ref.token_index_after) or 1000000000
  local kind_order = 4
  if ref and ref.anchor_kind == "reference" then
    kind_order = 1
  elseif ref and ref.anchor_kind == "range_start" then
    kind_order = 2
  elseif ref and ref.anchor_kind == "range_end" then
    kind_order = 3
  end
  return paragraph_index, token_index_after, kind_order, tostring(ref and ref.comment_id or "")
end

local function ref_position_less(a, b)
  local ap, at, ak, ai = ref_position_sort_value(a)
  local bp, bt, bk, bi = ref_position_sort_value(b)
  if ap ~= bp then return ap < bp end
  if at ~= bt then return at < bt end
  if ak ~= bk then return ak < bk end
  return ai < bi
end

local function choose_earliest_ref(existing, candidate)
  if not existing then return candidate end
  if not candidate then return existing end
  if ref_position_less(candidate, existing) then return candidate end
  return existing
end

local function normalize_docx_comments(parsed_comments, diagnostic_refs)
  parsed_comments = parsed_comments or { by_id = {}, order = {} }
  diagnostic_refs = diagnostic_refs or {}

  -- Same-anchor grouped comments must follow the canonical comment order from
  -- comments.xml instead of falling back to numeric/string id order. LibreOffice
  -- can emit nested refs in reverse/numeric-confusing order, while
  -- parsed_comments.order preserves the intended visible thread order. Document
  -- position remains the primary sort key; this map is used only as a
  -- same-anchor tie-breaker below.
  local comment_order_index = {}
  for order_index, id in ipairs(parsed_comments.order or {}) do
    if id ~= nil then
      comment_order_index[tostring(id)] = order_index
    end
  end

  local metadata_by_id = {}
  for _, ref in ipairs(diagnostic_refs) do
    local id = ref.comment_id
    if id and id ~= "" then
      local metadata = metadata_by_id[id]
      if not metadata then
        metadata = {}
        metadata_by_id[id] = metadata
      end

      if ref.anchor_kind == "range_start" then
        metadata.range_start = choose_earliest_ref(metadata.range_start, ref)
      elseif ref.anchor_kind == "range_end" then
        metadata.range_end = choose_earliest_ref(metadata.range_end, ref)
      elseif ref.anchor_kind == "reference" then
        metadata.reference = choose_earliest_ref(metadata.reference, ref)
      end
    end
  end

  local normalized = {
    by_id = {},
    refs = {},
    order = {},
  }

  for _, id in ipairs(parsed_comments.order or {}) do
    local comment = parsed_comments.by_id and parsed_comments.by_id[id]
    local metadata = metadata_by_id[id] or {}
    if comment then
      local range = {}
      if metadata.range_start then range.range_start = clone_ref_position(metadata.range_start) end
      if metadata.range_end then range.range_end = clone_ref_position(metadata.range_end) end
      if metadata.reference then range.reference = clone_ref_position(metadata.reference) end

      normalized.by_id[id] = {
        id = comment.id,
        text = comment.text,
        author = comment.author,
        date = comment.date,
        range = range,
      }
    end
  end

  for id, metadata in pairs(metadata_by_id) do
    local anchor = metadata.reference or metadata.range_start or metadata.range_end
    if anchor and parsed_comments.by_id and parsed_comments.by_id[id] then
      normalized.refs[#normalized.refs + 1] = {
        comment_id = id,
        paragraph_index = anchor.paragraph_index,
        token_index_after = anchor.token_index_after,
        anchor_kind = anchor.anchor_kind,
        visible_marker = true,
      }
    end
  end

  table.sort(normalized.refs, function(a, b)
    local ap = tonumber(a and a.paragraph_index) or 1000000000
    local bp = tonumber(b and b.paragraph_index) or 1000000000
    if ap ~= bp then return ap < bp end

    local at = tonumber(a and a.token_index_after) or 1000000000
    local bt = tonumber(b and b.token_index_after) or 1000000000
    if at ~= bt then return at < bt end

    local ai = comment_order_index[tostring(a and a.comment_id or "")]
    local bi = comment_order_index[tostring(b and b.comment_id or "")]
    if ai and bi and ai ~= bi then
      return ai < bi
    end

    return ref_position_less(a, b)
  end)

  for _, ref in ipairs(normalized.refs) do
    normalized.order[#normalized.order + 1] = ref.comment_id
  end

  return normalized
end

local function attach_normalized_comments_to_ir_like_doc(doc, normalized_comments)
  if not doc then return end
  normalized_comments = normalized_comments or { by_id = {}, refs = {}, order = {} }
  doc.comments = {
    by_id = normalized_comments.by_id or {},
    refs = normalized_comments.refs or {},
    order = normalized_comments.order or {},
  }
end

local function summarize_normalized_docx_comments(parsed_comments, normalized_comments)
  parsed_comments = parsed_comments or { by_id = {}, order = {} }
  normalized_comments = normalized_comments or { by_id = {}, refs = {}, order = {} }

  local summary = {
    comments_count = #(parsed_comments.order or {}),
    visible_refs_count = #(normalized_comments.refs or {}),
    comments_with_visible_marker_count = 0,
    comments_without_visible_marker_count = 0,
    duplicate_visible_marker_count = 0,
    normalized_order_count = #(normalized_comments.order or {}),
  }

  local visible_by_id = {}
  for _, ref in ipairs(normalized_comments.refs or {}) do
    local id = ref.comment_id
    if id and id ~= "" then
      visible_by_id[id] = (visible_by_id[id] or 0) + 1
    end
  end

  for _, id in ipairs(parsed_comments.order or {}) do
    local count = visible_by_id[id] or 0
    if count > 0 then
      summary.comments_with_visible_marker_count = summary.comments_with_visible_marker_count + 1
      if count > 1 then
        summary.duplicate_visible_marker_count = summary.duplicate_visible_marker_count + (count - 1)
      end
    else
      summary.comments_without_visible_marker_count = summary.comments_without_visible_marker_count + 1
    end
  end

  return summary
end

local function comment_order_diag_preview(text, max_chars)
  text = tostring(text or "")
  text = text:gsub("\\", "\\\\")
  text = text:gsub("\r", "\\r")
  text = text:gsub("\n", "\\n")
  text = text:gsub("\t", "\\t")
  max_chars = tonumber(max_chars) or 80
  if max_chars > 0 and #text > max_chars then
    return text:sub(1, max_chars) .. "..."
  end
  return text
end

local function comment_order_diag_max_rows(opts)
  local max_rows = tonumber(opts and opts.comment_order_diag_max_rows) or 80
  if max_rows < 0 then max_rows = 0 end
  return math.floor(max_rows + 0.5)
end

local function comment_order_group_refs_for_diag(refs, max_rows)
  local groups = {}
  local order = {}
  local rows = 0
  for _, ref in ipairs(type(refs) == "table" and refs or {}) do
    if rows >= max_rows then break end
    if type(ref) == "table" then
      local key = tostring(ref.paragraph_index or "nil") .. ":" .. tostring(ref.token_index_after or "nil")
      local group = groups[key]
      if not group then
        group = { key = key, paragraph_index = ref.paragraph_index, token_index_after = ref.token_index_after, ids = {} }
        groups[key] = group
        order[#order + 1] = group
        rows = rows + 1
      end
      if ref.comment_id ~= nil and tostring(ref.comment_id) ~= "" then
        group.ids[#group.ids + 1] = ref.comment_id
      end
    end
  end
  return order
end

local function build_comment_order_detail(parsed_comments, diagnostic_refs, normalized_comments, opts)
  local max_rows = comment_order_diag_max_rows(opts)
  local detail = {
    parsed_order = {},
    raw_refs = {},
    normalized_refs = {},
    groups = {},
  }

  if max_rows <= 0 then return detail end

  parsed_comments = parsed_comments or { by_id = {}, order = {} }
  normalized_comments = normalized_comments or { by_id = {}, refs = {}, order = {} }

  for i, id in ipairs(parsed_comments.order or {}) do
    if #detail.parsed_order >= max_rows then break end
    local comment = parsed_comments.by_id and parsed_comments.by_id[id] or nil
    detail.parsed_order[#detail.parsed_order + 1] = {
      index = i,
      comment_id = id,
      author = comment and comment.author or nil,
      date = comment and comment.date or nil,
      text = comment_order_diag_preview(comment and comment.text or "", 80),
    }
  end

  for i, ref in ipairs(type(diagnostic_refs) == "table" and diagnostic_refs or {}) do
    if #detail.raw_refs >= max_rows then break end
    if type(ref) == "table" then
      detail.raw_refs[#detail.raw_refs + 1] = {
        index = i,
        comment_id = ref.comment_id,
        paragraph_index = ref.paragraph_index,
        token_index_after = ref.token_index_after,
        anchor_kind = ref.anchor_kind,
      }
    end
  end

  for i, ref in ipairs(type(normalized_comments.refs) == "table" and normalized_comments.refs or {}) do
    if #detail.normalized_refs >= max_rows then break end
    if type(ref) == "table" then
      detail.normalized_refs[#detail.normalized_refs + 1] = {
        index = i,
        comment_id = ref.comment_id,
        paragraph_index = ref.paragraph_index,
        token_index_after = ref.token_index_after,
        anchor_kind = ref.anchor_kind,
        visible_marker = ref.visible_marker == true,
      }
    end
  end

  detail.groups = comment_order_group_refs_for_diag(normalized_comments.refs, max_rows)
  return detail
end


-- ══════════════════════════════════════════════════════════════
--  DOCX comment range-highlight diagnostics
-- ══════════════════════════════════════════════════════════════

local function ref_position_is_usable(ref)
  return ref ~= nil and ref.paragraph_index ~= nil and ref.token_index_after ~= nil
end

local function range_position_sort_value(range)
  local p = tonumber(range and range.start_paragraph_index) or tonumber(range and range.reference_paragraph_index) or 1000000000
  local t = tonumber(range and range.start_token_index_after) or tonumber(range and range.reference_token_index_after) or 1000000000
  local id = tostring(range and range.comment_id or "")
  return p, t, id
end

local function range_position_less(a, b)
  local ap, at, ai = range_position_sort_value(a)
  local bp, bt, bi = range_position_sort_value(b)
  if ap ~= bp then return ap < bp end
  if at ~= bt then return at < bt end
  return ai < bi
end

local function add_comment_id_to_token(token, comment_id)
  if not token or token.text == nil or token.newline then return false end
  token.comment_ids = token.comment_ids or {}
  for _, existing_id in ipairs(token.comment_ids) do
    if existing_id == comment_id then return false end
  end
  token.comment_ids[#token.comment_ids + 1] = comment_id
  return true
end

local function find_nearest_text_token_index(block, preferred_index)
  local tokens = block and block.tokens or {}
  local count = #tokens
  if count == 0 then return nil end

  preferred_index = tonumber(preferred_index) or 1
  if preferred_index < 1 then preferred_index = 1 end
  if preferred_index > count then preferred_index = count end

  for i = preferred_index, count do
    local token = tokens[i]
    if token and token.text ~= nil and not token.newline then return i end
  end
  for i = preferred_index - 1, 1, -1 do
    local token = tokens[i]
    if token and token.text ~= nil and not token.newline then return i end
  end

  return nil
end

local function compare_doc_position(p1, t1, p2, t2)
  p1 = tonumber(p1) or 0
  t1 = tonumber(t1) or 0
  p2 = tonumber(p2) or 0
  t2 = tonumber(t2) or 0
  if p1 < p2 then return -1 end
  if p1 > p2 then return 1 end
  if t1 < t2 then return -1 end
  if t1 > t2 then return 1 end
  return 0
end

local function mark_comment_range_tokens(doc, comment_id, start_ref, end_ref)
  local blocks = doc and doc.blocks or {}
  if not ref_position_is_usable(start_ref) or not ref_position_is_usable(end_ref) then
    return 0, false, true
  end

  local start_p = tonumber(start_ref.paragraph_index)
  local end_p = tonumber(end_ref.paragraph_index)
  local start_after = tonumber(start_ref.token_index_after) or 0
  local end_after = tonumber(end_ref.token_index_after) or 0

  if not start_p or not end_p or not blocks[start_p] or not blocks[end_p] then
    return 0, false, true
  end

  if compare_doc_position(start_p, start_after, end_p, end_after) > 0 then
    return 0, false, true
  end

  local covered = 0
  for paragraph_index = start_p, end_p do
    local block = blocks[paragraph_index]
    local tokens = block and block.tokens or {}
    for token_index, token in ipairs(tokens) do
      local in_range = false

      if start_p == end_p then
        in_range = token_index > start_after and token_index <= end_after
      elseif paragraph_index == start_p then
        in_range = token_index > start_after
      elseif paragraph_index == end_p then
        in_range = token_index <= end_after
      else
        in_range = true
      end

      if in_range and token and token.text ~= nil and not token.newline then
        if add_comment_id_to_token(token, comment_id) then
          covered = covered + 1
        end
      end
    end
  end

  if covered > 0 then
    return covered, false, false
  end

  -- Diagnostic fallback for zero-width or very short ranges: cover the nearest
  -- sensible text token after the range start so the console can reveal whether
  -- the anchor is usable for a future production heuristic.
  local block = blocks[start_p]
  local nearest_index = find_nearest_text_token_index(block, start_after + 1)
  if nearest_index then
    if add_comment_id_to_token(block.tokens[nearest_index], comment_id) then
      return 1, true, false
    end
    return 0, true, false
  end

  return 0, true, true
end

local function build_docx_comment_range_highlights(doc, parsed_comments, normalized_comments)
  parsed_comments = parsed_comments or { by_id = {}, order = {} }
  normalized_comments = normalized_comments or { by_id = {}, refs = {}, order = {} }

  if doc then
    doc.comments = doc.comments or { by_id = {}, refs = {}, order = {} }
    doc.comments.ranges = {}
  end

  local ranges = {}
  for _, id in ipairs(parsed_comments.order or {}) do
    local normalized_comment = normalized_comments.by_id and normalized_comments.by_id[id]
    local metadata = normalized_comment and normalized_comment.range or {}
    local range_start = metadata and metadata.range_start or nil
    local range_end = metadata and metadata.range_end or nil
    local reference = metadata and metadata.reference or nil
    local has_range_start = ref_position_is_usable(range_start)
    local has_range_end = ref_position_is_usable(range_end)
    local has_reference = ref_position_is_usable(reference)

    local range = {
      comment_id = id,
      start_paragraph_index = has_range_start and range_start.paragraph_index or nil,
      start_token_index_after = has_range_start and range_start.token_index_after or nil,
      end_paragraph_index = has_range_end and range_end.paragraph_index or nil,
      end_token_index_after = has_range_end and range_end.token_index_after or nil,
      has_reference = has_reference,
      reference_paragraph_index = has_reference and reference.paragraph_index or nil,
      reference_token_index_after = has_reference and reference.token_index_after or nil,
      token_coverage_count = 0,
      multi_paragraph = has_range_start and has_range_end and range_start.paragraph_index ~= range_end.paragraph_index or false,
      matched = parsed_comments.by_id and parsed_comments.by_id[id] ~= nil or false,
      usable_range = has_range_start and has_range_end,
      marker_fallback = false,
      zero_width_or_short = false,
      coverage_mismatch = false,
    }

    if range.usable_range then
      local covered, zero_width_or_short, mismatch = mark_comment_range_tokens(doc, id, range_start, range_end)
      range.token_coverage_count = covered
      range.zero_width_or_short = zero_width_or_short and true or false
      range.coverage_mismatch = mismatch or covered == 0
    elseif has_reference then
      range.marker_fallback = true
    else
      range.coverage_mismatch = true
    end

    ranges[#ranges + 1] = range
  end

  table.sort(ranges, range_position_less)

  if doc then
    doc.comments = doc.comments or { by_id = {}, refs = {}, order = {} }
    doc.comments.ranges = ranges
  end

  return ranges
end

local function summarize_docx_comment_ranges(doc, ranges)
  local summary = {
    ranges_count = #(ranges or {}),
    comments_with_usable_ranges_count = 0,
    comments_without_usable_ranges_count = 0,
    comments_using_marker_fallback_count = 0,
    total_covered_text_tokens_count = 0,
    tokens_with_multiple_comment_ids_count = 0,
    multi_paragraph_comment_ranges_count = 0,
    zero_width_short_ranges_count = 0,
    range_coverage_mismatches_count = 0,
  }

  for _, range in ipairs(ranges or {}) do
    if range.usable_range and (range.token_coverage_count or 0) > 0 then
      summary.comments_with_usable_ranges_count = summary.comments_with_usable_ranges_count + 1
    else
      summary.comments_without_usable_ranges_count = summary.comments_without_usable_ranges_count + 1
    end
    if range.marker_fallback then
      summary.comments_using_marker_fallback_count = summary.comments_using_marker_fallback_count + 1
    end
    if range.multi_paragraph then
      summary.multi_paragraph_comment_ranges_count = summary.multi_paragraph_comment_ranges_count + 1
    end
    if range.zero_width_or_short then
      summary.zero_width_short_ranges_count = summary.zero_width_short_ranges_count + 1
    end
    if range.coverage_mismatch then
      summary.range_coverage_mismatches_count = summary.range_coverage_mismatches_count + 1
    end
  end

  for _, block in ipairs(doc and doc.blocks or {}) do
    for _, token in ipairs(block.tokens or {}) do
      local ids = token.comment_ids
      if ids and #ids > 0 then
        summary.total_covered_text_tokens_count = summary.total_covered_text_tokens_count + 1
        if #ids > 1 then
          summary.tokens_with_multiple_comment_ids_count = summary.tokens_with_multiple_comment_ids_count + 1
        end
      end
    end
  end

  return summary
end

local function token_has_comment_id(token, comment_id)
  for _, id in ipairs(token and token.comment_ids or {}) do
    if id == comment_id then return true end
  end
  return false
end

local function collect_range_preview_parts(block, comment_id)
  local before = {}
  local highlighted = {}
  local after = {}
  local seen_highlight = false
  local finished_highlight = false

  for _, token in ipairs(block and block.tokens or {}) do
    if token.text ~= nil and not token.newline then
      if token_has_comment_id(token, comment_id) then
        highlighted[#highlighted + 1] = tostring(token.text)
        seen_highlight = true
      elseif not seen_highlight then
        before[#before + 1] = tostring(token.text)
      elseif not finished_highlight then
        finished_highlight = true
        after[#after + 1] = tostring(token.text)
      else
        after[#after + 1] = tostring(token.text)
      end
    end
  end

  return before, highlighted, after
end

local function tail_words(words, max_count)
  local out = {}
  local start_i = math.max(1, #words - max_count + 1)
  for i = start_i, #words do out[#out + 1] = words[i] end
  return table.concat(out, " ")
end

local function head_words(words, max_count)
  local out = {}
  local end_i = math.min(#words, max_count)
  for i = 1, end_i do out[#out + 1] = words[i] end
  return table.concat(out, " ")
end

local function format_same_paragraph_range_preview(doc, range, max_chars)
  local block = doc and doc.blocks and doc.blocks[range.start_paragraph_index]
  if not block then return "[missing paragraph]" end

  local before, highlighted, after = collect_range_preview_parts(block, range.comment_id)
  if #highlighted == 0 then
    local fallback, _ = ir_like_block_preview(block, max_chars or 220)
    return fallback
  end

  local pieces = {}
  local before_text = tail_words(before, 8)
  local highlighted_text = table.concat(highlighted, " ")
  local after_text = head_words(after, 8)

  if #before > 8 then pieces[#pieces + 1] = "..." end
  if before_text ~= "" then pieces[#pieces + 1] = before_text end
  pieces[#pieces + 1] = "[[" .. highlighted_text .. "]]"
  if after_text ~= "" then pieces[#pieces + 1] = after_text end
  if #after > 8 then pieces[#pieces + 1] = "..." end

  local preview, _ = normalize_preview_line(table.concat(pieces, " "), max_chars or 240)
  return preview
end

local function format_docx_comment_range_preview(doc, range)
  if not range then return "[missing range]" end
  if not range.usable_range then
    return string.format(
      "id=%s marker fallback paragraph=%s token_after=%s",
      tostring(range.comment_id),
      tostring(range.reference_paragraph_index or ""),
      tostring(range.reference_token_index_after or "")
    )
  end

  if not range.multi_paragraph then
    return format_same_paragraph_range_preview(doc, range, 260)
  end

  local start_block = doc and doc.blocks and doc.blocks[range.start_paragraph_index]
  local end_block = doc and doc.blocks and doc.blocks[range.end_paragraph_index]
  local start_preview = start_block and format_same_paragraph_range_preview(doc, range, 130) or "[missing start paragraph]"
  local end_range = {
    comment_id = range.comment_id,
    start_paragraph_index = range.end_paragraph_index,
  }
  local end_preview = end_block and format_same_paragraph_range_preview(doc, end_range, 130) or "[missing end paragraph]"

  return string.format(
    "multi-paragraph start_p=%s start_token_after=%s end_p=%s end_token_after=%s covered_tokens=%s | start: %s | end: %s",
    tostring(range.start_paragraph_index or ""),
    tostring(range.start_token_index_after or ""),
    tostring(range.end_paragraph_index or ""),
    tostring(range.end_token_index_after or ""),
    tostring(range.token_coverage_count or 0),
    start_preview,
    end_preview
  )
end


-- ══════════════════════════════════════════════════════════════
--  DOCX direct run formatting inventory diagnostics
-- ══════════════════════════════════════════════════════════════

local function find_xml_block_body(s, tag_name, pos)
  local open_start, open_end = find_xml_open_tag(s or "", tag_name, pos or 1)
  if not open_start or not open_end then return nil, nil, nil end

  local open_tag = s:sub(open_start, open_end)
  if open_tag:match("/%s*>") then
    return "", open_tag, open_end + 1
  end

  local close_tag = "</" .. tag_name .. ">"
  local close_start, close_end = s:find(close_tag, open_end + 1, true)
  if not close_start or not close_end then
    return "", open_tag, open_end + 1
  end

  return s:sub(open_end + 1, close_start - 1), open_tag, close_end + 1
end

local function xml_attr_any(tag, attr_names)
  for _, attr_name in ipairs(attr_names or {}) do
    local value = xml_attr(tag, attr_name)
    if value ~= nil then return value end
  end
  return nil
end

local function normalize_xml_bool_value(value)
  if value == nil or value == "" then return true end
  value = tostring(value):lower()
  if value == "0" or value == "false" or value == "off" or value == "no" or value == "none" then return false end
  return true
end

local function find_direct_property_tag(rpr_xml, tag_name)
  local tag_start, tag_end = find_xml_open_tag(rpr_xml or "", tag_name, 1)
  if not tag_start or not tag_end then return nil end
  return rpr_xml:sub(tag_start, tag_end)
end

local function parse_direct_bool_property(rpr_xml, tag_name)
  local tag = find_direct_property_tag(rpr_xml, tag_name)
  if not tag then return nil end
  return normalize_xml_bool_value(xml_attr(tag, "w:val"))
end

local function normalize_hex_color_value(raw)
  if not raw or raw == "" then return nil, nil end
  raw = tostring(raw)
  if raw:lower() == "auto" then return "auto/unresolved", "auto" end
  local hex = raw:match("^#?(%x%x%x%x%x%x)$")
  if hex then return "#" .. hex:upper(), hex:upper() end
  return nil, raw
end

local function parse_run_direct_style(rpr_xml)
  local style = {}
  if not rpr_xml or rpr_xml == "" then return style end

  local bold = parse_direct_bool_property(rpr_xml, "w:b")
  if bold ~= nil then style.bold = bold end

  local italic = parse_direct_bool_property(rpr_xml, "w:i")
  if italic ~= nil then style.italic = italic end

  local underline_tag = find_direct_property_tag(rpr_xml, "w:u")
  if underline_tag then
    local underline_val = xml_attr(underline_tag, "w:val")
    if underline_val and underline_val ~= "" then
      style.underline_val = underline_val
      style.underline = underline_val:lower() ~= "none"
    else
      style.underline = false
    end
  end

  local strike = parse_direct_bool_property(rpr_xml, "w:strike")
  local dstrike = parse_direct_bool_property(rpr_xml, "w:dstrike")
  if strike ~= nil or dstrike ~= nil then
    style.strike = (strike == true) or (dstrike == true)
  end

  local color_tag = find_direct_property_tag(rpr_xml, "w:color")
  if color_tag then
    local raw = xml_attr(color_tag, "w:val")
    if raw and raw ~= "" then
      local normalized, unresolved = normalize_hex_color_value(raw)
      style.color_raw = raw
      if normalized then style.color = normalized end
      if unresolved == "auto" then style.color_auto = true end
      if unresolved and unresolved ~= "auto" then style.color_unresolved = unresolved end
    end
  end

  local highlight_tag = find_direct_property_tag(rpr_xml, "w:highlight")
  if highlight_tag then
    local raw = xml_attr(highlight_tag, "w:val")
    if raw and raw ~= "" and raw:lower() ~= "none" then
      style.highlight = raw
    end
  end

  local shading_tag = find_direct_property_tag(rpr_xml, "w:shd")
  if shading_tag then
    local raw = xml_attr(shading_tag, "w:fill")
    if raw and raw ~= "" then
      local normalized, unresolved = normalize_hex_color_value(raw)
      style.shading_raw = raw
      if normalized then style.shading = normalized end
      if unresolved == "auto" then style.shading_auto = true end
      if unresolved and unresolved ~= "auto" then style.shading_unresolved = unresolved end
    end
  end

  return style
end

local function style_has_any_mapped_property(style)
  if not style then return false end
  return style.bold == true or style.italic == true or style.underline == true or style.strike == true or
         (style.color and style.color:match("^#%x%x%x%x%x%x$")) or
         style.highlight ~= nil or
         (style.shading and style.shading:match("^#%x%x%x%x%x%x$"))
end

local function style_property_count(style)
  local count = 0
  if style.bold == true then count = count + 1 end
  if style.italic == true then count = count + 1 end
  if style.underline == true then count = count + 1 end
  if style.strike == true then count = count + 1 end
  if style.color_raw ~= nil then count = count + 1 end
  if style.highlight ~= nil then count = count + 1 end
  if style.shading_raw ~= nil then count = count + 1 end
  return count
end

local function style_signature(style)
  style = style or {}
  return table.concat({
    style.bold == true and "b1" or "b0",
    style.italic == true and "i1" or "i0",
    style.underline == true and "u:" .. tostring(style.underline_val or "on") or "u0",
    style.strike == true and "s1" or "s0",
    "fg:" .. tostring(style.color or style.color_raw or ""),
    "hi:" .. tostring(style.highlight or ""),
    "shd:" .. tostring(style.shading or style.shading_raw or ""),
  }, "|")
end

local function apply_style_to_diagnostic_token(token, run)
  local style = run and run.style or {}
  token.source_run_index = run.run_index
  token.source_paragraph_index = run.paragraph_index

  if style.bold == true then token.bold = true end
  if style.italic == true then token.italic = true end
  if style.underline == true then token.underline = true end
  if style.strike == true then token.strike = true end
  if style.color and style.color:match("^#%x%x%x%x%x%x$") then token.fg = style.color end

  if style.shading and style.shading:match("^#%x%x%x%x%x%x$") then
    token.bg = style.shading
    token.bg_source = "shading"
  elseif style.highlight then
    token.bg = style.highlight
    token.bg_source = "highlight"
  end

  return token
end

local function append_styled_tokens_from_run(styled_tokens, run)
  if not run or not style_has_any_mapped_property(run.style) then return end

  local lines = split_lines_preserve_empty(run.text or "")
  for _, line in ipairs(lines) do
    for word in tostring(line or ""):gmatch("%S+") do
      local token = { text = word }
      apply_style_to_diagnostic_token(token, run)
      styled_tokens[#styled_tokens + 1] = token
    end
  end
end

local function docx_safe_external_href(value)
  if type(value) ~= "string" then return nil end
  if value == "" then return nil end
  if not (value:match("^https://") or value:match("^http://")) then return nil end
  if value:find('"', 1, true) then return nil end
  if value:find("[%c]") then return nil end
  return value
end

local function parse_docx_document_relationships(rels_xml)
  local summary = {
    relationship_count = 0,
    hyperlink_relationship_count = 0,
    supported_external_hyperlink_count = 0,
    unsupported_hyperlink_relationship_count = 0,
  }
  local hyperlinks_by_id = {}

  rels_xml = tostring(rels_xml or "")
  if rels_xml == "" then
    return hyperlinks_by_id, summary
  end

  local pos = 1
  while pos <= #rels_xml do
    local open_start, open_end = find_xml_open_tag(rels_xml, "Relationship", pos)
    if not open_start or not open_end then break end

    local tag = rels_xml:sub(open_start, open_end)
    summary.relationship_count = summary.relationship_count + 1

    local id = xml_attr(tag, "Id")
    local rel_type = xml_attr(tag, "Type")
    local target = xml_attr(tag, "Target")
    local target_mode = xml_attr(tag, "TargetMode")
    local is_hyperlink = type(rel_type) == "string" and rel_type:find("/hyperlink", 1, true) ~= nil

    if is_hyperlink then
      summary.hyperlink_relationship_count = summary.hyperlink_relationship_count + 1
      local href = docx_safe_external_href(target)
      local external_ok = target_mode == nil or target_mode == "" or tostring(target_mode):lower() == "external"
      if id and id ~= "" and href and external_ok then
        hyperlinks_by_id[id] = href
        summary.supported_external_hyperlink_count = summary.supported_external_hyperlink_count + 1
      else
        summary.unsupported_hyperlink_relationship_count = summary.unsupported_hyperlink_relationship_count + 1
      end
    end

    pos = open_end + 1
  end

  return hyperlinks_by_id, summary
end

local function make_docx_run_record(paragraph_index, run_index, run_xml, href)
  local rpr_xml = nil
  local rpr_body, rpr_open_tag = find_xml_block_body(run_xml, "w:rPr", 1)
  local has_rpr = rpr_body ~= nil or rpr_open_tag ~= nil
  if has_rpr then rpr_xml = rpr_body or rpr_open_tag or "" end

  local text = extract_text_from_paragraph_xml(run_xml)
  local visible = text:gsub("\r\n", "\n"):gsub("\r", "\n")
  visible = visible:gsub("[%s%c]", "")

  local style = parse_run_direct_style(rpr_xml)
  return {
    text = text,
    paragraph_index = paragraph_index,
    run_index = run_index,
    has_text = visible ~= "",
    has_rpr = has_rpr and true or false,
    href = href,
    bold = style.bold,
    italic = style.italic,
    underline = style.underline,
    underline_val = style.underline_val,
    strike = style.strike,
    color = style.color,
    color_raw = style.color_raw,
    highlight = style.highlight,
    shading = style.shading,
    shading_raw = style.shading_raw,
    color_auto = style.color_auto,
    shading_auto = style.shading_auto,
    style = style,
  }
end

local function append_docx_run_records_from_xml(out_runs, paragraph_xml, paragraph_index, start_pos, end_pos, href, first_run_index)
  local pos = start_pos or 1
  local run_index = first_run_index or 0
  local limit = end_pos or #paragraph_xml

  while pos <= limit do
    local run_start = find_xml_open_tag(paragraph_xml, "w:r", pos)
    if not run_start or run_start > limit then break end

    local run_xml, _, next_pos = find_xml_block_body(paragraph_xml, "w:r", pos)
    if not run_xml then break end
    if next_pos and next_pos - 1 > limit + 20 then break end

    run_index = run_index + 1
    out_runs[#out_runs + 1] = make_docx_run_record(paragraph_index, run_index, run_xml, href)
    pos = next_pos or (limit + 1)
  end

  return run_index
end

local function extract_docx_runs_with_hyperlinks(paragraph_xml, paragraph_index, hyperlink_relationships, hyperlink_summary)
  local runs = {}
  local pos = 1
  local run_index = 0
  paragraph_xml = tostring(paragraph_xml or "")
  hyperlink_relationships = type(hyperlink_relationships) == "table" and hyperlink_relationships or {}
  hyperlink_summary = type(hyperlink_summary) == "table" and hyperlink_summary or {}

  while pos <= #paragraph_xml do
    local next_h_start, next_h_open_end = find_xml_open_tag(paragraph_xml, "w:hyperlink", pos)
    local next_r_start = find_xml_open_tag(paragraph_xml, "w:r", pos)

    if next_h_start and (not next_r_start or next_h_start <= next_r_start) then
      local open_tag = paragraph_xml:sub(next_h_start, next_h_open_end)
      local close_start, close_end = paragraph_xml:find("</w:hyperlink>", next_h_open_end + 1, true)
      if not close_start or not close_end then
        pos = next_h_open_end + 1
      else
        hyperlink_summary.hyperlink_span_count = (hyperlink_summary.hyperlink_span_count or 0) + 1
        local rel_id = xml_attr(open_tag, "r:id") or xml_attr(open_tag, "id")
        local href = rel_id and hyperlink_relationships[rel_id] or nil
        if href then
          hyperlink_summary.supported_hyperlink_span_count = (hyperlink_summary.supported_hyperlink_span_count or 0) + 1
        else
          hyperlink_summary.unsupported_hyperlink_span_count = (hyperlink_summary.unsupported_hyperlink_span_count or 0) + 1
        end
        local before_count = #runs
        run_index = append_docx_run_records_from_xml(runs, paragraph_xml, paragraph_index, next_h_open_end + 1, close_start - 1, href, run_index)
        if href then
          hyperlink_summary.linked_run_count = (hyperlink_summary.linked_run_count or 0) + math.max(0, #runs - before_count)
        end
        pos = close_end + 1
      end
    elseif next_r_start then
      local run_xml, _, next_pos = find_xml_block_body(paragraph_xml, "w:r", pos)
      if not run_xml then break end
      run_index = run_index + 1
      runs[#runs + 1] = make_docx_run_record(paragraph_index, run_index, run_xml, nil)
      pos = next_pos or (#paragraph_xml + 1)
    else
      break
    end
  end

  return runs
end

local function inspect_docx_inline_run_formatting(paragraphs, hyperlink_relationships, hyperlink_summary, diag_context)
  local inventory = {
    runs = {},
    styled_tokens = {},
    paragraph_style_signatures = {},
  }

  hyperlink_summary = type(hyperlink_summary) == "table" and hyperlink_summary or {}
  hyperlink_summary.hyperlink_span_count = hyperlink_summary.hyperlink_span_count or 0
  hyperlink_summary.supported_hyperlink_span_count = hyperlink_summary.supported_hyperlink_span_count or 0
  hyperlink_summary.unsupported_hyperlink_span_count = hyperlink_summary.unsupported_hyperlink_span_count or 0
  hyperlink_summary.linked_run_count = hyperlink_summary.linked_run_count or 0
  hyperlink_summary.linked_token_count = hyperlink_summary.linked_token_count or 0

  for paragraph_index, paragraph in ipairs(paragraphs or {}) do
    local paragraph_xml = paragraph.xml or ""
    local signature_seen = {}
    local signature_count = 0
    local runs = extract_docx_runs_with_hyperlinks(paragraph_xml, paragraph_index, hyperlink_relationships, hyperlink_summary)
    local paragraph_diag_target = rb_diag_match_text(paragraph.text or "") ~= nil
    if not paragraph_diag_target then
      for _, diag_run in ipairs(runs or {}) do
        if rb_diag_run_is_target(diag_run) then
          paragraph_diag_target = true
          break
        end
      end
    end

    for _, run in ipairs(runs or {}) do
      if paragraph_diag_target and diag_context and diag_context.path then
        rb_diag_raw_run(diag_context.path, run)
      end
      inventory.runs[#inventory.runs + 1] = run
      append_styled_tokens_from_run(inventory.styled_tokens, run)

      if run.has_text then
        local signature = style_signature(run.style)
        if not signature_seen[signature] then
          signature_seen[signature] = true
          signature_count = signature_count + 1
        end
      end
    end

    inventory.paragraph_style_signatures[paragraph_index] = signature_count
  end

  return inventory
end

local function summarize_inline_run_formatting(inventory)
  local summary = {
    total_runs_count = 0,
    text_runs_count = 0,
    empty_non_text_runs_count = 0,
    runs_with_direct_rpr_count = 0,
    runs_with_bold_count = 0,
    runs_with_italic_count = 0,
    runs_with_underline_count = 0,
    runs_with_strike_count = 0,
    runs_with_text_color_count = 0,
    runs_with_auto_color_count = 0,
    runs_with_highlight_count = 0,
    runs_with_shading_fill_count = 0,
    runs_with_concrete_bg_candidate_count = 0,
    runs_with_multiple_style_properties_count = 0,
    paragraphs_with_mixed_formatting_count = 0,
  }

  inventory = inventory or { runs = {}, paragraph_style_signatures = {} }
  summary.total_runs_count = #(inventory.runs or {})

  for _, run in ipairs(inventory.runs or {}) do
    local style = run.style or {}
    if run.has_text then
      summary.text_runs_count = summary.text_runs_count + 1
      if style.bold == true then summary.runs_with_bold_count = summary.runs_with_bold_count + 1 end
      if style.italic == true then summary.runs_with_italic_count = summary.runs_with_italic_count + 1 end
      if style.underline == true then summary.runs_with_underline_count = summary.runs_with_underline_count + 1 end
      if style.strike == true then summary.runs_with_strike_count = summary.runs_with_strike_count + 1 end
      if style.color_raw ~= nil then summary.runs_with_text_color_count = summary.runs_with_text_color_count + 1 end
      if style.color_auto then summary.runs_with_auto_color_count = summary.runs_with_auto_color_count + 1 end
      if style.highlight ~= nil then summary.runs_with_highlight_count = summary.runs_with_highlight_count + 1 end
      if style.shading_raw ~= nil then summary.runs_with_shading_fill_count = summary.runs_with_shading_fill_count + 1 end
      if (style.shading and style.shading:match("^#%x%x%x%x%x%x$")) or style.highlight ~= nil then
        summary.runs_with_concrete_bg_candidate_count = summary.runs_with_concrete_bg_candidate_count + 1
      end
      if style_property_count(style) > 1 then
        summary.runs_with_multiple_style_properties_count = summary.runs_with_multiple_style_properties_count + 1
      end
    else
      summary.empty_non_text_runs_count = summary.empty_non_text_runs_count + 1
    end

    if run.has_rpr then
      summary.runs_with_direct_rpr_count = summary.runs_with_direct_rpr_count + 1
    end
  end

  for _, signature_count in pairs(inventory.paragraph_style_signatures or {}) do
    if signature_count and signature_count > 1 then
      summary.paragraphs_with_mixed_formatting_count = summary.paragraphs_with_mixed_formatting_count + 1
    end
  end

  return summary
end

local function summarize_styled_tokens(styled_tokens)
  local summary = {
    styled_token_count = #(styled_tokens or {}),
    tokens_with_bold_count = 0,
    tokens_with_italic_count = 0,
    tokens_with_underline_count = 0,
    tokens_with_strike_count = 0,
    tokens_with_fg_count = 0,
    tokens_with_bg_count = 0,
  }

  for _, token in ipairs(styled_tokens or {}) do
    if token.bold then summary.tokens_with_bold_count = summary.tokens_with_bold_count + 1 end
    if token.italic then summary.tokens_with_italic_count = summary.tokens_with_italic_count + 1 end
    if token.underline then summary.tokens_with_underline_count = summary.tokens_with_underline_count + 1 end
    if token.strike then summary.tokens_with_strike_count = summary.tokens_with_strike_count + 1 end
    if token.fg then summary.tokens_with_fg_count = summary.tokens_with_fg_count + 1 end
    if token.bg then summary.tokens_with_bg_count = summary.tokens_with_bg_count + 1 end
  end

  return summary
end

local function format_run_style_flags(run)
  local flags = {}
  if run.bold == true then flags[#flags + 1] = "bold" end
  if run.italic == true then flags[#flags + 1] = "italic" end
  if run.underline == true then flags[#flags + 1] = "underline:" .. tostring(run.underline_val or "on") end
  if run.strike == true then flags[#flags + 1] = "strike" end
  if #flags == 0 then return "none" end
  return table.concat(flags, ",")
end

local function format_optional_style_value(value)
  if value == nil or value == "" then return "none" end
  return tostring(value)
end

local function format_styled_token_flags(token)
  local flags = {}
  if token.bold then flags[#flags + 1] = "bold" end
  if token.italic then flags[#flags + 1] = "italic" end
  if token.underline then flags[#flags + 1] = "underline" end
  if token.strike then flags[#flags + 1] = "strike" end
  if token.fg then flags[#flags + 1] = "fg=" .. tostring(token.fg) end
  if token.bg then flags[#flags + 1] = "bg=" .. tostring(token.bg) end
  if token.bg_source then flags[#flags + 1] = "bg_source=" .. tostring(token.bg_source) end
  if #flags == 0 then return "none" end
  return table.concat(flags, ",")
end


-- ══════════════════════════════════════════════════════════════
--  DOCX paragraph/layout adapter diagnostics
-- ══════════════════════════════════════════════════════════════

local function diag_basename(path)
  path = tostring(path or "")
  local name = path:match("([^/\\]+)$")
  return name and name ~= "" and name or path
end

local function diag_bool(value)
  return value and "true" or "false"
end

local function diag_escape_text(text, max_chars)
  text = tostring(text or "")
  text = text:gsub("\\", "\\\\")
  text = text:gsub("\r", "\\r")
  text = text:gsub("\n", "\\n")
  text = text:gsub("\t", "\\t")
  max_chars = tonumber(max_chars) or 160
  if max_chars > 0 and #text > max_chars then
    return text:sub(1, max_chars) .. "..."
  end
  return text
end

local function diag_count_open_tags(xml, tag_name)
  local count = 0
  local pos = 1
  xml = tostring(xml or "")
  while pos <= #xml do
    local tag_start, tag_end = find_xml_open_tag(xml, tag_name, pos)
    if not tag_start or not tag_end then break end
    count = count + 1
    pos = tag_end + 1
  end
  return count
end

local function diag_contains_open_tag(xml, tag_name)
  return diag_count_open_tags(xml, tag_name) > 0
end

local function diag_get_paragraph_ppr_xml(paragraph_xml)
  local ppr_body, ppr_open_tag = find_xml_block_body(paragraph_xml or "", "w:pPr", 1)
  if ppr_body == nil and ppr_open_tag == nil then return nil end
  return tostring(ppr_open_tag or "") .. tostring(ppr_body or "")
end

local function diag_first_tag_xml(xml, tag_name)
  local tag_start, tag_end = find_xml_open_tag(xml or "", tag_name, 1)
  if not tag_start or not tag_end then return nil end
  return (xml or ""):sub(tag_start, tag_end)
end

local function diag_attr_or_empty(tag, attr_name)
  local value = xml_attr(tag, attr_name)
  if value == nil then return "" end
  return tostring(value)
end

local function diag_jc_value(ppr_xml)
  local tag = diag_first_tag_xml(ppr_xml, "w:jc")
  local value = xml_attr(tag, "w:val")
  return value ~= nil and tostring(value) or ""
end

local function diag_ind_summary(ppr_xml)
  local tag = diag_first_tag_xml(ppr_xml, "w:ind")
  if not tag then return "none" end
  return "left=" .. diag_attr_or_empty(tag, "w:left") ..
    " right=" .. diag_attr_or_empty(tag, "w:right") ..
    " firstLine=" .. diag_attr_or_empty(tag, "w:firstLine") ..
    " hanging=" .. diag_attr_or_empty(tag, "w:hanging")
end

local function diag_spacing_summary(ppr_xml)
  local tag = diag_first_tag_xml(ppr_xml, "w:spacing")
  if not tag then return "none" end
  return "before=" .. diag_attr_or_empty(tag, "w:before") ..
    " after=" .. diag_attr_or_empty(tag, "w:after") ..
    " line=" .. diag_attr_or_empty(tag, "w:line") ..
    " lineRule=" .. diag_attr_or_empty(tag, "w:lineRule")
end

local function diag_count_leading_ws(text)
  local leading = tostring(text or ""):match("^%s*") or ""
  return #leading
end

local function diag_count_trailing_ws(text)
  local trailing = tostring(text or ""):match("%s*$") or ""
  return #trailing
end

local function diag_excerpt_around_first_tag(xml, tag_name, radius)
  xml = tostring(xml or "")
  radius = tonumber(radius) or 90
  local tag_start, tag_end = find_xml_open_tag(xml, tag_name, 1)
  if not tag_start then return "" end
  local start_pos = math.max(1, tag_start - radius)
  local end_pos = math.min(#xml, (tag_end or tag_start) + radius)
  return diag_escape_text(xml:sub(start_pos, end_pos), radius * 2 + 80)
end

local function diag_matches_text(text, match_texts)
  local lower = tostring(text or ""):lower()
  for _, key in ipairs(match_texts or {}) do
    key = tostring(key or "")
    if key ~= "" and lower:find(key:lower(), 1, true) then
      return key
    end
  end
  return nil
end

local function diag_default_match_texts()
  return { "bold", "italic", "underline", "strikethrough", "highlight", "habr.com" }
end

local function diag_normalize_match_texts(opts)
  if type(opts and opts.paragraph_format_diag_match_texts) == "table" then
    return opts.paragraph_format_diag_match_texts
  end
  return diag_default_match_texts()
end

local function diag_max_rows(opts)
  local max_rows = tonumber(opts and opts.paragraph_format_diag_max_rows) or 80
  if max_rows < 0 then max_rows = 0 end
  return math.floor(max_rows + 0.5)
end

local function diag_append_line(lines, state, line)
  if not state then
    lines[#lines + 1] = line
    return true
  end
  if state.max_lines and #lines >= state.max_lines then
    if not state.truncated then
      lines[#lines + 1] = "[PSV DOCX PARAGRAPH FORMAT DIAG] ADAPTER_TRUNCATED line_limit=" .. tostring(state.max_lines)
      state.truncated = true
    end
    return false
  end
  lines[#lines + 1] = line
  return true
end

local function diag_run_bg_value(style)
  style = style or {}
  if style.shading ~= nil then return tostring(style.shading) end
  if style.shading_raw ~= nil then return tostring(style.shading_raw) end
  if style.highlight ~= nil then return tostring(style.highlight) end
  return "none"
end

local function diag_run_fg_value(style)
  style = style or {}
  if style.color ~= nil then return tostring(style.color) end
  if style.color_raw ~= nil then return tostring(style.color_raw) end
  return "none"
end

local function diag_append_run_lines(lines, state, file_label, paragraph_index, paragraph_xml)
  local pos = 1
  local run_index = 0
  paragraph_xml = tostring(paragraph_xml or "")

  while pos <= #paragraph_xml do
    local run_xml, _, next_pos = find_xml_block_body(paragraph_xml, "w:r", pos)
    if not run_xml then break end
    run_index = run_index + 1

    local rpr_xml = nil
    local rpr_body, rpr_open_tag = find_xml_block_body(run_xml, "w:rPr", 1)
    local has_rpr = rpr_body ~= nil or rpr_open_tag ~= nil
    if has_rpr then rpr_xml = tostring(rpr_open_tag or "") .. tostring(rpr_body or "") end

    local style = parse_run_direct_style(rpr_xml)
    local text = extract_text_from_paragraph_xml(run_xml)
    local tab_count = diag_count_open_tags(run_xml, "w:tab")
    local br_count = diag_count_open_tags(run_xml, "w:br")
    local cr_count = diag_count_open_tags(run_xml, "w:cr")

    if not diag_append_line(lines, state,
      "[PSV DOCX PARAGRAPH FORMAT DIAG] ADAPTER_RUN file=" .. file_label ..
      " paragraph_index=" .. tostring(paragraph_index) ..
      " run_index=" .. tostring(run_index) ..
      " text=\"" .. diag_escape_text(text, 140) .. "\"" ..
      " has_rPr=" .. diag_bool(has_rpr) ..
      " bold=" .. diag_bool(style.bold == true) ..
      " italic=" .. diag_bool(style.italic == true) ..
      " underline=" .. diag_bool(style.underline == true) ..
      " strike=" .. diag_bool(style.strike == true) ..
      " fg=" .. diag_run_fg_value(style) ..
      " bg=" .. diag_run_bg_value(style) ..
      " contains_w_tab=" .. diag_bool(tab_count > 0) ..
      " count_w_tab=" .. tostring(tab_count) ..
      " contains_w_br=" .. diag_bool(br_count > 0) ..
      " count_w_br=" .. tostring(br_count) ..
      " contains_w_cr=" .. diag_bool(cr_count > 0) ..
      " count_w_cr=" .. tostring(cr_count)) then
      return
    end

    pos = next_pos or (#paragraph_xml + 1)
  end
end

local function build_paragraph_format_diag_lines(path, document_xml, paragraphs, opts)
  opts = opts or {}
  if opts.paragraph_format_diag_enabled ~= true then return nil end

  local max_rows = diag_max_rows(opts)
  local match_texts = diag_normalize_match_texts(opts)
  local file_label = diag_basename(path)
  local lines = {}
  local state = {
    max_lines = math.max(20, max_rows * 20 + 20),
    truncated = false,
  }
  local summary = summarize_paragraphs(paragraphs)

  diag_append_line(lines, state,
    "[PSV DOCX PARAGRAPH FORMAT DIAG] ADAPTER_SUMMARY file=" .. file_label ..
    " path=\"" .. diag_escape_text(path, 220) .. "\"" ..
    " adapter=" .. tostring(DOCX_ADAPTER.VERSION or "") ..
    " adapter_build=" .. tostring(DOCX_ADAPTER.BUILD or "") ..
    " bridge=" .. tostring(opts.bridge_version or "") ..
    " paragraph_count=" .. tostring(summary.count or 0) ..
    " empty_paragraph_count=" .. tostring(summary.empty_count or 0) ..
    " longest_paragraph_byte_len=" .. tostring(summary.longest_len or 0) ..
    " contains_w_jc=" .. diag_bool(diag_contains_open_tag(document_xml, "w:jc")) ..
    " contains_w_ind=" .. diag_bool(diag_contains_open_tag(document_xml, "w:ind")) ..
    " contains_w_spacing=" .. diag_bool(diag_contains_open_tag(document_xml, "w:spacing")) ..
    " contains_w_tab=" .. diag_bool(diag_contains_open_tag(document_xml, "w:tab")) ..
    " contains_w_br=" .. diag_bool(diag_contains_open_tag(document_xml, "w:br")) ..
    " contains_w_cr=" .. diag_bool(diag_contains_open_tag(document_xml, "w:cr")) ..
    " contains_w_tbl=" .. diag_bool(diag_contains_open_tag(document_xml, "w:tbl")) ..
    " contains_w_drawing=" .. diag_bool(diag_contains_open_tag(document_xml, "w:drawing")) ..
    " contains_w_pict=" .. diag_bool(diag_contains_open_tag(document_xml, "w:pict")) ..
    " contains_w_object=" .. diag_bool(diag_contains_open_tag(document_xml, "w:object")))

  if max_rows <= 0 then
    return lines
  end

  local matched = {}
  for paragraph_index, paragraph in ipairs(paragraphs or {}) do
    local key = diag_matches_text(paragraph.text or "", match_texts)
    if key and #matched < max_rows then
      matched[#matched + 1] = {
        paragraph_index = paragraph_index,
        paragraph = paragraph,
        key = key,
      }
    end
  end

  for _, row in ipairs(matched) do
    local paragraph_index = row.paragraph_index
    local paragraph = row.paragraph or {}
    local paragraph_xml = paragraph.xml or ""
    local ppr_xml = diag_get_paragraph_ppr_xml(paragraph_xml)
    local tab_count = diag_count_open_tags(paragraph_xml, "w:tab")
    local br_count = diag_count_open_tags(paragraph_xml, "w:br")
    local cr_count = diag_count_open_tags(paragraph_xml, "w:cr")

    if not diag_append_line(lines, state,
      "[PSV DOCX PARAGRAPH FORMAT DIAG] ADAPTER_PARA file=" .. file_label ..
      " paragraph_index=" .. tostring(paragraph_index) ..
      " matched_text=\"" .. diag_escape_text(row.key, 80) .. "\"" ..
      " text=\"" .. diag_escape_text(paragraph.text or "", 260) .. "\"" ..
      " is_empty=" .. diag_bool(paragraph.is_empty == true) ..
      " byte_len=" .. tostring(paragraph.byte_len or #(paragraph.text or "")) ..
      " leading_ws_len=" .. tostring(diag_count_leading_ws(paragraph.text or "")) ..
      " trailing_ws_len=" .. tostring(diag_count_trailing_ws(paragraph.text or "")) ..
      " contains_w_tab=" .. diag_bool(tab_count > 0) ..
      " count_w_tab=" .. tostring(tab_count) ..
      " contains_w_br=" .. diag_bool(br_count > 0) ..
      " count_w_br=" .. tostring(br_count) ..
      " contains_w_cr=" .. diag_bool(cr_count > 0) ..
      " count_w_cr=" .. tostring(cr_count) ..
      " pPr_exists=" .. diag_bool(ppr_xml ~= nil) ..
      " w_jc=" .. tostring(diag_jc_value(ppr_xml)) ..
      " w_ind=\"" .. diag_escape_text(diag_ind_summary(ppr_xml), 180) .. "\"" ..
      " w_spacing=\"" .. diag_escape_text(diag_spacing_summary(ppr_xml), 180) .. "\"" ..
      " pPr_excerpt=\"" .. diag_escape_text(ppr_xml or "", 320) .. "\"" ..
      " first_w_tab_excerpt=\"" .. diag_excerpt_around_first_tag(paragraph_xml, "w:tab", 90) .. "\"") then
      return lines
    end

    for offset = -2, 2 do
      if offset ~= 0 then
        local neighbor_index = paragraph_index + offset
        local neighbor = paragraphs and paragraphs[neighbor_index]
        if neighbor then
          local neighbor_xml = neighbor.xml or ""
          local neighbor_ppr = diag_get_paragraph_ppr_xml(neighbor_xml)
          local neighbor_tab_count = diag_count_open_tags(neighbor_xml, "w:tab")
          if not diag_append_line(lines, state,
            "[PSV DOCX PARAGRAPH FORMAT DIAG] ADAPTER_NEIGHBOR file=" .. file_label ..
            " paragraph_index=" .. tostring(neighbor_index) ..
            " relative_offset=" .. tostring(offset) ..
            " text=\"" .. diag_escape_text(neighbor.text or "", 180) .. "\"" ..
            " is_empty=" .. diag_bool(neighbor.is_empty == true) ..
            " contains_w_tab=" .. diag_bool(neighbor_tab_count > 0) ..
            " w_jc=" .. tostring(diag_jc_value(neighbor_ppr)) ..
            " w_ind=\"" .. diag_escape_text(diag_ind_summary(neighbor_ppr), 140) .. "\"" ..
            " w_spacing=\"" .. diag_escape_text(diag_spacing_summary(neighbor_ppr), 140) .. "\"") then
            return lines
          end
        end
      end
    end

    diag_append_run_lines(lines, state, file_label, paragraph_index, paragraph_xml)
  end

  return lines
end


-- ══════════════════════════════════════════════════════════════
--  Clean adapter document construction
-- ══════════════════════════════════════════════════════════════

local function token_style_has_mapped_property(style)
  return style_has_any_mapped_property(style)
end

local function apply_style_fields_to_doc_token(token, style)
  style = style or {}
  if style.bold == true then token.bold = true end
  if style.italic == true then token.italic = true end
  if style.underline == true then token.underline = true end
  if style.strike == true then token.strike = true end
  if style.color and style.color:match("^#%x%x%x%x%x%x$") then token.fg = style.color end

  if style.shading and style.shading:match("^#%x%x%x%x%x%x$") then
    token.bg = style.shading
    token.bg_source = "shading"
  elseif style.highlight then
    token.bg = style.highlight
    token.bg_source = "highlight"
  end
end

local function token_events_from_text(text, previous_visible_ended_non_ws)
  local events = {}
  local state_ended_non_ws = previous_visible_ended_non_ws == true
  local lines = split_lines_preserve_empty(text or "")

  for line_i, line in ipairs(lines) do
    line = tostring(line or "")
    local pos = 1

    while pos <= #line do
      local s, e = line:find("%S+", pos)
      if not s then
        if pos <= #line then
          state_ended_non_ws = false
        end
        break
      end

      if s > pos then
        -- Real source whitespace exists before this visible fragment.
        state_ended_non_ws = false
      end

      local word = line:sub(s, e)
      events[#events + 1] = {
        text = word,
        no_space_before = state_ended_non_ws == true,
      }

      state_ended_non_ws = true
      pos = e + 1
    end

    if line == "" then
      -- Empty line itself does not create visible adjacency.
    end

    if line_i < #lines then
      events[#events + 1] = { newline = true }
      state_ended_non_ws = false
    end
  end

  return events, state_ended_non_ws
end

local function clone_docx_token_for_split(token)
  local out = {}
  for k, v in pairs(token or {}) do
    if type(v) == "table" then
      local copy = {}
      for ck, cv in pairs(v) do copy[ck] = cv end
      out[k] = copy
    else
      out[k] = v
    end
  end
  return out
end

local function token_text_has_prefix(token_text, prefix_text)
  if type(token_text) ~= "string" or type(prefix_text) ~= "string" then return false end
  if prefix_text == "" then return false end
  if #prefix_text > #token_text then return false end
  return token_text:sub(1, #prefix_text) == prefix_text
end

local function split_doc_token_at_prefix(tokens, token_index, event, diag_context)
  local token = tokens and tokens[token_index] or nil
  if not token or token.newline or token.text == nil then return nil end
  local token_text = tostring(token.text or "")
  local prefix_text = tostring(event and event.text or "")
  if prefix_text == "" or token_text == "" then return nil end
  if token_text == prefix_text then return token_index end
  if not token_text_has_prefix(token_text, prefix_text) then return nil end

  -- Safe for UTF-8 because the split boundary is the byte length of prefix_text,
  -- a real substring that came from the same DOCX-visible text stream.
  local remainder_text = token_text:sub(#prefix_text + 1)
  if remainder_text == "" then return token_index end

  local original_for_diag = token
  local matched = clone_docx_token_for_split(token)
  local remainder = clone_docx_token_for_split(token)
  matched.text = prefix_text
  remainder.text = remainder_text

  -- no_space_before is monotonic here. A source-adjacent matched prefix keeps
  -- the original token flag and is additionally marked when the DOCX event says
  -- it started immediately after previous visible source text. The remainder is
  -- always adjacent to the matched prefix because it continues the same original
  -- clean token without source whitespace.
  if event and event.no_space_before == true and matched.text ~= nil and not matched.newline then
    matched.no_space_before = true
  end
  remainder.no_space_before = true

  tokens[token_index] = matched
  table.insert(tokens, token_index + 1, remainder)
  rb_diag_split(diag_context and diag_context.path or nil, diag_context, token_index, original_for_diag, prefix_text, matched, remainder)
  return token_index
end

local function find_next_matching_token(tokens, start_index, event, diag_context)
  for i = math.max(1, start_index or 1), #(tokens or {}) do
    local token = tokens[i]
    if event.newline then
      if token and token.newline then return i end
    elseif event.text ~= nil then
      if token and token.text ~= nil and not token.newline then
        if token.text == event.text then
          if diag_context then diag_context.match_kind = "exact" end
          return i
        end
        if split_doc_token_at_prefix(tokens, i, event, diag_context) then
          if diag_context then diag_context.match_kind = "prefix_split" end
          return i
        end
      end
    end
  end
  return nil
end

local function apply_direct_run_styles_to_doc(doc, runs, diag_context)
  local cursor_by_paragraph = {}
  local previous_visible_ended_non_ws_by_paragraph = {}
  local diag_target_paragraphs = {}

  if rb_diag_enabled() then
    for _, diag_run in ipairs(runs or {}) do
      if rb_diag_run_is_target(diag_run) then
        diag_target_paragraphs[diag_run.paragraph_index] = true
      end
    end
  end

  for _, run in ipairs(runs or {}) do
    local paragraph_index = run.paragraph_index
    local block = doc and doc.blocks and doc.blocks[paragraph_index]
    if block then
      local cursor = cursor_by_paragraph[paragraph_index] or 1
      local previous_visible_ended_non_ws = previous_visible_ended_non_ws_by_paragraph[paragraph_index] == true
      local run_text = run.text or ""
      local events, next_visible_ended_non_ws = token_events_from_text(run_text, previous_visible_ended_non_ws)

      -- Explicitly preserve DOCX source adjacency across run boundaries. This
      -- mirrors token_events_from_text(), but keeps the direct-formatting layer
      -- authoritative when a visible event starts at the beginning of a run and
      -- the previous source run ended in non-whitespace. Real leading whitespace
      -- in the current run still breaks adjacency.
      if previous_visible_ended_non_ws and tostring(run_text or ""):match("^%S") ~= nil then
        for _, first_event in ipairs(events) do
          if first_event.text ~= nil and not first_event.newline then
            first_event.no_space_before = true
            break
          elseif first_event.newline then
            break
          end
        end
      elseif tostring(run_text or ""):match("^%s") ~= nil then
        for _, first_event in ipairs(events) do
          if first_event.text ~= nil and not first_event.newline then
            first_event.no_space_before = false
            break
          elseif first_event.newline then
            break
          end
        end
      end

      if tostring(run_text or ""):match("%S") ~= nil then
        next_visible_ended_non_ws = tostring(run_text or ""):match("%S$") ~= nil
      end

      local has_style = token_style_has_mapped_property(run.style)
      local href = docx_safe_external_href(run.href)
      local run_diag_target = diag_target_paragraphs[paragraph_index] == true
      if run_diag_target then
        for event_i, event in ipairs(events) do
          rb_diag_msg("EVENT file=" .. rb_diag_basename(diag_context and diag_context.path or nil) ..
            " p=" .. tostring(paragraph_index) ..
            " run=" .. tostring(run.run_index) ..
            " event=" .. tostring(event_i) ..
            " text=\"" .. rb_diag_preview(event.newline and "\\n" or (event.text or ""), 120) .. "\"" ..
            " newline=" .. rb_diag_bool(event.newline == true) ..
            " no_space_before=" .. rb_diag_bool(event.no_space_before == true) ..
            " prev_non_ws=" .. rb_diag_bool(previous_visible_ended_non_ws) ..
            " next_non_ws_after_run=" .. rb_diag_bool(next_visible_ended_non_ws))
        end
      end

      for event_i, event in ipairs(events) do
        local event_diag_context = nil
        if run_diag_target then
          event_diag_context = {
            path = diag_context and diag_context.path or nil,
            target = true,
            paragraph_index = paragraph_index,
            run_index = run.run_index,
            event_index = event_i,
            match_kind = nil,
          }
          rb_diag_msg("MATCH_BEFORE file=" .. rb_diag_basename(event_diag_context.path) ..
            " p=" .. tostring(paragraph_index) ..
            " run=" .. tostring(run.run_index) ..
            " event=" .. tostring(event_i) ..
            " cursor=" .. tostring(cursor) ..
            " event_text=\"" .. rb_diag_preview(event.newline and "\\n" or (event.text or ""), 120) .. "\"" ..
            " event_no_space=" .. rb_diag_bool(event.no_space_before == true) ..
            " tokens=" .. rb_diag_token_snapshot(block.tokens, cursor, 6))
        end
        local token_index = find_next_matching_token(block.tokens, cursor, event, event_diag_context)
        if run_diag_target then
          local matched_token = token_index and block.tokens and block.tokens[token_index] or nil
          rb_diag_msg("MATCH_AFTER file=" .. rb_diag_basename(diag_context and diag_context.path or nil) ..
            " p=" .. tostring(paragraph_index) ..
            " run=" .. tostring(run.run_index) ..
            " event=" .. tostring(event_i) ..
            " matched=" .. tostring(token_index or "nil") ..
            " kind=" .. tostring(event_diag_context and event_diag_context.match_kind or "none") ..
            " matched_text=\"" .. rb_diag_preview(matched_token and (matched_token.newline and "\\n" or matched_token.text) or "", 120) .. "\"" ..
            " matched_no_space=" .. rb_diag_bool(matched_token and matched_token.no_space_before == true))
        end
        if token_index then
          local token = block.tokens[token_index]
          if token and token.text ~= nil and not token.newline then
            -- Apply DOCX source adjacency independently of style/href. This is
            -- required for unstyled second fragments and punctuation after a
            -- styled run. Never write false over an existing no_space_before.
            if event.no_space_before == true then
              token.no_space_before = true
            end
            if has_style then
              apply_style_fields_to_doc_token(token, run.style)
            end
            if href then
              token.href = href
            end
          end
          cursor = token_index + 1
        end
      end

      cursor_by_paragraph[paragraph_index] = cursor
      previous_visible_ended_non_ws_by_paragraph[paragraph_index] = next_visible_ended_non_ws == true
    end
  end

  if rb_diag_enabled() then
    local ordered = {}
    for paragraph_index in pairs(diag_target_paragraphs) do ordered[#ordered + 1] = paragraph_index end
    table.sort(ordered)
    for _, paragraph_index in ipairs(ordered) do
      local block = doc and doc.blocks and doc.blocks[paragraph_index]
      rb_diag_final_tokens(diag_context and diag_context.path or nil, paragraph_index, block)
    end
  end
end


local function attach_adapter_comments_to_doc(doc, normalized_comments)
  if not doc then return end
  normalized_comments = normalized_comments or { by_id = {}, refs = {}, order = {} }
  doc.comments = {
    by_id = {},
    refs = {},
    order = {},
    ranges = {},
  }

  for id, comment in pairs(normalized_comments.by_id or {}) do
    doc.comments.by_id[id] = {
      id = comment.id,
      text = comment.text,
      author = comment.author,
      date = comment.date,
    }
  end

  for _, ref in ipairs(normalized_comments.refs or {}) do
    doc.comments.refs[#doc.comments.refs + 1] = {
      comment_id = ref.comment_id,
      paragraph_index = ref.paragraph_index,
      token_index_after = ref.token_index_after,
      anchor_kind = ref.anchor_kind,
    }
  end

  for _, id in ipairs(normalized_comments.order or {}) do
    doc.comments.order[#doc.comments.order + 1] = id
  end
end

local function build_clean_doc_from_paragraphs(paragraphs)
  local doc = convert_paragraphs_to_ir_like_doc(paragraphs)
  doc.source_format = "docx"
  doc.comments = {
    by_id = {},
    refs = {},
    order = {},
    ranges = {},
  }
  return doc
end

local function count_doc_tokens(doc)
  local summary = {
    block_count = 0,
    blank_block_count = 0,
    total_token_count = 0,
    text_token_count = 0,
    newline_token_count = 0,
    bold_token_count = 0,
    italic_token_count = 0,
    underline_token_count = 0,
    strike_token_count = 0,
    fg_token_count = 0,
    bg_token_count = 0,
    tokens_with_comment_ids_count = 0,
    href_token_count = 0,
  }

  summary.block_count = #(doc and doc.blocks or {})
  for _, block in ipairs(doc and doc.blocks or {}) do
    if block.is_blank_paragraph then summary.blank_block_count = summary.blank_block_count + 1 end
    for _, token in ipairs(block.tokens or {}) do
      summary.total_token_count = summary.total_token_count + 1
      if token.newline then summary.newline_token_count = summary.newline_token_count + 1 end
      if token.text ~= nil then
        summary.text_token_count = summary.text_token_count + 1
        if token.bold then summary.bold_token_count = summary.bold_token_count + 1 end
        if token.italic then summary.italic_token_count = summary.italic_token_count + 1 end
        if token.underline then summary.underline_token_count = summary.underline_token_count + 1 end
        if token.strike then summary.strike_token_count = summary.strike_token_count + 1 end
        if token.fg then summary.fg_token_count = summary.fg_token_count + 1 end
        if token.bg then summary.bg_token_count = summary.bg_token_count + 1 end
        if token.href then summary.href_token_count = summary.href_token_count + 1 end
        if token.comment_ids and #token.comment_ids > 0 then
          summary.tokens_with_comment_ids_count = summary.tokens_with_comment_ids_count + 1
        end
      end
    end
  end

  return summary
end

local function extract_zip_part(zip_data, zip, name)
  local entry = zip and zip.by_name and zip.by_name[name]
  if not entry then
    return nil, nil, nil
  end
  local data, err = extract_entry(zip_data, entry)
  return data, entry, err
end

local function make_key_part_diagnostics(parts)
  local out = {}
  for name, part in pairs(parts or {}) do
    out[name] = {
      found = part.found and true or false,
      extracted = part.data ~= nil,
      size = part.data and #part.data or 0,
      method = part.entry and part.entry.method or nil,
      error = part.error,
    }
  end
  return out
end

local function parse_file_impl(path, opts)
  opts = opts or {}
  local diagnostics = {
    adapter_version = DOCX_ADAPTER.VERSION,
    adapter_build = DOCX_ADAPTER.BUILD,
    bridge_version = opts and opts.bridge_version or nil,
    limitations = {
      "no CRC validation",
      "no Zip64",
      "no encrypted ZIP entries",
      "unsupported compression methods return ok=false for required parts",
      "direct run formatting only; no styles.xml inheritance",
      "no theme color resolution",
      "no real table/image rendering; unsupported block content uses visible placeholders",
      "no footnotes/endnotes/tracked changes",
    },
  }

  if not path or path == "" then
    return { ok = false, doc = nil, diagnostics = diagnostics, error = "No DOCX path provided" }
  end

  diagnostics.path = path
  local file_data, read_err = read_file_binary(path)
  if not file_data then
    return { ok = false, doc = nil, diagnostics = diagnostics, error = "Could not read file: " .. tostring(read_err or "unknown error") }
  end

  diagnostics.file_size = #file_data
  diagnostics.zip_signature = file_data:sub(1, 4) == "PK\003\004"

  local zip, zip_err = parse_zip_central_directory(file_data)
  if not zip then
    return { ok = false, doc = nil, diagnostics = diagnostics, error = "Could not read ZIP central directory: " .. tostring(zip_err or "unknown error") }
  end

  diagnostics.zip_entries_count = zip.total_entries or #(zip.entries or {})
  diagnostics.zip = {
    entries_count = diagnostics.zip_entries_count,
    central_directory_offset = zip.central_directory_offset,
    central_directory_size = zip.central_directory_size,
  }

  local key_names = {
    "[Content_Types].xml",
    "word/document.xml",
    "word/comments.xml",
    "word/_rels/document.xml.rels",
    "word/styles.xml",
    "word/numbering.xml",
  }

  local parts = {}
  for _, name in ipairs(key_names) do
    local entry = zip.by_name and zip.by_name[name]
    local data, extracted_entry, err = extract_zip_part(file_data, zip, name)
    parts[name] = {
      found = entry ~= nil,
      entry = extracted_entry or entry,
      data = data,
      error = err,
    }
  end

  diagnostics.parts = make_key_part_diagnostics(parts)
  diagnostics.key_parts_found = {}
  for _, name in ipairs(key_names) do
    diagnostics.key_parts_found[name] = parts[name] and parts[name].found or false
  end

  local document_part = parts["word/document.xml"]
  if not document_part or not document_part.found then
    return { ok = false, doc = nil, diagnostics = diagnostics, error = "word/document.xml not found" }
  end
  if not document_part.data then
    return { ok = false, doc = nil, diagnostics = diagnostics, error = "word/document.xml extraction failed: " .. tostring(document_part.error or "unknown error") }
  end

  diagnostics.document_xml_size = #document_part.data
  diagnostics.document_xml_method = document_part.entry and document_part.entry.method or nil

  local relationships_xml = parts["word/_rels/document.xml.rels"] and parts["word/_rels/document.xml.rels"].data or nil
  local hyperlink_relationships, hyperlink_diagnostics = parse_docx_document_relationships(relationships_xml)

  local paragraphs = extract_docx_paragraphs(document_part.data)
  diagnostics.unsupported_placeholders = paragraphs.unsupported_placeholders or {
    table_count = 0,
    image_count = 0,
    unknown_count = 0,
    mixed_inline_image_left_unchanged_count = 0,
  }
  diagnostics.paragraphs = summarize_paragraphs(paragraphs)
  diagnostics.paragraph_format_diag_lines = build_paragraph_format_diag_lines(path, document_part.data, paragraphs, opts)

  local doc = build_clean_doc_from_paragraphs(paragraphs)

  rb_diag_reset(path)
  local run_boundary_diag_context = { path = path }
  local formatting_inventory = inspect_docx_inline_run_formatting(paragraphs, hyperlink_relationships, hyperlink_diagnostics, run_boundary_diag_context)
  apply_direct_run_styles_to_doc(doc, formatting_inventory.runs, run_boundary_diag_context)
  diagnostics.inline_formatting = summarize_inline_run_formatting(formatting_inventory)
  diagnostics.styled_tokens = summarize_styled_tokens(formatting_inventory.styled_tokens)
  diagnostics.hyperlinks = hyperlink_diagnostics

  local comments_xml = parts["word/comments.xml"] and parts["word/comments.xml"].data or nil
  local parsed_comments = parse_docx_comments(comments_xml)
  local diagnostic_refs = extract_docx_comment_refs(paragraphs)
  local raw_ref_summary = summarize_docx_comment_refs(diagnostic_refs, parsed_comments.by_id)
  local normalized_comments = normalize_docx_comments(parsed_comments, diagnostic_refs)
  attach_adapter_comments_to_doc(doc, normalized_comments)
  local ranges = build_docx_comment_range_highlights(doc, parsed_comments, normalized_comments)

  diagnostics.comments = summarize_docx_comments(parsed_comments)
  diagnostics.comment_refs_raw = raw_ref_summary
  diagnostics.comments_normalized = summarize_normalized_docx_comments(parsed_comments, normalized_comments)
  if opts.comment_order_diag_enabled == true then
    diagnostics.comment_order_detail = build_comment_order_detail(parsed_comments, diagnostic_refs, normalized_comments, opts)
  end
  diagnostics.comment_ranges = summarize_docx_comment_ranges(doc, ranges)
  diagnostics.doc_tokens = count_doc_tokens(doc)
  if type(diagnostics.hyperlinks) == "table" and type(diagnostics.doc_tokens) == "table" then
    diagnostics.hyperlinks.linked_token_count = diagnostics.doc_tokens.href_token_count or diagnostics.hyperlinks.linked_token_count or 0
  end

  doc.diagnostics = {
    adapter_version = DOCX_ADAPTER.VERSION,
    adapter_build = DOCX_ADAPTER.BUILD,
    paragraph_count = diagnostics.paragraphs.count,
    zip_entries_count = diagnostics.zip_entries_count,
  }

  return { ok = true, doc = doc, diagnostics = diagnostics, error = nil }
end

function DOCX_ADAPTER.parse_file(path, opts)
  local ok, result = pcall(parse_file_impl, path, opts or {})
  if ok then
    return result
  end
  return {
    ok = false,
    doc = nil,
    diagnostics = { adapter_version = DOCX_ADAPTER.VERSION, adapter_build = DOCX_ADAPTER.BUILD },
    error = "DOCX adapter internal error: " .. tostring(result),
  }
end

return DOCX_ADAPTER
end

function DOCX_IMPORT.load_adapter()
  if DOCX_IMPORT.adapter then return DOCX_IMPORT.adapter, nil, DOCX_IMPORT.adapter_path end

  local embedded_path = "<embedded DOCX adapter v0.5>"
  local ok, adapter_or_err = pcall(DOCX_IMPORT.create_embedded_adapter)
  if not ok then
    return nil, "Embedded DOCX adapter raised an error while loading:\n" .. tostring(adapter_or_err), embedded_path
  end

  local adapter = adapter_or_err
  if type(adapter) ~= "table" or type(adapter.parse_file) ~= "function" then
    return nil, "Embedded DOCX adapter did not return a table with parse_file(path, opts).", embedded_path
  end

  DOCX_IMPORT.adapter = adapter
  DOCX_IMPORT.adapter_path = embedded_path
  return adapter, nil, embedded_path
end

function DOCX_IMPORT.copy_comment_ids(ids)
  if type(ids) ~= "table" then return nil end
  local out = {}
  for _, id in ipairs(ids) do
    out[#out + 1] = id
  end
  if #out == 0 then return nil end
  return out
end

function DOCX_IMPORT.color_to_psv_u32(value)
  if type(value) == "number" then return value end
  if type(value) ~= "string" then return nil end

  local hex = value:match("^#(%x%x%x%x%x%x)$") or value:match("^(%x%x%x%x%x%x)$")
  if hex then
    return rgba(
      tonumber(hex:sub(1, 2), 16),
      tonumber(hex:sub(3, 4), 16),
      tonumber(hex:sub(5, 6), 16)
    )
  end

  local rgb = DOCX_IMPORT.HIGHLIGHT_COLORS[value:lower()]
  if rgb then return rgba(rgb[1], rgb[2], rgb[3]) end
  return nil
end

function DOCX_IMPORT.safe_docx_external_href(value)
  if type(value) ~= "string" then return nil end
  if value == "" then return nil end
  if not (value:match("^https://") or value:match("^http://")) then return nil end
  if value:find('"', 1, true) then return nil end
  if value:find("[%c]") then return nil end
  return value
end

function DOCX_IMPORT.bridge_doc_to_psv_paragraphs(doc, result, source_path, adapter)
  local diagnostics = {
    source_block_count = 0,
    bridged_paragraph_count = 0,
    stripped_bg_source_token_count = 0,
    copied_strike_token_count = 0,
    copied_comment_ids_token_count = 0,
    synthesized_ref_fields_count = 0,
    copied_ranges_count = 0,
    ignored_fg_count = 0,
    ignored_bg_count = 0,
    empty_paragraph_normalization_enabled = DOCX_IMPORT.drop_pure_empty_paragraphs_enabled(),
    dropped_pure_empty_paragraph_count = 0,
  }

  local paragraphs = {}
  if type(doc) ~= "table" then
    paragraphs.comments = { by_id = {}, refs = {}, order = {}, ranges = {} }
    paragraphs.import_info = {
      source_format = "docx",
      adapter_version = adapter and adapter.VERSION or (result and result.diagnostics and result.diagnostics.adapter_version) or nil,
      original_file_path = source_path,
      bridge_version = DOCX_IMPORT.BRIDGE_VERSION,
    }
    return paragraphs, diagnostics
  end

  diagnostics.source_block_count = #(doc.blocks or {})

  local paragraph_format_diag_count = 0
  local paragraph_format_diag_max_rows = DOCX_IMPORT.paragraph_format_diag_max_rows()
  local source_to_bridged_index = {}
  local referenced_source_paragraph_indices = DOCX_IMPORT.collect_referenced_docx_paragraph_indices(doc.comments)

  for source_block_index, block in ipairs(doc.blocks or {}) do
    local bridged_block = {
      tokens = {},
      tag = type(block.tag) == "string" and block.tag or "p",
      is_heading = block.is_heading == true,
      is_blank_paragraph = block.is_blank_paragraph == true,
    }

    if block.docx_unsupported == true then
      bridged_block.docx_unsupported = true
      bridged_block.docx_unsupported_kind = block.docx_unsupported_kind
      bridged_block.docx_unsupported_placeholder = block.docx_unsupported_placeholder
    end

    for _, token in ipairs(block.tokens or {}) do
      if type(token) == "table" then
        if token.newline == true then
          bridged_block.tokens[#bridged_block.tokens + 1] = { newline = true }
        elseif token.text ~= nil then
          local out = { text = tostring(token.text) }
          if token.docx_unsupported_placeholder == true then
            out.docx_unsupported_placeholder = true
            out.docx_unsupported_kind = token.docx_unsupported_kind
          end

          local fg = DOCX_IMPORT.color_to_psv_u32(token.fg)
          if fg ~= nil then
            out.fg = fg
          elseif token.fg ~= nil then
            diagnostics.ignored_fg_count = diagnostics.ignored_fg_count + 1
          end

          local bg = DOCX_IMPORT.color_to_psv_u32(token.bg)
          if bg ~= nil then
            out.bg = bg
          elseif token.bg ~= nil then
            diagnostics.ignored_bg_count = diagnostics.ignored_bg_count + 1
          end

          local safe_href = DOCX_IMPORT.safe_docx_external_href(token.href)
          if safe_href ~= nil then out.href = safe_href end
          if token.bold ~= nil then out.bold = token.bold end
          if token.italic ~= nil then out.italic = token.italic end
          if token.underline ~= nil then out.underline = token.underline end

          if token.strike ~= nil then
            out.strike = token.strike
            diagnostics.copied_strike_token_count = diagnostics.copied_strike_token_count + 1
          end

          if token.no_space_before == true then
            out.no_space_before = true
          end

          local copied_comment_ids = DOCX_IMPORT.copy_comment_ids(token.comment_ids)
          if copied_comment_ids then
            out.comment_ids = copied_comment_ids
            diagnostics.copied_comment_ids_token_count = diagnostics.copied_comment_ids_token_count + 1
          end

          if token.bg_source ~= nil then
            diagnostics.stripped_bg_source_token_count = diagnostics.stripped_bg_source_token_count + 1
          end

          bridged_block.tokens[#bridged_block.tokens + 1] = out
        end
      end
    end

    if DOCX_IMPORT.should_drop_pure_empty_paragraph(block, source_block_index, bridged_block, referenced_source_paragraph_indices) then
      diagnostics.dropped_pure_empty_paragraph_count = diagnostics.dropped_pure_empty_paragraph_count + 1
    else
      local bridged_paragraph_index = #paragraphs + 1
      source_to_bridged_index[source_block_index] = bridged_paragraph_index

      local block_text = nil
      local matched_key = nil
      if DOCX_IMPORT.paragraph_format_diag_enabled() then
        block_text = DOCX_IMPORT.block_text_for_diag(bridged_block)
        matched_key = DOCX_IMPORT.match_paragraph_format_diag_text(block_text)
        if matched_key then
          bridged_block._docx_para_format_diag_matched_key = matched_key
        end
      end

      if matched_key and paragraph_format_diag_count < paragraph_format_diag_max_rows and
         not DOCX_IMPORT.paragraph_format_diag_adapter_only_output() then
        paragraph_format_diag_count = paragraph_format_diag_count + 1
          DOCX_IMPORT.msg("[PSV DOCX PARAGRAPH FORMAT DIAG] BRIDGE file=" .. DOCX_IMPORT.basename(source_path) ..
            " adapter=" .. tostring(adapter and adapter.VERSION or result and result.diagnostics and result.diagnostics.adapter_version or "") ..
            " adapter_build=" .. tostring(adapter and adapter.BUILD or result and result.diagnostics and result.diagnostics.adapter_build or "") ..
            " bridge=" .. tostring(DOCX_IMPORT.BRIDGE_VERSION) ..
            " source_block=" .. tostring(source_block_index) ..
            " bridged_para=" .. tostring(bridged_paragraph_index) ..
            " match=" .. tostring(matched_key))
          DOCX_IMPORT.msg('[PSV DOCX PARAGRAPH FORMAT DIAG] BRIDGE text="' .. DOCX_IMPORT.diag_escape_text(block_text, 220) .. '" token_count=' .. tostring(#(bridged_block.tokens or {})))
          for token_index, token in ipairs(bridged_block.tokens or {}) do
            if token_index > 30 then break end
            if type(token) == "table" then
              local t = token.newline and "\n" or tostring(token.text or "")
              local starts_ws = t:match("^[%s%c]") ~= nil
              local ends_ws = t:match("[%s%c]$") ~= nil
              local has_tab = t:find("\t", 1, true) ~= nil
              DOCX_IMPORT.msg("[PSV DOCX PARAGRAPH FORMAT DIAG] BRIDGE token " .. tostring(token_index) ..
                ' text="' .. DOCX_IMPORT.diag_escape_text(t, 80) .. '" flags=' .. DOCX_IMPORT.diag_token_flags(token) ..
                " ws_start=" .. tostring(starts_ws) ..
                " ws_end=" .. tostring(ends_ws) ..
                " has_tab=" .. tostring(has_tab))
            end
          end
        end

      paragraphs[#paragraphs + 1] = bridged_block
    end
  end

  diagnostics.bridged_paragraph_count = #paragraphs

  local src_comments = type(doc.comments) == "table" and doc.comments or {}
  local bridged_comments = { by_id = {}, refs = {}, order = {}, ranges = {} }

  local marker_diag_enabled = PSV_DOCX_MARKER_PLACEMENT_DIAG_ENABLED == true
  local marker_diag_rows = marker_diag_enabled and {} or nil
  local marker_diag_range_by_comment_id = marker_diag_enabled and {} or nil

  local function find_actual_comment_highlight_bounds(paragraph_index, comment_id)
    local para = type(paragraph_index) == "number" and paragraphs[paragraph_index] or nil
    local tokens = para and para.tokens or nil
    if type(tokens) ~= "table" then return nil, nil, 0 end

    local comment_id_str = tostring(comment_id)
    local first_i, last_i, count = nil, nil, 0
    for tok_i, tok in ipairs(tokens) do
      if type(tok) == "table" and type(tok.comment_ids) == "table" then
        for _, id in ipairs(tok.comment_ids) do
          if id == comment_id or tostring(id) == comment_id_str then
            if first_i == nil then first_i = tok_i end
            last_i = tok_i
            count = count + 1
            break
          end
        end
      end
    end

    return first_i, last_i, count
  end

  local function marker_diag_add_flag(flags, name)
    if flags then flags[#flags + 1] = name end
  end

  local function marker_diag_bool(v)
    if v == nil then return "nil" end
    return tostring(v == true)
  end

  local function marker_diag_pos(p, t)
    return "p=" .. tostring(p) .. " t_after=" .. tostring(t)
  end

  local function marker_diag_add_row(ref, raw_paragraph_index, raw_token_index_after, final_paragraph_index, final_token_index_after, normalized_range)
    if not marker_diag_enabled or type(ref) ~= "table" then return end

    local range = nil
    if ref.comment_id ~= nil then
      range = marker_diag_range_by_comment_id[ref.comment_id] or marker_diag_range_by_comment_id[tostring(ref.comment_id)]
    end

    local actual_first, actual_last, actual_count = find_actual_comment_highlight_bounds(final_paragraph_index, ref.comment_id)
    local final_token_n = tonumber(final_token_index_after)
    local flags = {}

    if actual_count > 0 and final_token_n == 0 then
      marker_diag_add_flag(flags, "final_ref_at_0_while_highlight_exists")
    end
    if actual_first ~= nil and final_token_n ~= nil and final_token_n < actual_first then
      marker_diag_add_flag(flags, "final_ref_before_first_highlighted_token")
    end
    if actual_last ~= nil and final_token_n ~= nil and final_token_n < actual_last then
      marker_diag_add_flag(flags, "final_ref_before_last_highlighted_token")
    end
    if range then
      local usable_range = range.usable_range == true or range.usable == true
      local placement_matches_actual = actual_last ~= nil and final_token_n ~= nil and final_token_n == actual_last
      -- zero_width_or_short and range.end vs actual-last differences are now
      -- informational when the final marker placement has already been repaired
      -- to the actual highlighted token coverage. Keep suspicious flags focused
      -- on unresolved placement/data cases.
      if usable_range and range.zero_width_or_short == true and not placement_matches_actual then
        marker_diag_add_flag(flags, "usable_range_but_zero_width_or_short_unresolved")
      end
      if usable_range and range.coverage_mismatch == true and not placement_matches_actual then
        marker_diag_add_flag(flags, "usable_range_but_coverage_mismatch_unresolved")
      end
      if usable_range and range.matched ~= true and not placement_matches_actual then
        marker_diag_add_flag(flags, "usable_range_but_not_matched_unresolved")
      end
      local coverage_count = tonumber(range.token_coverage_count)
      if usable_range and (coverage_count == nil or coverage_count <= 0) then
        marker_diag_add_flag(flags, "usable_range_but_no_token_coverage")
      end
      local range_end_n = tonumber(range.end_token_index_after)
      if actual_last ~= nil and range_end_n ~= nil and range_end_n ~= actual_last and not placement_matches_actual then
        marker_diag_add_flag(flags, "range_end_token_index_differs_from_actual_last_unresolved")
      end
    end
    if normalized_range == nil and actual_count > 0 then
      marker_diag_add_flag(flags, "normalized_range_missing_while_highlight_tokens_exist")
    end

    marker_diag_rows[#marker_diag_rows + 1] = {
      comment_id = ref.comment_id,
      comment_id_str = tostring(ref.comment_id),
      anchor_kind = ref.anchor_kind,
      raw_paragraph_index = raw_paragraph_index,
      raw_token_index_after = raw_token_index_after,
      final_paragraph_index = final_paragraph_index,
      final_token_index_after = final_token_index_after,
      normalized_range_found = normalized_range ~= nil,
      paragraph_changed = raw_paragraph_index ~= final_paragraph_index,
      token_index_changed = raw_token_index_after ~= final_token_index_after,
      range = range,
      actual_first = actual_first,
      actual_last = actual_last,
      actual_count = actual_count,
      flags = flags,
      suspicious = #flags > 0,
    }
  end

  local function marker_diag_print_rows()
    if not marker_diag_enabled then return end

    local suspicious = {}
    for _, row in ipairs(marker_diag_rows or {}) do
      if row.suspicious then suspicious[#suspicious + 1] = row end
    end

    DOCX_IMPORT.msg("=== PSV DOCX MARKER PLACEMENT DIAG ===")
    DOCX_IMPORT.msg("refs: " .. tostring(#(marker_diag_rows or {})) .. ", suspicious: " .. tostring(#suspicious))

    if #suspicious == 0 then
      DOCX_IMPORT.msg("no suspicious marker placement rows found")
      DOCX_IMPORT.msg("")
      return
    end

    for _, row in ipairs(suspicious) do
      local range = row.range or {}
      DOCX_IMPORT.msg("comment_id=" .. tostring(row.comment_id) .. " anchor_kind=" .. tostring(row.anchor_kind))
      DOCX_IMPORT.msg("  raw:   " .. marker_diag_pos(row.raw_paragraph_index, row.raw_token_index_after))
      DOCX_IMPORT.msg("  final: " .. marker_diag_pos(row.final_paragraph_index, row.final_token_index_after))
      DOCX_IMPORT.msg("  normalized_found=" .. tostring(row.normalized_range_found) ..
        " paragraph_changed=" .. tostring(row.paragraph_changed) ..
        " token_changed=" .. tostring(row.token_index_changed))
      DOCX_IMPORT.msg("  range: start=" .. marker_diag_pos(range.start_paragraph_index, range.start_token_index_after) ..
        " end=" .. marker_diag_pos(range.end_paragraph_index, range.end_token_index_after))
      DOCX_IMPORT.msg("  range_flags: usable_range=" .. marker_diag_bool(range.usable_range) ..
        " usable=" .. marker_diag_bool(range.usable) ..
        " marker_fallback=" .. marker_diag_bool(range.marker_fallback) ..
        " matched=" .. marker_diag_bool(range.matched) ..
        " multi_paragraph=" .. marker_diag_bool(range.multi_paragraph))
      DOCX_IMPORT.msg("  range_quality: token_coverage_count=" .. tostring(range.token_coverage_count) ..
        " zero_width_or_short=" .. marker_diag_bool(range.zero_width_or_short) ..
        " coverage_mismatch=" .. marker_diag_bool(range.coverage_mismatch))
      DOCX_IMPORT.msg("  actual_highlight: first=" .. tostring(row.actual_first) ..
        " last=" .. tostring(row.actual_last) ..
        " count=" .. tostring(row.actual_count))
      DOCX_IMPORT.msg("  suspicion: " .. table.concat(row.flags or {}, ", "))
    end

    DOCX_IMPORT.msg("")
  end

  -- DOCX marker placement normalization:
  -- When a comment has a usable same-paragraph range, keep the visible marker
  -- but anchor it after the covered range instead of at the raw reference/start
  -- boundary. This preserves existing marker click/card behavior while making
  -- temporary DOCX markers visually follow the highlighted word/phrase.
  local range_by_comment_id = {}
  for _, range in ipairs(type(src_comments.ranges) == "table" and src_comments.ranges or {}) do
    if type(range) == "table" and range.comment_id ~= nil then
      local remapped_range = DOCX_IMPORT.copy_docx_range_with_remapped_paragraphs(range, source_to_bridged_index)
      if marker_diag_enabled then
        marker_diag_range_by_comment_id[remapped_range.comment_id] = remapped_range
        marker_diag_range_by_comment_id[tostring(remapped_range.comment_id)] = remapped_range
      end
      local usable_range = remapped_range.usable_range == true or remapped_range.usable == true
      local marker_fallback = remapped_range.marker_fallback == true
      local start_paragraph_index = tonumber(remapped_range.start_paragraph_index)
      local end_paragraph_index = tonumber(remapped_range.end_paragraph_index)
      local end_token_index_after = tonumber(remapped_range.end_token_index_after)
      if usable_range
          and not marker_fallback
          and start_paragraph_index ~= nil
          and end_paragraph_index ~= nil
          and start_paragraph_index == end_paragraph_index
          and end_token_index_after ~= nil
          and end_token_index_after >= 0
          and paragraphs[end_paragraph_index]
          and end_token_index_after <= #(paragraphs[end_paragraph_index].tokens or {}) then
        range_by_comment_id[remapped_range.comment_id] = remapped_range
        range_by_comment_id[tostring(remapped_range.comment_id)] = remapped_range
      end
    end
  end

  for id, comment in pairs(type(src_comments.by_id) == "table" and src_comments.by_id or {}) do
    if type(comment) == "table" then
      local out = {
        id = comment.id ~= nil and comment.id or id,
        text = comment.text ~= nil and tostring(comment.text) or "",
      }
      if comment.author ~= nil then out.author = comment.author end
      if comment.date ~= nil then out.date = comment.date end
      bridged_comments.by_id[id] = out
    end
  end

  for _, id in ipairs(type(src_comments.order) == "table" and src_comments.order or {}) do
    bridged_comments.order[#bridged_comments.order + 1] = id
  end

  for i, ref in ipairs(type(src_comments.refs) == "table" and src_comments.refs or {}) do
    if type(ref) == "table" then
      local raw_paragraph_index = tonumber(ref.paragraph_index) or ref.paragraph_index
      local paragraph_index = DOCX_IMPORT.remap_docx_paragraph_index(source_to_bridged_index, raw_paragraph_index)
      local token_index_after = ref.token_index_after
      local raw_token_index_after = token_index_after
      local normalized_range = ref.comment_id ~= nil and (range_by_comment_id[ref.comment_id] or range_by_comment_id[tostring(ref.comment_id)]) or nil
      if normalized_range then
        paragraph_index = tonumber(normalized_range.end_paragraph_index) or normalized_range.end_paragraph_index
        token_index_after = tonumber(normalized_range.end_token_index_after) or normalized_range.end_token_index_after

        -- DOCX marker placement repair:
        -- For short/zero-width ranges, range.end_token_index_after may point to
        -- the boundary before the actually highlighted token. When the bridged
        -- paragraph has real token.comment_ids coverage for this comment, anchor
        -- the visible [*] marker after the actual last highlighted token instead.
        local actual_first_i, actual_last_i, actual_count = find_actual_comment_highlight_bounds(paragraph_index, ref.comment_id)
        if actual_count > 0 and actual_last_i ~= nil then
          token_index_after = actual_last_i
        end
      end

      marker_diag_add_row(ref, raw_paragraph_index, raw_token_index_after, paragraph_index, token_index_after, normalized_range)

      local paragraph_tag = "p"
      if type(paragraph_index) == "number" and paragraphs[paragraph_index] and paragraphs[paragraph_index].tag then
        paragraph_tag = paragraphs[paragraph_index].tag
      end

      local out = {
        comment_id = ref.comment_id,
        paragraph_index = paragraph_index,
        token_index_after = token_index_after,
        anchor_kind = ref.anchor_kind,
      }

      if ref.ref_id ~= nil and ref.ref_id ~= "" then
        out.ref_id = ref.ref_id
      else
        out.ref_id = "docx_ref_" .. tostring(i)
        diagnostics.synthesized_ref_fields_count = diagnostics.synthesized_ref_fields_count + 1
      end

      if ref.label ~= nil and ref.label ~= "" then
        out.label = ref.label
      else
        out.label = "*"
        diagnostics.synthesized_ref_fields_count = diagnostics.synthesized_ref_fields_count + 1
      end

      if ref.paragraph_tag ~= nil and ref.paragraph_tag ~= "" then
        out.paragraph_tag = ref.paragraph_tag
      else
        out.paragraph_tag = paragraph_tag
        diagnostics.synthesized_ref_fields_count = diagnostics.synthesized_ref_fields_count + 1
      end

      if ref.block_src ~= nil and ref.block_src ~= "" then
        out.block_src = ref.block_src
      else
        out.block_src = "docx:p" .. tostring(paragraph_index or "")
        diagnostics.synthesized_ref_fields_count = diagnostics.synthesized_ref_fields_count + 1
      end

      bridged_comments.refs[#bridged_comments.refs + 1] = out
    end
  end

  marker_diag_print_rows()

  local range_fields = {
    "comment_id",
    "start_paragraph_index",
    "start_token_index_after",
    "end_paragraph_index",
    "end_token_index_after",
    "has_reference",
    "reference_paragraph_index",
    "reference_token_index_after",
    "token_coverage_count",
    "multi_paragraph",
    "matched",
    "usable_range",
    "marker_fallback",
    "zero_width_or_short",
    "coverage_mismatch",
  }

  for _, range in ipairs(type(src_comments.ranges) == "table" and src_comments.ranges or {}) do
    if type(range) == "table" then
      local remapped_range = DOCX_IMPORT.copy_docx_range_with_remapped_paragraphs(range, source_to_bridged_index)
      local out = {}
      for _, field in ipairs(range_fields) do
        if remapped_range[field] ~= nil then out[field] = remapped_range[field] end
      end
      bridged_comments.ranges[#bridged_comments.ranges + 1] = out
    end
  end
  diagnostics.copied_ranges_count = #bridged_comments.ranges

  paragraphs.comments = bridged_comments
  paragraphs.import_info = {
    source_format = "docx",
    adapter_version = adapter and adapter.VERSION or (result and result.diagnostics and result.diagnostics.adapter_version) or nil,
    original_file_path = source_path,
    bridge_version = DOCX_IMPORT.BRIDGE_VERSION,
  }

  return paragraphs, diagnostics
end

function DOCX_IMPORT.summarize_paragraphs(paragraphs)
  local summary = {
    blocks = 0,
    tokens = 0,
    comments = 0,
    refs = 0,
    ranges = 0,
  }

  summary.blocks = #((type(paragraphs) == "table" and paragraphs) or {})
  for _, block in ipairs((type(paragraphs) == "table" and paragraphs) or {}) do
    for _, token in ipairs(block.tokens or {}) do
      summary.tokens = summary.tokens + 1
    end
  end

  local comments = type(paragraphs) == "table" and paragraphs.comments or nil
  if type(comments) == "table" then
    summary.comments = #(comments.order or {})
    summary.refs = #(comments.refs or {})
    summary.ranges = #(comments.ranges or {})
  end

  return summary
end

function DOCX_IMPORT.load_docx(path, opts)
  DOCX_IMPORT.PENDING_ADAPTER_LINES_TAIL_STATUS = nil
  DOCX_IMPORT.reset_long_token_layout_diag_state(path)
  psv_layout_audit_reset(path)

  local adapter, adapter_err = DOCX_IMPORT.load_adapter()
  if not adapter then return nil, adapter_err, nil end

  local adapter_opts = {
    verbose = false,
    paragraph_format_diag_enabled = PSV_DOCX_PARAGRAPH_FORMAT_DIAG_ENABLED == true,
    paragraph_format_diag_max_rows = PSV_DOCX_PARAGRAPH_FORMAT_DIAG_MAX_ROWS,
    paragraph_format_diag_match_texts = PSV_DOCX_PARAGRAPH_FORMAT_DIAG_MATCH_TEXTS,
    comment_order_diag_enabled = DOCX_IMPORT.comment_order_diag_enabled(),
    comment_order_diag_max_rows = DOCX_IMPORT.comment_order_diag_max_rows(),
    bridge_version = DOCX_IMPORT.BRIDGE_VERSION,
  }
  local ok, result_or_err = pcall(adapter.parse_file, path, adapter_opts)
  if not ok then
    return nil, "DOCX adapter parse_file raised an error:\n" .. tostring(result_or_err), nil
  end

  local result = result_or_err
  if type(result) ~= "table" then
    return nil, "DOCX adapter returned a non-table result.", nil
  end
  if not result.ok then
    return nil, tostring(result.error or "DOCX adapter returned ok=false."), nil
  end
  if type(result.doc) ~= "table" then
    return nil, "DOCX adapter returned ok=true but result.doc is missing.", nil
  end

  if DOCX_IMPORT.paragraph_format_diag_enabled() then
    local result_diagnostics = type(result.diagnostics) == "table" and result.diagnostics or nil
    local adapter_diag_lines = result_diagnostics and result_diagnostics.paragraph_format_diag_lines or nil
    local adapter_lines_status = DOCX_IMPORT.compute_adapter_lines_status(path, adapter, result_diagnostics, adapter_diag_lines)

    DOCX_IMPORT.PENDING_ADAPTER_LINES_TAIL_STATUS = adapter_lines_status
    DOCX_IMPORT.msg(DOCX_IMPORT.format_adapter_lines_status("ADAPTER_LINES_STATUS", adapter_lines_status))

    if type(adapter_diag_lines) == "table" then
      for _, line in ipairs(adapter_diag_lines) do
        DOCX_IMPORT.msg(line)
      end
    end
  end

  local bridged, bridge_diagnostics = DOCX_IMPORT.bridge_doc_to_psv_paragraphs(result.doc, result, path, adapter)
  DOCX_IMPORT.print_comment_order_load_diagnostics(path, adapter, result, bridged)
  DOCX_IMPORT.print_empty_paragraph_normalization_status(path, bridge_diagnostics)
  if type(bridged) ~= "table" or #bridged == 0 then
    return nil, "DOCX bridge produced no readable paragraphs.", nil
  end

  local summary = DOCX_IMPORT.summarize_paragraphs(bridged)
  summary.adapter_version = adapter.VERSION or (result.diagnostics and result.diagnostics.adapter_version) or "unknown"
  summary.bridge_diagnostics = bridge_diagnostics or {}
  return bridged, nil, summary
end

function DOCX_IMPORT.print_error(path, err)
  DOCX_IMPORT.msg(SCRIPT_NAME .. " DOCX import")
  DOCX_IMPORT.msg("file: " .. tostring(path or ""))
  DOCX_IMPORT.msg("status: failed")
  DOCX_IMPORT.msg("error: " .. tostring(err or "unknown error"))
  DOCX_IMPORT.msg("")
end

function DOCX_IMPORT.print_success(path, summary)
  if not DOCX_IMPORT.PRINT_SUCCESS_TO_CONSOLE then return end
  summary = summary or {}
  DOCX_IMPORT.msg(SCRIPT_NAME .. " DOCX import")
  DOCX_IMPORT.msg("file: " .. tostring(path or ""))
  DOCX_IMPORT.msg("adapter: " .. tostring(summary.adapter_version or "unknown"))
  DOCX_IMPORT.msg("bridge: " .. tostring(DOCX_IMPORT.BRIDGE_VERSION))
  DOCX_IMPORT.msg("blocks: " .. tostring(summary.blocks or 0))
  DOCX_IMPORT.msg("tokens: " .. tostring(summary.tokens or 0))
  DOCX_IMPORT.msg("comments: " .. tostring(summary.comments or 0))
  DOCX_IMPORT.msg("refs: " .. tostring(summary.refs or 0))
  DOCX_IMPORT.msg("ranges: " .. tostring(summary.ranges or 0))
  DOCX_IMPORT.msg("status: ok")
  DOCX_IMPORT.msg("")
end

function load_file(path, opts)
  opts = opts or {}

  local lower_path = tostring(path or ""):lower()
  if lower_path:match("%.docx$") then
    local parsed, import_err, import_summary = DOCX_IMPORT.load_docx(path, opts)
    if not parsed then
      if opts.clear_on_fail then
        reset_loaded_state(true)
      end
      DOCX_IMPORT.print_error(path, import_err)
      if not opts.silent then
        reaper.MB(
          "DOCX import failed:\n" .. tostring(import_err or "unknown error"),
          SCRIPT_NAME .. " – DOCX import",
          0
        )
      end
      return false
    end

    paragraphs = parsed
    file_path  = path
    invalidate_search_cache()
    reset_body_scroll_inertia()
    psv_layout_audit_reset(path)
    empty_state_layout_warmup_frames = 0

    if not opts.skip_save then
      save_file_for_project()
    end

    if not opts.skip_recent then
      add_recent_script(path)
    end

    DOCX_IMPORT.print_success(path, import_summary)
    return true
  end

  local f = io.open(path, "r")
  if not f then
    if opts.clear_on_fail then
      reset_loaded_state(true)
    end
    if not opts.silent then
      reaper.MB("Cannot open:\n" .. path, SCRIPT_NAME .. " – Ошибка", 0)
    end
    return false
  end

  local html = f:read("*all")
  f:close()

  if psv_is_likely_html_code_file(html, path) then
    paragraphs = psv_make_html_code_file_placeholder_document(path)
    file_path  = path
    PSV_COMMENTS_SIDEBAR_OPEN = false
    invalidate_search_cache()
    reset_body_scroll_inertia()
    psv_layout_audit_reset(path)
    empty_state_layout_warmup_frames = 0

    if not opts.skip_save then
      save_file_for_project()
    end

    if not opts.skip_recent then
      add_recent_script(path)
    end

    return true
  end

  local parsed = parse_document(html)

  if #parsed == 0 then
    paragraphs = {}
    file_path = nil
    invalidate_search_cache()
    reset_body_scroll_inertia()
    psv_layout_audit_reset(nil)
    search_input_buf = ""
    search_nav_index = 0
    search_nav_scroll_target = nil
    if search_filter then
      reaper.ImGui_TextFilter_Clear(search_filter)
    end

    request_empty_state_layout_warmup()

    if not opts.skip_save then
      save_file_for_project()
    end

    if not opts.silent then
      reaper.MB(
        "No readable script text found in this HTML file.",
        SCRIPT_NAME .. " – Unsupported HTML",
        0
      )
    end

    return false
  end

  paragraphs = parsed
  file_path  = path
  invalidate_search_cache()
  reset_body_scroll_inertia()
  psv_layout_audit_reset(path)
  empty_state_layout_warmup_frames = 0

  if not opts.skip_save then
    save_file_for_project()
  end

  if not opts.skip_recent then
    add_recent_script(path)
  end

  return true
end

local function clear_script()
  paragraphs = {}
  file_path  = nil
  invalidate_search_cache()

  -- Clear переводит ##body в empty-state, поэтому старый document-scroll
  -- должен быть сброшен сразу, а не после очередного restore/save цикла.
  -- Непосредственный ImGui_SetScrollY() нельзя вызывать отсюда: clear_script()
  -- может сработать из меню, вне активного ##body. Поэтому просим короткий
  -- reset, который будет выполнен внутри body child на следующих кадрах.
  body_render_cache.empty_scroll_reset_frames = 2
  pending_body_scroll_y = nil
  pending_body_scroll_restore_frames = 0
  current_body_scroll_y = 0
  reset_body_scroll_inertia()
  psv_layout_audit_reset(nil)
  if last_proj_key then
    project_body_scroll_y[last_proj_key] = 0
  end

  request_empty_state_layout_warmup()
  save_file_for_project()
end

local function open_dialog()
  local extension_list = "Supported script files (*.html;*.htm;*.docx)|*.html;*.htm;*.docx|HTML files (*.html;*.htm)|*.html;*.htm|DOCX files (*.docx)|*.docx"
  local ok, path = reaper.GetUserFileName(1, "Open HTML/DOCX script", "", extension_list)
  if ok and path ~= "" then load_file(path) end
end

-- ══════════════════════════════════════════════════════════════
--  PROJECT-SCOPED UI STATE
-- ══════════════════════════════════════════════════════════════

local function clamp_font_size(value)
  return math.max(
    UI_FONT_SIZE_MIN,
    math.min(UI_FONT_SIZE_MAX, tonumber(value) or UI_FONT_SIZE_DEFAULT)
  )
end

function clamp_comments_nav_font_size(value)
  return math.max(
    UI_COMMENTS_NAV_FONT_SIZE_MIN,
    math.min(
      UI_COMMENTS_NAV_FONT_SIZE_MAX,
      tonumber(value) or UI_COMMENTS_NAV_FONT_SIZE_DEFAULT
    )
  )
end

-- save_cfg/load_cfg оставлены как локальные compatibility names для уже
-- существующих вызовов View UI / shutdown path, но больше не читают и не пишут
-- глобальный PodcastViewer.cfg. Font size теперь привязан к project key.
local function save_cfg(project_key)
  project_key = project_key or get_project_key()
  reaper.SetExtState(
    EXTSTATE_SEC,
    "ui_font_size:" .. project_key,
    tostring(clamp_font_size(font_size)),
    true
  )
  reaper.SetExtState(
    EXTSTATE_SEC,
    "ui_comments_nav_font_size:" .. project_key,
    tostring(clamp_comments_nav_font_size(comments_nav_font_size)),
    true
  )
end

local function load_cfg(project_key)
  project_key = project_key or get_project_key()

  local saved = reaper.GetExtState(EXTSTATE_SEC, "ui_font_size:" .. project_key)
  if saved and saved ~= "" then
    font_size = clamp_font_size(saved)
  else
    font_size = UI_FONT_SIZE_DEFAULT
  end

  local saved_comments_font = reaper.GetExtState(
    EXTSTATE_SEC,
    "ui_comments_nav_font_size:" .. project_key
  )
  if saved_comments_font and saved_comments_font ~= "" then
    comments_nav_font_size = clamp_comments_nav_font_size(saved_comments_font)
  else
    comments_nav_font_size = UI_COMMENTS_NAV_FONT_SIZE_DEFAULT
  end
end

local function valid_window_geometry(x, y, w, h)
  local min_w = tonumber(UI_MIN_WINDOW_W) or 840
  local min_h = tonumber(UI_MIN_WINDOW_H) or 560
  return x ~= nil and y ~= nil and w ~= nil and h ~= nil
     and w >= min_w and h >= min_h
end

local function save_window_geometry_for_project(project_key)
  -- Window position/size persistence is intentionally disabled.
  -- Keep this compatibility function as a no-op so existing shutdown/frame
  -- call sites do not need broad rewiring, but never write win_* ExtState keys.
  return
end

local function load_window_geometry_for_project(project_key)
  -- Window geometry restore is intentionally disabled.
  -- Every fresh launch starts from the default floating position/size, while
  -- project file restore and other project-scoped settings remain unchanged.
  current_window_x = UI_INIT_WINDOW_X
  current_window_y = UI_INIT_WINDOW_Y
  current_window_w = UI_INIT_WINDOW_W
  current_window_h = UI_INIT_WINDOW_H

  pending_window_geometry_apply = true
end

local function load_project_ui_state(project_key)
  load_cfg(project_key)
end

local function save_project_ui_state(project_key)
  project_key = project_key or owner_project_key or get_project_key()
  save_cfg(project_key)

  -- Window geometry belongs to the launch/owner project only.
  -- Non-owner tabs must never overwrite it through maintenance frames.
  if not owner_project_key or project_key == owner_project_key then
    save_window_geometry_for_project(project_key)
  end
end

local function owner_project_is_open()
  local index = 0
  while true do
    local project = reaper.EnumProjects(index, "")
    if not project then return false end
    if project == owner_project then return true end
    index = index + 1
  end
end

local function sync_owner_project_key(project_key)
  if project_key == owner_project_key then return end

  -- Saving/Save As changes the persistence key, not the live document owner.
  -- Retain legacy keys and carry current state to the new key without loading
  -- another document, clearing search, or resetting body/layout state.
  local previous_key = owner_project_key
  if previous_key then save_project_ui_state(previous_key) end
  save_file_for_project()
  save_project_ui_state(project_key)

  local scroll_y = current_body_scroll_y
  if scroll_y == nil and previous_key then
    scroll_y = project_body_scroll_y[previous_key]
  end
  if scroll_y ~= nil then project_body_scroll_y[project_key] = scroll_y end

  owner_project_key = project_key
  last_proj_key = project_key
end

-- ══════════════════════════════════════════════════════════════
--  RENDERING
-- ══════════════════════════════════════════════════════════════

-- Returns true if colour is a meaningful document highlight.
-- Google Docs can export real bright highlights such as #ffff00,
-- so only near-white backgrounds are rejected as default/no-highlight.
local function is_highlight(col)
  if not col then return false end
  local r, g, b = u32_to_rgba(col)
  return not (r >= 248 and g >= 248 and b >= 248)
end

local function paragraph_search_text(para, token_spans)
  local parts = {}
  local byte_count = 0
  for token_index, tok in ipairs(para.tokens) do
    if tok.text then
      if tok.no_space_before and parts[#parts] == " " then
        parts[#parts] = nil
        byte_count = byte_count - 1
      end
      if token_spans then
        token_spans[#token_spans + 1] = {
          token_index = token_index,
          first_byte = byte_count + 1,
          last_byte = byte_count + #tok.text,
        }
      end
      parts[#parts + 1] = tok.text
      parts[#parts + 1] = " "
      byte_count = byte_count + #tok.text + 1
    elseif tok.newline then
      parts[#parts + 1] = "\n"
      byte_count = byte_count + 1
    end
  end
  return table.concat(parts)
end

-- Нормализация поискового текста для простого case-insensitive containment.
-- В этом пассе трактуем строку фильтра как обычный текстовый запрос,
-- без расширенного синтаксиса TextFilter.
local CYRILLIC_UPPER_TO_LOWER = {
  ["А"]="а", ["Б"]="б", ["В"]="в", ["Г"]="г", ["Д"]="д", ["Е"]="е",
  ["Ё"]="ё", ["Ж"]="ж", ["З"]="з", ["И"]="и", ["Й"]="й", ["К"]="к",
  ["Л"]="л", ["М"]="м", ["Н"]="н", ["О"]="о", ["П"]="п", ["Р"]="р",
  ["С"]="с", ["Т"]="т", ["У"]="у", ["Ф"]="ф", ["Х"]="х", ["Ц"]="ц",
  ["Ч"]="ч", ["Ш"]="ш", ["Щ"]="щ", ["Ъ"]="ъ", ["Ы"]="ы", ["Ь"]="ь",
  ["Э"]="э", ["Ю"]="ю", ["Я"]="я",
}

local function normalize_search_text(s)
  s = (s or ""):lower()
  for upper, lower in pairs(CYRILLIC_UPPER_TO_LOWER) do
    s = s:gsub(upper, lower)
  end
  s = s:gsub("\194\160", " "):gsub("%s+", " ")
  s = s:gsub("^%s+", ""):gsub("%s+$", "")
  return s
end

local function build_search_normalized_view(text)
  local parts, segments = {}, {}
  local position, normalized_size = 1, 0
  local function append_segment(part, raw_start, raw_end, collapsed)
    parts[#parts + 1] = part
    local previous = segments[#segments]
    if not collapsed and previous and not previous.collapsed and previous.raw_last + 1 == raw_start then
      previous.last = normalized_size + #part
      previous.raw_last = raw_end
    else
      segments[#segments + 1] = { first=normalized_size + 1, last=normalized_size + #part,
        raw_first=raw_start, raw_last=raw_end, collapsed=collapsed or nil }
    end
    normalized_size = normalized_size + #part
  end
  local function whitespace_size(index)
    local byte = text:byte(index)
    if byte == 32 or (byte and byte >= 9 and byte <= 13) then return 1 end
    if text:sub(index, index + 1) == "\194\160" then return 2 end
    return 0
  end
  while position <= #text do
    local raw_start = position
    local width = whitespace_size(position)
    if width > 0 then
      repeat
        position = position + width
        width = whitespace_size(position)
      until width == 0
      if #parts > 0 and position <= #text then
        append_segment(" ", raw_start, position - 1, position - raw_start ~= 1)
      end
    else
      repeat position = position + 1 until position > #text or whitespace_size(position) > 0
      local part = normalize_search_text(text:sub(raw_start, position - 1))
      append_segment(part, raw_start, position - 1, false)
    end
  end
  return table.concat(parts), segments
end

local function get_search_query_text()
  return normalize_search_text(reaper.ImGui_TextFilter_Get(search_filter))
end

-- Реальные реализации cache-helpers ставим здесь, уже после локальных
-- paragraph_search_text()/normalize_search_text(), чтобы они гарантированно
-- использовали именно эти локальные helpers, а не несуществующие globals.
invalidate_search_cache = function()
  search_doc_cache_version = search_doc_cache_version + 1

  search_doc_cache.cached_version = -1
  search_doc_cache.paragraph_texts = {}
  search_doc_cache.paragraph_norm_texts = {}
  search_doc_cache.paragraph_token_spans = {}
  search_doc_cache.paragraph_normalization_segments = {}

  search_query_cache.doc_version = -1
  search_query_cache.query = ""
  search_query_cache.has_filter = false
  search_query_cache.match_indices = {}
  search_query_cache.match_lookup = {}
  search_query_cache.token_hit_lookup = {}
  search_query_cache.occurrence_count = 0
  search_query_cache.occurrences = {}
end

ensure_search_document_cache = function()
  if search_doc_cache.cached_version == search_doc_cache_version then
    return
  end

  local paragraph_texts = {}
  local paragraph_norm_texts = {}
  local paragraph_token_spans = {}
  local paragraph_normalization_segments = {}

  for para_index, para in ipairs(paragraphs) do
    local spans = {}
    local para_text = paragraph_search_text(para, spans)
    paragraph_token_spans[para_index] = spans
    paragraph_texts[para_index] = para_text
    paragraph_norm_texts[para_index], paragraph_normalization_segments[para_index] = build_search_normalized_view(para_text)

  end

  search_doc_cache.paragraph_texts = paragraph_texts
  search_doc_cache.paragraph_norm_texts = paragraph_norm_texts
  search_doc_cache.paragraph_token_spans = paragraph_token_spans
  search_doc_cache.paragraph_normalization_segments = paragraph_normalization_segments
  search_doc_cache.cached_version = search_doc_cache_version
end

ensure_search_query_cache = function()
  ensure_search_document_cache()

  local query = get_search_query_text()
  if search_query_cache.doc_version == search_doc_cache_version
     and search_query_cache.query == query then
    return
  end


  -- PSV_NAV_DIAG_BEGIN hook
  search_diag.query_before_index = search_nav_index
  search_diag.query_before_value = search_query_cache.query
  -- PSV_NAV_DIAG_END hook
  search_nav_index = 0
  search_nav_scroll_target = nil
  search_nav_occurrence = nil

  local match_indices, match_lookup, token_hit_lookup, occurrences = {}, {}, {}, {}
  local has_filter = query ~= ""

  for para_index, _ in ipairs(paragraphs) do
    if not has_filter then
      match_indices[#match_indices + 1] = para_index
      match_lookup[para_index] = true
    else
      local para_norm = search_doc_cache.paragraph_norm_texts[para_index]
      local spans = search_doc_cache.paragraph_token_spans[para_index]
      local segments = search_doc_cache.paragraph_normalization_segments[para_index]
      local segment_cursor = 1
      local function raw_byte(position, is_end)
        while segments[segment_cursor] and segments[segment_cursor].last < position do
          segment_cursor = segment_cursor + 1
        end
        local segment = segments[segment_cursor]
        if not segment then return #search_doc_cache.paragraph_texts[para_index] end
        if segment.collapsed then return is_end and segment.raw_last or segment.raw_first end
        return segment.raw_first + position - segment.first
      end
      local query_pos, span_cursor = 1, 1
      local tok_hits = {}
      local para_has_match = false
      while true do
        local hit_s, hit_e = para_norm:find(query, query_pos, true)
        if not hit_s then break end
        local raw_s = raw_byte(hit_s, false)
        local raw_e = raw_byte(hit_e, true)
        local occurrence = { paragraph_index=para_index, first_byte=raw_s, last_byte=raw_e }
        while spans[span_cursor] and spans[span_cursor].last_byte < raw_s do
          span_cursor = span_cursor + 1
        end
        local index = span_cursor
        while spans[index] and spans[index].first_byte <= raw_e do
          local span = spans[index]
          if span.last_byte >= raw_s then
            tok_hits[span.token_index] = true
            if not occurrence.token_index then
              occurrence.token_index = span.token_index
              occurrence.token_byte = math.max(1, raw_s - span.first_byte + 1)
            end
          end
          index = index + 1
        end
        occurrences[#occurrences + 1] = occurrence
        para_has_match = true
        query_pos = hit_e + 1
      end
      if para_has_match then
        match_indices[#match_indices + 1] = para_index
        match_lookup[para_index] = true
        token_hit_lookup[para_index] = tok_hits
      end
    end
  end

  search_query_cache.doc_version = search_doc_cache_version
  search_query_cache.query = query
  search_query_cache.has_filter = has_filter
  search_query_cache.match_indices = match_indices
  search_query_cache.match_lookup = match_lookup
  search_query_cache.token_hit_lookup = token_hit_lookup
  search_query_cache.occurrence_count = #occurrences
  search_query_cache.occurrences = occurrences

  -- PSV_NAV_DIAG_BEGIN hook
  search_diag.watch = nil
  search_diag.record("query_rebuilt", { previous_index=search_diag.query_before_index,
    previous_query=search_diag.query_before_value, count=#occurrences })
  -- PSV_NAV_DIAG_END hook
end

local function scroll_search_occurrence_to_line(ctx, para_index, token_index, first_byte, last_byte, line_y)
  local occurrence = search_nav_occurrence
  if not occurrence or search_nav_scroll_target ~= para_index
     or occurrence.token_index ~= token_index then return false end
  local byte = occurrence.token_byte or 1
  if byte < first_byte or byte > last_byte then return false end
  reset_body_scroll_inertia()

  -- PSV_NAV_DIAG_BEGIN hook
  search_diag.request_scroll(ctx, "token", para_index, token_index, first_byte, last_byte, line_y, 0.5)
  -- PSV_NAV_DIAG_END hook
  -- GetCursorPos includes Scroll.y; SetScrollFromPosY adds it again.
  -- Convert the content coordinate to the visible window-local coordinate.
  reaper.ImGui_SetScrollFromPosY(ctx, line_y - reaper.ImGui_GetScrollY(ctx), 0.5)
  return true
end

local function collect_matching_paragraph_indices()
  ensure_search_query_cache()
  return search_query_cache.match_indices,
         search_query_cache.match_lookup,
         search_query_cache.has_filter,
         search_query_cache.token_hit_lookup
end

-- Подготавливает cache измеренных высот абзацев для текущей layout-конфигурации.
-- ВАЖНО:
-- Это не новый layout-engine и не retained system.
-- Нужен только для локального безопасного пропуска уже измеренных абзацев,
-- которые явно находятся далеко вне видимого viewport body child.
local function ensure_body_render_cache(has_filter)
  local layout_key = table.concat({
    tostring(search_doc_cache_version),
    tostring(font_size),
    tostring(body_margin_left),
    tostring(body_margin_right),
    tostring(first_line_indent),
    tostring(line_spacing),
    tostring(paragraph_spacing),
    tostring(PAGE_LAYOUT_ENABLED and 1 or 0),
    tostring(PAGE_H),
    tostring(PAGE_MARGIN_LEFT),
    tostring(PAGE_MARGIN_RIGHT),
    tostring(PAGE_GAP_Y),
    tostring(PAGE_STACK_TOP_GAP),
    tostring(PAGE_STACK_BOTTOM_GAP),
    tostring(PAGE_PAD_TOP),
    tostring(PAGE_PAD_BOTTOM),
  }, "|")

  if body_render_cache.doc_version ~= search_doc_cache_version
     or body_render_cache.layout_key ~= layout_key then

    -- PSV_NAV_DIAG_BEGIN hook
    search_diag.record("layout_cache_reset", { font=font_size,
      margin_left=body_margin_left, margin_right=body_margin_right })
    -- PSV_NAV_DIAG_END hook
    body_render_cache.doc_version = search_doc_cache_version
    body_render_cache.layout_key = layout_key
    body_render_cache.paragraph_heights = {}
    body_render_cache.paragraph_start_y = {}
  end

  return body_render_cache.paragraph_heights
end

local function open_or_copy_about_url(ctx, url)
  -- Safe link activation path used by About/Support, document-body links,
  -- and comment-card link rows.
  -- Order:
  -- 1) reject empty/placeholders with the previous quiet copy behavior
  -- 2) validate non-placeholder URLs before any browser-opening attempt
  -- 3) try CF_ShellExecute only for safe http/https URLs
  -- 4) try validated OS-specific ExecProcess fallback
  -- 5) copy to clipboard and show a visible fallback message.
  -- No os.execute/io.popen/platform-specific blocking shell calls are used.
  url = tostring(url or "")

  local function is_placeholder_or_empty(value)
    return value == ""
        or value == "PASTE_PATREON_URL_HERE"
        or value == "PASTE_CONTACT_URL_HERE"
  end

  local function is_safe_http_url(value)
    if is_placeholder_or_empty(value) then return false end
    if not (value:match("^https://") or value:match("^http://")) then return false end
    if value:find('"', 1, true) then return false end
    if value:find("[%c]") then return false end
    return true
  end

  local function copy_to_clipboard(value)
    if type(reaper.ImGui_SetClipboardText) == "function" then
      reaper.ImGui_SetClipboardText(ctx, value or "")
      return true
    end
    return false
  end

  local function show_copied_fallback_message(copied)
    local msg
    if copied then
      msg = "Could not open the browser automatically.\nThe link was copied to clipboard."
    else
      msg = "Could not open the browser automatically.\nPlease copy the link manually."
    end
    reaper.MB(msg, SCRIPT_NAME .. " – Link", 0)
  end

  if is_placeholder_or_empty(url) then
    copy_to_clipboard(url)
    return
  end

  if not is_safe_http_url(url) then
    local copied = copy_to_clipboard(url)
    show_copied_fallback_message(copied)
    return
  end

  if type(reaper.CF_ShellExecute) == "function" then
    local ok, rv = pcall(reaper.CF_ShellExecute, url)
    if ok and rv ~= false then
      return
    end
  end

  if type(reaper.ExecProcess) == "function" then
    local os_name = ""
    if type(reaper.GetOS) == "function" then
      os_name = tostring(reaper.GetOS() or "")
    end

    local cmd = nil
    if os_name:match("Win") then
      cmd = 'rundll32.exe url.dll,FileProtocolHandler "' .. url .. '"'
    elseif os_name:match("OSX") or os_name:match("macOS") then
      cmd = 'open "' .. url .. '"'
    else
      cmd = 'xdg-open "' .. url .. '"'
    end

    if cmd then
      local ok, rv = pcall(reaper.ExecProcess, cmd, -1)
      if ok and rv ~= false then
        return
      end

      if os_name:match("Win") then
        local explorer_cmd = 'explorer.exe "' .. url .. '"'
        local explorer_ok, explorer_rv = pcall(reaper.ExecProcess, explorer_cmd, -1)
        if explorer_ok and explorer_rv ~= false then
          return
        end
      end
    end
  end

  local copied = copy_to_clipboard(url)
  show_copied_fallback_message(copied)
end

function psv_block_document_interactions_this_frame(ctx)
  if reaper.ImGui_GetFrameCount then
    PSV_DOCUMENT_INTERACTIONS_BLOCK_FRAME = reaper.ImGui_GetFrameCount(ctx)
  else
    PSV_DOCUMENT_INTERACTIONS_BLOCK_FRAME = -1
  end
end

function psv_document_interactions_blocked(ctx)
  -- Document links/comment ranges/markers use manual screen-space hit-tests,
  -- so they must explicitly respect native/custom popup ownership.
  -- MenuItem/native popup interaction itself stays untouched.
  if show_about_overlay then return true end
  if PSV_TOP_ROW_CUSTOM_MENU_OPEN ~= nil then return true end
  if reaper.ImGui_GetFrameCount
     and PSV_DOCUMENT_INTERACTIONS_BLOCK_FRAME == reaper.ImGui_GetFrameCount(ctx) then
    return true
  end

  if reaper.ImGui_IsPopupOpen
     and reaper.ImGui_PopupFlags_AnyPopupId
     and reaper.ImGui_PopupFlags_AnyPopupLevel then
    local flags = reaper.ImGui_PopupFlags_AnyPopupId() | reaper.ImGui_PopupFlags_AnyPopupLevel()
    return reaper.ImGui_IsPopupOpen(ctx, "", flags) == true
  end

  return false
end


-- Narrow namespace for comment-card plain-URL helpers.
-- One local table keeps the helper set private without adding several
-- main-chunk locals to this already large single-file script.
local function search_keyboard_available(ctx)
  if psv_document_interactions_blocked(ctx) then return false end
  if paragraphs.comments and paragraphs.comments.active_id then return false end
  if reaper.ImGui_IsAnyItemActive and reaper.ImGui_IsAnyItemActive(ctx) and not search_input_active then
    return false
  end
  if reaper.ImGui_IsWindowFocused and reaper.ImGui_FocusedFlags_RootAndChildWindows
     and not reaper.ImGui_IsWindowFocused(ctx, reaper.ImGui_FocusedFlags_RootAndChildWindows()) then
    return false
  end
  return true
end

-- PSV_NAV_DIAG_BEGIN keys
function search_diag.observe_keys(context, enabled, total, has_filter)
  local read = search_diag.read
  local function key(enum, fn, pressed)
    if type(enum) ~= "function" then return false end
    if pressed then return read(fn, context, enum(), false) == true end
    return read(fn, context, enum()) == true
  end
  local enter = key(reaper.ImGui_Key_Enter, reaper.ImGui_IsKeyPressed, true)
  local keypad = key(reaper.ImGui_Key_KeypadEnter, reaper.ImGui_IsKeyPressed, true)
  local enter_down = key(reaper.ImGui_Key_Enter, reaper.ImGui_IsKeyDown)
  local keypad_down = key(reaper.ImGui_Key_KeypadEnter, reaper.ImGui_IsKeyDown)
  local left_shift = key(reaper.ImGui_Key_LeftShift, reaper.ImGui_IsKeyDown)
  local right_shift = key(reaper.ImGui_Key_RightShift, reaper.ImGui_IsKeyDown)
  local mods = read(reaper.ImGui_GetKeyMods, context)
  local modifier_changed = left_shift ~= (search_diag.left_shift or false)
    or right_shift ~= (search_diag.right_shift or false) or mods ~= search_diag.mods
  search_diag.index_before_keys = search_nav_index
  if enter or keypad or enter_down ~= (search_diag.enter_down or false)
     or keypad_down ~= (search_diag.keypad_down or false) or (has_filter and modifier_changed) then
    local flags = read(reaper.ImGui_FocusedFlags_RootAndChildWindows)
    search_diag.record("key_input", { enter=enter, keypad=keypad, enter_down=enter_down, keypad_down=keypad_down,
      mods=mods, left_shift=left_shift, right_shift=right_shift,
      enabled=enabled, total=total, has_filter=has_filter, available=search_keyboard_available(context),
      search_active=search_input_active, any_active=read(reaper.ImGui_IsAnyItemActive, context),
      focused=flags and read(reaper.ImGui_IsWindowFocused, context, flags),
      document_blocked=psv_document_interactions_blocked(context),
      menu=tostring(PSV_TOP_ROW_CUSTOM_MENU_OPEN), about=show_about_overlay,
      comment=tostring(paragraphs.comments and paragraphs.comments.active_id) })
  end
  search_diag.enter_down, search_diag.keypad_down = enter_down, keypad_down
  search_diag.left_shift, search_diag.right_shift, search_diag.mods = left_shift, right_shift, mods
end
-- PSV_NAV_DIAG_END keys

local comment_url = {}

-- Extract plain http/https URLs from a comment's already-parsed text.
-- Google Docs comment HTML exports may strip user-authored links down to plain
-- text, so comment-card production links are rendered as separate rows below
-- the unchanged comment text instead of as inline rich-text anchors.
comment_url.extract_plain_urls = function(text)
  local urls = {}
  local seen = {}

  for raw_url in tostring(text or ""):gmatch("https?://[%w%-%._~:/%?#%[%]@!%$&'%(%)%*%+,;=%%]+") do
    local url = raw_url:gsub("[%.%,%;:%)%]%}»”]+$", "")
    if url ~= "" and not seen[url] then
      urls[#urls + 1] = url
      seen[url] = true
    end
  end

  return urls
end

comment_url.escape_lua_pattern = function(text)
  return tostring(text or ""):gsub("([^%w])", "%%%1")
end

comment_url.is_punctuation_only_line = function(text)
  local residue = trim(tostring(text or ""))
  if residue == "" then return true end

  -- Remove ordinary punctuation plus the specific quote/bracket characters
  -- that are known URL-trailing residue in Google Docs comment exports.
  residue = residue:gsub("[%s%p]+", "")
  residue = residue:gsub("[»”“„‘’—–]+", "")
  return residue == ""
end

comment_url.sorted_copy_by_length_desc = function(urls)
  local sorted_urls = {}
  if type(urls) == "table" then
    for _, url in ipairs(urls) do
      url = tostring(url or "")
      if url ~= "" then
        sorted_urls[#sorted_urls + 1] = url
      end
    end
  end

  table.sort(sorted_urls, function(a, b)
    if #a == #b then return a < b end
    return #a > #b
  end)

  return sorted_urls
end

comment_url.remove_urls_from_display_text = function(text, urls)
  if type(urls) ~= "table" or #urls == 0 then
    return tostring(text or "")
  end

  -- Render-only de-duplication: keep stored comment.text intact, but remove
  -- exact URLs that are already rendered below as clickable comment link rows.
  -- Longer URLs are removed first so prefix-overlap pairs do not leave suffixes.
  local removal_urls = comment_url.sorted_copy_by_length_desc(urls)
  local normalized_text = tostring(text or "")
    :gsub("\r\n", "\n")
    :gsub("\r", "\n")
  local display_lines = {}

  for raw_line in (normalized_text .. "\n"):gmatch("([^\n]*)\n") do
    local display_line = raw_line
    local removed_url_from_line = false

    for _, url in ipairs(removal_urls) do
      local escaped_url = comment_url.escape_lua_pattern(url)
      local changed = false
      display_line = display_line:gsub(escaped_url, function()
        changed = true
        return ""
      end)
      if changed then
        removed_url_from_line = true
      end
    end

    if removed_url_from_line then
      display_line = display_line
        :gsub("[ \t]+", " ")
        :gsub("^%s+", "")
        :gsub("%s+$", "")
    end

    -- If the whole line was only a URL plus trailing punctuation/brackets,
    -- do not leave an empty or punctuation-only rendered line above the row.
    if not (removed_url_from_line and comment_url.is_punctuation_only_line(display_line)) then
      display_lines[#display_lines + 1] = display_line
    end
  end

  return table.concat(display_lines, "\n")
end

comment_url.fit_link_text_to_width = function(ctx, text, max_w)
  text = tostring(text or "")
  if select(1, reaper.ImGui_CalcTextSize(ctx, text)) <= max_w then
    return text
  end

  local ellipsis = "..."
  local ellipsis_w = select(1, reaper.ImGui_CalcTextSize(ctx, ellipsis))
  if ellipsis_w >= max_w then
    return ellipsis
  end

  local chars = {}
  if utf8 and utf8.codes and utf8.char then
    local ok = pcall(function()
      for _, codepoint in utf8.codes(text) do
        chars[#chars + 1] = utf8.char(codepoint)
      end
    end)
    if not ok then
      chars = {}
    end
  end
  if #chars == 0 then
    for i = 1, #text do
      chars[#chars + 1] = text:sub(i, i)
    end
  end

  local lo = 0
  local hi = #chars
  local best = ellipsis
  while lo <= hi do
    local mid = math.floor((lo + hi) / 2)
    local candidate = table.concat(chars, "", 1, mid) .. ellipsis
    local candidate_w = select(1, reaper.ImGui_CalcTextSize(ctx, candidate))
    if candidate_w <= max_w then
      best = candidate
      lo = mid + 1
    else
      hi = mid - 1
    end
  end
  return best
end

comment_url.append_link_rows = function(ctx, wrapped_lines, total_text_h, line_h, text_max_w, urls)
  if type(urls) ~= "table" or #urls == 0 then
    return total_text_h
  end

  if #wrapped_lines > 0 and not wrapped_lines[#wrapped_lines].is_gap then
    local link_top_gap_h = math.max(3, math.floor(line_h * 0.25 + 0.5))
    wrapped_lines[#wrapped_lines + 1] = {
      is_gap=true,
      y=total_text_h,
      h=link_top_gap_h,
    }
    total_text_h = total_text_h + link_top_gap_h
  end

  for _, url in ipairs(urls) do
    wrapped_lines[#wrapped_lines + 1] = {
      is_link=true,
      text=comment_url.fit_link_text_to_width(ctx, url, text_max_w),
      url=url,
      y=total_text_h,
    }
    total_text_h = total_text_h + line_h
  end

  return total_text_h
end

-- Экспериментальный scaffold будущего normal-ImGui renderer-а комментариев.
-- ВАЖНО: это намеренно controlled global namespace, а не top-level local,
-- потому что основной chunk скрипта уже находится у Lua-лимита local variables.
-- Таблица пересоздаётся при каждом запуске скрипта, поэтому stale-состояние
-- от предыдущего запуска не сохраняется. Текущий режим задаётся явно ниже.
PSV_COMMENT_CARD_RENDERER = {
  mode = "imgui_child",
}

PSV_COMMENT_CARD_RENDERER.render_imgui_child_scaffold = function(args)
  -- Minimal overlay-window prototype for the experimental normal-ImGui card path.
  -- It is only called when PSV_COMMENT_CARD_RENDERER.mode == "imgui_child".
  if type(args) ~= "table" then return false end
  if not args.ctx then return false end
  if type(args.comments) ~= "table" then return false end
  if type(args.comment_blocks) ~= "table" then return false end

  -- Диагностика comment-card должна быть копируемой и стабильной. Поэтому
  -- v3.0.20 выводит snapshots в REAPER console вместо временного ImGui-окна.
  -- Helper ниже только наблюдает уже рассчитанные значения и не участвует
  -- в placement, close policy, drag behavior или sizing.
  local function emit_comment_card_diag_console(reason, snapshot)
    if not PSV_COMMENT_CARD_DIAG_ENABLED then return end
    if type(args.comments) ~= "table" then return end

    snapshot = snapshot or {}

    local function diag_value(value)
      if value == nil then return "nil" end
      if type(value) == "number" then return string.format("%.1f", value) end
      return tostring(value)
    end

    local function diag_bool(value)
      return value == true and "true" or "false"
    end

    local comments = args.comments
    local active_id_s = tostring(snapshot.active_id or "nil")
    local selected_s = tostring(snapshot.selected_candidate_this_frame or "nil")
    local manual_enabled = snapshot.manual_card_position_enabled == true
    local dragging = snapshot.manual_card_dragging == true
    local close_requested = snapshot.clear_active_comment_card_state_requested == true
    local marker_unavailable = snapshot.marker_geometry_unavailable == true
    local no_fit = snapshot.no_fit_close_condition == true
    local locked_candidate_s = tostring(snapshot.locked_candidate or "nil")
    local locked_candidate_id_s = tostring(snapshot.locked_candidate_id or "nil")
    local candidate_lock_used = snapshot.candidate_lock_used == true
    local candidate_lock_initialized = snapshot.candidate_lock_initialized == true
    local candidate_lock_close_condition = snapshot.candidate_lock_close_condition == true
    local keep_inside_body_x = snapshot.keep_inside_body_x == true
    local body_edge_margin_x = tonumber(snapshot.body_edge_margin_x) or 0
    local body_vertical_scrollbar_visible = snapshot.body_vertical_scrollbar_visible == true
    local body_scrollbar_reserved_w = tonumber(snapshot.body_scrollbar_reserved_w) or 0
    local hard_x1 = tonumber(snapshot.hard_x1)
    local hard_x2 = tonumber(snapshot.hard_x2)
    local available_body_card_w = tonumber(snapshot.available_body_card_w)
    local horizontal_adjusted = snapshot.horizontal_adjusted == true

    -- Compact signature controls console spam. It intentionally tracks state
    -- transitions, not every scroll-driven coordinate change. Full coordinates
    -- are still printed inside each emitted snapshot.
    local signature = table.concat({
      active_id_s,
      selected_s,
      locked_candidate_s,
      locked_candidate_id_s,
      tostring(candidate_lock_used),
      tostring(candidate_lock_initialized),
      tostring(candidate_lock_close_condition),
      tostring(keep_inside_body_x),
      string.format("%.1f", body_edge_margin_x),
      tostring(body_vertical_scrollbar_visible),
      string.format("%.1f", body_scrollbar_reserved_w),
      string.format("%.1f", hard_x1 or -1),
      string.format("%.1f", hard_x2 or -1),
      string.format("%.1f", available_body_card_w or -1),
      tostring(horizontal_adjusted),
      tostring(manual_enabled),
      tostring(dragging),
      tostring(close_requested),
      tostring(marker_unavailable),
      tostring(no_fit),
    }, "|")

    local event_reason = reason
    if not event_reason or event_reason == "" then
      if comments.diag_console_last_active_id ~= active_id_s then
        event_reason = "open"
      elseif snapshot.selected_candidate_changed == true then
        event_reason = "candidate_changed"
      elseif candidate_lock_initialized then
        event_reason = "candidate_lock_initialized"
      elseif candidate_lock_close_condition then
        event_reason = "candidate_lock_close_condition"
      elseif no_fit then
        event_reason = "no_fit_close_condition"
      elseif close_requested then
        event_reason = "close_requested"
      elseif marker_unavailable then
        event_reason = "marker_geometry_unavailable"
      elseif comments.diag_console_last_manual_enabled ~= nil
         and comments.diag_console_last_manual_enabled ~= manual_enabled then
        event_reason = "manual_card_position_enabled_changed"
      elseif comments.diag_console_last_dragging ~= nil
         and comments.diag_console_last_dragging ~= dragging then
        event_reason = "manual_card_dragging_changed"
      elseif not comments.diag_console_has_printed then
        event_reason = "first"
      elseif comments.diag_console_last_signature ~= signature then
        event_reason = "state_changed"
      else
        return
      end
    end

    comments.diag_console_snapshot_index = (tonumber(comments.diag_console_snapshot_index) or 0) + 1

    local time_text = "n/a"
    if reaper.time_precise then
      local ok_time, time_value = pcall(reaper.time_precise)
      if ok_time and time_value then
        time_text = string.format("%.3f", time_value)
      end
    end

    local lines = {}
    lines[#lines + 1] = "=== PSV COMMENT CARD DIAG ==="
    lines[#lines + 1] = "version: 3.0.57"
    lines[#lines + 1] = "reason: " .. tostring(event_reason)
    lines[#lines + 1] = "frame/time: " .. tostring(comments.diag_console_snapshot_index) .. " / " .. time_text
    lines[#lines + 1] = "active_id: " .. active_id_s
    lines[#lines + 1] = "manual_card_position_enabled: " .. diag_bool(manual_enabled)
    lines[#lines + 1] = "manual_card_dragging: " .. diag_bool(dragging)
    lines[#lines + 1] = "active_x: " .. diag_value(snapshot.active_x)
    lines[#lines + 1] = "active_y: " .. diag_value(snapshot.active_y)
    lines[#lines + 1] = "marker_top_y: " .. diag_value(snapshot.marker_top_y)
    lines[#lines + 1] = "line_h: " .. diag_value(snapshot.line_h)
    lines[#lines + 1] = "body_window_x: " .. diag_value(snapshot.body_window_x)
    lines[#lines + 1] = "body_window_y: " .. diag_value(snapshot.body_window_y)
    lines[#lines + 1] = "body_window_w: " .. diag_value(snapshot.body_window_w)
    lines[#lines + 1] = "body_window_h: " .. diag_value(snapshot.body_window_h)
    lines[#lines + 1] = "card_w: " .. diag_value(snapshot.card_w)
    lines[#lines + 1] = "card_h: " .. diag_value(snapshot.card_h)
    lines[#lines + 1] = "desired_text_w_before_safety: " .. diag_value(snapshot.desired_text_w_before_safety)
    lines[#lines + 1] = "text_width_safety_x: " .. diag_value(snapshot.text_width_safety_x)
    lines[#lines + 1] = "desired_text_w_after_safety: " .. diag_value(snapshot.desired_text_w_after_safety)
    lines[#lines + 1] = "base_wrap_w: " .. diag_value(snapshot.base_wrap_w)
    lines[#lines + 1] = "estimated_wrap_w: " .. diag_value(snapshot.estimated_wrap_w)
    lines[#lines + 1] = "child_w: " .. diag_value(snapshot.child_w)
    lines[#lines + 1] = "target_x: " .. diag_value(snapshot.target_x)
    lines[#lines + 1] = "target_y: " .. diag_value(snapshot.target_y)
    lines[#lines + 1] = "card_x: " .. diag_value(snapshot.card_x)
    lines[#lines + 1] = "card_y: " .. diag_value(snapshot.card_y)
    lines[#lines + 1] = "card_x2: " .. diag_value(snapshot.card_x2)
    lines[#lines + 1] = "card_y2: " .. diag_value(snapshot.card_y2)
    lines[#lines + 1] = "scroll_y: " .. diag_value(snapshot.scroll_y)
    lines[#lines + 1] = "selected_candidate_this_frame: " .. selected_s
    lines[#lines + 1] = "selected_candidate_previous_frame: " .. tostring(snapshot.selected_candidate_previous_frame or "nil")
    lines[#lines + 1] = "selected_candidate_changed: " .. diag_bool(snapshot.selected_candidate_changed)
    lines[#lines + 1] = "locked_candidate: " .. locked_candidate_s
    lines[#lines + 1] = "locked_candidate_id: " .. locked_candidate_id_s
    lines[#lines + 1] = "candidate_lock_used: " .. diag_bool(candidate_lock_used)
    lines[#lines + 1] = "candidate_lock_initialized: " .. diag_bool(candidate_lock_initialized)
    lines[#lines + 1] = "candidate_lock_close_condition: " .. diag_bool(candidate_lock_close_condition)
    lines[#lines + 1] = "keep_inside_body_x: " .. diag_bool(keep_inside_body_x)
    lines[#lines + 1] = "body_edge_margin_x: " .. diag_value(body_edge_margin_x)
    lines[#lines + 1] = "body_vertical_scrollbar_visible: " .. diag_bool(body_vertical_scrollbar_visible)
    lines[#lines + 1] = "body_scrollbar_reserved_w: " .. diag_value(body_scrollbar_reserved_w)
    lines[#lines + 1] = "hard_x1: " .. diag_value(hard_x1)
    lines[#lines + 1] = "hard_x2: " .. diag_value(hard_x2)
    lines[#lines + 1] = "available_body_card_w: " .. diag_value(available_body_card_w)
    lines[#lines + 1] = "horizontal_adjusted: " .. diag_bool(horizontal_adjusted)
    lines[#lines + 1] = "no_fit_close_condition: " .. diag_bool(no_fit)
    lines[#lines + 1] = "clear_active_comment_card_state_requested: " .. diag_bool(close_requested)
    lines[#lines + 1] = "marker_geometry_unavailable: " .. diag_bool(marker_unavailable)
    lines[#lines + 1] = "candidate list:"

    if type(snapshot.candidate_rows) == "table" and #snapshot.candidate_rows > 0 then
      for _, row in ipairs(snapshot.candidate_rows) do
        lines[#lines + 1] = string.format(
          "  %s: raw_x=%s adjusted_x=%s y=%s fit=%s fail=%s horizontal_adjusted=%s final_left_fit=%s final_right_fit=%s",
          tostring(row.name or "nil"),
          diag_value(row.raw_x),
          diag_value(row.adjusted_x),
          diag_value(row.y),
          diag_bool(row.fits),
          tostring(row.failures or "none"),
          diag_bool(row.horizontal_adjusted),
          diag_bool(row.final_left_fits),
          diag_bool(row.final_right_fits)
        )
      end
    else
      lines[#lines + 1] = "  none / manual mode or missing body metrics"
    end

    if not comments.diag_console_cleared_once then
      if reaper.ClearConsole then reaper.ClearConsole() end
      comments.diag_console_cleared_once = true
    end

    reaper.ShowConsoleMsg(table.concat(lines, "\n") .. "\n\n")

    comments.diag_console_last_signature = signature
    comments.diag_console_last_active_id = active_id_s
    comments.diag_console_last_manual_enabled = manual_enabled
    comments.diag_console_last_dragging = dragging
    comments.diag_console_has_printed = true
  end

  local active_x = tonumber(args.active_x)
  local active_y = tonumber(args.active_y)
  if not active_x or not active_y then
    emit_comment_card_diag_console("marker_geometry_unavailable", {
      active_id = args.active_id or args.comments.active_id,
      manual_card_position_enabled = args.comments.manual_card_position_enabled == true,
      manual_card_dragging = args.comments.manual_card_dragging == true,
      active_x = args.active_x,
      active_y = args.active_y,
      marker_geometry_unavailable = true,
      locked_candidate = args.comments.active_card_locked_candidate,
      locked_candidate_id = args.comments.active_card_locked_candidate_id,
      candidate_lock_used = args.comments.active_card_locked_candidate ~= nil,
      clear_active_comment_card_state_requested = false,
    })
    return false
  end

  -- Единая локальная очистка active-card state для реального закрытия.
  -- Используется в том числе при уходе карточки полностью за body viewport:
  -- после такого close прокрутка назад не должна автоматически открыть карточку снова.
  local function clear_active_comment_card_state()
    args.comments.active_id = nil
    args.comments.active_label = nil
    args.comments.active_x = nil
    args.comments.active_y = nil
    args.comments.active_group_key = nil
    args.comments.active_group_comment_ids = nil
    args.comments.active_marker_visible = nil
    args.comments.active_marker_geometry_available = nil
    args.comments.card_scroll_y = nil
    args.comments.card_scroll_max_y = nil
    args.comments.card_x = nil
    args.comments.card_y = nil
    args.comments.card_x2 = nil
    args.comments.card_y2 = nil
    args.comments.manual_card_position_enabled = nil
    args.comments.manual_card_x = nil
    args.comments.manual_card_y = nil
    args.comments.manual_card_dragging = nil
    args.comments.manual_card_drag_start_mouse_x = nil
    args.comments.manual_card_drag_start_mouse_y = nil
    args.comments.manual_card_drag_start_card_x = nil
    args.comments.manual_card_drag_start_card_y = nil
    args.comments.active_card_locked_candidate = nil
    args.comments.active_card_locked_candidate_id = nil
    if type(PSV_COMMENT_CARD_RENDERER) == "table" then
      PSV_COMMENT_CARD_RENDERER.pending_args = nil
    end
  end

  local ctx = args.ctx

  -- Alpha для card UI clamp-ится локально: settings остаются простыми числами,
  -- но случайное значение ниже 0 или выше 255 не создаёт непредсказуемый цвет.
  local function comment_card_clamp_alpha(a)
    a = tonumber(a) or 255
    if a < 0 then return 0 end
    if a > 255 then return 255 end
    return a
  end

  -- У карточки один основной translucent background layer: outer window.
  -- Inner child по умолчанию прозрачный, чтобы alpha не наслаивался дважды.
  local card_bg_alpha = comment_card_clamp_alpha(UI_COMMENT_CARD_BG_ALPHA)
  local outer_bg_col = rgba(UI_COMMENT_CARD_OUTER_BG_RGBA[1], UI_COMMENT_CARD_OUTER_BG_RGBA[2], UI_COMMENT_CARD_OUTER_BG_RGBA[3], card_bg_alpha)
  local inner_bg_col = rgba(UI_COMMENT_CARD_INNER_BG_RGBA[1], UI_COMMENT_CARD_INNER_BG_RGBA[2], UI_COMMENT_CARD_INNER_BG_RGBA[3], comment_card_clamp_alpha(UI_COMMENT_CARD_INNER_BG_RGBA[4]))
  local border_col = rgba(UI_COMMENT_CARD_BORDER_RGBA[1], UI_COMMENT_CARD_BORDER_RGBA[2], UI_COMMENT_CARD_BORDER_RGBA[3], comment_card_clamp_alpha(UI_COMMENT_CARD_BORDER_RGBA[4]))

  -- v2.0.76: keep the native card window identity tied to the current
  -- active comment. This tests whether a constant ImGui window/child ID can
  -- leave stale native visual state when switching between active comments.
  local active_id = args.active_id
  if active_id == nil and type(args.comments) == "table" then
    active_id = args.comments.active_id
  end
  local safe_active_id = tostring(active_id or "none"):gsub("[^%w_%-%.]", "_")
  if safe_active_id == "" then safe_active_id = "none" end
  local overlay_window_id = "##psv_comment_card_imgui_overlay_" .. safe_active_id
  local inner_child_id = "##psv_comment_card_inner_" .. safe_active_id
  PSV_COMMENT_CARD_RENDERER.last_active_id = active_id
  PSV_COMMENT_CARD_RENDERER.last_overlay_window_id = overlay_window_id
  PSV_COMMENT_CARD_RENDERER.last_inner_child_id = inner_child_id

  -- Experimental overlay card only: TextWrapped handles ordinary word wrapping,
  -- but long uninterrupted ASCII-like chunks can still overflow the card.
  -- Keep UTF-8 words intact: only split ASCII tokens such as hashes, paths,
  -- technical strings, or URLs that survived the existing URL-removal pass.
  local function wrap_ascii_long_chunks_for_display(text, max_w)
    text = tostring(text or "")
    max_w = tonumber(max_w) or 0
    if text == "" or max_w <= 20 then return text end

    local function token_is_ascii(token)
      for i = 1, #token do
        if token:byte(i) > 127 then return false end
      end
      return true
    end

    local function split_token(token)
      if token == "" or not token_is_ascii(token) then return token end
      if select(1, reaper.ImGui_CalcTextSize(ctx, token)) <= max_w then return token end

      local parts = {}
      local line = ""
      for i = 1, #token do
        local ch = token:sub(i, i)
        local candidate = line .. ch
        if line ~= "" and select(1, reaper.ImGui_CalcTextSize(ctx, candidate)) > max_w then
          parts[#parts + 1] = line
          line = ch
        else
          line = candidate
        end
      end
      if line ~= "" then parts[#parts + 1] = line end
      return table.concat(parts, "\n")
    end

    return (text:gsub("%S+", split_token))
  end

  local function format_comment_card_date(raw_date)
    if raw_date == nil then return nil end
    local s = trim(tostring(raw_date))
    if s == "" then return nil end

    local y, m, d, hh, mm = s:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)[T%s](%d%d):(%d%d)")
    if y then
      return d .. "." .. m .. "." .. y .. " · " .. hh .. ":" .. mm
    end

    y, m, d = s:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)$")
    if y then
      return d .. "." .. m .. "." .. y
    end

    return s
  end

  -- Minimal safety contract for future manual activation.
  -- Keep this source-backed and parallel to the accepted legacy Escape pattern.
  -- Return true after clearing state so the legacy branch is not also executed
  -- in the same frame when the experimental renderer is explicitly active.
  if escape_key_owner == "comment"
     and reaper.ImGui_IsKeyPressed
     and reaper.ImGui_Key_Escape
     and reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Escape(), false) then
    clear_active_comment_card_state()
    return true
  end

  -- Читаем все UI_COMMENT_CARD_* в локальные значения кадра: так ниже проще
  -- видеть, какие настройки участвуют в measurement, layout и rendering.
  local line_h = reaper.ImGui_GetTextLineHeightWithSpacing(ctx)
  local card_min_w = UI_COMMENT_CARD_MIN_W
  local card_max_w = UI_COMMENT_CARD_MAX_W
  local content_min_h = UI_COMMENT_CARD_INNER_CHILD_MIN_H
  local content_max_h = UI_COMMENT_CARD_INNER_CHILD_MAX_H
  local window_pad_x = UI_COMMENT_CARD_OUTER_PAD_X
  local window_pad_y = UI_COMMENT_CARD_OUTER_PAD_Y
  local child_pad_x = UI_COMMENT_CARD_INNER_PAD_X
  local child_pad_y = UI_COMMENT_CARD_INNER_PAD_Y
  local item_spacing_x = UI_COMMENT_CARD_ITEM_SPACING_X
  local item_spacing_y = UI_COMMENT_CARD_ITEM_SPACING_Y
  local metadata_gap_y = math.max(1, math.floor((tonumber(item_spacing_y) or 0) * 0.5))
  local metadata_col = rgba(
    UI_COMMENT_CARD_TEXT_RGBA[1],
    UI_COMMENT_CARD_TEXT_RGBA[2],
    UI_COMMENT_CARD_TEXT_RGBA[3],
    math.min(comment_card_clamp_alpha(UI_COMMENT_CARD_TEXT_RGBA[4]), 195)
  )
  local link_gap_y = UI_COMMENT_CARD_LINK_GAP_Y
  local separator_gap_y = UI_COMMENT_CARD_SEPARATOR_GAP_Y
  local separator_line_h = UI_COMMENT_CARD_SEPARATOR_LINE_H
  local scrollbar_size = UI_COMMENT_CARD_SCROLLBAR_SIZE
  local estimated_scrollbar_w = UI_COMMENT_CARD_SCROLLBAR_RESERVED_W
  local desired_text_w = 0
  local prepared_blocks = {}

  -- Подготавливаем display-only данные: measurement и rendering должны видеть
  -- один и тот же текст без URL, не мутируя parser/comment data.
  for _, block in ipairs(args.comment_blocks) do
    local text = "No comment text found."
    local urls = {}
    if type(block) == "table" then
      text = trim(tostring(block.text or ""))
      urls = block.urls
      if type(urls) ~= "table" then
        urls = comment_url.extract_plain_urls(text)
      end
      text = trim(comment_url.remove_urls_from_display_text(text, urls))
      if text == "" and #urls == 0 then text = "No comment text found." end
    end

    local id = nil
    local author = nil
    local date = nil
    local display_date = nil
    local label = nil
    local meta_header = nil
    if type(block) == "table" then
      id = block.id
      label = block.label
      if block.author ~= nil then
        author = trim(tostring(block.author))
        if author == "" then author = nil end
      end
      if block.date ~= nil then
        date = trim(tostring(block.date))
        if date == "" then date = nil end
      end
    end

    display_date = format_comment_card_date(date)

    if author and display_date then
      meta_header = author .. " · " .. display_date
    elseif author then
      meta_header = author
    elseif display_date then
      meta_header = display_date
    end

    prepared_blocks[#prepared_blocks + 1] = {
      id = id,
      label = label,
      author = author,
      date = date,
      display_date = display_date,
      meta_header = meta_header,
      text = text,
      urls = urls,
    }

    if meta_header and meta_header ~= "" then
      local w = select(1, reaper.ImGui_CalcTextSize(ctx, meta_header))
      if w > desired_text_w then desired_text_w = w end
    end

    if text ~= "" then
      for line in (text .. "\n"):gmatch("(.-)\n") do
        if line ~= "" then
          local w = select(1, reaper.ImGui_CalcTextSize(ctx, line))
          if w > desired_text_w then desired_text_w = w end
        end
      end
    end

    for _, url in ipairs(urls) do
      local w = select(1, reaper.ImGui_CalcTextSize(ctx, tostring(url or "")))
      if w > desired_text_w then desired_text_w = w end
    end
  end

  local desired_text_w_before_safety = desired_text_w
  local text_width_safety_x = tonumber(UI_COMMENT_CARD_TEXT_WIDTH_SAFETY_X) or 0
  if text_width_safety_x < 0 then text_width_safety_x = 0 end
  local height_safety_y = tonumber(UI_COMMENT_CARD_HEIGHT_SAFETY_Y) or 0
  if height_safety_y < 0 then height_safety_y = 0 end

  -- Safety применяется только к measurement width: это небольшой запас для
  -- TextWrapped/child content, а не новый padding, min width или placement offset.
  desired_text_w = desired_text_w + text_width_safety_x
  local desired_text_w_after_safety = desired_text_w

  if desired_text_w > card_max_w - (window_pad_x * 2) - (child_pad_x * 2) then
    desired_text_w = card_max_w - (window_pad_x * 2) - (child_pad_x * 2)
  end

  local card_w = desired_text_w + (window_pad_x * 2) + (child_pad_x * 2)
  if card_w < card_min_w then card_w = card_min_w end
  if card_w > card_max_w then card_w = card_max_w end

  -- Сначала считаем wrap без scrollbar reserve. Это принципиально для коротких
  -- комментариев: если текст визуально помещается в одну строку без scrollbar,
  -- measurement не должен заранее сужать строку и получать ложные две строки.
  local base_wrap_w = card_w - (window_pad_x * 2) - (child_pad_x * 2)
  if base_wrap_w < 20 then base_wrap_w = 20 end

  local function estimate_text_height(text, max_w)
    text = tostring(text or "")
    if text == "" then return 0 end

    local h = 0
    for line in (text .. "\n"):gmatch("(.-)\n") do
      if line == "" then
        h = h + line_h
      else
        local w = select(1, reaper.ImGui_CalcTextSize(ctx, line))
        local n = math.ceil(w / max_w)
        if n < 1 then n = 1 end
        h = h + n * line_h
      end
    end
    return h
  end

  local function measure_comment_content(max_w)
    local h = 0
    for i, block in ipairs(prepared_blocks) do
      block.wrapped_text = wrap_ascii_long_chunks_for_display(block.text, max_w)

      if block.meta_header and block.meta_header ~= "" then
        h = h + line_h
        if block.wrapped_text ~= "" or #block.urls > 0 then
          h = h + metadata_gap_y
        end
      end

      if block.wrapped_text ~= "" then
        h = h + estimate_text_height(block.wrapped_text, max_w)
      end

      if #block.urls > 0 then
        if block.wrapped_text ~= "" then
          h = h + link_gap_y
        end
        h = h + (#block.urls * line_h)
      end

      if i < #prepared_blocks then
        h = h + (separator_gap_y * 2) + separator_line_h
      end
    end
    return h
  end

  local estimated_wrap_w = base_wrap_w
  local content_h = measure_comment_content(estimated_wrap_w)
  local child_content_h = content_h + (child_pad_y * 2) + height_safety_y
  local child_h = child_content_h
  if child_h < content_min_h then child_h = content_min_h end
  if child_h > content_max_h then child_h = content_max_h end

  -- Scrollbar reserve подключается только после первого расчёта без reserve.
  -- Если контент уже помещается в MAX_H, короткая карточка остаётся compact и
  -- не получает ложную высоту от преждевременно суженного wrap width.
  local needs_scroll = child_content_h > child_h + 0.5
  if needs_scroll then
    estimated_wrap_w = base_wrap_w - estimated_scrollbar_w
    if estimated_wrap_w < 20 then estimated_wrap_w = 20 end
    content_h = measure_comment_content(estimated_wrap_w)
    child_content_h = content_h + (child_pad_y * 2) + height_safety_y
    child_h = child_content_h
    if child_h < content_min_h then child_h = content_min_h end
    if child_h > content_max_h then child_h = content_max_h end
    needs_scroll = child_content_h > child_h + 0.5
  end

  -- Высота overlay выводится только из высоты text-child и outer padding;
  -- header удалён, поэтому line_h/header gap больше не резервируются.
  local card_h = child_h + (window_pad_y * 2)

  -- Diagnostic-only state for observing placement/candidate behavior.
  -- Эти переменные только собирают данные текущего кадра и не управляют placement.
  local diag_candidate_rows = {}
  local diag_selected_candidate = nil
  local diag_previous_candidate = args.comments.diag_previous_selected_candidate
  local diag_candidate_changed = false
  local diag_no_fit_close_requested = false
  local diag_clear_requested_this_frame = false
  local diag_marker_geometry_unavailable = false
  local diag_scroll_y = args.body_scroll_y or args.scroll_y or args.current_body_scroll_y
  local diag_candidate_lock_used = false
  local diag_candidate_lock_initialized = false
  local diag_candidate_lock_close_condition = false
  local diag_locked_candidate = args.comments.active_card_locked_candidate
  local diag_locked_candidate_id = args.comments.active_card_locked_candidate_id
  local diag_child_w = nil
  local diag_keep_inside_body_x = UI_COMMENT_CARD_KEEP_INSIDE_BODY_X == true
  local diag_body_edge_margin_x = tonumber(UI_COMMENT_CARD_BODY_EDGE_MARGIN_X) or 0
  if diag_body_edge_margin_x < 0 then diag_body_edge_margin_x = 0 end
  local diag_body_vertical_scrollbar_visible = args.body_vertical_scrollbar_visible == true
  local diag_body_scrollbar_reserved_w = 0
  if diag_body_vertical_scrollbar_visible then
    diag_body_scrollbar_reserved_w = tonumber(args.body_vertical_scrollbar_reserved_w) or 0
    if diag_body_scrollbar_reserved_w < 0 then diag_body_scrollbar_reserved_w = 0 end
  end
  local diag_hard_x1 = nil
  local diag_hard_x2 = nil
  local diag_available_body_card_w = nil
  local diag_horizontal_adjusted = false

  -- Позиционируем карточку относительно marker.
  -- Primary candidate сохраняет прежнее поведение: above-right от marker.
  -- v3.0.20: после первого выбора anchored-карточка больше не переходит
  -- на следующий fallback candidate во время scroll. Блокируется только имя
  -- candidate; координаты каждый кадр пересчитываются от свежей геометрии marker.
  local marker_top_y = active_y - line_h
  local target_x = active_x + UI_COMMENT_CARD_OPEN_OFFSET_X
  local target_y = marker_top_y - card_h + UI_COMMENT_CARD_OPEN_OFFSET_Y

  -- Draggable state: before the user drags, the card stays marker-anchored.
  -- After dragging, manual_card_position_enabled freezes the card at the
  -- user-selected screen position and body scrolling no longer moves it.
  local manual_position_enabled = args.comments.manual_card_position_enabled == true
  if manual_position_enabled then
    -- Manual mode полностью обходит anchored candidate lock. Старый anchored
    -- lock чистится, чтобы он не вернулся как stale state после reset/close.
    args.comments.active_card_locked_candidate = nil
    args.comments.active_card_locked_candidate_id = nil
    diag_locked_candidate = nil
    diag_locked_candidate_id = nil

    local manual_x = tonumber(args.comments.manual_card_x)
    local manual_y = tonumber(args.comments.manual_card_y)
    if manual_x and manual_y then
      target_x = manual_x
      target_y = manual_y
    else
      args.comments.manual_card_position_enabled = nil
      args.comments.active_card_locked_candidate = nil
      args.comments.active_card_locked_candidate_id = nil
      manual_position_enabled = false
    end
  end

  local body_x = tonumber(args.body_window_x)
  local body_y = tonumber(args.body_window_y)
  local body_w = tonumber(args.body_window_w)
  local body_h = tonumber(args.body_window_h)

  -- Anchored edge-placement fallback.
  -- Manual mode bypasses this completely: dragged cards keep their explicit
  -- screen-space manual_card_x/manual_card_y and are not auto-flipped.
  local anchored_candidate_fits = true
  if manual_position_enabled then
    diag_selected_candidate = "manual"
  end
  if not manual_position_enabled and body_x and body_y and body_w and body_h and body_w > 0 and body_h > 0 then
    local fit_margin = tonumber(UI_COMMENT_CARD_BODY_CLAMP_MARGIN) or 0
    local body_x1 = body_x + fit_margin
    local body_y1 = body_y + fit_margin
    local body_x2 = body_x + body_w - fit_margin
    local body_y2 = body_y + body_h - fit_margin

    local hard_edge_margin_x = diag_body_edge_margin_x
    local hard_x1 = body_x + hard_edge_margin_x
    local hard_x2 = body_x + body_w - hard_edge_margin_x - diag_body_scrollbar_reserved_w
    if hard_x2 < hard_x1 then hard_x2 = hard_x1 end
    local hard_w = hard_x2 - hard_x1
    diag_hard_x1 = hard_x1
    diag_hard_x2 = hard_x2
    diag_available_body_card_w = hard_w

    local candidate_status_by_name = {}

    local function candidate_status(name, raw_x, y)
      -- Candidate identity remains raw/semantic (above-right, above-left, etc.).
      -- Only the final displayed X may be adjusted inside the visible body/window.
      local adjusted_x = raw_x
      if diag_keep_inside_body_x then
        if adjusted_x + card_w > hard_x2 then
          adjusted_x = hard_x2 - card_w
        end
        if adjusted_x < hard_x1 then
          adjusted_x = hard_x1
        end
      end

      local horizontal_adjusted = math.abs(adjusted_x - raw_x) > 0.5
      local final_left_fits = adjusted_x >= hard_x1
      local final_right_fits = adjusted_x + card_w <= hard_x2
      local horizontal_fits = card_w <= hard_w + 0.5 and final_left_fits and final_right_fits
      local vertical_fits = (y >= body_y1) and (y + card_h <= body_y2)

      local failures = {}
      if not final_left_fits then failures[#failures + 1] = "left" end
      if y < body_y1 then failures[#failures + 1] = "top" end
      if not final_right_fits then failures[#failures + 1] = "right" end
      if y + card_h > body_y2 then failures[#failures + 1] = "bottom" end
      if card_w > hard_w + 0.5 then failures[#failures + 1] = "too-wide" end

      local fits = vertical_fits and horizontal_fits

      local row = {
        name = name,
        raw_x = raw_x,
        adjusted_x = adjusted_x,
        x = adjusted_x,
        y = y,
        fits = fits,
        failures = (#failures > 0) and table.concat(failures, ",") or "none",
        horizontal_adjusted = horizontal_adjusted,
        final_left_fits = final_left_fits,
        final_right_fits = final_right_fits,
      }
      candidate_status_by_name[name] = row
      diag_candidate_rows[#diag_candidate_rows + 1] = row
      return row
    end

    local candidates = {
      -- 1) above-right: current/default behavior.
      { "above-right",
        active_x + UI_COMMENT_CARD_OPEN_OFFSET_X,
        marker_top_y - card_h + UI_COMMENT_CARD_OPEN_OFFSET_Y },
      -- 2) above-left.
      { "above-left",
        active_x - card_w - UI_COMMENT_CARD_OPEN_OFFSET_X,
        marker_top_y - card_h + UI_COMMENT_CARD_OPEN_OFFSET_Y },
      -- 3) below-right.
      { "below-right",
        active_x + UI_COMMENT_CARD_OPEN_OFFSET_X,
        marker_top_y + line_h + UI_COMMENT_CARD_OPEN_OFFSET_Y },
      -- 4) below-left.
      { "below-left",
        active_x - card_w - UI_COMMENT_CARD_OPEN_OFFSET_X,
        marker_top_y + line_h + UI_COMMENT_CARD_OPEN_OFFSET_Y },
    }

    for _, candidate in ipairs(candidates) do
      candidate_status(candidate[1], candidate[2], candidate[3])
    end

    local locked_candidate = args.comments.active_card_locked_candidate
    local locked_candidate_id = args.comments.active_card_locked_candidate_id
    local has_locked_candidate = locked_candidate ~= nil and locked_candidate_id == active_id

    anchored_candidate_fits = false

    if has_locked_candidate then
      -- Already-open anchored card: keep the original candidate identity,
      -- recompute only its current marker-relative x/y, and close if it fails.
      diag_candidate_lock_used = true
      diag_selected_candidate = locked_candidate
      local locked_row = candidate_status_by_name[locked_candidate]
      if locked_row then
        target_x = locked_row.x
        target_y = locked_row.y
        anchored_candidate_fits = locked_row.fits == true
        diag_horizontal_adjusted = locked_row.horizontal_adjusted == true
        if not anchored_candidate_fits then
          diag_candidate_lock_close_condition = true
        end
      else
        -- Defensive path for impossible stale names: do not silently fallback.
        -- Treat as non-fitting locked state so the normal close path runs.
        diag_candidate_lock_close_condition = true
      end
    else
      -- Initial open / marker switch: preserve v2.0.108 fallback order and
      -- store only the first fitting candidate name for subsequent frames.
      for _, candidate in ipairs(candidates) do
        local candidate_name = candidate[1]
        local status = candidate_status_by_name[candidate_name]
        if status and status.fits and not anchored_candidate_fits then
          target_x = status.x
          target_y = status.y
          diag_selected_candidate = candidate_name
          diag_horizontal_adjusted = status.horizontal_adjusted == true
          anchored_candidate_fits = true
        end
      end

      if anchored_candidate_fits and diag_selected_candidate then
        args.comments.active_card_locked_candidate = diag_selected_candidate
        args.comments.active_card_locked_candidate_id = active_id
        diag_locked_candidate = args.comments.active_card_locked_candidate
        diag_locked_candidate_id = args.comments.active_card_locked_candidate_id
        diag_candidate_lock_initialized = true
      end
    end
  elseif not manual_position_enabled then
    diag_selected_candidate = "anchored-primary/no-body-metrics"
  end

  diag_selected_candidate = diag_selected_candidate or "none"
  diag_candidate_changed = diag_previous_candidate ~= nil and diag_previous_candidate ~= diag_selected_candidate
  args.comments.diag_previous_selected_candidate = diag_selected_candidate

  -- Prototype bounds state for outside-click/offscreen-close passes.
  -- Written from the selected anchored candidate or from manual screen-space position.
  args.comments.card_x = target_x
  args.comments.card_y = target_y
  args.comments.card_x2 = target_x + card_w
  args.comments.card_y2 = target_y + card_h

  local function emit_current_comment_card_diag_console(close_requested)
    emit_comment_card_diag_console(nil, {
      active_id = active_id,
      manual_card_position_enabled = args.comments.manual_card_position_enabled == true,
      manual_card_dragging = args.comments.manual_card_dragging == true,
      active_x = active_x,
      active_y = active_y,
      marker_top_y = marker_top_y,
      line_h = line_h,
      body_window_x = body_x,
      body_window_y = body_y,
      body_window_w = body_w,
      body_window_h = body_h,
      card_w = card_w,
      card_h = card_h,
      desired_text_w_before_safety = desired_text_w_before_safety,
      text_width_safety_x = text_width_safety_x,
      desired_text_w_after_safety = desired_text_w_after_safety,
      base_wrap_w = base_wrap_w,
      estimated_wrap_w = estimated_wrap_w,
      child_w = diag_child_w,
      target_x = target_x,
      target_y = target_y,
      card_x = args.comments.card_x,
      card_y = args.comments.card_y,
      card_x2 = args.comments.card_x2,
      card_y2 = args.comments.card_y2,
      scroll_y = diag_scroll_y,
      selected_candidate_this_frame = diag_selected_candidate,
      selected_candidate_previous_frame = diag_previous_candidate,
      selected_candidate_changed = diag_candidate_changed,
      locked_candidate = diag_locked_candidate,
      locked_candidate_id = diag_locked_candidate_id,
      candidate_lock_used = diag_candidate_lock_used,
      candidate_lock_initialized = diag_candidate_lock_initialized,
      candidate_lock_close_condition = diag_candidate_lock_close_condition,
      keep_inside_body_x = diag_keep_inside_body_x,
      body_edge_margin_x = diag_body_edge_margin_x,
      body_vertical_scrollbar_visible = diag_body_vertical_scrollbar_visible,
      body_scrollbar_reserved_w = diag_body_scrollbar_reserved_w,
      hard_x1 = diag_hard_x1,
      hard_x2 = diag_hard_x2,
      available_body_card_w = diag_available_body_card_w,
      horizontal_adjusted = diag_horizontal_adjusted,
      no_fit_close_condition = diag_no_fit_close_requested,
      clear_active_comment_card_state_requested = close_requested == true or diag_clear_requested_this_frame,
      marker_geometry_unavailable = diag_marker_geometry_unavailable,
      candidate_rows = diag_candidate_rows,
    })
  end

  if not manual_position_enabled and body_x and body_y and body_w and body_h and body_w > 0 and body_h > 0 then
    if not anchored_candidate_fits then
      -- Native overlay рисуется sibling-окном после ##body и не клипуется
      -- body viewport-ом. Если ни один anchored candidate не помещается,
      -- сохраняем прежний real-close policy вместо вывода карточки за body.
      diag_no_fit_close_requested = true
      diag_clear_requested_this_frame = true
      emit_current_comment_card_diag_console(true)
      clear_active_comment_card_state()
      return true
    end
  end

  -- Minimal experimental outside-click close contract.
  -- Keep this manual/screen-space and do not depend on native focus loss:
  -- the overlay is currently a prototype no-decoration window.
  if args.mouse_clicked and not args.comment_marker_clicked then
    local mouse_x = tonumber(args.mouse_x)
    local mouse_y = tonumber(args.mouse_y)
    if mouse_x and mouse_y then
      local outside_card = mouse_x < args.comments.card_x
        or mouse_x > args.comments.card_x2
        or mouse_y < args.comments.card_y
        or mouse_y > args.comments.card_y2
      if outside_card then
        diag_clear_requested_this_frame = true
        emit_current_comment_card_diag_console(true)
        clear_active_comment_card_state()
        return true
      end
    end
  end

  local window_flags = reaper.ImGui_WindowFlags_NoDecoration()
    | reaper.ImGui_WindowFlags_NoDocking()
    | reaper.ImGui_WindowFlags_NoSavedSettings()
    | reaper.ImGui_WindowFlags_NoCollapse()
    | reaper.ImGui_WindowFlags_NoFocusOnAppearing()
    | reaper.ImGui_WindowFlags_NoNav()

  reaper.ImGui_SetNextWindowPos(ctx, target_x, target_y, reaper.ImGui_Cond_Always())
  reaper.ImGui_SetNextWindowSize(ctx, card_w, card_h, reaper.ImGui_Cond_Always())

  -- Применяем scoped стиль внешнего overlay window: фон совпадает с телом карточки,
  -- padding/rounding/text/separators остаются локальными. Native border отключён ниже,
  -- потому что видимая обводка рисуется явно через drawlist и слушает UI settings.
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_WindowBg(), outer_bg_col)
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ChildBg(), inner_bg_col)
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Border(), border_col)
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), rgba(UI_COMMENT_CARD_TEXT_RGBA[1], UI_COMMENT_CARD_TEXT_RGBA[2], UI_COMMENT_CARD_TEXT_RGBA[3], UI_COMMENT_CARD_TEXT_RGBA[4]))
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Separator(), rgba(UI_COMMENT_CARD_SEPARATOR_RGBA[1], UI_COMMENT_CARD_SEPARATOR_RGBA[2], UI_COMMENT_CARD_SEPARATOR_RGBA[3], UI_COMMENT_CARD_SEPARATOR_RGBA[4]))
  reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_WindowRounding(), UI_COMMENT_CARD_CORNER_ROUNDING)
  reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_WindowBorderSize(), 0.0)
  reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_WindowPadding(), window_pad_x, window_pad_y)
  reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_ItemSpacing(), item_spacing_x, item_spacing_y)

  local visible = reaper.ImGui_Begin(ctx, overlay_window_id, true, window_flags)
  if not visible then
    reaper.ImGui_PopStyleVar(ctx, 4)
    reaper.ImGui_PopStyleColor(ctx, 5)
    return false
  end

  -- Manual drag mode: click-dragging the native overlay stores a screen-space
  -- card position on paragraphs.comments. Once manual mode is enabled, marker
  -- scrolling no longer changes target_x/target_y until the card is really closed.
  local mouse_now_x, mouse_now_y = reaper.ImGui_GetMousePos(ctx)
  local card_hovered = reaper.ImGui_IsWindowHovered(ctx, reaper.ImGui_HoveredFlags_RootAndChildWindows())
  if card_hovered and reaper.ImGui_IsMouseClicked(ctx, reaper.ImGui_MouseButton_Left(), false) then
    args.comments.manual_card_dragging = true
    args.comments.manual_card_drag_start_mouse_x = mouse_now_x
    args.comments.manual_card_drag_start_mouse_y = mouse_now_y
    args.comments.manual_card_drag_start_card_x = target_x
    args.comments.manual_card_drag_start_card_y = target_y
  end

  if args.comments.manual_card_dragging then
    if reaper.ImGui_IsMouseDown(ctx, reaper.ImGui_MouseButton_Left()) then
      local start_mouse_x = tonumber(args.comments.manual_card_drag_start_mouse_x) or mouse_now_x
      local start_mouse_y = tonumber(args.comments.manual_card_drag_start_mouse_y) or mouse_now_y
      local start_card_x = tonumber(args.comments.manual_card_drag_start_card_x) or target_x
      local start_card_y = tonumber(args.comments.manual_card_drag_start_card_y) or target_y
      local dx = mouse_now_x - start_mouse_x
      local dy = mouse_now_y - start_mouse_y
      if math.abs(dx) > 1 or math.abs(dy) > 1 then
        args.comments.manual_card_position_enabled = true
        args.comments.active_card_locked_candidate = nil
        args.comments.active_card_locked_candidate_id = nil
        diag_locked_candidate = nil
        diag_locked_candidate_id = nil
        diag_candidate_lock_used = false
        diag_selected_candidate = "manual"
        args.comments.manual_card_x = start_card_x + dx
        args.comments.manual_card_y = start_card_y + dy
        target_x = args.comments.manual_card_x
        target_y = args.comments.manual_card_y
        manual_position_enabled = true
        args.comments.card_x = target_x
        args.comments.card_y = target_y
        args.comments.card_x2 = target_x + card_w
        args.comments.card_y2 = target_y + card_h
      end
    else
      args.comments.manual_card_dragging = nil
      args.comments.manual_card_drag_start_mouse_x = nil
      args.comments.manual_card_drag_start_mouse_y = nil
      args.comments.manual_card_drag_start_card_x = nil
      args.comments.manual_card_drag_start_card_y = nil
    end
  end

  -- Явная drawlist-обводка карточки: так BORDER_RGBA/THICKNESS/ROUNDING
  -- гарантированно управляют видимым контуром no-decoration overlay window.
  local overlay_dl = reaper.ImGui_GetWindowDrawList(ctx)
  if overlay_dl and UI_COMMENT_CARD_BORDER_THICKNESS > 0 then
    reaper.ImGui_DrawList_AddRect(
      overlay_dl,
      target_x,
      target_y,
      target_x + card_w,
      target_y + card_h,
      border_col,
      UI_COMMENT_CARD_CORNER_ROUNDING,
      0,
      UI_COMMENT_CARD_BORDER_THICKNESS
    )
  end

  -- Inner text-child: это отдельная scrollable область для текста комментария.
  -- BeginChild(ctx, str_id, size_w, size_h, child_flags, window_flags) сохраняется.
  -- AlwaysUseWindowPadding нужен, чтобы INNER_PAD_X/Y реально влияли на inset текста
  -- даже у borderless child window.
  local child_w = select(1, reaper.ImGui_GetContentRegionAvail(ctx))
  if child_w < 40 then child_w = card_w - (window_pad_x * 2) end
  diag_child_w = child_w
  emit_current_comment_card_diag_console(false)
  local child_window_flags = needs_scroll and reaper.ImGui_WindowFlags_AlwaysVerticalScrollbar() or 0
  if UI_COMMENT_CARD_MANUAL_WHEEL_SCROLL_ENABLED then
    child_window_flags = child_window_flags | reaper.ImGui_WindowFlags_NoScrollWithMouse()
  end
  local child_flags = reaper.ImGui_ChildFlags_AlwaysUseWindowPadding()

  -- Scoped padding text-child: внешний frame остаётся узким, а текст получает
  -- настоящий внутренний отступ, управляемый UI_COMMENT_CARD_INNER_PAD_X/Y.
  reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_WindowPadding(), child_pad_x, child_pad_y)
  -- Scoped scrollbar style: ширина и цвета действуют только внутри comment child.
  reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_ScrollbarSize(), scrollbar_size)
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ScrollbarBg(), rgba(UI_COMMENT_CARD_SCROLLBAR_BG_RGBA[1], UI_COMMENT_CARD_SCROLLBAR_BG_RGBA[2], UI_COMMENT_CARD_SCROLLBAR_BG_RGBA[3], UI_COMMENT_CARD_SCROLLBAR_BG_RGBA[4]))
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ScrollbarGrab(), rgba(UI_COMMENT_CARD_SCROLLBAR_GRAB_RGBA[1], UI_COMMENT_CARD_SCROLLBAR_GRAB_RGBA[2], UI_COMMENT_CARD_SCROLLBAR_GRAB_RGBA[3], UI_COMMENT_CARD_SCROLLBAR_GRAB_RGBA[4]))
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ScrollbarGrabHovered(), rgba(UI_COMMENT_CARD_SCROLLBAR_GRAB_HOVER_RGBA[1], UI_COMMENT_CARD_SCROLLBAR_GRAB_HOVER_RGBA[2], UI_COMMENT_CARD_SCROLLBAR_GRAB_HOVER_RGBA[3], UI_COMMENT_CARD_SCROLLBAR_GRAB_HOVER_RGBA[4]))
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ScrollbarGrabActive(), rgba(UI_COMMENT_CARD_SCROLLBAR_GRAB_ACTIVE_RGBA[1], UI_COMMENT_CARD_SCROLLBAR_GRAB_ACTIVE_RGBA[2], UI_COMMENT_CARD_SCROLLBAR_GRAB_ACTIVE_RGBA[3], UI_COMMENT_CARD_SCROLLBAR_GRAB_ACTIVE_RGBA[4]))

  local child_visible = reaper.ImGui_BeginChild(ctx, inner_child_id, child_w, child_h, child_flags, child_window_flags)
  if child_visible then
    -- Ручная wheel-прокрутка только для comment-card: separate settings.
    -- На Windows native child/scrollbar hover может быть нестабилен, поэтому
    -- ownership определяется по rect-у inner child и всего видимого card overlay.
    -- Сам scroll применяется после рендера содержимого, когда ScrollMaxY уже
    -- актуален для этого кадра.
    local card_wheel_y = 0
    local child_x, child_y = reaper.ImGui_GetWindowPos(ctx)
    local child_size_w, child_size_h = reaper.ImGui_GetWindowSize(ctx)
    local wheel_mouse_x, wheel_mouse_y = reaper.ImGui_GetMousePos(ctx)
    local mouse_inside_child = wheel_mouse_x >= child_x and wheel_mouse_x <= child_x + child_size_w
      and wheel_mouse_y >= child_y and wheel_mouse_y <= child_y + child_size_h
    local mouse_inside_card = wheel_mouse_x >= target_x and wheel_mouse_x <= target_x + card_w
      and wheel_mouse_y >= target_y and wheel_mouse_y <= target_y + card_h
    local child_hovered = reaper.ImGui_IsWindowHovered(ctx, reaper.ImGui_HoveredFlags_None())

    if UI_COMMENT_CARD_MANUAL_WHEEL_SCROLL_ENABLED
       and (child_hovered or mouse_inside_child or mouse_inside_card) then
      card_wheel_y = select(1, reaper.ImGui_GetMouseWheel(ctx))
      if card_wheel_y ~= 0 then
        local max_ticks = UI_COMMENT_CARD_WHEEL_MAX_TICKS_PER_FRAME
        if card_wheel_y > max_ticks then
          card_wheel_y = max_ticks
        elseif card_wheel_y < -max_ticks then
          card_wheel_y = -max_ticks
        end
      end
    end

    local stored_card_scroll_y = tonumber(args.comments.card_scroll_y) or 0
    if stored_card_scroll_y > 0 then
      reaper.ImGui_SetScrollY(ctx, stored_card_scroll_y)
    end

    -- Рендерим компактное содержимое карточки: сразу текст, затем ссылки и separator между блоками.
    for i, block in ipairs(prepared_blocks) do
      local text = block.wrapped_text or block.text or ""
      local urls = block.urls or {}
      local meta_header = block.meta_header

      if meta_header and meta_header ~= "" then
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), metadata_col)
        reaper.ImGui_Text(ctx, meta_header)
        reaper.ImGui_PopStyleColor(ctx)
        if text ~= "" or #urls > 0 then
          reaper.ImGui_Dummy(ctx, 0, metadata_gap_y)
        end
      end

      if text ~= "" then
        local text_w = select(1, reaper.ImGui_GetContentRegionAvail(ctx))
        if text_w < 40 then text_w = card_w - (window_pad_x * 2) end
        reaper.ImGui_TextWrapped(ctx, wrap_ascii_long_chunks_for_display(text, text_w))
      end

      if #urls > 0 then
        local link_w = select(1, reaper.ImGui_GetContentRegionAvail(ctx))
        if link_w < 40 then link_w = card_w - (window_pad_x * 2) end
        if text ~= "" then reaper.ImGui_Spacing(ctx) end
        for _, url in ipairs(urls) do
          local link_text = comment_url.fit_link_text_to_width(ctx, url, link_w)
          -- Цвет ссылки scoped только на строку URL; opening path не меняем.
          reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), rgba(UI_COMMENT_CARD_LINK_RGBA[1], UI_COMMENT_CARD_LINK_RGBA[2], UI_COMMENT_CARD_LINK_RGBA[3], UI_COMMENT_CARD_LINK_RGBA[4]))
          reaper.ImGui_TextWrapped(ctx, link_text)
          reaper.ImGui_PopStyleColor(ctx)
          if reaper.ImGui_IsItemHovered(ctx, reaper.ImGui_HoveredFlags_None()) then
            if type(reaper.ImGui_SetMouseCursor) == "function"
               and type(reaper.ImGui_MouseCursor_Hand) == "function" then
              reaper.ImGui_SetMouseCursor(ctx, reaper.ImGui_MouseCursor_Hand())
            end
            if reaper.ImGui_IsItemClicked(ctx, reaper.ImGui_MouseButton_Left()) then
              open_or_copy_about_url(ctx, url)
            end
          end
        end
      end

      if i < #prepared_blocks then
        reaper.ImGui_Spacing(ctx)
        reaper.ImGui_Separator(ctx)
        reaper.ImGui_Spacing(ctx)
      end
    end

    local actual_scroll_max_y = reaper.ImGui_GetScrollMaxY(ctx)
    local actual_scroll_y = reaper.ImGui_GetScrollY(ctx)
    if actual_scroll_max_y < 0 then actual_scroll_max_y = 0 end

    if actual_scroll_max_y > 0 then
      if card_wheel_y ~= 0 and (child_hovered or mouse_inside_child or mouse_inside_card) then
        local fixed_step = line_h * UI_COMMENT_CARD_WHEEL_STEP_MULT
        actual_scroll_y = actual_scroll_y - card_wheel_y * fixed_step
        if actual_scroll_y < 0 then
          actual_scroll_y = 0
        elseif actual_scroll_y > actual_scroll_max_y then
          actual_scroll_y = actual_scroll_max_y
        end
        reaper.ImGui_SetScrollY(ctx, actual_scroll_y)
      end

      if actual_scroll_y < 0 then
        actual_scroll_y = 0
      elseif actual_scroll_y > actual_scroll_max_y then
        actual_scroll_y = actual_scroll_max_y
      end
      args.comments.card_scroll_y = actual_scroll_y
      args.comments.card_scroll_max_y = actual_scroll_max_y
    else
      -- Short/non-overflow cards must not accumulate fake scroll state.
      args.comments.card_scroll_y = 0
      args.comments.card_scroll_max_y = 0
    end
  end
  reaper.ImGui_EndChild(ctx)
  reaper.ImGui_PopStyleColor(ctx, 4)
  reaper.ImGui_PopStyleVar(ctx, 2)

  reaper.ImGui_End(ctx)
  reaper.ImGui_PopStyleVar(ctx, 4)
  reaper.ImGui_PopStyleColor(ctx, 5)
  return true
end
PSV_COMMENT_CARD_RENDERER.try_render = function(args)
  PSV_COMMENT_CARD_RENDERER.last_try_render_ok = nil
  PSV_COMMENT_CARD_RENDERER.last_try_render_result = nil
  PSV_COMMENT_CARD_RENDERER.last_try_render_error = nil
  if type(args) == "table" then
    PSV_COMMENT_CARD_RENDERER.last_active_id = args.active_id
  else
    PSV_COMMENT_CARD_RENDERER.last_active_id = nil
  end

  if PSV_COMMENT_CARD_RENDERER.mode ~= "imgui_child" then return false end
  if type(PSV_COMMENT_CARD_RENDERER.render_imgui_child_scaffold) ~= "function" then return false end

  -- Safe experimental boundary: an incomplete/failing future renderer must not
  -- blank the active comment card. Only an explicit true result skips legacy.
  local ok, result = pcall(PSV_COMMENT_CARD_RENDERER.render_imgui_child_scaffold, args)
  PSV_COMMENT_CARD_RENDERER.last_try_render_ok = ok
  PSV_COMMENT_CARD_RENDERER.last_try_render_result = result
  if not ok then
    PSV_COMMENT_CARD_RENDERER.last_try_render_error = tostring(result)
  end
  return ok and result == true
end

function render_docx_unsupported_placeholder_paragraph(ctx, para, column_start_cx, column_start_sx, column_right_sx, line_h, line_spacing, ensure_line_fits_current_page)
  if type(para) ~= "table" then return false end
  local is_system_placeholder = para.system_placeholder == true
  local is_docx_unsupported = para.docx_unsupported == true
  if not is_system_placeholder and not is_docx_unsupported then return false end

  local text = ""
  if is_system_placeholder and type(para.system_placeholder_text) == "string" then
    text = para.system_placeholder_text
  elseif type(para.docx_unsupported_placeholder) == "string" then
    text = para.docx_unsupported_placeholder
  end
  if text == "" and type(para.tokens) == "table" then
    local parts = {}
    for _, tok in ipairs(para.tokens) do
      if type(tok) == "table" then
        if tok.newline == true then
          parts[#parts + 1] = "\n"
        elseif tok.text ~= nil then
          parts[#parts + 1] = tostring(tok.text)
        end
      end
    end
    text = table.concat(parts, " "):gsub("%s+\n%s+", "\n")
  end

  text = tostring(text or ""):gsub("\r\n", "\n"):gsub("\r", "\n")
  local lines = {}
  local pos = 1
  while #lines < 2 do
    local nl = text:find("\n", pos, true)
    if nl then
      lines[#lines + 1] = text:sub(pos, nl - 1)
      pos = nl + 1
    else
      lines[#lines + 1] = text:sub(pos)
      break
    end
  end
  while #lines < 2 do
    lines[#lines + 1] = ""
  end

  line_h = math.max(1, tonumber(line_h) or 1)
  line_spacing = math.max(0, tonumber(line_spacing) or 0)
  local column_w = math.max(1, (tonumber(column_right_sx) or 0) - (tonumber(column_start_sx) or 0))
  local placeholder_col = rgba(132, 132, 132, 255)

  reaper.ImGui_SetCursorPos(ctx, column_start_cx, select(2, reaper.ImGui_GetCursorPos(ctx)))
  if type(ensure_line_fits_current_page) == "function" then
    ensure_line_fits_current_page(line_h, column_start_cx)
  end
  reaper.ImGui_Dummy(ctx, 0, line_h * 2)

  for i = 1, 2 do
    if type(ensure_line_fits_current_page) == "function" then
      ensure_line_fits_current_page(line_h, column_start_cx)
    end
    local _, cy = reaper.ImGui_GetCursorPos(ctx)
    local line = lines[i] or ""
    local line_w = select(1, reaper.ImGui_CalcTextSize(ctx, line))
    local centered_cx = column_start_cx + math.max(0, (column_w - line_w) * 0.5)
    reaper.ImGui_SetCursorPos(ctx, centered_cx, cy)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), placeholder_col)
    reaper.ImGui_Text(ctx, line)
    reaper.ImGui_PopStyleColor(ctx)
    if i < 2 and line_spacing > 0 then
      reaper.ImGui_Dummy(ctx, 0, line_spacing)
    end
  end

  reaper.ImGui_Dummy(ctx, 0, line_h * 2)
  return true
end


-- Exact cached paragraph skip helper.
-- ImGui_Dummy participates in item layout and may advance the cursor by
-- cached_h plus current ItemSpacingY. The cached paragraph height already
-- represents the full-render start→end cursor delta, so the skip path must
-- correct the cursor back to start_y + cached_h after submitting a real Dummy.
function submit_cached_paragraph_skip_dummy(ctx, cached_h, audit_path, para_index, para_start_cy)
  local h = tonumber(cached_h) or 0
  if h < 0 then h = 0 end

  local before_y = select(2, reaper.ImGui_GetCursorPos(ctx))
  before_y = tonumber(before_y) or 0
  local base_y = tonumber(para_start_cy)
  if base_y == nil then base_y = before_y end
  local expected_y = base_y + h

  reaper.ImGui_Dummy(ctx, 0, h)

  local after_y = select(2, reaper.ImGui_GetCursorPos(ctx))
  after_y = tonumber(after_y) or expected_y
  local correction = expected_y - after_y

  if math.abs(correction) > 0.001 then
    reaper.ImGui_SetCursorPosY(ctx, expected_y)
    if psv_layout_audit_enabled and psv_layout_audit_enabled() then
      psv_layout_audit_msg(
        audit_path,
        "SKIP_CURSOR_CORRECT para=" .. tostring(para_index or "") ..
          " before=" .. psv_layout_audit_num(before_y) ..
          " expected=" .. psv_layout_audit_num(expected_y) ..
          " after_dummy=" .. psv_layout_audit_num(after_y) ..
          " correction=" .. psv_layout_audit_num(correction),
        "SKIP_CURSOR_CORRECT:" .. tostring(para_index or "") .. ":" .. psv_layout_audit_num(before_y)
      )
    end
  end
end

local function render_paragraphs(ctx, has_filter, match_lookup, token_hit_lookup)
  -- PSV_NAV_DIAG_BEGIN hook
  search_diag.begin_body()
  -- PSV_NAV_DIAG_END hook
  local doc_t_setup = psv_profiler_doc_block_begin("doc_setup")
  local dl = reaper.ImGui_GetWindowDrawList(ctx)

  -- v2.0.76: the native comment-card overlay is submitted after ##body ends.
  -- render_paragraphs() only prepares the current frame args while it still has
  -- access to marker/body geometry and existing comment state.
  if PSV_COMMENT_CARD_RENDERER then
    PSV_COMMENT_CARD_RENDERER.pending_args = nil
  end

  -- Draw paper background only when the page-layout layer is disabled.
  -- When PAGE_LAYOUT_ENABLED=true, render_page_layer(ctx) has already drawn
  -- the app background and visual pages behind the text inside ##body.
  if not PAGE_LAYOUT_ENABLED then
    local body_sx, body_sy = reaper.ImGui_GetCursorScreenPos(ctx)
    local avail_w, avail_h = reaper.ImGui_GetContentRegionAvail(ctx)
    reaper.ImGui_DrawList_AddRectFilled(dl,
      body_sx, body_sy,
      body_sx + avail_w, body_sy + avail_h,
      C_PAPER)
  end

  local paragraph_heights = ensure_body_render_cache(has_filter)
  local render_spacing_diag_active = psv_render_spacing_diag_begin_document(file_path, paragraphs)

  -- Page-aware vertical flow uses the same minimum-start-lines policy on
  -- cold and cached frames. Long paragraphs continue across page boundaries.
  -- Cached heights include those page gaps and are valid only at the original
  -- content position; viewport culling must preserve the full-layout geometry.
  local page_flow_enabled = PAGE_LAYOUT_ENABLED and (tonumber(PAGE_H) or 0) > 0
  local page_h = math.max(1, tonumber(PAGE_H) or 1)
  local page_gap_y = math.max(0, tonumber(PAGE_GAP_Y) or 0)
  local page_stack_top_gap = math.max(0, tonumber(PAGE_STACK_TOP_GAP) or 0)
  local page_pad_top = math.max(0, tonumber(PAGE_PAD_TOP) or 0)
  local page_pad_bottom = math.max(0, tonumber(PAGE_PAD_BOTTOM) or 0)
  local page_slot_h = page_h + page_gap_y
  local page_usable_h = math.max(1, page_h - page_pad_top - page_pad_bottom)

  -- Видимая область текущего body child в screen-space.
  -- Используем консервативный запас, чтобы не резать абзацы слишком агрессивно
  -- возле границ viewport и не ловить видимые pop/glitch артефакты.
  local viewport_top = select(2, reaper.ImGui_GetWindowPos(ctx))
  local viewport_h = select(2, reaper.ImGui_GetWindowSize(ctx))
  local viewport_bottom = viewport_top + viewport_h
  local cull_buffer = UI_BODY_CULL_BUFFER_PX

  local layout_audit_enabled = psv_layout_audit_enabled()
  local layout_audit_page_params = nil
  if layout_audit_enabled then
    layout_audit_page_params = {
      top_gap = page_stack_top_gap,
      slot_h = page_slot_h,
      pad_top = page_pad_top,
      page_h = page_h,
      pad_bottom = page_pad_bottom,
      page_gap_y = page_gap_y,
      page_stack_top_gap = page_stack_top_gap,
      page_flow_enabled = page_flow_enabled,
      page_flow_cached_culling_allowed = ((not page_flow_enabled) or (page_flow_enabled and UI_BODY_PAGE_FLOW_CACHED_CULLING_ENABLED == true)),
      viewport_h = viewport_h,
    }
    local audit_geom = get_page_text_horizontal_geometry(ctx, nil, nil, body_margin_left, body_margin_right, first_line_indent)
    psv_layout_audit_begin_segment(ctx, paragraphs, file_path, audit_geom, {
      viewport_h = viewport_h,
      page_flow_enabled = page_flow_enabled,
      page_flow_cached_culling_allowed = layout_audit_page_params.page_flow_cached_culling_allowed,
      page_h = page_h,
      page_gap_y = page_gap_y,
      page_pad_top = page_pad_top,
      page_pad_bottom = page_pad_bottom,
      page_stack_top_gap = page_stack_top_gap,
      font_size = font_size,
    })
  end

  local active_comment_para_index = nil
  if paragraphs.comments and type(paragraphs.comments.active_group_key) == "string" then
    active_comment_para_index = tonumber(paragraphs.comments.active_group_key:match("^(%d+):"))
  end

  local rendered_any = false
  local scroll_consumed = false

  local mouse_x, mouse_y = reaper.ImGui_GetMousePos(ctx)
  local mouse_clicked = reaper.ImGui_IsMouseClicked(ctx, reaper.ImGui_MouseButton_Left())
  local comment_marker_clicked = false
  local link_col = rgba(44, 104, 180)
  local link_hover_col = rgba(26, 88, 160)
  local want_hand_cursor = false
  local document_interactions_blocked = psv_document_interactions_blocked(ctx)

  -- v3.0.25: central document-hover arbitration for manual drawlist hitboxes.
  -- This keeps the Hand cursor intentional and diagnosable without introducing
  -- native per-token widgets or retained cursor reset state.
  local doc_hover_kind = nil
  local doc_hover_debug_key = nil

  local function set_doc_hover(kind, debug_key)
    local priority = { link = 1, marker = 2, range = 3 }
    local new_priority = priority[kind]
    if not new_priority then return end

    local current_priority = doc_hover_kind and priority[doc_hover_kind] or nil
    if not current_priority or new_priority < current_priority then
      doc_hover_kind = kind
      doc_hover_debug_key = debug_key
    end
  end

  local function emit_doc_hover_diag_if_changed()
    if PSV_DOC_HOVER_DIAG_ENABLED ~= true then return end
    if type(reaper.ShowConsoleMsg) ~= "function" then return end

    local diag_state = paragraphs._doc_hover_diag_state
    if type(diag_state) ~= "table" then
      diag_state = {}
      paragraphs._doc_hover_diag_state = diag_state
    end

    local current_kind = doc_hover_kind or "nil"
    local current_key = doc_hover_debug_key and tostring(doc_hover_debug_key) or ""
    if diag_state.kind == current_kind and diag_state.key == current_key then return end

    local previous_kind = diag_state.kind or "nil"
    local previous_key = diag_state.key or ""
    local scroll_y = 0
    if type(reaper.ImGui_GetScrollY) == "function" then
      scroll_y = tonumber(reaper.ImGui_GetScrollY(ctx)) or 0
    end

    reaper.ShowConsoleMsg(string.format(
      "[PSV doc hover] %s%s -> %s%s mouse=%d,%d scroll_y=%d\n",
      previous_kind,
      previous_key ~= "" and (":" .. previous_key) or "",
      current_kind,
      current_key ~= "" and (":" .. current_key) or "",
      math.floor((tonumber(mouse_x) or 0) + 0.5),
      math.floor((tonumber(mouse_y) or 0) + 0.5),
      math.floor(scroll_y + 0.5)
    ))

    diag_state.kind = current_kind
    diag_state.key = current_key
  end

  local function make_comment_range_group_from_token(tok)
    if type(tok) ~= "table" or type(tok.comment_ids) ~= "table" then
      return nil, nil, nil
    end

    local active_group_comment_ids = {}
    local key_parts = {}
    for _, comment_id in ipairs(tok.comment_ids) do
      if comment_id ~= nil and tostring(comment_id) ~= "" then
        active_group_comment_ids[#active_group_comment_ids + 1] = comment_id
        key_parts[#key_parts + 1] = tostring(comment_id)
      end
    end

    if #active_group_comment_ids == 0 then
      return nil, nil, nil
    end

    return active_group_comment_ids[1], active_group_comment_ids, "range:" .. table.concat(key_parts, string.char(29))
  end

  local function clear_range_comment_card_state(comments)
    comments.active_id = nil
    comments.active_label = nil
    comments.active_x = nil
    comments.active_y = nil
    comments.active_group_key = nil
    comments.active_group_comment_ids = nil
    comments.card_scroll_y = nil
    comments.card_scroll_max_y = nil
    comments.card_x = nil
    comments.card_y = nil
    comments.card_x2 = nil
    comments.card_y2 = nil
    comments.manual_card_position_enabled = nil
    comments.manual_card_x = nil
    comments.manual_card_y = nil
    comments.manual_card_dragging = nil
    comments.manual_card_drag_start_mouse_x = nil
    comments.manual_card_drag_start_mouse_y = nil
    comments.manual_card_drag_start_card_x = nil
    comments.manual_card_drag_start_card_y = nil
    comments.active_card_locked_candidate = nil
    comments.active_card_locked_candidate_id = nil
    comments.former_card_wheel_shield_active = nil
    comments.former_card_x = nil
    comments.former_card_y = nil
    comments.former_card_x2 = nil
    comments.former_card_y2 = nil
    comments.former_card_wheel_idle_frames = nil
  end

  local function reset_range_comment_card_geometry(comments)
    comments.card_scroll_y = 0
    comments.card_scroll_max_y = nil
    comments.card_x = nil
    comments.card_y = nil
    comments.card_x2 = nil
    comments.card_y2 = nil
    comments.manual_card_position_enabled = nil
    comments.manual_card_x = nil
    comments.manual_card_y = nil
    comments.manual_card_dragging = nil
    comments.manual_card_drag_start_mouse_x = nil
    comments.manual_card_drag_start_mouse_y = nil
    comments.manual_card_drag_start_card_x = nil
    comments.manual_card_drag_start_card_y = nil
    comments.active_card_locked_candidate = nil
    comments.active_card_locked_candidate_id = nil
  end

  local function clear_range_former_card_wheel_shield(comments)
    comments.former_card_wheel_shield_active = nil
    comments.former_card_x = nil
    comments.former_card_y = nil
    comments.former_card_x2 = nil
    comments.former_card_y2 = nil
    comments.former_card_wheel_idle_frames = nil
  end

  local function update_active_comment_range_geometry(tok, sx, sy, line_h, token_visible)
    local comments = paragraphs.comments
    if not comments then return end

    local _, _, group_key = make_comment_range_group_from_token(tok)
    if group_key and comments.active_group_key == group_key then
      -- v3.0.35: active DOCX range cards anchor to the last matching highlighted
      -- token encountered in the current frame. render_paragraphs() traverses
      -- tokens in document order, so repeatedly refreshing this geometry makes
      -- multi-line highlighted ranges follow a stable end-of-range anchor.
      -- Marker geometry uses its separate marker path and is not affected here.
      comments.active_marker_geometry_available = true
      comments.active_marker_visible = token_visible
      comments.active_x = sx
      comments.active_y = sy + line_h
    end
  end

  local function open_or_toggle_comment_range(tok, sx, sy, line_h, token_visible)
    local comments = paragraphs.comments
    if not comments then return false end

    comments.navigator_pending = nil
    comments.navigator_scroll_target_para = nil
    comments.navigator_marker_scroll_attempts = nil
    comments.navigator_marker_scroll_waiting_for_visible = nil

    local active_id, active_group_comment_ids, group_key = make_comment_range_group_from_token(tok)
    if not active_id or not group_key then return false end

    local same_active_range = comments.active_group_key == group_key
    if not comments.active_group_key then
      same_active_range = comments.active_id == active_id
    end

    if same_active_range then
      -- Clicking an already-active highlighted range mirrors marker toggle-close.
      -- Mark this as an intentional comment click so the outside-click guard does
      -- not immediately race the close action in the same frame.
      clear_range_comment_card_state(comments)
      comment_marker_clicked = true
      return true
    end

    local switching_group = comments.active_group_key ~= group_key
    if not comments.active_group_key then
      switching_group = comments.active_id ~= active_id
    end

    if switching_group then
      -- Match marker switching semantics: a distinct comment group starts with
      -- fresh card geometry/scroll instead of inheriting stale runtime state.
      reset_range_comment_card_geometry(comments)
    end

    -- A newly opened/switched range card owns this screen area again.
    -- Clear any stale former-card wheel shield left by an Escape close.
    clear_range_former_card_wheel_shield(comments)

    comments.active_card_locked_candidate = nil
    comments.active_card_locked_candidate_id = nil
    comments.active_id = active_id
    comments.active_label = "[*]"
    comments.active_x = sx
    comments.active_y = sy + line_h
    comments.active_group_key = group_key
    comments.active_group_comment_ids = active_group_comment_ids
    comments.active_marker_geometry_available = true
    comments.active_marker_visible = token_visible
    comment_marker_clicked = true
    return true
  end

  local function comments_nav_marker_visibility_state(marker_screen_y)
    if UI_COMMENTS_NAV_MARKER_AWARE_SCROLL_ENABLED ~= true then
      return true, nil, nil, nil, nil, nil
    end

    marker_screen_y = tonumber(marker_screen_y)
    if not marker_screen_y then
      return true, nil, nil, nil, nil, nil
    end

    local body_y = select(2, reaper.ImGui_GetWindowPos(ctx))
    local body_h = select(2, reaper.ImGui_GetWindowSize(ctx))
    local current_scroll_y = tonumber(reaper.ImGui_GetScrollY(ctx)) or 0
    local scroll_max_y = tonumber(reaper.ImGui_GetScrollMaxY(ctx)) or 0

    local margin_top = math.max(0, tonumber(UI_COMMENTS_NAV_MARKER_VISIBLE_MARGIN_TOP) or 0)
    local margin_bottom = math.max(0, tonumber(UI_COMMENTS_NAV_MARKER_VISIBLE_MARGIN_BOTTOM) or 0)
    local visible_top = body_y + margin_top
    local visible_bottom = body_y + math.max(1, body_h) - margin_bottom
    if visible_bottom < visible_top then
      visible_bottom = visible_top
    end

    if marker_screen_y >= visible_top and marker_screen_y <= visible_bottom then
      return true, nil, current_scroll_y, scroll_max_y, visible_top, visible_bottom
    end

    local desired_scroll_y
    if marker_screen_y < visible_top then
      desired_scroll_y = current_scroll_y + (marker_screen_y - visible_top)
    else
      desired_scroll_y = current_scroll_y + (marker_screen_y - visible_bottom)
    end

    desired_scroll_y = math.max(0, math.min(scroll_max_y, desired_scroll_y or current_scroll_y))
    return false, desired_scroll_y, current_scroll_y, scroll_max_y, visible_top, visible_bottom
  end

  local function token_has_comment_range_highlight(tok)
    return type(tok) == "table"
      and type(tok.comment_ids) == "table"
      and next(tok.comment_ids) ~= nil
  end

  -- Google Docs comment refs are stored by the parser on the document table.
  -- Build a function-local render lookup only for this frame, without changing
  -- the parser model or adding retained/top-level state.
  local comment_ref_lookup = nil
  if paragraphs.comments and paragraphs.comments.refs and #paragraphs.comments.refs > 0 then
    comment_ref_lookup = {}
    for _, ref in ipairs(paragraphs.comments.refs) do
      local para_i = tonumber(ref.paragraph_index)
      local tok_i = tonumber(ref.token_index_after) or 0
      if para_i then
        comment_ref_lookup[para_i] = comment_ref_lookup[para_i] or {}
        comment_ref_lookup[para_i][tok_i] = comment_ref_lookup[para_i][tok_i] or {}
        comment_ref_lookup[para_i][tok_i][#comment_ref_lookup[para_i][tok_i] + 1] = ref
      end
    end
  end

  -- v2.0.82: active card follows current marker geometry every frame.
  -- Geometry availability is separate from hover/visibility: the card is allowed
  -- to move out of the viewport and closes only after its full rect is offscreen.
  if paragraphs.comments then
    paragraphs.comments.active_marker_visible = false
    paragraphs.comments.active_marker_geometry_available = false
    if type(paragraphs.comments.navigator_pending) == "table" then
      paragraphs.comments.navigator_pending._matched_this_frame = nil
    end
  end

  local function maybe_emit_renderer_docx_para_format_diag(para_index, para, stage, data)
    if not DOCX_IMPORT.paragraph_format_diag_enabled() then return end
    if DOCX_IMPORT.paragraph_format_diag_adapter_only_output() then return end
    local matched_key = type(para) == "table" and para._docx_para_format_diag_matched_key or nil
    if not matched_key then return end

    local diag_state = paragraphs._docx_paragraph_format_renderer_diag_state
    if type(diag_state) ~= "table" then
      diag_state = { seen = {}, count = 0 }
      paragraphs._docx_paragraph_format_renderer_diag_state = diag_state
    end

    local max_rows = DOCX_IMPORT.paragraph_format_diag_max_rows()
    if diag_state.count >= max_rows then return end

    local key = tostring(para_index) .. ":" .. tostring(stage or "")
    if diag_state.seen[key] then return end
    diag_state.seen[key] = true
    diag_state.count = diag_state.count + 1

    local text = DOCX_IMPORT.block_text_for_diag(para)
    data = data or {}
    local info = type(paragraphs.import_info) == "table" and paragraphs.import_info or {}
    DOCX_IMPORT.msg("[PSV DOCX PARAGRAPH FORMAT DIAG] RENDER file=" .. DOCX_IMPORT.basename(info.original_file_path or file_path or "") ..
      " para=" .. tostring(para_index) ..
      " stage=" .. tostring(stage or "") ..
      " match=" .. tostring(matched_key))
    DOCX_IMPORT.msg('[PSV DOCX PARAGRAPH FORMAT DIAG] RENDER text="' .. DOCX_IMPORT.diag_escape_text(text, 220) .. '"')
    DOCX_IMPORT.msg("[PSV DOCX PARAGRAPH FORMAT DIAG] RENDER geom para_cx=" .. tostring(data.para_cx) ..
      " para_cy=" .. tostring(data.para_cy) ..
      " para_sx=" .. tostring(data.para_sx) ..
      " para_sy=" .. tostring(data.para_sy) ..
      " para_line_cx=" .. tostring(data.para_line_cx) ..
      " first_line_cx=" .. tostring(data.first_line_cx) ..
      " first_line_sx=" .. tostring(data.first_line_sx) ..
      " line_start_sx=" .. tostring(data.line_start_sx) ..
      " line_width=" .. tostring(data.line_width))
    DOCX_IMPORT.msg("[PSV DOCX PARAGRAPH FORMAT DIAG] RENDER margins body_l=" .. tostring(body_margin_left) ..
      " body_r=" .. tostring(body_margin_right) ..
      " page_l=" .. tostring(PAGE_MARGIN_LEFT) ..
      " page_r=" .. tostring(PAGE_MARGIN_RIGHT) ..
      " effective_l=" .. tostring(data.effective_left_margin) ..
      " first_indent=" .. tostring(first_line_indent) ..
      " cached_h=" .. tostring(data.cached_para_h) ..
      " force_render=" .. tostring(data.force_render) ..
      " page_flow=" .. tostring(page_flow_enabled))
  end

  local function maybe_emit_renderer_docx_para_format_token_diag(para_index, para, line_items, source_line_start_sx, source_line_width)
    if not DOCX_IMPORT.paragraph_format_diag_enabled() then return end
    if DOCX_IMPORT.paragraph_format_diag_adapter_only_output() then return end
    local matched_key = type(para) == "table" and para._docx_para_format_diag_matched_key or nil
    if not matched_key then return end
    if type(line_items) ~= "table" or #line_items == 0 then return end

    local diag_state = paragraphs._docx_paragraph_format_renderer_token_diag_state
    if type(diag_state) ~= "table" then
      diag_state = { seen = {}, count = 0 }
      paragraphs._docx_paragraph_format_renderer_token_diag_state = diag_state
    end

    local max_rows = DOCX_IMPORT.paragraph_format_diag_max_rows()
    if diag_state.count >= max_rows then return end

    local key = tostring(para_index) .. ":render_tokens"
    if diag_state.seen[key] then return end
    diag_state.seen[key] = true

    local info = type(paragraphs.import_info) == "table" and paragraphs.import_info or {}
    local limit = math.min(20, #line_items)
    DOCX_IMPORT.msg("[PSV DOCX PARAGRAPH FORMAT DIAG] RENDER_TOKEN_BEGIN file=" .. DOCX_IMPORT.basename(info.original_file_path or file_path or "") ..
      " para=" .. tostring(para_index) ..
      " match=" .. tostring(matched_key) ..
      " line_start_sx=" .. tostring(source_line_start_sx) ..
      " line_width=" .. tostring(source_line_width) ..
      " item_count=" .. tostring(#line_items))

    for item_i = 1, limit do
      if diag_state.count >= max_rows then break end
      local item = line_items[item_i]
      local tok = type(item) == "table" and item.tok or nil
      diag_state.count = diag_state.count + 1
      DOCX_IMPORT.msg("[PSV DOCX PARAGRAPH FORMAT DIAG] RENDER_TOKEN para=" .. tostring(para_index) ..
        " item=" .. tostring(item_i) ..
        " token_index=" .. tostring(item and item.token_index or "") ..
        " text=\"" .. DOCX_IMPORT.diag_escape_text(item and item.word or "", 100) .. "\"" ..
        " sx=" .. tostring(item and item.sx or "") ..
        " sy=" .. tostring(item and item.sy or "") ..
        " word_w=" .. tostring(item and item.word_w or "") ..
        " line_start_sx=" .. tostring(source_line_start_sx) ..
        " line_width_before=" .. tostring(item and item.line_width_before or "") ..
        " gap_after=" .. tostring(item and item.gap_after or "") ..
        " visible=" .. tostring(item and item.visible) ..
        " flags=" .. DOCX_IMPORT.diag_token_flags(tok or {}))
    end
  end

  psv_profiler_doc_count("paragraphs_total", #paragraphs)
  psv_profiler_doc_block_end("doc_setup", doc_t_setup)
  local doc_t_paragraph_loop = psv_profiler_doc_block_begin("paragraph_loop")

  for para_index, para in ipairs(paragraphs) do
    psv_profiler_doc_count("paragraphs_looped", 1)
    if render_spacing_diag_active then
      psv_render_spacing_diag_scan_paragraph(file_path, paragraphs, para_index, para)
    end
    -- Full-document search contract:
    -- search больше не фильтрует видимость абзацев.
    -- match_lookup используется только как "этот абзац является search result"
    -- для навигации, подсветки и search-mode separation.
    local show_para = true
    local para_matches_search = has_filter and (match_lookup[para_index] ~= nil)

    if show_para then
      rendered_any = true
      local layout_audit_para_line_jumps = 0
      local layout_audit_para_start_pushes = 0

      if page_flow_enabled then
        local doc_t_page_flow = psv_profiler_doc_block_begin("page_flow_layout")
        local flow_cursor_y = select(2, reaper.ImGui_GetCursorPos(ctx))
        local relative_y = flow_cursor_y - page_stack_top_gap
        local flow_page_index = math.floor(relative_y / page_slot_h)
        if flow_page_index < 0 then flow_page_index = 0 end

        local flow_page_top = page_stack_top_gap + flow_page_index * page_slot_h
        local flow_content_top = flow_page_top + page_pad_top
        local flow_content_bottom = flow_page_top + page_h - page_pad_bottom

        -- Верхний padding первой/каждой страницы становится реальным layout-space:
        -- текст не начинается прямо от верхней кромки визуального листа.
        if flow_cursor_y < flow_content_top then
          local audit_from_y = flow_cursor_y
          local audit_dummy_h = flow_content_top - flow_cursor_y
          reaper.ImGui_Dummy(ctx, 0, audit_dummy_h)
          layout_audit_para_start_pushes = layout_audit_para_start_pushes + 1
          if layout_audit_enabled then
            psv_layout_audit_page_jump(file_path, "cursor_before_content_top", para_index, nil, audit_from_y, flow_content_top, audit_dummy_h, flow_page_index, flow_page_index, "cursor_before_content_top", layout_audit_page_params)
          end
          flow_cursor_y = flow_content_top
        end

        -- Apply the same page-start policy on cold and cached frames.
        -- It depends on available space, not on whether this paragraph was measured.
        do
          -- v3.0.26: soften the old whole-paragraph keep-together policy.
          -- Large paragraphs should not jump wholesale to the next page just
          -- because their full cached height cannot fit in the remaining area.
          -- If there is room for a reasonable start, let the paragraph begin
          -- here and let ensure_line_fits_current_page() handle continuation
          -- lines at the page boundary.
          if flow_cursor_y > flow_content_top then
            local para_scale = HEADING_SCALE[para.tag] or 1.0
            local para_px = math.max(UI_FONT_SIZE_MIN, math.floor((tonumber(font_size) or UI_FONT_SIZE_DEFAULT) * para_scale + 0.5))
            local para_font = get_font(para_px)
            local pushed_font = false
            if para_font then
              reaper.ImGui_PushFont(ctx, para_font, para_px)
              pushed_font = true
            end
            local doc_t_text_measure_flow = psv_profiler_doc_block_begin("text_measure")
            psv_profiler_doc_count("calc_text_calls", 1)
            local _, approx_lh = reaper.ImGui_CalcTextSize(ctx, "Ay")
            psv_profiler_doc_block_end("text_measure", doc_t_text_measure_flow)
            if pushed_font then
              reaper.ImGui_PopFont(ctx)
            end
            approx_lh = math.max(1, tonumber(approx_lh) or para_px)

            local min_start_lines = tonumber(PAGE_FLOW_MIN_START_LINES) or 3
            if min_start_lines < 1 then min_start_lines = 1 end
            min_start_lines = math.floor(min_start_lines + 0.5)

            local min_start_h = approx_lh * min_start_lines
            if min_start_lines > 1 then
              min_start_h = min_start_h + math.max(0, tonumber(line_spacing) or 0) * (min_start_lines - 1)
            end

            local remaining_h = flow_content_bottom - flow_cursor_y
            if remaining_h < min_start_h then
              local next_content_top = page_stack_top_gap + (flow_page_index + 1) * page_slot_h + page_pad_top
              if next_content_top > flow_cursor_y then
                local audit_from_y = flow_cursor_y
                local audit_dummy_h = next_content_top - flow_cursor_y
                reaper.ImGui_Dummy(ctx, 0, audit_dummy_h)
                layout_audit_para_start_pushes = layout_audit_para_start_pushes + 1
                if layout_audit_enabled then
                  psv_layout_audit_page_jump(file_path, "min_start_lines", para_index, nil, audit_from_y, next_content_top, audit_dummy_h, flow_page_index, flow_page_index + 1, "PAGE_FLOW_MIN_START_LINES", layout_audit_page_params)
                end
              end
            end
          end
        end
        psv_profiler_doc_block_end("page_flow_layout", doc_t_page_flow)
      end

      local para_start_cx, para_start_cy = reaper.ImGui_GetCursorPos(ctx)
      local para_start_sy = select(2, reaper.ImGui_GetCursorScreenPos(ctx))
      local cached_para_h = paragraph_heights[para_index]
      -- A measured height includes page-break gaps. Reuse it only at the
      -- content position where it was measured; otherwise lay out again.
      if page_flow_enabled and cached_para_h then
        local cached_start_y = body_render_cache.paragraph_start_y[para_index]
        if not cached_start_y or math.abs(cached_start_y - para_start_cy) > 0.001 then
          cached_para_h = nil
        end
      end
      if cached_para_h and cached_para_h > 0 then
        psv_profiler_doc_count("paragraphs_cache_height_hit", 1)
      else
        psv_profiler_doc_count("paragraphs_cache_height_miss", 1)
      end
      local comments_nav_scroll_target = paragraphs.comments and paragraphs.comments.navigator_scroll_target_para or nil
      local force_render = (search_nav_scroll_target == para_index)
        or (comments_nav_scroll_target == para_index)
        or (active_comment_para_index == para_index)
      if force_render then
        psv_profiler_doc_count("paragraphs_force_rendered", 1)
      end
      local force_reason = nil
      if search_nav_scroll_target == para_index then
        force_reason = "search_target"
      elseif comments_nav_scroll_target == para_index then
        force_reason = "comment_navigator_target"
      elseif active_comment_para_index == para_index then
        force_reason = "active_comment_card"
      end

      local doc_t_culling = psv_profiler_doc_block_begin("culling_decision")
      local page_flow_cached_culling_allowed = (not page_flow_enabled)
        or (page_flow_enabled and UI_BODY_PAGE_FLOW_CACHED_CULLING_ENABLED == true)
      if page_flow_enabled then
        if page_flow_cached_culling_allowed then
          psv_profiler_doc_count("paragraphs_pageflow_cached_skip_allowed", 1)
        else
          psv_profiler_doc_count("paragraphs_pageflow_cached_skip_blocked", 1)
        end
      end

      if layout_audit_enabled then
        psv_layout_audit_para_start(file_path, para_index, para, para_start_cy, para_start_sy, cached_para_h, force_render, force_reason, page_flow_enabled, page_flow_cached_culling_allowed, layout_audit_page_params)
      end

      if cached_para_h and cached_para_h > 0 and not force_render and page_flow_cached_culling_allowed then
        local para_end_sy_est = para_start_sy + cached_para_h

        if para_end_sy_est < (viewport_top - cull_buffer)
           or para_start_sy > (viewport_bottom + cull_buffer) then
          if layout_audit_enabled then
            psv_layout_audit_culling_decision(file_path, para_index, "cached_dummy_skip", {
              offscreen = true,
              cached = true,
              cached_h = cached_para_h,
              force_render = force_render,
              page_flow_enabled = page_flow_enabled,
              page_flow_cached_culling_allowed = page_flow_cached_culling_allowed,
              para_start_cy = para_start_cy,
              para_end_cy_est = para_start_cy + cached_para_h,
              para_start_sy = para_start_sy,
              para_end_sy_est = para_end_sy_est,
            }, layout_audit_page_params)
          end
          psv_profiler_doc_block_end("culling_decision", doc_t_culling)
          maybe_emit_renderer_docx_para_format_diag(para_index, para, "cached_dummy_skip", {
            para_cx = para_start_cx,
            para_cy = para_start_cy,
            para_sx = select(1, reaper.ImGui_GetCursorScreenPos(ctx)),
            para_sy = para_start_sy,
            cached_para_h = cached_para_h,
            force_render = force_render,
          })
          local doc_t_skip_dummy = psv_profiler_doc_block_begin("offscreen_skip_dummy")
          submit_cached_paragraph_skip_dummy(ctx, cached_para_h, file_path, para_index, para_start_cy)
          psv_profiler_doc_block_end("offscreen_skip_dummy", doc_t_skip_dummy)
          psv_profiler_doc_count("paragraphs_skipped_dummy", 1)
          goto continue_paragraph
        end
      end
      if layout_audit_enabled then
        local para_end_sy_est = cached_para_h and (para_start_sy + cached_para_h) or nil
        local offscreen = false
        if para_end_sy_est then
          offscreen = para_end_sy_est < (viewport_top - cull_buffer) or para_start_sy > (viewport_bottom + cull_buffer)
        end
        local decision = "full_render"
        if force_render then
          decision = "force_render"
        elseif not cached_para_h or cached_para_h <= 0 then
          decision = "no_cache_full_render"
        elseif page_flow_enabled and not page_flow_cached_culling_allowed then
          decision = "page_flow_culling_blocked"
        end
        psv_layout_audit_culling_decision(file_path, para_index, decision, {
          offscreen = offscreen,
          cached = cached_para_h ~= nil and cached_para_h > 0,
          cached_h = cached_para_h,
          force_render = force_render,
          page_flow_enabled = page_flow_enabled,
          page_flow_cached_culling_allowed = page_flow_cached_culling_allowed,
          para_start_cy = para_start_cy,
          para_end_cy_est = cached_para_h and (para_start_cy + cached_para_h) or nil,
          para_start_sy = para_start_sy,
          para_end_sy_est = para_end_sy_est,
        }, layout_audit_page_params)
      end
      psv_profiler_doc_block_end("culling_decision", doc_t_culling)

      if search_nav_scroll_target == para_index
         and (not search_nav_occurrence or para.system_placeholder or para.docx_unsupported) then
        reset_body_scroll_inertia()

        -- PSV_NAV_DIAG_BEGIN hook
        search_diag.request_scroll(ctx, "paragraph", para_index, nil, nil, nil,
          select(2, reaper.ImGui_GetCursorPos(ctx)), 0.0)
        -- PSV_NAV_DIAG_END hook
        reaper.ImGui_SetScrollHereY(ctx, 0.0)
        scroll_consumed = true
      end

      if paragraphs.comments and paragraphs.comments.navigator_scroll_target_para == para_index then
        reset_body_scroll_inertia()
        local marker_aware_pending = UI_COMMENTS_NAV_MARKER_AWARE_SCROLL_ENABLED == true
          and type(paragraphs.comments.navigator_pending) == "table"
        if marker_aware_pending then
          -- Keep the paragraph force-rendered, but do not queue the old
          -- paragraph-level SetScrollHereY. That delayed coarse scroll can
          -- apply after a visible marker has already opened its card.
        else
          reaper.ImGui_SetScrollHereY(ctx, 0.0)
          paragraphs.comments.navigator_scroll_target_para = nil
        end
      end

      psv_profiler_doc_count("paragraphs_full_rendered", 1)
      psv_profiler_doc_count("visible_paragraphs", 1)
      if layout_audit_enabled then psv_layout_audit_counter(file_path, "full_render", 1) end
      local doc_t_visible_para = psv_profiler_doc_block_begin("visible_paragraph_render")

      if para.is_blank_paragraph then
        -- Пустой абзац — это реальная structural единица документа.
        -- Он не содержит текста, но должен занимать одно предсказуемое
        -- blank-paragraph место в вертикальном потоке.
        local blank_px = math.floor(font_size + 0.5)
        local blank_font = get_font(blank_px)
        reaper.ImGui_PushFont(ctx, blank_font, blank_px)

        local doc_t_text_measure_blank = psv_profiler_doc_block_begin("text_measure")
        psv_profiler_doc_count("calc_text_calls", 1)
        local _, blank_lh = reaper.ImGui_CalcTextSize(ctx, "Ay")
        psv_profiler_doc_block_end("text_measure", doc_t_text_measure_blank)
        reaper.ImGui_Dummy(ctx, 0, blank_lh)

        if paragraph_spacing > 0 then
          reaper.ImGui_Dummy(ctx, 0, paragraph_spacing)
        end

        reaper.ImGui_PopFont(ctx)
      else
        local scale  = HEADING_SCALE[para.tag] or 1.0
        local px     = math.floor(font_size * scale + 0.5)
        local font   = get_font(px)
        reaper.ImGui_PushFont(ctx, font, px)

        local doc_t_text_measure_base = psv_profiler_doc_block_begin("text_measure")
        psv_profiler_doc_count("calc_text_calls", 2)
        local _, lh   = reaper.ImGui_CalcTextSize(ctx, "Ay")
        local space_w = select(1, reaper.ImGui_CalcTextSize(ctx, " "))
        psv_profiler_doc_block_end("text_measure", doc_t_text_measure_base)

        -- Shared horizontal page/text geometry contract.
        -- Cursor-space values are derived from screen-space bounds through the
        -- current ImGui cursor/screen anchor, not by assuming window-relative X.
        local para_cx, para_cy = reaper.ImGui_GetCursorPos(ctx)
        local para_sx, para_sy = reaper.ImGui_GetCursorScreenPos(ctx)
        local horizontal_geom = get_page_text_horizontal_geometry(
          ctx,
          para_cx,
          para_sx,
          body_margin_left,
          body_margin_right,
          first_line_indent
        )
        local para_line_cx = horizontal_geom.continuation_left_cx or para_cx
        local first_line_cx = horizontal_geom.first_line_left_cx or para_line_cx
        local first_line_sx = horizontal_geom.first_line_left_sx
        local effective_left_margin = para_line_cx - para_cx
        maybe_emit_renderer_docx_para_format_diag(para_index, para, "full_render", {
          para_cx = para_cx,
          para_cy = para_cy,
          para_sx = para_sx,
          para_sy = para_sy,
          para_line_cx = para_line_cx,
          first_line_cx = first_line_cx,
          first_line_sx = first_line_sx,
          line_start_sx = first_line_sx,
          line_width = nil,
          effective_left_margin = effective_left_margin,
          cached_para_h = cached_para_h,
          force_render = force_render,
        })

        local audit_line_index = 1

        -- Line-level page-flow guard for long paragraphs.
        -- Whole-paragraph page flow remains unchanged, but oversized paragraphs
        -- need to continue across visual pages line by line. Downward page moves
        -- submit real ImGui layout space via Dummy(), so scroll metrics,
        -- paragraph-height measurement and viewport movement stay stable.
        local function ensure_line_fits_current_page(line_h, target_cx)
          local doc_t_page_flow_line = psv_profiler_doc_block_begin("page_flow_layout")
          if not page_flow_enabled then
            psv_profiler_doc_block_end("page_flow_layout", doc_t_page_flow_line)
            return false
          end

          local _, line_y = reaper.ImGui_GetCursorPos(ctx)
          local relative_y = line_y - page_stack_top_gap
          local page_index = math.floor(relative_y / page_slot_h)
          if page_index < 0 then page_index = 0 end

          local page_top = page_stack_top_gap + page_index * page_slot_h
          local content_top = page_top + page_pad_top
          local content_bottom = page_top + page_h - page_pad_bottom
          local target_y = nil

          if line_y < content_top then
            target_y = content_top
          elseif line_y + line_h > content_bottom then
            target_y = page_stack_top_gap + (page_index + 1) * page_slot_h + page_pad_top
          end

          if not target_y then
            psv_profiler_doc_block_end("page_flow_layout", doc_t_page_flow_line)
            return false
          end

          local from_page = page_index
          local to_page = page_index
          if target_y >= page_stack_top_gap then
            to_page = math.floor((target_y - page_stack_top_gap) / page_slot_h)
            if to_page < 0 then to_page = 0 end
          end
          local dummy_h = target_y - line_y
          if target_y > line_y then
            reaper.ImGui_Dummy(ctx, 0, dummy_h)
            layout_audit_para_line_jumps = layout_audit_para_line_jumps + 1
            if layout_audit_enabled then
              psv_layout_audit_page_jump(file_path, "line", para_index, audit_line_index, line_y, target_y, dummy_h, from_page, to_page, "line_does_not_fit", layout_audit_page_params)
            end
            local new_y = select(2, reaper.ImGui_GetCursorPos(ctx))
            reaper.ImGui_SetCursorPos(ctx, target_cx, new_y)
          else
            if layout_audit_enabled then
              psv_layout_audit_page_jump(file_path, "line_to_content_top", para_index, audit_line_index, line_y, target_y, dummy_h, from_page, to_page, "line_before_content_top", layout_audit_page_params)
            end
            reaper.ImGui_SetCursorPos(ctx, target_cx, target_y)
          end

          psv_profiler_doc_block_end("page_flow_layout", doc_t_page_flow_line)
          return true
        end

        reaper.ImGui_SetCursorPos(ctx, first_line_cx, para_cy)
        ensure_line_fits_current_page(lh, first_line_cx)

        first_line_sx = select(1, reaper.ImGui_GetCursorScreenPos(ctx))
        local max_sx = horizontal_geom.wrap_right_sx

        if para.docx_unsupported == true or para.system_placeholder == true then
          if layout_audit_enabled then psv_layout_audit_count_placeholder(file_path) end
          render_docx_unsupported_placeholder_paragraph(
            ctx,
            para,
            horizontal_geom.content_left_cx or para_line_cx,
            horizontal_geom.placeholder_center_left_sx,
            horizontal_geom.placeholder_center_right_sx,
            lh,
            line_spacing,
            ensure_line_fits_current_page
          )

          reaper.ImGui_PopFont(ctx)

          if paragraph_spacing > 0 then
            reaper.ImGui_Dummy(ctx, 0, paragraph_spacing)
          end
        else

        -- Локальный helper: переводит курсор на новую визуальную строку,
        -- добавляет пользовательский межстрочный интервал и восстанавливает
        -- реальный cursor X на обычное левое поле абзаца. После wrap/newline
        -- line-level guard переносит continuation line в content-area следующей
        -- визуальной страницы, если строка уже не помещается.
        local function move_to_next_line()
          reaper.ImGui_NewLine(ctx)
          if line_spacing > 0 then
            reaper.ImGui_Dummy(ctx, 0, line_spacing)
          end
          local line_cy = select(2, reaper.ImGui_GetCursorPos(ctx))
          reaper.ImGui_SetCursorPos(ctx, para_line_cx, line_cy)
          ensure_line_fits_current_page(lh, para_line_cx)
          audit_line_index = audit_line_index + 1
        end

        -- v1.3.139: visual run coalescing stays local to render_paragraphs().
        -- The tokenizer still stores word tokens only; here we only bridge
        -- decorative visuals across the existing SameLine spacing.
        local line_tokens = {}
        local line_width = 0
        local line_start_cx = select(1, reaper.ImGui_GetCursorPos(ctx))
        local line_start_cy = select(2, reaper.ImGui_GetCursorPos(ctx))
        local line_start_sx = first_line_sx
        local line_start_sy = select(2, reaper.ImGui_GetCursorScreenPos(ctx))

        local function reset_line_state()
          line_tokens = {}
          line_width = 0
          line_start_cx = select(1, reaper.ImGui_GetCursorPos(ctx))
          line_start_cy = select(2, reaper.ImGui_GetCursorPos(ctx))
          line_start_sx = select(1, reaper.ImGui_GetCursorScreenPos(ctx))
          line_start_sy = select(2, reaper.ImGui_GetCursorScreenPos(ctx))
        end

        local paragraph_comment_refs = comment_ref_lookup and comment_ref_lookup[para_index] or nil

        local function token_safe_href(tok)
          local href = tok.href
          if href
             and (href:match("^https://") or href:match("^http://"))
             and not href:find('"', 1, true)
             and not href:find("[%c]") then
            return href
          end
          return nil
        end

        local flush_visual_line

        -- v2.0.103/v3.0.138: render-time wrapping for oversized visible link tokens
        -- and plain unbreakable DOCX text tokens. Parser/tokenize stay untouched:
        -- the original tok.text/tok.href remains the source of truth for search,
        -- comments and link target semantics.
        local function calc_word_width(text, token_font)
          local doc_t_text_measure = psv_profiler_doc_block_begin("text_measure")
          if token_font then reaper.ImGui_PushFont(ctx, token_font, px) end
          psv_profiler_doc_count("calc_text_calls", 1)
          local w = select(1, reaper.ImGui_CalcTextSize(ctx, text or ""))
          if token_font then reaper.ImGui_PopFont(ctx) end
          psv_profiler_doc_block_end("text_measure", doc_t_text_measure)
          return w
        end

        local function add_line_token(tok, word, word_w, token_font, safe_href, token_is_search_hit, gap_after, token_index, chunk_first_byte)
          local render_spacing_diag_enabled = psv_render_spacing_diag_enabled()
          local render_spacing_diag = nil

          if render_spacing_diag_enabled then
            local diag_prev_item = (#line_tokens > 0) and line_tokens[#line_tokens] or nil
            render_spacing_diag = {
              prev_item = diag_prev_item,
              prev_gap_before = diag_prev_item and (diag_prev_item.gap_after or space_w) or nil,
              line_width_before_no_space = line_width,
              removed_gap = 0,
              entered_no_space_branch = tok.no_space_before and #line_tokens > 0,
              wrap_triggered = false,
            }
          end

          -- HTML adjacent styled-span repair: when the parser knows that this
          -- visible token starts immediately after the previous visible token
          -- without source whitespace, remove only the artificial renderer gap
          -- before this token. Keep token text/style split intact.
          if tok.no_space_before and #line_tokens > 0 then
            local prev = line_tokens[#line_tokens]
            local prev_gap = prev.gap_after or space_w
            line_width = math.max(0, line_width - prev_gap)
            prev.gap_after = 0
            if render_spacing_diag then
              render_spacing_diag.removed_gap = prev_gap
            end
          end

          if #line_tokens > 0 and (line_start_sx + line_width + word_w > max_sx) then
            if render_spacing_diag then
              render_spacing_diag.wrap_triggered = true
            end
            flush_visual_line()
            move_to_next_line()
            reset_line_state()
          end

          local first_byte = chunk_first_byte or 1
          if scroll_search_occurrence_to_line(ctx, para_index, token_index,
              first_byte, first_byte + #word - 1, line_start_cy) then
            scroll_consumed = true
          end
          -- PSV_NAV_DIAG_BEGIN hook
          if search_diag.watch then
            search_diag.observe_target(para_index, token_index, first_byte,
              first_byte + #word - 1, line_start_cy, lh)
          end
          -- PSV_NAV_DIAG_END hook
          local sx = line_start_sx + line_width
          local sy = line_start_sy
          local line_width_before = line_width
          if render_spacing_diag then
            psv_render_spacing_diag_log_add_token(
              para_index,
              token_index,
              word,
              tok,
              line_tokens,
              sx,
              word_w,
              render_spacing_diag.prev_item,
              render_spacing_diag.prev_gap_before,
              render_spacing_diag.line_width_before_no_space,
              render_spacing_diag.entered_no_space_branch,
              render_spacing_diag.removed_gap,
              line_width,
              render_spacing_diag.wrap_triggered
            )
          end
          local token_visible = (sy + lh >= viewport_top - 4) and (sy <= viewport_bottom + 4)
          if token_visible then
            psv_profiler_doc_count("tokens_rendered_visible", 1)
          end
          local _, range_comment_ids, range_group_key = make_comment_range_group_from_token(tok)
          if safe_href then
            psv_profiler_doc_count("link_hitbox_checks", 1)
          end
          local link_hovered = token_visible
            and not document_interactions_blocked
            and safe_href
            and mouse_x >= sx and mouse_x <= sx + word_w
            and mouse_y >= sy and mouse_y <= sy + lh
          local fg = tok.fg or (safe_href and (link_hovered and link_hover_col or link_col) or C_TEXT)

          update_active_comment_range_geometry(tok, sx, sy, lh, token_visible)

          if link_hovered then
            set_doc_hover("link", safe_href or "link")
          end

          if safe_href and link_hovered and mouse_clicked then
            open_or_copy_about_url(ctx, safe_href)
          end

          line_tokens[#line_tokens + 1] = {
            tok=tok,
            token_index=token_index,
            no_space_before=tok.no_space_before == true,
            line_width_before=line_width_before,
            word=word,
            word_w=word_w,
            sx=sx,
            sy=sy,
            bg=tok.bg,
            comment_range_highlight=token_has_comment_range_highlight(tok),
            comment_ids=range_comment_ids,
            comment_range_group_key=range_group_key,
            comment_range_hovered=false,
            fg=fg,
            token_font=token_font,
            visible=token_visible,
            search_hit=token_is_search_hit,
            safe_href=safe_href,
            link_hovered=link_hovered,
            gap_after=gap_after or space_w,
          }

          line_width = line_width + word_w + (gap_after or space_w)
        end

        local function utf8_char_end_pos(text, pos)
          local len = #text
          if pos > len then return len end
          local b = text:byte(pos)
          if not b then return len end

          local char_len = 1
          if b >= 0xF0 then
            char_len = 4
          elseif b >= 0xE0 then
            char_len = 3
          elseif b >= 0xC0 then
            char_len = 2
          else
            char_len = 1
          end

          local end_pos = math.min(len, pos + char_len - 1)
          -- If the byte sequence is malformed/truncated, do not walk past the
          -- available bytes. This still guarantees we never split a valid UTF-8
          -- codepoint in the middle when chunking long visible DOCX tokens.
          return end_pos
        end

        local function is_ascii_wrap_separator(ch)
          return ch == "/" or ch == "?" or ch == "&" or ch == "="
             or ch == "-" or ch == "_" or ch == "." or ch == "#"
             or ch == "%"
        end

        local function is_plain_url_like_unbreakable_text(text)
          if type(text) ~= "string" or text == "" then return false end
          if text:find("%s") then return false end
          return text:match("^https://") ~= nil
             or text:match("^http://") ~= nil
             or text:match("^www%.") ~= nil
             or text:find("://", 1, true) ~= nil
        end

        local function find_link_chunk_fit(text, start_pos, max_w, token_font)
          local len = #text
          if start_pos > len then return "", start_pos end

          local best_end = nil
          local best_sep_end = nil
          local i = start_pos

          while i <= len do
            local char_end = utf8_char_end_pos(text, i)
            local chunk = text:sub(start_pos, char_end)
            if calc_word_width(chunk, token_font) <= max_w then
              best_end = char_end
              local ch = text:sub(i, char_end)
              if is_ascii_wrap_separator(ch) then
                best_sep_end = char_end
              end
              i = char_end + 1
            else
              break
            end
          end

          if not best_end then
            best_end = utf8_char_end_pos(text, start_pos)
          elseif best_sep_end then
            best_end = best_sep_end
          end

          return text:sub(start_pos, best_end), best_end + 1
        end

        local function add_wrapped_unbreakable_token(tok, token_font, safe_href, token_is_search_hit, token_index)
          local text = tok.text or ""
          local pos = 1
          local text_column_w = math.max(1, max_sx - para_sx)

          while pos <= #text do
            local remaining_w = max_sx - (line_start_sx + line_width)
            if remaining_w < math.min(text_column_w, space_w * 2) then
              if #line_tokens > 0 then
                flush_visual_line()
                move_to_next_line()
                reset_line_state()
              end
              remaining_w = math.max(1, max_sx - line_start_sx)
            end

            local fit_w = math.max(1, math.min(remaining_w, text_column_w))
            local chunk, next_pos = find_link_chunk_fit(text, pos, fit_w, token_font)
            if chunk == "" then
              local char_end = utf8_char_end_pos(text, pos)
              chunk = text:sub(pos, char_end)
              next_pos = char_end + 1
            end

            local chunk_w = calc_word_width(chunk, token_font)
            local is_last_chunk = next_pos > #text
            add_line_token(tok, chunk, chunk_w, token_font, safe_href, token_is_search_hit, is_last_chunk and space_w or 0, token_index, pos)

            pos = math.max(next_pos, pos + 1)
          end
        end

        function flush_visual_line()
          if #line_tokens == 0 then return end

          if layout_audit_enabled then
            psv_layout_audit_line_near_page_boundary(file_path, para_index, audit_line_index, line_start_cy, lh, line_tokens, line_width, layout_audit_page_params)
            psv_layout_audit_count_line_side_effects(file_path, line_tokens)
          end

          local doc_t_comments_links = psv_profiler_doc_block_begin("comments_links_markers")

          -- v3.0.25: DOCX comment range hit testing is visual-line run based.
          -- A multi-word highlighted range should feel like one continuous
          -- interactive phrase, including the renderer gap between adjacent
          -- tokens on the same visual line. This keeps the existing manual
          -- screen-space hitbox model and does not introduce native per-token widgets.
          local range_run_key = nil
          local range_run_first_item = nil
          local range_run_last_item = nil
          local range_run_x1 = nil
          local range_run_x2 = nil
          local range_run_y1 = nil
          local range_run_y2 = nil
          local range_run_click_handled = false

          local function finish_comment_range_run()
            if not range_run_key or not range_run_first_item then return end

            local run_hovered = (not document_interactions_blocked)
              and mouse_x >= range_run_x1 and mouse_x <= range_run_x2
              and mouse_y >= range_run_y1 and mouse_y <= range_run_y2

            if run_hovered then
              set_doc_hover("range", range_run_key)
              if mouse_clicked and not range_run_click_handled then
                range_run_click_handled = true
                local anchor_item = range_run_last_item or range_run_first_item
                open_or_toggle_comment_range(
                  anchor_item.tok,
                  anchor_item.sx,
                  anchor_item.sy,
                  lh,
                  true
                )
              end
            end
          end

          for _, item in ipairs(line_tokens) do
            local item_key = nil
            if item.visible
               and item.comment_range_group_key
               and item.word
               and item.word ~= "" then
              item_key = item.comment_range_group_key
            end

            if item_key and item_key == range_run_key then
              range_run_last_item = item
              range_run_x2 = item.sx + item.word_w + 3
              range_run_y1 = math.min(range_run_y1, item.sy)
              range_run_y2 = math.max(range_run_y2, item.sy + lh)
            else
              finish_comment_range_run()

              if item_key then
                range_run_key = item_key
                range_run_first_item = item
                range_run_last_item = item
                range_run_x1 = item.sx - 1
                range_run_x2 = item.sx + item.word_w + 3
                range_run_y1 = item.sy
                range_run_y2 = item.sy + lh
              else
                range_run_key = nil
                range_run_first_item = nil
                range_run_last_item = nil
                range_run_x1 = nil
                range_run_x2 = nil
                range_run_y1 = nil
                range_run_y2 = nil
              end
            end
          end
          finish_comment_range_run()
          psv_profiler_doc_block_end("comments_links_markers", doc_t_comments_links)

          maybe_emit_renderer_docx_para_format_token_diag(para_index, para, line_tokens, line_start_sx, line_width)

          local render_spacing_diag_line_target = psv_render_spacing_diag_enabled() and psv_render_spacing_diag_line_is_target(line_tokens)
          if render_spacing_diag_line_target then
            psv_render_spacing_diag_log_line_snapshot(para_index, audit_line_index, line_tokens, line_start_sx, line_width)
            for diag_i = 2, #line_tokens do
              psv_render_spacing_diag_log_line_pair(
                para_index,
                audit_line_index,
                line_tokens[diag_i - 1],
                line_tokens[diag_i],
                diag_i - 1,
                diag_i,
                line_start_sx,
                line_width
              )
            end
          end

          local doc_t_styled_text = psv_profiler_doc_block_begin("styled_text_render")

          -- Фоновые подложки нужно рисовать до ImGui_Text(), иначе они закроют текст.
          local run_bg = nil
          local run_x1 = nil
          local run_x2 = nil
          local run_y1 = nil
          local run_y2 = nil

          for _, item in ipairs(line_tokens) do
            if item.visible and is_highlight(item.bg) then
              if run_bg == item.bg then
                run_x2 = item.sx + item.word_w + 2
              else
                if run_bg then
                  reaper.ImGui_DrawList_AddRectFilled(dl, run_x1, run_y1, run_x2, run_y2, run_bg)
                end
                run_bg = item.bg
                run_x1 = item.sx - 1
                run_x2 = item.sx + item.word_w + 2
                run_y1 = item.sy
                run_y2 = item.sy + lh
              end
            else
              if run_bg then
                reaper.ImGui_DrawList_AddRectFilled(dl, run_x1, run_y1, run_x2, run_y2, run_bg)
                run_bg = nil
              end
            end
          end
          if run_bg then
            reaper.ImGui_DrawList_AddRectFilled(dl, run_x1, run_y1, run_x2, run_y2, run_bg)
          end

          -- DOCX comment range highlight is renderer-only.
          -- It uses token.comment_ids preserved by the DOCX bridge, does not
          -- mutate tok.bg, and stays below text/search/underline/marker visuals.
          local comment_range_col = rgba(
            UI_DOCX_COMMENT_RANGE_HIGHLIGHT_RGBA[1],
            UI_DOCX_COMMENT_RANGE_HIGHLIGHT_RGBA[2],
            UI_DOCX_COMMENT_RANGE_HIGHLIGHT_RGBA[3],
            UI_DOCX_COMMENT_RANGE_HIGHLIGHT_RGBA[4]
          )
          for _, item in ipairs(line_tokens) do
            if item.visible and item.comment_range_highlight and item.word and item.word ~= "" then
              reaper.ImGui_DrawList_AddRectFilled(
                dl,
                item.sx - 1,
                item.sy,
                item.sx + item.word_w + 2,
                item.sy + lh,
                comment_range_col,
                2
              )
            end
          end

          -- Inline comment markers use a small local highlight box.
          -- This is visual-only: mapping, hitbox ownership, and comment data
          -- stay attached to the same marker item/ref.
          for _, item in ipairs(line_tokens) do
            if item.visible and item.is_comment_marker and item.marker_bg then
              reaper.ImGui_DrawList_AddRectFilled(
                dl,
                item.sx - 2,
                item.sy,
                item.sx + item.word_w + 3,
                item.sy + lh,
                item.marker_bg,
                2
              )
            end
          end

          -- Position-authoritative final text drawing.
          -- add_line_token() computes authoritative screen-space x/y for every
          -- visual token, and item.sx/item.sy are kept aligned with highlights,
          -- underlines, search outlines, and link/comment hitboxes.
          local render_spacing_diag_rects = nil
          if psv_render_spacing_diag_enabled() and render_spacing_diag_line_target then render_spacing_diag_rects = {} end

          for draw_i, item in ipairs(line_tokens) do
            local item_cx = line_start_cx + ((tonumber(item.sx) or line_start_sx) - line_start_sx)
            local item_cy = line_start_cy + ((tonumber(item.sy) or line_start_sy) - line_start_sy)
            reaper.ImGui_SetCursorPos(ctx, item_cx, item_cy)
            local cursor_before_sx, cursor_before_sy = nil, nil
            if render_spacing_diag_rects then
              cursor_before_sx, cursor_before_sy = reaper.ImGui_GetCursorScreenPos(ctx)
            end
            if item.token_font then reaper.ImGui_PushFont(ctx, item.token_font, px) end
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), item.fg)
            reaper.ImGui_Text(ctx, item.word)
            reaper.ImGui_PopStyleColor(ctx)
            if item.token_font then reaper.ImGui_PopFont(ctx) end

            if render_spacing_diag_rects then
              local rect_min_x, rect_min_y = reaper.ImGui_GetItemRectMin(ctx)
              local rect_max_x, rect_max_y = reaper.ImGui_GetItemRectMax(ctx)
              render_spacing_diag_rects[draw_i] = {
                min_x = rect_min_x,
                min_y = rect_min_y,
                max_x = rect_max_x,
                max_y = rect_max_y,
              }
              psv_render_spacing_diag_log_draw_item(
                para_index,
                audit_line_index,
                draw_i,
                item,
                cursor_before_sx,
                cursor_before_sy,
                rect_min_x,
                rect_max_x
              )
              if draw_i > 1 then
                psv_render_spacing_diag_log_draw_pair(
                  para_index,
                  audit_line_index,
                  line_tokens[draw_i - 1],
                  item,
                  render_spacing_diag_rects[draw_i - 1],
                  render_spacing_diag_rects[draw_i]
                )
              end
            end
          end

          -- Preserve the line-level cursor-flow contract expected by the
          -- surrounding NewLine()/Dummy()-based paragraph layout without using
          -- SameLine() as the horizontal placement source of truth.
          reaper.ImGui_SetCursorPos(ctx, line_start_cx + line_width, line_start_cy)
          psv_profiler_doc_block_end("styled_text_render", doc_t_styled_text)

          local doc_t_search_highlight = psv_profiler_doc_block_begin("search_highlight")

          -- Search outline можно рисовать после текста: это тонкая рамка, не заливка.
          local search_x1 = nil
          local search_x2 = nil
          local search_y1 = nil
          local search_y2 = nil

          for _, item in ipairs(line_tokens) do
            if item.visible and item.search_hit then
              if search_x1 then
                search_x2 = item.sx + item.word_w + 3
              else
                search_x1 = item.sx - 2
                search_x2 = item.sx + item.word_w + 3
                search_y1 = item.sy - 1
                search_y2 = item.sy + lh + 1
              end
            else
              if search_x1 then
                reaper.ImGui_DrawList_AddRect(
                  dl,
                  search_x1, search_y1,
                  search_x2, search_y2,
                  C_SEARCH_HIT,
                  0,
                  reaper.ImGui_DrawFlags_None(),
                  1.0)
                search_x1 = nil
              end
            end
          end
          if search_x1 then
            reaper.ImGui_DrawList_AddRect(
              dl,
              search_x1, search_y1,
              search_x2, search_y2,
              C_SEARCH_HIT,
              0,
              reaper.ImGui_DrawFlags_None(),
              1.0)
          end
          psv_profiler_doc_block_end("search_highlight", doc_t_search_highlight)

          local doc_t_comments_links_underline = psv_profiler_doc_block_begin("comments_links_markers")

          -- Link/imported underline share one visual path to avoid duplicate lines.
          local ul_key = nil
          local ul_x1 = nil
          local ul_x2 = nil
          local ul_y = nil
          local ul_col = nil
          local ul_thickness = 1.0

          for _, item in ipairs(line_tokens) do
            local draw_ul = item.visible and (item.safe_href or item.tok.underline)
            local next_key = nil
            if draw_ul then
              if item.safe_href then
                next_key = "href:" .. item.safe_href
              else
                next_key = "ul:" .. tostring(item.fg)
              end
            end

            if draw_ul then
              local item_col = item.fg
              local item_thickness = item.link_hovered and 1.2 or 1.0
              if ul_key == next_key then
                ul_x2 = item.sx + item.word_w
                if item.link_hovered then
                  ul_col = item_col
                  ul_thickness = item_thickness
                end
              else
                if ul_key then
                  reaper.ImGui_DrawList_AddLine(dl, ul_x1, ul_y, ul_x2, ul_y, ul_col, ul_thickness)
                end
                ul_key = next_key
                ul_x1 = item.sx
                ul_x2 = item.sx + item.word_w
                ul_y = item.sy + lh - 1
                ul_col = item_col
                ul_thickness = item_thickness
              end
            else
              if ul_key then
                reaper.ImGui_DrawList_AddLine(dl, ul_x1, ul_y, ul_x2, ul_y, ul_col, ul_thickness)
                ul_key = nil
              end
            end
          end
          if ul_key then
            reaper.ImGui_DrawList_AddLine(dl, ul_x1, ul_y, ul_x2, ul_y, ul_col, ul_thickness)
          end

          -- DOCX direct strikethrough is visual-only. It reuses the same
          -- rendered visual-line fragments as underline/link decoration, so
          -- wrapping, measurement, search and comment hitboxes remain unchanged.
          local strike_key = nil
          local strike_x1 = nil
          local strike_x2 = nil
          local strike_y = nil
          local strike_col = nil
          local strike_thickness = 1.0

          for _, item in ipairs(line_tokens) do
            local draw_strike = item.visible and item.tok and item.tok.strike
            local next_strike_key = nil
            if draw_strike then
              next_strike_key = "strike:" .. tostring(item.fg)
            end

            if draw_strike then
              local item_col = item.fg
              if strike_key == next_strike_key then
                strike_x2 = item.sx + item.word_w
              else
                if strike_key then
                  reaper.ImGui_DrawList_AddLine(
                    dl,
                    strike_x1, strike_y,
                    strike_x2, strike_y,
                    strike_col,
                    strike_thickness
                  )
                end
                strike_key = next_strike_key
                strike_x1 = item.sx
                strike_x2 = item.sx + item.word_w
                strike_y = item.sy + math.max(1, math.floor(lh * 0.52))
                strike_col = item_col
              end
            else
              if strike_key then
                reaper.ImGui_DrawList_AddLine(
                  dl,
                  strike_x1, strike_y,
                  strike_x2, strike_y,
                  strike_col,
                  strike_thickness
                )
                strike_key = nil
              end
            end
          end
          if strike_key then
            reaper.ImGui_DrawList_AddLine(
              dl,
              strike_x1, strike_y,
              strike_x2, strike_y,
              strike_col,
              strike_thickness
            )
          end
          psv_profiler_doc_block_end("comments_links_markers", doc_t_comments_links_underline)

        end

        local function append_comment_refs_after(token_index)
          if not paragraph_comment_refs then return end

          local refs = paragraph_comment_refs[token_index]
          if not refs or #refs == 0 then return end
          psv_profiler_doc_count("comment_marker_checks", 1)

          -- Same-anchor Google Docs refs are treated as one visible comment
          -- thread/group. Source order is preserved by the existing refs array.
          -- This avoids rendering repeated adjacent markers for comment replies
          -- exported at the same text anchor.
          local primary_ref = refs[1]
          if not primary_ref then return end
          local doc_t_comment_marker = psv_profiler_doc_block_begin("comments_links_markers")

          -- Display one neutral marker for the whole same-anchor refs group.
          -- Keep all recovered labels stored internally; do not expose them in UI.
          local marker_word = "[*]"
          local marker_font = get_font(px, "bold")

          if marker_font then reaper.ImGui_PushFont(ctx, marker_font, px) end
          local doc_t_text_measure_marker = psv_profiler_doc_block_begin("text_measure")
          psv_profiler_doc_count("calc_text_calls", 1)
          local marker_w = select(1, reaper.ImGui_CalcTextSize(ctx, marker_word))
          psv_profiler_doc_block_end("text_measure", doc_t_text_measure_marker)
          if marker_font then reaper.ImGui_PopFont(ctx) end

          if #line_tokens > 0 and (line_start_sx + line_width + marker_w > max_sx) then
            flush_visual_line()
            move_to_next_line()
            reset_line_state()
          end

          local sx = line_start_sx + line_width
          local sy = line_start_sy
          local group_key = tostring(para_index) .. ":" .. tostring(token_index or 0)
          local marker_visible = (sy + lh >= viewport_top - 4) and (sy <= viewport_bottom + 4)
          local marker_hovered = marker_visible
            and not document_interactions_blocked
            and mouse_x >= sx - 2 and mouse_x <= sx + marker_w + 2
            and mouse_y >= sy - 1 and mouse_y <= sy + lh + 1
          local marker_active = paragraphs.comments
            and (
              paragraphs.comments.active_group_key == group_key
              or (
                not paragraphs.comments.active_group_key
                and paragraphs.comments.active_id == primary_ref.comment_id
              )
            )
          if marker_active and paragraphs.comments then
            -- v2.0.82: keep active marker geometry fresh even near/outside the
            -- visible viewport. The card uses this unclamped geometry to keep
            -- moving with the marker, then closes when its own rect is offscreen.
            paragraphs.comments.active_marker_geometry_available = true
            paragraphs.comments.active_marker_visible = marker_visible
            paragraphs.comments.active_x = sx
            paragraphs.comments.active_y = sy + lh
          end

          if paragraphs.comments and type(paragraphs.comments.navigator_pending) == "table" then
            local pending_nav = paragraphs.comments.navigator_pending
            if pending_nav.group_key == group_key
               and pending_nav.paragraph_index == para_index
               and pending_nav.token_index_after == (token_index or 0) then
              pending_nav._matched_this_frame = true

              local marker_anchor_y = sy + lh
              local marker_inside_safe_band = marker_visible
              local desired_scroll_y, current_scroll_y
              if UI_COMMENTS_NAV_MARKER_AWARE_SCROLL_ENABLED == true then
                marker_inside_safe_band, desired_scroll_y, current_scroll_y = comments_nav_marker_visibility_state(marker_anchor_y)
              end

              if UI_COMMENTS_NAV_MARKER_AWARE_SCROLL_ENABLED == true and not marker_inside_safe_band then
                local attempts = math.max(0, tonumber(paragraphs.comments.navigator_marker_scroll_attempts) or 0)
                local max_attempts = math.max(0, math.floor((tonumber(UI_COMMENTS_NAV_MARKER_SCROLL_MAX_ATTEMPTS) or 3) + 0.5))
                local scroll_delta = math.abs((tonumber(desired_scroll_y) or 0) - (tonumber(current_scroll_y) or 0))
                if attempts < max_attempts and desired_scroll_y and scroll_delta > 0.5 then
                  reaper.ImGui_SetScrollY(ctx, desired_scroll_y)
                  reset_body_scroll_inertia()
                  paragraphs.comments.navigator_marker_scroll_attempts = attempts + 1
                  paragraphs.comments.navigator_marker_scroll_waiting_for_visible = true
                else
                  -- Safety fallback: do not keep a bad navigator request alive
                  -- forever if the marker cannot be brought into the safe band.
                  marker_inside_safe_band = true
                end
              end

              if marker_inside_safe_band then
                local active_group_comment_ids = {}
                for _, group_ref in ipairs(refs) do
                  if group_ref.comment_id and group_ref.comment_id ~= "" then
                    active_group_comment_ids[#active_group_comment_ids + 1] = group_ref.comment_id
                  end
                end

                local pending_primary_id = pending_nav.primary_id or primary_ref.comment_id
                local same_active_group = paragraphs.comments.active_group_key == group_key
                if not paragraphs.comments.active_group_key then
                  same_active_group = paragraphs.comments.active_id == pending_primary_id
                end

                if not same_active_group then
                  paragraphs.comments.card_scroll_y = 0
                  paragraphs.comments.card_scroll_max_y = nil
                  paragraphs.comments.card_x = nil
                  paragraphs.comments.card_y = nil
                  paragraphs.comments.card_x2 = nil
                  paragraphs.comments.card_y2 = nil
                  paragraphs.comments.manual_card_position_enabled = nil
                  paragraphs.comments.manual_card_x = nil
                  paragraphs.comments.manual_card_y = nil
                  paragraphs.comments.manual_card_dragging = nil
                  paragraphs.comments.manual_card_drag_start_mouse_x = nil
                  paragraphs.comments.manual_card_drag_start_mouse_y = nil
                  paragraphs.comments.manual_card_drag_start_card_x = nil
                  paragraphs.comments.manual_card_drag_start_card_y = nil
                  paragraphs.comments.active_card_locked_candidate = nil
                  paragraphs.comments.active_card_locked_candidate_id = nil
                end

                paragraphs.comments.former_card_wheel_shield_active = nil
                paragraphs.comments.former_card_x = nil
                paragraphs.comments.former_card_y = nil
                paragraphs.comments.former_card_x2 = nil
                paragraphs.comments.former_card_y2 = nil
                paragraphs.comments.former_card_wheel_idle_frames = nil

                paragraphs.comments.active_card_locked_candidate = nil
                paragraphs.comments.active_card_locked_candidate_id = nil
                paragraphs.comments.active_id = pending_primary_id
                paragraphs.comments.active_label = marker_word
                paragraphs.comments.active_x = sx
                paragraphs.comments.active_y = marker_anchor_y
                paragraphs.comments.active_group_key = group_key
                paragraphs.comments.active_group_comment_ids = active_group_comment_ids
                paragraphs.comments.active_marker_geometry_available = true
                paragraphs.comments.active_marker_visible = marker_visible
                paragraphs.comments.navigator_pending = nil
                paragraphs.comments.navigator_scroll_target_para = nil
                paragraphs.comments.navigator_marker_scroll_attempts = nil
                paragraphs.comments.navigator_marker_scroll_waiting_for_visible = nil
                comment_marker_clicked = true
              end
            end
          end

          local marker_col = (marker_hovered or marker_active) and link_hover_col or C_TEXT
          local marker_bg = rgba(
            UI_DOCX_COMMENT_RANGE_HIGHLIGHT_RGBA[1],
            UI_DOCX_COMMENT_RANGE_HIGHLIGHT_RGBA[2],
            UI_DOCX_COMMENT_RANGE_HIGHLIGHT_RGBA[3],
            UI_DOCX_COMMENT_RANGE_HIGHLIGHT_RGBA[4]
          )

          if marker_hovered then
            set_doc_hover("marker", group_key)
          end

          if marker_hovered and mouse_clicked and paragraphs.comments then
            paragraphs.comments.navigator_pending = nil
            paragraphs.comments.navigator_scroll_target_para = nil
            paragraphs.comments.navigator_marker_scroll_attempts = nil
            paragraphs.comments.navigator_marker_scroll_waiting_for_visible = nil

            local same_active_marker = paragraphs.comments.active_group_key == group_key
            if not paragraphs.comments.active_group_key then
              same_active_marker = paragraphs.comments.active_id == primary_ref.comment_id
            end

            if same_active_marker then
              -- Clicking the already-active marker is a real toggle-close action,
              -- not an outside click and not a re-open in the same frame.
              -- Keep comment_marker_clicked=true so the outside-click guard does
              -- not race this close action.
              paragraphs.comments.active_id = nil
              paragraphs.comments.active_label = nil
              paragraphs.comments.active_x = nil
              paragraphs.comments.active_y = nil
              paragraphs.comments.active_group_key = nil
              paragraphs.comments.active_group_comment_ids = nil
              paragraphs.comments.card_scroll_y = nil
              paragraphs.comments.card_scroll_max_y = nil
              paragraphs.comments.card_x = nil
              paragraphs.comments.card_y = nil
              paragraphs.comments.card_x2 = nil
              paragraphs.comments.card_y2 = nil
              paragraphs.comments.manual_card_position_enabled = nil
              paragraphs.comments.manual_card_x = nil
              paragraphs.comments.manual_card_y = nil
              paragraphs.comments.manual_card_dragging = nil
              paragraphs.comments.manual_card_drag_start_mouse_x = nil
              paragraphs.comments.manual_card_drag_start_mouse_y = nil
              paragraphs.comments.manual_card_drag_start_card_x = nil
              paragraphs.comments.manual_card_drag_start_card_y = nil
              paragraphs.comments.active_card_locked_candidate = nil
              paragraphs.comments.active_card_locked_candidate_id = nil
              paragraphs.comments.former_card_wheel_shield_active = nil
              paragraphs.comments.former_card_x = nil
              paragraphs.comments.former_card_y = nil
              paragraphs.comments.former_card_x2 = nil
              paragraphs.comments.former_card_y2 = nil
              paragraphs.comments.former_card_wheel_idle_frames = nil
              comment_marker_clicked = true
            else
              local switching_group = paragraphs.comments.active_group_key ~= group_key
              if not paragraphs.comments.active_group_key then
                switching_group = paragraphs.comments.active_id ~= primary_ref.comment_id
              end

              if switching_group then
                -- Switching between distinct same-anchor groups must start the
                -- card at the top and must not inherit stale geometry/scroll
                -- values from the previously active comment/group.
                paragraphs.comments.card_scroll_y = 0
                paragraphs.comments.card_scroll_max_y = nil
                paragraphs.comments.card_x = nil
                paragraphs.comments.card_y = nil
                paragraphs.comments.card_x2 = nil
                paragraphs.comments.card_y2 = nil
                paragraphs.comments.manual_card_position_enabled = nil
                paragraphs.comments.manual_card_x = nil
                paragraphs.comments.manual_card_y = nil
                paragraphs.comments.manual_card_dragging = nil
                paragraphs.comments.manual_card_drag_start_mouse_x = nil
                paragraphs.comments.manual_card_drag_start_mouse_y = nil
                paragraphs.comments.manual_card_drag_start_card_x = nil
                paragraphs.comments.manual_card_drag_start_card_y = nil
                paragraphs.comments.active_card_locked_candidate = nil
                paragraphs.comments.active_card_locked_candidate_id = nil
              end

              -- A newly opened/switched card owns this screen area again.
              -- Clear any stale former-card wheel shield left by an Escape close.
              paragraphs.comments.former_card_wheel_shield_active = nil
              paragraphs.comments.former_card_x = nil
              paragraphs.comments.former_card_y = nil
              paragraphs.comments.former_card_x2 = nil
              paragraphs.comments.former_card_y2 = nil
              paragraphs.comments.former_card_wheel_idle_frames = nil

              local active_group_comment_ids = {}
              for _, group_ref in ipairs(refs) do
                if group_ref.comment_id and group_ref.comment_id ~= "" then
                  active_group_comment_ids[#active_group_comment_ids + 1] = group_ref.comment_id
                end
              end

              DOCX_IMPORT.print_comment_order_marker_click_diag(
                paragraphs.comments,
                group_key,
                para_index,
                token_index or 0,
                refs,
                active_group_comment_ids,
                primary_ref,
                sx,
                sy
              )

              paragraphs.comments.active_card_locked_candidate = nil
              paragraphs.comments.active_card_locked_candidate_id = nil
              paragraphs.comments.active_id = primary_ref.comment_id
              paragraphs.comments.active_label = marker_word
              paragraphs.comments.active_x = sx
              paragraphs.comments.active_y = sy + lh
              paragraphs.comments.active_group_key = group_key
              paragraphs.comments.active_group_comment_ids = active_group_comment_ids
              -- v2.0.82: на первом клике marker_active уже был посчитан выше
              -- как false, поэтому общий блок обновления геометрии active marker-а
              -- не сработает в этот же кадр. Явно помечаем геометрию
              -- открытого/переключённого маркера как доступную, иначе
              -- offscreen-close guard сразу снесёт только что открытую карточку.
              paragraphs.comments.active_marker_geometry_available = true
              paragraphs.comments.active_marker_visible = marker_visible
              comment_marker_clicked = true
            end
          end

          line_tokens[#line_tokens + 1] = {
            tok={},
            token_index="marker",
            line_width_before=line_width,
            word=marker_word,
            word_w=marker_w,
            sx=sx,
            sy=sy,
            bg=nil,
            fg=marker_col,
            token_font=marker_font,
            visible=marker_visible,
            marker_bg=marker_bg,
            search_hit=false,
            safe_href=nil,
            link_hovered=false,
            is_comment_marker=true,
            comment_ref=primary_ref,
            comment_refs=refs,
            comment_marker_hovered=marker_hovered,
            gap_after=space_w,
          }

          line_width = line_width + marker_w + space_w
          psv_profiler_doc_block_end("comments_links_markers", doc_t_comment_marker)
        end

        reset_line_state()
        append_comment_refs_after(0)

        for tok_index, tok in ipairs(para.tokens) do
          psv_profiler_doc_count("tokens_seen", 1)
          if tok.newline then
            if #line_tokens > 0 then
              flush_visual_line()
              move_to_next_line()
            end
            reset_line_state()
            append_comment_refs_after(tok_index)
          else
            local word = tok.text
            local token_font = nil

            if tok.bold and tok.italic then
              token_font = get_font(px, "bold_italic") or get_font(px, "italic") or get_font(px, "bold")
            elseif tok.bold then
              token_font = get_font(px, "bold")
            elseif tok.italic then
              token_font = get_font(px, "italic")
            end

            local word_w = calc_word_width(word, token_font)
            local safe_href = token_safe_href(tok)
            local token_is_search_hit = has_filter and token_hit_lookup[para_index] and token_hit_lookup[para_index][tok_index] or false
            local remaining_line_w = max_sx - (line_start_sx + line_width)
            local text_column_w = math.max(1, max_sx - para_sx)

            if DOCX_IMPORT.long_token_layout_diag_enabled
               and DOCX_IMPORT.long_token_layout_diag_enabled() then
              DOCX_IMPORT.maybe_print_long_token_layout_diag(
                file_path,
                para_index,
                tok_index,
                tok,
                word,
                word_w,
                text_column_w,
                remaining_line_w,
                max_sx,
                para_sx,
                safe_href,
                line_width
              )
            end

            local word_is_unbreakable = type(word) == "string" and word ~= "" and not word:find("%s")
            local plain_url_like = word_is_unbreakable and not safe_href and is_plain_url_like_unbreakable_text(word)
            local word_needs_wrapped_split = word_is_unbreakable and (
              (safe_href and (word_w > remaining_line_w or word_w > text_column_w))
              or (plain_url_like and (word_w > remaining_line_w or word_w > text_column_w))
              or ((not safe_href) and (not plain_url_like) and word_w > text_column_w)
            )

            if word_needs_wrapped_split then
              add_wrapped_unbreakable_token(tok, token_font, safe_href, token_is_search_hit, tok_index)
            else
              if word_is_unbreakable
                 and not safe_href
                 and #line_tokens == 0
                 and word_w > remaining_line_w
                 and word_w <= text_column_w
                 and line_start_cx ~= para_line_cx then
                move_to_next_line()
                reset_line_state()
              end
              add_line_token(tok, word, word_w, token_font, safe_href, token_is_search_hit, space_w, tok_index)
            end

            append_comment_refs_after(tok_index)
          end
        end

        if #line_tokens > 0 then
          flush_visual_line()
          reaper.ImGui_NewLine(ctx)
        end
        reaper.ImGui_PopFont(ctx)

        if para.is_heading then
          reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Separator(), C_LINE)
          reaper.ImGui_Separator(ctx)
          reaper.ImGui_PopStyleColor(ctx)
        end

        -- В full-document search mode поиск не должен менять layout документа.
        -- Matching paragraphs остаются в обычном потоке с тем же paragraph_spacing;
        -- search-hit indication остаётся только token-level overlay, без высотных
        -- Dummy/Separator эффектов вокруг абзаца.
        if paragraph_spacing > 0 then
          reaper.ImGui_Dummy(ctx, 0, paragraph_spacing)
        end
        end
      end

      psv_profiler_doc_block_end("visible_paragraph_render", doc_t_visible_para)

      if paragraphs.comments and type(paragraphs.comments.navigator_pending) == "table" then
        local pending_nav = paragraphs.comments.navigator_pending
        if pending_nav.paragraph_index == para_index and pending_nav._matched_this_frame ~= true then
          paragraphs.comments.navigator_pending = nil
          paragraphs.comments.navigator_scroll_target_para = nil
          paragraphs.comments.navigator_marker_scroll_attempts = nil
          paragraphs.comments.navigator_marker_scroll_waiting_for_visible = nil
        end
      end

      local para_end_cy = select(2, reaper.ImGui_GetCursorPos(ctx))
      local new_cached_para_h = math.max(0, para_end_cy - para_start_cy)
      if layout_audit_enabled then
        psv_layout_audit_cache_update(file_path, para_index, cached_para_h, new_cached_para_h, para_start_cy, layout_audit_para_line_jumps, layout_audit_para_start_pushes, layout_audit_page_params)
        psv_layout_audit_msg(file_path,
          "PARA_END i=" .. tostring(para_index) ..
          " start_y=" .. psv_layout_audit_num(para_start_cy) ..
          " end_y=" .. psv_layout_audit_num(para_end_cy) ..
          " measured_h=" .. psv_layout_audit_num(new_cached_para_h) ..
          " rendered=true line_jumps=" .. tostring(layout_audit_para_line_jumps or 0) ..
          " start_pushes=" .. tostring(layout_audit_para_start_pushes or 0),
          "PARA_END:" .. tostring(para_index) .. ":" .. psv_layout_audit_num(para_start_cy))
      end
      paragraph_heights[para_index] = new_cached_para_h
      body_render_cache.paragraph_start_y[para_index] = para_start_cy
    end

    ::continue_paragraph::
  end
  psv_render_spacing_diag_finish_document()
  psv_profiler_doc_block_end("paragraph_loop", doc_t_paragraph_loop)
  if layout_audit_enabled then
    psv_layout_audit_segment_summary(file_path)
  end

  -- Page-stack bottom gap: после последнего абзаца расширяем реальный
  -- ImGui layout до нижнего края последней фиксированной визуальной страницы
  -- плюс внешний PAGE_STACK_BOTTOM_GAP. Это не меняет PAGE_H и не делает
  -- последнюю страницу адаптивной; пользователь может проскроллить пустую
  -- часть белого листа и внешний app/background-зазор под ним.
  if page_flow_enabled then
    local current_y = select(2, reaper.ImGui_GetCursorPos(ctx))
    local page_stack_bottom_gap = math.max(0, tonumber(PAGE_STACK_BOTTOM_GAP) or 0)
    local relative_y = current_y - page_stack_top_gap
    local last_page_index = 0
    if relative_y > 0 then
      last_page_index = math.floor(relative_y / page_slot_h)
    end

    local last_page_bottom = page_stack_top_gap + last_page_index * page_slot_h + page_h
    local target_document_bottom = last_page_bottom + page_stack_bottom_gap

    if current_y < target_document_bottom then
      reaper.ImGui_Dummy(ctx, 0, target_document_bottom - current_y)
    end
  end

  -- Compact drawlist comment card MVP. Active state is kept under
  -- paragraphs.comments so it is naturally scoped to the loaded document and
  -- does not increase the main-chunk local count.
  if paragraphs.comments and paragraphs.comments.active_id then
    local active_id = paragraphs.comments.active_id
    -- Visible card header is intentionally generic. Recovered Google Docs
    -- labels remain stored in the parser data model, but are not shown.
    local label = "comment:"
    local comment_blocks = {}
    local active_group_comment_ids = paragraphs.comments.active_group_comment_ids

    if type(active_group_comment_ids) == "table" and #active_group_comment_ids > 0 then
      -- Preserve same-anchor source order exactly as stored by the marker click path.
      -- Do not infer reply semantics and do not sort by any id/label suffix.
      for _, comment_id in ipairs(active_group_comment_ids) do
        local comment_data = paragraphs.comments.by_id and paragraphs.comments.by_id[comment_id] or nil
        local comment_text = trim(tostring(comment_data and comment_data.text or ""))
        if comment_text == "" then
          comment_text = "No comment text found."
        end
        comment_blocks[#comment_blocks + 1] = {
          id=comment_id,
          author=comment_data and comment_data.author or nil,
          date=comment_data and comment_data.date or nil,
          label=comment_data and comment_data.label or nil,
          text=comment_text,
          urls=comment_url.extract_plain_urls(comment_text),
        }
      end
    else
      local comment_data = paragraphs.comments.by_id and paragraphs.comments.by_id[active_id] or nil
      local comment_text = trim(tostring(comment_data and comment_data.text or ""))
      if comment_text == "" then
        comment_text = "No comment text found."
      end
      comment_blocks[#comment_blocks + 1] = {
        id=active_id,
        author=comment_data and comment_data.author or nil,
        date=comment_data and comment_data.date or nil,
        label=comment_data and comment_data.label or nil,
        text=comment_text,
        urls=comment_url.extract_plain_urls(comment_text),
      }
    end

    if #comment_blocks == 0 then
      comment_blocks[1] = {
        text="No comment text found.",
        urls={},
      }
    end

    DOCX_IMPORT.print_comment_order_card_blocks_diag(
      paragraphs.comments,
      active_id,
      active_group_comment_ids,
      comment_blocks
    )

    local imgui_child_renderer_active = type(PSV_COMMENT_CARD_RENDERER) == "table"
      and PSV_COMMENT_CARD_RENDERER.mode == "imgui_child"
      and type(PSV_COMMENT_CARD_RENDERER.render_imgui_child_scaffold) == "function"

    if imgui_child_renderer_active then
      if paragraphs.comments.active_marker_geometry_available
         or paragraphs.comments.manual_card_position_enabled == true then
        -- Prepare exactly one current active-comment native overlay. In anchored
        -- mode it uses fresh marker geometry; in manual mode it uses the stored
        -- dragged card position and is allowed to stay visible even if the marker
        -- later scrolls away. The card is not clamped to the viewport; anchored
        -- mode still closes before submission when the card rect leaves body bounds.
        -- The actual ImGui_Begin/BeginChild submission happens after ##body ends,
        -- so the native window remains a sibling of the body child.
        PSV_COMMENT_CARD_RENDERER.pending_args = {
          ctx=ctx,
          comments=paragraphs.comments,
          active_id=active_id,
          active_group_comment_ids=active_group_comment_ids,
          comment_blocks=comment_blocks,
          active_x=paragraphs.comments.active_x,
          active_y=paragraphs.comments.active_y,
          body_window_x=select(1, reaper.ImGui_GetWindowPos(ctx)),
          body_window_y=select(2, reaper.ImGui_GetWindowPos(ctx)),
          body_window_w=select(1, reaper.ImGui_GetWindowSize(ctx)),
          body_window_h=select(2, reaper.ImGui_GetWindowSize(ctx)),
          body_vertical_scrollbar_visible=(reaper.ImGui_GetScrollMaxY(ctx) > 0),
          body_vertical_scrollbar_reserved_w=UI_COMMENT_CARD_BODY_SCROLLBAR_RESERVED_W,
          mouse_x=mouse_x,
          mouse_y=mouse_y,
          mouse_clicked=mouse_clicked,
          comment_marker_clicked=comment_marker_clicked,
        }
      else
        -- Если active marker geometry вообще не появилась в этом кадре
        -- (например, параграф уже не отрендерен/culling), это настоящий close,
        -- а не временное hide/reappear. При обратной прокрутке карточка сама
        -- не восстанавливается: пользователь заново открывает marker кликом.
        PSV_COMMENT_CARD_RENDERER.pending_args = nil
        paragraphs.comments.active_id = nil
        paragraphs.comments.active_label = nil
        paragraphs.comments.active_x = nil
        paragraphs.comments.active_y = nil
        paragraphs.comments.active_group_key = nil
        paragraphs.comments.active_group_comment_ids = nil
        paragraphs.comments.active_marker_visible = nil
        paragraphs.comments.active_marker_geometry_available = nil
        paragraphs.comments.card_scroll_y = nil
        paragraphs.comments.card_scroll_max_y = nil
        paragraphs.comments.card_x = nil
        paragraphs.comments.card_y = nil
        paragraphs.comments.card_x2 = nil
        paragraphs.comments.card_y2 = nil
        paragraphs.comments.manual_card_position_enabled = nil
        paragraphs.comments.manual_card_x = nil
        paragraphs.comments.manual_card_y = nil
        paragraphs.comments.manual_card_dragging = nil
        paragraphs.comments.manual_card_drag_start_mouse_x = nil
        paragraphs.comments.manual_card_drag_start_mouse_y = nil
        paragraphs.comments.manual_card_drag_start_card_x = nil
        paragraphs.comments.manual_card_drag_start_card_y = nil
        paragraphs.comments.active_card_locked_candidate = nil
        paragraphs.comments.active_card_locked_candidate_id = nil
      end
    else
      if escape_key_owner == "comment"
         and reaper.ImGui_IsKeyPressed
         and reaper.ImGui_Key_Escape
         and reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Escape(), false) then
      -- Former-card wheel shield.
      -- If Escape closes the drawlist card while the mouse is still over it,
      -- residual trackpad/wheel momentum must not fall through to the body
      -- document that is revealed underneath the same screen rectangle.
      -- The shield is rect-based, but not permanent: it releases after a short
      -- zero-wheel idle streak, so ordinary body wheel-scroll resumes without
      -- requiring a mouse move or focus reset.
      local former_card_x = tonumber(paragraphs.comments.card_x)
      local former_card_y = tonumber(paragraphs.comments.card_y)
      local former_card_x2 = tonumber(paragraphs.comments.card_x2)
      local former_card_y2 = tonumber(paragraphs.comments.card_y2)
      if former_card_x and former_card_y and former_card_x2 and former_card_y2
         and mouse_x >= former_card_x and mouse_x <= former_card_x2
         and mouse_y >= former_card_y and mouse_y <= former_card_y2 then
        paragraphs.comments.former_card_wheel_shield_active = true
        paragraphs.comments.former_card_x = former_card_x
        paragraphs.comments.former_card_y = former_card_y
        paragraphs.comments.former_card_x2 = former_card_x2
        paragraphs.comments.former_card_y2 = former_card_y2
        paragraphs.comments.former_card_wheel_idle_frames = 0
      else
        paragraphs.comments.former_card_wheel_shield_active = nil
        paragraphs.comments.former_card_x = nil
        paragraphs.comments.former_card_y = nil
        paragraphs.comments.former_card_x2 = nil
        paragraphs.comments.former_card_y2 = nil
        paragraphs.comments.former_card_wheel_idle_frames = nil
      end

      paragraphs.comments.active_id = nil
      paragraphs.comments.active_label = nil
      paragraphs.comments.active_x = nil
      paragraphs.comments.active_y = nil
      paragraphs.comments.active_group_key = nil
      paragraphs.comments.active_group_comment_ids = nil
      paragraphs.comments.card_scroll_y = 0
      paragraphs.comments.card_scroll_max_y = nil
      paragraphs.comments.card_x = nil
      paragraphs.comments.card_y = nil
      paragraphs.comments.card_x2 = nil
      paragraphs.comments.card_y2 = nil
      paragraphs.comments.manual_card_position_enabled = nil
      paragraphs.comments.manual_card_x = nil
      paragraphs.comments.manual_card_y = nil
      paragraphs.comments.manual_card_dragging = nil
      paragraphs.comments.manual_card_drag_start_mouse_x = nil
      paragraphs.comments.manual_card_drag_start_mouse_y = nil
      paragraphs.comments.manual_card_drag_start_card_x = nil
      paragraphs.comments.manual_card_drag_start_card_y = nil
      paragraphs.comments.active_card_locked_candidate = nil
      paragraphs.comments.active_card_locked_candidate_id = nil
    else
      local body_x, body_y = reaper.ImGui_GetWindowPos(ctx)
      local body_w, body_h = reaper.ImGui_GetWindowSize(ctx)
      local card_w = math.min(320, math.max(220, body_w - 24))
      local pad = 12
      local header_gap = 6
      local line_h = math.max(16, select(2, reaper.ImGui_CalcTextSize(ctx, "Mg")) + 3)
      local text_max_w = card_w - pad * 2
      local safe_body_h = math.max(54, body_h - 20)
      local card_min_h = math.min(96, safe_body_h)
      local card_max_h = math.max(card_min_h, safe_body_h)

      local function fit_comment_text_to_width(text, max_w)
        text = tostring(text or "")
        if select(1, reaper.ImGui_CalcTextSize(ctx, text)) <= max_w then
          return text
        end

        local ellipsis = "..."
        local ellipsis_w = select(1, reaper.ImGui_CalcTextSize(ctx, ellipsis))
        if ellipsis_w >= max_w then
          return ellipsis
        end

        local chars = {}
        if utf8 and utf8.codes and utf8.char then
          local ok = pcall(function()
            for _, codepoint in utf8.codes(text) do
              chars[#chars + 1] = utf8.char(codepoint)
            end
          end)
          if not ok then
            chars = {}
          end
        end
        if #chars == 0 then
          for i = 1, #text do
            chars[#chars + 1] = text:sub(i, i)
          end
        end

        local lo = 0
        local hi = #chars
        local best = ellipsis
        while lo <= hi do
          local mid = math.floor((lo + hi) / 2)
          local candidate = table.concat(chars, "", 1, mid) .. ellipsis
          local candidate_w = select(1, reaper.ImGui_CalcTextSize(ctx, candidate))
          if candidate_w <= max_w then
            best = candidate
            lo = mid + 1
          else
            hi = mid - 1
          end
        end
        return best
      end

      local wrapped_lines = {}
      local current_line = ""
      local total_text_h = 0
      local paragraph_gap_h = math.max(6, math.floor(line_h * 0.45 + 0.5))

      local function push_wrapped_line(line)
        line = trim(tostring(line or ""))
        if line ~= "" then
          wrapped_lines[#wrapped_lines + 1] = {
            text=line,
            y=total_text_h,
          }
          total_text_h = total_text_h + line_h
        end
      end

      local function finish_current_comment_line()
        if current_line ~= "" then
          push_wrapped_line(current_line)
          current_line = ""
        end
      end

      local function push_comment_paragraph_gap()
        finish_current_comment_line()
        if #wrapped_lines > 0 and not wrapped_lines[#wrapped_lines].is_gap then
          wrapped_lines[#wrapped_lines + 1] = {
            is_gap=true,
            y=total_text_h,
            h=paragraph_gap_h,
          }
          total_text_h = total_text_h + paragraph_gap_h
        end
      end

      local function append_word_to_lines(word)
        if current_line == "" then
          if select(1, reaper.ImGui_CalcTextSize(ctx, word)) <= text_max_w then
            current_line = word
          else
            -- Oversized unbreakable words remain conservative for this MVP:
            -- fit the visible part into one card line instead of introducing
            -- a character-level layout engine.
            push_wrapped_line(fit_comment_text_to_width(word, text_max_w))
          end
          return
        end

        local candidate = current_line .. " " .. word
        if select(1, reaper.ImGui_CalcTextSize(ctx, candidate)) <= text_max_w then
          current_line = candidate
        else
          push_wrapped_line(current_line)
          current_line = ""
          append_word_to_lines(word)
        end
      end

      local comment_separator_h = math.max(12, math.floor(line_h * 0.75 + 0.5))

      local function push_comment_block_separator()
        finish_current_comment_line()
        if #wrapped_lines > 0 then
          wrapped_lines[#wrapped_lines + 1] = {
            is_separator=true,
            y=total_text_h,
            h=comment_separator_h,
          }
          total_text_h = total_text_h + comment_separator_h
        end
      end

      local function trim_trailing_paragraph_gap()
        if #wrapped_lines > 0 and wrapped_lines[#wrapped_lines].is_gap then
          total_text_h = math.max(0, total_text_h - (wrapped_lines[#wrapped_lines].h or paragraph_gap_h))
          wrapped_lines[#wrapped_lines] = nil
        end
      end

      local function append_comment_text_block(block_text)
        local normalized_comment_text = tostring(block_text or "")
          :gsub("\r\n", "\n")
          :gsub("\r", "\n")
        local previous_raw_line_had_text = false

        -- Preserve paragraph structure per comment block. Same-anchor groups
        -- are separated outside this function, so paragraph gaps stay inside
        -- each stored comment text and separators stay between comment texts.
        for raw_line in (normalized_comment_text .. "\n"):gmatch("([^\n]*)\n") do
          local raw_trimmed = trim(raw_line)
          if raw_trimmed == "" then
            push_comment_paragraph_gap()
            previous_raw_line_had_text = false
          else
            if previous_raw_line_had_text then
              push_comment_paragraph_gap()
            end

            for word in raw_trimmed:gmatch("%S+") do
              append_word_to_lines(word)
            end

            previous_raw_line_had_text = true
          end
        end

        finish_current_comment_line()
        trim_trailing_paragraph_gap()
      end

      for block_index, block in ipairs(comment_blocks) do
        if block_index > 1 then
          push_comment_block_separator()
        end
        append_comment_text_block(comment_url.remove_urls_from_display_text(block.text, block.urls))
        finish_current_comment_line()
        total_text_h = comment_url.append_link_rows(ctx, wrapped_lines, total_text_h, line_h, text_max_w, block.urls)
      end

      if #wrapped_lines == 0 then
        wrapped_lines[1] = {
          text=fit_comment_text_to_width((comment_blocks[1] and comment_blocks[1].text) or "No comment text found.", text_max_w),
          y=0,
        }
        total_text_h = line_h
      end

      local header_h = line_h
      local text_area_top_extra = pad * 2 + header_h + header_gap
      local desired_card_h = math.max(
        card_min_h,
        text_area_top_extra + total_text_h
      )
      local card_h = math.min(desired_card_h, card_max_h)
      local text_view_h = math.max(line_h, card_h - text_area_top_extra)
      local scroll_max_y = math.max(0, total_text_h - text_view_h)
      local card_scroll_y = tonumber(paragraphs.comments.card_scroll_y) or 0

      local anchor_x = tonumber(paragraphs.comments.active_x) or (body_x + body_w - card_w - 14)
      local anchor_y = tonumber(paragraphs.comments.active_y) or (body_y + 14)
      local card_x_offset = 25
      local card_x = anchor_x + card_x_offset
      local card_y = anchor_y + 8

      if card_x + card_w > body_x + body_w - 10 then
        card_x = body_x + body_w - card_w - 10
      end
      if card_x < body_x + 10 then
        card_x = body_x + 10
      end
      if card_y + card_h > body_y + body_h - 10 then
        card_y = anchor_y - card_h - 8
      end
      if card_y < body_y + 10 then
        card_y = body_y + 10
      end

      local card_x2 = card_x + card_w
      local card_y2 = card_y + card_h
      local mouse_inside_card = mouse_x >= card_x and mouse_x <= card_x2
        and mouse_y >= card_y and mouse_y <= card_y2

      paragraphs.comments.card_x = card_x
      paragraphs.comments.card_y = card_y
      paragraphs.comments.card_x2 = card_x2
      paragraphs.comments.card_y2 = card_y2
      paragraphs.comments.card_scroll_max_y = scroll_max_y

      if scroll_max_y > 0 and mouse_inside_card then
        local wheel_y = select(1, reaper.ImGui_GetMouseWheel(ctx))
        if wheel_y ~= 0 then
          card_scroll_y = card_scroll_y - wheel_y * line_h * 3
        end
      end

      if card_scroll_y < 0 then
        card_scroll_y = 0
      elseif card_scroll_y > scroll_max_y then
        card_scroll_y = scroll_max_y
      end
      paragraphs.comments.card_scroll_y = card_scroll_y

      if mouse_clicked and not mouse_inside_card and not comment_marker_clicked then
        paragraphs.comments.active_id = nil
        paragraphs.comments.active_label = nil
        paragraphs.comments.active_x = nil
        paragraphs.comments.active_y = nil
        paragraphs.comments.active_group_key = nil
        paragraphs.comments.active_group_comment_ids = nil
        paragraphs.comments.card_scroll_y = 0
        paragraphs.comments.card_scroll_max_y = nil
        paragraphs.comments.card_x = nil
        paragraphs.comments.card_y = nil
        paragraphs.comments.card_x2 = nil
        paragraphs.comments.card_y2 = nil
        paragraphs.comments.manual_card_position_enabled = nil
        paragraphs.comments.manual_card_x = nil
        paragraphs.comments.manual_card_y = nil
        paragraphs.comments.manual_card_dragging = nil
        paragraphs.comments.manual_card_drag_start_mouse_x = nil
        paragraphs.comments.manual_card_drag_start_mouse_y = nil
        paragraphs.comments.manual_card_drag_start_card_x = nil
        paragraphs.comments.manual_card_drag_start_card_y = nil
        paragraphs.comments.active_card_locked_candidate = nil
        paragraphs.comments.active_card_locked_candidate_id = nil
      else
        local card_fill = rgba(80, 80, 80, 232)
        local card_border = rgba(220, 220, 220, 105)
        local card_text = rgba(245, 245, 245, 255)
        local card_link = rgba(198, 224, 255, 255)
        local card_link_hover = rgba(220, 235, 255, 255)
        local indicator_col = rgba(245, 245, 245, 96)
        local separator_col = rgba(245, 245, 245, 70)

        reaper.ImGui_DrawList_AddRectFilled(dl, card_x, card_y, card_x2, card_y2, card_fill, 9)
        reaper.ImGui_DrawList_AddRect(
          dl,
          card_x, card_y,
          card_x2, card_y2,
          card_border,
          9,
          reaper.ImGui_DrawFlags_None(),
          1.0
        )

        reaper.ImGui_DrawList_AddText(dl, card_x + pad, card_y + pad - 2, card_link, label)


        local text_x = card_x + pad
        local text_y1 = card_y + pad - 2 + header_h + header_gap
        local text_y2 = math.min(card_y2 - pad, text_y1 + text_view_h)
        local pushed_clip = false

        if reaper.ImGui_DrawList_PushClipRect and reaper.ImGui_DrawList_PopClipRect then
          local clip_ok = pcall(
            reaper.ImGui_DrawList_PushClipRect,
            dl,
            text_x,
            text_y1,
            card_x2 - pad,
            text_y2,
            true
          )
          if not clip_ok then
            clip_ok = pcall(
              reaper.ImGui_DrawList_PushClipRect,
              dl,
              text_x,
              text_y1,
              card_x2 - pad,
              text_y2
            )
          end
          pushed_clip = clip_ok
        end

        for _, item in ipairs(wrapped_lines) do
          local item_y = text_y1 + item.y - card_scroll_y
          if item.is_link then
            if item_y + line_h >= text_y1 and item_y <= text_y2 then
              local link_text = tostring(item.text or item.url or "")
              local link_w, link_h = reaper.ImGui_CalcTextSize(ctx, link_text)
              local link_hovered = mouse_x >= text_x
                and mouse_x <= text_x + link_w
                and mouse_y >= item_y
                and mouse_y <= item_y + link_h
              local link_col = link_hovered and card_link_hover or card_link

              if link_hovered then
                want_hand_cursor = true
                if mouse_clicked then
                  open_or_copy_about_url(ctx, item.url)
                end
              end

              reaper.ImGui_DrawList_AddText(dl, text_x, item_y, link_col, link_text)
              reaper.ImGui_DrawList_AddLine(
                dl,
                text_x,
                item_y + link_h + 1,
                text_x + link_w,
                item_y + link_h + 1,
                link_col,
                1.0
              )
            end
          elseif item.text then
            if item_y + line_h >= text_y1 and item_y <= text_y2 then
              reaper.ImGui_DrawList_AddText(dl, text_x, item_y, card_text, item.text)
            end
          elseif item.is_separator then
            local sep_y = item_y + math.floor((item.h or 0) * 0.5 + 0.5)
            if sep_y >= text_y1 and sep_y <= text_y2 then
              reaper.ImGui_DrawList_AddLine(
                dl,
                text_x,
                sep_y,
                card_x2 - pad,
                sep_y,
                separator_col,
                1.0
              )
            end
          end
        end

        if pushed_clip then
          reaper.ImGui_DrawList_PopClipRect(dl)
        end

        if scroll_max_y > 0 then
          local track_x = card_x2 - 7
          local track_y1 = text_y1
          local track_y2 = text_y2
          local track_h = math.max(1, track_y2 - track_y1)
          local thumb_h = math.max(12, track_h * (text_view_h / math.max(text_view_h, total_text_h)))
          local thumb_y = track_y1
          if scroll_max_y > 0 then
            thumb_y = track_y1 + (track_h - thumb_h) * (card_scroll_y / scroll_max_y)
          end
          reaper.ImGui_DrawList_AddRectFilled(
            dl,
            track_x,
            thumb_y,
            track_x + 2,
            math.min(track_y2, thumb_y + thumb_h),
            indicator_col,
            1
          )
        end
      end
    end
    end
  end

  emit_doc_hover_diag_if_changed()

  want_hand_cursor = want_hand_cursor or (doc_hover_kind ~= nil)

  if want_hand_cursor
     and type(reaper.ImGui_SetMouseCursor) == "function"
     and type(reaper.ImGui_MouseCursor_Hand) == "function" then
    reaper.ImGui_SetMouseCursor(ctx, reaper.ImGui_MouseCursor_Hand())
  end

  if scroll_consumed then

    -- PSV_NAV_DIAG_BEGIN hook
    search_diag.record("scroll_target_consumed")
    -- PSV_NAV_DIAG_END hook
    search_nav_scroll_target = nil
    search_nav_occurrence = nil
  end

  -- В full-document search mode тело документа больше не заменяется
  -- сообщением "Ничего не найдено": документ остаётся видимым всегда,
  -- а состояние 0 результатов отражается в верхнем current/total indicator.
end

local function draw_empty_state_dashed_rect(dl, x1, y1, x2, y2, col, rounding, thickness)
  -- Локальный helper только для empty-state dropzone.
  -- Рисуем пунктир вручную через AddLine, не вводя новый глобальный UI primitive.
  local dash = 9
  local gap = 6

  local function dash_line(ax, ay, bx, by)
    local dx = bx - ax
    local dy = by - ay
    local len = math.sqrt(dx * dx + dy * dy)
    if len <= 0 then return end

    local ux = dx / len
    local uy = dy / len
    local pos = 0

    while pos < len do
      local seg_end = math.min(pos + dash, len)
      reaper.ImGui_DrawList_AddLine(
        dl,
        ax + ux * pos,
        ay + uy * pos,
        ax + ux * seg_end,
        ay + uy * seg_end,
        col,
        thickness
      )
      pos = pos + dash + gap
    end
  end

  local r = math.max(0, rounding or 0)

  -- Пунктир идёт по прямым участкам рамки. Скруглённый фон под ним
  -- сохраняет мягкую форму панели, а пунктир остаётся простым и стабильным.
  dash_line(x1 + r, y1, x2 - r, y1)
  dash_line(x2, y1 + r, x2, y2 - r)
  dash_line(x2 - r, y2, x1 + r, y2)
  dash_line(x1, y2 - r, x1, y1 + r)
end

local function draw_empty_state_folder_icon(dl, cx, cy, col)
  -- Простая drawlist-папка в той же палитре, что и остальной viewer.
  -- Без bitmap/assets и без заимствования отдельной цветовой системы.
  local w = 42
  local h = 30
  local x1 = cx - w * 0.5
  local y1 = cy - h * 0.5
  local rounding = 5

  reaper.ImGui_DrawList_AddRect(
    dl,
    x1, y1 + 7,
    x1 + w, y1 + h,
    col,
    rounding,
    reaper.ImGui_DrawFlags_None(),
    1.5
  )

  reaper.ImGui_DrawList_AddLine(dl, x1 + 4, y1 + 7, x1 + 16, y1 + 7, col, 1.5)
  reaper.ImGui_DrawList_AddLine(dl, x1 + 16, y1 + 7, x1 + 22, y1 + 12, col, 1.5)
  reaper.ImGui_DrawList_AddLine(dl, x1 + 22, y1 + 12, x1 + w - 4, y1 + 12, col, 1.5)
end

local function render_empty_hint(ctx)
  local dl = reaper.ImGui_GetWindowDrawList(ctx)
  local body_sx, body_sy = reaper.ImGui_GetCursorScreenPos(ctx)
  local avail_w, avail_h = reaper.ImGui_GetContentRegionAvail(ctx)
  if not PAGE_LAYOUT_ENABLED then
    reaper.ImGui_DrawList_AddRectFilled(dl,
      body_sx, body_sy,
      body_sx + avail_w, body_sy + avail_h,
      C_PAPER)
  end

  local cursor_x, cursor_y = reaper.ImGui_GetCursorPos(ctx)

  if empty_state_layout_warmup_frames > 0 then
    empty_state_layout_warmup_frames = empty_state_layout_warmup_frames - 1

    -- During the first empty-state body frame, submit only the real body item.
    -- This prevents the centered absolute panel from being drawn from a transient
    -- stale width and then visibly jumping to the corrected centered position.
    reaper.ImGui_SetCursorPos(ctx, cursor_x, cursor_y)
    reaper.ImGui_Dummy(ctx, avail_w, avail_h)
    return
  end

  local label = "Open script"
  local sublabel = "click to choose an HTML/DOCX file"

  local task_control_lines = {
    "Opening this script in another REAPER project tab for the first time?",
    "Task Control: enable “Remember” → “New instance”.",
  }

  local instruction_lines = {
    "Import formats:",
    "Google Docs HTML export: unzip and choose the .html file.",
    "Experimental DOCX import: choose a .docx file directly.",
  }

  -- Empty-state typography is intentionally fixed and independent from
  -- the document font size. All values stay function-local to avoid adding
  -- new main-chunk locals.
  local task_note_px = 11
  local title_px = 16
  local sublabel_px = 14
  local instruction_px = 16

  local panel_w = math.min(360, math.max(260, avail_w - 64))
  local panel_h = 132
  local panel_rounding = 12

  local function calc_text_size_at_px(text, px)
    local font = get_font(px)
    reaper.ImGui_PushFont(ctx, font, px)
    local text_w, text_h = reaper.ImGui_CalcTextSize(ctx, text)
    reaper.ImGui_PopFont(ctx)
    return text_w, text_h
  end

  local function draw_centered_text_at_px(text, y, col, px)
    local font = get_font(px)
    reaper.ImGui_PushFont(ctx, font, px)
    local text_w = select(1, reaper.ImGui_CalcTextSize(ctx, text))
    reaper.ImGui_DrawList_AddText(
      dl,
      body_sx + math.max(0, (avail_w - text_w) * 0.5),
      y,
      col,
      text
    )
    local _, text_h = reaper.ImGui_CalcTextSize(ctx, "Ay")
    reaper.ImGui_PopFont(ctx)
    return text_h
  end

  local label_w, label_h = calc_text_size_at_px(label, title_px)
  local sublabel_w, _ = calc_text_size_at_px(sublabel, sublabel_px)
  local task_line_h = select(2, calc_text_size_at_px("Ay", task_note_px))
  local instruction_line_h = select(2, calc_text_size_at_px("Ay", instruction_px))

  -- Open panel geometry restored from v1.3.109.
  -- The panel is centered independently: surrounding instruction text is anchored
  -- to this already-computed panel_y and never participates in panel centering.
  local panel_x = cursor_x + math.max(0, (avail_w - panel_w) * 0.5)
  local panel_y = cursor_y + math.max(28, (avail_h - panel_h) * 0.34)

  local task_line_gap = 2
  local instruction_line_gap = 3
  local gap_panel_to_instruction = 28 -- restored v1.3.109 panel-to-instruction gap
  local gap_instruction_to_task = task_line_h * 2

  local task_h =
    #task_control_lines * task_line_h
    + math.max(0, #task_control_lines - 1) * task_line_gap

  local instruction_h =
    #instruction_lines * instruction_line_h
    + math.max(0, #instruction_lines - 1) * instruction_line_gap

  -- Lower help block layout:
  --   1) Google Docs export instruction
  --   2) about two Task-note line heights of calm breathing room
  --   3) smaller/dimmer Task Control note
  -- The entire block is anchored below the independently centered Open panel.
  local instruction_top = panel_y + panel_h + gap_panel_to_instruction
  local task_top = instruction_top + instruction_h + gap_instruction_to_task
  local lower_block_bottom = task_top + task_h
  local max_lower_block_bottom = cursor_y + avail_h - 6

  if lower_block_bottom > max_lower_block_bottom then
    local overflow = lower_block_bottom - max_lower_block_bottom
    instruction_top = math.max(panel_y + panel_h + 6, instruction_top - overflow)
    task_top = instruction_top + instruction_h + gap_instruction_to_task
  end

  local task_note_col = rgba(150, 145, 136, 200)

  reaper.ImGui_SetCursorPos(ctx, panel_x, panel_y)
  reaper.ImGui_InvisibleButton(
    ctx,
    "##empty_open_html_panel",
    panel_w,
    panel_h,
    reaper.ImGui_ButtonFlags_MouseButtonLeft()
  )

  local panel_clicked = reaper.ImGui_IsItemClicked(ctx, reaper.ImGui_MouseButton_Left())
  local panel_hovered = reaper.ImGui_IsItemHovered(ctx, reaper.ImGui_HoveredFlags_None())

  local panel_sx, panel_sy = reaper.ImGui_GetItemRectMin(ctx)
  local panel_ex, panel_ey = reaper.ImGui_GetItemRectMax(ctx)
  local panel_bg = panel_hovered and C_VIEW_BUTTON_HOVER or C_FRAME
  local panel_border = panel_hovered and C_DIM or C_LINE

  reaper.ImGui_DrawList_AddRectFilled(
    dl,
    panel_sx, panel_sy,
    panel_ex, panel_ey,
    panel_bg,
    panel_rounding
  )
  draw_empty_state_dashed_rect(
    dl,
    panel_sx + 1, panel_sy + 1,
    panel_ex - 1, panel_ey - 1,
    panel_border,
    panel_rounding,
    1.2
  )

  if panel_clicked and not show_about_overlay then
    open_dialog()
  end

  local icon_cx = panel_sx + panel_w * 0.5
  local icon_cy = panel_sy + 33

  draw_empty_state_folder_icon(dl, icon_cx, icon_cy, C_DIM)

  local label_font = get_font(title_px)
  reaper.ImGui_PushFont(ctx, label_font, title_px)
  reaper.ImGui_DrawList_AddText(
    dl,
    panel_sx + (panel_w - label_w) * 0.5,
    panel_sy + 62,
    C_TEXT,
    label
  )
  reaper.ImGui_PopFont(ctx)

  local sublabel_font = get_font(sublabel_px)
  reaper.ImGui_PushFont(ctx, sublabel_font, sublabel_px)
  reaper.ImGui_DrawList_AddText(
    dl,
    panel_sx + (panel_w - sublabel_w) * 0.5,
    panel_sy + 62 + label_h + 5,
    C_DIM,
    sublabel
  )
  reaper.ImGui_PopFont(ctx)

  for i, line in ipairs(instruction_lines) do
    draw_centered_text_at_px(
      line,
      body_sy + (instruction_top - cursor_y) + (i - 1) * (instruction_line_h + instruction_line_gap),
      C_DIM,
      instruction_px
    )
  end

  for i, line in ipairs(task_control_lines) do
    draw_centered_text_at_px(
      line,
      body_sy + (task_top - cursor_y) + (i - 1) * (task_line_h + task_line_gap),
      task_note_col,
      task_note_px
    )
  end

  -- Возвращаем layout cursor в безопасное состояние после абсолютной
  -- drawlist-отрисовки и InvisibleButton, чтобы empty body не схлопывался.
  -- ВАЖНО: после SetCursorPos обязательно submit-им реальный ImGui item.
  -- Иначе ReaImGui/ImGui считает это cursor-only расширением child-boundary
  -- и может assert-нуться на ImGui_EndChild().
  reaper.ImGui_SetCursorPos(ctx, cursor_x, cursor_y)
  reaper.ImGui_Dummy(ctx, avail_w, avail_h)
end

local function render_about_overlay(ctx)
  if not show_about_overlay then return end

  -- Contact URL is intentionally function-local to avoid increasing the Lua
  -- main-chunk local count. v1.3.108 failed by adding more top-level locals.
  local contact_url = "https://github.com/patch-34"

  local dl = reaper.ImGui_GetWindowDrawList(ctx)
  if type(reaper.ImGui_GetForegroundDrawList) == "function" then
    local ok, foreground_dl = pcall(reaper.ImGui_GetForegroundDrawList, ctx)
    if ok and foreground_dl then
      dl = foreground_dl
    end
  end

  local win_x, win_y = reaper.ImGui_GetWindowPos(ctx)
  local win_w, win_h = reaper.ImGui_GetWindowSize(ctx)

  -- Compact card size. The card remains intentionally small and is clamped
  -- for narrow/tiny script windows without submitting any layout items.
  local panel_w = math.min(360, math.max(300, win_w - 48))
  local panel_h = math.min(240, math.max(220, win_h - 48))
  panel_w = math.min(panel_w, math.max(220, win_w - 24))
  panel_h = math.min(panel_h, math.max(180, win_h - 24))

  local panel_x = win_x + math.max(12, (win_w - panel_w) * 0.5)
  local panel_y = win_y + math.max(12, (win_h - panel_h) * 0.5)
  local panel_r = 12

  local panel_x2 = panel_x + panel_w
  local panel_y2 = panel_y + panel_h

  local mouse_x, mouse_y = reaper.ImGui_GetMousePos(ctx)

  local function point_in_rect(px, py, x1, y1, x2, y2)
    return px >= x1 and px <= x2 and py >= y1 and py <= y2
  end

  local mouse_inside_window = point_in_rect(mouse_x, mouse_y, win_x, win_y, win_x + win_w, win_y + win_h)
  local mouse_inside_panel = point_in_rect(mouse_x, mouse_y, panel_x, panel_y, panel_x2, panel_y2)

  if escape_key_owner == "about"
     and reaper.ImGui_IsKeyPressed
     and reaper.ImGui_Key_Escape
     and reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Escape(), false) then
    show_about_overlay = false
    return
  end

  local mouse_clicked = false
  if type(reaper.ImGui_IsMouseClicked) == "function" then
    local ok, clicked = pcall(
      reaper.ImGui_IsMouseClicked,
      ctx,
      reaper.ImGui_MouseButton_Left()
    )
    mouse_clicked = ok and clicked or false
  end

  local panel_fill = rgba(80, 80, 80, 218)
  local panel_border = rgba(220, 220, 220, 95)
  local panel_text = rgba(245, 245, 245, 255)
  local panel_dim = rgba(210, 210, 210, 255)
  local button_fill = rgba(105, 105, 105, 230)
  local button_hover = rgba(122, 122, 122, 235)
  local button_border = rgba(230, 230, 230, 80)
  local link_col = rgba(165, 205, 255, 255)
  local link_hover_col = rgba(198, 224, 255, 255)

  -- No full-window dim overlay here: only the compact card is drawn, so the
  -- About panel does not read as a full-window modal layer.
  reaper.ImGui_DrawList_AddRectFilled(
    dl,
    panel_x,
    panel_y,
    panel_x2,
    panel_y2,
    panel_fill,
    panel_r
  )
  reaper.ImGui_DrawList_AddRect(
    dl,
    panel_x,
    panel_y,
    panel_x2,
    panel_y2,
    panel_border,
    panel_r,
    reaper.ImGui_DrawFlags_None(),
    1.0
  )

  local text_x = panel_x + 20
  local text_y = panel_y + 17
  local line_gap = 16

  local function draw_line(text, y, color)
    reaper.ImGui_DrawList_AddText(dl, text_x, y, color, text)
  end

  local function draw_link(text, y, url)
    local link_w, link_h = reaper.ImGui_CalcTextSize(ctx, text)
    local hovered = point_in_rect(
      mouse_x,
      mouse_y,
      text_x,
      y,
      text_x + link_w,
      y + link_h
    )
    local col = hovered and link_hover_col or link_col

    if hovered
       and type(reaper.ImGui_SetMouseCursor) == "function"
       and type(reaper.ImGui_MouseCursor_Hand) == "function" then
      reaper.ImGui_SetMouseCursor(ctx, reaper.ImGui_MouseCursor_Hand())
    end

    reaper.ImGui_DrawList_AddText(dl, text_x, y, col, text)
    reaper.ImGui_DrawList_AddLine(
      dl,
      text_x,
      y + link_h + 1,
      text_x + link_w,
      y + link_h + 1,
      col,
      1.0
    )

    if mouse_clicked and hovered then
      open_or_copy_about_url(ctx, url)
      return true
    end

    return false
  end

  draw_line(SCRIPT_NAME, text_y, panel_text)
  draw_line("Version: v" .. tostring(PSV_SCRIPT_VERSION or "1.0.0"), text_y + line_gap, panel_dim)

  local body_y = text_y + line_gap * 2 + 8
  draw_line("Imports HTML and DOCX.", body_y, panel_text)
  draw_line("DOCX: text, colors/highlights, comments.", body_y + line_gap, panel_text)

  local author_y = body_y + line_gap * 2 + 8
  draw_line("Aleksei Vorobev / Patch34", author_y, panel_text)

  local contact_label_y = author_y + line_gap + 7
  draw_line("Contact:", contact_label_y, panel_dim)
  draw_link(contact_url, contact_label_y + line_gap, contact_url)

  local support_y = contact_label_y + line_gap * 2 + 7
  draw_line("Support:", support_y, panel_dim)
  draw_link(SUPPORT_URL, support_y + line_gap, SUPPORT_URL)

  local function draw_overlay_button(label, x, y, w, h)
    local hovered = point_in_rect(mouse_x, mouse_y, x, y, x + w, y + h)
    local fill = hovered and button_hover or button_fill

    reaper.ImGui_DrawList_AddRectFilled(dl, x, y, x + w, y + h, fill, 7)
    reaper.ImGui_DrawList_AddRect(
      dl,
      x,
      y,
      x + w,
      y + h,
      button_border,
      7,
      reaper.ImGui_DrawFlags_None(),
      1.0
    )

    local text_w, text_h = reaper.ImGui_CalcTextSize(ctx, label)
    reaper.ImGui_DrawList_AddText(
      dl,
      x + (w - text_w) * 0.5,
      y + (h - text_h) * 0.5,
      panel_text,
      label
    )

    return hovered and mouse_clicked
  end

  local button_y = panel_y2 - 38
  local close_w = 74
  local button_h = 26
  local close_x = panel_x2 - close_w - 20

  if draw_overlay_button("Close", close_x, button_y, close_w, button_h) then
    show_about_overlay = false
    return
  end

  -- Manual outside-click close. Because overlay controls are drawlist-only,
  -- no cursor-positioned ImGui items are submitted here and parent/window
  -- layout boundaries cannot be extended accidentally.
  if mouse_clicked and mouse_inside_window and not mouse_inside_panel then
    show_about_overlay = false
  end
end

-- ══════════════════════════════════════════════════════════════
--  MAIN LOOP
-- ══════════════════════════════════════════════════════════════

local WIN_FLAGS = reaper.ImGui_WindowFlags_MenuBar()

-- ══════════════════════════════════════════════════════════════
--  VIEW SETTINGS CONTROLS
-- ══════════════════════════════════════════════════════════════

-- Native double-click reset suppression state for custom View sliders.
-- Intentionally non-local to avoid adding main-chunk locals in this large script.
PSV_VIEW_SLIDER_DOUBLE_CLICK_STATE = PSV_VIEW_SLIDER_DOUBLE_CLICK_STATE or {
  suppress_drag_id = nil,
  suppress_until_mouse_up = false,
  suppress_frames = 0,
}

-- Extraction-only шаг:
-- текущие View controls вынесены из popup menu в отдельную функцию,
-- чтобы позже можно было безопасно переиспользовать тот же UI в movable
-- View Settings window. Визуал, переменные, ranges/defaults и поведение
-- должны остаться идентичными v1.3.54.
local function render_view_settings_controls(ctx)
  -- Geometry/visual tuning вынесены в верхний UI SETTINGS / COLOURS блок.
  -- Это extraction-only шаг: функция продолжает использовать те же state
  -- variables, ranges/defaults и reset behavior, что и v1.3.56.

  -- Локальный helper для clamp integer values.
  local function view_clamp_int(v, min_value, max_value)
    if v < min_value then return min_value end
    if v > max_value then return max_value end
    return math.floor(v + 0.5)
  end

  -- Локальный custom slider только для View menu.
  -- Контракт: drawlist track/fill/circular knob + InvisibleButton
  -- для click/drag interaction. Native SliderInt здесь не рисуется.
  local function view_custom_slider(id, value, min_value, max_value, width, reset_value)
    local sx, sy = reaper.ImGui_GetCursorScreenPos(ctx)
    local dl = reaper.ImGui_GetWindowDrawList(ctx)

    local track_x1 = sx
    local track_x2 = sx + width
    local track_y = sy + UI_VIEW_ROW_H * 0.5

    reaper.ImGui_InvisibleButton(
      ctx,
      "##view_slider_" .. id,
      width,
      UI_VIEW_ROW_H,
      reaper.ImGui_ButtonFlags_MouseButtonLeft()
    )

    local changed = false
    local new_value = value
    local is_active = reaper.ImGui_IsItemActive(ctx)
    local is_hovered = reaper.ImGui_IsItemHovered(ctx, reaper.ImGui_HoveredFlags_None())

    local dc_state = PSV_VIEW_SLIDER_DOUBLE_CLICK_STATE
    local reset_by_double_click = false
    if reset_value ~= nil
       and is_hovered
       and reaper.ImGui_IsMouseDoubleClicked(ctx, reaper.ImGui_MouseButton_Left()) then
      new_value = view_clamp_int(reset_value, min_value, max_value)
      changed = (new_value ~= value)
      reset_by_double_click = true
      dc_state.suppress_drag_id = id
      dc_state.suppress_until_mouse_up = true
      dc_state.suppress_frames = 2
    end

    local suppress_drag = false
    if not reset_by_double_click and dc_state.suppress_drag_id == id then
      if dc_state.suppress_until_mouse_up and reaper.ImGui_IsMouseDown(ctx, reaper.ImGui_MouseButton_Left()) then
        suppress_drag = true
      elseif dc_state.suppress_frames and dc_state.suppress_frames > 0 then
        suppress_drag = true
        dc_state.suppress_frames = dc_state.suppress_frames - 1
      else
        dc_state.suppress_drag_id = nil
        dc_state.suppress_until_mouse_up = false
        dc_state.suppress_frames = 0
      end
    end

    if is_active and not reset_by_double_click and not suppress_drag then
      local mouse_x = reaper.ImGui_GetMousePos(ctx)
      local t = 0
      if width > 0 and max_value > min_value then
        t = (mouse_x - track_x1) / width
      end
      if t < 0 then t = 0 end
      if t > 1 then t = 1 end

      new_value = view_clamp_int(min_value + (max_value - min_value) * t, min_value, max_value)
      changed = (new_value ~= value)
    end

    local t = 0
    if max_value > min_value then
      t = (new_value - min_value) / (max_value - min_value)
    end
    if t < 0 then t = 0 end
    if t > 1 then t = 1 end

    local knob_x = track_x1 + width * t

    reaper.ImGui_DrawList_AddRectFilled(
      dl,
      track_x1,
      track_y - UI_VIEW_SLIDER_TRACK_H * 0.5,
      track_x2,
      track_y + UI_VIEW_SLIDER_TRACK_H * 0.5,
      C_VIEW_SLIDER_TRACK
    )
    reaper.ImGui_DrawList_AddRectFilled(
      dl,
      track_x1,
      track_y - UI_VIEW_SLIDER_TRACK_H * 0.5,
      knob_x,
      track_y + UI_VIEW_SLIDER_TRACK_H * 0.5,
      C_VIEW_SLIDER_FILL
    )

    reaper.ImGui_DrawList_AddCircleFilled(
      dl,
      knob_x,
      track_y,
      UI_VIEW_SLIDER_KNOB_R,
      C_VIEW_SLIDER_KNOB_FILL,
      UI_VIEW_SLIDER_CIRCLE_SEGMENTS
    )
    reaper.ImGui_DrawList_AddCircle(
      dl,
      knob_x,
      track_y,
      UI_VIEW_SLIDER_KNOB_R,
      C_VIEW_SLIDER_KNOB_OUTLINE,
      UI_VIEW_SLIDER_CIRCLE_SEGMENTS,
      is_hovered and UI_VIEW_SLIDER_KNOB_OUTLINE_HOVER or UI_VIEW_SLIDER_KNOB_OUTLINE_NORMAL
    )

    return changed, new_value
  end

  -- Локальная custom button row для нижних reset-controls.
  -- Это отдельный View-menu visual polish слой: reset actions собраны
  -- в одну нижнюю строку и больше не разрывают секции слайдеров.
  local function view_custom_button(id, label, width, height)
    local sx, sy = reaper.ImGui_GetCursorScreenPos(ctx)
    local dl = reaper.ImGui_GetWindowDrawList(ctx)

    reaper.ImGui_InvisibleButton(
      ctx,
      "##view_button_" .. id,
      width,
      height,
      reaper.ImGui_ButtonFlags_MouseButtonLeft()
    )

    local hovered = reaper.ImGui_IsItemHovered(ctx, reaper.ImGui_HoveredFlags_None())
    local active = reaper.ImGui_IsItemActive(ctx)
    local clicked = reaper.ImGui_IsItemClicked(ctx, reaper.ImGui_MouseButton_Left())

    local fill_col = C_VIEW_BUTTON_FILL
    if active then
      fill_col = C_VIEW_BUTTON_ACTIVE
    elseif hovered then
      fill_col = C_VIEW_BUTTON_HOVER
    end

    reaper.ImGui_DrawList_AddRectFilled(
      dl,
      sx,
      sy,
      sx + width,
      sy + height,
      fill_col,
      UI_VIEW_BUTTON_ROUNDING
    )
    reaper.ImGui_DrawList_AddRect(
      dl,
      sx,
      sy,
      sx + width,
      sy + height,
      C_VIEW_BUTTON_BORDER,
      UI_VIEW_BUTTON_ROUNDING,
      reaper.ImGui_DrawFlags_None(),
      1.0
    )

    local text_w, text_h = reaper.ImGui_CalcTextSize(ctx, label)
    reaper.ImGui_DrawList_AddText(
      dl,
      sx + (width - text_w) * 0.5,
      sy + (height - text_h) * 0.5,
      C_VIEW_BUTTON_TEXT,
      label
    )

    return clicked
  end

  local function view_section(title)
    reaper.ImGui_Dummy(ctx, 0, UI_VIEW_SECTION_TOP_GAP)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), C_DIM)
    reaper.ImGui_Text(ctx, title)
    reaper.ImGui_PopStyleColor(ctx)
    reaper.ImGui_Separator(ctx)
    reaper.ImGui_Dummy(ctx, 0, UI_VIEW_SECTION_BOTTOM_GAP)
  end

  local function view_custom_slider_row(label, id, value, min_value, max_value, reset_value)
    local row_x, row_y = reaper.ImGui_GetCursorPos(ctx)

    reaper.ImGui_SetCursorPos(ctx, row_x, row_y + UI_VIEW_ROW_LABEL_Y_OFFSET)
    reaper.ImGui_Text(ctx, label)

    reaper.ImGui_SetCursorPos(ctx, row_x + UI_VIEW_LABEL_W, row_y)
    local changed, new_value = view_custom_slider(id, value, min_value, max_value, UI_VIEW_SLIDER_W, reset_value)

    local value_text = string.format("%d px", new_value)
    local value_text_w = select(1, reaper.ImGui_CalcTextSize(ctx, value_text))
    local value_x = row_x + UI_VIEW_LABEL_W + UI_VIEW_SLIDER_W + UI_VIEW_VALUE_GAP + UI_VIEW_VALUE_W - value_text_w

    reaper.ImGui_SetCursorPos(ctx, value_x, row_y + UI_VIEW_ROW_LABEL_Y_OFFSET)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), C_DIM)
    reaper.ImGui_Text(ctx, value_text)
    reaper.ImGui_PopStyleColor(ctx)

    reaper.ImGui_SetCursorPos(ctx, row_x, row_y + UI_VIEW_ROW_H + UI_VIEW_ROW_GAP)

    return changed, new_value
  end

  -- Font
  view_section("Font")

  local ch, nv = view_custom_slider_row(
    "Size",
    "fs",
    font_size,
    UI_FONT_SIZE_MIN,
    UI_FONT_SIZE_MAX,
    UI_FONT_SIZE_DEFAULT
  )
  if ch then
    font_size = nv
    reset_body_scroll_inertia()
    save_cfg()
  end

  local ch_cnf, nv_cnf = view_custom_slider_row(
    "Comments font",
    "comments_nav_font_size",
    comments_nav_font_size,
    UI_COMMENTS_NAV_FONT_SIZE_MIN,
    UI_COMMENTS_NAV_FONT_SIZE_MAX,
    UI_COMMENTS_NAV_FONT_SIZE_DEFAULT
  )
  if ch_cnf then
    comments_nav_font_size = clamp_comments_nav_font_size(nv_cnf)
    save_cfg()
  end

  -- Text margins
  view_section("Text margins")

  body_margin_left = clamp_body_text_margin(
    body_margin_left,
    UI_BODY_TEXT_MARGIN_LEFT_DEFAULT
  )
  body_margin_right = clamp_body_text_margin(
    body_margin_right,
    UI_BODY_TEXT_MARGIN_RIGHT_DEFAULT
  )

  -- One visible absolute paired control. Stored runtime variables remain
  -- separate for compatibility with older/asymmetrical session state, but the
  -- slider displays the actual current margin in px and touching it normalizes
  -- both sides to the selected paired value.
  local text_margin_value = view_clamp_int(
    math.max(
      clamp_body_text_margin(body_margin_left, UI_BODY_TEXT_MARGIN_LEFT_DEFAULT),
      clamp_body_text_margin(body_margin_right, UI_BODY_TEXT_MARGIN_RIGHT_DEFAULT)
    ),
    UI_BODY_TEXT_MARGIN_MIN,
    UI_BODY_TEXT_MARGIN_MAX
  )
  local text_margin_default = view_clamp_int(
    math.max(UI_BODY_TEXT_MARGIN_LEFT_DEFAULT, UI_BODY_TEXT_MARGIN_RIGHT_DEFAULT),
    UI_BODY_TEXT_MARGIN_MIN,
    UI_BODY_TEXT_MARGIN_MAX
  )
  local ch_tm, nv_tm = view_custom_slider_row(
    "Text margins",
    "text_margins",
    text_margin_value,
    UI_BODY_TEXT_MARGIN_MIN,
    UI_BODY_TEXT_MARGIN_MAX,
    text_margin_default
  )
  if ch_tm then
    body_margin_left = clamp_body_text_margin(nv_tm, UI_BODY_TEXT_MARGIN_LEFT_DEFAULT)
    body_margin_right = clamp_body_text_margin(nv_tm, UI_BODY_TEXT_MARGIN_RIGHT_DEFAULT)
    reset_body_scroll_inertia()
  end

  -- Typography
  view_section("Typography")

  -- Локальный флаг только для live-изменений вертикальной типографики.
  -- При перетаскивании Line spacing / Paragraph старые измеренные высоты
  -- абзацев и pending scroll-restore могут один-два кадра спорить с новой
  -- раскладкой body child. Сбрасываем только этот cache/restore слой,
  -- не трогая сам скролл, wheel speed и renderer.
  local typography_layout_changed = false

  local ch_ls, nv_ls = view_custom_slider_row(
    "Line spacing",
    "line_spacing",
    line_spacing,
    UI_LINE_SPACING_MIN,
    UI_LINE_SPACING_MAX,
    UI_LINE_SPACING_DEFAULT
  )
  if ch_ls then
    line_spacing = nv_ls
    typography_layout_changed = true
  end

  local ch_ps, nv_ps = view_custom_slider_row(
    "Paragraph",
    "paragraph_spacing",
    paragraph_spacing,
    UI_PARAGRAPH_SPACING_MIN,
    UI_PARAGRAPH_SPACING_MAX,
    UI_PARAGRAPH_SPACING_DEFAULT
  )
  if ch_ps then
    paragraph_spacing = nv_ps
    typography_layout_changed = true
  end

  -- Reset footer block:
  -- компактные labels ("Margins", "Typography", "All") оставлены короткими,
  -- а назначение блока теперь объясняется отдельной лёгкой Reset-меткой.
  -- Строка reset-кнопок заполняет ту же ширину, что и View controls.
  -- All по-прежнему сбрасывает font_size тоже и вызывает save_cfg().
  reaper.ImGui_Dummy(ctx, 0, UI_VIEW_RESET_SECTION_TOP_GAP)
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), C_DIM)
  reaper.ImGui_Text(ctx, "Reset")

  -- Reset separator привязан к измеренному rect текста "Reset", а не к
  -- cursor position после ImGui_Text(). Поэтому UI_VIEW_RESET_LABEL_TO_LINE_GAP
  -- теперь означает реальный gap от нижней границы label до линии.
  -- Это убирает native cursor-flow spacing без отрицательных Y-offset.
  local reset_label_min_x, _ = reaper.ImGui_GetItemRectMin(ctx)
  local _, reset_label_max_y = reaper.ImGui_GetItemRectMax(ctx)

  reaper.ImGui_PopStyleColor(ctx)

  local reset_line_x = reset_label_min_x
  local reset_line_y = reset_label_max_y + UI_VIEW_RESET_LABEL_TO_LINE_GAP
  local reset_line_dl = reaper.ImGui_GetWindowDrawList(ctx)
  reaper.ImGui_DrawList_AddLine(
    reset_line_dl,
    reset_line_x,
    reset_line_y,
    reset_line_x + UI_VIEW_CONTENT_W,
    reset_line_y,
    C_LINE,
    UI_VIEW_RESET_LINE_THICKNESS
  )

  -- Cursor для кнопок ставится от измеренной линии и явных reset-констант.
  -- Это measured layout, а не ручная отрицательная подгонка.
  local reset_cursor_x, reset_cursor_y = reaper.ImGui_GetCursorPos(ctx)
  local window_y = select(2, reaper.ImGui_GetWindowPos(ctx))
  local buttons_cursor_y =
    reset_line_y - window_y + UI_VIEW_RESET_LINE_THICKNESS + UI_VIEW_RESET_LINE_TO_BUTTON_GAP
  reaper.ImGui_SetCursorPos(ctx, reset_cursor_x, buttons_cursor_y)

  if view_custom_button("reset_margins", "Margins", UI_VIEW_RESET_BUTTON_W, UI_VIEW_BUTTON_H) then
    body_margin_left = UI_BODY_TEXT_MARGIN_LEFT_DEFAULT
    body_margin_right = UI_BODY_TEXT_MARGIN_RIGHT_DEFAULT
    reset_body_scroll_inertia()
  end

  reaper.ImGui_SameLine(ctx, 0, UI_VIEW_BUTTON_GAP)
  if view_custom_button(
    "reset_typography",
    "Typography",
    UI_VIEW_RESET_BUTTON_W,
    UI_VIEW_BUTTON_H
  ) then
    -- Visible Typography controls are Line spacing and Paragraph.
    -- first_line_indent remains fixed internally and is reset here as a safety no-op.
    first_line_indent = UI_FIRST_LINE_INDENT_DEFAULT
    line_spacing = UI_LINE_SPACING_DEFAULT
    paragraph_spacing = UI_PARAGRAPH_SPACING_DEFAULT
    typography_layout_changed = true
  end

  reaper.ImGui_SameLine(ctx, 0, UI_VIEW_BUTTON_GAP)
  if view_custom_button("reset_all", "All", UI_VIEW_RESET_BUTTON_W, UI_VIEW_BUTTON_H) then
    font_size = UI_FONT_SIZE_DEFAULT
    comments_nav_font_size = UI_COMMENTS_NAV_FONT_SIZE_DEFAULT
    body_margin_left = UI_BODY_TEXT_MARGIN_LEFT_DEFAULT
    body_margin_right = UI_BODY_TEXT_MARGIN_RIGHT_DEFAULT
    first_line_indent = UI_FIRST_LINE_INDENT_DEFAULT
    line_spacing = UI_LINE_SPACING_DEFAULT
    paragraph_spacing = UI_PARAGRAPH_SPACING_DEFAULT
    typography_layout_changed = true
    save_cfg()
  end

  if typography_layout_changed then
    -- Принудительно инвалидируем только измерения body-layout.
    -- Следующий render_paragraphs() пересоберёт paragraph_heights уже
    -- с новым Line spacing / Paragraph, а live scroll останется на текущей
    -- позиции вместо сброса наверх.
    body_render_cache.layout_key = ""
    body_render_cache.paragraph_heights = {}
    body_render_cache.paragraph_start_y = {}

    -- Любой отложенный project-scroll restore после смены типографики
    -- больше не должен переустанавливать старый Y поверх новой высоты документа.
    pending_body_scroll_y = nil
    pending_body_scroll_restore_frames = 0
    reset_body_scroll_inertia()

    -- current_body_scroll_y уже обновляется из ##body каждый кадр.
    -- Здесь только сохраняем последнее реальное значение в project-local map,
    -- если оно известно, не вызывая SetScrollY() и не меняя wheel contract.
    if last_proj_key and current_body_scroll_y ~= nil then
      project_body_scroll_y[last_proj_key] = current_body_scroll_y
    end
  end

end

local function render_hidden_owner_mismatch_frame(ctx)
  local flags = 0
  local function add_window_flag(name)
    local fn = reaper["ImGui_WindowFlags_" .. name]
    if not fn then return end

    local ok, value = pcall(fn)
    if ok and type(value) == "number" then
      flags = flags | value
    end
  end

  add_window_flag("NoDecoration")
  add_window_flag("NoInputs")
  add_window_flag("NoSavedSettings")
  add_window_flag("NoMove")
  add_window_flag("NoResize")
  add_window_flag("NoScrollbar")
  add_window_flag("NoScrollWithMouse")
  add_window_flag("NoFocusOnAppearing")
  add_window_flag("NoBringToFrontOnFocus")

  reaper.ImGui_SetNextWindowPos(ctx, -10000, -10000, reaper.ImGui_Cond_Always())
  reaper.ImGui_SetNextWindowSize(ctx, 1, 1, reaper.ImGui_Cond_Always())
  if reaper.ImGui_SetNextWindowBgAlpha then
    reaper.ImGui_SetNextWindowBgAlpha(ctx, 0)
  end

  local visible = reaper.ImGui_Begin(ctx, "##PodcastScriptViewerHiddenMaintenance", true, flags)
  if visible then
    reaper.ImGui_End(ctx)
  end
end

function loop()

  -- PSV_NAV_DIAG_BEGIN hook
  search_diag.frame = search_diag.frame + 1
  -- PSV_NAV_DIAG_END hook
  PSV_PROFILER_FRAME_T0 = psv_profiler_frame_begin("loop")
  ensure_imgui_resources()
  apply_pending_ui_theme_if_needed()
  local cur_project = reaper.EnumProjects(-1, "")
  local cur_key = get_project_key()

  if not owner_project then
    owner_project = cur_project
  end
  if not owner_project_key then
    owner_project_key = cur_key
  end

  if cur_project ~= owner_project then
    if not owner_project_is_open() then
      -- The owner was closed. Do not keep an invisible defer loop alive or
      -- write file state into whichever project became active instead.
      save_project_ui_state(owner_project_key)
      win_open = false
      psv_profiler_frame_end(PSV_PROFILER_FRAME_T0, "owner_closed")
      return
    end
    owner_mismatch_hidden_last_frame = true
    render_hidden_owner_mismatch_frame(ctx)
    psv_profiler_frame_end(PSV_PROFILER_FRAME_T0, "owner_mismatch_hidden")
    reaper.defer(loop)
    return
  end

  sync_owner_project_key(cur_key)

  if owner_mismatch_hidden_last_frame then
    owner_mismatch_hidden_last_frame = false
    if not file_path or file_path == "" or #paragraphs == 0 then
      request_empty_state_layout_warmup()
    end
  end

  if cur_key ~= last_proj_key then
    -- Перед сменой project key сохраняем последнюю известную позицию
    -- scroll Y старого body child. Читать реальный scroll можно только внутри
    -- BeginChild("##body"), поэтому здесь используем последнее значение,
    -- обновлённое в предыдущем body-frame.
    if last_proj_key and current_body_scroll_y ~= nil then
      project_body_scroll_y[last_proj_key] = current_body_scroll_y
    end

    if last_proj_key then
      save_project_ui_state(last_proj_key)
    end

    last_proj_key = cur_key
    load_project_ui_state(cur_key)
    load_file_for_project()

    -- После загрузки состояния нового проекта готовим короткий pending restore.
    -- Применять scroll можно только внутри ##body, а первые кадры после reload
    -- могут ещё стабилизировать content height/culling cache, поэтому держим
    -- restore несколько кадров и затем автоматически отпускаем управление.
    local restore_y = project_body_scroll_y[cur_key]
    if restore_y and #paragraphs > 0 then
      pending_body_scroll_y = restore_y
      pending_body_scroll_restore_frames = 3
      current_body_scroll_y = restore_y
    else
      pending_body_scroll_y = nil
      pending_body_scroll_restore_frames = 0
      current_body_scroll_y = nil
    end
  end

  if pending_window_geometry_apply then
    reaper.ImGui_SetNextWindowPos(ctx, current_window_x, current_window_y, reaper.ImGui_Cond_Always())
    reaper.ImGui_SetNextWindowSize(ctx, current_window_w, current_window_h, reaper.ImGui_Cond_Always())
  end

  local in_startup = (startup_frames < STARTUP_HIDE_FRAMES)
  local pushed_colors = 0
  local startup_invisible = rgba(0, 0, 0, 0)

  -- ── Expanded UI chrome/style layer migrated from podcast_viewer_v6.lua ──

  local startup_text_col        = in_startup and startup_invisible or C_TEXT
  local startup_paper_col       = in_startup and startup_invisible or C_PAPER
  local startup_chrome_col      = in_startup and startup_invisible or C_CHROME
  local startup_chrome_deep_col = in_startup and startup_invisible or C_CHROME_DEEP
  local startup_title_col       = in_startup and startup_invisible or C_CHROME_TITLE
  local startup_line_col        = in_startup and startup_invisible or C_LINE
  local startup_menu_border_col = in_startup and startup_invisible or C_MENU_BORDER
  local startup_frame_col       = in_startup and startup_invisible or C_FRAME
  local startup_scroll_col      = in_startup and startup_invisible or C_SCROLL
  local startup_scroll_h_col    = in_startup and startup_invisible or C_SCROLL_H
  local startup_scroll_a_col    = in_startup and startup_invisible or C_SCROLL_A
  local startup_scroll_bg_col   = in_startup and startup_invisible or C_SCROLL_BG
  local startup_head_col        = in_startup and startup_invisible or C_HEAD
  local startup_head_h_col      = in_startup and startup_invisible or C_HEAD_H

  -- Текст (глобальный; dim-текст и document-specific overrides по-прежнему локальные)
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), startup_text_col)
  pushed_colors = pushed_colors + 1

  -- Главный фон окна и child-контейнеров
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_WindowBg(), startup_paper_col)
  pushed_colors = pushed_colors + 1
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ChildBg(), startup_paper_col)
  pushed_colors = pushed_colors + 1

  -- Popup / menu surfaces
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_PopupBg(), startup_chrome_col)
  pushed_colors = pushed_colors + 1
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_MenuBarBg(), startup_chrome_col)
  pushed_colors = pushed_colors + 1

  -- Borders / border shadow.
  -- C_MENU_BORDER lets REAPER Grey mute popup/menu outlines without weakening
  -- regular semantic separators that still use C_LINE / Separator colours.
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Border(), startup_menu_border_col)
  pushed_colors = pushed_colors + 1
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_BorderShadow(), rgba(0, 0, 0, 0))
  pushed_colors = pushed_colors + 1

  -- Input field trilogy (search bar and other frame-based controls)
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_FrameBg(), startup_frame_col)
  pushed_colors = pushed_colors + 1
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_FrameBgHovered(), startup_frame_col)
  pushed_colors = pushed_colors + 1
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_FrameBgActive(), startup_frame_col)
  pushed_colors = pushed_colors + 1

  -- Title bar trilogy
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_TitleBg(), startup_title_col)
  pushed_colors = pushed_colors + 1
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_TitleBgActive(), startup_chrome_deep_col)
  pushed_colors = pushed_colors + 1
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_TitleBgCollapsed(), startup_chrome_col)
  pushed_colors = pushed_colors + 1

  -- Scrollbar trilogy + track
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ScrollbarBg(), startup_scroll_bg_col)
  pushed_colors = pushed_colors + 1
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ScrollbarGrab(), startup_scroll_col)
  pushed_colors = pushed_colors + 1
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ScrollbarGrabHovered(), startup_scroll_h_col)
  pushed_colors = pushed_colors + 1
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ScrollbarGrabActive(), startup_scroll_a_col)
  pushed_colors = pushed_colors + 1

  -- Header trilogy (menus/selectable chrome states)
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Header(), startup_head_col)
  pushed_colors = pushed_colors + 1
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_HeaderHovered(), startup_head_h_col)
  pushed_colors = pushed_colors + 1
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_HeaderActive(), startup_head_h_col)
  pushed_colors = pushed_colors + 1

  -- Separator trilogy
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Separator(), startup_line_col)
  pushed_colors = pushed_colors + 1
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_SeparatorHovered(), startup_line_col)
  pushed_colors = pushed_colors + 1
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_SeparatorActive(), startup_head_col)
  pushed_colors = pushed_colors + 1

  if in_startup and reaper.ImGui_SetNextWindowBgAlpha then
    reaper.ImGui_SetNextWindowBgAlpha(ctx, 0)
  end

  -- Top-row height: WindowFlags_MenuBar reserves the native menu-bar rect
  -- during ImGui_Begin(), so FramePadding must be pushed before the main
  -- window Begin call. Keep this non-architectural and pop it immediately
  -- after the combined menu/Search row has been submitted.
  local top_row_window_style_var_count = 0
  if reaper.ImGui_StyleVar_FramePadding then
    reaper.ImGui_PushStyleVar(
      ctx,
      reaper.ImGui_StyleVar_FramePadding(),
      4,
      tonumber(UI_TOP_ROW_FRAME_PAD_Y) or 5
    )
    top_row_window_style_var_count = top_row_window_style_var_count + 1
  end

  local _, flt_max = reaper.ImGui_NumericLimits_Float()
  reaper.ImGui_SetNextWindowSizeConstraints(
    ctx,
    tonumber(UI_MIN_WINDOW_W) or 840,
    tonumber(UI_MIN_WINDOW_H) or 560,
    flt_max,
    flt_max
  )

  local main_window_title = make_main_window_title()
  local visible, still_open = reaper.ImGui_Begin(ctx, main_window_title, true, WIN_FLAGS)
  win_open = still_open

  if visible then
    if in_startup then
      startup_frames = startup_frames + 1
      reaper.ImGui_End(ctx)
      if top_row_window_style_var_count > 0 then
        reaper.ImGui_PopStyleVar(ctx, top_row_window_style_var_count)
        top_row_window_style_var_count = 0
      end
      reaper.ImGui_PopStyleColor(ctx, pushed_colors)

      psv_profiler_frame_end(PSV_PROFILER_FRAME_T0, "startup_hidden")
      if win_open then
        reaper.defer(loop)
      else
        save_project_ui_state(last_proj_key)
      end
      return
    end
    if not startup_refresh_done then
      startup_refresh_done = true
      if reaper.UpdateArrange then reaper.UpdateArrange() end
      if reaper.TrackList_AdjustWindows then reaper.TrackList_AdjustWindows(false) end
    end

    do
      local wx, wy = reaper.ImGui_GetWindowPos(ctx)
      local ww, wh = reaper.ImGui_GetWindowSize(ctx)

      if valid_window_geometry(wx, wy, ww, wh) then
        local changed = wx ~= current_window_x
          or wy ~= current_window_y
          or ww ~= current_window_w
          or wh ~= current_window_h

        current_window_x = wx
        current_window_y = wy
        current_window_w = ww
        current_window_h = wh

        if changed then
          save_window_geometry_for_project(owner_project_key or last_proj_key or cur_key)
        end
      end

      pending_window_geometry_apply = false
    end

    -- Search is now rendered inside the first/menu row.
    -- Behaviour stays identical to the former standalone search row: the same
    -- TextFilter state, disabled empty-state path, drawlist frame, placeholder,
    -- transparent native InputText frame, and Escape/navigation state are kept.
    -- v3.0.20: Search/filename/hits inherit the native menu-row font instead of
    -- pushing a separate fixed Search font, so the whole top row shares one
    -- visual typography/baseline model.
    local search_enabled = (file_path ~= nil and file_path ~= "" and #paragraphs > 0)

    if not search_enabled then
      if search_input_buf ~= "" or reaper.ImGui_TextFilter_IsActive(search_filter) then
        reaper.ImGui_TextFilter_Clear(search_filter)
        search_input_buf = ""
      end
      search_nav_index = 0
      search_nav_scroll_target = nil
    end

    local function render_search_field_inline()
      -- Единый visual contract для active/inactive search field.
      -- Оба состояния получают один и тот же drawlist-frame, один размер,
      -- один rounding/border/padding/baseline. Различается только interactivity.
      local _, search_placeholder_h = reaper.ImGui_CalcTextSize(ctx, "Search")
      local search_field_h = search_placeholder_h + 8
      if UI_SEARCH_FIELD_H and UI_SEARCH_FIELD_H > 0 then
        search_field_h = UI_SEARCH_FIELD_H
      elseif reaper.ImGui_GetFrameHeight then
        local ok_frame_h, measured_frame_h = pcall(reaper.ImGui_GetFrameHeight, ctx)
        if ok_frame_h and measured_frame_h and measured_frame_h > 0 then
          search_field_h = measured_frame_h
        end
      end

      -- Search остаётся внутри native menu row. Вертикальное выравнивание
      -- делается только малым cursor-Y offset, без изменения Search behavior.
      local search_y_adjust = tonumber(UI_TOP_ROW_SEARCH_Y_OFFSET) or 0
      local top_row_target_h = tonumber(UI_TOP_ROW_TARGET_H) or 0
      if top_row_target_h > search_field_h then
        search_y_adjust = search_y_adjust + math.max(0, (top_row_target_h - search_field_h) * 0.5 - 1)
      end
      if search_y_adjust ~= 0 then
        reaper.ImGui_SetCursorPosY(ctx, reaper.ImGui_GetCursorPosY(ctx) + search_y_adjust)
      end

      local search_field_sx, search_field_sy = reaper.ImGui_GetCursorScreenPos(ctx)
      local search_dl = reaper.ImGui_GetWindowDrawList(ctx)
      local search_page_theme = PAGE_THEMES and PAGE_THEMES[page_layout_theme] or nil
      local search_frame_fill = (search_page_theme and search_page_theme.page_bg) or C_PAPER
      reaper.ImGui_DrawList_AddRectFilled(
        search_dl,
        search_field_sx,
        search_field_sy,
        search_field_sx + UI_SEARCH_FIELD_W,
        search_field_sy + search_field_h,
        search_frame_fill,
        UI_SEARCH_FIELD_ROUNDING
      )
      reaper.ImGui_DrawList_AddRect(
        search_dl,
        search_field_sx,
        search_field_sy,
        search_field_sx + UI_SEARCH_FIELD_W,
        search_field_sy + search_field_h,
        C_SEARCH_FIELD_BORDER,
        UI_SEARCH_FIELD_ROUNDING,
        reaper.ImGui_DrawFlags_None(),
        UI_SEARCH_BORDER_THICKNESS
      )

      reaper.ImGui_SetNextItemWidth(ctx, UI_SEARCH_FIELD_W)

      local search_input_style_var_count = 0
      if reaper.ImGui_StyleVar_FramePadding then
        local search_input_pad_y = math.max(0, (search_field_h - search_placeholder_h) * 0.5)
        reaper.ImGui_PushStyleVar(
          ctx,
          reaper.ImGui_StyleVar_FramePadding(),
          UI_SEARCH_FIELD_PAD_X,
          search_input_pad_y
        )
        search_input_style_var_count = search_input_style_var_count + 1
      end

      if search_enabled then
        local current_filter_text = reaper.ImGui_TextFilter_Get(search_filter)
        if search_input_buf ~= current_filter_text then
          search_input_buf = current_filter_text
        end

        -- Native InputText остаётся реальным item-ом для typing/caret/selection,
        -- но его собственный frame/border локально прозрачный, чтобы он не спорил
        -- с единым drawlist-frame search field.
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_FrameBg(), rgba(0, 0, 0, 0))
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_FrameBgHovered(), rgba(0, 0, 0, 0))
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_FrameBgActive(), rgba(0, 0, 0, 0))
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Border(), rgba(0, 0, 0, 0))

        -- Локально пробуем доступные enum-имена цвета caret-а для InputText.
        -- Разные версии ReaImGui могут экспонировать разные имена, поэтому
        -- probing остаётся здесь, рядом с search input, без глобальных wrappers.
        local search_cursor_color_pushes = 0
        local function push_search_cursor_color(enum_fn)
          if type(enum_fn) ~= "function" then return end

          local ok, col = pcall(enum_fn)
          if ok and col then
            reaper.ImGui_PushStyleColor(ctx, col, C_TEXT)
            search_cursor_color_pushes = search_cursor_color_pushes + 1
          end
        end

        push_search_cursor_color(reaper.ImGui_Col_InputTextCursor)
        push_search_cursor_color(reaper.ImGui_Col_TextCursor)

        local changed_search, new_search = reaper.ImGui_InputText(ctx, "##search", search_input_buf, 0)
        if changed_search then
          search_input_buf = new_search
          reaper.ImGui_TextFilter_Set(search_filter, search_input_buf)
        end

        local search_item_active = reaper.ImGui_IsItemActive(ctx)
        search_input_active = search_item_active
        if (not search_item_active) and search_input_buf == "" then
          local min_x, min_y = reaper.ImGui_GetItemRectMin(ctx)
          local item_w, item_h = reaper.ImGui_GetItemRectSize(ctx)
          local text_w, text_h = reaper.ImGui_CalcTextSize(ctx, "Search")
          local text_x = min_x + UI_SEARCH_FIELD_PAD_X
          local text_y = min_y + math.max(0, (item_h - text_h) * 0.5)
          reaper.ImGui_DrawList_AddText(search_dl, text_x, text_y, C_DIM, "Search")
        end

        if search_cursor_color_pushes > 0 then
          reaper.ImGui_PopStyleColor(ctx, search_cursor_color_pushes)
        end
        reaper.ImGui_PopStyleColor(ctx, 4)
        if search_input_style_var_count > 0 then
          reaper.ImGui_PopStyleVar(ctx, search_input_style_var_count)
          search_input_style_var_count = 0
        end
      else
        search_input_active = false
        -- Empty-state path: не submit-им реальный InputText, чтобы поле не могло
        -- получить focus/caret/input. Dummy резервирует тот же footprint, который
        -- использует active InputText frame.
        reaper.ImGui_Dummy(ctx, UI_SEARCH_FIELD_W, search_field_h)

        local min_x, min_y = reaper.ImGui_GetItemRectMin(ctx)
        local item_w, item_h = reaper.ImGui_GetItemRectSize(ctx)
        local text_w, text_h = reaper.ImGui_CalcTextSize(ctx, "Search")
        local text_x = min_x + UI_SEARCH_FIELD_PAD_X
        local text_y = min_y + math.max(0, (item_h - text_h) * 0.5)
        reaper.ImGui_DrawList_AddText(search_dl, text_x, text_y, C_DIM, "Search")
        if search_input_style_var_count > 0 then
          reaper.ImGui_PopStyleVar(ctx, search_input_style_var_count)
          search_input_style_var_count = 0
        end
      end
    end

    local top_row_style_var_count = 0
    -- FramePadding is already pushed before the main ImGui_Begin() so it can
    -- affect native menu-bar height allocation. Keep only ItemSpacing here for
    -- row-internal spacing and avoid double-applying vertical padding.
    if reaper.ImGui_StyleVar_ItemSpacing then
      reaper.ImGui_PushStyleVar(
        ctx,
        reaper.ImGui_StyleVar_ItemSpacing(),
        8,
        tonumber(UI_TOP_ROW_ITEM_SPACING_Y) or 4
      )
      top_row_style_var_count = top_row_style_var_count + 1
    end

    local function build_comments_navigator_groups()
      local comments = paragraphs.comments
      local refs = comments and comments.refs or nil
      if type(refs) ~= "table" or #refs == 0 then return {} end

      local groups = {}
      local by_key = {}
      for ref_index, ref in ipairs(refs) do
        local para_i = tonumber(ref.paragraph_index)
        local tok_i = tonumber(ref.token_index_after) or 0
        local comment_id = ref.comment_id
        if para_i and comment_id ~= nil and tostring(comment_id) ~= "" then
          local group_key = tostring(para_i) .. ":" .. tostring(tok_i)
          local group = by_key[group_key]
          if not group then
            group = {
              group_key=group_key,
              paragraph_index=para_i,
              token_index_after=tok_i,
              first_seen=ref_index,
              comment_ids={},
              refs={},
            }
            by_key[group_key] = group
            groups[#groups + 1] = group
          end
          group.refs[#group.refs + 1] = ref
          group.comment_ids[#group.comment_ids + 1] = comment_id
        end
      end

      table.sort(groups, function(a, b)
        if a.paragraph_index ~= b.paragraph_index then
          return a.paragraph_index < b.paragraph_index
        end
        if a.token_index_after ~= b.token_index_after then
          return a.token_index_after < b.token_index_after
        end
        return (a.first_seen or 0) < (b.first_seen or 0)
      end)

      return groups
    end

    local function comments_navigator_available()
      if not file_path or file_path == "" then return false end
      if type(paragraphs) ~= "table" or #paragraphs == 0 then return false end
      local comments = paragraphs.comments
      if type(comments) ~= "table" then return false end
      local refs = comments.refs
      if type(refs) ~= "table" or #refs == 0 then return false end
      local groups = build_comments_navigator_groups()
      return type(groups) == "table" and #groups > 0
    end

    local function comments_navigator_normalize_single_line(text)
      text = tostring(text or "")
      text = text:gsub("%s+", " ")
      return trim(text)
    end

    local function comments_navigator_utf8_next_index(text, i)
      local b1 = text:byte(i)
      if not b1 then return nil end
      if b1 < 0x80 then
        return i + 1
      end

      local function is_continuation(pos)
        local b = text:byte(pos)
        return b and b >= 0x80 and b <= 0xBF
      end

      if b1 >= 0xC2 and b1 <= 0xDF and is_continuation(i + 1) then
        return i + 2
      elseif b1 >= 0xE0 and b1 <= 0xEF and is_continuation(i + 1) and is_continuation(i + 2) then
        return i + 3
      elseif b1 >= 0xF0 and b1 <= 0xF4 and is_continuation(i + 1) and is_continuation(i + 2) and is_continuation(i + 3) then
        return i + 4
      end

      -- Malformed byte sequence fallback: advance one byte rather than crashing.
      return i + 1
    end

    local function comments_navigator_utf8_truncate(text, max_chars)
      text = comments_navigator_normalize_single_line(text)
      max_chars = tonumber(max_chars) or 70
      if max_chars < 1 then max_chars = 1 end
      if text == "" then return text end

      local byte_len = #text
      local i = 1
      local char_count = 0
      local cut_i = nil
      while i <= byte_len and char_count < max_chars do
        local next_i = comments_navigator_utf8_next_index(text, i)
        if not next_i or next_i <= i then break end
        char_count = char_count + 1
        cut_i = next_i
        i = next_i
      end

      if i <= byte_len and cut_i and cut_i > 1 then
        return trim(text:sub(1, cut_i - 1)) .. "..."
      end
      return text
    end

    local function comments_navigator_utf8_truncate_to_width(text, max_w)
      text = comments_navigator_normalize_single_line(text)
      max_w = tonumber(max_w) or 0
      if text == "" or max_w <= 0 then return "" end

      local full_w = select(1, reaper.ImGui_CalcTextSize(ctx, text))
      if full_w <= max_w then return text end

      local ellipsis = "..."
      local ellipsis_w = select(1, reaper.ImGui_CalcTextSize(ctx, ellipsis))
      if ellipsis_w >= max_w then return ellipsis end

      local byte_len = #text
      local i = 1
      local last_fit_i = nil
      while i <= byte_len do
        local next_i = comments_navigator_utf8_next_index(text, i)
        if not next_i or next_i <= i then break end

        local candidate = trim(text:sub(1, next_i - 1))
        local candidate_w = select(1, reaper.ImGui_CalcTextSize(ctx, candidate .. ellipsis))
        if candidate_w > max_w then break end

        last_fit_i = next_i
        i = next_i
      end

      if last_fit_i and last_fit_i > 1 then
        return trim(text:sub(1, last_fit_i - 1)) .. ellipsis
      end

      return ellipsis
    end

    local function comments_navigator_preview_parts(group)
      local comments = paragraphs.comments
      local primary_id = group and group.comment_ids and group.comment_ids[1] or nil
      local data = comments and comments.by_id and primary_id and comments.by_id[primary_id] or nil
      local raw_text = data and data.text or ""
      local preview = comments_navigator_utf8_truncate(raw_text, 120)
      if preview == "" then preview = "No comment text found." end

      local author = comments_navigator_utf8_truncate(data and data.author or "", 80)
      local extra_count = group and group.comment_ids and (#group.comment_ids - 1) or 0
      return author, preview, extra_count
    end

    local function request_comments_navigator_open(group)
      local comments = paragraphs.comments
      if not comments or not group then return end

      local comment_ids = {}
      for _, comment_id in ipairs(group.comment_ids or {}) do
        if comment_id ~= nil and tostring(comment_id) ~= "" then
          comment_ids[#comment_ids + 1] = comment_id
        end
      end
      if #comment_ids == 0 then return end

      comments.navigator_pending = {
        group_key=group.group_key,
        paragraph_index=group.paragraph_index,
        token_index_after=group.token_index_after,
        comment_ids=comment_ids,
        primary_id=comment_ids[1],
      }
      comments.navigator_scroll_target_para = group.paragraph_index
      comments.navigator_marker_scroll_attempts = 0
      comments.navigator_marker_scroll_waiting_for_visible = false
      reset_body_scroll_inertia()
    end

    local function comments_navigator_rgba_tuple(tuple, fallback_col)
      if type(tuple) ~= "table" then return fallback_col end
      return rgba(tuple[1] or 0, tuple[2] or 0, tuple[3] or 0, tuple[4] or 255)
    end

    local function resolve_comments_navigator_colors()
      local colors = {
        popup_bg = C_CHROME_DEEP,
        child_bg = C_CHROME_DEEP,
        popup_border = C_LINE,
        row_bg = C_FRAME,
        row_hover_bg = C_HEAD,
        row_border = C_LINE,
        author_text = C_DIM,
        preview_text = C_TEXT,
      }

      if ui_theme == "paper" and UI_COMMENTS_NAV_PAGES_COLOR_OVERRIDE_ENABLED == true then
        colors.popup_bg = comments_navigator_rgba_tuple(UI_COMMENTS_NAV_PAGES_POPUP_BG_RGBA, colors.popup_bg)
        colors.child_bg = colors.popup_bg
        colors.popup_border = comments_navigator_rgba_tuple(UI_COMMENTS_NAV_PAGES_POPUP_BORDER_RGBA, colors.popup_border)
        colors.row_bg = comments_navigator_rgba_tuple(UI_COMMENTS_NAV_PAGES_ROW_BG_RGBA, colors.row_bg)
        colors.row_hover_bg = comments_navigator_rgba_tuple(UI_COMMENTS_NAV_PAGES_ROW_HOVER_BG_RGBA, colors.row_hover_bg)
        colors.row_border = comments_navigator_rgba_tuple(UI_COMMENTS_NAV_PAGES_ROW_BORDER_RGBA, colors.row_border)
        colors.author_text = comments_navigator_rgba_tuple(UI_COMMENTS_NAV_PAGES_AUTHOR_TEXT_RGBA, colors.author_text)
        colors.preview_text = comments_navigator_rgba_tuple(UI_COMMENTS_NAV_PAGES_PREVIEW_TEXT_RGBA, colors.preview_text)
      end

      if ui_theme == "reaper_grey" then
        colors.row_border = comments_navigator_rgba_tuple(UI_COMMENTS_NAV_REAPER_GREY_ROW_BORDER_RGBA, colors.row_border)
      end

      return colors
    end

    local function render_comments_navigator_card(group, row_w, row_h, nav_colors, bubble_gap_l, bubble_gap_r)
      local author, preview, extra_count = comments_navigator_preview_parts(group)
      local count_suffix = extra_count > 0 and (" (+" .. tostring(extra_count) .. ")") or ""
      local has_author = author and author ~= ""
      local line1 = has_author and (author .. count_suffix) or (preview .. count_suffix)
      local line2 = has_author and preview or nil

      reaper.ImGui_InvisibleButton(
        ctx,
        "##comments_nav_card_" .. tostring(group.group_key),
        row_w,
        row_h,
        reaper.ImGui_ButtonFlags_MouseButtonLeft()
      )

      local clicked = reaper.ImGui_IsItemClicked(ctx, reaper.ImGui_MouseButton_Left())
      local hovered = reaper.ImGui_IsItemHovered(ctx, reaper.ImGui_HoveredFlags_None())
      local x1, y1 = reaper.ImGui_GetItemRectMin(ctx)
      local x2, y2 = reaper.ImGui_GetItemRectMax(ctx)
      local full_row_w = math.max(1, x2 - x1)
      local gap_l = math.max(0, tonumber(bubble_gap_l) or 0)
      local gap_r = math.max(0, tonumber(bubble_gap_r) or 0)
      local min_bubble_w = math.min(40, full_row_w)
      local total_gap = gap_l + gap_r
      if full_row_w - total_gap < min_bubble_w then
        local allowed_gap = math.max(0, full_row_w - min_bubble_w)
        if total_gap > 0 then
          local scale = allowed_gap / total_gap
          gap_l = gap_l * scale
          gap_r = gap_r * scale
        else
          gap_l = 0
          gap_r = 0
        end
      end
      local bx1 = x1 + gap_l
      local bx2 = x2 - gap_r
      if bx2 < bx1 + 1 then bx2 = bx1 + 1 end
      local dl = reaper.ImGui_GetWindowDrawList(ctx)
      nav_colors = nav_colors or resolve_comments_navigator_colors()
      local bg_col = hovered and nav_colors.row_hover_bg or nav_colors.row_bg
      local border_col = nav_colors.row_border
      local pad_x = tonumber(UI_COMMENTS_NAV_ROW_PAD_X) or 8
      if pad_x < 0 then pad_x = 0 end
      local pad_y = tonumber(UI_COMMENTS_NAV_ROW_PAD_Y) or 5
      if pad_y < 0 then pad_y = 0 end
      local line_gap_y = tonumber(UI_COMMENTS_NAV_ROW_LINE_GAP_Y) or 1
      if line_gap_y < 0 then line_gap_y = 0 end
      local line_h = reaper.ImGui_GetTextLineHeight(ctx)
      local text_max_w = math.max(10, (bx2 - bx1) - pad_x * 2)

      line1 = comments_navigator_utf8_truncate_to_width(line1, text_max_w)
      if line2 then
        line2 = comments_navigator_utf8_truncate_to_width(line2, text_max_w)
      end

      local row_rounding = tonumber(UI_COMMENTS_NAV_ROW_ROUNDING) or 6.0
      if row_rounding < 0 then row_rounding = 0 end
      local row_border_thickness = tonumber(UI_COMMENTS_NAV_ROW_BORDER_THICKNESS) or 1.0
      if row_border_thickness < 0 then row_border_thickness = 0 end

      reaper.ImGui_DrawList_AddRectFilled(dl, bx1, y1, bx2, y2, bg_col, row_rounding)
      if row_border_thickness > 0 then
        reaper.ImGui_DrawList_AddRect(dl, bx1, y1, bx2, y2, border_col, row_rounding, 0, row_border_thickness)
      end

      if line2 then
        local block_h = line_h * 2 + line_gap_y
        local text_y1 = y1 + math.max(pad_y, math.floor((row_h - block_h) * 0.5))
        reaper.ImGui_DrawList_AddText(dl, bx1 + pad_x, text_y1, nav_colors.author_text, line1)
        reaper.ImGui_DrawList_AddText(dl, bx1 + pad_x, text_y1 + line_h + line_gap_y, nav_colors.preview_text, line2)
      else
        local text_y = y1 + math.max(pad_y, math.floor((row_h - line_h) * 0.5))
        reaper.ImGui_DrawList_AddText(dl, bx1 + pad_x, text_y, nav_colors.preview_text, line1)
      end

      if clicked then
        request_comments_navigator_open(group)
        return true
      end
      return false
    end

    local function render_comments_navigator_empty_card(row_w, row_h, nav_colors, bubble_gap_l, bubble_gap_r)
      reaper.ImGui_InvisibleButton(
        ctx,
        "##comments_nav_empty_card",
        row_w,
        row_h,
        reaper.ImGui_ButtonFlags_MouseButtonLeft()
      )
      local x1, y1 = reaper.ImGui_GetItemRectMin(ctx)
      local x2, y2 = reaper.ImGui_GetItemRectMax(ctx)
      local full_row_w = math.max(1, x2 - x1)
      local gap_l = math.max(0, tonumber(bubble_gap_l) or 0)
      local gap_r = math.max(0, tonumber(bubble_gap_r) or 0)
      local min_bubble_w = math.min(40, full_row_w)
      local total_gap = gap_l + gap_r
      if full_row_w - total_gap < min_bubble_w then
        local allowed_gap = math.max(0, full_row_w - min_bubble_w)
        if total_gap > 0 then
          local scale = allowed_gap / total_gap
          gap_l = gap_l * scale
          gap_r = gap_r * scale
        else
          gap_l = 0
          gap_r = 0
        end
      end
      local bx1 = x1 + gap_l
      local bx2 = x2 - gap_r
      if bx2 < bx1 + 1 then bx2 = bx1 + 1 end
      local dl = reaper.ImGui_GetWindowDrawList(ctx)
      nav_colors = nav_colors or resolve_comments_navigator_colors()
      local row_rounding = tonumber(UI_COMMENTS_NAV_ROW_ROUNDING) or 6.0
      if row_rounding < 0 then row_rounding = 0 end
      local row_border_thickness = tonumber(UI_COMMENTS_NAV_ROW_BORDER_THICKNESS) or 1.0
      if row_border_thickness < 0 then row_border_thickness = 0 end
      reaper.ImGui_DrawList_AddRectFilled(dl, bx1, y1, bx2, y2, nav_colors.row_bg, row_rounding)
      if row_border_thickness > 0 then
        reaper.ImGui_DrawList_AddRect(dl, bx1, y1, bx2, y2, nav_colors.row_border, row_rounding, 0, row_border_thickness)
      end
      local text = "No comments"
      local text_w, text_h = reaper.ImGui_CalcTextSize(ctx, text)
      reaper.ImGui_DrawList_AddText(
        dl,
        bx1 + math.max(8, math.floor(((bx2 - bx1) - text_w) * 0.5)),
        y1 + math.max(3, math.floor(((y2 - y1) - text_h) * 0.5)),
        nav_colors.author_text,
        text
      )
    end

    local function render_comments_navigator_popup_content(ctx, groups, child_h, row_h, row_gap, nav_needs_scroll, nav_colors, bubble_gap_l, bubble_gap_r, list_top_gap_y, sidebar_scrollbar_separation_enabled)
      local avail_w = select(1, reaper.ImGui_GetContentRegionAvail(ctx))
      local child_flags = reaper.ImGui_ChildFlags_None()
      local child_window_flags = 0
      if nav_needs_scroll then
        child_window_flags = child_window_flags | reaper.ImGui_WindowFlags_AlwaysVerticalScrollbar()
      end
      local should_close_popup = false
      if reaper.ImGui_BeginChild(ctx, "##comments_nav_popup_scroll", avail_w, child_h, child_flags, child_window_flags) then
        local child_avail_w = select(1, reaper.ImGui_GetContentRegionAvail(ctx))

        if sidebar_scrollbar_separation_enabled == true and UI_COMMENTS_SIDEBAR_BG_ENABLED ~= false then
          local bg = UI_COMMENTS_SIDEBAR_BG_RGBA
          if type(bg) == "table" then
            local bg_r = tonumber(bg[1])
            local bg_g = tonumber(bg[2])
            local bg_b = tonumber(bg[3])
            local bg_a = tonumber(bg[4])
            if bg_r and bg_g and bg_b and bg_a then
              if bg_a < 0 then bg_a = 0 elseif bg_a > 255 then bg_a = 255 end
              local child_win_x, child_win_y = reaper.ImGui_GetWindowPos(ctx)
              local child_win_w, child_win_h = reaper.ImGui_GetWindowSize(ctx)
              local bg_w = math.max(0, math.min(tonumber(child_avail_w) or 0, tonumber(child_win_w) or 0))
              if bg_w > 0 and child_win_h > 0 then
                local bg_rounding = tonumber(UI_COMMENTS_SIDEBAR_BG_ROUNDING) or 0.0
                if bg_rounding < 0 then bg_rounding = 0.0 end
                local dl = reaper.ImGui_GetWindowDrawList(ctx)
                reaper.ImGui_DrawList_AddRectFilled(
                  dl,
                  child_win_x, child_win_y,
                  child_win_x + bg_w, child_win_y + child_win_h,
                  rgba(bg_r, bg_g, bg_b, bg_a),
                  bg_rounding
                )
              end
            end
          end
        end

        local scrollbar_reserve_w = nav_needs_scroll and (tonumber(UI_COMMENTS_NAV_SCROLLBAR_RESERVED_W) or 8) or 0
        if scrollbar_reserve_w < 0 then scrollbar_reserve_w = 0 end
        local row_w = math.max(40, child_avail_w - scrollbar_reserve_w - 1)
        list_top_gap_y = tonumber(list_top_gap_y) or 0
        if list_top_gap_y < 0 then list_top_gap_y = 0 end
        if list_top_gap_y > 0 then
          reaper.ImGui_Dummy(ctx, 0, list_top_gap_y)
        end
        if #groups == 0 then
          render_comments_navigator_empty_card(row_w, row_h, nav_colors, bubble_gap_l, bubble_gap_r)
        else
          for group_index, group in ipairs(groups) do
            if render_comments_navigator_card(group, row_w, row_h, nav_colors, bubble_gap_l, bubble_gap_r) then
              should_close_popup = true
            end
            if group_index < #groups then
              reaper.ImGui_Dummy(ctx, 0, row_gap)
            end
          end
        end
        reaper.ImGui_EndChild(ctx)
      end
      return should_close_popup
    end

    local function render_comments_sidebar_toggle_trigger(trigger_w)
      local trigger_h = reaper.ImGui_GetFrameHeight(ctx)
      if trigger_h < 1 then trigger_h = tonumber(UI_TOP_ROW_TARGET_H) or 38 end

      local comments_available = comments_navigator_available()
      if not comments_available then
        PSV_COMMENTS_SIDEBAR_OPEN = false
      end

      reaper.ImGui_InvisibleButton(
        ctx,
        "Comments##comments_nav_trigger",
        trigger_w,
        trigger_h,
        reaper.ImGui_ButtonFlags_MouseButtonLeft()
      )

      local trigger_clicked = comments_available and reaper.ImGui_IsItemClicked(ctx, reaper.ImGui_MouseButton_Left())
      local trigger_hovered = comments_available and reaper.ImGui_IsItemHovered(ctx, reaper.ImGui_HoveredFlags_None())
      local tx1, ty1 = reaper.ImGui_GetItemRectMin(ctx)
      local tx2, ty2 = reaper.ImGui_GetItemRectMax(ctx)
      if comments_available and (not trigger_hovered) and reaper.ImGui_GetMousePos then
        local mx, my = reaper.ImGui_GetMousePos(ctx)
        trigger_hovered = mx >= tx1 and mx <= tx2 and my >= ty1 and my <= ty2
      end
      if trigger_clicked then
        PSV_COMMENTS_SIDEBAR_OPEN = not PSV_COMMENTS_SIDEBAR_OPEN
      end

      local dl = reaper.ImGui_GetWindowDrawList(ctx)
      if comments_available and (PSV_COMMENTS_SIDEBAR_OPEN or trigger_hovered) then
        local trigger_bg = (PSV_COMMENTS_SIDEBAR_OPEN and trigger_hovered) and C_HEAD_H or C_HEAD
        local trigger_rounding = tonumber(UI_TOP_ROW_COMMENTS_TRIGGER_ROUNDING) or 0.0
        if trigger_rounding < 0 then trigger_rounding = 0.0 end
        reaper.ImGui_DrawList_AddRectFilled(dl, tx1, ty1, tx2, ty2, trigger_bg, trigger_rounding)
      end
      local label = "Comments"
      local label_w, label_h = reaper.ImGui_CalcTextSize(ctx, label)
      reaper.ImGui_DrawList_AddText(
        dl,
        tx1 + math.max(6, math.floor(((tx2 - tx1) - label_w) * 0.5)),
        ty1 + math.max(1, math.floor(((ty2 - ty1) - label_h) * 0.5)),
        comments_available and C_TEXT or C_DIM,
        label
      )
    end


    local function resolve_comments_sidebar_bg_color(fallback_col)
      if UI_COMMENTS_SIDEBAR_BG_ENABLED == false then
        return fallback_col
      end

      local bg = UI_COMMENTS_SIDEBAR_BG_RGBA
      if type(bg) ~= "table" then
        return fallback_col
      end

      local r = tonumber(bg[1])
      local g = tonumber(bg[2])
      local b = tonumber(bg[3])
      local a = tonumber(bg[4])
      if not (r and g and b and a) then
        return fallback_col
      end

      if a < 0 then a = 0 elseif a > 255 then a = 255 end
      return rgba(r, g, b, a)
    end

    local function render_comments_navigator_sidebar_content(ctx)
      local groups = build_comments_navigator_groups()
      local nav_colors = resolve_comments_navigator_colors()

      local nav_font_size = clamp_comments_nav_font_size(comments_nav_font_size)
      local nav_font = get_font(nav_font_size)

      local nav_line_h = nav_font_size
      if nav_font then
        reaper.ImGui_PushFont(ctx, nav_font, nav_font_size)
        nav_line_h = select(2, reaper.ImGui_CalcTextSize(ctx, "Ay"))
        reaper.ImGui_PopFont(ctx)
      end

      local row_pad_y = tonumber(UI_COMMENTS_NAV_ROW_PAD_Y) or 5
      if row_pad_y < 0 then row_pad_y = 0 end
      local row_line_gap_y = tonumber(UI_COMMENTS_NAV_ROW_LINE_GAP_Y) or 1
      if row_line_gap_y < 0 then row_line_gap_y = 0 end
      local row_min_h = tonumber(UI_COMMENTS_NAV_ROW_MIN_H) or 40
      if row_min_h < 28 then row_min_h = 28 end
      local row_h = math.max(row_min_h, math.ceil(nav_line_h * 2 + row_pad_y * 2 + row_line_gap_y))
      local row_gap = tonumber(UI_COMMENTS_NAV_ROW_GAP_Y) or 1
      if row_gap < 0 then row_gap = 0 end

      local avail_w, avail_h = reaper.ImGui_GetContentRegionAvail(ctx)
      avail_w = math.max(1, tonumber(avail_w) or 1)
      avail_h = math.max(1, tonumber(avail_h) or 1)

      local item_count = (#groups > 0) and #groups or 1
      local content_h = item_count * row_h + math.max(0, item_count - 1) * row_gap
      local nav_needs_scroll = content_h > avail_h + 0.5

      local sidebar_bg_col = resolve_comments_sidebar_bg_color(nav_colors.child_bg)
      local sidebar_scrollbar_separation_enabled = UI_COMMENTS_SIDEBAR_SCROLLBAR_SEPARATION_ENABLED == true
      local inner_child_bg_col = sidebar_scrollbar_separation_enabled and rgba(0, 0, 0, 0) or sidebar_bg_col
      reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ChildBg(), inner_child_bg_col)
      reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ScrollbarBg(), rgba(UI_COMMENTS_NAV_SCROLLBAR_BG_RGBA[1], UI_COMMENTS_NAV_SCROLLBAR_BG_RGBA[2], UI_COMMENTS_NAV_SCROLLBAR_BG_RGBA[3], UI_COMMENTS_NAV_SCROLLBAR_BG_RGBA[4]))
      reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ScrollbarGrab(), rgba(UI_COMMENTS_NAV_SCROLLBAR_GRAB_RGBA[1], UI_COMMENTS_NAV_SCROLLBAR_GRAB_RGBA[2], UI_COMMENTS_NAV_SCROLLBAR_GRAB_RGBA[3], UI_COMMENTS_NAV_SCROLLBAR_GRAB_RGBA[4]))
      reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ScrollbarGrabHovered(), rgba(UI_COMMENTS_NAV_SCROLLBAR_GRAB_HOVER_RGBA[1], UI_COMMENTS_NAV_SCROLLBAR_GRAB_HOVER_RGBA[2], UI_COMMENTS_NAV_SCROLLBAR_GRAB_HOVER_RGBA[3], UI_COMMENTS_NAV_SCROLLBAR_GRAB_HOVER_RGBA[4]))
      reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ScrollbarGrabActive(), rgba(UI_COMMENTS_NAV_SCROLLBAR_GRAB_ACTIVE_RGBA[1], UI_COMMENTS_NAV_SCROLLBAR_GRAB_ACTIVE_RGBA[2], UI_COMMENTS_NAV_SCROLLBAR_GRAB_ACTIVE_RGBA[3], UI_COMMENTS_NAV_SCROLLBAR_GRAB_ACTIVE_RGBA[4]))
      if nav_font then reaper.ImGui_PushFont(ctx, nav_font, nav_font_size) end

      render_comments_navigator_popup_content(
        ctx,
        groups,
        avail_h,
        row_h,
        row_gap,
        nav_needs_scroll,
        nav_colors,
        UI_COMMENTS_SIDEBAR_BUBBLE_GAP_L,
        UI_COMMENTS_SIDEBAR_BUBBLE_GAP_R,
        UI_COMMENTS_SIDEBAR_LIST_TOP_GAP_Y,
        sidebar_scrollbar_separation_enabled
      )

      if nav_font then reaper.ImGui_PopFont(ctx) end
      reaper.ImGui_PopStyleColor(ctx, 5)
    end

    local top_row_separator_y = nil
    -- Latch Escape ownership before BeginPopup can close a native menu and
    -- clear its tracked state. One key press must not reach the search below.
    escape_key_owner = show_about_overlay and "about"
      or (PSV_TOP_ROW_CUSTOM_MENU_OPEN ~= nil and "menu")
      or (paragraphs.comments and paragraphs.comments.active_id and "comment")
      or "search"

    if reaper.ImGui_BeginMenuBar(ctx) then
      top_row_separator_y = select(2, reaper.ImGui_GetCursorScreenPos(ctx)) + (tonumber(UI_TOP_ROW_TARGET_H) or 38)

      local function close_file_custom_menu_after_action(ctx)
        psv_block_document_interactions_this_frame(ctx)
        if PSV_TOP_ROW_CUSTOM_MENU_OPEN == "file" then
          PSV_TOP_ROW_CUSTOM_MENU_OPEN = nil
        end
        if reaper.ImGui_CloseCurrentPopup then
          reaper.ImGui_CloseCurrentPopup(ctx)
        end
      end

      local function render_file_menu_contents(ctx)
        if reaper.ImGui_MenuItem(ctx, "Open HTML/DOCX...") then
          close_file_custom_menu_after_action(ctx)
          open_dialog()
        end
        if file_path then
          if reaper.ImGui_MenuItem(ctx, "Clear") then
            clear_script()
            close_file_custom_menu_after_action(ctx)
          end
        end

        reaper.ImGui_Separator(ctx)
        if reaper.ImGui_BeginMenu(ctx, "Recent Scripts") then
          local recent_scripts = load_recent_scripts()
          if #recent_scripts == 0 then
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), C_DIM)
            reaper.ImGui_Text(ctx, "No recent scripts")
            reaper.ImGui_PopStyleColor(ctx)
          else
            for _, recent_path in ipairs(recent_scripts) do
              if reaper.ImGui_MenuItem(ctx, basename_for_menu(recent_path)) then
                load_file(recent_path)
                close_file_custom_menu_after_action(ctx)
              end
            end
            reaper.ImGui_Separator(ctx)
            if reaper.ImGui_MenuItem(ctx, "Clear Recent Scripts") then
              clear_recent_scripts()
              close_file_custom_menu_after_action(ctx)
            end
          end
          reaper.ImGui_EndMenu(ctx)
        end

        reaper.ImGui_Separator(ctx)
        if reaper.ImGui_MenuItem(ctx, "Close") then
          psv_block_document_interactions_this_frame(ctx)
          PSV_TOP_ROW_CUSTOM_MENU_OPEN = nil
          if reaper.ImGui_CloseCurrentPopup then
            reaper.ImGui_CloseCurrentPopup(ctx)
          end
          win_open = false
        end
      end

      local function get_current_style_color(style_col, fallback_col)
        if reaper.ImGui_GetStyleColor then
          return reaper.ImGui_GetStyleColor(ctx, style_col)
        end
        return fallback_col
      end

      local function render_custom_top_menu_trigger(label, menu_id, popup_id)
        local label_w, label_h = reaper.ImGui_CalcTextSize(ctx, label)
        local trigger_pad_x = 8
        local trigger_w = label_w + trigger_pad_x * 2
        if menu_id == "file" then
          local view_label_w = reaper.ImGui_CalcTextSize(ctx, "View")
          local file_min_w = view_label_w + trigger_pad_x * 2
          if trigger_w < file_min_w then
            trigger_w = file_min_w
          end
        end
        local trigger_h = reaper.ImGui_GetFrameHeight(ctx)
        if trigger_h < 1 then trigger_h = tonumber(UI_TOP_ROW_TARGET_H) or 38 end

        reaper.ImGui_InvisibleButton(
          ctx,
          label .. "##custom_top_menu_trigger_" .. tostring(menu_id),
          trigger_w,
          trigger_h,
          reaper.ImGui_ButtonFlags_MouseButtonLeft()
        )

        local trigger_clicked = reaper.ImGui_IsItemClicked(ctx, reaper.ImGui_MouseButton_Left())
        local tx1, ty1 = reaper.ImGui_GetItemRectMin(ctx)
        local tx2, ty2 = reaper.ImGui_GetItemRectMax(ctx)
        local trigger_hovered = false
        if reaper.ImGui_HoveredFlags_AllowWhenBlockedByPopup then
          trigger_hovered = reaper.ImGui_IsItemHovered(
            ctx,
            reaper.ImGui_HoveredFlags_AllowWhenBlockedByPopup()
          )
        else
          trigger_hovered = reaper.ImGui_IsItemHovered(ctx, reaper.ImGui_HoveredFlags_None())
        end
        if not trigger_hovered and reaper.ImGui_GetMousePos then
          local mx, my = reaper.ImGui_GetMousePos(ctx)
          trigger_hovered = mx >= tx1 and mx <= tx2 and my >= ty1 and my <= ty2
        end

        local dl = reaper.ImGui_GetWindowDrawList(ctx)
        local close_requested = false

        if trigger_clicked then
          if PSV_TOP_ROW_CUSTOM_MENU_OPEN == menu_id then
            close_requested = true
            PSV_TOP_ROW_CUSTOM_MENU_OPEN = nil
          else
            PSV_TOP_ROW_CUSTOM_MENU_OPEN = menu_id
            reaper.ImGui_OpenPopup(ctx, popup_id)
          end
        elseif trigger_hovered
           and PSV_TOP_ROW_CUSTOM_MENU_OPEN ~= nil
           and PSV_TOP_ROW_CUSTOM_MENU_OPEN ~= menu_id
           and not (
             PSV_TOP_ROW_CUSTOM_MENU_OPEN == "view"
             and menu_id ~= "view"
             and reaper.ImGui_IsMouseDown
             and reaper.ImGui_IsMouseDown(ctx, reaper.ImGui_MouseButton_Left())
           ) then
          PSV_TOP_ROW_CUSTOM_MENU_OPEN = menu_id
          reaper.ImGui_OpenPopup(ctx, popup_id)
        end

        local menu_open = PSV_TOP_ROW_CUSTOM_MENU_OPEN == menu_id

        if trigger_hovered or menu_open then
          local open_hover_col = get_current_style_color(reaper.ImGui_Col_Header(), C_HEAD)
          local active_col = get_current_style_color(reaper.ImGui_Col_HeaderActive(), C_HEAD_H)
          local trigger_bg = (menu_open and trigger_hovered) and active_col or open_hover_col
          reaper.ImGui_DrawList_AddRectFilled(dl, tx1, ty1, tx2, ty2, trigger_bg, 0)
        end

        reaper.ImGui_DrawList_AddText(
          dl,
          tx1 + math.max(6, math.floor(((tx2 - tx1) - label_w) * 0.5)),
          ty1 + math.max(1, math.floor(((ty2 - ty1) - label_h) * 0.5)),
          get_current_style_color(reaper.ImGui_Col_Text(), C_TEXT),
          label
        )

        return {
          menu_id=menu_id,
          popup_id=popup_id,
          x1=tx1,
          y1=ty1,
          x2=tx2,
          y2=ty2,
          close_requested=close_requested,
        }
      end

      local function begin_native_like_custom_popup(trigger)
        reaper.ImGui_SetNextWindowPos(ctx, trigger.x1, trigger.y2, reaper.ImGui_Cond_Always())
        local popup_open = reaper.ImGui_BeginPopup(ctx, trigger.popup_id, reaper.ImGui_WindowFlags_NoMove())
        return popup_open
      end

      local function end_native_like_custom_popup(trigger, popup_open)
        if popup_open then
          reaper.ImGui_EndPopup(ctx)
        elseif PSV_TOP_ROW_CUSTOM_MENU_OPEN == trigger.menu_id and not trigger.close_requested then
          PSV_TOP_ROW_CUSTOM_MENU_OPEN = nil
        end
      end

      local function render_custom_file_popup(trigger)
        local popup_open = begin_native_like_custom_popup(trigger)
        if popup_open then
          if trigger.close_requested then
            psv_block_document_interactions_this_frame(ctx)
            reaper.ImGui_CloseCurrentPopup(ctx)
          else
            render_file_menu_contents(ctx)
          end
        end
        end_native_like_custom_popup(trigger, popup_open)
      end

      local function render_custom_view_popup(trigger)
        local popup_open = begin_native_like_custom_popup(trigger)
        if popup_open then
          if trigger.close_requested then
            psv_block_document_interactions_this_frame(ctx)
            reaper.ImGui_CloseCurrentPopup(ctx)
          else
            render_view_settings_controls(ctx)
          end
        end
        end_native_like_custom_popup(trigger, popup_open)
      end

      local function render_custom_theme_popup(trigger)
        local popup_open = begin_native_like_custom_popup(trigger)
        if popup_open then
          if trigger.close_requested then
            psv_block_document_interactions_this_frame(ctx)
            reaper.ImGui_CloseCurrentPopup(ctx)
          else
            if reaper.ImGui_MenuItem(ctx, "Pages", nil, ui_theme == "paper") then
              psv_block_document_interactions_this_frame(ctx)
              request_ui_theme_change("paper")
              PSV_TOP_ROW_CUSTOM_MENU_OPEN = nil
              reaper.ImGui_CloseCurrentPopup(ctx)
            end
            if reaper.ImGui_MenuItem(ctx, "REAPER Grey", nil, ui_theme == "reaper_grey") then
              psv_block_document_interactions_this_frame(ctx)
              request_ui_theme_change("reaper_grey")
              PSV_TOP_ROW_CUSTOM_MENU_OPEN = nil
              reaper.ImGui_CloseCurrentPopup(ctx)
            end
            if reaper.ImGui_MenuItem(ctx, "Google Docs White", nil, ui_theme == "google_docs_white") then
              psv_block_document_interactions_this_frame(ctx)
              request_ui_theme_change("google_docs_white")
              PSV_TOP_ROW_CUSTOM_MENU_OPEN = nil
              reaper.ImGui_CloseCurrentPopup(ctx)
            end
          end
        end
        end_native_like_custom_popup(trigger, popup_open)
      end

      local function render_custom_help_popup(trigger)
        local popup_open = begin_native_like_custom_popup(trigger)
        if popup_open then
          if trigger.close_requested then
            psv_block_document_interactions_this_frame(ctx)
            reaper.ImGui_CloseCurrentPopup(ctx)
          elseif reaper.ImGui_MenuItem(ctx, "About / Support") then
            psv_block_document_interactions_this_frame(ctx)
            show_about_overlay = true
            PSV_TOP_ROW_CUSTOM_MENU_OPEN = nil
            reaper.ImGui_CloseCurrentPopup(ctx)
          -- PSV_NAV_DIAG_BEGIN help
          elseif reaper.ImGui_MenuItem(ctx, "Скопировать логи") then
            psv_block_document_interactions_this_frame(ctx)
            if not search_diag.copy(ctx) then
              reaper.MB("Не удалось скопировать логи в буфер обмена.", SCRIPT_NAME, 0)
            end
            PSV_TOP_ROW_CUSTOM_MENU_OPEN = nil
            reaper.ImGui_CloseCurrentPopup(ctx)
          -- PSV_NAV_DIAG_END help
          end
        end
        end_native_like_custom_popup(trigger, popup_open)
      end

      -- Start the custom top-row menu family at the local menu-row left edge.
      -- This removes the remaining native menu-bar left inset for the first
      -- custom trigger without changing Search/Comments right-side anchoring.
      if reaper.ImGui_SetCursorPosX then
        reaper.ImGui_SetCursorPosX(ctx, 0)
      end

      if reaper.ImGui_StyleVar_FramePadding then
        reaper.ImGui_PushStyleVar(
          ctx,
          reaper.ImGui_StyleVar_FramePadding(),
          4,
          math.max(
            tonumber(UI_TOP_ROW_FRAME_PAD_Y) or 10,
            ((tonumber(UI_TOP_ROW_TARGET_H) or 38) - reaper.ImGui_GetTextLineHeight(ctx)) * 0.5
          )
        )
      end
      local file_trigger = render_custom_top_menu_trigger("File", "file", "##file_custom_popup")
      render_custom_file_popup(file_trigger)
      if reaper.ImGui_StyleVar_FramePadding then reaper.ImGui_PopStyleVar(ctx) end

      -- Keep custom File/View/Theme/Help triggers adjacent with the same
      -- zero-spacing pattern accepted for Theme/Help.
      reaper.ImGui_SameLine(ctx, 0, 0)

      if reaper.ImGui_StyleVar_FramePadding then
        reaper.ImGui_PushStyleVar(
          ctx,
          reaper.ImGui_StyleVar_FramePadding(),
          4,
          math.max(
            tonumber(UI_TOP_ROW_FRAME_PAD_Y) or 10,
            ((tonumber(UI_TOP_ROW_TARGET_H) or 38) - reaper.ImGui_GetTextLineHeight(ctx)) * 0.5
          )
        )
      end
      local view_trigger = render_custom_top_menu_trigger("View", "view", "##view_custom_popup")
      render_custom_view_popup(view_trigger)
      if reaper.ImGui_StyleVar_FramePadding then reaper.ImGui_PopStyleVar(ctx) end

      reaper.ImGui_SameLine(ctx, 0, 0)

      if reaper.ImGui_StyleVar_FramePadding then
        reaper.ImGui_PushStyleVar(
          ctx,
          reaper.ImGui_StyleVar_FramePadding(),
          4,
          math.max(
            tonumber(UI_TOP_ROW_FRAME_PAD_Y) or 10,
            ((tonumber(UI_TOP_ROW_TARGET_H) or 38) - reaper.ImGui_GetTextLineHeight(ctx)) * 0.5
          )
        )
      end
      local theme_trigger = render_custom_top_menu_trigger("Theme", "theme", "##theme_custom_popup")
      render_custom_theme_popup(theme_trigger)
      if reaper.ImGui_StyleVar_FramePadding then reaper.ImGui_PopStyleVar(ctx) end

      reaper.ImGui_SameLine(ctx, 0, 0)

      if reaper.ImGui_StyleVar_FramePadding then
        reaper.ImGui_PushStyleVar(
          ctx,
          reaper.ImGui_StyleVar_FramePadding(),
          4,
          math.max(
            tonumber(UI_TOP_ROW_FRAME_PAD_Y) or 10,
            ((tonumber(UI_TOP_ROW_TARGET_H) or 38) - reaper.ImGui_GetTextLineHeight(ctx)) * 0.5
          )
        )
      end
      local help_trigger = render_custom_top_menu_trigger("Help", "help", "##help_custom_popup")
      render_custom_help_popup(help_trigger)
      if reaper.ImGui_StyleVar_FramePadding then reaper.ImGui_PopStyleVar(ctx) end

      -- Menu actions such as Open/Clear can change the document state before
      -- the right-aligned Search field is rendered in the same menu-bar frame.
      -- Recompute the enabled state here so the moved field keeps the old
      -- standalone-row behavior after File menu actions.
      search_enabled = (file_path ~= nil and file_path ~= "" and #paragraphs > 0)
      if not search_enabled then
        if search_input_buf ~= "" or reaper.ImGui_TextFilter_IsActive(search_filter) then
          reaper.ImGui_TextFilter_Clear(search_filter)
          search_input_buf = ""
        end
        search_nav_index = 0
        search_nav_scroll_target = nil
      end

      -- Right-align the Search/Comments pair inside the native menu row.
      -- Target order: Search sits immediately to the left of Comments, while
      -- Comments is the rightmost control in this pair. Search hits are optional
      -- and are shown only when they do not collide with the reserved pair area.
      local menu_row_w = reaper.ImGui_GetWindowWidth(ctx)
      local menu_row_pad_r = 8

      local comments_label_w = select(1, reaper.ImGui_CalcTextSize(ctx, "Comments"))
      local comments_menu_w = comments_label_w + 22
      local comments_gap_to_search = tonumber(UI_TOP_ROW_COMMENTS_GAP_TO_SEARCH) or 8
      if comments_gap_to_search < 0 then comments_gap_to_search = 0 end

      -- Comments is the rightmost control. Search is positioned from Comments
      -- to the left, and must not push Comments through normal cursor flow.
      local comments_menu_x = menu_row_w - menu_row_pad_r - comments_menu_w
      local search_field_x = comments_menu_x - comments_gap_to_search - UI_SEARCH_FIELD_W

      local pair_left_min_x = reaper.ImGui_GetCursorPosX(ctx) + 8
      local comments_actual_gap = comments_gap_to_search
      local comments_min_gap_to_search = 2
      if search_field_x < pair_left_min_x then
        comments_actual_gap = comments_menu_x - UI_SEARCH_FIELD_W - pair_left_min_x
        if comments_actual_gap < comments_min_gap_to_search then
          comments_actual_gap = comments_min_gap_to_search
        end
        search_field_x = comments_menu_x - comments_actual_gap - UI_SEARCH_FIELD_W
      end

      reaper.ImGui_SameLine(ctx)
      reaper.ImGui_SetCursorPosX(ctx, search_field_x)
      render_search_field_inline()

      -- Capture the actual rendered Search field rect for sidebar alignment.
      -- The sidebar width pass uses screen-space geometry from the current
      -- frame instead of fixed width tuning, so resize/font/DPI changes keep
      -- the sidebar left edge aligned to the Search field when possible.
      PSV_TOP_ROW_SEARCH_RECT_MIN_X = select(1, reaper.ImGui_GetItemRectMin(ctx))
      PSV_TOP_ROW_SEARCH_RECT_MAX_X = select(1, reaper.ImGui_GetItemRectMax(ctx))

      -- Input is processed above. Draw the counter from this frame's query
      -- without submitting another item or changing the Search item geometry.
      ensure_search_query_cache()
      if search_enabled and search_query_cache.has_filter then
        local hits_text = string.format("%d / %d", search_nav_index, search_query_cache.occurrence_count or 0)
        local text_w, text_h = reaper.ImGui_CalcTextSize(ctx, hits_text)
        local min_x, min_y = reaper.ImGui_GetItemRectMin(ctx)
        local _, max_y = reaper.ImGui_GetItemRectMax(ctx)
        local text_x = min_x - 8 - text_w
        local window_x = reaper.ImGui_GetWindowPos(ctx)
        if text_x >= window_x + pair_left_min_x then
          reaper.ImGui_DrawList_AddText(reaper.ImGui_GetWindowDrawList(ctx), text_x,
            min_y + math.max(0, (max_y - min_y - text_h) * 0.5), C_DIM, hits_text)
        end
      end

      -- Keep Comments at the right edge of the pair. Do not allow the custom
      -- Search field cursor flow to recalculate or push it.
      reaper.ImGui_SameLine(ctx)
      reaper.ImGui_SetCursorPosX(ctx, comments_menu_x)
      render_comments_sidebar_toggle_trigger(comments_menu_w)

      if UI_TOP_ROW_SEPARATOR_ENABLED == true then
        local sep_rgba = UI_TOP_ROW_SEPARATOR_RGBA or {150, 150, 150, 255}
        local sep_thickness = tonumber(UI_TOP_ROW_SEPARATOR_THICKNESS) or 1.0
        if sep_thickness < 0.5 then sep_thickness = 0.5 end
        local win_x = reaper.ImGui_GetWindowPos(ctx)
        local win_w = reaper.ImGui_GetWindowWidth(ctx)
        local sep_y = top_row_separator_y
        reaper.ImGui_DrawList_AddLine(
          reaper.ImGui_GetWindowDrawList(ctx),
          win_x, sep_y,
          win_x + win_w, sep_y,
          rgba(sep_rgba[1] or 150, sep_rgba[2] or 150, sep_rgba[3] or 150, sep_rgba[4] or 255),
          sep_thickness
        )
      end

      reaper.ImGui_EndMenuBar(ctx)
    end

    if top_row_style_var_count > 0 then
      reaper.ImGui_PopStyleVar(ctx, top_row_style_var_count)
    end
    if top_row_window_style_var_count > 0 then
      reaper.ImGui_PopStyleVar(ctx, top_row_window_style_var_count)
      top_row_window_style_var_count = 0
    end

    local escape_pressed = reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Escape(), false)
    -- PSV_NAV_DIAG_BEGIN hook
    if escape_pressed then
      search_diag.record("escape_routed", { owner=escape_key_owner,
        menu=tostring(PSV_TOP_ROW_CUSTOM_MENU_OPEN), search_active=search_input_active })
    end
    -- PSV_NAV_DIAG_END hook
    if escape_pressed and escape_key_owner == "menu" then
      PSV_TOP_ROW_CUSTOM_MENU_OPEN = nil
      psv_block_document_interactions_this_frame(ctx)
    end
    if search_enabled and escape_key_owner == "search" and search_keyboard_available(ctx)
       and escape_pressed and search_input_buf ~= "" then
      reaper.ImGui_TextFilter_Clear(search_filter)
      search_input_buf = ""
      search_nav_index = 0
      search_nav_scroll_target = nil
    end

    local match_indices, match_lookup, has_filter, token_hit_lookup = collect_matching_paragraph_indices()
    local total_matches = has_filter and #search_query_cache.occurrences or 0

    -- PSV_NAV_DIAG_BEGIN hook
    search_diag.observe_keys(ctx, search_enabled, total_matches, has_filter)
    -- PSV_NAV_DIAG_END hook
    if (not search_enabled) or (not has_filter) or total_matches == 0 then
      search_nav_index = 0
      search_nav_scroll_target = nil
      search_nav_occurrence = nil
    else
      if search_nav_index < 0 or search_nav_index > total_matches then search_nav_index = 0 end
      local key_mods = reaper.ImGui_GetKeyMods(ctx)
      local shift_held = (key_mods & reaper.ImGui_Mod_Shift()) ~= 0
      local enter_pressed = reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Enter(), false)
        or (reaper.ImGui_Key_KeypadEnter and reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_KeypadEnter(), false))
      if search_keyboard_available(ctx) and enter_pressed then
        if shift_held then
          search_nav_index = search_nav_index == 0 and total_matches or math.max(1, search_nav_index - 1)
        else
          search_nav_index = math.min(total_matches, search_nav_index + 1)
        end
        search_nav_occurrence = search_query_cache.occurrences[search_nav_index]
        search_nav_scroll_target = search_nav_occurrence.paragraph_index

        -- PSV_NAV_DIAG_BEGIN hook
        search_diag.selected(search_diag.index_before_keys, key_mods, shift_held)
        -- PSV_NAV_DIAG_END hook
      end
    end

    -- Body starts directly below the combined menu/Search row.
    -- The top-row separator is drawn on the menu-row bottom edge itself,
    -- without a separate separator-owned vertical band.
    local body_font = get_font(font_size)
    reaper.ImGui_PushFont(ctx, body_font, font_size)

    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_NavCursor(), rgba(0, 0, 0, 0))

    local body_child_flags = reaper.ImGui_ChildFlags_None()
    local body_window_flags = reaper.ImGui_WindowFlags_NoScrollWithMouse()

    local body_child_w = 0
    local comments_sidebar_w = 0
    local comments_sidebar_gap = 0
    local comments_sidebar_open = (PSV_COMMENTS_SIDEBAR_OPEN == true)
    local available_content_w = select(1, reaper.ImGui_GetContentRegionAvail(ctx))
    local content_start_screen_x = select(1, reaper.ImGui_GetCursorScreenPos(ctx))

    if comments_sidebar_open then
      local requested_sidebar_w = math.max(0, tonumber(UI_COMMENTS_SIDEBAR_W) or 0)
      local requested_sidebar_gap = math.max(0, tonumber(UI_COMMENTS_SIDEBAR_GAP) or 0)
      local min_body_w = math.max(0, tonumber(UI_COMMENTS_SIDEBAR_MIN_BODY_W) or 320)
      local max_sidebar_w = math.max(0, available_content_w - requested_sidebar_gap - min_body_w)

      -- Primary sidebar width is derived from the actual Search field left edge
      -- captured in the top row. This keeps the sidebar left boundary aligned
      -- with Search across font/theme/DPI/window-size changes. UI_COMMENTS_SIDEBAR_W
      -- remains the fallback when Search geometry is unavailable this frame.
      local search_left_x = tonumber(PSV_TOP_ROW_SEARCH_RECT_MIN_X)
      local sidebar_right_x = content_start_screen_x + available_content_w
      if search_left_x and sidebar_right_x and search_left_x < sidebar_right_x then
        requested_sidebar_w = math.max(0, sidebar_right_x - search_left_x)
      end

      comments_sidebar_w = math.min(requested_sidebar_w, max_sidebar_w)
      if comments_sidebar_w > 0 then
        comments_sidebar_gap = requested_sidebar_gap
        body_child_w = math.max(0, available_content_w - comments_sidebar_w - comments_sidebar_gap)
      else
        comments_sidebar_gap = 0
        body_child_w = available_content_w
      end
    end

    local effective_body_w = comments_sidebar_open and body_child_w or available_content_w
    if effective_body_w and effective_body_w > 0 then
      local prev_body_w = tonumber(PSV_COMMENTS_SIDEBAR_LAST_BODY_W)
      if (not prev_body_w) or math.abs(prev_body_w - effective_body_w) > 0.5 then
        body_render_cache.layout_key = ""
        body_render_cache.paragraph_heights = {}
        body_render_cache.paragraph_start_y = {}
        reset_body_scroll_inertia()

        -- PSV_NAV_DIAG_BEGIN hook
        search_diag.record("body_width_changed", { previous=prev_body_w, current=effective_body_w })
        -- PSV_NAV_DIAG_END hook
        PSV_COMMENTS_SIDEBAR_LAST_BODY_W = effective_body_w
      end
    end

    local body_child_visible = false
    if reaper.ImGui_BeginChild(ctx, "##body", body_child_w, 0, body_child_flags, body_window_flags) then
      body_child_visible = true
      local wheel_y = 0
      local body_inertia_suppressed = false

      if UI_BODY_MANUAL_WHEEL_SCROLL_ENABLED
         and reaper.ImGui_IsWindowHovered(ctx, reaper.ImGui_HoveredFlags_None()) then
        wheel_y = select(1, reaper.ImGui_GetMouseWheel(ctx))

        -- Former-card wheel shield:
        -- after Escape closes a card while the mouse is still over it, block
        -- only the residual wheel/trackpad stream over that former card rect.
        -- Once the stream has been idle for a couple of frames, release the
        -- shield even if the mouse remains over the former card area, so a new
        -- deliberate body wheel-scroll works without focus/mouse reset.
        if paragraphs.comments and paragraphs.comments.former_card_wheel_shield_active then
          local shield_x = tonumber(paragraphs.comments.former_card_x)
          local shield_y = tonumber(paragraphs.comments.former_card_y)
          local shield_x2 = tonumber(paragraphs.comments.former_card_x2)
          local shield_y2 = tonumber(paragraphs.comments.former_card_y2)
          if shield_x and shield_y and shield_x2 and shield_y2 then
            local mouse_x, mouse_y = reaper.ImGui_GetMousePos(ctx)
            if mouse_x >= shield_x and mouse_x <= shield_x2
               and mouse_y >= shield_y and mouse_y <= shield_y2 then
              if wheel_y ~= 0 then
                wheel_y = 0
                body_inertia_suppressed = true
                reset_body_scroll_inertia()
                paragraphs.comments.former_card_wheel_idle_frames = 0
              else
                local idle_frames = (tonumber(paragraphs.comments.former_card_wheel_idle_frames) or 0) + 1
                if idle_frames >= 2 then
                  paragraphs.comments.former_card_wheel_shield_active = nil
                  paragraphs.comments.former_card_x = nil
                  paragraphs.comments.former_card_y = nil
                  paragraphs.comments.former_card_x2 = nil
                  paragraphs.comments.former_card_y2 = nil
                  paragraphs.comments.former_card_wheel_idle_frames = nil
                else
                  paragraphs.comments.former_card_wheel_idle_frames = idle_frames
                end
              end
            else
              paragraphs.comments.former_card_wheel_shield_active = nil
              paragraphs.comments.former_card_x = nil
              paragraphs.comments.former_card_y = nil
              paragraphs.comments.former_card_x2 = nil
              paragraphs.comments.former_card_y2 = nil
              paragraphs.comments.former_card_wheel_idle_frames = nil
            end
          else
            paragraphs.comments.former_card_wheel_shield_active = nil
            paragraphs.comments.former_card_x = nil
            paragraphs.comments.former_card_y = nil
            paragraphs.comments.former_card_x2 = nil
            paragraphs.comments.former_card_y2 = nil
            paragraphs.comments.former_card_wheel_idle_frames = nil
          end
        end

        -- Narrow card-local wheel guard:
        -- if the active comment card occupied this mouse position on the previous
        -- frame, do not also scroll the main body. The card render block consumes
        -- the same wheel event for its own local scroll state later in this frame.
        if paragraphs.comments and paragraphs.comments.active_id then
          local card_x = tonumber(paragraphs.comments.card_x)
          local card_y = tonumber(paragraphs.comments.card_y)
          local card_x2 = tonumber(paragraphs.comments.card_x2)
          local card_y2 = tonumber(paragraphs.comments.card_y2)
          if card_x and card_y and card_x2 and card_y2 then
            local mouse_x, mouse_y = reaper.ImGui_GetMousePos(ctx)
            if mouse_x >= card_x and mouse_x <= card_x2
               and mouse_y >= card_y and mouse_y <= card_y2 then
              wheel_y = 0
              body_inertia_suppressed = true
              reset_body_scroll_inertia()
            end
          end
        end

        -- Ctrl/Cmd + wheel changes document font size instead of scrolling
        -- the body. Keep the existing target-branch wheel axis contract: vertical
        -- wheel is select(1, ImGui_GetMouseWheel), positive means wheel-up.
        -- This is intentionally not the inertial-scroll controller from v2.2.x.
        if wheel_y ~= 0 then
          local key_mods = reaper.ImGui_GetKeyMods(ctx)
          local zoom_mod_held = ((key_mods & reaper.ImGui_Mod_Ctrl()) ~= 0)
                             or ((key_mods & reaper.ImGui_Mod_Super()) ~= 0)
          if zoom_mod_held then
            local font_delta = (wheel_y > 0) and 1 or -1
            local next_font_size = clamp_font_size(font_size + font_delta)
            if next_font_size ~= font_size then
              font_size = next_font_size
              save_cfg()
            end

            -- The zoom wheel event must not also scroll the body or leave
            -- residual body inertia after the font-size gesture.
            reset_body_scroll_inertia()
            wheel_y = 0
          end
        end
      end

      -- If an already-active native comment card is under the mouse, do not let
      -- previously accumulated body inertia keep moving the document underneath it.
      -- This is outside the body-hover wheel read path because the sibling overlay
      -- card can own hover while ##body itself is no longer hovered.
      if paragraphs.comments and paragraphs.comments.active_id then
        local card_x = tonumber(paragraphs.comments.card_x)
        local card_y = tonumber(paragraphs.comments.card_y)
        local card_x2 = tonumber(paragraphs.comments.card_x2)
        local card_y2 = tonumber(paragraphs.comments.card_y2)
        if card_x and card_y and card_x2 and card_y2 then
          local mouse_x, mouse_y = reaper.ImGui_GetMousePos(ctx)
          if mouse_x >= card_x and mouse_x <= card_x2
             and mouse_y >= card_y and mouse_y <= card_y2 then
            wheel_y = 0
            body_inertia_suppressed = true
            reset_body_scroll_inertia()
          end
        end
      end

      -- После File → Clear сбрасываем scroll самого ##body только здесь,
      -- где ImGui_SetScrollY() относится именно к body child. Это гасит
      -- одно-/двухкадровый хвост старого document-scrollbar в empty-state
      -- и не затрагивает обычный project-scroll restore для загруженных HTML.
      if #paragraphs == 0
         and body_render_cache.empty_scroll_reset_frames
         and body_render_cache.empty_scroll_reset_frames > 0 then
        reaper.ImGui_SetScrollY(ctx, 0)
        pending_body_scroll_y = nil
        pending_body_scroll_restore_frames = 0
        current_body_scroll_y = 0
        reset_body_scroll_inertia()
        if last_proj_key then
          project_body_scroll_y[last_proj_key] = 0
        end

        -- Не даём случайному wheel/trackpad событию на этом же кадре снова
        -- записать ненулевой scroll сразу после reset-а пустого body.
        wheel_y = 0

        body_render_cache.empty_scroll_reset_frames = body_render_cache.empty_scroll_reset_frames - 1
        if body_render_cache.empty_scroll_reset_frames <= 0 then
          body_render_cache.empty_scroll_reset_frames = nil
        end
      end

      -- Восстановление project-scoped scroll Y выполняется только внутри ##body,
      -- потому что только здесь официальные scroll API относятся к нужному
      -- scrollable child window. Restore короткий и самозатухающий.
      if pending_body_scroll_restore_frames > 0 and #paragraphs > 0 then
        if wheel_y ~= 0 then
          pending_body_scroll_y = nil
          pending_body_scroll_restore_frames = 0
        else
          local restore_y = pending_body_scroll_y or 0
          local scroll_max_y = reaper.ImGui_GetScrollMaxY(ctx)

          if restore_y < 0 then
            restore_y = 0
          elseif restore_y > scroll_max_y then
            restore_y = scroll_max_y
          end


          -- PSV_NAV_DIAG_BEGIN hook
          search_diag.override("project_restore", restore_y)
          -- PSV_NAV_DIAG_END hook
          reaper.ImGui_SetScrollY(ctx, restore_y)
          reset_body_scroll_inertia()

          pending_body_scroll_restore_frames = pending_body_scroll_restore_frames - 1
          if pending_body_scroll_restore_frames <= 0 then
            pending_body_scroll_y = nil
          end
        end
      end

      if UI_BODY_MANUAL_WHEEL_SCROLL_ENABLED then
        if body_inertia_suppressed then
          reset_body_scroll_inertia()
        else
          PSV_PROFILER_BLOCK_T0 = psv_profiler_block_begin("body_scroll")
          update_body_inertial_scroll(ctx, wheel_y)
          psv_profiler_block_end("body_scroll", PSV_PROFILER_BLOCK_T0)
        end
      end

      if #paragraphs > 0 then
        -- Page layout addon model: drawlist-only layer inside ##body, before
        -- document text rendering. It reads only the current body scroll/window
        -- metrics and does not change body margins, wrap, search or comments.
        -- Empty/Open screen intentionally does not draw the visual page stack:
        -- it should remain a clean app/open state, not a document page view.
        PSV_PROFILER_BLOCK_T0 = psv_profiler_block_begin("page_layer")
        render_page_layer(ctx)
        psv_profiler_block_end("page_layer", PSV_PROFILER_BLOCK_T0)
        PSV_PROFILER_BLOCK_T0 = psv_profiler_block_begin("document_render")
        render_paragraphs(ctx, has_filter, match_lookup, token_hit_lookup)
        psv_profiler_block_end("document_render", PSV_PROFILER_BLOCK_T0)
        DOCX_IMPORT.print_pending_adapter_lines_tail_status()
      else
        PSV_PROFILER_BLOCK_T0 = psv_profiler_block_begin("empty_render")
        render_empty_hint(ctx)
        psv_profiler_block_end("empty_render", PSV_PROFILER_BLOCK_T0)
      end

      if UI_BODY_MANUAL_WHEEL_SCROLL_ENABLED
         and PSV_BODY_SCROLL_STATE
         and PSV_BODY_SCROLL_STATE.body_scroll_apply_y ~= nil then
        local apply_y = PSV_BODY_SCROLL_STATE.body_scroll_apply_y
        local scroll_max_y = reaper.ImGui_GetScrollMaxY(ctx)
        if apply_y < 0 then
          apply_y = 0
        elseif apply_y > scroll_max_y then
          apply_y = scroll_max_y
        end

        -- PSV_NAV_DIAG_BEGIN hook
        search_diag.override("inertia", apply_y)
        -- PSV_NAV_DIAG_END hook
        reaper.ImGui_SetScrollY(ctx, apply_y)
        PSV_BODY_SCROLL_STATE.body_scroll_apply_y = nil
      end


      -- Каждый active body-frame обновляет session-local scroll state
      -- для текущего REAPER project key. Это не ExtState и не persistence,
      -- а только память для project switching внутри текущей сессии.
      if last_proj_key then
        current_body_scroll_y = reaper.ImGui_GetScrollY(ctx)
        project_body_scroll_y[last_proj_key] = current_body_scroll_y
      end


      -- PSV_NAV_DIAG_BEGIN hook
      search_diag.observe_scroll(ctx)
      -- PSV_NAV_DIAG_END hook
      reaper.ImGui_EndChild(ctx)
    end

    if comments_sidebar_open and comments_sidebar_w > 0 then
      reaper.ImGui_SameLine(ctx, 0, comments_sidebar_gap)

      -- Sidebar is a persistent document-area sibling, but visually it should
      -- attach to the same top-row bottom line as the custom dropdowns. Keep the
      -- document ##body in the normal flow, and only retarget the sidebar
      -- container Y by converting the captured top-row screen anchor to the
      -- current local cursor coordinate.
      if top_row_separator_y then
        local _, sidebar_cursor_screen_y = reaper.ImGui_GetCursorScreenPos(ctx)
        local sidebar_cursor_local_y = reaper.ImGui_GetCursorPosY(ctx)
        local sidebar_target_local_y = sidebar_cursor_local_y + (top_row_separator_y - sidebar_cursor_screen_y)
        reaper.ImGui_SetCursorPosY(ctx, sidebar_target_local_y)
      end

      local sidebar_child_flags = reaper.ImGui_ChildFlags_None()
      local sidebar_window_flags = reaper.ImGui_WindowFlags_None()
      local sidebar_outer_bg_col = resolve_comments_sidebar_bg_color(C_CHROME_DEEP)
      if UI_COMMENTS_SIDEBAR_SCROLLBAR_SEPARATION_ENABLED == true then
        sidebar_outer_bg_col = rgba(0, 0, 0, 0)
      end
      reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ChildBg(), sidebar_outer_bg_col)
      if reaper.ImGui_BeginChild(ctx, "##comments_sidebar", comments_sidebar_w, 0, sidebar_child_flags, sidebar_window_flags) then
        PSV_PROFILER_BLOCK_T0 = psv_profiler_block_begin("comments_sidebar")
        render_comments_navigator_sidebar_content(ctx)
        psv_profiler_block_end("comments_sidebar", PSV_PROFILER_BLOCK_T0)
        reaper.ImGui_EndChild(ctx)
      end
      reaper.ImGui_PopStyleColor(ctx, 1)
    end

    -- v2.0.76: submit the one current active-comment native card as a
    -- sibling overlay after the document/sidebar layout. Do not submit old/new
    -- or A/B windows. The renderer internals and pending_args payload are
    -- intentionally unchanged.
    if body_child_visible
       and PSV_COMMENT_CARD_RENDERER
       and type(PSV_COMMENT_CARD_RENDERER.pending_args) == "table" then
      PSV_PROFILER_BLOCK_T0 = psv_profiler_block_begin("comment_card")
      PSV_COMMENT_CARD_RENDERER.try_render(PSV_COMMENT_CARD_RENDERER.pending_args)
      psv_profiler_block_end("comment_card", PSV_PROFILER_BLOCK_T0)
      PSV_COMMENT_CARD_RENDERER.pending_args = nil
    end
    reaper.ImGui_PopStyleColor(ctx)

    reaper.ImGui_PopFont(ctx)
    render_about_overlay(ctx)
    reaper.ImGui_End(ctx)
  end

  if top_row_window_style_var_count > 0 then
    reaper.ImGui_PopStyleVar(ctx, top_row_window_style_var_count)
    top_row_window_style_var_count = 0
  end

  reaper.ImGui_PopStyleColor(ctx, pushed_colors)

  psv_profiler_frame_end(PSV_PROFILER_FRAME_T0, PROFILER_ENABLED and psv_profiler_make_context_label() or nil)

  if win_open then
    reaper.defer(loop)
  else
    save_project_ui_state(last_proj_key)
  end
end

-- ══════════════════════════════════════════════════════════════
local startup_delay_frames = 0

local function bootstrap()
  if startup_boot_phase == 0 then
    owner_project = reaper.EnumProjects(-1, "")
    owner_project_key = get_project_key()
    last_proj_key = owner_project_key
    load_ui_theme()
    load_window_geometry_for_project(owner_project_key)
    load_project_ui_state(owner_project_key)
    load_file_for_project()
    startup_boot_phase = 1
    reaper.defer(bootstrap)
    return
  end

  -- Pre-window delay: hold off ImGui context creation and first ImGui_Begin
  -- for UI_STARTUP_DELAY_FRAMES defer frames. During this period only
  -- reaper.defer(bootstrap) is called -- no ImGui calls whatsoever.
  if startup_delay_frames < UI_STARTUP_DELAY_FRAMES then
    startup_delay_frames = startup_delay_frames + 1
    reaper.defer(bootstrap)
    return
  end

  ensure_imgui_resources()
  loop()
end

bootstrap()
