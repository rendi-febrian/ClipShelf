import Foundation

enum ShareRetention: String, CaseIterable, Identifiable {
    case oneDay = "1d"
    case sevenDays = "7d"
    case thirtyDays = "30d"
    case never

    var id: String { rawValue }

    var title: String {
        switch self {
        case .oneDay: return "1 hari"
        case .sevenDays: return "7 hari"
        case .thirtyDays: return "30 hari"
        case .never: return "Never"
        }
    }

    var confirmationDuration: String {
        self == .never ? "tanpa kedaluwarsa" : "selama \(title)"
    }

    var successDescription: String {
        self == .never ? "Link ini tidak akan kedaluwarsa." : "Link ini berlaku selama \(title)."
    }
}

enum ClipShelfShareClient {
    private static let endpoint = URL(string: "https://clipshelf.ild.my.id/api/v1/shares")!
    private static let maxImageBytes = 4_000_000

    static func createLink(for text: String, retention: ShareRetention) async throws -> URL {
        try await createLink(
            with: CreateShareRequest(text: text, imageBase64: nil, expiresIn: retention.rawValue),
            isImage: false
        )
    }

    static func createLink(for imageData: Data, retention: ShareRetention) async throws -> URL {
        guard imageData.count <= maxImageBytes else { throw ShareError.imageTooLarge }
        return try await createLink(
            with: CreateShareRequest(
                text: nil,
                imageBase64: imageData.base64EncodedString(),
                expiresIn: retention.rawValue
            ),
            isImage: true
        )
    }

    private static func createLink(with payload: CreateShareRequest, isImage: Bool) async throws -> URL {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(payload)

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
                throw isImage ? ShareError.imageTooLarge : ShareError.textTooLarge
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
    let text: String?
    let imageBase64: String?
    let expiresIn: String

    enum CodingKeys: String, CodingKey {
        case text
        case imageBase64 = "image_base64"
        case expiresIn = "expires_in"
    }
}

private struct CreateShareResponse: Decodable {
    let url: URL
}

private enum ShareError: LocalizedError {
    case unavailable
    case invalidResponse
    case textTooLarge
    case imageTooLarge
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
        case .imageTooLarge:
            return "Gambar terlalu besar untuk dibagikan sebagai link."
        case .rateLimited:
            return "Terlalu banyak link dibuat dari jaringan ini. Coba lagi nanti."
        case .requestRejected(let statusCode):
            return "Layanan ClipShelf Share menolak permintaan (\(statusCode)). Coba lagi nanti."
        }
    }
}
