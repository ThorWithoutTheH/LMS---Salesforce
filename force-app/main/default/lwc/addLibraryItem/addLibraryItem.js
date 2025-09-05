import { LightningElement, track, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import createLibraryItem from '@salesforce/apex/LibraryItemService.createLibraryItem';
import getCategoriesForItemType from '@salesforce/apex/LibraryItemService.getCategoriesForItemType';

export default class AddLibraryItem extends LightningElement {
    @track itemName = '';
    @track itemType = '';
    @track category = '';
    @track authorManufacturer = '';
    @track isbnSerial = '';
    @track location = '';
    @track condition = 'Good';
    @track notes = '';
    @track purchaseDate = '';
    @track isLoading = false;
    @track availableCategories = [];
    @track showSuccess = false;
    @track showError = false;
    @track errorMessage = '';
    @track createdItemBarcode = '';
    @track showCard = false;

    // Check permissions when component loads
    connectedCallback() {
        this.checkUserPermissions();
    }

    async checkUserPermissions() {
        try {
            this.hasAccess = await isLibrarian();
            this.showCard = true;            
            if (!this.hasAccess) {
                // Show toast notification for unauthorized access
                this.showToast(
                    'Access Denied', 
                    'You do not have permission to add library items. Please contact your administrator.', 
                    'warning'
                );
            }
        } catch (error) {
            console.error('Error checking permissions:', error);
            this.hasAccess = false;
        } finally {
            this.permissionCheckComplete = true;
        }
    }


    // Computed property for category options
    get categoryOptions() {
        const options = [{ label: 'Select Category...', value: '' }];
        
        this.availableCategories.forEach(category => {
            options.push({ label: category, value: category });
        });

        // Add common categories if no existing ones
        if (this.availableCategories.length === 0 && this.itemType) {
            const defaultCategories = this.getDefaultCategoriesForType(this.itemType);
            defaultCategories.forEach(category => {
                options.push({ label: category, value: category });
            });
        }

        return options;
    }

    // should change this to get all types from the picklist value
    getDefaultCategoriesForType(itemType) {
        const defaults = {
            'Book': ['Fiction', 'Non-Fiction', 'Technical', 'Business', 'Reference'],
            'DVD': ['Training', 'Entertainment', 'Documentary', 'Educational'],
            'Equipment': ['Technology', 'Audio/Visual', 'Office Equipment', 'Photography'],
            'Magazine': ['Periodical', 'Industry Publication', 'Academic Journal'],
            'Software': ['Development', 'Productivity', 'Design', 'Analytics']
        };
        return defaults[itemType] || ['General'];
    }

    handleInputChange(event) {
        const field = event.target.dataset.field;
        this[field] = event.target.value;

        // Clear messages when user starts typing
        if (this.showSuccess || this.showError) {
            this.clearMessages();
        }

        // Load categories when item type changes
        if (field === 'itemType' && this.itemType) {
            this.loadCategories();
        }
    }

    async loadCategories() {
        try {
            this.availableCategories = await getCategoriesForItemType({ 
                itemType: this.itemType 
            });
        } catch (error) {
            console.error('Error loading categories:', error);
            // Use default categories if service call fails
            this.availableCategories = [];
        }
    }

    async handleSave() {
        if (!this.validateForm()) {
            this.showErrorMessage('Please fill in all required fields.');
            return;
        }

        this.isLoading = true;
        this.clearMessages();

        const request = {
            itemName: this.itemName,
            itemType: this.itemType,
            category: this.category,
            authorManufacturer: this.authorManufacturer,
            isbnSerial: this.isbnSerial,
            location: this.location,
            condition: this.condition,
            notes: this.notes,
            purchaseDate: this.purchaseDate || null
        };

        try {
            const result = await createLibraryItem({ request: request });
            
            this.createdItemBarcode = result.Barcode__c;
            this.showSuccessMessage();
            this.showToast('Success', 
                `Library item "${result.Item_Name__c}" created successfully!`, 
                'success');
            
            // Auto-hide success message after 5 seconds
            setTimeout(() => {
                this.clearMessages();
            }, 5000);

        } catch (error) {
            const errorMsg = error.body?.message || 'An unexpected error occurred';
            this.showErrorMessage(errorMsg);
            this.showToast('Error', 'Failed to create library item: ' + errorMsg, 'error');
        } finally {
            this.isLoading = false;
        }
    }

    handleClear() {
        this.resetForm();
        this.clearMessages();
    }

    validateForm() {
        const allValid = [...this.template.querySelectorAll('lightning-input, lightning-combobox, lightning-textarea')]
            .reduce((validSoFar, inputField) => {
                inputField.reportValidity();
                return validSoFar && inputField.checkValidity();
            }, true);

        // Custom validation for required fields
        if (!this.itemName.trim()) return false;
        if (!this.itemType.trim()) return false;
        if (!this.condition.trim()) return false;

        return allValid;
    }

    resetForm() {
        this.itemName = '';
        this.itemType = '';
        this.category = '';
        this.authorManufacturer = '';
        this.isbnSerial = '';
        this.location = '';
        this.condition = 'Good';
        this.notes = '';
        this.purchaseDate = '';
        this.availableCategories = [];
    }

    showSuccessMessage() {
        this.showSuccess = true;
        this.showError = false;
    }

    showErrorMessage(message) {
        this.errorMessage = message;
        this.showError = true;
        this.showSuccess = false;
    }

    clearMessages() {
        this.showSuccess = false;
        this.showError = false;
        this.errorMessage = '';
    }

    showToast(title, message, variant) {
        const evt = new ShowToastEvent({
            title: title,
            message: message,
            variant: variant
        });
        this.dispatchEvent(evt);
    }
}