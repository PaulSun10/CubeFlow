import SwiftUI
import UIKit

enum AlgPuzzle: String, CaseIterable, Identifiable {
    case twoByTwo = "2x2"
    case threeByThree = "3x3"
    case fourByFour = "4x4"
    case fiveByFive = "5x5"
    case sixBySix = "6x6"
    case sevenBySeven = "7x7"
    case megaminx = "Megaminx"
    case pyraminx = "Pyraminx"
    case squareOne = "Square-1"
    case clock = "Clock"
    case skewb = "Skewb"
    case threeByThreeBLD = "3x3 bld"
    case fourByFourBLD = "4x4 bld"
    case fiveByFiveBLD = "5x5 bld"

    var id: String { rawValue }

    var localizedTitleKey: String {
        switch self {
        case .twoByTwo: return "event.2x2"
        case .threeByThree: return "event.3x3"
        case .fourByFour: return "event.4x4"
        case .fiveByFive: return "event.5x5"
        case .sixBySix: return "event.6x6"
        case .sevenBySeven: return "event.7x7"
        case .megaminx: return "event.megaminx"
        case .pyraminx: return "event.pyraminx"
        case .squareOne: return "event.square1"
        case .clock: return "event.clock"
        case .skewb: return "event.skewb"
        case .threeByThreeBLD: return "event.3x3bld"
        case .fourByFourBLD: return "event.4x4bld"
        case .fiveByFiveBLD: return "event.5x5bld"
        }
    }

    static var regularCases: [AlgPuzzle] {
        [
            .twoByTwo,
            .threeByThree,
            .fourByFour,
            .fiveByFive,
            .squareOne,
            .megaminx,
            .pyraminx,
            .skewb
        ]
    }

    static var blindfoldedCases: [AlgPuzzle] {
        []
    }
}

struct AlgSectionData: Identifiable {
    let id: String
    let localizedTitleKey: LocalizedStringKey
    let items: [AlgItemData]

    private static func caseCount(for setID: String) -> Int {
        guard let set = AlgLibrarySet(itemID: setID),
              let payload = AlgLibraryLoader.load(set) else {
            return 0
        }
        return payload.cases.count
    }

    private static func item(id: String, titleKey: String, descriptionKey: String) -> AlgItemData {
        AlgItemData(
            id: id,
            localizedTitleKey: LocalizedStringKey(titleKey),
            algorithmCount: caseCount(for: id),
            localizedDescriptionKey: LocalizedStringKey(descriptionKey)
        )
    }

    static let threeByThreeSections: [AlgSectionData] = [
        AlgSectionData(
            id: "cfop",
            localizedTitleKey: "algs.section.cfop",
            items: [
                AlgItemData(
                    id: "f2l",
                    localizedTitleKey: "algs.item.f2l.title",
                    algorithmCount: 41,
                    localizedDescriptionKey: "algs.item.f2l.description"
                ),
                AlgItemData(
                    id: "oll",
                    localizedTitleKey: "algs.item.oll.title",
                    algorithmCount: 57,
                    localizedDescriptionKey: "algs.item.oll.description"
                ),
                AlgItemData(
                    id: "pll",
                    localizedTitleKey: "algs.item.pll.title",
                    algorithmCount: 21,
                    localizedDescriptionKey: "algs.item.pll.description"
                )
            ]
        ),
        AlgSectionData(
            id: "advanced",
            localizedTitleKey: "algs.section.advanced",
            items: [
                AlgItemData(
                    id: "advancedf2l",
                    localizedTitleKey: "algs.item.advancedf2l.title",
                    algorithmCount: 54,
                    localizedDescriptionKey: "algs.item.advancedf2l.description"
                ),
                AlgItemData(
                    id: "coll",
                    localizedTitleKey: "algs.item.coll.title",
                    algorithmCount: 40,
                    localizedDescriptionKey: "algs.item.coll.description"
                ),
                AlgItemData(
                    id: "wv",
                    localizedTitleKey: "algs.item.wv.title",
                    algorithmCount: 27,
                    localizedDescriptionKey: "algs.item.wv.description"
                ),
                AlgItemData(
                    id: "sv",
                    localizedTitleKey: "algs.item.sv.title",
                    algorithmCount: 27,
                    localizedDescriptionKey: "algs.item.sv.description"
                ),
                AlgItemData(
                    id: "cls",
                    localizedTitleKey: "algs.item.cls.title",
                    algorithmCount: 97,
                    localizedDescriptionKey: "algs.item.cls.description"
                )
            ]
        ),
        AlgSectionData(
            id: "roux",
            localizedTitleKey: "algs.section.roux",
            items: [
                AlgItemData(
                    id: "sbls",
                    localizedTitleKey: "algs.item.sbls.title",
                    algorithmCount: 65,
                    localizedDescriptionKey: "algs.item.sbls.description"
                ),
                AlgItemData(
                    id: "cmll",
                    localizedTitleKey: "algs.item.cmll.title",
                    algorithmCount: 42,
                    localizedDescriptionKey: "algs.item.cmll.description"
                ),
                AlgItemData(
                    id: "4a",
                    localizedTitleKey: "algs.item.4a.title",
                    algorithmCount: 9,
                    localizedDescriptionKey: "algs.item.4a.description"
                )
            ]
        ),
        AlgSectionData(
            id: "large_sets",
            localizedTitleKey: "algs.section.large_sets",
            items: [
                AlgItemData(
                    id: "zbll",
                    localizedTitleKey: "algs.item.zbll.title",
                    algorithmCount: 472,
                    localizedDescriptionKey: "algs.item.zbll.description"
                ),
                AlgItemData(
                    id: "vls",
                    localizedTitleKey: "algs.item.vls.title",
                    algorithmCount: 189,
                    localizedDescriptionKey: "algs.item.vls.description"
                ),
                AlgItemData(
                    id: "ollcp",
                    localizedTitleKey: "algs.item.ollcp.title",
                    algorithmCount: 342,
                    localizedDescriptionKey: "algs.item.ollcp.description"
                ),
                AlgItemData(
                    id: "zbls",
                    localizedTitleKey: "algs.item.zbls.title",
                    algorithmCount: 302,
                    localizedDescriptionKey: "algs.item.zbls.description"
                ),
                AlgItemData(
                    id: "1lll",
                    localizedTitleKey: "algs.item.1lll.title",
                    algorithmCount: 3914,
                    localizedDescriptionKey: "algs.item.1lll.description"
                )
            ]
        )
    ]

