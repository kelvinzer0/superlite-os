package pkg

import (
	"compress/gzip"
	"fmt"
	"net/http"
	"strings"
)

// PPASearch searches Ubuntu PPA repositories
func PPASearch(src Source, query string) ([]Package, error) {
	// PPA format: ppa:user/repo
	// URL: https://ppa.launchpadcontent.net/user/repo/ubuntu/dists/jammy/main/binary-amd64/Packages.gz
	parts := strings.Split(src.Name, "/")
	if len(parts) != 2 {
		return nil, fmt.Errorf("invalid PPA format: %s (expected user/repo)", src.Name)
	}
	user, repo := parts[0], parts[1]

	// Use jammy (22.04) as default Ubuntu release
	url := fmt.Sprintf("https://ppa.launchpadcontent.net/%s/%s/ubuntu/dists/jammy/main/binary-amd64/Packages.gz", user, repo)

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
	return parsePackagesIndex(gz, query, "ppa")
}
