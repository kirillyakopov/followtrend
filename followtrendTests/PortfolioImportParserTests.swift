//
//  PortfolioImportParserTests.swift
//  followtrendTests
//
//  Unit coverage for the pure-Foundation paste parser. No network — every
//  expectation is derived from PortfolioImportParser's documented behaviour.
//

import XCTest
@testable import followtrend

final class PortfolioImportParserTests: XCTestCase {

    // MARK: - Freeform positions

    func testFreeformPositionWithDate() {
        let result = PortfolioImportParser.parse("AAPL 12 @ 175.30 2024-01-15")

        XCTAssertTrue(result.issues.isEmpty)
        XCTAssertEqual(result.drafts.count, 1)
        let d = result.drafts[0]
        XCTAssertEqual(d.symbol, "AAPL")
        XCTAssertEqual(d.shares, 12)
        XCTAssertEqual(d.price, 175.30)
        XCTAssertEqual(d.dateString, "2024-01-15")
        XCTAssertNil(d.currency)
        XCTAssertFalse(d.isWatchlist)
        XCTAssertNil(d.coinId)
    }

    func testFreeformCryptoTagsCoinIdAndCurrency() {
        let result = PortfolioImportParser.parse("BTC 0.45 @ 43200 EUR")

        XCTAssertEqual(result.drafts.count, 1)
        let d = result.drafts[0]
        XCTAssertEqual(d.symbol, "BTC")
        XCTAssertEqual(d.shares, 0.45)
        XCTAssertEqual(d.price, 43200)
        XCTAssertEqual(d.currency, "EUR")
        XCTAssertEqual(d.coinId, "bitcoin")
    }

    func testFreeformDollarSignImpliesUSD() {
        let result = PortfolioImportParser.parse("MSFT 3 @ $410.20")

        XCTAssertEqual(result.drafts.count, 1)
        let d = result.drafts[0]
        XCTAssertEqual(d.symbol, "MSFT")
        XCTAssertEqual(d.shares, 3)
        XCTAssertEqual(d.price, 410.20)
        XCTAssertEqual(d.currency, "USD")
    }

    func testSymbolOnlyBecomesWatchlist() {
        let result = PortfolioImportParser.parse("TSLA")

        XCTAssertEqual(result.drafts.count, 1)
        XCTAssertTrue(result.drafts[0].isWatchlist)
        XCTAssertNil(result.drafts[0].shares)
        XCTAssertEqual(result.watchlistCount, 1)
        XCTAssertEqual(result.positionCount, 0)
    }

    func testQuotedNameIsCaptured() {
        let result = PortfolioImportParser.parse("AAPL 12 @ 175 \"Apple Inc.\"")

        XCTAssertEqual(result.drafts.count, 1)
        XCTAssertEqual(result.drafts[0].name, "Apple Inc.")
        XCTAssertEqual(result.drafts[0].symbol, "AAPL")
    }

    func testCommaActsAsSeparatorInFreeform() {
        // Freeform treats "," as a delimiter (not a decimal point).
        let result = PortfolioImportParser.parse("AAPL,12,175.30")

        XCTAssertEqual(result.drafts.count, 1)
        let d = result.drafts[0]
        XCTAssertEqual(d.symbol, "AAPL")
        XCTAssertEqual(d.shares, 12)
        XCTAssertEqual(d.price, 175.30)
    }

    // MARK: - Comments / blank lines

    func testCommentsAndBlankLinesAreIgnored() {
        let input = """
        # header comment
        // another comment

        AAPL 1 @ 100
        """
        let result = PortfolioImportParser.parse(input)

        XCTAssertTrue(result.issues.isEmpty)
        XCTAssertEqual(result.drafts.count, 1)
        XCTAssertEqual(result.drafts[0].symbol, "AAPL")
    }

    // MARK: - Issues

    func testInvalidSymbolProducesIssue() {
        let result = PortfolioImportParser.parse("123 45 @ 67")

        XCTAssertTrue(result.drafts.isEmpty)
        XCTAssertEqual(result.issues.count, 1)
        XCTAssertEqual(result.issues[0].reason, .invalidSymbol)
    }

    func testZeroSharesProducesInvalidSharesIssue() {
        let result = PortfolioImportParser.parse("AAPL 0 @ 175")

        XCTAssertTrue(result.drafts.isEmpty)
        XCTAssertEqual(result.issues.count, 1)
        XCTAssertEqual(result.issues[0].reason, .invalidShares)
    }

    func testSharesWithoutPriceProducesMissingPriceIssue() {
        let result = PortfolioImportParser.parse("AAPL 12")

        XCTAssertTrue(result.drafts.isEmpty)
        XCTAssertEqual(result.issues.count, 1)
        XCTAssertEqual(result.issues[0].reason, .missingPrice)
    }

    // MARK: - Dates

    func testParseDateAcceptsThreeFormatsToISO() {
        XCTAssertEqual(PortfolioImportParser.parseDate("2024-01-15"), "2024-01-15")
        XCTAssertEqual(PortfolioImportParser.parseDate("15.01.2024"), "2024-01-15")
        XCTAssertEqual(PortfolioImportParser.parseDate("01/15/2024"), "2024-01-15")
    }

