package pkg

import (
	"bufio"
	"fmt"
	"os/exec"
	"strings"
)

// ApkSearch searches Alpine repos using apk
func ApkSearch(query string) ([]Package, error) {
	cmd := exec.Command("apk", "search", "-v", query)
	out, err := cmd.Output()
	if err != nil {
		return nil, fmt.Errorf("apk search: %w", err)
	}

	var pkgs []Package
	scanner := bufio.NewScanner(strings.NewReader(string(out)))
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if line == "" {
			continue
		}
		p := parseApkSearchLine(line)
		if p != nil {
			pkgs = append(pkgs, *p)
		}
	}
	return pkgs, nil
}

// ApkListInstalled lists installed packages
func ApkListInstalled() ([]Package, error) {
	cmd := exec.Command("apk", "list", "--installed")
	out, err := cmd.Output()
	if err != nil {
		return nil, fmt.Errorf("apk list: %w", err)
	}

	var pkgs []Package
	scanner := bufio.NewScanner(strings.NewReader(string(out)))
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if line == "" {
			continue
		}
		p := parseApkListLine(line)
		if p != nil {
			pkgs = append(pkgs, *p)
		}
	}
	return pkgs, nil
}

// ApkInfo gets info about a package
func ApkInfo(name string) (*Package, error) {
	cmd := exec.Command("apk", "info", "-a", name)
	out, err := cmd.Output()
	if err != nil {
		return nil, fmt.Errorf("apk info: %w", err)
	}

	p := &Package{Name: name, Source: "alpine"}
	scanner := bufio.NewScanner(strings.NewReader(string(out)))
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if strings.HasPrefix(line, "Description:") {
			p.Description = strings.TrimSpace(strings.TrimPrefix(line, "Description:"))
		}
		if strings.HasPrefix(line, "Version:") {
			p.Version = strings.TrimSpace(strings.TrimPrefix(line, "Version:"))
		}
	}
	return p, nil
}

// ApkInstall installs a package via apk
func ApkInstall(name string) error {
	cmd := exec.Command("apk", "add", name)
	cmd.Stdout = nil
	cmd.Stderr = nil
	out, err := cmd.CombinedOutput()
	if err != nil {
		return fmt.Errorf("apk add %s: %s", name, string(out))
	}
	return nil
}

// ApkRemove removes a package via apk
func ApkRemove(name string) error {
	cmd := exec.Command("apk", "del", name)
	cmd.Stdout = nil
	cmd.Stderr = nil
	out, err := cmd.CombinedOutput()
	if err != nil {
		return fmt.Errorf("apk del %s: %s", name, string(out))
	}
	return nil
}

// ApkUpdate updates package indices
func ApkUpdate() error {
	cmd := exec.Command("apk", "update")
	cmd.Stdout = nil
	cmd.Stderr = nil
	out, err := cmd.CombinedOutput()
	if err != nil {
		return fmt.Errorf("apk update: %s", string(out))
	}
	return nil
}

// ApkUpgrade upgrades all packages
func ApkUpgrade() error {
	cmd := exec.Command("apk", "upgrade")
	cmd.Stdout = nil
	cmd.Stderr = nil
	out, err := cmd.CombinedOutput()
	if err != nil {
		return fmt.Errorf("apk upgrade: %s", string(out))
	}
	return nil
}

// parseApkSearchLine parses "name-version description" format
func parseApkSearchLine(line string) *Package {
	// Format: package-name-version description
	// Example: firefox-esr-128.5.0-r0
	parts := strings.SplitN(line, " ", 2)
	if len(parts) == 0 {
		return nil
	}

	nameVer := parts[0]
	desc := ""
	if len(parts) > 1 {
		desc = parts[1]
	}

	// Split name and version
	name, version := splitNameVersion(nameVer)
	return &Package{
		Name:        name,
		Version:     version,
		Description: desc,
		Source:      "alpine",
	}
}

// parseApkListLine parses installed package list
func parseApkListLine(line string) *Package {
	// Format: package-name-version description
	parts := strings.SplitN(line, " ", 2)
	if len(parts) == 0 {
		return nil
	}

	nameVer := parts[0]
	desc := ""
	if len(parts) > 1 {
		desc = strings.TrimSpace(parts[1])
	}

	name, version := splitNameVersion(nameVer)
	return &Package{
		Name:        name,
		Version:     version,
		Description: desc,
		Source:      "alpine",
		Installed:   true,
	}
}

// splitNameVersion splits "name-version" into name and version
func splitNameVersion(nameVer string) (string, string) {
	// Find the last hyphen followed by a digit
	for i := len(nameVer) - 1; i >= 0; i-- {
		if nameVer[i] == '-' && i > 0 {
			// Check if what follows looks like a version
			rest := nameVer[i+1:]
			if len(rest) > 0 && (rest[0] >= '0' && rest[0] <= '9') {
				return nameVer[:i], rest
			}
		}
	}
	return nameVer, ""
}
