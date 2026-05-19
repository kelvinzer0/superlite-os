package pkg

// Package represents a package from any source
type Package struct {
	Name        string
	Version     string
	Description string
	Source      string // alpine, debian, ppa, flatpak
	Size        int64
	Installed   bool
	Available   bool
}

// SearchResult holds results from all sources
type SearchResult struct {
	Query   string
	Package []Package
}
