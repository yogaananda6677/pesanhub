package main

import (
	"flag"
	"fmt"
	"os"

	"pesenhub/backend/internal/contractfixture"
)

func main() {
	checkPath := flag.String("check", "", "fail when the committed fixture differs from provider types")
	writePath := flag.String("write", "", "write a deterministic fixture from provider types")
	flag.Parse()
	if (*checkPath == "") == (*writePath == "") {
		fmt.Fprintln(os.Stderr, "exactly one of -check or -write is required")
		os.Exit(2)
	}
	var err error
	if *checkPath != "" {
		err = contractfixture.Check(*checkPath)
	} else {
		err = contractfixture.Write(*writePath)
	}
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}
