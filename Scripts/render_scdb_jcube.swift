import AppKit
import Foundation
import WebKit

struct AlgSetPayload: Decodable {
    let cases: [AlgCase]
}

struct AlgCase: Decodable {
    let imageKey: String
    let stickers: Stickers?
}

struct Stickers: Decodable {
    let us: String?
    let ub: String?
    let uf: String?
    let ul: String?
    let ur: String?
    let fl: String?
}

final class JCubeRenderer: NSObject, WKNavigationDelegate {
    private let cases: [AlgCase]
    private let outputDirectory: URL
    private let app = NSApplication.shared
    private let webView: WKWebView
    private var currentIndex = 0

    init(cases: [AlgCase], outputDirectory: URL) {
        self.cases = cases
        self.outputDirectory = outputDirectory
        self.webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 75, height: 75))
        super.init()
        webView.setValue(false, forKey: "drawsBackground")
        webView.navigationDelegate = self
        app.setActivationPolicy(.prohibited)
    }

    func start() {
        loadCurrentCase()
        app.run()
    }

    private func loadCurrentCase() {
        guard currentIndex < cases.count else {
            app.terminate(nil)
            return
        }

        let algCase = cases[currentIndex]
        guard let stickers = algCase.stickers else {
            currentIndex += 1
            loadCurrentCase()
            return
        }

        let cubeMarkup: String
        if let fl = stickers.fl {
            cubeMarkup = """
            <div class="icube" data-width="75" data-height="75" data-rank="3" data-fl="\(fl)"></div>
            """
        } else if
            let us = stickers.us,
            let ub = stickers.ub,
            let uf = stickers.uf,
            let ul = stickers.ul,
            let ur = stickers.ur
        {
            cubeMarkup = """
            <div class="jcube" data-width="75" data-height="75" data-rank="3" data-us="\(us)" data-ub="\(ub)" data-uf="\(uf)" data-ul="\(ul)" data-ur="\(ur)"></div>
            """
        } else {
            currentIndex += 1
            loadCurrentCase()
            return
        }

        let html = """
        <!doctype html>
        <html>
        <head>
        <meta charset="utf-8">
        <style>
        html, body { margin: 0; padding: 0; width: 75px; height: 75px; overflow: hidden; background: transparent; }
        .jcube, .icube { width: 75px; height: 75px; }
        </style>
        <script src="https://cdnjs.cloudflare.com/ajax/libs/jquery/3.6.1/jquery.min.js"></script>
        <script src="https://cdnjs.cloudflare.com/ajax/libs/svg.js/3.1.2/svg.min.js"></script>
        <script src="https://www.speedcubedb.com/includes/ijsm.js?d=2"></script>
        </head>
        <body>
        \(cubeMarkup)
        </body>
        </html>
        """

        webView.loadHTMLString(html, baseURL: URL(string: "https://www.speedcubedb.com/"))
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            webView.evaluateJavaScript("document.querySelector('.jcube svg, .icube svg')?.outerHTML.length") { [weak self] result, error in
                guard let self else { return }
                if let error {
                    print("svg eval error:", error.localizedDescription)
                }

                guard let count = result as? Int, count > 0 else {
                    print("svg not rendered for", self.cases[self.currentIndex].imageKey)
                    self.currentIndex += 1
                    self.loadCurrentCase()
                    return
                }

                let config = WKSnapshotConfiguration()
                config.rect = CGRect(x: 0, y: 0, width: 75, height: 75)
                webView.takeSnapshot(with: config) { image, error in
                    if let error {
                        print("snapshot error:", error.localizedDescription)
                    }

                    if let image,
                       let tiff = image.tiffRepresentation,
                       let rep = NSBitmapImageRep(data: tiff),
                       let png = rep.representation(using: .png, properties: [:]) {
                        let fileURL = self.outputDirectory.appendingPathComponent("\(self.cases[self.currentIndex].imageKey).png")
                        try? png.write(to: fileURL)
                    } else {
                        print("snapshot missing image for", self.cases[self.currentIndex].imageKey)
                    }

                    self.currentIndex += 1
                    self.loadCurrentCase()
                }
            }
        }
    }
}

let jsonPath = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "/Users/paulsun/Desktop/Projects/CubeFlow/CubeFlow/Resources/Algs/pll.json"
let outputPath = CommandLine.arguments.count > 2
    ? CommandLine.arguments[2]
    : "/Users/paulsun/Desktop/Projects/CubeFlow/CubeFlow/Resources/Algs/PLLImages"

let payload = try JSONDecoder().decode(AlgSetPayload.self, from: Data(contentsOf: URL(fileURLWithPath: jsonPath)))
let outputDirectory = URL(fileURLWithPath: outputPath, isDirectory: true)

try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

let renderer = JCubeRenderer(cases: payload.cases, outputDirectory: outputDirectory)
renderer.start()
