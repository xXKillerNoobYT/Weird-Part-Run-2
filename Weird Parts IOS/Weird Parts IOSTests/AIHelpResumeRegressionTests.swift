import XCTest
@testable import Weird_Parts

/// Regression coverage for GitHub #1459 / WEI-4986: Help can seed a local,
/// read-only assistant turn and users can safely resume persisted conversations.
final class AIHelpResumeRegressionTests: XCTestCase {
    func testHelpHandoffUsesStableNotificationAndOwnedPayload() throws {
        let navigation = try Self.readSource("Navigation/NavigationConfig.swift")
        let helpSheet = try Self.readSource("Shared/PageHelpSheet.swift")
        let mainView = try Self.readSource("Navigation/IOSMainView.swift")

        XCTAssertTrue(navigation.contains("WiredPart.askAIAboutHelp"))
        XCTAssertFalse(navigation.contains("WiredPart.seedAIHelpRequest"))
        XCTAssertTrue(
            helpSheet.contains("name: .askAIAboutHelp")
                && helpSheet.contains("\"requestID\": UUID().uuidString")
                && helpSheet.contains("\"title\": title")
                && helpSheet.contains("\"prompt\": prompt")
                && helpSheet.contains("\"helpBody\": helpBody"),
            "The Help action must forward the visible read-only help content."
        )
        XCTAssertTrue(helpSheet.contains(".onDisappear"))
        XCTAssertTrue(helpSheet.contains("pendingAIHelpRequest = userInfo"))
        XCTAssertTrue(
            mainView.contains("publisher(for: .askAIAboutHelp)")
                && mainView.contains("pendingHelpRequest: $pendingAIHelpRequest"),
            "The shell must present the assistant with an owned pending Help payload."
        )
    }

    func testHelpAffordanceIsVisibleTouchFriendlyAndAccessible() throws {
        let helpSheet = try Self.readSource("Shared/PageHelpSheet.swift")

        XCTAssertTrue(helpSheet.contains("Label(\"Ask AI about this page\", systemImage: \"sparkles\")"))
        XCTAssertTrue(helpSheet.contains("minHeight: 44"))
        XCTAssertTrue(helpSheet.contains("accessibilityLabel(\"Ask AI about this help page\")"))
        XCTAssertTrue(helpSheet.contains("accessibilityIdentifier(\"askAIAboutHelpButton\")"))
        XCTAssertTrue(helpSheet.contains("HelpContentRegistry.pageId(matchingTitle: title)"))
    }

    @MainActor
    func testHelpTitleLookupUsesDeclarationOrderForDuplicateNormalizedTitles() throws {
        let candidates = [
            HelpContentRegistry.HelpEntry(
                pageId: "expected-context",
                title: "Shared Help",
                sections: [("Expected", "First declaration wins.")]
            ),
            HelpContentRegistry.HelpEntry(
                pageId: "wrong-context",
                title: "  shared help  ",
                sections: [("Wrong", "Dictionary value order must not pick this duplicate.")]
            ),
        ]

        XCTAssertEqual(
            HelpContentRegistry.pageId(matchingTitle: "\nSHARED HELP\t", in: candidates),
            "expected-context"
        )
        XCTAssertNotEqual(
            HelpContentRegistry.pageId(matchingTitle: "shared help", in: candidates),
            "wrong-context",
            "Duplicate normalized titles must not hand the assistant the wrong page context."
        )
    }

    func testHelpTitleLookupDoesNotUseDictionaryValueOrder() throws {
        let registry = try Self.readSource("Shared/HelpContentRegistry.swift")
        let lookup = try TestSourceSlicer.braceBalancedBody(
            after: "static func pageId(matchingTitle title: String)",
            in: registry
        )

        XCTAssertTrue(lookup.contains("pageId(matchingTitle: title, in: allEntries)"))
        XCTAssertFalse(registry.contains("entries.values.first"))
    }

    func testHelpHandoffSeedsLocalResponseWithoutModelCall() throws {
        let assistant = try Self.readSource("AI/IOSAIAssistantPanel.swift")
        let handoff = try TestSourceSlicer.braceBalancedBody(
            after: "private func handleHelpHandoff(_ userInfo: [AnyHashable: Any])",
            in: assistant
        )

        XCTAssertTrue(handoff.contains("formattedHelpResponse"))
        XCTAssertTrue(handoff.contains("messages.append(AssistantMessage(role: .user"))
        XCTAssertTrue(handoff.contains("messages.append(AssistantMessage(role: .assistant"))
        XCTAssertTrue(handoff.contains("helpBody"), "Unregistered Help sheets need a visible-content fallback.")
        XCTAssertFalse(handoff.contains("generateResponse"), "Help handoff must not require a model response.")
        XCTAssertFalse(handoff.contains("chatWithTools"), "Help handoff must remain local and read-only.")
    }

    func testHelpHandoffWaitsForAnInFlightSendBeforeSeedingHelp() throws {
        let assistant = try Self.readSource("AI/IOSAIAssistantPanel.swift")
        let handoff = try TestSourceSlicer.braceBalancedBody(
            after: "private func handleHelpHandoff(_ userInfo: [AnyHashable: Any])",
            in: assistant
        )
        XCTAssertTrue(handoff.contains("!isProcessing"))
        XCTAssertTrue(handoff.contains("pendingFallbackSave == nil"))
        XCTAssertTrue(handoff.contains("helpHandoffReadiness.queueHelpRequest("))
        XCTAssertFalse(handoff.contains("isProcessing = false"))

        let send = try TestSourceSlicer.braceBalancedBody(
            after: "private func sendQuery()",
            in: assistant
        )
        guard let finish = send.range(of: "helpHandoffReadiness.finishSendLifecycle(sendLifecycleRequestID)")?.lowerBound,
              let consume = send.range(of: "consumePendingHelpRequestIfReady()")?.lowerBound else {
            XCTFail("Send completion must release its lifecycle before consuming queued Help.")
            return
        }
        XCTAssertLessThan(finish, consume)
    }

