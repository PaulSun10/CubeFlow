#if os(iOS)
import Photos
import SwiftUI
import UIKit

extension View {
    /// Enables the system selection menu for user-authored or data-bearing text.
    func selectableContent() -> some View {
        textSelection(.enabled)
    }

    func contentImageActions(
        source: ContentImageSource,
        presentation: ContentImagePresentation = .transparent
    ) -> some View {
        modifier(ContentImageActionsModifier(source: source, presentation: presentation))
    }
}

/// A single TextKit selection scope for content that is visually composed from
/// multiple SwiftUI text elements.
struct SelectableAttributedContent: UIViewRepresentable {
    let attributedText: NSAttributedString
    var inlineControls: [SelectableInlineControl] = []
    var onOpenURL: ((URL) -> Bool)? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> IntrinsicTextView {
        // Use one real, non-scrolling UITextView as the document and responder.
        // This keeps selection highlights, handles, and the system edit menu in
        // the same TextKit pipeline instead of mirroring SwiftUI text geometry.
        // Inline controls are positioned with NSLayoutManager, so select
        // TextKit 1 at creation rather than making UIKit switch engines after
        // the selection interaction has already been installed.
        let textView = IntrinsicTextView.makeTextKit1View()
        textView.backgroundColor = .clear
        textView.isEditable = false
        textView.isSelectable = true
        textView.isUserInteractionEnabled = true
        textView.isScrollEnabled = false
        textView.allowsEditingTextAttributes = false
        textView.dataDetectorTypes = []
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.textContainer.widthTracksTextView = true
        textView.tintColor = .systemBlue
        textView.textDragInteraction?.isEnabled = true
        textView.adjustsFontForContentSizeCategory = true
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        textView.setContentCompressionResistancePriority(.required, for: .vertical)
        textView.setContentHuggingPriority(.required, for: .vertical)
        textView.delegate = context.coordinator
        textView.inlineControlHandler = context.coordinator
        textView.linkTextAttributes = [
            .foregroundColor: UIColor.tintColor,
            .underlineStyle: 0
        ]
        return textView
    }

    func updateUIView(_ textView: IntrinsicTextView, context: Context) {
        context.coordinator.onOpenURL = onOpenURL
        context.coordinator.inlineControls = inlineControls.reduce(into: [:]) { result, control in
            result[control.id] = control
        }
        if !(context.coordinator.appliedAttributedText?.isEqual(to: attributedText) ?? false) {
            let selectedRange = textView.selectedRange
            let wasFirstResponder = textView.isFirstResponder
            textView.attributedText = attributedText
            context.coordinator.appliedAttributedText = attributedText.copy() as? NSAttributedString
            if wasFirstResponder, NSMaxRange(selectedRange) <= attributedText.length {
                textView.selectedRange = selectedRange
            }
            textView.invalidateIntrinsicContentSize()
        }
        textView.reloadInlineControls(inlineControls)
    }

    @available(iOS 16.0, *)
    func sizeThatFits(
        _ proposal: ProposedViewSize,
        uiView textView: IntrinsicTextView,
        context: Context
    ) -> CGSize? {
        guard let width = proposal.width, width.isFinite, width > 0 else {
            return nil
        }

        let measured = textView.sizeThatFits(
            CGSize(width: width, height: CGFloat.greatestFiniteMagnitude)
        )
        return CGSize(width: width, height: ceil(measured.height))
    }

