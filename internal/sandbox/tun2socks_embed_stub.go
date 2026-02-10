//go:build !linux

package sandbox

import "fmt"

// extractTun2Socks is not available on non-Linux platforms.
func extractTun2Socks() (string, error) {
	return "", fmt.Errorf("tun2socks is only available on Linux")
}
