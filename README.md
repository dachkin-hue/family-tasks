# FamilyTasks

Семейный менеджер задач: нативный iOS-клиент на SwiftUI и REST-бэкенд на FastAPI.

```
FamilyTasks/
├── FamilyTasks.swiftpm/     iOS-клиент (App Playground)
├── backend/                 FastAPI + PostgreSQL
├── API_CONTRACT.md          Контракт между ними
└── .github/workflows/ci.yml Сборка iOS и тесты бэкенда
```

## Как это разрабатывается без Mac

Xcode на Windows не существует, и локальной замены у него нет: SwiftUI и SwiftData
живут только внутри macOS SDK. Поэтому цикл такой:

| Где | Что делается |
|-----|--------------|
| Windows | правка кода, весь бэкенд, его тесты |
| GitHub Actions | компиляция iOS на macOS-раннере, тесты, линтер |
| iPad | запуск приложения и проверка интерфейса руками |

Проект лежит в формате `.swiftpm` (App Playground) именно поэтому: один и тот же
пакет открывается в Swift Playgrounds на iPad, собирается в CI и, если однажды
появится Mac, открывается в Xcode без конвертации.

## iOS-клиент

Требования: iOS 17.0+ (SwiftData, `@Observable`, `ContentUnavailableView`).
Сторонних зависимостей нет — сеть на `URLSession`, Keychain на `Security.framework`.

### Оформление

Приложение оформлено по дизайн-системе **Organic** от Claude Design. Токены перенесены
в [`DesignSystem/Theme.swift`](FamilyTasks.swiftpm/DesignSystem/Theme.swift) один в один из
`design_handoff_notes/prototype/_ds/organic-*/styles.css`:

| Роль | Токен | Значение |
|------|-------|----------|
| Фон экрана | `--color-bg` | `#f5ead8` |
| Поверхность строки | `--color-neutral-100` | `#f9f4ed` |
| Текст | `--color-text` | `#201e1d` |
| Акцент — действия и внимание | `--color-accent` | `#c67139` |
| Второй акцент — движение и готовность | `--color-accent-2` | `#7a8a5e` |
| Скругления | `--radius-*` | 8 / 16 / 28 |

Правило одно: экраны обращаются к ролям (`Theme.accent`, `Theme.surface`), а не к литералам.
Менять цвет — только в `Theme.swift`.

**Тёмной темы нет.** В манифесте системы `themes: []`, она светлая, поэтому все цвета
заданы явно и не зависят от системной настройки устройства.

**Системные компоненты сохранены.** `List`, `Form` и `ContentUnavailableView` перекрашены
через `.organicBackground()` и `.organicRow()`, а не заменены на `ScrollView` с самописными
ячейками. Так остаются бесплатными свайпы, разделители, Dynamic Type и VoiceOver —
то, что при переходе на собственную вёрстку пришлось бы писать руками.
Навигационная и таб-панель красятся через `Theme.applySystemAppearance()`: модификаторами
SwiftUI они не берутся.

### Шрифты

**Caprasimo** для заголовков, **Figtree** для текста — те же, что в дизайн-системе.
Файлы лежат в `FamilyTasks.swiftpm/Resources/Fonts/` вместе с лицензиями OFL,
под которыми они распространяются.

Регистрация — в рантайме через `CTFontManagerRegisterFontsForURL` (`Theme.registerFonts()`),
а не через `UIAppFonts` в Info.plist: у App Playground своего Info.plist нет, а так одно
и то же работает и в пакете, и в обычном Xcode-проекте. Вызывается из
`Theme.applySystemAppearance()` на старте приложения.

Начертания подставляются **по имени файла**, а не через `.weight()`:

| Вес | Файл |
|-----|------|
| regular | `Figtree-Regular.ttf` |
| medium | `Figtree-Medium.ttf` |
| semibold | `Figtree-SemiBold.ttf` |
| bold и тяжелее | `Figtree-Bold.ttf` |

Для кастомного семейства SwiftUI не синтезирует вес, а ищет зарегистрированное начертание —
`.weight(.semibold)` на `Figtree-Regular` не дал бы полужирного.

Если файлов не окажется, `Theme.heading` и `Theme.body` вернут системный аналог,
и приложение останется работоспособным.

### Запуск на iPad

1. Установите **Swift Playgrounds** из App Store.
2. Перенесите папку `FamilyTasks.swiftpm` на iPad — через iCloud Drive
   (есть клиент для Windows) или архивом в приложение «Файлы».
3. Откройте её в Swift Playgrounds и нажмите запуск.

Приложение работает на встроенных данных: `AppConfig.useMockBackend = true`.
На экране входа подойдёт любая почта и пароль от 4 символов.

Проверить состояния интерфейса:

```swift
// AppConfig.swift
static let useMockBackend = true

// MockBackend.swift — экран ошибки
var shouldFail = true

// MockBackend.swift — долгая загрузка
var latency: Duration = .seconds(3)
```

Блокировка после перебора пароля воспроизводится и в моке: пять раз введите
пароль короче 4 символов.

