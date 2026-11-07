import SwiftUI

struct MessageBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if message.role == .user {
                Spacer(minLength: 80)
            }
            VStack(alignment: message.role == .user ? HorizontalAlignment.trailing : .leading, spacing: 3) {
                Text(displayText)
                    .textSelection(.enabled)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(bubbleColor, in: RoundedRectangle(cornerRadius: 12))
                Text(message.createdAt, style: .time)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            if message.role == .assistant {
                Spacer(minLength: 80)
            }
        }
        .padding(.horizontal, 14)
    }

    private var displayText: String {
        if message.content.isEmpty && message.role == .assistant {
            return "正在思考…"
        }
        return message.content
    }

    private var bubbleColor: Color {
        message.role == .user ? Color.accentColor.opacity(0.22) : Color.gray.opacity(0.14)
    }
}

extension View {
    /// 绑定 String? 错误信息的通用 alert。
    func errorAlert(_ message: Binding<String?>) -> some View {
        alert(
            "出错了",
            isPresented: Binding(
                get: { message.wrappedValue != nil },
                set: { presented in
                    if !presented {
                        message.wrappedValue = nil
                    }
                }
            ),
            actions: {
                Button("好", role: .cancel) {}
            },
            message: {
                Text(message.wrappedValue ?? "")
            }
        )
    }
}
