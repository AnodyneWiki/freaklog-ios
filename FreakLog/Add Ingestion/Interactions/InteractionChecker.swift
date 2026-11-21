import Foundation

// swiftlint:disable type_body_length
enum InteractionChecker {
    static let additionalInteractionsToCheck = [
        "Alcohol",
        "Caffeine",
        "Cannabis",
        "Grapefruit",
        "Hormonal birth control",
        "Nicotine",
        "Lithium",
        "MAOI",
        "SSRIs",
        "SNRIs",
        "5-Hydroxytryptophan",
        "Tricyclic antidepressants",
        "Antibiotics",
        "Antihistamine",
    ]

    static func getInteractionBetween(aName: String, bName: String) -> Interaction? {
        if let interactionType = getInteractionTypeBetween(aName: aName, bName: bName) {
            return Interaction(
                aName: aName,
                bName: bName,
                interactionType: interactionType
            )
        } else {
            return nil
        }
    }

    // Results only depend on the substance data and the user's categories and are symmetric, so they are cached per pair
    static func getInteractionTypeBetween(aName: String, bName: String) -> InteractionType? {
        guard aName != bName else { return nil }
        let key = aName < bName ? "\(aName)\u{0}\(bName)" : "\(bName)\u{0}\(aName)"
        cacheLock.lock()
        if let cached = cache[key] {
            cacheLock.unlock()
            return cached
        }
        cacheLock.unlock()
        let interactionType = computeInteractionTypeBetween(aName: aName, bName: bName)
        cacheLock.lock()
        cache[key] = .some(interactionType)
        cacheLock.unlock()
        return interactionType
    }

    // The user's categories take part in matching, so changing them drops the cached results
    static func clearCache() {
        cacheLock.lock()
        cache.removeAll()
        cacheLock.unlock()
    }

    private static let cacheLock = NSLock()
    nonisolated(unsafe) private static var cache: [String: InteractionType?] = [:]

    // The more dangerous of the two directions, preferring a to b on a tie
    private static func computeInteractionTypeBetween(aName: String, bName: String) -> InteractionType? {
        let interactions = [getInteraction(fromName: aName, toName: bName), getInteraction(fromName: bName, toName: aName)]
        return interactions.compactMap { $0 }.reduce(nil) { best, next in
            guard let best else { return next }
            return best.dangerCount >= next.dangerCount ? best : next
        }
    }

    // Direct name matches win over wildcard matches, which win over class matches
    private static func getInteraction(fromName: String, toName: String) -> InteractionType? {
        guard let substance = SubstanceRepo.shared.getSubstance(name: fromName) else { return nil }
        guard let interactions = substance.interactions else { return nil }
        if let direct = firstMatch(in: interactions, where: { $0.contains(toName) }) {
            return direct
        }
        if let wildCard = firstMatch(in: interactions, where: { names in
            names.contains { hasXAndMatches(wordWithX: $0, matchWith: toName) }
        }) {
            return wildCard
        }
        let categories = PersistenceController.shared.categories(for: toName)
        return firstMatch(in: interactions, where: { names in
            categories.contains { categoryName in
                names.contains { $0.caseInsensitiveContains(categoryName) }
            }
        })
    }

    // The most dangerous interaction list whose (extended) names match
    private static func firstMatch(in interactions: Interactions, where matches: ([String]) -> Bool) -> InteractionType? {
        let lists: [(InteractionType, [String])] = [
            (.dangerous, interactions.dangerous),
            (.unsafe, interactions.unsafe),
            (.uncertain, interactions.uncertain),
        ]
        return lists.first { matches(extendAndCleanInteractions(interactions: $0.1)) }?.0
    }

    // Names like DOx, 2C-T-x, 25x-NBOMe or 5-MeO-xxT stand for a family: each x is one or more characters
    static func hasXAndMatches(wordWithX: String, matchWith unchangedWord: String) -> Bool {
        guard wordWithX.contains("x") else { return false }
        let modifiedPattern = "^" + wordWithX.replacingOccurrences(of: "x", with: "[\\S]+") + "$"
        guard let regex = try? NSRegularExpression(pattern: modifiedPattern, options: .caseInsensitive) else { return false }
        let range = NSRange(location: 0, length: unchangedWord.utf16.count)
        return regex.firstMatch(in: unchangedWord, options: [], range: range) != nil
    }