    func testResumeControlsUseExistingPersistenceHelpersAndSafeEmptyState() throws {
        let assistant = try Self.readSource("AI/IOSAIAssistantPanel.swift")

        XCTAssertTrue(assistant.contains("FoundationModelsService.latestConversationId("))
        XCTAssertTrue(assistant.contains("FoundationModelsService.listConversations("))
        XCTAssertTrue(assistant.contains("let ownerUserId = appCore.aiConversationReadOwnerUserId"))
        XCTAssertTrue(assistant.contains("savedConversations = []"))
        XCTAssertTrue(assistant.contains("No Saved Conversations"))
        XCTAssertTrue(assistant.contains("Loading conversations…"))
        XCTAssertTrue(assistant.contains("accessibilityLabel(\"Resume a past conversation\")"))
        XCTAssertTrue(assistant.contains("accessibilityLabel(\"Resume conversation: \\(plainText(fromMarkdown: conversation.preview))\")"))
        XCTAssertTrue(assistant.contains("await resumeLastConversationIfNeeded()"))
        XCTAssertTrue(assistant.contains(".task(id: resumePrerequisiteToken)"))
        XCTAssertTrue(assistant.contains(".frame(width: 44, height: 44)\n                        .contentShape(Rectangle())"))
        XCTAssertTrue(assistant.contains(".frame(width: 44, height: 44)\n            .contentShape(Rectangle())"))
    }

    func testResumeAttemptWaitsForDatabaseAndAuthenticatedUser() throws {
        let assistant = try Self.readSource("AI/IOSAIAssistantPanel.swift")
        let resume = try TestSourceSlicer.braceBalancedBody(
            after: "private func resumeLastConversationIfNeeded() async",
            in: assistant
        )

        guard let prerequisiteIndex = resume.range(of: "guard let db = appCore.aiConversationReadDatabase")?.lowerBound,
              let attemptedIndex = resume.range(of: "didAttemptResume = true")?.lowerBound else {
            XCTFail("Automatic resume must guard its prerequisites and record the attempt.")
            return
        }
        XCTAssertLessThan(prerequisiteIndex, attemptedIndex)
        XCTAssertTrue(assistant.contains("private var resumePrerequisiteToken: ResumePrerequisiteToken"))
        XCTAssertTrue(assistant.contains("ownerUserId: appCore.aiConversationReadOwnerUserId"))
        XCTAssertTrue(assistant.contains("databaseIdentity: appCore.aiConversationReadDatabase.map(ObjectIdentifier.init)"))
    }

    func testInitializationTaskKeepsMissingPrerequisitesFailClosedUntilTokenChanges() throws {
        let assistant = try Self.readSource("AI/IOSAIAssistantPanel.swift")
        let task = try TestSourceSlicer.braceBalancedBody(
            after: ".task(id: resumePrerequisiteToken)",
            in: assistant
        )

        XCTAssertTrue(task.contains("let initializationPrerequisites = resumePrerequisiteToken"))
        XCTAssertTrue(task.contains("isLoadingConversationHistory = true"))
        XCTAssertTrue(task.contains("guard await resumeLastConversationIfNeeded() else"))
        XCTAssertTrue(task.contains("guard resumePrerequisiteToken == initializationPrerequisites else { return }"))
        XCTAssertTrue(task.contains("AIAssistantInitializationLoadingPolicy.keepsLoading("))
        XCTAssertTrue(task.contains("prerequisitesAvailable: initializationPrerequisites.databaseIdentity != nil"))
        XCTAssertFalse(
            task.contains("guard await resumeLastConversationIfNeeded() else {\n                guard resumePrerequisiteToken == initializationPrerequisites else { return }\n                isLoadingConversationHistory = false"),
            "Missing DB/user prerequisites must not enable a blank composer before the keyed task retries."
        )
    }

    func testConversationReadFailureLogsKeepLocalizedDetailsPrivate() throws {
        let assistant = try Self.readSource("AI/IOSAIAssistantPanel.swift")

        XCTAssertEqual(
            assistant.components(separatedBy: "error.localizedDescription, privacy: .private").count - 1,
            3
        )
        XCTAssertFalse(assistant.contains("error.localizedDescription, privacy: .public"))
    }

    func testTranscriptHydrationFailureSurfacesRetryWithoutWelcomeFallback() throws {
        let assistant = try Self.readSource("AI/IOSAIAssistantPanel.swift")
        let load = try TestSourceSlicer.braceBalancedBody(
            after: "private func loadSavedMessages() async",
            in: assistant
        )
        let catchBody = try XCTUnwrap(load.components(separatedBy: "} catch {").last)

        XCTAssertTrue(catchBody.contains("conversationHistoryReadError = \"Stored messages could not be loaded"))
        XCTAssertTrue(catchBody.contains("conversationHistoryRetry = .transcriptHydration"))
        XCTAssertTrue(catchBody.contains("aiConversationLog.error"))
        XCTAssertFalse(
            catchBody.contains("addWelcomeMessageIfNeeded()"),
            "A thrown transcript read must not masquerade as a genuinely empty conversation."
        )
        XCTAssertTrue(assistant.contains("accessibilityLabel(\"Retry loading conversation history\")"))
    }

    func testLatestConversationLookupFailureRemainsRetryableForSameOwner() throws {
        let assistant = try Self.readSource("AI/IOSAIAssistantPanel.swift")
        let latest = try TestSourceSlicer.braceBalancedBody(
            after: "private func resumeLastConversationIfNeeded() async -> Bool",
            in: assistant
        )

        XCTAssertTrue(latest.contains("let latest = try await FoundationModelsService.latestConversationId"))
        XCTAssertFalse(latest.contains("try? await FoundationModelsService.latestConversationId"))
        XCTAssertTrue(latest.contains("appCore.aiConversationReadOwnerUserId == ownerUserId"))
        XCTAssertTrue(latest.contains("didAttemptResume = false"))
        XCTAssertTrue(latest.contains("conversationHistoryRetry = .latestConversationLookup"))
        XCTAssertTrue(latest.contains("return false"))

        let retry = try TestSourceSlicer.braceBalancedBody(
            after: "private func retryConversationHistoryRead()",
            in: assistant
        )
        XCTAssertTrue(retry.contains("guard await resumeLastConversationIfNeeded()"))
        XCTAssertTrue(retry.contains("await loadCurrentConversation()"))
    }