    final class Coordinator: NSObject, UITextViewDelegate, SelectableInlineControlHandling,
        UIPopoverPresentationControllerDelegate {
        var onOpenURL: ((URL) -> Bool)?
        var inlineControls: [String: SelectableInlineControl] = [:]
        var appliedAttributedText: NSAttributedString?
        private weak var presentedPopover: UIViewController?

        func textView(
            _ textView: UITextView,
            shouldInteractWith URL: URL,
            in characterRange: NSRange,
            interaction: UITextItemInteraction
        ) -> Bool {
            !(onOpenURL?(URL) ?? false)
        }

        func activateInlineControl(id: String, sourceView: UIView) {
            guard let control = inlineControls[id] else { return }
            if let action = control.action {
                action()
            }
            guard let message = control.popoverText, !message.isEmpty,
                  presentedPopover == nil,
                  let presenter = sourceView.nearestViewController else { return }

            let label = UILabel()
            label.text = message
            label.font = UIFont.preferredFont(forTextStyle: .subheadline)
            label.textColor = .label
            label.numberOfLines = 0
            label.textAlignment = .center
            label.translatesAutoresizingMaskIntoConstraints = false

            let container = UIViewController()
            container.view.backgroundColor = .clear
            container.view.addSubview(label)
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: container.view.leadingAnchor, constant: 14),
                label.trailingAnchor.constraint(equalTo: container.view.trailingAnchor, constant: -14),
                label.topAnchor.constraint(equalTo: container.view.topAnchor, constant: 10),
                label.bottomAnchor.constraint(equalTo: container.view.bottomAnchor, constant: -10)
            ])
            let maximumWidth = min(max((sourceView.window?.bounds.width ?? 320) - 32, 180), 260)
            let measured = label.sizeThatFits(
                CGSize(width: maximumWidth - 28, height: CGFloat.greatestFiniteMagnitude)
            )
            container.preferredContentSize = CGSize(
                width: min(max(ceil(measured.width) + 28, 72), maximumWidth),
                height: ceil(measured.height) + 20
            )
            container.modalPresentationStyle = .popover
            guard let popover = container.popoverPresentationController else { return }
            popover.sourceView = sourceView
            popover.sourceRect = CGRect(
                x: sourceView.bounds.midX,
                y: sourceView.bounds.midY - sourceView.bounds.height * 0.14,
                width: 1,
                height: 1
            )
            popover.permittedArrowDirections = [.up, .down]
            popover.delegate = self
            presentedPopover = container
            presenter.present(container, animated: true)
        }

        func adaptivePresentationStyle(
            for controller: UIPresentationController
        ) -> UIModalPresentationStyle {
            .none
        }

        func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
            presentedPopover = nil
        }
    }

    final class IntrinsicTextView: UITextView {
        private struct InlineControlSignature: Equatable {
            let id: String
            let content: String
            let accessibilityLabel: String
            let color: String
            let alignment: SelectableInlineControl.Alignment
            let minimumHitSize: CGSize
        }

        private var measuredWidth: CGFloat = 0
        private var inlineButtons: [String: UIButton] = [:]
        private var inlineControlsByID: [String: SelectableInlineControl] = [:]
        private var installedInlineControlSignature: [InlineControlSignature] = []
        private var ownedTextStorage: NSTextStorage?
        weak var inlineControlHandler: SelectableInlineControlHandling?

        private(set) var inlineControlInstallationGeneration = 0

        static func makeTextKit1View() -> IntrinsicTextView {
            let textStorage = NSTextStorage()
            let layoutManager = NSLayoutManager()
            let textContainer = NSTextContainer(size: .zero)
            textStorage.addLayoutManager(layoutManager)
            layoutManager.addTextContainer(textContainer)

            // Use the Swift subclass's designated initializer. UIKit's
            // +textViewUsingTextLayoutManager: class factory can allocate this
            // subclass without running its Swift stored-property initializers.
            let textView = IntrinsicTextView(frame: .zero, textContainer: textContainer)
            textView.ownedTextStorage = textStorage
            return textView
        }

        var installedInlineControlIDs: Set<String> {
            Set(inlineButtons.keys)
        }

        func isInlineControlHidden(id: String) -> Bool? {
            inlineButtons[id]?.isHidden
        }

        override var intrinsicContentSize: CGSize {
            guard bounds.width > 0 else { return super.intrinsicContentSize }
            return sizeThatFits(
                CGSize(width: bounds.width, height: CGFloat.greatestFiniteMagnitude)
            )
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            if abs(bounds.width - measuredWidth) > 0.5 {
                measuredWidth = bounds.width
                invalidateIntrinsicContentSize()
            }
            layoutInlineControls()
        }

        func reloadInlineControls(_ controls: [SelectableInlineControl]) {
            var controlsByID: [String: SelectableInlineControl] = [:]
            for control in controls where !control.id.isEmpty {
                controlsByID[control.id] = control
            }
            inlineControlsByID = controlsByID

            let signature = controlsByID.values
                .map { control in
                    InlineControlSignature(
                        id: control.id,
                        content: control.content.configurationSignature,
                        accessibilityLabel: control.accessibilityLabel,
                        color: control.color.description,
                        alignment: control.alignment,
                        minimumHitSize: control.minimumHitSize
                    )
                }
                .sorted { $0.id < $1.id }

            guard signature != installedInlineControlSignature else {
                setNeedsLayout()
                return
            }

            let staleIDs = inlineButtons.keys.filter { controlsByID[$0] == nil }
            for id in staleIDs {
                inlineButtons.removeValue(forKey: id)?.removeFromSuperview()
            }

            for control in controlsByID.values {
                let button = inlineButtons[control.id] ?? makeInlineButton(id: control.id)
                configure(button, for: control)
            }
            installedInlineControlSignature = signature
            inlineControlInstallationGeneration += 1
            setNeedsLayout()
        }

        private func makeInlineButton(id: String) -> UIButton {
            let button = UIButton(type: .custom)
            button.accessibilityIdentifier = id
            button.contentHorizontalAlignment = .center
            button.contentVerticalAlignment = .center
            button.titleLabel?.textAlignment = .center
            button.titleLabel?.baselineAdjustment = .alignCenters
            button.addTarget(self, action: #selector(didTapInlineControl(_:)), for: .touchUpInside)
            addSubview(button)
            inlineButtons[id] = button
            return button
        }

        private func configure(_ button: UIButton, for control: SelectableInlineControl) {
            button.accessibilityLabel = control.accessibilityLabel
            button.tintColor = control.color
            button.setTitleColor(control.color, for: .normal)
            button.contentHorizontalAlignment = .center
            button.titleLabel?.transform = .identity
            switch control.content {
            case .glyph(let glyph, let fontName, let fontSize):
                button.setImage(nil, for: .normal)
                button.setTitle(glyph, for: .normal)
                button.titleLabel?.font = UIFont(name: fontName, size: fontSize)
                let centerOffset = control.content.glyphInkMetrics?.centerOffset ?? 0
                button.titleLabel?.transform = CGAffineTransform(
                    translationX: -centerOffset,
                    y: 0
                )
            case .systemImage(let name, let pointSize, let weight):
                button.setTitle(nil, for: .normal)
                let configuration = UIImage.SymbolConfiguration(pointSize: pointSize, weight: weight)
                button.setImage(UIImage(systemName: name, withConfiguration: configuration), for: .normal)
            }
        }

        private func layoutInlineControls() {
            inlineButtons.values.forEach { $0.isHidden = true }
            guard attributedText.length > 0, !inlineButtons.isEmpty else { return }
            layoutManager.ensureLayout(for: textContainer)
            attributedText.enumerateAttribute(
                .selectableInlineControlID,
                in: NSRange(location: 0, length: attributedText.length)
            ) { value, characterRange, _ in
                guard let id = value as? String,
                      let button = inlineButtons[id],
                      let control = inlineControlsByID[id],
                      characterRange.location != NSNotFound,
                      characterRange.length > 0,
                      characterRange.location >= 0,
                      NSMaxRange(characterRange) <= attributedText.length else { return }
                let glyphRange = layoutManager.glyphRange(
                    forCharacterRange: characterRange,
                    actualCharacterRange: nil
                )
                guard glyphRange.location != NSNotFound, glyphRange.length > 0 else { return }
                var anchorRect = layoutManager.boundingRect(
                    forGlyphRange: glyphRange,
                    in: textContainer
                )
                anchorRect.origin.x += textContainerInset.left - contentOffset.x
                anchorRect.origin.y += textContainerInset.top - contentOffset.y

                if control.alignment == .paragraphCenter {
                    let paragraphRange = (attributedText.string as NSString).paragraphRange(
                        for: characterRange
                    )
                    let paragraphGlyphRange = layoutManager.glyphRange(
                        forCharacterRange: paragraphRange,
                        actualCharacterRange: nil
                    )
                    var paragraphRect = layoutManager.boundingRect(
                        forGlyphRange: paragraphGlyphRange,
                        in: textContainer
                    )
                    paragraphRect.origin.y += textContainerInset.top - contentOffset.y
                    anchorRect.origin.y = paragraphRect.midY - anchorRect.height / 2
                }

                let minimumHitSize = control.minimumHitSize
                let hitSize = CGSize(
                    width: max(minimumHitSize.width, anchorRect.width + 6),
                    height: max(minimumHitSize.height, anchorRect.height + 4)
                )
                let buttonCenterX: CGFloat
                if control.alignment == .glyphLeading,
                   let metrics = control.content.glyphInkMetrics {
                    buttonCenterX = anchorRect.minX
                        + metrics.bounds.minX
                        + metrics.bounds.width / 2
                        + CompetitionEventIconFont.leadingOpticalInset
                } else {
                    buttonCenterX = anchorRect.midX
                }
                button.frame = CGRect(
                    x: buttonCenterX - hitSize.width / 2,
                    y: anchorRect.midY - hitSize.height / 2,
                    width: hitSize.width,
                    height: hitSize.height
                ).integral
                button.isHidden = false
            }
        }

        @objc private func didTapInlineControl(_ sender: UIButton) {
            guard let id = sender.accessibilityIdentifier else { return }
            inlineControlHandler?.activateInlineControl(id: id, sourceView: sender)
        }
    }
}

