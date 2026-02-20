import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum TeamAPIConstants {
    public static let defaultServerBaseURL = URL(string: "https://ukuxfyfawzdiddzogpeu.supabase.co")!
    public static let redeemInvitePath = "/functions/v1/redeem_invite"
    public static let reportUsagePath = "/functions/v1/report_usage"
}

public struct TeamRedeemInviteRequest: Codable, Sendable {
    public let inviteCode: String
    public let deviceLabel: String
    public let platform: String
    public let appVersion: String

    public init(inviteCode: String, deviceLabel: String, platform: String, appVersion: String) {
        self.inviteCode = inviteCode
        self.deviceLabel = deviceLabel
        self.platform = platform
        self.appVersion = appVersion
    }

    private enum CodingKeys: String, CodingKey {
        case inviteCode = "invite_code"
        case deviceLabel = "device_label"
        case platform
        case appVersion = "app_version"
    }
}

public struct TeamRedeemInviteResponse: Decodable, Sendable {
    public struct Team: Codable, Sendable {
        public let id: String
        public let name: String

        public init(id: String, name: String) {
            self.id = id
            self.name = name
        }
    }

    public struct Member: Codable, Sendable {
        public let publicID: String

        public init(publicID: String) {
            self.publicID = publicID
        }

        private enum CodingKeys: String, CodingKey {
            case publicID = "public_id"
        }
    }

    public struct Device: Codable, Sendable {
        public let id: String
        public let deviceLabel: String
        public let platform: String
        public let appVersion: String

        public init(id: String, deviceLabel: String, platform: String, appVersion: String) {
            self.id = id
            self.deviceLabel = deviceLabel
            self.platform = platform
            self.appVersion = appVersion
        }

        private enum CodingKeys: String, CodingKey {
            case id
            case deviceLabel = "device_label"
            case platform
            case appVersion = "app_version"
        }
    }

    public struct Reporting: Codable, Sendable {
        public let token: String
        public let recommendedIntervalSeconds: Int?

        public init(token: String, recommendedIntervalSeconds: Int?) {
            self.token = token
            self.recommendedIntervalSeconds = recommendedIntervalSeconds
        }

        private enum CodingKeys: String, CodingKey {
            case token
            case recommendedIntervalSeconds = "recommended_interval_seconds"
        }
    }

    public struct Claim: Codable, Sendable {
        public let claimCode: String?
        public let expiresAt: String?
        public let claimPage: String?

        public init(claimCode: String?, expiresAt: String?, claimPage: String?) {
            self.claimCode = claimCode
            self.expiresAt = expiresAt
            self.claimPage = claimPage
        }

        private enum CodingKeys: String, CodingKey {
            case claimCode = "claim_code"
            case expiresAt = "expires_at"
            case claimPage = "claim_page"
        }
    }

    public let team: Team
    public let member: Member
    public let device: Device
    public let reporting: Reporting?
    public let deviceToken: String
    public let claim: Claim?

    public init(
        team: Team,
        member: Member,
        device: Device,
        reporting: Reporting?,
        claim: Claim?,
        deviceToken: String? = nil)
    {
        self.team = team
        self.member = member
        self.device = device
        self.reporting = reporting
        let directToken = deviceToken?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let fallbackToken = reporting?.token.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self.deviceToken = directToken.isEmpty ? fallbackToken : directToken
        self.claim = claim
    }

    private enum CodingKeys: String, CodingKey {
        case team
        case member
        case device
        case reporting
        case claim
        case deviceToken = "device_token"
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let team = try container.decode(Team.self, forKey: .team)
        let member = try container.decode(Member.self, forKey: .member)
        let device = try container.decode(Device.self, forKey: .device)
        let reporting = try container.decodeIfPresent(Reporting.self, forKey: .reporting)
        let claim = try container.decodeIfPresent(Claim.self, forKey: .claim)
        let deviceToken = try container.decodeIfPresent(String.self, forKey: .deviceToken)

        self.init(
            team: team,
            member: member,
            device: device,
            reporting: reporting,
            claim: claim,
            deviceToken: deviceToken)
    }
}

public enum TeamReportPostResult: Sendable, Equatable {
    case ok
    case duplicate
}

public enum TeamAPIClientError: LocalizedError, Sendable, Equatable {
    case invalidResponse
    case unauthorized
    case throttled(retryAfterSeconds: TimeInterval?)
    case serverStatus(code: Int, message: String?)
    case decodingFailed(message: String)

