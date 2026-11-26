import Foundation

struct WebhookResult {
    let success: Bool
    let messageId: String?
    let error: Error?
}

struct WebhookService {
    enum DeliveryError: Error {
        case rejected
        case unknownDelivery
    }

    typealias LoadData = (URLRequest) async throws -> (Data, URLResponse)

    static let defaultTemplate = "[{user}: ][{dose} {unit} ]{substance} via {route}[ ({site})][\n> {note}]"
    static let defaultNoteTemplate = "[{user}: ]{note}"

    static func deleteWebhookMessage(url: String, messageId: String) async -> Bool {
        guard let requestUrl = requestURL(url, messageId: messageId) else { return false }
        var request = URLRequest(url: requestUrl)
        request.httpMethod = "DELETE"

        let maxRetries = 3
        for attempt in 0..<maxRetries {
            do {
                let (_, response) = try await URLSession.shared.data(for: request)
                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 204 {
                    return true
                }
                // If 404, it's already gone, consider success
                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 404 {
                    return true
                }
            } catch {
                if attempt < maxRetries - 1 {
                    let delay = Double(1 << attempt)
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
            }
        }
        return false
    }

    // The message for an ingestion. The global username stands in for "you".
    static func content(for data: WebhookManager.WebhookDataSnapshot, settings: WebhookManager.WebhookSettingsSnapshot) -> String {
        let dose = data.dose
        let user = data.user.isEmpty ? settings.username : data.user
        let doseString: String
        let unitString: String
        if dose > 0 {
            let formattedDose = dose.truncatingRemainder(dividingBy: 1) == 0 ? String(format: "%.0f", dose) : String(dose)
            doseString = data.isEstimate ? "~\(formattedDose)" : formattedDose
            unitString = data.units
        } else {
            doseString = ""
            unitString = ""
        }

        var displaySubstance = data.substanceDisplayName
        if settings.isHyperlinked {
            if let encodedSub = data.substance.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) {
                displaySubstance = "[\(data.substanceDisplayName)](<\(settings.substanceInfoUrl)\(encodedSub)>)"
            }
        }

        let values: [String: String] = [
            "user": user,
            "substance": displaySubstance,
            "dose": doseString,
            "unit": unitString,
            "route": data.route,
            "site": data.site,
            "site_simple": data.simpleSite,
            "note": data.note
        ]

        return processTemplate(settings.template, values: values)
    }

    // The message for a timed note, which is always the user's own
    static func content(forNote note: String, settings: WebhookManager.WebhookSettingsSnapshot) -> String {
        processTemplate(settings.noteTemplate, values: ["user": settings.username, "note": note])
    }

    static func sendWebhookWithRetry(url: String, content: String, editing messageId: String? = nil) async -> WebhookResult {
        await sendWebhookWithRetry(url: url, content: content, editing: messageId) {
            try await URLSession.shared.data(for: $0)
        }
    }

    static func sendWebhookWithRetry(
        url: String,
        content: String,
        editing messageId: String? = nil,
        loadData: LoadData
    ) async -> WebhookResult {
        guard let requestUrl = requestURL(url, messageId: messageId),
              let body = try? JSONEncoder().encode(MessageBody(content: content)) else {
            return WebhookResult(success: false, messageId: nil, error: URLError(.badURL))
        }
        var request = URLRequest(url: requestUrl)
        request.httpMethod = messageId == nil ? "POST" : "PATCH"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Only PATCH is safe to retry. A POST's response can be lost after the message is created.
        let attempts = messageId == nil ? 1 : 3
        var lastError: Error?
        for attempt in 0..<attempts {
            do {
                let (data, response) = try await loadData(request)
                guard let response = response as? HTTPURLResponse else { throw DeliveryError.unknownDelivery }
                guard (200...299).contains(response.statusCode) else {
                    if (400...499).contains(response.statusCode), response.statusCode != 408 {
                        throw DeliveryError.rejected
                    }
                    throw DeliveryError.unknownDelivery
                }
                if let messageId {
                    return WebhookResult(success: true, messageId: messageId, error: nil)
                }
                guard let posted = try? JSONDecoder().decode(PostedMessage.self, from: data), !posted.id.isEmpty else {
                    throw DeliveryError.unknownDelivery
                }
                return WebhookResult(success: true, messageId: posted.id, error: nil)
            } catch {
                if messageId == nil && error as? DeliveryError != .rejected {
                    lastError = DeliveryError.unknownDelivery
                } else {
                    lastError = error
                }
                if attempt < attempts - 1 {
                    let delay = Double(1 << attempt)
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
            }
        }
        return WebhookResult(success: false, messageId: nil, error: lastError)
    }

    private struct MessageBody: Encodable {
        let content: String
    }

    private struct PostedMessage: Decodable {
        let id: String
    }

    private static func requestURL(_ url: String, messageId: String?) -> URL? {
        guard var components = URLComponents(string: url),
              let scheme = components.scheme?.lowercased(),
              scheme == "https" || scheme == "http",
              let host = components.host, !host.isEmpty else { return nil }
        components.fragment = nil
        if let messageId {
            return components.url?.appendingPathComponent("messages").appendingPathComponent(messageId)
        }
        var query = (components.queryItems ?? []).filter { $0.name != "wait" }
        query.append(URLQueryItem(name: "wait", value: "true"))
        components.queryItems = query
        return components.url
    }

    private static let templateRegex: NSRegularExpression? = {
        try? NSRegularExpression(pattern: "\\[([^\\[\\]]+)\\]", options: [])
    }()

    static func processTemplate(_ template: String, values: [String: String]) -> String {
        var processed = template
        guard let regex = templateRegex else {
            return template
        }
        let range = NSRange(processed.startIndex..<processed.endIndex, in: processed)
        let matches = regex.matches(in: processed, options: [], range: range).reversed()

        for match in matches {
            let fullRange = match.range
            let contentRange = match.range(at: 1)

            if let swiftFullRange = Range(fullRange, in: processed),
               let swiftContentRange = Range(contentRange, in: processed) {

                let content = String(processed[swiftContentRange])
                var keepBlock = true

                for (key, value) in values {
                    if content.contains("{\(key)}") && value.isEmpty {
                        keepBlock = false
                        break
                    }
                }

                if keepBlock {
                    processed.replaceSubrange(swiftFullRange, with: content)
                } else {
                    processed.replaceSubrange(swiftFullRange, with: "")
                }
            }
        }

        for (key, value) in values {
            processed = processed.replacingOccurrences(of: "{\(key)}", with: value)
        }

        return processed
    }
}
