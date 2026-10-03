package main

import "testing"

func TestInvoiceTotalAppliesTax(t *testing.T) {
	inv := Invoice{
		ID:      4820,
		Country: "DE",
		LineItems: []LineItem{
			{Description: "Widget", UnitPrice: 80.00, Quantity: 3},
		},
	}

	got := inv.Total()
	want := 285.60

	if diff := got - want; diff > 0.01 || diff < -0.01 {
		t.Errorf("Total() = %.2f, want %.2f", got, want)
	}
}

func TestInvoiceTotalWithUnknownCountryIsUntaxed(t *testing.T) {
	inv := Invoice{
		ID:      1,
		Country: "ZZ",
		LineItems: []LineItem{
			{Description: "Widget", UnitPrice: 100.00, Quantity: 1},
		},
	}

	if got := inv.Total(); got != 100.00 {
		t.Errorf("Total() = %.2f, want 100.00", got)
	}
}
