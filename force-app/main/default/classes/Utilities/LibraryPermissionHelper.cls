public with sharing class LibraryPermissionHelper {
    
    private static Map<Id, Boolean> librarianCache = new Map<Id, Boolean>();
    
    @AuraEnabled(cacheable=true)
    public static Boolean isLibrarian() {
        return hasLibrarianAccess(UserInfo.getUserId());
    }
    
    public static Boolean hasLibrarianAccess(Id userId) {
        if(librarianCache.containsKey(userId)) {
            return librarianCache.get(userId);
        }
        
        Boolean hasAccess = false;
        
        // Check permission sets
        List<PermissionSetAssignment> psas = [
            SELECT Id 
            FROM PermissionSetAssignment 
            WHERE AssigneeId = :userId 
            AND PermissionSet.Name IN ('Library_Admin', 'Library_Manager')
            LIMIT 1
        ];
        
        if(!psas.isEmpty()) {
            hasAccess = true;
        } else {
            // Check profile
            User u = [SELECT Profile.Name FROM User WHERE Id = :userId LIMIT 1];
            hasAccess = u.Profile.Name == 'Librarian' ||
                u.Profile.Name == 'System Administrator';
        }
        
        librarianCache.put(userId, hasAccess);
        return hasAccess;
    }
    
    @AuraEnabled
    public static Boolean canUserReturnItem(Id userId, Id borrowerId) {
        return userId == borrowerId || hasLibrarianAccess(userId);
    }
    
    @AuraEnabled
    public static void clearCache() {
        librarianCache.clear();
    }
    
    /**
     * Get all users with librarian access (useful for admin purposes)
     * NEW METHOD
     */
    @AuraEnabled(cacheable=true)
    public static List<User> getLibrarians() {
        Set<Id> librarianIds = new Set<Id>();
        
        // Get users with Library permission sets
        List<PermissionSetAssignment> psas = [
            SELECT AssigneeId 
            FROM PermissionSetAssignment 
            WHERE PermissionSet.Name IN ('Library_Admin', 'Library_Manager')
        ];
        
        for(PermissionSetAssignment psa : psas) {
            librarianIds.add(psa.AssigneeId);
        }
        
        // Get users with Librarian or System Administrator profile
        List<User> profileUsers = [
            SELECT Id 
            FROM User 
            WHERE Profile.Name IN ('Librarian', 'System Administrator')
            AND IsActive = true
        ];
        
        for(User u : profileUsers) {
            librarianIds.add(u.Id);
        }
        
        // Return all unique librarian users
        if(librarianIds.isEmpty()) {
            return new List<User>();
        }
        
        return [
            SELECT Id, Name, Email, Profile.Name, IsActive 
            FROM User 
            WHERE Id IN :librarianIds
            ORDER BY Name
        ];
    }
    
    @AuraEnabled(cacheable=true)
    public static Boolean canPerformAdminActions() {
        Id userId = UserInfo.getUserId();
        
        List<PermissionSetAssignment> adminPSAs = [
            SELECT Id 
            FROM PermissionSetAssignment 
            WHERE AssigneeId = :userId 
            AND PermissionSet.Name = 'Library_Admin'
            LIMIT 1
        ];
        
        if(!adminPSAs.isEmpty()) {
            return true;
        }
        
        // Check if System Administrator
        User u = [SELECT Profile.Name FROM User WHERE Id = :userId LIMIT 1];
        return u.Profile.Name == 'System Administrator';
    }
}