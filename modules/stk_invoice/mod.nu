# STK Invoice Module
# This module provides commands for working with stk_invoice and stk_invoice_line tables

# Module Constants
const STK_SCHEMA = "api"
const STK_INVOICE_TABLE_NAME = "stk_invoice"
const STK_INVOICE_LINE_TABLE_NAME = "stk_invoice_line"
const STK_INVOICE_COLUMNS = [search_key, description, is_template, is_valid, record_json]
const STK_INVOICE_LINE_COLUMNS = [search_key, description, is_valid, record_json]

# Invoice module overview
export def "invoice" [] {
    r#'Invoices record sales and purchase transactions with business partners.
Invoices contain header information and line items for products/services.

Templates enable reusable invoice structures for recurring billing.
Invoices integrate with business partners and financial reporting.

Type 'invoice <tab>' to see available commands.
'#
}

# Create a new invoice with specified search key and type
#
# This is the primary way to create invoices in the chuck-stack system.
# Invoices represent sales transactions (customer invoices) or purchase
# transactions (vendor bills) with line items for products and services.
# The system automatically assigns default values via triggers if type is not specified.
#
# Accepts piped input:
#   string - UUID of business partner for this invoice (required)
#   record - A record containing a 'uu' field
#   table - A single-row table from commands like 'bp list | where'
#
# Examples:
#   $bp_uuid | invoice new "INV-2024-001"
#   bp list | where name == "ACME Corp" | invoice new "INV-2024-002" --description "Monthly consulting services"
#   bp list | first | invoice new "INV-2024-003" --type-search-key "SALES_STANDARD"
#   $customer_uuid | invoice new "DEP-2024-001" --type-search-key "SALES_DEPOSIT" --description "50% project deposit"
#   $vendor_uuid | invoice new "BILL-2024-001" --type-search-key "PURCHASE_STANDARD"
#   $bp_uuid | invoice new "TEMPLATE-001" --template --json '{"payment_terms": "Net 30", "tax_rate": 0.08}'
#   
#   # Interactive examples:
#   $bp_uuid | invoice new "INV-2024-004" --type-search-key SALES_STANDARD --interactive
#   bp list | first | invoice new "BILL-2024-002" --interactive --description "Equipment purchase"
#
# Returns: The UUID and search_key of the newly created invoice record
# Note: Uses chuck-stack conventions for automatic entity and type assignment
export def "invoice new" [
    search_key: string              # The unique identifier/number of the invoice to create
    --type-uu: string              # Type UUID (use 'invoice types' to find UUIDs)
    --type-search-key: string      # Type search key (unique identifier for type)
    --description(-d): string      # Optional description of the invoice
    --template                     # Mark this invoice as a template
    --entity-uu(-e): string        # Optional entity UUID (uses default if not provided)
    --json(-j): string             # Optional JSON data to store in record_json field
    --interactive                  # Interactively build JSON data using the type's schema
] {
    # Extract business partner UUID from piped input
    let bp_uuid = ($in | extract-single-uu --error-msg "Business Partner UUID is required via piped input")
    
    # Validate the business partner exists
    psql validate-uuid-table $bp_uuid "stk_business_partner"
    
    # Resolve type using utility function
    let type_record = (resolve-type --schema $STK_SCHEMA --table $STK_INVOICE_TABLE_NAME --type-uu $type_uu --type-search-key $type_search_key)
    
    # Handle JSON input - one line replaces multiple lines of boilerplate
    let record_json = (resolve-json $json $interactive $type_record)
    
    # Build parameters record internally - eliminates cascading if/else logic
    let params = {
        search_key: $search_key
        type_uu: ($type_record.uu? | default null)
        description: ($description | default null)
        is_template: ($template | default false)
        stk_entity_uu: ($entity_uu | default null)
        stk_business_partner_uu: $bp_uuid
        record_json: $record_json  # Already a JSON string from resolve-json
    }
    
    # Single call with all parameters - no more cascading logic
    psql new-record $STK_SCHEMA $STK_INVOICE_TABLE_NAME $params
}

