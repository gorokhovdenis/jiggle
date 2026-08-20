import Foundation

/// Пишет в ~/Library/Logs/jiggle.log.
///
/// Нужен именно файл, а не print: у menu bar приложения stdout читать некому,
/// и когда курсор стоял при бодром счётчике шевелений, выяснять причину
/// приходилось замерами со стороны. Теперь приложение говорит само.
enum Log {

    private static let url: URL = FileManager.default
        .homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/jiggle.log")

    private static let queue = DispatchQueue(label: "jiggle.log", qos: .utility)
    private static let limit = 256 * 1024

    private static let stamp: DateFormatter = {
        let f = DateFormatter()
        // Без фиксированной локали dateFormat подчиняется календарю и цифрам
        // пользователя (буддийский год, арабские цифры) — лог перестаёт быть
        // сравнимым между машинами.
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()

    static func write(_ message: String) {
        queue.async {
            guard let data = "\(stamp.string(from: Date())) \(message)\n"
                    .data(using: .utf8) else { return }

            let fm = FileManager.default

            // Обрезаем целиком, а не построчно: лог диагностический, история
            // старше последних килобайт никому не нужна.
            if let attrs = try? fm.attributesOfItem(atPath: url.path),
               let size = attrs[.size] as? Int, size > limit {
                try? fm.removeItem(at: url)
            }

            if let handle = try? FileHandle(forWritingTo: url) {
                handle.seekToEndOfFile()
                handle.write(data)
                try? handle.close()
            } else {
                try? data.write(to: url)
            }
        }
    }

    static var path: String { url.path }
}
