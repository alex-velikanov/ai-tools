<?php

declare(strict_types=1);

namespace Domain;

final class LineItem
{
    public function __construct(
        public readonly string $description,
        public readonly float $unitPrice,
        public readonly int $quantity,
    ) {
    }

    public function total(): float
    {
        return $this->unitPrice * $this->quantity;
    }
}
