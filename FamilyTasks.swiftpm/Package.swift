// swift-tools-version: 5.9

// Формат App Playground: этот же пакет открывается в Swift Playgrounds на iPad,
// собирается на macOS-раннере в CI и, если однажды появится Mac, открывается
// в Xcode без конвертации.
//
// AppleProductTypes поставляется вместе с Xcode и Swift Playgrounds.
// Обычный `swift build` этот манифест не поймёт — сборка только через xcodebuild.

import AppleProductTypes
import PackageDescription

let package = Package(
    name: "FamilyTasks",
    platforms: [
        // SwiftData и @Observable требуют iOS 17.
        .iOS("17.0")
    ],
    products: [
        .iOSApplication(
            name: "FamilyTasks",
            targets: ["AppModule"],
            // TODO: заменить на реальный идентификатор перед первой сборкой в App Store.
            // Он же используется как ключ Keychain в AppConfig.keychainService —
            // менять его после установки на устройство значит разлогинить пользователя.
            bundleIdentifier: "com.yourcompany.familytasks",
            teamIdentifier: "",
            displayVersion: "1.0",
            bundleVersion: "1",
            accentColor: .presetColor(.blue),
            supportedDeviceFamilies: [.phone, .pad],
            supportedInterfaceOrientations: [
                .portrait,
                .landscapeRight,
                .landscapeLeft,
                .portraitUpsideDown(.when(deviceFamilies: [.pad]))
            ]
        )
    ],
    targets: [
        .executableTarget(
            name: "AppModule",
            path: ".",
            // Шрифты Organic: Caprasimo и Figtree. Регистрируются в рантайме
            // через CTFontManager — см. Theme.registerFonts().
            resources: [.process("Resources")]
        )
    ]
)
