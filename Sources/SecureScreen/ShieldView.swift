import SwiftUI
import AppKit

struct ShieldView: View {
    @ObservedObject var hintState: HintState

    var body: some View {
        ZStack {
            VisualEffectBlur()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea()

            if hintState.visible {
                Text("Locked — Press ⌥⇧U to Unlock")
                    .foregroundColor(.white.opacity(0.35))
                    .font(.system(size: 13, weight: .light, design: .default))
                    .transition(.opacity)
                    .animation(.easeInOut(duration: 0.4), value: hintState.visible)
            }
        }
    }
}

struct VisualEffectBlur: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .fullScreenUI
        v.blendingMode = .behindWindow
        v.state = .active
        v.appearance = NSAppearance(named: .darkAqua)
        return v
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

// Shared observable so LockWindow can trigger hint without re-creating the view
final class HintState: ObservableObject {
    @Published var visible = false
    private var hideTask: DispatchWorkItem?

    func flash() {
        hideTask?.cancel()
        withAnimation { visible = true }
        let task = DispatchWorkItem { [weak self] in
            withAnimation { self?.visible = false }
        }
        hideTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: task)
    }
}