struct VerticalTextPopoverPresenter: UIViewRepresentable {
    @Binding var isPresented: Bool
    let text: String
    var glyph: String?
    var glyphFontName: String?
    var glyphFontSize: CGFloat?

    func makeCoordinator() -> Coordinator {
        Coordinator(isPresented: $isPresented)
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        context.coordinator.anchorView = view
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.isPresented = $isPresented
        context.coordinator.text = text
        context.coordinator.glyph = glyph
        context.coordinator.glyphFontName = glyphFontName
        context.coordinator.glyphFontSize = glyphFontSize
        context.coordinator.anchorView = uiView

        DispatchQueue.main.async {
            context.coordinator.updatePresentation()
        }
    }

    final class Coordinator: NSObject, UIPopoverPresentationControllerDelegate {
        var isPresented: Binding<Bool>
        var text = ""
        var glyph: String?
        var glyphFontName: String?
        var glyphFontSize: CGFloat?
        weak var anchorView: UIView?
        weak var presentedController: UIViewController?

        init(isPresented: Binding<Bool>) {
            self.isPresented = isPresented
        }

        func updatePresentation() {
            guard let anchorView else { return }
            if isPresented.wrappedValue {
                guard presentedController == nil,
                      !text.isEmpty,
                      anchorView.window != nil,
                      let presenter = anchorView.nearestViewController else { return }
                present(from: presenter, anchorView: anchorView)
            } else if let presentedController {
                presentedController.dismiss(animated: true)
            }
        }

