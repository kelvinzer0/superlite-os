package pkg

import (
	"bufio"
	"compress/gzip"
	"fmt"
	"io"
	"net/http"
	"strings"
)

// Supported architectures (like debianpool-searcher)
var DebianArchitectures = []string{
	"amd64",
	"i386",
	"arm64",
	"armhf",
	"ppc64el",
	"mips64el",
	"s390x",
	"all",
}

// DebianSearch searches Debian package repositories
func DebianSearch(src Source, query string) ([]Package, error) {
	dist := src.Dist
	if dist == "" {
		dist = "stable"
	}
	comp := src.Comp
	if comp == "" {
		comp = "main"
	}

	var allPkgs []Package

	// Search across multiple architectures
	for _, arch := range DebianArchitectures {
		url := fmt.Sprintf("http://%s/dists/%s/%s/binary-%s/Packages.gz", src.URL, dist, comp, arch)

		pkgs, err := searchDebianURL(url, query, arch)
		if err != nil {
			// Silently skip failed architectures
			continue
		}
		allPkgs = append(allPkgs, pkgs...)
	}

	return allPkgs, nil
}

// searchDebianURL searches a specific Debian Packages.gz URL
func searchDebianURL(url, query, arch string) ([]Package, error) {
	resp, err := http.Get(url)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("http status: %d", resp.StatusCode)
	}

	gz, err := gzip.NewReader(resp.Body)
	if err != nil {
		return nil, err
	}
	defer gz.Close()

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
			if inPackage && matchesQuery(currentPkg.Name, currentPkg.Description, query) {
				currentPkg.Source = source
				pkgs = append(pkgs, currentPkg)
			}
			currentPkg = Package{}
			inPackage = false
			continue
		}

		if strings.HasPrefix(line, " ") {
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
		case "Architecture":
			// Store arch info if needed
		}
	}

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

// FindSimilar finds similar package names (like debianpool-searcher's similar_text)
func FindSimilar(query string, allPkgs []Package, threshold float64) []Package {
	var similar []Package
	q := strings.ToLower(query)

	for _, pkg := range allPkgs {
		percent := similarity(q, strings.ToLower(pkg.Name))
		if percent > threshold {
			similar = append(similar, pkg)
		}
	}

	return similar
}

// similarity calculates string similarity (0-100)
func similarity(a, b string) float64 {
	if a == b {
		return 100
	}

	// Simple Levenshtein-based similarity
	lenA := len(a)
	lenB := len(b)
	if lenA == 0 || lenB == 0 {
		return 0
	}

	// Count matching characters
	matches := 0
	for i := 0; i < lenA && i < lenB; i++ {
		if a[i] == b[i] {
			matches++
		}
	}

	return float64(matches) / float64(max(lenA, lenB)) * 100
}

func max(a, b int) int {
	if a > b {
		return a
	}
	return b
}
