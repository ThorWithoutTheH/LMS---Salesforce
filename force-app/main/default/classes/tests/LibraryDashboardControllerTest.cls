@isTest
private class LibraryDashboardControllerTest {
    
    @testSetup
    static void setup() {
        // Create items
        List<Library_Item__c> items = TestDataFactory.createLibraryItems(20);
        
        // Create users
        User user1 = TestDataFactory.createStandardUser();
        User user2 = TestDataFactory.createLibrarian();
        
        // Create borrowing records
        System.runAs(user1) {
            for(Integer i = 0; i < 5; i++) {
                TestDataFactory.createBorrowingRecord(
                    items[i].Id,
                user1.Id,
                i < 3 ? 'Active' : 'Returned'
                    );
            }
        }
        
        System.runAs(user2) {
            for(Integer i = 5; i < 10; i++) {
                Borrowing_Record__c br = TestDataFactory.createBorrowingRecord(
                    items[i].Id,
                user2.Id,
                'Active'
                    );
                // Make some overdue
                if(i > 7) {
                    br.Due_Date__c = Date.today().addDays(-5);
                    update br;
                }
            }
        }
    }
    
    @isTest
    static void testGetDashboardData() {
        Test.startTest();
        LibraryDashboardController.DashboardData data =
            LibraryDashboardController.getDashboardData();
        Test.stopTest();
        
        System.assertNotEquals(null, data);
        System.assertNotEquals(null, data.itemStats);
        System.assert(data.itemStats.totalCount > 0);
        System.assertNotEquals(null, data.popularItems);
        System.assertNotEquals(null, data.topBorrowers);
        System.assertNotEquals(null, data.overdueStats);
        System.assertNotEquals(null, data.recentActivity);
        System.assertNotEquals(null, data.itemTypeDistribution);
    }
    
    @isTest
    static void testGetBorrowingTrends() {
        Test.startTest();
        List<LibraryDashboardController.BorrowingTrend> trends =
            LibraryDashboardController.getBorrowingTrends();
        Test.stopTest();
        
        System.assertNotEquals(null, trends);
    }
    
    @isTest
    static void testItemStatistics() {
        // Update some items to different statuses
        List<Library_Item__c> items = [SELECT Id FROM Library_Item__c LIMIT 5];
        items[0].Current_Status__c = 'Checked Out';
        items[1].Current_Status__c = 'Available';
        items[2].Current_Status__c = 'Overdue';
        items[3].Current_Status__c = 'Lost';
        items[4].Current_Status__c = 'Maintenance';
        update items;
        
        Test.startTest();
        LibraryDashboardController.DashboardData data =
            LibraryDashboardController.getDashboardData();
        Test.stopTest();
        
        System.assert(data.itemStats.availableCount >= 0);
        System.assert(data.itemStats.checkedOutCount >= 0);
        System.assert(data.itemStats.overdueCount >= 0);
        System.assertEquals(100, data.itemStats.availablePercentage +
            data.itemStats.checkedOutPercentage +
            (data.itemStats.overdueCount * 100 / data.itemStats.totalCount) +
            (data.itemStats.lostCount * 100 / data.itemStats.totalCount) +
            (data.itemStats.maintenanceCount * 100 / data.itemStats.totalCount),
        10); // Allow for rounding
    }
}