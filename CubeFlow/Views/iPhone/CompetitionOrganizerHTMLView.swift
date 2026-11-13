#if os(iOS)
import SwiftUI
import WebKit

/// Organizer documents need browser table/image layout, not flattened runs of
/// attributed text. Only our nonce-bearing sizing script may execute.
struct CompetitionOrganizerHTMLView: View {
    let html: String
    let baseURL: URL?
    @State private var height: CGFloat = 1
    @Environment(\.openURL) private var openURL
    @Environment(\.colorScheme) private var colorScheme
    @ScaledMetric(relativeTo: .body) private var textSize: CGFloat = 17

    var body: some View {
        // In a vertical ScrollView the native document may report a wider
        // ideal width. Give WebKit the viewport width, not its content width.
        GeometryReader { viewport in
            OrganizerWebDocument(html: html, baseURL: baseURL, dark: colorScheme == .dark,
                textSize: textSize, height: $height, open: { openURL($0) })
                .frame(width: viewport.size.width, height: height)
        }
        .frame(height: height)
        .padding(14)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
    }
}

struct OrganizerWebDocument: UIViewRepresentable {
    let html: String
    let baseURL: URL?
    let dark: Bool
    let textSize: CGFloat
    @Binding var height: CGFloat
    let open: (URL) -> Void

    static func sectionKey(for id: String) -> String? {
        ["information", "regulations", "travel", "registration"].first {
            id == "cubing-v2-\($0)" || id.hasPrefix("cubing-v2-organizer-\($0)-")
        }
    }

    static func sourceURL(slug: String?, section: String) -> URL {
        let key = sectionKey(for: section) ?? "information"
        let suffix = key == "information" ? "" : "/\(key)"
        if let slug, let url = URL(string: "https://cubing.com/competition/\(slug)\(suffix)") { return url }
        return URL(string: "https://cubing.com/")!
    }

    static func document(_ html: String, nonce: String, dark: Bool, textSize: CGFloat) -> String {
        let clean = CubingChinaSemanticHTML.sanitize(html)
        return """
        <!doctype html><html data-cf-nonce="\(nonce)" data-cf-dark="\(dark)" style="--cf-font:\(textSize)px"><head><meta name="viewport" content="width=device-width,initial-scale=1">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src https: data:; style-src 'unsafe-inline'; script-src 'nonce-\(nonce)'; base-uri 'none'; form-action 'none'">
        <style>
        :root{color-scheme:light;--ink:#1c1c1e;--link:#006dcc;--rule:#d6d6dc;--panel:#f2f2f7}
        :root[data-cf-dark="true"]{color-scheme:dark;--ink:#f5f5f7;--link:#64aaff;--rule:#48484a;--panel:#2c2c2e}
        html,body{margin:0!important;padding:0!important;width:100%!important;overflow-x:hidden}
        body{font:var(--cf-font) -apple-system;line-height:1.5;color:var(--ink);overflow-wrap:anywhere;-webkit-text-size-adjust:100%}
        #cf-content{display:flow-root}
        #cf-content :is(.prose,.cc-card,.cc-card__body,.cc-hero__panel,.cc-hero__body,p,h1,h2,h3,h4,h5,h6,li,blockquote,td,th){
          height:auto!important;max-height:none!important;overflow:visible!important}
        #cf-content :is(p,li,blockquote,td,th){line-height:1.5!important}
        #cf-content :is(div,section,article,figure){box-sizing:border-box;min-width:0!important;max-width:100%!important}
        #cf-content :is(h1,h2,h3,h4,h5,h6){line-height:1.25!important;margin:.9em 0 .45em}
        #cf-content :is(p,ul,ol,figure,blockquote){margin:.55em 0}
        ul,ol{padding-inline-start:1.45em}li+li{margin-block-start:.25em}
        blockquote{border-inline-start:2px solid var(--rule);padding-inline-start:.7em}
        img,video{max-width:100%!important;height:auto!important}a{color:var(--link)}
        [data-cc-block]{display:flow-root;box-sizing:border-box;margin:.8em 0;padding:.75em;
          border:1px solid var(--rule);border-radius:12px;background:var(--panel)}
        .cc-card__header{display:flex;align-items:baseline;gap:.5em}
        .cc-card__header :is(h2,h3,h4){margin:0 0 .35em;min-width:0}
        .cc-hero__bg[alt=""]{display:none}
        .cf-table{overflow-x:auto;max-width:100%;margin:.7em 0;-webkit-overflow-scrolling:touch}
        table{border-collapse:collapse}td,th{padding:6px;vertical-align:top;border:1px solid var(--rule)}
        th{background:var(--panel);text-align:start}
        p:first-child{margin-top:0}p:last-child{margin-bottom:0}iframe,object,embed,form{display:none!important}
        </style></head><body><main id="cf-content">\(clean)</main>
        <script nonce="\(nonce)">
        document.querySelectorAll('table').forEach(table=>{const box=document.createElement('div');box.className='cf-table';table.before(box);box.append(table)});
        const content=document.getElementById('cf-content');
        const range=document.createRange();
        let previousHeight=0, previousWidth=0, previousFlow=0, pending=false, force=false;
        const send=()=>{
            pending=false;
            const rect=content.getBoundingClientRect();
            const width=document.documentElement.clientWidth;
            if(width<=0)return;
            const flow=Math.ceil(Math.max(rect.height,content.scrollHeight));
            const shouldMeasure=force || flow!==previousFlow || width!==previousWidth;
            force=false;
            if(!shouldMeasure)return;
            previousFlow=flow;
            range.selectNodeContents(content);
            const extent=range.getBoundingClientRect().bottom-rect.top;
            const height=Math.max(flow,Math.ceil(extent));
            if(height===previousHeight && width===previousWidth)return;
            previousHeight=height;previousWidth=width;
            window.webkit.messageHandlers.documentHeight.postMessage({nonce:'\(nonce)',height,width});
        };
        const measure=(contentChanged=false)=>{
            force=force||contentChanged;
            if(pending)return;
            pending=true;requestAnimationFrame(send);
        };
        new ResizeObserver(()=>measure(true)).observe(content,{box:'border-box'});
        content.addEventListener('load',()=>measure(true),true);
        content.addEventListener('error',()=>measure(true),true);
        window.addEventListener('resize',()=>measure());
        document.fonts.ready.then(()=>measure(true));
        measure();
        </script></body></html>
        """
    }

