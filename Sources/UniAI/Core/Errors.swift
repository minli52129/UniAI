import Foundation

/// 统一的可展示错误类型：直接把 message 显示给用户。
struct APIError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}