# List the 10 most recent invoices from the chuck-stack system
#
# Displays invoices in chronological order (newest first) to help you
# monitor recent transactions, track invoice status, or review billing history.
# This is typically your starting point for invoice investigation.
# Use the returned UUIDs with other invoice commands for detailed work.
# Type information is always included for all invoices.
#
# Accepts piped input: none
#
# Examples:
#   invoice list
#   invoice list | where is_template == true
#   invoice list | where type_enum == "SALES_STANDARD"
#   invoice list | where is_revoked == false
#   invoice list | select search_key description | table
#   invoice list | where search_key =~ "INV"
#   invoice list | lines  # Add lines column with all invoice line items
#   invoice list | lines | where {|i| ($i.lines | length) > 5}  # Invoices with more than 5 lines
#   invoice list | lines | get lines.0 | flatten  # Get all line items from all invoices
#
# Create a useful alias:
#   def il [] { invoice list | lines | select search_key description lines }  # Concise invoice view with lines
#
# Using elaborate to resolve foreign key references:
#   invoice list | elaborate                                          # Resolve with default columns
#   invoice list | elaborate search_key stk_business_partner_uu       # Show business partner details
#   invoice list | elaborate --detail | select search_key stk_business_partner_uu_resolved.name  # BP names
#
# Returns: search_key, description, is_template, is_valid, created, updated, is_revoked, uu, table_name, type_enum, type_name, type_description
# Note: Only shows the 10 most recent invoices - use direct SQL for larger queries
export def "invoice list" [
    --all(-a)     # Include revoked invoices
] {
    # Build complete arguments array including flags
    let args = [$STK_SCHEMA, $STK_INVOICE_TABLE_NAME] | append $STK_INVOICE_COLUMNS
    
    # Add --all flag to args if needed
    let args = if $all { $args | append "--all" } else { $args }
    
    # Execute query
    psql list-records ...$args
}

# Retrieve a specific invoice by its UUID
#
# Fetches complete details for a single invoice when you need to
# inspect its contents, verify its state, or extract specific
# data. Use this when you have a UUID from invoice list or from
# other system outputs. Type information is always included.
#
# Accepts piped input:
#   string - The UUID of the invoice to retrieve
#   record - A record containing a 'uu' field
#   table - A single-row table from commands like 'invoice list | where'
#
# Examples:
#   "12345678-1234-5678-9012-123456789abc" | invoice get
#   invoice list | get uu.0 | invoice get
#   invoice list | where search_key == "INV-2024-001" | invoice get
#   invoice list | first | invoice get
#   $invoice_uuid | invoice get | get description
#   $invoice_uuid | invoice get | get type_enum
#   $uu | invoice get | if $in.is_revoked { print "Invoice was revoked" }
#   $invoice_uuid | invoice get | lines  # Get invoice with all its line items
#   $invoice_uuid | invoice get | lines | get lines.0  # Extract just the lines
#   invoice get --uu "12345678-1234-5678-9012-123456789abc"
#   invoice get --uu $my_invoice_uuid
#
# Returns: search_key, description, is_template, is_valid, created, updated, is_revoked, uu, table_name, type_enum, type_name, and other type information
# Error: Returns empty result if UUID doesn't exist
export def "invoice get" [
    --uu: string  # UUID as a parameter instead of piped input
] {
    # Extract UUID from piped input or --uu parameter
    let uu = ($in | extract-uu-with-param $uu)
    
    psql get-record $STK_SCHEMA $STK_INVOICE_TABLE_NAME $STK_INVOICE_COLUMNS $uu
}

