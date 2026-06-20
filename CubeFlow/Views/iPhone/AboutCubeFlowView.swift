import SwiftUI
import UIKit

#if os(iOS)
struct AboutCubeFlowView: View {
    @AppStorage("appLanguage") private var appLanguage: String = "en"
    @State private var isShowingShareSheet = false

    private let githubURL = URL(string: "https://github.com/PaulSun10/CubeFlow")!
    private let feedbackURL = URL(string: "https://github.com/PaulSun10/CubeFlow/issues/new")!

    var body: some View {
        List {
            Section {
                aboutHeader
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
            }

            Section("about.section.support") {
                Link(destination: feedbackURL) {
                    aboutRow(
                        titleKey: "about.send_feedback",
                        systemImage: "exclamationmark.bubble"
                    )
                }

                Link(destination: githubURL) {
                    aboutRow(
                        titleKey: "about.github",
                        systemImage: "chevron.left.forwardslash.chevron.right"
                    )
                }

                Button {
                    isShowingShareSheet = true
                } label: {
                    aboutRow(
                        titleKey: "about.share",
                        systemImage: "square.and.arrow.up"
                    )
                }
            }

            Section {
                NavigationLink {
                    CubeFlowAcknowledgementsView()
                } label: {
                    aboutRow(
                        titleKey: "about.acknowledgements",
                        systemImage: "heart"
                    )
                }

                NavigationLink {
                    CubeFlowOpenSourceView()
                } label: {
                    aboutRow(
                        titleKey: "about.open_source",
                        systemImage: "doc.text"
                    )
                }

                NavigationLink {
                    CubeFlowPrivacyView()
                } label: {
                    aboutRow(
                        titleKey: "about.privacy",
                        systemImage: "hand.raised"
                    )
                }

                NavigationLink {
                    CubeFlowWCADisclaimerView()
                } label: {
                    aboutRow(
                        titleKey: "about.wca_disclaimer",
                        systemImage: "checkmark.seal"
                    )
                }
            } header: {
                Text("about.section.information")
            } footer: {
                Text("about.footer")
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
                    .padding(.top, 8)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(Text(appLocalizedString("about.title", languageCode: appLanguage)))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $isShowingShareSheet) {
            AboutShareSheet(
                activityItems: [
                    appLocalizedString("about.share_message", languageCode: appLanguage),
                    githubURL
                ]
            )
        }
    }

    private var aboutHeader: some View {
        VStack(spacing: 10) {
            CubeFlowAppIconView()

            Text("CubeFlow")
                .font(.system(size: 26, weight: .bold))

            Text("about.tagline")
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Text(versionDescription)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 12)
    }

    private var versionDescription: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "-"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "-"
        return String(
            format: appLocalizedString("about.version_format", languageCode: appLanguage),
            version,
            build
        )
    }

    private func aboutRow(titleKey: LocalizedStringKey, systemImage: String) -> some View {
        Label(titleKey, systemImage: systemImage)
            .foregroundStyle(.primary)
    }
}

private struct CubeFlowAcknowledgementsView: View {
    @AppStorage("appLanguage") private var appLanguage: String = "en"

