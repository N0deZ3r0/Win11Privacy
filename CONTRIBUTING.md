# Contributing

**English** · [Русский](#участие-в-разработке)

Thanks for wanting to help. Win11Privacy is a Windows privacy tool that disables Microsoft telemetry, and it is maintained
by one person — so a well-described issue is worth as much as a pull request.

## Reporting a bug

Open a [bug report](https://github.com/N0deZ3r0/Win11Privacy/issues/new?template=bug_report.yml).
The form asks for the version, environment and steps to reproduce — please fill
those in, because "it does not work" cannot be acted on.

Found a **security** problem? Do not open a public issue —
[report it privately](https://github.com/N0deZ3r0/Win11Privacy/security/advisories/new).

## Running it locally

1. Clone the repository.
2. Run `build.cmd` — it produces `Win11Privacy.exe`.
3. Run the executable **as administrator**; most settings need it.

## Checks before you push

```cmd
check-engine.cmd    :: validate the PowerShell engine
build.cmd           :: build Win11Privacy.exe
```

CI builds on `windows-latest` for every push and pull request.

## Pull requests

- **One change per pull request.** A PR that fixes a bug *and* renames files is
  hard to review and hard to revert.
- **Explain the why, not only the what.** The diff already shows what changed.
- **Match the surrounding code.** Same naming, same indentation, same comment
  density as the file you are editing — do not reformat untouched lines.
- **Say how you tested it.** Even "loaded unpacked in Chrome 141 and clicked
  through the popup" is useful.

Small fixes — typos, dead links, a clearer sentence — do not need an issue first.
Just open the pull request.

## Language

Issues and pull requests in **English or Russian** are equally welcome.

---

# Участие в разработке

[English](#contributing) · **Русский**

Спасибо, что хотите помочь. Проект ведёт один человек, поэтому подробно
описанная задача ценится не меньше, чем пул-реквест.

## Сообщить об ошибке

Откройте [баг-репорт](https://github.com/N0deZ3r0/Win11Privacy/issues/new?template=bug_report.yml).
Форма просит версию, окружение и шаги воспроизведения — заполните их,
потому что по «не работает» сделать ничего нельзя.

Нашли **уязвимость**? Не создавайте публичную задачу —
[сообщите приватно](https://github.com/N0deZ3r0/Win11Privacy/security/advisories/new).

## Запуск у себя

1. Склонируйте репозиторий.
2. Запустите `build.cmd` — получится `Win11Privacy.exe`.
3. Запускайте программу **от имени администратора** — без этого большая часть настроек недоступна.

## Проверки перед отправкой

```cmd
check-engine.cmd    :: проверить движок PowerShell
build.cmd           :: собрать Win11Privacy.exe
```

CI собирает проект на `windows-latest` при каждом push и pull request.

## Пул-реквесты

- **Одно изменение — один пул-реквест.** PR, который чинит баг *и* переименовывает
  файлы, тяжело ревьюить и тяжело откатывать.
- **Объясняйте зачем, а не что.** Что изменилось, видно из диффа.
- **Держитесь стиля вокруг.** Те же имена, отступы и плотность комментариев, что
  в файле, который правите; не переформатируйте нетронутые строки.
- **Напишите, как проверяли.** Даже «загрузил распакованным в Chrome 141 и
  прокликал попап» — полезно.

Мелкие правки — опечатки, битые ссылки, более понятная формулировка — можно
слать пул-реквестом сразу, без задачи.

## Язык

Задачи и пул-реквесты на **русском или английском** одинаково приветствуются.
