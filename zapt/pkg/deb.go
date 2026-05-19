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
	Arch        string
}

// System libraries that should NOT be overwritten
var protectedLibs = []string{
	"/ld-linux", "/ld.so", "/ld-",
	"/libc.so", "/libstdc++", "/libgcc_s.so", "/libm.so",
	"/libpthread.so", "/libdl.so", "/librt.so", "/libresolv.so",
	"/libnss_", "/libutil.so", "/libcrypt.so",
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

	// Create backup directory
	backupDir := filepath.Join(tmpDir, "backup")
	if err := os.MkdirAll(backupDir, 0755); err != nil {
		return nil, fmt.Errorf("create backup dir: %w", err)
	}

	// Extract .deb using ar
	extractDir := filepath.Join(tmpDir, "extracted")
	if err := os.MkdirAll(extractDir, 0755); err != nil {
		return nil, err
	}
	if err := extractAr(path, extractDir); err != nil {
		return nil, fmt.Errorf("extract ar: %w", err)
	}

	// Parse control file
	info, err := parseControl(filepath.Join(extractDir, "control.tar.gz"))
	if err != nil {
		info, err = parseControl(filepath.Join(extractDir, "control.tar.xz"))
		if err != nil {
			info, err = parseControl(filepath.Join(extractDir, "control.tar.zst"))
			if err != nil {
				return nil, fmt.Errorf("parse control: %w", err)
			}
		}
	}

	// Extract data.tar.* to temp dir first (not directly to /)
	dataFile := findDataTar(extractDir)
	if dataFile == "" {
		return nil, fmt.Errorf("data.tar.* not found in .deb")
	}

	dataDir := filepath.Join(tmpDir, "data")
	if err := os.MkdirAll(dataDir, 0755); err != nil {
		return nil, err
	}
	if err := extractDataToDir(dataFile, dataDir); err != nil {
		return nil, fmt.Errorf("extract data: %w", err)
	}

	// Install files with safety checks (inspired by sailfish installer)
	fmt.Printf("Installing %s %s...\n", info.Name, info.Version)
	installed, skipped, err := installFilesWithSafety(dataDir, backupDir)
	if err != nil {
		return nil, fmt.Errorf("install files: %w", err)
	}

	fmt.Printf("  Installed: %d files\n", installed)
	if skipped > 0 {
		fmt.Printf("  Skipped:   %d files (protected libs)\n", skipped)
	}

	// Run postinst if exists
	postinst := findScript(extractDir, "postinst")
	if postinst != "" {
		fmt.Printf("  Running postinst...\n")
		if err := exec.Command("sh", postinst, "configure").Run(); err != nil {
			fmt.Fprintf(os.Stderr, "  Warning: postinst failed: %v\n", err)
		}
	}

	// Update library cache
	fmt.Printf("  Updating library cache...\n")
	exec.Command("ldconfig").Run()

	// Register in zapt database
	if err := registerPackage(info); err != nil {
		fmt.Fprintf(os.Stderr, "  Warning: register failed: %v\n", err)
	}

	// Show backup location if any files were backed up
	if entries, _ := os.ReadDir(backupDir); len(entries) > 0 {
		fmt.Printf("  Backup saved to: %s\n", backupDir)
	}

	return info, nil
}

// installFilesWithSafety installs files with backup and protection
func installFilesWithSafety(dataDir, backupDir string) (installed, skipped int, err error) {
	// Walk the data directory
	err = filepath.Walk(dataDir, func(path string, info os.FileInfo, err error) error {
		if err != nil {
			return err
		}

		// Get relative path
		relPath, err := filepath.Rel(dataDir, path)
		if err != nil {
			return err
		}

		// Skip the root directory
		if relPath == "." {
			return nil
		}

		// Map paths: usr/bin → bin, usr/lib → lib, etc.
		destPath := mapDebPath(relPath)

		// Check if this is a protected library
		if isProtectedLib(destPath) {
			skipped++
			return nil
		}

		// Create directories
		if info.IsDir() {
			return os.MkdirAll(destPath, info.Mode())
		}

		// Backup existing file
		if _, err := os.Stat(destPath); err == nil {
			backupPath := filepath.Join(backupDir, relPath)
			os.MkdirAll(filepath.Dir(backupPath), 0755)
			os.Rename(destPath, backupPath)
		}

		// Copy file
		if err := copyFileWithMode(path, destPath, info.Mode()); err != nil {
			return err
		}

		installed++
		return nil
	})

	return installed, skipped, err
}

