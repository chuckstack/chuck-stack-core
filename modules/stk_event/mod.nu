# STK Event Module
# This module provides commands for working with stk_event table

# Module Constants
const STK_SCHEMA = "api"
const STK_TABLE_NAME = "stk_event"
const STK_EVENT_COLUMNS = [name, description, table_name_uu_json, record_json]

# Event module overview
export def "event" [] {
    r#'Events capture significant occurrences in your system:
logins, errors, transactions, and other activities worth recording.

Events are append-only and immutable for audit integrity.
Use .append event pattern to attach events to any record.

Type 'event <tab>' to see available commands.
'#
}

# Create a new event with optional attachment to another record
#
# This is the primary way to create events in the chuck-stack system.
# You can either pipe in a UUID/record to attach to, or provide it via --attach.
# The UUID identifies the parent record this event should be linked to.
# Use --description to provide event details and --json for structured data.
#
# Accepts piped input:
#   string - UUID of record to attach this event to (optional)
#   record - Record with 'uu' field to attach this event to (optional)
#   table - Table of records, uses first row's 'uu' field (optional)
#
# Examples:
#   .append event "authentication" --description "User login successful"
#   "12345678-1234-5678-9012-123456789abc" | .append event "bug-fix" --description "System error occurred"
#   project list | get 0 | .append event "project-update" --description "Project milestone reached"
#   todo list | where priority == "high" | .append event "task-review" --description "Review high priority tasks"
#   .append event "system-backup" --description "Database backup completed" --attach $backup_uuid
#   event list | get uu.0 | .append event "follow-up" --description "Follow up on this event"
#   .append event "system-error" --description "Critical system failure" --json '{"urgency": "high", "component": "database"}'
#   .append event "login" --search-key "EVT-2024-001" --description "Admin login event"
#   
#   # Interactive examples:
#   .append event "error" --type-search-key error --interactive
#   .append event "audit" --interactive --description "Security audit event"
#
# Returns: The UUID of the newly created event record
# Note: When a UUID is provided (via pipe or --attach), table_name_uu_json is auto-populated
export def ".append event" [
    name: string                    # The name/topic of the event (used for categorization and filtering)
    --search-key(-s): string       # Optional search key (unique identifier)
    --description(-d): string = ""  # Description of the event (optional)
    --type-name: string             # Lookup type by name field
    --type-search-key: string       # Lookup type by search_key field  
    --type-uu: string               # Lookup type by UUID
    --json(-j): string              # Optional JSON data to store in record_json field
    --interactive                   # Interactively build JSON data using the type's schema
    --attach(-a): string           # UUID of record to attach this event to (alternative to piped input)
] {
    let table = $"($STK_SCHEMA).($STK_TABLE_NAME)"
    
    # Extract attachment data from piped input or --attach parameter
    let attach_data = ($in | extract-attach-from-input $attach)
    
    # Resolve type using utility function (handles validation and resolution)
    let type_record = (resolve-type --schema $STK_SCHEMA --table $STK_TABLE_NAME --type-uu $type_uu --type-search-key $type_search_key --type-name $type_name)
    
    # Handle JSON input - one line replaces multiple lines of boilerplate
    let record_json = (resolve-json $json $interactive $type_record)
    
    if ($attach_data | is-empty) {
        # Standalone event - no attachment
        let params = {
            name: $name
            search_key: ($search_key | default null)
            description: $description
            type_uu: ($type_record.uu? | default null)
            record_json: $record_json
        }
        psql new-record $STK_SCHEMA $STK_TABLE_NAME $params
    } else {
        # Event with attachment - auto-populate table_name_uu_json
        # Get table_name_uu as nushell record (not JSON!)
        let table_name_uu = if ($attach_data.table_name? | is-not-empty) {
            # We have the table name - use it directly (no DB lookup)
            {table_name: $attach_data.table_name, uu: $attach_data.uu}
        } else {
            # No table name - look it up using psql command
            psql get-table-name-uu $attach_data.uu
        }
        
        # Convert to JSON for storage
        let table_name_uu_json = ($table_name_uu | to json)
        let params = {
            name: $name
            search_key: ($search_key | default null)
            description: $description
            type_uu: ($type_record.uu? | default null)
            table_name_uu_json: $table_name_uu_json
            record_json: $record_json
        }
        psql new-record $STK_SCHEMA $STK_TABLE_NAME $params
    }
}

