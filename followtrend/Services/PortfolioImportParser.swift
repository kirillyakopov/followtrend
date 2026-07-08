//
//  PortfolioImportParser.swift
//  followtrend
//
//  On-device parser for pasted portfolio text (Phase 1 of the import
//  pipeline). Turns free-form lines / spreadsheet rows / simple CSV into
//  draft positions; nothing here touches the store — the review UI decides.
//
//  Accepted per line (separators: space, comma, semicolon, tab):
//      AAPL 12 @ 175.30 2024-01-15     → position (default currency)
//      BTC 0.45 @ 43200 EUR            → position priced in EUR
//      MSFT 3 @ $410.20                → position priced in USD
//      TSLA                            → watchlist (ghost bubble)
//  A leading CSV header row (symbol,shares,price,date[,currency,name]) is
//  detected and mapped automatically. Lines starting with # or // are ignored.
//  `serialize(_:)` is the inverse — used by the review screen's inline editor
//  to write an edited row back into the text field.
//

import Foundation

// MARK: - Ticker existence state (async validation)

enum TickerCheck: Equatable {
    case checking      // request in flight
    case valid         // provider returned a real quote
    case notFound      // provider says the symbol is unknown
    case unverified    // couldn't be determined (offline / rate limited)
}

// MARK: - Draft model

struct ImportDraft: Identifiable, Equatable {
    let id: UUID
    var line: Int               // 1-based source line (for issue messages / text sync)
    var symbol: String          // uppercased ticker
    var name: String?           // optional quoted name
    var shares: Double?         // nil → watchlist candidate
    var price: Double?          // avg purchase price per share
    var currency: String?       // "USD"/"EUR"; nil → follow the import-wide default
    var dateString: String?     // yyyy-MM-dd; nil → today (estimate)
    var coinId: String?         // known-crypto mapping for the data layer

    var isWatchlist: Bool { shares == nil }

    init(id: UUID = UUID(), line: Int, symbol: String, name: String? = nil,
         shares: Double? = nil, price: Double? = nil, currency: String? = nil,
         dateString: String? = nil, coinId: String? = nil) {
        self.id = id; self.line = line; self.symbol = symbol; self.name = name
        self.shares = shares; self.price = price; self.currency = currency
        self.dateString = dateString; self.coinId = coinId
    }
}

struct ImportIssue: Identifiable, Equatable {
    enum Reason: Equatable { case invalidSymbol, invalidShares, missingPrice, invalidDate }
    let id = UUID()
    let line: Int
    let text: String            // offending source line (trimmed, for context)
    let reason: Reason

    static func == (lhs: ImportIssue, rhs: ImportIssue) -> Bool {
        lhs.line == rhs.line && lhs.reason == rhs.reason
    }
}

struct ImportParseResult: Equatable {
    var drafts: [ImportDraft] = []
    var issues: [ImportIssue] = []
    var positionCount: Int { drafts.filter { !$0.isWatchlist }.count }
    var watchlistCount: Int { drafts.filter { $0.isWatchlist }.count }
}

// MARK: - Parser

enum PortfolioImportParser {

    /// Symbols the data layer treats as crypto (mirrors MarketDataService).
    static let knownCrypto: [String: String] = [
        "BTC": "bitcoin",   "ETH": "ethereum",  "SOL": "solana",
        "BNB": "binancecoin", "XRP": "ripple",  "ADA": "cardano",
        "DOGE": "dogecoin", "AVAX": "avalanche-2", "DOT": "polkadot",
        "MATIC": "matic-network",
    ]

    static func parse(_ input: String) -> ImportParseResult {
        var result = ImportParseResult()
        var lines = input.components(separatedBy: .newlines)
        var lineOffset = 0

        // CSV header detection: first non-empty line naming a symbol column.
        var columns: [String: Int]? = nil
        if let headerIdx = lines.firstIndex(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) {
            let header = lines[headerIdx].lowercased()
            if header.contains("symbol") || header.contains("ticker") {
                columns = mapHeader(lines[headerIdx])
                lineOffset = headerIdx + 1
                lines.removeSubrange(0...headerIdx)
            }
        }

        for (idx, rawLine) in lines.enumerated() {
            let lineNo = idx + 1 + lineOffset
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#"), !trimmed.hasPrefix("//") else { continue }
            if let columns {
                parseCSVRow(trimmed, line: lineNo, columns: columns, into: &result)
            } else {
                parseFreeformLine(trimmed, line: lineNo, into: &result)
            }
        }
        return result
    }

