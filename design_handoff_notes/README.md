# Передача: раздел «Заметки» в iOS-клиенте FamilyTasks

> **Решение изменено заказчиком 14 сентября 2026.**
>
> Пункт «Прототип» ниже говорит, что дизайн-систему Organic в нативный клиент переносить
> не нужно. Это указание **отменено**: приложение перекрашено по Organic.
>
> Что сделано вместо: токены перенесены в `FamilyTasks.swiftpm/DesignSystem/Theme.swift`
> один в один из `prototype/_ds/organic-*/styles.css`, экраны обращаются к ролям
> (`Theme.accent`, `Theme.surface`), а не к литералам. Нативные `List`, `Form`
> и `ContentUnavailableView` **сохранены** и перекрашены модификаторами
> `.organicBackground()` / `.organicRow()` — отказ от них ради точного повторения вёрстки
> прототипа стоил бы свайпов, разделителей, Dynamic Type и VoiceOver.
>
> Шрифты Caprasimo и Figtree тоже перенесены: файлы лежат в
> `FamilyTasks.swiftpm/Resources/Fonts/` с лицензиями OFL, регистрируются в рантайме
> через `CTFontManager`. Подробности — в разделах «Оформление» и «Шрифты»
> корневого README проекта.

## Задача одной строкой

Добавить в `FamilyTasks.swiftpm` четвёртую вкладку «Заметки» на существующий бэкенд-эндпоинт
`/notes`. Swift-код уже написан и лежит в `swift/FamilyTasks.swiftpm/` этого пакета — его нужно
перенести в репозиторий, проверить сборку и прогнать по месту. HTML-прототип в `prototype/` —
это **референс поведения и состава экрана, а не код для переноса**.

## Что уже есть в проекте (не переписывать)

- **Бэкенд готов полностью**: `backend/app/api/routes/notes.py` — GET/POST/PUT/DELETE `/notes`,
  модель `Note` (`backend/app/db/models.py`), схемы `NoteCreate`/`NoteUpdate`/`NoteOut`
  (`backend/app/schemas/note.py`), правила доступа `backend/app/api/access.py`,
  тесты `backend/tests/test_notes.py` и `test_visibility.py`. Миграция
  `511a7e870979_task_visibility_and_notes.py` уже создаёт таблицу `notes`.
- **iOS-клиента для заметок нет**: ни DTO, ни сервиса, ни вкладки.

Контракт, который должен соблюсти клиент:

| Правило | Где в коде бэкенда |
| --- | --- |
| `title` обязателен (1–200), `body` необязателен (до 10 000) | `schemas/note.py` |
| `visibility`: `family` \| `parents`, по умолчанию `family` | `schemas/note.py`, `db/models.py` |
| Ставить `parents` может только родитель, иначе 403 | `access.py: ensure_may_set_visibility` |
| Ребёнку заметки `parents` не отдаются; прямое обращение — 404, не 403 | `access.py: visible_to`, `ensure_visible` |
| Список: недавно изменённые сверху (`updated_at desc`) | `routes/notes.py: list_notes` |
| PUT — полная замена; автора сервер не переписывает | `routes/notes.py: update_note` |
| Общую заметку может править и ребёнок | `tests/test_notes.py: test_child_can_edit_family_note` |

Клиент **не фильтрует видимость сам** — так решено в комментарии `access.py`: клиентская
фильтрация спрятала бы запись с экрана, но она всё равно приехала бы по сети и осела в кэше.

## Что нужно сделать

### 1. Скопировать новые файлы

Из `swift/FamilyTasks.swiftpm/` в одноимённые папки репозитория:

| Файл | Роль |
| --- | --- |
| `Models/DTO/NoteDTO.swift` | `Visibility`, `NoteDTO`, `NoteDraft` под схемы бэкенда |
| `Models/Local/NoteItem.swift` | `@Model`-кэш заметки (SwiftData) |
| `Core/Networking/APIEndpoint-Notes.swift` | **переименовать в `APIEndpoint+Notes.swift`** |
| `Services/NoteService.swift` | `NoteServicing`, `RemoteNoteService`, `MockNotesBackend`, `MockNoteService` |
| `Core/Persistence/NoteRepository.swift` | слияние сервер → кэш, сортировка по `updatedAt desc` |
| `Features/Notes/NotesViewModel.swift` | `ViewState`, поиск, фильтр видимости, быстрая запись |
| `Features/Notes/NotesView.swift` | список, pull-to-refresh, swipe-удаление, пустые состояния |
| `Features/Notes/NoteRowView.swift` | строка списка |
| `Features/Notes/NoteEditorView.swift` | форма создания и редактирования |

