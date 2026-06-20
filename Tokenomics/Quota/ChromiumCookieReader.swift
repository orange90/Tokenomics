import Foundation
import Security
import CommonCrypto
import CryptoKit

enum ChromiumBrowser: String, CaseIterable, Identifiable, Codable {
    case chrome
    case brave

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .chrome: return "Chrome"
        case .brave:  return "Brave"
        }
    }

    fileprivate var userDataDir: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        switch self {
        case .chrome:
            return home.appendingPathComponent("Library/Application Support/Google/Chrome", isDirectory: true)
        case .brave:
            return home.appendingPathComponent("Library/Application Support/BraveSoftware/Brave-Browser", isDirectory: true)
        }
    }

    fileprivate var safeStorageService: String {
        switch self {
        case .chrome: return "Chrome Safe Storage"
        case .brave:  return "Brave Safe Storage"
        }
    }

    fileprivate var safeStorageAccount: String {
        switch self {
        case .chrome: return "Chrome"
        case .brave:  return "Brave"
        }
    }
}

enum ChromiumCookieError: LocalizedError {
    case browserNotInstalled(ChromiumBrowser)
    case noCookiesFile(ChromiumBrowser)
    case sqliteUnavailable
    case sqliteFailed(String)
    case noSessionKey(ChromiumBrowser)
    case keychainMissing(ChromiumBrowser)
    case keychainDenied(ChromiumBrowser, OSStatus)
    case decryptFailed(String)

    var errorDescription: String? {
        switch self {
        case .browserNotInstalled(let b): return L10n.tr("browser.not_installed.fmt", b.displayName)
        case .noCookiesFile(let b):       return L10n.tr("browser.no_cookies.fmt", b.displayName)
        case .sqliteUnavailable:           return L10n.tr("browser.sqlite_unavailable")
        case .sqliteFailed(let m):         return L10n.tr("browser.sqlite_failed.fmt", m)
        case .noSessionKey(let b):         return L10n.tr("browser.no_session_key.fmt", b.displayName)
        case .keychainMissing(let b):      return L10n.tr("browser.keychain_missing.fmt", b.displayName)
        case .keychainDenied(let b, let s):return L10n.tr("browser.keychain_denied.fmt", b.displayName, String(s))
        case .decryptFailed(let m):        return L10n.tr("browser.decrypt_failed.fmt", m)
        }
    }
}

/// 从本地 Chromium 系（Chrome / Brave）浏览器读取 claude.ai 的 sessionKey。
///
/// 流程：
///   1. 枚举所有 profile 下的 `Cookies` SQLite（含 Default / Profile 1 / …）。
///   2. SQLite 文件常被浏览器持锁，所以**先拷贝到临时目录**再读，避免 SQLITE_BUSY。
///   3. 通过 `/usr/bin/sqlite3` 子进程执行 `SELECT host_key, encrypted_value FROM cookies WHERE name='sessionKey'`。
///   4. encrypted_value 以 3 字节前缀标识版本：
///        - `v10` → AES-128-CBC，密钥来自 Keychain "<Browser> Safe Storage"（PBKDF2-HMAC-SHA1, salt="saltysalt", iter=1003）。
///        - `v20` → App-Bound Encryption (Chrome 127+)：先解开 `Local State.os_crypt.app_bound_encrypted_key`，再用得到的 AES-256-GCM key 解 cookie。
///   5. 返回解密后的 sessionKey 字符串。
final class ChromiumCookieReader {

    struct ImportedCookie {
        let browser: ChromiumBrowser
        let profile: String           // "Default" / "Profile 1" 等
        let sessionKey: String        // sk-ant-...
        let hostKey: String           // ".claude.ai"
    }

