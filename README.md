# Hunter Forkop — OpenWrt 24.10 и 25.12

Установщик Forkop с расширенным sing-box и патчем XHTTP. **Только ARM64 / aarch64.** Выберите команду для своей версии OpenWrt. Это установка пакетов, не перепрошивка роутера.

| Версия OpenWrt | Пакеты | Подробная инструкция |
|---|---|---|
| **25.12.x** | APK | **[Установка на OpenWrt 25](README-25.md)** |
| **24.10.x** | IPK / opkg | **[Установка на OpenWrt 24](README-24.md)** |

## Установка на OpenWrt 25.12

Выполните по SSH от root:

```sh
wget -O /tmp/hunter-forkop25.sh https://raw.githubusercontent.com/gerser777/Hunter-Forkop/hunter-forkop-25-v0.1.0-rc1/install-25.sh && sh /tmp/hunter-forkop25.sh
```

Требуется минимум 80 MB свободной flash на чистой системе или 35 MB при установленном Forkop, 130 MB доступной RAM и работающий интернет. Проверено на Cudy WBR3000UAX v1 с OpenWrt 25.12.5.

[Полная инструкция, Auto и откат для версии 25](README-25.md) · [Выпуск 25](https://github.com/gerser777/Hunter-Forkop/releases/tag/hunter-forkop-25-v0.1.0-rc1)

## Установка на OpenWrt 24.10

Выполните по SSH от root:

```sh
wget -O /tmp/hunter-forkop.sh https://raw.githubusercontent.com/gerser777/Hunter-Forkop/hunter-forkop-24-v0.1.0-rc2/install.sh && sh /tmp/hunter-forkop.sh
```

Требуется минимум 35 MB свободной flash, 130 MB доступной RAM и работающий интернет. Проверено на Cudy WBR3000UAX v1 с OpenWrt 24.10.5.

[Полная инструкция, Auto и откат для версии 24](README-24.md) · [Выпуск 24](https://github.com/gerser777/Hunter-Forkop/releases/tag/hunter-forkop-24-v0.1.0-rc2)

## После установки

На новом роутере добавьте **свою подписку** в LuCI → Forkop, настройте маршрутизацию и группу Auto по инструкции вашей версии. Подписки, UUID и ключи в поставку не входят. Существующие настройки сохраняются; перед изменением создаётся резервная копия и печатается команда отката.

Оба выпуска предварительные. Для версии 25 проверены поэтапная чистая установка компонентов, перезагрузка и LAN; готовый установщик проверен поверх работающего Forkop. Чистая установка именно готовой командой отдельно ещё не проверена. Другие архитектуры и модели не заявлены как проверенные.

Исходники и лицензии: [Forkop 1.0.5](https://github.com/ushan0v/forkop/releases/tag/1.0.5), [sing-box-extended](https://github.com/shtorm-7/sing-box-extended/releases/tag/v1.14.1-extended-2.7.2), [GPL](LICENSE.Forkop), [патч XHTTP](forkop-xhttp-preserve.patch).
