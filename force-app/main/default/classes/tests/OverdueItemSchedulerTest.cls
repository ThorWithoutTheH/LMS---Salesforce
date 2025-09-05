@isTest
public class OverdueItemSchedulerTest {
    
    @testSetup
    static void setupTestData() {
        // Create test user with specific email
        Profile standardProfile = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        User testBorrower = new User(
            FirstName = 'Rosa',
        LastName = 'Test Borrower',
        Email = 'rosa.vt@proton.me',  // This email will be used in test context
        Username = 'rosa.test.borrower' + System.currentTimeMillis() + '@library.test',
        Alias = 'rosatest',
        TimeZoneSidKey = 'America/New_York',
        LocaleSidKey = 'en_US',
        EmailEncodingKey = 'UTF-8',
        ProfileId = standardProfile.Id,
        LanguageLocaleKey = 'en_US'
            );
        insert testBorrower;
        
        // Create library items
        List<Library_Item__c> items = new List<Library_Item__c>();
        items.add(new Library_Item__c(
            Item_Name__c = 'The Great Gatsby',
        Item_Type__c = 'Book',
        Category__c = 'Fiction',
        Author_Manufacturer__c = 'F. Scott Fitzgerald',
        Barcode__c = 'BOOK-001-TEST',
        ISBN_Serial__c = 'ISBN-123456789',
        Current_Status__c = 'Checked_Out',
        Location__c = 'Shelf A-1',
        Condition__c = 'Good',
        Current_Borrower__c = testBorrower.Id
            ));
        
        items.add(new Library_Item__c(
            Item_Name__c = 'To Kill a Mockingbird',
        Item_Type__c = 'Book',
        Category__c = 'Fiction',
        Author_Manufacturer__c = 'Harper Lee',
        Barcode__c = 'BOOK-002-TEST',
        ISBN_Serial__c = 'ISBN-987654321',
        Current_Status__c = 'Checked_Out',
        Location__c = 'Shelf A-2',
        Condition__c = 'Excellent',
        Current_Borrower__c = testBorrower.Id
            ));
        
        items.add(new Library_Item__c(
            Item_Name__c = 'The Matrix',
        Item_Type__c = 'DVD',
        Category__c = 'Science Fiction',
        Author_Manufacturer__c = 'Warner Bros',
        Barcode__c = 'DVD-001-TEST',
        ISBN_Serial__c = 'DVD-123456',
        Current_Status__c = 'Checked_Out',
        Location__c = 'Media Section B',
        Condition__c = 'Good',
        Current_Borrower__c = testBorrower.Id
            ));
        
        insert items;
        
        // Create overdue borrowing records
        List<Borrowing_Record__c> borrowingRecords = new List<Borrowing_Record__c>();
        
        // Record 1: 7 days overdue
        borrowingRecords.add(new Borrowing_Record__c(
            Library_Item__c = items[0].Id,
        Borrower__c = testBorrower.Id,
        Status__c = 'Checked_Out',
        Checkout_Date__c = DateTime.now().addDays(-21),
        Due_Date__c = Date.today().addDays(-7),
        Checked_Out_By__c = UserInfo.getUserId()
            ));
        
        // Record 2: 14 days overdue
        borrowingRecords.add(new Borrowing_Record__c(
            Library_Item__c = items[1].Id,
        Borrower__c = testBorrower.Id,
        Status__c = 'Checked_Out',
        Checkout_Date__c = DateTime.now().addDays(-28),
        Due_Date__c = Date.today().addDays(-14),
        Checked_Out_By__c = UserInfo.getUserId()
            ));
        
        // Record 3: 3 days overdue
        borrowingRecords.add(new Borrowing_Record__c(
            Library_Item__c = items[2].Id,
        Borrower__c = testBorrower.Id,
        Status__c = 'Checked_Out',
        Checkout_Date__c = DateTime.now().addDays(-17),
        Due_Date__c = Date.today().addDays(-3),
        Checked_Out_By__c = UserInfo.getUserId()
            ));
        
        insert borrowingRecords;
    }
    
    @isTest
    static void testScheduledExecution() {
        Test.startTest();
        
        // Schedule the job
        String cronExp = '0 0 1 * * ?';
        String jobId = System.schedule('Test Overdue Scheduler', cronExp, new OverdueItemScheduler());
        
        // Get the scheduled job
        CronTrigger ct = [
            SELECT Id, CronExpression, TimesTriggered, NextFireTime
            FROM CronTrigger
            WHERE Id = :jobId
        ];
        
        // Verify the job was scheduled correctly
        System.assertEquals(cronExp, ct.CronExpression, 'Cron expression should match');
        System.assertEquals(0, ct.TimesTriggered, 'Job should not have run yet');
        
        Test.stopTest();
    }
    
