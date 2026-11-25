import Foundation

enum Transfer {
    static let prefix = "WTK1:"

    struct Payload: Codable, Equatable {
        var name: String
        var store: String
        var category: String
        var purchased: String?
        var price: String
        var warrantyMonths: Int?
        var extendedEnd: String?
        var returnDays: Int?
        var expires: String?
        var model: String
        var serial: String
        var phone: String
    }

    static func code(for item: Item) -> String {
        let p = Payload(name: item.name, store: item.store, category: item.category, purchased: item.purchased?.iso,
                        price: item.price, warrantyMonths: item.warrantyMonths, extendedEnd: item.extendedEnd?.iso,
                        returnDays: item.returnDays, expires: item.expires?.iso, model: item.model, serial: item.serial, phone: item.phone)
        let data = (try? JSONEncoder().encode(p)) ?? Data()
        return prefix + data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }

    static func item(from text: String, categories: [CategoryDef]) throws -> Item {
        guard let r = text.range(of: prefix) else { throw WarrantyError.badCode }
        var body = String(text[r.upperBound...].prefix { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" })
        guard !body.isEmpty, body.count < 4000 else { throw WarrantyError.badCode }
        body = body.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while body.count % 4 != 0 { body += "=" }
        guard let data = Data(base64Encoded: body), let p = try? JSONDecoder().decode(Payload.self, from: data) else {
            throw WarrantyError.badCode
        }
        var item = Item()
        item.name = String(p.name.prefix(80))
        item.store = String(p.store.prefix(80))
        item.category = categories.contains { $0.id == p.category } ? p.category : "other"
        item.purchased = p.purchased.flatMap(Day.init(iso:))
        item.price = String(p.price.prefix(20))
        item.warrantyMonths = p.warrantyMonths.map { min(max($0, 0), 600) }
        item.extendedEnd = p.extendedEnd.flatMap(Day.init(iso:))
        item.returnDays = p.returnDays.map { min(max($0, 0), 365) }
        item.expires = p.expires.flatMap(Day.init(iso:))
        item.model = String(p.model.prefix(80))
        item.serial = String(p.serial.prefix(80))
        item.phone = String(p.phone.prefix(40))
        guard !item.displayName.isEmpty, item.purchased != nil || item.expires != nil else { throw WarrantyError.badCode }
        return item
    }
}

enum CSVExport {
    static func text(_ state: AppState) -> String {
        let head = ["name", "category", "store", "purchased", "price", "warranty_end", "extended_end", "return_end", "expires", "model", "serial", "phone", "notes"]
            .map { L.t("csv." + $0) }
        var rows = [head]
        for i in state.items.sorted(by: { ($0.purchased ?? $0.expires ?? Day.today) > ($1.purchased ?? $1.expires ?? Day.today) }) {
            rows.append([i.displayName, state.category(i.category).title, i.store, i.purchased?.iso ?? "", i.price,
                         i.warrantyEnd?.iso ?? "", i.extendedEnd?.iso ?? "", i.returnEnd?.iso ?? "", i.expires?.iso ?? "",
                         i.model, i.serial, i.phone, i.notes])
        }
        return rows.map { $0.map(cell).joined(separator: ",") }.joined(separator: "\r\n") + "\r\n"
    }

    static func cell(_ raw: String) -> String {
        var s = raw
        if let f = s.first, "=+-@\t\r".contains(f) { s = "'" + s }
        if s.contains(where: { ",\"\n\r".contains($0) }) {
            s = "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return s
    }
}
