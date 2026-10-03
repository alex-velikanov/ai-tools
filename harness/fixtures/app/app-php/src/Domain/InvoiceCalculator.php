<?php

declare(strict_types=1);

namespace Domain;

final class InvoiceCalculator
{
    /** @param LineItem[] $lineItems */
    public function __construct(
        private readonly array $lineItems,
        private readonly Customer $customer,
        private readonly TaxResolver $taxResolver,
    ) {
    }

    public function subtotal(): float
    {
        return array_sum(array_map(
            static fn (LineItem $item): float => $item->total(),
            $this->lineItems,
        ));
    }

    public function total(): float
    {
        $subtotal = $this->subtotal();
        $rate = $this->taxResolver->rateFor($this->customer);

        return $subtotal + ($subtotal * $rate);
    }
}
