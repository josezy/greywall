import Cocoa
import SystemExtensions
import NetworkExtension
import os.log

@main
class AppDelegate: NSObject, NSApplicationDelegate, OSSystemExtensionRequestDelegate {

    private let log = Logger(subsystem: "io.greywall.proxy.app", category: "app")
    private let extensionBundleID = "io.greywall.proxy.extension"

    // MARK: - App lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        log.info("GreywallProxy app launched")
        activateExtension()
    }

    // MARK: - System extension activation

    private func activateExtension() {
        log.info("Requesting activation of \(self.extensionBundleID)")
        let request = OSSystemExtensionRequest.activationRequest(
            forExtensionWithIdentifier: extensionBundleID,
            queue: .main
        )
        request.delegate = self
        OSSystemExtensionManager.shared.submitRequest(request)
    }

    // MARK: - OSSystemExtensionRequestDelegate

    func request(_ request: OSSystemExtensionRequest,
                 didFinishWithResult result: OSSystemExtensionRequest.Result) {
        log.info("Extension activation finished: \(result.rawValue)")
        switch result {
        case .completed:
            log.info("Extension activated, configuring proxy manager")
            configureProxyManager()
        case .willCompleteAfterReboot:
            log.info("Extension will activate after reboot")
        @unknown default:
            log.warning("Unknown result: \(result.rawValue)")
        }
    }

    func request(_ request: OSSystemExtensionRequest, didFailWithError error: Error) {
        log.error("Extension activation failed: \(error.localizedDescription)")
    }

    func requestNeedsUserApproval(_ request: OSSystemExtensionRequest) {
        log.info("User approval needed -- check System Settings > Privacy & Security")
    }

    func request(_ request: OSSystemExtensionRequest,
                 actionForReplacingExtension existing: OSSystemExtensionProperties,
                 withExtension ext: OSSystemExtensionProperties) -> OSSystemExtensionRequest.ReplacementAction {
        log.info("Replacing existing extension v\(existing.bundleShortVersion) with v\(ext.bundleShortVersion)")
        return .replace
    }

    // MARK: - Proxy manager configuration

    private func configureProxyManager() {
        NETransparentProxyManager.loadAllFromPreferences { managers, error in
            if let error {
                self.log.error("Failed to load proxy managers: \(error.localizedDescription)")
                return
            }

            let manager = managers?.first ?? NETransparentProxyManager()

            let proto = NETunnelProviderProtocol()
            proto.providerBundleIdentifier = self.extensionBundleID
            proto.serverAddress = "127.0.0.1"

            manager.protocolConfiguration = proto
            manager.localizedDescription = "Greywall Proxy"
            manager.isEnabled = true

            manager.saveToPreferences { error in
                if let error {
                    self.log.error("Failed to save proxy config: \(error.localizedDescription)")
                    return
                }
                self.log.info("Proxy config saved, starting tunnel")
                manager.loadFromPreferences { error in
                    if let error {
                        self.log.error("Failed to reload: \(error.localizedDescription)")
                        return
                    }
                    do {
                        try manager.connection.startVPNTunnel()
                        self.log.info("Tunnel started")
                    } catch {
                        self.log.error("Failed to start tunnel: \(error.localizedDescription)")
                    }
                }
            }
        }
    }
}
