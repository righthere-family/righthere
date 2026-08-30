import PhotosUI
import SwiftUI

// MARK: - Postcard

struct PostcardView: View {
    let parent: Parent
    @Environment(\.dismiss) private var dismiss
    @State private var model = PostcardViewModel()
    @FocusState private var isWriting: Bool
    @State private var pickedPhoto: PhotosPickerItem?
    @State private var isShowingPaywall = false
    private let purchases = PurchaseModel.shared

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                editor
                photoRow
                    .padding(.top, 12)
                Text(L10n.postcardHint)
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.inkSecondary)
                    .lineSpacing(3)
                    .padding(.top, 14)
                Spacer()
                sendButton
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 20)
            .background(Palette.background)
            .navigationTitle(L10n.postcardTitle(kind: parent.kind))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.postcardCancel) { dismiss() }
                        .foregroundStyle(Palette.accent)
                }
            }
            .onAppear {
                isWriting = true
                Task { await purchases.load() }
            }
            .sheet(isPresented: $isShowingPaywall) { PaywallSheet() }
            .onChange(of: pickedPhoto) { _, item in
                guard let item else { return }
                Task { await model.attach(item) }
            }
            .onChange(of: model.isSent) { _, sent in
                if sent { dismiss() }
            }
        }
    }

    // MARK: - Editor

    private var editor: some View {
        VStack(alignment: .leading, spacing: 0) {
            TextEditor(text: Bindable(model).body)
                .focused($isWriting)
                .font(Typography.quote)
                .foregroundStyle(Palette.ink)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 120, maxHeight: 190)
                .overlay(alignment: .topLeading) {
                    if model.body.isEmpty {
                        Text(L10n.postcardPlaceholder(kind: parent.kind))
                            .font(Typography.quote)
                            .foregroundStyle(Palette.inkSecondary.opacity(0.5))
                            .padding(.top, 8)
                            .padding(.leading, 5)
                            .allowsHitTesting(false)
                    }
                }

            if model.didFail {
                Text(L10n.postcardFailed)
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.alert)
                    .padding(.top, 6)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Palette.card, in: .rect(cornerRadius: 20))
        .shadow(color: Palette.ink.opacity(0.04), radius: 10, y: 4)
    }

    // MARK: - Photo

    @ViewBuilder
    private var photoRow: some View {
        if let image = model.attachedImage {
            HStack(spacing: 10) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 54, height: 54)
                    .clipShape(.rect(cornerRadius: 10))
                Button {
                    model.removePhoto()
                    pickedPhoto = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(Palette.inkSecondary.opacity(0.6))
                }
                .buttonStyle(.plain)
                Spacer()
            }
        } else {
            // Photos are free: the postcard is a retention ritual, not premium
            // merchandise — a direct Telegram message replaces the channel, so
            // nobody would pay for it, but nothing replaces the moment.
            PhotosPicker(selection: $pickedPhoto, matching: .images) {
                Label(L10n.postcardAddPhoto, systemImage: "photo")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Palette.accent)
            }
        }
    }

    // MARK: - Send

    private var sendButton: some View {
        FormPrimaryButton(
            title: L10n.postcardSend,
            isEnabled: model.canSend,
            isBusy: model.isSending
        ) {
            Task { await model.send(to: parent.id) }
        }
    }
}

// MARK: - View Model

@Observable
@MainActor
final class PostcardViewModel {
    var body = ""
    private(set) var isSending = false
    private(set) var isSent = false
    private(set) var didFail = false
    private(set) var attachedImage: UIImage?
    private var attachedData: Data?

    static let limit = 500

    var canSend: Bool {
        (!body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || attachedData != nil)
            && body.count <= Self.limit
            && !isSending
    }

    func attach(_ item: PhotosPickerItem) async {
        guard let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else { return }
        // Telegram photos cap around 10MB; 1600pt at 0.75 stays far below and
        // looks fine on any phone.
        let resized = image.resized(maxDimension: 1600)
        attachedImage = resized
        attachedData = resized.jpegData(compressionQuality: 0.75)
    }

    func removePhoto() {
        attachedImage = nil
        attachedData = nil
    }

    func send(to parentId: UUID) async {
        guard canSend else { return }
        isSending = true
        didFail = false
        defer { isSending = false }
        let text = body.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            var photoPath: String?
            if let attachedData {
                photoPath = try await FamilyAPI().uploadPostcardPhoto(attachedData)
            }
            guard try await FamilyAPI().sendPostcard(parentId: parentId, body: text, photoPath: photoPath) else {
                didFail = true
                return
            }
            isSent = true
        } catch {
            #if DEBUG
            NSLog("postcard send failed: %@", String(describing: error))
            #endif
            didFail = true
        }
    }
}

// MARK: - Resize

private extension UIImage {
    func resized(maxDimension: CGFloat) -> UIImage {
        let largest = max(size.width, size.height)
        guard largest > maxDimension else { return self }
        let scale = maxDimension / largest
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        // Pixels, not points: the default screen scale would triple the size.
        format.scale = 1
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: target))
        }
    }
}

#Preview {
    PostcardView(parent: .sample)
}
