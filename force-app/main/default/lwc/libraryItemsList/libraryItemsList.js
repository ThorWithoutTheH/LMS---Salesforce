import { LightningElement, track, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { refreshApex} from '@salesforce/apex';
import getAllLibraryItems from '@salesforce/apex/LibraryItemService.getAllLibraryItems';
import checkoutItem from '@salesforce/apex/BorrowingRecordService.checkoutItem';
import returnItem from '@salesforce/apex/BorrowingRecordService.returnItem';
import renewItem from '@salesforce/apex/BorrowingRecordService.renewItem';
import Id from '@salesforce/user/Id';

export default class LibraryItemsList extends NavigationMixin(LightningElement) {
    @track allItems = [];
    @track filteredItems = [];
    @track displayedItems = []; // New: Items shown on current page
    @track searchTerm = '';
    @track selectedItemType = '';
    @track selectedStatus = '';
    @track isLoading = true;
    @track error;
    @track sortDirection = 'asc';
    @track sortedBy = '';
    @track showCheckoutModal = false;
    @track showReturnModal = false;
    @track selectedItem = null;
    @track selectedBorrower = '';
    @track borrowingLimits = {};
    @track isProcessing = false;

    // Pagination properties
    @track currentPage = 1;
    @track pageSize = 25; // Items per page
    @track totalPages = 0;

    currentUserId = Id;
    wiredItemsResult;

    @wire(getAllLibraryItems)
    wiredItems(result) {
        this.wiredItemsResult = result;
        if (result.data) {
            this.allItems = this.processItemData(result.data);
            this.filteredItems = [...this.allItems];
            this.updatePagination();
            this.error = undefined;
            this.isLoading = false;
        } else if (result.error) {
            this.error = result.error.body?.message || 'Error loading library items';
            this.allItems = [];
            this.filteredItems = [];
            this.displayedItems = [];
            this.isLoading = false;
        }
    }

    connectedCallback() {
        this.selectedBorrower = this.currentUserId;
    }

    // Pagination computed properties
    get startRecord() {
        return (this.currentPage - 1) * this.pageSize + 1;
    }

    get endRecord() {
        return Math.min(this.currentPage * this.pageSize, this.filteredItems.length);
    }

    get hasPreviousPage() {
        return this.currentPage > 1;
    }

    get hasNextPage() {
        return this.currentPage < this.totalPages;
    }

    get disablePreviousPage() {
        return !this.hasPreviousPage;
    }

    get disableNextPage() {
        return !this.hasNextPage;
    }

    get paginationInfo() {
        return `${this.startRecord}-${this.endRecord} of ${this.filteredItems.length} items`;
    }

    get showPagination() {
        return this.totalPages > 1;
    }

    get pageSizeOptions() {
        return [
            { label: '10', value: 10 },
            { label: '25', value: 25 },
            { label: '50', value: 50 },
            { label: '100', value: 100 }
        ];
    }

    // Pagination methods
    updatePagination() {
        this.totalPages = Math.ceil(this.filteredItems.length / this.pageSize);
        
        // Reset to page 1 if current page is beyond total pages
        if (this.currentPage > this.totalPages && this.totalPages > 0) {
            this.currentPage = 1;
        }
        
        this.updateDisplayedItems();
    }

    updateDisplayedItems() {
        const startIndex = (this.currentPage - 1) * this.pageSize;
        const endIndex = startIndex + this.pageSize;
        this.displayedItems = this.filteredItems.slice(startIndex, endIndex);
    }

    handlePageSizeChange(event) {
        this.pageSize = parseInt(event.target.value);
        this.currentPage = 1;
        this.updatePagination();
    }

    handlePreviousPage() {
        if (this.hasPreviousPage) {
            this.currentPage--;
            this.updateDisplayedItems();
        }
    }

    handleNextPage() {
        if (this.hasNextPage) {
            this.currentPage++;
            this.updateDisplayedItems();
        }
    }

    handleFirstPage() {
        this.currentPage = 1;
        this.updateDisplayedItems();
    }

    handleLastPage() {
        this.currentPage = this.totalPages;
        this.updateDisplayedItems();
    }

    // Process and enrich item data
    processItemData(items) {
        return items.map(item => ({
            ...item,
            isAvailable: item.Current_Status__c === 'Available',
            isCheckedOut: item.Current_Status__c === 'Checked Out',
            isOverdue: item.Current_Status__c === 'Overdue',
            statusClass: this.getStatusClass(item.Current_Status__c),
            canRenew: this.canItemBeRenewed(item)
        }));
    }

    canItemBeRenewed(item) {
        if (item.Current_Status__c !== 'Checked Out' && item.Current_Status__c !== 'Overdue') {
            return false;
        }
        
        const itemSettings = this.borrowingLimits[item.Item_Type__c];
        return itemSettings ? itemSettings.allowRenewal : false;
    }

    getStatusClass(status) {
        const statusClasses = {
            'Available': 'status-available',
            'Checked Out': 'status-checked-out',
            'Overdue': 'status-overdue',
            'Maintenance': 'status-maintenance',
            'Lost': 'status-lost',
            'Retired': 'status-retired'
        };
        return statusClasses[status] || '';
    }

    // Filter options
    get itemTypeFilterOptions() {
        const types = [{ label: 'All Types', value: '' }];
        const uniqueTypes = [...new Set(this.allItems.map(item => item.Item_Type__c))];
        uniqueTypes.sort().forEach(type => types.push({ label: type, value: type }));
        return types;
    }

    get statusFilterOptions() {
        const statuses = [{ label: 'All Statuses', value: '' }];
        const uniqueStatuses = [...new Set(this.allItems.map(item => item.Current_Status__c))];
        uniqueStatuses.sort().forEach(status => statuses.push({ label: status, value: status }));
        return statuses;
    }

    // Computed properties
    get hasItems() {
        return this.displayedItems.length > 0;
    }

    get totalItems() {
        return this.allItems.length;
    }

    get hasActiveFilters() {
        return this.searchTerm || this.selectedItemType || this.selectedStatus;
    }

    get sortedByName() {
        return this.sortedBy === 'name';
    }

    get nameSortIcon() {
        return this.sortDirection === 'asc' ? 'utility:arrowup' : 'utility:arrowdown';
    }

    get statistics() {
        const stats = {
            total: this.allItems.length,
            available: 0,
            checkedOut: 0,
            overdue: 0,
            maintenance: 0
        };

        this.allItems.forEach(item => {
            switch (item.Current_Status__c) {
                case 'Available':
                    stats.available++;
                    break;
                case 'Checked Out':
                    stats.checkedOut++;
                    break;
                case 'Overdue':
                    stats.overdue++;
                    break;
                case 'Maintenance':
                    stats.maintenance++;
                    break;
            }
        });

        return stats;
    }

    // Event handlers
    handleSearchChange(event) {
        this.searchTerm = event.target.value;
        this.debounceSearch();
    }

    handleItemTypeFilter(event) {
        this.selectedItemType = event.target.value;
        this.applyFilters();
    }

    handleStatusFilter(event) {
        this.selectedStatus = event.target.value;
        this.applyFilters();
    }

    handleBorrowerChange(event) {
        this.selectedBorrower = event.target.value;
    }

    // Debounced search to avoid too many API calls
    debounceSearch() {
        clearTimeout(this.searchTimeout);
        this.searchTimeout = setTimeout(() => {
            this.applyFilters();
        }, 300);
    }

    applyFilters() {
        let filtered = [...this.allItems];

        // Apply search filter
        if (this.searchTerm) {
            const searchLower = this.searchTerm.toLowerCase();
            filtered = filtered.filter(item => 
                item.Item_Name__c?.toLowerCase().includes(searchLower) ||
                item.Author_Manufacturer__c?.toLowerCase().includes(searchLower) ||
                item.Barcode__c?.toLowerCase().includes(searchLower) ||
                item.Category__c?.toLowerCase().includes(searchLower)
            );
        }

        // Apply item type filter
        if (this.selectedItemType) {
            filtered = filtered.filter(item => item.Item_Type__c === this.selectedItemType);
        }

        // Apply status filter
        if (this.selectedStatus) {
            filtered = filtered.filter(item => item.Current_Status__c === this.selectedStatus);
        }

        this.filteredItems = filtered;
        this.currentPage = 1; // Reset to first page when filters change
        this.updatePagination();
    }

    sortByName() {
        this.sortDirection = this.sortedBy === 'name' && this.sortDirection === 'asc' ? 'desc' : 'asc';
        this.sortedBy = 'name';

        this.filteredItems.sort((a, b) => {
            const nameA = a.Item_Name__c || '';
            const nameB = b.Item_Name__c || '';
            
            if (this.sortDirection === 'asc') {
                return nameA.localeCompare(nameB);
            } else {
                return nameB.localeCompare(nameA);
            }
        });
        
        this.updateDisplayedItems();
    }

    handleItemAction(event) {
        const action = event.target.value;
        const itemId = event.target.dataset.itemId;
        const item = this.allItems.find(i => i.Id === itemId);

        switch (action) {
            case 'view':
                this.handleViewItem(itemId);
                break;
            case 'edit':
                this.handleEditItem(itemId);
                break;
            case 'checkout':
                this.handleCheckoutItem(item);
                break;
            case 'return':
                this.handleReturnItem(item);
                break;
            case 'renew':
                this.handleRenewItem(item);
                break;
        }
    }

    handleViewItem(itemId) {
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: itemId,
                objectApiName: 'Library_Item__c',
                actionName: 'view'
            }
        });
    }

    handleEditItem(itemId) {
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: itemId,
                objectApiName: 'Library_Item__c',
                actionName: 'edit'
            }
        });
    }

    handleCheckoutItem(item) {
        this.selectedItem = item;
        this.showCheckoutModal = true;
    }

    handleReturnItem(item) {
        this.selectedItem = item;
        this.showReturnModal = true;
    }

    async handleRenewItem(item) {
        if (!item.Current_Borrower__c) {
            this.showToast('Error', 'Cannot renew item without current borrower', 'error');
            return;
        }

        this.isProcessing = true;
        
        try {
            const result = await renewItem({
                itemCode: item.Barcode__c,
                borrowerId: item.Current_Borrower__c
            });

            if (result.isSuccess) {
                this.showToast('Success', result.message, 'success');
                this.refreshData();
            } else {
                this.showToast('Renewal Failed', result.message, 'error');
            }
        } catch (error) {
            this.showToast('Error', 'Error renewing item: ' + error.body.message, 'error');
        } finally {
            this.isProcessing = false;
        }
    }

    async processCheckout() {
        if (!this.selectedBorrower || !this.selectedItem) {
            this.showToast('Error', 'Please select a borrower', 'error');
            return;
        }

        this.isProcessing = true;

        try {
            const result = await checkoutItem({
                itemCode: this.selectedItem.Barcode__c,
                borrowerId: this.selectedBorrower
            });

            if (result.isSuccess) {
                this.showToast('Success', result.message, 'success');
                this.closeCheckoutModal();
                this.refreshData();
            } else {
                this.showToast('Checkout Failed', result.message, 'error');
            }
        } catch (error) {
            this.showToast('Error', 'Error during checkout: ' + error.body.message, 'error');
        } finally {
            this.isProcessing = false;
        }
    }

    async processReturn() {
        if (!this.selectedItem) {
            return;
        }

        this.isProcessing = true;

        try {
            const result = await returnItem({
                itemCode: this.selectedItem.Barcode__c
            });

            if (result.isSuccess) {
                this.showToast('Success', result.message, 'success');
                this.closeReturnModal();
                this.refreshData();
            } else {
                this.showToast('Return Failed', result.message, 'error');
            }
        } catch (error) {
            this.showToast('Error', 'Error during return: ' + error.body.message, 'error');
        } finally {
            this.isProcessing = false;
        }
    }

    closeCheckoutModal() {
        this.showCheckoutModal = false;
        this.selectedItem = null;
    }

    closeReturnModal() {
        this.showReturnModal = false;
        this.selectedItem = null;
    }

    handleAddNew() {
        this[NavigationMixin.Navigate]({
            type: 'standard__objectPage',
            attributes: {
                objectApiName: 'Library_Item__c',
                actionName: 'new'
            }
        });
    }

    // Refresh data
    async refreshData() {
        this.isLoading = true;
        try {
            await refreshApex(this.wiredItemsResult);
        } catch (error) {
            this.showToast('Error', 'Error refreshing data', 'error');
        } finally {
            this.isLoading = false;
        }
    }

    showToast(title, message, variant) {
        const evt = new ShowToastEvent({
            title: title,
            message: message,
            variant: variant,
            duration: 3000
        });
        this.dispatchEvent(evt);
    }
}