    static let twoByTwoSections: [AlgSectionData] = [
        AlgSectionData(
            id: "ortega_method",
            localizedTitleKey: "algs.section.ortega_method",
            items: [
                item(id: "ortegaoll", titleKey: "algs.item.ortegaoll.title", descriptionKey: "algs.item.ortegaoll.description"),
                item(id: "ortegapbl", titleKey: "algs.item.ortegapbl.title", descriptionKey: "algs.item.ortegapbl.description")
            ]
        ),
        AlgSectionData(
            id: "cll_eg_method",
            localizedTitleKey: "algs.section.cll_eg_method",
            items: [
                item(id: "cll", titleKey: "algs.item.cll.title", descriptionKey: "algs.item.cll.description"),
                item(id: "eg1", titleKey: "algs.item.eg1.title", descriptionKey: "algs.item.eg1.description"),
                item(id: "eg2", titleKey: "algs.item.eg2.title", descriptionKey: "algs.item.eg2.description")
            ]
        )
    ]

    static let fourByFourSections: [AlgSectionData] = [
        AlgSectionData(
            id: "four_by_four",
            localizedTitleKey: "algs.section.parity",
            items: [
                item(id: "ollparity", titleKey: "algs.item.ollparity.title", descriptionKey: "algs.item.ollparity.description"),
                item(id: "pllparity", titleKey: "algs.item.pllparity.title", descriptionKey: "algs.item.pllparity.description")
            ]
        )
    ]

    static let fiveByFiveSections: [AlgSectionData] = [
        AlgSectionData(
            id: "five_by_five",
            localizedTitleKey: "algs.section.reduction_finish",
            items: [
                item(id: "l2e", titleKey: "algs.item.l2e.title", descriptionKey: "algs.item.l2e.description"),
                item(id: "l2c", titleKey: "algs.item.l2c.title", descriptionKey: "algs.item.l2c.description")
            ]
        )
    ]

    static let squareOneSections: [AlgSectionData] = [
        AlgSectionData(
            id: "square_one",
            localizedTitleKey: "algs.section.vandenbergh_method",
            items: [
                item(id: "sq1cs", titleKey: "algs.item.sq1cs.title", descriptionKey: "algs.item.sq1cs.description"),
                item(id: "sq1co", titleKey: "algs.item.sq1co.title", descriptionKey: "algs.item.sq1co.description"),
                item(id: "sq1eo", titleKey: "algs.item.sq1eo.title", descriptionKey: "algs.item.sq1eo.description"),
                item(id: "sq1cp", titleKey: "algs.item.sq1cp.title", descriptionKey: "algs.item.sq1cp.description"),
                item(id: "sq1ep", titleKey: "algs.item.sq1ep.title", descriptionKey: "algs.item.sq1ep.description"),
                item(id: "sq1parity", titleKey: "algs.item.sq1parity.title", descriptionKey: "algs.item.sq1parity.description")
            ]
        ),
        AlgSectionData(
            id: "square_one_large_sets",
            localizedTitleKey: "algs.section.large_sets",
            items: [
                item(id: "lin", titleKey: "algs.item.lin.title", descriptionKey: "algs.item.lin.description")
            ]
        )
    ]

    static let megaminxSections: [AlgSectionData] = [
        AlgSectionData(
            id: "megaminx",
            localizedTitleKey: "algs.section.megaminx_4lll",
            items: [
                item(id: "megaminxeo", titleKey: "algs.item.megaminxeo.title", descriptionKey: "algs.item.megaminxeo.description"),
                item(id: "megaminxco", titleKey: "algs.item.megaminxco.title", descriptionKey: "algs.item.megaminxco.description"),
                item(id: "megaminxep", titleKey: "algs.item.megaminxep.title", descriptionKey: "algs.item.megaminxep.description"),
                item(id: "megaminxcp", titleKey: "algs.item.megaminxcp.title", descriptionKey: "algs.item.megaminxcp.description")
            ]
        ),
        AlgSectionData(
            id: "megaminx_large_sets",
            localizedTitleKey: "algs.section.large_sets",
            items: [
                item(id: "megaminxoll", titleKey: "algs.item.megaminxoll.title", descriptionKey: "algs.item.megaminxoll.description"),
                item(id: "megaminxpll", titleKey: "algs.item.megaminxpll.title", descriptionKey: "algs.item.megaminxpll.description")
            ]
        )
    ]

    static let pyraminxSections: [AlgSectionData] = [
        AlgSectionData(
            id: "pyraminx",
            localizedTitleKey: "algs.section.pyraminx_last_layer",
            items: [
                item(id: "l3e", titleKey: "algs.item.l3e.title", descriptionKey: "algs.item.l3e.description"),
                item(id: "l4e", titleKey: "algs.item.l4e.title", descriptionKey: "algs.item.l4e.description")
            ]
        )
    ]

    static let skewbSections: [AlgSectionData] = [
        AlgSectionData(
            id: "skewb",
            localizedTitleKey: "algs.section.sarah_method",
            items: [
                item(id: "sarahsadvanced", titleKey: "algs.item.sarahsadvanced.title", descriptionKey: "algs.item.sarahsadvanced.description")
            ]
        )
    ]

    static var allSections: [AlgSectionData] {
        threeByThreeSections
        + twoByTwoSections
        + fourByFourSections
        + fiveByFiveSections
        + squareOneSections
        + megaminxSections
        + pyraminxSections
        + skewbSections
    }

    static func sections(for puzzle: AlgPuzzle) -> [AlgSectionData] {
        switch puzzle {
        case .threeByThree:
            return threeByThreeSections
        case .twoByTwo:
            return twoByTwoSections
        case .fourByFour:
            return fourByFourSections
        case .fiveByFive:
            return fiveByFiveSections
        case .squareOne:
            return squareOneSections
        case .megaminx:
            return megaminxSections
        case .pyraminx:
            return pyraminxSections
        case .skewb:
            return skewbSections
        default:
            return []
        }
    }
}

struct AlgItemData: Identifiable {
    let id: String
    let localizedTitleKey: LocalizedStringKey
    let algorithmCount: Int
    var learnedPercent: Int = 0
    var localizedDescriptionKey: LocalizedStringKey = ""

    var imageAssetName: String {
        "alg_\(id)"
    }

