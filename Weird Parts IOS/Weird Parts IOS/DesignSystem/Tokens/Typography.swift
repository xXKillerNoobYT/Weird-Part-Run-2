import SwiftUI

/// Design System typography scale.
///
/// Semantic aliases over SwiftUI text styles. Never use fixed point sizes
/// (`.font(.system(size:))`) — always use these tokens or raw SwiftUI text
/// styles so Dynamic Type scaling works automatically.
///
/// Usage:
///   Text("Dashboard").dsStyle(.pageTitle)
///   Text("$1,234").dsStyle(.kpiValue)
extension DS {
    enum Typography {
        case pageTitle      // .title2 + .bold — page greeting, main headers
        case sectionTitle   // .headline — card section headers
        case cardTitle      // .subheadline + .semibold — row titles, card labels
        case bodyText       // .body — standard content
        case detail         // .callout — row subtitles, descriptions
        case caption        // .caption — secondary labels, dates
        case label          // .caption2 + .semibold — StatusBadge text, tiny labels
        case kpiValue       // .title + .bold + .rounded — KPI card numbers
        case mono           // .caption + monospaced — codes, IDs
    }
}

/// ViewModifier that applies a DS.Typography style to a Text view.
struct DSTypographyModifier: ViewModifier {
    let style: DS.Typography

    func body(content: Content) -> some View {
        switch style {
        case .pageTitle:
            content
                .font(.title2)
                .fontWeight(.bold)
        case .sectionTitle:
            content
                .font(.headline)
        case .cardTitle:
            content
                .font(.subheadline)
                .fontWeight(.semibold)
        case .bodyText:
            content
                .font(.body)
        case .detail:
            content
                .font(.callout)
        case .caption:
            content
                .font(.caption)
        case .label:
            content
                .font(.caption2)
                .fontWeight(.semibold)
        case .kpiValue:
            content
                .font(.system(.title, design: .rounded))
                .fontWeight(.bold)
        case .mono:
            content
                .font(.caption)
                .monospaced()
        }
    }
}

extension View {
    /// Apply a Design System typography style.
    func dsStyle(_ style: DS.Typography) -> some View {
        modifier(DSTypographyModifier(style: style))
    }
}
