package cmd

import (
	"fmt"
	"os"
	"strings"

	"github.com/kelvinzer0/superlite-os/zapt/pkg"
	"github.com/spf13/cobra"
)

var installCmd = &cobra.Command{
	Use:   "install [package or .deb file]",
	Short: "Install a package or .deb file",
	Long: `Install a package from Alpine repo or a .deb file directly.
Examples:
  zapt install firefox-esr
  zapt install ./package.deb
  zapt install https://example.com/package.deb`,
	Args: cobra.MinimumNArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		for _, arg := range args {
			if err := installPackage(arg); err != nil {
				return err
			}
		}
		return nil
	},
}

func installPackage(target string) error {
	// Check if it's a .deb file (local or URL)
	if strings.HasSuffix(target, ".deb") {
		return installDeb(target)
	}

	// Otherwise treat as Alpine package name
	return pkg.ApkInstall(target)
}

func installDeb(target string) error {
	// Download if URL
	if strings.HasPrefix(target, "http://") || strings.HasPrefix(target, "https://") {
		fmt.Printf("Downloading %s...\n", target)
		localPath, err := pkg.DownloadFile(target)
		if err != nil {
			return fmt.Errorf("download: %w", err)
		}
		defer os.Remove(localPath)
		target = localPath
	}

	// Verify .deb file
	if err := pkg.VerifyDeb(target); err != nil {
		return fmt.Errorf("invalid .deb file: %w", err)
	}

	// Extract and install
	fmt.Printf("Installing %s...\n", target)
	info, err := pkg.ExtractDeb(target)
	if err != nil {
		return fmt.Errorf("extract .deb: %w", err)
	}

	fmt.Printf("Installed %s %s\n", info.Name, info.Version)
	return nil
}