        private func present(from presenter: UIViewController, anchorView: UIView) {
            let label = UILabel()
            label.text = text
            label.font = UIFont.systemFont(ofSize: 15, weight: .medium)
            label.textColor = .label
            label.numberOfLines = 0
            label.textAlignment = .center
            label.translatesAutoresizingMaskIntoConstraints = false

            let container = UIViewController()
            container.view.backgroundColor = .clear
            container.view.addSubview(label)
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: container.view.leadingAnchor, constant: 14),
                label.trailingAnchor.constraint(equalTo: container.view.trailingAnchor, constant: -14),
                label.topAnchor.constraint(equalTo: container.view.topAnchor, constant: 10),
                label.bottomAnchor.constraint(equalTo: container.view.bottomAnchor, constant: -10)
            ])

            let availableWidth = max((anchorView.window?.bounds.width ?? 320) - 32, 180)
            let maximumWidth = min(availableWidth, 260)
            let measured = label.sizeThatFits(
                CGSize(width: maximumWidth - 28, height: .greatestFiniteMagnitude)
            )
            container.preferredContentSize = CGSize(
                width: min(max(ceil(measured.width) + 28, 72), maximumWidth),
                height: ceil(measured.height) + 20
            )
            container.modalPresentationStyle = .popover

            guard let popover = container.popoverPresentationController else { return }
            popover.sourceView = anchorView
            popover.sourceRect = visibleGlyphAnchorRect(in: anchorView.bounds)
            popover.permittedArrowDirections = [.up, .down]
            popover.delegate = self
            presentedController = container
            presenter.present(container, animated: true)
        }

        private func visibleGlyphAnchorRect(in bounds: CGRect) -> CGRect {
            guard let glyph,
                  let glyphFontName,
                  let glyphFontSize,
                  let metrics = CompetitionEventIconFont.glyphMetrics(
                    for: glyph,
                    fontName: glyphFontName,
                    pointSize: glyphFontSize
                  ) else {
                return CGRect(x: bounds.midX, y: bounds.midY, width: 1, height: 1)
            }
            let visibleCenterX = bounds.midX + metrics.centerOffset
            let upperMiddleY = bounds.midY - min(glyphFontSize * 0.18, bounds.height * 0.18)
            return CGRect(x: visibleCenterX, y: upperMiddleY, width: 1, height: 1)
        }

        func adaptivePresentationStyle(
            for controller: UIPresentationController
        ) -> UIModalPresentationStyle {
            .none
        }

        func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
            presentedController = nil
            if isPresented.wrappedValue {
                isPresented.wrappedValue = false
            }
        }
    }
}

