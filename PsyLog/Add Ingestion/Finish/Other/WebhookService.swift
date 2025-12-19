import Foundation

struct WebhookResult {
    let success: Bool
    let messageId: String?
    let error: Error?
}

struct WebhookService {
    static let defaultTemplate = "{user}: [{dose} {unit} ]{substance} via {route}[ ({site})][\n> {note}]"

    static func sendWebhook(
        url: String,
        user: String,
        substance: String,
        dose: Double,
        units: String,
        isEstimate: Bool,
        route: String,
        site: String,
        note: String,
        template: String,
        isHyperlinked: Bool,
        substanceInfoUrl: String
    ) async -> WebhookResult {
        return await sendWebhookWithRetry(
            url: url,
            user: user,
            substance: substance,
            dose: dose,
            units: units,
            isEstimate: isEstimate,
            route: route,
            site: site,
            note: note,
            template: template,
            isHyperlinked: isHyperlinked,
            substanceInfoUrl: substanceInfoUrl,
            isEdit: false,
            messageId: nil
        )
    }

    static func editWebhook(
        url: String,
        messageId: String,
        user: String,
        substance: String,
        dose: Double,
        units: String,
        isEstimate: Bool,
        route: String,
        site: String,
        note: String,
        template: String,
        isHyperlinked: Bool,
        substanceInfoUrl: String
    ) async -> WebhookResult {
        await sendWebhookWithRetry(
            url: url,
            user: user,
            substance: substance,
            dose: dose,
            units: units,
            isEstimate: isEstimate,
            route: route,
            site: site,
            note: note,
            template: template,
            isHyperlinked: isHyperlinked,
            substanceInfoUrl: substanceInfoUrl,
            isEdit: true,
            messageId: messageId
        )
    }

    static func deleteWebhookMessage(url: String, messageId: String) async -> Bool {
        guard let webhookUrl = URL(string: url) else { return false }

        let requestUrl = webhookUrl.appendingPathComponent("messages").appendingPathComponent(messageId)
        var request = URLRequest(url: requestUrl)
        request.httpMethod = "DELETE"

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else { return false }
            return (200...299).contains(httpResponse.statusCode)
        } catch {
            return false
        }
    }

    private static func sendWebhookWithRetry(
        url: String,
        user: String,
        substance: String,
        dose: Double,
        units: String,
        isEstimate: Bool,
        route: String,
        site: String,
        note: String,
        template: String,
        isHyperlinked: Bool,
        substanceInfoUrl: String,
        isEdit: Bool,
        messageId: String?
    ) async -> WebhookResult {
        let doseString: String
        let unitString: String
        if dose > 0 {
            let formattedDose = dose.truncatingRemainder(dividingBy: 1) == 0 ? String(format: "%.0f", dose) : String(dose)
            doseString = isEstimate ? "~\(formattedDose)" : formattedDose
            unitString = units
        } else {
            doseString = ""
            unitString = ""
        }

        var displaySubstance = substance
        if isHyperlinked {
            if let encodedSub = substance.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) {
                displaySubstance = "[\(substance)](<\(substanceInfoUrl)\(encodedSub)>)"
            }
        }

        let values: [String: String] = [
            "user": user,
            "substance": displaySubstance,
            "dose": doseString,
            "unit": unitString,
            "route": route,
            "site": site,
            "note": note
        ]

        let content = processTemplate(template, values: values)
        let payload: [String: Any] = ["content": content]

        let maxRetries = 3
        var lastError: Error?

        for attempt in 0..<maxRetries {
            do {
                let result = try await performWebhookRequest(
                    url: url,
                    payload: payload,
                    isEdit: isEdit,
                    messageId: messageId
                )
                return WebhookResult(success: true, messageId: result, error: nil)
            } catch {
                lastError = error
                if attempt < maxRetries - 1 {
                    let delay = Double(1 << attempt)
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
            }
        }

        return WebhookResult(success: false, messageId: nil, error: lastError)
    }

    private static func performWebhookRequest(
        url: String,
        payload: [String: Any],
        isEdit: Bool,
        messageId: String?
    ) async throws -> String? {
        guard let webhookUrl = URL(string: url) else {
            throw URLError(.badURL)
        }

        var requestUrl = webhookUrl
        if isEdit, let messageId = messageId {
            requestUrl = webhookUrl.appendingPathComponent("messages").appendingPathComponent(messageId)
        } else {
            let separator = requestUrl.absoluteString.contains("?") ? "&" : "?"
            guard let urlWithWait = URL(string: requestUrl.absoluteString + separator + "wait=true") else {
                throw URLError(.badURL)
            }
            requestUrl = urlWithWait
        }

        let jsonData = try JSONSerialization.data(withJSONObject: payload)
        var request = URLRequest(url: requestUrl)
        request.httpMethod = isEdit ? "PATCH" : "POST"
        request.httpBody = jsonData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        if !isEdit, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let messageId = json["id"] as? String {
            return messageId
        }

        return nil
    }

    static func processTemplate(_ template: String, values: [String: String]) -> String {
        var processed = template
        let pattern = "\\[([^\\[\\]]+)\\]"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
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
