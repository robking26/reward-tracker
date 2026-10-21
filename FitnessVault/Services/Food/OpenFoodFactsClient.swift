import Foundation

/// Finds a product's nutrition from its barcode.
protocol ProductLookup: Sendable {
    func product(barcode: String) async -> Result<FoodProduct, OpenFoodFacts.LookupError>
}

/// Open Food Facts: a free, open database of packaged food. No account or key; only the barcode is sent.
struct OpenFoodFactsClient: ProductLookup {
    var session: URLSession = .shared

    func product(barcode: String) async -> Result<FoodProduct, OpenFoodFacts.LookupError> {
        guard let url = OpenFoodFacts.url(barcode: barcode) else { return .failure(.notFound) }
        var request = URLRequest(url: url, timeoutInterval: 15)
        // Open Food Facts asks apps to identify themselves.
        request.setValue("Vaultality/2.1 (iOS; personal use)", forHTTPHeaderField: "User-Agent")
        do {
            let (data, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode == 404 { return .failure(.notFound) }
            return OpenFoodFacts.parse(data, barcode: barcode)
        } catch {
            return .failure(.unreadable)
        }
    }
}

/// For tests and previews: answers from a fixed set of products.
struct FixedProductLookup: ProductLookup {
    var products: [String: FoodProduct] = [:]

    func product(barcode: String) async -> Result<FoodProduct, OpenFoodFacts.LookupError> {
        products[barcode].map { .success($0) } ?? .failure(.notFound)
    }
}
