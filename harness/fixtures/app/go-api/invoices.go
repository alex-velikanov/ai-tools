package main

import "fmt"

type LineItem struct {
	Description string
	UnitPrice   float64
	Quantity    int
}

func (li LineItem) Total() float64 {
	return li.UnitPrice * float64(li.Quantity)
}

type Invoice struct {
	ID        int
	Country   string
	LineItems []LineItem
}

var taxRates = map[string]float64{
	"DE": 0.19,
	"FR": 0.20,
	"US": 0.0,
}

func (inv Invoice) Subtotal() float64 {
	var sum float64
	for _, li := range inv.LineItems {
		sum += li.Total()
	}
	return sum
}

func (inv Invoice) Total() float64 {
	subtotal := inv.Subtotal()
	rate := taxRates[inv.Country]
	return subtotal + subtotal*rate
}

var invoices = map[int]Invoice{
	4820: {
		ID:      4820,
		Country: "DE",
		LineItems: []LineItem{
			{Description: "Widget", UnitPrice: 80.00, Quantity: 3},
		},
	},
}

func invoiceNotFoundError(id int) error {
	return fmt.Errorf("invoice %d not found", id)
}
