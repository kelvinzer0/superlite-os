package cmd

import (
	"fmt"

	"github.com/kelvinzer0/superlite-os/zapt/pkg"
	"github.com/spf13/cobra"
)

var updateCmd = &cobra.Command{
	Use:   "update",
	Short: "Update package indices",
	Long:  "Update package indices from all configured sources",
	RunE: func(cmd *cobra.Command, args []string) error {
		fmt.Println("Updating package indices...")
		if err := pkg.ApkUpdate(); err != nil {
			return err
		}
		fmt.Println("Done.")
		return nil
	},
}