# Revoke an invoice by setting its revoked timestamp
#
# This performs a soft delete by setting the revoked column to now().
# Once revoked, invoices are considered cancelled and won't appear in 
# normal selections. Use this instead of hard deleting to maintain
# audit trails and data integrity in the chuck-stack system.
#
# Accepts piped input: 
#   string - The UUID of the invoice to revoke
#   record - A record containing a 'uu' field
#   table - A single-row table from commands like 'invoice list | where'
#
# Examples:
#   invoice list | where search_key == "cancelled-invoice" | get uu.0 | invoice revoke
#   invoice list | where search_key == "cancelled-invoice" | invoice revoke
#   invoice list | where is_template == true | each { |row| $row.uu | invoice revoke }
#   "12345678-1234-5678-9012-123456789abc" | invoice revoke
#   invoice revoke --uu "12345678-1234-5678-9012-123456789abc"
#   invoice revoke --uu $cancelled_invoice_uuid
#
# Returns: uu, search_key, revoked timestamp, and is_revoked status
# Error: Command fails if UUID doesn't exist or invoice is already revoked
export def "invoice revoke" [
    --uu: string  # UUID as a parameter instead of piped input
] {
    # Extract UUID from piped input or --uu parameter
    let target_uuid = ($in | extract-uu-with-param $uu)
    
    psql revoke-record $STK_SCHEMA $STK_INVOICE_TABLE_NAME $target_uuid
}


# List available invoice types using generic psql list-types command
#
# Shows all available invoice types that can be used when creating invoices.
# Use this to see valid type options and their descriptions before
# creating new invoices with specific types.
#
# Accepts piped input: none
#
# Examples:
#   invoice types
#   invoice types | where type_enum == "SALES_STANDARD"
#   invoice types | where is_default == true
#   invoice types | select type_enum name is_default | table
#
# Returns: uu, type_enum, name, description, is_default, created for all invoice types
# Note: Uses the generic psql list-types command for consistency across chuck-stack
export def "invoice types" [] {
    psql list-types $STK_SCHEMA $STK_INVOICE_TABLE_NAME
}



