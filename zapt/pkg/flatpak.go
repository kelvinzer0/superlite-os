package pkg

import (
	"bufio"
	"fmt"
	"os/exec"
	"strings"
)

// FlatpakSearch searches Flatpak repositories
func FlatpakSearch(query string) ([]Package, error) {
	// Check if flatpak is installed
	if _, err := exec.LookPath("flatpak"); err != nil {
		return nil, fmt.Errorf("flatpak not installed")
	}

	// Run flatpak search
	cmd := exec.Command("flatpak", "search", query)
	out, err := cmd.Output()
	if err != nil {
		return nil, fmt.Errorf("flatpak search: %w", err)
	}

	var pkgs []Package
	scanner := bufio.NewScanner(strings.NewReader(string(out)))
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if line == "" || strings.HasPrefix(line, "Name") {
			continue
		}

		// Parse flatpak search output
		// Format: Application ID\tVersion\tDescription
		parts := strings.SplitN(line, "\t", 3)
		if len(parts) >= 1 {
			p := Package{
				Name:   parts[0],
				Source: "flatpak",
			}
			if len(parts) >= 2 {
				p.Version = parts[1]
			}
			if len(parts) >= 3 {
				p.Description = parts[2]
			}
			pkgs = append(pkgs, p)
		}
	}

	return pkgs, nil
}