    // MARK: Freeform lines

    private static func parseFreeformLine(_ line: String, line lineNo: Int, into result: inout ImportParseResult) {
        var work = line
        var name: String? = nil
        if let open = work.firstIndex(of: "\""),
           let close = work[work.index(after: open)...].firstIndex(of: "\"") {
            name = String(work[work.index(after: open)..<close])
            work.removeSubrange(open...close)
        }

        // Currency from an attached symbol ($ / €) before we strip them off numbers.
        var currency: String? = detectCurrencySymbol(work)

        let normalized = work
            .replacingOccurrences(of: "@", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
            .replacingOccurrences(of: ";", with: " ")
            .replacingOccurrences(of: ",", with: " ")

        var tokens = normalized.split(separator: " ").map(String.init).filter { !$0.isEmpty }
        guard !tokens.isEmpty else { return }

        // Standalone currency code token (USD / EUR), removed from the token list.
        if let ci = tokens.firstIndex(where: { normalizeCurrency($0) != nil }) {
            currency = normalizeCurrency(tokens[ci])
            tokens.remove(at: ci)
        }

        let symbolToken = tokens.removeFirst().uppercased()
        guard isValidSymbol(symbolToken) else {
            result.issues.append(ImportIssue(line: lineNo, text: line, reason: .invalidSymbol))
            return
        }

        var dateString: String? = nil
        if let di = tokens.firstIndex(where: { parseDate($0) != nil }) {
            dateString = parseDate(tokens[di])
            tokens.remove(at: di)
        }

        let numbers = tokens.compactMap(parseNumber)

        if numbers.isEmpty && dateString == nil {
            result.drafts.append(ImportDraft(
                line: lineNo, symbol: symbolToken, name: name,
                shares: nil, price: nil, currency: currency,
                dateString: nil, coinId: knownCrypto[symbolToken]
            ))
            return
        }
        guard let shares = numbers.first, shares > 0 else {
            result.issues.append(ImportIssue(line: lineNo, text: line, reason: .invalidShares))
            return
        }
        guard numbers.count >= 2, numbers[1] > 0 else {
            result.issues.append(ImportIssue(line: lineNo, text: line, reason: .missingPrice))
            return
        }
        result.drafts.append(ImportDraft(
            line: lineNo, symbol: symbolToken, name: name,
            shares: shares, price: numbers[1], currency: currency,
            dateString: dateString, coinId: knownCrypto[symbolToken]
        ))
    }

    // MARK: CSV rows

    private static func mapHeader(_ header: String) -> [String: Int] {
        var map: [String: Int] = [:]
        let cols = splitCSV(header).map { $0.lowercased().trimmingCharacters(in: .whitespaces) }
        for (i, col) in cols.enumerated() {
            switch col {
            case let c where c.contains("symbol") || c.contains("ticker"): map["symbol"] = i
            case let c where c.contains("share") || c.contains("quantity") || c.contains("qty")
                          || c.contains("amount") || c.contains("stück"):
                if map["shares"] == nil { map["shares"] = i }
            case let c where c.contains("price") || c.contains("cost") || c.contains("avg") || c.contains("kauf"):
                if map["price"] == nil { map["price"] = i }
            case let c where c.contains("currency") || c.contains("ccy") || c.contains("währung") || c.contains("valuta"):
                if map["currency"] == nil { map["currency"] = i }
            case let c where c.contains("date") || c.contains("datum"):
                if map["date"] == nil { map["date"] = i }
            case let c where c.contains("name"):
                if map["name"] == nil { map["name"] = i }
            default: break
            }
        }
        return map
    }

    private static func parseCSVRow(_ row: String, line lineNo: Int, columns: [String: Int], into result: inout ImportParseResult) {
        let cells = splitCSV(row).map { $0.trimmingCharacters(in: CharacterSet(charactersIn: " \"")) }
        func cell(_ key: String) -> String? {
            guard let i = columns[key], i < cells.count else { return nil }
            let v = cells[i]; return v.isEmpty ? nil : v
        }

        guard let rawSymbol = cell("symbol") else {
            result.issues.append(ImportIssue(line: lineNo, text: row, reason: .invalidSymbol)); return
        }
        let symbol = rawSymbol.uppercased()
        guard isValidSymbol(symbol) else {
            result.issues.append(ImportIssue(line: lineNo, text: row, reason: .invalidSymbol)); return
        }

        let shares = cell("shares").flatMap(parseNumber)
        let price  = cell("price").flatMap(parseNumber)
        let name   = cell("name")
        var currency = cell("currency").flatMap(normalizeCurrency)
        if currency == nil, let priceCell = cell("price") { currency = detectCurrencySymbol(priceCell) }

        var dateString: String? = nil
        if let rawDate = cell("date") {
            dateString = parseDate(rawDate)
            if dateString == nil { result.issues.append(ImportIssue(line: lineNo, text: row, reason: .invalidDate)); return }
        }

        if shares == nil && price == nil {
            result.drafts.append(ImportDraft(
                line: lineNo, symbol: symbol, name: name,
                shares: nil, price: nil, currency: currency, dateString: nil, coinId: knownCrypto[symbol]))
            return
        }
        guard let s = shares, s > 0 else { result.issues.append(ImportIssue(line: lineNo, text: row, reason: .invalidShares)); return }
        guard let p = price, p > 0 else { result.issues.append(ImportIssue(line: lineNo, text: row, reason: .missingPrice)); return }

        result.drafts.append(ImportDraft(
            line: lineNo, symbol: symbol, name: name,
            shares: s, price: p, currency: currency, dateString: dateString, coinId: knownCrypto[symbol]))
    }

    // MARK: - Serialize (draft → canonical line, for the inline editor)

    static func serialize(_ d: ImportDraft) -> String {
        if d.isWatchlist {
            var s = d.symbol
            if let n = d.name, !n.isEmpty { s += " \"\(n)\"" }
            return s
        }
        var parts: [String] = [d.symbol]
        if let sh = d.shares { parts.append(numberString(sh)) }
        if let p = d.price { parts.append("@ \(numberString(p))") }
        if let c = d.currency { parts.append(c) }
        if let date = d.dateString { parts.append(date) }
        if let n = d.name, !n.isEmpty { parts.append("\"\(n)\"") }
        return parts.joined(separator: " ")
    }

    // MARK: Token helpers

    private static func splitCSV(_ row: String) -> [String] {
        let sep: Character = row.contains(";") ? ";" : (row.contains("\t") ? "\t" : ",")
        return row.split(separator: sep, omittingEmptySubsequences: false).map(String.init)
    }

    private static func isValidSymbol(_ s: String) -> Bool {
        guard (1...12).contains(s.count) else { return false }
        guard s.rangeOfCharacter(from: .letters) != nil else { return false }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ".-"))
        return s.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    /// Only the app's two supported currencies.
    private static func normalizeCurrency(_ token: String) -> String? {
        switch token.uppercased() {
        case "USD", "US$", "$": return "USD"
        case "EUR", "€":        return "EUR"
        default:                return nil
        }
    }

