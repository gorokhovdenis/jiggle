import Cocoa

/// Ядро: двигает курсор по случайному расписанию и возвращает его на место.
///
/// События постятся с источником `.hidSystemState` — система засчитывает их
/// как ввод живого человека и сбрасывает HIDIdleTime, тот самый счётчик,
/// по которому определяется простой.
final class Jiggler {

    struct Settings {
        var minPause: Double = 30      // сек
        var maxPause: Double = 90      // сек
        var delta: Double = 150        // px
        var glideDuration: Double = 0.5 // сек на один проход
        var smart: Bool = true         // не мешать, когда за маком работают
    }

    var settings = Settings()
    private(set) var jiggleCount = 0
    private(set) var lastJiggle: Date?

    /// События уходят, курсор стоит — почти всегда нет Accessibility.
    private(set) var isBlocked = false

    /// Вызывается в главном потоке после каждого шевеления и при старте/стопе.
    var onChange: (() -> Void)?

    private let source = CGEventSource(stateID: .hidSystemState)
    private let queue = DispatchQueue(label: "jiggle.worker", qos: .utility)
    private var workItem: DispatchWorkItem?
    private var lastLeftAt: CGPoint = .zero

    var isRunning: Bool { workItem != nil }

    // MARK: - Управление

    func start() {
        guard !isRunning else { return }
        lastLeftAt = Self.cursor()
        isBlocked = false          // проверится заново на первом же ходе
        scheduleNext()
        Log.write("старт: пауза \(Int(settings.minPause))–\(Int(settings.maxPause)) с, "
                  + "ход \(Int(settings.delta)) px, "
                  + "пропуск при работе за маком: \(settings.smart ? "да" : "нет")")
        onChange?()
    }

    func stop() {
        workItem?.cancel()
        workItem = nil
        Log.write("стоп, шевелений за сеанс: \(jiggleCount)")
        onChange?()
    }

    func toggle() { isRunning ? stop() : start() }

    // MARK: - Цикл

    private func scheduleNext() {
        let pause = Double.random(in: settings.minPause...max(settings.minPause, settings.maxPause))
        let item = DispatchWorkItem { [weak self] in
            guard let self, !(self.workItem?.isCancelled ?? true) else { return }
            self.tick()
            self.scheduleNext()
        }
        workItem = item
        queue.asyncAfter(deadline: .now() + pause, execute: item)
    }

    private func tick() {
        let now = Self.cursor()

        if settings.smart && userIsPresent(cursorNow: now) {
            lastLeftAt = now
            return
        }

        let target = CGPoint(x: now.x + Double.random(in: -settings.delta...settings.delta),
                             y: now.y + Double.random(in: -settings.delta...settings.delta))

        glide(from: now, to: target)

        // Проверяем результат, а не факт отправки. Без Accessibility
        // CGEvent.post молча не делает ничего: счётчик растёт, в статусе
        // «Running», курсор стоит. На этом однажды ушёл час диагностики, так
        // что теперь каждый ход подтверждается чтением позиции.
        let reached = Self.cursor()
        let intended = hypot(target.x - now.x, target.y - now.y)
        let achieved = hypot(reached.x - now.x, reached.y - now.y)
        let moved = intended < 2 || achieved > intended / 4

        glide(from: target, to: now)   // возвращаем ровно туда, где был

        if moved {
            if isBlocked { Log.write("движение восстановилось") }
            isBlocked = false
            jiggleCount += 1
        } else if !isBlocked {
            isBlocked = true
            Log.write("""
                курсор не сдвинулся: задумано \(Int(intended)) px, вышло \
                \(Int(achieved)) px. События уходят вникуда — нет прав \
                Accessibility (AXIsProcessTrusted = \(AXIsProcessTrusted())).
                """)
        }

        lastLeftAt = Self.cursor()
        let stamp = Date()
        DispatchQueue.main.async { [weak self] in
            self?.lastJiggle = stamp
            self?.onChange?()
        }
    }

    /// Курсор не там, где мы его оставили, — значит его двигали руками.
    /// Клавиатуру проверяем отдельно: свои события мы шлём только мышиные,
    /// поэтому keyDown — честный признак живого человека.
    private func userIsPresent(cursorNow: CGPoint) -> Bool {
        let moved = abs(cursorNow.x - lastLeftAt.x) > 1 || abs(cursorNow.y - lastLeftAt.y) > 1
        let typing = CGEventSource.secondsSinceLastEventType(.combinedSessionState,
                                                             eventType: .keyDown) < 60
        return moved || typing
    }

    // MARK: - Движение

    /// Плавный ход вместо телепорта: курсор ведёт себя как под рукой человека.
    private func glide(from start: CGPoint, to end: CGPoint) {
        let frameTime = 1.0 / 90.0
        let steps = max(2, Int(settings.glideDuration / frameTime))

        for i in 1...steps {
            let t = Self.easeInOut(Double(i) / Double(steps))
            post(CGPoint(x: start.x + (end.x - start.x) * t,
                         y: start.y + (end.y - start.y) * t))
            Thread.sleep(forTimeInterval: frameTime)
        }
    }

    private func post(_ point: CGPoint) {
        CGEvent(mouseEventSource: source,
                mouseType: .mouseMoved,
                mouseCursorPosition: point,
                mouseButton: .left)?.post(tap: .cghidEventTap)
    }

    private static func easeInOut(_ t: Double) -> Double {
        t < 0.5 ? 2 * t * t : 1 - pow(-2 * t + 2, 2) / 2
    }

    static func cursor() -> CGPoint {
        CGEvent(source: nil)?.location ?? .zero
    }
}
