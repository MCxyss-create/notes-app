import SwiftUI

// Этап 0: проверочный экран. Задача — убедиться, что приложение,
// собранное в GitHub Actions, ставится на iPhone и открывается.
struct ContentView: View {
    private var versionText: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "Версия \(version), сборка \(build)"
    }

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)

            Text("Работает")
                .font(.largeTitle.bold())

            Text(versionText)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text("Этап 0: собрано в GitHub Actions и установлено без Mac.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
