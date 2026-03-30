import NetworkExtension
import os.log

class TransparentProxyProvider: NETransparentProxyProvider {

    private let log = Logger(subsystem: "io.greywall.proxy", category: "provider")

    // MARK: - Lifecycle

    override func startProxy(options: [String: Any]?, completionHandler: @escaping (Error?) -> Void) {
        log.info("startProxy called")

        let settings = NETransparentProxyNetworkSettings(tunnelRemoteAddress: "127.0.0.1")

        // Capture all outbound TCP
        let tcpRule = NENetworkRule(
            remoteNetwork: nil, remotePrefix: 0,
            localNetwork: nil, localPrefix: 0,
            protocol: .TCP, direction: .outbound
        )

        // Capture all outbound UDP (includes DNS on port 53)
        let udpRule = NENetworkRule(
            remoteNetwork: nil, remotePrefix: 0,
            localNetwork: nil, localPrefix: 0,
            protocol: .UDP, direction: .outbound
        )

        // Exclude loopback to avoid interfering with local services
        let loopbackV4 = NENetworkRule(
            remoteNetwork: NWHostEndpoint(hostname: "127.0.0.0", port: "0"),
            remotePrefix: 8,
            localNetwork: nil, localPrefix: 0,
            protocol: .any, direction: .any
        )
        let loopbackV6 = NENetworkRule(
            remoteNetwork: NWHostEndpoint(hostname: "::1", port: "0"),
            remotePrefix: 128,
            localNetwork: nil, localPrefix: 0,
            protocol: .any, direction: .any
        )

        settings.includedNetworkRules = [tcpRule, udpRule]
        settings.excludedNetworkRules = [loopbackV4, loopbackV6]

        setTunnelNetworkSettings(settings) { error in
            if let error {
                self.log.error("Failed to set network settings: \(error.localizedDescription)")
            } else {
                self.log.info("Network settings applied, proxy active")
            }
            completionHandler(error)
        }
    }

    override func stopProxy(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        log.info("stopProxy called, reason: \(String(describing: reason))")
        completionHandler()
    }

    // MARK: - Flow handling (Step 1: passive logging, all passthrough)

    override func handleNewFlow(_ flow: NEAppProxyFlow) -> Bool {
        let meta = flow.metaData
        let signingID = meta.sourceAppSigningIdentifier
        let hostname = flow.remoteHostname ?? "<no hostname>"
        let pid = extractPID(from: meta.sourceAppAuditToken)

        if let tcpFlow = flow as? NEAppProxyTCPFlow {
            let endpoint = tcpFlow.remoteEndpoint as? NWHostEndpoint
            let dest = endpoint.map { "\($0.hostname):\($0.port)" } ?? "<unknown>"
            log.info("TCP flow: pid=\(pid) app=\(signingID) host=\(hostname) dest=\(dest)")
        } else if flow is NEAppProxyUDPFlow {
            log.info("UDP flow: pid=\(pid) app=\(signingID) host=\(hostname)")
        }

        // Step 1: passthrough everything -- just log and let it through
        return false
    }

    // MARK: - Helpers

    private func extractPID(from auditToken: Data?) -> pid_t {
        guard let token = auditToken, token.count >= 24 else { return -1 }
        // audit_token_t is 8 x UInt32; PID is at index 5 (byte offset 20)
        return token.withUnsafeBytes { ptr in
            let tokens = ptr.bindMemory(to: UInt32.self)
            return pid_t(tokens[5])
        }
    }
}
