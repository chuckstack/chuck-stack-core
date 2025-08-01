# STK Business Partner Module
# This module provides commands for working with stk_business_partner table

# Module Constants
const STK_SCHEMA = "api"
const STK_TABLE_NAME = "stk_business_partner"
const STK_BUSINESS_PARTNER_COLUMNS = [name, description, is_template, is_valid, record_json]

# Business Partner module overview
export def "bp" [] {
    r#'Business Partners represent anyone you engage with financially:
customers, vendors, employees, contractors, or partners.

Types define entity structure (ORGANIZATION, INDIVIDUAL, GROUP).
Business roles are assigned through tags (BP_CUSTOMER, BP_VENDOR, etc.).

Type 'bp <tab>' to see available commands.
'#
}


# Create a new business partner with specified name and type
#
# Business Partners represent anyone you engage with financially: customers,
# vendors, employees, contractors, or partners. The type defines the entity
# structure (ORGANIZATION, INDIVIDUAL, GROUP), while business roles are
# handled through tags (BP_CUSTOMER, BP_VENDOR, etc.).
#
# Accepts piped input:
#   string - Parent BP UUID for creating subsidiaries
#   record - Parent BP record with 'uu' field
#   table - Table of BP records, uses first row as parent
#
# Examples:
#   bp new "ACME Corporation"
#   bp new "John Smith" --type-search-key individual
#   bp new "ABC Holdings" --type-search-key group --description "Holding company"
#   bp new "Customer Template" --template --type-search-key organization
#   bp new "Vendor Corp" --json '{"tax_id": "12-3456789", "legal_name": "Vendor Corporation"}'
#   bp new "Acme Inc" --search-key "ACME-001" --type-search-key organization
#   
#   # Interactive examples:
#   bp new "Acme Corp" --type-search-key organization --interactive
#   bp new "Jane Smith" --type-search-key individual --interactive --description "Key contact"
#   
#   # Create subsidiary with parent
#   bp list | where name == "ACME Corporation" | bp new "ACME Subsidiary"
#   $parent_uuid | bp new "ACME Europe"
#
# Returns: The UUID and name of the newly created business partner
# Note: Use tags to assign business roles after creation (customer, vendor, etc.)
export def "bp new" [
    name: string                    # The name of the business partner
    --type-uu: string              # Type UUID (use 'bp types' to find UUIDs)
    --type-search-key: string      # Type search key (ORGANIZATION, INDIVIDUAL, GROUP)
    --search-key(-s): string       # Optional search key (unique identifier)
    --description(-d): string      # Optional description
    --template                     # Create as template for reuse
    --entity-uu(-e): string        # Optional entity UUID (uses default if not provided)
    --json(-j): string             # Optional JSON data to store in record_json field
    --interactive                  # Interactively build JSON data using the type's schema
] {
    # Extract parent UUID from piped input if provided
    let piped_input = $in
    let parent_uuid = if ($piped_input | is-not-empty) {
        # Extract UUID from various input types
        let uuid = ($piped_input | extract-single-uu)
        # Validate parent exists in same table
        psql validate-uuid-table $uuid $STK_TABLE_NAME
    } else {
        null
    }
    
    # Resolve type using utility function
    let type_record = (resolve-type --schema $STK_SCHEMA --table $STK_TABLE_NAME --type-uu $type_uu --type-search-key $type_search_key)
    
    # Handle JSON input - one line replaces multiple lines of boilerplate
    let record_json = (resolve-json $json $interactive $type_record)
    
    # Build parameters record
    let params = {
        name: $name
        type_uu: ($type_record.uu? | default null)
        search_key: ($search_key | default null)
        description: ($description | default null)
        is_template: ($template | default false)
        parent_uu: ($parent_uuid | default null)
        stk_entity_uu: ($entity_uu | default null)
        record_json: $record_json  # Already a JSON string from parse-json
    }
    
    psql new-record $STK_SCHEMA $STK_TABLE_NAME $params
}