    func testHistoryRetryCapturesFullLifecycleAndKeepsMissingPrerequisitesFailClosed() throws {
        let assistant = try Self.readSource("AI/IOSAIAssistantPanel.swift")
        let retry = try TestSourceSlicer.braceBalancedBody(
            after: "private func retryConversationHistoryRead()",
            in: assistant
        )

        guard let prerequisiteGuard = retry.range(of: "guard let retry = conversationHistoryRetry")?.lowerBound,
              let errorClear = retry.range(of: "conversationHistoryReadError = nil")?.lowerBound else {
            XCTFail("Retry must validate prerequisites before clearing its fail-closed error state.")
            return
        }
        XCTAssertLessThan(prerequisiteGuard, errorClear)
        XCTAssertTrue(retry.contains("AIConversationHistoryRetryToken("))
        XCTAssertTrue(retry.contains("ownerUserId: appCore.aiConversationReadOwnerUserId"))
        XCTAssertTrue(retry.contains("database: appCore.aiConversationReadDatabase"))
        XCTAssertTrue(retry.contains("conversationId: conversationId"))
        XCTAssertTrue(retry.contains("revision: conversationRevision"))
        XCTAssertTrue(retry.contains("completionToken.matches("))
        XCTAssertTrue(assistant.contains("@State private var conversationHistoryRetryTask: Task<Void, Never>?"))
    }

    func testPrerequisiteReplacementResetsVisibleTranscriptAndResumeScope() throws {
        let assistant = try Self.readSource("AI/IOSAIAssistantPanel.swift")
        let reset = try TestSourceSlicer.braceBalancedBody(
            after: "private func resetConversationReadScopeIfNeeded(for prerequisites: ResumePrerequisiteToken)",
            in: assistant
        )

        XCTAssertTrue(reset.contains("AIConversationReadScopeState("))
        XCTAssertTrue(reset.contains("scopeState.replaceScope"))
        XCTAssertTrue(reset.contains("guard prerequisites.databaseIdentity != nil"))
        XCTAssertTrue(reset.contains("(prerequisites.ownerUserId ?? 0) > 0"))
        XCTAssertTrue(reset.contains("isLoadingConversationHistory = true"))
        XCTAssertTrue(reset.contains("didAttemptResume = scopeState.didAttemptResume"))
        XCTAssertTrue(reset.contains("conversationId = scopeState.conversationId"))
        XCTAssertTrue(reset.contains("messages = scopeState.messages"))
        XCTAssertTrue(reset.contains("savedConversations = scopeState.savedConversations"))
        XCTAssertTrue(reset.contains("conversationHistoryReadError = nil"))
        XCTAssertTrue(reset.contains("showConversationPicker = false"))
        XCTAssertTrue(reset.contains("isLoadingConversationHistory = true"))
        XCTAssertTrue(
            reset.contains("cancelConversationListLoad(clearError: false)"),
            "Withdrawing prerequisites must retire an in-flight Resume load without discarding its retryable error."
        )
        XCTAssertTrue(reset.contains("let wasLoadingConversationList = isLoadingConversations"))
        XCTAssertTrue(reset.contains("AIConversationListReadFailurePolicy.errorAfterPrerequisiteWithdrawal("))
    }

    func testResumeListFailurePreservesRowsAndDoesNotRenderEmptyCopy() throws {
        let assistant = try Self.readSource("AI/IOSAIAssistantPanel.swift")
        let list = try TestSourceSlicer.braceBalancedBody(
            after: "private func loadConversationList(requestID: UInt) async",
            in: assistant
        )

        XCTAssertTrue(list.contains("let rows = try await FoundationModelsService.listConversations"))
        XCTAssertFalse(list.contains("try? await FoundationModelsService.listConversations"))
        XCTAssertTrue(list.contains("rows: savedConversations"))
        XCTAssertTrue(list.contains("conversationListReadError = \"Saved conversations could not be read"))
        XCTAssertTrue(list.contains("finishConversationListPrerequisiteFailure(requestID: requestID)"))
        XCTAssertTrue(list.contains("isLoadingConversations = lifecycleCoordinator.isLoadingConversations"))
        XCTAssertTrue(list.contains("appCore.aiConversationReadOwnerUserId"))
        XCTAssertTrue(assistant.contains("else if let conversationListReadError"))
        XCTAssertTrue(assistant.contains("accessibilityLabel(\"Retry loading saved conversations\")"))

        guard let errorBranch = assistant.range(of: "else if let conversationListReadError")?.lowerBound,
              let emptyBranch = assistant.range(of: "else if savedConversations.isEmpty")?.lowerBound else {
            XCTFail("Resume picker must distinguish read failure from a genuine empty result.")
            return
        }
        XCTAssertLessThan(errorBranch, emptyBranch)
    }

    func testResumeRetryKeepsErrorUntilAReplacementReadSucceeds() throws {
        let assistant = try Self.readSource("AI/IOSAIAssistantPanel.swift")
        let present = try TestSourceSlicer.braceBalancedBody(
            after: "private func presentConversationPicker()",
            in: assistant
        )
        let load = try TestSourceSlicer.braceBalancedBody(
            after: "private func loadConversationList(requestID: UInt) async",
            in: assistant
        )

        XCTAssertFalse(
            present.contains("conversationListReadError = nil"),
            "Starting Retry must retain the last error behind the loading UI so prerequisite withdrawal can reveal Retry again."
        )
        XCTAssertTrue(load.contains("conversationListReadError = nil"), "Only a matching successful list read may clear the error.")
    }

