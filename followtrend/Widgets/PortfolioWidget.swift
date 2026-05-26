//
//  PortfolioWidget.swift
//  followtrend
//
//  Widget extension initialization configuring WidgetKit properties.
//

import WidgetKit
import SwiftUI

@main
struct PortfolioWidget: Widget {
    let kind: String = "PortfolioWidget"
    
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PortfolioProvider()) { entry in
            WidgetView(entry: entry)
                .containerBackground(Color.bgDeep, for: .widget)
        }
        .configurationDisplayName("followtrend")
        .description("Track your portfolio balance and top watchlist assets.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
