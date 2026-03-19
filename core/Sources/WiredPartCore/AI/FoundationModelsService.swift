import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

// MARK: - AI Availability

/// Describes the availability status of the on-device AI model.
public enum AIAvailability: String, Sendable {
    case available
    case deviceNotEligible
    case appleIntelligenceNotEnabled
    case modelNotReady
    case unavailable
    case notSupported // Platform too old
}

// MARK: - Enhance Mode

/// Text enhancement modes matching the TypeScript implementation.
public enum EnhanceMode: String, Sendable, CaseIterable {
    case proofread
    case rewrite
    case summarize
    case expand
    case professional

    public var displayName: String {
        rawValue.capitalized
    }

    public var systemImage: String {
        switch self {
        case .proofread: return "text.magnifyingglass"
        case .rewrite: return "arrow.triangle.2.circlepath"
        case .summarize: return "text.badge.minus"
        case .expand: return "text.badge.plus"
        case .professional: return "briefcase"
        }
    }
}

// MARK: - AI Result

/// Result of an AI text generation operation.
public struct AIResult: Sendable {
    public let success: Bool
    public let text: String?
    public let error: String?

    public static func ok(_ text: String) -> AIResult {
        AIResult(success: true, text: text, error: nil)
    }

    public static func fail(_ error: String) -> AIResult {
        AIResult(success: false, text: nil, error: error)
    }
}

// MARK: - Foundation Models Service