extension NSAttributedString.Key {
    static let selectableInlineControlID = NSAttributedString.Key(
        "CubeFlow.SelectableInlineControlID"
    )
}

struct SelectableInlineControl {
    enum Content {
        case glyph(String, fontName: String, fontSize: CGFloat)
        case systemImage(String, pointSize: CGFloat, weight: UIImage.SymbolWeight)

        fileprivate var configurationSignature: String {
            switch self {
            case .glyph(let glyph, let fontName, let fontSize):
                return "glyph|\(glyph)|\(fontName)|\(fontSize)"
            case .systemImage(let name, let pointSize, let weight):
                return "system|\(name)|\(pointSize)|\(String(describing: weight))"
            }
        }

        fileprivate var glyphInkMetrics: CompetitionEventIconFont.GlyphMetrics? {
            guard case .glyph(let glyph, let fontName, let fontSize) = self else { return nil }
            return CompetitionEventIconFont.glyphMetrics(
                for: glyph,
                fontName: fontName,
                pointSize: fontSize
            )
        }
    }

    enum Alignment: Equatable {
        case glyphCenter
        case glyphLeading
        case paragraphCenter
    }

    let id: String
    let content: Content
    let accessibilityLabel: String
    var color: UIColor = .label
    var popoverText: String? = nil
    var alignment: Alignment = .glyphCenter
    var minimumHitSize = CGSize(width: 24, height: 24)
    var action: (() -> Void)? = nil
}

protocol SelectableInlineControlHandling: AnyObject {
    func activateInlineControl(id: String, sourceView: UIView)
}

struct SelectableKeyValueRow: Hashable {
    let label: String
    let value: String
}

/// A single TextKit document for visually structured label/value information.
/// Tabs preserve the two-column layout while selection can cross every row.
struct SelectableKeyValueContent: View {
    let rows: [SelectableKeyValueRow]
    var valueColumnOffset: CGFloat = 132
    var horizontalPadding: CGFloat = 16
    var verticalPadding: CGFloat = 7

    var body: some View {
        SelectableAttributedContent(attributedText: attributedText)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
    }

    private var attributedText: NSAttributedString {
        let result = NSMutableAttributedString()
        let labelFont = UIFontMetrics(forTextStyle: .body).scaledFont(
            for: UIFont.systemFont(ofSize: 14, weight: .semibold)
        )
        let valueFont = UIFontMetrics(forTextStyle: .body).scaledFont(
            for: UIFont.systemFont(ofSize: 15, weight: .regular)
        )

        for (index, row) in rows.enumerated() {
            if index > 0 { result.append(NSAttributedString(string: "\n")) }
            let start = result.length
            result.append(NSAttributedString(string: row.label, attributes: [
                .font: labelFont,
                .foregroundColor: UIColor.label
            ]))
            result.append(NSAttributedString(string: "\t"))
            result.append(NSAttributedString(string: row.value, attributes: [
                .font: valueFont,
                .foregroundColor: UIColor.label
            ]))

            let paragraph = NSMutableParagraphStyle()
            paragraph.tabStops = [NSTextTab(textAlignment: .left, location: valueColumnOffset)]
            paragraph.defaultTabInterval = valueColumnOffset
            paragraph.headIndent = valueColumnOffset
            paragraph.firstLineHeadIndent = 0
            paragraph.lineSpacing = 2
            paragraph.paragraphSpacing = verticalPadding * 2
            result.addAttribute(
                .paragraphStyle,
                value: paragraph,
                range: NSRange(location: start, length: result.length - start)
            )
        }
        return result
    }
}

enum ContentImageSource {
    case image(UIImage)
    case remote(URL)

    func load() async throws -> UIImage {
        switch self {
        case .image(let image):
            return image
        case .remote(let url):
            return try await ContentImageLoader.shared.image(for: url)
        }
    }
}

struct ContentImagePresentation {
    let backgroundColor: UIColor?

    static let transparent = ContentImagePresentation(backgroundColor: nil)
    static let white = ContentImagePresentation(backgroundColor: .white)
}

