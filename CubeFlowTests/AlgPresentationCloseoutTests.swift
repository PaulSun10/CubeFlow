import Testing
import SwiftUI
import UIKit
@testable import CubeFlow

@Suite("Alg presentation closeout", .serialized)
@MainActor struct AlgPresentationCloseoutTests {
    @Test func exactProbabilityUsesCountsAndDoesNotInventFractions() {
        let locale = Locale(identifier: "en_US")
        #expect(AlgProbabilityPresentation.text(exact: .init(numerator: 2, denominator: 20_736), approximate: nil, locale: locale) == "1/10,368 \u{00B7} 0.00965%")
        #expect(AlgProbabilityPresentation.text(exact: .init(numerator: 6, denominator: 15), approximate: nil, locale: locale) == "2/5 \u{00B7} 40%")
        #expect(AlgProbabilityPresentation.text(exact: nil, approximate: 0.00965, locale: locale) == "\u{2248}0.965%")
        #expect(AlgProbabilityPresentation.text(exact: .init(numerator: 1, denominator: 0), approximate: nil) == nil)
        #expect(AlgExactProbability(numerator: 0, denominator: 10).reduced?.1 == 1)
        for set in [AlgLibrarySet.sq1PBL, .sq1OBL, .sq1CSP] {
            let cases = AlgLibraryLoader.loadRaw(set)?.cases ?? []
            #expect(!cases.isEmpty)
            #expect(cases.allSatisfy { $0.probabilityExact?.value == $0.probability })
        }
    }

    @Test func productionGroupPresentationUsesChineseTerms() {
        for (language, nonParity) in [("zh-Hans", "无特"), ("zh-Hant", "無特")] {
            for set in ["SQ1PBL", "SQ1EP"] {
                #expect(displayAlgGroupTitle(setID: set, title: "Parity", languageCode: language) == "有特")
                #expect(displayAlgGroupTitle(setID: set, title: "Non-Parity", languageCode: language) == nonParity)
            }
            #expect(localizedAlgCaseName(setID: "SQ1CSP", caseName: "Even", languageCode: language) == (language == "zh-Hans" ? "偶数" : "偶數"))
            #expect(appLocalizedString("algs.orientation.inverted", languageCode: language).contains("倒置"))
        }
    }

    @Test func legacyArtworkActuallyWinsOverGeneratedState() throws {
        for set in [AlgLibrarySet.cmll, .pll, .oll, .coll, .f2l, .oneLLL, .lin, .sq1CS, .sq1CO, .sq1EP] {
            let cases = try #require(AlgLibraryLoader.loadRaw(set)?.cases)
            // All CMLL cases, plus representatives from each other affected family.
            for item in set == .cmll ? cases : Array(cases.prefix(1)) {
                let folder = item.imageKey.split(separator: "_").first!.uppercased() + "Images"
                let url = ["Resources/Algs/" + folder, "Algs/" + folder, folder].compactMap {
                    Bundle.main.url(forResource: item.imageKey, withExtension: "png", subdirectory: $0)
                }.first ?? Bundle.main.url(forResource: item.imageKey, withExtension: "png")
                let original = try #require(url.flatMap { UIImage(contentsOfFile: $0.path) })
                let used = try #require(AlgCaseImageProvider.image(named: item.imageKey))
                #expect(used.pngData() == original.pngData())
            }
        }
        for set in [AlgLibrarySet.sq1CSP, .sq1OBL, .sq1PBL, .sq1EPParity] {
            let item = try #require(AlgLibraryLoader.loadRaw(set)?.cases.first)
            #expect(AlgCaseImageProvider.image(named: item.imageKey) != nil)
        }
    }