    func testConversationLifecycleUsesReadScopedOwnerAndFailureIconIsDecorative() throws {
        let assistant = try Self.readSource("AI/IOSAIAssistantPanel.swift")
        let lifecycle = try TestSourceSlicer.braceBalancedBody(
            after: "private func currentLifecycleCoordinator()",
            in: assistant
        )
        let failure = try TestSourceSlicer.braceBalancedBody(
            after: "private func conversationListReadFailure(message: String)",
            in: assistant
        )

        XCTAssertTrue(lifecycle.contains("ownerUserId: appCore.aiConversationReadOwnerUserId"))
        XCTAssertFalse(lifecycle.contains("ownerUserId: appCore.currentUser?.id"))
        XCTAssertTrue(failure.contains(".accessibilityHidden(true)"), "The warning symbol must not duplicate the readable failure copy in VoiceOver.")
    }

    func testReadFailureRetryControlsExpose44PointAccessibleHitRegions() throws {
        let assistant = try Self.readSource("AI/IOSAIAssistantPanel.swift")

        XCTAssertTrue(
            assistant.contains(
                "Text(\"Retry\")\n                            .frame(minWidth: 45, minHeight: 45)\n                            .contentShape(Rectangle())\n                    }\n                    .buttonStyle(.borderedProminent)\n                    .accessibilityLabel(\"Retry loading saved conversations\")"
            ),
            "The saved-conversation Retry label must own a 44×44-point hit region before button styling is applied."
        )
        XCTAssertTrue(
            assistant.contains(
                "Text(\"Retry\")\n                        .font(.caption)\n                        .frame(minWidth: 45, minHeight: 45)\n                        .contentShape(Rectangle())\n                }\n                .disabled(isLoadingConversationHistory)\n                .accessibilityLabel(\"Retry loading conversation history\")"
            ),
            "The history Retry label must own a 44×44-point hit region while preserving its accessible name and disabled state."
        )
    }

    func testReadFailureQAControlsExposeOnlyOneAccessibilitySurfaceWhileResumeIsPresented() throws {
        let assistant = try Self.readSource("AI/IOSAIAssistantPanel.swift")
        let chatBody = try TestSourceSlicer.braceBalancedBody(
            after: "private var chatBody: some View",
            in: assistant
        )
        let picker = try TestSourceSlicer.braceBalancedBody(
            after: "private var conversationPicker: some View",
            in: assistant
        )

        XCTAssertTrue(
            chatBody.contains("aiReadRecoveryQAControls") && chatBody.contains("&& !showConversationPicker"),
            "The assistant-body QA controls must leave the accessibility tree while Resume owns the controls."
        )
        XCTAssertTrue(picker.contains("aiReadRecoveryQAControls"))
        XCTAssertFalse(picker.contains("!showConversationPicker"))
    }

    func testPrerequisiteRecoverySeamIsSimulatorFlagGatedAndReadScoped() throws {
        let appCore = try Self.readSource("App/AppCore.swift")
        let assistant = try Self.readSource("AI/IOSAIAssistantPanel.swift")
        let databaseAccessor = try TestSourceSlicer.braceBalancedBody(
            after: "var aiConversationReadDatabase: AppDatabase?",
            in: appCore
        )
        let ownerAccessor = try TestSourceSlicer.braceBalancedBody(
            after: "var aiConversationReadOwnerUserId: Int64?",
            in: appCore
        )
        let controls = try TestSourceSlicer.braceBalancedBody(
            after: "private var wei5159AIPrerequisiteRecoveryQAControls: some View",
            in: assistant
        )

        XCTAssertTrue(appCore.contains("#if DEBUG && targetEnvironment(simulator)"))
        XCTAssertTrue(appCore.contains("-UITestingWEI5159AIPrerequisiteRecovery"))
        XCTAssertTrue(appCore.contains("arguments.contains(Self.uiTestingLaunchFlag)"))
        XCTAssertTrue(databaseAccessor.contains("return nil"))
        XCTAssertTrue(databaseAccessor.contains("return db"))
        XCTAssertTrue(ownerAccessor.contains("return nil"))
        XCTAssertTrue(ownerAccessor.contains("return currentUser?.id"))
        XCTAssertTrue(assistant.contains("appCore.aiConversationReadDatabase"))
        XCTAssertTrue(assistant.contains("appCore.aiConversationReadOwnerUserId"))
        XCTAssertTrue(assistant.contains("await appCore.waitForWEI5159AIConversationListLoadReleaseIfNeeded()"))
        XCTAssertTrue(controls.contains(".frame(minWidth: 45, minHeight: 45)"))
        XCTAssertTrue(controls.contains("WEI5159 withhold AI conversation prerequisites"))
        XCTAssertTrue(controls.contains("WEI5159 restore AI conversation prerequisites"))
        XCTAssertTrue(controls.contains("WEI5159 suspend next saved conversation load"))
    }

    func testReadFailureFixtureSQLUsesCanonicalTableNameConstants() throws {
        let appCore = try Self.readSource("App/AppCore.swift")
        let fixture = try TestSourceSlicer.braceBalancedBody(
            after: "nonisolated private static func prepareWEI5134AIReadFailureFixture(",
            in: appCore
        )
        let transition = try TestSourceSlicer.braceBalancedBody(
            after: "func setWEI5134AIConversationTableBroken(_ shouldBeBroken: Bool)",
            in: appCore
        )

        XCTAssertTrue(fixture.contains("DELETE FROM \\(Self.wei5134AIConversationTable)"))
        XCTAssertTrue(fixture.contains("INSERT INTO \\(Self.wei5134AIConversationTable)"))
        XCTAssertTrue(
            fixture.contains(
                "ALTER TABLE \\(Self.wei5134AIConversationTable) RENAME TO \\(Self.wei5134AIConversationBackupTable)"
            )
        )
        XCTAssertTrue(
            transition.contains(
                "ALTER TABLE \\(Self.wei5134AIConversationTable) RENAME TO \\(Self.wei5134AIConversationBackupTable)"
            )
        )
        XCTAssertTrue(
            transition.contains(
                "ALTER TABLE \\(Self.wei5134AIConversationBackupTable) RENAME TO \\(Self.wei5134AIConversationTable)"
            )
        )
        XCTAssertTrue(transition.contains("error.localizedDescription, privacy: .private"))
        XCTAssertTrue(transition.contains("WEI5134 QA table state: error — transition failed"))
        XCTAssertFalse(
            transition.contains("wei5134AIReadFailureQAState = \"WEI5134 QA table state: error — \\(error.localizedDescription)\""),
            "The accessibility-observable QA state must not expose private database or file details."
        )
    }

