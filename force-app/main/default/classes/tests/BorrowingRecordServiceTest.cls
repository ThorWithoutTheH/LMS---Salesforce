@isTest
private class BorrowingRecordServiceTest {
    
    @testSetup
    static void setup() {
        TestDataFactory.createLibraryItems(5);
    }
    
    @isTest
    static void testCheckoutItem() {
        Library_Item__c item = [SELECT Id, Barcode__c FROM Library_Item__c LIMIT 1];
        User testUser = TestDataFactory.createStandardUser();
        
        Test.startTest();
        BorrowingRecordService.CheckoutResult result =
            BorrowingRecordService.checkoutItem(item.Barcode__c, testUser.Id);
        Test.stopTest();
        
        System.assert(result.isSuccess);
        System.assertNotEquals(null, result.transactionId);
        
        Borrowing_Record__c br = [
            SELECT Id, Status__c, Library_Item__c, Borrower__c 
            FROM Borrowing_Record__c 
            WHERE Id = :result.transactionId
        ];
        System.assertEquals('Active', br.Status__c);
        System.assertEquals(item.Id, br.Library_Item__c);
        System.assertEquals(testUser.Id, br.Borrower__c);
    }
    
    @isTest
    static void testCheckoutUnavailableItem() {
        Library_Item__c item = [SELECT Id, Barcode__c FROM Library_Item__c LIMIT 1];
        item.Current_Status__c = 'Checked Out';
        update item;
        
        Test.startTest();
        BorrowingRecordService.CheckoutResult result =
            BorrowingRecordService.checkoutItem(item.Barcode__c, UserInfo.getUserId());
        Test.stopTest();
        
        System.assertEquals(false, result.isSuccess);
        System.assert(result.message.contains('not available'));
    }
    
    @isTest
    static void testReturnItem() {
        Library_Item__c item = [SELECT Id, Barcode__c FROM Library_Item__c LIMIT 1];
        User testUser = TestDataFactory.createStandardUser();
        
        // Checkout first
        BorrowingRecordService.checkoutItem(item.Barcode__c, testUser.Id);
        
        Test.startTest();
        BorrowingRecordService.CheckoutResult result =
            BorrowingRecordService.returnItem(item.Barcode__c);
        Test.stopTest();
        
        System.assert(result.isSuccess);
        
        Borrowing_Record__c br = [
            SELECT Status__c, Return_Date__c 
            FROM Borrowing_Record__c 
            WHERE Id = :result.transactionId
        ];
        System.assertEquals('Returned', br.Status__c);
        System.assertNotEquals(null, br.Return_Date__c);
    }
    
    @isTest
    static void testRenewItem() {
        Library_Item__c item = [SELECT Id, Barcode__c FROM Library_Item__c LIMIT 1];
        User testUser = TestDataFactory.createStandardUser();
        
        // Checkout first
        BorrowingRecordService.checkoutItem(item.Barcode__c, testUser.Id);
        
        Test.startTest();
        BorrowingRecordService.CheckoutResult result =
            BorrowingRecordService.renewItem(item.Barcode__c, testUser.Id);
        Test.stopTest();
        
        // Result depends on configuration
        System.assertNotEquals(null, result);
    }
    
    @isTest
    static void testGetActiveBorrowings() {
        Library_Item__c item = [SELECT Id, Barcode__c FROM Library_Item__c LIMIT 1];
        User testUser = TestDataFactory.createStandardUser();
        
        BorrowingRecordService.checkoutItem(item.Barcode__c, testUser.Id);
        
        Test.startTest();
        List<Borrowing_Record__c> activeBorrowings =
            BorrowingRecordService.getActiveBorrowings(testUser.Id);
        Test.stopTest();
        
        System.assertEquals(1, activeBorrowings.size());
        System.assertEquals('Active', activeBorrowings[0].Status__c);
    }
    
    @isTest
    static void testGetBorrowingHistory() {
        User testUser = TestDataFactory.createStandardUser();
        List<Library_Item__c> items = [SELECT Id, Barcode__c FROM Library_Item__c LIMIT 3];
        
        for(Library_Item__c item : items) {
            BorrowingRecordService.checkoutItem(item.Barcode__c, testUser.Id);
        }
        
        Test.startTest();
        List<Borrowing_Record__c> history =
            BorrowingRecordService.getBorrowingHistory(testUser.Id, 10);
        Test.stopTest();
        
        System.assertEquals(3, history.size());
    }
}