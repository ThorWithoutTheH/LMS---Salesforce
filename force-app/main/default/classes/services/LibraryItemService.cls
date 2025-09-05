public with sharing class LibraryItemService {
    
    // Custom exceptions
    public class LibraryItemException extends Exception {}
    public class DuplicateItemException extends Exception {}
    
    /**
     * Create a new library item
     */
    @AuraEnabled
    public static Library_Item__c createLibraryItem(LibraryItemRequest request) {
        validateItemRequest(request);
        
        Library_Item__c item = new Library_Item__c(
            Item_Name__c = request.itemName,
        Item_Type__c = request.itemType,
        Category__c = request.category,
        Barcode__c = request.barcode != null ? request.barcode : generateBarcode(request.itemType),
        ISBN_Serial__c = request.isbnSerial,
        Author_Manufacturer__c = request.authorManufacturer,
        Current_Status__c = 'Available',
        Location__c = request.location,
        Condition__c = request.condition != null ? request.condition : 'Good',
        Purchase_Date__c = request.purchaseDate != null ? request.purchaseDate : Date.today(),
        Notes__c = request.notes
            );
        
        try {
            insert item;
            System.debug('Created library item: ' + item.Item_Name__c + ' (Barcode: ' + item.Barcode__c + ')');
            return item;
        } catch (DmlException e) {
            throw new AuraHandledException('Failed to create library item: ' + e.getMessage());
        }
    }
    
    /**
     * Get all library items with borrower information
     */
    @AuraEnabled(cacheable=true)
    public static List<Library_Item__c> getAllLibraryItems() {
        return LibraryItemDAO.getAllItemsWithBorrowerDetails();
    }
    
    /**
     * Update library item status (used by BorrowingRecordService)
     */
    public static void updateItemStatus(Id itemId, String newStatus, Id currentBorrowerId) {
        Library_Item__c item = LibraryItemDAO.findItemByIdForStatusUpdate(itemId);
        
        if (item == null) {
            throw new LibraryItemException('Library item not found: ' + itemId);
        }
        
        item.Current_Status__c = newStatus;
        item.Current_Borrower__c = currentBorrowerId;
        
        try {
            update item;
            System.debug('Updated item status: ' + itemId + ' -> ' + newStatus);
        } catch (DmlException e) {
            throw new LibraryItemException('Failed to update item status: ' + e.getMessage());
        }
    }
    
    /**
     * Search for library items
     */
    @AuraEnabled(cacheable=true)
    public static List<Library_Item__c> searchLibraryItems(String searchTerm, String itemType, String status) {
        return LibraryItemDAO.searchItemsWithFilters(searchTerm, itemType, status);
    }
    
    /**
     * Get library item by barcode (used by BorrowingRecordService)
     */
    public static Library_Item__c getItemByBarcode(String barcode) {
        if (String.isBlank(barcode)) {
            return null;
        }
        
        return LibraryItemDAO.findItemByBarcodeForBorrowing(barcode);
    }
    
    /**
     * Get library item by ID
     */
    public static Library_Item__c getLibraryItemById(Id itemId) {
        if (itemId == null) {
            return null;
        }
        
        return LibraryItemDAO.findItemByIdForStatusUpdate(itemId);
    }
    
    /**
     * Update library item details
     */
    @AuraEnabled
    public static Library_Item__c updateLibraryItem(Id itemId, LibraryItemRequest request) {
        Library_Item__c item = LibraryItemDAO.findItemByIdForStatusUpdate(itemId);
        
        if (item == null) {
            throw new LibraryItemException('Library item not found: ' + itemId);
        }
        
        // Validate request (but skip barcode uniqueness check if barcode unchanged)
        if (request.barcode != null && request.barcode != item.Barcode__c) {
            validateBarcodeUniqueness(request.barcode);
        }
        
        // Update fields
        updateItemFields(item, request);
        
        try {
            update item;
            System.debug('Updated library item: ' + item.Item_Name__c);
            return item;
        } catch (DmlException e) {
            throw new AuraHandledException('Failed to update library item: ' + e.getMessage());
        }
    }
    
    /**
     * Delete library item (only if not currently borrowed)
     */
    @AuraEnabled
    public static DeleteResult deleteLibraryItem(Id itemId) {
        DeleteResult result = new DeleteResult();
        
        try {
            Library_Item__c item = LibraryItemDAO.findItemByIdForStatusUpdate(itemId);
            
            if (item == null) {
                result.isSuccess = false;
                result.message = 'Library item not found';
                return result;
            }
            
            if (item.Current_Status__c == 'Checked Out') {
                result.isSuccess = false;
                result.message = 'Cannot delete item that is currently Checked Out';
                return result;
            }
            
            // Check for borrowing history
            Integer historyCount = LibraryItemDAO.countBorrowingHistoryForItem(itemId);
            
            if (historyCount > 0) {
                result.isSuccess = false;
                result.message = 'Cannot delete item with borrowing history. Consider marking as Retired instead.';
                return result;
            }
            
            delete item;
            
            result.isSuccess = true;
            result.message = 'Library item deleted successfully';
            
            System.debug('Deleted library item: ' + itemId);
            
        } catch (Exception e) {
            result.isSuccess = false;
            result.message = 'Failed to delete item: ' + e.getMessage();
        }
        
        return result;
    }
    
    /**
     * Get available categories for item type
     */
    @AuraEnabled(cacheable=true)
    public static List<String> getCategoriesForItemType(String itemType) {
        if (String.isBlank(itemType)) {
            return new List<String>();
        }
        
        List<AggregateResult> categories = LibraryItemDAO.getCategoriesByItemType(itemType);
        
        List<String> result = new List<String>();
        for (AggregateResult ar : categories) {
            String category = (String)ar.get('Category__c');
            if (String.isNotBlank(category)) {
                result.add(category);
            }
        }
        
        return result;
    }
    
    /**
     * Get item statistics
     */
    @AuraEnabled(cacheable=true)
    public static ItemStatistics getItemStatistics() {
        ItemStatistics stats = new ItemStatistics();
        
        List<AggregateResult> results = LibraryItemDAO.getItemStatisticsByStatus();
        
        for (AggregateResult result : results) {
            String status = (String)result.get('status');
            Integer count = (Integer)result.get('count');
            
            switch on status {
                when 'Available' {
                    stats.availableCount = count;
                }
                when 'Checked Out' {
                    stats.checkedOutCount = count;
                }
                when 'Overdue' {
                    stats.overdueCount = count;
                }
                when 'Maintenance' {
                    stats.maintenanceCount = count;
                }
                when 'Lost' {
                    stats.lostCount = count;
                }
                when 'Retired' {
                    stats.retiredCount = count;
                }
            }
            stats.totalCount += count;
        }
        
        return stats;
    }
    
    /**
     * Get items Checked_Out to specific user
     */
    @AuraEnabled(cacheable=true)
    public static List<Library_Item__c> getItemsCheckedOutToUser(Id userId) {
        return LibraryItemDAO.findItemsCheckedOutToUser(userId);
    }
    
    /**
     * Get available items by type (for suggestions)
     */
    @AuraEnabled(cacheable=true)
    public static List<Library_Item__c> getAvailableItemsByType(String itemType, Integer limitCount) {
        return LibraryItemDAO.findAvailableItemsByType(itemType, limitCount);
    }
    
    /**
     * Get items by location (for inventory)
     */
    @AuraEnabled(cacheable=true)
    public static List<Library_Item__c> getItemsByLocation(String location) {
        return LibraryItemDAO.findItemsByLocation(location);
    }
    
    /**
     * Get recently added items
     */
    @AuraEnabled(cacheable=true)
    public static List<Library_Item__c> getRecentlyAddedItems(Integer days) {
        Integer daysToSearch = days != null ? days : 7;
        return LibraryItemDAO.findRecentlyAddedItems(daysToSearch);
    }
    
    /**
     * Batch creation with partial success handling
     */
    @AuraEnabled
    public static BatchCreationResult createItemsWithPartialSuccess(List<LibraryItemRequest> requests) {
        BatchCreationResult result = new BatchCreationResult();
        
        for (LibraryItemRequest request : requests) {
            try {
                Library_Item__c item = createLibraryItem(request);
                result.createdItems.add(item);
                result.successCount++;
            } catch (Exception e) {
                result.errors.add('Failed to create "' + request.itemName + '": ' + e.getMessage());
                result.errorCount++;
            }
        }
        
        return result;
    }
    
    // PRIVATE HELPER METHODS
    
    /**
     * Generate automatic barcode
     */
    private static String generateBarcode(String itemType) {
        String prefix = getBarcodePrefix(itemType);
        Integer nextNumber = getNextBarcodeNumber(prefix);
        return prefix + String.valueOf(nextNumber).leftPad(6, '0');
    }
    
    /**
     * Get barcode prefix for item type
     */
    private static String getBarcodePrefix(String itemType) {
        Map<String, String> prefixMap = new Map<String, String>{
            'Book' => 'BOOK',
            'DVD' => 'DVD',
            'Blu-ray' => 'BR',
            'Video Game' => 'GAME',
            'Audio Equipment' => 'AV',
            'Equipment' => 'EQUIP',
            'Magazine' => 'MAG',
            'Software' => 'SOFT'
        };
        
        return prefixMap.get(itemType) != null ? prefixMap.get(itemType) : 'ITEM';
    }
    
    /**
     * Get next available barcode number
     */
    private static Integer getNextBarcodeNumber(String prefix) {
        Library_Item__c lastItem = LibraryItemDAO.getLastItemWithBarcodePrefix(prefix);
        
        if (lastItem == null) {
            return 1;
        }
        
        String lastBarcode = lastItem.Barcode__c;
        String numberPart = lastBarcode.substring(prefix.length());
        
        try {
            return Integer.valueOf(numberPart) + 1;
        } catch (Exception e) {
            return 1;
        }
    }
    
    /**
     * Validate item request
     */
    private static void validateItemRequest(LibraryItemRequest request) {
        if (String.isBlank(request.itemName)) {
            throw new LibraryItemException('Item name is required');
        }
        
        if (String.isBlank(request.itemType)) {
            throw new LibraryItemException('Item type is required');
        }
        
        // Validate item type against configuration
        List<String> validTypes = LibraryConfigService.getAvailableItemTypes();
        if (!validTypes.isEmpty() && !validTypes.contains(request.itemType)) {
            throw new LibraryItemException('Invalid item type: ' + request.itemType);
        }
        
        // Check for duplicate barcode if provided
        if (String.isNotBlank(request.barcode)) {
            validateBarcodeUniqueness(request.barcode);
        }
    }
    
    /**
     * Validate barcode uniqueness
     */
    private static void validateBarcodeUniqueness(String barcode) {
        if (LibraryItemDAO.doesBarcodeExist(barcode)) {
            throw new DuplicateItemException('Barcode already exists: ' + barcode);
        }
    }
    
    /**
     * Update item fields from request
     */
    private static void updateItemFields(Library_Item__c item, LibraryItemRequest request) {
        if (String.isNotBlank(request.itemName)) {
            item.Item_Name__c = request.itemName;
        }
        if (String.isNotBlank(request.itemType)) {
            item.Item_Type__c = request.itemType;
        }
        if (String.isNotBlank(request.category)) {
            item.Category__c = request.category;
        }
        if (String.isNotBlank(request.barcode)) {
            item.Barcode__c = request.barcode;
        }
        if (String.isNotBlank(request.authorManufacturer)) {
            item.Author_Manufacturer__c = request.authorManufacturer;
        }
        if (String.isNotBlank(request.isbnSerial)) {
            item.ISBN_Serial__c = request.isbnSerial;
        }
        if (String.isNotBlank(request.location)) {
            item.Location__c = request.location;
        }
        if (String.isNotBlank(request.condition)) {
            item.Condition__c = request.condition;
        }
        if (request.purchaseDate != null) {
            item.Purchase_Date__c = request.purchaseDate;
        }
        if (String.isNotBlank(request.notes)) {
            item.Notes__c = request.notes;
        }
    }
    
    // WRAPPER CLASSES
    
    /**
     * Request wrapper for creating/updating library items
     */
    public class LibraryItemRequest {
        @AuraEnabled public String itemName { get; set; }
        @AuraEnabled public String itemType { get; set; }
        @AuraEnabled public String category { get; set; }
        @AuraEnabled public String barcode { get; set; }
        @AuraEnabled public String isbnSerial { get; set; }
        @AuraEnabled public String authorManufacturer { get; set; }
        @AuraEnabled public String location { get; set; }
        @AuraEnabled public String condition { get; set; }
        @AuraEnabled public Date purchaseDate { get; set; }
        @AuraEnabled public String notes { get; set; }
        
        public LibraryItemRequest(String itemName, String itemType, String category) {
            this.itemName = itemName;
            this.itemType = itemType;
            this.category = category;
        }
        
        public LibraryItemRequest() {}
    }
    
    /**
     * Batch creation result wrapper
     */
    public class BatchCreationResult {
        @AuraEnabled public List<Library_Item__c> createdItems { get; set; }
        @AuraEnabled public List<String> errors { get; set; }
        @AuraEnabled public Integer successCount { get; set; }
        @AuraEnabled public Integer errorCount { get; set; }
        
        public BatchCreationResult() {
            this.createdItems = new List<Library_Item__c>();
            this.errors = new List<String>();
            this.successCount = 0;
            this.errorCount = 0;
        }
    }
    
    /**
     * Delete operation result wrapper
     */
    public class DeleteResult {
        @AuraEnabled public Boolean isSuccess { get; set; }
        @AuraEnabled public String message { get; set; }
        
        public DeleteResult() {
            this.isSuccess = false;
        }
    }
    
    /**
     * Item statistics wrapper
     */
    public class ItemStatistics {
        @AuraEnabled public Integer totalCount { get; set; }
        @AuraEnabled public Integer availableCount { get; set; }
        @AuraEnabled public Integer checkedOutCount { get; set; }
        @AuraEnabled public Integer overdueCount { get; set; }
        @AuraEnabled public Integer maintenanceCount { get; set; }
        @AuraEnabled public Integer lostCount { get; set; }
        @AuraEnabled public Integer retiredCount { get; set; }
        
        public ItemStatistics() {
            this.totalCount = 0;
            this.availableCount = 0;
            this.checkedOutCount = 0;
            this.overdueCount = 0;
            this.maintenanceCount = 0;
            this.lostCount = 0;
            this.retiredCount = 0;
        }
    }
}