    #if DEBUG && targetEnvironment(simulator)
    func testSharedAIConversationFixtureTopologyDiagnosticIsTruthfulForBothModes() throws {
        let diagnostic = AppCore.UITestBootstrapError.aiConversationFixtureInvalidTableTopology(
            currentExists: true,
            backupExists: true
        )
        XCTAssertEqual(
            diagnostic.errorDescription,
            "AI conversation UI-test fixture table topology is invalid (current: true, backup: true)."
        )
        XCTAssertFalse(
            diagnostic.errorDescription?.contains("WEI-5134") == true,
            "A topology error shared by WEI-5134 and WEI-5159 must not identify only one fixture mode."
        )

        let appCore = try Self.readSource("App/AppCore.swift")
        let readFailureFixture = try TestSourceSlicer.braceBalancedBody(
            after: "nonisolated private static func prepareWEI5134AIReadFailureFixture(",
            in: appCore
        )
        let prerequisiteFixture = try TestSourceSlicer.braceBalancedBody(
            after: "nonisolated private static func prepareWEI5159AIPrerequisiteRecoveryFixture(",
            in: appCore
        )
        let transition = try TestSourceSlicer.braceBalancedBody(
            after: "func setWEI5134AIConversationTableBroken(_ shouldBeBroken: Bool)",
            in: appCore
        )
        let sharedThrow = "throw UITestBootstrapError.aiConversationFixtureInvalidTableTopology("

        XCTAssertTrue(readFailureFixture.contains(sharedThrow))
        XCTAssertTrue(prerequisiteFixture.contains(sharedThrow))
        XCTAssertTrue(transition.contains(sharedThrow))
        XCTAssertFalse(appCore.contains("wei5134InvalidTableTopology"))
    }
    #endif

    func testSelectingCurrentConversationAfterHydrationFailureStartsRecoveryBeforeClearingFailure() throws {
        let assistant = try Self.readSource("AI/IOSAIAssistantPanel.swift")
        let resume = try TestSourceSlicer.braceBalancedBody(
            after: "private func resumeConversation(_ id: String)",
            in: assistant
        )

        guard let policyIndex = resume.range(of: "AIAssistantResumeSelectionPolicy.action(")?.lowerBound,
              let recoveryIndex = resume.range(of: "case .retryCurrentHydration:")?.lowerBound,
              let loadIndex = resume.range(of: "beginCurrentConversationLoad()")?.lowerBound,
              let clearIndex = resume.range(of: "conversationHistoryReadError = nil")?.lowerBound else {
            XCTFail("Resume must route a failed same-conversation selection through recovery hydration.")
            return
        }
        XCTAssertLessThan(policyIndex, recoveryIndex)
        XCTAssertLessThan(recoveryIndex, loadIndex)
        XCTAssertLessThan(loadIndex, clearIndex)
        XCTAssertTrue(resume.contains("hasTranscriptHydrationFailure: conversationHistoryRetry == .transcriptHydration"))
    }

    func testHelpObservationUsesDedicatedConstantSizeRequestIdentity() throws {
        let assistant = try Self.readSource("AI/IOSAIAssistantPanel.swift")
        let token = try TestSourceSlicer.braceBalancedBody(
            after: "private var pendingHelpRequestToken: String?",
            in: assistant
        )

        XCTAssertTrue(token.contains("pendingHelpRequest?[\"requestID\"] as? String"))
        XCTAssertFalse(token.contains("helpBody"))
        XCTAssertFalse(token.contains("joined"))
    }

    func testHelpHandoffWaitsForInitialHistoryAndClearWaitsForPersistence() throws {
        let assistant = try Self.readSource("AI/IOSAIAssistantPanel.swift")
        let mainView = try Self.readSource("Navigation/IOSMainView.swift")

        XCTAssertTrue(assistant.contains("let initialization = helpHandoffReadiness.beginInitialization()"))
        XCTAssertTrue(assistant.contains("helpHandoffReadiness.finishInitialization(initialization)"))
        XCTAssertTrue(assistant.contains(".onChange(of: resumePrerequisiteToken)"))
        XCTAssertTrue(assistant.contains("consumePendingHelpRequestIfReady()"))
        XCTAssertTrue(assistant.contains("pendingHelpRequestToken"))
        XCTAssertTrue(
            assistant.contains(".onChange(of: pendingHelpRequestToken)"),
            "The mounted assistant must observe a second Help payload after the initial task has already run."
        )
        XCTAssertTrue(
            assistant.contains(".onChange(of: isClearingConversation) { _, isClearing in\n            if !isClearing {\n                consumePendingHelpRequestIfReady()"),
            "A Help handoff queued during Clear must be retried when Clear finishes."
        )
        XCTAssertFalse(mainView.contains("Task.sleep"), "Help presentation must follow dismissal state, not a timer.")
        XCTAssertTrue(assistant.contains("let pendingHelpPersistence = helpPersistenceTask"))
        XCTAssertTrue(assistant.contains("await pendingHelpPersistence?.value"))
        XCTAssertTrue(assistant.contains("try await aiService.clearConversation(cid, ownerUserId: ownerUserId, from: db)"))
        XCTAssertTrue(assistant.contains("aiService.stageHelpConversation("))
        XCTAssertTrue(assistant.contains("ownerUserId: ownerUserId"))
        XCTAssertTrue(assistant.contains("conversationPersistenceError = \"This Help conversation is visible now but could not be saved"))
        XCTAssertFalse(assistant.contains("try? await FoundationModelsService.saveMessages"))
        XCTAssertFalse(assistant.contains("Task.detached { [db, currentConversationId, userPrompt, assistantResponse]"))
    }

