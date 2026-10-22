# Конфигурация виртуального сервера devops-vm

## 1. Исходный образ

- ОС: Ubuntu Server 24.04.5 LTS.
- Гипервизор: Oracle VM VirtualBox.
- Имя виртуальной машины и узла: `devops-vm`.
- Полное имя узла: `devops-vm.devops.local`.
- Базовый снимок: `01-clean-install`.

## 2. Сетевая конфигурация

- Адаптер 1: NAT, адрес ВМ `10.0.2.15/24`.
- Адаптер 2: Host-only, адрес ВМ `192.168.56.101/24`.
- Проброс NAT: `127.0.0.1:2222` на гостевой порт `2222/tcp`.
- На хостовой системе имя `devops.local` сопоставлено с `192.168.56.101` через файл `hosts`.

## 3. Учётные записи

- `student` — первоначальная учётная запись, созданная при установке.
- `devops` — рабочая учётная запись для администрирования по SSH; входит в группу `sudo`.
- Прямой вход под `root` запрещён.

## 4. Аутентификация по ключу

- Тип ключа: Ed25519.
- Открытый ключ установлен в `/home/devops/.ssh/authorized_keys`.
- Права: `700` для каталога `.ssh`, `600` для `authorized_keys`.
- На хосте используется профиль `Host devops` в `~/.ssh/config`.
- Контрольный снимок после настройки ключей: `02-keys-configured`.

## 5. Служба SSH

- Порт: `2222/tcp`.
- `PermitRootLogin no`.
- `PasswordAuthentication no`.
- `PubkeyAuthentication yes`.
- `PermitEmptyPasswords no`.
- `MaxAuthTries 3`, `LoginGraceTime 30`.
- Разрешённый пользователь: `AllowUsers devops`.
- `X11Forwarding no`.
- `ClientAliveInterval 300`, `ClientAliveCountMax 2`.
- Служба `ssh.service` включена; активация через `ssh.socket` отключена.
- Контрольный снимок: `03-ssh-hardened`.

## 6. Межсетевой экран

- UFW включён и автоматически запускается при загрузке.
- Политики по умолчанию: `deny incoming`, `allow outgoing`.
- `2222/tcp` — `LIMIT` для SSH.
- `80/tcp` — `ALLOW` для HTTP.
- `443/tcp` — `ALLOW` для HTTPS.
- Журналирование включено на уровне `medium`.
- Попытка соединения с закрытым портом `8080/tcp` фиксируется как `UFW BLOCK`.

## 7. SSH-туннель

Тестовый HTTP-сервис, привязанный к `127.0.0.1:8080` внутри ВМ, недоступен напрямую через Host-only сеть. Доступ с хоста проверен через локальный туннель:

```bash
ssh -L 9090:127.0.0.1:8080 -N devops
```

После создания туннеля ресурс доступен по адресу `http://127.0.0.1:9090`.

## 8. Веб-сервер

- Установлен пакет `nginx` из репозитория Ubuntu.
- Конфигурация ресурса: `/etc/nginx/sites-available/devops-site`.
- Ресурс активирован ссылкой `/etc/nginx/sites-enabled/devops-site`; стандартный ресурс отключён.
- HTTP на порту `80` перенаправляется кодом `301` на HTTPS.
- HTTPS обслуживается на порту `443` с протоколами TLS 1.2 и TLS 1.3.
- Каталог ресурса: `/var/www/devops-site`, владелец `devops:devops`.
- Права каталогов ресурса: `755`; права файлов: `644`.
- Сертификат: `/etc/ssl/certs/devops.crt`, владелец `root:root`, права `644`.
- Закрытый ключ: `/etc/ssl/private/devops.key`, владелец `root:root`, права `600`.
- Сертификат выпущен на 365 дней для `devops.local` с SAN `DNS:devops.local`:

```bash
sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout /etc/ssl/private/devops.key \
  -out /etc/ssl/certs/devops.crt \
  -subj "/CN=devops.local" \
  -addext "subjectAltName=DNS:devops.local"
```

- Содержимое доставляется сценарием `scripts/deploy.sh` через `rsync` с правами `D755,F644`.
- Контрольный снимок после настройки HTTPS: `04-nginx-https`.

## 9. Контейнеризация

- Docker Engine установлен из официального APT-репозитория Docker для Ubuntu; версия Engine: `29.9.2`, Docker Compose: `v5.6.1`.
- Пользователь `devops` входит в группы `sudo` и `docker`. Членство в группе `docker` фактически предоставляет административные возможности и разрешено только пользователю с правом `sudo`.
- Проект приложения расположен на сервере в `/home/devops/app` и доставляется с хоста командой `rsync` с обязательным исключением `--exclude=.env`.
- Секреты хранятся только на сервере в `/home/devops/app/.env`; владелец `devops:devops`, права `600`. В репозитории находится только шаблон `app/.env.example`.
- Compose запускает сервисы `app` и `db` в изолированной сети `app_backend`. Приложение находит PostgreSQL по DNS-имени сервиса `db`.
- Порт приложения опубликован только как `127.0.0.1:5000`; порт PostgreSQL `5432` на хосте не публикуется.
- Данные PostgreSQL сохраняются в именованном томе `app_db_data`. Команда `docker compose down` сохраняет том, а `docker compose down -v` удаляет его вместе с данными.
- Приложение работает в контейнере от непривилегированного пользователя `app`.
- В HTTPS-блоке `/etc/nginx/sites-available/devops-site` настроен обратный прокси:

```nginx
location /app/ {
    proxy_pass http://127.0.0.1:5000/;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
}
```

- Внешний доступ выполняется только через `https://devops.local/app/`; статический ресурс продолжает обслуживаться по `https://devops.local/`.
- Контрольный снимок после настройки Compose: `05-docker-compose`.

## 10. Диагностика и восстановление

1. Проверить синтаксис: `sudo sshd -t`.
2. Проверить эффективные параметры: `sudo sshd -T`.
3. Проверить прослушиваемый порт: `sudo ss -tlnp | grep sshd`.
4. Проверить службу: `sudo systemctl status ssh`.
5. Проверить firewall: `sudo ufw status verbose`.
6. Проверить Nginx: `sudo nginx -t && systemctl is-active nginx`.
7. Просмотреть журналы: `sudo journalctl -u ssh --no-pager`, `/var/log/nginx/devops-site.access.log` и `/var/log/nginx/devops-site.error.log`.
8. При потере доступа открыть консоль VirtualBox, исправить конфигурацию или восстановить снимок `03-ssh-hardened` либо `04-nginx-https`.
9. Проверить контейнеры: `cd ~/app && docker compose ps`.
10. Проверить журнал приложения: `cd ~/app && docker compose logs app`.
11. Проверить обратный прокси: `curl --cacert ~/devops.crt https://devops.local/app/health`.
12. При ответе `502 Bad Gateway` проверить контейнер приложения, сокет `127.0.0.1:5000` и `/var/log/nginx/devops-site.error.log`.

Автоматическая проверка основных параметров выполняется скриптом `scripts/audit.sh`.
