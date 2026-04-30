# OurCLIProxy — Railway-обёртка над CLIProxyAPI

Тонкий Docker-образ поверх `eceasy/cli-proxy-api:latest` ([CLIProxyAPI](https://github.com/router-for-me/CLIProxyAPI)) для деплоя на Railway. Конфиг генерируется при старте из env-переменных Railway, OAuth-токены провайдеров живут на persistent volume.

## Что внутри

- `Dockerfile` — `FROM eceasy/cli-proxy-api:latest` + кастомный ENTRYPOINT.
- `entrypoint.sh` — генерирует `/CLIProxyAPI/config.yaml` из `MGMT_SECRET`, `API_KEYS`, `PORT`, потом запускает бинарь.
- `.gitignore` — исключает локальные секреты и IDE-файлы.

Ничего больше — CLIProxyAPI сам тащит образ из Docker Hub.

## Подготовка (5 минут)

### 1. Сгенерируй два секрета

На своей машине:

```bash
openssl rand -hex 32   # это MGMT_SECRET (пароль для Web UI)
openssl rand -hex 32   # это тело API-ключа — потом припиши префикс sk-
```

Сохрани оба значения — пригодятся на шаге 3.

### 2. Создай сервис на Railway

В нужном Railway-проекте:

- `+ New → GitHub Repo` → выбери этот репозиторий (`OurCLIProxy`).
  Если репозиторий приватный и не виден — попроси владельца GitHub-аккаунта добавить тебя коллаборатором, либо сделай форк к себе.

Railway автоматически найдёт Dockerfile и начнёт сборку. Сразу после создания сервиса — пока он билдится — настрой остальное:

### 3. Variables

Открой **Settings → Variables** и добавь:

| Переменная     | Значение                                       |
| -------------- | ---------------------------------------------- |
| `MGMT_SECRET`  | первый секрет из шага 1                        |
| `API_KEYS`     | `sk-<второй секрет>` (несколько — через запятую) |

`PORT` Railway инжектит сам — задавать вручную не нужно, entrypoint его подхватит.

### 4. Volume

**Settings → Volumes → New Volume**:

- Mount path: `/root/.cli-proxy-api`
- Size: 1 GB

Это критично: без volume OAuth-токены провайдеров умрут при первом редеплое.

### 5. Networking

**Settings → Networking → Public Networking**:

- Generate Domain
- Target Port: `8317`

### 6. Подожди деплой

В логах Railway должна появиться строка `CLIProxyAPI started on port 8317` (или похожая). Если есть ошибка про парсинг yaml — проверь, что `MGMT_SECRET` и `API_KEYS` заданы.

## OAuth-логин провайдеров

1. Открой `https://<твой-домен>.up.railway.app/management.html`.
2. Введи `MGMT_SECRET` → Connect.
3. В разделе провайдеров: Add OAuth → выбери Claude / Gemini / Codex / Antigravity → **обязательно с флагом WebUI mode** (это включает параметр `?is_webui=true`).
4. Пройди OAuth в новой вкладке. После успеха — токен сохранится в `/root/.cli-proxy-api/` на volume.

### Почему WebUI mode критичен

OAuth-провайдеры зашили в свои redirect_uri конкретные локальные порты (Claude 54545, Gemini 8085, Codex 1455, Antigravity 51121). На Railway пробросить столько публичных портов нельзя. WebUI mode запускает временный callback-форвардер **внутри контейнера** на 51121 и финальный редирект отправляет через основной порт 8317 — тот, который смотрит наружу. Поэтому одного публичного домена достаточно.

iFlow требует callback на 11451 — там WebUI mode работает не так гладко, при необходимости — отдельная настройка.

## Проверка работы

```bash
curl https://<твой-домен>.up.railway.app/v1/chat/completions \
  -H "Authorization: Bearer sk-<твой_API_KEY>" \
  -H "Content-Type: application/json" \
  -d '{"model":"claude-sonnet-4-5","messages":[{"role":"user","content":"ping"}]}'
```

Должен прийти ответ от Claude.

Поддерживаемые модели зависят от того, какие OAuth-провайдеры подключил: `claude-sonnet-4-5`, `claude-opus-4-7`, `gemini-2.5-pro`, `gpt-5`, и т.д.

## Persistence-тест

В Railway сделай **Redeploy** через UI. После рестарта тот же `curl` должен работать без повторного OAuth — это значит, volume сработал.

## Риски и нюансы

- **Anthropic ToS**: подключение Claude-аккаунта через OAuth-прокси нарушает ToS Claude Code и Claude Pro/Max. С начала 2026-го Anthropic активнее детектит такие схемы. Не привязывай ценный/основной аккаунт.
- **Несколько провайдеров одного типа**: можно добавить несколько Claude / Gemini / Codex OAuth-сессий — CLIProxyAPI ротирует их при исчерпании квоты (`quota-exceeded.switch-project: true` в конфиге).
- **Тег `:latest`**: Railway кэширует слои, обновления апстрима могут не подтягиваться автоматом. Если хочется детерминизма — зафиксировать конкретный тег в `Dockerfile` (например `eceasy/cli-proxy-api:v6.2.38`).
- **config.yaml регенерируется при каждом старте**: если правишь конфиг через Web UI — изменения не сохранятся между деплоями. Постоянное место правок — `entrypoint.sh` (или env-переменные).

## Использование из своего кода

```python
from openai import OpenAI

client = OpenAI(
    base_url="https://<твой-домен>.up.railway.app/v1",
    api_key="sk-<твой_API_KEY>",
)

resp = client.chat.completions.create(
    model="claude-sonnet-4-5",
    messages=[{"role": "user", "content": "Привет"}],
)
print(resp.choices[0].message.content)
```

Если потребитель — другой сервис в том же Railway-проекте, можно ходить через private networking: `http://<service-name>.railway.internal:8317/v1` (тогда public domain вообще не нужен, только Web UI на нём — но Web UI можно открыть через Railway port-forward).