    private static func detectCurrencySymbol(_ s: String) -> String? {
        if s.contains("€") { return "EUR" }
        if s.contains("$") { return "USD" }
        return nil
    }

    /// Tolerant number parsing: strips currency symbols, accepts "," as a
    /// decimal separator when no "." is present ("43200,50" → 43200.5).
    private static func parseNumber(_ token: String) -> Double? {
        var t = token
            .replacingOccurrences(of: "€", with: "").replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: "£", with: "").replacingOccurrences(of: "x", with: "")
            .replacingOccurrences(of: "X", with: "").trimmingCharacters(in: .whitespaces)
        if t.contains(",") && !t.contains(".") { t = t.replacingOccurrences(of: ",", with: ".") }
        else { t = t.replacingOccurrences(of: ",", with: "") }
        guard !t.isEmpty else { return nil }
        return Double(t)
    }

    /// Compact number for serialized lines: "12", "0.45", "43200".
    static func numberString(_ v: Double) -> String {
        v.truncatingRemainder(dividingBy: 1) == 0 ? String(format: "%.0f", v) : String(format: "%g", v)
    }

    /// Accepts yyyy-MM-dd, dd.MM.yyyy, MM/dd/yyyy — returns yyyy-MM-dd.
    static func parseDate(_ token: String) -> String? {
        let formats = ["yyyy-MM-dd", "dd.MM.yyyy", "MM/dd/yyyy"]
        let out = DateFormatter(); out.dateFormat = "yyyy-MM-dd"
        let inFmt = DateFormatter(); inFmt.locale = Locale(identifier: "en_US_POSIX")
        for f in formats {
            inFmt.dateFormat = f
            if let d = inFmt.date(from: token),
               token.contains("-") || token.contains(".") || token.contains("/") {
                return out.string(from: d)
            }
        }
        return nil
    }
}