actor ContentImageLoader {
    static let shared = ContentImageLoader()

    private let memoryCache = NSCache<NSURL, UIImage>()

    func image(for url: URL) async throws -> UIImage {
        if let cached = memoryCache.object(forKey: url as NSURL) {
            return cached
        }

        let request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad)
        if let response = URLCache.shared.cachedResponse(for: request),
           let image = UIImage(data: response.data) {
            memoryCache.setObject(image, forKey: url as NSURL)
            return image
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode),
              let image = UIImage(data: data) else {
            throw ContentImageActionError.unavailable
        }
        memoryCache.setObject(image, forKey: url as NSURL)
        return image
    }
}

enum ContentImageActionError: LocalizedError {
    case unavailable
    case photosDenied
    case saveFailed

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "The image could not be loaded. Please try again."
        case .photosDenied:
            return "Allow CubeFlow to add photos in Settings, then try again."
        case .saveFailed:
            return "The image could not be saved to Photos."
        }
    }
}

@MainActor
enum ContentImageActions {
    static func copy(_ image: UIImage) {
        UIPasteboard.general.image = image
    }

    static func save(_ image: UIImage) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            throw ContentImageActionError.photosDenied
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            } completionHandler: { success, error in
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: error ?? ContentImageActionError.saveFailed)
                }
            }
        }
    }
}

struct SharedImageItem: Identifiable {
    let id = UUID()
    let image: UIImage
}

extension View {
    func zoomViewerPresentation<Destination: View>(
        isPresented: Binding<Bool>,
        @ViewBuilder destination: @escaping () -> Destination
    ) -> some View {
        modifier(
            ZoomViewerPresentationModifier(
                isPresented: isPresented,
                destination: destination
            )
        )
    }

}

private struct ZoomViewerPresentationModifier<Destination: View>: ViewModifier {
    @Binding var isPresented: Bool
    let destination: () -> Destination

    @Namespace private var transitionNamespace
    @State private var transitionID = UUID()

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content
                .matchedTransitionSource(id: transitionID, in: transitionNamespace)
                .fullScreenCover(isPresented: $isPresented) {
                    destination()
                        .navigationTransition(
                            .zoom(sourceID: transitionID, in: transitionNamespace)
                        )
                }
        } else {
            content
                .fullScreenCover(isPresented: $isPresented, content: destination)
        }
    }
}

@MainActor
enum ScreenTransientFeedback {
    private static weak var currentView: UIView?
    private static var currentController: UIViewController?

    static func showSuccess(_ message: String) {
        currentView?.removeFromSuperview()
        currentController = nil
        guard let window = activeWindow else { return }

        let controller = UIHostingController(rootView: ScreenCompletionHUD(message: message))
        controller.view.backgroundColor = .clear
        controller.view.isUserInteractionEnabled = false
        controller.view.translatesAutoresizingMaskIntoConstraints = false
        window.addSubview(controller.view)
        let maximumSize = CGSize(
            width: min(max(window.bounds.width - 48, 120), 300),
            height: 180
        )
        let fittingSize = controller.sizeThatFits(in: maximumSize)
        let hudWidth = min(max(ceil(fittingSize.width), 120), maximumSize.width)
        let hudHeight = min(max(ceil(fittingSize.height), 104), maximumSize.height)
        NSLayoutConstraint.activate([
            controller.view.centerXAnchor.constraint(equalTo: window.centerXAnchor),
            controller.view.centerYAnchor.constraint(equalTo: window.centerYAnchor),
            controller.view.widthAnchor.constraint(equalToConstant: hudWidth),
            controller.view.heightAnchor.constraint(equalToConstant: hudHeight)
        ])
        window.layoutIfNeeded()

        let hudView = controller.view!
        hudView.alpha = 0
        hudView.transform = CGAffineTransform(scaleX: 0.92, y: 0.92)
        UIView.animate(
            withDuration: 0.22,
            delay: 0,
            options: [.curveEaseOut, .allowUserInteraction]
        ) {
            hudView.alpha = 1
            hudView.transform = .identity
        }
        currentView = hudView
        currentController = controller
        UINotificationFeedbackGenerator().notificationOccurred(.success)

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_750_000_000)
            guard currentView === hudView else { return }
            UIView.animate(
                withDuration: 0.18,
                delay: 0,
                options: [.curveEaseIn],
                animations: {
                    hudView.alpha = 0
                    hudView.transform = CGAffineTransform(scaleX: 0.96, y: 0.96)
                },
                completion: { _ in
                    hudView.removeFromSuperview()
                }
            )
            currentView = nil
            currentController = nil
        }
    }

    private static var activeWindow: UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .filter { $0.activationState == .foregroundActive }
            .flatMap(\.windows)
            .first(where: { $0.isKeyWindow })
    }
}

