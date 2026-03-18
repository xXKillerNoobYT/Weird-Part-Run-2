import SwiftUI

/// User avatar circle with initials.
///
/// Extracted from UserMenuSheet's profile section. Shows the user's
/// initials in a tinted circle that scales with Dynamic Type.
///
/// Usage:
///   DSAvatarView(name: "John Smith")
///   DSAvatarView(name: "Jane Doe", size: .large)
struct DSAvatarView: View {
    let name: String
    var size: AvatarSize = .medium

    /// Avatar diameter that scales with Dynamic Type.
    @ScaledMetric(relativeTo: .title3) private var mediumSize: CGFloat = 40
    @ScaledMetric(relativeTo: .title) private var largeSize: CGFloat = 50

    private var diameter: CGFloat {
        switch size {
        case .small: mediumSize * 0.75
        case .medium: mediumSize
        case .large: largeSize
        }
    }

    private var fontSize: Font {
        switch size {
        case .small: .caption
        case .medium: .callout
        case .large: .title3
        }
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(DS.SemanticColor.tint(.accentColor))
                .frame(width: diameter, height: diameter)

            Text(initials)
                .font(fontSize)
                .fontWeight(.semibold)
                .foregroundStyle(Color.accentColor)
        }
        .accessibilityLabel(name)
    }

    private var initials: String {
        let parts = name.split(separator: " ")
        switch parts.count {
        case 0: return "?"
        case 1: return String(parts[0].prefix(1)).uppercased()
        default: return (String(parts[0].prefix(1)) + String(parts[1].prefix(1))).uppercased()
        }
    }

    enum AvatarSize {
        case small, medium, large
    }
}

#Preview {
    HStack(spacing: DS.Space.lg) {
        DSAvatarView(name: "John Smith", size: .small)
        DSAvatarView(name: "Jane Doe", size: .medium)
        DSAvatarView(name: "Bob Builder", size: .large)
    }
    .padding()
}
