import Foundation

enum ClipShelfShareClient {
    private static let endpoint = URL(string: "https://clipshelf.ild.my.id/api/v1/shares")!

    static func createLink(for text: String) async throws -> URL {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(CreateShareRequest(text: text))

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw ShareError.unavailable
        }

        guard let response = response as? HTTPURLResponse else {
            throw ShareError.invalidResponse
        }
        guard response.statusCode == 201 else {
            if response.statusCode == 413 {
                throw ShareError.textTooLarge
            }
            if response.statusCode == 429 {
                throw ShareError.rateLimited
            }
            throw ShareError.requestRejected(response.statusCode)
        }

        guard let share = try? JSONDecoder().decode(CreateShareResponse.self, from: data),
              share.url.scheme == "https",
              share.url.host == "clipshelf.ild.my.id",
              share.url.path.hasPrefix("/clip/share/") else {
            throw ShareError.invalidResponse
        }

        return share.url
    }
}

private struct CreateShareRequest: Encodable {
    let text: String
}

private struct CreateShareResponse: Decodable {
    let url: URL
}

private enum ShareError: LocalizedError {
    case unavailable
    case invalidResponse
    case textTooLarge
    case rateLimited
    case requestRejected(Int)

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "Tidak bisa terhubung ke layanan ClipShelf Share. Coba lagi nanti."
        case .invalidResponse:
            return "Layanan ClipShelf Share mengirim jawaban yang tidak dikenali."
        case .textTooLarge:
            return "Teks terlalu besar untuk dibagikan sebagai link."
        case .rateLimited:
            return "Terlalu banyak link dibuat dari jaringan ini. Coba lagi nanti."
        case .requestRejected(let statusCode):
            return "Layanan ClipShelf Share menolak permintaan (\(statusCode)). Coba lagi nanti."
        }
    }
}
