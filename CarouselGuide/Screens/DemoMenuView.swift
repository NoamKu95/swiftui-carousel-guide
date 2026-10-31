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
                                DemoRow(kind: kind)
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

            Text("Eight polished demos covering finite, infinite, auto, and manual carousels.")
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

private struct DemoRow: View {
    let kind: DemoKind

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(rowAccent)
                    .frame(width: 56, height: 56)

                Image(systemName: kind.systemImage)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color(.systemBackground))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(kind.title)
                    .font(.headline)
                    .foregroundStyle(.primary)

                Text(kind.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary.opacity(0.55))
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color(.secondarySystemBackground))
                .shadow(color: .primary.opacity(0.08), radius: 12, y: 6)
        )
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the \(kind.title) demo")
    }

    private var rowAccent: LinearGradient {
        // Distinct primary/secondary mixes per row — adaptive in light and dark.
        switch kind {
        case .horizontal:
            LinearGradient(
                colors: [.primary, .secondary],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .vertical:
            LinearGradient(
                colors: [.secondary, .primary.opacity(0.75)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .horizontalInfinite:
            LinearGradient(
                colors: [.primary.opacity(0.85), .secondary.opacity(0.65)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .verticalInfinite:
            LinearGradient(
                colors: [.secondary.opacity(0.9), .primary],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .stackedThreeInfinite:
            LinearGradient(
                colors: [.primary.opacity(0.7), .secondary.opacity(0.95)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
}

#Preview {
    DemoMenuView()
}
