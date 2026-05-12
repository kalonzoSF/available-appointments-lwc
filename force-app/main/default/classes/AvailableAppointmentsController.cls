public with sharing class AvailableAppointmentsController {

    private static final Double EARTH_RADIUS_MILES = 3958.8;
    private static final Double ROAD_FACTOR = 1.3;
    private static final Double AVG_SPEED_MPH = 30.0;

    public class ResourceContext {
        @AuraEnabled public String resourceId;
        @AuraEnabled public Boolean isCrewMember;
        @AuraEnabled public List<String> territoryIds;
        @AuraEnabled public List<String> skillIds;
        @AuraEnabled public List<ScheduledAppt> scheduledAppointments;
    }

    public class ScheduledAppt {
        @AuraEnabled public String id;
        @AuraEnabled public Datetime schedStartTime;
        @AuraEnabled public Datetime schedEndTime;
        @AuraEnabled public Decimal lat;
        @AuraEnabled public Decimal lng;
    }

    public class AvailableAppt implements Comparable {
        @AuraEnabled public String id;
        @AuraEnabled public String appointmentNumber;
        @AuraEnabled public String subject;
        @AuraEnabled public String ganttLabel;
        @AuraEnabled public Decimal duration;
        @AuraEnabled public Datetime earliestStart;
        @AuraEnabled public Datetime dueDate;
        @AuraEnabled public String street;
        @AuraEnabled public String city;
        @AuraEnabled public String state;
        @AuraEnabled public String zip;
        @AuraEnabled public Decimal lat;
        @AuraEnabled public Decimal lng;
        @AuraEnabled public Integer estimatedTravelMinutes;

        public Integer compareTo(Object obj) {
            AvailableAppt other = (AvailableAppt) obj;
            Integer a = this.estimatedTravelMinutes != null ? this.estimatedTravelMinutes : 9999;
            Integer b = other.estimatedTravelMinutes != null ? other.estimatedTravelMinutes : 9999;
            return a - b;
        }
    }

    @AuraEnabled
    public static ResourceContext getResourceContext() {
        ResourceContext ctx = new ResourceContext();

        List<ServiceResource> resources = [
            SELECT Id FROM ServiceResource
            WHERE RelatedRecordId = :UserInfo.getUserId() AND IsActive = true
            LIMIT 1
        ];
        if (resources.isEmpty()) {
            throw new AuraHandledException('No active Service Resource found for current user.');
        }
        ctx.resourceId = resources[0].Id;

        ctx.territoryIds = new List<String>();
        for (ServiceTerritoryMember stm : [
            SELECT ServiceTerritoryId FROM ServiceTerritoryMember
            WHERE ServiceResourceId = :ctx.resourceId
            AND EffectiveStartDate <= TODAY
            AND (EffectiveEndDate = null OR EffectiveEndDate >= TODAY)
        ]) {
            ctx.territoryIds.add(stm.ServiceTerritoryId);
        }

        ctx.skillIds = new List<String>();
        for (ServiceResourceSkill srs : [
            SELECT SkillId FROM ServiceResourceSkill
            WHERE ServiceResourceId = :ctx.resourceId
        ]) {
            ctx.skillIds.add(srs.SkillId);
        }

        ctx.isCrewMember = [
            SELECT COUNT() FROM ServiceCrewMember
            WHERE ServiceResourceId = :ctx.resourceId
        ] > 0;

        ctx.scheduledAppointments = getSchedule(ctx.resourceId);
        return ctx;
    }

    @AuraEnabled
    public static List<AvailableAppt> getAvailableAppointments(
        String resourceId, List<String> territoryIds, List<String> skillIds,
        Decimal lat, Decimal lng, Decimal radiusMiles,
        Integer timeBufferMinutes, String backOnSiteTime
    ) {
        List<ServiceAppointment> candidates = [
            SELECT Id, AppointmentNumber, Subject, Duration, DurationType,
                   EarliestStartTime, DueDate, Street, City, State, PostalCode,
                   Latitude, Longitude, ServiceTerritoryId, FSL__GanttLabel__c,
                   ParentRecordId
            FROM ServiceAppointment
            WHERE Status = 'None'
            AND ServiceTerritoryId IN :territoryIds
            AND Latitude != null AND Longitude != null
            LIMIT 2000
        ];
        if (candidates.isEmpty()) return new List<AvailableAppt>();

        Set<Id> parentIds = new Set<Id>();
        for (ServiceAppointment sa : candidates) {
            if (sa.ParentRecordId != null) parentIds.add(sa.ParentRecordId);
        }
        Map<Id, Id> parentToWorkType = new Map<Id, Id>();
        if (!parentIds.isEmpty()) {
            for (WorkOrder wo : [
                SELECT Id, WorkTypeId FROM WorkOrder
                WHERE Id IN :parentIds AND WorkTypeId != null
            ]) {
                parentToWorkType.put(wo.Id, wo.WorkTypeId);
            }
        }

        Set<Id> workTypeIds = new Set<Id>(parentToWorkType.values());
        Map<Id, Set<Id>> skillReqsByWorkType = new Map<Id, Set<Id>>();
        if (!workTypeIds.isEmpty()) {
            for (SkillRequirement sr : [
                SELECT RelatedRecordId, SkillId FROM SkillRequirement
                WHERE RelatedRecordId IN :workTypeIds
            ]) {
                if (!skillReqsByWorkType.containsKey(sr.RelatedRecordId)) {
                    skillReqsByWorkType.put(sr.RelatedRecordId, new Set<Id>());
                }
                skillReqsByWorkType.get(sr.RelatedRecordId).add(sr.SkillId);
            }
        }
        Set<Id> resourceSkillSet = new Set<Id>();
        for (String sid : skillIds) {
            resourceSkillSet.add((Id) sid);
        }

        List<ScheduledAppt> schedule = getSchedule(resourceId);

        Datetime backOnSiteDt = parseBackOnSiteTime(backOnSiteTime);
        ScheduledAppt nextAppt = findNextScheduledAppt(schedule);

        Integer buffer = timeBufferMinutes != null ? timeBufferMinutes : 0;
        List<AvailableAppt> results = new List<AvailableAppt>();
        Datetime now = Datetime.now();

        for (ServiceAppointment sa : candidates) {
            Id workTypeId = parentToWorkType.get(sa.ParentRecordId);
            if (workTypeId != null) {
                Set<Id> required = skillReqsByWorkType.get(workTypeId);
                if (required != null && !resourceSkillSet.containsAll(required)) continue;
            }

            Double saLat = sa.Latitude;
            Double saLng = sa.Longitude;

            Integer travelFromUser = 0;
            if (lat != null && lng != null) {
                Double dist = haversineDistance(
                    lat.doubleValue(), lng.doubleValue(), saLat, saLng);
                if (radiusMiles != null && radiusMiles > 0
                    && dist > radiusMiles.doubleValue()) continue;
                travelFromUser = estimateTravelMinutes(
                    lat.doubleValue(), lng.doubleValue(), saLat, saLng);
            }

            Double durMin = sa.Duration != null ? sa.Duration : 60;
            if (sa.DurationType == 'Hours') durMin *= 60;

            if (!fitsInSchedule(
                sa, saLat, saLng, durMin, schedule, buffer, travelFromUser, now
            )) continue;

            if (backOnSiteDt != null && backOnSiteDt > now && lat != null && lng != null) {
                Integer travelBack = estimateTravelMinutes(saLat, saLng,
                    lat.doubleValue(), lng.doubleValue());
                Double minutesNeeded = travelFromUser + durMin + travelBack;
                Double minutesAvailable =
                    (backOnSiteDt.getTime() - now.getTime()) / 60000.0;
                if (minutesNeeded > minutesAvailable) continue;
            }

            AvailableAppt appt = new AvailableAppt();
            appt.id = sa.Id;
            appt.appointmentNumber = sa.AppointmentNumber;
            appt.subject = sa.Subject;
            appt.ganttLabel = sa.FSL__GanttLabel__c;
            appt.duration = durMin;
            appt.earliestStart = sa.EarliestStartTime;
            appt.dueDate = sa.DueDate;
            appt.street = sa.Street;
            appt.city = sa.City;
            appt.state = sa.State;
            appt.zip = sa.PostalCode;
            appt.lat = sa.Latitude;
            appt.lng = sa.Longitude;
            appt.estimatedTravelMinutes = travelFromUser;
            results.add(appt);
        }

        results.sort();
        return results;
    }

    @AuraEnabled
    public static String selfAssignAppointment(String saId, String resourceId) {
        Savepoint sp = Database.setSavepoint();
        try {
            ServiceAppointment sa = [
                SELECT Id, Duration, DurationType, Status
                FROM ServiceAppointment WHERE Id = :saId LIMIT 1
            ];
            if (sa.Status != 'None') {
                throw new AuraHandledException(
                    'This appointment is no longer available.');
            }

            AssignedResource ar = new AssignedResource();
            ar.ServiceAppointmentId = saId;
            ar.ServiceResourceId = resourceId;
            insert ar;

            Double durMin = sa.Duration != null ? sa.Duration : 60;
            if (sa.DurationType == 'Hours') durMin *= 60;

            sa.Status = 'Scheduled';
            sa.SchedStartTime = Datetime.now();
            sa.SchedEndTime = Datetime.now().addMinutes((Integer) durMin);
            update sa;

            return 'SUCCESS';
        } catch (AuraHandledException e) {
            Database.rollback(sp);
            throw e;
        } catch (Exception e) {
            Database.rollback(sp);
            throw new AuraHandledException(e.getMessage());
        }
    }

    private static List<ScheduledAppt> getSchedule(String resourceId) {
        List<ScheduledAppt> schedule = new List<ScheduledAppt>();
        for (AssignedResource ar : [
            SELECT ServiceAppointment.Id,
                   ServiceAppointment.SchedStartTime,
                   ServiceAppointment.SchedEndTime,
                   ServiceAppointment.Latitude,
                   ServiceAppointment.Longitude
            FROM AssignedResource
            WHERE ServiceResourceId = :resourceId
            AND ServiceAppointment.Status = 'Scheduled'
            AND ServiceAppointment.SchedStartTime >= TODAY
            ORDER BY ServiceAppointment.SchedStartTime ASC
        ]) {
            ScheduledAppt s = new ScheduledAppt();
            s.id = ar.ServiceAppointment.Id;
            s.schedStartTime = ar.ServiceAppointment.SchedStartTime;
            s.schedEndTime = ar.ServiceAppointment.SchedEndTime;
            s.lat = ar.ServiceAppointment.Latitude;
            s.lng = ar.ServiceAppointment.Longitude;
            schedule.add(s);
        }
        return schedule;
    }

    private static Boolean fitsInSchedule(
        ServiceAppointment sa, Double saLat, Double saLng, Double durMin,
        List<ScheduledAppt> schedule, Integer buffer,
        Integer travelFromUser, Datetime now
    ) {
        if (schedule.isEmpty()) return true;

        ScheduledAppt first = schedule[0];
        Integer travelToFirst = (first.lat != null && first.lng != null)
            ? estimateTravelMinutes(saLat, saLng,
                first.lat.doubleValue(), first.lng.doubleValue())
            : 0;
        Double avail =
            (first.schedStartTime.getTime() - now.getTime()) / 60000.0;
        if (travelFromUser + durMin + travelToFirst <= avail + buffer)
            return true;

        for (Integer i = 0; i < schedule.size() - 1; i++) {
            ScheduledAppt prev = schedule[i];
            ScheduledAppt next = schedule[i + 1];
            Double gap = (next.schedStartTime.getTime()
                - prev.schedEndTime.getTime()) / 60000.0;
            Integer travelTo = (prev.lat != null && prev.lng != null)
                ? estimateTravelMinutes(
                    prev.lat.doubleValue(), prev.lng.doubleValue(),
                    saLat, saLng)
                : 0;
            Integer travelFrom = (next.lat != null && next.lng != null)
                ? estimateTravelMinutes(saLat, saLng,
                    next.lat.doubleValue(), next.lng.doubleValue())
                : 0;
            if (travelTo + durMin + travelFrom <= gap + buffer) return true;
        }

        ScheduledAppt last = schedule[schedule.size() - 1];
        Integer travelToSA = (last.lat != null && last.lng != null)
            ? estimateTravelMinutes(
                last.lat.doubleValue(), last.lng.doubleValue(), saLat, saLng)
            : 0;
        Datetime canStart = last.schedEndTime.addMinutes(travelToSA);
        Datetime canFinish = canStart.addMinutes((Integer) durMin);
        if (canFinish <= sa.DueDate) return true;

        return false;
    }

    private static Datetime parseBackOnSiteTime(String backOnSiteTime) {
        if (String.isBlank(backOnSiteTime)) return null;
        try {
            return Datetime.valueOfGmt(backOnSiteTime.replace('T', ' '));
        } catch (Exception e) {
            return null;
        }
    }

    private static ScheduledAppt findNextScheduledAppt(
        List<ScheduledAppt> schedule
    ) {
        if (schedule.isEmpty()) return null;
        Datetime now = Datetime.now();
        for (ScheduledAppt s : schedule) {
            if (s.schedStartTime > now) return s;
        }
        return null;
    }

    private static Double haversineDistance(
        Double lat1, Double lng1, Double lat2, Double lng2
    ) {
        Double lat1Rad = lat1 * Math.PI / 180;
        Double lat2Rad = lat2 * Math.PI / 180;
        Double dLat = (lat2 - lat1) * Math.PI / 180;
        Double dLng = (lng2 - lng1) * Math.PI / 180;
        Double a = Math.sin(dLat / 2) * Math.sin(dLat / 2) +
                   Math.cos(lat1Rad) * Math.cos(lat2Rad) *
                   Math.sin(dLng / 2) * Math.sin(dLng / 2);
        Double c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
        return EARTH_RADIUS_MILES * c;
    }

    private static Integer estimateTravelMinutes(
        Double lat1, Double lng1, Double lat2, Double lng2
    ) {
        Double distance = haversineDistance(lat1, lng1, lat2, lng2);
        Double minutes = (distance * ROAD_FACTOR) / AVG_SPEED_MPH * 60;
        return (Integer)(Math.round(minutes / 5.0) * 5);
    }
}