    @Test func orderedCSPPresentationsBindIdentityParitySetupAndReference() throws {
        let payload = try #require(AlgLibraryLoader.loadRaw(.sq1CSP))
        let normalized = AlgCanonicalCases.normalize(payload)
        #expect(normalized.cases.count == 340)
        var shapes = Set<String>(), contexts = Set<String>(), formulas = Set<String>()
        let solved = SquareOneState(), solvedID = SquareOneCSP.presentationID(state: solved)
        var solvedContexts = 0, regressionContexts = 0
        let fiveCorner = Set(["010101010111", "010101011011", "010101101011"])
        for item in normalized.cases {
            var state = SquareOneState()
            let setupApplied = state.apply(item.setup ?? "")
            #expect(setupApplied)
            let metadata = try #require(item.csp)
            let shape = SquareOneCSP.presentationID(state: state)
            #expect(shape == metadata.shapeID)
            #expect(item.name == SquareOneCSP.presentationPattern(state: state))
            #expect(item.group == item.name)
            #expect(item.algorithmGroups == nil)
            let reference = SquareOneState(top: metadata.referenceTop, bottom: metadata.referenceBottom)
            #expect(SquareOneCSP.presentationID(state: reference) == shape)
            let count = try #require(SquareOneCSP.swapCount(state: state, reference: reference))
            #expect(count == metadata.swapCount && count % 2 == metadata.traceParity)
            let inserted = contexts.insert(shape + ":" + String(metadata.traceParity)).inserted
            #expect(inserted)
            shapes.insert(shape)
            if shape == solvedID { solvedContexts += 1 }
            let layers = shape.split(separator: "|").map(String.init)
            if fiveCorner.contains(layers[0]) && layers[1] == "010111101111" {
                regressionContexts += 1
                #expect(shape != "010101110111|010110101111") // Shield / Muffin.
                #expect(pieceCount(state.top, corners: true) == 5)
                #expect(pieceCount(state.bottom, corners: true) == 3)
            }
            if (fiveCorner.contains(layers[0]) && layers[1] == "010111101111")
                || shape == solvedID || shape == "010101110111|010110101111" {
                let colors = ScrambleColorConfiguration.decode(from: UserDefaults.standard.data(forKey: "scrambleDiagramColorSchemeData"))
                let expected = try #require(SquareOneCaseDiagram.image(setup: item.setup ?? "", colors: colors.squareOne))
                let displayed = try #require(AlgCaseImageProvider.image(named: item.imageKey))
                #expect(displayed.pngData() == expected.pngData())
            }
            let solution = item.algorithms.first?.notation ?? ""
            formulas.insert(solution)
            let solutionApplied = state.apply(solution)
            #expect(solutionApplied && state == solved)
        }
        #expect(shapes.count == 170 && contexts.count == 340 && solvedContexts == 2)
        #expect(formulas.count == 340) // Includes the cube-shape even identity.
        #expect(regressionContexts == 6) // All three five-corner geometries, not a guessed nickname.
    }