    func testImmediateFollowUpWaitsForCompletedHelpStaging() throws {
        let assistant = try Self.readSource("AI/IOSAIAssistantPanel.swift")
        let sendQuery = try TestSourceSlicer.braceBalancedBody(
            after: "private func sendQuery()",
            in: assistant
        )

        XCTAssertTrue(sendQuery.contains("let pendingHelpPersistence = helpPersistenceTask"))
        XCTAssertTrue(sendQuery.contains("let sendConversationId = conversationId"))
        XCTAssertTrue(sendQuery.contains("let sendOwnerUserId = appCore.currentUser?.id"))
        XCTAssertTrue(sendQuery.contains("await pendingHelpPersistence?.value"))
        XCTAssertTrue(sendQuery.contains("conversationId == sendConversationId"))
        XCTAssertTrue(sendQuery.contains("appCore.currentUser?.id == sendOwnerUserId"))
        XCTAssertFalse(
            sendQuery.contains("if let conversationPersistenceError"),
            "A best-effort Help persistence warning must not replace the generated follow-up response."
        )
        guard let waitIndex = sendQuery.range(of: "await pendingHelpPersistence?.value")?.lowerBound,
              let generationIndex = sendQuery.range(of: "let response = await generateResponse")?.lowerBound else {
            XCTFail("sendQuery must contain both the Help-staging wait and response generation.")
            return
        }
        XCTAssertLessThan(waitIndex, generationIndex, "Follow-up generation must be ordered after completed Help staging.")
    }

    func testHelpExclusionCoversGenerationAndBothPersistencePaths() throws {
        let assistant = try Self.readSource("AI/IOSAIAssistantPanel.swift")
        let sendQuery = try TestSourceSlicer.braceBalancedBody(
            after: "private func sendQuery()",
            in: assistant
        )

        guard let beginIndex = sendQuery.range(of: "helpHandoffReadiness.beginSendLifecycle()")?.lowerBound,
              let generationIndex = sendQuery.range(of: "let response = await generateResponse")?.lowerBound,
              let fallbackIndex = sendQuery.range(of: "await persistFallbackTurn(pendingSave)")?.lowerBound,
              let finishIndex = sendQuery.range(of: "helpHandoffReadiness.finishSendLifecycle(sendLifecycleRequestID)")?.lowerBound else {
            XCTFail("sendQuery must serialize Help around generation and persistence.")
            return
        }

        XCTAssertLessThan(beginIndex, generationIndex)
        XCTAssertLessThan(beginIndex, fallbackIndex)
        XCTAssertLessThan(finishIndex, generationIndex, "The finish call must be registered in defer before generation can suspend.")
        XCTAssertTrue(sendQuery.contains("defer {"))
        XCTAssertFalse(sendQuery.contains("beginFallbackPersistence"))
    }

    func testHelpPersistenceErrorCannotBleedAcrossLifecycleChanges() throws {
        let assistant = try Self.readSource("AI/IOSAIAssistantPanel.swift")
        let persist = try TestSourceSlicer.braceBalancedBody(
            after: "private func persistHelpHandoffTurn(userPrompt: String, assistantResponse: String)",
            in: assistant
        )
        let cancel = try TestSourceSlicer.braceBalancedBody(
            after: "private func cancelHelpPersistenceTask() -> Task<Void, Never>?",
            in: assistant
        )

        XCTAssertTrue(persist.contains("let currentConversationId = conversationId"))
        XCTAssertTrue(persist.contains("let currentConversationRevision = conversationRevision"))
        XCTAssertTrue(persist.contains("let currentLifecycle = AIConversationLifecycleSnapshot"))
        XCTAssertTrue(persist.contains("currentLifecycleCoordinator()"))
        XCTAssertEqual(
            persist.components(separatedBy: "lifecycleCoordinator.finishHelpPersistence(").count - 1,
            2,
            "Help persistence must guard both success and failure writes through the production lifecycle coordinator seam."
        )
        XCTAssertFalse(assistant.contains("AIHelpAsyncLifecycleRegressionHarness"))
        XCTAssertTrue(assistant.contains("AIAssistantLifecycleCoordinator"))
        XCTAssertTrue(cancel.contains("pendingHelpPersistence?.cancel()"))
        XCTAssertTrue(cancel.contains("helpPersistenceTask = nil"))

        for lifecycleFunction in [
            "private func startNewConversation()",
            "private func resetForLogout()",
            "private func clearPersistedConversation(_ cid: String)",
            "private func resumeConversation(_ id: String)",
        ] {
            let body = try TestSourceSlicer.braceBalancedBody(after: lifecycleFunction, in: assistant)
            XCTAssertTrue(body.contains("cancelHelpPersistenceTask()"), "\(lifecycleFunction) must cancel and take ownership of stale Help persistence.")
        }

        let resume = try TestSourceSlicer.braceBalancedBody(
            after: "private func resumeConversation(_ id: String)",
            in: assistant
        )
        XCTAssertTrue(resume.contains("conversationPersistenceError = nil"))
    }

    func testConversationPickerLoadingFlagClearsOnStaleListReturn() throws {
        let assistant = try Self.readSource("AI/IOSAIAssistantPanel.swift")
        let list = try TestSourceSlicer.braceBalancedBody(
            after: "private func loadConversationList(requestID: UInt) async",
            in: assistant
        )

        XCTAssertTrue(list.contains("defer {"))
        XCTAssertTrue(list.contains("if conversationListRequestID == requestID"))
        XCTAssertTrue(list.contains("isLoadingConversations = lifecycleCoordinator.isLoadingConversations"))
        XCTAssertTrue(list.contains("conversationListRequestID == requestID"))
        XCTAssertTrue(list.contains("lifecycleCoordinator.finishConversationListLoad"))
        XCTAssertTrue(assistant.contains("@State private var conversationListTask: Task<Void, Never>?"))
    }

