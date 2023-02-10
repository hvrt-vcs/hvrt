package hvrt

import (
	_ "embed"
	"fmt"
	"strings"
)

//go:embed VERSION.txt
var BareVersion string
var FormattedVersion string

func init() {
	BareVersion = strings.TrimSpace(BareVersion)
	FormattedVersion = fmt.Sprintf("Havarti VCS %s", BareVersion)
}
