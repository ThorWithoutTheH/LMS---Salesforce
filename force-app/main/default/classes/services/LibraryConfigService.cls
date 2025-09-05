/**
 * @description Service class for managing library configuration settings using Custom Metadata only
 * @author ConForceSo Library System
 * @date 2025
 *
 * Configuration JSON Structure in Library_Configuration__mdt:
 * {
     *   "itemTypes": {
         *     "Book": {
             *       "loanDays": 14,
             *       "maxItems": 10,
             *       "allowRenewal": true,
             *       "renewalDays": 7
         *     },
         *     "DVD": {
             *       "loanDays": 7,
             *       "maxItems": 5,
             *       "allowRenewal": false
         *     },
         *     "Equipment": {
             *       "loanDays": 3,
             *       "maxItems": 2,
             *       "allowRenewal": true,
             *       "renewalDays": 3
         *     }
     *   },
     *   "globalSettings": {
         *     "maxTotalItems": 20,
         *     "enableOverdueNotifications": true,
         *     "overdueGracePeriod": 2,
         *     "defaultLoanDays": 14
     *   }
 * }
 */
public with sharing class LibraryConfigService {
    
    // Cache for performance
    private static Map<String, Map<String, Object>> configCache = new Map<String, Map<String, Object>>();
    
    /**
     * Get configuration for current user with priority logic
     * Priority: User-specific → Profile-specific → Role-specific → Department → Organization default
     */
    public static Map<String, Object> getCurrentUserConfig() {
        String cacheKey = 'current_user_' + UserInfo.getUserId();
        
        if (!configCache.containsKey(cacheKey)) {
            Map<String, Object> config = null;
            
            // Try user-specific config first
            config = getConfigurationByUserId(UserInfo.getUserId());
            
            // Try profile-specific if no user config
            if (config == null) {
                String profileName = getCurrentProfileName();
                config = getConfigurationByProfileName(profileName);
            }
            
            // Try role-specific if no profile config
            if (config == null) {
                String userRole = getCurrentUserRole();
                if (String.isNotBlank(userRole)) {
                    config = getConfigurationByRole(userRole);
                }
            }
            
            // Try department if no role config
            if (config == null) {
                String department = getCurrentUserDepartment();
                if (String.isNotBlank(department)) {
                    config = getConfigurationByDepartment(department);
                }
            }
            
            // Fall back to organization default
            if (config == null) {
                config = getOrganizationConfig();
            }
            
            // If still null, use system defaults
            if (config == null) {
                config = getSystemDefaultConfig();
            }
            
            configCache.put(cacheKey, config);
        }
        
        return configCache.get(cacheKey);
    }
    
    /**
     * Get organization-wide default configuration
     */
    public static Map<String, Object> getOrganizationConfig() {
        String cacheKey = 'organization';
        
        if (!configCache.containsKey(cacheKey)) {
            List<Library_Configuration__mdt> configs = [
                SELECT Configuration_JSON__c 
                FROM Library_Configuration__mdt 
                WHERE Configuration_Type__c = 'Organization'
                AND DeveloperName = 'Default_Organization_Config'
                LIMIT 1
            ];
            
            Map<String, Object> config = null;
            if (!configs.isEmpty() && String.isNotBlank(configs[0].Configuration_JSON__c)) {
                try {
                    config = (Map<String, Object>)JSON.deserializeUntyped(configs[0].Configuration_JSON__c);
                } catch (Exception e) {
                    System.debug('Error parsing organization config JSON: ' + e.getMessage());
                }
            }
            
            configCache.put(cacheKey, config);
        }
        
        return configCache.get(cacheKey);
    }
    
    /**
     * Get configuration for specific profile
     */
    public static Map<String, Object> getConfigurationByProfileName(String profileName) {
        if (String.isBlank(profileName)) return null;
        
        String cacheKey = 'profile_' + profileName;
        
        if (!configCache.containsKey(cacheKey)) {
            // Look for profile-specific configuration
            List<Library_Configuration__mdt> configs = [
                SELECT Configuration_JSON__c 
                FROM Library_Configuration__mdt 
                WHERE Configuration_Type__c = 'Profile' 
                AND Label = :profileName
                LIMIT 1
            ];
            
            Map<String, Object> config = null;
            if (!configs.isEmpty() && String.isNotBlank(configs[0].Configuration_JSON__c)) {
                try {
                    config = (Map<String, Object>)JSON.deserializeUntyped(configs[0].Configuration_JSON__c);
                } catch (Exception e) {
                    System.debug('Error parsing profile config JSON: ' + e.getMessage());
                }
            }
            
            configCache.put(cacheKey, config);
        }
        
        return configCache.get(cacheKey);
    }
    
    /**
     * Get configuration for specific user
     */
    private static Map<String, Object> getConfigurationByUserId(Id userId) {
        String cacheKey = 'user_' + userId;
        
        if (!configCache.containsKey(cacheKey)) {
            List<Library_Configuration__mdt> configs = [
                SELECT Configuration_JSON__c 
                FROM Library_Configuration__mdt 
                WHERE Configuration_Type__c = 'User' 
                AND Label = :String.valueOf(userId)
                LIMIT 1
            ];
            
            Map<String, Object> config = null;
            if (!configs.isEmpty() && String.isNotBlank(configs[0].Configuration_JSON__c)) {
                try {
                    config = (Map<String, Object>)JSON.deserializeUntyped(configs[0].Configuration_JSON__c);
                } catch (Exception e) {
                    System.debug('Error parsing user config JSON: ' + e.getMessage());
                }
            }
            
            configCache.put(cacheKey, config);
        }
        
        return configCache.get(cacheKey);
    }
    
    /**
     * Get configuration for specific role
     */
    private static Map<String, Object> getConfigurationByRole(String roleName) {
        String cacheKey = 'role_' + roleName;
        
        if (!configCache.containsKey(cacheKey)) {
            List<Library_Configuration__mdt> configs = [
                SELECT Configuration_JSON__c 
                FROM Library_Configuration__mdt 
                WHERE Configuration_Type__c = 'Role' 
                AND Label = :roleName
                LIMIT 1
            ];
            
            Map<String, Object> config = null;
            if (!configs.isEmpty() && String.isNotBlank(configs[0].Configuration_JSON__c)) {
                try {
                    config = (Map<String, Object>)JSON.deserializeUntyped(configs[0].Configuration_JSON__c);
                } catch (Exception e) {
                    System.debug('Error parsing role config JSON: ' + e.getMessage());
                }
            }
            
            configCache.put(cacheKey, config);
        }
        
        return configCache.get(cacheKey);
    }
    
    /**
     * Get configuration for specific department
     */
    private static Map<String, Object> getConfigurationByDepartment(String department) {
        String cacheKey = 'dept_' + department;
        
        if (!configCache.containsKey(cacheKey)) {
            List<Library_Configuration__mdt> configs = [
                SELECT Configuration_JSON__c 
                FROM Library_Configuration__mdt 
                WHERE Configuration_Type__c = 'Department' 
                AND Label = :department
                LIMIT 1
            ];
            
            Map<String, Object> config = null;
            if (!configs.isEmpty() && String.isNotBlank(configs[0].Configuration_JSON__c)) {
                try {
                    config = (Map<String, Object>)JSON.deserializeUntyped(configs[0].Configuration_JSON__c);
                } catch (Exception e) {
                    System.debug('Error parsing department config JSON: ' + e.getMessage());
                }
            }
            
            configCache.put(cacheKey, config);
        }
        
        return configCache.get(cacheKey);
    }
    
    /**
     * Get system default configuration (hardcoded fallback)
     */
    private static Map<String, Object> getSystemDefaultConfig() {
        Map<String, Object> config = new Map<String, Object>();
        
        // Default item types configuration
        Map<String, Object> itemTypes = new Map<String, Object>();
        
        // Book defaults
        Map<String, Object> bookConfig = new Map<String, Object>();
        bookConfig.put('loanDays', 14);
        bookConfig.put('maxItems', 10);
        bookConfig.put('allowRenewal', true);
        bookConfig.put('renewalDays', 7);
        itemTypes.put('Book', bookConfig);
        
        // DVD defaults
        Map<String, Object> dvdConfig = new Map<String, Object>();
        dvdConfig.put('loanDays', 7);
        dvdConfig.put('maxItems', 5);
        dvdConfig.put('allowRenewal', false);
        itemTypes.put('DVD', dvdConfig);
        
        // Equipment defaults
        Map<String, Object> equipmentConfig = new Map<String, Object>();
        equipmentConfig.put('loanDays', 3);
        equipmentConfig.put('maxItems', 2);
        equipmentConfig.put('allowRenewal', true);
        equipmentConfig.put('renewalDays', 3);
        itemTypes.put('Equipment', equipmentConfig);
        
        // Magazine defaults
        Map<String, Object> magazineConfig = new Map<String, Object>();
        magazineConfig.put('loanDays', 7);
        magazineConfig.put('maxItems', 5);
        magazineConfig.put('allowRenewal', false);
        itemTypes.put('Magazine', magazineConfig);
        
        // Software defaults
        Map<String, Object> softwareConfig = new Map<String, Object>();
        softwareConfig.put('loanDays', 7);
        softwareConfig.put('maxItems', 3);
        softwareConfig.put('allowRenewal', true);
        softwareConfig.put('renewalDays', 7);
        itemTypes.put('Software', softwareConfig);
        
        config.put('itemTypes', itemTypes);
        
        // Global settings
        Map<String, Object> globalSettings = new Map<String, Object>();
        globalSettings.put('maxTotalItems', 20);
        globalSettings.put('enableOverdueNotifications', true);
        globalSettings.put('overdueGracePeriod', 2);
        globalSettings.put('defaultLoanDays', 14);
        config.put('globalSettings', globalSettings);
        
        return config;
    }
    
    /**
     * Get loan days for specific item type
     */
    public static Integer getLoanDays(String itemType) {
        Map<String, Object> config = getCurrentUserConfig();
        if (config == null) return 14; // Safe fallback
        
        Map<String, Object> itemTypes = (Map<String, Object>)config.get('itemTypes');
        if (itemTypes == null) {
            // Try global default
            Map<String, Object> globalSettings = (Map<String, Object>)config.get('globalSettings');
            if (globalSettings != null && globalSettings.containsKey('defaultLoanDays')) {
                return Integer.valueOf(globalSettings.get('defaultLoanDays'));
            }
            return 14;
        }
        
        Map<String, Object> itemConfig = (Map<String, Object>)itemTypes.get(itemType);
        if (itemConfig == null || !itemConfig.containsKey('loanDays')) {
            // Try global default
            Map<String, Object> globalSettings = (Map<String, Object>)config.get('globalSettings');
            if (globalSettings != null && globalSettings.containsKey('defaultLoanDays')) {
                return Integer.valueOf(globalSettings.get('defaultLoanDays'));
            }
            return 14;
        }
        
        return Integer.valueOf(itemConfig.get('loanDays'));
    }
    
    /**
     * Get maximum items allowed for specific item type
     */
    public static Integer getMaxItems(String itemType) {
        Map<String, Object> config = getCurrentUserConfig();
        if (config == null) return null; // No limit
        
        Map<String, Object> itemTypes = (Map<String, Object>)config.get('itemTypes');
        if (itemTypes == null) return null;
        
        Map<String, Object> itemConfig = (Map<String, Object>)itemTypes.get(itemType);
        if (itemConfig == null || !itemConfig.containsKey('maxItems')) return null;
        
        return Integer.valueOf(itemConfig.get('maxItems'));
    }
    
    /**
     * Check if renewal is allowed for specific item type
     */
    public static Boolean allowRenewal(String itemType) {
        Map<String, Object> config = getCurrentUserConfig();
        if (config == null) return false;
        
        Map<String, Object> itemTypes = (Map<String, Object>)config.get('itemTypes');
        if (itemTypes == null) return false;
        
        Map<String, Object> itemConfig = (Map<String, Object>)itemTypes.get(itemType);
        if (itemConfig == null || !itemConfig.containsKey('allowRenewal')) return false;
        
        return Boolean.valueOf(itemConfig.get('allowRenewal'));
    }
    
    /**
     * Get renewal days for specific item type
     */
    public static Integer getRenewalDays(String itemType) {
        Map<String, Object> config = getCurrentUserConfig();
        if (config == null) return 7; // Default renewal period
        
        Map<String, Object> itemTypes = (Map<String, Object>)config.get('itemTypes');
        if (itemTypes == null) return 7;
        
        Map<String, Object> itemConfig = (Map<String, Object>)itemTypes.get(itemType);
        if (itemConfig == null || !itemConfig.containsKey('renewalDays')) {
            // If renewal days not specified, use loan days
            return getLoanDays(itemType);
        }
        
        return Integer.valueOf(itemConfig.get('renewalDays'));
    }
    
    /**
     * Get global settings
     */
    public static Map<String, Object> getGlobalSettings() {
        Map<String, Object> config = getCurrentUserConfig();
        if (config == null || !config.containsKey('globalSettings')) {
            return new Map<String, Object>();
        }
        return (Map<String, Object>)config.get('globalSettings');
    }
    
    /**
     * Get all configurations for admin purposes
     */
    @AuraEnabled(cacheable=true)
    public static List<Library_Configuration__mdt> getAllConfigurations() {
        return [
            SELECT Label, DeveloperName, Configuration_Type__c, Configuration_JSON__c 
            FROM Library_Configuration__mdt 
            ORDER BY Configuration_Type__c, Label
        ];
    }
    
    // Lightning Web Component accessible methods
    
    /**
     * Get loan days for LWC
     */
    @AuraEnabled(cacheable=true)
    public static Integer getLoanDaysForLWC(String itemType) {
        return getLoanDays(itemType);
    }
    
    /**
     * Get max items for LWC
     */
    @AuraEnabled(cacheable=true)
    public static Integer getMaxItemsForLWC(String itemType) {
        return getMaxItems(itemType);
    }
    
    /**
     * Get all configuration for LWC
     */
    @AuraEnabled(cacheable=true)
    public static Map<String, Object> getAllConfigForLWC() {
        return getCurrentUserConfig();
    }
    
    /**
     * Get available item types
     */
    @AuraEnabled(cacheable=true)
    public static List<String> getAvailableItemTypes() {
        Map<String, Object> config = getCurrentUserConfig();
        if (config == null) {
            // Return default item types
            return new List<String>{'Book', 'DVD', 'Equipment', 'Magazine', 'Software'};
        }
        
        Map<String, Object> itemTypes = (Map<String, Object>)config.get('itemTypes');
        return itemTypes != null ? new List<String>(itemTypes.keySet()) : new List<String>();
    }
    
    /**
     * Private helper to get current user's profile name
     */
    private static String getCurrentProfileName() {
        return [SELECT Profile.Name FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1].Profile.Name;
    }
    
    /**
     * Private helper to get current user's role
     */
    private static String getCurrentUserRole() {
        User currentUser = [SELECT UserRole.Name FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1];
        return currentUser.UserRole != null ? currentUser.UserRole.Name : null;
    }
    
    /**
     * Private helper to get current user's department
     */
    private static String getCurrentUserDepartment() {
        User currentUser = [SELECT Department FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1];
        return currentUser.Department;
    }
    
    /**
     * Clear cache (useful for testing or when configurations change)
     */
    @AuraEnabled
    public static void clearCache() {
        configCache.clear();
    }
    
    /**
     * Test method to verify configuration is valid JSON
     */
    @TestVisible
    private static Boolean isValidConfigJSON(String jsonString) {
        try {
            Map<String, Object> config = (Map<String, Object>)JSON.deserializeUntyped(jsonString);
            // Check for required structure
            return config.containsKey('itemTypes') || config.containsKey('globalSettings');
        } catch (Exception e) {
            return false;
        }
    }
}