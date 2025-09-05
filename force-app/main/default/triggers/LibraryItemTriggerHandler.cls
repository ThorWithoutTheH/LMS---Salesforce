public with sharing class LibraryItemTriggerHandler {
    
    public void beforeInsert(List<Library_Item__c> newItems) {
        setDefaultValues(newItems);
    }
    
    public void beforeUpdate(List<Library_Item__c> newItems, Map<Id, Library_Item__c> oldMap) {
        validateStatusChanges(newItems, oldMap);
    }
    
    private void setDefaultValues(List<Library_Item__c> items) {
        for(Library_Item__c item : items) {
            if(String.isBlank(item.Current_Status__c)) {
                item.Current_Status__c = 'Available';
            }
        }
    }
    
    private void validateStatusChanges(List<Library_Item__c> newItems, Map<Id, Library_Item__c> oldMap) {
        for(Library_Item__c item : newItems) {
            Library_Item__c oldItem = oldMap.get(item.Id);
            
            // Prevent manual status changes when item is Checked_Out
            if(item.Current_Borrower__c != null &&
                item.Current_Status__c != oldItem.Current_Status__c &&
            item.Current_Status__c == 'Available') {
                item.addError('Cannot mark item as Available while it has a current borrower');
            }
            
            // Auto-sync status with borrower
            if(item.Current_Borrower__c != null && oldItem.Current_Borrower__c == null) {
                item.Current_Status__c = 'Checked Out';
            } else if(item.Current_Borrower__c == null && oldItem.Current_Borrower__c != null) {
                item.Current_Status__c = 'Available';
            }
        }
    }
}