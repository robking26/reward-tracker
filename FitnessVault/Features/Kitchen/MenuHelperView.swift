import PhotosUI
import SwiftUI

/// Eating out: picks from a photographed or pasted menu (SO1). Estimates, never a lecture.
struct MenuHelperView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var photo: PhotosPickerItem?
    @State private var scanning = false
    @State private var reading = false
    @State private var picks: [MenuPick]?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if DocumentScanner.isAvailable {
                        Button("Scan the menu", systemImage: "camera") { scanning = true }
                    }
                    PhotosPicker(selection: $photo, matching: .images) {
                        Label("Photo or screenshot of the menu", systemImage: "photo")
                    }
                    TextEditor(text: $text).frame(minHeight: 120)
                    Button("Suggest something") { picks = MenuAdvisor.picks(from: text) }
                        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                } footer: {
                    Text("Read on your iPhone. Nothing is uploaded.")
                }
                if reading { Section { HStack { ProgressView(); Text("Reading…") } } }
                if let picks {
                    Section {
                        if picks.isEmpty {
                            Text("Nothing obvious stood out. Have what you fancy; one meal doesn't change anything.")
                        }
                        ForEach(picks, id: \.dish) { pick in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(pick.dish).font(.headline)
                                Text(pick.reason).font(.caption).foregroundStyle(Palette.textSecondary)
                            }
                        }
                    } header: {
                        Text("Good options")
                    } footer: {
                        Text(MenuAdvisor.footnote)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .pageBackground()
            .navigationTitle("Eating out")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .fullScreenCover(isPresented: $scanning) {
            DocumentScanner { images in
                scanning = false
                read { await TextRecognition.text(in: images) }
            } onCancel: {
                scanning = false
            }
            .ignoresSafeArea()
        }
        .onChange(of: photo) { _, item in
            guard let item else { return }
            read {
                guard let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else { return "" }
                return await TextRecognition.text(in: image)
            }
        }
    }

    private func read(_ work: @escaping () async -> String) {
        reading = true
        Task {
            let result = await work()
            reading = false
            text = result
            picks = MenuAdvisor.picks(from: result)
        }
    }
}
