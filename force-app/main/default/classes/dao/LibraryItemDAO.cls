public with sharing class LibraryItemDAO {
    
    /**
     * Get all library items with complete details including borrower information
     */
    public static List<Library_Item__c> getAllItemsWithBorrowerDetails() {
        return [
        SELECT Id, Name, Item_Name__c, Item_Type__c, Category__c, 
               Barcode__c, Author_Manufacturer__c, Current_Status__c,
               Location__c, Condition__c, Purchase_Date__c, Notes__c,
               Current_Borrower__c, Current_Borrower__r.Name,
               ISBN_Serial__c
        FROM Library_Item__c 
        ORDER BY Item_Name__c ASC
        LIMIT 1000
    ];
    }
    
    /**
     * Find library item by barcode with all necessary fields for borrowing operations
     */
    public static Library_Item__c findItemByBarcodeForBorrowing(String barcode) {
        List<Library_Item__c> items = [
        SELECT Id, Name, Item_Name__c, Item_Type__c, Category__c, Barcode__c,
               Author_Manufacturer__c, Current_Status__c, 
               Current_Borrower__c, Current_Borrower__r.Name,
               Location__c, ISBN_Serial__c, Condition__c
        FROM Library_Item__c 
        WHERE Barcode__c = :barcode 
        LIMIT 1
    ];
        
        return items.isEmpty() ? null : items[0];
    }
    
    /**
     * Find library item by ID with core fields for status updates
     */
    public static Library_Item__c findItemByIdForStatusUpdate(Id itemId) {
        List<Library_Item__c> items = [
        SELECT Id, Item_Name__c, Item_Type__c, Current_Status__c, 
               Current_Borrower__c, Current_Borrower__r.Name, Barcode__c, Location__c
        FROM Library_Item__c 
        WHERE Id = :itemId 
        LIMIT 1
    ];
        
        return items.isEmpty() ? null : items[0];
    }
    
    /**
     * Search library items with dynamic filtering
     */
    public static List<Library_Item__c> searchItemsWithFilters(String searchTerm, String itemType, String status) {
        String query = 'SELECT Id, Name, Item_Name__c, Item_Type__c, Category__c, Barcode__c, ' +
            'Author_Manufacturer__c, Current_Status__c, Location__c, Condition__c, ' +
            'Current_Borrower__c, Current_Borrower__r.Name, ISBN_Serial__c ' +
            'FROM Library_Item__c WHERE Id != null';
        
        if (String.isNotBlank(searchTerm)) {
            String searchPattern = '%' + String.escapeSingleQuotes(searchTerm) + '%';
            query += ' AND (Item_Name__c LIKE :searchPattern OR ' +
                'Author_Manufacturer__c LIKE :searchPattern OR ' +
                'Barcode__c LIKE :searchPattern OR ' +
                'Category__c LIKE :searchPattern)';
        }
        
        if (String.isNotBlank(itemType)) {
            query += ' AND Item_Type__c = :itemType';
        }
        
        if (String.isNotBlank(status)) {
            query += ' AND Current_Status__c = :status';
        }
        
        query += ' ORDER BY Item_Name__c LIMIT 50';
        
        return Database.query(query);
    }
    
    /**
     * Check if barcode already exists (for uniqueness validation)
     */
    public static Boolean doesBarcodeExist(String barcode) {
        List<Library_Item__c> existingItems = [
            SELECT Id 
            FROM Library_Item__c 
            WHERE Barcode__c = :barcode 
            LIMIT 1
        ];
        
        return !existingItems.isEmpty();
    }
    
    /**
     * Get next available barcode number for auto-generation
     */
    public static Library_Item__c getLastItemWithBarcodePrefix(String prefix) {
        List<Library_Item__c> existingItems = [
            SELECT Barcode__c 
            FROM Library_Item__c 
            WHERE Barcode__c LIKE :(prefix + '%')
            ORDER BY Barcode__c DESC
            LIMIT 1
        ];
        
        return existingItems.isEmpty() ? null : existingItems[0];
    }
    
    /**
     * Get distinct categories for specific item type
     */
    public static List<AggregateResult> getCategoriesByItemType(String itemType) {
        return [
            SELECT Category__c 
            FROM Library_Item__c 
            WHERE Item_Type__c = :itemType 
            AND Category__c != null
            GROUP BY Category__c
            ORDER BY Category__c
            LIMIT 20
        ];
    }
    
    /**
     * Get item statistics grouped by status
     */
    public static List<AggregateResult> getItemStatisticsByStatus() {
        return [
            SELECT Current_Status__c status, COUNT(Id)
            FROM Library_Item__c
            GROUP BY Current_Status__c
        ];
    }
    
    /**
     * Check if item has borrowing history (for safe deletion)
     */
    public static Integer countBorrowingHistoryForItem(Id itemId) {
        return [
            SELECT COUNT() 
            FROM Borrowing_Record__c 
            WHERE Library_Item__c = :itemId
        ];
    }
    
    /**
     * Get items by multiple IDs (for batch operations)
     */
    public static List<Library_Item__c> findItemsByIds(List<Id> itemIds) {
        return [
            SELECT Id, Item_Name__c, Item_Type__c, Current_Status__c, 
                   Current_Borrower__c, Current_Borrower__r.Name, Barcode__c
            FROM Library_Item__c 
            WHERE Id IN :itemIds
        ];
    }
    
    /**
     * Get items with overdue status for reporting
     */
    public static List<Library_Item__c> findOverdueItems() {
        return [
            SELECT Id, Item_Name__c, Barcode__c, Current_Borrower__r.Name,
                   Current_Borrower__r.Email, Location__c
            FROM Library_Item__c 
            WHERE Current_Status__c = 'Overdue'
            ORDER BY Item_Name__c
        ];
    }
    
    public static List<Library_Item__c> findItemsCheckedOutToUser(Id userId) {
        return [
            SELECT Id, Item_Name__c, Item_Type__c, Barcode__c, 
                   Author_Manufacturer__c, Location__c
            FROM Library_Item__c 
            WHERE Current_Borrower__c = :userId
            AND Current_Status__c IN ('Checked Out', 'Overdue')
            ORDER BY Item_Name__c
        ];
    }
    
    /**
     * Get available items by type (for quick checkout suggestions)
     */
    public static List<Library_Item__c> findAvailableItemsByType(String itemType, Integer limitCount) {
        Integer queryLimit = limitCount != null ? limitCount : 10;
        
        return [
            SELECT Id, Item_Name__c, Barcode__c, Author_Manufacturer__c, Location__c, Item_Type__c, Category__c, Current_Status__c
            FROM Library_Item__c 
            WHERE Item_Type__c = :itemType
            AND Current_Status__c = 'Available'
            ORDER BY Item_Name__c
            LIMIT :queryLimit
        ];
    }
    
    /**
     * Get items by location (for inventory management)
     */
    public static List<Library_Item__c> findItemsByLocation(String location) {
        return [
            SELECT Id, Item_Name__c, Item_Type__c, Barcode__c, 
                   Current_Status__c, Author_Manufacturer__c, Location__c
            FROM Library_Item__c 
            WHERE Location__c = :location
            ORDER BY Item_Type__c, Item_Name__c
        ];
    }
    
    /**
     * Get recently added items (for dashboard)
     */
    public static List<Library_Item__c> findRecentlyAddedItems(Integer days) {
        Date cutoffDate = Date.today().addDays(-days);
        
        return [
            SELECT Id, Item_Name__c, Item_Type__c, Barcode__c, 
                   Purchase_Date__c, Current_Status__c, Author_Manufacturer__c, Location__c
            FROM Library_Item__c 
            WHERE Purchase_Date__c >= :cutoffDate
            OR CreatedDate >= :cutoffDate
            ORDER BY CreatedDate DESC
            LIMIT 20
        ];
    }
    
    /**
     * Get items in maintenance status
     */
    public static List<Library_Item__c> findItemsInMaintenance() {
        return [
            SELECT Id, Item_Name__c, Item_Type__c, Barcode__c, 
                   Location__c, Notes__c, LastModifiedDate
            FROM Library_Item__c 
            WHERE Current_Status__c = 'Maintenance'
            ORDER BY LastModifiedDate DESC
        ];
    }
    
    /**
     * Find duplicate items by name and author (for data quality)
     */
    public static List<AggregateResult> findPotentialDuplicateItems() {
        return [
            SELECT Item_Name__c, Author_Manufacturer__c, COUNT(Id) duplicateCount
            FROM Library_Item__c 
            WHERE Item_Name__c != null 
            AND Author_Manufacturer__c != null
            GROUP BY Item_Name__c, Author_Manufacturer__c
            HAVING COUNT(Id) > 1
            ORDER BY COUNT(Id) DESC
            LIMIT 50
        ];
    }
}