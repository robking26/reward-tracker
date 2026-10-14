import Foundation

/// An AI estimate of a meal's nutrition. Always an estimate, never a measurement.
struct NutritionEstimate: Codable, Hashable, Sendable {
    enum Confidence: String, Codable, CaseIterable, Sendable {
        case low, medium, high
        var title: String { rawValue.capitalized }
    }

    var name: String
    var items: [String]
    var portionDescription: String
    var kilocalories: Int
    var proteinGrams: Int
    var carbohydrateGrams: Int
    var fatGrams: Int
    var confidence: Confidence
}

enum MealAnalysisError: LocalizedError {
    case notConfigured
    case offline
    case server(String)
    case unreadableResponse

    var errorDescription: String? {
        switch self {
        case .notConfigured: "Meal analysis isn't set up yet. Add your analysis server in Settings."
        case .offline: "You're offline. Meal analysis needs a connection."
        case .server(let message): message
        case .unreadableResponse: "The analysis came back in an unexpected format."
        }
    }
}

/// Provider-independent meal analysis. The app never talks to an AI vendor directly,
/// and no AI credentials ship in the app bundle.
protocol MealAnalyzing: Sendable {
    func analyse(jpeg: Data) async throws -> NutritionEstimate
}

/// Development-only analyser. Returns a fixed, clearly labelled placeholder.
struct MockMealAnalyzer: MealAnalyzing {
    func analyse(jpeg: Data) async throws -> NutritionEstimate {
        try await Task.sleep(for: .milliseconds(900))
        return NutritionEstimate(
            name: "Sample meal (mock analysis)",
            items: ["Grilled chicken", "Rice", "Green vegetables"],
            portionDescription: "Placeholder values for development",
            kilocalories: 620, proteinGrams: 45, carbohydrateGrams: 70, fatGrams: 16,
            confidence: .low)
    }
}

/// Posts the photo to your own backend, which calls a vision model and returns
/// `NutritionEstimate` JSON. The device authenticates with a per-device token held in the Keychain.
///
/// Request: `POST {endpoint}` with `Content-Type: image/jpeg` and `Authorization: Bearer <device token>`.
/// Response: a JSON body matching `NutritionEstimate`.
struct RemoteMealAnalyzer: MealAnalyzing {
    let endpoint: URL
    let deviceToken: String?
    var session: URLSession = .shared

    func analyse(jpeg: Data) async throws -> NutritionEstimate {
        var request = URLRequest(url: endpoint, timeoutInterval: 45)
        request.httpMethod = "POST"
        request.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let deviceToken { request.setValue("Bearer \(deviceToken)", forHTTPHeaderField: "Authorization") }
        request.httpBody = jpeg

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError where error.code == .notConnectedToInternet {
            throw MealAnalysisError.offline
        }
        guard let http = response as? HTTPURLResponse else { throw MealAnalysisError.unreadableResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw MealAnalysisError.server("The analysis server returned an error (\(http.statusCode)).")
        }
        do {
            return try JSONDecoder().decode(NutritionEstimate.self, from: data)
        } catch {
            throw MealAnalysisError.unreadableResponse
        }
    }
}
