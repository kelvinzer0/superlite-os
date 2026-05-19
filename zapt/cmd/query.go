package cmd

import (
	"fmt"
	"os"
	"text/tabwriter"

	"github.com/kelvinzer0/superlite-os/zapt/pkg"
	"github.com/spf13/cobra"
)

var queryCmd = &cobra.Command{
	Use:   "query [search term]",
	Short: "Search packages across all sources",
	Long: `Search for packages across Alpine repos, Debian pools, Ubuntu PPAs, and Flatpak.
Example: zapt query firefox`,
	Args: cobra.MinimumNArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		query := args[0]
		return runQuery(query)
	},
}

func runQuery(query string) error {
	sources, err := pkg.LoadSources("")
	if err != nil {
		return fmt.Errorf("load sources: %w", err)
	}

	var allPkgs []pkg.Package

	// Search each source type
	for _, src := range sources {
		switch src.Type {
		case "alpine":
			pkgs, err := pkg.ApkSearch(query)
			if err != nil {
				fmt.Fprintf(os.Stderr, "Warning: alpine search failed: %v\n", err)
				continue
			}
			allPkgs = append(allPkgs, pkgs...)

		case "debian":
			pkgs, err := pkg.DebianSearch(src, query)
			if err != nil {
				fmt.Fprintf(os.Stderr, "Warning: debian search failed: %v\n", err)
				continue
			}
			allPkgs = append(allPkgs, pkgs...)

		case "ppa":
			pkgs, err := pkg.PPASearch(src, query)
			if err != nil {
				fmt.Fprintf(os.Stderr, "Warning: ppa search failed: %v\n", err)
				continue
			}
			allPkgs = append(allPkgs, pkgs...)

		case "flatpak":
			pkgs, err := pkg.FlatpakSearch(query)
			if err != nil {
				fmt.Fprintf(os.Stderr, "Warning: flatpak search failed: %v\n", err)
				continue
			}
			allPkgs = append(allPkgs, pkgs...)
		}
	}

	if len(allPkgs) == 0 {
		fmt.Printf("No packages found for '%s'\n", query)
		return nil
	}

	// Print results as table
	w := tabwriter.NewWriter(os.Stdout, 0, 0, 2, ' ', 0)
	fmt.Fprintf(w, "SOURCE\tPACKAGE\tVERSION\tDESCRIPTION\n")
	for _, p := range allPkgs {
		installed := ""
		if p.Installed {
			installed = " [installed]"
		}
		fmt.Fprintf(w, "%s\t%s\t%s\t%s%s\n", p.Source, p.Name, p.Version, p.Description, installed)
	}
	w.Flush()

	fmt.Printf("\n%d packages found\n", len(allPkgs))
	return nil
}
