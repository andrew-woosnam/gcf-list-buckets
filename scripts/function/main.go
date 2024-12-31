package function

import (
	"fmt"
	"net/http"
)

// HelloWorld is a basic Cloud Function.
func HelloWorld(w http.ResponseWriter, r *http.Request) {
	fmt.Fprintln(w, "Hello, World!")
}
