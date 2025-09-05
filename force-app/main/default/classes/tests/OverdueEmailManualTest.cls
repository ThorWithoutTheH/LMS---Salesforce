public class OverdueEmailManualTest {
    
    // Method to create test data and send real email to rosa.vt@proton.me
    public static void sendTestEmailToRosa() {
        // Create a test user representing Rosa
        User rosaUser;
        try {
            rosaUser = [SELECT Id, Email FROM User WHERE Email = 'rosa.vt@proton.me' LIMIT 1];
            System.debug('Found existing user with email rosa.vt@proton.me');
        } catch(Exception e) {
            // Create user if doesn't exist
            Profile standardProfile = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
            rosaUser = new User(
                FirstName = 'Rosa',
            LastName = 'Library Test',
            Email = 'rosa.vt@proton.me',
            Username = 'rosa.library.test.' + System.currentTimeMillis() + '@test.com',
            Alias = 'rosalt',
            TimeZoneSidKey = 'America/New_York',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            ProfileId = standardProfile.Id,
            LanguageLocaleKey = 'en_US'
                );
            insert rosaUser;
            System.debug('Created new user with email rosa.vt@proton.me');
        }
        
        // Create test library items
        List<Library_Item__c> testItems = new List<Library_Item__c>();
        testItems.add(new Library_Item__c(
            Item_Name__c = 'Test Book - The Great Gatsby',
        Item_Type__c = 'Book',
        Category__c = 'Fiction',
        Author_Manufacturer__c = 'F. Scott Fitzgerald',
        Barcode__c = 'TEST-' + System.currentTimeMillis(),
        ISBN_Serial__c = 'ISBN-TEST-001',
        Current_Status__c = 'Checked_Out',
        Location__c = 'Test Shelf',
        Condition__c = 'Good',
        Current_Borrower__c = rosaUser.Id
            ));
        
        testItems.add(new Library_Item__c(
            Item_Name__c = 'Test DVD - The Matrix',
        Item_Type__c = 'DVD',
        Category__c = 'Science Fiction',
        Author_Manufacturer__c = 'Warner Bros',
        Barcode__c = 'TEST-DVD-' + System.currentTimeMillis(),
        ISBN_Serial__c = 'DVD-TEST-001',
        Current_Status__c = 'Checked_Out',
        Location__c = 'Media Section',
        Condition__c = 'Excellent',
        Current_Borrower__c = rosaUser.Id
            ));
        
        insert testItems;
        System.debug('Created ' + testItems.size() + ' test items');
        
        // Create overdue borrowing records
        List<Borrowing_Record__c> overdueRecords = new List<Borrowing_Record__c>();
        overdueRecords.add(new Borrowing_Record__c(
            Library_Item__c = testItems[0].Id,
        Borrower__c = rosaUser.Id,
        Status__c = 'Checked_Out',
        Checkout_Date__c = DateTime.now().addDays(-14),
        Due_Date__c = Date.today().addDays(-7), // 7 days overdue
        Checked_Out_By__c = UserInfo.getUserId()
            ));
        
        overdueRecords.add(new Borrowing_Record__c(
            Library_Item__c = testItems[1].Id,
        Borrower__c = rosaUser.Id,
        Status__c = 'Checked_Out',
        Checkout_Date__c = DateTime.now().addDays(-10),
        Due_Date__c = Date.today().addDays(-3), // 3 days overdue
        Checked_Out_By__c = UserInfo.getUserId()
            ));
        
        insert overdueRecords;
        System.debug('Created ' + overdueRecords.size() + ' overdue records');
        
        // Now run the scheduler to process and send emails
        System.debug('Starting batch job to process overdue items and send email...');
        Id batchId = Database.executeBatch(new OverdueItemScheduler(), 200);
        System.debug('Batch job started with ID: ' + batchId);
        System.debug('Email will be sent to: rosa.vt@proton.me');
        System.debug('Check Setup > Apex Jobs to monitor progress');
        
        return;
    }
    
    // Alternative: Send a test email directly without the scheduler
    public static void sendDirectTestEmail() {
        Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
        
        email.setToAddresses(new List<String>{'rosa.vt@proton.me'});
        email.setSubject('Library System Test: You have 2 overdue items');
        
        String emailBody = 'Dear Rosa,\n\n';
        emailBody += 'This is a TEST EMAIL from the Library Management System.\n\n';
        emailBody += 'The following items are overdue:\n\n';
        emailBody += '• The Great Gatsby by F. Scott Fitzgerald\n';
        emailBody += '  Barcode: BOOK-001\n';
        emailBody += '  Due Date: ' + Date.today().addDays(-7).format() + ' (7 days overdue)\n\n';
        emailBody += '• The Matrix (DVD)\n';
        emailBody += '  Barcode: DVD-001\n';
        emailBody += '  Due Date: ' + Date.today().addDays(-3).format() + ' (3 days overdue)\n\n';
        emailBody += 'Please return these items as soon as possible.\n\n';
        emailBody += 'This is a test email sent at: ' + DateTime.now().format() + '\n\n';
        emailBody += 'Thank you,\n';
        emailBody += 'Library Management System';
        
        email.setPlainTextBody(emailBody);
        email.setSaveAsActivity(false);
        
        try {
            Messaging.SendEmailResult[] results = Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{email});
            
            if(results[0].isSuccess()) {
                System.debug('✅ Test email sent successfully to rosa.vt@proton.me');
            } else {
                System.debug('❌ Failed to send email: ' + results[0].getErrors()[0].getMessage());
            }
        } catch(Exception e) {
            System.debug('❌ Error sending email: ' + e.getMessage());
        }
    }
}