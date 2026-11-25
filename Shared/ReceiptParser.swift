import Foundation

struct ParsedReceipt: Equatable {
    var store: String?
    var date: Day?
    var amount: String?
    var name: String? = nil
    var model: String? = nil
}

enum ReceiptParser {
    static func parse(_ lines: [String], today: Day = .today) -> ParsedReceipt {
        let clean = lines.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        let shop = store(clean)
        return ParsedReceipt(store: shop, date: date(clean, today: today), amount: amount(clean),
                             name: itemName(clean, store: shop), model: model(clean))
    }


    static let ignoreWords = ["receipt", "welcome", "thank", "tel:", "tel.", "phone:", "phone #", "www", "http", "cashier", "store #", "invoice", "order",
                              "收据", "收據", "欢迎", "歡迎", "电话", "電話", "收银", "收銀", "订单", "訂單", "领収", "領収", "レシート"]

    private static func isPlainText(_ line: String) -> Bool {
        let letters = line.filter { $0.isLetter }
        let l = line.lowercased()
        return letters.count >= 3 && letters.count > line.filter { $0.isNumber }.count
            && numbers(in: line).isEmpty && dates(in: line).isEmpty
            && !ignoreWords.contains(where: { l.contains($0) })
            && !totalWords.contains(where: { l.contains($0) }) && !skipWords.contains(where: { l.contains($0) })
    }

    static func itemName(_ lines: [String], store: String?) -> String? {
        let start = store.flatMap { s in lines.firstIndex { String($0.prefix(30)) == s } }.map { $0 + 1 } ?? 0
        for line in lines.dropFirst(start).prefix(8) where isPlainText(line) && !isModel(line) {
            let s = String(line.prefix(40))
            return s == s.uppercased() && s.allSatisfy({ $0.isASCII }) ? s.capitalized : s
        }
        return nil
    }

    private static func isModel(_ line: String) -> Bool {
        let t = line.trimmingCharacters(in: .whitespaces)
        guard (5...20).contains(t.count), !t.contains(" "), t.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }) else { return false }
        return t.contains(where: { $0.isLetter }) && t.filter({ $0.isNumber }).count >= 2
    }

    static func model(_ lines: [String]) -> String? {
        lines.prefix(10).first { isModel($0) && numbers(in: $0).isEmpty && dates(in: $0).isEmpty }
            .map { $0.trimmingCharacters(in: .whitespaces) }
    }


    static func date(_ lines: [String], today: Day) -> Day? {
        let earliest = today.adding(months: -12 * 20)
        let found = lines.flatMap { dates(in: $0) }.filter { $0 <= today.adding(days: 1) && $0 >= earliest }
        return found.first
    }

    static func dates(in line: String) -> [Day] {
        var out: [Day] = []
        let s = line.replacingOccurrences(of: "／", with: "/").replacingOccurrences(of: "－", with: "-")
        for m in matches(#"(\d{4})\s*年\s*(\d{1,2})\s*月\s*(\d{1,2})\s*日"#, s) {
            if let d = Day.valid(year: m[0], month: m[1], day: m[2]) { out.append(d) }
        }
        for m in matches(#"(?<!\d)(\d{4})[-/.](\d{1,2})[-/.](\d{1,2})(?!\d)"#, s) {
            if let d = Day.valid(year: m[0], month: m[1], day: m[2]) { out.append(d) }
        }
        for (m, sep) in matchesWithSeparator(#"(?<!\d)(\d{1,2})([-/.])(\d{1,2})[-/.](\d{2}|\d{4})(?!\d)"#, s) {
            var y = m[2]
            if y < 100 { y += 2000 }
            let a = m[0], b = m[1]
            let dayFirst = sep == "." || a > 12
            let d = dayFirst ? Day.valid(year: y, month: b, day: a) : Day.valid(year: y, month: a, day: b)
            if let d { out.append(d) }
        }
        let months = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"]
        let lower = s.lowercased()
        for (i, name) in months.enumerated() {
            for m in matches(name + #"[a-z]*\.?\s+(\d{1,2}),?\s+(\d{4})"#, lower) {
                if let d = Day.valid(year: m[1], month: i + 1, day: m[0]) { out.append(d) }
            }
            for m in matches(#"(\d{1,2})\s+"# + name + #"[a-z]*\.?,?\s+(\d{4})"#, lower) {
                if let d = Day.valid(year: m[1], month: i + 1, day: m[0]) { out.append(d) }
            }
        }
        return out
    }


    static let totalWords = ["total", "amount due", "balance due", "grand total", "合计", "合計", "总计", "總計", "实付", "實付", "应付", "金额", "金額", "お支払", "合 計"]
    static let skipWords = ["subtotal", "sub total", "sub-total", "tax", "小计", "小計", "税", "change", "找零", "savings", "discount"]

    static func amount(_ lines: [String]) -> String? {
        var best: String?
        for line in lines {
            let l = line.lowercased()
            guard totalWords.contains(where: { l.contains($0) }), !skipWords.contains(where: { l.contains($0) }) else { continue }
            if let v = numbers(in: line).last { best = v }
        }
        if let best { return best }
        let all = lines.flatMap { numbers(in: $0) }
        return all.max { (Double($0) ?? 0) < (Double($1) ?? 0) }
    }

    static func numbers(in line: String) -> [String] {
        let s = line.replacingOccurrences(of: "．", with: ".").replacingOccurrences(of: "，", with: ",")
        guard let re = try? NSRegularExpression(pattern: #"(?<![\d.])(\d{1,3}(?:,\d{3})+|\d+)\.(\d{2})(?!\d)"#) else { return [] }
        return re.matches(in: s, range: NSRange(s.startIndex..., in: s)).compactMap { m in
            guard let a = Range(m.range(at: 1), in: s), let b = Range(m.range(at: 2), in: s) else { return nil }
            return s[a].replacingOccurrences(of: ",", with: "") + "." + s[b]
        }
    }


    static func store(_ lines: [String]) -> String? {
        for line in lines.prefix(6) {
            let letters = line.filter { $0.isLetter }
            guard letters.count >= 3, numbers(in: line).isEmpty, dates(in: line).isEmpty else { continue }
            let l = line.lowercased()
            if ["receipt", "welcome", "thank", "tel", "phone", "www", "http", "收据", "收據", "欢迎", "歡迎", "电话", "電話"].contains(where: { l.contains($0) }) { continue }
            if line.filter({ $0.isNumber }).count > letters.count { continue }
            return String(line.prefix(30))
        }
        return nil
    }


    private static func matches(_ pattern: String, _ s: String) -> [[Int]] {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return [] }
        return re.matches(in: s, range: NSRange(s.startIndex..., in: s)).map { m in
            (1..<m.numberOfRanges).compactMap { i in Range(m.range(at: i), in: s).flatMap { Int(s[$0]) } }
        }
    }

    private static func matchesWithSeparator(_ pattern: String, _ s: String) -> [([Int], String)] {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return [] }
        return re.matches(in: s, range: NSRange(s.startIndex..., in: s)).compactMap { m in
            guard m.numberOfRanges == 5,
                  let r1 = Range(m.range(at: 1), in: s), let r2 = Range(m.range(at: 2), in: s),
                  let r3 = Range(m.range(at: 3), in: s), let r4 = Range(m.range(at: 4), in: s),
                  let a = Int(s[r1]), let b = Int(s[r3]), let y = Int(s[r4]) else { return nil }
            return ([a, b, y], String(s[r2]))
        }
    }
}
