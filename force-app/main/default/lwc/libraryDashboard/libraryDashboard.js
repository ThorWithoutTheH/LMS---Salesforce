import { LightningElement, track } from 'lwc';
import getDashboardData from '@salesforce/apex/LibraryDashboardController.getDashboardData';
import getBorrowingTrends from '@salesforce/apex/LibraryDashboardController.getBorrowingTrends';

export default class LibraryDashboard extends LightningElement {
    @track isLoading = true;
    @track dashboardData = {};
    
    // Data properties
    itemStats = {};
    popularItems = [];
    topBorrowers = [];
    overdueStats = {};
    recentActivity = [];
    itemTypeDistribution = [];
    borrowingTrends = [];
    
    // Chart data for Lightning charts
    @track itemTypeChartData = [];
    @track trendChartData = [];

    connectedCallback() {
        this.loadDashboardData();
    }

    async loadDashboardData() {
        try {
            this.isLoading = true;
            
            // Load main dashboard data
            const data = await getDashboardData();
            this.processDashboardData(data);
            
            // Load trending data
            const trends = await getBorrowingTrends();
            this.borrowingTrends = trends || [];
            
            // Prepare chart data
            this.prepareChartData();
            
        } catch (error) {
            console.error('Error loading dashboard data:', error);
            // Show error to user
            this.showToast('Error', 'Failed to load dashboard data', 'error');
        } finally {
            this.isLoading = false;
        }
    }

    processDashboardData(data) {
        this.itemStats = data.itemStats || {};
        this.popularItems = data.popularItems || [];
        this.topBorrowers = data.topBorrowers || [];
        this.overdueStats = data.overdueStats || {};
        this.itemTypeDistribution = data.itemTypeDistribution || [];
        
        // FIXED: Ensure overdue counts are consistent
        this.reconcileOverdueData();
        
        // Process recent activity for display
        this.recentActivity = (data.recentActivity || []).map(activity => ({
            ...activity,
            badgeClass: activity.actionType === 'Checked Out' ? '' : 'slds-theme_success'
        }));
    }

    // NEW: Method to ensure overdue data consistency
    reconcileOverdueData() {
        // Calculate total overdue from breakdown if not provided
        if (this.overdueStats) {
            const calculatedTotal = 
                (this.overdueStats.overdue1Week || 0) + 
                (this.overdueStats.overdue2Weeks || 0) + 
                (this.overdueStats.overdueMoreThan2Weeks || 0);
            
            // If itemStats.overdueCount doesn't match, update it
            if (!this.itemStats.overdueCount || this.itemStats.overdueCount !== calculatedTotal) {
                this.itemStats = {
                    ...this.itemStats,
                    overdueCount: calculatedTotal
                };
            }
            
            // Ensure overdueStats has totalOverdue
            this.overdueStats = {
                ...this.overdueStats,
                totalOverdue: calculatedTotal
            };
        }
        
        // Update percentages if needed
        if (this.itemStats.totalCount > 0) {
            this.itemStats.overduePercentage = Math.round(
                (this.itemStats.overdueCount / this.itemStats.totalCount) * 100
            );
        }
    }

    prepareChartData() {
        // Prepare Item Type Distribution data for Lightning chart
        this.prepareItemTypeChartData();
        
        // Prepare Trend Chart data for Lightning chart
        this.prepareTrendChartData();
    }

    prepareItemTypeChartData() {
        if (!this.itemTypeDistribution || this.itemTypeDistribution.length === 0) {
            this.itemTypeChartData = [];
            return;
        }

        // Lightning charts expect data in a specific format
        // For a pie/donut chart, we'll use a bar chart as Lightning doesn't have native donut
        const labels = [];
        const data = [];
        const backgroundColors = [
            'rgb(21, 137, 238)',   // Blue
            'rgb(75, 202, 129)',   // Green
            'rgb(255, 154, 60)',   // Orange
            'rgb(194, 57, 52)',    // Red
            'rgb(144, 80, 233)',   // Purple
            'rgb(0, 174, 169)',    // Teal
            'rgb(112, 110, 107)',  // Gray
            'rgb(255, 99, 132)',   // Pink
            'rgb(54, 162, 235)',   // Light Blue
            'rgb(255, 206, 86)'    // Yellow
        ];

        this.itemTypeDistribution.forEach((item, index) => {
            labels.push(item.itemType || 'Unknown');
            data.push(item.totalCount || 0);
        });

        this.itemTypeChartData = {
            labels: labels,
            datasets: [{
                label: 'Items by Type',
                data: data,
                backgroundColor: backgroundColors.slice(0, labels.length),
                borderWidth: 1
            }]
        };
    }

