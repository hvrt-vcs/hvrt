package hvrt

import (
	"os"
	"strconv"
)

var _DEBUG int

// init sets initial values for variables used in the package.
func init() {
	if val, present := os.LookupEnv("HVRT_DEBUG"); present && val != "" {
		int_val, err := strconv.Atoi(val)
		if err != nil {
			_DEBUG = int_val
		}
	}
}