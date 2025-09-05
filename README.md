# Library Management System

Salesforce-based library management system with barcode scanning capability.

## Features
- Barcode scanner interface for rapid checkout/return
- Item tracking and borrowing history
- Configurable loan periods via Custom Metadata
- Role-based permissions for librarians

## Setup
1. Clone repository
2. Authorize your org: `sfdx auth:web:login -a MyOrg`
3. Deploy: `sfdx force:source:deploy -p force-app`

## Components
- **BarcodeScannerController**: Handles barcode processing
- **LibraryItemService**: Manages library items
- **BorrowingRecordService**: Handles checkout/return logic
- **barcodeScanner LWC**: UI for scanning interface
- **addLibraryItem LWC**: UI for add individual inventory item with Notes
- **libraryDashboard LWC**: UI for Item stats and history
