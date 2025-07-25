#!/usr/bin/env nu
# Digital Consultant ERP Demo - Building a Complete Business Partner
# 
# This demo shows how to create a business partner with full context:
# - Basic information and attributes
# - Business roles via tags
# - Addresses with structured JSON data
# - Custom data in record_json
#
# To run: nu -l -c "source demo/digital-consultant-erp.nu"

use ../modules *

print "============================================"
print "=== Building a Complete Business Partner ==="
print "============================================"
print ""

# Step 1: Create the business partner
print "1. Creating business partner..."
print ""

# Create a client company with general information
let client = (bp new "ACME Corporation" 
    --type-search-key "ORGANIZATION" 
    --description "Enterprise retail company - our largest client" 
    --json '{
        "tax_id": "12-3456789",
        "duns_number": "123456789",
        "website": "www.acme-corp.com",
        "industry": "Retail",
        "annual_revenue": "500M",
        "employee_count": 2500,
        "primary_contact": "John Smith",
        "primary_phone": "+1-555-123-4567",
        "primary_email": "john.smith@acme-corp.com"
    }')

print $"✓ Created business partner: ($client.name) with UUID: ($client.uu)"
print ""

# Step 2: Add business roles via tags
print "2. Assigning business roles..."
print ""

# Mark as customer with customer-specific details
let customer_tag = $client | .append tag --type-search-key "BP_CUSTOMER" --json '{
    "payment_terms": "Net 30",
    "payment_terms_days": 30,
    "credit_limit": 100000,
    "currency": "USD",
    "price_list": "STANDARD",
    "tax_exempt": false
}'
print "✓ Tagged as BP_CUSTOMER with payment terms and credit limit"
print ""

# Also mark as vendor (they occasionally provide services to us)
let vendor_tag = $client | .append tag --type-search-key "BP_VENDOR" --json '{
    "payment_terms": "Net 45",
    "payment_terms_days": 45,
    "our_account_number": "ACCT-0001",
    "payment_method": "ACH",
    "currency": "USD",
    "preferred_vendor": true
}'
print "✓ Tagged as BP_VENDOR with vendor payment terms"
print ""

# Step 3: Add business roles via tags
print "3. Assigning contacts..."
print ""

# Add a contact
$client | contact new "Julie Smith" --json '{
        "primary_phone": "+1-555-123-4567",
        "primary_email": "julie.smith@acme-corp.com"
    }'
print "✓ Added Julie Smith as a contact"
print ""

# Step 4: Add addresses
print "4. Adding addresses..."
print ""

# Headquarters address - using structured JSON
let hq_address = $client | .append address --json '{
    "address1": "123 Main Street",
    "address2": "Suite 1000",
    "city": "New York",
    "region": "NY",
    "postal": "10001",
    "country": "US"
}'
print "✓ Added headquarters address"
print ""

# Billing address - using structured JSON
let billing_address = $client | .append address --json '{
    "address1": "456 Finance Blvd",
    "city": "Jersey City",
    "region": "NJ",
    "postal": "07302",
    "country": "US"
}'
print "✓ Added billing address"
print ""

# Shipping address - using structured JSON
let shipping_address = $client | .append address --json '{
    "address1": "789 Warehouse Way",
    "city": "Newark",
    "region": "NJ",
    "postal": "07102",
    "country": "US"
}'
print "✓ Added shipping address"
print ""

# Step 5: Show the complete business partner profile
print "================================"
print "=== Business Partner Profile ==="
print "================================"
print ""

# Get BP with details and display as a record
print "Business Partner: returned from get"
$client | bp get | print
print ""

# Show JSON attributes as a formatted table
print "Company Details:"
let bp_detail = ($client | bp get )
$bp_detail.record_json | print
print ""

# Show tags as a table
print "Business Roles & Classifications:"
$client | bp get | tags | select type_enum description created | print
print ""

# Show addresses with their JSON data
print "Addresses:"
$client | bp get | tags | get tags | where {$in.search_key =~ ADDRESS} | table -e | print
print ""