    prepareTrendChartData() {
        if (!this.borrowingTrends || this.borrowingTrends.length === 0) {
            this.trendChartData = [];
            return;
        }

        const labels = [];
        const data = [];

        this.borrowingTrends.forEach(trend => {
            if (trend.dateValue) {
                // Format date for display
                const date = new Date(trend.dateValue);
                labels.push(date.toLocaleDateString('en-US', { month: 'short', day: 'numeric' }));
                data.push(trend.checkoutCount || 0);
            }
        });

        this.trendChartData = {
            labels: labels,
            datasets: [{
                label: 'Daily Checkouts',
                data: data,
                fill: false,
                borderColor: 'rgb(21, 137, 238)',
                backgroundColor: 'rgba(21, 137, 238, 0.1)',
                tension: 0.4,
                pointBackgroundColor: 'rgb(21, 137, 238)',
                pointBorderColor: '#fff',
                pointBorderWidth: 2,
                pointRadius: 4,
                pointHoverRadius: 6
            }]
        };
    }

    refreshDashboard() {
        // Reload data
        this.loadDashboardData();
    }

    // FIXED: Updated getter to use correct property
    get hasOverdueItems() {
        return this.overdueStats && this.overdueStats.totalOverdue > 0;
    }

    get hasItemTypeData() {
        return this.itemTypeChartData && this.itemTypeChartData.labels && this.itemTypeChartData.labels.length > 0;
    }

    get hasTrendData() {
        return this.trendChartData && this.trendChartData.labels && this.trendChartData.labels.length > 0;
    }

    // Create simple bar chart data for visualization
    get itemTypeBarData() {
        if (!this.itemTypeDistribution || this.itemTypeDistribution.length === 0) {
            return [];
        }

        // Find max value for scaling
        const maxValue = Math.max(...this.itemTypeDistribution.map(item => item.totalCount || 0));

        return this.itemTypeDistribution.map((item, index) => {
            const colors = [
                '#1589ee', '#4bca81', '#ff9a3c', '#c23934', 
                '#9050e9', '#00aea9', '#706e6b', '#ff6384'
            ];
            
            const percentageValue = maxValue > 0 ? Math.round((item.totalCount / maxValue) * 100) : 0;
            
            return {
                itemType: item.itemType || 'Unknown',
                totalCount: item.totalCount || 0,
                availableCount: item.availableCount || 0,
                checkedOutCount: item.checkedOutCount || 0,
                percentage: percentageValue,
                color: colors[index % colors.length]
            };
        });
    }

    // Create sparkline data for trends
    get trendSparklineData() {
        if (!this.borrowingTrends || this.borrowingTrends.length === 0) {
            return [];
        }

        const maxValue = Math.max(...this.borrowingTrends.map(trend => trend.checkoutCount || 0));
        
        return this.borrowingTrends.map(trend => ({
            date: trend.dateValue ? new Date(trend.dateValue).toLocaleDateString() : '',
            count: trend.checkoutCount || 0,
            heightPercentage: maxValue > 0 ? ((trend.checkoutCount / maxValue) * 100) : 0,
            // Add a computed style string for the template
            barStyle: `height: ${maxValue > 0 ? ((trend.checkoutCount / maxValue) * 100) : 0}%; background: linear-gradient(to top, #1589ee, #4bca81); border-radius: 2px 2px 0 0; position: relative;`
        }));
    }

    // Add computed property for total checkouts
    get totalCheckouts() {
        if (!this.trendSparklineData || this.trendSparklineData.length === 0) {
            return 0;
        }
        return this.trendSparklineData.reduce((sum, trend) => sum + trend.count, 0);
    }

    // Add computed properties for checking if arrays have data
    get hasPopularItems() {
        return this.popularItems && this.popularItems.length > 0;
    }

    get hasTopBorrowers() {
        return this.topBorrowers && this.topBorrowers.length > 0;
    }

    get hasRecentActivity() {
        return this.recentActivity && this.recentActivity.length > 0;
    }

    // NEW: Debug helper - can be removed in production
    logOverdueData() {
        console.log('ItemStats Overdue Count:', this.itemStats.overdueCount);
        console.log('OverdueStats:', JSON.stringify(this.overdueStats, null, 2));
        console.log('Total Calculated:', 
            (this.overdueStats.overdue1Week || 0) + 
            (this.overdueStats.overdue2Weeks || 0) + 
            (this.overdueStats.overdueMoreThan2Weeks || 0)
        );
    }

    // NEW: Toast helper method
    showToast(title, message, variant) {
        const event = new ShowToastEvent({
            title: title,
            message: message,
            variant: variant
        });
        this.dispatchEvent(event);
    }
}