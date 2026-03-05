package sandbox

import (
	"fmt"
	"os"
)

var useColor = detectColor()

func detectColor() bool {
	// NO_COLOR convention: https://no-color.org/
	if _, ok := os.LookupEnv("NO_COLOR"); ok {
		return false
	}
	fi, err := os.Stdout.Stat()
	if err != nil {
		return false
	}
	return fi.Mode()&os.ModeCharDevice != 0
}

// CheckOK formats a green ✓ line (or plain if no color support).
func CheckOK(msg string) string {
	if useColor {
		return fmt.Sprintf("  \033[32m✓\033[0m %s", msg)
	}
	return fmt.Sprintf("  ✓ %s", msg)
}

// CheckFail formats a red ✗ line (or plain if no color support).
func CheckFail(msg string) string {
	if useColor {
		return fmt.Sprintf("  \033[31m✗\033[0m %s", msg)
	}
	return fmt.Sprintf("  ✗ %s", msg)
}
