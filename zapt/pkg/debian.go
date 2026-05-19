package pkg

import (
	"bufio"
	"compress/gzip"
	"fmt"
	"io"
	"net/http"
	"strings"
)

// DebianSearch searches Debian package repositories
func DebianSearch(src Source, query string) ([]Package, error) {
	// Build URL for Packages.gz
	// Format: http://deb.debian.org/debian/dists/stable/main/binary-amd64/Packages.gz
	dist := src.Dist
	if dist == "" {
		dist = "stable"
	}
	comp := src.Comp
	if comp == "" {
		comp = "main"
	}

	url := fmt.Sprintf("http://%s/dists/%s/%s/binary-amd64/Packages.gz", src.URL, dist, comp)

	// Download Packages.gz
	resp, err := http.Get(url)
	if err != nil {
		return nil, fmt.Errorf("http get: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("http status: %d", resp.StatusCode)
	}

	// Decompress gzip
	gz, err := gzip.NewReader(resp.Body)
	if err != nil {
		return nil, fmt.Errorf("gzip reader: %w", err)
	}
	defer gz.Close()

	// Parse and search
	return parsePackagesIndex(gz, query, "debian")
}

// parsePackagesIndex parses a Debian Packages index
func parsePackagesIndex(r io.Reader, query string, source string) ([]Package, error) {
	var pkgs []Package
	scanner := bufio.NewScanner(r)

	var currentPkg Package
	inPackage := false

	for scanner.Scan() {
		line := scanner.Text()

		if line == "" {
			// End of package entry
			if inPackage && matchesQuery(currentPkg.Name, currentPkg.Description, query) {
				currentPkg.Source = source
				pkgs = append(pkgs, currentPkg)
			}
			currentPkg = Package{}
			inPackage = false
			continue
		}

		if strings.HasPrefix(line, " ") {
			// Continuation line, skip
			continue
		}

		parts := strings.SplitN(line, ": ", 2)
		if len(parts) != 2 {
			continue
		}

		key, value := parts[0], parts[1]
		switch key {
		case "Package":
			currentPkg.Name = value
			inPackage = true
		case "Version":
			currentPkg.Version = value
		case "Description":
			currentPkg.Description = value
		}
	}

	// Handle last package
	if inPackage && matchesQuery(currentPkg.Name, currentPkg.Description, query) {
		currentPkg.Source = source
		pkgs = append(pkgs, currentPkg)
	}

	return pkgs, nil
}

// matchesQuery checks if name or description matches query
func matchesQuery(name, desc, query string) bool {
	q := strings.ToLower(query)
	return strings.Contains(strings.ToLower(name), q) ||
		strings.Contains(strings.ToLower(desc), q)
}
