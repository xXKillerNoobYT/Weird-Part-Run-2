import SwiftUI

/// A brief horizontal carousel introducing key app modules.
/// Shows after the NewUserWelcomeView is dismissed, only once per device.
struct ModuleTourView: View {
    @AppStorage("hasSeenModuleTour") private var hasSeenTour = false
    @AppStorage("hasSeenWelcome") private var hasSeenWelcome = false
    @State private var currentPage = 0

    private let pages: [(icon: String, title: String, description: String)] = [
        ("house.fill", "Dashboard", "Your daily command center. Clock in, see KPIs, scan QR codes."),
        ("briefcase.fill", "Jobs", "Track every job from start to finish. Clock hours, manage to-dos, track warranty."),
        ("cart.fill", "Orders", "Create parts orders for jobs. Track POs from draft to delivery."),
        ("building.2.fill", "Warehouse", "Know where every part is. Audit stock, manage locations, prep job boxes."),
        ("person.3.fill", "People", "Your team, customers, and contractors. Hats control who can do what."),
        ("wrench.fill", "Tools", "Track every tool and kit. Checkout, return, trade, maintain."),
    ]

    var body: some View {
        // Only show after welcome is dismissed, and only once
        if hasSeenWelcome && !hasSeenTour {
            tourOverlay
        }
    }

    private var tourOverlay: some View {
        VStack(spacing: 20) {
            Spacer()

            Text("Quick Tour")
                .font(.title2)
                .fontWeight(.bold)

            TabView(selection: $currentPage) {
                ForEach(Array(pages.enumerated()), id: \.offset) { index, page in
                    VStack(spacing: 16) {
                        Image(systemName: page.icon)
                            .decorativeIconFont(48)
                            .foregroundStyle(.blue)

                        Text(page.title)
                            .font(.title3)
                            .fontWeight(.semibold)

                        Text(page.description)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .frame(height: 220)

            HStack(spacing: 16) {
                Button("Skip") {
                    withAnimation { hasSeenTour = true }
                }
                .foregroundStyle(.secondary)

                Spacer()

                if currentPage < pages.count - 1 {
                    Button {
                        withAnimation { currentPage += 1 }
                    } label: {
                        HStack(spacing: 4) {
                            Text("Next")
                            Image(systemName: "chevron.right")
                        }
                        .fontWeight(.medium)
                    }
                } else {
                    Button {
                        withAnimation { hasSeenTour = true }
                    } label: {
                        Text("Get Started")
                            .fontWeight(.semibold)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(.horizontal, 32)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial)
    }
}
