package proxy

import (
	"fmt"
	"io"
	"os"
	"os/exec"
)

// Start runs "greyproxy service start" to start the greyproxy service.
func Start(output io.Writer) error {
	if output == nil {
		output = os.Stderr
	}

	path, found := checkInstalled()
	if !found {
		return fmt.Errorf("greyproxy not found on PATH")
	}

	_, _ = fmt.Fprintf(output, "Starting greyproxy service...\n")
	cmd := exec.Command(path, "service", "start") //nolint:gosec // path comes from exec.LookPath
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	if err := cmd.Run(); err != nil {
		return fmt.Errorf("failed to start greyproxy service: %w", err)
	}

	return nil
}
