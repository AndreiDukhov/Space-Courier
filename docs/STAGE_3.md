# Этап 3: хаб и расписания

Хаб — отдельное здание. В его карточках показываются только локации `area: hub`; корабельные помещения относятся к другой зоне. Кабинет и терминал описаны в [отчёте этапа 4](STAGE_4.md).

## Что сделано

- Пять квадратных карточек локаций со скруглёнными краями сверху слева.
- Картинка пользователя подключена как фон и миниатюра главного зала `hub_kitchen`.
- Под карточками показаны значки героинь, находящихся в соответствующей локации.
- Клик по карточке меняет локацию игрока. Переходы стоят 0 слотов; `wait` стоит 1 слот.
- Расписания выбирают место по весам при смене слота. Выбранное место сохраняется до следующей смены времени.
- Условия `at`, `time`, `others_absent` и доступ к локациям проверяет `ConditionEvaluator`.
- Из зала можно открыть тестовый диалог с присутствующим пилотом. После выбора интерфейс возвращается в хаб.
- Сейв содержит согласованное поле `location` игрока и `loc` каждой героини. Загрузка восстанавливает места без повторного выбора по весам.

## Тестовое расписание

| Слот | Пилот | Медик |
| --- | --- | --- |
| morning | hub_kitchen | hub_kitchen |
| day | ship_bridge при aboard=true, иначе hub_tech | hub_tech |
| evening | hub_kitchen с весом 2, hub_tech с весом 1 | hub_showers |
| night | ship_bridge | hub_corridor |

`hub_showers` доступна игроку вечером и ночью. Ограничение задано в JSON.

## Созданы

- `scripts/time_slots.gd`
- `scripts/schedule_manager.gd`
- `scripts/location_validator.gd`
- `scripts/hub_service.gd`
- `scripts/location_art.gd`
- `scripts/hub_widgets.gd`
- `scripts/hub.gd`
- `data/locations/hub.json`
- `data/locations/schedules.json`
- `data/heroines/medic.json`
- `art/backgrounds/hub_kitchen.png`
- `tests/stage_three.gd`
- `tests/stage_three.tscn`

Godot также создаёт служебные файлы `.uid` и `.import` для новых ресурсов.

## Обновлены

- `project.godot`
- `scenes/hub.tscn`
- `scripts/main.gd`
- `scripts/clock.gd`
- `scripts/game_state.gd`
- `scripts/condition_evaluator.gd`
- `scripts/effect_applier.gd`
- `scripts/data_loader.gd`
- `scripts/data_validator.gd`
- `scripts/dialogue_runner.gd`
- `scripts/dialogue.gd`
- `data/heroines/pilot.json`
- `data/locations/ship.json`
- `data/scenes/pilot_test_01.json`
- `data/scenes/pilot_test_02.json`
- `data/scenes/pilot_test_03.json`
- `tests/stage_one.gd`

## Как проверить руками

1. Открыть `project.godot` в Godot и нажать F5. Появится главный зал; значки M и P будут под его карточкой.
2. Кликнуть по карточке мастерской. Фон сменится на заглушку, время останется morning. Вернуться в зал.
3. Нажать `wait`. Наступит day: M переместится под карточку мастерской. Пилот по тестовому расписанию уйдёт на корабль и исчезнет из значков здания.
4. Перейти по карточке мастерской к медику. Её значок появится в панели текущей локации.
5. Нажать `wait` до evening. Карточка душевых станет доступной; выбранное вечернее место пилота останется фиксированным при переходах между комнатами.
6. Перезапустить F5. Нажать кнопку пилота внизу слева: откроется компактный диалог. Выбрать тестовую реплику — время и значки обновятся, диалог закроется.
7. Для автоматических проверок открыть `tests/stage_three.tscn` и нажать F6. Ожидается `Stage 3 checks: 111 passed, 0 failed`.

## Проверено

Godot 4.7.2, Compatibility / OpenGL:

- 48 проверок каркаса, включая создание, загрузку и удаление тестового `user://save.json`.
- 79 проверок диалогов.
- 117 проверок хаба с отрисовкой, включая три снимка экрана.
- Полный оконный запуск проекта: код выхода 0, ошибок в консоли нет.

Тестовый процесс использует отдельный `APPDATA` внутри `.godot/verification-user-data`. Там размещаются его `user://` и shader cache.

Журналы: `.godot/stage-one-isolated.log`, `.godot/stage-two-isolated.log`, `.godot/stage-three-isolated-render.log`, `.godot/stage-four-run.log`.

Снимки: `.godot/stage-three-morning.png`, `.godot/stage-three-day.png`, `.godot/stage-three-dialogue.png`.

## Ограничения прототипа

- Остальные фоны и портреты героинь пока заменены цветными заглушками и буквенными значками.
- Дневной и ночной варианты главного зала используют одну исходную картинку; ночью применяется затемнение.
- Сейвы прежнего формата без `location` и `loc` отклоняются. Автоматической миграции пока нет.
