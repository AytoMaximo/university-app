# Интерактивная карта РТУ МИРЭА

Этот fork поддерживает standalone web-версию интерактивной карты РТУ МИРЭА.

Оригинальный репозиторий мобильного приложения: [0niel/university-app](https://github.com/0niel/university-app).

## Что есть в этой версии

- веб-приложение с картой кампусов и этажей;
- локальный поиск аудиторий без backend/API-запросов;
- фокусировка карты на выбранной аудитории;
- подсветка выбранной аудитории;
- построение маршрутов между точками на карте;
- отдельная production-сборка только для карты, без основного shell мобильного приложения.

## Публичная версия

Основной адрес веб-карты: [map.aytomaximo.ru](https://map.aytomaximo.ru/).

Также проект может быть опубликован через Vercel: [university-app-taupe.vercel.app](https://university-app-taupe.vercel.app/).

## Сборка

Standalone web-приложение запускается из `lib/main/main_map_web.dart`.

Production-сборка:

```powershell
D:\Flutter\bin\flutter.bat build web --release --target lib\main\main_map_web.dart
```

Для slim-сборки используется `tools/pubspec_map_web.yaml`; на Vercel это делает `tools/vercel_build_flutter_web.sh`.

## Деплой

Push в `master` запускает GitHub Actions workflow `Deploy map to MSK`, который:

1. собирает standalone web-карту;
2. архивирует `build/web`;
3. загружает release на сервер MSK;
4. переключает `/srv/map.aytomaximo.ru/current`;
5. проверяет доступность `https://map.aytomaximo.ru/version.json`.

Workflow `Sync upstream` периодически проверяет обновления в `0niel/university-app:master` и готовит pull request с изменениями upstream.
