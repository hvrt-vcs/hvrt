package hvrt

import (
	_ "embed"
	"fmt"
	"strings"
)

//go:embed SEMANTIC_VERSION.txt
var SemanticVersion string
var FormattedVersion string

func init() {
	SemanticVersion = strings.TrimSpace(SemanticVersion)
	FormattedVersion = fmt.Sprintf("Havarti VCS %s", SemanticVersion)
}
