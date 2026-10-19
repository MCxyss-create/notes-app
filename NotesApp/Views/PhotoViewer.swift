import SwiftData
import SwiftUI
import UIKit

/// Открыть просмотр с фото номер index.
struct PhotoViewerRequest: Identifiable {
    let id = UUID()
    let index: Int
}

/// Фото записи на весь экран: листать свайпом, увеличивать щипком и двойным тапом,
/// «Поделиться», «Удалить» (с вопросом), закрыть свайпом вниз или крестиком.
struct PhotoViewer: View {
    let itemID: UUID

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query private var photos: [PhotoAttachment]
    @State private var index: Int
    @State private var zoomed = false
    @State private var pull: CGFloat = 0
    @State private var confirmDelete = false

    init(itemID: UUID, startIndex: Int = 0) {
        self.itemID = itemID
        _index = State(initialValue: startIndex)
        _photos = Query(filter: #Predicate<PhotoAttachment> { $0.itemID == itemID }, sort: \.sortIndex)
    }

    private var current: PhotoAttachment? {
        photos.indices.contains(index) ? photos[index] : nil
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color.black
                .opacity(1 - min(pull / 500, 0.6))
                .ignoresSafeArea()

            TabView(selection: $index) {
                ForEach(Array(photos.enumerated()), id: \.element.uid) { offset, photo in
                    ZoomableImage(data: photo.imageData, zoomed: $zoomed,
                                  onPull: { pull = $0 }, onRelease: release)
                        .tag(offset)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea()
            .offset(y: pull)

            if pull == 0, let current {
                ViewerBar(photo: current, position: index + 1, total: photos.count,
                          onClose: { dismiss() }, onDelete: { confirmDelete = true })
            }
        }
        .statusBarHidden()
        .environment(\.colorScheme, .dark)
        .confirmationDialog("Удалить фото?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Удалить", role: .destructive) {
                if let current {
                    PhotoStore.delete(current, context: context)
                }
            }
            Button("Отмена", role: .cancel) {}
        }
        .onChange(of: photos.count) { _, count in
            if count == 0 {
                dismiss()
            } else if index >= count {
                index = count - 1
            }
        }
    }

    /// Отпустили палец после свайпа вниз: далеко или быстро — закрыть, иначе вернуть на место.
    private func release(_ close: Bool) {
        if close {
            dismiss()
        } else {
            withAnimation(.spring(duration: 0.25)) { pull = 0 }
        }
    }
}

/// Верхняя полоса: закрыть, «2 из 5», поделиться, удалить.
private struct ViewerBar: View {
    let photo: PhotoAttachment
    let position: Int
    let total: Int
    var onClose: () -> Void
    var onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            circle("xmark", label: "Закрыть", action: onClose)
            Spacer()
            Text("\(position) из \(total)")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial, in: Capsule())
            Spacer()
            if let image = UIImage(data: photo.imageData) {
                ShareLink(item: Image(uiImage: image), preview: SharePreview("Фото", image: Image(uiImage: image))) {
                    icon("square.and.arrow.up")
                }
                .accessibilityLabel("Поделиться")
            }
            circle("trash", label: "Удалить", action: onDelete)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private func circle(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            icon(symbol)
        }
        .accessibilityLabel(label)
    }

    private func icon(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(Color.white)
            .frame(width: 44, height: 44)
            .background(.ultraThinMaterial, in: Circle())
    }
}

/// Фото с увеличением: щипок, двойной тап, перетаскивание увеличенного. Без увеличения свайп
/// вниз тянет фото и закрывает просмотр; влево-вправо — листает (это делает TabView).
private struct ZoomableImage: UIViewRepresentable {
    let data: Data
    @Binding var zoomed: Bool
    var onPull: (CGFloat) -> Void
    var onRelease: (Bool) -> Void

    func makeUIView(context: Context) -> ZoomView {
        let view = ZoomView()
        view.image = UIImage(data: data)
        return view
    }

    func updateUIView(_ view: ZoomView, context: Context) {
        view.onZoom = { isZoomed in
            if zoomed != isZoomed { zoomed = isZoomed }
        }
        view.onPull = onPull
        view.onRelease = onRelease
    }
}

private final class ZoomView: UIScrollView, UIScrollViewDelegate {
    var onZoom: ((Bool) -> Void)?
    var onPull: ((CGFloat) -> Void)?
    var onRelease: ((Bool) -> Void)?
    var image: UIImage? {
        didSet { imageView.image = image }
    }

    private let imageView = UIImageView()
    private lazy var pullGesture = UIPanGestureRecognizer(target: self, action: #selector(pulled(_:)))

    init() {
        super.init(frame: .zero)
        delegate = self
        minimumZoomScale = 1
        maximumZoomScale = 4
        bouncesZoom = true
        showsVerticalScrollIndicator = false
        showsHorizontalScrollIndicator = false
        contentInsetAdjustmentBehavior = .never
        backgroundColor = .clear
        imageView.contentMode = .scaleAspectFit
        addSubview(imageView)

        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(doubleTapped(_:)))
        doubleTap.numberOfTapsRequired = 2
        addGestureRecognizer(doubleTap)
        addGestureRecognizer(pullGesture)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private var isZoomed: Bool {
        zoomScale > minimumZoomScale + 0.01
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if !isZoomed {
            imageView.frame = bounds
            contentSize = bounds.size
        }
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        imageView
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        onZoom?(isZoomed)
    }

    /// Двойной тап: увеличить в точку касания или вернуть как было.
    @objc private func doubleTapped(_ tap: UITapGestureRecognizer) {
        if isZoomed {
            setZoomScale(minimumZoomScale, animated: true)
        } else {
            let point = tap.location(in: imageView)
            let scale: CGFloat = 2.5
            let size = CGSize(width: bounds.width / scale, height: bounds.height / scale)
            zoom(to: CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2,
                            width: size.width, height: size.height), animated: true)
        }
    }

    /// Свайп вниз ловим только без увеличения и только вниз — иначе листание и перетаскивание.
    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === pullGesture else {
            return super.gestureRecognizerShouldBegin(gestureRecognizer)
        }
        guard !isZoomed else { return false }
        let velocity = pullGesture.velocity(in: self)
        return velocity.y > 0 && velocity.y > abs(velocity.x)
    }

    @objc private func pulled(_ pan: UIPanGestureRecognizer) {
        let distance = max(0, pan.translation(in: self).y)
        switch pan.state {
        case .changed:
            onPull?(distance)
        case .ended:
            onRelease?(distance > 120 || pan.velocity(in: self).y > 900)
        case .cancelled, .failed:
            onRelease?(false)
        default:
            break
        }
    }
}
