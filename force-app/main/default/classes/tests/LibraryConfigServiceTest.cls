@isTest
private class LibraryConfigServiceTest {
    
    @isTest
    static void testGetCurrentUserConfig() {
        Test.startTest();
        Map<String, Object> config = LibraryConfigService.getCurrentUserConfig();
        Test.stopTest();
        
        // Config might be null if no metadata records exist in test
        System.assertNotEquals(null, config);
    }
    
    @isTest
    static void testGetLoanDays() {
        Test.startTest();
        Integer loanDays = LibraryConfigService.getLoanDays('Book');
        Test.stopTest();
        
        // Should return default value if no config
        System.assert(loanDays > 0);
        System.assertEquals(14, loanDays); // Default value
    }
    
    @isTest
    static void testGetMaxItems() {
        Test.startTest();
        Integer maxItems = LibraryConfigService.getMaxItems('DVD');
        Test.stopTest();
        
        System.assert(maxItems > 0);
    }
    
    @isTest
    static void testAllowRenewal() {
        Test.startTest();
        Boolean allowRenewal = LibraryConfigService.allowRenewal('Book');
        Test.stopTest();
        
        System.assertNotEquals(null, allowRenewal);
    }
    
    @isTest
    static void testGetAvailableItemTypes() {
        Test.startTest();
        List<String> itemTypes = LibraryConfigService.getAvailableItemTypes();
        Test.stopTest();
        
        System.assertNotEquals(null, itemTypes);
    }
    
    @isTest
    static void testClearCache() {
        // Get config to populate cache
        LibraryConfigService.getCurrentUserConfig();
        
        Test.startTest();
        LibraryConfigService.clearCache();
        // Get config again - should repopulate cache
        Map<String, Object> config = LibraryConfigService.getCurrentUserConfig();
        Test.stopTest();
        
        System.assertNotEquals(null, config);
    }
}