    @isTest
    static void testBatchExecution() {
        // Get initial counts
        Integer initialOverdueCount = [
            SELECT COUNT() 
            FROM Borrowing_Record__c 
            WHERE Status__c = 'Checked_Out' 
            AND Due_Date__c < TODAY
        ];
        System.assertEquals(3, initialOverdueCount, 'Should have 3 overdue records');
        
        Test.startTest();
        
        // Run the batch job
        OverdueItemScheduler scheduler = new OverdueItemScheduler();
        Id batchId = Database.executeBatch(scheduler);
        
        Test.stopTest();
        
        // Verify records were updated to Overdue status
        List<Borrowing_Record__c> updatedRecords = [
            SELECT Id, Status__c, Due_Date__c 
            FROM Borrowing_Record__c 
            WHERE Status__c = 'Overdue'
        ];
        System.assertEquals(3, updatedRecords.size(), 'All 3 records should be marked as Overdue');
        
        // Verify library items were updated
        List<Library_Item__c> updatedItems = [
            SELECT Id, Current_Status__c 
            FROM Library_Item__c 
            WHERE Current_Status__c = 'Overdue'
        ];
        System.assertEquals(3, updatedItems.size(), 'All 3 items should be marked as Overdue');
        
        // Verify emails were queued (in test context, emails are not actually sent)
        System.assertEquals(1, Limits.getEmailInvocations(), 'Email should have been invoked');
    }
    
    @isTest
    static void testEmailGeneration() {
        // Get test data
        User testBorrower = [SELECT Id, Email, FirstName, Name FROM User WHERE Email = 'rosa.vt@proton.me' LIMIT 1];
        List<Borrowing_Record__c> overdueRecords = [
            SELECT Id, Status__c, Due_Date__c, Checkout_Date__c,
                   Library_Item__r.Item_Name__c,
                   Library_Item__r.Author_Manufacturer__c,
                   Library_Item__r.Barcode__c,
                   Library_Item__r.Item_Type__c,
                   Borrower__r.Name,
                   Borrower__r.Email,
                   Borrower__r.FirstName
            FROM Borrowing_Record__c
            WHERE Borrower__c = :testBorrower.Id
        ];
        
        System.assertEquals(3, overdueRecords.size(), 'Should have 3 overdue records for test borrower');
        
        Test.startTest();
        
        // Run the batch
        OverdueItemScheduler scheduler = new OverdueItemScheduler();
        Database.executeBatch(scheduler);
        
        Test.stopTest();
        
        // Verify the batch processed records
        System.assertEquals(3, scheduler.totalOverdueItems, 'Should have processed 3 overdue items');
        System.assert(scheduler.overdueByBorrower.containsKey(testBorrower.Id), 'Should track borrower in map');
    }
    
    @isTest
    static void testNoOverdueRecords() {
        // Delete all overdue records
        delete [SELECT Id FROM Borrowing_Record__c];
        
        // Create a non-overdue record
        User testUser = [SELECT Id FROM User WHERE Email = 'rosa.vt@proton.me' LIMIT 1];
        Library_Item__c item = [SELECT Id FROM Library_Item__c LIMIT 1];
        
        Borrowing_Record__c currentRecord = new Borrowing_Record__c(
            Library_Item__c = item.Id,
        Borrower__c = testUser.Id,
        Status__c = 'Checked_Out',
        Checkout_Date__c = DateTime.now(),
        Due_Date__c = Date.today().addDays(7), // Due in future
        Checked_Out_By__c = UserInfo.getUserId()
            );
        insert currentRecord;
        
        Test.startTest();
        
        OverdueItemScheduler scheduler = new OverdueItemScheduler();
        Database.executeBatch(scheduler);
        
        Test.stopTest();
        
        // Verify no records were marked as overdue
        List<Borrowing_Record__c> overdueRecords = [
            SELECT Id FROM Borrowing_Record__c WHERE Status__c = 'Overdue'
        ];
        System.assertEquals(0, overdueRecords.size(), 'No records should be marked as overdue');
    }
    
    @isTest
    static void testStatefulBehavior() {
        Test.startTest();
        
        OverdueItemScheduler scheduler = new OverdueItemScheduler();
        Database.executeBatch(scheduler, 1); // Process one record at a time
        
        Test.stopTest();
        
        // Verify stateful properties were maintained
        System.assert(scheduler.totalOverdueItems > 0, 'Should track total overdue items');
        System.assert(!scheduler.overdueByItemType.isEmpty(), 'Should track items by type');
    }
}