    /// 顺序探测多个浏览器，返回第一个成功解出的 sessionKey。
    func readSessionKey(preferred: [ChromiumBrowser] = ChromiumBrowser.allCases) -> Result<ImportedCookie, ChromiumCookieError> {
        var lastError: ChromiumCookieError = .browserNotInstalled(preferred.first ?? .chrome)
        for browser in preferred {
            switch readSessionKey(from: browser) {
            case .success(let cookie):
                return .success(cookie)
            case .failure(let err):
                lastError = err
                continue
            }
        }
        return .failure(lastError)
    }

    func readSessionKey(from browser: ChromiumBrowser) -> Result<ImportedCookie, ChromiumCookieError> {
        let userDataDir = browser.userDataDir
        guard FileManager.default.fileExists(atPath: userDataDir.path) else {
            return .failure(.browserNotInstalled(browser))
        }

        let profiles = enumerateProfiles(in: userDataDir)
        guard !profiles.isEmpty else {
            return .failure(.noCookiesFile(browser))
        }

        // 取 Keychain 密钥；v10 + v20 都要用到
        let safeStorageKey: Data
        switch readSafeStorageKey(browser: browser) {
        case .success(let k): safeStorageKey = k
        case .failure(let e): return .failure(e)
        }

        // 预读 Local State（v20 解 ABE 用），失败不致命
        let appBoundKey: Data? = readAppBoundKey(in: userDataDir, safeStorageKey: safeStorageKey)

        var lastError: ChromiumCookieError = .noSessionKey(browser)
        for profile in profiles {
            let cookiesURL = profile.appendingPathComponent("Cookies")
            guard FileManager.default.fileExists(atPath: cookiesURL.path) else { continue }

            let rows: [(host: String, encrypted: Data)]
            switch querySessionKeyRows(cookiesURL: cookiesURL) {
            case .success(let r): rows = r
            case .failure(let e): lastError = e; continue
            }
            if rows.isEmpty { continue }

            for row in rows {
                switch decryptCookieValue(encrypted: row.encrypted,
                                          safeStorageKey: safeStorageKey,
                                          appBoundKey: appBoundKey) {
                case .success(let value) where !value.isEmpty:
                    return .success(ImportedCookie(
                        browser: browser,
                        profile: profile.lastPathComponent,
                        sessionKey: value,
                        hostKey: row.host
                    ))
                case .success:
                    continue
                case .failure(let e):
                    lastError = e
                    continue
                }
            }
        }
        return .failure(lastError)
    }

    // MARK: - Profile 枚举