    func testClearInvalidatesPendingFollowUpBeforeDeletion() throws {
        let assistant = try Self.readSource("AI/IOSAIAssistantPanel.swift")
        let sendQuery = try TestSourceSlicer.braceBalancedBody(
            after: "private func sendQuery()",
            in: assistant
        )
        let clear = try TestSourceSlicer.braceBalancedBody(
            after: "private func clearPersistedConversation(_ cid: String)",
            in: assistant
        )

        XCTAssertTrue(
            assistant.contains(".disabled(messages.isEmpty || isProcessing || isClearingConversation)"),
            "Clear must not remain user-actionable while a response task is pending."
        )
        XCTAssertTrue(sendQuery.contains("let sendConversationRevision = conversationRevision"))
        XCTAssertEqual(
            sendQuery.components(separatedBy: "conversationRevision == sendConversationRevision").count - 1,
            2,
            "Send must reject an invalidated task before generation and before appending its response."
        )
        guard let invalidateIndex = clear.range(of: "conversationRevision &+= 1")?.lowerBound,
              let waitIndex = clear.range(of: "await pendingHelpPersistence?.value")?.lowerBound,
              let deleteIndex = clear.range(of: "try await aiService.clearConversation")?.lowerBound else {
            XCTFail("Clear must synchronously invalidate pending sends before awaiting Help staging or deletion.")
            return
        }
        XCTAssertLessThan(invalidateIndex, waitIndex)
        XCTAssertLessThan(invalidateIndex, deleteIndex)
    }

    func testConversationLoadsAreCancelledAndGenerationCheckedAcrossLifecycleChanges() throws {
        let assistant = try Self.readSource("AI/IOSAIAssistantPanel.swift")
        let load = try TestSourceSlicer.braceBalancedBody(
            after: "private func loadSavedMessages() async",
            in: assistant
        )
        let latest = try TestSourceSlicer.braceBalancedBody(
            after: "private func resumeLastConversationIfNeeded() async",
            in: assistant
        )
        let list = try TestSourceSlicer.braceBalancedBody(
            after: "private func loadConversationList(requestID: UInt) async",
            in: assistant
        )

        XCTAssertTrue(assistant.contains("@State private var conversationLoadTask: Task<Void, Never>?"))
        XCTAssertTrue(load.contains("let loadConversationId = conversationId"))
        XCTAssertTrue(load.contains("let loadConversationRevision = conversationRevision"))
        XCTAssertTrue(load.contains("!Task.isCancelled"))
        XCTAssertTrue(load.contains("conversationId == loadConversationId"))
        XCTAssertTrue(load.contains("appCore.aiConversationReadOwnerUserId == ownerUserId"))
        XCTAssertEqual(
            load.components(separatedBy: "databaseIdentity.matches(appCore.aiConversationReadDatabase)").count - 1,
            2,
            "Transcript success and failure completions must reject a replaced database."
        )
        XCTAssertTrue(load.contains("conversationRevision == loadConversationRevision"))
        XCTAssertTrue(latest.contains("let lookupConversationRevision = conversationRevision"))
        XCTAssertTrue(latest.contains("conversationRevision == lookupConversationRevision"))
        XCTAssertEqual(
            latest.components(separatedBy: "databaseIdentity.matches(appCore.aiConversationReadDatabase)").count - 1,
            2,
            "Latest-conversation success and failure completions must reject a replaced database."
        )
        XCTAssertTrue(latest.contains("conversationRevision &+= 1"))
        XCTAssertTrue(list.contains("let listLifecycle = lifecycleCoordinator.beginConversationListLoad(requestID: requestID)"))
        XCTAssertTrue(list.contains("lifecycleCoordinator.finishConversationListLoad("))
        XCTAssertTrue(list.contains("requestID: requestID"))
        XCTAssertEqual(
            list.components(separatedBy: "databaseIdentity.matches(appCore.aiConversationReadDatabase)").count - 1,
            3,
            "Resume-list success, failure, and loading cleanup must reject a replaced database."
        )
        XCTAssertTrue(assistant.contains("savedConversations.removeAll()"))

        let scopeReset = try TestSourceSlicer.braceBalancedBody(
            after: "private func resetConversationReadScopeIfNeeded(for prerequisites: ResumePrerequisiteToken)",
            in: assistant
        )
        XCTAssertTrue(scopeReset.contains("conversationLoadTask?.cancel()"))
        XCTAssertTrue(scopeReset.contains("cancelConversationListLoad()"))
        XCTAssertTrue(scopeReset.contains("cancelConversationHistoryRetryTask()"))

        for lifecycleFunction in [
            "private func startNewConversation()",
            "private func resetForLogout()",
            "private func clearPersistedConversation(_ cid: String)",
            "private func resumeConversation(_ id: String)",
        ] {
            let body = try TestSourceSlicer.braceBalancedBody(after: lifecycleFunction, in: assistant)
            XCTAssertTrue(body.contains("conversationLoadTask?.cancel()"), "\(lifecycleFunction) must cancel stale history hydration.")
            XCTAssertTrue(body.contains("cancelConversationHistoryRetryTask()"), "\(lifecycleFunction) must cancel stale manual Retry work.")
        }
    }

