# HAProxy: домены и backend-сервисы

HAProxy выбирает сертификат по SNI, а backend — по HTTP-заголовку `Host`.
В конфигурации сертификаты автоматически загружаются из `/tmp/certs/`; отдельная
запись для каждого сертификата в `haproxy.cfg` не нужна.

## Добавление домена и сервиса

Предположим, новый домен — `blog.example.com`, Compose-сервис — `blog`,
внутренний порт приложения — `8080`.

1. Убедитесь, что DNS домена указывает на сервер, а сертификат включает этот домен.
2. Подключите `blog` к сети `haproxy`.
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

После успешной проверки выполните мягкую перезагрузку HAProxy:

```bash
docker compose exec -T haproxy \
  /bin/sh /usr/local/bin/haproxy-scripts/reload-certs.sh
```

Скрипт подготовит сертификаты и перезагрузит HAProxy вместе с конфигурацией.
