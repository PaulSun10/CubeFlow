#if os(iOS)
import SwiftUI
import WebKit

struct ScrambleDiagramView: View {
    let puzzleKey: String
    let scramble: String

    var body: some View {
        ScrambleDiagramWebView(puzzleKey: puzzleKey, scramble: scramble)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.clear)
    }
}

struct ScrambleDiagramSheet: View {
    let title: LocalizedStringKey
    let puzzleKey: String
    let scramble: String

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrambleDiagramView(puzzleKey: puzzleKey, scramble: scramble)
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("common.done") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

private struct ScrambleDiagramWebView: UIViewRepresentable {
    let puzzleKey: String
    let scramble: String

    final class Coordinator {
        var lastPuzzleKey: String?
        var lastScramble: String?
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        loadIfNeeded(webView, coordinator: context.coordinator, force: true)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        loadIfNeeded(webView, coordinator: context.coordinator, force: false)
    }

    private func loadIfNeeded(_ webView: WKWebView, coordinator: Coordinator, force: Bool) {
        guard force || coordinator.lastPuzzleKey != puzzleKey || coordinator.lastScramble != scramble else {
            return
        }
        coordinator.lastPuzzleKey = puzzleKey
        coordinator.lastScramble = scramble
        webView.loadHTMLString(Self.html(puzzleKey: puzzleKey, scramble: scramble), baseURL: Bundle.main.resourceURL)
    }

    private static func html(puzzleKey: String, scramble: String) -> String {
        let sourceMap: [String: String] = [
            "main": loadJavaScript(relativePath: "main.js"),
            "mathlib": loadJavaScript(relativePath: "mathlib.js"),
            "cubes/nnn": loadJavaScript(relativePath: "cubes/nnn.js"),
            "cubes/clk": loadJavaScript(relativePath: "cubes/clk.js"),
            "cubes/megaminx": loadJavaScript(relativePath: "cubes/megaminx.js"),
            "cubes/pyraminx": loadJavaScript(relativePath: "cubes/pyraminx.js"),
            "cubes/skewb": loadJavaScript(relativePath: "cubes/skewb.js"),
            "cubes/squareone": loadJavaScript(relativePath: "cubes/squareone.js"),
        ]

        let sourceEntries = sourceMap.map { key, value in
            "\(javaScriptLiteral(key)): \(javaScriptLiteral(value))"
        }
        .sorted()
        .joined(separator: ",\n")

        return """
        <!doctype html>
        <html>
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0">
          <style>
            :root { color-scheme: light dark; }
            html, body {
              margin: 0;
              padding: 0;
              width: 100%;
              height: 100%;
              background: transparent;
              overflow: hidden;
              font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif;
            }
            body {
              display: flex;
              align-items: center;
              justify-content: center;
              min-height: 0;
            }
            #wrap {
              width: 100%;
              height: 100%;
              display: flex;
              align-items: center;
              justify-content: center;
              padding: 0;
              box-sizing: border-box;
            }
            #diagram {
              width: 100%;
              height: 100%;
              object-fit: contain;
              display: none;
            }
            #message {
              color: rgba(60, 60, 67, 0.7);
              font-size: 15px;
              text-align: center;
              padding: 16px;
            }
          </style>
        </head>
        <body>
          <div id="wrap">
            <img id="diagram" alt="Scramble diagram" />
            <div id="message">Rendering scramble…</div>
          </div>
          <script>
            const sourceMap = {
            \(sourceEntries)
            };

            const factories = {};
            const cache = {};

            const canvasShim = {
              createCanvas: function(width, height) {
                const canvas = document.createElement("canvas");
                canvas.width = width;
                canvas.height = height;
                canvas.toBuffer = () => canvas.toDataURL("image/png");
                return canvas;
              }
            };

            function normalize(parts) {
              const output = [];
              for (const part of parts) {
                if (!part || part === ".") continue;
                if (part === "..") output.pop();
                else output.push(part);
              }
              return output.join("/");
            }

            function stripExtension(path) {
              return path.endsWith(".js") ? path.slice(0, -3) : path;
            }

            function resolve(from, request) {
              if (request === "canvas") return "canvas";
              if (!request.startsWith(".")) return stripExtension(request);
              const base = from.split("/");
              base.pop();
              return stripExtension(normalize(base.concat(request.split("/"))));
            }

            function defineModule(name, source) {
              factories[name] = new Function("require", "module", "exports", source);
            }

            function requireModule(name) {
              if (name === "canvas") return canvasShim;
              if (cache[name]) return cache[name].exports;
              const factory = factories[name];
              if (!factory) throw new Error("Missing module: " + name);
              const module = { exports: {} };
              cache[name] = module;
              const localRequire = (request) => requireModule(resolve(name, request));
              factory(localRequire, module, module.exports);
              return module.exports;
            }

            Object.entries(sourceMap).forEach(([name, source]) => defineModule(name, source));

            function render() {
              const image = document.getElementById("diagram");
              const message = document.getElementById("message");
              try {
                const scrambleImage = requireModule("main");
                const result = scrambleImage.genImage(\(javaScriptLiteral(puzzleKey)), \(javaScriptLiteral(scramble)), "default");
                const dataURL = typeof result === "string"
                  ? result
                  : (result && typeof result.toDataURL === "function" ? result.toDataURL("image/png") : "");
                if (!dataURL) throw new Error("Empty render result");
                image.src = dataURL;
                image.style.display = "block";
                message.style.display = "none";
              } catch (error) {
                console.error(error);
                message.textContent = "Unable to render scramble: " + String((error && (error.stack || error.message)) || error);
                image.style.display = "none";
              }
            }

            render();
          </script>
        </body>
        </html>
        """
    }

    private static func loadJavaScript(relativePath: String) -> String {
        for candidate in resourceCandidates(relativePath: relativePath) {
            if let url = candidate, let content = try? String(contentsOf: url, encoding: .utf8) {
                return content
            }
        }
        return ""
    }

    private static func resourceCandidates(relativePath: String) -> [URL?] {
        let relative = relativePath.split(separator: "/").map(String.init)
        let fileName = relative.last
        let base = Bundle.main.resourceURL
        let drawScramble = base?.appendingPathComponent("DrawScramble", isDirectory: true)
        let resourcesDrawScramble = base?.appendingPathComponent("Resources/DrawScramble", isDirectory: true)

        func append(_ root: URL?) -> URL? {
            relative.reduce(root) { partial, component in
                partial?.appendingPathComponent(component, isDirectory: false)
            }
        }

        return [
            append(drawScramble),
            append(resourcesDrawScramble),
            drawScramble.flatMap { root in fileName.map { root.appendingPathComponent($0, isDirectory: false) } },
            resourcesDrawScramble.flatMap { root in fileName.map { root.appendingPathComponent($0, isDirectory: false) } },
            append(base)
        ] + [base.flatMap { root in fileName.map { root.appendingPathComponent($0, isDirectory: false) } }]
    }

    private static func javaScriptLiteral(_ string: String) -> String {
        let data = try? JSONSerialization.data(withJSONObject: [string])
        let encoded = data.flatMap { String(data: $0, encoding: .utf8) } ?? "[\"\"]"
        return String(encoded.dropFirst().dropLast())
    }
}
#endif
