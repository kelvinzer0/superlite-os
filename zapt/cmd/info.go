package cmd

import (
	"fmt"

	"github.com/kelvinzer0/superlite-os/zapt/pkg"
	"github.com/spf13/cobra"
)

var infoCmd = &cobra.Command{
	Use:   "info [package]",
	Short: "Show package information",
	Args:  cobra.ExactArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		p, err := pkg.ApkInfo(args[0])
		if err != nil {
			return err
		}
		fmt.Printf("Package:      %s\n", p.Name)
		fmt.Printf("Version:      %s\n", p.Version)
		fmt.Printf("Source:       %s\n", p.Source)
		fmt.Printf("Description:  %s\n", p.Description)
		return nil
	},
}