# List the 10 most recent business partners
#
# Displays business partners in chronological order (newest first) to help
# you browse and manage relationships. Use the returned UUIDs with other
# bp commands or to create tags for roles (customer, vendor, etc.).
#
# Accepts piped input: none
#
# Examples:
#   bp list
#   bp list --all                                    # Include revoked BPs
#   bp list --templates                              # Show only templates  
#   bp list | where name =~ "corp"
#   bp list | where is_template == false
#   bp list | where type_enum == "ORGANIZATION"
#   
#   # Find BPs with specific roles using tags
#   bp list | tags | where type_enum == "BP_CUSTOMER" | get table_name_uu_json | bp get
#
# Returns: name, description, is_template, is_valid, created, updated, is_revoked, uu, type_enum, type_name, parent_uu
export def "bp list" [
    --all(-a)       # Include revoked business partners and templates
    --templates     # Show only templates
    --limit(-l): int  # Maximum number of records to return
] {
    # Build complete arguments array
    let args = [$STK_SCHEMA, $STK_TABLE_NAME] | append $STK_BUSINESS_PARTNER_COLUMNS
    
    # Add flags to args if needed
    let args = if $all { $args | append "--all" } else { $args }
    let args = if $templates { $args | append "--templates" } else { $args }
    
    # Add limit to args if provided
    let args = if $limit != null { $args | append ["--limit" ($limit | into string)] } else { $args }
    
    # Execute query
    psql list-records ...$args
}

# Retrieve a specific business partner by UUID
#
# Fetches complete details for a single business partner including
# type information, validation status, and custom data. Use this
# to inspect BP properties before creating invoices or assignments.
#
# Accepts piped input:
#   string - The UUID of the BP to retrieve
#   record - Record with 'uu' field to retrieve
#   table - Table of records, uses first row's 'uu' field
#
# Examples:
#   "12345678-1234-5678-9012-123456789abc" | bp get
#   bp get --uu "12345678-1234-5678-9012-123456789abc"
#   bp list | where name == "ACME Corp" | bp get
#   bp list | get 0 | bp get
#   
#   # Get BP and check roles
#   $bp_uuid | bp get | tags | where type_enum =~ "^BP_"
#
# Returns: name, description, is_template, is_valid, record_json, created, updated, uu, type information and parent relationships
export def "bp get" [
    --uu: string  # UUID as parameter (alternative to piped input)
] {
    # Extract UUID from piped input or --uu parameter
    let uu = ($in | extract-uu-with-param $uu)
    
    psql get-record $STK_SCHEMA $STK_TABLE_NAME $STK_BUSINESS_PARTNER_COLUMNS $uu
}

# Revoke a business partner (soft delete)
#
# Sets the revoked timestamp to mark a BP as inactive. Revoked BPs
# won't appear in normal listings but maintain audit history. Use
# this when a relationship ends or a partner becomes inactive.
#
# Accepts piped input:
#   string - The UUID of the BP to revoke
#   record - Record with 'uu' field to revoke
#   table - Table of records, uses first row's 'uu' field
#
# Examples:
#   bp list | where name == "old-vendor" | bp revoke
#   "12345678-1234-5678-9012-123456789abc" | bp revoke
#   bp revoke --uu $bp_uuid
#   
#   # Bulk revoke inactive BPs
#   bp list | where is_valid == false | each { |row| $row | bp revoke }
#
# Returns: uu, name, revoked timestamp, and is_revoked status
# Error: Fails if UUID doesn't exist or BP is already revoked
export def "bp revoke" [
    --uu: string  # UUID as parameter (alternative to piped input)
] {
    # Extract UUID from piped input or --uu parameter
    let target_uuid = ($in | extract-uu-with-param $uu)
    
    psql revoke-record $STK_SCHEMA $STK_TABLE_NAME $target_uuid
}

# List available business partner types
#
# Shows the types that define BP entity structure: ORGANIZATION for
# companies, INDIVIDUAL for people, and GROUP for related entities.
# Note that business roles (customer, vendor, etc.) are handled via
# tags, not types.
#
# Accepts piped input: none
#
# Examples:
#   bp types
#   bp types | where type_enum == "ORGANIZATION"
#   bp types | where is_default == true
#
# Returns: uu, type_enum, name, description, is_default, record_json
# Note: record_json contains pg_jsonschema for type-specific validation
export def "bp types" [] {
    psql list-types $STK_SCHEMA $STK_TABLE_NAME
}