//
//  WidgetDesignExtensions.swift
//  followtrend
//
//  UI design extensions utilized exclusively by the PortfolioWidget target.
//  This prevents duplicate declarations in the main target which defines its own DesignSystem.
//

import SwiftUI

extension Color {
    public static let bgDeep        = Color(hex: "#07070a")
    public static let bgCard        = Color(hex: "#0e0e15")
    public static let bgElevated    = Color(hex: "#13131d")
    public static let borderHair    = Color.white.opacity(0.07)
    public static let jade          = Color(hex: "#00d17e")
    public static let crimson       = Color(hex: "#ff4a6a")
    public static let textPrimary   = Color.white
    public static let textSecondary = Color(white: 0.55)
    public static let textMuted     = Color(white: 0.35)
    
    public init(hex: String) {
        var str = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if str.hasPrefix("#") { str = String(str.dropFirst()) }
        var rgb: UInt64 = 0
        Scanner(string: str).scanHexInt64(&rgb)
        let r = Double((rgb >> 16) & 0xff) / 255
        let g = Double((rgb >>  8) & 0xff) / 255
        let b = Double( rgb        & 0xff) / 255
        self.init(red: r, green: g, blue: b)
    }
}

extension Double {
    public var gainColor: Color { self >= 0 ? .jade : .crimson }
    public var gainPrefix: String { self >= 0 ? "+" : "" }
}
