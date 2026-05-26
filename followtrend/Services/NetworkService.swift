//
//  NetworkService.swift
//  followtrend
//

import Foundation

// MARK: - Network errors

enum NetworkError: LocalizedError {
    case noAPIKey
    case badURL
    case httpError(Int)
    case decode(Error)
    case network(Error)
    case rateLimited
    case noData

    var errorDescription: String? {
        switch self {
        case .noAPIKey:        return "API key not configured."
        case .badURL:          return "Invalid request URL."
        case .httpError(let c):return "HTTP error \(c)."
        case .decode(let e):   return "Decode error: \(e.localizedDescription)"
        case .network(let e):  return "Network error: \(e.localizedDescription)"
        case .rateLimited:     return "Rate limited — please wait."
        case .noData:          return "No data returned."
        }
    }
}

// MARK: - Network service

final class NetworkService {
    static let shared = NetworkService()

    private let session: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest  = 15
        cfg.timeoutIntervalForResource = 30
        cfg.requestCachePolicy = .useProtocolCachePolicy  // respect Finnhub Cache-Control
        return URLSession(configuration: cfg)
    }()

    private init() {}

    // Generic JSON fetch
    func fetch<T: Decodable>(_ url: URL) async throws -> T {
        let (data, response) = try await session.data(from: url)

        if let http = response as? HTTPURLResponse {
            switch http.statusCode {
            case 200...299: break
            case 429:       throw NetworkError.rateLimited
            default:        throw NetworkError.httpError(http.statusCode)
            }
        }

        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw NetworkError.decode(error)
        }
    }

    // Build URL with query params
    func makeURL(base: String, path: String, params: [String: String]) -> URL? {
        var components = URLComponents(string: base + path)
        components?.queryItems = params.map { URLQueryItem(name: $0.key, value: $0.value) }
        return components?.url
    }
}