    @Test func CSPRecognitionDoesNotSortLayersOrEraseChirality() {
        var asymmetric = SquareOneState()
        let setupApplied = asymmetric.apply("/ (-3,0) / (-2,-1) / (0,3) /")
        #expect(setupApplied)
        let base = SquareOneCSP.presentationID(state: asymmetric)
        #expect(base == "010101110111|010110101111") // Shield / Muffin boundary fixture.
        #expect(SquareOneCSP.presentationID(state: asymmetric.invertedPresentation) != base)
        let aligned = asymmetric.apply("(3,-3)")
        #expect(aligned && SquareOneCSP.presentationID(state: asymmetric) == base)
        #expect(asymmetric.invertedPresentation.invertedPresentation == asymmetric)
        #expect(SquareOneCSP.presentationID(state: SquareOneState().invertedPresentation)
            == SquareOneCSP.presentationID(state: SquareOneState()))
        var chiral = SquareOneState()
        let chiralSetup = chiral.apply("/ (-3,0) /")
        #expect(chiralSetup)
        let reflected = SquareOneState(top: Array(chiral.top.reversed()), bottom: chiral.bottom)
        #expect(SquareOneCSP.presentationID(state: reflected) != SquareOneCSP.presentationID(state: chiral))
    }

    private func pieceCount(_ layer: [Int], corners: Bool) -> Int {
        layer.enumerated().filter { i, v in v != layer[(i + 11) % 12] && (v % 2 == 1) == corners }.count
    }

    @Test func physicalCSPAnchorsHaveIndependentlyRecordedPiecePermutations() throws {
        let cases = try #require(AlgLibraryLoader.loadRaw(.sq1CSP)?.cases)
        func permutation(_ state: SquareOneState, corners: Bool) -> [Int] {
            [state.top, state.bottom].flatMap { ring in
                ring.enumerated().compactMap { i, id in
                    guard id != ring[(i + 11) % 12], (id % 2 == 1) == corners else { return nil }
                    return corners ? (id - 1) / 2 : id / 2
                }
            }
        }
        func sign(_ p: [Int]) -> Int {
            var result = 0
            for i in p.indices { for j in p.indices where j > i && p[i] > p[j] { result ^= 1 } }
            return result
        }
        let shield = try #require(cases.first { $0.id == "csp_010101110111_010101110111_1" })
        var state = SquareOneState()
        let applied = state.apply(shield.setup ?? "")
        #expect(applied)
        let corners = permutation(state, corners: true), edges = permutation(state, corners: false)
        #expect(corners == [7, 1, 0, 6, 5, 3, 2, 4])
        #expect(edges == [0, 6, 1, 7, 2, 4, 3, 5])
        // Diagnostic fixture: fixed-piece-order sign is NOT an unspecified
        // standard-form trace label. Do not turn this into a guessed relabel.
        #expect(sign(corners) == 0 && sign(edges) == 0)
        #expect(shield.sliceCount == 6)
        let solved = state.apply(shield.algorithms[0].notation)
        #expect(solved && state == SquareOneState())
        let control = try #require(cases.first { $0.id == "csp_010101011111_010101110111_0" })
        state = SquareOneState()
        let controlApplied = state.apply(control.setup ?? "")
        #expect(controlApplied)
        #expect(sign(permutation(state, corners: true)) ^ sign(permutation(state, corners: false)) == 0)
        let controlSolved = state.apply(control.algorithms[0].notation)
        #expect(controlSolved && state == SquareOneState())
    }

    @Test func shrinkFitsWholeSixAndSevenScramblesWithoutScrolling() throws {
        guard #available(iOS 16.0, *) else { return }
        let styles = [TimerFontStyleOption.system(weight: .medium, isItalic: false),
            TimerFontStyleOption(id: "fixture-custom", name: "Avenir Next", source: .custom(postScriptName: "AvenirNext-Regular"),
                weightValue: 400, isItalic: false, resolvedFaceSignature: "AvenirNext-Regular")]
        for style in styles {
            for count in [80, 100, 140, 240, 300] {
                let text = Array(repeating: "3Rw2 U' Fw D2 Lw' B", count: count / 6 + 1).joined(separator: " ")
                for width in [220.0, 310.0] {
                    let available = CGSize(width: width, height: 120)
                    let size = TimerScrambleFontFit.size(text: text, available: available, maximum: 20, design: .default, style: style)
                    #expect(size > 0 && size < 20)
                    let renderer = ImageRenderer(content: Text(text).font(Font(TimerFontDesignOption.default.uiFont(size: CGFloat(size), style: style)))
                        .multilineTextAlignment(.center).frame(width: width).fixedSize(horizontal: false, vertical: true))
                    renderer.scale = 1
                    let image = try #require(renderer.uiImage)
                    #expect(image.size.height <= available.height)
                }
            }
        }
    }

    @Test func trailingProbabilityWrapsAtAccessibilitySizes() throws {
        guard #available(iOS 16.0, *) else { return }
        var item = try #require(AlgLibraryLoader.loadRaw(.sq1PBL)?.cases.first)
        item.probabilityExact = AlgExactProbability(numerator: 1, denominator: 10_368)
        var heights = [CGFloat]()
        for size in [DynamicTypeSize.large, .accessibility3, .accessibility5] {
            let renderer = ImageRenderer(content: AlgProbabilityLabel(algCase: item)
                .environment(\.dynamicTypeSize, size))
            renderer.scale = 1
            let image = try #require(renderer.uiImage)
            #expect(image.size.width <= 126)
            heights.append(image.size.height)
        }
        #expect(heights[1] > heights[0] && heights[2] >= heights[1])
    }

    @Test func shrinkRenderedFeedbackFitsWithoutReducingShortScrambles() async throws {
        let style = TimerFontStyleOption.system(weight: .medium, isItalic: false)
        for count in [6, 80, 100, 140, 240] {
            let moves = ["3Rw2", "U'", "Fw", "D2", "Lw'", "B"]
            let text = (0..<count).map { moves[$0 % moves.count] }.joined(separator: " ")
            let available = CGSize(width: 220, height: 60)
            let probe = ShrinkProbe()
            let content = TimerFittingScrambleText(text: text, maximumFontSize: 20, design: .default, style: style) { size in
                // Deliberately exceed the estimator to exercise actual-render feedback.
                Text(text).font(.system(size: size * (count == 6 ? 1 : 2), weight: .medium))
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity)
                    .background {
                        GeometryReader { geometry in
                            Color.clear.onAppear { probe.height = geometry.size.height; probe.size = size }
                                .onChange(of: geometry.size.height) { probe.height = $0 }
                                .onChange(of: size) { probe.size = $0 }
                        }
                    }
            }.frame(width: available.width, height: available.height)
            let host = UIHostingController(rootView: content)
            let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
            let window = UIWindow(windowScene: scene)
            window.frame = CGRect(x: 0, y: 0, width: 260, height: 200)
            window.rootViewController = host; window.isHidden = false
            defer { window.isHidden = true }
            host.view.setNeedsLayout(); host.view.layoutIfNeeded()
            try await Task.sleep(nanoseconds: 250_000_000)
            let height = try #require(probe.height), size = try #require(probe.size)
            #expect(height <= available.height)
            #expect(findScroll(in: host.view) == nil)
            if count == 6 { #expect(size == 20) }
            else {
                let initial = TimerScrambleFontFit.size(text: text, available: available, maximum: 20, design: .default, style: style)
                #expect(size < initial)
            }
        }
    }

    @Test func restoredDetailExportRetainsNormalDiagramAndNotation() async throws {
        let notation = "R U R' U' F2"
        let colors = ScrambleColorConfiguration.default.schemeString(for: "333")
        let diagram = try await ScrambleExportRenderer.render(puzzleKey: "333", scramble: notation,
            colorScheme: colors, kind: .diagramOnly, appearance: .solveDetail(.light))
        let withText = try await ScrambleExportRenderer.render(puzzleKey: "333", scramble: notation,
            colorScheme: colors, kind: .withScramble, appearance: .solveDetail(.light))
        #expect(diagram.size.width > 0 && diagram.size.height > 0)
        #expect(withText.size.height > diagram.size.height)
        #expect(diagram.pngData() != withText.pngData())
    }

    @Test func shrinkUsesFinalPositionedRegionDespiteStaleProposal() async throws {
        let style = TimerFontStyleOption.system(weight: .medium, isItalic: false)
        for count in [6, 100, 240, 500] {
            for position in [0.0, 1.0] {
                let text = (0..<count).map { ["3Rw2", "U'", "Fw", "D2", "Lw'", "B"][$0 % 6] }.joined(separator: " ")
                let probe = PositionedShrinkProbe()
                let root = VStack(spacing: 0) {
                    Color.clear.frame(height: 100)
                    TimerScrambleShrinkViewport(availableHeight: 450, timerTop: 220, coordinateSpace: "shrink-test") { height in
                        let top = TimerArrangementLayout.scrambleTop(availableHeight: height, contentHeight: 44, normalizedPosition: position)
                        HStack(alignment: .top) {
                            TimerFittingScrambleText(text: text, maximumFontSize: 20, design: .default, style: style) { size in
                                Text(text).font(.system(size: size, weight: .medium))
                                    .multilineTextAlignment(.center)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .frame(maxWidth: .infinity)
                                    .background {
                                        GeometryReader { actual in
                                            Color.clear.onAppear { probe.frame = actual.frame(in: .named("shrink-test")); probe.size = size }
                                                .onChange(of: actual.frame(in: .named("shrink-test"))) { probe.frame = $0 }
                                                .onChange(of: size) { probe.size = $0 }
                                        }
                                    }
                            }
                            .frame(height: TimerArrangementLayout.scrollViewportHeight(availableHeight: height, topOffset: top))
                            Color.clear.frame(width: 36, height: 36)
                        }
                        .padding(.top, top)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 24)
                .coordinateSpace(name: "shrink-test")
                .frame(width: 310, height: 600)
                let host = UIHostingController(rootView: root)
                let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
                let window = UIWindow(windowScene: scene)
                window.frame = CGRect(x: 0, y: 0, width: 310, height: 700)
                window.rootViewController = host; window.isHidden = false
                defer { window.isHidden = true }
                host.view.setNeedsLayout(); host.view.layoutIfNeeded()
                try await Task.sleep(nanoseconds: 300_000_000)
                let frame = try #require(probe.frame)
                #expect(frame.minY >= 100 && frame.maxY <= 208)
                #expect(findScroll(in: host.view) == nil)
                if count == 6 && position == 0 { #expect(probe.size == 20) }
            }
        }
    }

    @Test func detailSeparatorUsesExistingGapWithoutChangingContentFrames() throws {
        guard #available(iOS 16.0, *) else { return }
        for scheme in [ColorScheme.light, .dark] {
            func render(separator: Bool) throws -> UIImage {
                let renderer = ImageRenderer(content: VStack(spacing: ScrambleDetailSeparator.contentSpacing) {
                    if separator {
                        Color.clear.frame(height: 120).modifier(ScrambleDetailSeparator())
                    } else {
                        Color.clear.frame(height: 120)
                    }
                    Color.clear.frame(height: 40)
                }
                .frame(width: 250)
                .background(scheme == .light ? Color.white : Color.black)
                .environment(\.colorScheme, scheme))
                renderer.scale = 2
                return try #require(renderer.uiImage)
            }
            let before = try render(separator: false), after = try render(separator: true)
            #expect(before.size == CGSize(width: 250, height: 184))
            #expect(after.size == before.size)
            func pixels(_ image: UIImage) throws -> [UInt8] {
                let cg = try #require(image.cgImage)
                var data = [UInt8](repeating: 0, count: cg.width * cg.height * 4)
                let ctx = try #require(CGContext(data: &data, width: cg.width, height: cg.height,
                    bitsPerComponent: 8, bytesPerRow: cg.width * 4,
                    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
                ctx.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
                return data
            }
            let a = try pixels(before), b = try pixels(after)
            var changedRows = Set<Int>(), changedColumns = Set<Int>()
            for y in 0..<368 {
                for x in 0..<500 {
                    let index = (y * 500 + x) * 4
                    if a[index..<index + 4] != b[index..<index + 4] {
                        changedRows.insert(y); changedColumns.insert(x)
                    }
                }
            }
            #expect(!changedRows.isEmpty)
            #expect(changedRows.allSatisfy { abs(Double($0) / 2 - 132) <= 1 },
                "Changed bitmap rows: \(changedRows.sorted())")
            #expect(changedColumns.count == 500)
        }
    }

    @Test func detailDisplayUsesTransparentDiagramInsteadOfTimerExportBackground() async throws {
        let colors = ScrambleColorConfiguration.default.schemeString(for: "333")
        let display = try await ScrambleExportRenderer.diagramForDisplay(puzzleKey: "333", scramble: "R U R'", colorScheme: colors)
        let cg = try #require(display.cgImage)
        var pixel = [UInt8](repeating: 0, count: 4)
        let context = try #require(CGContext(data: &pixel, width: 1, height: 1, bitsPerComponent: 8,
            bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
        #expect(pixel[3] == 0) // Native Light/Dark background shows through, not baked black/gray.
        for scheme in [ColorScheme.light, .dark] {
            let host = UIHostingController(rootView: ScrambleDiagramSheet(title: "Scramble", puzzleKey: "333",
                scramble: "R U R'", exportAppearance: .solveDetail(.dark)).environment(\.colorScheme, scheme))
            let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
            let window = UIWindow(windowScene: scene)
            window.frame = CGRect(x: 0, y: 0, width: 390, height: 700)
            window.overrideUserInterfaceStyle = scheme == .light ? .light : .dark
            window.rootViewController = host; window.isHidden = false
            defer { window.isHidden = true }
            host.view.setNeedsLayout(); host.view.layoutIfNeeded()
            try await Task.sleep(nanoseconds: 300_000_000)
            #expect(findScroll(in: host.view)?.pinchGestureRecognizer == nil)
            let format = UIGraphicsImageRendererFormat(); format.scale = 1
            let snapshot = UIGraphicsImageRenderer(size: window.bounds.size, format: format).image { _ in
                window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
            let corner = try #require(snapshot.cgImage?.cropping(to: CGRect(x: 10, y: 650, width: 1, height: 1)))
            context.clear(CGRect(x: 0, y: 0, width: 1, height: 1))
            context.draw(corner, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            #expect(scheme == .light ? pixel[0] > 240 : pixel[0] < 15)
        }
    }

    @Test func rootAnchorClipsRealScrollTextEvenWithStaleOversizedProposal() async throws {
        for count in [80, 140, 5_000] {
            let text = Array(repeating: "3Rw2 U' Fw D2 Lw' B", count: count / 6 + 1).joined(separator: " ")
            let probe = ExclusionProbe()
            let root = ZStack {
                Color.white
                Text("0.00").font(.system(size: 72)).foregroundStyle(.blue)
                    .anchorPreference(key: TimerExclusionAnchorPreferenceKey.self, value: .bounds) { $0 }
                    .position(x: 195, y: 310)
            }
            .overlayPreferenceValue(TimerExclusionAnchorPreferenceKey.self) { anchor in
                GeometryReader { proxy in
                    if let anchor {
                        let frame = proxy[anchor]
                        TimerScrambleExclusionLayer(timerTop: frame.minY) {
                            VStack(spacing: 0) {
                                Color.clear.frame(height: 100)
                                HStack(alignment: .top) {
                                    ScrollView {
                                        Text(text).font(.system(size: 20, weight: .medium))
                                            .foregroundStyle(Color(red: 1, green: 0, blue: 0))
                                            .multilineTextAlignment(.center)
                                            .fixedSize(horizontal: false, vertical: true)
                                            .frame(maxWidth: .infinity)
                                    }
                                    .frame(height: 450) // Simulate a stale/animated child proposal.
                                    Color.clear.frame(width: 32, height: 32)
                                }
                                .padding(.horizontal, 24)
                                Spacer(minLength: 0)
                            }
                        }
                        .onAppear {
                            probe.frame = frame
                            probe.origin = proxy.frame(in: .global).origin
                        }
                    }
                }
            }
            .frame(width: 390, height: 600)
            let host = UIHostingController(rootView: root)
            let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
            let window = UIWindow(windowScene: scene)
            window.frame = CGRect(x: 0, y: 0, width: 390, height: 600)
            window.rootViewController = host
            window.isHidden = false
            defer { window.isHidden = true }
            host.view.setNeedsLayout(); host.view.layoutIfNeeded()
            try await Task.sleep(nanoseconds: 150_000_000)
            let frame = try #require(probe.frame)
            let origin = try #require(probe.origin)
            let windowFrame = frame.offsetBy(dx: origin.x, dy: origin.y)
            for end in [false, true] {
                if end, let scroll = findScroll(in: host.view) {
                    scroll.setContentOffset(CGPoint(x: 0, y: max(0, scroll.contentSize.height - scroll.bounds.height)), animated: false)
                }
                // Snapshot at native scale: downsampling fabricates a one-pixel halo.
                let format = UIGraphicsImageRendererFormat(); format.scale = scene.screen.scale
                let image = UIGraphicsImageRenderer(size: window.bounds.size, format: format).image { _ in
                    window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
                }
                let cg = try #require(image.cgImage)
                let pixelScale = CGFloat(cg.width) / window.bounds.width
                var pixels = [UInt8](repeating: 0, count: cg.width * cg.height * 4)
                let ctx = try #require(CGContext(data: &pixels, width: cg.width, height: cg.height, bitsPerComponent: 8,
                    bytesPerRow: cg.width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
                ctx.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
                var visibleRed = 0, escapedRed = 0, blueTop = cg.height, blueBottom = 0, visibleBlue = 0
                for y in 0..<cg.height { for x in 0..<cg.width {
                    let i = (y * cg.width + x) * 4
                    if Int(pixels[i + 2]) > Int(pixels[i]) + 30 && Int(pixels[i + 2]) > Int(pixels[i + 1]) + 30 {
                        visibleBlue += 1
                        blueTop = min(blueTop, y); blueBottom = max(blueBottom, y)
                    }
                    if Int(pixels[i]) > Int(pixels[i + 1]) + 5 && abs(Int(pixels[i + 1]) - Int(pixels[i + 2])) < 3 {
                        visibleRed += 1
                        if CGFloat(y) >= ceil((windowFrame.minY - 12) * pixelScale) { escapedRed += 1 }
                    }
                } }
                #expect(visibleBlue > 0)
                #expect(CGFloat(blueTop) >= windowFrame.minY * pixelScale && CGFloat(blueBottom) < windowFrame.maxY * pixelScale)
                #expect(visibleRed > 0)
                #expect(escapedRed == 0)
                if count == 5_000 && !end {
                    try image.pngData()?.write(to: URL(fileURLWithPath: "/tmp/cubeflow-alg-closeout/scroll-clipping.png"))
                }
            }
        }
    }

    private func findScroll(in view: UIView) -> UIScrollView? {
        if let scroll = view as? UIScrollView { return scroll }
        for child in view.subviews { if let scroll = findScroll(in: child) { return scroll } }
        return nil
    }
}

@MainActor private final class ExclusionProbe { var frame: CGRect?; var origin: CGPoint? }
@MainActor private final class ShrinkProbe { var height: CGFloat?; var size: Double? }
@MainActor private final class PositionedShrinkProbe { var frame: CGRect?; var size: Double? }