private struct ScreenCompletionHUD: View {
    let message: String
    @State private var checkmarkProgress: CGFloat = 0

    var body: some View {
        Group {
            if #available(iOS 26.0, *) {
                hudContent
                    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            } else {
                hudContent
                    .background(
                        .regularMaterial,
                        in: RoundedRectangle(cornerRadius: 24, style: .continuous)
                    )
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.36)) {
                checkmarkProgress = 1
            }
        }
    }

    private var hudContent: some View {
        VStack(spacing: 10) {
            AnimatedCheckmark(progress: checkmarkProgress)
                .stroke(
                    Color.primary,
                    style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round)
                )
                .frame(width: 38, height: 30)

            Text(message)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 16)
    }
}

private struct AnimatedCheckmark: Shape {
    var progress: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.08, y: rect.midY * 1.03))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.40, y: rect.maxY * 0.84))
        path.addLine(to: CGPoint(x: rect.maxX - rect.width * 0.04, y: rect.minY + rect.height * 0.10))
        return path.trimmedPath(from: 0, to: progress)
    }
}

private struct ContentImageActionsModifier: ViewModifier {
    let source: ContentImageSource
    let presentation: ContentImagePresentation

    @State private var sharedItem: SharedImageItem?
    @State private var showingViewer = false
    @State private var errorMessage: String?

    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            .highPriorityGesture(
                TapGesture().onEnded { showingViewer = true }
            )
            .contextMenu {
                Button {
                    perform { image in
                        ContentImageActions.copy(image)
                    }
                } label: {
                    Label("Copy Image", systemImage: "doc.on.doc")
                }

                Button {
                    perform { image in
                        do {
                            try await ContentImageActions.save(image)
                            ScreenTransientFeedback.showSuccess("Saved to Photos")
                        } catch {
                            errorMessage = readableMessage(for: error)
                        }
                    }
                } label: {
                    Label("Save Image", systemImage: "square.and.arrow.down")
                }

                Button {
                    perform { image in
                        sharedItem = SharedImageItem(image: image)
                    }
                } label: {
                    Label("Share…", systemImage: "square.and.arrow.up")
                }
            }
            .zoomViewerPresentation(isPresented: $showingViewer) {
                CompatibleNavigationContainer {
                    ContentImageViewer(source: source, presentation: presentation)
                }
            }
            .sheet(item: $sharedItem) { item in
                SystemShareSheet(items: [item.image])
            }
            .alert(
                "Unable to Complete Action",
                isPresented: Binding(
                    get: { errorMessage != nil },
                    set: { if !$0 { errorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
    }

    private func perform(_ operation: @escaping @MainActor (UIImage) async -> Void) {
        Task {
            do {
                let image = try await source.load()
                await operation(image)
            } catch {
                errorMessage = readableMessage(for: error)
            }
        }
    }

    private func readableMessage(for error: Error) -> String {
        let message = (error as? LocalizedError)?.errorDescription
            ?? error.localizedDescription
        return message.isEmpty ? "The operation could not be completed." : message
    }
}

struct ContentImageViewer: View {
    let source: ContentImageSource
    var presentation: ContentImagePresentation = .transparent

    @Environment(\.dismiss) private var dismiss
    @State private var image: UIImage?
    @State private var sharedItem: SharedImageItem?
    @State private var errorMessage: String?

    var body: some View {
        GeometryReader { proxy in
            Group {
                if let image {
                    ZoomableContentImage(
                        image: image,
                        backgroundColor: presentation.backgroundColor
                    )
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .frame(width: proxy.size.width, height: proxy.size.height)
                } else if let errorMessage {
                    ContentUnavailableViewCompat(
                        title: "Unable to Load Image",
                        systemImage: "photo.badge.exclamationmark",
                        description: errorMessage
                    )
                } else {
                    ProgressView()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                }
            }
        }
        .navigationTitle("Image")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                }
                .accessibilityLabel("Close")
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    guard let image else { return }
                    sharedItem = SharedImageItem(image: image)
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .disabled(image == nil)
                .accessibilityLabel("Share")
            }
        }
        .sheet(item: $sharedItem) { item in
            SystemShareSheet(items: [item.image])
        }
        .task {
            do {
                image = try await source.load()
                errorMessage = nil
            } catch {
                errorMessage = (error as? LocalizedError)?.errorDescription
                    ?? error.localizedDescription
            }
        }
    }
}