    private func enumerateProfiles(in userDataDir: URL) -> [URL] {
        let fm = FileManager.default
        guard let children = try? fm.contentsOfDirectory(at: userDataDir,
                                                         includingPropertiesForKeys: [.isDirectoryKey],
                                                         options: [.skipsHiddenFiles]) else { return [] }
        var result: [URL] = []
        for child in children {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: child.path, isDirectory: &isDir), isDir.boolValue else { continue }
            let name = child.lastPathComponent
            // 典型 profile 目录：Default / Profile 1 / Profile 2 / Guest Profile / ...
            if name == "Default" || name.hasPrefix("Profile ") {
                result.append(child)
            }
        }
        // 让 Default 排在最前，常见 sessionKey 多在那里
        return result.sorted { a, b in
            if a.lastPathComponent == "Default" { return true }
            if b.lastPathComponent == "Default" { return false }
            return a.lastPathComponent < b.lastPathComponent
        }
    }

    // MARK: - SQLite 读取（通过 /usr/bin/sqlite3 子进程）

    /// 将 Cookies 拷贝到临时目录，避免读被锁住。返回每条 sessionKey 的 (host, encryptedValue) 列表。
    private func querySessionKeyRows(cookiesURL: URL) -> Result<[(host: String, encrypted: Data)], ChromiumCookieError> {
        let sqlite = "/usr/bin/sqlite3"
        guard FileManager.default.isExecutableFile(atPath: sqlite) else {
            return .failure(.sqliteUnavailable)
        }

        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("tokenomics-cookies-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        } catch {
            return .failure(.sqliteFailed("无法创建临时目录: \(error.localizedDescription)"))
        }
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let copyURL = tmpDir.appendingPathComponent("Cookies")
        do {
            try FileManager.default.copyItem(at: cookiesURL, to: copyURL)
            // WAL / SHM 也尽量拷一份（如果存在）
            for ext in ["-wal", "-shm"] {
                let src = cookiesURL.appendingPathExtension(String(ext.dropFirst()))
                if FileManager.default.fileExists(atPath: src.path) {
                    let dst = copyURL.appendingPathExtension(String(ext.dropFirst()))
                    try? FileManager.default.copyItem(at: src, to: dst)
                }
            }
        } catch {
            return .failure(.sqliteFailed("拷贝 Cookies 失败: \(error.localizedDescription)"))
        }

        // 用 hex(encrypted_value) 把 BLOB 转十六进制，| 作为列分隔避免冲突。
        // 注意：list 模式与分隔符必须用命令行 flag（-list / -separator）传入，
        // **不能**把 `.mode list` / `.separator |` 这类点命令塞进 SQL 参数里——
        // sqlite3 会把分隔符当成多余参数报错（"extra argument: |"），导致整条备用路失败。
        let sql = "SELECT host_key, hex(encrypted_value) FROM cookies"
            + " WHERE name = 'sessionKey' AND host_key LIKE '%claude.ai';"

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: sqlite)
        // -readonly + immutable=1：避免触发 SQLite 写锁
        proc.arguments = ["-readonly", "-list", "-separator", "|",
                          "file:\(copyURL.path)?immutable=1", sql]
        let outPipe = Pipe(), errPipe = Pipe()
        proc.standardOutput = outPipe
        proc.standardError = errPipe

        do {
            try proc.run()
        } catch {
            return .failure(.sqliteFailed("启动 sqlite3 失败: \(error.localizedDescription)"))
        }
        proc.waitUntilExit()

        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        if proc.terminationStatus != 0 {
            let msg = String(data: errData, encoding: .utf8) ?? "exit=\(proc.terminationStatus)"
            return .failure(.sqliteFailed(msg))
        }

        guard let text = String(data: outData, encoding: .utf8) else {
            return .success([])
        }
        var rows: [(host: String, encrypted: Data)] = []
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            let parts = line.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else { continue }
            let host = String(parts[0])
            let hexStr = String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard let blob = Data(hexEncoded: hexStr) else { continue }
            rows.append((host: host, encrypted: blob))
        }
        return .success(rows)
    }

    // MARK: - 解密：v10 / v20 路由

    private func decryptCookieValue(encrypted: Data,
                                    safeStorageKey: Data,
                                    appBoundKey: Data?) -> Result<String, ChromiumCookieError> {
        guard encrypted.count > 3 else {
            return .failure(.decryptFailed("encrypted_value too short"))
        }
        let prefix = encrypted.prefix(3)
        let body = encrypted.subdata(in: 3..<encrypted.count)

        if prefix == Data("v10".utf8) {
            return decryptV10(body: body, key: safeStorageKey)
        }
        if prefix == Data("v20".utf8) {
            guard let abk = appBoundKey else {
                return .failure(.decryptFailed("v20 cookie 但 app-bound key 不可用"))
            }
            return decryptV20(body: body, key: abk)
        }
        return .failure(.decryptFailed("未知 cookie 加密前缀：\(String(data: prefix, encoding: .utf8) ?? "?")"))
    }

    // MARK: - v10：AES-128-CBC + PKCS7

    /// v10 = AES-128-CBC，IV 固定为 16 个 0x20，key 由 Keychain 密码经 PBKDF2 派生。
    private func decryptV10(body: Data, key: Data) -> Result<String, ChromiumCookieError> {
        let iv = Data(repeating: 0x20, count: 16)
        guard let plain = aesCBCDecrypt(cipherText: body, key: key, iv: iv) else {
            return .failure(.decryptFailed("v10 AES-CBC 解密失败"))
        }
        guard let s = String(data: plain, encoding: .utf8) else {
            return .failure(.decryptFailed("v10 解密后非 UTF-8"))
        }
        // Chromium v10 没有元数据前缀，直接就是 cookie 值
        return .success(s.trimmingCharacters(in: .controlCharacters))
    }

    // MARK: - v20：AES-256-GCM + 32 字节元数据前缀

    /// v20 cookie 结构（解开 ABE 拿到 32B AES key 之后）：
    ///   [nonce(12B)] [ciphertext+tag(N+16)]
    /// 解出明文后前 32B 是 "host_key + path + creation_time" 等元数据，cookie 真值从第 32 字节开始。
    /// 参考：Chromium src/components/os_crypt/sync/os_crypt_mac.mm 以及社区分析。
    private func decryptV20(body: Data, key: Data) -> Result<String, ChromiumCookieError> {
        guard body.count > 12 + 16 else {
            return .failure(.decryptFailed("v20 ciphertext too short"))
        }
        let nonce = body.prefix(12)
        let cipherWithTag = body.suffix(from: 12)
        guard let plain = aesGCMDecrypt(cipherWithTag: cipherWithTag, key: key, nonce: nonce) else {
            return .failure(.decryptFailed("v20 AES-GCM 解密失败"))
        }
        let value: Data
        if plain.count > 32 {
            value = plain.suffix(from: 32)
        } else {
            value = plain
        }
        guard let s = String(data: value, encoding: .utf8) else {
            return .failure(.decryptFailed("v20 解密后非 UTF-8"))
        }
        return .success(s.trimmingCharacters(in: .controlCharacters))
    }

    // MARK: - Keychain：Safe Storage 密码 → PBKDF2 派生 AES-128 key

    private func readSafeStorageKey(browser: ChromiumBrowser) -> Result<Data, ChromiumCookieError> {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: browser.safeStorageService,
            kSecAttrAccount as String: browser.safeStorageAccount,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnData as String: true
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound {
            return .failure(.keychainMissing(browser))
        }
        guard status == errSecSuccess, let data = item as? Data, let password = String(data: data, encoding: .utf8) else {
            return .failure(.keychainDenied(browser, status))
        }
        let derived = pbkdf2SHA1(password: password,
                                 salt: "saltysalt",
                                 iterations: 1003,
                                 keyLength: 16)
        return .success(derived)
    }

    // MARK: - v20：Local State 读取并解开 app-bound key

    /// `Local State` 中 `os_crypt.app_bound_encrypted_key` 是 base64 的 blob，
    /// 经过去掉 "APPB" magic 前缀后，**自身又是一个 v10 / v20 ciphertext**。
    /// macOS 上目前以 v10 包装居多（不像 Windows 走 OS-bound）。
    private func readAppBoundKey(in userDataDir: URL, safeStorageKey: Data) -> Data? {
        let localStateURL = userDataDir.appendingPathComponent("Local State")
        guard let data = try? Data(contentsOf: localStateURL),
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let osCrypt = root["os_crypt"] as? [String: Any],
              let b64 = osCrypt["app_bound_encrypted_key"] as? String,
              let raw = Data(base64Encoded: b64)
        else { return nil }

        // 去掉 "APPB" magic（4 字节）
        let magic = "APPB"
        let payload: Data
        if raw.count > magic.count, raw.prefix(magic.count) == Data(magic.utf8) {
            payload = raw.suffix(from: magic.count)
        } else {
            payload = raw
        }
        guard payload.count > 3 else { return nil }
        let prefix = payload.prefix(3)
        let body = payload.subdata(in: 3..<payload.count)
        if prefix == Data("v10".utf8) {
            let iv = Data(repeating: 0x20, count: 16)
            // 注意：这里输出可能是 32B 的 AES-256-GCM 原始 key
            return aesCBCDecrypt(cipherText: body, key: safeStorageKey, iv: iv)
        }
        // v20 解 app-bound 自身需要 OS Elevation Service，macOS 上极少见，先放弃
        return nil
    }

    // MARK: - CommonCrypto helpers

    private func aesCBCDecrypt(cipherText: Data, key: Data, iv: Data) -> Data? {
        let bufferSize = cipherText.count + kCCBlockSizeAES128
        var buffer = Data(count: bufferSize)
        var outLength: size_t = 0
        let status: CCCryptorStatus = buffer.withUnsafeMutableBytes { outBytes -> CCCryptorStatus in
            cipherText.withUnsafeBytes { inBytes in
                iv.withUnsafeBytes { ivBytes in
                    key.withUnsafeBytes { keyBytes in
                        CCCrypt(CCOperation(kCCDecrypt),
                                CCAlgorithm(kCCAlgorithmAES),
                                CCOptions(kCCOptionPKCS7Padding),
                                keyBytes.baseAddress, key.count,
                                ivBytes.baseAddress,
                                inBytes.baseAddress, cipherText.count,
                                outBytes.baseAddress, bufferSize,
                                &outLength)
                    }
                }
            }
        }
        guard status == kCCSuccess else { return nil }
        return buffer.prefix(outLength)
    }

    /// AES-256-GCM 解密。利用 CryptoKit 的 AES.GCM，因为 CommonCrypto 不支持 GCM。
    private func aesGCMDecrypt(cipherWithTag: Data, key: Data, nonce: Data) -> Data? {
        // 延迟到运行时按需 import；这里直接用 fully qualified API。
        // cipherWithTag = ciphertext(N) + tag(16)
        guard cipherWithTag.count >= 16 else { return nil }
        let tag = cipherWithTag.suffix(16)
        let ciphertext = cipherWithTag.prefix(cipherWithTag.count - 16)
        do {
            let sealed = try CryptoKitGCM.SealedBox(nonce: nonce, ciphertext: ciphertext, tag: tag)
            return try CryptoKitGCM.open(sealed, using: key)
        } catch {
            return nil
        }
    }

    private func pbkdf2SHA1(password: String, salt: String, iterations: Int, keyLength: Int) -> Data {
        var derived = Data(count: keyLength)
        let passwordBytes = Array(password.utf8)
        let saltBytes = Array(salt.utf8)
        let status: Int32 = derived.withUnsafeMutableBytes { outBytes -> Int32 in
            CCKeyDerivationPBKDF(
                CCPBKDFAlgorithm(kCCPBKDF2),
                passwordBytes, passwordBytes.count,
                saltBytes, saltBytes.count,
                CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1),
                UInt32(iterations),
                outBytes.baseAddress, keyLength
            )
        }
        return status == kCCSuccess ? derived : Data()
    }
}

// MARK: - CryptoKit GCM wrapper

private enum CryptoKitGCM {
    static func open(_ sealed: AES.GCM.SealedBox, using keyData: Data) throws -> Data {
        let key = SymmetricKey(data: keyData)
        return try AES.GCM.open(sealed, using: key)
    }
    typealias SealedBox = AES.GCM.SealedBox
}

extension AES.GCM.SealedBox {
    init(nonce: Data, ciphertext: Data, tag: Data) throws {
        try self.init(nonce: AES.GCM.Nonce(data: nonce), ciphertext: ciphertext, tag: tag)
    }
}

// MARK: - Hex string → Data

private extension Data {
    init?(hexEncoded hex: String) {
        let trimmed = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count % 2 == 0 else { return nil }
        var data = Data(capacity: trimmed.count / 2)
        var index = trimmed.startIndex
        while index < trimmed.endIndex {
            let next = trimmed.index(index, offsetBy: 2)
            guard let byte = UInt8(trimmed[index..<next], radix: 16) else { return nil }
            data.append(byte)
            index = next
        }
        self = data
    }
}