### 2. Заменить три существующих файла

Готовые версии лежат в том же дереве. Если файлы изменились после 14 сентября 2026 —
не перезаписывать целиком, а внести три правки вручную:

| Файл | Правка |
| --- | --- |
| `Core/Persistence/ModelContainer-App.swift` → `ModelContainer+App.swift` | `Schema([TaskItem.self])` → `Schema([TaskItem.self, NoteItem.self])` |
| `App/AppEnvironment.swift` | добавить `let noteService: any NoteServicing` в свойства и `init`, передать `MockNoteService(backend: MockNotesBackend())` в `live()` (ветка мока) и `preview()`, `RemoteNoteService(api: api)` в боевой ветке, добавить фабрику `makeNoteRepository()` |
| `Features/Root/MainTabView.swift` | вкладка `NotesView(appEnvironment:)` с `Label("Заметки", systemImage: "note.text")` между «Задачами» и «Семьёй» |

Схема SwiftData меняется — при первом запуске кэш пересоздастся; `makeAppContainer` это
уже умеет (`deleteStoreFiles`), данные приедут с сервера заново. Миграция не нужна.

### 3. Проверить

- Сборка пакета, превью `NotesView` и `NoteEditorView` (моки, `AppEnvironment.preview()`).
- Родителем: создание быстрой записи, создание с текстом, правка, удаление свайпом,
  переключатель «Вся семья / Только родители», подсказка под ним меняется.
- Ребёнком (`UserDTO.previewChild`, вызвать `MockNotesBackend.setCurrentUser(_:)`):
  заметок `parents` в списке нет, сегмент видимости скрыт, общую заметку править можно,
  автор после правки не меняется.
- Состояния из `DesignSystem/StateViews.swift`: `LoadingStateView(title: "Загружаем заметки…")`,
  `EmptyStateView`, `ErrorStateView` (`MockNotesBackend.setShouldFail(true)`).

## Принятые решения — и почему

- **Мок заметок вынесен в отдельный актор `MockNotesBackend`**, а не в `MockBackend`: раздел
  ничего не знает о задачах и авторизации, а править существующий актор из другого файла нельзя.
  Если понадобится общий «текущий пользователь» — вызвать `setCurrentUser(_:)` после входа.
- **Быстрая запись прямо в заголовке списка**: `body` необязателен, короткая заметка часто и есть
  один заголовок (`tests/test_notes.py: test_note_without_body`). Ради неё не стоит открывать форму.
- **Переключатель видимости виден только родителю** (`NotesViewModel.showsVisibilityFilter`):
  ребёнку скрытые заметки не приходят, выбор был бы пустым.
- **Плашка с замком** в строке, а не отдельная секция: порядок списка задан сервером
  (`updated_at desc`), группировка по видимости его бы сломала.
- **Порядок кэша совпадает с серверным** (`NoteRepository.sorted`) — иначе после правки
  заметка не поднималась бы наверх до следующего обновления.

## Прототип

`prototype/FamilyTasks - iOS.dc.html` — HTML-референс: вкладка «Заметки» на реальных данных
клиента, а также существующие экраны задач, семьи и профиля для контекста. Открывается в браузере.
Это **не код для переноса**: нативные экраны собраны на `Form`, `List` и компонентах из
`DesignSystem/`, а не на вёрстке из прототипа. Совпадать должны состав, тексты и поведение.

Оформление прототипа сделано в дизайн-системе Organic (кремовый фон, терракотовый акцент,
Caprasimo + Figtree). ~~В нативный клиент её переносить не нужно — там системные компоненты iOS.~~

**Отменено 14 сентября 2026:** систему в клиент перенесли, см. врезку в начале файла.
Компоненты при этом остались системными — перекрашены, но не заменены.

## Чего сознательно нет

Тегов, вложений, ссылок «задача ↔ заметка», архива, оффлайн-правок. Всё это требует полей
на бэкенде. Отдельный крупный пробел: у задач на сервере тоже есть `visibility`
(`schemas/task.py`, `routes/tasks.py`, включая правило «скрытую задачу нельзя назначить ребёнку»),
но в `TaskDTO`/`TaskDraft`/`TaskUpdateDTO` этого поля нет — значит все задачи создаются
как `family` и видны детям. Это следующий логичный шаг, в этот пакет он не входит.
