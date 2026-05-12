import { LightningElement, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getResourceContext from '@salesforce/apex/AvailableAppointmentsController.getResourceContext';
import getAvailableAppointments from '@salesforce/apex/AvailableAppointmentsController.getAvailableAppointments';
import selfAssignAppointment from '@salesforce/apex/AvailableAppointmentsController.selfAssignAppointment';

export default class AvailableAppointments extends LightningElement {
    @track appointments = [];
    @track mapMarkers = [];
    resourceContext;
    currentLat;
    currentLng;
    radiusMiles = 25;
    timeBufferMinutes = 0;
    viewMode = 'list';
    checkInventory = false;
    backOnSiteDeadline = null;
    isLoading = true;
    errorMessage;
    gpsAcquired = false;
    mapCenter;
    lastApptLocation;
    selectedMapAppt;
    _refreshInterval;

    get showList() {
        return this.viewMode === 'list';
    }

    get showMap() {
        return this.viewMode === 'map';
    }

    get isCrewMember() {
        return this.resourceContext?.isCrewMember === true;
    }

    get hasAppointments() {
        return this.appointments.length > 0;
    }

    get appointmentCount() {
        return this.appointments.length;
    }

    get nextScheduledTime() {
        const scheds = this.resourceContext?.scheduledAppointments;
        if (!scheds || scheds.length === 0) return 'None scheduled';
        const now = Date.now();
        const next = scheds.find(s => new Date(s.schedStartTime).getTime() > now);
        if (!next) return 'None upcoming';
        return new Date(next.schedStartTime).toLocaleString('en-US', {
            month: 'short', day: 'numeric',
            hour: 'numeric', minute: '2-digit'
        });
    }

    get listButtonVariant() {
        return this.viewMode === 'list' ? 'brand' : 'neutral';
    }

    get mapButtonVariant() {
        return this.viewMode === 'map' ? 'brand' : 'neutral';
    }

    get inventoryButtonVariant() {
        return this.checkInventory ? 'brand' : 'neutral';
    }

    get statusMessage() {
        if (this.isLoading) return 'Loading...';
        if (this.errorMessage) return this.errorMessage;
        if (!this.gpsAcquired) return 'Waiting for GPS location...';
        if (this.appointments.length === 0) return 'No available appointments match your filters.';
        return '';
    }

    get showStatus() {
        if (this.isLoading || this.errorMessage || !this.gpsAcquired) return true;
        if (this.appointments.length === 0 && this.viewMode === 'list') return true;
        return false;
    }

    get hasMapMarkers() {
        return this.mapMarkers.length > 0;
    }

    get showNoAppointmentsMapNote() {
        return this.viewMode === 'map' && !this.isLoading && this.appointments.length === 0;
    }

    connectedCallback() {
        this.loadContext();
        this.requestGps();
        this._refreshInterval = setInterval(() => {
            this.loadAppointments();
        }, 120000);
    }

    disconnectedCallback() {
        if (this._refreshInterval) {
            clearInterval(this._refreshInterval);
        }
    }

    async loadContext() {
        try {
            this.resourceContext = await getResourceContext();
            const scheds = this.resourceContext.scheduledAppointments;
            if (scheds && scheds.length > 0) {
                const last = scheds[scheds.length - 1];
                if (last.lat && last.lng) {
                    this.lastApptLocation = {
                        latitude: last.lat, longitude: last.lng
                    };
                }
            }
            if (this.gpsAcquired) this.loadAppointments();
        } catch (error) {
            this.errorMessage = error.body?.message || 'Failed to load resource context.';
            this.isLoading = false;
        }
    }

    requestGps() {
        if (navigator.geolocation) {
            navigator.geolocation.getCurrentPosition(
                (pos) => {
                    this.currentLat = pos.coords.latitude;
                    this.currentLng = pos.coords.longitude;
                    this.gpsAcquired = true;
                    this.mapCenter = {
                        location: {
                            Latitude: this.currentLat,
                            Longitude: this.currentLng
                        }
                    };
                    if (this.resourceContext) this.loadAppointments();
                },
                () => {
                    this.currentLat = null;
                    this.currentLng = null;
                    this.gpsAcquired = true;
                    if (this.resourceContext) this.loadAppointments();
                },
                { enableHighAccuracy: true, timeout: 10000 }
            );
        } else {
            this.gpsAcquired = true;
            if (this.resourceContext) this.loadAppointments();
        }
    }

    async loadAppointments() {
        this.isLoading = true;
        this.errorMessage = null;
        try {
            let backOnSiteTime = null;
            if (this.isCrewMember && this.backOnSiteDeadline) {
                backOnSiteTime = this.backOnSiteDeadline;
            }
            const results = await getAvailableAppointments({
                resourceId: this.resourceContext.resourceId,
                territoryIds: this.resourceContext.territoryIds,
                skillIds: this.resourceContext.skillIds,
                lat: this.currentLat,
                lng: this.currentLng,
                radiusMiles: this.radiusMiles,
                timeBufferMinutes: this.timeBufferMinutes,
                backOnSiteTime: backOnSiteTime,
                checkInventory: this.checkInventory,
                locationId: this.resourceContext.locationId
            });
            this.appointments = results.map(a => ({
                ...a,
                formattedWindow: this.formatWindow(a.earliestStart, a.dueDate),
                travelLabel: a.estimatedTravelMinutes != null
                    ? a.estimatedTravelMinutes + ' min away' : '',
                addressLine: [a.street, a.city, a.state].filter(Boolean).join(', ')
            }));
            this.buildMapMarkers();
        } catch (error) {
            this.errorMessage = error.body?.message || 'Failed to load appointments.';
            this.appointments = [];
        } finally {
            this.isLoading = false;
        }
    }

    buildMapMarkers() {
        const markers = [];
        if (this.currentLat && this.currentLng) {
            markers.push({
                location: { Latitude: this.currentLat, Longitude: this.currentLng },
                title: 'My Location',
                description: 'Your current location',
                mapIcon: {
                    path: 'M 125,5 155,90 245,90 175,145 200,230 125,180 50,230 75,145 5,90 95,90 z',
                    fillColor: '#0176d3',
                    fillOpacity: 1,
                    strokeColor: '#014486',
                    strokeWeight: 1,
                    scale: 0.12
                }
            });
        }
        if (this.lastApptLocation) {
            markers.push({
                location: {
                    Latitude: this.lastApptLocation.latitude,
                    Longitude: this.lastApptLocation.longitude
                },
                title: 'Last Appointment',
                description: 'Last scheduled appointment location',
                mapIcon: {
                    path: 'M 125,5 155,90 245,90 175,145 200,230 125,180 50,230 75,145 5,90 95,90 z',
                    fillColor: '#2e844a',
                    fillOpacity: 1,
                    strokeColor: '#194e2b',
                    strokeWeight: 1,
                    scale: 0.12
                }
            });
        }
        this.appointments
            .filter(a => a.lat && a.lng)
            .forEach(a => {
                markers.push({
                    location: { Latitude: a.lat, Longitude: a.lng },
                    title: a.ganttLabel || a.appointmentNumber,
                    description: `${a.addressLine} | ${a.duration} min`,
                    value: a.id
                });
            });
        this.mapMarkers = markers;
    }

    formatWindow(start, end) {
        const opts = { month: 'short', day: 'numeric', hour: 'numeric', minute: '2-digit' };
        const s = start ? new Date(start).toLocaleString('en-US', opts) : '?';
        const e = end ? new Date(end).toLocaleString('en-US', opts) : '?';
        return `${s} - ${e}`;
    }

    handleViewToggle(event) {
        this.viewMode = event.target.dataset.view;
    }

    handleInventoryToggle() {
        this.checkInventory = !this.checkInventory;
        this.loadAppointments();
    }

    handleRadiusChange(event) {
        this.radiusMiles = event.detail.value;
    }

    handleRadiusCommit() {
        this.loadAppointments();
    }

    handleBufferChange(event) {
        this.timeBufferMinutes = event.detail.value;
    }

    handleBufferCommit() {
        this.loadAppointments();
    }

    handleBackOnSiteChange(event) {
        const val = event.detail.value;
        this.backOnSiteDeadline = (val && new Date(val) > Date.now()) ? val : null;
        this.loadAppointments();
    }

    handleCenterGps() {
        if (this.currentLat && this.currentLng) {
            this.mapCenter = {
                location: {
                    Latitude: this.currentLat,
                    Longitude: this.currentLng
                }
            };
        }
    }

    handleCenterLastAppt() {
        if (this.lastApptLocation) {
            this.mapCenter = {
                location: {
                    Latitude: this.lastApptLocation.latitude,
                    Longitude: this.lastApptLocation.longitude
                }
            };
        }
    }

    handleMarkerSelect(event) {
        const selectedValue = event.detail.selectedMarkerValue;
        this.selectedMapAppt = this.appointments.find(a => a.id === selectedValue) || null;
    }

    handleRefresh() {
        this.requestGps();
    }

    handleMapSelfAssign() {
        if (this.selectedMapAppt) {
            this.assignAppointment(this.selectedMapAppt.id);
        }
    }

    async handleSelfAssign(event) {
        const saId = event.currentTarget.dataset.id;
        this.assignAppointment(saId);
    }

    async assignAppointment(saId) {
        const appt = this.appointments.find(a => a.id === saId);
        try {
            const result = await selfAssignAppointment({
                saId: saId,
                resourceId: this.resourceContext.resourceId
            });
            if (result === 'SUCCESS') {
                this.dispatchEvent(new ShowToastEvent({
                    title: 'Assigned',
                    message: `${appt?.ganttLabel || 'Appointment'} assigned to you.`,
                    variant: 'success'
                }));
                this.appointments = this.appointments.filter(a => a.id !== saId);
                if (this.selectedMapAppt?.id === saId) {
                    this.selectedMapAppt = null;
                }
                this.buildMapMarkers();
            }
        } catch (error) {
            this.dispatchEvent(new ShowToastEvent({
                title: 'Error',
                message: error.body?.message || 'Could not assign appointment.',
                variant: 'error'
            }));
        }
    }
}
