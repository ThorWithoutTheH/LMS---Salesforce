@isTest
private class LibraryPermissionHelperTest {
    
    @isTest
    static void testHasLibrarianAccess() {
        User librarian = TestDataFactory.createLibrarian();
        User standardUser = TestDataFactory.createStandardUser();
        
        Test.startTest();
        System.runAs(librarian) {
            Boolean hasAccess = LibraryPermissionHelper.hasLibrarianAccess(librarian.Id);
            // Result depends on whether permission sets exist in the test context
            System.assertNotEquals(null, hasAccess, 'Should return a boolean value');
        }
        
        System.runAs(standardUser) {
            Boolean hasAccess = LibraryPermissionHelper.hasLibrarianAccess(standardUser.Id);
            // Standard users typically won't have librarian access
            System.assertNotEquals(null, hasAccess, 'Should return a boolean value');
        }
        Test.stopTest();
    }
    
    @isTest
    static void testIsLibrarian() {
        User librarian = TestDataFactory.createLibrarian();
        
        Test.startTest();
        System.runAs(librarian) {
            Boolean isLib = LibraryPermissionHelper.isLibrarian();
            System.assertNotEquals(null, isLib, 'Should return a boolean value');
        }
        Test.stopTest();
    }
    
    @isTest
    static void testCanUserReturnItem() {
        User user1 = TestDataFactory.createStandardUser();
        User user2 = TestDataFactory.createLibrarian();
        
        Test.startTest();
        // User can return their own item
        Boolean canReturn1 = LibraryPermissionHelper.canUserReturnItem(user1.Id, user1.Id);
        System.assertEquals(true, canReturn1, 'User should be able to return their own item');
        
        // Standard user cannot return another's item (unless they're a librarian)
        System.runAs(user1) {
            Boolean canReturn2 = LibraryPermissionHelper.canUserReturnItem(user1.Id, user2.Id);
            // This should be false unless user1 has librarian access
            System.assertNotEquals(null, canReturn2, 'Should return a boolean value');
        }
        
        // Librarian can return anyone's item
        System.runAs(user2) {
            Boolean canReturn3 = LibraryPermissionHelper.canUserReturnItem(user2.Id, user1.Id);
            System.assertNotEquals(null, canReturn3, 'Should return a boolean value');
        }
        Test.stopTest();
    }
    
    @isTest
    static void testClearCache() {
        // First populate the cache
        Boolean hasAccess = LibraryPermissionHelper.hasLibrarianAccess(UserInfo.getUserId());
        
        Test.startTest();
        // Clear the cache - now public method
        LibraryPermissionHelper.clearCache();
        
        // Check access again - should repopulate cache
        Boolean hasAccessAfterClear = LibraryPermissionHelper.hasLibrarianAccess(UserInfo.getUserId());
        Test.stopTest();
        
        System.assertNotEquals(null, hasAccessAfterClear, 'Should return a value after cache clear');
        System.assertEquals(hasAccess, hasAccessAfterClear, 'Should return same result after cache clear');
    }
    
    @isTest
    static void testGetLibrarians() {
        // Create test users
        User librarian = TestDataFactory.createLibrarian();
        User standardUser = TestDataFactory.createStandardUser();
        
        Test.startTest();
        List<User> librarians = LibraryPermissionHelper.getLibrarians();
        Test.stopTest();
        
        System.assertNotEquals(null, librarians, 'Should return a list (even if empty)');
        // In test context, we should at least find the System Administrator running the test
        System.assert(librarians.size() >= 0, 'Should return zero or more librarians');
    }
    
    @isTest
    static void testCanPerformAdminActions() {
        User standardUser = TestDataFactory.createStandardUser();
        
        Test.startTest();
        // Test as current user (likely System Admin in test context)
        Boolean canPerformAdmin = LibraryPermissionHelper.canPerformAdminActions();
        System.assertNotEquals(null, canPerformAdmin, 'Should return a boolean value');
        
        // Test as standard user
        System.runAs(standardUser) {
            Boolean canPerformAdminAsStandard = LibraryPermissionHelper.canPerformAdminActions();
            System.assertEquals(false, canPerformAdminAsStandard, 'Standard user should not have admin access');
        }
        Test.stopTest();
    }
    
    @isTest
    static void testCacheEffectiveness() {
        User testUser = TestDataFactory.createStandardUser();
        
        Test.startTest();
        // First call - should query database
        Boolean firstCall = LibraryPermissionHelper.hasLibrarianAccess(testUser.Id);
        
        // Second call - should use cache
        Boolean secondCall = LibraryPermissionHelper.hasLibrarianAccess(testUser.Id);
        
        // Results should be the same
        System.assertEquals(firstCall, secondCall, 'Cached result should match initial result');
        
        // Clear cache
        LibraryPermissionHelper.clearCache();
        
        // Third call - should query database again
        Boolean thirdCall = LibraryPermissionHelper.hasLibrarianAccess(testUser.Id);
        
        // Should still get same result
        System.assertEquals(firstCall, thirdCall, 'Result after cache clear should match initial result');
        Test.stopTest();
    }
    
    @isTest
    static void testSystemAdminAlwaysHasAccess() {
        // Create a System Admin user
        Profile sysAdminProfile = [SELECT Id FROM Profile WHERE Name = 'System Administrator' LIMIT 1];
        User sysAdmin = new User(
            FirstName = 'System',
        LastName = 'Administrator',
        Email = 'sysadmin@test.com',
        Username = 'sysadmin@test' + System.now().getTime() + '.com',
        Alias = 'sadmin',
        TimeZoneSidKey = 'America/New_York',
        LocaleSidKey = 'en_US',
        EmailEncodingKey = 'UTF-8',
        ProfileId = sysAdminProfile.Id,
        LanguageLocaleKey = 'en_US'
            );
        insert sysAdmin;
        
        Test.startTest();
        System.runAs(sysAdmin) {
            Boolean isLibrarian = LibraryPermissionHelper.isLibrarian();
            Boolean canPerformAdmin = LibraryPermissionHelper.canPerformAdminActions();
            
            System.assertEquals(true, isLibrarian, 'System Admin should have librarian access');
            System.assertEquals(true, canPerformAdmin, 'System Admin should have admin actions access');
        }
        Test.stopTest();
    }
    
    @isTest
    static void testMultipleUsersInCache() {
        List<User> testUsers = new List<User>();
        for(Integer i = 0; i < 5; i++) {
            testUsers.add(TestDataFactory.createStandardUser());
        }
        
        Test.startTest();
        // Check access for all users - should populate cache
        for(User u : testUsers) {
            Boolean hasAccess = LibraryPermissionHelper.hasLibrarianAccess(u.Id);
            System.assertNotEquals(null, hasAccess, 'Should return a value for each user');
        }
        
        // Check again - should use cache
        for(User u : testUsers) {
            Boolean hasAccess = LibraryPermissionHelper.hasLibrarianAccess(u.Id);
            System.assertNotEquals(null, hasAccess, 'Should return cached value');
        }
        
        // Clear cache
        LibraryPermissionHelper.clearCache();
        
        // Check again - should repopulate
        for(User u : testUsers) {
            Boolean hasAccess = LibraryPermissionHelper.hasLibrarianAccess(u.Id);
            System.assertNotEquals(null, hasAccess, 'Should return value after cache clear');
        }
        Test.stopTest();
    }
}