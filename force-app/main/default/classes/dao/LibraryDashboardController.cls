public with sharing class LibraryDashboardController {
    
    /**
     * Get comprehensive dashboard data
     */
    @AuraEnabled(cacheable=true)
    public static DashboardData getDashboardData() {
        DashboardData data = new DashboardData();
        
        // Get item statistics
        data.itemStats = getItemStatistics();
        
        // Get most popular items
        data.popularItems = getMostPopularItems();
        
        // Get most frequent borrowers
        data.topBorrowers = getTopBorrowers();
        
        // Get overdue summary
        data.overdueStats = getOverdueStatistics();
        
        // Get recent activity
        data.recentActivity = getRecentActivity();
        
        // Get items by type distribution
        data.itemTypeDistribution = getItemTypeDistribution();
        
        return data;
    }
    
    /**
     * Get item statistics by status
     */
    private static ItemStatistics getItemStatistics() {
        ItemStatistics stats = new ItemStatistics();
        
        // Get counts by status
        for(AggregateResult ar : [
            SELECT Current_Status__c status, COUNT(Id) cnt
            FROM Library_Item__c
            GROUP BY Current_Status__c
        ]) {
            String status = (String)ar.get('status');
            Integer count = (Integer)ar.get('cnt');
            
            if(status == 'Available') {
                stats.availableCount = count;
            } else if(status == 'Checked Out') {
                stats.checkedOutCount = count;
            } else if(status == 'Overdue') {
                stats.overdueCount = count;
            } else if(status == 'Lost') {
                stats.lostCount = count;
            } else if(status == 'Maintenance') {
                stats.maintenanceCount = count;
            }
            stats.totalCount += count;
        }
        
        // Calculate percentages
        if(stats.totalCount > 0) {
            stats.availablePercentage = (stats.availableCount * 100.0 / stats.totalCount).intValue();
            stats.checkedOutPercentage = (stats.checkedOutCount * 100.0 / stats.totalCount).intValue();
        }
        
        return stats;
    }
    
    /**
     * Get most popular items (most borrowed)
     */
    private static List<PopularItem> getMostPopularItems() {
        List<PopularItem> popularItems = new List<PopularItem>();
        
        for(AggregateResult ar : [
            SELECT Library_Item__r.Item_Name__c itemName,
                   Library_Item__r.Item_Type__c itemType,
                   Library_Item__r.Barcode__c barcode,
                   COUNT(Id) borrowCount
            FROM Borrowing_Record__c
            WHERE CreatedDate >= LAST_N_DAYS:30
            GROUP BY Library_Item__r.Item_Name__c, 
                     Library_Item__r.Item_Type__c,
                     Library_Item__r.Barcode__c
            ORDER BY COUNT(Id) DESC
            LIMIT 10
        ]) {
            PopularItem item = new PopularItem();
            item.itemName = (String)ar.get('itemName');
            item.itemType = (String)ar.get('itemType');
            item.barcode = (String)ar.get('barcode');
            item.borrowCount = (Integer)ar.get('borrowCount');
            popularItems.add(item);
        }
        
        return popularItems;
    }
    
    /**
     * Get most frequent borrowers
     */
    private static List<TopBorrower> getTopBorrowers() {
        List<TopBorrower> topBorrowers = new List<TopBorrower>();
        
        for(AggregateResult ar : [
        SELECT Borrower__r.Name borrowerName,
               COUNT(Id) borrowCount,
               COUNT_DISTINCT(Library_Item__c) uniqueItems  // Fixed: Use COUNT_DISTINCT
        FROM Borrowing_Record__c
        WHERE CreatedDate >= LAST_N_DAYS:30
        GROUP BY Borrower__r.Name
        ORDER BY COUNT(Id) DESC
        LIMIT 10
    ]) {
            TopBorrower borrower = new TopBorrower();
            borrower.borrowerName = (String)ar.get('borrowerName');
            borrower.borrowCount = (Integer)ar.get('borrowCount');
            borrower.uniqueItemCount = (Integer)ar.get('uniqueItems');
            topBorrowers.add(borrower);
        }
        
        return topBorrowers;
    }
    
    /**
     * Get overdue statistics
     */
    private static OverdueStatistics getOverdueStatistics() {
        OverdueStatistics stats = new OverdueStatistics();
        
        // Count total overdue
        stats.totalOverdue = [
            SELECT COUNT()
            FROM Borrowing_Record__c
            WHERE Status__c = 'Active'
            AND Due_Date__c < TODAY
        ];
        
        // Get overdue by days
        for(Borrowing_Record__c br : [
            SELECT Due_Date__c
            FROM Borrowing_Record__c
            WHERE Status__c = 'Active'
            AND Due_Date__c < TODAY
        ]) {
            Integer daysOverdue = br.Due_Date__c.daysBetween(Date.today());
            
            if(daysOverdue <= 7) {
                stats.overdue1Week++;
            } else if(daysOverdue <= 14) {
                stats.overdue2Weeks++;
            } else {
                stats.overdueMoreThan2Weeks++;
            }
        }
        
        return stats;
    }
    
    /**
     * Get recent borrowing activity
     */
    private static List<RecentActivity> getRecentActivity() {
        List<RecentActivity> activities = new List<RecentActivity>();
        
        for(Borrowing_Record__c br : [
            SELECT Library_Item__r.Item_Name__c,
                   Borrower__r.Name,
                   Status__c,
                   Checkout_Date__c,
                   Return_Date__c
            FROM Borrowing_Record__c
            ORDER BY LastModifiedDate DESC
            LIMIT 20
        ]) {
            RecentActivity activity = new RecentActivity();
            activity.itemName = br.Library_Item__r.Item_Name__c;
            activity.borrowerName = br.Borrower__r.Name;
            activity.status = br.Status__c;
            activity.actionDate = br.Return_Date__c != null ? br.Return_Date__c : br.Checkout_Date__c;
            activity.actionType = br.Return_Date__c != null ? 'Returned' : 'Checked Out';
            activities.add(activity);
        }
        
        return activities;
    }
    
    /**
     * Get item distribution by type
     */
    private static List<ItemTypeDistribution> getItemTypeDistribution() {
        List<ItemTypeDistribution> distribution = new List<ItemTypeDistribution>();
        
        for(AggregateResult ar : [
            SELECT Item_Type__c itemType, 
                   COUNT(Id) itemCount,
                   COUNT(Current_Borrower__c) checkedOutCount
            FROM Library_Item__c
            GROUP BY Item_Type__c
            ORDER BY COUNT(Id) DESC
        ]) {
            ItemTypeDistribution dist = new ItemTypeDistribution();
            dist.itemType = (String)ar.get('itemType');
            dist.totalCount = (Integer)ar.get('itemCount');
            dist.checkedOutCount = (Integer)ar.get('checkedOutCount');
            dist.availableCount = dist.totalCount - dist.checkedOutCount;
            distribution.add(dist);
        }
        
        return distribution;
    }
    
    /**
     * Get borrowing trends (last 30 days)
     */
    @AuraEnabled(cacheable=true)
    public static List<BorrowingTrend> getBorrowingTrends() {
        List<BorrowingTrend> trends = new List<BorrowingTrend>();
        
        // Group by date for last 30 days
        for(AggregateResult ar : [
            SELECT DAY_ONLY(Checkout_Date__c) checkoutDate,
                   COUNT(Id) checkoutCount
            FROM Borrowing_Record__c
            WHERE Checkout_Date__c >= LAST_N_DAYS:30
            GROUP BY DAY_ONLY(Checkout_Date__c)
            ORDER BY DAY_ONLY(Checkout_Date__c)
        ]) {
            BorrowingTrend trend = new BorrowingTrend();
            trend.dateValue = (Date)ar.get('checkoutDate');
            trend.checkoutCount = (Integer)ar.get('checkoutCount');
            trends.add(trend);
        }
        
        return trends;
    }
    
    // Wrapper Classes
    public class DashboardData {
        @AuraEnabled public ItemStatistics itemStats;
        @AuraEnabled public List<PopularItem> popularItems;
        @AuraEnabled public List<TopBorrower> topBorrowers;
        @AuraEnabled public OverdueStatistics overdueStats;
        @AuraEnabled public List<RecentActivity> recentActivity;
        @AuraEnabled public List<ItemTypeDistribution> itemTypeDistribution;
    }
    
    public class ItemStatistics {
        @AuraEnabled public Integer totalCount = 0;
        @AuraEnabled public Integer availableCount = 0;
        @AuraEnabled public Integer checkedOutCount = 0;
        @AuraEnabled public Integer overdueCount = 0;
        @AuraEnabled public Integer lostCount = 0;
        @AuraEnabled public Integer maintenanceCount = 0;
        @AuraEnabled public Integer availablePercentage = 0;
        @AuraEnabled public Integer checkedOutPercentage = 0;
    }
    
    public class PopularItem {
        @AuraEnabled public String itemName;
        @AuraEnabled public String itemType;
        @AuraEnabled public String barcode;
        @AuraEnabled public Integer borrowCount;
    }
    
    public class TopBorrower {
        @AuraEnabled public String borrowerName;
        @AuraEnabled public Integer borrowCount;
        @AuraEnabled public Integer uniqueItemCount;
    }
    
    public class OverdueStatistics {
        @AuraEnabled public Integer totalOverdue = 0;
        @AuraEnabled public Integer overdue1Week = 0;
        @AuraEnabled public Integer overdue2Weeks = 0;
        @AuraEnabled public Integer overdueMoreThan2Weeks = 0;
    }
    
    public class RecentActivity {
        @AuraEnabled public String itemName;
        @AuraEnabled public String borrowerName;
        @AuraEnabled public String status;
        @AuraEnabled public DateTime actionDate;
        @AuraEnabled public String actionType;
    }
    
    public class ItemTypeDistribution {
        @AuraEnabled public String itemType;
        @AuraEnabled public Integer totalCount;
        @AuraEnabled public Integer availableCount;
        @AuraEnabled public Integer checkedOutCount;
    }
    
    public class BorrowingTrend {
        @AuraEnabled public Date dateValue;
        @AuraEnabled public Integer checkoutCount;
    }
}