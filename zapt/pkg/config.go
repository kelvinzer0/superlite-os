package pkg

import (
	"bufio"
	"fmt"
	"os"
	"strings"
)

const (
	DefaultConfig = "/etc/zapt/sources.conf"
)

// Source represents a package source
type Source struct {
	Type string // alpine, debian, ppa, flatpak
	URL  string
	Dist string // for debian: stable, unstable, etc
	Comp string // for debian: main, contrib, etc
	Name string
}

// LoadSources reads sources from config file
func LoadSources(path string) ([]Source, error) {
	if path == "" {
		path = DefaultConfig
	}

	// If config doesn't exist, return default Alpine sources
	if _, err := os.Stat(path); os.IsNotExist(err) {
		return DefaultSources(), nil
	}

	f, err := os.Open(path)
	if err != nil {
		return nil, fmt.Errorf("open sources: %w", err)
	}
	defer f.Close()

	var sources []Source
	scanner := bufio.NewScanner(f)
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		s := parseSourceLine(line)
		if s != nil {
			sources = append(sources, *s)
		}
	}

	if len(sources) == 0 {
		return DefaultSources(), nil
	}
	return sources, nil
}

// DefaultSources returns the default Alpine sources
func DefaultSources() []Source {
	return []Source{
		{Type: "alpine", URL: "dl-cdn.alpinelinux.org/alpine/edge/main"},
		{Type: "alpine", URL: "dl-cdn.alpinelinux.org/alpine/edge/community"},
		{Type: "alpine", URL: "dl-cdn.alpinelinux.org/alpine/edge/testing"},
	}
}

func parseSourceLine(line string) *Source {
	if strings.HasPrefix(line, "alpine://") {
		return &Source{Type: "alpine", URL: strings.TrimPrefix(line, "alpine://")}
	}
	if strings.HasPrefix(line, "debian://") {
		parts := strings.Fields(strings.TrimPrefix(line, "debian://"))
		if len(parts) >= 2 {
			s := &Source{Type: "debian", URL: parts[0], Dist: parts[1]}
			if len(parts) >= 3 {
				s.Comp = parts[2]
			}
			return s
		}
	}
	if strings.HasPrefix(line, "ppa:") {
		return &Source{Type: "ppa", Name: strings.TrimPrefix(line, "ppa:")}
	}
	if line == "flatpak://auto" || strings.HasPrefix(line, "flatpak://") {
		return &Source{Type: "flatpak", URL: "auto"}
	}
	return nil
}
