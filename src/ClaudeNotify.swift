import Cocoa
import UserNotifications

class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}

// 解析命令行参数
var title = "Claude Code"
var message = "任务已完成"
let args = CommandLine.arguments
var i = 1
while i < args.count {
    switch args[i] {
    case "-title":
        i += 1; if i < args.count { title = args[i] }
    case "-message":
        i += 1; if i < args.count { message = args[i] }
    default: break
    }
    i += 1
}

// 启动应用（不显示 Dock 图标）
let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let delegate = NotificationDelegate()
let center = UNUserNotificationCenter.current()
center.delegate = delegate

// 请求权限并发送通知
center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
    guard granted else {
        exit(1)
    }

    let content = UNMutableNotificationContent()
    content.title = title
    content.body = message
    content.sound = .default

    let request = UNNotificationRequest(
        identifier: UUID().uuidString,
        content: content,
        trigger: nil
    )

    center.add(request) { error in
        if let error = error {
            fputs("Error: \(error.localizedDescription)\n", stderr)
        }
        // 延迟退出，确保通知发出
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            exit(0)
        }
    }
}

// 运行事件循环
app.run()