### Переключение на боевой бэкенд

```swift
// AppConfig.swift
static let useMockBackend = false
static let baseURL = URL(string: "https://api.вашдомен.ru/v1")!
static let keychainService = "ru.вашдомен.familytasks"
```

Больше нигде ничего менять не нужно: `AppEnvironment.live()` подставит
`NetworkManager` вместо `MockBackend`, протоколы сервисов останутся теми же.

### Структура

```
FamilyTasks.swiftpm/
├── Package.swift              Манифест App Playground
├── App/
│   ├── FamilyTasksApp.swift   @main
│   ├── AppConfig.swift        Флаг мока, baseURL, Keychain service
│   ├── AppEnvironment.swift   DI: live() и preview()
│   └── AppSession.swift       Состояние авторизации на весь апп
├── Core/
│   ├── Networking/
│   │   ├── NetworkManager.swift   actor: 401 → refresh → retry
│   │   ├── APIEndpoint.swift      Вся карта REST в одном файле
│   │   ├── APIError.swift         Типизированные ошибки + isRetryable
│   │   ├── JSONCoding.swift       snake_case + ISO-8601
│   │   └── TokenStorage.swift     actor поверх Keychain
│   └── Persistence/
│       ├── ModelContainer+App.swift
│       ├── TaskRepository.swift   Слияние «сервер → кэш»
│       └── NoteRepository.swift   То же для заметок
├── Models/
│   ├── DTO/                   Codable-структуры сервера + Visibility
│   └── Local/                 TaskItem, NoteItem — @Model, локальный кэш
├── Services/
│   ├── ServiceProtocols.swift Контракты задач, семьи, авторизации
│   ├── RemoteServices.swift   Реализация поверх NetworkManager
│   ├── NoteService.swift      Контракт заметок + боевой и мок-сервис
│   └── MockBackend.swift      actor-имитация сервера + сидовые данные
├── DesignSystem/
│   ├── ViewState.swift        idle / loading / loaded / empty / failed
│   ├── StateViews.swift       Загрузка, ошибка, пустой список
│   ├── Theme.swift            Токены Organic: цвета, шрифты, радиусы
│   └── DomainStyling.swift    Иконки, аватары, формат дат
└── Features/
    ├── Root/       RootView (сплэш → вход → табы), MainTabView
    ├── Auth/       LoginView
    ├── TaskList/   ViewModel, список, строка, редактор
    ├── TaskDetail/ Экран задачи
    ├── Notes/      ViewModel, список, строка, редактор заметок
    └── Profile/    Состав семьи, профиль, выход
```

### Принятые решения

**Сервер — источник истины, SwiftData — кэш.** `TaskRepository.merge` перезаписывает
локальные записи данными сервера и удаляет то, чего на сервере больше нет.
Поэтому в `TaskItem` нет флагов вида `isDirty`: офлайн-редактирование не поддерживается
намеренно — это отдельный, заметно более дорогой уровень со своей очередью операций.

**Работа с `ModelContext` — на главном акторе.** Репозиторий помечен `@MainActor`
и использует `mainContext`. Для семейного списка задач объёмы такие, что фоновый
контекст только добавил бы сложности с `Sendable`.

**`empty` отделён от `loaded([])`.** У пустого списка своя вёрстка с призывом
к действию, и текст зависит от активного фильтра.

**Оформление — из дизайн-системы, поведение — системное.** Цвета и типографика взяты
из Organic, но компоненты остались нативными. Это сознательный компромисс: фирменный вид
без потери того, что `List` и `Form` дают даром.

**Ошибки разделены на два класса.** Ошибка загрузки занимает весь экран и предлагает
«Повторить»; ошибка операции показывается алертом поверх данных. У `429` кнопки
«Повторить» нет намеренно — она предлагала бы заблокированное действие.

## Бэкенд

Поднимается за пять минут на SQLite, в продакшене — PostgreSQL.
Подробности, деплой и принятые решения: [backend/README.md](backend/README.md).

```bash
cd backend
python -m venv .venv && source .venv/bin/activate
pip install -r requirements-dev.txt
cp .env.example .env
alembic upgrade head
uvicorn app.main:app --reload
```

## Статус

| Часть | Состояние |
|-------|-----------|
| Бэкенд | 45 тестов зелёные, линтер чист, проверен на живом сервере |
| iOS | **ни разу не компилировался** — Xcode недоступен, ждёт первого прогона CI |

## Что дальше

1. Первая сборка в CI и разбор ошибок компилятора
2. Скриншоты из симулятора артефактом CI — чтобы видеть интерфейс без Mac
3. Роли: `require_parent` на бэкенде написан, но не подключён — нужно решить,
   что запрещено детям
4. Видимость задач в клиенте: поле есть на сервере и у заметок, у `TaskDTO` его пока нет
5. Инвайт в семью: код на бэкенде есть, экрана в клиенте нет
6. Push-уведомления (APNs + `device_tokens`)
7. Смена и восстановление пароля
8. Unit-тесты на `TaskRepository.merge` и `NetworkManager` через `URLProtocol`-стаб
