import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Floating Screen Edge Dropzone Window that slides out when files are dragged near the right screen edge.
public final class ScreenEdgeDropzoneController: NSObject {
    public static let shared = ScreenEdgeDropzoneController()

    private var dropzoneWindow: ScreenEdgeDropzoneWindow?
    private var isEnabled: Bool {
        if UserDefaults.standard.object(forKey: "screen_edge_dropzone_enabled") == nil {
            return true
        }
        return UserDefaults.standard.bool(forKey: "screen_edge_dropzone_enabled")
    }

    private override init() {
        super.init()
    }

    public func start() {
        guard dropzoneWindow == nil else { return }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )

        createWindow()
    }

    public func reloadPreferences() {
        if isEnabled {
            if dropzoneWindow == nil {
                createWindow()
            } else {
                dropzoneWindow?.orderFront(nil)
            }
        } else {
            dropzoneWindow?.orderOut(nil)
        }
    }

    @objc private func screenParametersChanged() {
        dropzoneWindow?.repositionOnScreen()
    }

    private func createWindow() {
        guard isEnabled else { return }

        let window = ScreenEdgeDropzoneWindow()
        window.repositionOnScreen()
        window.orderFront(nil)
        self.dropzoneWindow = window
    }
}

public final class ScreenEdgeDropzoneWindow: NSPanel {
    private let idleWidth: CGFloat = 24
    private let expandedWidth: CGFloat = 220
    private let panelHeight: CGFloat = 320
    private var isExpanded: Bool = false

    private var dropView: DropzoneContainerView!

    public init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 24, height: 320),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        self.level = .floating
        self.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = false
        self.isMovableByWindowBackground = false

        self.dropView = DropzoneContainerView(frame: self.contentView?.bounds ?? .zero) { [weak self] expanded in
            self?.setExpanded(expanded)
        }
        self.contentView = dropView
    }

    public func repositionOnScreen() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let screenFrame = screen.visibleFrame
        let currentWidth = isExpanded ? expandedWidth : idleWidth
        let x = screenFrame.maxX - currentWidth
        let y = screenFrame.minY + (screenFrame.height - panelHeight) / 2

        self.setFrame(NSRect(x: x, y: y, width: currentWidth, height: panelHeight), display: true)
    }

    public func setExpanded(_ expanded: Bool) {
        guard isExpanded != expanded else { return }
        isExpanded = expanded

        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let screenFrame = screen.visibleFrame
        let targetWidth = expanded ? expandedWidth : idleWidth
        let targetX = screenFrame.maxX - targetWidth
        let targetY = screenFrame.minY + (screenFrame.height - panelHeight) / 2

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            self.animator().setFrame(NSRect(x: targetX, y: targetY, width: targetWidth, height: panelHeight), display: true)
        }
    }
}

final class DropzoneContainerView: NSView {
    private var isHovered: Bool = false
    private var isSuccess: Bool = false
    private let onExpandChanged: (Bool) -> Void

    private let hostingView: NSHostingView<DropzoneVisualContentView>

    init(frame frameRect: NSRect, onExpandChanged: @escaping (Bool) -> Void) {
        self.onExpandChanged = onExpandChanged
        let model = DropzoneVisualModel()
        self.hostingView = NSHostingView(rootView: DropzoneVisualContentView(model: model))
        super.init(frame: frameRect)

        self.autoresizingMask = [.width, .height]
        self.addSubview(hostingView)
        hostingView.frame = self.bounds
        hostingView.autoresizingMask = [.width, .height]

        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Transparent click-through: allow all mouse clicks on browser scrollbars
    /// and background buttons to pass through completely when not dragging.
    override func hitTest(_ point: NSPoint) -> NSView? {
        return (isHovered || isSuccess) ? super.hitTest(point) : nil
    }

    private func updateUIModel(isDragging: Bool, success: Bool = false) {
        let trustedPeer = ControlSessionServer.shared.connectedPeers.first(where: { $0.isTrusted })
        let model = DropzoneVisualModel(
            isDragging: isDragging,
            isSuccess: success,
            connectedDeviceName: trustedPeer?.name ?? "Android Companion",
            isConnected: trustedPeer != nil
        )
        hostingView.rootView = DropzoneVisualContentView(model: model)
    }

    // MARK: - NSDraggingDestination

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        let pboard = sender.draggingPasteboard
        guard let types = pboard.types, types.contains(.fileURL) else {
            return []
        }

        isHovered = true
        onExpandChanged(true)
        updateUIModel(isDragging: true)
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        isHovered = false
        updateUIModel(isDragging: false)
        onExpandChanged(false)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let pboard = sender.draggingPasteboard
        guard let urls = pboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL], !urls.isEmpty else {
            isHovered = false
            updateUIModel(isDragging: false)
            onExpandChanged(false)
            return false
        }