// mapDebPath maps Debian paths to system paths
func mapDebPath(relPath string) string {
	// Remove leading ./
	relPath = strings.TrimPrefix(relPath, "./")

	// Map usr/* to root /*
	mappings := map[string]string{
		"usr/bin":     "bin",
		"usr/sbin":    "sbin",
		"usr/lib":     "lib",
		"usr/lib64":   "lib64",
		"usr/libexec": "libexec",
		"usr/include": "include",
		"usr/share":   "share",
		"etc":         "etc",
	}

	for prefix, replacement := range mappings {
		if strings.HasPrefix(relPath, prefix) {
			return "/" + replacement + relPath[len(prefix):]
		}
	}

	return "/" + relPath
}

// isProtectedLib checks if a path is a protected system library
func isProtectedLib(path string) bool {
	for _, lib := range protectedLibs {
		if strings.Contains(path, lib) {
			return true
		}
	}
	return false
}

// copyFileWithMode copies a file preserving permissions
func copyFileWithMode(src, dst string, mode os.FileMode) error {
	in, err := os.Open(src)
	if err != nil {
		return err
	}
	defer in.Close()

	// Create destination directory
	if err := os.MkdirAll(filepath.Dir(dst), 0755); err != nil {
		return err
	}

	out, err := os.OpenFile(dst, os.O_WRONLY|os.O_CREATE|os.O_TRUNC, mode)
	if err != nil {
		return err
	}
	defer out.Close()

	_, err = io.Copy(out, in)
	return err
}

// extractAr extracts an ar archive
func extractAr(debPath, destDir string) error {
	cmd := exec.Command("ar", "x", debPath)
	cmd.Dir = destDir
	return cmd.Run()
}

// extractDataToDir extracts data.tar.* to a specific directory
func extractDataToDir(tarPath, destDir string) error {
	f, err := os.Open(tarPath)
	if err != nil {
		return err
	}
	defer f.Close()

	var cmd *exec.Cmd
	if strings.HasSuffix(tarPath, ".gz") {
		cmd = exec.Command("tar", "xzf", "-", "-C", destDir)
	} else if strings.HasSuffix(tarPath, ".xz") {
		cmd = exec.Command("tar", "xJf", "-", "-C", destDir)
	} else if strings.HasSuffix(tarPath, ".zst") {
		cmd = exec.Command("tar", "--zstd", "xf", "-", "-C", destDir)
	} else {
		cmd = exec.Command("tar", "xf", "-", "-C", destDir)
	}

	cmd.Stdin = f
	return cmd.Run()
}

// findScript finds a script in the control archive
func findScript(dir, name string) string {
	// Look in common locations
	locations := []string{
		filepath.Join(dir, name),
		filepath.Join(dir, "control", name),
		filepath.Join(dir, "scripts", name),
	}

	for _, loc := range locations {
		if _, err := os.Stat(loc); err == nil {
			return loc
		}
	}
	return ""
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
		} else if strings.HasPrefix(line, "Architecture:") {
			info.Arch = strings.TrimSpace(strings.TrimPrefix(line, "Architecture:"))
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

// registerPackage registers a .deb package in zapt database
func registerPackage(info *DebInfo) error {
	dbDir := "/var/lib/zapt/installed"
	if err := os.MkdirAll(dbDir, 0755); err != nil {
		return err
	}

	// Write package info
	pkgFile := filepath.Join(dbDir, info.Name)
	content := fmt.Sprintf("Package: %s\nVersion: %s\nArchitecture: %s\nDescription: %s\n",
		info.Name, info.Version, info.Arch, info.Description)
	return os.WriteFile(pkgFile, []byte(content), 0644)
}
