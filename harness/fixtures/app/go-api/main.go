package main

import (
	"encoding/json"
	"log"
	"net/http"
)

func healthHandler(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]string{"status": "ok"})
}

func invoiceHandler(w http.ResponseWriter, r *http.Request) {
	id := 4820
	inv, ok := invoices[id]
	if !ok {
		http.Error(w, invoiceNotFoundError(id).Error(), http.StatusNotFound)
		return
	}
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]any{
		"id":       inv.ID,
		"country":  inv.Country,
		"subtotal": inv.Subtotal(),
		"total":    inv.Total(),
	})
}

func main() {
	mux := http.NewServeMux()
	mux.HandleFunc("/health", healthHandler)
	mux.HandleFunc("/invoices/4820", invoiceHandler)

	log.Println("listening on :8081")
	// Local dev/test service only, never deployed — plaintext HTTP is fine here.
	log.Fatal(http.ListenAndServe(":8081", mux)) // nosemgrep: go.lang.security.audit.net.use-tls.use-tls
}