        let sent = FileStreamingManager.shared.sendFilesToConnectedPeer(urls: urls)
        updateUIModel(isDragging: false, success: sent)

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            self?.isHovered = false
            self?.updateUIModel(isDragging: false, success: false)
            self?.onExpandChanged(false)
        }

        return sent
    }
}

final class DropzoneVisualModel: ObservableObject {
    @Published var isDragging: Bool
    @Published var isSuccess: Bool
    @Published var connectedDeviceName: String
    @Published var isConnected: Bool

    init(
        isDragging: Bool = false,
        isSuccess: Bool = false,
        connectedDeviceName: String = "Android Companion",
        isConnected: Bool = false
    ) {
        self.isDragging = isDragging
        self.isSuccess = isSuccess
        self.connectedDeviceName = connectedDeviceName
        self.isConnected = isConnected
    }
}

struct DropzoneVisualContentView: View {
    @ObservedObject var model: DropzoneVisualModel

    var body: some View {
        ZStack {
            // Frosted Glass Background
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                .clipShape(
                    UnevenRoundedRectangle(
                        topLeadingRadius: 16,
                        bottomLeadingRadius: 16,
                        bottomTrailingRadius: 0,
                        topTrailingRadius: 0
                    )
                )
                .overlay(
                    UnevenRoundedRectangle(
                        topLeadingRadius: 16,
                        bottomLeadingRadius: 16,
                        bottomTrailingRadius: 0,
                        topTrailingRadius: 0
                    )
                    .strokeBorder(
                        model.isDragging
                            ? Color(red: 0.04, green: 0.52, blue: 1.0)
                            : (model.isSuccess ? Color(red: 0.20, green: 0.78, blue: 0.35) : Color.white.opacity(0.15)),
                        lineWidth: model.isDragging ? 2.0 : 1.0
                    )
                )
                .shadow(color: Color.black.opacity(0.25), radius: 12, x: -4, y: 0)

            // Content
            VStack(spacing: 12) {
                if model.isSuccess {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 36))
                        .foregroundStyle(Color(red: 0.20, green: 0.78, blue: 0.35))

                    Text("Terkirim!")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.primary)

                    Text("Mentransfer ke \(model.connectedDeviceName)")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 10)
                } else {
                    ZStack {
                        Circle()
                            .fill(Color(red: 0.04, green: 0.52, blue: 1.0).opacity(model.isDragging ? 0.25 : 0.12))
                            .frame(width: 54, height: 54)

                        Image(systemName: model.isDragging ? "arrow.down.doc.fill" : "arrow.left.to.line.compact")
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundStyle(Color(red: 0.04, green: 0.52, blue: 1.0))
                    }

                    VStack(spacing: 4) {
                        Text(model.isDragging ? "Lepas untuk Kirim" : "Corda Dropzone")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.primary)

                        HStack(spacing: 4) {
                            Circle()
                                .fill(model.isConnected ? Color(red: 0.20, green: 0.78, blue: 0.35) : Color.orange)
                                .frame(width: 6, height: 6)

                            Text(model.connectedDeviceName)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }

                    Text("Drop berkas di sini untuk mengirim ke Android secara instan")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 12)
                }
            }
            .padding(.leading, 8)
            .padding(.trailing, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .opacity((model.isDragging || model.isSuccess) ? 1.0 : 0.0)
        .animation(.easeOut(duration: 0.15), value: model.isDragging)
    }
}