print "========================================="
print "=== Complete Business Partner Created ==="
print "========================================="
print ""

print "This business partner now has:"
print "- Core company information with legal and financial details"
print "- Multiple business role tags (customer and vendor)"
print "- Multiple addresses for different purposes (HQ, billing, shipping)"
print ""

# Step 6: Create items for invoicing
print "======================================="
print "=== Creating items for invoicing... ==="
print "======================================="
print ""

# Note: Item types don't have JSON schemas yet, so we're using common-sense fields
let consultation = (item new "Hourly Consultation" 
    --type-search-key "SERVICE"
    --description "Professional consulting services")
print $"✓ Created item: ($consultation.name)"

let project_fee = (item new "Project Setup Fee"
    --type-search-key "SERVICE"
    --description "One-time project initialization fee")
print $"✓ Created item: ($project_fee.name)"
print ""

# Step 7: Create an invoice for the client
print "======================================"
print "=== Creating invoice for client... ==="
print "======================================"
print ""

# Note: Invoice types don't have JSON schemas yet, so we're using practical fields
let invoice = ($client | invoice new "INV-2025-001"
    --type-search-key "SALES_STANDARD"
    --description "January 2025 Consulting Services")
print $"✓ Created invoice: ($invoice.search_key) for ($client.name)"
print ""

# Step 8: Add line items to the invoice
print "======================================="
print "=== Adding line items to invoice... ==="
print "======================================="
print ""

# Add consultation hours - using the enhanced syntax
let line1 = ($invoice | invoice line new "Hourly Consultation" --qty 40 --price 150)
print "✓ Added 40 hours of consultation @ $150/hour"

# Add project setup fee
let line2 = ($invoice | invoice line new "Project Setup Fee" --qty 1 --price 2500)
print "✓ Added project setup fee @ $2,500"

# Add a discount line (without item reference)
let line3 = ($invoice | invoice line new --description "Early payment discount (5%)" 
    --type-search-key "DISCOUNT" 
    --json '{"discount_amount": -425, "discount_basis": "subtotal"}')
print "✓ Added early payment discount"
print ""

# Step 9: Show invoice summary
print "======================="
print "=== Invoice Summary ==="
print "======================="
print ""

# Display invoice header
print "Invoice Details:"
$invoice | invoice get | select search_key description type_enum created | print
print ""

# Display linked business partner
print $"Customer: ($client.name)"
print ""

# Display line items with natural table formatting
print "Line Items:"
$invoice | invoice line list | select search_key description record_json | table -e | print
print ""

# Show totals by using the already-parsed JSON data
print "Invoice Totals:"
let lines = ($invoice | invoice line list)
let line_totals = ($lines | each {|line| 
    let json = $line.record_json
    {
        line: $line.search_key
        amount: (if ($json.price_extended? | is-not-empty) { $json.price_extended } else if ($json.discount_amount? | is-not-empty) { $json.discount_amount } else { 0 })
    }
})

let subtotal = ($line_totals | where amount > 0 | get amount | math sum)
let discount = ($line_totals | where amount < 0 | get amount | math sum | math abs)
let total = ($subtotal - $discount)

[
    [Description Amount];
    ["Subtotal" $subtotal]
    ["Discount" $"($discount)"]
    ["Total" $total]
] | print
print ""

print "=================================="
print "=== Complete BP → Invoice Flow ==="
print "=================================="
print ""

print "This demonstration showed:"
print "- Creating a business partner with full context"
print "- Setting up service items for invoicing"
print "- Creating an invoice linked to the BP"
print "- Adding line items with automatic item lookup by name"
print "- Using the new --qty and --price parameters"
print "- Line numbers auto-generated as 10, 20, 30"
print ""
print "Key Features Demonstrated:"
print "- Item lookup by name or search_key"
print "- Automatic price calculations (price_extended)"
print "- JSON storage for line item details"
print "- Type-specific line items (ITEM vs DISCOUNT)"
print ""