    var body: some View {
        List {
            Section {
                Text("about.acknowledgements_intro")
                    .foregroundStyle(.secondary)
            }

            acknowledgementSection(
                title: "SpeedCubeDB",
                detailKey: "about.acknowledgements_speedcubedb",
                url: "https://www.speedcubedb.com"
            )

            acknowledgementSection(
                title: "Speedsolving.com Wiki",
                detailKey: "about.acknowledgements_wiki",
                url: "https://www.speedsolving.com/wiki/index.php/Main_Page"
            )

            acknowledgementSection(
                title: "CubeRoot",
                detailKey: "about.acknowledgements_cuberoot",
                url: "https://www.cuberoot.me"
            )

            Section {
                Text("about.acknowledgements_independent")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(Text(appLocalizedString("about.acknowledgements", languageCode: appLanguage)))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func acknowledgementSection(
        title: String,
        detailKey: LocalizedStringKey,
        url: String
    ) -> some View {
        Section(title) {
            Text(detailKey)
                .foregroundStyle(.secondary)

            if let destination = URL(string: url) {
                Link("about.visit_website", destination: destination)
            }
        }
    }
}

private struct CubeFlowOpenSourceView: View {
    @AppStorage("appLanguage") private var appLanguage: String = "en"

    var body: some View {
        List {
            Section {
                Text("about.open_source_intro")
                    .foregroundStyle(.secondary)
            }

            openSourceSection(
                title: "CubeFlow",
                license: "MIT",
                detailKey: "about.open_source_cubeflow",
                url: "https://github.com/PaulSun10/CubeFlow"
            )

            openSourceSection(
                title: "TNoodle",
                license: "AGPL-3.0",
                detailKey: "about.open_source_tnoodle",
                url: "https://github.com/thewca/tnoodle"
            )

            openSourceSection(
                title: "min2phaseCXX",
                license: "GPLv3 / MIT",
                detailKey: "about.open_source_min2phase",
                url: "https://github.com/lilborgo/min2phaseCXX"
            )
        }
        .listStyle(.insetGrouped)
        .navigationTitle(Text(appLocalizedString("about.open_source", languageCode: appLanguage)))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func openSourceSection(
        title: String,
        license: String,
        detailKey: LocalizedStringKey,
        url: String
    ) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 5) {
                Text(detailKey)
                    .foregroundStyle(.secondary)

                Text(license)
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
            }

            if let destination = URL(string: url) {
                Link("about.view_source", destination: destination)
            }
        } header: {
            Text(title)
        }
    }
}

private struct CubeFlowPrivacyView: View {
    @AppStorage("appLanguage") private var appLanguage: String = "en"

    var body: some View {
        List {
            privacySection(
                titleKey: "about.privacy_local_title",
                bodyKey: "about.privacy_local_body"
            )
            privacySection(
                titleKey: "about.privacy_wca_title",
                bodyKey: "about.privacy_wca_body"
            )
            privacySection(
                titleKey: "about.privacy_location_title",
                bodyKey: "about.privacy_location_body"
            )
            privacySection(
                titleKey: "about.privacy_bluetooth_title",
                bodyKey: "about.privacy_bluetooth_body"
            )
            privacySection(
                titleKey: "about.privacy_network_title",
                bodyKey: "about.privacy_network_body"
            )
            privacySection(
                titleKey: "about.privacy_analytics_title",
                bodyKey: "about.privacy_analytics_body"
            )
        }
        .listStyle(.insetGrouped)
        .navigationTitle(Text(appLocalizedString("about.privacy", languageCode: appLanguage)))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func privacySection(
        titleKey: LocalizedStringKey,
        bodyKey: LocalizedStringKey
    ) -> some View {
        Section(titleKey) {
            Text(bodyKey)
                .foregroundStyle(.secondary)
        }
    }
}

private struct CubeFlowWCADisclaimerView: View {
    @AppStorage("appLanguage") private var appLanguage: String = "en"

    var body: some View {
        List {
            Section {
                Text("about.wca_disclaimer_independent")
                Text("about.wca_disclaimer_accuracy")
                Text("about.wca_disclaimer_identity")
            }

            Section {
                Link(
                    "about.visit_wca",
                    destination: URL(string: "https://www.worldcubeassociation.org")!
                )
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(Text(appLocalizedString("about.wca_disclaimer", languageCode: appLanguage)))
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct CubeFlowAppIconView: View {
    var body: some View {
        Group {
            if let image = currentAppIcon {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                ZStack {
                    Color.red
                    Image(systemName: "square.grid.3x3.fill")
                        .font(.system(size: 38, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
        }
        .frame(width: 82, height: 82)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.16), radius: 8, y: 4)
        .accessibilityHidden(true)
    }

    private var currentAppIcon: UIImage? {
        if let alternateIconName = UIApplication.shared.alternateIconName,
           let image = UIImage(named: alternateIconName) {
            return image
        }

        guard
            let icons = Bundle.main.infoDictionary?["CFBundleIcons"] as? [String: Any],
            let primaryIcon = icons["CFBundlePrimaryIcon"] as? [String: Any],
            let iconFiles = primaryIcon["CFBundleIconFiles"] as? [String],
            let iconName = iconFiles.last
        else {
            return UIImage(named: "CubeflowRed")
        }

        return UIImage(named: iconName) ?? UIImage(named: "CubeflowRed")
    }
}

private struct AboutShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
#endif
