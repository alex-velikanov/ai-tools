<?php

declare(strict_types=1);

namespace Domain\Tests;

use Domain\Customer;
use Domain\InvoiceCalculator;
use Domain\LineItem;
use Domain\TaxResolver;
use PHPUnit\Framework\TestCase;

final class InvoiceCalculatorTest extends TestCase
{
    public function testGermanCustomerWithBackfilledTaxRegionIsTaxed(): void
    {
        $customer = new Customer(id: 1, country: 'DE', taxRegion: 'DE');
        $calculator = $this->calculatorFor($customer);

        $this->assertEqualsWithDelta(285.60, $calculator->total(), 0.01);
    }

    public function testGermanCustomerPredatingTaxRegionColumnIsStillTaxed(): void
    {
        // Invoice #4821: customer predates the tax_region backfill.
        // country=DE but tax_region=null. Expected total is 285.60
        // (240.00 subtotal + 19% VAT), not 240.00.
        $customer = new Customer(id: 4821, country: 'DE', taxRegion: null);
        $calculator = $this->calculatorFor($customer);

        $this->assertEqualsWithDelta(285.60, $calculator->total(), 0.01);
    }

    private function calculatorFor(Customer $customer): InvoiceCalculator
    {
        $lineItems = [
            new LineItem('Widget', 80.00, 3),
        ];

        return new InvoiceCalculator($lineItems, $customer, new TaxResolver());
    }
}
