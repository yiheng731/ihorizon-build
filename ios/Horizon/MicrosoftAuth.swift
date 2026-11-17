import Foundation
import Security
import UIKit

struct Account {
    let name: String
    let uuid: String
    let accessToken: String
}

enum AuthError: LocalizedError {
    case http(Int, String)
    case noProfile
    case xbox(String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case let .http(code, body):
            return "服务器返回 \(code)\(body.isEmpty ? "" : "：\(body.prefix(160))")"
        case .noProfile:
            return "这个微软账号没有 Minecraft: Java Edition"
        case let .xbox(detail):
            return detail
        case .cancelled:
            return "已取消"
        }
    }
}

final class MicrosoftAuth {

    static let clientID = "00000000402b5328"
    static let scopes = "XboxLive.signin offline_access"

    private static let service = "ihorizon.account"

    static var documents: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    static var sessionFile: URL { documents.appendingPathComponent("session.json") }

    static func load() -> Account? {
        guard let data = readKeychain(),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: String],
              let name = json["name"], let uuid = json["uuid"], let token = json["access_token"]
        else { return nil }
        return Account(name: name, uuid: uuid, accessToken: token)
    }

    static func writeSessionFile(_ account: Account?) {
        let path = sessionFile
        guard let account else {
            try? FileManager.default.removeItem(at: path)
            return
        }
        let json: [String: String] = [
            "name": account.name,
            "uuid": account.uuid,
            "access_token": account.accessToken,
            "user_type": "msa",
        ]
        if let data = try? JSONSerialization.data(withJSONObject: json) {
            try? data.write(to: path, options: .atomic)
        }
    }

    static func signOut() {
        deleteKeychain()
        writeSessionFile(nil)
    }

    @MainActor
    static func signIn(progress: @MainActor @escaping (String) -> Void) async throws -> Account {
        let device = try await requestDeviceCode()
        progress("在浏览器里打开 \(device.verification) 并输入 \(device.code)")
        if let url = URL(string: device.verification) {
            await UIApplication.shared.open(url)
        }
        let token = try await pollForToken(device)
        progress("已拿到微软账号，正在验证 Xbox 档案")
        let account = try await minecraftAccount(msToken: token)
        save(account)
        writeSessionFile(account)
        return account
    }

    private struct Device {
        let code: String
        let deviceCode: String
        let verification: String
        let interval: TimeInterval
        let expires: Date
    }

    private static func requestDeviceCode() async throws -> Device {
        var request = URLRequest(
            url: URL(string: "https://login.live.com/oauth20_connect.srf")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let encoded = scopes.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? scopes
        let body = "client_id=\(clientID)&scope=\(encoded)&response_type=device_code"
        request.httpBody = body.data(using: .utf8)
        let json = try await send(request)
        guard let code = json["user_code"] as? String,
              let deviceCode = json["device_code"] as? String,
              let verification = (json["verification_uri"] as? String)
                ?? (json["verification_url"] as? String)
        else {
            let detail = (json["error_description"] as? String) ?? "\(json)"
            throw AuthError.http(-1, "设备码响应缺少字段：\(detail.prefix(200))")
        }
        let interval = (json["interval"] as? Double) ?? 5
        let expires = (json["expires_in"] as? Double) ?? 900
        return Device(
            code: code,
            deviceCode: deviceCode,
            verification: verification,
            interval: interval,
            expires: Date().addingTimeInterval(expires)
        )
    }

    private static func pollForToken(_ device: Device) async throws -> String {
        while Date() < device.expires {
            try await Task.sleep(nanoseconds: UInt64(device.interval * 1_000_000_000))
            var request = URLRequest(
                url: URL(string: "https://login.live.com/oauth20_token.srf")!)
            request.httpMethod = "POST"
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            let body = [
                "grant_type=urn:ietf:params:oauth:grant-type:device_code",
                "client_id=\(clientID)",
                "device_code=\(device.deviceCode)",
            ].joined(separator: "&")
            request.httpBody = body.data(using: .utf8)
            do {
                let json = try await send(request)
                if let token = json["access_token"] as? String { return token }
            } catch let AuthError.http(_, body) {
                if body.contains("authorization_pending") { continue }
                if body.contains("slow_down") {
                    try await Task.sleep(nanoseconds: 5_000_000_000)
                    continue
                }
                if body.contains("expired_token") { throw AuthError.cancelled }
                throw AuthError.http(-1, body)
            }
        }
        throw AuthError.cancelled
    }

    private static func minecraftAccount(msToken: String) async throws -> Account {
        var xblRequest = URLRequest(url: URL(string: "https://user.auth.xboxlive.com/user/authenticate")!)
        xblRequest.httpMethod = "POST"
        xblRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        xblRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        xblRequest.httpBody = try JSONSerialization.data(withJSONObject: [
            "Properties": [
                "AuthMethod": "RPL",
                "SiteName": "user.auth.xboxlive.com",
                "RpsTicket": "d=\(msToken)",
            ],
            "RelyingParty": "http://auth.xboxlive.com",
            "TokenType": "JWT",
        ])
        let xbl = try await send(xblRequest)
        guard let xblToken = xbl["Token"] as? String,
              let xui = (xbl["DisplayClaims"] as? [String: Any])?["xui"] as? [[String: Any]],
              let uhs = xui.first?["uhs"] as? String
        else { throw AuthError.xbox("Xbox Live 没有返回令牌") }

        var xstsRequest = URLRequest(url: URL(string: "https://xsts.auth.xboxlive.com/xsts/authorize")!)
        xstsRequest.httpMethod = "POST"
        xstsRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        xstsRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        xstsRequest.httpBody = try JSONSerialization.data(withJSONObject: [
            "Properties": ["SandboxId": "RETAIL", "UserTokens": [xblToken]],
            "RelyingParty": "rp://api.minecraftservices.com/",
            "TokenType": "JWT",
        ])
        let xsts: [String: Any]
        do {
            xsts = try await send(xstsRequest)
        } catch let AuthError.http(code, body) {
            if code == 401, body.contains("2148916233") {
                throw AuthError.xbox("这个微软账号还没有 Xbox 档案，请先在 xbox.com 创建")
            }
            if code == 401, body.contains("2148916238") {
                throw AuthError.xbox("未成年人账号需要家长加入家庭组")
            }
            throw AuthError.http(code, body)
        }
        guard let xstsToken = xsts["Token"] as? String else {
            throw AuthError.xbox("XSTS 没有返回令牌")
        }

        var mcRequest = URLRequest(
            url: URL(string: "https://api.minecraftservices.com/authentication/login_with_xbox")!)
        mcRequest.httpMethod = "POST"
        mcRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        mcRequest.httpBody = try JSONSerialization.data(withJSONObject: [
            "identityToken": "XBL3.0 x=\(uhs);\(xstsToken)",
        ])
        let mc = try await send(mcRequest)
        guard let mcToken = mc["access_token"] as? String else {
            throw AuthError.xbox("Minecraft 服务没有返回令牌")
        }

        var profileRequest = URLRequest(
            url: URL(string: "https://api.minecraftservices.com/minecraft/profile")!)
        profileRequest.setValue("Bearer \(mcToken)", forHTTPHeaderField: "Authorization")
        let profile: [String: Any]
        do {
            profile = try await send(profileRequest)
        } catch {
            throw AuthError.noProfile
        }
        guard let name = profile["name"] as? String, let id = profile["id"] as? String else {
            throw AuthError.noProfile
        }
        return Account(name: name, uuid: id, accessToken: mcToken)
    }

    private static func send(_ request: URLRequest) async throws -> [String: Any] {
        let (data, response) = try await URLSession.shared.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? -1
        let text = String(data: data, encoding: .utf8) ?? ""
        guard (200..<300).contains(code) else { throw AuthError.http(code, text) }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AuthError.http(code, text)
        }
        return json
    }

    static func avatarURL(_ uuid: String) -> URL? {
        URL(string: "https://mc-heads.net/avatar/\(uuid)/128")
    }

    private static func save(_ account: Account) {
        let json: [String: String] = [
            "name": account.name,
            "uuid": account.uuid,
            "access_token": account.accessToken,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: json) else { return }
        deleteKeychain()
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: accountKey,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    private static let accountKey = "primary"

    private static func readKeychain() -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: accountKey,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess else { return nil }
        return item as? Data
    }

    private static func deleteKeychain() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: accountKey,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