    static func sameDocumentURL(_ lhs: URL?, _ rhs: URL?) -> Bool {
        guard let lhs, let rhs else { return false }
        func path(_ url: URL) -> String { url.path.isEmpty ? "/" : url.path }
        return lhs.scheme?.lowercased() == rhs.scheme?.lowercased()
            && lhs.host?.lowercased() == rhs.host?.lowercased()
            && lhs.port == rhs.port && path(lhs) == path(rhs) && lhs.query == rhs.query
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.preferences.javaScriptCanOpenWindowsAutomatically = false
        config.userContentController.add(context.coordinator, name: "documentHeight")
        let web = WKWebView(frame: .zero, configuration: config)
        context.coordinator.web = web
        web.navigationDelegate = context.coordinator
        web.isOpaque = false; web.backgroundColor = .clear
        web.scrollView.backgroundColor = .clear
        web.scrollView.isScrollEnabled = false
        web.scrollView.contentInsetAdjustmentBehavior = .never
        return web
    }
    func updateUIView(_ web: WKWebView, context: Context) {
        context.coordinator.parent = self
        let source = Source(html: html, baseURL: baseURL)
        let style = Style(dark: dark, textSize: textSize)
        if context.coordinator.source == source {
            context.coordinator.apply(style, to: web)
            return
        }
        context.coordinator.source = source
        context.coordinator.style = style
        let nonce = UUID().uuidString
        context.coordinator.nonce = nonce
        web.stopLoading()
        web.loadHTMLString(Self.document(html, nonce: nonce, dark: dark, textSize: textSize), baseURL: baseURL)
    }
    static func dismantleUIView(_ web: WKWebView, coordinator: Coordinator) {
        web.stopLoading(); web.navigationDelegate = nil
        web.configuration.userContentController.removeScriptMessageHandler(forName: "documentHeight")
    }
    struct Source: Equatable { let html: String; let baseURL: URL? }
    struct Style: Equatable { let dark: Bool; let textSize: CGFloat }
    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        var parent: OrganizerWebDocument
        weak var web: WKWebView?
        var nonce = ""
        var source: Source?
        var style: Style?
        init(_ parent: OrganizerWebDocument) { self.parent = parent }
        func apply(_ next: Style, to web: WKWebView) {
            guard style != next else { return }
            style = next
            if !web.isLoading { applyCurrentStyle(to: web) }
        }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            applyCurrentStyle(to: webView)
        }
        private func applyCurrentStyle(to web: WKWebView) {
            guard let style, style.textSize.isFinite else { return }
            web.evaluateJavaScript("""
                if (document.documentElement.dataset.cfNonce === '\(nonce)') {
                    document.documentElement.dataset.cfDark = '\(style.dark)';
                    document.documentElement.style.setProperty('--cf-font', '\(style.textSize)px');
                }
                """, completionHandler: nil)
        }
        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.frameInfo.isMainFrame, let body = message.body as? [String: Any],
                  body["nonce"] as? String == nonce, let number = body["height"] as? Double, number.isFinite,
                  let width = body["width"] as? Double, let web, abs(web.bounds.width - width) <= 1 else { return }
            let next = max(1, ceil(number))
            if abs(parent.height - next) > 0.5 { parent.height = next }
        }
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            // Rapid loadHTMLString calls can deliver superseded initial-policy
            // callbacks. A shared one-shot flag lets an older load block the
            // newest one; validate each synthetic load against the current base.
            if action.navigationType == .other,
               action.targetFrame?.isMainFrame == true,
               Self.initialDocumentAllowed(action.request.url, base: parent.baseURL) {
                decisionHandler(.allow)
                return
            }
            if action.navigationType == .linkActivated, let url = action.request.url {
                if ["https", "http", "mailto", "tel"].contains(url.scheme?.lowercased() ?? "") { parent.open(url) }
                decisionHandler(.cancel)
            } else {
                decisionHandler(.cancel)
            }
        }
        private static func initialDocumentAllowed(_ url: URL?, base: URL?) -> Bool {
            OrganizerWebDocument.sameDocumentURL(url, base) || url?.scheme == "about"
        }
    }
}
#endif