struct ZoomableContentImage: UIViewRepresentable {
    let image: UIImage
    var backgroundColor: UIColor? = nil

    final class Coordinator: NSObject, UIScrollViewDelegate {
        weak var zoomContentView: UIView?

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            zoomContentView
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            (scrollView as? ContentImageScrollView)?.centerZoomContent()
        }
    }

    final class ContentImageScrollView: UIScrollView {
        let zoomContentView = UIView()
        let imageView = UIImageView()

        private var fittedBoundsSize: CGSize = .zero
        private var fittedImageSize: CGSize = .zero

        override init(frame: CGRect) {
            super.init(frame: frame)
            zoomContentView.addSubview(imageView)
            addSubview(zoomContentView)
            imageView.contentMode = .scaleAspectFit
            imageView.clipsToBounds = true
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            layoutFittedContentIfNeeded()
        }

        func configure(image: UIImage, backingColor: UIColor?) {
            let imageChanged = imageView.image !== image
            imageView.image = image
            zoomContentView.backgroundColor = backingColor ?? .clear
            imageView.backgroundColor = backingColor ?? .clear
            backgroundColor = .clear

            if imageChanged {
                setZoomScale(minimumZoomScale, animated: false)
                fittedImageSize = .zero
            }
            setNeedsLayout()
        }

        func centerZoomContent() {
            let horizontalInset = max(0, (bounds.width - zoomContentView.frame.width) / 2)
            let verticalInset = max(0, (bounds.height - zoomContentView.frame.height) / 2)
            contentInset = UIEdgeInsets(
                top: verticalInset,
                left: horizontalInset,
                bottom: verticalInset,
                right: horizontalInset
            )
        }

        private func layoutFittedContentIfNeeded() {
            guard bounds.width > 0, bounds.height > 0,
                  let image = imageView.image,
                  image.size.width > 0, image.size.height > 0 else { return }

            let boundsChanged = abs(fittedBoundsSize.width - bounds.width) > 0.5
                || abs(fittedBoundsSize.height - bounds.height) > 0.5
            guard boundsChanged || fittedImageSize != image.size else {
                centerZoomContent()
                return
            }

            fittedBoundsSize = bounds.size
            fittedImageSize = image.size
            setZoomScale(minimumZoomScale, animated: false)

            let scale = min(bounds.width / image.size.width, bounds.height / image.size.height)
            let fittedSize = CGSize(
                width: max(image.size.width * scale, 1),
                height: max(image.size.height * scale, 1)
            )
            zoomContentView.frame = CGRect(origin: .zero, size: fittedSize)
            imageView.frame = zoomContentView.bounds
            contentSize = fittedSize
            centerZoomContent()
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = ContentImageScrollView()
        scrollView.delegate = context.coordinator
        scrollView.minimumZoomScale = 1
        scrollView.maximumZoomScale = 6
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.contentInsetAdjustmentBehavior = .never
        context.coordinator.zoomContentView = scrollView.zoomContentView
        scrollView.configure(image: image, backingColor: backgroundColor)
        return scrollView
    }

    func updateUIView(_ scrollView: UIScrollView, context: Context) {
        guard let imageScrollView = scrollView as? ContentImageScrollView else { return }
        context.coordinator.zoomContentView = imageScrollView.zoomContentView
        imageScrollView.configure(image: image, backingColor: backgroundColor)
    }
}

private extension UIView {
    var nearestViewController: UIViewController? {
        sequence(first: next, next: { $0?.next })
            .compactMap { $0 as? UIViewController }
            .first
    }
}

private struct ContentUnavailableViewCompat: View {
    let title: String
    let systemImage: String
    let description: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 30, weight: .semibold))
            Text(title)
                .font(.headline)
            Text(description)
                .font(.subheadline)
                .multilineTextAlignment(.center)
        }
        .foregroundStyle(.secondary)
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct SystemShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) { }
}
#endif
