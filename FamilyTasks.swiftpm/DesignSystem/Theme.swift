import CoreText
import SwiftUI
import UIKit

/// Дизайн-система Organic в Swift.
///
/// Значения перенесены один в один из `_ds/organic-*/styles.css` — того же файла,
/// на котором собран прототип Claude Design. Менять их здесь и только здесь:
/// экраны обращаются к ролям (`Theme.background`), а не к литералам.
enum Theme {

    // MARK: - Палитра

    /// Базовые токены системы. Имена совпадают с CSS-переменными.
    private enum Token {
        static let bg = Color(hex: "#f5ead8")
        static let surface = Color(hex: "#ebddc5")
        static let text = Color(hex: "#201e1d")
        static let accent = Color(hex: "#c67139")
        static let accent2 = Color(hex: "#7a8a5e")

        static let neutral100 = Color(hex: "#f9f4ed")
        static let neutral200 = Color(hex: "#eee7db")
        static let neutral300 = Color(hex: "#dcd3c4")
        static let neutral400 = Color(hex: "#c0b6a5")
        static let neutral500 = Color(hex: "#a19786")
        static let neutral600 = Color(hex: "#82796a")
        static let neutral700 = Color(hex: "#645c50")
        static let neutral900 = Color(hex: "#2e2b25")

        static let accent100 = Color(hex: "#fff2eb")
        static let accent200 = Color(hex: "#ffe1d0")
        static let accent600 = Color(hex: "#b2622d")
        static let accent700 = Color(hex: "#8c491a")

        static let accent2100 = Color(hex: "#f0fae1")
        static let accent2200 = Color(hex: "#e1eecc")
        static let accent2600 = Color(hex: "#728157")
        static let accent2700 = Color(hex: "#56633f")
    }

    // MARK: - Роли

    /// Фон экрана.
    static let background = Token.bg
    /// Поверхность строки списка и карточки.
    static let surface = Token.neutral100
    /// Заполнение полей ввода, сегментов, плашек.
    static let fill = Token.surface

    static let text = Token.text
    static let textSecondary = Token.neutral700
    static let textTertiary = Token.neutral500
    static let divider = Token.text.opacity(0.16)

    /// Основной акцент — действия и то, что требует внимания.
    static let accent = Token.accent
    static let accentSoft = Token.accent200
    static let accentStrong = Token.accent700

    /// Второй акцент — движение и завершённость.
    static let accent2 = Token.accent2600
    static let accent2Soft = Token.accent2200
    static let accent2Strong = Token.accent2700

    /// В системе нет роли для разрушающих действий — выведена из акцентной шкалы
    /// сдвигом в красный, чтобы «Удалить» не путалось с обычной кнопкой.
    static let danger = Color(hex: "#a33b1f")

    // MARK: - Скругления и отступы

    enum Radius {
        static let small: CGFloat = 8
        static let medium: CGFloat = 16
        static let large: CGFloat = 28
    }

    /// Шаг системы — 4.4 pt. В вёрстке округлён до чётных значений:
    /// дробные отступы дают размытые границы на экранах @2x.
    enum Space {
        static let xs: CGFloat = 4
        static let s: CGFloat = 9
        static let m: CGFloat = 13
        static let l: CGFloat = 18
        static let xl: CGFloat = 26
        static let xxl: CGFloat = 35
    }

    // MARK: - Шрифты

    /// Caprasimo для заголовков, Figtree для текста — файлы лежат в `Resources/Fonts`.
    ///
    /// Начертания подставляются по имени, а не через `.weight()`: для кастомного
    /// семейства SwiftUI не синтезирует вес, а берёт зарегистрированный шрифт.
    /// Если файла нет, каждый метод возвращает системный аналог — приложение
    /// остаётся работоспособным даже с пустой папкой Resources.
    private static let headingFont = "Caprasimo-Regular"

