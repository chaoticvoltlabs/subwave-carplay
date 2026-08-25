//
//  AddStationView.swift
//  subwave-carplay
//

import SwiftUI

struct AddStationView: View {
    @Bindable var store: StationStore
    /// nil adds a new station; non-nil edits that station in place.
    var editingStation: Station?
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var address: String
    @State private var validationError: String?

    init(store: StationStore, editingStation: Station? = nil) {
        self.store = store
        self.editingStation = editingStation
        _name = State(initialValue: editingStation?.name ?? "")
        _address = State(initialValue: editingStation?.address ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("My Station", text: $name)
                }
                Section("Address") {
                    TextField("radio.example.com", text: $address)
                        .autocorrectionDisabled()
                    Text("For a private station, include the shared password: dj:secret@radio.example.com")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let validationError {
                    Text(validationError)
                        .foregroundStyle(.red)
                }
            }
            .navigationTitle(editingStation == nil ? "Add Station" : "Edit Station")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || address.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func save() {
        guard ResolvedAddress(typedAddress: address) != nil else {
            validationError = "That doesn't look like a valid address."
            return
        }
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let trimmedAddress = address.trimmingCharacters(in: .whitespaces)
        if let editingStation {
            store.updateStation(editingStation, name: trimmedName, address: trimmedAddress)
        } else {
            store.addStation(name: trimmedName, address: trimmedAddress)
        }
        dismiss()
    }
}