    func testParseDateRejectsGarbage() {
        XCTAssertNil(PortfolioImportParser.parseDate("not-a-date"))
        XCTAssertNil(PortfolioImportParser.parseDate("12"))
    }

    // MARK: - CSV

    func testCSVHeaderDetectionAndRows() {
        let input = """
        symbol,shares,price,date
        AAPL,12,175.30,2024-01-15
        BTC,0.45,43200,2024-02-10
        """
        let result = PortfolioImportParser.parse(input)

        XCTAssertTrue(result.issues.isEmpty)
        XCTAssertEqual(result.drafts.count, 2)

        let aapl = result.drafts[0]
        XCTAssertEqual(aapl.symbol, "AAPL")
        XCTAssertEqual(aapl.shares, 12)
        XCTAssertEqual(aapl.price, 175.30)
        XCTAssertEqual(aapl.dateString, "2024-01-15")
        // Line numbers account for the stripped header row.
        XCTAssertEqual(aapl.line, 2)

        let btc = result.drafts[1]
        XCTAssertEqual(btc.symbol, "BTC")
        XCTAssertEqual(btc.coinId, "bitcoin")
        XCTAssertEqual(btc.dateString, "2024-02-10")
    }

    func testCSVGermanHeadersAndEuropeanDecimals() {
        // Semicolon-separated cells let "," survive as a decimal separator.
        let input = """
        Ticker;Stückzahl;Kaufpreis;Währung
        BTC;0,45;43200,50;EUR
        """
        let result = PortfolioImportParser.parse(input)

        XCTAssertEqual(result.drafts.count, 1)
        let d = result.drafts[0]
        XCTAssertEqual(d.symbol, "BTC")
        XCTAssertEqual(d.shares, 0.45)
        XCTAssertEqual(d.price, 43200.50)
        XCTAssertEqual(d.currency, "EUR")
    }

    func testCSVInvalidDateProducesIssue() {
        let input = """
        symbol,shares,price,date
        AAPL,12,175,not-a-date
        """
        let result = PortfolioImportParser.parse(input)

        XCTAssertTrue(result.drafts.isEmpty)
        XCTAssertEqual(result.issues.count, 1)
        XCTAssertEqual(result.issues[0].reason, .invalidDate)
    }

    func testCSVEmptySharesAndPriceBecomesWatchlist() {
        let input = """
        symbol,shares,price
        TSLA,,
        """
        let result = PortfolioImportParser.parse(input)

        XCTAssertTrue(result.issues.isEmpty)
        XCTAssertEqual(result.drafts.count, 1)
        XCTAssertTrue(result.drafts[0].isWatchlist)
        XCTAssertEqual(result.drafts[0].symbol, "TSLA")
    }

    // MARK: - Result counts (mixed input)

    func testMixedInputCounts() {
        let input = """
        AAPL 12 @ 175.30
        BTC 0.45 @ 43200 EUR
        TSLA
        NVDA
        """
        let result = PortfolioImportParser.parse(input)

        XCTAssertEqual(result.drafts.count, 4)
        XCTAssertEqual(result.positionCount, 2)
        XCTAssertEqual(result.watchlistCount, 2)
    }

    // MARK: - Serialize (inline-editor inverse)

    func testSerializePositionRoundTrips() {
        let draft = ImportDraft(
            line: 1, symbol: "AAPL", shares: 12, price: 175.3,
            currency: "EUR", dateString: "2024-01-15"
        )
        let line = PortfolioImportParser.serialize(draft)
        XCTAssertEqual(line, "AAPL 12 @ 175.3 EUR 2024-01-15")

        let reparsed = PortfolioImportParser.parse(line)
        XCTAssertEqual(reparsed.drafts.count, 1)
        let r = reparsed.drafts[0]
        XCTAssertEqual(r.symbol, "AAPL")
        XCTAssertEqual(r.shares, 12)
        XCTAssertEqual(r.price, 175.3)
        XCTAssertEqual(r.currency, "EUR")
        XCTAssertEqual(r.dateString, "2024-01-15")
    }

    func testSerializeWatchlistIsSymbolOnly() {
        let draft = ImportDraft(line: 1, symbol: "TSLA")
        XCTAssertEqual(PortfolioImportParser.serialize(draft), "TSLA")
    }

    func testSerializeWatchlistWithName() {
        let draft = ImportDraft(line: 1, symbol: "TSLA", name: "Tesla Inc.")
        XCTAssertEqual(PortfolioImportParser.serialize(draft), "TSLA \"Tesla Inc.\"")
    }

    // MARK: - numberString

    func testNumberStringFormatting() {
        XCTAssertEqual(PortfolioImportParser.numberString(12.0), "12")
        XCTAssertEqual(PortfolioImportParser.numberString(43200.0), "43200")
        XCTAssertEqual(PortfolioImportParser.numberString(0.45), "0.45")
    }
}
