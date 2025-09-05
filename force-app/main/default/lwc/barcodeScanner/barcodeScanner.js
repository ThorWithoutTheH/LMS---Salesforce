import { LightningElement, track, api, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

// Apex imports
import processBarcodeAction from '@salesforce/apex/BarcodeScannerController.processBarcodeAction';
import getMyCheckedOutItems from '@salesforce/apex/BarcodeScannerController.getMyCheckedOutItems';
import Id from '@salesforce/user/Id';

export default class BarcodeScanner extends LightningElement {
    // Configuration properties
    @api defaultAction;
    @api enableBulkMode;
    @api showStatistics;
    @api showMyItems;
    @api maxRecentScans;
    @api autoFocusDelay;
    
    // Component state
    @track currentBarcode = '';
    @track currentMode = 'checkout';
    @track processingQueue = [];
    @track recentHistory = [];
    @track lastResult = null;
    @track myItems = [];
    
    // Statistics
    successCount = 0;
    errorCount = 0;
    sessionStartTime = Date.now();
    
    // State flags
    isProcessing = false;
    lastScanSuccess = false;
    lastScanError = false;

    // Wire service (optional)
    @wire(getMyCheckedOutItems)
    wiredMyItems({ data, error }) {
        if (data) {
            this.myItems = data;
        }
    }

    connectedCallback() {
        // Set defaults
        if (this.defaultAction) {
            this.currentMode = this.defaultAction;
        }
        
        // Don't call focusInput here - component isn't rendered yet
    }

    renderedCallback() {
        // Focus input after render
        // Use defensive check to ensure element exists
        const input = this.template.querySelector('#barcode-input');
        if (input) {
            // Use setTimeout to ensure DOM is ready
            setTimeout(() => {
                if (input) {
                    input.focus();
                }
            }, 100);
        }
    }

    handleInputChange(event) {
        this.currentBarcode = event.target.value;
    }

    handleBarcodeInput(event) {
        // Process on Enter key
        if (event.key === 'Enter' || event.keyCode === 13) {
            event.preventDefault();
            
            const barcode = this.currentBarcode ? this.currentBarcode.trim() : '';
            if (barcode) {
                this.processScannedBarcode(barcode);
                
                // Clear input immediately
                this.currentBarcode = '';
                event.target.value = '';
            }
        }
    }

    async processScannedBarcode(barcode) {
        if (this.isProcessing) {
            return; // Prevent concurrent processing
        }
        
        // Add to queue for visual feedback
        const queueItem = {
            id: Date.now(),
            barcode: barcode
        };
        this.processingQueue = [...this.processingQueue, queueItem];
        
        this.isProcessing = true;
        this.lastScanSuccess = false;
        this.lastScanError = false;
        
        try {
            const result = await processBarcodeAction({
                barcode: barcode,
                action: this.currentMode,
                userId: Id
            });
            
            this.handleScanSuccess(result, barcode);
            
        } catch (error) {
            this.handleScanError(error, barcode);
        } finally {
            // Remove from queue
            this.processingQueue = this.processingQueue.filter(item => item.id !== queueItem.id);
            this.isProcessing = false;
            
            // Refocus for next scan
            setTimeout(() => {
                const input = this.template.querySelector('#barcode-input');
                if (input) {
                    input.focus();
                }
            }, 100);
        }
    }

    handleScanSuccess(result, barcode) {
        const timestamp = new Date().toLocaleTimeString();
        
        // Update last result
        this.lastResult = {
            success: result.success,
            message: result.message || 'Processed',
            barcode: barcode,
            timestamp: timestamp,
            itemName: result.itemDetails?.itemName || barcode
        };
        
        // Update counters
        if (result.success) {
            this.successCount++;
            this.lastScanSuccess = true;
            this.playSuccessBeep();
            
            // Clear success indicator after 1 second
            setTimeout(() => {
                this.lastScanSuccess = false;
            }, 1000);
        } else {
            this.errorCount++;
            this.lastScanError = true;
            this.playErrorBeep();
            
            // Show error toast
            this.showToast('Error', result.message || 'Processing failed', 'error');
            
            // Clear error indicator after 2 seconds
            setTimeout(() => {
                this.lastScanError = false;
            }, 2000);
        }
        
        // Add to history
        this.addToHistory({
            id: Date.now(),
            barcode: barcode,
            itemName: this.lastResult.itemName,
            time: timestamp,
            success: result.success,
            iconName: result.success ? 'utility:success' : 'utility:error',
            variant: result.success ? 'success' : 'error'
        });
    }

    handleScanError(error, barcode) {
        this.errorCount++;
        this.lastScanError = true;
        this.playErrorBeep();
        
        const timestamp = new Date().toLocaleTimeString();
        
        this.lastResult = {
            success: false,
            message: error.body?.message || 'Processing error',
            barcode: barcode,
            timestamp: timestamp,
            itemName: 'Error'
        };
        
        this.showToast('Error', 'Failed to process barcode', 'error');
        
        // Add to history
        this.addToHistory({
            id: Date.now(),
            barcode: barcode,
            itemName: 'Error',
            time: timestamp,
            success: false,
            iconName: 'utility:error',
            variant: 'error'
        });
        
        setTimeout(() => {
            this.lastScanError = false;
        }, 2000);
    }

    addToHistory(historyItem) {
        const maxItems = this.maxRecentScans ? parseInt(this.maxRecentScans) : 20;
        this.recentHistory = [historyItem, ...this.recentHistory].slice(0, maxItems);
    }

    setCheckoutMode() {
        this.currentMode = 'checkout';
        // Focus inline instead of calling method
        const input = this.template.querySelector('#barcode-input');
        if (input) {
            input.focus();
        }
    }

    setReturnMode() {
        this.currentMode = 'return';
        // Focus inline instead of calling method
        const input = this.template.querySelector('#barcode-input');
        if (input) {
            input.focus();
        }
    }

    clearForm() {
        this.currentBarcode = '';
        const input = this.template.querySelector('#barcode-input');
        if (input) {
            input.focus();
        }
    }

    clearHistory() {
        this.recentHistory = [];
        this.successCount = 0;
        this.errorCount = 0;
        this.sessionStartTime = Date.now();
        this.lastResult = null;
    }

    playSuccessBeep() {
        try {
            const audioContext = new (window.AudioContext || window.webkitAudioContext)();
            const oscillator = audioContext.createOscillator();
            oscillator.frequency.value = 800;
            oscillator.connect(audioContext.destination);
            oscillator.start();
            oscillator.stop(audioContext.currentTime + 0.1);
        } catch (e) {
            // Silent fail
        }
    }

    playErrorBeep() {
        try {
            const audioContext = new (window.AudioContext || window.webkitAudioContext)();
            const oscillator = audioContext.createOscillator();
            oscillator.frequency.value = 300;
            oscillator.connect(audioContext.destination);
            oscillator.start();
            oscillator.stop(audioContext.currentTime + 0.2);
        } catch (e) {
            // Silent fail
        }
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({
            title: title,
            message: message,
            variant: variant,
            mode: variant === 'error' ? 'sticky' : 'dismissable'
        }));
    }

    // Getters for template
    get currentModeLabel() {
        return this.currentMode === 'checkout' ? 'CHECKOUT' : 'RETURN';
    }

    get isCheckoutMode() {
        return this.currentMode === 'checkout' ? 'brand' : 'neutral';
    }

    get isReturnMode() {
        return this.currentMode === 'return' ? 'brand' : 'neutral';
    }

    get sessionCount() {
        return this.successCount + this.errorCount;
    }

    get scanRate() {
        const minutesElapsed = (Date.now() - this.sessionStartTime) / 60000;
        if (minutesElapsed < 1) return '--';
        return Math.round(this.sessionCount / minutesElapsed);
    }

    get hasQueue() {
        return this.processingQueue.length > 0;
    }

    get hasHistory() {
        return this.recentHistory.length > 0;
    }

    get hasMyItems() {
        return this.myItems && this.myItems.length > 0;
    }

    get lastResultClass() {
        if (!this.lastResult) return 'slds-box slds-var-m-bottom_medium';
        return this.lastResult.success ? 
            'slds-box slds-var-m-bottom_medium slds-theme_success' : 
            'slds-box slds-var-m-bottom_medium slds-theme_error';
    }

    get lastResultIcon() {
        if (!this.lastResult) return 'utility:scan';
        return this.lastResult.success ? 'utility:success' : 'utility:error';
    }

    get lastResultVariant() {
        return this.lastResult?.success ? 'success' : 'error';
    }

    get shouldShowStatistics() {
        return this.showStatistics === true || this.showStatistics === 'true';
    }

    get shouldShowMyItems() {
        return this.showMyItems === true || this.showMyItems === 'true';
    }
}