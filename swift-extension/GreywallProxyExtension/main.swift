import Foundation
import NetworkExtension
import os.log

let log = Logger(subsystem: "io.greywall.proxy", category: "extension")
log.info("GreywallProxy network extension starting")

NEProvider.startSystemExtensionMode()
dispatchMain()
