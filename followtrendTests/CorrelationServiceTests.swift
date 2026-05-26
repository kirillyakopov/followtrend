//
//  CorrelationServiceTests.swift
//  followtrendTests
//

import XCTest
@testable import followtrend

final class CorrelationServiceTests: XCTestCase {
    private let service = CorrelationService.shared
    private let accuracy = 0.000001

    func testPearsonPerfectPositiveCorrelation() async {
        let result = await service.pearson(
            x: [1, 2, 3, 4, 5],
            y: [2, 4, 6, 8, 10]
        )

        XCTAssertEqual(result, 1.0, accuracy: accuracy)
        XCTAssertWithinPearsonBounds(result)
    }

    func testPearsonPerfectNegativeCorrelation() async {
        let result = await service.pearson(
            x: [1, 2, 3, 4, 5],
            y: [10, 8, 6, 4, 2]
        )

        XCTAssertEqual(result, -1.0, accuracy: accuracy)
        XCTAssertWithinPearsonBounds(result)
    }

    func testPearsonKnownDataset() async {
        let result = await service.pearson(
            x: [43, 21, 25, 42, 57, 59],
            y: [99, 65, 79, 75, 87, 81]
        )

        XCTAssertEqual(result, 0.5298089018901744, accuracy: accuracy)
        XCTAssertWithinPearsonBounds(result)
    }

    func testPearsonRejectsMismatchedDatasets() async {
        let result = await service.pearson(
            x: [0.01, 0.02, 0.03],
            y: [0.01, 0.02]
        )

        XCTAssertNil(result)
    }

    func testPearsonRejectsZeroVarianceDatasets() async {
        let result = await service.pearson(
            x: [0.02, 0.02, 0.02, 0.02],
            y: [0.01, 0.03, 0.05, 0.07]
        )

        XCTAssertNil(result)
    }

    func testSelfValidationSuitePasses() async {
        let result = await service.runSelfTests()

        XCTAssertTrue(result)
    }

    private func XCTAssertWithinPearsonBounds(
        _ value: Double?,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let value else {
            XCTFail("Expected a Pearson coefficient.", file: file, line: line)
            return
        }

        XCTAssertGreaterThanOrEqual(value, -1.0, file: file, line: line)
        XCTAssertLessThanOrEqual(value, 1.0, file: file, line: line)
    }
}
