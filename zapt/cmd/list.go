package cmd

import (
	"fmt"
	"os"
	"text/tabwriter"

	"github.com/kelvinzer0/superlite-os/zapt/pkg"
	"github.com/spf13/cobra"
)

var listCmd = &cobra.Command{
	Use:   "list",
	Short: "List packages",
	Long:  "List installed or available packages",
	RunE: func(cmd *cobra.Command, args []string) error {
		available, _ := cmd.Flags().GetBool("available")
		if available {
			return listAvailable()
		}
		return listInstalled()
	},
}

func init() {
	listCmd.Flags().BoolP("available", "a", false, "List available packages")
}

func listInstalled() error {
	pkgs, err := pkg.ApkListInstalled()
	if err != nil {
		return err
	}

	w := tabwriter.NewWriter(os.Stdout, 0, 0, 2, ' ', 0)
	fmt.Fprintf(w, "PACKAGE\tVERSION\tDESCRIPTION\n")
	for _, p := range pkgs {
		fmt.Fprintf(w, "%s\t%s\t%s\n", p.Name, p.Version, p.Description)
	}
	w.Flush()

	fmt.Printf("\n%d packages installed\n", len(pkgs))
	return nil
}

func listAvailable() error {
	// List all available packages (not installed)
	cmd := []string{"apk", "list", "-a"}
	out, err := pkg.RunCommand(cmd[0], cmd[1:]...)
	if err != nil {
		return err
	}
	fmt.Print(string(out))
	return nil
}
