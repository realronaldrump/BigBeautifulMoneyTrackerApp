import PDFKit
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct PayStatementImportButton: View {
    let onImport: (PayStatement) -> Void
    @State private var choosingFile = false
    @State private var reading = false
    @State private var errorMessage: String?

    var body: some View {
        Button {
            choosingFile = true
        } label: {
            Label(reading ? "Reading paycheck…" : "Import paycheck PDF", systemImage: "doc.badge.plus")
        }
        .disabled(reading)
        .fileImporter(isPresented: $choosingFile, allowedContentTypes: [.pdf]) { result in
            switch result {
            case .success(let url):
                reading = true
                Task {
                    let statement = await Task.detached(priority: .userInitiated) {
                        let access = url.startAccessingSecurityScopedResource()
                        defer { if access { url.stopAccessingSecurityScopedResource() } }
                        guard let text = PDFDocument(url: url)?.string else { return nil as PayStatement? }
                        return PayStatement(text: text)
                    }.value
                    reading = false
                    if let statement { onImport(statement) }
                    else { errorMessage = "The pay summary could not be read. You can enter the amounts by hand." }
                }
            case .failure(let error):
                if (error as NSError).code != NSUserCancelledError { errorMessage = error.localizedDescription }
            }
        }
        .alert("Paycheck import", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK") { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
    }
}

struct PaycheckSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    let job: JobProfile
    @State private var grossText: String
    @State private var netText: String
    @State private var statement: PayStatement?
    @State private var usePayDetails = true
    @State private var errorText: String?

    init(job: JobProfile) {
        self.job = job
        _grossText = State(initialValue: job.paycheckReference.map { LocalizedNumericInput.decimalText(for: $0.gross) } ?? "")
        _netText = State(initialValue: job.paycheckReference.map { LocalizedNumericInput.decimalText(for: $0.net) } ?? "")
    }

    private var reference: PaycheckReference? {
        PaycheckReference(gross: LocalizedNumericInput.decimalValue(from: grossText),
                          net: LocalizedNumericInput.decimalValue(from: netText))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                TimecardHeading(title: job.displayName)
                PayStatementImportButton { imported in
                    statement = imported
                    grossText = LocalizedNumericInput.decimalText(for: imported.paycheck.gross)
                    netText = LocalizedNumericInput.decimalText(for: imported.paycheck.net)
                    usePayDetails = true
                    errorText = nil
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                Text("Choose a PDF or enter both totals from one check. The PDF stays on your device.")
                    .font(TypeStyle.callout).foregroundStyle(.secondary)
                VStack(spacing: 0) {
                    amountField("Gross pay", text: $grossText, identifier: "paycheck.gross")
                    Divider()
                    amountField("Take-home pay", text: $netText, identifier: "paycheck.net")
                }
                .padding(.horizontal, 16).ruledSection()
                if let reference {
                    PayReadout(title: "Take-home per $100 earned", amount: reference.netRate * 100, mode: .takeHome) {
                        Text("Future estimates assume similar earnings and deductions.")
                    }
                } else if !grossText.isEmpty && !netText.isEmpty {
                    AppInlineNotice(message: "Enter a positive gross amount and take-home pay between zero and gross pay.")
                }
                if let statement, let start = statement.periodStart, let frequency = statement.frequency,
                   let rate = statement.hourlyRate, job.compensationKind == .hourly {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle("Use pay details from this check", isOn: $usePayDetails)
                        if usePayDetails {
                            Divider()
                            LabeledContent("Hourly rate", value: rate.formatted(.currency(code: "USD")))
                            LabeledContent("Pay cycle", value: frequency.title)
                            LabeledContent("Period began", value: start.formatted(date: .abbreviated, time: .omitted))
                            if let paid = statement.paidDate {
                                LabeledContent("Pay date", value: paid.formatted(date: .abbreviated, time: .omitted))
                            }
                            Text("Applies the rate from this period’s start. Later dated rates still apply.")
                                .font(TypeStyle.caption).foregroundStyle(.secondary)
                        }
                    }.padding(16).ruledSection()
                }
                if let errorText { AppInlineNotice(message: errorText) }
                if job.paycheckReference != nil {
                    Button("Use automatic estimate") { save(nil) }.frame(minHeight: 44)
                        .accessibilityHint("Return to the saved federal and Colorado estimate for this job")
                }
            }
            .padding(20)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Button("Save paycheck settings") { save(reference) }
                .buttonStyle(AppActionButtonStyle())
                .disabled(reference == nil)
                .padding(.horizontal, 20).padding(.vertical, 8)
                .background(TimecardColor.stock)
        }
        .tint(TimecardColor.blueInk)
        .background(MoneyBackground())
        .navigationTitle("Take-home pay")
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
    }

    private func amountField(_ title: String, text: Binding<String>, identifier: String) -> some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
            : AnyLayout(HStackLayout(spacing: 12))
        return layout {
            Text(title).fixedSize(horizontal: false, vertical: true).accessibilityHidden(true)
            TextField("$0.00", text: text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(typeSize.isAccessibilitySize ? .leading : .trailing)
                .accessibilityLabel(title)
                .accessibilityIdentifier(identifier)
        }
        .padding(.vertical, 10).frame(minHeight: 52)
    }

    private func save(_ reference: PaycheckReference?) {
        do {
            try JobService.savePaycheckReference(reference, for: job,
                                                 hourlyDetails: usePayDetails ? statement : nil, in: modelContext)
            dismiss()
        } catch { errorText = error.localizedDescription }
    }
}