    var usesCaseCount: Bool {
        AlgLibrarySet(itemID: id) != nil
    }

    var title: LocalizedStringKey { localizedTitleKey }

    var description: LocalizedStringKey { localizedDescriptionKey }
}

enum AlgBrowseViewMode: String {
    case list
    case grid
}

enum AlgBrowseOrganization: String {
    case number
    case subset
    case hybrid
}

enum AlgSearchItemKind: Int, Comparable {
    case set
    case subset
    case caseName

    static func < (lhs: AlgSearchItemKind, rhs: AlgSearchItemKind) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

enum AlgSearchDestination {
    case set(AlgSetPayload)
    case subset(AlgSetPayload, AlgSubset)
    case caseDetail(AlgSetPayload, AlgCase)
    case placeholder(AlgItemData)
}

struct AlgSearchItem: Identifiable {
    let id: String
    let kind: AlgSearchItemKind
    let title: String
    let subtitle: String
    let searchableText: [String]
    let destination: AlgSearchDestination

    func matches(_ query: String) -> Bool {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedQuery.isEmpty else { return true }
        return searchableText.joined(separator: " ").lowercased().contains(normalizedQuery)
    }
}

struct AlgSubset: Identifiable, Hashable {
    let id: String
    let title: String
    let cases: [AlgCase]

    var uniqueCaseIDs: [String] {
        Array(Set(cases.map(\.id))).sorted()
    }

    var uniqueCaseCount: Int {
        uniqueCaseIDs.count
    }
}

struct AlgSubsetGroup: Identifiable, Hashable {
    let id: String
    let title: String
    let subsets: [AlgSubset]

    var uniqueCaseIDs: [String] {
        Array(Set(subsets.flatMap(\.uniqueCaseIDs))).sorted()
    }

    var uniqueCaseCount: Int {
        uniqueCaseIDs.count
    }
}

struct AlgCaseGroup: Identifiable, Hashable {
    let id: String
    let title: String
    let cases: [AlgCase]

    var uniqueCaseIDs: [String] {
        Array(Set(cases.map(\.id))).sorted()
    }

    var uniqueCaseCount: Int {
        uniqueCaseIDs.count
    }
}

enum AlgTrainerRecognitionLevel: String, Codable {
    case group
    case subset
    case caseName
}

struct AlgTrainerQuestionSeed: Identifiable, Hashable {
    let id: String
    let algCase: AlgCase
    let answerID: String
    let answerTitle: String
}

struct AlgTrainerQuestionChoice: Identifiable, Hashable {
    let id: String
    let title: String
}

struct AlgTrainerQuestion: Identifiable, Hashable {
    let id: String
    let algCase: AlgCase
    let choices: [AlgTrainerQuestionChoice]
    let correctAnswerID: String
    let correctAnswerTitle: String
}

struct AlgTrainerAttemptRecord: Identifiable, Codable, Hashable {
    let id: String
    let setID: String
    let scopeID: String
    let level: AlgTrainerRecognitionLevel
    let caseID: String
    let answerID: String?
    let isCorrect: Bool
    let isSkipped: Bool
    let timestamp: Date
}

struct AlgRecentPracticeContext: Identifiable {
    let id: String
    let dismissToken: String
    let title: String
    let subtitle: String
    let destination: AlgRecentPracticeDestination
}

enum AlgRecentPracticeDestination {
    case set(AlgSetPayload)
    case subset(AlgSetPayload, AlgSubset)
}

struct AlgTrainerWeakReviewItem: Identifiable {
    let id: String
    let setTitle: String
    let caseTitle: String
    let subtitle: String
    let payload: AlgSetPayload
    let algCase: AlgCase
    let lastAttempt: Date
}

struct AlgTrainerSetOption: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let payload: AlgSetPayload
}

struct AlgTrainerSessionSummary {
    let title: String
    let scopeTitle: String
    let languageCode: String
    let answeredCount: Int
    let correctCount: Int
    let wrongCount: Int
    let skipCount: Int
    let bestStreak: Int
    let sessionDuration: TimeInterval
    let averageRecognitionDuration: TimeInterval?
}

func decodeAlgTrainerAttempts(from store: String) -> [AlgTrainerAttemptRecord] {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return (try? decoder.decode([AlgTrainerAttemptRecord].self, from: Data(store.utf8))) ?? []
}

func makeAlgTrainerWeakReviewItems(from records: [AlgTrainerAttemptRecord], languageCode: String) -> [AlgTrainerWeakReviewItem] {
    let grouped = Dictionary(grouping: records) { "\($0.setID)::\($0.caseID)" }

    let setTitles = Dictionary(uniqueKeysWithValues: AlgSectionData.allSections
        .flatMap(\.items)
        .map { ($0.id.lowercased(), appLocalizedString("algs.item.\($0.id).title", languageCode: languageCode, defaultValue: $0.id)) })

    return grouped.compactMap { _, attempts in
        guard let first = attempts.first,
              let latestAttempt = attempts.max(by: { $0.timestamp < $1.timestamp }),
              let set = AlgLibrarySet(itemID: first.setID),
              let payload = AlgLibraryLoader.load(set),
              let algCase = payload.cases.first(where: { $0.id == first.caseID }) else {
            return nil
        }

        let answeredAttempts = attempts.filter { !$0.isSkipped }
        let totalAnswered = answeredAttempts.count
        let mistakeCount = attempts.filter { !$0.isCorrect && !$0.isSkipped }.count
        guard mistakeCount >= 5 else { return nil }

        let errorRate = Double(mistakeCount) / Double(totalAnswered)
        guard errorRate > 0.5 else { return nil }

        let errorPercent = Int((errorRate * 100).rounded())
        let subtitle = String(
            format: localizedAlgString(key: "algs.trainer.weak_item_subtitle_format", languageCode: languageCode),
            errorPercent,
            mistakeCount,
            totalAnswered
        )

        return AlgTrainerWeakReviewItem(
            id: "\(first.setID)::\(first.caseID)",
            setTitle: setTitles[first.setID.lowercased()] ?? payload.set,
            caseTitle: localizedAlgCaseName(setID: payload.set, caseName: algCase.displayName, languageCode: languageCode),
            subtitle: subtitle,
            payload: payload,
            algCase: algCase,
            lastAttempt: latestAttempt.timestamp
        )
    }
    .sorted {
        if $0.lastAttempt != $1.lastAttempt {
            return $0.lastAttempt > $1.lastAttempt
        }
        return $0.caseTitle < $1.caseTitle
    }
}