    private static func bodyFont(_ weight: Font.Weight) -> String {
        switch weight {
        case .medium: return "Figtree-Medium"
        case .semibold: return "Figtree-SemiBold"
        case .bold, .heavy, .black: return "Figtree-Bold"
        default: return "Figtree-Regular"
        }
    }

    static func heading(_ size: CGFloat, relativeTo style: Font.TextStyle = .title) -> Font {
        guard UIFont(name: headingFont, size: size) != nil else {
            return .system(size: size, weight: .heavy, design: .serif)
        }
        return .custom(headingFont, size: size, relativeTo: style)
    }

    static func body(
        _ size: CGFloat,
        weight: Font.Weight = .regular,
        relativeTo style: Font.TextStyle = .body
    ) -> Font {
        let name = bodyFont(weight)
        guard UIFont(name: name, size: size) != nil else {
            return .system(size: size, weight: weight)
        }
        return .custom(name, size: size, relativeTo: style)
    }

    // MARK: - Регистрация шрифтов

    /// Регистрирует шрифты из бандла пакета.
    ///
    /// Через `CTFontManager`, а не через `UIAppFonts` в Info.plist: у App Playground
    /// своего Info.plist нет, а так одно и то же работает и в пакете, и в Xcode-проекте.
    /// Повторный вызов безвреден — система вернёт «уже зарегистрирован».
    static func registerFonts() {
        let names = [
            "Caprasimo-Regular",
            "Figtree-Regular",
            "Figtree-Medium",
            "Figtree-SemiBold",
            "Figtree-Bold"
        ]

        // Только Bundle.main: в App Playground ресурсы попадают прямо в бандл
        // приложения, а синтезированного Bundle.module у такого таргета нет —
        // первая сборка в CI упала именно на нём.
        for name in names {
            guard let url = Bundle.main.url(forResource: name, withExtension: "ttf") else {
                continue
            }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }

    // MARK: - Оформление системных панелей

    /// Навигационная и таб-панель не красятся модификаторами SwiftUI —
    /// только через UIKit-appearance. Вызывается один раз на старте.
    @MainActor
    static func applySystemAppearance() {
        registerFonts()

        let navigation = UINavigationBarAppearance()
        navigation.configureWithOpaqueBackground()
        navigation.backgroundColor = UIColor(background)
        navigation.shadowColor = UIColor(divider)
        navigation.titleTextAttributes = [.foregroundColor: UIColor(text)]
        navigation.largeTitleTextAttributes = [
            .foregroundColor: UIColor(text),
            .font: headingUIFont(32)
        ]

        UINavigationBar.appearance().standardAppearance = navigation
        UINavigationBar.appearance().compactAppearance = navigation
        UINavigationBar.appearance().scrollEdgeAppearance = navigation

        let tab = UITabBarAppearance()
        tab.configureWithOpaqueBackground()
        tab.backgroundColor = UIColor(background)
        tab.shadowColor = UIColor(divider)

        UITabBar.appearance().standardAppearance = tab
        UITabBar.appearance().scrollEdgeAppearance = tab
    }

    private static func headingUIFont(_ size: CGFloat) -> UIFont {
        UIFont(name: headingFont, size: size)
            ?? UIFont.systemFont(ofSize: size, weight: .heavy).withSerifDesign()
    }
}

private extension UIFont {
    func withSerifDesign() -> UIFont {
        guard let descriptor = fontDescriptor.withDesign(.serif) else { return self }
        return UIFont(descriptor: descriptor, size: pointSize)
    }
}

// MARK: - Модификаторы

extension View {

    /// Кремовый фон системы вместо стандартного серого у `List` и `Form`.
    func organicBackground() -> some View {
        self
            .scrollContentBackground(.hidden)
            .background(Theme.background)
    }

    /// Строка списка на светлой поверхности со скруглением системы.
    func organicRow() -> some View {
        self
            .listRowBackground(
                RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous)
                    .fill(Theme.surface)
                    .padding(.vertical, 2)
            )
            .listRowSeparatorTint(Theme.divider)
    }
}
