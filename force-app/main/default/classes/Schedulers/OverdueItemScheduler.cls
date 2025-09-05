global class OverdueItemScheduler implements Schedulable, Database.Batchable<sObject>, Database.Stateful {
    
    // Track statistics for summary email
    global Integer totalOverdueItems = 0;
    global Integer totalEmailsSent = 0;
    global Map<String, Integer> overdueByItemType = new Map<String, Integer>();
    global List<String> errorMessages = new List<String>();
    global Map<Id, List<Borrowing_Record__c>> overdueByBorrower = new Map<Id, List<Borrowing_Record__c>>();
    
    global void execute(SchedulableContext ctx) {
        Database.executeBatch(new OverdueItemScheduler(), 200);
    }
    
    global Database.QueryLocator start(Database.BatchableContext bc) {
        // Query with all needed fields including borrower email through User lookup
        return Database.getQueryLocator([
            SELECT Id, Status__c, Due_Date__c, Library_Item__c,
                   Library_Item__r.Item_Name__c, 
                   Library_Item__r.Item_Type__c,
                   Library_Item__r.Barcode__c,
                   Library_Item__r.Author_Manufacturer__c,
                   Borrower__c,
                   Borrower__r.Name,
                   Borrower__r.Email,
                   Borrower__r.FirstName,
                   Checkout_Date__c
            FROM Borrowing_Record__c
            WHERE Status__c = 'Checked_Out'
            AND Due_Date__c < TODAY
            AND Return_Date__c = null
        ]);
    }
    
    global void execute(Database.BatchableContext bc, List<Borrowing_Record__c> scope) {
        List<Borrowing_Record__c> recordsToUpdate = new List<Borrowing_Record__c>();
        Set<Id> itemIds = new Set<Id>();
        List<Messaging.SingleEmailMessage> emailsToSend = new List<Messaging.SingleEmailMessage>();
        
        // Group overdue records by borrower for consolidated emails
        Map<Id, List<Borrowing_Record__c>> currentBatchByBorrower = new Map<Id, List<Borrowing_Record__c>>();
        
        for(Borrowing_Record__c record : scope) {
            // Update status to Overdue
            record.Status__c = 'Overdue';
            recordsToUpdate.add(record);
            itemIds.add(record.Library_Item__c);
            
            // Track statistics
            totalOverdueItems++;
            String itemType = record.Library_Item__r.Item_Type__c;
            overdueByItemType.put(itemType, overdueByItemType.containsKey(itemType) ?
                overdueByItemType.get(itemType) + 1 : 1);
            
            // Group by borrower for email
            if(record.Borrower__c != null) {
                if(!currentBatchByBorrower.containsKey(record.Borrower__c)) {
                    currentBatchByBorrower.put(record.Borrower__c, new List<Borrowing_Record__c>());
                }
                currentBatchByBorrower.get(record.Borrower__c).add(record);
                
                // Also track for summary report
                if(!overdueByBorrower.containsKey(record.Borrower__c)) {
                    overdueByBorrower.put(record.Borrower__c, new List<Borrowing_Record__c>());
                }
                overdueByBorrower.get(record.Borrower__c).add(record);
            }
        }
        
        // Update borrowing records
        if(!recordsToUpdate.isEmpty()) {
            try {
                update recordsToUpdate;
                
                // Update item status to Overdue
                List<Library_Item__c> itemsToUpdate = [
                    SELECT Id FROM Library_Item__c WHERE Id IN :itemIds
                ];
                for(Library_Item__c item : itemsToUpdate) {
                    item.Current_Status__c = 'Overdue';
                }
                update itemsToUpdate;
            } catch(Exception e) {
                errorMessages.add('Error updating records: ' + e.getMessage());
            }
        }
        
        // Check if email notifications are enabled in configuration
        if(shouldSendEmails()) {
            // Create email for each borrower in this batch
            for(Id borrowerId : currentBatchByBorrower.keySet()) {
                List<Borrowing_Record__c> borrowerRecords = currentBatchByBorrower.get(borrowerId);
                if(!borrowerRecords.isEmpty() && borrowerRecords[0].Borrower__r.Email != null) {
                    Messaging.SingleEmailMessage email = createOverdueEmail(
                        borrowerRecords[0].Borrower__r,
                    borrowerRecords
                        );
                    if(email != null) {
                        emailsToSend.add(email);
                    }
                }
            }
            
            // Send emails (respecting governor limits)
            if(!emailsToSend.isEmpty()) {
                try {
                    List<Messaging.SendEmailResult> results = Messaging.sendEmail(emailsToSend, false);
                    for(Messaging.SendEmailResult result : results) {
                        if(result.isSuccess()) {
                            totalEmailsSent++;
                        } else {
                            for(Messaging.SendEmailError error : result.getErrors()) {
                                errorMessages.add('Email error: ' + error.getMessage());
                            }
                        }
                    }
                } catch(Exception e) {
                    errorMessages.add('Error sending emails: ' + e.getMessage());
                }
            }
        }
    }
    
    global void finish(Database.BatchableContext bc) {
        // Send summary email to library administrators
        if(totalOverdueItems > 0 && shouldSendSummaryEmail()) {
            sendSummaryEmail();
        }
    }
    
    // Check if email notifications are enabled in configuration
    private Boolean shouldSendEmails() {
        try {
            Map<String, Object> config = LibraryConfigService.getGlobalSettings();
            if(config != null && config.containsKey('sendOverdueEmails')) {
                return (Boolean)config.get('sendOverdueEmails');
            }
        } catch(Exception e) {
            System.debug('Error reading email configuration: ' + e.getMessage());
        }
        // Default to true if not configured
        return true;
    }
    
    // Check if summary emails should be sent
    private Boolean shouldSendSummaryEmail() {
        try {
            Map<String, Object> config = LibraryConfigService.getGlobalSettings();
            if(config != null && config.containsKey('sendSummaryEmails')) {
                return (Boolean)config.get('sendSummaryEmails');
            }
        } catch(Exception e) {
            System.debug('Error reading summary email configuration: ' + e.getMessage());
        }
        return true;
    }
    
    // Create email for individual borrower
    private Messaging.SingleEmailMessage createOverdueEmail(User borrower, List<Borrowing_Record__c> overdueRecords) {
        Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
        
        // Set recipient
        email.setToAddresses(new List<String>{borrower.Email});
        email.setSubject('Library Notice: You have ' + overdueRecords.size() + ' overdue item(s)');
        
        // Build email body
        String emailBody = 'Dear ' + (borrower.FirstName != null ? borrower.FirstName : borrower.Name) + ',\n\n';
        emailBody += 'The following library item(s) are overdue and need to be returned:\n\n';
        
        for(Borrowing_Record__c record : overdueRecords) {
            Integer daysOverdue = record.Due_Date__c.daysBetween(Date.today());
            emailBody += '• ' + record.Library_Item__r.Item_Name__c;
            if(record.Library_Item__r.Author_Manufacturer__c != null) {
                emailBody += ' by ' + record.Library_Item__r.Author_Manufacturer__c;
            }
            emailBody += '\n';
            emailBody += '  Barcode: ' + record.Library_Item__r.Barcode__c + '\n';
            emailBody += '  Due Date: ' + record.Due_Date__c.format() + ' (' + daysOverdue + ' days overdue)\n';
            emailBody += '  Checked Out: ' + record.Checkout_Date__c.date().format() + '\n\n';
        }
        
        emailBody += 'Please return these items as soon as possible to avoid any late fees or restrictions on future borrowing.\n\n';
        emailBody += 'If you have already returned these items, please contact the library to update our records.\n\n';
        emailBody += 'Thank you for your cooperation.\n\n';
        emailBody += 'Library Management System';
        
        email.setPlainTextBody(emailBody);
        email.setSaveAsActivity(false);
        
        // Optional: Use org-wide email address if configured
        try {
            List<OrgWideEmailAddress> orgWideAddresses = [
                SELECT Id FROM OrgWideEmailAddress 
                WHERE DisplayName = 'Library System' 
                LIMIT 1
            ];
            if(!orgWideAddresses.isEmpty()) {
                email.setOrgWideEmailAddressId(orgWideAddresses[0].Id);
            }
        } catch(Exception e) {
            // Continue without org-wide address
        }
        
        return email;
    }
    
    // Send summary email to administrators
    private void sendSummaryEmail() {
        try {
            // Get admin email addresses from configuration or default to system admins
            List<String> adminEmails = getAdminEmailAddresses();
            
            if(adminEmails.isEmpty()) {
                return;
            }
            
            Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
            email.setToAddresses(adminEmails);
            email.setSubject('Library Overdue Items Report - ' + Date.today().format());
            
            // Build summary body
            String emailBody = 'Daily Overdue Items Processing Summary\n';
            emailBody += '=====================================\n\n';
            emailBody += 'Processing Date: ' + DateTime.now().format() + '\n';
            emailBody += 'Total Overdue Items: ' + totalOverdueItems + '\n';
            emailBody += 'Email Notifications Sent: ' + totalEmailsSent + '\n\n';
            
            // Breakdown by item type
            if(!overdueByItemType.isEmpty()) {
                emailBody += 'Overdue Items by Type:\n';
                emailBody += '----------------------\n';
                for(String itemType : overdueByItemType.keySet()) {
                    emailBody += itemType + ': ' + overdueByItemType.get(itemType) + '\n';
                }
                emailBody += '\n';
            }
            
            // Top borrowers with overdue items
            if(!overdueByBorrower.isEmpty()) {
                emailBody += 'Borrowers with Overdue Items:\n';
                emailBody += '-----------------------------\n';
                Integer count = 0;
                for(Id borrowerId : overdueByBorrower.keySet()) {
                    List<Borrowing_Record__c> records = overdueByBorrower.get(borrowerId);
                    if(!records.isEmpty() && records[0].Borrower__r != null) {
                        emailBody += records[0].Borrower__r.Name + ': ' + records.size() + ' item(s)\n';
                        count++;
                        if(count >= 10) break; // Limit to top 10
                    }
                }
                emailBody += '\n';
            }
            
            // Include any errors
            if(!errorMessages.isEmpty()) {
                emailBody += 'Errors Encountered:\n';
                emailBody += '-------------------\n';
                for(String errorMsg : errorMessages) {
                    emailBody += '• ' + errorMsg + '\n';
                }
                emailBody += '\n';
            }
            
            emailBody += 'End of Report\n';
            emailBody += '\nThis is an automated message from the Library Management System.';
            
            email.setPlainTextBody(emailBody);
            email.setSaveAsActivity(false);
            
            Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{email});
            
        } catch(Exception e) {
            System.debug('Error sending summary email: ' + e.getMessage());
        }
    }
    
    // Get administrator email addresses
    private List<String> getAdminEmailAddresses() {
        List<String> adminEmails = new List<String>();
        
        try {
            // First check configuration for admin emails
            Map<String, Object> config = LibraryConfigService.getGlobalSettings();
            if(config != null && config.containsKey('adminEmails')) {
                String emailString = (String)config.get('adminEmails');
                if(String.isNotBlank(emailString)) {
                    adminEmails.addAll(emailString.split('[,;]'));
                }
            }
            
            // If no configured emails, default to users with Library_Admin permission set
            if(adminEmails.isEmpty()) {
                List<User> adminUsers = [
                    SELECT Email 
                    FROM User 
                    WHERE Id IN (
                        SELECT AssigneeId 
                        FROM PermissionSetAssignment 
                        WHERE PermissionSet.Name = 'Library_Admin'
                    )
                    AND IsActive = true
                    AND Email != null
                    LIMIT 10
                ];
                
                for(User u : adminUsers) {
                    adminEmails.add(u.Email);
                }
            }
            
            // If still no emails, get system administrators
            if(adminEmails.isEmpty()) {
                List<User> sysAdmins = [
                    SELECT Email 
                    FROM User 
                    WHERE Profile.Name = 'System Administrator' 
                    AND IsActive = true 
                    AND Email != null
                    LIMIT 5
                ];
                
                for(User u : sysAdmins) {
                    adminEmails.add(u.Email);
                }
            }
        } catch(Exception e) {
            System.debug('Error getting admin emails: ' + e.getMessage());
        }
        
        return adminEmails;
    }
    
    // Schedule the job to run daily at 1 AM
    public static String scheduleJob() {
        String cronExp = '0 0 1 * * ?'; // Run daily at 1 AM
        return System.schedule('Update Overdue Items - ' + DateTime.now().format(), cronExp, new OverdueItemScheduler());
    }
    
    // Method to manually run the batch job
    public static Id runNow() {
        return Database.executeBatch(new OverdueItemScheduler(), 200);
    }
}