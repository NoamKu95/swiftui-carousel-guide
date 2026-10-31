import SwiftUI

struct DemoMenuView: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    header

                    VStack(spacing: 14) {
                        ForEach(DemoKind.allCases) { kind in
                            NavigationLink(value: kind) {
                                DemoRowView(kind: kind)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 32)
            }
            .background(menuBackground)
            .navigationTitle("Carousels")
            .navigationBarTitleDisplayMode(.large)
            .navigationDestination(for: DemoKind.self) { kind in
                CarouselDemoView(kind: kind)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("SwiftUI patterns")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.8)

            Text("Six demos covering finite, infinite, auto, manual, and 3D circle carousels.")
                .font(.title3)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private var menuBackground: some View {
        LinearGradient(
            colors: [
                Color.primary.opacity(0.06),
                Color.secondary.opacity(0.10),
                Color.primary.opacity(0.04)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .background(Color(.systemBackground))
        .ignoresSafeArea()
    }
}

#Preview {
    DemoMenuView()
}
