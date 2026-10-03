<?php

declare(strict_types=1);

namespace Domain;

final class TaxResolver
{
    /** @var array<string, float> */
    private array $rates = [
        'DE' => 0.19,
        'FR' => 0.20,
        'US' => 0.0,
    ];

    public function rateFor(Customer $customer): float
    {
        return $this->rates[$customer->taxRegion] ?? 0.0;
    }
}
