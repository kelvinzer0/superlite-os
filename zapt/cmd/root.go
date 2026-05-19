package cmd

import (
	"github.com/spf13/cobra"
)

var version = "dev"

func SetVersion(v string) {
	version = v
}

var rootCmd = &cobra.Command{
	Use:   "zapt",
	Short: "Multi-source package manager for SuperLite OS",
	Long: `zapt is an apt-inspired package manager for Alpine-based SuperLite OS.
It searches across Alpine repos, Debian pools, Ubuntu PPAs, and Flatpak.
It can also install .deb files directly from file manager.`,
	Version: version,
}

func Execute() error {
	return rootCmd.Execute()
}

func init() {
	rootCmd.AddCommand(queryCmd)
	rootCmd.AddCommand(installCmd)
	rootCmd.AddCommand(removeCmd)
	rootCmd.AddCommand(updateCmd)
	rootCmd.AddCommand(upgradeCmd)
	rootCmd.AddCommand(listCmd)
	rootCmd.AddCommand(infoCmd)
	rootCmd.AddCommand(searchCmd)
}
