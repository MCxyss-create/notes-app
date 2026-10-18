import SwiftUI
import UIKit

/// Убрать клавиатуру с любого экрана, не зная, какое поле сейчас в фокусе.
@MainActor
enum Keyboard {
    static func hide() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

extension View {
    /// Клавиатура убирается свайпом вниз по списку (уезжает за пальцем), тапом по пустому месту
    /// и кнопкой ⌄ над клавиатурой. Вешать на экран один раз — иначе кнопка ⌄ задвоится.
    func keyboardDismissable() -> some View {
        modifier(KeyboardDismissable())
    }

    /// Свайп вниз по этой области больше ~30 pt убирает клавиатуру. Для панели ввода.
    func swipeDownHidesKeyboard() -> some View {
        background { KeyboardGestureCatcher(gesture: .swipeDown) }
    }
}

private struct KeyboardDismissable: ViewModifier {
    @State private var keyboardShown = false

    func body(content: Content) -> some View {
        content
            .scrollDismissesKeyboard(.interactively)
            .background { KeyboardGestureCatcher(gesture: .tap) }
            // Своя кнопка, а не ToolbarItemGroup(placement: .keyboard): в iOS 26 та висит поверх
            // кнопки «отправить» у панели ввода, а у поля поиска её нет вовсе.
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if keyboardShown {
                    HStack {
                        Spacer()
                        Button {
                            Keyboard.hide()
                        } label: {
                            Image(systemName: "keyboard.chevron.compact.down")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(Color.primary)
                                .frame(width: 52, height: 36)
                                .background(.regularMaterial, in: Capsule())
                                .shadow(color: .black.opacity(0.12), radius: 4, y: 1)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Убрать клавиатуру")
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 6)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
                keyboardShown = true
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
                keyboardShown = false
            }
    }
}

private enum KeyboardGesture {
    /// Тап мимо полей ввода.
    case tap
    /// Свайп вниз больше ~30 pt.
    case swipeDown
}

/// Невидимая подложка под областью. Сама касаний не берёт: жест ловит распознаватель на окне.
/// Он не мешает остальным жестам (свайпы по строкам, прокрутка, кнопки работают как раньше)
/// и смотрит только касания в границах подложки и только на её экране — не на листе поверх.
private struct KeyboardGestureCatcher: UIViewRepresentable {
    let gesture: KeyboardGesture

    func makeUIView(context: Context) -> KeyboardGestureView {
        KeyboardGestureView(gesture: gesture)
    }

    func updateUIView(_ uiView: KeyboardGestureView, context: Context) {}
}

private final class KeyboardGestureView: UIView, UIGestureRecognizerDelegate {
    private let gesture: KeyboardGesture
    private var recognizer: UIGestureRecognizer?
    /// Когда палец коснулся. Повёл после долгого нажатия — это выделение текста, а не свайп.
    private var touchedAt: TimeInterval = 0
    private var swipeActive = false

    init(gesture: KeyboardGesture) {
        self.gesture = gesture
        super.init(frame: .zero)
        isUserInteractionEnabled = false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if let recognizer {
            recognizer.view?.removeGestureRecognizer(recognizer)
            self.recognizer = nil
        }
        guard let window else { return }
        let added: UIGestureRecognizer
        switch gesture {
        case .tap:
            added = UITapGestureRecognizer(target: self, action: #selector(tapped))
        case .swipeDown:
            added = UIPanGestureRecognizer(target: self, action: #selector(panned(_:)))
        }
        added.cancelsTouchesInView = false
        added.delaysTouchesEnded = false
        added.delegate = self
        window.addGestureRecognizer(added)
        recognizer = added
    }

    /// Корневой вид своего экрана: открытые поверх листы в него не входят.
    private var screenView: UIView? {
        var view = superview
        while let current = view {
            if current.next is UIViewController { return current }
            view = current.superview
        }
        return nil
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard let touched = touch.view, let screen = screenView, touched.isDescendant(of: screen),
              bounds.contains(touch.location(in: self)) else { return false }
        let field = touched.textInput
        switch gesture {
        case .tap:
            // Тап по полю ввода нужен самому полю.
            if field != nil { return false }
        case .swipeDown:
            // Длинный текст в поле листается пальцем — не мешать.
            if let text = field as? UITextView, text.contentSize.height > text.bounds.height + 1 { return false }
        }
        touchedAt = touch.timestamp
        return true
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        true
    }

    @objc private func tapped() {
        Keyboard.hide()
    }

    @objc private func panned(_ pan: UIPanGestureRecognizer) {
        switch pan.state {
        case .began:
            let velocity = pan.velocity(in: self)
            swipeActive = ProcessInfo.processInfo.systemUptime - touchedAt < 0.4 && velocity.y > abs(velocity.x)
        case .changed:
            let move = pan.translation(in: self)
            if swipeActive, move.y > 30, move.y > abs(move.x) {
                swipeActive = false
                Keyboard.hide()
            }
        default:
            swipeActive = false
        }
    }
}

private extension UIView {
    /// Поле ввода, в которое попал палец, если попал.
    var textInput: UIView? {
        var view: UIView? = self
        while let current = view {
            if current is UITextField || current is UITextView { return current }
            view = current.superview
        }
        return nil
    }
}