/// Provides on-device AI text generation via Apple Foundation Models.
///
/// This service wraps `LanguageModelSession` to provide:
/// - Availability checking
/// - Text completion (autocomplete suggestions)
/// - Text enhancement (proofread, rewrite, summarize, expand, professional)
/// - Pre-fill generation for empty fields
///
/// All methods are safe to call on any platform. On platforms where
/// Foundation Models is not available, methods return graceful fallbacks.
public actor FoundationModelsService {

    /// Maximum characters of context to send to the model.
    private let maxContextChars: Int

    /// System instructions for the electrical contracting domain.
    private let domainInstructions = """
        You are an AI assistant for an electrical contracting business management app \
        called WiredPart. Write in a professional, trade-appropriate tone. Keep responses \
        concise and practical. Use terminology common in electrical contracting, \
        construction, and trade work.
        """

    public init(maxContextChars: Int = 1000) {
        self.maxContextChars = maxContextChars
    }

    // MARK: - Availability

    /// Check whether the on-device AI model is available.
    public func checkAvailability() -> AIAvailability {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, iOS 26.0, *) {
            let model = SystemLanguageModel.default
            switch model.availability {
            case .available:
                return .available
            case .unavailable(.deviceNotEligible):
                return .deviceNotEligible
            case .unavailable(.appleIntelligenceNotEnabled):
                return .appleIntelligenceNotEnabled
            case .unavailable(.modelNotReady):
                return .modelNotReady
            case .unavailable:
                return .unavailable
            }
        } else {
            return .notSupported
        }
        #else
        return .notSupported
        #endif
    }

    /// Convenience: returns true only when the model is fully available.
    public func isAvailable() -> Bool {
        checkAvailability() == .available
    }

    // MARK: - Text Completion

    /// Generate an inline autocomplete suggestion for partial text.
    ///
    /// - Parameters:
    ///   - partialText: The text the user has typed so far.
    ///   - fieldType: Description of the field (e.g. "job notes", "dispatch notes").
    ///   - contextData: Additional context key-value pairs.
    /// - Returns: An `AIResult` containing the suggested continuation text.
    public func generateCompletion(
        partialText: String,
        fieldType: String? = nil,
        contextData: [String: String]? = nil
    ) async -> AIResult {
        guard partialText.count >= 10 else {
            return .fail("Text too short for completion")
        }

        let trimmed = String(partialText.suffix(maxContextChars))

        var instructions = domainInstructions + "\n\n"
        instructions += "Complete the following text naturally. "
        instructions += "Only output the continuation — do not repeat any of the existing text. "
        instructions += "Keep the continuation brief (1-2 sentences max)."

        if let fieldType {
            instructions += "\nThis text is for a \(fieldType) field."
        }

        var prompt = trimmed
        if let contextData, !contextData.isEmpty {
            let contextStr = contextData.map { "\($0.key): \($0.value)" }.joined(separator: ", ")
            prompt = "Context: \(contextStr)\n\nText to complete: \(trimmed)"
        }

        return await generate(instructions: instructions, prompt: prompt)
    }

    // MARK: - Text Enhancement

    /// Enhance existing text using the specified mode.
    ///
    /// - Parameters:
    ///   - text: The original text to enhance.
    ///   - mode: The enhancement mode (proofread, rewrite, etc.).
    ///   - fieldType: Description of the field context.
    /// - Returns: An `AIResult` containing the enhanced text.
    public func enhanceText(
        text: String,
        mode: EnhanceMode,
        fieldType: String? = nil
    ) async -> AIResult {
        guard !text.isEmpty else {
            return .fail("No text to enhance")
        }

        var instructions = domainInstructions + "\n\n"

        switch mode {
        case .proofread:
            instructions += """
                Fix spelling, grammar, and punctuation errors. \
                Keep the original meaning and style. \
                Only output the corrected text.
                """
        case .rewrite:
            instructions += """
                Rewrite the following text to be clearer and more professional. \
                Keep the same meaning. Only output the rewritten text.
                """
        case .summarize:
            instructions += """
                Summarize the following text in 1-3 concise sentences. \
                Focus on the key information. Only output the summary.
                """
        case .expand:
            instructions += """
                Expand the following text with more detail and context. \
                Keep the professional tone. Only output the expanded text.
                """
        case .professional:
            instructions += """
                Rewrite the following text in a formal, professional business tone. \
                Keep the same meaning. Only output the professional version.
                """
        }

        if let fieldType {
            instructions += "\nThis text is for a \(fieldType) field."
        }

        return await generate(instructions: instructions, prompt: text)
    }

    // MARK: - Pre-Fill Generation

    /// Generate draft content for an empty field based on context.
    ///
    /// - Parameters:
    ///   - fieldType: The type of field to pre-fill (e.g. "dispatch notes", "job description").
    ///   - contextData: Key-value pairs providing context (e.g. jobName, crewLead, date).
    /// - Returns: An `AIResult` containing the generated draft text.
    public func generatePreFill(
        fieldType: String,
        contextData: [String: String]
    ) async -> AIResult {
        guard !contextData.isEmpty else {
            return .fail("No context data provided")
        }

        var instructions = domainInstructions + "\n\n"
        instructions += """
            Generate a draft for a \(fieldType) field. \
            Use the provided context to create appropriate content. \
            Keep it concise and professional. \
            Only output the draft text — no labels or formatting.
            """

        let contextStr = contextData.map { "- \($0.key): \($0.value)" }.joined(separator: "\n")
        let prompt = "Generate a \(fieldType) using this context:\n\(contextStr)"

        return await generate(instructions: instructions, prompt: prompt)
    }

    // MARK: - Chat / Q&A

    /// Respond to a general natural-language question about the business.
    ///
    /// - Parameter query: The user's question.
    /// - Returns: An `AIResult` containing the assistant's response.
    public func chat(query: String) async -> AIResult {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            return .fail("Empty query")
        }

        let instructions = domainInstructions + "\n\n" + """
            Answer the user's question helpfully and concisely. \
            If the question is about app navigation, explain where to find the feature. \
            If you don't have enough information, say so honestly. \
            Keep responses under 3 sentences when possible.
            """

        return await generate(instructions: instructions, prompt: query)
    }

    // MARK: - Chat with Tools (Database Access)

    /// Respond to a question using Foundation Models tool calling for real database access.
    ///
    /// Tools are automatically called by the framework when the model decides they're needed.
    /// Each tool respects user permissions — queries for data the user can't see return
    /// a permission-denied message instead of results.
    ///
    /// - Parameters:
    ///   - query: The user's question.
    ///   - db: The app database for tool queries.
    ///   - permissions: The current user's permission keys.
    ///   - navigationContext: A string describing the app's module/tab layout with access annotations.
    /// - Returns: An `AIResult` containing the assistant's response.
    public func chatWithTools(
        query: String,
        db: AppDatabase,
        permissions: [String],
        navigationContext: String
    ) async -> AIResult {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            return .fail("Empty query")
        }

        #if canImport(FoundationModels)
        if #available(macOS 26.0, iOS 26.0, *) {
            do {
                let tools: [any FoundationModels.Tool] = [
                    SearchPartsTool(db: db, permissions: permissions),
                    SearchContactsTool(db: db, permissions: permissions),
                    SearchJobsTool(db: db, permissions: permissions),
                    GetSupplierInfoTool(db: db, permissions: permissions),
                ]

                let chatInstructions = domainInstructions + "\n\n" + """
                    You are a helpful assistant for the WiredPart app. You have access to tools \
                    that can search the local database for parts, contacts, jobs, and suppliers. \
                    Use these tools when the user asks about specific data. \
                    \
                    When answering navigation questions, use the app layout below to direct users \
                    to the correct module and tab. If a section is marked [NO ACCESS], tell the user \
                    they don't have permission and suggest they talk to their admin. \
                    \
                    Keep responses concise and practical. If you used a tool, summarize the results \
                    naturally — don't just dump raw data. \
                    \
                    \(navigationContext)
                    """

                let session = LanguageModelSession(tools: tools, instructions: chatInstructions)
                let response = try await session.respond(to: query)
                let text = response.content
                return .ok(text.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines))
            } catch {
                return .fail("AI generation failed: \(error.localizedDescription)")
            }
        } else {
            return .fail("Foundation Models requires macOS 26+ or iOS 26+")
        }
        #else
        return .fail("Foundation Models not available on this platform")
        #endif
    }

    // MARK: - Private Generation

    /// Core generation method that handles the FoundationModels API call.
    private func generate(instructions: String, prompt: String) async -> AIResult {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, iOS 26.0, *) {
            do {
                let session = LanguageModelSession(instructions: instructions)
                let response = try await session.respond(to: prompt)
                let text = response.content
                return .ok(text.trimmingCharacters(in: .whitespacesAndNewlines))
            } catch {
                return .fail("AI generation failed: \(error.localizedDescription)")
            }
        } else {
            return .fail("Foundation Models requires macOS 26+ or iOS 26+")
        }
        #else
        return .fail("Foundation Models not available on this platform")
        #endif
    }
}
