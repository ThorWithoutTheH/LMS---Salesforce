public with sharing class BorrowingRecordService {
    
    // Custom exceptions
    public class BorrowingException extends Exception {}
    public class ItemNotAvailableException extends Exception {}
    public class ItemNotFoundException extends Exception {}
    
    /**
     * Checkout an item to a borrower
     */
    @AuraEnabled
    public static CheckoutResult checkoutItem(String itemCode, Id borrowerId) {
        CheckoutResult result = new CheckoutResult();
        
        try {
            // Validate inputs
            if (String.isBlank(itemCode) || borrowerId == null) {
                throw new BorrowingException('Item code and borrower are required');
            }
            
            // Get the item and validate availability
            Library_Item__c item = LibraryItemService.getItemByBarcode(itemCode);
            
            if (item == null) {
                throw new ItemNotFoundException('Item not found with code: ' + itemCode);
            }
            
            if (item.Current_Status__c != 'Available') {
                throw new ItemNotAvailableException('Item "' + item.Item_Name__c + '" is not available for checkout');
            }
            
            // Check borrowing limits
            validateBorrowingLimits(borrowerId, item.Item_Type__c);
            
            // Create borrowing record - FIXED: passing item object instead of just ID
            Borrowing_Record__c borrowingRecord = createBorrowingRecord(item, borrowerId);
            insert borrowingRecord;
            
            // Update item status
            LibraryItemService.updateItemStatus(item.Id, 'Checked Out', borrowerId);
            
            result.isSuccess = true;
            result.message = 'Successfully Checked Out: ' + item.Item_Name__c;
            result.transactionId = borrowingRecord.Id;
            
            System.debug('Checkout successful: Item=' + item.Item_Name__c + ', Borrower=' + borrowerId);
            
        } catch (ItemNotFoundException e) {
            result.isSuccess = false;
            result.message = e.getMessage();
        } catch (ItemNotAvailableException e) {
            result.isSuccess = false;
            result.message = e.getMessage();
        } catch (BorrowingException e) {
            result.isSuccess = false;
            result.message = e.getMessage();
        } catch (Exception e) {
            result.isSuccess = false;
            result.message = 'Checkout failed: ' + e.getMessage();
            System.debug('Checkout error: ' + e.getMessage() + '\n' + e.getStackTraceString());
        }
        
        return result;
    }
    
    /**
     * Return an item
     */
    @AuraEnabled
    public static CheckoutResult returnItem(String itemCode) {
        CheckoutResult result = new CheckoutResult();
        
        try {
            if (String.isBlank(itemCode)) {
                throw new BorrowingException('Item code is required');
            }
            
            // Get the item
            Library_Item__c item = LibraryItemService.getItemByBarcode(itemCode);
            
            if (item == null) {
                throw new ItemNotFoundException('Item not found with code: ' + itemCode);
            }
            
            if (item.Current_Status__c == 'Available') {
                throw new BorrowingException('Item "' + item.Item_Name__c + '" is not currently Checked Out');
            }
            
            // Find and update active borrowing record
            Borrowing_Record__c activeRecord = getActiveBorrowingRecord(item.Id);
            
            if (activeRecord == null) {
                throw new BorrowingException('No active borrowing record found for this item');
            }
            
            // Process the return
            processReturn(activeRecord);
            
            // Update item status
            LibraryItemService.updateItemStatus(item.Id, 'Available', null);
            
            result.isSuccess = true;
            result.message = 'Successfully returned: ' + item.Item_Name__c;
            result.transactionId = activeRecord.Id;
            
            System.debug('Return successful: Item=' + item.Item_Name__c);
            
        } catch (ItemNotFoundException e) {
            result.isSuccess = false;
            result.message = e.getMessage();
        } catch (BorrowingException e) {
            result.isSuccess = false;
            result.message = e.getMessage();
        } catch (Exception e) {
            result.isSuccess = false;
            result.message = 'Return failed: ' + e.getMessage();
            System.debug('Return error: ' + e.getMessage() + '\n' + e.getStackTraceString());
        }
        
        return result;
    }
    
    /**
     * Renew an item
     */
    @AuraEnabled
    public static CheckoutResult renewItem(String itemCode, Id borrowerId) {
        CheckoutResult result = new CheckoutResult();
        
        try {
            if (String.isBlank(itemCode) || borrowerId == null) {
                throw new BorrowingException('Item code and borrower are required');
            }
            
            // Find the active borrowing record
            List<Borrowing_Record__c> records = [
                SELECT Id, Library_Item__r.Item_Name__c, Library_Item__r.Item_Type__c, 
                       Due_Date__c, Status__c
                FROM Borrowing_Record__c 
                WHERE Library_Item__r.Barcode__c = :itemCode 
                AND Borrower__c = :borrowerId
                AND Status__c IN ('Checked Out', 'Overdue')
                AND Return_Date__c = null
                LIMIT 1
            ];
            
            if (records.isEmpty()) {
                throw new BorrowingException('No active checkout found for renewal');
            }
            
            Borrowing_Record__c record = records[0];
            String itemType = record.Library_Item__r.Item_Type__c;
            
            // Check if renewal is allowed
            if (!isRenewalAllowed(itemType)) {
                throw new BorrowingException(itemType + ' items cannot be renewed');
            }
            
            // Calculate new due date
            Integer loanDays = LibraryConfigService.getLoanDays(itemType);
            Date newDueDate = Date.today().addDays(loanDays);
            
            // Update the record
            record.Due_Date__c = newDueDate;
            record.Status__c = 'Checked Out'; // Reset from Overdue if applicable
            update record;
            
            result.isSuccess = true;
            result.message = 'Successfully renewed: ' + record.Library_Item__r.Item_Name__c +
                ' (New due date: ' + newDueDate.format() + ')';
            result.transactionId = record.Id;
            
            System.debug('Renewal successful: Item=' + record.Library_Item__r.Item_Name__c +
                ', New due date=' + newDueDate);
            
        } catch (BorrowingException e) {
            result.isSuccess = false;
            result.message = e.getMessage();
        } catch (Exception e) {
            result.isSuccess = false;
            result.message = 'Renewal failed: ' + e.getMessage();
            System.debug('Renewal error: ' + e.getMessage() + '\n' + e.getStackTraceString());
        }
        
        return result;
    }
    
    /**
     * Get active borrowing records for a user
     */
    @AuraEnabled(cacheable=true)
    public static List<Borrowing_Record__c> getActiveBorrowings(Id borrowerId) {
        return [
            SELECT Id, Library_Item__r.Item_Name__c, Library_Item__r.Barcode__c,
                   Library_Item__r.Item_Type__c, Status__c, Checkout_Date__c, 
                   Due_Date__c, Notes__c
            FROM Borrowing_Record__c
            WHERE Borrower__c = :borrowerId
            AND Status__c IN ('Checked Out', 'Overdue')
            AND Return_Date__c = null
            ORDER BY Due_Date__c ASC
        ];
    }
    
    /**
     * Get borrowing history for a user
     */
    @AuraEnabled(cacheable=true)
    public static List<Borrowing_Record__c> getBorrowingHistory(Id borrowerId, Integer limitCount) {
        Integer queryLimit = limitCount != null ? limitCount : 50;
        
        return [
            SELECT Id, Library_Item__r.Item_Name__c, Library_Item__r.Barcode__c,
                   Library_Item__r.Item_Type__c, Status__c, Checkout_Date__c, 
                   Due_Date__c, Return_Date__c, Notes__c
            FROM Borrowing_Record__c
            WHERE Borrower__c = :borrowerId
            ORDER BY Checkout_Date__c DESC
            LIMIT :queryLimit
        ];
    }
    
    /**
     * Get overdue items
     */
    @AuraEnabled(cacheable=true)
    public static List<Borrowing_Record__c> getOverdueItems() {
        return [
            SELECT Id, Library_Item__r.Item_Name__c, Library_Item__r.Barcode__c,
                   Library_Item__r.Item_Type__c, Borrower__r.Name, Borrower__r.Email,
                   Status__c, Checkout_Date__c, Due_Date__c, Notes__c
            FROM Borrowing_Record__c
            WHERE Status__c = 'Overdue'
            AND Return_Date__c = null
            ORDER BY Due_Date__c ASC
        ];
    }
    
    // PRIVATE HELPER METHODS
    
    /**
     * Create a new borrowing record
     * FIXED: Now accepts Library_Item__c object instead of just ID
     */
    private static Borrowing_Record__c createBorrowingRecord(Library_Item__c item, Id borrowerId) {
        return new Borrowing_Record__c(
            Library_Item__c = item.Id,
        Borrower__c = borrowerId,
        Status__c = 'Checked Out',
        Checkout_Date__c = System.now(),
        Due_Date__c = calculateDueDate(item.Item_Type__c), // FIXED: Now using item type
        Checked_Out_By__c = UserInfo.getUserId()
            );
    }
    
    /**
     * Calculate due date based on item type
     * This method is correctly expecting itemType parameter
     */
    @AuraEnabled
    public static Date calculateDueDate(String itemType) {
        Integer loanDays = LibraryConfigService.getLoanDays(itemType);
        return Date.today().addDays(loanDays);
    }
    
    /**
     * Check if renewal is allowed for item type
     */
    private static Boolean isRenewalAllowed(String itemType) {
        // Updated to use LibraryConfigService directly
        return LibraryConfigService.allowRenewal(itemType);
    }
    
    /**
     * Validate borrowing limits
     */
    private static void validateBorrowingLimits(Id borrowerId, String itemType) {
        Integer maxItems = LibraryConfigService.getMaxItems(itemType);
        
        if (maxItems == null || maxItems == 0) {
            return; // No limit defined or unlimited
        }
        
        // Count current active borrowings for this item type
        Integer currentCount = [
            SELECT COUNT() 
            FROM Borrowing_Record__c 
            WHERE Borrower__c = :borrowerId
            AND Library_Item__r.Item_Type__c = :itemType
            AND Status__c IN ('Checked Out', 'Overdue')
            AND Return_Date__c = null
        ];
        
        if (currentCount >= maxItems) {
            throw new BorrowingException('You have reached the maximum number of items (' +
                maxItems + ') for ' + itemType + ' items.');
        }
    }
    
    /**
     * Get active borrowing record for an item
     */
    private static Borrowing_Record__c getActiveBorrowingRecord(Id itemId) {
        List<Borrowing_Record__c> records = [
            SELECT Id, Status__c, Checkout_Date__c
            FROM Borrowing_Record__c 
            WHERE Library_Item__c = :itemId 
            AND Status__c IN ('Checked Out', 'Overdue')
            AND Return_Date__c = null
            LIMIT 1
        ];
        
        return records.isEmpty() ? null : records[0];
    }
    
    /**
     * Process item return
     */
    private static void processReturn(Borrowing_Record__c record) {
        record.Return_Date__c = System.now();
        record.Status__c = 'Returned';
        update record;
    }
    
    /**
     * Result wrapper class
     */
    public class CheckoutResult {
        @AuraEnabled public Boolean isSuccess { get; set; }
        @AuraEnabled public String message { get; set; }
        @AuraEnabled public Id transactionId { get; set; }
        
        public CheckoutResult() {
            this.isSuccess = false;
        }
    }
}