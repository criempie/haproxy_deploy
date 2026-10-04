# HAProxy: домены и backend-сервисы

HAProxy выбирает сертификат по SNI, а backend — по HTTP-заголовку `Host`.
PEM-файлы экспортирует отдельный репозиторий `certbot_deploy` в `export/haproxy/`;
HAProxy подключает этот каталог только для чтения и загружает из него сертификаты
автоматически. Отдельная запись для каждого сертификата в `haproxy.cfg` не нужна.

## Подключение к Certbot

1. В `certbot_deploy` включите `hooks/deploy.d/export-pem.sh.example` как описано в
   README того репозитория и выпустите сертификат. HAProxy не запустится без хотя
   бы одного PEM-файла, поэтому сначала получите сертификат.
2. Скопируйте `.env.example` в `.env` и укажите абсолютный путь к каталогу
   `export/haproxy/` на хосте. `EXPORT_GID` должен совпадать с `EXPORT_GID` в
   `.env` репозитория Certbot:

   ```sh
   cp .env.example .env
   ```

3. Запустите HAProxy: `docker compose up -d`.
4. Чтобы HAProxy перечитывал новые PEM после успешного обновления, настройте
   необязательный `hooks/after-renew.sh` в репозитории Certbot. Пример содержимого
   (замените путь на каталог этого репозитория):

   ```sh
   #!/bin/sh
   set -eu
   cd /srv/haproxy
   docker compose exec -T haproxy \
     /bin/sh /usr/local/bin/haproxy-scripts/reload-certs.sh
   ```

   Сделайте hook исполняемым (`chmod +x hooks/after-renew.sh`). Он выполняется на
   хосте от имени пользователя, запустившего Certbot; для доступа к Docker обычно
   его запускают через cron от root. Если `docker compose exec` не может подключиться
   к HAProxy, hook завершится ошибкой — в частности, это возможно, если HAProxy
   ещё не запущен.

Certbot и HAProxy должны иметь доступ к экспортированным PEM по числовому GID.
`group_add` в Compose добавляет HAProxy группу `EXPORT_GID`; права на каталог и
файлы настраиваются в `certbot_deploy`. Каталог `letsencrypt/live/` HAProxy не
подключает и PEM самостоятельно не собирает.

## Добавление домена и сервиса

Предположим, новый домен — `blog.example.com`, Compose-сервис — `blog`,
внутренний порт приложения — `8080`.

1. Убедитесь, что DNS домена указывает на сервер, а сертификат включает этот домен.
2. Подключите `blog` к общей Docker-сети `haproxy`. Этот Compose-файл создаёт её;
   в Compose-файле приложения объявите её внешней:

   ```yaml
   services:
     blog:
       networks:
         - haproxy

   networks:
     haproxy:
       external: true
       name: haproxy
   ```

3. Добавьте правило в `frontend https`, перед `default_backend`:

   ```haproxy
   acl host_blog hdr(host) -i blog.example.com
   use_backend be_blog if host_blog
   ```

4. Добавьте backend:

   ```haproxy
   backend be_blog
       server blog blog:8080 resolvers docker init-addr none
   ```

`blog:8080` — имя Compose-сервиса и порт, на котором он слушает внутри контейнера.
Публиковать этот порт на хосте для связи с HAProxy не требуется.

Если один сервис обслуживает несколько доменов, перечислите их в одной ACL:

```haproxy
acl host_blog hdr(host) -i blog.example.com www.blog.example.com
use_backend be_blog if host_blog
```

Правила ACL должны находиться в `frontend https`, а backend — отдельно, на верхнем
уровне конфигурации.

### Параметры `server`

В примере:

- `blog` — произвольное имя сервера в HAProxy;
- `blog:8080` — Compose-имя сервиса и его внутренний порт;
- `resolvers docker` — разрешение имени через DNS Docker;
- `init-addr none` — позволяет HAProxy запуститься, если сервис ещё недоступен.

Проверка доступности (`check`) намеренно не включена: при её ошибке HAProxy
перестаёт отправлять запросы на сервер. Добавляйте её, если такое автоматическое
поведение нужно, например, при наличии нескольких серверов.

### SNI вместо `Host`

Для маршрутизации по SNI используйте `ssl_fc_sni` во `frontend https`:

```haproxy
acl sni_blog ssl_fc_sni -i blog.example.com
use_backend be_blog if sni_blog
```

SNI доступен потому, что HAProxy завершает TLS на своём `bind :443 ssl`.
Маршрутизация по `Host` остаётся обычным вариантом для HTTP reverse proxy; SNI
уже используется HAProxy для выбора сертификата.

## WebSocket

Для долгоживущих WebSocket-соединений при необходимости задайте в соответствующем
backend таймаут бездействия:

```haproxy
backend be_blog
    timeout tunnel 1h
    server blog blog:8080 resolvers docker init-addr none
```

Это не ограничение общей продолжительности соединения: HAProxy закроет туннель,
если в нём не будет трафика в течение часа. Подберите значение с учётом
keepalive приложения.

## Применение изменений

Проверьте синтаксис:

```bash
docker compose exec haproxy \
  haproxy -c -f /usr/local/etc/haproxy/haproxy.cfg
```

После обновления PEM выполните мягкую перезагрузку HAProxy (эта команда также
перечитывает конфигурацию):

```bash
docker compose exec -T haproxy \
  /bin/sh /usr/local/bin/haproxy-scripts/reload-certs.sh
```

Обычно эту команду вызывает хостовый `hooks/after-renew.sh` из репозитория
Certbot. Сам HAProxy PEM-файлы не генерирует.