    func testComposerWaitsForConversationHydrationBeforeSending() throws {
        let assistant = try Self.readSource("AI/IOSAIAssistantPanel.swift")
        let editor = try TestSourceSlicer.braceBalancedBody(
            after: "private var chatTextEditor: some View",
            in: assistant
        )
        let inputBar = try TestSourceSlicer.braceBalancedBody(
            after: "private var inputBar: some View",
            in: assistant
        )
        let initializationTask = try TestSourceSlicer.braceBalancedBody(
            after: ".task(id: resumePrerequisiteToken)",
            in: assistant
        )
        let sendQuery = try TestSourceSlicer.braceBalancedBody(
            after: "private func sendQuery()",
            in: assistant
        )
        let beginLoad = try TestSourceSlicer.braceBalancedBody(
            after: "private func beginCurrentConversationLoad()",
            in: assistant
        )
        let resume = try TestSourceSlicer.braceBalancedBody(
            after: "private func resumeConversation(_ id: String)",
            in: assistant
        )

        XCTAssertTrue(assistant.contains("@State private var isLoadingConversationHistory = false"))
        XCTAssertTrue(initializationTask.contains("let initialization = helpHandoffReadiness.beginInitialization()"))
        XCTAssertTrue(initializationTask.contains("isLoadingConversationHistory = true"))
        XCTAssertTrue(sendQuery.contains("!isLoadingConversationHistory"))
        XCTAssertGreaterThanOrEqual(
            assistant.components(separatedBy: "|| isLoadingConversationHistory").count - 1,
            2,
            "Both the editor and Send control must stay disabled while persisted history hydrates."
        )
        XCTAssertTrue(
            assistant.contains("|| conversationHistoryReadError != nil"),
            "The editor must stay disabled while persisted history hydrates."
        )
        XCTAssertTrue(
            assistant.contains("|| isLoadingConversationHistory\n                    || conversationHistoryReadError != nil"),
            "The Send control must stay disabled while persisted history hydrates."
        )
        XCTAssertTrue(editor.contains("isLoadingConversationHistory"))
        XCTAssertTrue(editor.contains("conversationHistoryReadError != nil"))
        XCTAssertTrue(inputBar.contains("isLoadingConversationHistory"))
        XCTAssertTrue(inputBar.contains("conversationHistoryReadError != nil"))
        XCTAssertTrue(beginLoad.contains("isLoadingConversationHistory = true"))
        XCTAssertTrue(beginLoad.contains("guard let loadOwnerUserId = appCore.aiConversationReadOwnerUserId"))
        XCTAssertTrue(beginLoad.contains("loadOwnerUserId > 0"))
        XCTAssertTrue(beginLoad.contains("let loadDatabase = appCore.aiConversationReadDatabase"))
        XCTAssertTrue(beginLoad.contains("return Task {}"))
        XCTAssertTrue(beginLoad.contains("await loadSavedMessages()"))
        XCTAssertTrue(beginLoad.contains("loadDatabaseIdentity.matches(appCore.aiConversationReadDatabase)"))
        XCTAssertTrue(beginLoad.contains("conversationRevision == loadConversationRevision"))
        XCTAssertTrue(beginLoad.contains("isLoadingConversationHistory = false"))
        XCTAssertTrue(resume.contains("beginCurrentConversationLoad()"))

        guard let prerequisiteGuard = beginLoad.range(of: "guard let loadOwnerUserId")?.lowerBound,
              let loadTask = beginLoad.range(of: "let task = Task")?.lowerBound,
              let clearLoading = beginLoad.range(of: "isLoadingConversationHistory = false")?.lowerBound else {
            XCTFail("History loading must validate positive owner/database prerequisites before starting or completing a load.")
            return
        }
        XCTAssertLessThan(prerequisiteGuard, loadTask)
        XCTAssertLessThan(loadTask, clearLoading)
    }

    func testAssistantMessagesAndHistoryPreviewsRenderMarkdown() throws {
        let assistant = try Self.readSource("AI/IOSAIAssistantPanel.swift")

        XCTAssertTrue(assistant.contains("Text(renderedMarkdown(message.content))"))
        XCTAssertTrue(assistant.contains("Text(renderedMarkdown(conversation.preview))"))
        XCTAssertTrue(assistant.contains("markdown: normalized"))
        XCTAssertTrue(assistant.contains("interpretedSyntax: .full"))
        XCTAssertTrue(assistant.contains("run.presentationIntent?.components.first?.identity"))
        XCTAssertFalse(assistant.contains("markdownBlocks(content)"))
    }

    func testMarkdownRendererPreservesFencedCodeAndParagraphSpacing() {
        let markdown = """
        Before code.

        ```swift
        let first = 1

        let second = 2
        ```

        After code.
        """

        let rendered = AIAssistantMarkdownRenderer.plainText(fromMarkdown: markdown)

        XCTAssertEqual(
            rendered,
            "Before code.\n\nlet first = 1\n\nlet second = 2\n\nAfter code."
        )
        XCTAssertFalse(rendered.contains("```"))
    }

    func testMarkdownRendererPreservesBlankLineListAndIndentedCodeContent() {
        let markdown = """
        - First item

              let first = 1

              let second = 2

        - Second item
        """

        let rendered = AIAssistantMarkdownRenderer.plainText(fromMarkdown: markdown)

        XCTAssertEqual(
            rendered,
            "First item\n\nlet first = 1\n\nlet second = 2\n\nSecond item"
        )
        XCTAssertFalse(rendered.contains("- "))
    }

    func testExistingAssistantBugReportContextRemainsAvailable() throws {
        let assistant = try Self.readSource("AI/IOSAIAssistantPanel.swift")

        XCTAssertTrue(assistant.contains("isBugReportPresented"))
        XCTAssertTrue(assistant.contains("ReportABugPage(originModule: activeModuleName)"))
        XCTAssertTrue(assistant.contains("HelpContentRegistry.helpFor(pageId)"))
        XCTAssertTrue(assistant.contains("accessibilityLabel(\"Report a bug\")"))
    }

    private static func readSource(_ relativePath: String, file: StaticString = #filePath) throws -> String {
        let testFileURL = URL(fileURLWithPath: "\(file)")
        let projectRoot = testFileURL
            .deletingLastPathComponent() // Weird Parts IOSTests
            .deletingLastPathComponent() // Weird Parts IOS
        let sourceURL = projectRoot
            .appendingPathComponent("Weird Parts IOS")
            .appendingPathComponent(relativePath)
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }
}