# Add a line item to an invoice by referencing an item or creating custom line
#
# Creates a new invoice line (product, service, discount, or description) 
# associated with a specific invoice. Invoice lines are the detailed items 
# that make up an invoice and can reference stk_item for product/service details.
# Line numbers are auto-generated (10, 20, 30...) if not explicitly provided.
#
# Accepts piped input:
#   string - The UUID of the invoice (required)
#   record - A record containing a 'uu' field
#   table - A single-row table from commands like 'invoice list | where'
#
# Examples:
#   # Add item by search_key with quantity and price
#   $invoice_uuid | invoice line new "WIDGET-001" --qty 5 --price 29.99
#   $invoice_uuid | invoice line new "SERVICE-CONSULT" --qty 40 --price 150
#   
#   # Add custom line without item reference
#   $invoice_uuid | invoice line new --description "Custom service charge" --qty 1 --price 100
#   $invoice_uuid | invoice line new --description "Early payment discount" --type-search-key "DISCOUNT" --price -50
#   
#   # Specify custom line number
#   $invoice_uuid | invoice line new "WIDGET-001" --line-number "15" --qty 2 --price 45.50
#   
#   # Full JSON control
#   $invoice_uuid | invoice line new --json '{"quantity": 40, "price_unit": 150, "price_extended": 6000}'
#   
#   # Interactive examples:
#   $invoice_uuid | invoice line new --type-search-key ITEM --interactive
#   $invoice_uuid | invoice line new "WIDGET-001" --interactive
#
# Returns: The UUID and search_key of the newly created invoice line record
# Note: Line numbers auto-generate as 10, 20, 30... when not specified
export def "invoice line new" [
    item_search_key?: string        # Optional item search key to find and add to invoice
    --line-number(-l): string      # Optional line number (defaults to next available: 10, 20, 30...)
    --qty(-q): float               # Quantity for this line item
    --price(-p): float             # Unit price for this line item
    --type-uu: string              # Type UUID (use 'invoice line types' to find UUIDs)
    --type-search-key: string      # Type search key (unique identifier for type)
    --description(-d): string      # Optional description of the line
    --json(-j): string             # Optional JSON data to store in record_json field
    --interactive                  # Interactively build JSON data using the type's schema
] {
    # Extract UUID from piped input
    let invoice_uu = ($in | extract-single-uu --error-msg "Invoice UUID is required via piped input")
    
    # Look up item if search_key provided
    let item_info = if ($item_search_key | is-not-empty) {
        let item_result = (item list | where {|it| $it.search_key == $item_search_key or $it.name == $item_search_key})
        if ($item_result | is-empty) {
            error make {msg: $"Item with search_key or name '($item_search_key)' not found"}
        }
        $item_result | first
    } else {
        null
    }
    
    # Extract item UUID if found
    let item_uu = if ($item_info != null) { $item_info.uu } else { null }
    
    # Use item description if no description provided and item was found
    let final_description = if ($description | is-empty) and ($item_info != null) {
        $item_info.description | default $item_info.name
    } else {
        $description
    }
    
    # Resolve type using utility function
    let type_record = (resolve-type --schema $STK_SCHEMA --table $STK_INVOICE_LINE_TABLE_NAME --type-uu $type_uu --type-search-key $type_search_key)
    
    # Build JSON with quantity and price if provided
    let json_obj = if ($json | is-not-empty) {
        # User provided explicit JSON
        $json
    } else if ($qty != null) or ($price != null) {
        # Build JSON from parameters
        mut obj = {}
        if ($qty != null) { $obj = ($obj | insert quantity $qty) }
        if ($price != null) { $obj = ($obj | insert price_unit $price) }
        if ($qty != null) and ($price != null) {
            $obj = ($obj | insert price_extended ($qty * $price))
        }
        $obj | to json
    } else {
        null
    }
    
    # Handle JSON input - one line replaces multiple lines of boilerplate
    let record_json = (resolve-json $json_obj $interactive $type_record)
    
    # Build parameters record internally - eliminates cascading if/else logic
    let params = {
        search_key: ($line_number | default null)  # Will auto-generate if null
        type_uu: ($type_record.uu? | default null)
        description: ($final_description | default null)
        stk_item_uu: $item_uu
        record_json: $record_json  # Already a JSON string from resolve-json
    }
    
    # Single call with all parameters - no more cascading logic
    psql new-line-record $STK_SCHEMA $STK_INVOICE_LINE_TABLE_NAME $invoice_uu $params
}

# List invoice lines for a specific invoice
#
# Displays all line items associated with an invoice to help you
# view invoice breakdown, track products/services, or manage billing details.
# Shows the most recent lines first for easy review.
#
# Accepts piped input:
#   string - The UUID of the invoice (required)
#   record - A record containing a 'uu' field
#   table - A single-row table from commands like 'invoice list | where'
#
# Examples:
#   $invoice_uuid | invoice line list
#   invoice list | where search_key == "INV-2024-001" | invoice line list
#   $invoice_uuid | invoice line list | select name description | table
#   $invoice_uuid | invoice line list | where search_key =~ "LINE"
#   $invoice_uuid | invoice line list | elaborate  # Resolve all UUID references
#   $invoice_uuid | invoice line list | elaborate | get type_uu_resolved  # See line type details
#
# Returns: search_key, description, is_valid, created, updated, is_revoked, uu, table_name
# Note: By default shows only active lines, use --all to include revoked
export def "invoice line list" [
    --all(-a)  # Include revoked invoice lines
] {
    # Extract UUID from piped input
    let invoice_uu = ($in | extract-single-uu --error-msg "Invoice UUID is required via piped input")
    
    # Build arguments array
    let args = [$STK_SCHEMA, $STK_INVOICE_LINE_TABLE_NAME, $invoice_uu] | append $STK_INVOICE_LINE_COLUMNS
    
    # Add --all flag if needed
    let args = if $all { $args | append "--all" } else { $args }
    
    psql list-line-records ...$args
}

