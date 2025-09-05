@isTest
private class LibraryItemServiceTest {
    
    @isTest
    static void testCreateLibraryItem() {
        LibraryItemService.LibraryItemRequest request = new LibraryItemService.LibraryItemRequest();
        request.itemName = 'Test Book';
        request.itemType = 'Book';
        request.category = 'Fiction';
        request.barcode = 'TEST123456';
        request.location = 'Shelf A1';
        
        Test.startTest();
        Library_Item__c item = LibraryItemService.createLibraryItem(request);
        Test.stopTest();
        
        System.assertNotEquals(null, item);
        System.assertNotEquals(null, item.Id);
        System.assertEquals('Test Book', item.Item_Name__c);
        System.assertEquals('TEST123456', item.Barcode__c);
        System.assertEquals('Available', item.Current_Status__c);
    }
    
    @isTest
    static void testCreateItemWithAutoBarcode() {
        LibraryItemService.LibraryItemRequest request = new LibraryItemService.LibraryItemRequest();
        request.itemName = 'Test DVD';
        request.itemType = 'DVD';
        request.category = 'Action';
        // Don't set barcode - should auto-generate
        
        Test.startTest();
        Library_Item__c item = LibraryItemService.createLibraryItem(request);
        Test.stopTest();
        
        System.assertNotEquals(null, item.Barcode__c);
        System.assert(item.Barcode__c.startsWith('DVD'));
    }
    
    @isTest
    static void testUpdateLibraryItem() {
        Library_Item__c item = TestDataFactory.createLibraryItems(1)[0];
        
        LibraryItemService.LibraryItemRequest request = new LibraryItemService.LibraryItemRequest();
        request.itemName = 'Updated Book Name';
        request.location = 'New Shelf B2';
        
        Test.startTest();
        Library_Item__c updatedItem = LibraryItemService.updateLibraryItem(item.Id, request);
        Test.stopTest();
        
        System.assertEquals('Updated Book Name', updatedItem.Item_Name__c);
        System.assertEquals('New Shelf B2', updatedItem.Location__c);
    }
    
    @isTest
    static void testDeleteLibraryItem() {
        Library_Item__c item = TestDataFactory.createLibraryItems(1)[0];
        
        Test.startTest();
        LibraryItemService.DeleteResult result = LibraryItemService.deleteLibraryItem(item.Id);
        Test.stopTest();
        
        System.assert(result.isSuccess);
        
        List<Library_Item__c> items = [SELECT Id FROM Library_Item__c WHERE Id = :item.Id];
        System.assertEquals(0, items.size());
    }
    
    @isTest
    static void testDeleteCheckedOutItem() {
        Library_Item__c item = TestDataFactory.createLibraryItems(1)[0];
        item.Current_Status__c = 'Checked Out';
        item.Current_Borrower__c = UserInfo.getUserId();
        update item;
        
        Test.startTest();
        LibraryItemService.DeleteResult result = LibraryItemService.deleteLibraryItem(item.Id);
        Test.stopTest();
        
        System.assertEquals(false, result.isSuccess);
        System.assert(result.message.contains('currently checked out'));
    }
    
    @isTest
    static void testGetItemStatistics() {
        List<Library_Item__c> items = TestDataFactory.createLibraryItems(10);
        items[0].Current_Status__c = 'Checked Out';
        items[1].Current_Status__c = 'Overdue';
        update items;
        
        Test.startTest();
        LibraryItemService.ItemStatistics stats = LibraryItemService.getItemStatistics();
        Test.stopTest();
        
        System.assertEquals(10, stats.totalCount);
        System.assert(stats.availableCount > 0);
    }
    
    @isTest
    static void testBatchCreation() {
        List<LibraryItemService.LibraryItemRequest> requests =
            new List<LibraryItemService.LibraryItemRequest>();
        
        for(Integer i = 0; i < 3; i++) {
            LibraryItemService.LibraryItemRequest req = new LibraryItemService.LibraryItemRequest();
            req.itemName = 'Batch Item ' + i;
            req.itemType = 'Book';
            req.category = 'Test';
            requests.add(req);
        }
        
        Test.startTest();
        LibraryItemService.BatchCreationResult result =
            LibraryItemService.createItemsWithPartialSuccess(requests);
        Test.stopTest();
        
        System.assertEquals(3, result.successCount);
        System.assertEquals(0, result.errorCount);
        System.assertEquals(3, result.createdItems.size());
    }
}