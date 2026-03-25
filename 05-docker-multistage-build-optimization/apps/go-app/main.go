package main

import (
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
	"runtime"
)

type response struct {
	Message   string `json:"message"`
	Hostname  string `json:"hostname"`
	GoVersion string `json:"goVersion"`
	GOOS      string `json:"goos"`
}

type healthResponse struct {
	Status string `json:"status"`
}

func rootHandler(w http.ResponseWriter, r *http.Request) {
	hostname, _ := os.Hostname()
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(response{
		Message:   "Hello from Go multi-stage build!",
		Hostname:  hostname,
		GoVersion: runtime.Version(),
		GOOS:      runtime.GOOS,
	})
}

func healthHandler(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(healthResponse{Status: "ok"})
}

func main() {
	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}

	http.HandleFunc("/", rootHandler)
	http.HandleFunc("/health", healthHandler)

	fmt.Printf("Go server listening on :%s (uid=%d)\n", port, os.Getuid())
	log.Fatal(http.ListenAndServe(":"+port, nil))
}
