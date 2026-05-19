package pkg

import (
	"archive/tar"
	"compress/gzip"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
)

// DebInfo holds .deb package metadata
type DebInfo struct {
	Name        string
	Version     string
	Description string
	Depends     string
}

// VerifyDeb checks if a file is a valid .deb
func VerifyDeb(path string) error {
	f, err := os.Open(path)
	if err != nil {
		return fmt.Errorf("open file: %w", err)
	}
	defer f.Close()

	// Check for ar magic "!<arch>"
	buf := make([]byte, 8)
	if _, err := f.Read(buf); err != nil {
		return fmt.Errorf("read header: %w", err)
	}
	if string(buf[:8]) != "!<arch>\n" {
		return fmt.Errorf("not a valid .deb file (missing ar magic)")
	}

	return nil
}

// ExtractDeb extracts a .deb file and installs it to /
func ExtractDeb(path string) (*DebInfo, error) {
	if err := RequireRoot(); err != nil {
		return nil, err
	}

	// Create temp directory for extraction
	tmpDir, err := os.MkdirTemp("", "zapt-deb-*")
	if err != nil {
		return nil, fmt.Errorf("create temp dir: %w", err)
	}
	defer os.RemoveAll(tmpDir)

	// Extract .deb using ar
	if err := extractAr(path, tmpDir); err != nil {
		return nil, fmt.Errorf("extract ar: %w", err)
	}

	// Parse control file
	info, err := parseControl(filepath.Join(tmpDir, "control.tar.gz"))
	if err != nil {
		// Try control.tar.xz
		info, err = parseControl(filepath.Join(tmpDir, "control.tar.xz"))
		if err != nil {
			return nil, fmt.Errorf("parse control: %w", err)
		}
	}

	// Extract data.tar.* to /
	dataFile := findDataTar(tmpDir)
	if dataFile == "" {
		return nil, fmt.Errorf("data.tar.* not found in .deb")
	}

	if err := extractDataToRoot(dataFile); err != nil {
		return nil, fmt.Errorf("extract data: %w", err)
	}

	// Run postinst if exists
	postinst := filepath.Join(tmpDir, "postinst")
	if _, err := os.Stat(postinst); err == nil {
		if err := exec.Command("sh", postinst, "configure").Run(); err != nil {
			fmt.Fprintf(os.Stderr, "Warning: postinst failed: %v\n", err)
		}
	}

	// Register in zapt database
	if err := registerPackage(info); err != nil {
		fmt.Fprintf(os.Stderr, "Warning: register failed: %v\n", err)
	}

	return info, nil
}

// extractAr extracts an ar archive
func extractAr(debPath, destDir string) error {
	// Use ar command to extract
	cmd := exec.Command("ar", "x", debPath)
	cmd.Dir = destDir
	return cmd.Run()
}

// parseControl parses the control.tar.gz to get package info
func parseControl(tarPath string) (*DebInfo, error) {
	f, err := os.Open(tarPath)
	if err != nil {
		return nil, err
	}
	defer f.Close()

	var reader io.Reader = f
	if strings.HasSuffix(tarPath, ".gz") {
		gz, err := gzip.NewReader(f)
		if err != nil {
			return nil, err
		}
		defer gz.Close()
		reader = gz
	}

	tr := tar.NewReader(reader)
	for {
		hdr, err := tr.Next()
		if err == io.EOF {
			break
		}
		if err != nil {
			return nil, err
		}

		if hdr.Name == "./control" || hdr.Name == "control" {
			data, err := io.ReadAll(tr)
			if err != nil {
				return nil, err
			}
			return parseControlData(string(data)), nil
		}
	}

	return nil, fmt.Errorf("control file not found")
}

// parseControlData parses control file content
func parseControlData(data string) *DebInfo {
	info := &DebInfo{}
	for _, line := range strings.Split(data, "\n") {
		line = strings.TrimSpace(line)
		if strings.HasPrefix(line, "Package:") {
			info.Name = strings.TrimSpace(strings.TrimPrefix(line, "Package:"))
		} else if strings.HasPrefix(line, "Version:") {
			info.Version = strings.TrimSpace(strings.TrimPrefix(line, "Version:"))
		} else if strings.HasPrefix(line, "Description:") {
			info.Description = strings.TrimSpace(strings.TrimPrefix(line, "Description:"))
		} else if strings.HasPrefix(line, "Depends:") {
			info.Depends = strings.TrimSpace(strings.TrimPrefix(line, "Depends:"))
		}
	}
	return info
}

// findDataTar finds the data.tar.* file
func findDataTar(dir string) string {
	entries, err := os.ReadDir(dir)
	if err != nil {
		return ""
	}
	for _, e := range entries {
		if strings.HasPrefix(e.Name(), "data.tar") {
			return filepath.Join(dir, e.Name())
		}
	}
	return ""
}

// extractDataToRoot extracts data.tar.* to /
func extractDataToRoot(tarPath string) error {
	f, err := os.Open(tarPath)
	if err != nil {
		return err
	}
	defer f.Close()

	// Determine compression
	var cmd *exec.Cmd
	if strings.HasSuffix(tarPath, ".gz") {
		cmd = exec.Command("tar", "xzf", "-", "-C", "/")
	} else if strings.HasSuffix(tarPath, ".xz") {
		cmd = exec.Command("tar", "xJf", "-", "-C", "/")
	} else if strings.HasSuffix(tarPath, ".zst") {
		cmd = exec.Command("tar", "--zstd", "xf", "-", "-C", "/")
	} else {
		cmd = exec.Command("tar", "xf", "-", "-C", "/")
	}

	cmd.Stdin = f
	return cmd.Run()
}

// registerPackage registers a .deb package in zapt database
func registerPackage(info *DebInfo) error {
	dbDir := "/var/lib/zapt/installed"
	if err := os.MkdirAll(dbDir, 0755); err != nil {
		return err
	}

	// Write package info
	pkgFile := filepath.Join(dbDir, info.Name)
	return os.WriteFile(pkgFile, []byte(fmt.Sprintf("Package: %s\nVersion: %s\n", info.Name, info.Version)), 0644)
}