# Retrieve a specific invoice line by its UUID
#
# Fetches complete details for a single invoice line when you need to
# inspect its contents, verify its state, or extract specific
# data. Use this when you have a UUID from invoice line list or from
# other system outputs. Type information is always included.
#
# Accepts piped input: 
#   string - The UUID of the invoice line to retrieve
#   record - A record containing a 'uu' field
#   table - A single-row table from commands like 'invoice line list | where'
#
# Examples:
#   $invoice_uuid | invoice line list | get uu.0 | invoice line get
#   $invoice_uuid | invoice line list | where search_key == "LINE-002" | invoice line get
#   $invoice_uuid | invoice line list | first | invoice line get
#   $line_uuid | invoice line get | get description
#   $line_uuid | invoice line get | get type_enum
#   "12345678-1234-5678-9012-123456789abc" | invoice line get
#   invoice line get --uu "12345678-1234-5678-9012-123456789abc"
#   invoice line get --uu $my_line_uuid
#
# Returns: search_key, description, is_valid, created, updated, is_revoked, uu, type_enum, type_name, and other type information
# Error: Returns empty result if UUID doesn't exist
export def "invoice line get" [
    --uu: string  # UUID as a parameter instead of piped input
] {
    # Extract UUID from piped input or --uu parameter
    let target_uuid = if ($in | is-empty) {
        if ($uu | is-empty) {
            error make {msg: "Invoice line UUID is required via piped input or --uu parameter."}
        }
        $uu
    } else {
        ($in | extract-single-uu)
    }
    
    psql get-record $STK_SCHEMA $STK_INVOICE_LINE_TABLE_NAME $STK_INVOICE_LINE_COLUMNS $target_uuid
}

# Revoke an invoice line by setting its revoked timestamp
#
# This performs a soft delete by setting the revoked column to now().
# Once revoked, invoice lines are considered inactive and won't appear in 
# normal selections. Use this instead of hard deleting to maintain
# audit trails and data integrity in the chuck-stack system.
#
# Accepts piped input: 
#   string - The UUID of the invoice line to revoke
#   record - A record containing a 'uu' field
#   table - A single-row table from commands like 'invoice line list | where'
#   list - Multiple UUIDs to revoke in bulk
#
# Examples:
#   $invoice_uuid | invoice line list | where search_key == "obsolete-item" | get uu.0 | invoice line revoke
#   $invoice_uuid | invoice line list | where search_key == "obsolete-item" | invoice line revoke
#   $invoice_uuid | invoice line list | where created < (date now) - 30day | get uu | invoice line revoke
#   "12345678-1234-5678-9012-123456789abc" | invoice line revoke
#   [$uuid1, $uuid2, $uuid3] | invoice line revoke
#   invoice line revoke --uu "12345678-1234-5678-9012-123456789abc"
#   invoice line revoke --uu $obsolete_line_uuid
#
# Returns: uu, search_key, revoked timestamp, and is_revoked status for each revoked line
# Error: Command fails if UUID doesn't exist or line is already revoked
export def "invoice line revoke" [
    --uu: string  # UUID as a parameter instead of piped input
] {
    # Extract UUID from piped input or --uu parameter
    let target_uuid = ($in | extract-uu-with-param $uu)
    
    psql revoke-record $STK_SCHEMA $STK_INVOICE_LINE_TABLE_NAME $target_uuid
}


# List available invoice line types using generic psql list-types command
#
# Shows all available invoice line types that can be used when creating lines.
# Use this to see valid type options and their descriptions before
# creating new invoice lines with specific types.
#
# Accepts piped input: none
#
# Examples:
#   invoice line types
#   invoice line types | where type_enum == "ITEM"
#   invoice line types | where is_default == true
#   invoice line types | select type_enum name is_default | table
#
# Returns: uu, type_enum, name, description, is_default, created for all invoice line types
# Note: Uses the generic psql list-types command for consistency across chuck-stack
export def "invoice line types" [] {
    psql list-types $STK_SCHEMA $STK_INVOICE_LINE_TABLE_NAME
}
