import SwiftUI

struct DemoRowView: View {
    let kind: DemoKind

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(kind.rowAccent)
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
                .shadow(color: .black.opacity(0.12), radius: 12, y: 6)
        )
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the \(kind.title) demo")
    }
}

#Preview {
    DemoRowView(kind: .horizontal)
        .padding()
}
