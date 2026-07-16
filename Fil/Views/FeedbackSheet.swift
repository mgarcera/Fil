import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// A calm feedback form: optional sentiment + a message (+ an optional email for a reply). Posted to
/// Formspree, which emails it to Mason — no account, no backend, no keys. Auto-attaches app/device
/// context. Presented from Settings → About and from the smart-search failure note.
struct FeedbackSheet: View {
    /// Optional context appended to the submission (e.g. the query smart search couldn't answer).
    var context: String? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var message = ""
    @State private var email = ""
    @State private var sentiment: String?
    @State private var isSending = false
    @State private var outcome: Outcome?
    @FocusState private var messageFocused: Bool

    private enum Outcome { case sent, failed }
    private let sentiments = ["😍", "☺️", "😡", "😒", "😭", "🐛"]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("How's it going?")
                        .font(Theme.dmSans(15))
                        .foregroundStyle(Theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 14) {
                        ForEach(sentiments, id: \.self) { emoji in
                            Button {
                                sentiment = (sentiment == emoji) ? nil : emoji
                            } label: {
                                Text(emoji)
                                    .font(.system(size: 28))
                                    .opacity(sentiment == nil || sentiment == emoji ? 1 : 0.3)
                                    .scaleEffect(sentiment == emoji ? 1.15 : 1)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .animation(.snappy(duration: 0.2), value: sentiment)

                    ZStack(alignment: .topLeading) {
                        if message.isEmpty {
                            Text("Your thoughts")
                                .font(Theme.dmSans(16))
                                .foregroundStyle(Theme.tertiaryText)
                                .padding(.top, 8)
                                .padding(.leading, 5)
                                .allowsHitTesting(false)
                        }
                        TextEditor(text: $message)
                            .font(Theme.dmSans(16))
                            .foregroundStyle(Theme.primaryText)
                            .scrollContentBackground(.hidden)
                            .frame(minHeight: 140)
                            .focused($messageFocused)
                    }
                    .padding(12)
                    .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                    TextField("Your email (optional, for a reply)", text: $email)
                        .font(Theme.dmSans(15))
                        .foregroundStyle(Theme.primaryText)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                        .autocorrectionDisabled()
                        .padding(14)
                        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                    Button {
                        Task { await send() }
                    } label: {
                        Text(isSending ? "Sending…" : "Send")
                            .font(Theme.dmSans(16, weight: .semibold))
                            .foregroundStyle(Theme.background)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(Theme.primaryText, in: Capsule())
                            .opacity(canSend ? 1 : 0.5)
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSend || isSending)
                }
                .padding(20)
            }
            .scrollIndicators(.hidden)
            .navigationTitle("Feedback")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
        }
        .presentationDetents([.large])
        .presentationBackground(Theme.background)
        .onAppear { messageFocused = true }
        .alert("Thank you!", isPresented: alertBinding(.sent)) {
            Button("OK") { dismiss() }
        } message: {
            Text("Your feedback has been sent!")
        }
        .alert("Couldn't send", isPresented: alertBinding(.failed)) {
            Button("OK") {}
        } message: {
            Text("Something went wrong. Please try again, or email mason@rootcause.ltd.")
        }
    }

    private var canSend: Bool {
        !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func alertBinding(_ target: Outcome) -> Binding<Bool> {
        Binding(get: { outcome == target }, set: { if !$0 { outcome = nil } })
    }

    private func send() async {
        isSending = true
        do {
            try await FeedbackService.submit(message: message, email: email, sentiment: sentiment, context: context)
            outcome = .sent
        } catch {
            outcome = .failed
        }
        isSending = false
    }
}

/// Posts feedback to Formspree (form-to-email; no account or key needed).
enum FeedbackService {
    /// Fil's Formspree form (form-to-email; no key needed). Manage at formspree.io.
    private static let endpoint = URL(string: "https://formspree.io/f/meeyqyrj")!

    enum FeedbackError: Error { case server }

    static func submit(message: String, email: String, sentiment: String?, context: String?) async throws {
        var payload: [String: String] = [
            "message": message.trimmingCharacters(in: .whitespacesAndNewlines),
            "sentiment": sentiment ?? "",
            "context": context ?? "",
            "appVersion": appVersion,
            "device": deviceModel,
            "iOS": systemVersion,
            "timestamp": ISO8601DateFormatter().string(from: Date()),
        ]
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedEmail.isEmpty { payload["email"] = trimmedEmail }   // Formspree uses this as reply-to

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw FeedbackError.server
        }
    }

    private static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    }
    private static var deviceModel: String {
        #if canImport(UIKit)
        UIDevice.current.model
        #else
        "unknown"
        #endif
    }
    private static var systemVersion: String {
        #if canImport(UIKit)
        UIDevice.current.systemVersion
        #else
        "unknown"
        #endif
    }
}