    public var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Team server returned an invalid response."
        case .unauthorized:
            return "Team reporting credentials were rejected."
        case let .throttled(retryAfterSeconds):
            if let retryAfterSeconds {
                return "Team server throttled this report. Retry in \(Int(retryAfterSeconds))s."
            }
            return "Team server throttled this report."
        case let .serverStatus(code, message):
            if let message, !message.isEmpty {
                return "Team server error (\(code)): \(message)"
            }
            return "Team server error (\(code))."
        case let .decodingFailed(message):
            return "Team server response decode failed: \(message)"
        }
    }
}

public struct TeamAPIClient: Sendable {
    public typealias DataLoader = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    private let dataLoader: DataLoader
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(
        dataLoader: @escaping DataLoader = { request in
            try await URLSession.shared.data(for: request)
        },
        encoder: JSONEncoder? = nil,
        decoder: JSONDecoder? = nil)
    {
        self.dataLoader = dataLoader
        self.encoder = encoder ?? Self.makeJSONEncoder()
        self.decoder = decoder ?? Self.makeJSONDecoder()
    }

    public func redeemInvite(
        baseURL: URL,
        payload: TeamRedeemInviteRequest) async throws -> TeamRedeemInviteResponse
    {
        var request = URLRequest(url: self.endpoint(baseURL: baseURL, path: TeamAPIConstants.redeemInvitePath))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try self.encoder.encode(payload)

        let (data, response) = try await self.dataLoader(request)
        let httpResponse = try self.parseHTTPResponse(response)
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw self.apiError(httpResponse: httpResponse, data: data)
        }

        do {
            return try self.decoder.decode(TeamRedeemInviteResponse.self, from: data)
        } catch {
            throw TeamAPIClientError.decodingFailed(message: error.localizedDescription)
        }
    }

    public func reportUsage(
        baseURL: URL,
        bearerToken: String,
        deviceID: String?,
        payloadData: Data) async throws -> TeamReportPostResult
    {
        var request = URLRequest(url: self.endpoint(baseURL: baseURL, path: TeamAPIConstants.reportUsagePath))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        if let deviceID, !deviceID.isEmpty {
            request.setValue(deviceID, forHTTPHeaderField: "X-CodexBar-Device-ID")
        }
        request.httpBody = payloadData

        let (data, response) = try await self.dataLoader(request)
        let httpResponse = try self.parseHTTPResponse(response)
        switch httpResponse.statusCode {
        case 200..<300:
            return .ok
        case 409:
            return .duplicate
        default:
            throw self.apiError(httpResponse: httpResponse, data: data)
        }
    }
}

extension TeamAPIClient {
    fileprivate static func makeJSONEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    fileprivate static func makeJSONDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private func endpoint(baseURL: URL, path: String) -> URL {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            return baseURL.appendingPathComponent(path)
        }
        let cleanedPath = path.hasPrefix("/") ? String(path.dropFirst()) : path
        let basePath = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        components.path = "/" + [basePath, cleanedPath].filter { !$0.isEmpty }.joined(separator: "/")
        return components.url ?? baseURL.appendingPathComponent(cleanedPath)
    }

    private func parseHTTPResponse(_ response: URLResponse) throws -> HTTPURLResponse {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw TeamAPIClientError.invalidResponse
        }
        return httpResponse
    }

    private func apiError(httpResponse: HTTPURLResponse, data: Data) -> TeamAPIClientError {
        let statusCode = httpResponse.statusCode
        switch statusCode {
        case 401, 403:
            return .unauthorized
        case 429:
            return .throttled(retryAfterSeconds: self.parseRetryAfter(headerValue: httpResponse.value(
                forHTTPHeaderField: "Retry-After")))
        default:
            break
        }

        return .serverStatus(code: statusCode, message: self.extractServerMessage(data: data))
    }

    private func parseRetryAfter(headerValue: String?) -> TimeInterval? {
        guard let headerValue else { return nil }
        let trimmed = headerValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let seconds = TimeInterval(trimmed) {
            return max(0, seconds)
        }
        return nil
    }

    private func extractServerMessage(data: Data) -> String? {
        guard !data.isEmpty else { return nil }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        if let message = object["message"] as? String {
            return message.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let error = object["error"] as? String {
            return error.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let errorObj = object["error"] as? [String: Any],
           let message = errorObj["message"] as? String
        {
            return message.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }
}
