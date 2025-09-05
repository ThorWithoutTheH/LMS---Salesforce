@isTest
public class TestDataFactory {
    
    public static User createLibrarian() {
        Profile librarianProfile = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        User librarian = new User(
            FirstName = 'Test',
        LastName = 'Librarian',
        Email = 'librarian@test.com',
        Username = 'librarian@test' + System.now().getTime() + '.com',
        Alias = 'tlib',
        TimeZoneSidKey = 'America/New_York',
        LocaleSidKey = 'en_US',
        EmailEncodingKey = 'UTF-8',
        ProfileId = librarianProfile.Id,
        LanguageLocaleKey = 'en_US'
            );
        insert librarian;
        
        // Assign Library_Admin permission set if it exists
        try {
            PermissionSet ps = [SELECT Id FROM PermissionSet WHERE Name = 'Library_Admin' LIMIT 1];
            insert new PermissionSetAssignment(
                AssigneeId = librarian.Id,
            PermissionSetId = ps.Id
                );
        } catch(Exception e) {
            // Permission set doesn't exist in test context
        }
        
        return librarian;
    }
    
    public static User createStandardUser() {
        Profile standardProfile = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        User standardUser = new User(
            FirstName = 'Test',
        LastName = 'User',
        Email = 'user@test.com',
        Username = 'user@test' + System.now().getTime() + '.com',
        Alias = 'tuser',
        TimeZoneSidKey = 'America/New_York',
        LocaleSidKey = 'en_US',
        EmailEncodingKey = 'UTF-8',
        ProfileId = standardProfile.Id,
        LanguageLocaleKey = 'en_US'
            );
        insert standardUser;
        return standardUser;
    }
    
    public static List<Library_Item__c> createLibraryItems(Integer count) {
        List<Library_Item__c> items = new List<Library_Item__c>();
        
        for(Integer i = 0; i < count; i++) {
            items.add(new Library_Item__c(
                Item_Name__c = 'Test Book ' + i,
            Barcode__c = 'TEST' + String.valueOf(1000 + i).leftPad(6, '0'),
            Item_Type__c = 'Book',
            Category__c = 'Fiction',
            Current_Status__c = 'Available',
            Location__c = 'Shelf A' + i,
            Author_Manufacturer__c = 'Test Author ' + i,
            ISBN_Serial__c = 'ISBN' + String.valueOf(1000000 + i),
            Condition__c = 'Good',
            Purchase_Date__c = Date.today().addDays(-30),
            Notes__c = 'Test notes for item ' + i
                ));
        }
        
        insert items;
        return items;
    }
    
    public static Borrowing_Record__c createBorrowingRecord(Id itemId, Id borrowerId, String status) {
        Borrowing_Record__c record = new Borrowing_Record__c(
            Library_Item__c = itemId,
        Borrower__c = borrowerId,
        Status__c = status,
        Checkout_Date__c = DateTime.now().addDays(-7),
        Due_Date__c = Date.today().addDays(7),
        Checked_Out_By__c = UserInfo.getUserId()
            );
        insert record;
        return record;
    }
}