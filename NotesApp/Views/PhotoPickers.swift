import PhotosUI
import SwiftUI
import UIKit

/// Камеры нет на симуляторе — тогда пункта «Сфотографировать» нет.
enum PhotoSource {
    static var hasCamera: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
    }
}

/// Пункты меню «Добавить фото»: из галереи и с камеры.
struct PhotoAddButtons: View {
    @Binding var showLibrary: Bool
    @Binding var showCamera: Bool

    var body: some View {
        Button {
            showLibrary = true
        } label: {
            Label("Из галереи", systemImage: "photo.on.rectangle")
        }
        if PhotoSource.hasCamera {
            Button {
                showCamera = true
            } label: {
                Label("Сфотографировать", systemImage: "camera")
            }
        }
    }
}

extension View {
    /// Галерея (можно несколько, но не больше limit; разрешение на галерею не нужно) и камера.
    /// Готовые фото — уменьшенные, с миниатюрами — приходят в onAdd.
    func photoPickers(library: Binding<Bool>, camera: Binding<Bool>, limit: Int,
                      onAdd: @escaping ([PreparedPhoto]) -> Void) -> some View {
        modifier(PhotoPickers(showLibrary: library, showCamera: camera, limit: limit, onAdd: onAdd))
    }
}

private struct PhotoPickers: ViewModifier {
    @Binding var showLibrary: Bool
    @Binding var showCamera: Bool
    let limit: Int
    let onAdd: ([PreparedPhoto]) -> Void

    @State private var picked: [PhotosPickerItem] = []

    func body(content: Content) -> some View {
        content
            .photosPicker(isPresented: $showLibrary, selection: $picked, maxSelectionCount: max(1, limit),
                          matching: .images)
            .onChange(of: picked) { _, items in
                guard !items.isEmpty else { return }
                picked = []
                Task { await load(items) }
            }
            .fullScreenCover(isPresented: $showCamera) {
                CameraPicker { image in
                    Task {
                        let photo = await Task.detached { PhotoStore.prepare(image: image) }.value
                        if let photo {
                            onAdd([photo])
                        }
                    }
                }
                .ignoresSafeArea()
            }
    }

    /// Фото из галереи — по одному, уменьшаем не на главном потоке.
    private func load(_ items: [PhotosPickerItem]) async {
        var result: [PreparedPhoto] = []
        for item in items.prefix(max(0, limit)) {
            guard let data = try? await item.loadTransferable(type: Data.self) else { continue }
            if let photo = await Task.detached(operation: { PhotoStore.prepare(data: data) }).value {
                result.append(photo)
            }
        }
        if !result.isEmpty {
            onAdd(result)
        }
    }
}

/// Системная камера. Снимок — в onImage, закрывается сама.
struct CameraPicker: UIViewControllerRepresentable {
    let onImage: (UIImage) -> Void

    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        private let parent: CameraPicker

        init(_ parent: CameraPicker) {
            self.parent = parent
        }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.onImage(image)
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

/// Миниатюра из данных JPEG, квадратная, с обрезкой.
struct PhotoThumb: View {
    let data: Data
    var size: CGFloat = 64
    var corner: CGFloat = 10

    var body: some View {
        Group {
            if let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Color(.tertiarySystemFill)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
    }
}
