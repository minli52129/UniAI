import Foundation

struct APIConfig {
    var baseURL: String
    var apiKey: String
}

/// 极简 OpenAI 兼容 HTTP 客户端：JSON、SSE 流式、multipart 上传。
struct APIClient {
    let config: APIConfig

    private func url(path: String) throws -> URL {
        var base = config.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if base.isEmpty {
            throw APIError(message: "尚未配置服务端地址（Base URL），请先到「设置」填写。")
        }
        if !base.hasPrefix("http://") && !base.hasPrefix("https://") {
            base = "https://" + base
        }
        while base.hasSuffix("/") { base.removeLast() }
        let suffix = path.hasPrefix("/") ? String(path.dropFirst()) : path
        guard let url = URL(string: base + "/" + suffix) else {
            throw APIError(message: "无法构造请求地址：\(base)/\(suffix)")
        }
        return url
    }

    private func makeRequest(path: String, method: String, body: Data?, contentType: String?) throws -> URLRequest {
        var request = URLRequest(url: try url(path: path))
        request.httpMethod = method
        // 请求级超时指“数据间隔”空闲时间，长流式输出和视频轮询不会误伤
        request.timeoutInterval = 300
        if !config.apiKey.isEmpty {
            request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        }
        if let contentType {
            request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        }
        request.httpBody = body
        return request
    }

    // MARK: - JSON / 二进制

    func postData(_ path: String, json: Data) async throws -> Data {
        let request = try makeRequest(path: path, method: "POST", body: json, contentType: "application/json")
        let (data, response) = try await URLSession.shared.data(for: request)
        return try Self.validate(data: data, response: response)
    }

    func getData(_ path: String) async throws -> Data {
        let request = try makeRequest(path: path, method: "GET", body: nil, contentType: nil)
        let (data, response) = try await URLSession.shared.data(for: request)
        return try Self.validate(data: data, response: response)
    }

    func postMultipart(_ path: String, form: MultipartBody) async throws -> Data {
        let request = try makeRequest(path: path, method: "POST", body: form.finalized, contentType: form.contentType)
        let (data, response) = try await URLSession.shared.data(for: request)
        return try Self.validate(data: data, response: response)
    }

    // MARK: - SSE 流式

    func streamSSE(_ path: String, json: Data) -> AsyncThrowingStream<Data, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let request = try makeRequest(path: path, method: "POST", body: json, contentType: "application/json")
                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                        var buffered = Data()
                        for try await byte in bytes {
                            buffered.append(byte)
                            if buffered.count > 8_192 { break }
                        }
                        throw APIError(message: Self.errorText(buffered, status: http.statusCode))
                    }
                    for try await line in bytes.lines {
                        guard line.hasPrefix("data:") else { continue }
                        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                        if payload.isEmpty { continue }
                        if payload == "[DONE]" { break }
                        if let data = payload.data(using: .utf8) {
                            continuation.yield(data)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - 响应校验与错误解析

    static func validate(data: Data, response: URLResponse) throws -> Data {
        guard let http = response as? HTTPURLResponse else {
            throw APIError(message: "无效的网络响应")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw APIError(message: errorText(data, status: http.statusCode))
        }
        return data
    }

    static func errorText(_ data: Data, status: Int) -> String {
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let error = object["error"] as? [String: Any],
               let message = (error["message"] as? String) ?? (error["msg"] as? String) {
                return "HTTP \(status)：\(message)"
            }
            if let message = (object["message"] as? String)
                ?? (object["msg"] as? String)
                ?? (object["error"] as? String) {
                return "HTTP \(status)：\(message)"
            }
        }
        let raw = String(data: data.prefix(500), encoding: .utf8) ?? ""
        return raw.isEmpty ? "HTTP \(status)" : "HTTP \(status)：\(raw)"
    }

    /// 解析流式过程中的错误事件（部分服务在流中返回 {"error": ...}）。
    static func streamErrorText(from data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        if let error = object["error"] {
            if let dict = error as? [String: Any],
               let message = (dict["message"] as? String) ?? (dict["msg"] as? String) {
                return message
            }
            if let message = error as? String { return message }
        }
        if object["choices"] == nil,
           let message = (object["message"] as? String) ?? (object["msg"] as? String) {
            return message
        }
        return nil
    }
}

struct MultipartBody {
    let boundary = "UniAI-" + UUID().uuidString
    private(set) var data = Data()

    var contentType: String { "multipart/form-data; boundary=\(boundary)" }

    mutating func addField(_ name: String, _ value: String) {
        data.append(Data("--\(boundary)\r\n".utf8))
        data.append(Data("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".utf8))
        data.append(Data(value.utf8))
        data.append(Data("\r\n".utf8))
    }

    mutating func addFile(_ name: String, filename: String, mimeType: String, content: Data) {
        data.append(Data("--\(boundary)\r\n".utf8))
        data.append(Data("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n".utf8))
        data.append(Data("Content-Type: \(mimeType)\r\n\r\n".utf8))
        data.append(content)
        data.append(Data("\r\n".utf8))
    }

    var finalized: Data {
        var all = data
        all.append(Data("--\(boundary)--\r\n".utf8))
        return all
    }
}