# List events from the chuck-stack system
#
# Displays events in chronological order (newest first) to help you
# monitor recent activity, debug issues, or track system behavior.
# This is typically your starting point for event investigation.
# Use the returned UUIDs with other event commands for detailed work.
# Type information is always included for all events.
#
# Accepts piped input: none
#
# Examples:
#   event list
#   event list | where name == "authentication" 
#   event list | where type_enum == "ACTION"
#   event list | where is_revoked == false
#   event list | select name created | table
#
# Using resolve to resolve foreign key references:
#   event list | resolve                                               # Resolve with default columns
#   event list | resolve name table_name                               # Show referenced table names
#   event list | resolve --detail | select name table_name_uu_json_resolved.name  # Show referenced record names
#
# Returns: name, description, table_name_uu_json, record_json, created, updated, is_revoked, uu, type_enum, type_name, type_description
# Note: Returns all events by default - use --limit to control the number returned
export def "event list" [
    --all(-a)     # Include revoked events
    --limit(-l): int  # Maximum number of records to return
] {
    # Build complete arguments array including flags
    let args = [$STK_SCHEMA, $STK_TABLE_NAME] | append $STK_EVENT_COLUMNS
    
    # Add --all flag to args if needed
    let args = if $all { $args | append "--all" } else { $args }
    
    # Add limit to args if provided
    let args = if $limit != null { $args | append ["--limit" ($limit | into string)] } else { $args }
    
    # Execute query
    psql list-records ...$args
}

# Retrieve a specific event by its UUID
#
# Fetches complete details for a single event when you need to
# inspect its contents, verify its state, or extract specific
# data from the record_json field. Use this when you have a
# UUID from event list or from other system outputs.
# Type information is always included.
#
# Accepts piped input:
#   string - The UUID of the event to retrieve
#   record - Record with 'uu' field to retrieve
#   table - Table of records, uses first row's 'uu' field
#
# Examples:
#   # Using piped input
#   "12345678-1234-5678-9012-123456789abc" | event get
#   event list | get 0 | event get
#   event list | where name == "error" | event get
#   
#   # Using --uu parameter
#   event get --uu "12345678-1234-5678-9012-123456789abc"
#   event get --uu $event_uuid
#   
#   # Practical examples
#   $event_uuid | event get | get description
#   event get --uu $uu | get record_json
#   $uu | event get | if $in.is_revoked { print "Event was revoked" }
#
# Returns: name, description, record_json, created, updated, is_revoked, uu, type_enum, type_name, and other type information
# Error: Returns empty result if UUID doesn't exist
export def "event get" [
    --uu: string  # UUID as parameter (alternative to piped input)
] {
    # Extract UUID from piped input or --uu parameter
    let uu = ($in | extract-uu-with-param $uu)
    
    psql get-record $STK_SCHEMA $STK_TABLE_NAME $STK_EVENT_COLUMNS $uu
}

# Revoke an event by setting its revoked timestamp
#
# This performs a soft delete by setting the revoked column to now().
# Once revoked, events are considered immutable and won't appear in 
# normal selections. Use this instead of hard deleting to maintain
# audit trails and data integrity in the chuck-stack system.
#
# Accepts piped input: 
#   string - The UUID of the event to revoke
#   record - Record with 'uu' field to revoke
#   table - Table of records, uses first row's 'uu' field
#
# Examples:
#   # Using piped input
#   event list | where name == "test" | get 0 | event revoke
#   "12345678-1234-5678-9012-123456789abc" | event revoke
#   
#   # Using --uu parameter
#   event revoke --uu "12345678-1234-5678-9012-123456789abc"
#   event revoke --uu $event_uuid
#   
#   # Bulk operations
#   event list | where created < (date now) - 30day | each { |row| event revoke --uu $row.uu }
#
# Returns: uu, name, revoked timestamp, and is_revoked status
# Error: Command fails if UUID doesn't exist or event is already revoked
export def "event revoke" [
    --uu: string  # UUID as parameter (alternative to piped input)
] {
    # Extract UUID from piped input or --uu parameter
    let target_uuid = ($in | extract-uu-with-param $uu)
    
    psql revoke-record $STK_SCHEMA $STK_TABLE_NAME $target_uuid
}

# List available event types using generic psql list-types command
#
# Shows all available event types that can be used when creating events.
# Use this to see valid type options and their descriptions before
# creating new events with specific types.
#
# Accepts piped input: none
#
# Examples:
#   event types
#   event types | where type_enum == "ACTION"
#   event types | where is_default == true
#   event types | select type_enum name is_default | table
#
# Returns: uu, type_enum, name, description, is_default, created for all event types
# Note: Uses the generic psql list-types command for consistency across chuck-stack
export def "event types" [] {
    psql list-types $STK_SCHEMA $STK_TABLE_NAME
}

# Add an 'events' column to records, fetching associated stk_event records
#
# This command enriches piped records with an 'events' column containing
# their associated event records. It uses the table_name_uu_json pattern
# to find events that reference the input records.
#
# Examples:
#   project list | events                          # Default columns
#   project list | events --detail                 # All event columns
#   project list | events name description created # Specific columns
#
# Returns: Original records with added 'events' column containing array of event records
export def events [
    ...columns: string  # Specific columns to include in event records
    --detail(-d)        # Include all columns (select *)
    --all(-a)           # Include revoked events
] {
    $in | psql append-table-name-uu-json $STK_SCHEMA $STK_TABLE_NAME "events" $STK_EVENT_COLUMNS ...$columns --detail=$detail --all=$all
}


