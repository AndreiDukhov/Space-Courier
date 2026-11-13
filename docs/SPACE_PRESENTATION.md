# Интерфейс карты, космические фоны и пиратский перехват

Выполнено 2026-11-07. Поле `system.background` согласовано в чате по правилу №7.

## Что сделано

- Подсказки полёта находятся в одной строке, включая указание курса, следование за курсором, действия корабля, паузу и карту.
- Справа сверху первая строка содержит день, топливо и корпус. Кредиты расположены ниже и выровнены по правому краю.
- Созданы три растровых космических фона со звёздами и туманностями. Варианты распределены между 12 системами, по четыре системы на вариант. Изображение назначается в `data/galaxy/systems.json` через `background`.
- Фон текущей системы используется и в полёте, и в бою. Он расположен под сеткой и 3D-моделями. Боевые клетки имеют прозрачность 50%, чтобы изображение читалось сквозь них.
- При смене системы и загрузке обновляется фон. DataLoader проверяет существование изображения в проекте и поддерживаемое расширение.
- Пират, преследующий игрока, автоматически открывает встречу при сближении до 48 единиц. Окно предлагает бой или откуп, а доступность оплаты зависит от денег. Движение игрока и NPC останавливается на время выбора.
- После откупа конкретный пират прекращает преследование и получает задержку агрессии. Встреча сохраняется вместе с существующим `flight.encounter`.

## Файлы

Созданы

- `art/backgrounds/space_blue.png` и метаданные импорта.
- `art/backgrounds/space_violet.png` и метаданные импорта.
- `art/backgrounds/space_amber.png` и метаданные импорта.
- `scripts/space_backdrop.gd` с uid скрипта.
- `tests/space_presentation.gd`, uid скрипта и `tests/space_presentation.tscn`.
- `docs/SPACE_PRESENTATION.md` с этим отчётом и промптами.

Изменены

- `scenes/system_flight.tscn`, `scripts/system_flight.gd`, `data/ui/flight.json` для строк интерфейса и фонового слоя.
- `scripts/combat.gd` и `scripts/combat_board.gd` для фонового слоя и прозрачности сетки.
- `data/galaxy/systems.json` и `scripts/space_content_validator.gd` для назначения и проверки изображений.
- `scripts/condition_evaluator.gd`, `scripts/effect_applier.gd` для автоматического перехвата.
- `tests/space_activity.gd`, `tests/pirates_and_boost.gd` и `tests/stage_seven.gd` для обновлённого поведения пиратов и перехода в бой после перехвата.
- `docs/DESIGN_NOTES.md` с согласованным расширением данных и механикой перехвата.

## Как проверить руками

1. Запустить F5 и вылететь через компьютер мастерской. Проверить одну строку подсказок снизу и расположение ресурсов справа сверху. Повторить при размере окна 900×600.
2. Сравнить Солнечную, Альфу и Бету. У них соответственно синий, фиолетовый и янтарный фоны под сеткой.
3. Дать пирату начать преследование и остановиться, чтобы он догнал корабль. При сближении должно автоматически открыться окно встречи с боем и откупом.
4. Выбрать бой и проверить тот же фон под боевой сеткой. Проверить движение камеры, выбор клетки и наведение на оружие.
5. В другом перехвате откупиться за 200 кредитов. Проверить завершение встречи и задержку нового преследования этим кораблём. При нехватке денег кнопка оплаты недоступна, выбор боя доступен.
6. Сохранить игру во время пиратской встречи и загрузить. Проверить сохранение встречи, текущей системы и соответствующего фона.

## Проверки

Целевые проверки пройдены в Godot 4.7.2 Compatibility при 1280×800 и 900×600. Для каждого из трёх вариантов проверены полёт и бой, фактическое отображение изображения под 3D-слоем, прозрачность сетки, управление картой, размещение строк, смена системы, загрузка и валидация ошибочных путей.

Автоматический перехват, приостановка симуляции, откуп и защита от немедленного повторения проверены для всех 36 пиратов. Проверены окно без предварительного клика, недостаток денег, сохранение встречи и бой против перехватившего корабля. Снимки интерфейса просмотрены визуально. Для сохранений использованы изолированные тестовые каталоги внутри проекта.

Успешно пройден 21 набор проверок проекта. Импорт редактора и запуск основной сцены прошли без ошибок консоли.

## Изображения и промпты

Изображения созданы встроенным инструментом ImageGen. Итоговые файлы скопированы в проект.

- `D:/space-courier/art/backgrounds/space_blue.png`
- `D:/space-courier/art/backgrounds/space_violet.png`
- `D:/space-courier/art/backgrounds/space_amber.png`

Промпты приведены ниже в порядке этих файлов.

### Blue

```text
Use case: stylized-concept. Asset type: wide 16:9 background texture for a top-down 3D space strategy game, placed behind a readable tactical grid. Create a cinematic deep-space starfield with very faint cool blue nebula wisps and scattered tiny stars. Broad quiet dark negative space across the whole frame, subtle depth and soft gaseous details, restrained low brightness for gameplay readability. No planets, ships, UI, grid, horizon, text, borders or logos. Full-bleed landscape image, dark navy and black with cool blue accents.
```

### Violet

```text
Use case: stylized-concept. Asset type: wide 16:9 background texture for a top-down 3D space strategy game, placed behind a readable tactical grid. Create a cinematic deep-space starfield with a faint violet and burgundy nebula drifting diagonally, small distant stars and delicate clouds. Broad quiet dark negative space across the whole frame, restrained low brightness, soft subtle detail for gameplay readability. No planets, ships, UI, grid, horizon, text, borders or logos. Full-bleed landscape image with a dark near-black field and restrained violet nebula accents.
```

### Amber

```text
Use case: stylized-concept. Asset type: wide 16:9 background texture for a top-down 3D space strategy game, placed behind a readable tactical grid. Create a cinematic deep-space starfield with sparse tiny stars and a faint warm amber interstellar dust cloud, diffuse smoky filaments against vast deep black space. Broad quiet dark negative space across the whole frame, restrained low brightness, subtle depth for gameplay readability. No planets, ships, UI, grid, horizon, text, borders or logos. Full-bleed landscape image with charcoal black and subdued warm amber accents.
```

