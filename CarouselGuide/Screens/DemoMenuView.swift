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
                Color(hex: 0xF7F4EF),
                Color(hex: 0xE8EEF2),
                Color(hex: 0xF3EDE4)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
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
                    .foregroundStyle(.white)
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
                .foregroundStyle(.tertiary)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.background.opacity(0.92))
                .shadow(color: .black.opacity(0.06), radius: 12, y: 6)
        )
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the \(kind.title) demo")
    }

    private var rowAccent: LinearGradient {
        switch kind {
        case .horizontal:
            LinearGradient(colors: [Color(hex: 0x1F4E5F), Color(hex: 0x79A8A9)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .vertical:
            LinearGradient(colors: [Color(hex: 0x14213D), Color(hex: 0x4361EE)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .horizontalInfinite:
            LinearGradient(colors: [Color(hex: 0xC46B3A), Color(hex: 0xF2C14E)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .verticalInfinite:
            LinearGradient(colors: [Color(hex: 0x3A0CA3), Color(hex: 0xF72585)], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }
}

#Preview {
    DemoMenuView()
}