func formatAlgTrainerSessionDuration(_ duration: TimeInterval) -> String {
    let totalSeconds = max(Int(duration.rounded(.down)), 0)
    let hours = totalSeconds / 3600
    let minutes = (totalSeconds % 3600) / 60
    let seconds = totalSeconds % 60

    if hours > 0 {
        return String(format: "%d:%02d:%02d", hours, minutes, seconds)
    }

    return String(format: "%02d:%02d", minutes, seconds)
}

func formatAlgTrainerAverageDuration(_ duration: TimeInterval, languageCode: String) -> String {
    String(
        format: localizedAlgString(key: "algs.trainer.average_time_format", languageCode: languageCode),
        duration
    )
}

func normalizedAlgSetID(_ setID: String) -> String {
    setID.lowercased()
}

func normalizedAlgPreviewSlug(_ title: String) -> String {
    title
        .lowercased()
        .replacingOccurrences(of: #"[^a-z0-9]+"#, with: "_", options: .regularExpression)
        .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
}

private extension String {
    func strippingPrefix(_ prefix: String) -> String? {
        guard hasPrefix(prefix) else { return nil }
        return String(dropFirst(prefix.count))
    }
}

func algPuzzleSourcePath(puzzle: String) -> String? {
    let normalizedPuzzle = puzzle.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    switch normalizedPuzzle {
    case "2x2":
        return "2x2"
    case "3x3":
        return "3x3"
    case "4x4":
        return "4x4"
    case "5x5":
        return "5x5"
    case "sq1", "square-1", "square1":
        return "SQ1"
    case "megaminx":
        return "Megaminx"
    case "pyraminx":
        return "Pyraminx"
    case "skewb":
        return "Skewb"
    default:
        return nil
    }
}

func algPuzzleSourceURL(puzzle: String) -> URL? {
    guard let puzzlePath = algPuzzleSourcePath(puzzle: puzzle) else { return nil }
    return URL(string: "https://www.speedcubedb.com/a/\(puzzlePath)")
}

func algSourceURL(puzzle: String, setID: String) -> URL? {
    guard let puzzlePath = algPuzzleSourcePath(puzzle: puzzle) else { return nil }

    guard let encodedSetID = setID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
        return nil
    }
    return URL(string: "https://www.speedcubedb.com/a/\(puzzlePath)/\(encodedSetID)")
}

func algSourceURL(puzzle: String, setID: String, childTitle: String) -> URL? {
    guard let puzzlePath = algPuzzleSourcePath(puzzle: puzzle),
          let childPath = algSourcePagePath(setID: setID, childTitle: childTitle),
          let encodedChildPath = childPath.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
        return nil
    }
    return URL(string: "https://www.speedcubedb.com/a/\(puzzlePath)/\(encodedChildPath)")
}

