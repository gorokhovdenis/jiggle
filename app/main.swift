import Cocoa

// Menu bar приложение: иконки в доке нет (LSUIElement в Info.plist).
// Если места в строке меню не нашлось, переключаемся в док — тогда то же
// самое меню доступно по правому клику на иконке.

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {

    private var statusItem: NSStatusItem!
    private let jiggler = Jiggler()
    private let defaults = UserDefaults.standard

    // MARK: - Жизненный цикл

    func applicationDidFinishLaunching(_ notification: Notification) {
        loadSettings()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = icon()

        // Меню наполняется прямо перед показом (menuNeedsUpdate), а не хранится
        // собранным: иначе пришлось бы синхронизировать галочки руками и
        // пересобирать его под носом у открытого меню.
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        jiggler.onChange = { [weak self] in
            DispatchQueue.main.async { self?.refresh() }
        }

        refresh()
        requestAccessibilityIfNeeded()

        // Позиция окна status item становится окончательной не сразу.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.verifyStatusItemIsReachable()
        }
    }

    // MARK: - Разрешения

    /// Без Accessibility события мыши постятся вникуда: приложение выглядит
    /// работающим, а курсор стоит.
    ///
    /// Системный запрос здесь обязателен, а не для красоты: именно он
    /// регистрирует приложение в TCC и создаёт запись в списке Accessibility.
    /// Добавление той же записи руками через «+» его не заменяет — такая
    /// запись теряется при перезапуске приложения.
    ///
    /// Свой NSAlert тут был и оказался ловушкой: он объяснял пользователю, что
    /// делать, но ничего не регистрировал, и приложение не получало прав вовсе.
    /// Убирать надо было именно его, а не системный вызов.
    private func requestAccessibilityIfNeeded() {
        let prompt = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let trusted = AXIsProcessTrustedWithOptions([prompt: true] as CFDictionary)
        // Путь к бандлу в логе — не для красоты: разрешение выдаётся конкретному
        // бандлу, и когда копий несколько, «приложение запущено, а прав нет»
        // объясняется именно этим. Выяснять это со стороны было долго.
        Log.write("запуск: \(Bundle.main.bundlePath), AXIsProcessTrusted = \(trusted)")
    }

    /// Анкер com.apple.preference.security?Privacy_Accessibility — формат до
    /// Ventura; на новых macOS он открывает произвольную панель. Рабочий —
    /// через PrivacySecurity.extension, проверено на macOS 26.
    @objc private func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.settings"
                            + ".PrivacySecurity.extension?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }

    /// Иконка может оказаться за пределами экрана, оставаясь `isVisible = true`:
    /// чаще всего её туда уводит менеджер строки меню (Hidden Bar, Ice, Bartender),
    /// сворачивая в скрытую секцию; реже — нехватка места в самой строке.
    /// Кликнуть по ней в обоих случаях нельзя. Молча выглядеть работающим —
    /// худший вариант, поэтому говорим прямо и уходим в док как запасной путь.
    private func verifyStatusItemIsReachable(attempt: Int = 0) {
        // Окно у кнопки появляется не мгновенно. Раньше здесь стоял guard с
        // молчаливым return — и проверка просто не отрабатывала, приложение
        // оставалось невидимым без единого слова. Повторяем, потом сдаёмся.
        guard let window = statusItem.button?.window else {
            guard attempt < 5 else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.verifyStatusItemIsReachable(attempt: attempt + 1)
            }
            return
        }

        let onScreen = NSScreen.screens.contains { $0.frame.intersects(window.frame) }
        guard !onScreen else { return }

        NSApp.setActivationPolicy(.regular)   // появится иконка в доке
        updateDockBadge()

        // Объясняем один раз: при каждом запуске это было бы назойливо, а
        // иконка в доке дальше говорит сама за себя.
        guard !defaults.bool(forKey: "menuBarWarningShown") else { return }
        defaults.set(true, forKey: "menuBarWarningShown")

        let alert = NSAlert()
        alert.messageText = "Jiggle's menu bar icon is hidden"
        alert.informativeText = """
            The icon exists but sits off-screen, so you cannot click it.

            The usual cause is a menu bar manager — Hidden Bar, Ice or Bartender — \
            which puts new icons in its collapsed section. Expand it, then \
            Cmd-drag the Jiggle icon to the always-visible side of the separator.

            Less often the menu bar is simply out of room; freeing a slot in \
            System Settings → Control Center helps there.

            Either way Jiggle is in the Dock meanwhile: click the icon to start \
            and stop it, right-click for settings.
            """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    // MARK: - Меню

    /// Одно и то же меню и для строки меню, и для правого клика по доку.
    /// Пункты создаются заново при каждом показе, поэтому галочки всегда
    /// соответствуют текущему состоянию без ручной синхронизации.
    private func populate(_ menu: NSMenu) {
        menu.removeAllItems()

        let status = NSMenuItem(title: statusLine(), action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)
        menu.addItem(.separator())

        let toggle = NSMenuItem(title: jiggler.isRunning ? "Stop" : "Start",
                                action: #selector(toggleJiggler), keyEquivalent: "")
        toggle.target = self
        menu.addItem(toggle)
        menu.addItem(.separator())

        menu.addItem(submenu(title: "Interval",
                             options: [("5–10 sec", 5, 10), ("30–90 sec", 30, 90),
                                       ("1–3 min", 60, 180), ("3–8 min", 180, 480)],
                             selected: { [weak self] a, b in
                                 self?.jiggler.settings.minPause == a && self?.jiggler.settings.maxPause == b
                             },
                             action: #selector(setInterval(_:))))

        menu.addItem(submenu(title: "Movement",
                             options: [("Subtle (4 px)", 4, 0.15), ("Normal (150 px)", 150, 0.5),
                                       ("Wide (400 px)", 400, 0.9)],
                             selected: { [weak self] delta, _ in
                                 self?.jiggler.settings.delta == delta
                             },
                             action: #selector(setMovement(_:))))

        let smart = NSMenuItem(title: "Pause while I'm using the Mac",
                               action: #selector(toggleSmart), keyEquivalent: "")
        smart.target = self
        smart.state = jiggler.settings.smart ? .on : .off
        menu.addItem(smart)

        menu.addItem(.separator())

        let access = NSMenuItem(title: "Accessibility settings…",
                                action: #selector(openAccessibilitySettings), keyEquivalent: "")
        access.target = self
        menu.addItem(access)

        let log = NSMenuItem(title: "Open log", action: #selector(openLog), keyEquivalent: "")
        log.target = self
        menu.addItem(log)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Jiggle",
                                action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    @objc private func openLog() {
        NSWorkspace.shared.open(URL(fileURLWithPath: Log.path))
    }

    private func statusLine() -> String {
        // Заблокированное состояние важнее всего остального: раньше в этом
        // случае честно писалось «Running · N moves» при неподвижном курсоре.
        if jiggler.isBlocked { return "Cursor not moving — no Accessibility access" }
        guard jiggler.isRunning else { return "Stopped" }
        var text = "Running · \(jiggler.jiggleCount) moves"
        if let last = jiggler.lastJiggle {
            let f = DateFormatter()
            f.dateFormat = "HH:mm:ss"
            text += " · last \(f.string(from: last))"
        }
        return text
    }

    private func submenu(title: String,
                         options: [(String, Double, Double)],
                         selected: (Double, Double) -> Bool?,
                         action: Selector) -> NSMenuItem {
        let parent = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let sub = NSMenu()
        for (label, a, b) in options {
            let item = NSMenuItem(title: label, action: action, keyEquivalent: "")
            item.target = self
            item.representedObject = [a, b]
            item.state = (selected(a, b) ?? false) ? .on : .off
            sub.addItem(item)
        }
        parent.submenu = sub
        return parent
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        populate(menu)
    }

    /// Правый клик по иконке в доке — то же меню. Без него в док-режиме
    /// настройки были бы недоступны вообще.
    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let menu = NSMenu()
        populate(menu)
        return menu
    }

    /// Обычный клик по иконке в доке переключает джигглер.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        jiggler.toggle()
        return true
    }

    // MARK: - Состояние

    private func refresh() {
        statusItem.button?.image = icon()
        if NSApp.activationPolicy() == .regular { updateDockBadge() }
    }

    /// В док-режиме бейдж — единственная обратная связь о состоянии.
    private func updateDockBadge() {
        NSApp.dockTile.badgeLabel = jiggler.isBlocked ? "!" : (jiggler.isRunning ? "ON" : nil)
    }

    private func icon() -> NSImage? {
        let name: String
        if jiggler.isBlocked        { name = "exclamationmark.triangle" }
        else if jiggler.isRunning   { name = "cursorarrow.motionlines" }
        else                        { name = "cursorarrow" }

        let image = NSImage(systemSymbolName: name, accessibilityDescription: "Jiggle")
        image?.isTemplate = true
        return image
    }

    // MARK: - Действия

    @objc private func toggleJiggler() { jiggler.toggle() }

    @objc private func toggleSmart() {
        jiggler.settings.smart.toggle()
        saveSettings()
        refresh()
    }

    @objc private func setInterval(_ sender: NSMenuItem) {
        guard let pair = sender.representedObject as? [Double], pair.count == 2 else { return }
        jiggler.settings.minPause = pair[0]
        jiggler.settings.maxPause = pair[1]
        saveSettings()
        refresh()
    }

    @objc private func setMovement(_ sender: NSMenuItem) {
        guard let pair = sender.representedObject as? [Double], pair.count == 2 else { return }
        jiggler.settings.delta = pair[0]
        jiggler.settings.glideDuration = pair[1]
        saveSettings()
        refresh()
    }

    // MARK: - Настройки

    private func loadSettings() {
        defaults.register(defaults: [
            "minPause": 30.0, "maxPause": 90.0,
            "delta": 150.0, "glideDuration": 0.5, "smart": true,
        ])
        jiggler.settings.minPause = defaults.double(forKey: "minPause")
        jiggler.settings.maxPause = defaults.double(forKey: "maxPause")
        jiggler.settings.delta = defaults.double(forKey: "delta")
        jiggler.settings.glideDuration = defaults.double(forKey: "glideDuration")
        jiggler.settings.smart = defaults.bool(forKey: "smart")
    }

    private func saveSettings() {
        defaults.set(jiggler.settings.minPause, forKey: "minPause")
        defaults.set(jiggler.settings.maxPause, forKey: "maxPause")
        defaults.set(jiggler.settings.delta, forKey: "delta")
        defaults.set(jiggler.settings.glideDuration, forKey: "glideDuration")
        defaults.set(jiggler.settings.smart, forKey: "smart")
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
