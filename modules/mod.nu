# Chuck-Stack Nushell Modules
#
# This file exports all available chuck-stack modules for database interaction.
# Each module provides nushell commands for specific chuck-stack functionality.

# PostgreSQL command execution with structured output
export use stk_psql *

# Utility functions for chuck-stack modules
export use stk_utility *

# Event logging and retrieval for audit trails and system monitoring  
export use stk_event *

# Request tracking and management for follow-up actions
export use stk_request *

# Todo list management built on hierarchical requests
export use stk_todo *

# Item management for products, services, accounts, and charges
export use stk_item *

# Project management with hierarchical structure and line items
export use stk_project *

# Tag system for flexible metadata attachment with JSON Schema validation
export use stk_tag *

# Link system for many-to-many relationships between any chuck-stack records
export use stk_link *

# AI-powered text transformation utilities for chuck-stack
export use stk_ai *

# Address management with AI-powered natural language processing
export use stk_address *

# Timesheet tracking for recording work hours against projects and tasks
export use stk_timesheet *

# Business Partner management for customers, vendors, employees, and other financial relationships
export use stk_business_partner *

# Contact management for people associated with business partners
export use stk_contact *

# Interactive tutorial system for learning chuck-stack patterns
export use stk_tutor *

# Invoice management for sales and purchase transactions with business partners
export use stk_invoice *

# Entity management for organizational units and transactional contexts
export use stk_entity *
