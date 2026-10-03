<?php

declare(strict_types=1);

namespace Domain;

final class Customer
{
    public function __construct(
        public readonly int $id,
        public readonly string $country,
        public readonly ?string $taxRegion = null,
    ) {
    }
}
