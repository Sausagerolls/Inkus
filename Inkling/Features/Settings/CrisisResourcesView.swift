import SwiftUI

struct CrisisResourcesView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.l) {
                header

                resource(
                    region: "United States & Canada",
                    name: "988 Suicide & Crisis Lifeline",
                    detail: "Call or text 988. Free, confidential, 24/7.",
                    callURL: URL(string: "tel://988"),
                    webURL: URL(string: "https://988lifeline.org")
                )

                resource(
                    region: "United Kingdom & Ireland",
                    name: "Samaritans",
                    detail: "Call 116 123, free from any phone, 24/7.",
                    callURL: URL(string: "tel://116123"),
                    webURL: URL(string: "https://www.samaritans.org")
                )

                resource(
                    region: "Anywhere else",
                    name: "Find a local helpline",
                    detail: "Find an international list of crisis lines and helplines.",
                    callURL: nil,
                    webURL: URL(string: "https://findahelpline.com")
                )

                Text("Inkus is not a substitute for talking to a person. If you're in crisis or worried about yourself or someone else, please reach out.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.top, Spacing.m)
            }
            .padding(Spacing.l)
        }
        .navigationTitle("Crisis Resources")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Image(systemName: "heart.text.square")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(Color.inkAccent)
            Text("If today is heavy")
                .font(.system(.title, design: .serif).weight(.semibold))
            Text("Real people, on the other end of a line.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private func resource(region: String, name: String, detail: String, callURL: URL?, webURL: URL?) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Text(region.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .tracking(0.5)
            Text(name)
                .font(.body.weight(.semibold))
            Text(detail)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: Spacing.s) {
                if let url = callURL {
                    Link(destination: url) {
                        Label("Call", systemImage: "phone.fill")
                            .font(.callout.weight(.semibold))
                            .padding(.horizontal, Spacing.m)
                            .padding(.vertical, Spacing.s)
                            .background(Capsule().fill(Color.inkAccent))
                            .foregroundStyle(.white)
                    }
                }
                if let url = webURL {
                    Link(destination: url) {
                        Label("Open", systemImage: "safari")
                            .font(.callout.weight(.medium))
                            .padding(.horizontal, Spacing.m)
                            .padding(.vertical, Spacing.s)
                            .background(Capsule().fill(Color.inkSecondary))
                            .foregroundStyle(.primary)
                    }
                }
            }
            .padding(.top, Spacing.xs)
        }
        .padding(Spacing.m)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.inkSecondary.opacity(0.6))
        )
    }
}
