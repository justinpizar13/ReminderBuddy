import SwiftUI

/// A shared reference tab for the household's important month-to-month information:
/// utilities (internet, gas, water, etc.), each with a dashboard link, account number,
/// and monthly price. This is reference data — there's nothing to complete here.
struct SharedInfoView: View {
    @EnvironmentObject private var store: TaskStore
    @State private var showingAdd = false

    var body: some View {
        NavigationStack {
            Group {
                if store.isLoading && store.infoItems.isEmpty {
                    ProgressView("Syncing…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if store.infoItems.isEmpty {
                    emptyState
                } else {
                    infoList
                }
            }
            .navigationTitle("Info")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingAdd = true } label: { Image(systemName: "plus") }
                }
            }
            .refreshable { await store.refresh(announceChanges: false) }
            .sheet(isPresented: $showingAdd) {
                SharedInfoEditorView(mode: .create)
            }
            .overlay(alignment: .bottom) {
                if let error = store.errorMessage {
                    ErrorBanner(message: error) { store.errorMessage = nil }
                }
            }
        }
    }

    private var infoList: some View {
        List {
            Section {
                ForEach(store.infoItems) { item in
                    NavigationLink(value: item) {
                        SharedInfoRow(item: item)
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            Task { await store.deleteInfoItem(item) }
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            } footer: {
                let total = store.monthlyInfoTotal()
                if total > 0 {
                    Text("Estimated monthly total: \(total.formattedAsCurrency())")
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationDestination(for: SharedInfoItem.self) { item in
            if let live = store.infoItems.first(where: { $0.id == item.id }) {
                SharedInfoDetailView(item: live)
            } else {
                SharedInfoDetailView(item: item)
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Info Yet", systemImage: "info.circle")
        } description: {
            Text("Keep the important stuff in one place — utilities, account numbers, dashboard links, and what you pay each month.")
        } actions: {
            Button("Add Info") { showingAdd = true }
                .buttonStyle(.borderedProminent)
        }
    }
}

// MARK: - Row

struct SharedInfoRow: View {
    let item: SharedInfoItem

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.title)
                .font(.body)

            HStack(spacing: 8) {
                if !item.accountNumber.isEmpty {
                    Label(item.accountNumber, systemImage: "number")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if item.url != nil {
                    Label("Link", systemImage: "link")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            if let price = item.monthlyPrice {
                Text("\(price.formattedAsCurrency()) / mo")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Detail

struct SharedInfoDetailView: View {
    @EnvironmentObject private var store: TaskStore
    let item: SharedInfoItem

    @State private var showingEdit = false

    var body: some View {
        List {
            Section {
                Text(item.title)
                    .font(.title3.weight(.semibold))
                if !item.detail.isEmpty {
                    Text(item.detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Details") {
                if let url = item.url {
                    Link(destination: url) {
                        LabeledContent("Dashboard") {
                            Label("Open", systemImage: "arrow.up.right.square")
                        }
                    }
                }
                if !item.accountNumber.isEmpty {
                    LabeledContent("Account #") {
                        Text(item.accountNumber)
                            .textSelection(.enabled)
                    }
                }
                if let price = item.monthlyPrice {
                    LabeledContent("Per month", value: price.formattedAsCurrency())
                }
                LabeledContent("Added by", value: item.createdByName.isEmpty ? "—" : item.createdByName)
            }
        }
        .navigationTitle("Info")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Edit") { showingEdit = true }
            }
        }
        .sheet(isPresented: $showingEdit) {
            SharedInfoEditorView(mode: .edit(item))
        }
    }
}

// MARK: - Editor

struct SharedInfoEditorView: View {
    enum Mode {
        case create
        case edit(SharedInfoItem)
    }

    @EnvironmentObject private var store: TaskStore
    @Environment(\.dismiss) private var dismiss

    let mode: Mode

    @State private var title = ""
    @State private var detail = ""
    @State private var link = ""
    @State private var accountNumber = ""
    @State private var priceText = ""

    private var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name (e.g. Internet — Xfinity)", text: $title, axis: .vertical)
                    TextField("Notes (optional)", text: $detail, axis: .vertical)
                        .lineLimit(1...5)
                }

                Section("Account") {
                    TextField("Dashboard link", text: $link)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    TextField("Account number", text: $accountNumber)
                        .autocorrectionDisabled()
                }

                Section {
                    HStack {
                        Text("Per month")
                        Spacer()
                        TextField("0.00", text: $priceText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 120)
                    }
                } header: {
                    Text("Cost")
                } footer: {
                    Text("Leave blank if there's no fixed monthly cost.")
                }
            }
            .navigationTitle(isEditing ? "Edit Info" : "New Info")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(!canSave)
                }
            }
            .onAppear(perform: populate)
        }
    }

    private func populate() {
        guard case .edit(let item) = mode else { return }
        title = item.title
        detail = item.detail
        link = item.link
        accountNumber = item.accountNumber
        if let price = item.monthlyPrice {
            priceText = String(format: "%.2f", price)
        }
    }

    private func save() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDetail = detail.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedLink = link.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedAccount = accountNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        let price = SharedInfoEditorView.parsePrice(priceText)

        Task {
            switch mode {
            case .create:
                await store.addInfoItem(title: trimmedTitle,
                                        detail: trimmedDetail,
                                        link: trimmedLink,
                                        accountNumber: trimmedAccount,
                                        monthlyPrice: price)
            case .edit(let original):
                var updated = original
                updated.title = trimmedTitle
                updated.detail = trimmedDetail
                updated.link = trimmedLink
                updated.accountNumber = trimmedAccount
                updated.monthlyPrice = price
                await store.updateInfoItem(updated)
            }
            dismiss()
        }
    }

    /// Parses a user-entered price, tolerating currency symbols and grouping separators.
    /// Returns nil when the field is empty or unparseable.
    private static func parsePrice(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let allowed = CharacterSet(charactersIn: "0123456789.,")
        let filtered = String(trimmed.unicodeScalars.filter { allowed.contains($0) })
            .replacingOccurrences(of: ",", with: "")
        guard let value = Double(filtered), value >= 0 else { return nil }
        return value
    }
}

// MARK: - Currency formatting

extension Double {
    /// Formats the value as localized currency (e.g. "$45.00").
    func formattedAsCurrency() -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = .current
        return formatter.string(from: NSNumber(value: self)) ?? String(format: "%.2f", self)
    }
}