func algSourcePagePath(setID: String, childTitle: String) -> String? {
    let normalizedSet = normalizedAlgSetID(setID)
    let trimmedTitle = childTitle.trimmingCharacters(in: .whitespacesAndNewlines)

    switch normalizedSet {
    case "zbll":
        switch trimmedTitle {
        case "U": return "ZBLLU"
        case "L": return "ZBLLL"
        case "T": return "ZBLLT"
        case "H": return "ZBLLH"
        case "Pi": return "ZBLLPi"
        case "S": return "ZBLLS"
        case "AS": return "ZBLLAS"
        default: return nil
        }
    case "ollcp":
        let compact = trimmedTitle.replacingOccurrences(of: " ", with: "")
        guard compact.range(of: #"^OLLCP\d+$"#, options: .regularExpression) != nil else { return nil }
        return compact
    case "vls":
        let compact = trimmedTitle
            .replacingOccurrences(of: " ", with: "")
            .uppercased()
        switch compact {
        case "NOEDGES":
            return "VLSNE"
        case "UB", "UBUL", "UF", "UFUB", "UFUL", "UL":
            return "VLS\(compact)"
        default:
            return nil
        }
    case "1lll":
        if trimmedTitle == "PLL" { return "PLL" }
        if trimmedTitle == "Anti PLL" { return "APLL" }
        if let zbllSuffix = trimmedTitle.strippingPrefix("ZBLL ") {
            return algSourcePagePath(setID: "zbll", childTitle: zbllSuffix)
        }
        if let numberText = trimmedTitle.strippingPrefix("1LLL "),
           let number = Int(numberText) {
            return String(format: "1LLL%02d", number)
        }
        return nil
    case "lin":
        switch trimmedTitle {
        case "Lin PLL": return "SQ1LinPLL"
        case "Lin Parity PLL": return "SQ1LinParityPLL"
        case "Lin PLL+1": return "SQ1LinPLL1"
        default: return nil
        }
    case "megaminxoll":
        return megaminxOLLSourcePagePath(title: trimmedTitle)
    case "megaminxpll":
        return megaminxPLLSourcePagePath(title: trimmedTitle)
    default:
        return nil
    }
}

func algChildHasSourcePage(setID: String, childTitle: String) -> Bool {
    algSourcePagePath(setID: setID, childTitle: childTitle) != nil
}

func algSubsetsContainOnlySelfGroup(_ subsets: [AlgSubset], groupTitle: String) -> Bool {
    guard subsets.count == 1, let onlySubset = subsets.first else { return false }
    return normalizedAlgSetID(onlySubset.title) == normalizedAlgSetID(groupTitle)
}

func algSupportsHybridCapsules(setID: String, subsets: [AlgSubset], parentTitle: String? = nil) -> Bool {
    let meaningfulSubsets = parentTitle.map {
        algSubsetsContainOnlySelfGroup(subsets, groupTitle: $0) ? [] : subsets
    } ?? subsets

    guard !meaningfulSubsets.isEmpty else { return false }
    return meaningfulSubsets.allSatisfy { !algChildHasSourcePage(setID: setID, childTitle: $0.title) }
}

func algSourceURL(puzzle: String, setID: String, subset: AlgSubset) -> URL? {
    if algChildHasSourcePage(setID: setID, childTitle: subset.title) {
        return algSourceURL(puzzle: puzzle, setID: setID, childTitle: subset.title)
    }

    if let parentTitle = subsetGroupTitle(for: setID, subsetTitle: subset.title),
       algChildHasSourcePage(setID: setID, childTitle: parentTitle) {
        return algSourceURL(puzzle: puzzle, setID: setID, childTitle: parentTitle)
    }

    if let firstCase = subset.cases.first,
       let parentTitle = caseGroupTitle(for: setID, algCase: firstCase),
       algChildHasSourcePage(setID: setID, childTitle: parentTitle) {
        return algSourceURL(puzzle: puzzle, setID: setID, childTitle: parentTitle)
    }

    return algSourceURL(puzzle: puzzle, setID: setID)
}

func megaminxOLLSourcePagePath(title: String) -> String? {
    let orderedTitles = [
        "EO",
        "2 Corner CO",
        "3 Corner CO",
        "4 Corner CO",
        "5 Corner CO",
        "Anchor Shapes",
        "T Shapes",
        "C Shapes",
        "S Shapes",
        "Pi Shapes",
        "Y Shapes",
        "Hammerhead Shapes",
        "W Shapes",
        "Duckhead Shapes",
        "Megaphone Shapes",
        "Claw Shapes",
        "Rabbit Shapes",
        "Long Block",
        "Fox Head Shapes",
        "Scorpion Shapes",
        "Line Shapes",
        "Flower Shapes",
        "Chandelier shapes",
        "P Shapes",
        "E Shapes",
        "Sprinter Shapes",
        "Eagle Shapes",
        "Big Block",
        "Lobster Shapes",
        "Lightning Shapes",
        "Cobra Shapes",
        "Hand Shapes",
        "Magic Lamp Shapes",
        "Human Shapes",
        "Axe Shapes",
        "Parrot Shapes",
        "L Shapes"
    ]

    guard let index = orderedTitles.firstIndex(of: title) else { return nil }
    return "MegaminxOLL\(index + 1)"
}

func megaminxPLLSourcePagePath(title: String) -> String? {
    let orderedTitles = [
        "3 corner CP",
        "Double R block",
        "2 2x1s touching",
        "3x1 and 2x2",
        "4 corner CP",
        "3x1 and 2x1s",
        "2x1 and headlights",
        "5 piece EP/CP",
        "2x1",
        "J Block",
        "5 corner CP",
        "Double headlights, no blocks",
        "2 3x1s",
        "5 2x1s",
        "R Block",
        "5 edge EP",
        "R block and 2x1",
        "2 2x1s, not touching",
        "2,3 or 4 2x1s in these patterns",
        "3 edge EP",
        "2x2 and 2x1",
        "2 2x2s",
        "No blocks or headlights",
        "2 2x1s in Y pattern and other stuff",
        "4 edge EP"
    ]

    guard let index = orderedTitles.firstIndex(of: title),
          let scalar = UnicodeScalar(65 + index) else {
        return nil
    }
    return "MegaminxPLL\(Character(scalar))"
}

func algPuzzleEventKey(_ puzzle: String) -> String {
    let normalizedPuzzle = puzzle.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    switch normalizedPuzzle {
    case "2x2":
        return "event.2x2"
    case "3x3":
        return "event.3x3"
    case "4x4":
        return "event.4x4"
    case "5x5":
        return "event.5x5"
    case "sq1", "square-1", "square1":
        return "event.square1"
    case "megaminx":
        return "event.megaminx"
    case "pyraminx":
        return "event.pyraminx"
    case "skewb":
        return "event.skewb"
    default:
        return puzzle
    }
}

func algGroupPreviewImageKey(setID: String, title: String) -> String? {
    let normalizedSet = normalizedAlgSetID(setID)
    switch normalizedSet {
    case "ollcp":
        let number = title.replacingOccurrences(of: "OLLCP", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !number.isEmpty {
            return "ollcp_group_ollcp_\(number)"
        }
        return "ollcp_group_\(normalizedAlgPreviewSlug(title))"
    case "zbll", "vls", "1lll":
        return "\(normalizedSet)_group_\(normalizedAlgPreviewSlug(title))"
    default:
        return nil
    }
}

func algSubsetPreviewImageKey(setID: String, parentGroupTitle: String? = nil, subsetTitle: String) -> String? {
    let normalizedSet = normalizedAlgSetID(setID)
    if normalizedSet == "zbll" || (parentGroupTitle?.hasPrefix("ZBLL ") == true) {
        return "zbll_subset_\(normalizedAlgPreviewSlug(subsetTitle))"
    }

    return nil
}

func displayAlgGroupTitle(setID: String, title: String) -> String {
    guard normalizedAlgSetID(setID) == "zbll" else { return title }

    switch title {
    case "U", "L", "T", "H", "Pi", "S", "AS":
        return "ZBLL \(title)"
    default:
        return title
    }
}

func orderedSubsets(from cases: [AlgCase]) -> [AlgSubset] {
    var orderedTitles: [String] = []
    var grouped: [String: [AlgCase]] = [:]

    for algCase in cases {
        let subgroup = algCase.subgroup.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !subgroup.isEmpty else { continue }
        if grouped[subgroup] == nil {
            orderedTitles.append(subgroup)
            grouped[subgroup] = []
        }
        grouped[subgroup, default: []].append(algCase)
    }

    return orderedTitles.map { title in
        AlgSubset(id: normalizedAlgSetID(title), title: title, cases: grouped[title] ?? [])
    }
}

func subsetGroupTitle(for setID: String, subsetTitle: String) -> String? {
    guard normalizedAlgSetID(setID) == "zbll" else { return nil }

    let trimmed = subsetTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.hasPrefix("AS") { return "AS" }
    if trimmed.hasPrefix("Pi") { return "Pi" }
    if let first = trimmed.first {
        switch first {
        case "U": return "U"
        case "L": return "L"
        case "T": return "T"
        case "H": return "H"
        case "S": return "S"
        default: break
        }
    }

    return nil
}

func caseGroupTitle(for setID: String, algCase: AlgCase) -> String? {
    if let group = algCase.group?.trimmingCharacters(in: .whitespacesAndNewlines), !group.isEmpty {
        return group
    }

    let trimmed = algCase.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
    switch normalizedAlgSetID(setID) {
    case "ollcp":
        guard trimmed.hasPrefix("OLLCP") else { return nil }
        return trimmed.split(separator: " ").first.map(String.init)
    case "1lll":
        if trimmed == "Pure" {
            return "Anti PLL"
        }

        if trimmed.hasPrefix("ZBLL ") {
            let parts = trimmed.split(separator: " ")
            guard parts.count >= 2 else { return nil }
            return parts.prefix(2).joined(separator: " ")
        }

        if trimmed.hasPrefix("1LLL ") {
            let parts = trimmed.split(separator: " ")
            guard parts.count >= 2 else { return nil }
            return parts.prefix(2).joined(separator: " ")
        }

        return "Anti PLL"
    default:
        return nil
    }
}

func orderedSubsetGroups(setID: String, subsets: [AlgSubset]) -> [AlgSubsetGroup] {
    let preferredOrder = ["U", "L", "T", "H", "Pi", "S", "AS"]
    var grouped: [String: [AlgSubset]] = [:]
    var orderedTitles: [String] = []

    for subset in subsets {
        guard let title = subsetGroupTitle(for: setID, subsetTitle: subset.title) else { continue }
        if grouped[title] == nil {
            orderedTitles.append(title)
            grouped[title] = []
        }
        grouped[title, default: []].append(subset)
    }

    let titles = preferredOrder.filter { grouped[$0] != nil } + orderedTitles.filter { !preferredOrder.contains($0) }
    return titles.map { title in
        AlgSubsetGroup(id: normalizedAlgSetID(title), title: title, subsets: grouped[title] ?? [])
    }
}

func orderedCaseGroups(setID: String, cases: [AlgCase]) -> [AlgCaseGroup] {
    var orderedTitles: [String] = []
    var grouped: [String: [AlgCase]] = [:]

    for algCase in cases {
        guard let title = caseGroupTitle(for: setID, algCase: algCase) else { continue }
        if grouped[title] == nil {
            orderedTitles.append(title)
            grouped[title] = []
        }
        grouped[title, default: []].append(algCase)
    }

    let titles: [String]
    if normalizedAlgSetID(setID) == "ollcp" {
        titles = orderedTitles.sorted { lhs, rhs in
            let lhsNumber = Int(lhs.replacingOccurrences(of: "OLLCP", with: "")) ?? .max
            let rhsNumber = Int(rhs.replacingOccurrences(of: "OLLCP", with: "")) ?? .max
            return lhsNumber < rhsNumber
        }
    } else if normalizedAlgSetID(setID) == "vls" {
        let preferredOrder = ["UB", "UB UL", "UF", "UF UB", "UF UL", "UL", "No Edges"]
        titles = preferredOrder.filter { grouped[$0] != nil } + orderedTitles.filter { !preferredOrder.contains($0) }
    } else if normalizedAlgSetID(setID) == "1lll" {
        let preferredOrder = ["PLL", "ZBLL U", "ZBLL L", "ZBLL T", "ZBLL H", "ZBLL Pi", "ZBLL S", "ZBLL AS", "Anti PLL"]
        let numberedGroups = orderedTitles
            .filter { $0.hasPrefix("1LLL ") }
            .sorted {
                let lhsNumber = Int($0.replacingOccurrences(of: "1LLL ", with: "")) ?? .max
                let rhsNumber = Int($1.replacingOccurrences(of: "1LLL ", with: "")) ?? .max
                return lhsNumber < rhsNumber
            }
        let remainingGroups = orderedTitles.filter { !preferredOrder.contains($0) && !$0.hasPrefix("1LLL ") }
        titles = preferredOrder.filter { grouped[$0] != nil } + numberedGroups + remainingGroups
    } else {
        titles = orderedTitles
    }

    return titles.map { title in
        AlgCaseGroup(id: normalizedAlgSetID(title), title: title, cases: grouped[title] ?? [])
    }
}

func makeSetTrainerSeeds(
    payload: AlgSetPayload,
    languageCode: String,
    organization: AlgBrowseOrganization
) -> (AlgTrainerRecognitionLevel, [AlgTrainerQuestionSeed]) {
    let subsets = orderedSubsets(from: payload.cases)
    let subsetGroups = orderedSubsetGroups(setID: payload.set, subsets: subsets)
    let caseGroups = orderedCaseGroups(setID: payload.set, cases: payload.cases)

    if organization == .number {
        let seeds = payload.cases.map { algCase in
            AlgTrainerQuestionSeed(
                id: algCase.id,
                algCase: algCase,
                answerID: algCase.id,
                answerTitle: localizedAlgCaseName(setID: payload.set, caseName: algCase.displayName, languageCode: languageCode)
            )
        }
        return (.caseName, seeds)
    }

    if !subsetGroups.isEmpty {
        let seeds = payload.cases.compactMap { algCase -> AlgTrainerQuestionSeed? in
            guard let groupTitle = subsetGroupTitle(for: payload.set, subsetTitle: algCase.subgroup) else { return nil }
            return AlgTrainerQuestionSeed(
                id: algCase.id,
                algCase: algCase,
                answerID: groupTitle,
                answerTitle: displayAlgGroupTitle(setID: payload.set, title: groupTitle)
            )
        }
        return (.group, seeds)
    }

    if !caseGroups.isEmpty {
        let seeds = payload.cases.compactMap { algCase -> AlgTrainerQuestionSeed? in
            guard let groupTitle = caseGroupTitle(for: payload.set, algCase: algCase) else { return nil }
            return AlgTrainerQuestionSeed(
                id: algCase.id,
                algCase: algCase,
                answerID: groupTitle,
                answerTitle: displayAlgGroupTitle(setID: payload.set, title: groupTitle)
            )
        }
        return (.group, seeds)
    }

    if !subsets.isEmpty {
        let seeds = payload.cases.map { algCase in
            AlgTrainerQuestionSeed(
                id: algCase.id,
                algCase: algCase,
                answerID: algCase.subgroup,
                answerTitle: localizedAlgSubgroup(algCase.subgroup, languageCode: languageCode)
            )
        }
        return (.subset, seeds)
    }

    let seeds = payload.cases.map { algCase in
        AlgTrainerQuestionSeed(
            id: algCase.id,
            algCase: algCase,
            answerID: algCase.id,
            answerTitle: localizedAlgCaseName(setID: payload.set, caseName: algCase.displayName, languageCode: languageCode)
        )
    }
    return (.caseName, seeds)
}

func makeSubsetTrainerSeeds(setID: String, subset: AlgSubset, languageCode: String) -> (AlgTrainerRecognitionLevel, [AlgTrainerQuestionSeed]) {
    let seeds = subset.cases.map { algCase in
        AlgTrainerQuestionSeed(
            id: algCase.id,
            algCase: algCase,
            answerID: algCase.id,
            answerTitle: localizedAlgCaseName(setID: setID, caseName: algCase.displayName, languageCode: languageCode)
        )
    }
    return (.caseName, seeds)
}

func makeAlgTrainerSetOptions(languageCode: String) -> [(AlgSectionData, [AlgTrainerSetOption])] {
    AlgSectionData.allSections.compactMap { section in
        let options = section.items.compactMap { item -> AlgTrainerSetOption? in
            guard let set = AlgLibrarySet(itemID: item.id),
                  let payload = AlgLibraryLoader.load(set) else {
                return nil
            }

            let title = appLocalizedString("algs.item.\(item.id).title", languageCode: languageCode, defaultValue: payload.set)
            let subtitle = localizedCaseCount(payload.cases.count, languageCode: languageCode)

            return AlgTrainerSetOption(
                id: item.id,
                title: title,
                subtitle: subtitle,
                payload: payload
            )
        }

        guard !options.isEmpty else { return nil }
        return (section, options)
    }
}

func algBrowsePreferenceMap(from storage: String) -> [String: String] {
    guard let data = storage.data(using: .utf8),
          let map = try? JSONDecoder().decode([String: String].self, from: data) else {
        return [:]
    }
    return map
}

func algBrowsePreferenceStorage(from map: [String: String]) -> String {
    guard let data = try? JSONEncoder().encode(map),
          let string = String(data: data, encoding: .utf8) else {
        return "{}"
    }
    return string
}

func globalAlgBrowsePreferenceValue(storage: String, setID: String) -> String? {
    if !storage.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("{") {
        return storage
    }

    let map = algBrowsePreferenceMap(from: storage)
    return map["global"] ?? map[normalizedAlgSetID(setID)] ?? map.values.first
}

func algBrowseViewMode(setID: String, storage: String) -> AlgBrowseViewMode {
    let value = globalAlgBrowsePreferenceValue(storage: storage, setID: setID)
    return value.flatMap(AlgBrowseViewMode.init(rawValue:)) ?? .list
}

func updatedAlgBrowseViewModeStorage(storage: String, setID: String, mode: AlgBrowseViewMode) -> String {
    mode.rawValue
}

func algBrowseOrganization(setID: String, storage: String) -> AlgBrowseOrganization {
    let value = globalAlgBrowsePreferenceValue(storage: storage, setID: setID)
    return value.flatMap(AlgBrowseOrganization.init(rawValue:)) ?? .hybrid
}

func updatedAlgBrowseOrganizationStorage(storage: String, setID: String, organization: AlgBrowseOrganization) -> String {
    organization.rawValue
}

func learnedCaseMap(from storage: String) -> [String: Set<String>] {
    guard let data = storage.data(using: .utf8),
          let raw = try? JSONDecoder().decode([String: [String]].self, from: data) else {
        return [:]
    }

    return raw.reduce(into: [:]) { partialResult, entry in
        partialResult[entry.key] = Set(entry.value)
    }
}

func learnedCaseStorage(from map: [String: Set<String>]) -> String {
    let raw = map.reduce(into: [String: [String]]()) { partialResult, entry in
        partialResult[entry.key] = entry.value.sorted()
    }

    guard let data = try? JSONEncoder().encode(raw),
          let string = String(data: data, encoding: .utf8) else {
        return "{}"
    }

    return string
}

func isAlgCaseLearned(setID: String, caseID: String, storage: String) -> Bool {
    learnedCaseMap(from: storage)[normalizedAlgSetID(setID), default: []].contains(caseID)
}

func updatedLearnedCaseStorage(storage: String, setID: String, caseID: String, learned: Bool) -> String {
    var map = learnedCaseMap(from: storage)
    let key = normalizedAlgSetID(setID)
    var learnedCases = map[key, default: []]

    if learned {
        learnedCases.insert(caseID)
    } else {
        learnedCases.remove(caseID)
    }

    map[key] = learnedCases
    return learnedCaseStorage(from: map)
}

func updatedLearnedCaseStorageForAll(storage: String, setID: String, caseIDs: [String], learned: Bool) -> String {
    var map = learnedCaseMap(from: storage)
    let key = normalizedAlgSetID(setID)
    var learnedCases = map[key, default: []]

    if learned {
        learnedCases.formUnion(caseIDs)
    } else {
        learnedCases.subtract(caseIDs)
    }

    map[key] = learnedCases
    return learnedCaseStorage(from: map)
}

func learnedCaseCount(setID: String, storage: String) -> Int {
    learnedCaseMap(from: storage)[normalizedAlgSetID(setID), default: []].count
}

func learnedCaseCount(setID: String, caseIDs: [String], storage: String) -> Int {
    let learned = learnedCaseMap(from: storage)[normalizedAlgSetID(setID), default: []]
    return learned.intersection(Set(caseIDs)).count
}

func learnedPercent(setID: String, totalCases: Int, storage: String) -> Int {
    guard totalCases > 0 else { return 0 }
    let learned = min(learnedCaseCount(setID: setID, storage: storage), totalCases)
    return Int((Double(learned) / Double(totalCases) * 100).rounded())
}

func learnedFraction(setID: String, totalCases: Int, storage: String) -> Double {
    guard totalCases > 0 else { return 0 }
    let learned = min(learnedCaseCount(setID: setID, storage: storage), totalCases)
    return min(max(Double(learned) / Double(totalCases), 0), 1)
}

func localizedCaseCount(_ count: Int, languageCode: String) -> String {
    String(format: localizedAlgString(key: "algs.case_count_format", languageCode: languageCode), count)
}

func localizedAlgorithmCount(_ count: Int, languageCode: String) -> String {
    String(format: localizedAlgString(key: "algs.algorithm_count_format", languageCode: languageCode), count)
}

func localizedAlgorithmsSubtitle(_ count: Int, learnedPercent: Int, languageCode: String) -> String {
    let learnedText: String
    if learnedPercent <= 0 {
        learnedText = localizedAlgString(key: "algs.not_started", languageCode: languageCode)
    } else if learnedPercent >= 100 {
        learnedText = localizedAlgString(key: "algs.learned_complete", languageCode: languageCode)
    } else {
        learnedText = String(format: localizedAlgString(key: "algs.learned_percent_format", languageCode: languageCode), learnedPercent)
    }

    let countText = localizedAlgorithmCount(count, languageCode: languageCode)
    return "\(countText) · \(learnedText)"
}

func localizedCaseSubtitle(_ count: Int, learnedCount: Int, learnedFraction: Double, languageCode: String) -> String {
    let caseText = localizedCaseCount(count, languageCode: languageCode)
    let learnedText: String
    if learnedCount <= 0 {
        learnedText = localizedAlgString(key: "algs.not_started", languageCode: languageCode)
    } else if learnedFraction >= 1 {
        learnedText = localizedAlgString(key: "algs.learned_complete", languageCode: languageCode)
    } else if learnedFraction < 0.01 {
        learnedText = localizedAlgString(key: "algs.learned_less_than_one_percent", languageCode: languageCode)
    } else {
        let learnedPercent = Int((learnedFraction * 100).rounded())
        learnedText = String(format: localizedAlgString(key: "algs.learned_percent_format", languageCode: languageCode), learnedPercent)
    }
    return "\(caseText) · \(learnedText)"
}

func localizedAlgString(key: String, languageCode: String) -> String {
    appLocalizedString(key, languageCode: languageCode)
}

func algSubgroupLocalizationKey(_ subgroup: String) -> String? {
    switch subgroup.lowercased() {
    case "free pairs":
        return "algs.f2l.subgroup.free_pairs"
    case "connected pairs":
        return "algs.f2l.subgroup.connected_pairs"
    case "corner in slot":
        return "algs.f2l.subgroup.corner_in_slot"
    case "disconnected pairs":
        return "algs.f2l.subgroup.disconnected_pairs"
    case "edge in slot":
        return "algs.f2l.subgroup.edge_in_slot"
    case "pieces in slot":
        return "algs.f2l.subgroup.pieces_in_slot"
    case "adj swap":
        return "algs.pll.subgroup.adj_swap"
    case "opp swap":
        return "algs.pll.subgroup.opp_swap"
    case "all corners oriented":
        return "algs.subgroup.all_corners_oriented"
    case "awkward shapes":
        return "algs.subgroup.awkward_shapes"
    case "c shapes":
        return "algs.subgroup.c_shapes"
    case "dot case":
        return "algs.subgroup.dot_case"
    case "fish shapes":
        return "algs.subgroup.fish_shapes"
    case "knight move shapes":
        return "algs.subgroup.knight_move_shapes"
    case "l shapes":
        return "algs.subgroup.l_shapes"
    case "lightning shapes":
        return "algs.subgroup.lightning_shapes"
    case "line shapes":
        return "algs.subgroup.line_shapes"
    case "p shapes":
        return "algs.subgroup.p_shapes"
    case "square shapes":
        return "algs.subgroup.square_shapes"
    case "t shapes":
        return "algs.subgroup.t_shapes"
    case "w shapes":
        return "algs.subgroup.w_shapes"
    case "both pieces trapped":
        return "algs.subgroup.both_pieces_trapped"
    case "trapped corner":
        return "algs.subgroup.trapped_corner"
    case "trapped edge":
        return "algs.subgroup.trapped_edge"
    case "cross color facing front":
        return "algs.subgroup.cross_color_facing_front"
    case "cross color facing right":
        return "algs.subgroup.cross_color_facing_right"
    case "cross color facing up":
        return "algs.subgroup.cross_color_facing_up"
    case "corner on d facing forward":
        return "algs.subgroup.corner_on_d_facing_forward"
    case "corner on d facing side":
        return "algs.subgroup.corner_on_d_facing_side"
    case "corner on d solved":
        return "algs.subgroup.corner_on_d_solved"
    case "corner on u facing up":
        return "algs.subgroup.corner_on_u_facing_up"
    case "corner on u misoriented":
        return "algs.subgroup.corner_on_u_misoriented"
    case "corner on u oriented":
        return "algs.subgroup.corner_on_u_oriented"
    case "anti sune":
        return "algs.subgroup.anti_sune"
    case "sune":
        return "algs.subgroup.sune"
    case "solved":
        return "algs.subgroup.solved"
    case "1 slice":
        return "algs.subgroup.sq1.1_slice"
    case "2 slices":
        return "algs.subgroup.sq1.2_slices"
    case "3 slices":
        return "algs.subgroup.sq1.3_slices"
    case "4 slices":
        return "algs.subgroup.sq1.4_slices"
    case "5 slices":
        return "algs.subgroup.sq1.5_slices"
    case "6 slices":
        return "algs.subgroup.sq1.6_slices"
    case "7 slices":
        return "algs.subgroup.sq1.7_slices"
    default:
        return nil
    }
}

func localizedAlgSubgroup(_ subgroup: String, languageCode: String) -> String {
    guard let key = algSubgroupLocalizationKey(subgroup) else { return subgroup }
    return localizedAlgString(key: key, languageCode: languageCode)
}

func algCaseLocalizationKey(setID: String, caseName: String) -> String? {
    switch normalizedAlgSetID(setID) {
    case "sq1cs":
        return "algs.case.sq1cs.\(normalizedAlgPreviewSlug(caseName))"
    default:
        return nil
    }
}

func localizedAlgCaseName(setID: String, caseName: String, languageCode: String) -> String {
    guard let key = algCaseLocalizationKey(setID: setID, caseName: caseName) else {
        return caseName
    }
    return appLocalizedString(key, languageCode: languageCode, defaultValue: caseName)
}

#if os(iOS)
enum AlgCaseImageProvider {
    private static var cache: [String: UIImage] = [:]

    static func image(named imageKey: String) -> UIImage? {
        if let cached = cache[imageKey] {
            return cached
        }

        let folderName = imageFolderName(for: imageKey)
        let candidates: [String?] = [
            "Resources/Algs/\(folderName)",
            "Algs/\(folderName)",
            folderName,
            nil
        ]

        for subdirectory in candidates {
            if let url = Bundle.main.url(forResource: imageKey, withExtension: "png", subdirectory: subdirectory),
               let image = UIImage(contentsOfFile: url.path) {
                cache[imageKey] = image
                return image
            }
        }

        if let bundled = UIImage(named: imageKey) {
            cache[imageKey] = bundled
            return bundled
        }

        return nil
    }

    private static func imageFolderName(for imageKey: String) -> String {
        let prefix = imageKey.split(separator: "_").first.map(String.init)?.uppercased() ?? "PLL"
        return "\(prefix)Images"
    }
}
#endif