    private static func extendAndCleanInteractions(interactions: [String]) -> [String] {
        interactions.flatMap { name in
            switch name {
            case "Substituted amphetamines":
                return substitutedAmphetamines
            case "Serotonin releasers":
                return serotoninReleasers
            case "Tricyclic antidepressants": // remove because we don't want to match "depressant" with it and there is no substance that belongs to that class
                return []
            default:
                return [name]
            }
        }.uniqued()
    }

    private static let serotoninReleasers = [
        "MDMA",
        "MDA",
        "Mephedrone",
    ]

    private static let substitutedAmphetamines = [
        "Amphetamine",
        "MDMA",
        "DOM",
        "DOB",
        "DOI",
        "DOC",
        "Methamphetamine",
        "Ethylamphetamine",
        "Propylamphetamine",
        "Isopropylamphetamine",
        "Bromo-DragonFLY",
        "Lisdexamfetamine",
        "Dextroamphetamine",
        "Levoamphetamine",
        "Clobenzorex",
        "Ephedrine",
        "Dimethylamphetamine",
        "Selegiline",
        "Benzphetamine",
        "Pseudoephedrine",
        "Ortetamine",
        "3-Methylamphetamine",
        "4-Methylamphetamine",
        "4-MMA",
        "Xylopropamine",
        "ß-methylamphetamine",
        "3-phenylmethamphetamine",
        "2-FA",
        "2-FMA",
        "2-FEA",
        "3-FA",
        "3-FMA",
        "3-FEA",
        "Fenfluramine",
        "Norfenfluramine",
        "4-FA",
        "4-FMA",
        "4-CA",
        "4-BA",
        "4-IA",
        "DCA",
        "4-HA",
        "4-HMA",
        "3,4-DHA",
        "OMA",
        "3-MA",
        "MMMA",
        "MMA",
        "PMA",
        "PMMA",
        "PMEA",
        "4-ETA",
        "TMA-2",
        "TMA-6",
        "4-MTA",
        "5-API",
        "Cathine",
        "Phenmetrazine",
        "3-FPM",
        "Prolintane",
        "Benzofuran",
        "2-APB",
        "2-MAPB",
        "2-EAPB",
        "3-APB",
        "Mebfap",
        "5-MeO-BFE",
        "5-MeO-DiBF",
        "4-APB",
        "5-APB",
        "5-APDB",
        "5-MAPB",
        "5-MAPDB",
        "βk-5-MAPB",
        "5-EAPB",
        "5-EAPDB",
        "5-MBPB",
        "5-DBFPV",
        "6-MeO-5-APDB",
        "6-APB",
        "6-APDB",
        "6-MAPB",
        "6-MAPDB",
        "βk-6-MAPB",
        "6-EAPB",
        "6-EAPDB",
        "6-MBPB",
        "F-2",
        "F-22",
        "7-APB",
        "DOI-2-hemifly",
        "Bromo-DragonFLY",
        "2C-B-FLY",
        "Methylphenidate",
        "Ethylphenidate",
        "Isopropylphenidate",
        "Propylphenidate",
        "4-Methylmethylphenidate",
        "3,4-CTMP",
        "4F-MPH",
        "4F-EPH",
        "Methylnaphthidate",
        "Ethylnaphthidate",
    ]
}

struct Interaction: Comparable {
    static func < (lhs: Interaction, rhs: Interaction) -> Bool {
        lhs.interactionType.dangerCount > rhs.interactionType.dangerCount
    }

    let aName: String
    let bName: String
    let interactionType: InteractionType
}

extension Interaction: Hashable, Identifiable {
    var id: Int {
        hashValue
    }

    func hash(into hasher: inout Hasher) {
        var hash: String = interactionType.hashValue.formatted()
        if aName < bName {
            hash = hash + aName + bName
        } else {
            hash = hash + bName + aName
        }
        hasher.combine(hash)
    }
}
// swiftlint:enable type_body_length
