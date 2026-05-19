package cmd

import (
	"fmt"

	"github.com/kelvinzer0/superlite-os/zapt/pkg"
	"github.com/spf13/cobra"
)

var upgradeCmd = &cobra.Command{
	Use:   "upgrade",
	Short: "Upgrade all packages",
	Long:  "Upgrade all installed packages to their latest versions",
	RunE: func(cmd *cobra.Command, args []string) error {
		fmt.Println("Upgrading packages...")
		if err := pkg.ApkUpgrade(); err != nil {
			return err
		}
		fmt.Println("Done.")
		return nil
	},
}
