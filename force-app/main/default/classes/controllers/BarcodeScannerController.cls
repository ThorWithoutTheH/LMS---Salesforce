public with sharing class BarcodeScannerController {
    
    /**
     * Process single barcode scan - leverages existing BorrowingRecordService
     */
    @AuraEnabled
    public static ScanResult processBarcodeAction(String barcode, String action, Id userId) {
        ScanResult result = new ScanResult();
        
        try {
            // Validate inputs
            if(String.isBlank(barcode)) {
                throw new AuraHandledException('Barcode cannot be empty');
            }
            
            // Default to current user if not specified
            if(userId == null) {
                userId = UserInfo.getUserId();
            }
            
            // Process based on action using existing services
            if(action == 'checkout') {
                result = performCheckout(barcode, userId);
            } else if(action == 'return') {
                result = performReturn(barcode);
            } else if(action == 'info') {
                result = getItemInfo(barcode);
            } else {
                result.success = false;
                result.message = 'Invalid action: ' + action;
                result.messageType = 'error';
            }
            
        } catch(Exception e) {
            result.success = false;
            result.message = e.getMessage();
            result.messageType = 'error';
        }
        
        return result;
    }
    
    /**
     * Checkout using existing BorrowingRecordService
     */
    private static ScanResult performCheckout(String barcode, Id borrowerId) {
        ScanResult result = new ScanResult();
        
        // Use existing service
        BorrowingRecordService.CheckoutResult serviceResult =
            BorrowingRecordService.checkoutItem(barcode, borrowerId);
        
        // Map service result to scan result
        result.success = serviceResult.isSuccess;
        result.message = serviceResult.message;
        result.messageType = serviceResult.isSuccess ? 'success' : 'error';
        result.recordId = serviceResult.transactionId;
        
        // Get item details for UI
        if(serviceResult.isSuccess) {
            Library_Item__c item = LibraryItemService.getItemByBarcode(barcode);
            result.itemDetails = buildItemDetails(item);
        }
        
        return result;
    }
    
    /**
     * Return using existing BorrowingRecordService
     */
    private static ScanResult performReturn(String barcode) {
        ScanResult result = new ScanResult();
        
        // Use existing service
        BorrowingRecordService.CheckoutResult serviceResult =
            BorrowingRecordService.returnItem(barcode);
        
        // Map service result
        result.success = serviceResult.isSuccess;
        result.message = serviceResult.message;
        result.messageType = serviceResult.isSuccess ? 'success' : 'error';
        result.recordId = serviceResult.transactionId;
        
        // Get item details
        if(serviceResult.isSuccess) {
            Library_Item__c item = LibraryItemService.getItemByBarcode(barcode);
            result.itemDetails = buildItemDetails(item);
        }
        
        return result;
    }
    
    /**
     * Get item info using existing services
     */
    private static ScanResult getItemInfo(String barcode) {
        ScanResult result = new ScanResult();
        
        Library_Item__c item = LibraryItemService.getItemByBarcode(barcode);
        
        if(item == null) {
            result.success = false;
            result.message = 'Item not found with barcode: ' + barcode;
            result.messageType = 'error';
            return result;
        }
        
        result.success = true;
        result.itemDetails = buildItemDetails(item);
        
        if(item.Current_Borrower__c != null) {
            User borrower = [SELECT Name FROM User WHERE Id = :item.Current_Borrower__c LIMIT 1];
            
            // Get active borrowing for due date
            List<Borrowing_Record__c> activeRecords = BorrowingRecordService.getActiveBorrowings(item.Current_Borrower__c);
            Borrowing_Record__c itemRecord = null;
            
            for(Borrowing_Record__c rec : activeRecords) {
                if(rec.Library_Item__c == item.Id) {
                    itemRecord = rec;
                    break;
                }
            }
            
            if(itemRecord != null) {
                String dueInfo = itemRecord.Due_Date__c.format();
                if(itemRecord.Status__c == 'Overdue') {
                    dueInfo += ' - OVERDUE';
                }
                result.message = String.format('Checked Out to: {0} (Due: {1})',
                new List<String>{borrower.Name, dueInfo});
                result.messageType = itemRecord.Status__c == 'Overdue' ? 'warning' : 'info';
            } else {
                result.message = 'Checked Out to: ' + borrower.Name;
                result.messageType = 'info';
            }
        } else {
            result.message = 'Item is available for checkout';
            result.messageType = 'success';
        }
        
        return result;
    }
    
    /**
     * Build item details for UI display
     */
    private static Map<String, Object> buildItemDetails(Library_Item__c item) {
        if(item == null) return new Map<String, Object>();
        
        Map<String, Object> details = new Map<String, Object>{
            'id' => item.Id,
            'name' => item.Name,
            'itemName' => item.Item_Name__c,
            'barcode' => item.Barcode__c,
            'type' => item.Item_Type__c,
            'category' => item.Category__c,
            'status' => item.Current_Status__c,
            'location' => item.Location__c,
            'author' => item.Author_Manufacturer__c,
            'isbn' => item.ISBN_Serial__c,
            'condition' => item.Condition__c,
            'isAvailable' => item.Current_Borrower__c == null
        };
        
        if(item.Current_Borrower__c != null) {
            details.put('currentBorrowerId', item.Current_Borrower__c);
            // Get borrower name if available
            if(item.Current_Borrower__r != null) {
                details.put('currentBorrower', item.Current_Borrower__r.Name);
            }
        }
        
        return details;
    }
    
    /**
     * Process multiple barcodes
     */
    @AuraEnabled
    public static BatchScanResult processBulkScan(List<String> barcodes, String action, Id userId) {
        BatchScanResult batchResult = new BatchScanResult();
        batchResult.results = new List<ScanResult>();
        
        for(String barcode : barcodes) {
            ScanResult result = processBarcodeAction(barcode, action, userId);
            batchResult.results.add(result);
            
            if(result.success) {
                batchResult.successCount++;
            } else {
                batchResult.errorCount++;
            }
        }
        
        batchResult.totalProcessed = barcodes.size();
        return batchResult;
    }
    
    /**
     * Renew item - wraps existing service
     */
    @AuraEnabled
    public static ScanResult renewItem(String barcode, Id userId) {
        ScanResult result = new ScanResult();
        
        try {
            BorrowingRecordService.CheckoutResult serviceResult =
                BorrowingRecordService.renewItem(barcode, userId);
            
            result.success = serviceResult.isSuccess;
            result.message = serviceResult.message;
            result.messageType = serviceResult.isSuccess ? 'success' : 'error';
            result.recordId = serviceResult.transactionId;
            
            if(serviceResult.isSuccess) {
                Library_Item__c item = LibraryItemService.getItemByBarcode(barcode);
                result.itemDetails = buildItemDetails(item);
            }
        } catch(Exception e) {
            result.success = false;
            result.message = e.getMessage();
            result.messageType = 'error';
        }
        
        return result;
    }
    
    @AuraEnabled(cacheable=true)
    public static List<BorrowingRecordWrapper> getMyCheckedOutItems() {
        List<BorrowingRecordWrapper> wrappers = new List<BorrowingRecordWrapper>();
        List<Borrowing_Record__c> records = BorrowingRecordService.getActiveBorrowings(UserInfo.getUserId());
        
        for(Borrowing_Record__c rec : records) {
            BorrowingRecordWrapper wrapper = new BorrowingRecordWrapper();
            wrapper.recordId = rec.Id;
            wrapper.itemName = rec.Library_Item__r.Item_Name__c;
            wrapper.barcode = rec.Library_Item__r.Barcode__c;
            wrapper.itemType = rec.Library_Item__r.Item_Type__c;
            wrapper.checkoutDate = rec.Checkout_Date__c;
            wrapper.dueDate = rec.Due_Date__c;
            wrapper.status = rec.Status__c;
            wrapper.isOverdue = rec.Status__c == 'Overdue';
            wrapper.canRenew = LibraryConfigService.allowRenewal(rec.Library_Item__r.Item_Type__c);
            wrappers.add(wrapper);
        }
        
        return wrappers;
    }
    
    /**
     * Search items using existing service
     */
    @AuraEnabled(cacheable=true)
    public static List<Library_Item__c> searchItems(String searchTerm, String itemType, String status) {
        return LibraryItemService.searchLibraryItems(searchTerm, itemType, status);
    }
    
    /**
     * Get statistics using existing service
     */
    @AuraEnabled(cacheable=true)
    public static LibraryItemService.ItemStatistics getLibraryStatistics() {
        return LibraryItemService.getItemStatistics();
    }
    
    /**
     * Result wrapper classes
     */
    public class ScanResult {
        @AuraEnabled public Boolean success;
        @AuraEnabled public String message;
        @AuraEnabled public String messageType;
        @AuraEnabled public Map<String, Object> itemDetails;
        @AuraEnabled public Id recordId;
        
        public ScanResult() {
            this.success = false;
            this.itemDetails = new Map<String, Object>();
        }
    }
    
    public class BatchScanResult {
        @AuraEnabled public List<ScanResult> results;
        @AuraEnabled public Integer totalProcessed = 0;
        @AuraEnabled public Integer successCount = 0;
        @AuraEnabled public Integer errorCount = 0;
    }
    
    public class BorrowingRecordWrapper {
        @AuraEnabled public Id recordId;
        @AuraEnabled public String itemName;
        @AuraEnabled public String barcode;
        @AuraEnabled public String itemType;
        @AuraEnabled public DateTime checkoutDate;
        @AuraEnabled public Date dueDate;
        @AuraEnabled public String status;
        @AuraEnabled public Boolean isOverdue;
        @AuraEnabled public String statusBadgeClass;
        @AuraEnabled public Boolean canRenew;
    }
}